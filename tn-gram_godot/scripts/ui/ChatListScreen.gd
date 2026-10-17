extends ScreenBase
## Список чатов: другие аккаунты на этом устройстве + переход в переписку.

func _ready() -> void:
	build()
	if not Store.data_changed.is_connected(_on_data_changed):
		Store.data_changed.connect(_on_data_changed)
	if not Net.changed.is_connected(_on_net_changed):
		Net.changed.connect(_on_net_changed)

func _on_data_changed() -> void:
	if is_inside_tree():
		rebuild()

func _on_net_changed() -> void:
	if is_inside_tree():
		rebuild()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	build()

func build() -> void:
	var card := vbox(16)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAD)
	margin.add_theme_constant_override("margin_right", PAD)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	margin.add_child(card)

	# --- верхняя строка: кто вошёл и кнопки ---
	var top := hbox(12)
	top.add_child(avatar(Store.current_nick, 40))
	var who := vbox(0)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(label(Store.current_nick, 15))
	who.add_child(hint(Loc.t("chats_you"), 12))
	top.add_child(who)
	top.add_child(spacer())
	top.add_child(ghost_button(Loc.t("chats_new_nick"), func() -> void:
		navigate.emit("new", null)))
	top.add_child(ghost_button(Loc.t("settings"), func() -> void:
		navigate.emit("settings", null)))
	card.add_child(top)

	# --- заголовок ---
	var head := vbox(4)
	head.add_child(heading(Loc.t("chats_title"), 30))
	head.add_child(hint(Loc.t("chats_on_device"), 13))
	var net_line := hint(Net.status_text(), 12)
	net_line.add_theme_color_override("font_color", pal()["a2"] if Net.is_online() else pal()["muted"])
	head.add_child(net_line)
	card.add_child(head)

	# --- список собеседников ---
	var list := vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var peers := Store.contacts()

	if peers.is_empty():
		var empty := hint(Loc.t("chats_empty"), 14)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var empty_panel := PanelContainer.new()
		empty_panel.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 20, pal()["line"], 1, 28))
		empty_panel.add_child(empty)
		list.add_child(empty_panel)
	else:
		for peer in peers:
			var last: Dictionary = Store.last_message(peer)
			var preview := Loc.t("chats_no_messages")
			var time_text := ""
			if not last.is_empty():
				preview = String(last.get("text", ""))
				time_text = Store.format_time(int(last.get("ts", 0)))
			elif not Store.account_exists(peer):
				preview = Loc.t("chats_remote")
			list.add_child(contact_button(peer, preview, time_text, func() -> void:
				navigate.emit("chat", peer)))

	var scroller := scroll()
	scroller.add_child(list)
	card.add_child(scroller)

	# --- низ: выход ---
	var bottom := hbox(12)
	bottom.add_child(ghost_button(Loc.t("chats_logout"), func() -> void:
		Store.logout()
		navigate.emit("login", null)))
	bottom.add_child(spacer())
	card.add_child(bottom)
