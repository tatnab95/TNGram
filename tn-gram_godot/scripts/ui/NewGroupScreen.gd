extends ScreenBase
## Экран «Новая группа»: название и галочки напротив нужных людей.

var title_field: LineEdit
var error_code := ""
var selected: Array = []   ## ники, отмеченные галочкой (в порядке отметки)

func _ready() -> void:
	build()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	build()

func build() -> void:
	var scroller := scroll()
	scroller.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroller)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", PAD)
	margin.add_theme_constant_override("margin_right", PAD)
	margin.add_theme_constant_override("margin_top", PAD)
	margin.add_theme_constant_override("margin_bottom", PAD)
	scroller.add_child(margin)

	var outer := vbox(0)
	margin.add_child(outer)

	var row := hbox(0)
	outer.add_child(row)
	row.add_child(spacer())
	var column := vbox(12)
	column.custom_minimum_size = Vector2(440, 0)
	row.add_child(column)
	row.add_child(spacer())

	# --- верхняя строка ---
	var top := hbox(12)
	column.add_child(top)
	top.add_child(ghost_button(Loc.t("back"), func() -> void:
		navigate.emit("chats", null)))
	top.add_child(spacer())

	# --- заголовок ---
	var head := vbox(4)
	head.add_child(heading(Loc.t("group_title"), 26))
	column.add_child(head)

	var name_box := vbox(6)
	column.add_child(label(Loc.t("group_name"), 13, pal()["muted"]))
	title_field = LineEdit.new()
	title_field.placeholder_text = Loc.t("newgroup_name_hint")
	title_field.custom_minimum_size = Vector2(0, 46)
	column.add_child(title_field)

	if error_code != "":
		column.add_child(label(Loc.t("err_group_members") if error_code == "err_group_members" else Loc.t(error_code), 14, Color("#ff9a9a")))

	var people := Store.contacts()
	var pick := PanelContainer.new()
	pick.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 18, pal()["line"], 1, 16))
	var pick_box := vbox(8)
	pick_box.add_child(label(Loc.t("newgroup_who"), 14))
	pick_box.add_child(hint(Loc.t("newgroup_hint"), 12))
	if people.is_empty():
		pick_box.add_child(hint(Loc.t("newgroup_nobody"), 13))
	else:
		for peer in people:
			pick_box.add_child(member_row(peer))
	pick.add_child(pick_box)
	column.add_child(pick)

	var create := accent_button(Loc.t("newgroup_create"), func() -> void: _create())
	column.add_child(create)

	var back := ghost_button(Loc.t("back"), func() -> void:
		navigate.emit("chats", null))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(back)

	if title_field != null:
		title_field.grab_focus()

## Строка с человеком: кружок, ник и галочка
func member_row(nick: String) -> Control:
	var row := hbox(10)
	row.add_child(avatar(nick, 34, Store.is_online(nick)))
	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = selected.has(nick)
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 40)
	button.text = ("✓  " + nick) if selected.has(nick) else ("•  " + nick)
	button.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0), 12, pal()["line"], 1, 8))
	button.add_theme_stylebox_override("hover", UiStyle.box(pal()["panel_strong"], 12, pal()["a2"], 1, 8))
	button.add_theme_stylebox_override("pressed", UiStyle.box(pal()["panel_strong"], 12, pal()["a2"], 1, 8))
	button.add_theme_stylebox_override("focus", UiStyle.box(Color(0, 0, 0, 0), 12, Color(0, 0, 0, 0), 0, 8))
	button.toggled.connect(func(on: bool) -> void:
		button.text = ("✓  " + nick) if on else ("•  " + nick)
		if on and not selected.has(nick):
			selected.append(nick)
		elif not on:
			selected.erase(nick))
	row.add_child(button)
	return row

## ------------------------------------------------------------- действия

func _create() -> void:
	var title := title_field.text if title_field != null else ""
	var result := Store.create_group(title, selected)
	if not bool(result.get("ok", false)):
		error_code = String(result.get("error", ""))
		rebuild()
		return
	var key := String(result.get("key", ""))
	navigate.emit("chat", key)
