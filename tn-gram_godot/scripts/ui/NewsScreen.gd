extends ScreenBase
## Экран «Что нового»: что изменилось в каждой версии, и предложение обновиться,
## если на сайте лежит версия новее нашей.

var server_news: Array = []      ## новости из облака
var news_asked := false          ## уже спрашивали облако в этот раз

func _ready() -> void:
	build()
	fetch_news()

## Спросить у облака новости разработчика. Без связи просто ничего не делаем.
func fetch_news() -> void:
	if news_asked or Store.current_nick == "":
		return
	if OS.get_environment("TNGRAM_PROFILE").strip_edges() != "":
		return
	if not P.is_cloud(Store.relay_host()):
		return
	news_asked = true
	Net.cloud_fetch_news(Store.relay_host(), Store.relay_key(), func(ok: bool, items: Array) -> void:
		if not is_inside_tree():
			return
		if ok and not items.is_empty():
			server_news = items
			rebuild())

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
		navigate.emit("settings", null)))
	top.add_child(spacer())
	column.add_child(top)

	var head := vbox(4)
	head.add_child(heading(Loc.t("news_title"), 30))
	head.add_child(hint(Loc.t("news_subtitle"), 13))
	column.add_child(head)

	# --- новости от разработчика (из облака) ---
	column.add_child(server_news_block())

	var scroller := scroll()
	var list := vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(list)
	column.add_child(scroller)

	# --- предложение обновиться ---
	var update := Store.update_available()
	if update != "":
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel_strong"], 18, pal()["a2"], 1, 16))
		var box := vbox(8)
		box.add_child(label(Loc.tf("news_update_title", [update]), 17, pal()["a2"]))
		box.add_child(hint(Loc.t("news_update_text"), 13))
		var row := hbox(10)
		row.add_child(accent_button(Loc.t("news_open_site"), func() -> void:
			app().open_site()))
		box.add_child(row)
		card.add_child(box)
		list.add_child(card)
	else:
		list.add_child(hint(Loc.tf("news_current", [P.APP_VERSION]), 13))

	# --- что нового по версиям ---
	for entry in P.changelog(Loc.lang):
		list.add_child(version_card(entry))

## Блок новостей из облака: заголовок и карточки. Если новостей нет или связи
## нет — просто подсказка, ничего не ломается.
func server_news_block() -> Control:
	var block := vbox(8)
	block.add_child(label(Loc.t("news_from_server"), 16, pal()["a2"]))
	if server_news.is_empty():
		block.add_child(hint(Loc.t("news_empty") if news_asked else Loc.t("news_no_connection"), 13))
		return block
	for item in server_news:
		block.add_child(news_card(item as Dictionary))
	return block

## Карточка одной новости: заголовок, текст и дата
func news_card(item: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 18, pal()["line"], 1, 16))
	var box := vbox(6)
	var title := String(item.get("title", "")).strip_edges()
	var body := String(item.get("body", "")).strip_edges()
	if title != "":
		card.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 18, pal()["a2"], 1, 16))
		box.add_child(label(title, 16, pal()["a2"]))
	if body != "":
		box.add_child(label(body, 14, pal()["text"], true))
	var date := short_date(String(item.get("date", "")))
	if date != "":
		box.add_child(hint(date, 12))
	card.add_child(box)
	return card

## «2026-10-18T12:34:56+00:00» → «18.10.2026» (пусто — не показываем дату)
func short_date(value: String) -> String:
	var text := value.strip_edges()
	if text.length() < 10:
		return ""
	var day := text.substr(0, 10).split("-")
	if day.size() != 3:
		return ""
	return "%s.%s.%s" % [String(day[2]), String(day[1]), String(day[0])]

## Карточка одной версии: номер, дата и список изменений
func version_card(entry: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(pal()["panel"], 18, pal()["line"], 1, 16))

	var box := vbox(8)
	var title_row := hbox(10)
	title_row.add_child(label(Loc.t("app_name") + " " + String(entry.get("version", "")), 17))
	title_row.add_child(hint(String(entry.get("date", "")), 12))
	title_row.add_child(spacer())
	box.add_child(title_row)

	var items: Array = entry.get("items", [])
	if items.is_empty():
		box.add_child(hint(Loc.t("soon"), 13))
	for item in items:
		box.add_child(label("•   " + String(item), 14, pal()["text"], true))

	card.add_child(box)
	return card
