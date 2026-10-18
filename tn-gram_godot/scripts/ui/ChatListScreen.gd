extends ScreenBase
## Список чатов: другие аккаунты на этом устройстве + переход в переписку.

const P := preload("res://scripts/net/Protocol.gd")

var net_line: Label       ## подпись «связь есть/нет»
var server_line: Label    ## подпись «сервер: облако · пинг 84 мс»

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
	if not is_inside_tree():
		return
	# Обновляем только подписи. Пинг замеряется каждые несколько секунд, и полная
	# перерисовка списка на каждый замер сбивала бы прокрутку и выделение.
	if net_line != null and is_instance_valid(net_line):
		net_line.text = Net.status_text()
		net_line.add_theme_color_override("font_color", pal()["a2"] if Net.is_online() else pal()["muted"])
	if server_line != null and is_instance_valid(server_line):
		server_line.text = _server_text()

## Где живут наши сообщения и как быстро отвечает сервер
func _server_text() -> String:
	var where := Loc.t("server_cloud") if P.is_cloud(Store.relay_host()) else Loc.t("server_own")
	if Net.ping_ms >= 0:
		return where + " · " + Loc.tf("ping_line", [str(Net.ping_ms)])
	return where + " · " + Loc.t("ping_wait")

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
	top.add_child(ghost_button(Loc.t("chats_new_chat"), func() -> void:
		navigate.emit("newchat", null)))
	top.add_child(ghost_button(Loc.t("chats_new_nick"), func() -> void:
		navigate.emit("new", null)))
	top.add_child(ghost_button(Loc.t("settings"), func() -> void:
		navigate.emit("settings", null)))
	card.add_child(top)

	# --- заголовок ---
	var head := vbox(4)
	head.add_child(heading(Loc.t("chats_title"), 30))
	head.add_child(hint(Loc.t("chats_on_device"), 13))
	var net_line_label := hint(Net.status_text(), 12)
	net_line_label.add_theme_color_override("font_color", pal()["a2"] if Net.is_online() else pal()["muted"])
	net_line = net_line_label
	head.add_child(net_line_label)
	server_line = hint(_server_text(), 12)
	server_line.add_theme_color_override("font_color", pal()["muted"])
	head.add_child(server_line)
	card.add_child(head)

	# --- предупреждение: наш ник занят ещё кем-то ---
	if Store.nick_conflict:
		var warn_panel := PanelContainer.new()
		warn_panel.add_theme_stylebox_override("panel",
			UiStyle.box(Color("#3a2a12"), 16, Color("#8a6a2a"), 1, 14))
		var warn := label(Loc.tf("chats_conflict", [Store.current_nick]), 13, Color("#ffcf7a"), true)
		warn_panel.add_child(warn)
		card.add_child(warn_panel)

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
			var unread := Store.unread_count(peer)
			if unread > 0:
				time_text = ("● %d   %s" % [unread, time_text]) if time_text != "" else ("● %d" % unread)
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
