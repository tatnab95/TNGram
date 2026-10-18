extends ScreenBase
## Экран переписки: пузыри сообщений, поле ввода, удаление переписки.

var peer := ""
var messages_box: VBoxContainer
var scroller: ScrollContainer
var input: LineEdit
var note_label: Label
var ping_label: Label

func _ready() -> void:
	Store.mark_read(peer)
	build()
	if not Store.data_changed.is_connected(_on_data_changed):
		Store.data_changed.connect(_on_data_changed)
	if not Net.changed.is_connected(net_changed):
		Net.changed.connect(net_changed)
	await get_tree().process_frame
	scroll_to_bottom()

func _on_data_changed() -> void:
	if not is_inside_tree():
		return
	if messages_box == null or not is_instance_valid(messages_box):
		rebuild()
		return
	# Пришло новое сообщение — обновляем только список. Полная перерисовка
	# стёрла бы текст, который человек печатает прямо сейчас, и сбила бы курсор.
	Store.mark_read(peer)
	fill_messages()
	await get_tree().process_frame
	scroll_to_bottom()

## Состояние связи изменилось — обновляем только подпись, не трогая ввод
func net_changed() -> void:
	if note_label != null and is_instance_valid(note_label):
		note_label.text = _note_text()
	if ping_label != null and is_instance_valid(ping_label):
		ping_label.text = _ping_text()

func _note_text() -> String:
	return Loc.t("net_note_online") if Net.is_online() else Loc.t("net_note_offline")

## Отклик сервера: «Пинг 84 мс», а пока не измерено — «Пинг…»
func _ping_text() -> String:
	if Net.ping_ms < 0:
		return Loc.t("ping_wait")
	return Loc.tf("ping_line", [str(Net.ping_ms)])

## Полная перерисовка экрана (например, после смены темы). Не теряем то, что
## уже напечатано, и возвращаем курсор туда, где он был.
func rebuild() -> void:
	var draft := ""
	var caret := 0
	var had_focus := false
	if input != null and is_instance_valid(input):
		draft = input.text
		caret = input.caret_column
		had_focus = input.has_focus()

	for child in get_children():
		child.queue_free()
	build()

	if draft != "" and input != null and is_instance_valid(input):
		input.text = draft
		input.caret_column = caret
	if not had_focus and input != null and is_instance_valid(input):
		input.release_focus()

	await get_tree().process_frame
	scroll_to_bottom()

func build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAD)
	margin.add_theme_constant_override("margin_right", PAD)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var column := vbox(14)
	margin.add_child(column)

	# --- верхняя строка ---
	var top := hbox(12)
	top.add_child(ghost_button(Loc.t("back"), func() -> void:
		navigate.emit("chats", null)))
	top.add_child(avatar(peer, 38))
	var title := label(peer, 17)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title)
	ping_label = label(_ping_text(), 12, pal()["muted"])
	ping_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(ping_label)
	top.add_child(spacer())
	top.add_child(ghost_button(Loc.t("chat_delete"), func() -> void:
		_confirm_delete()))
	column.add_child(top)

	# --- сообщения ---
	messages_box = vbox(10)
	scroller = scroll()
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("margin_right", 8)
	holder.add_child(messages_box)
	scroller.add_child(holder)
	column.add_child(scroller)

	fill_messages()

	# --- поле ввода ---
	var bottom := hbox(10)
	input = LineEdit.new()
	input.placeholder_text = Loc.t("chat_placeholder")
	input.custom_minimum_size = Vector2(0, 48)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(func(_text: String) -> void: send())
	bottom.add_child(input)
	bottom.add_child(accent_button(Loc.t("chat_send"), func() -> void: send()))
	column.add_child(bottom)

	note_label = hint(_note_text(), 12)
	column.add_child(note_label)
	input.grab_focus()

## ------------------------------------------------------------- сообщения

func fill_messages() -> void:
	for child in messages_box.get_children():
		child.queue_free()

	var list := Store.messages(peer)
	if list.is_empty():
		var empty := hint(Loc.t("chat_empty"), 14)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 20, pal()["line"], 1, 26))
		panel.add_child(empty)
		messages_box.add_child(panel)
		return

	for message in list:
		messages_box.add_child(message_row(message))

## Одно сообщение: пузырь слева (собеседник) или справа (моё)
func message_row(message: Dictionary) -> Control:
	var p := pal()
	var mine := bool(message.get("mine", true))
	var text := String(message.get("text", ""))

	var row := hbox(0)
	if mine:
		row.add_child(spacer())

	var bubble := PanelContainer.new()
	var radius := 18
	var fill: Color = p["a1"].lerp(p["a2"], 0.25) if mine else p["panel_strong"]
	var border: Color = Color(0, 0, 0, 0) if mine else p["line"]
	bubble.add_theme_stylebox_override("panel", UiStyle.box(fill, radius, border, 1, 12))

	var body := vbox(4)
	var message_label := label(text, 15, Color("#04121b") if mine else p["text"], true)
	# Ширина пузыря зависит от длины текста, чтобы короткие сообщения не растягивались
	message_label.custom_minimum_size = Vector2(clampf(float(text.length()) * 8.4 + 28.0, 56.0, 420.0), 0)
	message_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(message_label)

	var time_label := label(Store.format_time(int(message.get("ts", 0))), 11, Color(0, 0, 0, 0.55) if mine else p["muted"])
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body.add_child(time_label)

	bubble.add_child(body)
	row.add_child(bubble)

	if not mine:
		row.add_child(spacer())
	return row

func scroll_to_bottom() -> void:
	if scroller == null:
		return
	await get_tree().process_frame
	scroller.scroll_vertical = int(scroller.get_v_scroll_bar().max_value)

## ------------------------------------------------------------- действия

func send() -> void:
	if input == null:
		return
	if app().send_message(peer, input.text):
		input.text = ""
		# data_changed уже попросил перерисовать экран; прокрутим вниз после перерисовки

func _confirm_delete() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.theme = UiStyle.build(Store.theme())
	dialog.dialog_text = Loc.tf("chat_delete_confirm", [peer])
	dialog.title = Loc.t("chat_delete")
	dialog.ok_button_text = Loc.t("delete")
	dialog.cancel_button_text = Loc.t("cancel")
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		Store.delete_history(peer)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
