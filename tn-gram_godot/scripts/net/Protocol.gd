extends RefCounted
## Общий язык приложения и сервера-передаточника.
## Здесь только имена и константы — чтобы клиент и сервер не разъехались.
##
## Формат: по одному JSON-объекту на строку, поверх обычного TCP.
## Логика обещания: сервер держит сообщение, пока получатель не подтвердит
## получение, и сразу после подтверждения удаляет его у себя.

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 7777

## ---- облако (Supabase) ----
## Тот же обещание, только хранилищем служит таблица в облаке, а о новом
## сообщении приложение узнаёт мгновенно — по потоку изменений (Realtime).
## Так связь работает из любой сети, а не только внутри одной.
const CLOUD_SUFFIX := ".supabase.co"
const CLOUD_TABLE := "messages"
const CLOUD_REALTIME_PATH := "/realtime/v1/websocket"
const CLOUD_VSN := "1.0.0"
const CLOUD_TOPIC := "realtime:public:messages"

## Готовый облачный проект «Тнграм». Если ничего не настраивать, приложение
## подключается сюда — и работает из любой точки интернета, без своего сервера.
## Свой сервер (домашняя сеть) включается в «Настройки → Связь» или через start.bat.
const CLOUD_DEFAULT_URL := "https://hqmgjnloilemdwejzoyy.supabase.co"
const CLOUD_DEFAULT_KEY := "sb_publishable_eyJSH1Zs1IDEeE61009XDw_cQt5ujXj"

## Адрес похож на облачный? (http/https или что-то.supabase.co)
static func is_cloud(url: String) -> bool:
	var u := url.strip_edges().to_lower()
	return u.begins_with("http://") or u.begins_with("https://") or u.contains(CLOUD_SUFFIX)

## «https://проект.supabase.co» → «wss://проект.supabase.co/realtime/v1/websocket?apikey=…»
static func realtime_url(base_url: String, key: String) -> String:
	var u := base_url.strip_edges()
	if u.to_lower().begins_with("https://"):
		u = "wss://" + u.substr(8)
	elif u.to_lower().begins_with("http://"):
		u = "ws://" + u.substr(7)
	u = u.trim_suffix("/")
	return "%s%s?apikey=%s&vsn=%s" % [u, CLOUD_REALTIME_PATH, key, CLOUD_VSN]

## «https://проект.supabase.co» + «messages?select=*» → полный адрес таблицы
static func rest_url(base_url: String, path: String) -> String:
	return base_url.strip_edges().trim_suffix("/") + "/rest/v1/" + path

## ---- приложение → сервер ----
const C_HELLO := "hello"   ## { "t":"hello", "nick":"админ" }
const C_SEND := "send"     ## { "t":"send", "to":"админ2", "text":"привет" }
const C_ACK := "ack"       ## { "t":"ack", "ids":["id1"] } — забрал, можно удалять
const C_STATS := "stats"   ## { "t":"stats" } — сколько на связи и сколько держим

## ---- сервер → приложение ----
const S_WELCOME := "welcome"  ## { "t":"welcome", "nick":"админ", "queued":2 }
const S_MSG := "msg"          ## { "t":"msg", "id":"…", "from":"админ", "to":"админ2", "text":"…", "ts":123 }
const S_SENT := "sent"        ## { "t":"sent", "id":"…", "to":"админ2" } — принял, держу
const S_STATS := "stats"      ## { "t":"stats", "online":1, "pending":2, "per":{…} }
const S_ERROR := "error"      ## { "t":"error", "text":"…" }
