extends ScreenBase
## Экран «Новый чат»: написать любому человеку по нику, а не только тем,
## кто уже есть на устройстве. Если облако настроено, спрашиваем у него,
## есть ли такой ник на самом деле.

var error_code := ""
var checking := false
var typed_nick := ""      ## что ввёл человек (чтобы не потерять при перерисовке)
var pending_nick := ""    ## ник, которого нет в облаке — можно открыть всё равно

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
	outer.add_child(vspacer())

	var row := hbox(0)
	outer.add_child(row)
	row.add_child(spacer())

	var column := vbox(14)
	column.custom_minimum_size = Vector2(440, 0)
	row.add_child(column)
	row.add_child(spacer())

	outer.add_child(vspacer())

	var title := heading(Loc.t("newchat_title"), 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var sub := hint(Loc.t("newchat_subtitle"), 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	column.add_child(gap(8))

	var pair := text_field(Loc.t("newchat_who"), Loc.t("newchat_who_hint"))
	column.add_child(pair[0])
	var nick_edit: LineEdit = pair[1]
	nick_edit.text = pending_nick if pending_nick != "" else typed_nick

	if error_code != "":
		column.add_child(label(Loc.t(error_code), 14, Color("#ff9a9a")))
	if checking:
		column.add_child(hint(Loc.t("newchat_checking"), 13))

	if pending_nick != "":
		column.add_child(accent_button(Loc.t("newchat_open_anyway"), func() -> void:
			_open(pending_nick, true)))

	var open_button := accent_button(Loc.t("newchat_open"), func() -> void:
		_open(nick_edit.text))
	open_button.disabled = checking
	column.add_child(open_button)

	var back := ghost_button(Loc.t("back"), func() -> void:
		navigate.emit("chats", null))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(back)

	if pending_nick == "":
		nick_edit.grab_focus()

## ------------------------------------------------------------- действия

func _open(raw_nick: String, force: bool = false) -> void:
	var nick := raw_nick.strip_edges()
	typed_nick = nick
	if nick.length() < 2:
		error_code = "err_nick_short"
		rebuild()
		return
	if P.nick_key(nick) == P.nick_key(Store.current_nick):
		error_code = "newchat_self"
		rebuild()
		return

	if not force:
		checking = true
		error_code = ""
		rebuild()
		var verdict := await _ask_cloud(nick)
		checking = false
		if not is_instance_valid(self) or not is_inside_tree():
			return
		if verdict == "missing":
			error_code = "newchat_no_such"
			pending_nick = nick
			rebuild()
			return

	Store.ensure_contact(nick)
	navigate.emit("chat", nick)

## Спросить облако, есть ли такой человек. Ответ: "found" | "missing" | "unknown"
func _ask_cloud(nick: String) -> String:
	var host := Store.relay_host()
	if not P.is_cloud(host):
		return "unknown"
	var tree := get_tree()
	var state := { "done": false, "ok": false, "taken": false }
	var answer := func(ok: bool, taken: bool, _hash: String) -> void:
		state["ok"] = ok
		state["taken"] = taken
		state["done"] = true
	Net.cloud_lookup_nick(host, Store.relay_key(), nick, answer)
	var deadline := Time.get_ticks_msec() + 5000
	while not bool(state["done"]) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if not is_instance_valid(self):
			return "unknown"
	if not bool(state["ok"]):
		return "unknown"
	return "found" if bool(state["taken"]) else "missing"

## ------------------------------------------------------------- вспомогательное

func gap(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node

## Подпись + поле ввода. Возвращает [контейнер, поле]
func text_field(caption: String, placeholder: String) -> Array:
	var box := vbox(6)
	box.add_child(label(caption, 13, pal()["muted"]))

	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 46)
	box.add_child(edit)

	return [box, edit]
