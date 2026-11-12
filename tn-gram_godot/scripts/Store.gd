extends Node
## Хранилище приложения «Тнграм».
## Держит аккаунты, переписку и настройки, сохраняет всё в один файл на устройстве.
## Подключается как автозагрузка (Autoload) с именем Store — см. project.godot.

const P := preload("res://scripts/net/Protocol.gd")

const DEFAULT_SAVE_PATH := "user://tngram_data.json"
## Аккаунты, которые создаются при первом запуске (без пароля)
const DEFAULT_ACCOUNTS := ["админ", "админ2"]

signal data_changed  ## данные изменились — надо перерисовать экраны
signal presence_changed  ## кто-то появился в сети — обновить зелёные точки

var save_path := DEFAULT_SAVE_PATH  ## где лежат данные (см. профиль ниже)
var accounts: Array = []        ## [{ "nick": String, "pass_hash": String, "created": int }]
var chats: Dictionary = {}      ## { "владелец": { "собеседник": [ {"text", "ts", "mine"} ] } }
var settings: Dictionary = {}   ## { "lang": "ru", "theme": "dark", "relay_host": … }
var current_nick := ""          ## кто сейчас вошёл; пустая строка — никто

## Непрочитанные: { "владелец": { "собеседник": сколько } }
var unread: Dictionary = {}
## Группы: { "владелец": { "адрес_группы": { "title", "members", "created" } } }
var groups: Dictionary = {}
## Кто в сети (только в памяти): { "ключ_ника": когда_видели }
var peer_seen: Dictionary = {}
## Правда, если наш ник занят ещё кем-то (облако сказало или пришло сообщение
## от собеседника с нашим же ником). Тогда в списке чатов видно предупреждение.
var nick_conflict := false

## ------------------------------------------------------------------ жизненный цикл

func _ready() -> void:
	# Переменная TNGRAM_PROFILE включает второй профиль: свои аккаунты и своя переписка.
	# Нужно, чтобы запустить два окна приложения на одном компьютере и проверить связь.
	var profile := OS.get_environment("TNGRAM_PROFILE").strip_edges()
	if profile != "":
		save_path = "user://tngram_data_%s.json" % profile.to_lower().validate_filename()
	load_data()
	if accounts.is_empty():
		_seed_default_accounts()
		save_data()
	_restore_session()

## Вспомнить, кто вошёл в прошлый раз: вход не нужно вводить заново при каждом запуске
func _restore_session() -> void:
	var nick := String(settings.get("last_nick", ""))
	if nick == "" or current_nick != "":
		return
	var acc := find_account(nick)
	if not acc.is_empty():
		current_nick = String(acc["nick"])

## Создаём аккаунты «админ» и «админ2» при самом первом запуске
func _seed_default_accounts() -> void:
	for nick in DEFAULT_ACCOUNTS:
		_add_account_raw(nick, "")

## ------------------------------------------------------------------ аккаунты

func account_exists(nick: String) -> bool:
	return not find_account(nick).is_empty()

func find_account(nick: String) -> Dictionary:
	var wanted := nick.strip_edges().to_lower()
	for acc in accounts:
		if String(acc.get("nick", "")).to_lower() == wanted:
			return acc
	return {}

## Создать аккаунт. Возвращает { "ok": bool, "error": код_ошибки }
func create_account(nick: String, password: String) -> Dictionary:
	nick = nick.strip_edges()
	var err := nick_error(nick)
	if err != "":
		return { "ok": false, "error": err }
	_add_account_raw(nick, password)
	save_data()
	return { "ok": true, "error": "" }

## Проверить ник, ничего не создавая. Возвращает код ошибки или пустую строку.
func nick_error(nick: String) -> String:
	nick = nick.strip_edges()
	if nick.length() < 2:
		return "err_nick_short"
	if nick.length() > 24:
		return "err_nick_long"
	if account_exists(nick):
		return "err_nick_used"
	return ""

## Хеш пароля — чтобы сверить занятый ник с облаком, не читая пароль оттуда
func hash_password(password: String) -> String:
	return _hash(password)

func _add_account_raw(nick: String, password: String) -> void:
	accounts.append({
		"nick": nick,
		"pass_hash": _hash(password),
		"created": int(Time.get_unix_time_from_system())
	})
	chats[nick] = {}
	unread[nick] = {}
	emit_signal("data_changed")

## Вход. Пустой пароль в аккаунте = вход без пароля
func login(nick: String, password: String) -> Dictionary:
	var acc := find_account(nick)
	if acc.is_empty():
		return { "ok": false, "error": "err_no_account" }
	var saved := String(acc.get("pass_hash", ""))
	if saved != "" and saved != _hash(password):
		return { "ok": false, "error": "err_pass_wrong" }
	current_nick = String(acc["nick"])
	nick_conflict = false
	peer_seen.clear()
	settings["last_nick"] = current_nick
	save_data()
	emit_signal("data_changed")
	return { "ok": true, "error": "" }

