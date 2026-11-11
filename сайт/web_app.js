/* Тнграм — веб-мессенджер на сайте.
   Говорит с тем же облаком Supabase, что и приложение: те же таблицы,
   тот же протокол групп, та же схема «доставил — удалил с сервера». */
(function () {
  'use strict';

  var SB_URL = 'https://hqmgjnloilemdwejzoyy.supabase.co';
  var SB_KEY = 'sb_publishable_eyJSH1Zs1IDEeE61009XDw_cQt5ujXj';
  var RT_TOPIC = 'realtime:public:messages';
  var ONLINE_SEC = 70;
  var GROUP_MARK = '\u0001G';
  var GROUP_PREFIX = 'g:';
  var GROUP_MAX = 32;
  var TITLE_MAX = 32;
  var SESSION_KEY = 'tngram-web-session';
  var DATA_PREFIX = 'tngram-web-data:';
  var SEEN_MAX = 400;

  var shell = null;
  var st = {
    nick: '', data: null, view: 'chats', peer: '', search: '',
    authMode: 'login', online: false, status: '', ping: -1,
    err: '', pending: '', busy: false, news: null, newsErr: false, mode: 'site'
  };
  var peerSeen = {};
  var ws = null, joined = false, refN = 0, retryDelay = 1000;
  var retryTimer = null, hbTimer = null, wantOnline = false;
  var timers = [];
  var audioCtx = null;

  /* ------------------------------------------------------------ мелочи */

  function $(id) { return document.getElementById(id); }
  function noop() {}
  function nk(s) { return String(s || '').trim().toLowerCase(); }
  function nowSec() { return Math.floor(Date.now() / 1000); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function fv(form, name) {
    var el = form.querySelector('[name="' + name + '"]');
    return el ? el.value : '';
  }
  function parseTime(text) {
    var clean = String(text || '').replace(/(\.\d{3})\d+/, '$1');
    var t = Date.parse(clean);
    return isNaN(t) ? 0 : Math.floor(t / 1000);
  }
  function two(n) { return String(n).padStart(2, '0'); }
  function fmtTime(ts) {
    var d = new Date(ts * 1000);
    return two(d.getHours()) + ':' + two(d.getMinutes());
  }
  function dayLabel(ts) {
    var d = new Date(ts * 1000), now = new Date();
    if (d.toDateString() === now.toDateString()) return 'Сегодня';
    var y = new Date(now);
    y.setDate(now.getDate() - 1);
    if (d.toDateString() === y.toDateString()) return 'Вчера';
    return two(d.getDate()) + '.' + two(d.getMonth() + 1) + '.' + d.getFullYear();
  }
  function ago(ts) {
    var diff = Math.max(nowSec() - ts, 0);
    if (diff < 60) return 'только что';
    if (diff < 3600) return Math.floor(diff / 60) + ' мин назад';
    if (diff < 86400) return Math.floor(diff / 3600) + ' ч назад';
    return Math.floor(diff / 86400) + ' дн назад';
  }
  async function sha256(text) {
    if (!text) return '';
    var buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buf)).map(function (b) { return two(b.toString(16)); }).join('');
  }

  /* ------------------------------------------------------------ облако (REST) */

  function rest(method, path, body, prefer) {
    var headers = { apikey: SB_KEY, Authorization: 'Bearer ' + SB_KEY, Accept: 'application/json' };
    if (body !== undefined) headers['Content-Type'] = 'application/json; charset=utf-8';
    if (prefer) headers.Prefer = prefer;
    return fetch(SB_URL + '/rest/v1/' + path, {
      method: method,
      headers: headers,
      body: body !== undefined ? JSON.stringify(body) : undefined
    }).then(function (res) {
      return res.text().then(function (text) {
        if (!res.ok) {
          var err = new Error('http ' + res.status);
          err.status = res.status;
          throw err;
        }
        return text ? JSON.parse(text) : null;
      });
    });
  }

  function apiFindProfile(nick) {
    return rest('GET', 'profiles?select=pass_hash,nick&nick_key=eq.' + encodeURIComponent(nk(nick)))
      .then(function (rows) { return (rows && rows[0]) || null; });
  }
  function apiClaimProfile(nick, hash) {
    return rest('POST', 'profiles', { nick_key: nk(nick), nick: nick.trim(), pass_hash: hash }, 'return=minimal');
  }
  function apiPresenceUpsert() {
    return rest('POST', 'presence?on_conflict=nick_key',
      [{ nick_key: nk(st.nick), nick: st.nick, last_seen: new Date().toISOString() }],
      'resolution=merge-duplicates,return=minimal');
  }
  function apiPresenceFind(keys) {
    var list = keys.map(function (k) { return encodeURIComponent(k); }).join(',');
    return rest('GET', 'presence?select=nick_key,nick,last_seen&nick_key=in.(' + list + ')');
  }
  function apiSend(to, body, ts) {
    return rest('POST', 'messages',
      { from_nick: st.nick, to_nick: to, body: body, client_ts: ts }, 'return=minimal');
  }
  function apiPending() {
    return rest('GET', 'messages?select=*&to_nick=eq.' + encodeURIComponent(st.nick) + '&order=id.asc');
  }
  function apiDelete(id) {
    return rest('DELETE', 'messages?id=eq.' + encodeURIComponent(id));
  }
  function apiNews() {
    return rest('GET', 'news?select=*&published=eq.true&order=created_at.desc&limit=20');
  }
  function apiPing() {
    return rest('GET', 'profiles?select=nick_key&limit=1');
  }

  /* ------------------------------------------------------------ хранилище */

  function loadData(nick) {
    var raw = null, d = null;
    try { raw = localStorage.getItem(DATA_PREFIX + nk(nick)); } catch (e) {}
    try { d = raw ? JSON.parse(raw) : null; } catch (e) { d = null; }
    if (!d || typeof d !== 'object') d = {};
    d.nick = d.nick || nick;
    d.chats = d.chats || {};
    d.groups = d.groups || {};
    d.unread = d.unread || {};
    d.seen = d.seen || [];
    return d;
  }
  function saveData() {
    if (!st.data) return;
    try { localStorage.setItem(DATA_PREFIX + nk(st.nick), JSON.stringify(st.data)); } catch (e) {}
  }

  /* ------------------------------------------------------------ группы (как в приложении) */

  function uniqNicks(list) {
    var out = [];
    list.forEach(function (n) {
      n = String(n || '').trim();
      if (n && !hasNick(out, n)) out.push(n);
    });
    return out;
  }
  function hasNick(list, n) {
    var k = nk(n);
    return list.some(function (x) { return nk(x) === k; });
  }
  function groupKey(title, owner) {
    var slug = '';
    Array.from(title.trim().toLowerCase()).forEach(function (ch) {
      if (ch === ' ' || ch === '-' || ch === '_') slug += '_';
      else if (/[a-z0-9а-я]/.test(ch) || ch === 'ё') slug += ch;
    });
    if (!slug) slug = 'grp';
    slug = Array.from(slug).slice(0, 18).join('');
    return GROUP_PREFIX + slug + '_' + nk(owner).replace(/ /g, '_');
  }
  function encodeGroup(key, title, members, text, owner) {
    var head = JSON.stringify({ k: key, t: title, m: uniqNicks(members), o: owner || '' });
    return GROUP_MARK + head + GROUP_MARK + text;
  }
  function decodeGroup(body) {
    if (body.indexOf(GROUP_MARK) !== 0) return null;
    var rest = body.slice(GROUP_MARK.length);
    var cut = rest.indexOf(GROUP_MARK);
    if (cut < 0) return null;
    var head = null;
    try { head = JSON.parse(rest.slice(0, cut)); } catch (e) { return null; }
    if (!head || !head.k) return null;
    return {
      key: String(head.k),
      title: String(head.t || ''),
      members: Array.isArray(head.m) ? head.m : [],
      owner: String(head.o || ''),
      text: rest.slice(cut + GROUP_MARK.length)
    };
  }
  function adoptGroup(g, sender) {
    var cur = st.data.groups[g.key];
    var roster = cur ? cur.members.slice() : [];
    var extra = (g.members || []).concat(g.owner ? [g.owner] : [], sender ? [sender] : [], [st.nick]);
    extra.forEach(function (n) {
      if (nk(n) && !hasNick(roster, n)) roster.push(n);
    });
    st.data.groups[g.key] = {
      title: (g.title || (cur && cur.title) || g.key).slice(0, TITLE_MAX),
      members: roster,
      owner: (cur && cur.owner) || g.owner || '',
      created: cur ? cur.created : nowSec()
    };
  }

  /* ------------------------------------------------------------ чаты */

  function ensureChat(key, name) {
    if (!st.data.chats[key]) st.data.chats[key] = { name: name, msgs: [] };
    return st.data.chats[key];
  }
  function msgsOf(key) {
    var c = st.data.chats[key];
    return c && c.msgs ? c.msgs : [];
  }
  function lastMsg(key) {
    var list = msgsOf(key);
    return list.length ? list[list.length - 1] : null;
  }
  function lastTs(key) {
    var m = lastMsg(key);
    return m ? m.ts : 0;
  }
  function sortMsgs(list) {
    list.sort(function (a, b) { return a.ts - b.ts; });
  }
  function isGroup(key) {
    return !!st.data.groups[key];
  }
  function titleOf(key) {
    if (isGroup(key)) return st.data.groups[key].title || key;
    var c = st.data.chats[key];
    return c && c.name ? c.name : key;
  }
  function isOnline(key) {
    var t = peerSeen[key];
    return !!t && nowSec() - t <= ONLINE_SEC;
  }
  function groupRoster(key) {
    return st.data.groups[key].members || [];
  }
  function chatItems() {
    var items = [], me = nk(st.nick);
    Object.keys(st.data.groups).forEach(function (k) {
      items.push({ key: k, group: true, ts: lastTs(k) });
    });
    Object.keys(st.data.chats).forEach(function (k) {
      if (k === me || st.data.groups[k] || k.indexOf(GROUP_PREFIX) === 0) return;
      items.push({ key: k, group: false, ts: lastTs(k) });
    });
    items.sort(function (a, b) { return b.ts - a.ts; });
    return items;
  }
  function markRead(key) {
    if (st.data.unread[key]) {
      st.data.unread[key] = 0;
      saveData();
    }
  }

  function receiveDirect(from, text, ts, id) {
    var key = nk(from);
    var chat = ensureChat(key, from);
    if (!text.trim()) return;
    chat.msgs.push({ text: text, ts: ts, mine: false, id: id });
    sortMsgs(chat.msgs);
    if (!(st.view === 'chat' && st.peer === key)) {
      st.data.unread[key] = (st.data.unread[key] || 0) + 1;
    }
  }
  function receiveGroup(from, g, ts, id) {
    adoptGroup(g, from);
    var chat = ensureChat(g.key, titleOf(g.key));
    if (!g.text.trim()) return;
    chat.msgs.push({ text: g.text, ts: ts, mine: false, from: from, id: id });
    sortMsgs(chat.msgs);
    if (!(st.view === 'chat' && st.peer === g.key)) {
      st.data.unread[g.key] = (st.data.unread[g.key] || 0) + 1;
    }
  }

  function sendText(text) {
    text = String(text || '').trim();
    var key = st.peer;
    if (!text || !key || !st.data) return;
    var ts = nowSec();
    if (isGroup(key)) {
      var g = st.data.groups[key];
      ensureChat(key, g.title).msgs.push({ text: text, ts: ts, mine: true, from: st.nick });
      saveData();
      refreshAll();
      var packed = encodeGroup(key, g.title, g.members, text, g.owner);
      g.members.filter(function (n) { return nk(n) !== nk(st.nick); })
        .forEach(function (n) { apiSend(n, packed, ts).catch(sendFailed); });
    } else {
      var chat = ensureChat(key, key);
      chat.msgs.push({ text: text, ts: ts, mine: true });
      saveData();
      refreshAll();
      apiSend(chat.name, text, ts).catch(sendFailed);
    }
  }
  function sendFailed() {
    st.status = 'Сообщение не ушло: нет связи с облаком';
    refreshAll();
  }

  /* Пришло сообщение из облака: сохраняем у себя и только потом удаляем на сервере */
  function deliver(row) {
    if (!st.data) return;
    var id = String(row.id == null ? '' : row.id);
    if (!id) return;
    if (st.data.seen.indexOf(id) < 0) {
      var body = String(row.body || '');
      var from = String(row.from_nick || '');
      var ts = Number(row.client_ts) || nowSec();
      var group = decodeGroup(body);
      var key = group ? group.key : nk(from);
      if (key && from) {
        if (group) receiveGroup(from, group, ts, id);
        else receiveDirect(from, body, ts, id);
        st.data.seen.push(id);
        if (st.data.seen.length > SEEN_MAX) st.data.seen.splice(0, st.data.seen.length - SEEN_MAX);
        saveData();
        var text = group ? group.text : body;
        if (text.trim() && !(st.view === 'chat' && st.peer === key)) {
          notify(key, group ? titleOf(key) : from, group ? from + ': ' + text : text);
        }
      }
    }
    apiDelete(id).catch(noop);
    refreshAll();
  }

  /* ------------------------------------------------------------ кто в сети и пинг */

  function presenceKeys() {
    var keys = [];
    function add(k) {
      if (k && keys.indexOf(k) < 0 && k !== nk(st.nick)) keys.push(k);
    }
    Object.keys(st.data.chats).forEach(function (k) {
      if (k.indexOf(GROUP_PREFIX) !== 0 && !isGroup(k)) add(k);
    });
    Object.keys(st.data.groups).forEach(function (g) {
      groupRoster(g).forEach(function (n) { add(nk(n)); });
    });
    return keys;
  }
  function beat() {
    if (!st.nick) return;
    apiPresenceUpsert().catch(noop);
  }
  function look() {
    if (!st.nick) return;
    var keys = presenceKeys();
    if (!keys.length) return;
    apiPresenceFind(keys).then(function (rows) {
      (rows || []).forEach(function (r) { peerSeen[r.nick_key] = parseTime(r.last_seen); });
      refreshAll();
    }).catch(noop);
  }
  function measurePing() {
    if (!st.nick) return;
    var t = Date.now();
    apiPing().then(function () {
      st.ping = Date.now() - t;
      updatePing();
    }).catch(function () {
      st.ping = -1;
      updatePing();
    });
  }
  function pingText() {
    return st.ping < 0 ? 'Пинг: —' : 'Пинг: ' + st.ping + ' мс';
  }
  function updatePing() {
    var el = $('tg-ping');
    if (el) el.textContent = pingText();
  }
  function pullPending() {
    if (!st.nick) return;
    apiPending().then(function (rows) {
      (rows || []).forEach(deliver);
    }).catch(noop);
  }

  /* ------------------------------------------------------------ живой канал (Realtime) */

  function nextRef() {
    refN++;
    return String(refN);
  }
  function sendFrame(obj) {
    if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj));
  }
  function closeSocket() {
    clearInterval(hbTimer);
    hbTimer = null;
    joined = false;
    if (ws) {
      var s = ws;
      ws = null;
      s.onclose = null;
      s.onmessage = null;
      try { s.close(); } catch (e) {}
    }
  }
  function disconnect() {
    wantOnline = false;
    clearTimeout(retryTimer);
    closeSocket();
  }
  function scheduleRetry() {
    clearTimeout(retryTimer);
    st.status = 'Нет связи, пробую снова…';
    retryTimer = setTimeout(connect, retryDelay);
    retryDelay = Math.min(retryDelay * 2, 15000);
  }
  function setOnline(v) {
    st.online = v;
    if (v) st.status = '';
    refreshAll();
  }
  function connect() {
    if (!st.nick) return;
    wantOnline = true;
    clearTimeout(retryTimer);
    closeSocket();
    st.status = 'Подключаюсь…';
    var sock = null;
    try {
      sock = new WebSocket(SB_URL.replace(/^https/, 'wss') + '/realtime/v1/websocket?apikey=' +
        encodeURIComponent(SB_KEY) + '&vsn=1.0.0');
    } catch (e) {
      scheduleRetry();
      return;
    }
    ws = sock;
    sock.onopen = function () {
      sendFrame({
        topic: RT_TOPIC,
        event: 'phx_join',
        payload: {
          config: {
            broadcast: { self: false },
            presence: { key: '' },
            postgres_changes: [{
              event: 'INSERT', schema: 'public', table: 'messages', filter: 'to_nick=eq.' + st.nick
            }]
          },
          access_token: SB_KEY
        },
        ref: nextRef()
      });
      clearInterval(hbTimer);
      hbTimer = setInterval(function () {
        sendFrame({ topic: 'phoenix', event: 'heartbeat', payload: {}, ref: nextRef() });
      }, 25000);
    };
    sock.onmessage = function (ev) {
      if (sock === ws) onFrame(ev.data);
    };
    sock.onclose = function () {
      if (sock !== ws) return;
      joined = false;
      clearInterval(hbTimer);
      ws = null;
      scheduleRetry();
      setOnline(false);
    };
    refreshAll();
  }
  function onFrame(text) {
    var msg = null;
    try { msg = JSON.parse(text); } catch (e) { return; }
    if (msg.event === 'phx_reply' && msg.topic === RT_TOPIC) {
      if (msg.payload && msg.payload.status === 'ok') {
        if (!joined) {
          joined = true;
          retryDelay = 1000;
          setOnline(true);
          pullPending();
        }
      } else {
        st.status = 'Облако не приняло подключение';
        if (ws) ws.close();
      }
    } else if (msg.event === 'postgres_changes') {
      var data = msg.payload && msg.payload.data;
      if (data && data.type === 'INSERT' && data.record) deliver(data.record);
    } else if (msg.event === 'phx_error' || msg.event === 'phx_close') {
      if (ws) ws.close();
    }
  }

  /* ------------------------------------------------------------ уведомления */

  function beep() {
    try {
      audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
      var o = audioCtx.createOscillator();
      var g = audioCtx.createGain();
      o.frequency.value = 880;
      g.gain.setValueAtTime(0.15, audioCtx.currentTime);
      g.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.35);
      o.connect(g);
      g.connect(audioCtx.destination);
      o.start();
      o.stop(audioCtx.currentTime + 0.36);
    } catch (e) {}
  }
  function notify(key, title, text) {
    beep();
    var layer = $('tg-toast-layer');
    if (!layer) {
      layer = document.createElement('div');
      layer.id = 'tg-toast-layer';
      layer.className = 'tg-toast-layer';
      document.body.appendChild(layer);
    }
    var card = document.createElement('div');
    card.className = 'tg-toast';
    card.innerHTML = '<b>' + esc(title) + '</b><span>' + esc(text) + '</span>';
    card.addEventListener('click', function () {
      card.remove();
      if (st.nick) openChat(key);
    });
    layer.appendChild(card);
    setTimeout(function () { card.remove(); }, 5000);
    if (document.hidden && 'Notification' in window && Notification.permission === 'granted') {
      try { new Notification(title, { body: text }); } catch (e) {}
    }
  }
  function requestNotify() {
    if ('Notification' in window) {
      Notification.requestPermission().then(function () { render(); }, noop);
    }
  }

  /* ------------------------------------------------------------ вход и выход */

  function failAuth(text) {
    st.busy = false;
    st.err = text;
    render();
  }
  function enterAs(nick, hash) {
    st.nick = nick;
    st.busy = false;
    st.err = '';
    st.data = loadData(nick);
    st.data.nick = nick;
    st.data.pass_hash = hash;
    saveData();
    try { localStorage.setItem(SESSION_KEY, nick); } catch (e) {}
    startApp();
  }
  async function doLogin(form) {
    var nick = fv(form, 'nick').trim();
    var pass = fv(form, 'password');
    if (nick.length < 2) return failAuth('Ник слишком короткий: нужно хотя бы 2 символа.');
    st.busy = true;
    st.err = '';
    render();
    try {
      var p = await apiFindProfile(nick);
      if (!p) return failAuth('Аккаунт не найден. Создай ник.');
      var hash = await sha256(pass);
      if (p.pass_hash && p.pass_hash !== hash) return failAuth('Неверный пароль.');
      enterAs(p.nick || nick, p.pass_hash || '');
    } catch (e) {
      failAuth('Нет связи с облаком. Проверь интернет и попробуй ещё раз.');
    }
  }
  async function doRegister(form) {
    var nick = fv(form, 'nick').trim();
    var pass = fv(form, 'password');
    var repeat = fv(form, 'repeat');
    if (nick.length < 2) return failAuth('Ник слишком короткий: нужно хотя бы 2 символа.');
    if (nick.length > 24) return failAuth('Ник слишком длинный: максимум 24 символа.');
    if (pass !== repeat) return failAuth('Пароли не совпадают.');
    if (pass && pass.length < 6) return failAuth('Пароль слишком короткий: нужно хотя бы 6 знаков.');
    st.busy = true;
    st.err = '';
    render();
    try {
      if (await apiFindProfile(nick)) return failAuth('Такой ник уже занят. Войди под ним.');
      var hash = await sha256(pass);
      await apiClaimProfile(nick, hash);
      enterAs(nick, hash);
    } catch (e) {
      failAuth(e.status === 409 ? 'Такой ник уже занят. Войди под ним.'
        : 'Нет связи с облаком. Попробуй ещё раз.');
    }
  }
  function logout() {
    disconnect();
    stopTimers();
    try { localStorage.removeItem(SESSION_KEY); } catch (e) {}
    st.nick = '';
    st.data = null;
    st.view = 'chats';
    st.peer = '';
    st.online = false;
    st.err = '';
    st.authMode = 'login';
    render();
  }
  function startApp() {
    st.view = 'chats';
    st.peer = '';
    st.err = '';
    st.online = false;
    render();
    stopTimers();
    connect();
    beat();
    look();
    measurePing();
    timers.push(setInterval(beat, 25000));
    timers.push(setInterval(look, 12000));
    timers.push(setInterval(measurePing, 8000));
    timers.push(setInterval(pullPending, 12000));
  }
  function stopTimers() {
    timers.forEach(clearInterval);
    timers = [];
  }

  /* ------------------------------------------------------------ действия в приложении */

  function go(view) {
    st.view = view;
    st.err = '';
    st.pending = '';
    render();
  }
  function openChat(key) {
    st.view = 'chat';
    st.peer = key;
    st.err = '';
    st.pending = '';
    markRead(key);
    render();
  }
  async function openNewChat(raw, force) {
    var nick = String(raw || '').trim();
    st.err = '';
    st.pending = '';
    if (nick.length < 2) {
      st.err = 'Ник слишком короткий: нужно хотя бы 2 символа.';
      return render();
    }
    if (nk(nick) === nk(st.nick)) {
      st.err = 'Это твой собственный ник.';
      return render();
    }
    if (!force) {
      st.busy = true;
      render();
      var p = null;
      try {
        p = await apiFindProfile(nick);
      } catch (e) {
        st.busy = false;
        st.err = 'Нет связи с облаком. Попробуй ещё раз.';
        return render();
      }
      st.busy = false;
      if (!p) {
        st.pending = nick;
        st.err = 'Такого ника в Тнграме нет. Проверь написание или открой всё равно.';
        return render();
      }
      nick = p.nick || nick;
    }
    ensureChat(nk(nick), nick);
    saveData();
    openChat(nk(nick));
  }
  function createGroup(form) {
    var title = fv(form, 'title').trim();
    var picked = Array.prototype.slice.call(form.querySelectorAll('input[name="m"]:checked'))
      .map(function (b) { return b.value; });
    var extra = fv(form, 'extra').split(',').map(function (s) { return s.trim(); }).filter(Boolean);
    var members = [];
    picked.concat(extra).forEach(function (n) {
      if (nk(n) && nk(n) !== nk(st.nick) && !hasNick(members, n)) members.push(n);
    });
    if (title.length < 2) {
      st.err = 'Название группы — хотя бы 2 символа.';
      return render();
    }
    if (!members.length) {
      st.err = 'Отметь хотя бы одного человека.';
      return render();
    }
    title = title.slice(0, TITLE_MAX);
    members = members.slice(0, GROUP_MAX);
    var key = groupKey(title, st.nick);
    st.data.groups[key] = {
      title: title,
      members: uniqNicks([st.nick].concat(members)),
      owner: st.nick,
      created: nowSec()
    };
    ensureChat(key, title);
    saveData();
    openChat(key);
  }
  function deleteHistory() {
    if (!st.peer || !st.data.chats[st.peer]) return;
    if (!window.confirm('Удалить переписку с ' + titleOf(st.peer) + '? Восстановить её нельзя.')) return;
    st.data.chats[st.peer].msgs = [];
    st.data.unread[st.peer] = 0;
    saveData();
    refreshAll();
  }
  function clearAll() {
    if (!window.confirm('Удалить всю переписку в этом браузере? Восстановить её нельзя.')) return;
    st.data.chats = {};
    st.data.groups = {};
    st.data.unread = {};
    saveData();
    go('chats');
  }
  function fetchNews() {
    st.news = null;
    st.newsErr = false;
    render();
    apiNews().then(function (rows) {
      st.news = rows || [];
      paintNews();
    }).catch(function () {
      st.news = [];
      st.newsErr = true;
      paintNews();
    });
  }
  function sendFromForm(form) {
    var input = form.querySelector('[name="text"]');
    if (!input) return;
    var value = input.value;
    input.value = '';
    sendText(value);
    scrollBottom();
    input.focus();
  }

  /* ------------------------------------------------------------ отрисовка */

  function colorFor(seed) {
    if (seed === 'group') return '#10dfa0';
    var s = nk(seed) || '?';
    var h = 0;
    for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
    return 'hsl(' + (Math.abs(h) % 360) + ', 70%, 68%)';
  }
  function avatarHtml(label, size, online, seed) {
    var letter = (String(label || '?').trim().charAt(0) || '?').toUpperCase();
    return '<div class="tg-avatar' + (size ? ' ' + size : '') + '" style="background:' + colorFor(seed || label) + '">' +
      esc(letter) + (online ? '<span class="tg-online-dot"></span>' : '') + '</div>';
  }
  function errHtml() {
    return st.err ? '<p class="tg-err">' + esc(st.err) + '</p>' : '';
  }

  function authHtml() {
    var reg = st.authMode === 'register';
    return '<div class="tg-window"><div class="tg-center-wrap">' +
      '<form class="tg-auth-card" data-form="' + (reg ? 'register' : 'login') + '" autocomplete="off">' +
      '<img class="tg-auth-logo" src="icon.png" alt="">' +
      '<h2 class="tg-auth-title">' + (reg ? 'Новый ник' : 'Вход в Тнграм') + '</h2>' +
      '<p class="tg-auth-sub">' + (reg ? 'Ник — твой адрес. Телефон и почта не нужны.'
        : 'Тот же ник и пароль, что и в приложении.') + '</p>' +
      '<div><span class="tg-label">Ник</span>' +
      '<input class="tg-input pill" name="nick" placeholder="например, твой_ник" autocomplete="username"></div>' +
      '<div><span class="tg-label">Пароль' + (reg ? ' (необязательно)' : '') + '</span>' +
      '<input class="tg-input pill" type="password" name="password" autocomplete="' +
      (reg ? 'new-password' : 'current-password') + '"></div>' +
      (reg ? '<div><span class="tg-label">Повтори пароль</span>' +
        '<input class="tg-input pill" type="password" name="repeat" autocomplete="new-password"></div>' : '') +
      errHtml() +
      '<button class="tg-btn accent" type="submit"' + (st.busy ? ' disabled' : '') + '>' +
      (reg ? 'Создать и войти' : 'Войти') + '</button>' +
      '<button class="tg-btn" type="button" data-act="' + (reg ? 'show-login' : 'show-register') + '">' +
      (reg ? 'Уже есть ник — войти' : 'Создать ник') + '</button>' +
      '</form></div></div>';
  }

  function sideHtml() {
    return '<div class="tg-side-top">' +
      '<div class="tg-user-row">' + avatarHtml(st.nick, '', false) +
      '<div class="tg-user-info"><b>' + esc(st.nick) + '</b><small>Это ты</small></div></div>' +
      '<div class="tg-status-box" id="tg-status-line"></div>' +
      '<div class="tg-actions-row">' +
      '<button class="tg-btn sm" data-act="new-chat">Новый чат</button>' +
      '<button class="tg-btn sm" data-act="new-group">Группа</button></div>' +
      '<input class="tg-input pill" id="tg-search" placeholder="Поиск по чатам" autocomplete="off">' +
      '</div>' +
      '<div class="tg-chat-list" id="tg-chatlist"></div>' +
      '<div class="tg-side-bottom">' +
      '<button class="tg-btn sm" data-act="news">Что нового</button>' +
      '<button class="tg-btn sm" data-act="settings">Настройки</button></div>';
  }

  function panelHead(title) {
    return '<div class="tg-chat-head"><button class="tg-btn sm" data-act="back">← Назад</button>' +
      '<div class="tg-chat-head-info"><span class="tg-chat-head-title">' + esc(title) + '</span></div></div>';
  }

  function chatHtml() {
    return '<div class="tg-chat-head" id="tg-head"></div>' +
      '<div class="tg-messages-stage"><div class="tg-messages" id="tg-msgs"></div>' +
      '<button class="tg-down-btn" id="tg-down" data-act="scroll-bottom" hidden>↓</button></div>' +
      '<form class="tg-input-bar" data-form="send" autocomplete="off">' +
      '<div class="tg-input-note" id="tg-note"></div>' +
      '<div class="tg-input-row"><input class="tg-input pill" id="tg-input" name="text" ' +
      'placeholder="Сообщение…" maxlength="2000">' +
      '<button class="tg-btn accent" type="submit">Отправить</button></div></form>';
  }

  function chatRowHtml(item) {
    var key = item.key;
    var last = lastMsg(key);
    var title = titleOf(key);
    var sub;
    if (last) {
      var prefix = last.mine ? 'Вы: ' : (item.group && last.from ? last.from + ': ' : '');
      sub = prefix + last.text;
    } else {
      sub = item.group ? 'Участников: ' + groupRoster(key).length : 'Сообщений пока нет';
    }
    var unread = st.data.unread[key] || 0;
    var online = !item.group && isOnline(key);
    return '<button class="tg-contact-card' + (st.view === 'chat' && st.peer === key ? ' selected' : '') +
      '" data-act="open-chat" data-key="' + esc(key) + '">' +
      avatarHtml(title, 'sm', online, item.group ? 'group' : title) +
      '<div class="tg-contact-body"><span class="tg-contact-name">' + esc(title) + '</span>' +
      '<span class="tg-contact-sub">' + esc(sub) + '</span></div>' +
      '<div class="tg-contact-meta"><span class="tg-contact-time">' +
      (last ? fmtTime(last.ts) : '') + '</span>' +
      (unread > 0 ? '<span class="tg-unread-badge">' + unread + '</span>' : '') + '</div></button>';
  }

  function paintSide() {
    var line = $('tg-status-line');
    if (line) {
      line.innerHTML = st.online
        ? '<span class="tg-status-online">● На связи с облаком</span>'
        : '<span>' + esc(st.status || 'Нет связи, пробую снова…') + '</span>';
    }
    var list = $('tg-chatlist');
    if (!list) return;
    var all = chatItems();
    var needle = nk(st.search);
    var items = all.filter(function (item) {
      if (!needle) return true;
      var last = lastMsg(item.key);
      return titleOf(item.key).toLowerCase().indexOf(needle) >= 0 ||
        (last && String(last.text).toLowerCase().indexOf(needle) >= 0);
    });
    if (!items.length) {
      list.innerHTML = '<div class="tg-empty-box">' +
        (all.length ? 'Ничего не нашлось' : 'Пока никого. Нажми «Новый чат» и впиши ник собеседника.') + '</div>';
      return;
    }
    list.innerHTML = items.map(chatRowHtml).join('');
  }

  function messagesHtml(list, group) {
    var html = '', lastDay = '';
    list.forEach(function (m, idx) {
      var day = dayLabel(m.ts);
      if (day !== lastDay) {
        lastDay = day;
        html += '<div class="tg-day-sep">' + esc(day) + '</div>';
      }
      var author = (!m.mine && group && m.from) ? '<span class="tg-bubble-author">' + esc(m.from) + '</span>' : '';
      html += '<div class="tg-bubble-row ' + (m.mine ? 'mine' : 'theirs') + '"><div class="tg-bubble">' +
        author + '<span class="tg-bubble-text">' + esc(m.text) + '</span>' +
        '<span class="tg-bubble-time">' + fmtTime(m.ts) +
        ' <button class="tg-copy-btn" data-act="copy" data-i="' + idx + '">Копировать</button></span></div></div>';
    });
    return html;
  }

  function scrollBottom() {
    var box = $('tg-msgs');
    if (!box) return;
    box.scrollTop = box.scrollHeight;
    updateDown();
  }
  function updateDown() {
    var box = $('tg-msgs'), btn = $('tg-down');
    if (!box || !btn) return;
    btn.hidden = !(box.scrollHeight - box.scrollTop - box.clientHeight > 60);
  }

  function paintChat() {
    var head = $('tg-head'), box = $('tg-msgs');
    if (!head || !box || !st.peer) return;
    var key = st.peer;
    var group = isGroup(key);
    var line = '';
    if (group) line = 'участников: ' + groupRoster(key).length;
    else if (isOnline(key)) line = 'в сети';
    else if (peerSeen[key]) line = 'был(а) ' + ago(peerSeen[key]);
    head.innerHTML = '<button class="tg-btn sm tg-mobile-only" data-act="back">←</button>' +
      avatarHtml(titleOf(key), 'sm', !group && isOnline(key), group ? 'group' : titleOf(key)) +
      '<div class="tg-chat-head-info"><span class="tg-chat-head-title">' + esc(titleOf(key)) + '</span>' +
      '<span class="tg-chat-head-status' + (!group && isOnline(key) ? ' online' : '') + '">' + esc(line) + '</span></div>' +
      '<span class="tg-ping-badge" id="tg-ping">' + pingText() + '</span>' +
      '<button class="tg-btn sm danger" data-act="delete-history">Очистить</button>';
    var note = $('tg-note');
    if (note) {
      note.textContent = st.online
        ? 'Связь есть: сообщение уйдёт на сервер и удалится, когда дойдёт.'
        : 'Связи нет: сообщение пока сохранится только в этом браузере.';
    }
    var list = msgsOf(key);
    var stick = box.scrollHeight - box.scrollTop - box.clientHeight < 80;
    box.innerHTML = list.length ? messagesHtml(list, group)
      : '<div class="tg-empty-box">Напиши первое сообщение' +
        (group ? ' — группа появится у всех, кого отметил.' : '.') + '</div>';
    if (stick) box.scrollTop = box.scrollHeight;
    markRead(key);
    updateDown();
  }

  function newChatHtml() {
    return panelHead('Новый чат') +
      '<div class="tg-panel-scroll"><form class="tg-card" data-form="newchat" autocomplete="off">' +
      '<span class="tg-label">Кому (ник собеседника)</span>' +
      '<input class="tg-input pill" name="nick" placeholder="ник собеседника" autocomplete="off">' +
      errHtml() +
      '<button class="tg-btn accent" type="submit"' + (st.busy ? ' disabled' : '') + '>Открыть чат</button>' +
      (st.pending ? '<button class="tg-btn" type="button" data-act="open-anyway" data-nick="' +
        esc(st.pending) + '">Всё равно открыть</button>' : '') +
      '</form></div>';
  }

  function newGroupHtml() {
    var people = chatItems().filter(function (i) { return !i.group; });
    var boxes = people.length ? people.map(function (i) {
      var t = titleOf(i.key);
      return '<label class="tg-contact-card"><input type="checkbox" name="m" value="' + esc(t) + '"> ' +
        avatarHtml(t, 'sm', false) + '<span class="tg-contact-name">' + esc(t) + '</span></label>';
    }).join('') : '<p class="tg-auth-sub">Пока нет собеседников. Сначала открой чат с человеком.</p>';
    return panelHead('Новая группа') +
      '<div class="tg-panel-scroll"><form class="tg-card" data-form="newgroup" autocomplete="off">' +
      '<span class="tg-label">Название группы</span>' +
      '<input class="tg-input pill" name="title" placeholder="например, Дачники" maxlength="32">' +
      '<span class="tg-label">Кого добавить</span>' + boxes +
      '<span class="tg-label">Или ники через запятую</span>' +
      '<input class="tg-input pill" name="extra" placeholder="ник1, ник2" autocomplete="off">' +
      errHtml() +
      '<button class="tg-btn accent" type="submit">Создать группу</button></form></div>';
  }

  function newsInner() {
    if (st.news === null) return '<p class="tg-auth-sub">Загружаю…</p>';
    if (st.newsErr) return '<div class="tg-empty-box">Новости не загрузились — проверь связь.</div>';
    if (!st.news.length) return '<div class="tg-empty-box">Новостей пока нет.</div>';
    return st.news.map(function (n) {
      var date = n.created_at ? dayLabel(parseTime(n.created_at)) : '';
      return '<div class="tg-card"><b style="color:rgb(var(--a2))">' + esc(n.title || '') + '</b>' +
        '<span>' + esc(n.body || '') + '</span>' +
        (date ? '<span class="tg-auth-sub">' + esc(date) + '</span>' : '') + '</div>';
    }).join('');
  }
  function paintNews() {
    var el = $('tg-news');
    if (el) el.innerHTML = newsInner();
  }

  function settingsHtml() {
    var perm = 'Notification' in window ? Notification.permission : 'unsupported';
    var permText = perm === 'granted' ? 'включены'
      : perm === 'denied' ? 'запрещены в настройках браузера'
      : perm === 'default' ? 'не включены' : 'не поддерживаются этим браузером';
    return panelHead('Настройки') + '<div class="tg-panel-scroll">' +
      '<div class="tg-card"><div class="tg-card-row"><span>Аккаунт</span><b>' + esc(st.nick) + '</b></div>' +
      '<button class="tg-btn" data-act="logout">Выйти из аккаунта</button></div>' +
      '<div class="tg-card"><span>Уведомления браузера: ' + permText + '</span>' +
      (perm === 'default' ? '<button class="tg-btn" data-act="notify">Разрешить уведомления</button>' : '') +
      '</div>' +
      '<div class="tg-card"><span class="tg-auth-sub">Переписка на сайте хранится только в этом браузере.</span>' +
      '<button class="tg-btn danger" data-act="clear-all">Очистить всю переписку здесь</button></div>' +
      '<div class="tg-card tg-banner">ИИ-помощник и отправка файлов пока только в приложении.</div>' +
      '</div>';
  }

  function newsHtml() {
    return panelHead('Что нового') + '<div class="tg-panel-scroll" id="tg-news">' + newsInner() + '</div>';
  }

  function chatShellHtml() {
    return chatHtml();
  }

  function mainHtml() {
    switch (st.view) {
      case 'chat': return chatShellHtml();
      case 'newchat': return newChatHtml();
      case 'newgroup': return newGroupHtml();
      case 'settings': return settingsHtml();
      case 'news': return newsHtml();
      default:
        return '<div class="tg-panel-scroll" style="justify-content:center">' +
          '<div class="tg-empty-box">Выбери чат слева или нажми «Новый чат».</div></div>';
    }
  }

  function render() {
    if (!shell) return;
    if (!st.nick) {
      shell.innerHTML = authHtml();
      return;
    }
    shell.innerHTML = '<div class="tg-window"><div class="tg-split' +
      (st.view !== 'chats' ? ' mobile-show-main' : '') + '">' +
      '<aside class="tg-sidebar">' + sideHtml() + '</aside>' +
      '<section class="tg-main">' + mainHtml() + '</section></div></div>';
    var search = $('tg-search');
    if (search) search.value = st.search;
    paintSide();
    if (st.view === 'chat') {
      paintChat();
      var box = $('tg-msgs');
      if (box) box.addEventListener('scroll', updateDown);
      requestAnimationFrame(scrollBottom);
    }
  }

  function refreshAll() {
    if (!st.nick || !st.data) return;
    if (st.view === 'chat') paintChat();
    paintSide();
  }

  /* ------------------------------------------------------------ обработчики */

  function onClick(e) {
    var el = e.target.closest('[data-act]');
    if (!el || !shell.contains(el)) return;
    switch (el.dataset.act) {
      case 'show-register': st.authMode = 'register'; st.err = ''; render(); break;
      case 'show-login': st.authMode = 'login'; st.err = ''; render(); break;
      case 'open-chat': openChat(el.dataset.key); break;
      case 'new-chat': go('newchat'); break;
      case 'new-group': go('newgroup'); break;
      case 'news': go('news'); fetchNews(); break;
      case 'settings': go('settings'); break;
      case 'back': go('chats'); break;
      case 'logout': logout(); break;
      case 'notify': requestNotify(); break;
      case 'clear-all': clearAll(); break;
      case 'delete-history': deleteHistory(); break;
      case 'open-anyway': openNewChat(el.dataset.nick, true); break;
      case 'scroll-bottom': scrollBottom(); break;
      case 'copy': copyMessage(el); break;
    }
  }
  function copyMessage(el) {
    var m = msgsOf(st.peer)[Number(el.dataset.i)];
    if (!m) return;
    var done = function () {
      el.textContent = 'Скопировано';
      setTimeout(function () { el.textContent = 'Копировать'; }, 1200);
    };
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(m.text).then(done, noop);
      return;
    }
    var area = document.createElement('textarea');
    area.value = m.text;
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    try { document.execCommand('copy'); done(); } catch (e) {}
    area.remove();
  }
  function onSubmit(e) {
    var form = e.target;
    var kind = form.dataset ? form.dataset.form : '';
    if (!kind) return;
    e.preventDefault();
    if (kind === 'login') doLogin(form);
    else if (kind === 'register') doRegister(form);
    else if (kind === 'send') sendFromForm(form);
    else if (kind === 'newchat') openNewChat(fv(form, 'nick'), false);
    else if (kind === 'newgroup') createGroup(form);
  }
  function onInput(e) {
    if (e.target.id === 'tg-search') {
      st.search = e.target.value;
      paintSide();
    }
  }

  function setMode(mode) {
    st.mode = mode;
    document.body.classList.toggle('messenger-mode', mode === 'chat');
    document.querySelectorAll('[data-mode]').forEach(function (b) {
      b.setAttribute('aria-selected', String(b.dataset.mode === mode));
    });
    if (mode === 'chat') render();
  }

  function init() {
    shell = $('webapp-shell');
    if (!shell) return;
    shell.addEventListener('click', onClick);
    shell.addEventListener('submit', onSubmit);
    shell.addEventListener('input', onInput);
    document.querySelectorAll('[data-mode]').forEach(function (b) {
      b.addEventListener('click', function () { setMode(b.dataset.mode); });
    });
    var saved = null;
    try { saved = localStorage.getItem(SESSION_KEY); } catch (e) {}
    if (saved) {
      st.nick = saved;
      st.data = loadData(saved);
      startApp();
    } else {
      render();
    }
    setMode(location.hash === '#messenger' ? 'chat' : 'site');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
