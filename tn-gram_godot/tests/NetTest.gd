extends Node
## Автопроверка связи: сервер-передаточник и два независимых клиента.
## Запуск: godot --headless --path <папка проекта> res://tests/NetTest.tscn
##
## Здесь проверяется главное обещание: сообщение доходит до получателя и
## сразу удаляется с сервера; а то, что доставить не удалось, ждёт получателя.
## Сервер поднимается прямо внутри проверки, на отдельном порту.

const TnNetScript := preload("res://scripts/net/TnNet.gd")

const HOST := "127.0.0.1"
const PORT := 47801

var failures := 0
var passes := 0
var lines: Array[String] = []

var relay: Node
var a: Node
var b: Node
var inbox_a: Array = []   ## что дошло до «админ»
var inbox_b: Array = []   ## что дошло до «админ2»

func report(text: String) -> void:
	lines.append(text)
	print(text)

func check(title: String, condition: bool, extra: String = "") -> void:
	if condition:
		passes += 1
		report("OK   | " + title + (" | " + extra if extra != "" else ""))
	else:
		failures += 1
		report("FAIL | " + title + " | " + extra)

## Ждём, пока условие станет истинным. Отсчёт по реальному времени,
## чтобы проверка не зависела от частоты кадров.
func wait_until(predicate: Callable, ms: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())

