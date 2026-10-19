extends Node
class_name TnNet
## Связь «Тнграм» — два способа, одно обещание.
##
## 1. Свой сервер-передаточник: по одному JSON на строку, поверх TCP.
## 2. Облако (Supabase): сообщение ложится строкой в таблицу, о новом сообщении
##    приложение узнаёт мгновенно по потоку изменений (Realtime, WebSocket).
##
## Способ выбирается по введённому адресу: «127.0.0.1:7777» — свой сервер,
## «https://проект.supabase.co» — облако. Обещание одно: получатель забрал —
## сообщение удаляется у сервера; не забрал — ждёт его там.
##
## Это единственное место в приложении, которое знает про сеть.

signal changed                  ## состояние или статус изменились
signal notice(text: String)     ## отладочные строки (включаются флагом debug)

const P := preload("res://scripts/net/Protocol.gd")

## Сколько ждать ответа от сервера, прежде чем сказать «не удалось».
## Важно: Windows сам по себе может «висеть» на закрытом порту очень долго,
## поэтому свой тайм-аут обязателен — иначе экран подключения замирает.
const CONNECT_TIMEOUT := 3.5
## Облако живёт за интернетом: даём ему больше времени на рукопожатие.
const CLOUD_TIMEOUT := 12.0
## Раз в сколько секунд напоминать облаку, что мы ещё здесь
const CLOUD_HEARTBEAT := 25.0
## Раз в сколько секунд сами заглядывать в таблицу: поток изменений иногда теряет
## событие, а сообщение при этом спокойно лежит в облаке и ждёт. Такая «проверка
## пропущенного» делает доставку надёжной, даже если поток промолчал.
const CLOUD_CATCHUP := 12.0

enum State { OFF, CONNECTING, ONLINE }
enum Mode { TCP, CLOUD }

var state: int = State.OFF
var host := P.DEFAULT_HOST
var port := P.DEFAULT_PORT
var nick := ""
var cloud_key := ""             ## публичный ключ проекта (для облака)
var auth_token := ""            ## пропуск вошедшего человека (пусто — только ключ)
var mode: int = Mode.TCP        ## выбранный способ связи (по адресу)
var keep_trying := true         ## пробовать снова, если не получилось
var debug := false              ## писать в notice каждую строку протокола
var last_stats: Dictionary = {} ## последний ответ сервера на «stats» (для проверок)
var ping_ms := -1               ## отклик сервера в миллисекундах (-1 — ещё не измерен)
var _ping_sent_at := 0          ## когда отправили запрос, по которому считаем отклик

## Вызывается при входящем сообщении: on_message(from, text, ts, id) -> bool.
## Должна вернуть true, если сообщение сохранено — только тогда сервер удалит его у себя.
var on_message: Callable = Callable()

var _peer := StreamPeerTCP.new()
var _buffer := ""
var _want := false              ## пользователь хочет быть на связи
var _retry_wait := 0.0
var _retry_step := 0.5
var _connect_elapsed := 0.0
var _status_key := "net_off"
var _status_arg := ""

## ---- облако ----
var _cloud_base := ""           ## «https://проект.supabase.co»
var _ws := WebSocketPeer.new()
## Чем проверять шифрование: обычно — стандартные корни. Если в системе они
## не работают (так бывает на Android), сюда кладут свои корни из файла.
var tls_options: TLSOptions = null
var _http: HTTPRequest = null
var _http_job: Dictionary = {}
var _http_queue: Array = []
var _http_busy := false
var _joined := false            ## вошли ли в канал изменений
var _join_sent := false
var _ref := 0                   ## счётчик запросов к каналу
var _hb := 0.0                  ## таймер «я ещё здесь»
var _catchup := CLOUD_CATCHUP   ## таймер «не пропустили ли сообщение»
var _seen: Dictionary = {}      ## уже забранные сообщения (по метке)

func _ready() -> void:
	set_process(true)
	_http = HTTPRequest.new()
	_http.name = "Cloud"
	# Чтобы проверка ника не висела вечно, если облако молчит
	_http.timeout = 10.0
	_http.request_completed.connect(_on_http_completed)
	add_child(_http)

## ------------------------------------------------------------------ снаружи

