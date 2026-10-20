extends ScreenBase
## Экран переписки: аккуратные пузыри, шапка чата на отдельной панели,
## своя панель ввода внизу и кнопка «вниз» для длинных переписок.
## Собеседник «ИИ-помощник» — локальный: отвечает сам, интернет не нужен.

var peer := ""
var messages_box: VBoxContainer
var scroller: ScrollContainer
var input: LineEdit
var note_label: Label
var ping_label: Label
var status_label: Label  ## «в сети» / «был(а) 5 мин назад» / «участников: 3» / «печатает…»
var down_button: Button  ## «вниз»: появляется, когда поднялись выше последних сообщений
var _typing := false     ## ИИ сейчас печатает ответ
var _rendered := 0       ## сколько сообщений уже нарисовано (для появления новых)

func _ready() -> void:
	Store.mark_read(peer)
	build()
	if not Store.data_changed.is_connected(_on_data_changed):
		Store.data_changed.connect(_on_data_changed)
	if not Store.presence_changed.is_connected(_on_presence_changed):
		Store.presence_changed.connect(_on_presence_changed)
	if not Net.changed.is_connected(net_changed):
		Net.changed.connect(net_changed)
	await get_tree().process_frame
	scroll_to_bottom()

## Кто-то появился в сети — меняем только подпись, печатать не мешаем
func _on_presence_changed() -> void:
	_paint_status()

func _on_data_changed() -> void:
	if not is_inside_tree():
		return
	if messages_box == null or not is_instance_valid(messages_box):
		rebuild()
		return
	# Пришло новое сообщение — обновляем только список. Полная перерисовка
	# стёрла бы текст, который человек печатает прямо сейчас, и сбила бы курсор.
	Store.mark_read(peer)
	if P.is_ai_key(peer) and not _last_is_mine():
		_typing = false
	fill_messages()
	_paint_status()
	await get_tree().process_frame
	scroll_to_bottom()

## Последнее сообщение чата — своё? (пустой чат = своё, «печатать» не мешаем)
func _last_is_mine() -> bool:
	var list := Store.messages(peer)
	if list.is_empty():
		return true
	return bool((list[list.size() - 1] as Dictionary).get("mine", true))

## Состояние связи изменилось — обновляем только подписи, не трогая ввод
func net_changed() -> void:
	if not P.is_ai_key(peer):
		if note_label != null and is_instance_valid(note_label):
			note_label.text = _note_text()
		if ping_label != null and is_instance_valid(ping_label):
			ping_label.text = _ping_text()
	_paint_status()

## Название чата: для ИИ — его имя, для группы — её имя, для человека — ник
func title_text() -> String:
	if P.is_ai_key(peer):
		return Loc.t("ai_title")
	return Store.peer_title(peer)

## Вторая строка в шапке: у группы — сколько людей, у человека — «в сети»
## или «был(а)…», у ИИ — подпись «печатает…», пока он готовит ответ
func _status_line() -> String:
	if P.is_ai_key(peer):
		return Loc.t("ai_typing") if _typing else Loc.t("ai_status")
	if Store.is_group(peer):
		return Loc.tf("group_members_count", [str(Store.group_roster(peer).size())])
	return status_text(peer)

