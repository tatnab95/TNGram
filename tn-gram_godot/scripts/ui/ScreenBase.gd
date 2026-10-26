extends Control
class_name ScreenBase
## Общая основа для всех экранов приложения.
## Здесь собраны готовые «кирпичики» интерфейса, чтобы экраны не повторяли друг друга.

## Экран просит показать другой экран: navigate("chat", "админ")
signal navigate(target: String, arg: Variant)

const P := preload("res://scripts/net/Protocol.gd")
const FlingScrollScript := preload("res://scripts/ui/FlingScroll.gd")

const PAD := 26  ## отступ содержимого от краёв окна

## Текущая палитра темы
func pal() -> Dictionary:
	return UiStyle.palette(Store.theme())

## Главный узел приложения — ближайший предок, умеющий показывать экраны.
## Ищем по способности (show_screen), а не по текущей главной сцене: иначе
## ломается в проверках, где главная сцена — сам тест, а не приложение.
func app() -> Node:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("show_screen"):
			return node
		node = node.get_parent()
	return null

## ---------------------------------------------------------------- текст

func label(text: String, size: int = 15, color: Color = Color(0, 0, 0, 0), wrap: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color if color.a > 0.0 else pal()["text"])
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

func heading(text: String, size: int = 30) -> Label:
	return label(text, size, pal()["text"])

func hint(text: String, size: int = 13) -> Label:
	var node := label(text, size, pal()["muted"], true)
	return node

## Заголовок-акцент (градиент заменяем на цвет темы — так надёжнее)
func accent_label(text: String, size: int = 13, wrap: bool = false) -> Label:
	var node := label(text, size, pal()["a2"], wrap)
	node.add_theme_constant_override("outline_size", 0)
	return node

## ---------------------------------------------------------------- контейнеры

func vbox(separation: int = 12) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box

func hbox(separation: int = 12) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box

func spacer(min_width: int = 0) -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.custom_minimum_size = Vector2(min_width, 0)
	return node

## Распорка, которая тянется по вертикали — для центрирования содержимого
func vspacer() -> Control:
	var node := Control.new()
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node

## Прокручиваемая область. Двигается пальцем с разгоном (см. FlingScroll) и
## сама доводит до поля ввода, когда открывается клавиатура на телефоне.
func scroll() -> ScrollContainer:
	var node := ScrollContainer.new()
	node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node.follow_focus = true
	var fling := FlingScrollScript.new()
	fling.name = "FlingScroll"
	fling.target = node
	add_child(fling)
	return node

## ------------------------------------------------------------------ цвета

## Свой цвет для каждого ника: одинаковый ник — всегда один и тот же цвет.
## Так аватарки различаются с первого взгляда, а не все одинаковые.
func nick_color(nick: String) -> Color:
	var key := nick.strip_edges().to_lower()
	if key == "":
		key = "?"
	var hue := float(absi(hash(key)) % 360) / 360.0
	return Color.from_hsv(hue, 0.52, 0.96)

## ------------------------------------------------------------------ кто в сети

## Подпись про человека: «в сети», «был(а) 5 мин назад» или пусто, если не знаем.
func status_text(nick: String) -> String:
	if Store.is_online(nick):
		return Loc.t("status_online")
	var seen := Store.seen_at(nick)
	if seen <= 0:
		return ""
	return Loc.tf("status_last_seen", [time_ago(seen)])

## «только что», «5 мин назад», «3 ч назад», «2 дн назад»
func time_ago(ts: int) -> String:
	var diff := maxi(int(Time.get_unix_time_from_system()) - ts, 0)
	if diff < 60:
		return Loc.t("time_now")
	if diff < 3600:
		return Loc.tf("time_minutes", [str(diff / 60)])
	if diff < 86400:
		return Loc.tf("time_hours", [str(diff / 3600)])
	return Loc.tf("time_days", [str(diff / 86400)])

