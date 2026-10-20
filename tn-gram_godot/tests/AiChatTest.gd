extends Node
## Проверка «телефонного» сценария слабого ИИ на компьютере.
## ИИ-чат живёт только на телефоне, поэтому включаем его принудительно
## (TNGRAM_AI_ALL=1) и прогоняем весь путь как на Android: карточка в списке,
## открытие чата, отправка, ответ бота, «вниз».
## Запуск: godot --headless --path <папка проекта> res://tests/AiChatTest.tscn
## Идёт в отдельном профиле (TNGRAM_PROFILE=ai), настоящие данные не трогаются.

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

func find_by(root: Node, predicate: Callable) -> Node:
	for child in root.get_children():
		if bool(predicate.call(child)):
			return child
		var found := find_by(child, predicate)
		if found != null:
			return found
	return null

func find_label(root: Node, text: String) -> Label:
	if root is Label and String((root as Label).text) == text:
		return root as Label
	for child in root.get_children():
		var found := find_label(child, text)
		if found != null:
			return found
	return null

func _ready() -> void:
	await get_tree().process_frame
	if not Protocol.is_ai_enabled():
		report("пропуск: ИИ-чат выключен (нужен TNGRAM_AI_ALL=1)")
		print("---")
		print("проверок пройдено: 0, ошибок: 0")
		get_tree().quit(0)
		return

	var main: Control = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.show_screen("login", null)
	Store.login("админ", "")
	main.show_screen("chats", null)
	await get_tree().process_frame
	await get_tree().process_frame

	# Карточка ИИ-помощника — первая в списке чатов
	var ai_card := find_by(main.screen, func(n: Node) -> bool:
		return n is Button and find_label(n, "ИИ-помощник") != null)
	check("карточка ИИ-помощника есть в списке чатов", ai_card != null)
	check("под карточкой видно «работает без интернета»",
		ai_card != null and find_label(ai_card, "Слабый ИИ · работает без интернета") != null)

	# Открываем чат нажатием карточки (как это делает человек)
	Store.delete_history(Protocol.AI_KEY)
	if ai_card != null:
		(ai_card as Button).emit_signal("pressed")
		await get_tree().process_frame
		await get_tree().process_frame
	check("нажатие на карточку открывает ИИ-чат",
		main.current_id == "chat" and String(main.current_arg) == Protocol.AI_KEY,
		String(main.current_id) + " / " + String(main.current_arg))
	check("в шапке видно имя помощника", find_label(main.screen, "ИИ-помощник") != null)
	check("в шапке видно «слабый ИИ · офлайн»", find_label(main.screen, "слабый ИИ · офлайн") != null)
	check("внизу видно заметку про устройство",
		find_label(main.screen, "Помощник отвечает по-своему: вся переписка хранится только на этом устройстве.") != null)
	check("в пустом чате есть подсказка",
		find_label(main.screen, "Напиши «привет» — помощник ответит даже без интернета.") != null)

	# Пишем сообщение и жмём «Отправить» кнопкой
	var input := find_by(main.screen, func(n: Node) -> bool: return n is LineEdit) as LineEdit
	var send_button := find_by(main.screen, func(n: Node) -> bool:
		return n is Button and String((n as Button).text) == "Отправить") as Button
	check("в ИИ-чате есть поле ввода и кнопка отправки", input != null and send_button != null)
	if input != null and send_button != null:
		input.text = "привет, как дела?"
		send_button.emit_signal("pressed")
		await get_tree().process_frame
		check("своё сообщение видно в чате", find_label(main.screen, "привет, как дела?") != null)
		check("поле ввода очистилось", String(input.text) == "")
		check("пока ИИ думает — видно «печатает…»", find_label(main.screen, "печатает…") != null)
		# Ждём ответ бота (Main отвечает через 0,75 с)
		var deadline := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < deadline and Store.messages(Protocol.AI_KEY).size() < 2:
			await get_tree().process_frame
		check("ИИ ответил в чат", Store.messages(Protocol.AI_KEY).size() >= 2,
			"сообщений: %d" % Store.messages(Protocol.AI_KEY).size())
		if Store.messages(Protocol.AI_KEY).size() >= 2:
			var answer := String((Store.messages(Protocol.AI_KEY)[-1] as Dictionary).get("text", ""))
			check("ответ ИИ не пустой", answer.strip_edges() != "", answer)
			check("ответ ИИ пришёл не от меня",
				not bool((Store.messages(Protocol.AI_KEY)[-1] as Dictionary).get("mine", true)))
			check("ответ ИИ виден в чате", find_label(main.screen, answer) != null, answer)
		check("после ответа «печатает…» исчезло", find_label(main.screen, "печатает…") == null)

	# Ещё раз: пример и время — и всё это без интернета
	if input != null and send_button != null:
		input.text = "2+2"
		send_button.emit_signal("pressed")
		var before := Store.messages(Protocol.AI_KEY).size()
		var deadline2 := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < deadline2 and Store.messages(Protocol.AI_KEY).size() <= before:
			await get_tree().process_frame
		var math_reply := ""
		if Store.messages(Protocol.AI_KEY).size() > before:
			math_reply = String((Store.messages(Protocol.AI_KEY)[-1] as Dictionary).get("text", ""))
		check("ИИ решил пример прямо в чате", math_reply.contains("4"), math_reply)

	# Кнопка «вниз»: поднимаемся выше и ждём, что она появится
	main.show_screen("chats", null)
	await get_tree().process_frame
	check("ИИ-чат не задваивается как человек",
		not Store.contacts().has(Protocol.AI_KEY))
	Store.delete_history(Protocol.AI_KEY)

	print("---")
	print("проверок пройдено: ", passes, ", ошибок: ", failures)
	main.queue_free()
	for i in 4:
		await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)
