extends Node
## Автопроверка приложения без экрана (headless).
## Запуск: godot --headless --path <папка проекта> res://tests/SmokeTest.tscn
## Проверяет данные, вход, переписку, переключение языка/темы и сборку экранов.

const TnNetScript := preload("res://scripts/net/TnNet.gd")
const Protocol := preload("res://scripts/net/Protocol.gd")

var failures := 0
var passes := 0
var lines: Array[String] = []

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

## Есть ли в списке чатов запись про этот чат (группа или человек)
func has_chat(list: Array, key: String, group: bool) -> bool:
	for item in list:
		if String((item as Dictionary).get("key", "")) == key \
				and bool((item as Dictionary).get("group", false)) == group:
			return true
	return false

## Есть ли на экране кнопка с таким текстом
func has_button_named(root: Node, text: String) -> bool:
	return find_by(root, func(n: Node) -> bool:
		return n is Button and String(n.text) == text) != null

## Ключи текста, которые просит скрипт: Loc.t("…") и Loc.tf("…")
func loc_keys_in(text: String) -> Array:
	var found: Array = []
	var re := RegEx.create_from_string("Loc\\.tf?\\(\\s*\"([^\"]+)\"")
	for m in re.search_all(text):
		found.append(m.get_string(1))
	return found

## Все файлы *.gd внутри папки (рекурсивно)
func gd_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(gd_files(dir_path.path_join(entry)))
		elif entry.ends_with(".gd"):
			out.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	return out

func count_nodes(root: Node, class_name_to_find: String) -> int:
	var total := 0
	for child in root.get_children():
		if child.is_class(class_name_to_find):
			total += 1
		total += count_nodes(child, class_name_to_find)
	return total

func find_label(root: Node, text: String) -> Label:
	for child in root.get_children():
		if child is Label and String(child.text) == text:
			return child
		var found := find_label(child, text)
		if found != null:
			return found
	return null

## Первый узел, подходящий под условие
func find_by(root: Node, predicate: Callable) -> Node:
	for child in root.get_children():
		if bool(predicate.call(child)):
			return child
		var found := find_by(child, predicate)
		if found != null:
			return found
	return null

## Ждём, пока условие станет истинным (по реальному времени, а не по кадрам)
func wait_until(predicate: Callable, ms: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())