## Текущее состояние словами (на языке интерфейса)
func status_text() -> String:
	return Loc.tf(_status_key, [_status_arg]) if _status_arg != "" else Loc.t(_status_key)

func is_online() -> bool:
	return state == State.ONLINE

func is_connecting() -> bool:
	return state == State.CONNECTING

func is_off() -> bool:
	return state == State.OFF

## Выйти на связь. Повторяет попытки, пока не получится (см. keep_trying).
## Адрес вида «127.0.0.1:7777» — свой сервер; «https://проект.supabase.co» — облако,
## тогда нужен публичный ключ проекта (cloud_key).
func connect_to(p_host: String, p_port: int, p_nick: String, p_cloud_key: String = "") -> void:
	host = p_host if p_host.strip_edges() != "" else P.DEFAULT_HOST
	port = p_port if p_port > 0 else P.DEFAULT_PORT
	nick = p_nick
	cloud_key = p_cloud_key
	mode = Mode.CLOUD if P.is_cloud(host) else Mode.TCP
	_want = true
	_retry_step = 0.5
	_retry_wait = 0.0
	_try_now()

func stop() -> void:
	_want = false
	state = State.OFF
	_buffer = ""
	_join_sent = false
	_joined = false
	ping_ms = -1
	_ping_sent_at = 0
	_http_queue.clear()
	if _ws != null:
		_ws.close()
	_peer.disconnect_from_host()
	_set_status("net_off")

## Отправить сообщение через сервер.
## false — связи нет; тогда сообщение остаётся только на устройстве.
func send_message(to_nick: String, text: String) -> bool:
	if state != State.ONLINE or to_nick.strip_edges() == "" or text.strip_edges() == "":
		return false
	if mode == Mode.CLOUD:
		_queue_http("send", "POST", P.rest_url(_cloud_base, P.CLOUD_TABLE), {
			"from_nick": nick,
			"to_nick": to_nick.strip_edges(),
			"body": text,
			"client_ts": int(Time.get_unix_time_from_system())
		})
		return true
	_send_line({ "t": P.C_SEND, "to": to_nick, "text": text })
	return true

## Спросить у сервера статистику (нужно проверкам и отладке)
func ask_stats() -> void:
	if mode == Mode.CLOUD:
		if state != State.ONLINE:
			return
		_queue_http("stats", "GET",
			P.rest_url(_cloud_base, P.CLOUD_TABLE + "?select=id&to_nick=eq." + nick.uri_encode()),
			null, ["Prefer: count=exact", "Range: 0-0"])
		return
	_send_line({ "t": P.C_STATS })

## Измерить отклик сервера: сколько миллисекунд идёт ответ. Результат ложится в
## ping_ms, о нём узнают экраны (сигнал changed). Ничего лишнего не спрашиваем:
## у своего сервера — короткий «stats», у облака — крохотная таблица версии.
func measure_ping() -> void:
	if state != State.ONLINE:
		if ping_ms != -1:
			ping_ms = -1
			emit_signal("changed")
		return
	_ping_sent_at = Time.get_ticks_msec()
	if mode == Mode.CLOUD:
		_queue_http("ping", "GET", P.version_url(_cloud_base), null, [], { "key": cloud_key })
		return
	# Сокет вдруг разорвался — не шлём запрос в пустоту, отклик недоступен
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_ping_sent_at = 0
		return
	_send_line({ "t": P.C_STATS })

## Записать отклик, если мы его ждали (ответ пришёл — считаем разницу)
func _note_ping() -> void:
	if _ping_sent_at <= 0:
		return
	ping_ms = maxi(int(Time.get_ticks_msec() - _ping_sent_at), 1)
	_ping_sent_at = 0
	emit_signal("changed")

## ------------------------------------------------------------------ ники в облаке

## Свободен ли ник? Ответ придёт в answer(ok, taken, pass_hash):
## ok=false — облако недоступно; taken=true — ник уже занят кем-то.
## Работает и без подключённого канала сообщений — обычным запросом к таблице.
func cloud_lookup_nick(base_url: String, key: String, nick: String, answer: Callable) -> void:
	var base := base_url.strip_edges().trim_suffix("/")
	if base == "" or key.strip_edges() == "" or P.nick_key(nick) == "":
		answer.call(false, false, "")
		return
	_queue_http("nick_lookup", "GET",
		P.rest_url(base, P.PROFILES_TABLE + "?select=pass_hash,nick&nick_key=eq." + P.nick_key(nick).uri_encode()),
		null, [], { "key": key, "cb": answer })