func logout() -> void:
	current_nick = ""
	nick_conflict = false
	peer_seen.clear()
	settings.erase("last_nick")
	save_data()
	emit_signal("data_changed")

func current_account() -> Dictionary:
	return find_account(current_nick)

func has_password(nick: String) -> bool:
	var acc := find_account(nick)
	return acc != {} and String(acc.get("pass_hash", "")) != ""

## ---- пропуск в облако (серверный вход) ----
## Пропуск выдаёт облако, когда ник и пароль совпали. По нему облако пускает
## человека только к его переписке: одного ключа из программы для этого мало.
## Лежит он в самом аккаунте, рядом с ником, и переживает перезапуск.

func _session_of(nick: String) -> Dictionary:
	var acc := find_account(nick)
	if acc.is_empty():
		return {}
	var raw: Variant = acc.get("auth", null)
	return raw if typeof(raw) == TYPE_DICTIONARY else {}

## Запомнить выданный пропуск
func set_session(nick: String, session: Dictionary) -> void:
	var acc := find_account(nick)
	if acc.is_empty():
		return
	var token := String(session.get("access_token", "")).strip_edges()
	if token == "":
		return
	acc["auth"] = {
		"access_token": token,
		"refresh_token": String(session.get("refresh_token", "")).strip_edges(),
		"expires_at": int(Time.get_unix_time_from_system()) + maxi(int(session.get("expires_in", 3600)), 60),
		"user_id": String(session.get("user_id", "")).strip_edges()
	}
	save_data()
	emit_signal("data_changed")

## Действующий пропуск. Пустая строка — пропуска нет или срок уже вышел.
func auth_token(nick: String = "") -> String:
	var sess := _session_of(nick if nick != "" else current_nick)
	if sess.is_empty():
		return ""
	if int(sess.get("expires_at", 0)) <= int(Time.get_unix_time_from_system()) + 30:
		return ""
	return String(sess.get("access_token", ""))

## Пропуск был, но срок вышел — его надо обновить
func session_expired(nick: String = "") -> bool:
	var sess := _session_of(nick if nick != "" else current_nick)
	if sess.is_empty():
		return false
	return int(sess.get("expires_at", 0)) <= int(Time.get_unix_time_from_system()) + 30

func has_session(nick: String = "") -> bool:
	return not _session_of(nick if nick != "" else current_nick).is_empty()

## Ключ обновления: по нему получают новый пропуск, не спрашивая пароль снова
func refresh_value(nick: String = "") -> String:
	return String(_session_of(nick if nick != "" else current_nick).get("refresh_token", ""))

func clear_session(nick: String) -> void:
	var acc := find_account(nick)
	if acc.is_empty() or not acc.has("auth"):
		return
	acc.erase("auth")
	save_data()
	emit_signal("data_changed")

func delete_account(nick: String) -> void:
	var acc := find_account(nick)
	if acc == {}:
		return
	accounts.erase(acc)
	chats.erase(String(acc["nick"]))
	unread.erase(String(acc["nick"]))
	groups.erase(String(acc["nick"]))
	peer_seen.clear()
	if current_nick == String(acc["nick"]):
		current_nick = ""
		nick_conflict = false
	save_data()

## ------------------------------------------------------------------ переписка

func contacts() -> Array:
	var list: Array = []
	var seen: Dictionary = {}
	for acc in accounts:
		var nick := String(acc.get("nick", ""))
		if nick == "" or _same_nick(nick, current_nick) or seen.has(P.nick_key(nick)):
			continue
		seen[P.nick_key(nick)] = true
		list.append(nick)
	# Собеседники, с которыми уже есть переписка: например, сообщение пришло по сети
	# от ника, которого нет среди аккаунтов этого устройства.
	if chats.has(current_nick):
		for peer in chats[current_nick].keys():
			var name := String(peer)
			# Группа живёт отдельной карточкой (см. chat_keys). Если пропустить
			# эту проверку, группа появляется в списке дважды: как группа и как
			# «человек» с ником вида g:дачники_админ.
			if P.is_group_key(name):
				continue
			# Чат с локальным ИИ показывает отдельная карточка (только телефон),
			# а в списке людей и в «кто в сети» ему делать нечего.
			if P.is_ai_key(name):
				continue
			if seen.has(P.nick_key(name)):
				continue
			# Собеседник с моим собственным ником — это чужая ошибка: ник занят
			# дважды. Прятать его нельзя, иначе «мои сообщения пропадают».
			# Показываем, но только если там что-то есть.
			if _same_nick(name, current_nick) and _messages_of(current_nick, name).is_empty():
				continue
			seen[P.nick_key(name)] = true
			list.append(name)
	return list

## Сообщения чата с собеседником (пустой список, если чата ещё нет)
func messages(peer: String) -> Array:
	return _messages_of(current_nick, peer)

## Последнее сообщение чата — для списка чатов
func last_message(peer: String) -> Dictionary:
	var list := messages(peer)
	return list[-1] if list.size() > 0 else {}

