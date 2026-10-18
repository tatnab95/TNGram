extends RefCounted
## Общие константы и helpers для client/server.
## Сервер читает JSON-строки по одной, TCP без HTTP.
## Клиент подключается к своему серверу или к облаку Supabase
## по HTTPS (REST) и по WebSocket (Realtime, сообщения).

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 7777

## ---- Облако (Supabase) ----
const CLOUD_SUFFIX := ".supabase.co"
const CLOUD_TABLE := "messages"
const CLOUD_REALTIME_PATH := "/realtime/v1/websocket"
const CLOUD_VSN := "1.0.0"
const CLOUD_TOPIC := "realtime:public:messages"

const CLOUD_DEFAULT_URL := "https://hqmgjnloilemdwejzoyy.supabase.co"
const CLOUD_DEFAULT_KEY := "sb_publishable_eyJSH1Zs1IDEeE61009XDw_cQt5ujXj"

## ---- Аккаунты ----
const PROFILES_TABLE := "profiles"

## ---- Версия и обновления ----
const APP_VERSION := "1.5"

const VERSION_TABLE := "version"
const SITE_URL := "https://tatnab95.github.io/TNGram/"
const UPDATE_FILE := "version.json"

const CHANGELOG := [
	{
		"version": "1.5",
		"date": "18.10.2026",
		"ru": [
			"Телефон: приложению выдано разрешение на интернет. Раньше система его блокировала — из-за этого и была «ошибка связи».",
			"Телефон: экран теперь вертикальный, как в обычных мессенджерах, и всё стало крупнее.",
			"Телефон: корни шифрования лежат внутри приложения — соединение с сервером надёжнее."
		],
		"en": [
			"Phone: the app now has the internet permission. The system was blocking it before — that caused the \"connection error\".",
			"Phone: the screen is now portrait, like in normal messengers, and everything is bigger.",
			"Phone: the encryption roots ship inside the app — the server connection is more reliable."
		]
	},
	{
		"version": "1.4",
		"date": "18.10.2026",
		"ru": [
			"Связь на телефоне починена: телефон теперь находит сервер (корни шифрования встроены в приложение)."
		],
		"en": [
			"Fixed connection on phones: the server is now found (encryption roots are built into the app)."
		]
	},
	{
		"version": "1.3",
		"date": "18.10.2026",
		"ru": [
			"Вход через сервер: пароль проверяется в облаке — аккаунт работает на любом устройстве.",
			"Пинг: в списке чатов и в переписке видно, где живёт сервер и как быстро он отвечает."
		],
		"en": [
			"Server-side login: the password is checked in the cloud — the account works on any device.",
			"Ping: the chat list and the chat show where the server lives and how fast it responds."
		]
	},
	{
		"version": "1.2",
		"date": "18.10.2026",
		"ru": [
			"Настройка «Сглаживание»: качество текста и картинки.",
			"Звук: короткий сигнал на новое сообщение. Можно выключить и настроить громкость.",
			"Уведомления в приложении: всплывающая карточка о новом сообщении — щелчок открывает чат.",
			"Экран «Что нового»: что изменилось в каждой версии.",
			"Приложение проверяет сайт и говорит, если вышла новая версия.",
			"Фон стал мягче: свечение рисуется в большем разрешении."
		],
		"en": [
			"New \"Smoothing\" setting: text and image quality.",
			"Sound: a short chime on a new message. Can be turned off, volume adjustable.",
			"In-app notifications: a pop-up card about a new message — click opens the chat.",
			"A \"What's new\" screen: what changed in each version.",
			"The app checks the site and tells you when a new version is out.",
			"Smoother background: the glow is drawn at a higher resolution."
		]
	},
	{
		"version": "1.1",
		"date": "18.10.2026",
		"ru": [
			"Один ник — один человек: ники бронируются в облаке, занять чужой ник нельзя.",
			"Кнопка «Новый чат»: написать можно любому по нику, а не только тем, кто уже на устройстве.",
			"Значки непрочитанных сообщений — снимаются при открытии чата.",
			"Регистр букв в нике больше не создаёт отдельный чат: «Админ» и «админ» — один человек.",
			"Если твой ник занят кем-то ещё, приложение предупреждает об этом."
		],
		"en": [
			"One nickname — one person: nicknames are reserved in the cloud, you cannot take someone else's.",
			"\"New chat\" button: you can write to anyone by nickname, not only to accounts on this device.",
			"Unread badges — cleared when you open the chat.",
			"Letter case in a nickname no longer creates a second chat: \"Admin\" and \"admin\" are one person.",
			"If your nickname is taken by someone else, the app warns you."
		]
	}
]

