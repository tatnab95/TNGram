extends Control
## Главный узел приложения «Тнграм».
## Здесь живёт фон со свечением и переключение экранов.
## Экраны лежат в scripts/ui/, каждый умеет строить себя сам.

const SCREENS := {
	"login": preload("res://scripts/ui/LoginScreen.gd"),
	"new": preload("res://scripts/ui/NewAccountScreen.gd"),
	"chats": preload("res://scripts/ui/ChatListScreen.gd"),
	"chat": preload("res://scripts/ui/ChatScreen.gd"),
	"settings": preload("res://scripts/ui/SettingsScreen.gd")
}

var current_id := "login"
var current_arg: Variant = null
var screen: Control = null
var background: Control = null

func _ready() -> void:
	Loc.lang = Store.lang()
	apply_theme()
	build_background()
	Net.on_message = _on_net_message
	show_screen("chats" if Store.current_nick != "" else "login", null)

## Тема приложения (цвета — в scripts/Style.gd)
func apply_theme() -> void:
	theme = UiStyle.build(Store.theme())

## Полная перерисовка: после смены языка или темы
func rebuild() -> void:
	apply_theme()
	build_background()
	show_screen(current_id, current_arg)

## Показать экран по имени. arg — например ник собеседника для чата.
func show_screen(id: String, arg: Variant = null) -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
		screen = null

	Loc.lang = Store.lang()
	current_id = id
	current_arg = arg

	var script: GDScript = SCREENS.get(id, SCREENS["login"])
	var node: Control = script.new()
	node.name = "Screen"
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	if id == "chat":
		node.set("peer", String(arg) if arg != null else "")
	add_child(node)
	node.navigate.connect(_on_navigate)
	screen = node

	# Связь: на экране входа мы ещё никто, на остальных — если включено «подключаться при входе»
	if id == "login":
		Net.stop()
	else:
		maybe_connect()

func _on_navigate(target: String, arg: Variant) -> void:
	show_screen(target, arg)

## ---------------------------------------------------------------- связь

## Отправить сообщение: сначала сохраняем у себя, потом пробуем отправить по сети.
func send_message(peer: String, text: String) -> bool:
	if not Store.send_message(peer, text):
		return false
	Net.send_message(peer, text)
	return true

## Входящее сообщение из сети: сохраняем у себя и только тогда подтверждаем — сервер удалит.
func _on_net_message(from_nick: String, text: String, ts: int, net_id: String) -> bool:
	return Store.receive_message(from_nick, text, ts, net_id)

## Выйти на связь, если это включено в настройках и мы уже вошли
func maybe_connect() -> void:
	if Store.current_nick == "" or not Store.relay_auto():
		return
	if Net.is_online() and Net.nick == Store.current_nick:
		return
	Net.connect_to(Store.relay_host(), Store.relay_port(), Store.current_nick, Store.relay_key())

## ---------------------------------------------------------------- фон

## Мягкое свечение: тёмный фон + пара размытых цветных пятен (как на сайте)
func build_background() -> void:
	if background != null and is_instance_valid(background):
		background.queue_free()

	var p := UiStyle.palette(Store.theme())
	background = Control.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var base := ColorRect.new()
	base.color = p["bg"]
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(base)

	add_blob(Vector2(0.08, 0.02), 820, p["a1"], 0.30)
	add_blob(Vector2(0.96, 0.14), 720, p["a2"], 0.26)
	add_blob(Vector2(0.50, 1.02), 940, p["a1"].lerp(p["a2"], 0.5), 0.16)

## Пятно свечения: центр в точке anchor (доли от размера окна), диаметр size
func add_blob(anchor: Vector2, size: float, color: Color, strength: float) -> void:
	var blob := TextureRect.new()
	blob.texture = UiStyle.glow_texture(Color(color.r, color.g, color.b, strength))
	blob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blob.stretch_mode = TextureRect.STRETCH_SCALE
	blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blob.anchor_left = anchor.x
	blob.anchor_right = anchor.x
	blob.anchor_top = anchor.y
	blob.anchor_bottom = anchor.y
	blob.offset_left = -size * 0.5
	blob.offset_right = size * 0.5
	blob.offset_top = -size * 0.5
	blob.offset_bottom = size * 0.5
	background.add_child(blob)