## Подпись и цвет второй строки шапки
func _paint_status() -> void:
	if status_label == null or not is_instance_valid(status_label):
		return
	status_label.text = _status_line()
	var p := pal()
	var color: Color = p["muted"]
	if _typing or P.is_ai_key(peer) or (not Store.is_group(peer) and Store.is_online(peer)):
		color = p["a2"]
	status_label.add_theme_color_override("font_color", color)

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
	var is_ai := P.is_ai_key(peer)
	var p := pal()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAD)
	margin.add_theme_constant_override("margin_right", PAD)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var column := vbox(10)
	margin.add_child(column)

	# --- шапка: кнопка «назад», аватар, имя со статусом, пинг и удаление ---
	var group := Store.is_group(peer)
	var top := hbox(10)
	top.add_child(ghost_button(Loc.t("back"), func() -> void:
		navigate.emit("chats", null)))
	top.add_child(avatar(title_text(), 40, not group and not is_ai and Store.is_online(peer)))
	var names := vbox(0)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := label(title_text(), 16)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(title)
	status_label = hint(_status_line(), 12)
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(status_label)
	top.add_child(names)
	if not is_ai:
		ping_label = hint(_ping_text(), 11)
		ping_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(ping_label)
	top.add_child(ghost_button(Loc.t("chat_delete"), func() -> void:
		_confirm_delete()))
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiStyle.box(p["panel"], 20, p["line"], 1, 8))
	head.add_child(top)
	column.add_child(head)
	_paint_status()

	# --- сообщения ---
	messages_box = vbox(8)
	scroller = scroll()
	scroller.get_v_scroll_bar().value_changed.connect(_sync_down_button)
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("margin_right", 6)
	holder.add_child(messages_box)
	scroller.add_child(holder)

	# Сообщения и кнопка «вниз» на одном «подиуме»: кнопка висит в углу
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(scroller)
	scroller.set_anchors_preset(Control.PRESET_FULL_RECT)
	down_button = Button.new()
	down_button.text = "↓"
	down_button.focus_mode = Control.FOCUS_NONE
	down_button.custom_minimum_size = Vector2(44, 44)
	down_button.anchor_left = 1.0
	down_button.anchor_right = 1.0
	down_button.anchor_top = 1.0
	down_button.anchor_bottom = 1.0
	down_button.offset_left = -54
	down_button.offset_right = -10
	down_button.offset_top = -54
	down_button.offset_bottom = -10
	down_button.add_theme_stylebox_override("normal", UiStyle.box(p["panel_strong"], 999, p["a2"], 1, 10))
	down_button.add_theme_stylebox_override("hover", UiStyle.box(p["a1"] * Color(1, 1, 1, 0.4), 999, p["a2"], 1, 10))
	down_button.add_theme_stylebox_override("pressed", UiStyle.box(p["a1"], 999, p["a2"], 1, 10))
	down_button.add_theme_stylebox_override("focus", UiStyle.box(Color(0, 0, 0, 0), 999, Color(0, 0, 0, 0), 0, 10))
	down_button.pressed.connect(func() -> void: scroll_to_bottom())
	down_button.visible = false
	stage.add_child(down_button)
	column.add_child(stage)

	fill_messages()

	# --- панель ввода: заметка про связь и строка «поле + отправить» ---
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.box(p["panel"], 22, p["line"], 1, 8))
	var inner := vbox(6)
	note_label = hint(Loc.t("ai_note") if is_ai else _note_text(), 11)
	note_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	note_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inner.add_child(note_label)
	var bottom := hbox(8)
	input = LineEdit.new()
	input.placeholder_text = Loc.t("chat_placeholder")
	input.custom_minimum_size = Vector2(0, 46)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(func(_text: String) -> void: send())
	# Поле ввода — скруглённое «таблеткой», как в больших мессенджерах
	input.add_theme_stylebox_override("normal", UiStyle.box(Color(1, 1, 1, 0.05), 999, p["line"], 1, 12))
	input.add_theme_stylebox_override("focus", UiStyle.box(Color(1, 1, 1, 0.07), 999, p["a2"] * Color(1, 1, 1, 0.6), 1, 12))
	bottom.add_child(input)
	bottom.add_child(accent_button(Loc.t("chat_send"), func() -> void: send()))
	inner.add_child(bottom)
	bar.add_child(inner)
	column.add_child(bar)

	input.grab_focus()
	await get_tree().process_frame
	_sync_down_button()

## ------------------------------------------------------------- сообщения

