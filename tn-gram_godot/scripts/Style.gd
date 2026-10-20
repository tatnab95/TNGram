extends RefCounted
class_name UiStyle
## Всё оформление приложения в одном месте: цвета тем, панели, кнопки, свечение.
## Хочешь поменять цвета — правь PALETTES ниже.

## Палитры тем. Меняй значения — интерфейс перекрасится целиком.
const PALETTES := {
	"dark": {
		"bg": Color("#05080d"),
		"panel": Color(1, 1, 1, 0.062),
		"panel_strong": Color(1, 1, 1, 0.098),
		"line": Color(1, 1, 1, 0.12),
		"text": Color("#f5f8fd"),
		"muted": Color("#98a3b5"),
		"a1": Color("#2f7bff"),   # синий
		"a2": Color("#10dfa0")    # зелёный
	},
	"green": {
		"bg": Color("#040906"),
		"panel": Color(1, 1, 1, 0.062),
		"panel_strong": Color(1, 1, 1, 0.098),
		"line": Color(1, 1, 1, 0.12),
		"text": Color("#f2fbf6"),
		"muted": Color("#96b2a5"),
		"a1": Color("#00c484"),
		"a2": Color("#8ad62a")
	},
	"blue": {
		"bg": Color("#04060d"),
		"panel": Color(1, 1, 1, 0.062),
		"panel_strong": Color(1, 1, 1, 0.098),
		"line": Color(1, 1, 1, 0.12),
		"text": Color("#f3f5ff"),
		"muted": Color("#99a2c0"),
		"a1": Color("#3b82f6"),
		"a2": Color("#8b5cf6")
	}
}

## Цвета текущей темы
static func palette(theme_id: String) -> Dictionary:
	return PALETTES.get(theme_id, PALETTES["dark"])

## ---------- сглаживание ----------

## Размер текстуры свечения по уровню сглаживания: чем больше, тем мягче фон
## (на градиенте не видно «ступенек»). 512 — уже 1 МБ на пятно, это нормально.
static func glow_size(aa_level: int) -> int:
	var sizes := [192, 256, 384, 512]
	return int(sizes[clampi(aa_level, 0, 3)])

## Шрифт нужного качества. Возвращает null, если встроенный шрифт поменять
## не удалось, — тогда сглаживание текста просто остаётся заводским.
static func aa_font(aa_level: int) -> Font:
	var base: Font = ThemeDB.fallback_font
	var file: FontFile = null
	if base is FontFile:
		file = (base as FontFile).duplicate() as FontFile
	elif base is FontVariation and (base as FontVariation).base_font is FontFile:
		file = ((base as FontVariation).base_font as FontFile).duplicate() as FontFile
	if file == null:
		return null
	match clampi(aa_level, 0, 3):
		0:
			# без сглаживания: буквы резкие, «пиксельные»
			file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			file.hinting = TextServer.HINTING_NORMAL
		1:
			file.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
			file.hinting = TextServer.HINTING_LIGHT
		2:
			file.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_HALF
			file.hinting = TextServer.HINTING_LIGHT
		_:
			# самый мягкий: тонкая подстройка положения букв
			file.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER
			file.hinting = TextServer.HINTING_NONE
	return file

## Умеет ли эта видеокарта сглаживать фигуры (MSAA)? В простом режиме
## (OpenGL «Compatibility») — нет, там сглаживается только текст.
static func shapes_aa_supported() -> bool:
	return RenderingServer.get_rendering_device() != null

## Насколько мягко сглаживать края фигур (панели, кружки-аватарки). В простом
## графическом режиме MSAA не работает, зато этот параметр работает всегда:
## чем выше уровень «Сглаживания» в настройках, тем мягче край.
static var shape_softness := 1.0

## Пересчитать мягкость краёв фигур по уровню сглаживания (0…3).
static func apply_aa_level(aa_level: int) -> void:
	shape_softness = 1.0 + float(clampi(aa_level, 0, 3)) * 0.5

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
	sb.anti_aliasing_size = shape_softness
	return sb

## Пузырь сообщения в переписке. Свои — градиент акцентных цветов с загнутым
## правым углом, чужие — стеклянная панель с загнутым левым. Так пузырь
## читается с первого взгляда и выглядит как в больших мессенджерах.
static func bubble_box(mine: bool, accent_a: Color, accent_b: Color, panel: Color, line: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(18)
	sb.corner_detail = 7
	sb.anti_aliasing = true
	sb.anti_aliasing_size = shape_softness
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 6.0
	if mine:
		sb.set_corner_radius_bottom_right(6)
		sb.bg_color = accent_a
		var gradient := Gradient.new()
		gradient.set_color(0, accent_a)
		gradient.set_color(1, accent_b)
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 256
		texture.height = 64
		texture.fill = GradientTexture2D.FILL_LINEAR
		texture.fill_from = Vector2(0, 0)
		texture.fill_to = Vector2(1, 1)
		sb.gradient = texture
		sb.gradient_fill_from = Vector2(0, 0)
		sb.gradient_fill_to = Vector2(1, 1)
	else:
		sb.set_corner_radius_bottom_left(6)
		sb.bg_color = panel
		sb.set_border_width_all(1)
		sb.border_color = line
	return sb

## Гладкий круг для аватарки. Рисуем крупную текстуру и уменьшаем её — край
## получается мягким в любом графическом режиме (даже там, где MSAA не работает).
## Текстуру не кэшируем: она живёт вместе с аватаркой и освобождается вместе с ней.
static func circle_texture(fill: Color, rim: Color, size: int = 128) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, fill)
	gradient.set_color(1, rim)
	# 0…0.90 — основной цвет, 0.90…0.955 — светлая обводка, 0.955…1 — плавный край
	gradient.offsets = PackedFloat32Array([0.0, 0.90, 0.955, 1.0])
	gradient.colors = PackedColorArray([fill, fill, rim, Color(rim.r, rim.g, rim.b, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = size
	texture.height = size
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture

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

static func build(theme_id: String, aa_level: int = 1) -> Theme:
	var p := palette(theme_id)
	var theme := Theme.new()

	# Сглаживание текста (см. aa_font). null — оставляем заводской шрифт.
	var font := aa_font(aa_level)
	if font != null:
		theme.default_font = font

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