## Занять ник в облаке насовсем. answer(ok, busy): busy=true — ник уже за другим.
func cloud_claim_nick(base_url: String, key: String, nick: String, pass_hash: String, answer: Callable) -> void:
	var base := base_url.strip_edges().trim_suffix("/")
	if base == "" or key.strip_edges() == "" or P.nick_key(nick) == "":
		answer.call(false, false)
		return
	_queue_http("nick_claim", "POST", P.rest_url(base, P.PROFILES_TABLE), {
		"nick_key": P.nick_key(nick),
		"nick": nick.strip_edges(),
		"pass_hash": pass_hash
	}, ["Prefer: return=minimal"], { "key": key, "cb": answer })

## Узнать у облака последнюю версию приложения. answer(ok, { "version", "notes", "url" }).
## Работает и без подключённого канала — обычным запросом к таблице.
func cloud_fetch_version(base_url: String, key: String, answer: Callable) -> void:
	var base := base_url.strip_edges().trim_suffix("/")
	if base == "" or key.strip_edges() == "":
		answer.call(false, {})
		return
	_queue_http("version", "GET", P.version_url(base), null, [], { "key": key, "cb": answer })

## ------------------------------------------------------------------ кто в сети

## Сказать облаку «я здесь». Строка одна на человека: время просто переписывается.
## answer(ok) — получилось ли отметиться.
func cloud_presence_ping(base_url: String, key: String, nick: String, answer: Callable) -> void:
	var base := base_url.strip_edges().trim_suffix("/")
	if base == "" or key.strip_edges() == "" or P.nick_key(nick) == "":
		answer.call(false)
		return
	_queue_http("presence_ping", "POST", P.presence_url(base), [{
		"nick_key": P.nick_key(nick),
		"nick": nick.strip_edges(),
		"last_seen": Time.get_datetime_string_from_system(true, true) + "+00"
	}], ["Prefer: resolution=merge-duplicates,return=minimal"], { "key": key, "cb": answer })

## Спросить про нескольких: answer(ok, { "ключ_ника": секунды })
func cloud_presence_get(base_url: String, key: String, nicks: Array, answer: Callable) -> void:
	var base := base_url.strip_edges().trim_suffix("/")
	var keys: Array = []
	for nick in nicks:
		var text := P.nick_key(String(nick))
		if text != "":
			keys.append(text)
	var url := P.presence_query_url(base, keys)
	if base == "" or key.strip_edges() == "" or url == "":
		answer.call(false, {})
		return
	_queue_http("presence_get", "GET", url, null, [], { "key": key, "cb": answer })

## ------------------------------------------------------------------ новости

## Новости приложения из облака. answer(ok, [ { "title", "body", "date" } ])
func cloud_fetch_news(base_url: String, key: String, answer: Callable) -> void:
	var base := base_url.strip_edges().trim_suffix("/")
	if base == "" or key.strip_edges() == "":
		answer.call(false, [])
		return
	_queue_http("news", "GET", P.news_url(base), null, [], { "key": key, "cb": answer })

## ------------------------------------------------------------------ вход в облако
## Ник превращается в служебный адрес (см. Protocol.auth_email) — почты у нас нет.
## Облако проверяет пароль и выдаёт пропуск; пропуск и есть доказательство, кто ты.

## Зарегистрировать ник в облаке. answer(ok, причина, пропуск)
func cloud_auth_signup(base_url: String, key: String, nick: String, password: String, answer: Callable) -> void:
	_auth_request("auth_signup", "signup", base_url, key, P.auth_email(nick), password, answer)

## Войти по нику и паролю. answer(ok, причина, пропуск)
func cloud_auth_login(base_url: String, key: String, nick: String, password: String, answer: Callable) -> void:
	_auth_request("auth_login", "token?grant_type=password", base_url, key, P.auth_email(nick), password, answer)

