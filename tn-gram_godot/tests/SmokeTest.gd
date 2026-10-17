extends Node
## Автопроверка приложения без экрана (headless).
## Запуск: godot --headless --path <папка проекта> res://tests/SmokeTest.tscn
## Проверяет данные, вход, переписку, переключение языка/темы и сборку экранов.

const TnNetScript := preload("res://scripts/net/TnNet.gd")

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

	main.show_screen("chat", "админ2")
	await get_tree().process_frame
	await get_tree().process_frame
	check("экран чата открывается", main.current_id == "chat")
	check("в чате одно поле ввода", count_nodes(main.screen, "LineEdit") == 1)
	check("сообщение видно в чате", find_label(main.screen, "привет") != null)

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

	# ---------------------------------------------------------- 15. Итог и уборка
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
	await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)