## Сохранить своё сообщение. Пока сервера нет — оно просто живёт на устройстве.
func send_message(peer: String, text: String) -> bool:
	text = text.strip_edges()
	if text == "" or current_nick == "" or peer.strip_edges() == "":
		return false
	if not chats.has(current_nick):
		chats[current_nick] = {}
	var own: Dictionary = chats[current_nick]
	var key := _peer_key(own, peer)
	if not own.has(key):
		own[key] = []
	own[key].append({
		"text": text,
		"ts": int(Time.get_unix_time_from_system()),
		"mine": true
	})
	save_data()
	emit_signal("data_changed")
	return true

## Показать переписку удалённой на устройстве
func delete_history(peer: String) -> void:
	if chats.has(current_nick):
		var own: Dictionary = chats[current_nick]
		own.erase(_peer_key(own, peer))
		mark_read(peer)
		save_data()
		emit_signal("data_changed")

## Записать сообщение, пришедшее от собеседника (по сети).
## net_id — метка сообщения на сервере: по ней отсеиваем повторную доставку.
func receive_message(from_nick: String, text: String, ts: int = 0, net_id: String = "") -> bool:
	text = text.strip_edges()
	if text == "" or current_nick == "" or from_nick.strip_edges() == "":
		return false
	if not chats.has(current_nick):
		chats[current_nick] = {}
	var own: Dictionary = chats[current_nick]
	var key := _peer_key(own, from_nick)
	if not own.has(key):
		own[key] = []
	var list: Array = own[key]
	if net_id != "":
		for message in list:
			if String(message.get("id", "")) == net_id:
				return true  # уже было — но подтвердить получение всё равно нужно
	_insert_sorted(list, {
		"text": text,
		"ts": ts if ts > 0 else int(Time.get_unix_time_from_system()),
		"mine": false,
		"id": net_id
	})
	# Сообщение от собеседника с нашим же ником = ник занят ещё кем-то.
	if _same_nick(key, current_nick):
		nick_conflict = true
	bump_unread(key)
	save_data()
	emit_signal("data_changed")
	return true

## Облако подтвердило, что наш ник занят ещё кем-то — показываем предупреждение
func flag_nick_conflict() -> void:
	if nick_conflict:
		return
	nick_conflict = true
	emit_signal("data_changed")

## Завести пустой чат с новым собеседником, чтобы он появился в списке
func ensure_contact(peer: String) -> bool:
	peer = peer.strip_edges()
	if peer == "" or current_nick == "" or _same_nick(peer, current_nick):
		return false
	if not chats.has(current_nick):
		chats[current_nick] = {}
	var own: Dictionary = chats[current_nick]
	var key := _peer_key(own, peer)
	if not own.has(key):
		own[key] = []
		save_data()
		emit_signal("data_changed")
	return true

## ------------------------------------------------------------------ группы

## Чат — это группа? (адрес начинается с «g:» и группа нам известна)
func is_group(key: String) -> bool:
	if not P.is_group_key(key):
		return false
	if not groups.has(current_nick):
		return false
	return (groups[current_nick] as Dictionary).has(key)

func group_info(key: String) -> Dictionary:
	if not groups.has(current_nick):
		return {}
	var own: Dictionary = groups[current_nick]
	return own.get(key, {})

func group_title(key: String) -> String:
	var info := group_info(key)
	var title := String(info.get("title", "")).strip_edges()
	return title if title != "" else key

## Полный состав группы: создатель, все участники и я сам. Именно этот список
## едет в шапке сообщения, поэтому у каждого участника группа выглядит одинаково
## и ответ доходит до всех — до создателя тоже.
func group_roster(key: String) -> Array:
	var info := group_info(key)
	var full: Array = []
	var owner_nick := String(info.get("owner", "")).strip_edges()
	if owner_nick != "" and not _has_nick(full, owner_nick):
		full.append(owner_nick)
	var stored: Variant = info.get("members", [])
	if typeof(stored) == TYPE_ARRAY:
		for member in (stored as Array):
			var nick := String(member).strip_edges()
			if nick != "" and not _has_nick(full, nick):
				full.append(nick)
	if current_nick != "" and not _has_nick(full, current_nick):
		full.append(current_nick)
	return full

## Состав группы без меня самого — это те, кому уходит сообщение.
func group_members(key: String) -> Array:
	var roster: Array = []
	for nick in group_roster(key):
		if not _same_nick(nick, current_nick):
			roster.append(nick)
	return roster

## Все группы этого человека, свежие сверху
func group_list() -> Array:
	if not groups.has(current_nick):
		return []
	var keys: Array = []
	for key in (groups[current_nick] as Dictionary).keys():
		keys.append({ "key": String(key), "ts": _last_ts(String(key)) })
	keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["ts"]) > int(b["ts"]))
	var list: Array = []
	for item in keys:
		list.append(String(item["key"]))
	return list

