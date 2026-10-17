extends Node
## Сквозная проверка облака «как в жизни»: настоящее приложение (Main + Store)
## и настоящий собеседник — через интернет.
## Запуск: godot --headless --path <папка проекта> res://tests/CloudAppTest.tscn
##
## Идёт в отдельном профиле (TNGRAM_PROFILE=smoke), настоящие данные не трогаются.
## Адрес и ключ берутся из TNGRAM_CLOUD_URL / TNGRAM_CLOUD_KEY, иначе — из значений ниже.

const TnNetScript := preload("res://scripts/net/TnNet.gd")

const FALLBACK_URL := "https://hqmgjnloilemdwejzoyy.supabase.co"
const FALLBACK_KEY := "sb_publishable_eyJSH1Zs1IDEeE61009XDw_cQt5ujXj"

var failures := 0
var passes := 0
var lines: Array[String] = []

var url := ""
var key := ""

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

## Стереть все строки для ника напрямую из облака
func delete_rows_for(nick: String) -> void:
	var headers := PackedStringArray([
		"apikey: " + key,
		"Authorization: Bearer " + key,
		"Content-Type: application/json"
	])
	var request := HTTPRequest.new()
	add_child(request)
	request.request(url + "/rest/v1/messages?to_nick=eq." + nick.uri_encode(),
		headers, HTTPClient.METHOD_DELETE, "")
	await request.request_completed
	request.queue_free()

func _ready() -> void:
	await get_tree().process_frame

	url = OS.get_environment("TNGRAM_CLOUD_URL").strip_edges()
	key = OS.get_environment("TNGRAM_CLOUD_KEY").strip_edges()
	if url == "":
		url = FALLBACK_URL
	if key == "":
		key = FALLBACK_KEY

	# ---------------------------------------------------------- чистый старт в своём профиле
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Store.save_path))
	Store.accounts = []
	Store.chats = {}
	Store.settings = {}
	Store.current_nick = ""
	Store._seed_default_accounts()

	var stamp := str(Time.get_ticks_msec())
	var my_nick := "хозяин_" + stamp
	var peer_nick := "гость_" + stamp
	report("ники этой проверки: " + my_nick + " / " + peer_nick)

	check("свой ник создан", bool(Store.create_account(my_nick, "").get("ok")))
	check("вошли под своим ником", bool(Store.login(my_nick, "").get("ok")), Store.current_nick)

	Store.set_relay(url, 7777, true, key)
	check("приложение настроено на облако",
		Store.relay_host() == url and Store.relay_key() == key and Store.relay_auto(),
		Store.relay_host())

	# ---------------------------------------------------------- второе «устройство»
	var peer_inbox: Array = []
	var peer_client: Node = TnNetScript.new()
	peer_client.name = "Peer"
	peer_client.keep_trying = false
	peer_client.on_message = func(from_nick: String, text: String, ts: int, id: String) -> bool:
		peer_inbox.append({ "from": from_nick, "text": text, "id": id })
		return true
	add_child(peer_client)
	await get_tree().process_frame

	# ---------------------------------------------------------- само приложение
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.name = "App"
	add_child(main)
	await get_tree().process_frame

	peer_client.connect_to(url, 0, peer_nick, key)

	var online := await wait_until(func() -> bool: return Net.is_online() and peer_client.is_online(), 25000)
	check("приложение само вышло в облако", online, Net.status_text() + " / " + peer_client.status_text())
	check("приложение вошло под своим ником", Net.nick == my_nick, Net.nick)

	# ---------------------------------------------------------- 1. Из приложения — собеседнику
	main.send_message(peer_nick, "исходящее в облако")
	var delivered := await wait_until(func() -> bool: return peer_inbox.size() == 1, 12000)
	check("сообщение из приложения дошло через облако",
		delivered and peer_inbox.size() == 1 and String(peer_inbox[0]["text"]) == "исходящее в облако",
		str(peer_inbox))

	# ---------------------------------------------------------- 2. От собеседника — в приложение
	peer_client.send_message(my_nick, "входящее из облака")
	var arrived := await wait_until(func() -> bool:
		var list: Array = Store.messages(peer_nick)
		return list.size() >= 2 and String(list[list.size() - 1].get("text", "")) == "входящее из облака", 12000)
	check("сообщение из облака дошло и сохранилось", arrived, str(Store.messages(peer_nick)))
	check("входящее помечено как чужое",
		Store.messages(peer_nick).size() >= 2 and not bool(Store.messages(peer_nick)[-1].get("mine", true)))

	# ---------------------------------------------------------- 3. Облако очистилось после доставки
	var clean := false
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		Net.last_stats = {}
		Net.ask_stats()
		await wait_until(func() -> bool: return not Net.last_stats.is_empty(), 1000)
		if int(Net.last_stats.get("pending", -1)) == 0:
			clean = true
			break
	check("облако удалило доставленное приложению", clean, str(Net.last_stats))

	# ---------------------------------------------------------- уборка
	Net.stop()
	peer_client.stop()
	Store.delete_history(peer_nick)
	await delete_rows_for(my_nick)
	await delete_rows_for(peer_nick)
	check("после проверки связь выключена", Net.is_off(), Net.status_text())

	# ---------------------------------------------------------- отчёт
	print("---")
	print("проверок пройдено: ", passes, ", ошибок: ", failures)
	var file := FileAccess.open("user://cloud_app_report.txt", FileAccess.WRITE)
	if file != null:
		file.store_string("проверок пройдено: %d, ошибок: %d\n" % [passes, failures])
		file.store_string("\n".join(lines))
		file.close()
		print("отчёт: ", ProjectSettings.globalize_path("user://cloud_app_report.txt"))
	await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)