## Подпись дня для разделителя в переписке: «Сегодня», «Вчера», «18.10.2026»
func day_text(ts: int) -> String:
	var today := int(Time.get_unix_time_from_system())
	if ts <= 0:
		return ""
	if Time.get_date_string_from_unix_time(ts) == Time.get_date_string_from_unix_time(today):
		return Loc.t("day_today")
	if Time.get_date_string_from_unix_time(ts) == Time.get_date_string_from_unix_time(today - 86400):
		return Loc.t("day_yesterday")
	var d := Time.get_datetime_dict_from_unix_time(ts)
	return "%02d.%02d.%04d" % [int(d.get("day", 1)), int(d.get("month", 1)), int(d.get("year", 2000))]

## ---------------------------------------------------------------- кнопки

func ghost_button(text: String, on_press: Callable = Callable()) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	if on_press.is_valid():
		button.pressed.connect(on_press)
	return button

## Акцентная кнопка (синий-зелёный цвет темы, тёмный текст)
func accent_button(text: String, on_press: Callable = Callable()) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	if on_press.is_valid():
		button.pressed.connect(on_press)
	var p := pal()
	var radius := 999
	button.add_theme_stylebox_override("normal", UiStyle.box(p["a1"], radius, Color(0, 0, 0, 0), 0, 14))
	button.add_theme_stylebox_override("hover", UiStyle.box(p["a1"].lerp(p["a2"], 0.5), radius, Color(0, 0, 0, 0), 0, 14))
	button.add_theme_stylebox_override("pressed", UiStyle.box(p["a2"], radius, Color(0, 0, 0, 0), 0, 14))
	button.add_theme_stylebox_override("focus", UiStyle.box(Color(0, 0, 0, 0), radius, Color(0, 0, 0, 0), 0, 14))
	button.add_theme_color_override("font_color", Color("#04121b"))
	button.add_theme_color_override("font_hover_color", Color("#04121b"))
	button.add_theme_color_override("font_pressed_color", Color("#04121b"))
	return button

## Кнопка-переключатель (для языка и тем). Активная подсвечивается.
func toggle_button(text: String, active: bool, on_press: Callable = Callable()) -> Button:
	var p := pal()
	var button := ghost_button(text, on_press)
	if active:
		button.add_theme_stylebox_override("normal", UiStyle.box(p["a2"] * Color(1, 1, 1, 0.5), 999, p["a2"], 1, 12))
		button.add_theme_color_override("font_color", Color("#04121b"))
		button.add_theme_color_override("font_hover_color", Color("#04121b"))
	return button

## ---------------------------------------------------------------- карточки

## Круглая «аватарка» с первой буквой ника. Цвет свой у каждого ника, а зелёная
## точка в углу показывает, что человек сейчас в сети.
func avatar(nick: String, size: int = 44, online: bool = false) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Круг рисуем крупной текстурой и уменьшаем: сглаженный край получается
	# в любом графическом режиме, даже там, где MSAA не работает.
	var circle := TextureRect.new()
	circle.texture = UiStyle.circle_texture(_avatar_color(nick), Color(1, 1, 1, 0.35), 128)
	circle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	circle.stretch_mode = TextureRect.STRETCH_SCALE
	circle.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(circle)

	var letter := label(Store.avatar_letter(nick), int(size * 0.42), Color("#04121b"))
	letter.set_anchors_preset(Control.PRESET_FULL_RECT)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(letter)

	if online:
		holder.add_child(online_dot(size))
	return holder

## Цвет аватарки: свой у каждого ника, у группы — спокойный цвет темы.
func _avatar_color(nick: String) -> Color:
	if P.is_group_key(nick):
		return pal()["a2"].lerp(Color("#ffffff"), 0.25)
	return nick_color(nick)

