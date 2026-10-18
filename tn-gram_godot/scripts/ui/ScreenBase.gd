extends Control
class_name ScreenBase
## Общая основа для всех экранов приложения.
## Здесь собраны готовые «кирпичики» интерфейса, чтобы экраны не повторяли друг друга.

## Экран просит показать другой экран: navigate("chat", "админ")
signal navigate(target: String, arg: Variant)

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

## Прокручиваемая область
func scroll() -> ScrollContainer:
	var node := ScrollContainer.new()
	node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node

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

## Круглая «аватарка» с первой буквой ника
func avatar(nick: String, size: int = 44) -> Control:
	var p := pal()
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Круг рисуем крупной текстурой и уменьшаем: сглаженный край получается
	# в любом графическом режиме, даже там, где MSAA не работает.
	var circle := TextureRect.new()
	circle.texture = UiStyle.circle_texture(p["a1"].lerp(p["a2"], 0.35), Color(1, 1, 1, 0.35), 128)
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
	return holder

## Кликабельная карточка: аватар, ник, подпись, справа — время
func contact_button(nick: String, subtitle: String, right_text: String, on_press: Callable) -> Button:
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

	row.add_child(avatar(nick, 46))

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

	if right_text != "":
		var right := label(right_text, 12, p["muted"])
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(right)

	return button

## Строка настроек: подпись слева, содержимое справа
func settings_row(title: String, content: Control) -> PanelContainer:
	var p := pal()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(p["panel"], 18, p["line"], 1, 16))
	var row := hbox(14)
	row.add_child(label(title, 15))
	row.add_child(spacer())
	content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(content)
	panel.add_child(row)
	return panel