## Собрать группу: название и список людей. Возвращает { ok, error, key }.
func create_group(title: String, members: Array) -> Dictionary:
	title = title.strip_edges()
	if current_nick == "":
		return { "ok": false, "error": "err_no_account" }
	if title.length() < 2:
		return { "ok": false, "error": "err_group_title" }
	var roster: Array = []
	for member in members:
		var nick := String(member).strip_edges()
		if nick == "" or _same_nick(nick, current_nick) or _has_nick(roster, nick):
			continue
		roster.append(nick)
	if roster.is_empty():
		return { "ok": false, "error": "err_group_members" }
	if roster.size() > P.GROUP_MAX_MEMBERS:
		roster = roster.slice(0, P.GROUP_MAX_MEMBERS)
	title = title.substr(0, P.GROUP_TITLE_MAX)
	var key := P.group_key(title, current_nick)
	if not groups.has(current_nick):
		groups[current_nick] = {}
	(groups[current_nick] as Dictionary)[key] = {
		"title": title,
		# Полный состав, включая создателя: иначе у остальных участников
		# создатель пропадёт из списка и его ответ до них не дойдёт.
		"members": _unique_nicks([current_nick] + roster),
		"owner": current_nick,
		"created": int(Time.get_unix_time_from_system())
	}
	if not chats.has(current_nick):
		chats[current_nick] = {}
	if not (chats[current_nick] as Dictionary).has(key):
		(chats[current_nick] as Dictionary)[key] = []
	save_data()
	emit_signal("data_changed")
	return { "ok": true, "error": "", "key": key }

## Завести чужую группу у себя: она пришла вместе с первым сообщением.
## Возвращает true, если группу создали или состав обновился.
## Завести у себя группу из чужого письма (или обновить её состав).
## owner_nick — создатель из шапки; sender_nick — кто написал письмо: в старых
## письмах создатель в шапке не едет, но отправитель точно должен быть в составе,
## иначе ответы до него не дойдут.
func adopt_group(key: String, title: String, members: Array, owner_nick: String = "",
		sender_nick: String = "") -> bool:
	if current_nick == "" or not P.is_group_key(key):
		return false
	if not groups.has(current_nick):
		groups[current_nick] = {}
	var own: Dictionary = groups[current_nick]
	var known: Dictionary = own.get(key, {})
	var known_members: Variant = known.get("members", [])
	var roster: Array = _unique_nicks(known_members) if typeof(known_members) == TYPE_ARRAY else []
	var fresh := false
	for member in members:
		var nick := String(member).strip_edges()
		if nick == "" or _same_nick(nick, current_nick) or _has_nick(roster, nick):
			continue
		roster.append(nick)
		fresh = true
	var clean_title := title.strip_edges()
	if clean_title == "":
		clean_title = String(known.get("title", "")).strip_edges()
	if clean_title == "":
		clean_title = key
	# Создатель группы — участник наравне со всеми
	var owner := String(known.get("owner", "")).strip_edges()
	if owner == "":
		owner = owner_nick.strip_edges()
	if owner != "" and not _same_nick(owner, current_nick) and not _has_nick(roster, owner):
		roster.append(owner)
		fresh = true
	# Отправитель письма — тоже участник, даже если шапка старая и без создателя
	var sender := sender_nick.strip_edges()
	if sender != "" and not _same_nick(sender, current_nick) and not _has_nick(roster, sender):
		roster.append(sender)
		fresh = true
	if known.is_empty() or fresh or String(known.get("title", "")) != clean_title \
			or String(known.get("owner", "")) != owner:
		own[key] = {
			"title": clean_title.substr(0, P.GROUP_TITLE_MAX),
			"members": roster,
			"owner": owner,
			"created": int(known.get("created", Time.get_unix_time_from_system()))
		}
		save_data()
		return true
	return false

## Написать в группу. Сообщение сохраняется у себя и уходит всем участникам
## (рассылку делает Main — здесь только запись).
func send_group_message(key: String, text: String) -> bool:
	text = text.strip_edges()
	if text == "" or current_nick == "" or not is_group(key):
		return false
	if not chats.has(current_nick):
		chats[current_nick] = {}
	var own: Dictionary = chats[current_nick]
	if not own.has(key):
		own[key] = []
	(own[key] as Array).append({
		"text": text,
		"ts": int(Time.get_unix_time_from_system()),
		"mine": true,
		"from": current_nick
	})
	save_data()
	emit_signal("data_changed")
	return true

## Сообщение из группы: заводим группу (если впервые слышим) и записываем текст.
## owner_nick — создатель группы из шапки сообщения (в старых сообщениях его нет).
func receive_group_message(from_nick: String, key: String, title: String, members: Array,
		text: String, ts: int = 0, net_id: String = "", owner_nick: String = "") -> bool:
	text = text.strip_edges()
	if text == "" or current_nick == "" or not P.is_group_key(key) or from_nick.strip_edges() == "":
		return false
	adopt_group(key, title, members, owner_nick, from_nick)
	if not chats.has(current_nick):
		chats[current_nick] = {}
	var own: Dictionary = chats[current_nick]
	if not own.has(key):
		own[key] = []
	var list: Array = own[key]
	if net_id != "":
		for message in list:
			if String(message.get("id", "")) == net_id:
				return true
	_insert_sorted(list, {
		"text": text,
		"ts": ts if ts > 0 else int(Time.get_unix_time_from_system()),
		"mine": false,
		"from": from_nick,
		"id": net_id
	})
	bump_unread(key)
	save_data()
	emit_signal("data_changed")
	return true