## Сколько сервер держит для ника (по свежему ответу на «stats»)
func held_for(client: Node, nick: String, want: int, ms: int = 3000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		client.last_stats = {}
		client.ask_stats()
		await wait_until(func() -> bool: return not client.last_stats.is_empty(), 500)
		var per: Dictionary = client.last_stats.get("per", {})
		if int(per.get(nick, 0)) == want:
			return true
	return false

func total_pending(client: Node) -> int:
	return int(client.last_stats.get("pending", -1))

func _ready() -> void:
	# ---------------------------------------------------------- сервер
	OS.set_environment("TNGRAM_PORT", str(PORT))
	var relay_scene: PackedScene = load("res://relay/RelayServer.tscn")
	check("сцена сервера загружается", relay_scene != null)
	if relay_scene == null:
		finish()
		return
	relay = relay_scene.instantiate()
	check("в сцене сервера есть нужный код", relay != null and relay.get("server") != null,
		"нет скрипта" if relay == null else "")
	if relay == null:
		finish()
		return
	add_child(relay)
	await get_tree().process_frame
	await get_tree().process_frame
	check("сервер запущен на порту " + str(PORT), relay.server.is_listening(), str(relay.server.is_listening()))

	# ---------------------------------------------------------- два «устройства»
	a = TnNetScript.new()
	a.name = "ClientA"
	a.debug = true
	a.on_message = func(from_nick: String, text: String, ts: int, id: String) -> bool:
		inbox_a.append({ "from": from_nick, "text": text, "ts": ts, "id": id })
		return true
	add_child(a)

	b = TnNetScript.new()
	b.name = "ClientB"
	b.debug = true
	b.on_message = func(from_nick: String, text: String, ts: int, id: String) -> bool:
		inbox_b.append({ "from": from_nick, "text": text, "ts": ts, "id": id })
		return true
	add_child(b)
	await get_tree().process_frame

	a.connect_to(HOST, PORT, "админ")
	b.connect_to(HOST, PORT, "админ2")
	var both := await wait_until(func() -> bool: return a.is_online() and b.is_online())
	check("оба клиента вышли на связь", both, a.status_text() + " / " + b.status_text())
	# Готовность = не только соединение, но и ответ сервера с приветствием
	var greeted := await wait_until(func() -> bool:
		return a.status_text() == Loc.tf("net_online", ["админ"]))
	check("клиент понял, что он на связи", greeted, a.status_text())

	# ---------------------------------------------------------- 1. Доставка
	inbox_b.clear()
	a.send_message("админ2", "привет")
	var got := await wait_until(func() -> bool: return inbox_b.size() == 1)
	check("сообщение дошло до получателя", got and inbox_b.size() == 1, str(inbox_b.size()))
	if inbox_b.size() == 1:
		check("текст дошёл верно", String(inbox_b[0]["text"]) == "привет", String(inbox_b[0]["text"]))
		check("отправитель указан верно", String(inbox_b[0]["from"]) == "админ", String(inbox_b[0]["from"]))
		check("у сообщения есть метка", String(inbox_b[0]["id"]) != "", String(inbox_b[0]["id"]))

	# ---------------------------------------------------------- 2. Удаление после доставки
	var emptied := await held_for(a, "админ2", 0)
	a.last_stats = {}
	a.ask_stats()
	await wait_until(func() -> bool: return not a.last_stats.is_empty(), 1000)
	check("после доставки сервер ничего не держит", emptied and total_pending(a) == 0, str(a.last_stats))
	check("сервер посчитал доставленное", int(a.last_stats.get("delivered", 0)) >= 1, str(a.last_stats))
	check("сервер посчитал удалённое", int(a.last_stats.get("deleted", 0)) >= 1, str(a.last_stats))

	# ---------------------------------------------------------- 3. Получатель офлайн
	b.stop()
	await wait_until(func() -> bool: return b.is_off(), 1000)
	inbox_b.clear()
	a.send_message("админ2", "пока")
	var held := await held_for(a, "админ2", 1)
	check("сообщение офлайн-получателю ждёт на сервере", held, str(a.last_stats))
	check("и получателю оно ещё не доставлено", inbox_b.is_empty(), str(inbox_b.size()))

	# ---------------------------------------------------------- 4. Получатель вернулся
	b.connect_to(HOST, PORT, "админ2")
	await wait_until(func() -> bool: return b.is_online())
	var late := await wait_until(func() -> bool: return inbox_b.size() == 1)
	check("дождавшееся сообщение доходит после возвращения", late and inbox_b.size() == 1, str(inbox_b.size()))
	if inbox_b.size() == 1:
		check("текст дождавшегося сообщения верный", String(inbox_b[0]["text"]) == "пока", String(inbox_b[0]["text"]))
	var emptied2 := await held_for(a, "админ2", 0)
	check("после возвращения сервер снова пуст", emptied2, str(a.last_stats))

	# ---------------------------------------------------------- 5. Незнакомый ник
	a.send_message("никого", "ау")
	var waiting := await held_for(a, "никого", 1)
	check("сообщение незнакомому нику ждёт на сервере", waiting, str(a.last_stats))

	# ---------------------------------------------------------- 6. Честные отказы
	check("пустое сообщение не отправляется", not a.send_message("админ2", "   "))

	var c: Node = TnNetScript.new()
	c.keep_trying = false
	add_child(c)
	c.connect_to(HOST, PORT + 1, "один")
	# Свой тайм-аут подключения: сколько ждать «занято/пусто», прежде чем сказать «не удалось»
	var failed := await wait_until(func() -> bool: return c.is_off() and c.status_text() != Loc.t("net_off"),
		int(TnNetScript.CONNECT_TIMEOUT * 1000.0) + 2000)
	check("без сервера клиент честно сообщает об ошибке", failed, c.status_text())
	c.stop()

	# ---------------------------------------------------------- 7. Один ник — одно устройство
	a.keep_trying = false
	var d: Node = TnNetScript.new()
	d.keep_trying = false
	add_child(d)
	d.connect_to(HOST, PORT, "админ")
	var d_online := await wait_until(func() -> bool: return d.is_online(), 3000)
	var a_kicked := await wait_until(func() -> bool: return a.is_off(), 3000)
	check("новый клиент с тем же ником вытесняет старую сессию", d_online and a_kicked,
		d.status_text() + " / " + a.status_text())
	d.stop()

	# ---------------------------------------------------------- уборка
	finish()

## Уборка, отчёт и выход (вызывается и при раннем обрыве проверки)
func finish() -> void:
	if a != null and is_instance_valid(a):
		a.stop()
	if b != null and is_instance_valid(b):
		b.stop()
	if relay != null and is_instance_valid(relay):
		relay.queue_free()
	await get_tree().process_frame

	print("---")
	print("проверок пройдено: ", passes, ", ошибок: ", failures)
	var file := FileAccess.open("user://net_report.txt", FileAccess.WRITE)
	if file != null:
		file.store_string("проверок пройдено: %d, ошибок: %d\n" % [passes, failures])
		file.store_string("\n".join(lines))
		file.close()
		print("отчёт: ", ProjectSettings.globalize_path("user://net_report.txt"))
	await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)
