extends Node
## Сервер-передаточник «Тнграм».
##
## Его задача ровно одна: держать сообщение, пока получатель его не заберёт,
## и сразу удалять у себя после подтверждения. Регистрация, пароли и хранение
## переписки — не его дело: переписка остаётся на устройствах.
##
## Запуск:  godot --headless --path . relay/RelayServer.tscn
## Порт:    переменная окружения TNGRAM_PORT (по умолчанию 7777)
##
## Пока сервер живёт в памяти: если его перезапустить, неотданные сообщения
## пропадут. Файловое хранение — следующий шаг (см. README).

const P := preload("res://scripts/net/Protocol.gd")

## Через сколько секунд напоминать получателю про сообщение, если подтверждение
## не пришло. Повторять безопасно: приложение узнаёт сообщение по метке id и
## повторно записывать его не станет.
const RESEND_EVERY := 10.0

var port := P.DEFAULT_PORT
var server := TCPServer.new()
var clients: Array = []         ## [{ "peer": StreamPeerTCP, "buf": String, "nick": String, "dead": bool }]
var pending: Dictionary = {}    ## ник → [ { id, from, to, text, ts, sent } ] — ждём подтверждения
var _next_id := 0
var _resend_in := RESEND_EVERY
var _delivered_total := 0
var _deleted_total := 0

func _ready() -> void:
	var env_port := OS.get_environment("TNGRAM_PORT").strip_edges()
	if env_port != "" and env_port.is_valid_int():
		port = int(env_port)
	if server.listen(port, "0.0.0.0") != OK:
		print("[сервер] ОШИБКА: не удалось занять порт %d (возможно, сервер уже запущен)" % port)
		get_tree().quit(1)
		return
	print("[сервер] слушаю порт %d — держу сообщения, пока получатель не заберёт" % port)
	set_process(true)

func _exit_tree() -> void:
	server.stop()

func _process(_delta: float) -> void:
	while server.is_connection_available():
		var peer := server.take_connection()
		clients.append({ "peer": peer, "buf": "", "nick": "", "dead": false })
		print("[сервер] новый клиент (всего %d)" % clients.size())

	var alive: Array = []
	for client in clients:
		if bool(client.get("dead", false)):
			continue
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			print("[сервер] клиент отключился" + (" (" + String(client["nick"]) + ")" if String(client["nick"]) != "" else ""))
			continue
		var count := peer.get_available_bytes()
		if count > 0:
			var result: Array = peer.get_data(count)
			if int(result[0]) == OK:
				client["buf"] = String(client["buf"]) + (result[1] as PackedByteArray).get_string_from_utf8()
				_drain(client)
		if not bool(client.get("dead", false)):
			alive.append(client)
	clients = alive

	# Напоминаем получателям про то, что им ждёт, — пока не придёт подтверждение
	_resend_in -= _delta
	if _resend_in <= 0.0:
		_resend_in = RESEND_EVERY
		_resend_waiting()

## Напомнить всем, кто на связи, про неотданное
func _resend_waiting() -> void:
	for nick in pending.keys():
		if _client_by_nick(nick).is_empty():
			continue
		for item in _queue_for(nick):
			item["sent"] = false
		_deliver_to(nick)

## ------------------------------------------------------------------ разбор строк

func _drain(client: Dictionary) -> void:
	while not bool(client.get("dead", false)):
		var buffer := String(client["buf"])
		var cut := buffer.find("\n")
		if cut < 0:
			break
		client["buf"] = buffer.substr(cut + 1)
		var line := buffer.substr(0, cut)
		if line.strip_edges() != "":
			_handle(client, line)

