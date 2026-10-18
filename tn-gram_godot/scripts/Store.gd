extends Node
## Хранилище приложения «Тнграм».
## Держит аккаунты, переписку и настройки, сохраняет всё в один файл на устройстве.
## Подключается как автозагрузка (Autoload) с именем Store — см. project.godot.

const P := preload("res://scripts/net/Protocol.gd")

const DEFAULT_SAVE_PATH := "user://tngram_data.json"
## Аккаунты, которые создаются при первом запуске (без пароля)
const DEFAULT_ACCOUNTS := ["админ", "админ2"]

signal data_changed  ## данные изменились — надо перерисовать экраны

var save_path := DEFAULT_SAVE_PATH  ## где лежат данные (см. профиль ниже)
var accounts: Array = []        ## [{ "nick": String, "pass_hash": String, "created": int }]
var chats: Dictionary = {}      ## { "владелец": { "собеседник": [ {"text", "ts", "mine"} ] } }
var settings: Dictionary = {}   ## { "lang": "ru", "theme": "dark", "relay_host": … }
var current_nick := ""          ## кто сейчас вошёл; пустая строка — никто

## Непрочитанные: { "владелец": { "собеседник": сколько } }
var unread: Dictionary = {}
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
	settings["last_nick"] = current_nick
	save_data()
	emit_signal("data_changed")
	return { "ok": true, "error": "" }

func logout() -> void:
	current_nick = ""
	nick_conflict = false
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
	list.append({
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

## Вышла ли новая версия? Возвращает её номер или пустую строку.
func update_available() -> String:
	var remote := remote_version()
	return remote if remote != "" and P.version_compare(remote, P.APP_VERSION) > 0 else ""

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
