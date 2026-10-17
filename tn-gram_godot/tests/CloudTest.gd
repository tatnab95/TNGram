extends Node
## Автопроверка облачной связи (Supabase) — настоящая, по интернету.
## Запуск: godot --headless --path <папка проекта> res://tests/CloudTest.tscn
##
## Проект и ключ берутся из переменных окружения TNGRAM_CLOUD_URL / TNGRAM_CLOUD_KEY,
## иначе — из значений ниже. Ключ публичный (publishable), его можно показывать.
##
## Проверяется главное обещание: сообщение доходит до получателя, ждёт его,
## если он офлайн, и удаляется из облака после доставки.

const TnNetScript := preload("res://scripts/net/TnNet.gd")

const FALLBACK_URL := "https://hqmgjnloilemdwejzoyy.supabase.co"
const FALLBACK_KEY := "sb_publishable_eyJSH1Zs1IDEeE61009XDw_cQt5ujXj"

var failures := 0
var passes := 0
var lines: Array[String] = []

var url := ""
var key := ""

var a: Node
var b: Node
var inbox_a: Array = []
var inbox_b: Array = []

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

func wait_until(predicate: Callable, ms: int = 8000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())

## Ждём, пока в облаке для ника станет ровно want ждущих сообщений
func wait_pending(nick: String, want: int, ms: int = 8000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if await pending_for(nick) == want:
			return true
		await get_tree().process_frame
	return await pending_for(nick) == want

## Сколько сообщений сейчас ждёт ник в облаке (напрямую, в обход приложения)
func pending_for(nick: String) -> int:
	var headers := PackedStringArray([
		"apikey: " + key,
		"Authorization: Bearer " + key,
		"Content-Type: application/json",
		"Prefer: count=exact",
		"Range: 0-0"
	])
	var request := HTTPRequest.new()
	add_child(request)
	var err := request.request(url + "/rest/v1/messages?select=id&to_nick=eq." + nick.uri_encode(),
		headers, HTTPClient.METHOD_GET, "")
	if err != OK:
		request.queue_free()
		return -1
	var answer: Array = await request.request_completed
	request.queue_free()
	if int(answer[0]) != HTTPRequest.RESULT_SUCCESS:
		return -1
	var total := -1
	for line in answer[2]:
		if String(line).to_lower().begins_with("content-range:"):
			total = int(String(line).split("/")[-1])
	return total

## Убрать за собой: стереть все строки для двух ников
func cleanup(nicks: Array) -> void:
	for nick in nicks:
		var headers := PackedStringArray([
			"apikey: " + key,
			"Authorization: Bearer " + key,
			"Content-Type: application/json"
		])
		var request := HTTPRequest.new()
		add_child(request)
		request.request(url + "/rest/v1/messages?to_nick=eq." + String(nick).uri_encode(),
			headers, HTTPClient.METHOD_DELETE, "")
		await request.request_completed
		request.queue_free()

func _ready() -> void:
	url = OS.get_environment("TNGRAM_CLOUD_URL").strip_edges()
	key = OS.get_environment("TNGRAM_CLOUD_KEY").strip_edges()
	if url == "":
		url = FALLBACK_URL
	if key == "":
		key = FALLBACK_KEY

	check("адрес облака задан", url.begins_with("http"), url)
	check("ключ проекта задан", key != "", "длина " + str(key.length()))

	# Уникальные ники — чтобы не мешать настоящим пользователям
	var stamp := str(Time.get_ticks_msec())
	var nick_a := "проба_а_" + stamp
	var nick_b := "проба_б_" + stamp
	report("ники этой проверки: " + nick_a + " / " + nick_b)

	# ---------------------------------------------------------- два «устройства»
	a = TnNetScript.new()
	a.name = "ClientA"
	a.keep_trying = false
	a.debug = true
	a.on_message = func(from_nick: String, text: String, ts: int, id: String) -> bool:
		inbox_a.append({ "from": from_nick, "text": text, "ts": ts, "id": id })
		return true
	add_child(a)

	b = TnNetScript.new()
	b.name = "ClientB"
	b.keep_trying = false
	b.debug = true
	b.on_message = func(from_nick: String, text: String, ts: int, id: String) -> bool:
		inbox_b.append({ "from": from_nick, "text": text, "ts": ts, "id": id })
		return true
	add_child(b)
	await get_tree().process_frame

	a.notice.connect(func(text: String) -> void: report("A " + text))
	b.notice.connect(func(text: String) -> void: report("B " + text))

	a.connect_to(url, 0, nick_a, key)
	b.connect_to(url, 0, nick_b, key)
	var both := await wait_until(func() -> bool: return a.is_online() and b.is_online(), 20000)
	check("оба клиента вошли в облако", both, a.status_text() + " / " + b.status_text())

	# ---------------------------------------------------------- 1. Доставка
	inbox_b.clear()
	a.send_message(nick_b, "привет из облака")
	var got := await wait_until(func() -> bool: return inbox_b.size() == 1)
	check("сообщение дошло до получателя", got and inbox_b.size() == 1, str(inbox_b.size()))
	if inbox_b.size() == 1:
		check("текст дошёл верно", String(inbox_b[0]["text"]) == "привет из облака", String(inbox_b[0]["text"]))
		check("отправитель указан верно", String(inbox_b[0]["from"]) == nick_a, String(inbox_b[0]["from"]))
		check("у сообщения есть метка", String(inbox_b[0]["id"]) != "", String(inbox_b[0]["id"]))

	# ---------------------------------------------------------- 2. Удаление после доставки
	var emptied := await wait_pending(nick_b, 0)
	var left_after := await pending_for(nick_b)
	check("после доставки в облаке для получателя пусто", emptied and left_after == 0, str(left_after))

	# ---------------------------------------------------------- 3. Получатель офлайн
	b.stop()
	await wait_until(func() -> bool: return b.is_off(), 2000)
	inbox_b.clear()
	a.send_message(nick_b, "пока")
	var held := await wait_pending(nick_b, 1)
	var held_count := await pending_for(nick_b)
	check("сообщение офлайн-получателю ждёт в облаке", held and held_count == 1, str(held_count))
	check("и получателю оно ещё не доставлено", inbox_b.is_empty(), str(inbox_b.size()))

	# ---------------------------------------------------------- 4. Получатель вернулся
	b.connect_to(url, 0, nick_b, key)
	await wait_until(func() -> bool: return b.is_online(), 20000)
	var late := await wait_until(func() -> bool: return inbox_b.size() == 1, 8000)
	check("дождавшееся сообщение доходит после возвращения", late and inbox_b.size() == 1, str(inbox_b.size()))
	if inbox_b.size() == 1:
		check("текст дождавшегося сообщения верный", str(inbox_b[0]["text"]) == "пока", str(inbox_b[0]["text"]))
	var emptied2 := await wait_pending(nick_b, 0)
	var left2 := await pending_for(nick_b)
	check("после возвращения облако снова пусто", emptied2 and left2 == 0, str(left2))

	# ---------------------------------------------------------- 5. Статистика из облака
	var stats_ok := false
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		a.last_stats = {}
		a.ask_stats()
		await wait_until(func() -> bool: return not a.last_stats.is_empty(), 1000)
		if a.last_stats.has("pending"):
			stats_ok = true
			break
	check("приложение умеет спросить статистику у облака", stats_ok, str(a.last_stats))

	# ---------------------------------------------------------- 6. Неверный ключ — честный отказ
	var c: Node = TnNetScript.new()
	c.keep_trying = false
	c.debug = true
	add_child(c)
	c.connect_to(url, 0, "проба_в_" + stamp, "sb_publishable_неверный")
	var refused := await wait_until(func() -> bool:
		return not c.is_online() and not c.is_connecting(), 20000)
	check("с неверным ключом связи нет и сказано почему", refused and not c.is_online(), c.status_text())
	c.stop()

	# ---------------------------------------------------------- уборка
	a.stop()
	b.stop()
	await cleanup([nick_a, nick_b])
	var left := await pending_for(nick_b)
	check("облако очищено после проверки", left == 0, str(left))

	# ---------------------------------------------------------- отчёт
	print("---")
	print("проверок пройдено: ", passes, ", ошибок: ", failures)
	var file := FileAccess.open("user://cloud_report.txt", FileAccess.WRITE)
	if file != null:
		file.store_string("проверок пройдено: %d, ошибок: %d\n" % [passes, failures])
		file.store_string("\n".join(lines))
		file.close()
		print("отчёт: ", ProjectSettings.globalize_path("user://cloud_report.txt"))
	await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)