## Красивое имя собеседника: группы — название, люди — ник из аккаунта,
## если он у нас есть, иначе то написание, каким записан чат.
func peer_title(key: String) -> String:
	if is_group(key):
		return group_title(key)
	for acc in accounts:
		if _same_nick(String(acc.get("nick", "")), key):
			return String(acc.get("nick", ""))
	return key

## Разговор: человек это или группа. Так список чатов показывает и то, и другое.
func chat_keys() -> Array:
	var list: Array = []
	for key in group_list():
		list.append({ "key": key, "group": true, "ts": _last_ts(key) })
	for peer in contacts():
		list.append({ "key": peer, "group": false, "ts": _last_ts(peer) })
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["ts"]) > int(b["ts"]))
	return list

## ------------------------------------------------------------------ кто в сети

## Отметить, что человека видели в сети (время — секунды, как у всех).
func note_seen(nick: String, ts: int) -> void:
	var key := P.nick_key(nick)
	if key == "":
		return
	var before := int(peer_seen.get(key, 0))
	peer_seen[key] = maxi(ts, 1)
	if before != peer_seen[key]:
		emit_signal("presence_changed")

## Применить ответ облака: { "ключ_ника": время }
func apply_presence(found: Dictionary) -> void:
	var changed := false
	for key in found.keys():
		var stamp := int(found[key])
		if int(peer_seen.get(String(key), 0)) != stamp:
			changed = true
		peer_seen[String(key)] = stamp
	if changed:
		emit_signal("presence_changed")

## Когда человека видели в последний раз (0 — не знаем)
func seen_at(nick: String) -> int:
	return int(peer_seen.get(P.nick_key(nick), 0))

## Считается ли человек сейчас в сети
func is_online(nick: String) -> bool:
	var seen := seen_at(nick)
	if seen <= 0:
		return false
	return int(Time.get_unix_time_from_system()) - seen <= P.PRESENCE_ONLINE_SEC

## Про кого спрашивать облако: собеседники, участники групп и открытый чат
func presence_keys() -> Array:
	var keys: Array = []
	for peer in contacts():
		keys.append(P.nick_key(peer))
	for key in group_list():
		for member in group_members(key):
			if not keys.has(P.nick_key(member)):
				keys.append(P.nick_key(member))
	return keys

## ------------------------------------------------------------------ непрочитанные

func bump_unread(peer: String) -> void:
	if current_nick == "":
		return
	if not unread.has(current_nick):
		unread[current_nick] = {}
	var own: Dictionary = unread[current_nick]
	own[peer] = int(own.get(peer, 0)) + 1

func unread_count(peer: String) -> int:
	if not unread.has(current_nick):
		return 0
	var own: Dictionary = unread[current_nick]
	return int(own.get(_peer_key(own, peer), 0))

## Чат открыли — снимаем значок
func mark_read(peer: String) -> void:
	if not unread.has(current_nick):
		return
	var own: Dictionary = unread[current_nick]
	var key := _peer_key(own, peer)
	if own.has(key):
		own.erase(key)
		save_data()

func unread_total() -> int:
	var count := 0
	if unread.has(current_nick):
		for value in (unread[current_nick] as Dictionary).values():
			count += int(value)
	return count

## ------------------------------------------------------------------ сравнение ников

## Один и тот же ник? Регистр букв и пробелы по краям не важны.
func _same_nick(a: String, b: String) -> bool:
	return a.strip_edges() != "" and P.nick_key(a) == P.nick_key(b)

## Найти уже существующий «карман» собеседника, не глядя на регистр букв.
## Так «Админ» и «админ» остаются одним чатом, а не двумя разными.
func _peer_key(owner: Dictionary, peer: String) -> String:
	var wanted := P.nick_key(peer)
	for key in owner.keys():
		if P.nick_key(String(key)) == wanted:
			return String(key)
	return peer.strip_edges()

## Сырой список сообщений из «кармана» владельца (без обращения к current_nick)
func _messages_of(owner_nick: String, peer: String) -> Array:
	if owner_nick == "" or not chats.has(owner_nick):
		return []
	var own: Dictionary = chats[owner_nick]
	var key := _peer_key(own, peer)
	return own.get(key, []) if own.has(key) else []

## Когда в этом чате было последнее сообщение (0 — сообщений нет)
func _last_ts(key: String) -> int:
	var list := messages(key)
	if list.is_empty():
		return 0
	return int((list[list.size() - 1] as Dictionary).get("ts", 0))

## Есть ли такой ник в списке (регистр букв не важен)
func _has_nick(list: Array, nick: String) -> bool:
	for item in list:
		if _same_nick(String(item), nick):
			return true
	return false

