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
	if nick.length() < 2:
		return { "ok": false, "error": "err_nick_short" }
	if nick.length() > 24:
		return { "ok": false, "error": "err_nick_long" }
	if account_exists(nick):
		return { "ok": false, "error": "err_nick_used" }
	_add_account_raw(nick, password)
	save_data()
	return { "ok": true, "error": "" }

func _add_account_raw(nick: String, password: String) -> void:
	accounts.append({
		"nick": nick,
		"pass_hash": _hash(password),
		"created": int(Time.get_unix_time_from_system())
	})
	chats[nick] = {}
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
	settings["last_nick"] = current_nick
	save_data()
	emit_signal("data_changed")
	return { "ok": true, "error": "" }

func logout() -> void:
	current_nick = ""
	emit_signal("data_changed")

func current_account() -> Dictionary:
	return find_account(current_nick)

func has_password(nick: String) -> bool:
	var acc := find_account(nick)
	return acc != {} and String(acc.get("pass_hash", "")) != ""

func delete_account(nick: String) -> void:
	var acc := find_account(nick)
	if acc == {}:
		return
	accounts.erase(acc)
	chats.erase(String(acc["nick"]))
	if current_nick == String(acc["nick"]):
		current_nick = ""
	save_data()

## ------------------------------------------------------------------ переписка

func contacts() -> Array:
	var list: Array = []
	for acc in accounts:
		if String(acc["nick"]) != current_nick:
			list.append(String(acc["nick"]))
	# Собеседники, с которыми уже есть переписка: например, сообщение пришло по сети
	# от ника, которого нет среди аккаунтов этого устройства.
	if chats.has(current_nick):
		for peer in chats[current_nick].keys():
			if String(peer) != current_nick and not list.has(String(peer)):
				list.append(String(peer))
	return list

## Сообщения чата с собеседником (пустой список, если чата ещё нет)
func messages(peer: String) -> Array:
	if not chats.has(current_nick):
		return []
	var own: Dictionary = chats[current_nick]
	return own.get(peer, [])

## Последнее сообщение чата — для списка чатов
func last_message(peer: String) -> Dictionary:
	var list := messages(peer)
	return list[-1] if list.size() > 0 else {}

## Сохранить своё сообщение. Пока сервера нет — оно просто живёт на устройстве.
func send_message(peer: String, text: String) -> bool:
	text = text.strip_edges()
	if text == "" or current_nick == "" or peer == "":
		return false
	if not chats.has(current_nick):
		chats[current_nick] = {}
	var own: Dictionary = chats[current_nick]
	if not own.has(peer):
		own[peer] = []
	own[peer].append({
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
		chats[current_nick].erase(peer)
		save_data()
		emit_signal("data_changed")

## Записать сообщение, пришедшее от собеседника (по сети).
## net_id — метка сообщения на сервере: по ней отсеиваем повторную доставку.
func receive_message(from_nick: String, text: String, ts: int = 0, net_id: String = "") -> bool:
	text = text.strip_edges()
	if text == "" or current_nick == "" or from_nick == "":
		return false
	if not chats.has(current_nick):
		chats[current_nick] = {}
	var own: Dictionary = chats[current_nick]
	if not own.has(from_nick):
		own[from_nick] = []
	var list: Array = own[from_nick]
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
	save_data()
	emit_signal("data_changed")
	return true

func unread_total() -> int:
	var count := 0
	for peer in contacts():
		count += messages(peer).size()
	return count

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

## ------------------------------------------------------------------ связь

func relay_host() -> String:
	return String(settings.get("relay_host", P.DEFAULT_HOST))

func relay_port() -> int:
	return int(settings.get("relay_port", P.DEFAULT_PORT))

## Публичный ключ облачного проекта (Supabase). Не секрет: его можно показывать.
func relay_key() -> String:
	return String(settings.get("relay_key", ""))

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
		"settings": settings
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
