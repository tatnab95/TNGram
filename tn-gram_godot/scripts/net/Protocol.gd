extends RefCounted
## Общий язык приложения и сервера-передаточника.
## Здесь только имена и константы — чтобы клиент и сервер не разъехались.
##
## Формат: по одному JSON-объекту на строку, поверх обычного TCP.
## Логика обещания: сервер держит сообщение, пока получатель не подтвердит
## получение, и сразу после подтверждения удаляет его у себя.

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 7777

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