## Убрать повторы одного и того же ника (регистр букв не важен)
func _unique_nicks(list: Array) -> Array:
	var out: Array = []
	for item in list:
		var nick := String(item).strip_edges()
		if nick != "" and not _has_nick(out, nick):
			out.append(nick)
	return out

## Вставить сообщение по времени: старые сверху. Так даже при разнице часов
## на устройствах переписка не перепутывается.
func _insert_sorted(list: Array, message: Dictionary) -> void:
	var stamp := int(message.get("ts", 0))
	var at := list.size()
	for i in list.size():
		if int((list[i] as Dictionary).get("ts", 0)) > stamp:
			at = i
			break
	list.insert(at, message)

## ------------------------------------------------------------------ чистка

## Привести данные к одному виду: один аккаунт на ник, один чат на собеседника,
## один карман непрочитанных. «Клоны» (тот же ник в другом регистре, дубли от
## старых версий) склеиваются — переписка при этом не теряется, а складывается
## и выставляется по времени. Вызывается при загрузке файла данных.
func _normalize_data() -> void:
	accounts = _merge_accounts(accounts)
	var canon: Dictionary = {}  # ключ ника -> лучшее написание
	for acc in accounts:
		canon[P.nick_key(String(acc.get("nick", "")))] = String(acc.get("nick", "")).strip_edges()
	# Владельцы чатов и групп: любое написание ника сводим к одному
	for map in [chats, groups, unread]:
		for owner in map.keys():
			var key := P.nick_key(String(owner))
			if key != "" and not canon.has(key):
				canon[key] = String(owner).strip_edges()
	chats = _merge_owner_map(chats, canon, "messages")
	unread = _merge_owner_map(unread, canon, "numbers")
	groups = _merge_owner_map(groups, canon, "dicts")
	# У группы создатель должен быть среди участников — иначе его ответы
	# до остальных не дойдут (старые группы собирались без него)
	for owner in groups.keys():
		var own: Dictionary = groups[owner]
		for key in own.keys():
			_ensure_owner_member(own[key])

## Склеить аккаунты с одинаковым ником. Оставляем лучший: с паролем и пропуском
func _merge_accounts(list: Array) -> Array:
	var out: Array = []
	var index: Dictionary = {}
	for acc in list:
		if typeof(acc) != TYPE_DICTIONARY:
			continue
		var nick := String(acc.get("nick", "")).strip_edges()
		var key := P.nick_key(nick)
		if key == "":
			continue
		if not index.has(key):
			index[key] = out.size()
			out.append(acc)
			continue
		var keep: Dictionary = out[index[key]]
		if String(keep.get("pass_hash", "")) == "" and String(acc.get("pass_hash", "")) != "":
			keep["pass_hash"] = acc["pass_hash"]
		if keep.get("auth", null) == null and acc.get("auth", null) != null:
			keep["auth"] = acc["auth"]
	return out

## Склеить словарь «владелец → собеседник → …». Владельца берём по ключу ника,
## а все написания одного собеседника сливаем в один карман: сообщения — в один
## список по времени, числа непрочитанных — суммой, словари групп — полем за
## полем. Оставляется только одно, «лучшее» написание — иначе при сохранении
## один и тот же список уехал бы в файл под двумя ключами и размножался.
func _merge_owner_map(source: Dictionary, canon: Dictionary, kind: String) -> Dictionary:
	# Шаг 1: складываем записи в общие карманы «владелец → ключ ника собеседника»
	var buckets: Dictionary = {}    # владелец -> { ключ ника -> [ { "peer", "value" } ] }
	var owner_order: Array = []     # порядок владельцев, как встретились
	var peer_order: Dictionary = {} # владелец -> [ ключ ника собеседника ]
	for owner in source.keys():
		var raw: Variant = source[owner]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var owner_key := P.nick_key(String(owner))
		var owner_name := String(canon.get(owner_key, String(owner).strip_edges()))
		if not buckets.has(owner_name):
			buckets[owner_name] = {}
			peer_order[owner_name] = []
			owner_order.append(owner_name)
		var mine: Dictionary = buckets[owner_name]
		for peer in (raw as Dictionary).keys():
			var clean := String(peer).strip_edges()
			var wanted := P.nick_key(clean)
			if wanted == "":
				continue
			if not mine.has(wanted):
				mine[wanted] = []
				(peer_order[owner_name] as Array).append(wanted)
			# Копию кладём: склеенный список не должен оставаться тем же
			# объектом, что и прежние списки-дубликаты.
			var stored: Variant = (raw as Dictionary)[peer]
			var piece: Variant = stored
			if typeof(stored) == TYPE_ARRAY or typeof(stored) == TYPE_DICTIONARY:
				piece = stored.duplicate()
			(mine[wanted] as Array).append({ "peer": clean, "value": piece })
	# Шаг 2: содержимое каждого кармана сводим в одно
	var out: Dictionary = {}
	for owner_name in owner_order:
		var target: Dictionary = {}
		out[owner_name] = target
		var keys: Array = peer_order[owner_name]
		var merged: Dictionary = {}  # ключ ника -> { "peer", "value" }
		for wanted in keys:
			var entries: Array = (buckets[owner_name] as Dictionary)[wanted]
			var value: Variant = _merge_slot(entries, kind)
			if kind == "dicts":
				_ensure_owner_member(value)
			merged[wanted] = { "peer": _slot_name(entries, kind), "value": value }
		for wanted in keys:
			var item: Dictionary = merged[wanted]
			target[String(item["peer"])] = item["value"]
	return out

