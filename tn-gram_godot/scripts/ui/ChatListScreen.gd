extends ScreenBase
## Список чатов: люди и группы, поиск, зелёные точки «в сети», полоса обновления.

var net_line: Label       ## подпись «связь есть/нет»
var server_line: Label    ## подпись «сервер: облако · пинг 84 мс»
var list_box: VBoxContainer  ## сюда собираются карточки чатов
var search_field: LineEdit   ## поиск по нику, названию и последнему сообщению
var _animate_rows := false   ## первый список появляется с лёгким оживанием

func _ready() -> void:
	_animate_rows = true
	build()
	if not Store.data_changed.is_connected(_on_data_changed):
		Store.data_changed.connect(_on_data_changed)
	if not Store.presence_changed.is_connected(_on_presence_changed):
		Store.presence_changed.connect(_on_presence_changed)
	if not Net.changed.is_connected(_on_net_changed):
		Net.changed.connect(_on_net_changed)

func _on_data_changed() -> void:
	if is_inside_tree():
		rebuild()

## Кто-то появился в сети — обновляем только список, а не весь экран:
## так не сбрасывается поиск.
func _on_presence_changed() -> void:
	if is_inside_tree():
		fill_list()

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
	var card := vbox(14)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAD)
	margin.add_theme_constant_override("margin_right", PAD)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	margin.add_child(card)

	# --- верхняя строка: кто вошёл и настройки ---
	var top := hbox(12)
	top.add_child(avatar(Store.current_nick, 44, true))
	var who := vbox(1)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(label(Store.current_nick, 16))
	who.add_child(hint(Loc.t("chats_you"), 12))
	top.add_child(who)
	top.add_child(spacer())
	top.add_child(ghost_button(Loc.t("settings"), func() -> void:
		navigate.emit("settings", null)))
	card.add_child(top)

	# --- заголовок и связь ---
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

	# --- полоса «вышла новая версия» ---
	var fresh := Store.update_available()
	if fresh != "":
		card.add_child(update_banner(fresh))

	# --- кнопки действий ---
	var actions := hbox(10)
	actions.add_child(ghost_button(Loc.t("chats_new_chat"), func() -> void:
		navigate.emit("newchat", null)))
	actions.add_child(ghost_button(Loc.t("chats_new_group"), func() -> void:
		navigate.emit("newgroup", null)))
	actions.add_child(ghost_button(Loc.t("chats_new_nick"), func() -> void:
		navigate.emit("new", null)))
	actions.add_child(spacer())
	card.add_child(actions)

	# --- предупреждение: наш ник занят ещё кем-то ---
	if Store.nick_conflict:
		var warn_panel := PanelContainer.new()
		warn_panel.add_theme_stylebox_override("panel",
			UiStyle.box(Color("#3a2a12"), 16, Color("#8a6a2a"), 1, 14))
		var warn := label(Loc.tf("chats_conflict", [Store.current_nick]), 13, Color("#ffcf7a"), true)
		warn_panel.add_child(warn)
		card.add_child(warn_panel)

	# --- поиск ---
	search_field = LineEdit.new()
	search_field.placeholder_text = Loc.t("chats_search")
	search_field.custom_minimum_size = Vector2(0, 38)
	search_field.text_changed.connect(func(_text: String) -> void: fill_list())
	card.add_child(search_field)

	# --- список чатов ---
	list_box = vbox(10)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill_list()

	var scroller := scroll()
	scroller.add_child(list_box)
	card.add_child(scroller)

	# --- низ: выход ---
	var bottom := hbox(12)
	bottom.add_child(ghost_button(Loc.t("chats_logout"), func() -> void:
		Store.logout()
		navigate.emit("login", null)))
	bottom.add_child(spacer())
	card.add_child(bottom)

## Полоса «доступна новая версия» с кнопкой
func update_banner(version: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiStyle.box(pal()["a1"].lerp(pal()["a2"], 0.4), 16, pal()["a2"], 1, 12))
	var row := hbox(12)
	var text := label(Loc.tf("update_available", [version]), 14, Color("#04121b"), true)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	row.add_child(spacer())
	var get_button := ghost_button(Loc.t("update_get"), func() -> void:
		app().open_update())
	get_button.add_theme_color_override("font_color", Color("#04121b"))
	row.add_child(get_button)
	panel.add_child(row)
	Anim.fade_in(panel, 0.2)
	return panel

## Собрать карточки чатов с учётом поиска. Вызывается и при вводе в поиск.
func fill_list() -> void:
	if list_box == null or not is_instance_valid(list_box):
		return
	for child in list_box.get_children():
		child.queue_free()
	var needle := search_field.text.strip_edges().to_lower() if search_field != null else ""
	var shown := 0

	# Чат со слабым ИИ — только на телефоне и всегда первым: он работает
	# даже без интернета, а переписка хранится прямо на устройстве.
	if P.is_ai_enabled():
		var ai_title := Loc.t("ai_title")
		var ai_last := Store.last_message(P.AI_KEY)
		var ai_preview := Loc.t("ai_subtitle") if ai_last.is_empty() else String(ai_last.get("text", ""))
		if needle == "" or ai_title.to_lower().contains(needle) or ai_preview.to_lower().contains(needle):
			var ai_time := Store.format_time(int(ai_last.get("ts", 0))) if not ai_last.is_empty() else ""
			list_box.add_child(contact_button(ai_title, ai_preview, ai_time, func() -> void:
				navigate.emit("chat", P.AI_KEY), false, Store.unread_count(P.AI_KEY)))
			shown += 1

	var entries := Store.chat_keys()
	for item in entries:
		var key := String((item as Dictionary).get("key", ""))
		var group := bool((item as Dictionary).get("group", false))
		var title := Store.peer_title(key)
		var preview := preview_text(key, group)
		if needle != "" and not (title.to_lower().contains(needle) or preview.to_lower().contains(needle)):
			continue
		shown += 1
		var last: Dictionary = Store.last_message(key)
		var time_text := Store.format_time(int(last.get("ts", 0))) if not last.is_empty() else ""
		list_box.add_child(contact_button(title, preview, time_text, func() -> void:
			navigate.emit("chat", key),
			Store.is_online(key) and not group, Store.unread_count(key)))
	if shown == 0:
		var empty := hint(Loc.t("chats_empty") if entries.is_empty() else Loc.t("search_nothing"), 14)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var empty_panel := PanelContainer.new()
		empty_panel.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 20, pal()["line"], 1, 28))
		empty_panel.add_child(empty)
		list_box.add_child(empty_panel)
	# Первый показ списка оживает; сигналы (присутствие, поиск) не мигают.
	if _animate_rows:
		_animate_rows = false
		Anim.stagger(list_box)

## Что писать под названием чата
func preview_text(key: String, group: bool) -> String:
	var last: Dictionary = Store.last_message(key)
	if last.is_empty():
		if group:
			return Loc.tf("group_members_count", [str(Store.group_members(key).size())])
		return Loc.t("chats_remote") if not Store.account_exists(key) else Loc.t("chats_no_messages")
	var text := String(last.get("text", ""))
	if not group:
		if Store.is_online(key):
			return Loc.t("status_online") + " · " + text
		return text
	var author := String(last.get("from", ""))
	if bool(last.get("mine", false)) or author == "":
		return text
	return author + ": " + text