## Обновить пропуск по ключу обновления (пропуск живёт час). answer(ok, причина, пропуск)
func cloud_auth_refresh(base_url: String, key: String, refresh_token: String, answer: Callable) -> void:
	var base := base_url.strip_edges().trim_suffix("/")
	if base == "" or key.strip_edges() == "" or refresh_token.strip_edges() == "":
		answer.call(false, "bad_request", {})
		return
	_queue_http("auth_refresh", "POST", P.auth_url(base, "token?grant_type=refresh_token"),
		{ "refresh_token": refresh_token.strip_edges() }, [], { "key": key, "cb": answer })

func _auth_request(tag: String, path: String, base_url: String, key: String, email: String, password: String, answer: Callable) -> void:
	var base := base_url.strip_edges().trim_suffix("/")
	if base == "" or key.strip_edges() == "" or email == "":
		answer.call(false, "bad_request", {})
		return
	_queue_http(tag, "POST", P.auth_url(base, path),
		{ "email": email, "password": password }, [], { "key": key, "cb": answer })

## ------------------------------------------------------------------ обычные файлы

## Забрать текстовый файл по обычному адресу (например, version.json с сайта).
## Ключ облака сюда не отправляем: это чужой сервер. answer(ok, текст).
func fetch_text(url: String, answer: Callable) -> void:
	var u := url.strip_edges()
	if u == "":
		answer.call(false, "")
		return
	_queue_http("text", "GET", u, null, [], { "cb": answer, "plain": true })

## ------------------------------------------------------------------ соединение

func _process(delta: float) -> void:
	# Служебные запросы к облаку (проверка и занятие ников) идут всегда —
	# даже когда канал сообщений ещё не подключён.
	_pump_http()
	if mode == Mode.CLOUD:
		_process_cloud(delta)
		return
	match state:
		State.OFF:
			if _want and keep_trying:
				_retry_wait -= delta
				if _retry_wait <= 0.0:
					_try_now()
		State.CONNECTING:
			_peer.poll()
			var status := _peer.get_status()
			if status == StreamPeerTCP.STATUS_CONNECTED:
				_go_online()
			elif status == StreamPeerTCP.STATUS_ERROR:
				_fail("net_failed")
			else:
				_connect_elapsed += delta
				if _connect_elapsed > CONNECT_TIMEOUT:
					_fail("net_failed")
		State.ONLINE:
			_peer.poll()
			if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_fail("net_lost")
				return
			_read_available()

func _try_now() -> void:
	if mode == Mode.CLOUD:
		_try_cloud()
		return
	_peer = StreamPeerTCP.new()
	_buffer = ""
	_connect_elapsed = 0.0
	state = State.CONNECTING
	if _peer.connect_to_host(host, port) != OK:
		_fail("net_failed")
		return
	_set_status("net_connecting", "%s:%d" % [host, port])

func _fail(key: String) -> void:
	state = State.OFF
	_join_sent = false
	_joined = false
	ping_ms = -1
	_ping_sent_at = 0
	if mode == Mode.CLOUD:
		if _ws != null:
			_ws.close()
		_set_status(key, _cloud_base)
	else:
		_peer.disconnect_from_host()
		_set_status(key, "%s:%d" % [host, port])
	_retry_wait = _retry_step
	_retry_step = minf(_retry_step * 2.0, 5.0)

func _go_online() -> void:
	state = State.ONLINE
	_retry_step = 0.5
	_set_status("net_hello", nick)
	_send_line({ "t": P.C_HELLO, "nick": nick })

func _set_status(key: String, arg: String = "") -> void:
	_status_key = key
	_status_arg = arg
	emit_signal("changed")

## ------------------------------------------------------------------ облако

func _try_cloud() -> void:
	_cloud_base = host.strip_edges().trim_suffix("/")
	_buffer = ""
	_join_sent = false
	_joined = false
	_connect_elapsed = 0.0
	_seen.clear()
	state = State.CONNECTING
	_ws = WebSocketPeer.new()
	var opts := tls_options
	if opts == null:
		opts = TLSOptions.client()
	if _ws.connect_to_url(P.realtime_url(_cloud_base, cloud_key), opts) != OK:
		_fail("net_failed")
		return
	_set_status("net_connecting", _cloud_base)