func _handle(client: Dictionary, line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parsed
	match String(msg.get("t", "")):
		P.C_HELLO:
			_hello(client, String(msg.get("nick", "")).strip_edges())
		P.C_SEND:
			_send(client, String(msg.get("to", "")).strip_edges(), String(msg.get("text", "")))
		P.C_ACK:
			_ack(client, msg.get("ids", []))
		P.C_STATS:
			_stats(client)

func _hello(client: Dictionary, nick: String) -> void:
	if nick == "":
		_reply(client, { "t": P.S_ERROR, "text": "пустой ник" })
		return
	# Тот же ник уже на связи — старый отключается: один ник = одно устройство
	for other in clients:
		if other["peer"] != client["peer"] and String(other["nick"]) == nick:
			_reply(other, { "t": P.S_ERROR, "text": "этот ник вышел на связь в другом месте" })
			_close(other)
	client["nick"] = nick
	var queue := _queue_for(nick)
	# После переподключения отправляем всё заново: подтверждения от прошлого раза не было
	for item in queue:
		item["sent"] = false
	_reply(client, { "t": P.S_WELCOME, "nick": nick, "queued": queue.size() })
	print("[сервер] %s на связи (сообщений ждёт: %d)" % [nick, queue.size()])
	_deliver_to(nick)

func _send(client: Dictionary, to_nick: String, text: String) -> void:
	var from_nick := String(client["nick"])
	if from_nick == "":
		_reply(client, { "t": P.S_ERROR, "text": "сначала поздоровайся" })
		return
	if to_nick == "" or text.strip_edges() == "":
		_reply(client, { "t": P.S_ERROR, "text": "пустое сообщение" })
		return
	_next_id += 1
	var item := {
		"id": "%s-%d-%d" % [from_nick, int(Time.get_unix_time_from_system()), _next_id],
		"from": from_nick,
		"to": to_nick,
		"text": text,
		"ts": int(Time.get_unix_time_from_system()),
		"sent": false
	}
	if not pending.has(to_nick):
		pending[to_nick] = []
	pending[to_nick].append(item)
	_reply(client, { "t": P.S_SENT, "id": String(item["id"]), "to": to_nick })
	print("[сервер] %s → %s: держу, пока не заберут" % [from_nick, to_nick])
	_deliver_to(to_nick)

## Отдать получателю всё, что для него держим (и что ещё не отправляли)
func _deliver_to(nick: String) -> void:
	var target := _client_by_nick(nick)
	if target.is_empty():
		return
	var sent := 0
	for item in _queue_for(nick):
		if bool(item.get("sent", false)):
			continue
		_reply(target, {
			"t": P.S_MSG,
			"id": String(item["id"]),
			"from": String(item["from"]),
			"to": String(item["to"]),
			"text": String(item["text"]),
			"ts": int(item["ts"])
		})
		item["sent"] = true
		sent += 1
		_delivered_total += 1
	if sent > 0:
		print("[сервер] отдал %s сообщений: %d (ждём подтверждения)" % [nick, sent])

## Подтверждение получения — вот теперь удаляем
func _ack(client: Dictionary, ids: Variant) -> void:
	var nick := String(client["nick"])
	if nick == "" or typeof(ids) != TYPE_ARRAY:
		return
	var kept: Array = []
	var removed := 0
	for item in _queue_for(nick):
		if (ids as Array).has(String(item["id"])):
			removed += 1
		else:
			kept.append(item)
	if removed == 0:
		return
	if kept.is_empty():
		pending.erase(nick)
	else:
		pending[nick] = kept
	_deleted_total += removed
	print("[сервер] %s подтвердил получение — удалил %d (осталось держать: %d)" % [nick, removed, kept.size()])

func _stats(client: Dictionary) -> void:
	var per := {}
	var total := 0
	for nick in pending.keys():
		var count: int = (pending[nick] as Array).size()
		per[nick] = count
		total += count
	_reply(client, {
		"t": P.S_STATS,
		"online": clients.size(),
		"pending": total,
		"per": per,
		"delivered": _delivered_total,
		"deleted": _deleted_total
	})

## ------------------------------------------------------------------ мелочи

func _queue_for(nick: String) -> Array:
	return pending.get(nick, [])

func _client_by_nick(nick: String) -> Dictionary:
	for client in clients:
		if String(client["nick"]) == nick and not bool(client.get("dead", false)):
			return client
	return {}

func _close(client: Dictionary) -> void:
	client["dead"] = true
	var peer: StreamPeerTCP = client["peer"]
	peer.disconnect_from_host()

func _reply(client: Dictionary, data: Dictionary) -> void:
	if bool(client.get("dead", false)):
		return
	var peer: StreamPeerTCP = client["peer"]
	peer.put_data((JSON.stringify(data) + "\n").to_utf8_buffer())
