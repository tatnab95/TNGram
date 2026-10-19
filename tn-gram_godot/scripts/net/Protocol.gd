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

## ---- Кто сейчас в сети ----
## Одна строка на человека: ник и время последнего «я здесь». По этому времени
## приложение понимает, в сети собеседник или заходил раньше.
const PRESENCE_TABLE := "presence"
## Сколько секунд после последнего «я здесь» человек считается в сети.
const PRESENCE_ONLINE_SEC := 70

## ---- Новости ----
const NEWS_TABLE := "news"

## ---- Группы ----
## Группа живёт без отдельной таблицы: каждому участнику уходит обычное
## сообщение, а внутри него спрятана шапка группы (название и состав).
## Получатель по шапке сам заводит такую же группу у себя.
const GROUP_PREFIX := "g:"
const GROUP_MARK := "\u0001G"
const GROUP_MAX_MEMBERS := 32
const GROUP_TITLE_MAX := 32

## ---- Версия и обновления ----
const APP_VERSION := "1.7"

const VERSION_TABLE := "version"
const SITE_URL := "https://tatnab95.github.io/TNGram/"
const UPDATE_FILE := "version.json"

const CHANGELOG := [
	{
		"version": "1.7",
		"date": "19.10.2026",
		"ru": [
			"Группы починены: больше не появляются копии группы, а ответы участников доходят до создателя.",
			"Клоны аккаунтов и чатов (один ник в разном регистре) склеиваются сами — вся переписка собирается в один чат по времени.",
			"Уведомления Windows снова работают: всплывашка видна, даже когда окно свёрнуто.",
			"Телефон: приложение вибрирует о новом сообщении, когда свёрнуто (разрешение Vibrate выдано).",
			"«Кто в сети» починен для русских ников: раньше облако портило буквы и человек пропадал из списка."
		],
		"en": [
			"Groups are fixed: no more duplicate cards, and replies reach the creator.",
			"Account and chat clones (same nick in different letter case) merge automatically into one timeline.",
			"Windows notifications work again: the popup shows even when the window is minimized.",
			"Phone: the app vibrates on new messages while minimized (Vibrate permission granted).",
			"\"Who is online\" is fixed for non-Latin nicknames: the cloud used to mangle the letters."
		]
	},
	{
		"version": "1.6",
		"date": "18.10.2026",
		"ru": [
			"Группы: можно собрать несколько человек в один чат. Кто написал — видно по имени.",
			"Видно, кто в сети: зелёная точка у аватарки и надпись «в сети» или «был(а) 5 минут назад».",
			"Создать второй аккаунт с чужим ником нельзя: приложение отправляет сразу войти под этим ником.",
			"Прокрутка на телефоне стала плавной, с разгоном пальцем — как в обычных приложениях.",
			"Новая версия теперь видна сразу: полоса вверху списка чатов и кнопка «Обновить».",
			"Раздел «Новости»: объявления от разработчика прямо из сервера.",
			"Аватарки стали цветными — у каждого ника свой цвет. В переписке появились разделители дат.",
			"В списке чатов есть поиск, а в настройках — кнопка «Проверить обновления»."
		],
		"en": [
			"Groups: gather several people into one chat. You can see who wrote by name.",
			"See who is online: a green dot on the avatar and \"online\" or \"last seen 5 minutes ago\".",
			"You cannot create a second account with someone else's nickname: the app asks you to just log in.",
			"Scrolling on the phone is now smooth, with finger momentum, like in normal apps.",
			"A new version is announced right away: a banner in the chat list and a download button.",
			"A \"News\" feed straight from the server.",
			"Colored avatars: every nickname gets its own colour. Date separators in chats.",
			"Search in the chat list; a \"Check for updates\" button in settings."
		]
	},
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

## ---- Кто в сети: адреса и разбор ----

## Одна строка на человека. Пишем себя: ники и время «я здесь».
## Адрес записи о себе. on_conflict обязателен: без него повторная запись того же
## ника не перезаписывает строку, а просто отбрасывается — и «был(а) в сети»
## навсегда замирает на первом заходе.
static func presence_url(base_url: String) -> String:
	return rest_url(base_url, PRESENCE_TABLE + "?on_conflict=nick_key")

## Спросить сразу про нескольких: nick_key=in.(админ,админ2)
static func presence_query_url(base_url: String, keys: Array) -> String:
	var clean: Array = []
	for key in keys:
		var text := String(key).strip_edges()
		if text != "" and not clean.has(text):
			clean.append(text)
	if clean.is_empty():
		return ""
	var list := ""
	for i in clean.size():
		if i > 0:
			list += ","
		# Ключ обязан быть percent-encoded: кириллица в адресе портится на пути
		# и облако отвечает пустым списком — человек пропадал из «кто в сети».
		list += String(clean[i]).uri_encode()
	return rest_url(base_url, PRESENCE_TABLE + "?select=nick_key,nick,last_seen&nick_key=in.(%s)" % list)

## Разобрать ответ про присутствие: { "ключ_ника": время_в_секундах }
static func parse_presence(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		return {}
	var found: Dictionary = {}
	for row in (parsed as Array):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var key := String((row as Dictionary).get("nick_key", "")).strip_edges()
		if key == "":
			continue
		found[key] = _unix_from_text(String((row as Dictionary).get("last_seen", "")))
	return found

## «2026-10-18T12:34:56.789123+00:00» → секунды. Пустая строка → 0.
static func _unix_from_text(text: String) -> int:
	var clean := text.strip_edges().replace("T", " ")
	if clean.length() < 19:
		return 0
	# Оставляем только «2026-10-18 12:34:56» и считаем время как UTC.
	var parts := clean.substr(0, 19).split(" ")
	if parts.size() != 2:
		return 0
	var day := String(parts[0]).split("-")
	var clock := String(parts[1]).split(":")
	if day.size() != 3 or clock.size() != 3:
		return 0
	var stamp := {
		"year": int(day[0]), "month": int(day[1]), "day": int(day[2]),
		"hour": int(clock[0]), "minute": int(clock[1]), "second": int(clock[2])
	}
	return int(Time.get_unix_time_from_datetime_dict(stamp))

## ---- Новости из облака ----

static func news_url(base_url: String, limit: int = 20) -> String:
	return rest_url(base_url, NEWS_TABLE + "?select=*&published=eq.true&order=created_at.desc&limit=%d" % limit)

## Разбор списка новостей. Плохой ответ — пустой список, а не ошибка.
static func parse_news(text: String) -> Array:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		return []
	var list: Array = []
	for row in (parsed as Array):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var item := row as Dictionary
		var title := String(item.get("title", "")).strip_edges()
		var body := String(item.get("body", "")).strip_edges()
		if title == "" and body == "":
			continue
		list.append({
			"title": title,
			"body": body,
			"date": String(item.get("created_at", "")).strip_edges()
		})
	return list

## ---- Группы ----

## Короткое имя группы — оно и есть её адрес у всех участников.
## Одинаковое название у одного и того же создателя даёт одну и ту же группу.
static func group_key(title: String, owner: String) -> String:
	var slug := ""
	for ch in title.strip_edges().to_lower():
		if ch == " " or ch == "-" or ch == "_":
			slug += "_"
		elif (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			slug += ch
		elif (ch >= "а" and ch <= "я") or ch == "ё":
			slug += ch
	if slug == "":
		slug = "grp"
	if slug.length() > 18:
		slug = slug.substr(0, 18)
	return GROUP_PREFIX + slug + "_" + nick_key(owner).replace(" ", "_")

## Это адрес группы, а не ник человека?
static func is_group_key(value: String) -> bool:
	return value.strip_edges().begins_with(GROUP_PREFIX)

## Упаковать сообщение группы: [шапка]текст. Шапка едет вместе с текстом,
## поэтому отдельная таблица группам не нужна.
static func encode_group(key: String, title: String, members: Array, text: String, owner_nick: String = "") -> String:
	var roster: Array = []
	for member in members:
		var nick := String(member).strip_edges()
		if nick != "" and not roster.has(nick):
			roster.append(nick)
	var head := JSON.stringify({ "k": key, "t": title.strip_edges(), "m": roster, "o": owner_nick.strip_edges() })
	return GROUP_MARK + head + GROUP_MARK + text

## Развернуть сообщение группы. Не группа — пустой словарь.
## Возвращает { "key", "title", "members", "owner", "text" }.
static func decode_group(body: String) -> Dictionary:
	if not body.begins_with(GROUP_MARK):
		return {}
	var rest := body.substr(GROUP_MARK.length())
	var cut := rest.find(GROUP_MARK)
	if cut < 0:
		return {}
	var parsed: Variant = JSON.parse_string(rest.substr(0, cut))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var head := parsed as Dictionary
	var key := String(head.get("k", "")).strip_edges()
	if key == "":
		return {}
	var members: Array = []
	var raw: Variant = head.get("m", [])
	if typeof(raw) == TYPE_ARRAY:
		for member in (raw as Array):
			var nick := String(member).strip_edges()
			if nick != "" and not members.has(nick):
				members.append(nick)
	return {
		"key": key,
		"title": String(head.get("t", "")).strip_edges(),
		"members": members,
		"owner": String(head.get("o", "")).strip_edges(),
		"text": rest.substr(cut + GROUP_MARK.length())
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