func _process_cloud(delta: float) -> void:
	if state == State.OFF:
		if _want and keep_trying:
			_retry_wait -= delta
			if _retry_wait <= 0.0:
				_try_cloud()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_read_ws()
			if state == State.CONNECTING:
				if not _join_sent:
					_join_sent = true
					_send_ws({
						"topic": P.CLOUD_TOPIC,
						"event": "phx_join",
						"payload": {
							"config": {
								"broadcast": { "self": false },
								"presence": { "key": "" },
								"postgres_changes": [{
									"event": "INSERT",
									"schema": "public",
									"table": P.CLOUD_TABLE,
									"filter": "to_nick=eq." + nick
								}]
							},
							"access_token": auth_token if auth_token.strip_edges() != "" else cloud_key
						},
						"ref": _next_ref()
					})
				_connect_elapsed += delta
				if _connect_elapsed > CLOUD_TIMEOUT:
					_fail("net_failed")
				return
			_hb += delta
			if _hb >= CLOUD_HEARTBEAT:
				_hb = 0.0
				_send_ws({ "topic": "phoenix", "event": "heartbeat", "payload": {}, "ref": _next_ref() })
			# Заглядываем в таблицу сами: поток изменений иногда теряет событие
			_catchup -= delta
			if _catchup <= 0.0:
				_catchup = CLOUD_CATCHUP
				_fetch_pending()
		WebSocketPeer.STATE_CONNECTING:
			_connect_elapsed += delta
			if _connect_elapsed > CLOUD_TIMEOUT:
				_fail("net_failed")
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			_fail("net_lost" if state == State.ONLINE else "net_failed")

