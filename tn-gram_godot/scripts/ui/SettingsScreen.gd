extends ScreenBase
## Настройки: язык, тема, связь, аккаунт, удаление аккаунта, о приложении.

var address_field: LineEdit
var key_field: LineEdit
var connect_button: Button
var auto_check: CheckButton
var status_label: Label
var update_status: Label  ## ответ проверки обновлений

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

	# --- сглаживание ---
	list.add_child(graphics_block())

	# --- звук ---
	list.add_child(sound_block())

	# --- уведомления ---
	list.add_child(notify_block())

	# --- связь ---
	list.add_child(net_block())

	# --- обновления ---
	list.add_child(update_block())

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
	var about_row := hbox(12)
	about_row.add_child(label(Loc.t("settings_about"), 15))
	about_row.add_child(spacer())
	about_row.add_child(hint(Loc.tf("settings_version", [P.APP_VERSION]), 13))
	about_box.add_child(about_row)
	about_box.add_child(hint(Loc.t("settings_about_text"), 13))
	about_box.add_child(accent_label(Loc.t("settings_soon_server"), 13, true))
	var news_row := hbox(10)
	news_row.add_child(ghost_button(Loc.t("settings_news"), func() -> void:
		navigate.emit("news", null)))
	var update := Store.update_available()
	if update != "":
		news_row.add_child(accent_label(Loc.tf("news_update_badge", [update]), 13, true))
	about_box.add_child(news_row)
	about.add_child(about_box)
	list.add_child(about)

## ------------------------------------------------------------- обновления

## Проверка обновлений: что установлено, кнопка и понятный ответ.
## Человек сам решает, когда проверять — но новая версия видна сразу.
func update_block() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 18, pal()["line"], 1, 16))
	var box := vbox(10)
	var row := hbox(12)
	row.add_child(label(Loc.t("update_check"), 15))
	row.add_child(spacer())
	row.add_child(hint(Loc.tf("settings_version", [P.APP_VERSION]), 13))
	box.add_child(row)
	update_status = hint(_update_status_text(), 13)
	box.add_child(update_status)
	var buttons := hbox(10)
	buttons.add_child(ghost_button(Loc.t("update_check"), func() -> void: _check_updates()))
	if Store.update_available() != "":
		buttons.add_child(accent_button(Loc.t("update_get"), func() -> void:
			app().open_update()))
	box.add_child(buttons)
	panel.add_child(box)
	return panel

func _update_status_text() -> String:
	var fresh := Store.update_available()
	if fresh != "":
		return Loc.tf("update_available", [fresh])
	return Loc.tf("update_latest", [P.APP_VERSION])

## Спросить у сайта и облака, не вышла ли новая версия, и показать ответ
func _check_updates() -> void:
	if update_status != null and is_instance_valid(update_status):
		update_status.text = Loc.t("update_checking")
	app().check_update(true, func(_remote: String) -> void:
		if is_inside_tree():
			rebuild())

## ------------------------------------------------------------- сглаживание

## Качество картинки: сглаживание текста и (где умеет видеокарта) фигур.
func graphics_block() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 18, pal()["line"], 1, 16))

	var box := vbox(10)
	box.add_child(label(Loc.t("settings_graphics"), 15))

	var buttons := hbox(8)
	for level in [0, 1, 2, 3]:
		buttons.add_child(toggle_button(Loc.t("aa_%d" % level), Store.aa_level() == level, func() -> void:
			Store.set_aa(level)
			app().rebuild()))
	box.add_child(buttons)

	box.add_child(hint(Loc.t("settings_graphics_hint"), 12))
	if not UiStyle.shapes_aa_supported():
		box.add_child(hint(Loc.t("settings_graphics_simple"), 12))

	panel.add_child(box)
	return panel

## ------------------------------------------------------------- звук

