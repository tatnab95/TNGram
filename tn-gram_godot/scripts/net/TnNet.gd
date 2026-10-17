extends Node
class_name TnNet
## Связь с сервером-передаточником «Тнграм».
##
## Простой протокол: по одному JSON на строку, поверх TCP (см. scripts/net/Protocol.gd).
## Сервер держит сообщение, пока получатель не заберёт, и сразу удаляет.
##
## Это единственное место в приложении, которое знает про сеть. Позже этот слой
## можно направить на облачный сервис или на свой сервер — экраны не изменятся.

signal changed                  ## состояние или статус изменились
signal notice(text: String)     ## отладочные строки (включаются флагом debug)

const P := preload("res://scripts/net/Protocol.gd")

## Сколько ждать ответа от сервера, прежде чем сказать «не удалось».
## Важно: Windows сам по себе может «висеть» на закрытом порту очень долго,
## поэтому свой тайм-аут обязателен — иначе экран подключения замирает.
const CONNECT_TIMEOUT := 3.5

enum State { OFF, CONNECTING, ONLINE }

var state: int = State.OFF
var host := P.DEFAULT_HOST
var port := P.DEFAULT_PORT
var nick := ""
var keep_trying := true         ## пробовать снова, если не получилось
var debug := false              ## писать в notice каждую строку протокола
var last_stats: Dictionary = {} ## последний ответ сервера на «stats» (для проверок)

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

func _ready() -> void:
	set_process(true)

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
func connect_to(p_host: String, p_port: int, p_nick: String) -> void:
	host = p_host if p_host.strip_edges() != "" else P.DEFAULT_HOST
	port = p_port if p_port > 0 else P.DEFAULT_PORT
	nick = p_nick
	_want = true
	_retry_step = 0.5
	_retry_wait = 0.0
	_try_now()

func stop() -> void:
	_want = false
	state = State.OFF
	_buffer = ""
	_peer.disconnect_from_host()
	_set_status("net_off")

## Отправить сообщение через сервер.
## false — связи нет; тогда сообщение остаётся только на устройстве.
func send_message(to_nick: String, text: String) -> bool:
	if state != State.ONLINE or to_nick.strip_edges() == "" or text.strip_edges() == "":
		return false
	_send_line({ "t": P.C_SEND, "to": to_nick, "text": text })
	return true

## Спросить у сервера статистику (нужно проверкам и отладке)
func ask_stats() -> void:
	_send_line({ "t": P.C_STATS })

## ------------------------------------------------------------------ соединение

func _process(delta: float) -> void:
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