func _send_ws(data: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_note("→ " + JSON.stringify(data))
	_ws.send_text(JSON.stringify(data))

func _next_ref() -> String:
	_ref += 1
	return str(_ref)

func _read_ws() -> void:
	while _ws.get_available_packet_count() > 0:
		_handle_ws_text(_ws.get_packet().get_string_from_utf8())

func _handle_ws_text(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parsed
	_note("← " + text)
	match String(msg.get("event", "")):
		"phx_reply":
			var payload: Dictionary = msg.get("payload", {})
			if String(payload.get("status", "")) == "ok":
				if not _joined:
					_go_online_cloud()
			else:
				_set_status("net_server_error", JSON.stringify(payload))
		"postgres_changes":
			_take_cloud_event(msg)
		"phx_error":
			_fail("net_lost")

func _go_online_cloud() -> void:
	_joined = true
	state = State.ONLINE
	_retry_step = 0.5
	_hb = 0.0
	_catchup = CLOUD_CATCHUP
	_set_status("net_online", nick)
	# Пока нас не было, сообщения копились в таблице — забираем их
	_fetch_pending()

## Новое сообщение из потока изменений: собираем строку и отдаём наверх
func _take_cloud_event(msg: Dictionary) -> void:
	var payload: Dictionary = msg.get("payload", {})
	var data: Dictionary = payload.get("data", {})
	if str(data.get("type", "")) != "INSERT":
		return
	var row: Dictionary = {}
	# Облако кладёт саму строку в «record». В «columns» — только имена и типы,
	# значений там нет, поэтому читать их оттуда нельзя.
	var record: Variant = data.get("record", null)
	if typeof(record) == TYPE_DICTIONARY:
		row = record
	else:
		for column in data.get("columns", []):
			if typeof(column) == TYPE_DICTIONARY and column.has("value"):
				row[str(column.get("name", ""))] = column.get("value")
	_deliver_cloud_row(row)

## Метка строки словами: из JSON числа приходят дробными (4.0), а базе нужен «4»
func _id_text(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		return str(int(value))
	return str(value).strip_edges()

## Забрать ждущие сообщения напрямую из таблицы (то, что пришло, пока мы молчали)
func _fetch_pending() -> void:
	_queue_http("pending", "GET",
		P.rest_url(_cloud_base, P.CLOUD_TABLE + "?select=*&to_nick=eq." + nick.uri_encode() + "&order=id.asc"))

func _delete_row(id: String) -> void:
	_queue_http("delete", "DELETE", P.rest_url(_cloud_base, P.CLOUD_TABLE + "?id=eq." + id))

## Отдать сообщение наверх и удалить из облака, если его сохранили
func _deliver_cloud_row(row: Dictionary) -> void:
	_note("строка из облака: " + JSON.stringify(row))
	var id := _id_text(row.get("id", ""))
	if id == "" or id == "<null>" or _seen.has(id):
		return
	var from_nick := str(row.get("from_nick", ""))
	var text := str(row.get("body", ""))
	var ts := int(row.get("client_ts", 0))
	var stored := false
	if on_message.is_valid():
		stored = bool(on_message.call(from_nick, text, ts, id))
	if stored:
		_seen[id] = true
		_delete_row(id)
		_note("подтвердил и удалил: " + id)
	else:
		_note("не подтверждаю: " + id)

## ------------------------------------------------------------------ облачный обмен

func _cloud_headers(extra: Array = [], key: String = "", plain: bool = false) -> PackedStringArray:
	var headers := PackedStringArray()
	if plain:
		# Обычный запрос к чужому серверу: без ключей нашего облака
		headers.append("Accept: application/json")
	else:
		var token := key if key.strip_edges() != "" else cloud_key
		headers.append("apikey: " + token)
		# Пропуск человека (если он есть) — по нему облако узнаёт, чьи это сообщения
		var bearer := token
		if auth_token.strip_edges() != "":
			bearer = auth_token.strip_edges()
		headers.append("Authorization: Bearer " + bearer)
		# charset обязателен: без него облако портило кириллицу в никах
		headers.append("Content-Type: application/json; charset=utf-8")
		headers.append("Accept: application/json")
	for line in extra:
		headers.append(String(line))
	return headers

func _queue_http(tag: String, method: String, url: String, body: Variant = null, extra: Array = [], meta: Dictionary = {}) -> void:
	_http_queue.append({ "tag": tag, "method": method, "url": url, "body": body, "extra": extra, "meta": meta })

## По одному запросу за раз: HTTPRequest не умеет несколько сразу
func _pump_http() -> void:
	if _http_busy or _http == null or _http_queue.is_empty():
		return
	var job: Dictionary = _http_queue.pop_front()
	var method := HTTPClient.METHOD_GET
	if String(job["method"]) == "POST":
		method = HTTPClient.METHOD_POST
	elif String(job["method"]) == "DELETE":
		method = HTTPClient.METHOD_DELETE
	var body_text := ""
	if job["body"] != null:
		body_text = JSON.stringify(job["body"])
	_http_job = job
	_http_busy = true
	_note("⇒ " + String(job["method"]) + " " + String(job["url"]))
	var meta: Dictionary = job.get("meta", {})
	if _http.request(String(job["url"]), _cloud_headers(job["extra"], String(meta.get("key", "")), bool(meta.get("plain", false))), method, body_text) != OK:
		_http_busy = false
		_note("не смог начать запрос")

func _on_http_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_http_busy = false
	var job: Dictionary = _http_job
	_http_job = {}
	var tag := String(job.get("tag", ""))
	var callback: Callable = (job.get("meta", {}) as Dictionary).get("cb", Callable())
	if result != HTTPRequest.RESULT_SUCCESS:
		_note("сетевая ошибка запроса: " + str(result))
		if tag == "nick_claim" and callback.is_valid():
			callback.call(false, false)
		elif tag == "nick_lookup" and callback.is_valid():
			callback.call(false, false, "")
		elif tag == "version" and callback.is_valid():
			callback.call(false, {})
		elif tag == "text" and callback.is_valid():
			callback.call(false, "")
		elif tag == "presence_ping" and callback.is_valid():
			callback.call(false)
		elif tag == "presence_get" and callback.is_valid():
			callback.call(false, {})
		elif tag == "news" and callback.is_valid():
			callback.call(false, [])
		elif tag.begins_with("auth_") and callback.is_valid():
			# Облако не ответило — вход продолжится по устройству (запасной путь)
			callback.call(false, "net_error", {})
		return
	var text := body.get_string_from_utf8()
	if code >= 400:
		_note("облако ответило %d: %s" % [code, text])
		# 409 — ник уже занят другим человеком
		if tag == "nick_claim" and callback.is_valid():
			callback.call(true, code == 409)
		elif tag == "nick_lookup" and callback.is_valid():
			callback.call(false, false, "")
		elif tag == "version" and callback.is_valid():
			# Таблицы версии может ещё не быть — это не ошибка, просто ответа нет
			callback.call(false, {})
		elif tag == "text" and callback.is_valid():
			callback.call(false, "")
		elif tag == "presence_ping" and callback.is_valid():
			callback.call(false)
		elif tag == "presence_get" and callback.is_valid():
			callback.call(false, {})
		elif tag == "news" and callback.is_valid():
			# Таблицы новостей может ещё не быть — покажем только «Что нового»
			callback.call(false, [])
		elif tag.begins_with("auth_") and callback.is_valid():
			# 400 — не тот пароль или ник занят; причина приходит словами
			callback.call(false, P.parse_auth_error(text), {})
		return
	match tag:
		"version":
			if callback.is_valid():
				callback.call(true, P.parse_version_answer(text))
		"text":
			if callback.is_valid():
				callback.call(true, text)
		"nick_lookup":
			var taken := false
			var pass_hash := ""
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_ARRAY and (parsed as Array).size() > 0:
				taken = true
				pass_hash = String((parsed[0] as Dictionary).get("pass_hash", ""))
			if callback.is_valid():
				callback.call(true, taken, pass_hash)
		"nick_claim":
			if callback.is_valid():
				callback.call(true, false)
		"presence_ping":
			if callback.is_valid():
				callback.call(true)
		"presence_get":
			var seen := P.parse_presence(text)
			if callback.is_valid():
				callback.call(true, seen)
		"news":
			var items := P.parse_news(text)
			if callback.is_valid():
				callback.call(true, items)
		"auth_signup", "auth_login", "auth_refresh":
			if callback.is_valid():
				callback.call(true, "", P.parse_session(text))
		"pending":
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_ARRAY:
				for row in parsed:
					if typeof(row) == TYPE_DICTIONARY:
						_deliver_cloud_row(row)
		"stats":
			var total := -1
			for line in headers:
				if String(line).to_lower().begins_with("content-range:"):
					total = int(String(line).split("/")[-1])
			last_stats = { "pending": maxi(total, 0), "online": -1, "cloud": true, "delivered": 0, "deleted": 0 }
		"ping":
			_note_ping()

## ------------------------------------------------------------------ приём

func _read_available() -> void:
	var count := _peer.get_available_bytes()
	if count <= 0:
		return
	var result: Array = _peer.get_data(count)
	if int(result[0]) != OK:
		return
	_buffer += (result[1] as PackedByteArray).get_string_from_utf8()
	while true:
		var cut := _buffer.find("\n")
		if cut < 0:
			break
		var line := _buffer.substr(0, cut)
		_buffer = _buffer.substr(cut + 1)
		if line.strip_edges() != "":
			_handle_line(line)

func _handle_line(line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		_note("непонятная строка от сервера: " + line)
		return
	var msg: Dictionary = parsed
	_note("← " + line)
	match String(msg.get("t", "")):
		P.S_WELCOME:
			_set_status("net_online", nick)
		P.S_MSG:
			_take_message(msg)
		P.S_ERROR:
			_set_status("net_server_error", String(msg.get("text", "")))
		P.S_STATS:
			last_stats = msg
			_note_ping()
		P.S_SENT:
			pass
		_:
			_note("неизвестное сообщение от сервера: " + line)

## Входящее сообщение: отдаём наверх и только потом подтверждаем получение.
func _take_message(msg: Dictionary) -> void:
	var from_nick := String(msg.get("from", ""))
	var text := String(msg.get("text", ""))
	var ts := int(msg.get("ts", 0))
	var id := String(msg.get("id", ""))
	var stored := true
	if on_message.is_valid():
		stored = bool(on_message.call(from_nick, text, ts, id))
	else:
		_note("входящее сообщение некому отдать — оставляю на сервере")
		stored = false
	if stored:
		_send_line({ "t": P.C_ACK, "ids": [id] })
		_note("подтвердил получение: " + id)
	else:
		_note("не подтверждаю: " + id)

func _send_line(data: Dictionary) -> void:
	if state != State.ONLINE:
		return
	var line := JSON.stringify(data)
	_note("→ " + line)
	_peer.put_data((line + "\n").to_utf8_buffer())

func _note(text: String) -> void:
	if debug:
		emit_signal("notice", text)