static func version_compare(a: String, b: String) -> int:
	var pa := a.strip_edges().split(".")
	var pb := b.strip_edges().split(".")
	for i in maxi(pa.size(), pb.size()):
		var va := int(pa[i]) if i < pa.size() and String(pa[i]).is_valid_int() else 0
		var vb := int(pb[i]) if i < pb.size() and String(pb[i]).is_valid_int() else 0
		if va != vb:
			return 1 if va > vb else -1
	return 0

static func changelog(lang: String) -> Array:
	var list: Array = []
	for entry in CHANGELOG:
		list.append({
			"version": String(entry.get("version", "")),
			"date": String(entry.get("date", "")),
			"items": entry.get(lang, entry.get("ru", []))
		})
	return list

static func nick_key(nick: String) -> String:
	return nick.strip_edges().to_lower()

static func is_cloud(url: String) -> bool:
	var u := url.strip_edges().to_lower()
	return u.begins_with("http://") or u.begins_with("https://") or u.contains(CLOUD_SUFFIX)

static func realtime_url(base_url: String, key: String) -> String:
	var u := base_url.strip_edges()
	if u.to_lower().begins_with("https://"):
		u = "wss://" + u.substr(8)
	elif u.to_lower().begins_with("http://"):
		u = "ws://" + u.substr(7)
	u = u.trim_suffix("/")
	return "%s%s?apikey=%s&vsn=%s" % [u, CLOUD_REALTIME_PATH, key, CLOUD_VSN]

static func rest_url(base_url: String, path: String) -> String:
	return base_url.strip_edges().trim_suffix("/") + "/rest/v1/" + path

static func version_url(base_url: String) -> String:
	return rest_url(base_url, VERSION_TABLE + "?select=*&order=updated_at.desc&limit=1")

static func parse_version_answer(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_ARRAY:
		var rows := parsed as Array
		if rows.is_empty():
			return {}
		return parse_version_answer(JSON.stringify(rows[0]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var row := parsed as Dictionary
	var version := String(row.get("version", "")).strip_edges()
	if version == "":
		return {}
	return {
		"version": version,
		"notes": String(row.get("notes", "")).strip_edges(),
		"url": String(row.get("url", "")).strip_edges()
	}

const AUTH_DOMAIN := "@tngram.local"
const AUTH_MIN_PASSWORD := 6

static func auth_email(nick: String) -> String:
	var key := nick_key(nick)
	if key == "":
		return ""
	var hex := ""
	for byte in key.to_utf8_buffer():
		hex += "%02x" % byte
	return "n" + hex + AUTH_DOMAIN

static func auth_url(base_url: String, path: String) -> String:
	return base_url.strip_edges().trim_suffix("/") + "/auth/v1/" + path

static func parse_session(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var row := parsed as Dictionary
	var token := String(row.get("access_token", "")).strip_edges()
	if token == "":
		return {}
	var user_id := ""
	var user: Variant = row.get("user", null)
	if typeof(user) == TYPE_DICTIONARY:
		user_id = String((user as Dictionary).get("id", "")).strip_edges()
	return {
		"access_token": token,
		"refresh_token": String(row.get("refresh_token", "")).strip_edges(),
		"expires_in": int(row.get("expires_in", 3600)),
		"user_id": user_id
	}

static func parse_auth_error(text: String) -> String:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var row := parsed as Dictionary
	for field in ["error_code", "msg"]:
		var value: Variant = row.get(field, null)
		if typeof(value) == TYPE_STRING and String(value).strip_edges() != "":
			return String(value).strip_edges()
	return ""

const C_HELLO := "hello"
const C_SEND := "send"
const C_ACK := "ack"
const C_STATS := "stats"

const S_WELCOME := "welcome"
const S_MSG := "msg"
const S_SENT := "sent"
const S_STATS := "stats"
const S_ERROR := "error"
