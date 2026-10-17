extends ScreenBase
## Экран создания ника: имя + необязательный пароль. Номер телефона не нужен.

var error_code := ""

func _ready() -> void:
	build()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	build()

func build() -> void:
	# Прокрутка — на случай маленького окна
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
	outer.add_child(vspacer())

	var row := hbox(0)
	outer.add_child(row)
	row.add_child(spacer())

	var column := vbox(14)
	column.custom_minimum_size = Vector2(440, 0)
	row.add_child(column)
	row.add_child(spacer())

	outer.add_child(vspacer())

	# Заголовок
	var title := heading(Loc.t("new_title"), 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var sub := hint(Loc.t("new_subtitle"), 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	column.add_child(gap(8))

	# Поля
	var nick_pair := text_field(Loc.t("new_nick"), Loc.t("new_nick_hint"), false)
	column.add_child(nick_pair[0])
	var pass_pair := text_field(Loc.t("new_password"), Loc.t("new_password_hint"), true)
	column.add_child(pass_pair[0])
	var repeat_pair := text_field(Loc.t("new_password_repeat"), "", true)
	column.add_child(repeat_pair[0])

	var nick_edit: LineEdit = nick_pair[1]
	var pass_edit: LineEdit = pass_pair[1]
	var repeat_edit: LineEdit = repeat_pair[1]

	# Ошибка
	if error_code != "":
		column.add_child(label(Loc.t(error_code), 14, Color("#ff9a9a")))

	# Кнопка создания
	var submit := accent_button(Loc.t("new_submit"), func() -> void:
		_submit(nick_edit.text, pass_edit.text, repeat_edit.text))
	column.add_child(submit)

	var back := ghost_button(Loc.t("back"), func() -> void:
		navigate.emit("login", null))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(back)

	column.add_child(gap(4))
	column.add_child(hint(Loc.t("new_no_password_note"), 13))

	nick_edit.grab_focus()

## ------------------------------------------------------------- действия

func _submit(nick: String, password: String, repeat: String) -> void:
	if password != repeat:
		error_code = "err_pass_mismatch"
		rebuild()
		return

	var result := Store.create_account(nick, password)
	if not bool(result.get("ok", false)):
		error_code = String(result.get("error", ""))
		rebuild()
		return

	var login_result := Store.login(nick, password)
	if bool(login_result.get("ok", false)):
		navigate.emit("chats", null)
		return
	error_code = String(login_result.get("error", ""))
	rebuild()

## ------------------------------------------------------------- вспомогательное

func gap(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node

## Подпись + поле ввода. Возвращает [контейнер, поле]
func text_field(caption: String, placeholder: String, secret: bool) -> Array:
	var box := vbox(6)
	box.add_child(label(caption, 13, pal()["muted"]))

	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.custom_minimum_size = Vector2(0, 46)
	box.add_child(edit)

	return [box, edit]