## Содержимое одного склеенного кармана
func _merge_slot(entries: Array, kind: String) -> Variant:
	if kind == "numbers":
		var sum := 0
		for entry in entries:
			sum += _slot_number((entry as Dictionary)["value"])
		return sum
	if kind == "dicts":
		var merged: Dictionary = {}
		for entry in entries:
			var payload: Variant = (entry as Dictionary)["value"]
			if typeof(payload) != TYPE_DICTIONARY:
				continue
			for field in (payload as Dictionary).keys():
				# Список участников копируем — он у склеенных карманов свой
				var piece: Variant = payload[field]
				merged[field] = piece.duplicate() if typeof(piece) == TYPE_ARRAY else piece
		return merged
	var list: Array = []
	for entry in entries:
		var payload: Variant = (entry as Dictionary)["value"]
		if typeof(payload) != TYPE_ARRAY:
			continue
		for message in (payload as Array):
			if typeof(message) == TYPE_DICTIONARY:
				# Копию словаря берём: сообщение не должно зависеть от того,
				# какой карман склеивали первым.
				list.append((message as Dictionary).duplicate())
	return _sorted_messages(list)

## Какое написание ника оставить у склеенного кармана
func _slot_name(entries: Array, kind: String) -> String:
	# У группы оставляем сам адрес (g:…) — он у всех участников одинаковый
	if kind == "dicts":
		return String((entries[0] as Dictionary)["peer"])
	var best := String((entries[0] as Dictionary)["peer"])
	var best_value := _slot_number((entries[0] as Dictionary)["value"])
	for entry in entries:
		var name := String((entry as Dictionary)["peer"])
		var value := _slot_number((entry as Dictionary)["value"])
		# У переписки берём то написание, где писем больше; у счётчика — короткое
		if (kind == "messages" and value > best_value) \
				or (kind == "numbers" and name.length() < best.length()):
			best = name
			best_value = value
	return best

## Сколько «единиц» в кармане: сообщений или непрочитанных
func _slot_number(value: Variant) -> int:
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).size()
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return 0

## Сообщения по времени: старые сверху. Порядок при равных метках сохраняем.
func _sorted_messages(list: Array) -> Array:
	var indexed: Array = []
	for i in list.size():
		if typeof(list[i]) == TYPE_DICTIONARY:
			indexed.append({ "i": i, "m": list[i] })
	indexed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := int((a["m"] as Dictionary).get("ts", 0))
		var tb := int((b["m"] as Dictionary).get("ts", 0))
		return (ta < tb) if ta != tb else int(a["i"]) < int(b["i"]))
	var out: Array = []
	for item in indexed:
		out.append((item as Dictionary)["m"])
	return out

## Добавить создателя в состав группы, если его там нет
func _ensure_owner_member(info: Dictionary) -> void:
	if typeof(info) != TYPE_DICTIONARY:
		return
	var stored: Variant = info.get("members", [])
	var roster: Array = _unique_nicks(stored) if typeof(stored) == TYPE_ARRAY else []
	var owner_nick := String(info.get("owner", "")).strip_edges()
	if owner_nick != "" and not _has_nick(roster, owner_nick):
		roster = [owner_nick] + roster
	info["members"] = roster

## ------------------------------------------------------------------ настройки

func lang() -> String:
	return String(settings.get("lang", "ru"))

func theme() -> String:
	return String(settings.get("theme", "dark"))

func set_lang(value: String) -> void:
	settings["lang"] = value
	save_data()

func set_theme(value: String) -> void:
	settings["theme"] = value
	save_data()

## ------------------------------------------------------------------ графика

## Уровень сглаживания: 0 — выключено, 1 — обычное, 2 — улучшенное, 3 — максимум.
## Управляет сглаживанием текста и, где видеокарта умеет, сглаживанием фигур (MSAA).
func aa_level() -> int:
	return clampi(int(settings.get("aa", 1)), 0, 3)

func set_aa(level: int) -> void:
	settings["aa"] = clampi(level, 0, 3)
	save_data()

## ------------------------------------------------------------------ звук

func sound_on() -> bool:
	return bool(settings.get("sound", true))

func set_sound(on: bool) -> void:
	settings["sound"] = bool(on)
	save_data()

## Громкость звука: 0.0 … 1.0
func sound_volume() -> float:
	return clampf(float(settings.get("sound_volume", 0.7)), 0.0, 1.0)

func set_sound_volume(value: float) -> void:
	settings["sound_volume"] = clampf(value, 0.0, 1.0)
	save_data()

## ------------------------------------------------------------------ уведомления