## Зелёная точка «в сети» в правом нижнем углу аватарки
func online_dot(size: int) -> Control:
	var dot := TextureRect.new()
	var side := maxf(float(size) * 0.3, 8.0)
	dot.texture = UiStyle.circle_texture(Color("#3ddc84"), Color(0, 0, 0, 0.55), 64)
	dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dot.stretch_mode = TextureRect.STRETCH_SCALE
	dot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.anchor_left = 1.0
	dot.anchor_right = 1.0
	dot.anchor_top = 1.0
	dot.anchor_bottom = 1.0
	dot.offset_left = -side
	dot.offset_right = 0.0
	dot.offset_top = -side
	dot.offset_bottom = 0.0
	return dot

## Кликабельная карточка: аватар, ник, подпись, справа — время.
## online — показать зелёную точку «в сети»; unread — значок непрочитанных.
func contact_button(nick: String, subtitle: String, right_text: String, on_press: Callable,
		online: bool = false, unread: int = 0) -> Button:
	var p := pal()
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 74)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", UiStyle.box(p["panel"], 20, p["line"], 1, 0))
	button.add_theme_stylebox_override("hover", UiStyle.box(p["panel_strong"], 20, p["a2"] * Color(1, 1, 1, 0.5), 1, 0))
	button.add_theme_stylebox_override("pressed", UiStyle.box(p["panel_strong"], 20, p["a2"], 1, 0))
	button.add_theme_stylebox_override("focus", UiStyle.box(Color(0, 0, 0, 0), 20, Color(0, 0, 0, 0), 0, 0))
	button.pressed.connect(on_press)

	var row := hbox(14)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_top = 12
	row.offset_right = -18
	row.offset_bottom = -12
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	row.add_child(avatar(nick, 46, online))

	var texts := vbox(2)
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(label(nick, 16))
	var sub := hint(subtitle, 13)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(sub)
	row.add_child(texts)

	if unread > 0:
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", UiStyle.box(p["a1"].lerp(p["a2"], 0.35), 999, Color(0, 0, 0, 0), 0, 6))
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var count := label(str(unread), 12, Color("#04121b"))
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_child(count)
		row.add_child(badge)

	if right_text != "":
		var right := label(right_text, 12, p["muted"])
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(right)

	return button

## Разделитель по дате в переписке: «Сегодня», «Вчера», «18.10.2026»
func date_separator(text: String) -> Control:
	var row := hbox(10)
	row.add_child(spacer())
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel",
		UiStyle.box(pal()["panel"], 999, pal()["line"], 1, 5))
	var text_label := label(text, 12, pal()["muted"])
	chip.add_child(text_label)
	row.add_child(chip)
	row.add_child(spacer())
	return row

## Строка с галочкой — для выбора людей в группу
func check_row(title: String, checked: bool, on_toggle: Callable) -> Control:
	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = checked
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_stylebox_override("normal", UiStyle.box(pal()["panel"], 14, pal()["line"], 1, 10))
	button.add_theme_stylebox_override("hover", UiStyle.box(pal()["panel_strong"], 14, pal()["a2"], 1, 10))
	button.add_theme_stylebox_override("pressed", UiStyle.box(pal()["panel_strong"], 14, pal()["a2"], 1, 10))
	button.add_theme_stylebox_override("focus", UiStyle.box(Color(0, 0, 0, 0), 14, Color(0, 0, 0, 0), 0, 10))
	button.text = ("✓  " if checked else "•  ") + title
	button.toggled.connect(func(on: bool) -> void:
		button.text = ("✓  " if on else "•  ") + title
		on_toggle.call(on))
	return button

## Строка настроек: подпись слева, содержимое справа
func settings_row(title: String, content: Control) -> PanelContainer:
	var p := pal()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(p["panel"], 18, p["line"], 1, 16))
	var row := hbox(14)
	if title != "":
		row.add_child(label(title, 15))
		row.add_child(spacer())
	else:
		row.add_child(spacer())
	content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(content)
	row.add_child(spacer())
	panel.add_child(row)
	return panel