func sound_block() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 18, pal()["line"], 1, 16))

	var box := vbox(10)
	box.add_child(label(Loc.t("settings_sound"), 15))

	var on_row := hbox(8)
	var check := CheckButton.new()
	check.button_pressed = Store.sound_on()
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void:
		Store.set_sound(on)
		if on:
			Sfx.play("incoming"))
	on_row.add_child(check)
	var on_label := label(Loc.t("settings_sound_on"), 14)
	on_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	on_row.add_child(on_label)
	on_row.add_child(spacer())
	box.add_child(on_row)

	var volume_row := hbox(10)
	var volume_label := label(Loc.t("settings_sound_volume"), 14)
	volume_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume_row.add_child(volume_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Store.sound_volume()
	slider.custom_minimum_size = Vector2(180, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(value: float) -> void:
		Store.set_sound_volume(value))
	slider.drag_ended.connect(func(_changed: bool) -> void:
		Sfx.play("incoming"))
	volume_row.add_child(spacer())
	volume_row.add_child(slider)
	box.add_child(volume_row)

	panel.add_child(box)
	return panel

## ------------------------------------------------------------- уведомления

func notify_block() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 18, pal()["line"], 1, 16))

	var box := vbox(10)
	box.add_child(label(Loc.t("settings_notify"), 15))

	var row := hbox(8)
	var check := CheckButton.new()
	check.button_pressed = Store.notify_on()
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void:
		Store.set_notify(on))
	row.add_child(check)
	var on_label := label(Loc.t("settings_notify_on"), 14)
	on_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(on_label)
	row.add_child(spacer())
	box.add_child(row)
	box.add_child(hint(Loc.t("settings_notify_hint"), 12))

	# Системные уведомления: на Windows их видно, даже когда окно свёрнуто;
	# на телефоне они появляются в шторке.
	if OS.has_feature("windows") or OS.has_feature("android"):
		var os_row := hbox(8)
		var os_check := CheckButton.new()
		os_check.name = "NotifyOs"
		os_check.button_pressed = Store.notify_os()
		os_check.focus_mode = Control.FOCUS_NONE
		os_check.toggled.connect(func(on: bool) -> void:
			Store.set_notify_os(on))
		os_row.add_child(os_check)
		var os_key := "settings_notify_os_android" if OS.has_feature("android") else "settings_notify_os"
		var os_label := label(Loc.t(os_key), 14)
		os_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		os_row.add_child(os_label)
		os_row.add_child(spacer())
		box.add_child(os_row)
		box.add_child(hint(Loc.t(os_key + "_hint"), 12))

	panel.add_child(box)
	return panel

## ------------------------------------------------------------- связь

## Блок «Связь»: адрес сервера, подключение, автоматический вход на связь
func net_block() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 18, pal()["line"], 1, 16))

	var box := vbox(10)
	box.add_child(label(Loc.t("net"), 15))

	var address_row := hbox(10)
	address_field = LineEdit.new()
	address_field.text = Store.relay_host() if P.is_cloud(Store.relay_host()) \
		else "%s:%d" % [Store.relay_host(), Store.relay_port()]
	address_field.placeholder_text = Loc.t("net_host_hint")
	address_field.custom_minimum_size = Vector2(0, 42)
	address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_row.add_child(address_field)
	connect_button = accent_button(connect_text(), func() -> void: _toggle_connection())
	address_row.add_child(connect_button)
	box.add_child(address_row)

	# Ключ облачного проекта. Нужен только для облака, но пусть будет всегда —
	# так меньше путаницы: вставил адрес и ключ, нажал «Подключиться».
	key_field = LineEdit.new()
	key_field.text = Store.relay_key()
	key_field.placeholder_text = Loc.t("net_key_hint")
	key_field.custom_minimum_size = Vector2(0, 42)
	key_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(key_field)

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
	Store.set_relay(String(address["host"]), int(address["port"]), Store.relay_auto(), _key_from_field())
	Net.connect_to(String(address["host"]), int(address["port"]), Store.current_nick, _key_from_field())
	apply_net_state()

## Запомнить галочку «подключаться при входе»
func _save_relay(auto: bool) -> void:
	var address := _address_from_field()
	if bool(address["ok"]):
		Store.set_relay(String(address["host"]), int(address["port"]), auto, _key_from_field())
	else:
		Store.set_relay(Store.relay_host(), Store.relay_port(), auto, _key_from_field())
	if auto:
		app().maybe_connect()

func _key_from_field() -> String:
	return key_field.text.strip_edges() if key_field != null else ""

## Разобрать адрес из поля: «адрес:порт» для своего сервера или
## «https://проект.supabase.co» для облака.
func _address_from_field() -> Dictionary:
	var raw := address_field.text.strip_edges()
	if raw == "":
		return { "ok": false }
	# Адрес облака: приводим привычные «ws://»/«wss://» к «https://»
	if P.is_cloud(raw):
		var url := raw
		if url.to_lower().begins_with("wss://"):
			url = "https://" + url.substr(6)
		elif url.to_lower().begins_with("ws://"):
			url = "http://" + url.substr(5)
		url = url.trim_suffix("/").strip_edges()
		if url == "":
			return { "ok": false }
		return { "ok": true, "host": url, "port": P.DEFAULT_PORT, "cloud": true }
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