func notify_on() -> bool:
	return bool(settings.get("notify", true))

func set_notify(on: bool) -> void:
	settings["notify"] = bool(on)
	save_data()

## Показывать системные уведомления Windows (всплывашка в правом нижнем углу),
## когда окно программы свёрнуто или не в фокусе.
func notify_os() -> bool:
	return bool(settings.get("notify_os", true))

func set_notify_os(on: bool) -> void:
	settings["notify_os"] = bool(on)
	save_data()

## ------------------------------------------------------------------ обновления

## Адрес сайта приложения (откуда узнаём про новые версии)
func site_url() -> String:
	return String(settings.get("site_url", P.SITE_URL))

func set_site_url(url: String) -> void:
	settings["site_url"] = url.strip_edges()
	save_data()

## Последняя версия, которую увидели на сайте (пустая — ещё не проверяли)
func remote_version() -> String:
	return String(settings.get("remote_version", ""))

func set_remote_version(value: String) -> void:
	settings["remote_version"] = value.strip_edges()
	save_data()

## Версия, о которой человеку уже сказали (чтобы не показывать одно и то же дважды)
func last_seen_version() -> String:
	return String(settings.get("update_seen", "")).strip_edges()

func set_last_seen_version(value: String) -> void:
	settings["update_seen"] = value.strip_edges()
	save_data()

## Вышла ли новая версия? Возвращает её номер или пустую строку.
func update_available() -> String:
	var remote := remote_version()
	return remote if remote != "" and P.version_compare(remote, P.APP_VERSION) > 0 else ""

## Куда ведёт кнопка «Обновить»: ссылка из облака, иначе адрес сайта.
func update_url() -> String:
	var url := String(settings.get("update_url", "")).strip_edges()
	return url if url != "" else site_url()

func set_update_url(url: String) -> void:
	settings["update_url"] = url.strip_edges()
	save_data()

## ------------------------------------------------------------------ связь

## Адрес по умолчанию — облако: тогда на любом компьютере всё работает сразу,
## ничего не надо вписывать. Свой сервер (домашняя сеть) ставится вручную в
## «Настройки → Связь» — например, 192.168.1.102:7777.
func relay_host() -> String:
	return String(settings.get("relay_host", P.CLOUD_DEFAULT_URL))

func relay_port() -> int:
	return int(settings.get("relay_port", P.DEFAULT_PORT))

## Публичный ключ облачного проекта (Supabase). Не секрет: его можно показывать.
func relay_key() -> String:
	return String(settings.get("relay_key", P.CLOUD_DEFAULT_KEY))

## Адрес именно облачного проекта: в нём же лежит таблица версий. Если в
## настройках стоит свой сервер в домашней сети, для облачных вопросов всё
## равно берём облако приложения.
func cloud_url() -> String:
	var host := relay_host()
	return host if P.is_cloud(host) else P.CLOUD_DEFAULT_URL

func cloud_key() -> String:
	var host := relay_host()
	return relay_key() if P.is_cloud(host) else P.CLOUD_DEFAULT_KEY

## Галочка «подключаться при входе». По умолчанию включена: иначе входящий на связь
## пользователь просто набирает текст, и сообщение уходит только на своё устройство.
func relay_auto() -> bool:
	return bool(settings.get("relay_auto", true))

func set_relay(host: String, port: int, auto: bool, key: String = "") -> void:
	settings["relay_host"] = host.strip_edges()
	settings["relay_port"] = int(port)
	settings["relay_auto"] = bool(auto)
	settings["relay_key"] = key.strip_edges()
	save_data()

## ------------------------------------------------------------------ файл данных

func save_data() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Не удалось сохранить данные: " + save_path)
		return
	file.store_string(JSON.stringify({
		"accounts": accounts,
		"chats": chats,
		"groups": groups,
		"settings": settings,
		"unread": unread
	}, "\t"))
	file.close()

func load_data() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Файл данных повреждён, начинаем с чистого листа")
		return
	var data: Dictionary = parsed
	accounts = data.get("accounts", [])
	chats = data.get("chats", {})
	settings = data.get("settings", {})
	var loaded_unread: Variant = data.get("unread", {})
	unread = loaded_unread if typeof(loaded_unread) == TYPE_DICTIONARY else {}
	var loaded_groups: Variant = data.get("groups", {})
	groups = loaded_groups if typeof(loaded_groups) == TYPE_DICTIONARY else {}
	# Склеиваем клоны (один ник в разных регистрах, дубли старых версий) и
	# расставляем переписку по времени — сразу, чтобы чистка была заметна.
	_normalize_data()
	save_data()

## ------------------------------------------------------------------ мелочи

func _hash(password: String) -> String:
	return "" if password == "" else password.sha256_text()

## «14:05» из метки времени
func format_time(ts: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(ts)
	return "%02d:%02d" % [int(d.get("hour", 0)), int(d.get("minute", 0))]

## Буква-заглушка для аватара (первая буква ника)
func avatar_letter(nick: String) -> String:
	return nick.substr(0, 1).to_upper() if nick != "" else "?"
