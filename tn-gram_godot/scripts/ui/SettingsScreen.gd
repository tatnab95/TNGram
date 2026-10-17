extends ScreenBase
## Настройки: язык, тема, связь, аккаунт, удаление аккаунта, о приложении.

const P := preload("res://scripts/net/Protocol.gd")

var address_field: LineEdit
var connect_button: Button
var auto_check: CheckButton
var status_label: Label

func _ready() -> void:
	build()
	if not Net.changed.is_connected(net_changed):
		Net.changed.connect(net_changed)

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	build()

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
	top.add_child(spacer())
	column.add_child(top)

	var head := vbox(4)
	head.add_child(heading(Loc.t("settings"), 30))
	column.add_child(head)

	var scroller := scroll()
	var list := vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(list)
	column.add_child(scroller)

	# --- язык ---
	var lang_buttons := hbox(8)
	for code in ["ru", "en"]:
		lang_buttons.add_child(toggle_button(code.to_upper(), Loc.lang == code, func() -> void:
			Store.set_lang(code)
			Loc.lang = code
			app().rebuild()))
	list.add_child(settings_row(Loc.t("settings_lang"), lang_buttons))

	# --- тема ---
	var theme_buttons := hbox(8)
	for theme_id in ["dark", "green", "blue"]:
		theme_buttons.add_child(toggle_button(Loc.t("theme_" + theme_id), Store.theme() == theme_id, func() -> void:
			Store.set_theme(theme_id)
			app().rebuild()))
	list.add_child(settings_row(Loc.t("settings_theme"), theme_buttons))

	# --- связь ---
	list.add_child(net_block())

	# --- аккаунт ---
	list.add_child(settings_row(Loc.t("settings_account"), label(Store.current_nick, 15)))

	# --- удаление аккаунта ---
	var danger := ghost_button(Loc.t("settings_delete_account"), func() -> void: _confirm_delete_account())
	danger.add_theme_color_override("font_color", Color("#ff8f8f"))
	danger.add_theme_color_override("font_hover_color", Color("#ff6b6b"))
	list.add_child(settings_row("", danger))

	# --- о приложении ---
	var about := PanelContainer.new()
	about.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 18, pal()["line"], 1, 16))
	var about_box := vbox(8)
	about_box.add_child(label(Loc.t("settings_about"), 15))
	about_box.add_child(hint(Loc.t("settings_about_text"), 13))
	about_box.add_child(accent_label(Loc.t("settings_soon_server"), 13, true))
	about.add_child(about_box)
	list.add_child(about)

## ------------------------------------------------------------- связь

## Блок «Связь»: адрес сервера, подключение, автоматический вход на связь
func net_block() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 18, pal()["line"], 1, 16))

	var box := vbox(10)
	box.add_child(label(Loc.t("net"), 15))

	var address_row := hbox(10)
	address_field = LineEdit.new()
	address_field.text = "%s:%d" % [Store.relay_host(), Store.relay_port()]
	address_field.placeholder_text = Loc.t("net_host_hint")
	address_field.custom_minimum_size = Vector2(0, 42)
	address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_row.add_child(address_field)
	connect_button = accent_button(connect_text(), func() -> void: _toggle_connection())
	address_row.add_child(connect_button)
	box.add_child(address_row)

	var auto_row := hbox(8)
	auto_check = CheckButton.new()
	auto_check.button_pressed = Store.relay_auto()
	auto_check.focus_mode = Control.FOCUS_NONE
	auto_check.toggled.connect(func(on: bool) -> void: _save_relay(on))
	auto_row.add_child(auto_check)
	var auto_label := label(Loc.t("net_auto"), 14)
	auto_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	auto_row.add_child(auto_label)
	auto_row.add_child(spacer())
	box.add_child(auto_row)

	status_label = hint(Net.status_text(), 13)
	box.add_child(status_label)

	panel.add_child(box)
	apply_net_state()
	return panel

func connect_text() -> String:
	return Loc.t("net_disconnect") if Net.is_online() else Loc.t("net_connect")

## Состояние связи изменилось — обновляем подпись и кнопку, не трогая введённый адрес
func net_changed() -> void:
	apply_net_state()

func apply_net_state() -> void:
	if status_label != null and is_instance_valid(status_label):
		status_label.text = Net.status_text()
		var color: Color = pal()["muted"]
		if Net.is_online():
			color = pal()["a2"]
		elif Net.is_connecting():
			color = pal()["text"]
		status_label.add_theme_color_override("font_color", color)
	if connect_button != null and is_instance_valid(connect_button):
		connect_button.text = connect_text()

## Подключиться к введённому адресу или отключиться
func _toggle_connection() -> void:
	if Net.is_online():
		Net.stop()
		return
	var address := _address_from_field()
	if not bool(address["ok"]):
		status_label.text = Loc.t("net_bad_address")
		status_label.add_theme_color_override("font_color", Color("#ff8f8f"))
		return
	Store.set_relay(String(address["host"]), int(address["port"]), Store.relay_auto())
	Net.connect_to(String(address["host"]), int(address["port"]), Store.current_nick)
	apply_net_state()

## Запомнить галочку «подключаться при входе»
func _save_relay(auto: bool) -> void:
	var address := _address_from_field()
	if bool(address["ok"]):
		Store.set_relay(String(address["host"]), int(address["port"]), auto)
	else:
		Store.set_relay(Store.relay_host(), Store.relay_port(), auto)
	if auto:
		app().maybe_connect()

## Разобрать «адрес:порт» из поля
func _address_from_field() -> Dictionary:
	var raw := address_field.text.strip_edges()
	if raw == "":
		return { "ok": false }
	# start.bat печатает адрес с префиксом ws:// — принимаем и его, и голый «адрес:порт»
	for scheme in ["ws://", "wss://", "tcp://"]:
		if raw.to_lower().begins_with(scheme):
			raw = raw.substr(scheme.length()).strip_edges()
	raw = raw.trim_suffix("/").strip_edges()
	var host := raw
	var port := P.DEFAULT_PORT
	var cut := raw.rfind(":")
	if cut > 0:
		host = raw.substr(0, cut).strip_edges()
		var port_text := raw.substr(cut + 1).strip_edges()
		if not port_text.is_valid_int():
			return { "ok": false }
		port = int(port_text)
	if host == "" or port <= 0 or port > 65535:
		return { "ok": false }
	return { "ok": true, "host": host, "port": port }

func _confirm_delete_account() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.theme = UiStyle.build(Store.theme())
	dialog.dialog_text = Loc.tf("settings_delete_confirm", [Store.current_nick])
	dialog.title = Loc.t("settings_delete_account")
	dialog.ok_button_text = Loc.t("delete")
	dialog.cancel_button_text = Loc.t("cancel")
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		Store.delete_account(Store.current_nick)
		dialog.queue_free()
		navigate.emit("login", null))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