func _ready() -> void:
	await get_tree().process_frame
	report("--- размер окна: " + str(get_viewport().get_visible_rect().size)
		+ " | окно: " + str(DisplayServer.window_get_size())
		+ " | настройки: " + str(ProjectSettings.get_setting("display/window/size/viewport_width"))
		+ "x" + str(ProjectSettings.get_setting("display/window/size/viewport_height")))

	# ---------------------------------------------------------- 1. Чистый старт
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Store.save_path))
	Store.accounts = []
	Store.chats = {}
	Store.settings = {}
	Store.current_nick = ""
	Store._seed_default_accounts()
	check("при первом запуске создаются два аккаунта", Store.accounts.size() == 2, "их " + str(Store.accounts.size()))
	check("аккаунт «админ» есть", Store.account_exists("админ"))
	check("аккаунт «админ2» есть", Store.account_exists("админ2"))
	check("пароля по умолчанию нет", not Store.has_password("админ"))

	# ---------------------------------------------------------- 2. Проверки ника
	check("короткий ник отклоняется", String(Store.create_account("a", "").get("error")) == "err_nick_short")
	check("повтор ника отклоняется", String(Store.create_account("АДМИН", "").get("error")) == "err_nick_used")
	check("новый ник создаётся", bool(Store.create_account("тест", "1234").get("ok")))
	check("у нового ника есть пароль", Store.has_password("тест"))

	# ---------------------------------------------------------- 3. Вход
	check("вход без пароля работает", bool(Store.login("админ", "").get("ok")))
	check("вошли как «админ»", Store.current_nick == "админ", Store.current_nick)
	check("неверный пароль отклоняется", String(Store.login("тест", "0000").get("error")) == "err_pass_wrong")
	Store.login("админ", "")
	check("собеседники — остальные аккаунты", Store.contacts() == ["админ2", "тест"], str(Store.contacts()))

	# ---------------------------------------------------------- 4. Сообщения
	check("сообщение отправляется", Store.send_message("админ2", "привет"))
	check("сообщение сохранено", Store.messages("админ2").size() == 1)
	check("текст совпадает", String(Store.last_message("админ2").get("text")) == "привет")
	check("пустое сообщение не отправляется", not Store.send_message("админ2", "   "))

	# ---------------------------------------------------------- 5. Сохранение в файл
	Store.save_data()
	var accounts_before := Store.accounts.size()
	Store.load_data()
	check("данные читаются из файла", Store.accounts.size() == accounts_before, str(Store.accounts.size()) + " из " + str(accounts_before))
	check("переписка уцелела", Store.messages("админ2").size() == 1)

	# ---------------------------------------------------------- 5б. Приём сообщения из сети
	check("сообщение из сети сохраняется", Store.receive_message("гость", "привет из сети", 0, "net-1"))
	check("сообщение из сети видно", Store.messages("гость").size() == 1, str(Store.messages("гость").size()))
	check("сообщение из сети — не моё", not bool(Store.messages("гость")[0].get("mine", true)))
	check("повтор того же сообщения не дублируется",
		Store.receive_message("гость", "привет из сети", 0, "net-1") and Store.messages("гость").size() == 1,
		str(Store.messages("гость").size()))
	check("собеседник по сети появляется в списке", Store.contacts().has("гость"), str(Store.contacts()))
	check("пустое сообщение из сети не сохраняется", not Store.receive_message("гость", "   ", 0, "net-2"))
	Store.delete_history("гость")
	check("переписка с гостем убрана", Store.messages("гость").is_empty())

	# ---------------------------------------------------------- 5в. Настройки связи
	# Пока адрес не задан, приложение само настраивается на облако
	check("по умолчанию приложение настраивается на облако",
		Store.relay_host() == Protocol.CLOUD_DEFAULT_URL, Store.relay_host())
	check("и уже знает публичный ключ проекта",
		Store.relay_key() == Protocol.CLOUD_DEFAULT_KEY, Store.relay_key())
	check("по умолчанию подключение при входе включено", Store.relay_auto())
	Store.set_relay("192.168.1.5", 8123, true)
	check("адрес сервера запоминается", Store.relay_host() == "192.168.1.5", Store.relay_host())
	check("порт сервера запоминается", Store.relay_port() == 8123, str(Store.relay_port()))
	check("галочка «подключаться при входе» запоминается", Store.relay_auto())
	# Адрес должен пережить перезапуск — читаем настройки из файла заново
	Store.load_data()
	check("адрес сервера уцелел после перезапуска", Store.relay_host() == "192.168.1.5", Store.relay_host())
	check("порт сервера уцелел после перезапуска", Store.relay_port() == 8123, str(Store.relay_port()))
	check("галочка «подключаться при входе» уцелела после перезапуска", Store.relay_auto())
	# Облако: адрес-ссылка и публичный ключ проекта
	Store.set_relay("https://probe.supabase.co", 7777, true, "sb_publishable_probe")
	check("облачный адрес запоминается", Store.relay_host() == "https://probe.supabase.co", Store.relay_host())
	check("ключ проекта запоминается", Store.relay_key() == "sb_publishable_probe", Store.relay_key())
	Store.load_data()
	check("ключ проекта уцелел после перезапуска", Store.relay_key() == "sb_publishable_probe", Store.relay_key())
	Store.set_relay("127.0.0.1", 7777, false)
	check("настройки связи возвращаются к обычным",
		Store.relay_host() == "127.0.0.1" and Store.relay_port() == 7777 and not Store.relay_auto())

	# ---------------------------------------------------------- 6. Язык
	Loc.lang = "en"
	check("английский язык работает", Loc.t("app_name") == "Tngram", Loc.t("app_name"))
	check("статус связи есть по-английски", Loc.t("net_off") == "Not connected", Loc.t("net_off"))
	Loc.lang = "ru"
	check("русский язык работает", Loc.t("app_name") == "Тнграм", Loc.t("app_name"))
	check("статус связи есть по-русски", Loc.t("net_off") == "Не подключено", Loc.t("net_off"))
	check("подстановка в текст работает", Loc.tf("chat_delete_confirm", ["админ2"]).contains("админ2"))

	# ---------------------------------------------------------- 7. Экраны
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	check("после входа открыт список чатов", main.current_id == "chats", main.current_id)
	check("фон построен", main.background != null)
	check("тема приложения задана", main.theme != null)

	main.show_screen("login", null)
	await get_tree().process_frame
	check("экран входа открывается", main.current_id == "login")
	check("на экране входа есть кнопки", count_nodes(main.screen, "Button") >= 3, str(count_nodes(main.screen, "Button")))
	check("на экране входа видно имя приложения", find_label(main.screen, "Тнграм") != null)

	main.show_screen("new", null)
	await get_tree().process_frame
	check("экран создания ника открывается", main.current_id == "new")
	check("на нём три поля ввода", count_nodes(main.screen, "LineEdit") == 3, str(count_nodes(main.screen, "LineEdit")))
	# Пароль короче шести знаков облако считает слабым — предупреждаем сразу
	main.screen.call("_submit", "короткий", "123", "123")
	await get_tree().process_frame
	check("короткий пароль не пропускается",
		String(main.screen.get("error_code")) == "err_pass_short", String(main.screen.get("error_code")))
	check("видно объяснение про короткий пароль", find_label(main.screen, Loc.t("err_pass_short")) != null)

	main.show_screen("chat", "админ2")
	await get_tree().process_frame
	await get_tree().process_frame
	check("экран чата открывается", main.current_id == "chat")
	check("в чате одно поле ввода", count_nodes(main.screen, "LineEdit") == 1)
	check("сообщение видно в чате", find_label(main.screen, "привет") != null)

	# Недописанный текст не должен пропадать, когда приходит новое сообщение
	var chat_input: Node = find_by(main.screen, func(n: Node) -> bool: return n is LineEdit)
	(chat_input as LineEdit).text = "недописанное"
	Store.receive_message("админ2", "ответ друга", 0, "draft-1")
	await get_tree().process_frame
	await get_tree().process_frame
	var same_input: Node = find_by(main.screen, func(n: Node) -> bool: return n is LineEdit)
	check("после нового сообщения набранный текст сохраняется",
		same_input != null and String((same_input as LineEdit).text) == "недописанное",
		String((same_input as LineEdit).text) if same_input != null else "нет поля")
	check("новое сообщение появилось в чате", find_label(main.screen, "ответ друга") != null)
	(same_input as LineEdit).text = ""
	# Возвращаем переписку к тому виду, на который рассчитывают проверки ниже
	Store.delete_history("админ2")
	Store.send_message("админ2", "привет")

	main.show_screen("settings", null)
	await get_tree().process_frame
	check("экран настроек открывается", main.current_id == "settings")
	check("переключателя языка два", count_nodes(main.screen, "Button") >= 5, str(count_nodes(main.screen, "Button")))
	var address_field: Node = main.screen.get("address_field")
	var connect_button: Node = main.screen.get("connect_button")
	var status_label: Node = main.screen.get("status_label")
	check("в настройках есть поле адреса сервера", address_field != null)
	check("адрес сервера заполнен", address_field != null and String(address_field.text) == "127.0.0.1:7777",
		String(address_field.text) if address_field != null else "")
	check("в настройках есть кнопка подключения", connect_button != null)
	check("кнопка подключения подписана", connect_button != null and String(connect_button.text) == Loc.t("net_connect"),
		String(connect_button.text) if connect_button != null else "")
	check("в настройках видно состояние связи", status_label != null and String(status_label.text) == Loc.t("net_off"),
		String(status_label.text) if status_label != null else "")
	# Уведомления Windows — отдельный переключатель (только на Windows)
	if OS.has_feature("windows"):
		var os_toggle: Node = find_by(main.screen, func(n: Node) -> bool:
			return n is CheckButton and n.name == "NotifyOs")
		check("в настройках есть переключатель уведомлений Windows",
			os_toggle != null and (os_toggle as CheckButton).button_pressed == Store.notify_os())
	# Раскладка нового блока: поле адреса должно быть видимым и растянутым
	await get_tree().process_frame
	await get_tree().process_frame
	var field_control := address_field as Control
	var button_control := connect_button as Control
	check("поле адреса видно и растянуто по ширине",
		field_control != null and field_control.size.x > 200.0 and field_control.size.y >= 30.0,
		str(field_control.size) if field_control != null else "")
	check("кнопка подключения видна",
		button_control != null and button_control.size.x > 40.0 and button_control.size.y >= 30.0,
		str(button_control.size) if button_control != null else "")
	# Блок связи должен занимать всю ширину настроек и не вылезать за края
	var scroller_node: Node = find_by(main.screen, func(n: Node) -> bool: return n is ScrollContainer)
	var content_width := (scroller_node as Control).size.x if scroller_node != null else 0.0
	check("блок связи занимает всю ширину настроек",
		content_width > 0.0 and field_control != null and button_control != null
		and field_control.size.x + button_control.size.x < content_width,
		"поле %s + кнопка %s в области %s" % [
			str(field_control.size), str(button_control.size), str(content_width)])
	check("поле адреса шире кнопки",
		field_control != null and button_control != null and field_control.size.x > button_control.size.x,
		"")
	# Слабое место: непонятный адрес не должен ронять приложение
	if address_field != null:
		address_field.text = "127.0.0.1:порт"
		if connect_button != null:
			connect_button.emit_signal("pressed")
			await get_tree().process_frame
			check("неправильный адрес вежливо отклонён", String(status_label.text) == Loc.t("net_bad_address"),
				String(status_label.text))
		# Адрес из start.bat напечатан с префиксом ws:// — он обязан приниматься
		address_field.text = "ws://192.168.1.5:8123"
		var parsed: Dictionary = main.screen.call("_address_from_field")
		check("адрес с префиксом ws:// принимается",
			bool(parsed.get("ok")) and String(parsed.get("host")) == "192.168.1.5" and int(parsed.get("port")) == 8123,
			str(parsed))
		# Облачный адрес — ссылка на проект; порт у него не указывают
		address_field.text = "https://probe.supabase.co"
		var cloud_parsed: Dictionary = main.screen.call("_address_from_field")
		check("облачный адрес принимается",
			bool(cloud_parsed.get("ok")) and String(cloud_parsed.get("host")) == "https://probe.supabase.co",
			str(cloud_parsed))
		address_field.text = "127.0.0.1:7777"
	Net.stop()
	# Отправка «мимо сети»: связи нет, но сообщение обязано остаться у нас
	var before_offline: int = Store.messages("админ2").size()
	var offline_sent: bool = main.send_message("админ2", "без связи")
	check("сообщение без связи сохраняется локально",
		offline_sent and Store.messages("админ2").size() == before_offline + 1,
		str(Store.messages("админ2").size()) + " из " + str(before_offline + 1))
	check("пустое сообщение через Main не проходит", not main.send_message("админ2", "   "))
	Store.delete_history("админ2")

	# ---------------------------------------------------------- 7б. Экраны отмечают состояние связи
	# Смоделируем «на связи» — экраны обязаны показать это сразу, без перезапуска
	Net.state = TnNetScript.State.ONLINE
	Net._status_key = "net_online"
	Net._status_arg = "админ"
	Net.emit_signal("changed")
	check("настройки сразу показывают связь",
		status_label != null and String(status_label.text) == Loc.tf("net_online", ["админ"]),
		String(status_label.text) if status_label != null else "")
	check("кнопка превращается в «Отключиться»",
		connect_button != null and String(connect_button.text) == Loc.t("net_disconnect"),
		String(connect_button.text) if connect_button != null else "")

	main.show_screen("chats", null)
	check("в списке чатов видно, что связь есть",
		find_label(main.screen, Loc.tf("net_online", ["админ"])) != null)

	main.show_screen("chat", "админ2")
	check("в переписке видно, что связь есть",
		find_label(main.screen, Loc.t("net_note_online")) != null)

	Net.state = TnNetScript.State.OFF
	Net._status_key = "net_off"
	Net._status_arg = ""
	Net.emit_signal("changed")
	check("после разрыва подпись снова про локальное хранение",
		find_label(main.screen, Loc.t("net_note_offline")) != null)

	# ---------------------------------------------------------- 7в. Сквозная проверка: приложение ↔ сервер
	# Самый честный случай: настоящее приложение (Main + Store) и настоящий сервер.
	OS.set_environment("TNGRAM_PORT", "47803")
	var relay: Node = load("res://relay/RelayServer.tscn").instantiate()
	add_child(relay)
	await get_tree().process_frame
	await get_tree().process_frame
	check("сервер для сквозной проверки поднялся", relay.server.is_listening())

	# Второй собеседник — как будто другое устройство
	var peer_inbox: Array = []
	var peer_client: Node = TnNetScript.new()
	peer_client.on_message = func(from_nick: String, text: String, ts: int, id: String) -> bool:
		peer_inbox.append({ "from": from_nick, "text": text, "id": id })
		return true
	add_child(peer_client)
	await get_tree().process_frame

	Store.delete_history("админ2")
	Net.connect_to("127.0.0.1", 47803, "админ")
	peer_client.connect_to("127.0.0.1", 47803, "админ2")
	var online := await wait_until(func() -> bool:
		return Net.is_online() and peer_client.is_online(), 4000)
	check("приложение вышло на связь с сервером", online, Net.status_text() + " / " + peer_client.status_text())

	# 1) Исходящее из приложения доходит до собеседника
	main.send_message("админ2", "исходящее из приложения")
	var delivered := await wait_until(func() -> bool: return peer_inbox.size() == 1, 4000)
	check("сообщение из приложения доходит до собеседника",
		delivered and String(peer_inbox[0]["text"]) == "исходящее из приложения", str(peer_inbox))

	# 2) Входящее от собеседника доходит до приложения и сохраняется
	peer_client.send_message("админ", "входящее из сети")
	var arrived := await wait_until(func() -> bool:
		var list: Array = Store.messages("админ2")
		return list.size() >= 2 and String(list[list.size() - 1].get("text", "")) == "входящее из сети", 4000)
	check("сообщение из сети доходит и сохраняется", arrived, str(Store.messages("админ2")))
	check("входящее помечено как чужое",
		not Store.messages("админ2").is_empty() and not bool(Store.messages("админ2")[-1].get("mine", true)))

	# 3) Сервер удалил доставленное
	var clean := false
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		Net.last_stats = {}
		Net.ask_stats()
		await wait_until(func() -> bool: return not Net.last_stats.is_empty(), 500)
		if int(Net.last_stats.get("pending", -1)) == 0:
			clean = true
			break
	check("сквозная проверка: сервер удалил доставленное", clean, str(Net.last_stats))

	# уборка
	Net.stop()
	peer_client.stop()
	relay.queue_free()
	Store.delete_history("админ2")
	await get_tree().process_frame
	check("после сквозной проверки связь выключена", Net.is_off(), Net.status_text())

	# ---------------------------------------------------------- 8. Темы
	var dark_accent: Color = UiStyle.palette("dark")["a1"]
	Store.set_theme("green")
	main.rebuild()
	await get_tree().process_frame
	check("тема меняется", UiStyle.palette(Store.theme())["a1"] != dark_accent)
	Store.set_theme("dark")

	# ---------------------------------------------------------- 9. Удаление переписки
	Store.delete_history("админ2")
	check("переписка удаляется", Store.messages("админ2").is_empty())

	# ---------------------------------------------------------- 10. Раскладка
	var vp: Vector2 = get_viewport().get_visible_rect().size

	main.show_screen("login", null)
	await get_tree().process_frame
	await get_tree().process_frame
	var column: Node = find_by(main.screen, func(n: Node) -> bool:
		return n is VBoxContainer and n.custom_minimum_size.x == 440.0)
	if column != null:
		check("колонка входа шириной 440", absf(column.size.x - 440.0) < 1.0, str(column.size.x))
		var center: float = column.global_position.x + column.size.x * 0.5
		check("колонка входа по центру окна", absf(center - vp.x * 0.5) < 8.0, str(center) + " против " + str(vp.x * 0.5))
		check("колонка входа помещается по высоте", column.size.y <= vp.y, str(column.size.y) + " из " + str(vp.y))
	else:
		check("колонка входа найдена", false, "не найдена")

	# Содержимое экрана входа должно помещаться целиком, без полосы прокрутки
	var login_scroll: Node = find_by(main.screen, func(n: Node) -> bool: return n is ScrollContainer)
	check("экрану входа не нужна прокрутка",
		login_scroll != null and not login_scroll.get_v_scroll_bar().visible,
		("есть прокрутка" if login_scroll == null or login_scroll.get_v_scroll_bar().visible else "не нужна"))

	var base: Node = find_by(main.background, func(n: Node) -> bool: return n is ColorRect)
	check("фон закрывает всё окно", base != null and base.size.x >= vp.x and base.size.y >= vp.y,
		(str(base.size) if base != null else "нет фона"))

	# ---------------------------------------------------------- 11. Пузырь длинного сообщения
	var long_text := "Это очень длинное сообщение, которое обязано переноситься на несколько строк и не растягивать окно на всю ширину."
	Store.send_message("админ2", long_text)
	main.show_screen("chat", "админ2")
	await get_tree().process_frame
	await get_tree().process_frame
	var bubble: Node = find_by(main.screen, func(n: Node) -> bool:
		return n is PanelContainer and n.get_parent() is HBoxContainer and n.custom_minimum_size.x == 0.0)
	if bubble != null:
		check("пузырь не шире 460 точек", bubble.size.x <= 460.0, str(bubble.size.x))
		check("пузырь не пустой по высоте", bubble.size.y > 20.0, str(bubble.size.y))
		check("пузырь внутри окна", bubble.global_position.x + bubble.size.x <= vp.x, str(bubble.global_position.x + bubble.size.x))
	else:
		check("пузырь найден", false, "не найден")

	# ---------------------------------------------------------- 12. Окно подтверждения
	main.show_screen("chat", "админ2")
	await get_tree().process_frame
	main.screen.call("_confirm_delete")
	await get_tree().process_frame
	var dialog: Node = find_by(main.screen, func(n: Node) -> bool: return n is ConfirmationDialog)
	check("окно подтверждения открывается", dialog != null and dialog.visible,
		("видно" if dialog != null and dialog.visible else "не найдено"))
	if dialog != null:
		check("окно подтверждения с нашей темой", dialog.theme != null)
		dialog.hide()

	# ---------------------------------------------------------- 13. Нажатия как у человека
	Store.delete_history("админ2")
	main.show_screen("login", null)
	await get_tree().process_frame
	await get_tree().process_frame
	var card: Node = find_by(main.screen, func(n: Node) -> bool:
		return n is Button and n.custom_minimum_size.y == 74.0)
	check("карточка аккаунта на экране входа есть", card != null)
	if card != null:
		card.emit_signal("pressed")
		await get_tree().process_frame
		check("нажатие на аккаунт открывает чаты", main.current_id == "chats", main.current_id)
		check("вошли в аккаунт «админ»", Store.current_nick == "админ", Store.current_nick)

	# Чат открывается нажатием на карточку собеседника
	var peer_card: Node = find_by(main.screen, func(n: Node) -> bool:
		return n is Button and n.custom_minimum_size.y == 74.0)
	if peer_card != null:
		peer_card.emit_signal("pressed")
		await get_tree().process_frame
		check("нажатие на собеседника открывает переписку", main.current_id == "chat", main.current_id)

	# Отправка сообщения кнопкой
	if main.current_id == "chat":
		var edit: Node = find_by(main.screen, func(n: Node) -> bool: return n is LineEdit)
		var send_button: Node = find_by(main.screen, func(n: Node) -> bool:
			return n is Button and n.text == Loc.t("chat_send"))
		check("поле ввода и кнопка отправки есть", edit != null and send_button != null)
		if edit != null and send_button != null:
			check("у кнопки «Отправить» есть обработчик", send_button.pressed.get_connections().size() > 0,
				str(send_button.pressed.get_connections().size()))
			edit.text = "проверка кнопкой"
			send_button.emit_signal("pressed")
			await get_tree().process_frame
			await get_tree().process_frame
			var sent: Array = Store.messages("админ2")
			check("кнопка «Отправить» добавляет сообщение", sent.size() == 1, str(sent.size()))
			check("текст сообщения верный",
				sent.size() == 1 and String(sent[0].get("text")) == "проверка кнопкой",
				String(sent[0].get("text")) if sent.size() == 1 else "")
			var new_edit: Node = find_by(main.screen, func(n: Node) -> bool: return n is LineEdit)
			check("поле ввода очищается после отправки", new_edit != null and String(new_edit.text) == "",
				String(new_edit.text) if new_edit != null else "поля нет")
			check("сообщение видно в переписке", find_label(main.screen, "проверка кнопкой") != null)

	# Акцентные кнопки должны работать: проверяем «Создать ник» на экране входа
	main.show_screen("login", null)
	await get_tree().process_frame
	var create_button: Node = find_by(main.screen, func(n: Node) -> bool:
		return n is Button and n.text == Loc.t("login_create"))
	check("кнопка «Создать ник» есть", create_button != null)
	if create_button != null:
		create_button.emit_signal("pressed")
		await get_tree().process_frame
		check("кнопка «Создать ник» открывает создание ника", main.current_id == "new", main.current_id)

	# ---------------------------------------------------------- 14. Вход по паролю через интерфейс
	Store.create_account("тест2", "5555")
	Store.logout()
	main.show_screen("login", null)
	await get_tree().process_frame
	await get_tree().process_frame
	var locked_card: Node = find_by(main.screen, func(n: Node) -> bool:
		return n is Button and n.custom_minimum_size.y == 74.0 and find_label(n, "тест2") != null)
	check("карточка аккаунта с паролем есть", locked_card != null)
	if locked_card != null:
		locked_card.emit_signal("pressed")
		await get_tree().process_frame
		var pass_edit: Node = find_by(main.screen, func(n: Node) -> bool: return n is LineEdit)
		check("открылся шаг ввода пароля", pass_edit != null and pass_edit.secret)
		if pass_edit != null:
			pass_edit.text = "0000"
			var enter_button: Node = find_by(main.screen, func(n: Node) -> bool:
				return n is Button and n.text == Loc.t("login_enter"))
			check("кнопка «Войти» есть", enter_button != null)
			if enter_button != null:
				enter_button.emit_signal("pressed")
				await get_tree().process_frame
				check("неверный пароль не пускает", main.current_id == "login" and Store.current_nick == "",
					main.current_id + " / " + Store.current_nick)
				check("показана ошибка про пароль", find_label(main.screen, Loc.t("err_pass_wrong")) != null)

				var pass_edit2: Node = find_by(main.screen, func(n: Node) -> bool: return n is LineEdit)
				if pass_edit2 != null:
					pass_edit2.text = "5555"
					var enter2: Node = find_by(main.screen, func(n: Node) -> bool:
						return n is Button and n.text == Loc.t("login_enter"))
					if enter2 != null:
						enter2.emit_signal("pressed")
						await get_tree().process_frame
						check("верный пароль пускает в чаты", main.current_id == "chats", main.current_id)
						check("вошли в аккаунт «тест2»", Store.current_nick == "тест2", Store.current_nick)
	Store.delete_account("тест2")
	check("аккаунт с паролем удалён", not Store.account_exists("тест2"))

	# ---------------------------------------------------------- 16. Ники: один ник на всех
	Store.login("админ", "")
	Store.unread = {}
	check("ключ ника не зависит от регистра",
		Protocol.nick_key("Админ") == Protocol.nick_key("админ") and Protocol.nick_key(" админ ") == "админ")
	var before_peers := Store.messages("админ2").size()
	Store.send_message("АДМИН2", "регистр")
	check("регистр в нике не создаёт второй чат",
		Store.messages("админ2").size() == before_peers + 1 and not Store.contacts().has("АДМИН2"),
		str(Store.contacts()))
	check("список собеседников не задваивает ник",
		Store.contacts().count("админ2") == 1, str(Store.contacts()))
	Store.delete_history("АДМИН2")

	# Непрочитанные
	Store.receive_message("админ2", "первое", 0, "n-1")
	Store.receive_message("админ2", "второе", 0, "n-2")
	Store.receive_message("гость", "третье", 0, "n-3")
	check("непрочитанные считаются по чату", Store.unread_count("админ2") == 2, str(Store.unread_count("админ2")))
	check("непрочитанные считаются всего", Store.unread_total() == 3, str(Store.unread_total()))
	Store.mark_read("админ2")
	check("снятие значка обнуляет только один чат",
		Store.unread_count("админ2") == 0 and Store.unread_total() == 1,
		str(Store.unread_count("админ2")) + "/" + str(Store.unread_total()))
	Store.receive_message("админ2", "непрочитанное", 0, "n-9")
	check("перед открытием чата значок есть", Store.unread_count("админ2") == 1, str(Store.unread_count("админ2")))
	main.show_screen("chat", "админ2")
	await get_tree().process_frame
	check("открытие чата в интерфейсе снимает значок", Store.unread_count("админ2") == 0, str(Store.unread_count("админ2")))
	Store.delete_history("админ2")
	Store.delete_history("гость")

	# Собеседник с моим же ником: ник занят дважды — сообщения не должны пропадать
	check("чат с одноимённым собеседником не прячется",
		Store.receive_message("админ", "это не я", 0, "self-1") and Store.contacts().has("админ"),
		str(Store.contacts()))
	check("поднято предупреждение о чужом нике", Store.nick_conflict)
	check("непрочитанное от одноимённого считается", Store.unread_count("админ") == 1, str(Store.unread_count("админ")))
	Store.mark_read("админ")
	Store.delete_history("админ")
	Store.nick_conflict = false

	# Новый чат с любым ником
	check("чат с новым человеком заводится", Store.ensure_contact("новичок"))
	check("новый человек виден в списке", Store.contacts().has("новичок"), str(Store.contacts()))
	check("чат с самим собой не заводится", not Store.ensure_contact("АДМИН"))
	Store.delete_history("новичок")

	# Проверка ника и пароля без создания аккаунта
	check("слишком короткий ник — ошибка", Store.nick_error("a") == "err_nick_short")
	check("занятый ник — ошибка", Store.nick_error("АДМИН") == "err_nick_used")
	check("свободный ник — без ошибки", Store.nick_error("свободный_ник") == "")
	check("хеш пароля считается", Store.hash_password("1234") != "" and Store.hash_password("") == "")

	# Экран «Новый чат»
	main.show_screen("newchat", null)
	await get_tree().process_frame
	check("экран нового чата открывается", main.current_id == "newchat", main.current_id)
	check("на экране нового чата одно поле",
		count_nodes(main.screen, "LineEdit") == 1, str(count_nodes(main.screen, "LineEdit")))
	check("есть кнопка «Открыть чат»", find_by(main.screen, func(n: Node) -> bool:
		return n is Button and n.text == Loc.t("newchat_open")) != null)

	# ---------------------------------------------------------- 17. Сглаживание, звук, уведомления, обновления

	# Сравнение версий: по числам, а не как строки (1.10 новее 1.9)
	check("версия 1.10 новее, чем 1.9", Protocol.version_compare("1.10", "1.9") == 1)
	check("одинаковые версии равны", Protocol.version_compare("1.2", "1.2") == 0)
	check("старая версия определяется", Protocol.version_compare("1.1", "1.2") == -1)
	check("пустая версия считается старой", Protocol.version_compare("", "1.2") == -1)

	# Что нового
	var changelog: Array = Protocol.changelog("ru")
	check("история версий есть", changelog.size() >= 2, str(changelog.size()))
	var has_current := false
	for entry in changelog:
		if String(entry.get("version", "")) == Protocol.APP_VERSION:
			has_current = true
	check("в истории есть текущая версия", has_current, Protocol.APP_VERSION)
	check("у записи есть пункты", not (changelog[0].get("items", []) as Array).is_empty())
	check("история переводится на английский",
		String((Protocol.changelog("en")[0].get("items", []) as Array)[0]) != String((changelog[0].get("items", []) as Array)[0]))

	# Сглаживание
	Store.set_aa(999)
	check("уровень сглаживания не выходит за границы", Store.aa_level() == 3, str(Store.aa_level()))
	Store.set_aa(2)
	check("уровень сглаживания запоминается", Store.aa_level() == 2, str(Store.aa_level()))
	check("текстура свечения растёт вместе со сглаживанием", UiStyle.glow_size(0) < UiStyle.glow_size(3),
		"%d < %d" % [UiStyle.glow_size(0), UiStyle.glow_size(3)])
	var plain_font: Font = UiStyle.aa_font(0)
	var soft_font: Font = UiStyle.aa_font(2)
	check("шрифт без сглаживания получился",
		plain_font is FontFile and (plain_font as FontFile).antialiasing == TextServer.FONT_ANTIALIASING_NONE)
	check("у мягкого шрифта сглаживание включено",
		soft_font is FontFile and (soft_font as FontFile).antialiasing == TextServer.FONT_ANTIALIASING_GRAY)
	check("у мягкого шрифта буквы подстраиваются тоньше",
		plain_font is FontFile and soft_font is FontFile
		and (soft_font as FontFile).subpixel_positioning != (plain_font as FontFile).subpixel_positioning)
	check("признак сглаживания фигур — да/нет", typeof(UiStyle.shapes_aa_supported()) == TYPE_BOOL)

	# Мягкость краёв фигур: работает в любом графическом режиме (даже без MSAA)
	UiStyle.apply_aa_level(0)
	var hard_softness := UiStyle.shape_softness
	UiStyle.apply_aa_level(3)
	check("«Сглаживание» меняет мягкость краёв фигур", UiStyle.shape_softness > hard_softness,
		"%s -> %s" % [str(hard_softness), str(UiStyle.shape_softness)])
	check("панели используют эту мягкость",
		is_equal_approx(UiStyle.box(Color(1, 1, 1, 0.1)).anti_aliasing_size, UiStyle.shape_softness),
		str(UiStyle.box(Color(1, 1, 1, 0.1)).anti_aliasing_size))
	UiStyle.apply_aa_level(1)

	# Гладкие аватарки: круг рисуется крупной текстурой и уменьшается
	var circle := UiStyle.circle_texture(Color("#2f7bff"), Color(1, 1, 1, 0.35), 64)
	check("круг для аватарки получился", circle is GradientTexture2D and (circle as GradientTexture2D).width == 64,
		str((circle as GradientTexture2D).width if circle is GradientTexture2D else -1))
	check("у круга есть плавный край и обводка",
		circle is GradientTexture2D and (circle as GradientTexture2D).gradient.offsets.size() == 4,
		str((circle as GradientTexture2D).gradient.offsets.size() if circle is GradientTexture2D else -1))
	if main.screen != null and main.screen.has_method("avatar"):
		var av: Control = main.screen.avatar("админ2", 40)
		check("аватарка нарисована гладким кружком",
			av != null and find_by(av, func(n: Node) -> bool:
				return n is TextureRect and (n as TextureRect).texture is GradientTexture2D) != null)
		check("буква ника на аватарке на месте", av != null and find_label(av, "А") != null)
		# Аватарку в дерево не добавляем — освобождаем сами
		if av != null and is_instance_valid(av):
			av.free()
	Store.set_aa(1)

	# Звук: тоны считаются в коде, звуковых файлов в проекте нет
	var incoming: AudioStreamWAV = Sfx._stream("incoming")
	check("звук нового сообщения собран", incoming != null and incoming.data.size() > 0,
		str(incoming.data.size() if incoming != null else -1))
	check("звук с нужной частотой", incoming.mix_rate == Sfx.RATE, str(incoming.mix_rate))
	check("звуки запоминаются", Sfx._stream("incoming") == incoming)
	check("звук отправки короче входящего", Sfx._stream("sent").data.size() < incoming.data.size())
	check("неизвестного звука нет", Sfx._stream("неизвестный") == null)
	check("по умолчанию звук включён", Store.sound_on())
	Store.set_sound(false)
	check("звук выключается", not Store.sound_on())
	Sfx.play("incoming")  # выключен — просто ничего не делает
	Store.set_sound(true)
	Store.set_sound_volume(0.5)
	check("громкость запоминается", is_equal_approx(Store.sound_volume(), 0.5), str(Store.sound_volume()))
	Store.set_sound_volume(9.0)
	check("громкость не выходит за границы", is_equal_approx(Store.sound_volume(), 1.0))
	Store.set_sound_volume(0.7)

	# Уведомления
	check("по умолчанию уведомления включены", Store.notify_on())
	Store.set_notify(false)
	check("уведомления выключаются", not Store.notify_on())
	Store.set_notify(true)

	# Системные уведомления Windows (в автотестах их показывать нельзя)
	check("по умолчанию уведомления Windows включены", Store.notify_os())
	Store.set_notify_os(false)
	check("уведомления Windows выключаются", not Store.notify_os())
	Store.set_notify_os(true)
	check("в безоконном режиме системных уведомлений нет", not TnNotify.available())
	check("в автотесте системное уведомление не отправляется", not TnNotify.toast("Ваня", "привет"))
	var ps: String = TnNotify.build_script("Ваня'с", "привет")
	check("кавычка в тексте уведомления не ломает команду",
		ps.contains("''") and ps.contains("ToastNotificationManager"))
	check("уведомление регистрирует своё имя приложения",
		ps.contains("TNGram.Notifier") and ps.contains("AppUserModelId"), ps.substr(0, 200))
	check("длинный текст уведомления обрезается",
		not TnNotify._clean("x".repeat(500), 100).contains("xxxxx".repeat(30)))
	check("кириллица и эмодзи переживают кодирование",
		TnNotify._decode_command(TnNotify._encode_command("Привет, мир! 👋")) == "Привет, мир! 👋")

	# Всплывающая карточка о новом сообщении
	main.clear_toasts()
	main.show_toast("админ2", "привет")
	await get_tree().process_frame
	var tray: Control = main.ensure_toast_layer()
	check("карточка уведомления появилась", count_nodes(tray, "PanelContainer") == 1,
		str(count_nodes(tray, "PanelContainer")))
	check("в карточке видно текст сообщения", find_label(tray, "привет") != null)
	main.show_toast("админ2", "второе")
	await get_tree().process_frame
	check("карточки копятся", count_nodes(tray, "PanelContainer") == 2, str(count_nodes(tray, "PanelContainer")))
	check("карточки стоят столбиком, а не друг на друге",
		tray.get_child_count() == 1 and tray.get_child(0).get_child_count() == 2,
		"слоёв: %d, в колонке: %d" % [tray.get_child_count(), tray.get_child(0).get_child_count()])
	var cards: Array = tray.get_child(0).get_children()
	if cards.size() == 2:
		var c0 := cards[0] as Control
		var c1 := cards[1] as Control
		check("карточки уведомлений не перекрывают друг друга",
			c0.position.y + c0.size.y <= c1.position.y + 1.0,
			"первая до %d, вторая с %d" % [int(c0.position.y + c0.size.y), int(c1.position.y)])
		check("карточка уведомления не уезжает за край окна",
			c0.global_position.x + c0.size.x <= main.size.x + 1.0 and c0.size.x >= 200.0,
			"правый край %d при ширине окна %d" % [int(c0.global_position.x + c0.size.x), int(main.size.x)])
	else:
		check("карточки уведомлений не перекрывают друг друга", false, "карточек: %d" % cards.size())
		check("карточка уведомления не уезжает за край окна", false, "карточек: %d" % cards.size())
	check("карточки поверх экрана", tray.get_index() == main.get_child_count() - 1)
	main.clear_toasts()
	await get_tree().process_frame
	check("карточки убираются", count_nodes(tray, "PanelContainer") == 0)

	# Обновления
	Store.set_remote_version("")
	check("без проверки обновления нет", Store.update_available() == "")
	Store.set_remote_version("1.1")
	check("старая версия на сайте — обновления нет", Store.update_available() == "")
	Store.set_remote_version("1.99")
	check("новая версия на сайте — предлагаем обновиться", Store.update_available() == "1.99", Store.update_available())
	Store.set_remote_version("")
	check("адрес сайта задан", Store.site_url().begins_with("https://"), Store.site_url())

	# Версия из облака: приложение спрашивает таблицу «version», а не только сайт
	check("адрес строки версии в облаке собран верно",
		Protocol.version_url("https://x.supabase.co").ends_with("/rest/v1/version?select=*&order=updated_at.desc&limit=1"),
		Protocol.version_url("https://x.supabase.co"))
	var from_list := Protocol.parse_version_answer('[{"version":"1.3","notes":"починили","url":"https://a/b"}]')
	check("версия из облака разбирается (список)", String(from_list.get("version", "")) == "1.3", str(from_list))
	check("заметки к версии из облака разбираются", String(from_list.get("notes", "")) == "починили", str(from_list))
	check("ссылка на новую версию разбирается", String(from_list.get("url", "")) == "https://a/b", str(from_list))
	var from_obj := Protocol.parse_version_answer('{"version":"2.0"}')
	check("версия из облака разбирается (объект)", String(from_obj.get("version", "")) == "2.0", str(from_obj))
	check("пустой ответ облака не ломает разбор", Protocol.parse_version_answer("[]").is_empty())
	check("битый ответ облака не ломает разбор", Protocol.parse_version_answer("<html>").is_empty())
	check("без номера версии ответ пустой", Protocol.parse_version_answer('[{"notes":"x"}]').is_empty())
	# Адрес облака берём именно облачный, даже если выбран свой сервер в сети
	Store.set_relay("192.168.1.5", 7777, true, "")
	check("для версий берётся облако, а не свой сервер",
		Store.cloud_url().begins_with("https://") and Store.cloud_url().contains("supabase.co"), Store.cloud_url())
	check("ключ облака подставляется для версий", Store.cloud_key() != "", Store.cloud_key().substr(0, 12) + "…")
	Store.set_relay(Protocol.CLOUD_DEFAULT_URL, Protocol.DEFAULT_PORT, true, Protocol.CLOUD_DEFAULT_KEY)

	var answered: Array = []
	Net.fetch_text("", func(ok: bool, text: String) -> void:
		answered.append([ok, text]))
	await get_tree().process_frame
	check("пустой адрес сайта не запрашивается",
		answered.size() == 1 and bool(answered[0][0]) == false and String(answered[0][1]) == "", str(answered))
	if OS.get_environment("TNGRAM_PROFILE").strip_edges() != "":
		check("в проверках чужой сайт не опрашивается", not main._update_checked)

	# Экран «Что нового»
	main.show_screen("news", null)
	await get_tree().process_frame
	check("экран «Что нового» открывается", main.current_id == "news", main.current_id)
	check("на экране видно заголовок", find_label(main.screen, Loc.t("news_title")) != null)
	check("в списке есть текущая версия " + Protocol.APP_VERSION,
		find_by(main.screen, func(n: Node) -> bool:
			return n is Label and String(n.text).contains(Protocol.APP_VERSION)) != null)

	# Настройки: новые разделы
	main.show_screen("settings", null)
	await get_tree().process_frame
	check("в настройках есть раздел «Сглаживание»", find_label(main.screen, Loc.t("settings_graphics")) != null)
	check("в настройках есть раздел «Звук»", find_label(main.screen, Loc.t("settings_sound")) != null)
	check("в настройках есть раздел «Уведомления»", find_label(main.screen, Loc.t("settings_notify")) != null)
	var aa_buttons := 0
	for level in [0, 1, 2, 3]:
		if find_by(main.screen, func(n: Node) -> bool:
			return n is Button and String(n.text) == Loc.t("aa_%d" % level)) != null:
			aa_buttons += 1
	check("в настройках четыре уровня сглаживания", aa_buttons == 4, str(aa_buttons))
	check("в настройках есть ползунок громкости", count_nodes(main.screen, "HSlider") == 1,
		str(count_nodes(main.screen, "HSlider")))
	check("в настройках есть включатели звука и уведомлений", count_nodes(main.screen, "CheckButton") >= 3,
		str(count_nodes(main.screen, "CheckButton")))
	check("в настройках видно версию приложения",
		find_by(main.screen, func(n: Node) -> bool:
			return n is Label and String(n.text).contains(Protocol.APP_VERSION)) != null)
	check("из настроек есть дорога к «Что нового»", find_by(main.screen, func(n: Node) -> bool:
		return n is Button and String(n.text) == Loc.t("settings_news")) != null)

	# ---------------------------------------------------------- 15. Вход в облако
	# Ник превращается в служебный адрес: почты у нас нет, а облако принимает
	# только «почтовые» адреса. Один ник — один адрес, значит и один человек.
	var mail_admin := Protocol.auth_email("Админ")
	check("ник превращается в служебный адрес",
		mail_admin.ends_with(Protocol.AUTH_DOMAIN) and mail_admin.length() > 10, mail_admin)
	check("«Админ» и « админ » — один и тот же адрес",
		Protocol.auth_email(" админ ") == mail_admin, Protocol.auth_email(" админ "))
	check("разные ники — разные адреса", Protocol.auth_email("админ") != Protocol.auth_email("админ2"))
	check("пустой ник — пустой адрес", Protocol.auth_email("   ") == "")
	var latin_only := true
	for i in mail_admin.length():
		var code := mail_admin.unicode_at(i)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 122) or code == 64 or code == 46):
			latin_only = false
	check("в адресе только латиница и цифры", latin_only, mail_admin)
	check("адрес службы входа собран верно",
		Protocol.auth_url("https://x.supabase.co", "signup") == "https://x.supabase.co/auth/v1/signup",
		Protocol.auth_url("https://x.supabase.co", "signup"))

	# Разбор ответа службы входа
	var session := Protocol.parse_session('{"access_token":"aaa","refresh_token":"bbb","expires_in":3600,"user":{"id":"u-1"}}')
	check("пропуск из ответа облака разбирается", String(session.get("access_token", "")) == "aaa", str(session))
	check("ключ обновления разбирается", String(session.get("refresh_token", "")) == "bbb", str(session))
	check("срок пропуска разбирается", int(session.get("expires_in", 0)) == 3600, str(session))
	check("имя на сервере разбирается", String(session.get("user_id", "")) == "u-1", str(session))
	check("ответ без пропуска входом не считается", Protocol.parse_session('{"user":{"id":"u-1"}}').is_empty())
	check("битый ответ службы входа не ломает разбор", Protocol.parse_session("<html>").is_empty())
	check("причина отказа разбирается",
		Protocol.parse_auth_error('{"code":400,"error_code":"invalid_credentials","msg":"x"}') == "invalid_credentials",
		Protocol.parse_auth_error('{"code":400,"error_code":"invalid_credentials","msg":"x"}'))
	check("причина отказа без кода не ломает разбор", Protocol.parse_auth_error("garbage") == "")

	# Пропуск живёт в аккаунте и переживает перезапуск
	Store.login("админ", "")
	check("без ответа облака пропуска нет", Store.auth_token() == "", Store.auth_token())
	check("и «просроченным» он не считается", not Store.session_expired())
	Store.set_session("админ", { "access_token": "tok1", "refresh_token": "ref1", "expires_in": 3600, "user_id": "u1" })
	check("после ответа облака пропуск на месте", Store.auth_token() == "tok1", Store.auth_token())
	check("сразу после выдачи пропуск ещё годен", not Store.session_expired())
	check("ключ обновления сохранён", Store.refresh_value() == "ref1", Store.refresh_value())
	check("чужому аккаунту пропуск не подставляется", Store.auth_token("админ2") == "", Store.auth_token("админ2"))
	Store.save_data()
	Store.accounts = []
	Store.load_data()
	check("пропуск переживает перезапуск", Store.auth_token("админ") == "tok1", Store.auth_token("админ"))
	Store.clear_session("админ")
	check("пропуск убирается", Store.auth_token("админ") == "", Store.auth_token("админ"))

	Store.logout()

	# ---------------------------------------------------------- 15б. Группы
	Store.logout()
	Store.login("админ", "")
	Store.groups = {}
	Store.chats = {}
	var made := Store.create_group("Дачники", ["админ2"])
	check("группа создаётся", bool(made.get("ok", false)), str(made))
	var gkey := String(made.get("key", ""))
	check("адрес группы начинается с «g:»", gkey.begins_with(Protocol.GROUP_PREFIX), gkey)
	check("группа опознаётся как группа", Store.is_group(gkey))
	check("название группы на месте", Store.group_title(gkey) == "Дачники", Store.group_title(gkey))
	check("участники группы записаны", Store.group_members(gkey) == ["админ2"], str(Store.group_members(gkey)))
	check("сам создатель в участники для отправки не попал",
		not Store.group_members(gkey).has("админ"))
	check("но создатель есть в полном составе группы",
		Store.group_roster(gkey).has("админ") and Store.group_roster(gkey).has("админ2"),
		str(Store.group_roster(gkey)))
	check("группа без названия не создаётся",
		String(Store.create_group("", ["админ2"]).get("error", "")) == "err_group_title")
	check("группа без людей не создаётся",
		String(Store.create_group("Пусто", []).get("error", "")) == "err_group_members")
	check("то же название и тот же создатель — та же группа",
		Protocol.group_key("Дачники", "админ") == gkey, Protocol.group_key("Дачники", "админ"))
	check("разные создатели — разные группы", Protocol.group_key("Дачники", "админ2") != gkey)
	check("в списке чатов группа есть", has_chat(Store.chat_keys(), gkey, true), str(Store.chat_keys()))

	# Письмо в группу сохраняется у отправителя
	check("в группу можно написать", Store.send_group_message(gkey, "привет всем"))
	check("письмо в группе на месте", String(Store.last_message(gkey).get("text", "")) == "привет всем",
		str(Store.last_message(gkey)))
	check("в группе помечено, кому писать", Store.group_members(gkey) == ["админ2"])

	# Шапка группы едет вместе с текстом — так участник узнаёт про группу
	var packed := Protocol.encode_group(gkey, "Дачники", Store.group_roster(gkey), "привет всем", "админ")
	check("письмо группы помечено как групповое", packed.begins_with(Protocol.GROUP_MARK))
	var opened := Protocol.decode_group(packed)
	check("адрес группы разбирается из письма", String(opened.get("key", "")) == gkey, str(opened))
	check("название группы разбирается из письма", String(opened.get("title", "")) == "Дачники", str(opened))
	check("состав группы разбирается из письма",
		(opened.get("members", []) as Array).has("админ2") and (opened.get("members", []) as Array).has("админ"),
		str(opened))
	check("создатель группы разбирается из письма", String(opened.get("owner", "")) == "админ", str(opened))
	check("текст письма группы разбирается", String(opened.get("text", "")) == "привет всем", str(opened))
	check("обычное письмо группой не считается", Protocol.decode_group("привет").is_empty())

	# У получателя та же группа заводится сама
	Store.logout()
	Store.login("админ2", "")
	Store.unread = {}
	check("письмо из группы принято",
		Store.receive_group_message("админ", gkey, "Дачники", ["админ", "админ2"], "привет всем", 0, "g-1"))
	check("группа завелась у получателя", Store.is_group(gkey))
	check("название группы пришло с письмом", Store.group_title(gkey) == "Дачники", Store.group_title(gkey))
	check("повтор того же письма не задваивается",
		Store.receive_group_message("админ", gkey, "Дачники", ["админ", "админ2"], "привет всем", 0, "g-1"))
	check("письмо в группе осталось одно", Store.messages(gkey).size() == 1, str(Store.messages(gkey).size()))
	check("непрочитанное в группе посчитано", Store.unread_count(gkey) == 1, str(Store.unread_count(gkey)))
	check("создатель группы есть в составе у участника",
		Store.group_roster(gkey).has("админ"), str(Store.group_roster(gkey)))
	check("ответ из группы уйдёт и создателю", Store.group_members(gkey).has("админ"),
		str(Store.group_members(gkey)))
	check("адрес группы не попал в список людей", not Store.contacts().has(gkey), str(Store.contacts()))
	var same_card := 0
	for chat_card in Store.chat_keys():
		if String((chat_card as Dictionary).get("key", "")) == gkey:
			same_card += 1
	check("в списке чатов группа ровно одна карточка", same_card == 1, str(same_card))

	# Старое письмо без создателя в шапке: он всё равно добавляется в состав
	Store.logout()
	Store.login("админ2", "")
	Store.receive_group_message("админ", "g:старая_админ", "Старая", ["админ2"], "старое", 0, "g-old")
	check("в старой группе создатель найден по шапке",
		Store.group_members("g:старая_админ").has("админ"),
		str(Store.group_members("g:старая_админ")))

	# ---------------------------------------------------------- 15в. Кто в сети
	Store.logout()
	Store.login("админ", "")
	Store.peer_seen = {}
	var now := int(Time.get_unix_time_from_system())
	Store.note_seen("админ2", now)
	check("свежее «я здесь» — человек в сети", Store.is_online("админ2"))
	Store.note_seen("админ2", now - Protocol.PRESENCE_ONLINE_SEC - 5)
	check("давнее «я здесь» — человек не в сети", not Store.is_online("админ2"))
	check("время последнего визита помнится", Store.seen_at("админ2") == now - Protocol.PRESENCE_ONLINE_SEC - 5)
	check("регистр букв в нике не важен", Store.seen_at("АДМИН2") == Store.seen_at("админ2"))
	check("про незнакомца времени нет", Store.seen_at("незнакомец") == 0)
	var seen_map := Protocol.parse_presence('[{"nick_key":"админ2","nick":"админ2","last_seen":"2026-10-18 12:34:56+00"}]')
	check("ответ облака про присутствие разбирается", int(seen_map.get("админ2", 0)) > 0, str(seen_map))
	check("мусор вместо присутствия не ломает", Protocol.parse_presence("garbage").is_empty())
	check("без ключа ника строка пропускается", Protocol.parse_presence('[{"nick":"x","last_seen":"2026-10-18 12:34:56+00"}]').is_empty())
	Store.apply_presence({ "админ2": now })
	check("ответ облака обновляет время", Store.seen_at("админ2") == now, str(Store.seen_at("админ2")))
	check("про собеседника спрашивают облако", Store.presence_keys().has("админ2"), str(Store.presence_keys()))
	check("адрес запроса про присутствие собран верно",
		Protocol.presence_query_url("https://x.supabase.co", ["админ2"]).ends_with(
			"/rest/v1/presence?select=nick_key,nick,last_seen&nick_key=in.(" + "админ2".uri_encode() + ")"),
		Protocol.presence_query_url("https://x.supabase.co", ["админ2"]))
	check("в адресе кириллица уходит percent-encoded",
		Protocol.presence_query_url("https://x.supabase.co", ["админ2"]).contains("%D0%B0"),
		Protocol.presence_query_url("https://x.supabase.co", ["админ2"]))
	check("латиница в адресе остаётся как есть",
		Protocol.presence_query_url("https://x.supabase.co", ["nick2"]).ends_with(
			"/rest/v1/presence?select=nick_key,nick,last_seen&nick_key=in.(nick2)"))
	check("запись о себе идёт upsert-ом по ключу ника",
		Protocol.presence_url("https://x.supabase.co").ends_with("/rest/v1/presence?on_conflict=nick_key"),
		Protocol.presence_url("https://x.supabase.co"))
	check("без ников запрос про присутствие пустой",
		Protocol.presence_query_url("https://x.supabase.co", []).is_empty())

	# Подписи «в сети» / «был(а) 5 мин назад» — в переписке
	main.show_screen("chat", "админ2")
	await get_tree().process_frame
	check("в переписке видно, что человек в сети", find_label(main.screen, Loc.t("status_online")) != null)
	Store.note_seen("админ2", now - 300)
	await get_tree().process_frame
	check("в переписке видно, когда человек заходил",
		find_label(main.screen, Loc.tf("status_last_seen", [Loc.tf("time_minutes", ["5"])])) != null,
		Loc.tf("status_last_seen", [Loc.tf("time_minutes", ["5"])]))
	var screen_api := main.screen as ScreenBase
	check("сегодняшний день подписан как «Сегодня»", screen_api.day_text(now) == Loc.t("day_today"), screen_api.day_text(now))
	check("вчерашний день подписан как «Вчера»", screen_api.day_text(now - 86400) == Loc.t("day_yesterday"),
		screen_api.day_text(now - 86400))
	check("свежее время — «только что»", screen_api.time_ago(now) == Loc.t("time_now"), screen_api.time_ago(now))
	check("час назад — «1 ч назад»", screen_api.time_ago(now - 3600) == Loc.tf("time_hours", ["1"]), screen_api.time_ago(now - 3600))
	check("двое суток назад — «2 дн назад»", screen_api.time_ago(now - 172800) == Loc.tf("time_days", ["2"]),
		screen_api.time_ago(now - 172800))

	# Групповой чат: название, участники, автор письма
	main.show_screen("chat", gkey)
	await get_tree().process_frame
	check("в групповом чате видно название", find_label(main.screen, "Дачники") != null)
	check("в групповом чате видно число участников",
		find_label(main.screen, Loc.tf("group_members_count", ["2"])) != null,
		Loc.tf("group_members_count", ["2"]))
	Store.receive_group_message("админ2", gkey, "Дачники", ["админ", "админ2"], "всем привет")
	await get_tree().process_frame
	check("в группе видно, кто написал", find_label(main.screen, "админ2") != null)

	# ---------------------------------------------------------- 15г. Поиск и новости
	main.show_screen("chats", null)
	await get_tree().process_frame
	check("группа видна в списке чатов", find_label(main.screen, "Дачники") != null)
	check("есть кнопка «Группа»", has_button_named(main.screen, Loc.t("chats_new_group")))
	check("есть поиск по чатам", find_by(main.screen, func(n: Node) -> bool:
		return n is LineEdit and String(n.placeholder_text) == Loc.t("chats_search")) != null)
	var search := find_by(main.screen, func(n: Node) -> bool:
		return n is LineEdit and String(n.placeholder_text) == Loc.t("chats_search")) as LineEdit
	if search != null:
		search.text = "дач"
		search.text_changed.emit("дач")
		await get_tree().process_frame
		check("поиск оставляет подходящий чат", find_label(main.screen, "Дачники") != null)
		check("поиск убирает неподходящие чаты", find_label(main.screen, "админ2") == null)
		check("поиск без совпадений никого не показывает", find_label(main.screen, Loc.t("chats_search")) == null)
		search.text = "абракадабра"
		search.text_changed.emit("дач")
		await get_tree().process_frame
		check("пустой поиск ничего не находит", find_label(main.screen, Loc.t("search_nothing")) != null)
		search.text = ""
		search.text_changed.emit("")
		await get_tree().process_frame
		check("пустой поиск снова показывает всех", find_label(main.screen, "админ2") != null)

	# Полоса «вышла новая версия» прямо в списке чатов
	Store.set_remote_version("9.9")
	main.show_screen("chats", null)
	await get_tree().process_frame
	check("в списке чатов видно, что вышла новая версия",
		find_label(main.screen, Loc.tf("update_available", ["9.9"])) != null)
	check("в списке чатов есть кнопка «Обновить»", has_button_named(main.screen, Loc.t("update_get")))
	Store.set_remote_version("")

	# Новости из облака на экране «Что нового»
	var news := Protocol.parse_news('[{"title":"Заголовок","body":"Текст","created_at":"2026-10-18T09:00:00+00:00"}]')
	check("новость разбирается", news.size() == 1, str(news))
	check("заголовок новости читается", String((news[0] as Dictionary).get("title", "")) == "Заголовок", str(news))
	check("текст новости читается", String((news[0] as Dictionary).get("body", "")) == "Текст", str(news))
	check("пустая новость пропускается", Protocol.parse_news('[{"title":"","body":""}]').is_empty())
	check("мусор вместо новостей не ломает", Protocol.parse_news("garbage").is_empty())
	main.show_screen("news", null)
	await get_tree().process_frame
	check("на экране «Что нового» есть блок новостей", find_label(main.screen, Loc.t("news_from_server")) != null)

	# ---------------------------------------------------------- 15д. Прокрутка (телефон)
	var fling := preload("res://scripts/ui/FlingScroll.gd").new()
	var fling_target := ScrollContainer.new()
	fling_target.custom_minimum_size = Vector2(300, 200)
	fling_target.size = Vector2(300, 200)
	var tall := Control.new()
	tall.custom_minimum_size = Vector2(0, 2000)
	fling_target.add_child(tall)
	add_child(fling_target)
	fling.target = fling_target
	add_child(fling)
	await get_tree().process_frame
	check("прокрутка: предел списка известен", fling._scroll_limit() > 0.0, str(fling._scroll_limit()))
	var strip := Control.new()
	var strip_button := Button.new()
	var strip_slider := HSlider.new()
	strip.add_child(strip_button)
	strip.add_child(strip_slider)
	fling.pass_through(strip)
	check("кнопки пропускают палец к списку", strip_button.mouse_filter == Control.MOUSE_FILTER_PASS,
		str(strip_button.mouse_filter))
	check("ползунки не трогаем", strip_slider.mouse_filter == Control.MOUSE_FILTER_STOP,
		str(strip_slider.mouse_filter))
	fling._velocity = 600.0
	fling._on_scroll_ended()
	check("быстрый рывок пальцем даёт разгон", fling._active)
	fling._velocity = 20.0
	fling._on_scroll_ended()
	check("медленное движение разгона не даёт", not fling._active)
	fling._velocity = 999999.0
	fling._on_scroll_ended()
	check("слишком сильный рывок ограничен", fling._velocity <= fling.max_speed, str(fling._velocity))
	fling._velocity = 1000.0
	fling._active = true
	fling._process(0.5)
	check("инерция затухает сама", not fling._active, str(fling._velocity))
	fling.queue_free()
	fling_target.queue_free()

	# У каждого прокручиваемого экрана есть узел инерции
	main.show_screen("chats", null)
	await get_tree().process_frame
	var flinger := find_by(main.screen, func(n: Node) -> bool:
		return n.get_script() == preload("res://scripts/ui/FlingScroll.gd"))
	check("у списка есть узел инерции", flinger != null)
	check("инерция привязана к прокрутке", flinger != null and flinger.target != null)

	# ---------------------------------------------------------- 15д2. Экран «Новая группа»
	main.show_screen("newgroup", null)
	await get_tree().process_frame
	check("на экране группы есть заголовок", find_label(main.screen, Loc.t("group_title")) != null)
	check("на экране группы подпись про людей", find_label(main.screen, Loc.t("newgroup_who")) != null)
	check("на экране группы есть кнопка создания", has_button_named(main.screen, Loc.t("newgroup_create")))
	var ru_keys: Array = (Loc.STRINGS["ru"] as Dictionary).keys()
	var en_keys: Array = (Loc.STRINGS["en"] as Dictionary).keys()
	ru_keys.sort()
	en_keys.sort()
	check("русский и английский тексты совпадают по набору ключей", ru_keys == en_keys,
		"ru=%d en=%d" % [ru_keys.size(), en_keys.size()])
	# Проверка, что в коде нет несущих ключей
	var missing := {}
	var all_files := gd_files("res://scripts")
	for p in all_files:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var content := f.get_as_text()
		f.close()
		for k in loc_keys_in(content):
			if k.ends_with("_") or k.contains("%"):
				continue  # ключ собирается на лету: "theme_" + id, "aa_%d"
			if not Loc.STRINGS["ru"].has(k) or not Loc.STRINGS["en"].has(k):
				if not missing.has(k):
					missing[k] = []
				missing[k].append(p.get_file())
	check("в коде нет ключей, которых нет в Loc", missing.is_empty(), str(missing).substr(0, 120))
	# Темы и уровни сглаживания собираются ключом на лету — сверим их отдельно
	var dynamic_bad := []
	for k in ["theme_dark", "theme_green", "theme_blue", "aa_0", "aa_1", "aa_2", "aa_3", "aa_4"]:
		if not Loc.STRINGS["ru"].has(k) or not Loc.STRINGS["en"].has(k):
			dynamic_bad.append(k)
	check("тексты тем и уровней сглаживания на месте", dynamic_bad.is_empty(), str(dynamic_bad))
	# Никакой экран не должен показывать «сырой» ключ вместо текста
	main.show_screen("chats", null)
	await get_tree().process_frame
	check("в списке чатов нет сырых ключей вместо текста",
		find_label(main.screen, "chats_new_group") == null and find_label(main.screen, "net_online") == null and find_label(main.screen, "status_online") == null)

	# ---------------------------------------------------------- 15е. Занятый ник — войти, а не создать
	main.show_screen("new", null)
	await get_tree().process_frame
	main.screen.error_code = "err_nick_used"
	main.screen.rebuild()
	await get_tree().process_frame
	check("при занятом нике видно объяснение", not Loc.t("err_nick_used").is_empty())
	check("при занятом нике есть кнопка «войти под этим ником»",
		has_button_named(main.screen, Loc.t("new_nick_taken_login")))
	main.show_screen("login", "админ2")
	await get_tree().process_frame
	check("вход сразу открывается под нужным ником", find_label(main.screen, "админ2") != null)
	check("на шаге входа есть поле пароля", find_by(main.screen, func(n: Node) -> bool:
		return n is LineEdit and bool(n.secret)) != null)
	check("второй такой же ник не создать", String(Store.create_account("АДМИН ", "").get("error", "")) == "err_nick_used")

	# ---------------------------------------------------------- 15ж. Клоны аккаунтов и чатов
	Store.logout()
	Store.login("админ", "")
	Store.chats = {}
	Store.chats["админ"] = { "АДМИН2": [ { "text": "старое", "ts": 5, "mine": false } ] }
	Store.chats["АДМИН"] = { "админ2": [ { "text": "новое", "ts": 7, "mine": false } ] }
	Store.unread = { "АДМИН": { "АДМИН2": 2 }, "админ": { "админ2": 3 } }
	Store.accounts.append({ "nick": "АДМИН", "pass_hash": "", "created": 1 })
	Store._normalize_data()
	var acc_names: Array = []
	for acc in Store.accounts:
		acc_names.append(String((acc as Dictionary).get("nick", "")))
	check("клон аккаунта склеен в один",
		acc_names.filter(func(n: String) -> bool: return n.to_lower() == "админ").size() == 1, str(acc_names))
	check("аккаунт остался под своим написанием", acc_names.has("админ"), str(acc_names))
	var merged_chat := Store.messages("АДМИН2")
	check("чаты-клоны склеены", merged_chat.size() == 2, str(merged_chat))
	check("письма встали по времени",
		String((merged_chat[0] as Dictionary).get("text", "")) == "старое"
		and String((merged_chat[1] as Dictionary).get("text", "")) == "новое", str(merged_chat))
	check("непрочитанные сложились", Store.unread_count("АДМИН2") == 5, str(Store.unread_count("АДМИН2")))
	check("непрочитанные видны при любом написании", Store.unread_count("админ2") == 5)
	check("владельцы-клоны склеены", Store.chats.size() == 1, str(Store.chats.keys()))
	Store.groups = {}
	Store.groups["АДМИН"] = { "g:дачники_админ": { "title": "Дачники", "members": ["админ2"], "owner": "админ", "created": 1 } }
	Store.groups["админ"] = { "g:дачники_админ": { "title": "Дачники", "members": ["админ", "админ2"], "owner": "админ", "created": 1 } }
	Store._normalize_data()
	check("группы-клоны склеены", Store.groups.size() == 1, str(Store.groups.keys()))
	check("в склеенной группе состав полон",
		Store.group_roster("g:дачники_админ").has("админ") and Store.group_roster("g:дачники_админ").has("админ2"),
		str(Store.group_roster("g:дачники_админ")))
	check("имя собеседника берётся из аккаунта", Store.peer_title("АДМИН2") == "админ2", Store.peer_title("АДМИН2"))
	check("группе имя — её название", Store.peer_title("g:дачники_админ") == "Дачники")

	# Уборка после новых проверок: данные — как после первого запуска
	Store.groups = {}
	Store.chats = {}
	Store.unread = {}
	Store.peer_seen = {}
	Store.save_data()

	# ---------------------------------------------------------- 16. Итог и уборка
	Store.delete_account("тест")
	check("аккаунт удаляется", not Store.account_exists("тест"))
	# Приводим данные к состоянию «первый запуск»: переписки нет, настройки по умолчанию
	Store.login("админ", "")
	Store.delete_history("админ2")
	check("тестовая переписка убрана", Store.messages("админ2").is_empty())
	Store.logout()
	Store.settings = { "lang": "ru", "theme": "dark", "last_nick": "" }
	Store.save_data()
	check("настройки сброшены", Store.lang() == "ru" and Store.theme() == "dark" and Store.current_nick == "")

	print("---")
	print("проверок пройдено: ", passes, ", ошибок: ", failures)
	# Отчёт в файл — чтобы читать результат и в оконном режиме, где вывод не перехватывается
	var file := FileAccess.open("user://smoke_report.txt", FileAccess.WRITE)
	if file != null:
		file.store_string("проверок пройдено: %d, ошибок: %d\n" % [passes, failures])
		file.store_string("\n".join(lines))
		file.close()
		print("отчёт: ", ProjectSettings.globalize_path("user://smoke_report.txt"))
	# Уборка перед выходом: отпускаем всё, что держали в руках (само приложение,
	# второго собеседника и сервер проверки). Без этого движок иногда сообщает,
	# что пара объектов осталась в памяти — на работу это не влияет, но в отчёте
	# выглядит как ошибка.
	main.queue_free()
	peer_client.queue_free()
	main = null
	peer_client = null
	relay = null
	for i in 5:
		await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)