func fill_messages() -> void:
	var old_count := _rendered
	for child in messages_box.get_children():
		child.queue_free()
	_rendered = 0

	var list: Array = Store.messages(peer)
	if list.is_empty():
		var hint_key := "ai_empty" if P.is_ai_key(peer) else ("group_invite_hint" if Store.is_group(peer) else "chat_empty")
		var empty := hint(Loc.t(hint_key), 14)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 20, pal()["line"], 1, 26))
		panel.add_child(empty)
		messages_box.add_child(panel)
		return

	# Разделители по дням: «Сегодня», «Вчера», «18.10.2026»
	var group := Store.is_group(peer)
	var last_day := ""
	var index := 0
	for message in list:
		var ts := int((message as Dictionary).get("ts", 0))
		var day := Time.get_date_string_from_unix_time(ts) if ts > 0 else ""
		if day != "" and day != last_day:
			last_day = day
			var sep := date_separator(day_text(ts))
			messages_box.add_child(sep)
			if index >= old_count:
				Anim.fade_in(sep, 0.14)
		messages_box.add_child(message_row(message))
		# Сообщения, которых ещё не было в прошлый раз, проступают мягко;
		# старые не мигают при каждой перерисовке.
		if index >= old_count:
			Anim.fade_in(messages_box.get_child(messages_box.get_child_count() - 1), 0.15)
		index += 1
	_rendered = index

## Одно сообщение: пузырь слева (собеседник) или справа (моё)
func message_row(message: Dictionary) -> Control:
	var p := pal()
	var mine := bool(message.get("mine", true))
	var text := String(message.get("text", ""))
	var is_ai := P.is_ai_key(peer)

	var row := hbox(0)
	if mine:
		row.add_child(spacer())

	var bubble := PanelContainer.new()
	# Свои — градиент акцента, чужие — стеклянный; у ИИ обводка зелёная
	var line_color: Color = p["a2"] * Color(1, 1, 1, 0.45) if is_ai and not mine else p["line"]
	bubble.add_theme_stylebox_override("panel",
		UiStyle.bubble_box(mine, p["a1"], p["a1"].lerp(p["a2"], 0.45), p["panel_strong"], line_color))

	var body := vbox(2)
	# В группе подписываем, кто написал (в своих пузырях подпись не нужна)
	var author := String(message.get("from", ""))
	if not mine and author != "" and Store.is_group(peer):
		var author_label := label(author, 11, p["a2"])
		author_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		body.add_child(author_label)
	var message_label := label(text, 15, Color("#f7fbff") if mine else p["text"], true)
	# Ширина пузыря зависит от длины текста и не вылезает за пределы экрана
	var max_width := clampf(get_viewport_rect().size.x * 0.76, 200.0, 430.0)
	message_label.custom_minimum_size = Vector2(clampf(float(text.length()) * 8.4 + 30.0, 60.0, max_width), 0)
	message_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(message_label)

	var time_label := label(Store.format_time(int(message.get("ts", 0))), 10,
		Color(1, 1, 1, 0.72) if mine else p["muted"])
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body.add_child(time_label)

	bubble.add_child(body)
	row.add_child(bubble)

	if not mine:
		row.add_child(spacer())
	return row

func scroll_to_bottom() -> void:
	if scroller == null or not is_instance_valid(scroller):
		return
	await get_tree().process_frame
	if scroller == null or not is_instance_valid(scroller):
		return
	scroller.scroll_vertical = int(scroller.get_v_scroll_bar().max_value)
	_sync_down_button()

## Кнопка «вниз» видна только когда поднялись выше последних сообщений
func _sync_down_button() -> void:
	if down_button == null or not is_instance_valid(down_button) or scroller == null:
		return
	var bar := scroller.get_v_scroll_bar()
	down_button.visible = bar.max_value > 0.0 and bar.value < bar.max_value - 40.0

## ------------------------------------------------------------- действия

func send() -> void:
	if input == null:
		return
	if app().send_message(peer, input.text):
		input.text = ""
		# data_changed уже попросил перерисовать экран
		if P.is_ai_key(peer):
			# Ответ приедет чуть позже (см. Main._ai_reply_later)
			_typing = true
			_paint_status()
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(14)
		# data_changed уже попросил перерисовать экран; прокрутим вниз после перерисовки

func _confirm_delete() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.theme = UiStyle.build(Store.theme())
	dialog.dialog_text = Loc.tf("chat_delete_confirm", [title_text()])
	dialog.title = Loc.t("chat_delete")
	dialog.ok_button_text = Loc.t("delete")
	dialog.cancel_button_text = Loc.t("cancel")
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		Store.delete_history(peer)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
