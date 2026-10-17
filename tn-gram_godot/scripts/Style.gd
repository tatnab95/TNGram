extends RefCounted
class_name UiStyle
## Всё оформление приложения в одном месте: цвета тем, панели, кнопки, свечение.
## Хочешь поменять цвета — правь PALETTES ниже.

## Палитры тем. Меняй значения — интерфейс перекрасится целиком.
const PALETTES := {
	"dark": {
		"bg": Color("#05070a"),
		"panel": Color(1, 1, 1, 0.055),
		"panel_strong": Color(1, 1, 1, 0.085),
		"line": Color(1, 1, 1, 0.10),
		"text": Color("#f4f7fb"),
		"muted": Color("#99a3b2"),
		"a1": Color("#2f7bff"),   # синий
		"a2": Color("#00e08f")    # зелёный
	},
	"green": {
		"bg": Color("#040906"),
		"panel": Color(1, 1, 1, 0.055),
		"panel_strong": Color(1, 1, 1, 0.085),
		"line": Color(1, 1, 1, 0.10),
		"text": Color("#f2fbf6"),
		"muted": Color("#97b3a6"),
		"a1": Color("#00c484"),
		"a2": Color("#8ad62a")
	},
	"blue": {
		"bg": Color("#04060d"),
		"panel": Color(1, 1, 1, 0.055),
		"panel_strong": Color(1, 1, 1, 0.085),
		"line": Color(1, 1, 1, 0.10),
		"text": Color("#f3f5ff"),
		"muted": Color("#9aa3c0"),
		"a1": Color("#3b82f6"),
		"a2": Color("#8b5cf6")
	}
}

## Цвета текущей темы
static func palette(theme_id: String) -> Dictionary:
	return PALETTES.get(theme_id, PALETTES["dark"])

## ---------- маленькие конструкторы стилей ----------

## Панель со скруглением и тонкой светлой обводкой
static func box(fill: Color, radius: int = 20, border: Color = Color(0, 0, 0, 0), border_width: int = 1, pad: int = 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_width if border.a > 0.0 else 0)
	sb.border_color = border
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb

## Заливка без скругления (фон окна)
static func flat(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	return sb

## Круглый градиент — для мягкого свечения на фоне
static func glow_texture(from: Color, to: Color = Color(0, 0, 0, 0), size: int = 256) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = size
	texture.height = size
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture

## Линейный градиент (для кнопок-акцентов и аватаров)
static func gradient_texture(from: Color, to: Color, size: Vector2i = Vector2i(256, 64)) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = size.x
	texture.height = size.y
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 1)
	return texture

## ---------- общая тема Control-узлов ----------

static func build(theme_id: String) -> Theme:
	var p := palette(theme_id)
	var theme := Theme.new()

	# Текст
	theme.set_color("font_color", "Label", p["text"])
	theme.set_color("font_color", "RichTextLabel", p["text"])
	theme.set_font_size("font_size", "Label", 15)
	theme.set_color("default_color", "RichTextLabel", p["text"])

	# Стеклянная панель
	theme.set_stylebox("panel", "PanelContainer", box(p["panel"], 22, p["line"], 1, 18))
	theme.set_stylebox("panel", "Panel", box(p["panel"], 22, p["line"], 1, 18))
	theme.set_stylebox("panel", "PopupPanel", box(p["panel_strong"], 20, p["line"], 1, 14))

	# Окна подтверждения (ConfirmationDialog) — тоже в стиле приложения
	theme.set_stylebox("panel", "AcceptDialog", box(p["panel_strong"], 20, p["line"], 1, 16))
	theme.set_stylebox("panel", "Window", box(p["panel_strong"], 20, p["line"], 1, 16))
	theme.set_color("font_color", "AcceptDialog", p["text"])
	theme.set_font_size("font_size", "AcceptDialog", 15)

	# Кнопки: обычные — стеклянные, акцентные настраиваются отдельно (см. ScreenBase)
	theme.set_stylebox("normal", "Button", box(p["panel"], 14, p["line"], 1, 12))
	theme.set_stylebox("hover", "Button", box(p["panel_strong"], 14, p["line"], 1, 12))
	theme.set_stylebox("pressed", "Button", box(p["a1"] * Color(1, 1, 1, 0.35), 14, p["line"], 1, 12))
	theme.set_stylebox("disabled", "Button", box(p["panel"] * Color(1, 1, 1, 0.5), 14, p["line"], 1, 12))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 14, Color(0, 0, 0, 0), 0, 12))
	theme.set_color("font_color", "Button", p["text"])
	theme.set_color("font_hover_color", "Button", p["text"])
	theme.set_color("font_pressed_color", "Button", p["text"])
	theme.set_color("font_disabled_color", "Button", p["muted"])
	theme.set_font_size("font_size", "Button", 15)

	# Поля ввода
	theme.set_stylebox("normal", "LineEdit", box(Color(1, 1, 1, 0.05), 14, p["line"], 1, 14))
	theme.set_stylebox("focus", "LineEdit", box(Color(1, 1, 1, 0.07), 14, p["a2"] * Color(1, 1, 1, 0.6), 1, 14))
	theme.set_color("font_color", "LineEdit", p["text"])
	theme.set_color("font_placeholder_color", "LineEdit", Color(p["muted"], 0.75))
	theme.set_color("caret_color", "LineEdit", p["a2"])
	theme.set_font_size("font_size", "LineEdit", 15)

	# Список и прокрутка
	theme.set_stylebox("panel", "ScrollContainer", box(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 0))
	theme.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.25), 8, Color(0, 0, 0, 0), 0, 4))
	theme.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.18), 8, Color(0, 0, 0, 0), 0, 4))
	theme.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 1, 1, 0.30), 8, Color(0, 0, 0, 0), 0, 4))

	return theme
