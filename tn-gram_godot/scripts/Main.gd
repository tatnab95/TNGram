extends Control
## Главный узел приложения «Тнграм».
## Здесь живёт фон со свечением и переключение экранов.
## Экраны лежат в scripts/ui/, каждый умеет строить себя сам.

const SCREENS := {
	"login": preload("res://scripts/ui/LoginScreen.gd"),
	"new": preload("res://scripts/ui/NewAccountScreen.gd"),
	"chats": preload("res://scripts/ui/ChatListScreen.gd"),
	"chat": preload("res://scripts/ui/ChatScreen.gd"),
	"newchat": preload("res://scripts/ui/NewChatScreen.gd"),
	"news": preload("res://scripts/ui/NewsScreen.gd"),
	"settings": preload("res://scripts/ui/SettingsScreen.gd")
}

const P := preload("res://scripts/net/Protocol.gd")

var current_id := "login"
var current_arg: Variant = null
var screen: Control = null
var background: Control = null
var _nick_checked := ""  ## ник, который уже сверили с облаком (чтобы не дёргать зря)
var _update_checked := false  ## версию на сайте проверяем один раз за запуск
var toast_layer: Control = null  ## слой всплывающих уведомлений
var toast_column: VBoxContainer = null  ## колонка карточек в этом слое
const TOAST_WIDTH := 320.0  ## ширина карточки-уведомления

func _ready() -> void:
	Loc.lang = Store.lang()
	fit_mobile_screen()
	apply_theme()
	apply_aa()
	build_background()
	Net.on_message = _on_net_message
	# Периодический замер пинга
	var ping_timer := Timer.new()
	ping_timer.wait_time = 8.0
	ping_timer.timeout.connect(_ping_tick)
	ping_timer.autostart = true
	add_child(ping_timer)
	show_screen("chats" if Store.current_nick != "" else "login", null)
	check_update()

func _ping_tick() -> void:
	if not is_inside_tree():
		return
	Net.measure_ping()

## На телефоне экран вытянут вертикально, а размеры в приложении считаются
## от ширины окна. Берём для телефона узкую основу — тогда текст и кнопки
## получаются крупными, как в обычном мобильном приложении, а не мелкими.
func fit_mobile_screen() -> void:
	if not OS.has_feature("mobile"):
		return
	var win := get_window()
	if win == null:
		return
	win.content_scale_size = Vector2i(500, 1000)

## Тема приложения (цвета — в scripts/Style.gd)
func apply_theme() -> void:
	# Мягкость краёв фигур зависит от «Сглаживания» и работает в любом режиме.
	UiStyle.apply_aa_level(Store.aa_level())
	theme = UiStyle.build(Store.theme(), Store.aa_level())

## Сглаживание фигур (MSAA). Текст сглаживается шрифтом (см. UiStyle.aa_font).
## В простом графическом режиме (OpenGL) MSAA не поддерживается — тогда значение
## не выставляем вовсе, чтобы движок не ругался, и об этом сказано в настройках.
func apply_aa() -> void:
	if not UiStyle.shapes_aa_supported():
		return
	var modes := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
	get_viewport().msaa_2d = modes[clampi(Store.aa_level(), 0, 3)]

## Полная перерисовка: после смены языка, темы или сглаживания
func rebuild() -> void:
	apply_theme()
	apply_aa()
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

	# Всплывающие уведомления всегда поверх экрана
	if toast_layer != null and is_instance_valid(toast_layer):
		move_child(toast_layer, -1)

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
	Sfx.play("sent")
	Net.send_message(peer, text)
	return true

## Входящее сообщение из сети: сохраняем у себя и только тогда подтверждаем — сервер удалит.
func _on_net_message(from_nick: String, text: String, ts: int, net_id: String) -> bool:
	var saved := Store.receive_message(from_nick, text, ts, net_id)
	if saved:
		notify_new_message(from_nick, text)
	return saved

## Выйти на связь, если это включено в настройках и мы уже вошли
func maybe_connect() -> void:
	if Store.current_nick == "" or not Store.relay_auto():
		return
	check_nick()
	check_update()
	refresh_session()
	apply_session()
	if Net.is_online() and Net.nick == Store.current_nick:
		return
	Net.connect_to(Store.relay_host(), Store.relay_port(), Store.current_nick, Store.relay_key())

## Приложить пропуск к связи: по нему облако пускает к своим сообщениям
func apply_session() -> void:
	Net.auth_token = Store.auth_token()

## Пропуск живёт час. Если срок вышел — меняем его на новый по ключу обновления.
## Если обновить не вышло, человек всё равно продолжает работать: запасной путь.
func refresh_session() -> void:
	if Store.current_nick == "" or not P.is_cloud(Store.relay_host()):
		return
	if not Store.session_expired():
		return
	var refresh := Store.refresh_value()
	if refresh == "":
		return
	var nick := Store.current_nick
	Net.cloud_auth_refresh(Store.relay_host(), Store.relay_key(), refresh,
		func(ok: bool, _reason: String, session: Dictionary) -> void:
			if ok and is_inside_tree() and Store.current_nick == nick:
				Store.set_session(nick, session)
				apply_session())

## Сверить свой ник с облаком: занят ли он ещё кем-то. Заодно занять свой ник,
## чтобы больше никто не мог назваться так же. Делается один раз на вход.
func check_nick() -> void:
	if Store.current_nick == "" or Store.current_nick == _nick_checked:
		return
	# В проверках не трогаем настоящее облако — там живут ники живых людей.
	if OS.get_environment("TNGRAM_PROFILE").strip_edges() != "":
		return
	var host := Store.relay_host()
	if not P.is_cloud(host):
		return
	_nick_checked = Store.current_nick
	var nick := Store.current_nick
	var key := Store.relay_key()
	var my_hash := String(Store.current_account().get("pass_hash", ""))
	Net.cloud_lookup_nick(host, key, nick, func(ok: bool, taken: bool, other_hash: String) -> void:
		if not ok or not is_inside_tree():
			return
		if taken:
			# Ник занят, и пароль не наш — значит, за ним стоит другой человек.
			if other_hash != my_hash:
				Store.flag_nick_conflict()
			return
		Net.cloud_claim_nick(host, key, nick, my_hash, func(_ok: bool, _busy: bool) -> void:
			pass))

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
	blob.texture = UiStyle.glow_texture(Color(color.r, color.g, color.b, strength),
		Color(0, 0, 0, 0), UiStyle.glow_size(Store.aa_level()))
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

## ---------------------------------------------------------------- звук

## Звук нового сообщения. Если сейчас открыт именно этот чат — карточку не
## показываем (и так всё видно), но звук оставляем.
func notify_new_message(from_nick: String, text: String) -> void:
	Sfx.play("incoming")
	if from_nick == current_peer():
		return
	if Store.notify_on():
		show_toast(from_nick, text)
		DisplayServer.window_request_attention()

## Ник открытого сейчас чата ("" — открыт не чат)
func current_peer() -> String:
	if current_id != "chat" or current_arg == null:
		return ""
	return String(current_arg)

## ---------------------------------------------------------------- уведомления

## Всплывающая карточка «пришло сообщение». Сама исчезает через несколько секунд,
## щелчок открывает чат с этим человеком.
func show_toast(from_nick: String, text: String) -> void:
	var layer := ensure_toast_layer()
	if layer == null or toast_column == null:
		return
	var holder := toast_column

	var p := UiStyle.palette(Store.theme())
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(p["panel_strong"], 18, p["a2"] * Color(1, 1, 1, 0.45), 1, 14))
	card.custom_minimum_size = Vector2(300, 0)
	card.modulate = Color(1, 1, 1, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var title := Label.new()
	title.text = from_nick
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", p["a2"])
	box.add_child(title)

	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", p["text"])
	body.custom_minimum_size = Vector2(280, 0)
	body.max_lines_visible = 3
	box.add_child(body)

	# Щелчок по карточке открывает переписку
	var catcher := Button.new()
	catcher.flat = true
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0), 18, Color(0, 0, 0, 0), 0, 14))
	catcher.add_theme_stylebox_override("hover", UiStyle.box(Color(1, 1, 1, 0.05), 18, Color(0, 0, 0, 0), 0, 14))
	catcher.add_theme_stylebox_override("pressed", UiStyle.box(Color(1, 1, 1, 0.09), 18, Color(0, 0, 0, 0), 0, 14))
	catcher.pressed.connect(func() -> void:
		_remove_toast(card)
		show_screen("chat", from_nick))
	card.add_child(catcher)

	holder.add_child(card)

	# Твин привязан к самой карточке: когда карточка удалится, твин умрёт вместе
	# с ней и не останется «висеть» (иначе при выходе движок сообщает об утечке).
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.18)
	tween.tween_interval(4.0)
	tween.tween_property(card, "modulate:a", 0.0, 0.35)
	tween.tween_callback(func() -> void: _remove_toast(card))

## Слой карточек: создаётся при первой надобности и всегда поверх экрана
func ensure_toast_layer() -> Control:
	if toast_layer != null and is_instance_valid(toast_layer):
		return toast_layer
	toast_layer = Control.new()
	toast_layer.name = "Toasts"
	toast_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	column.offset_left = -340
	column.offset_right = -20
	column.offset_top = 20
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(column)
	toast_column = column
	add_child(toast_layer)
	move_child(toast_layer, -1)
	return toast_layer

func _remove_toast(card: Control) -> void:
	# Анимация карточки привязана к ней самой, поэтому уйдёт вместе с карточкой.
	if card != null and is_instance_valid(card):
		card.queue_free()

## Убрать все всплывающие карточки (например, при выходе из аккаунта)
func clear_toasts() -> void:
	if toast_column != null and is_instance_valid(toast_column):
		for child in toast_column.get_children():
			child.queue_free()

## ---------------------------------------------------------------- обновления

## Проверить на сайте, не вышла ли новая версия. Тихо ничего не делает, если
## сайта нет или интернета нет: обновление — не повод мешать работать.
func check_update() -> void:
	if _update_checked:
		return
	# В проверках настоящее облако и сайт не трогаем
	if OS.get_environment("TNGRAM_PROFILE").strip_edges() != "":
		return
	_update_checked = true
	var base := Store.site_url()
	if base.strip_edges() == "":
		return
	var url := base.trim_suffix("/") + "/" + P.UPDATE_FILE
	Net.fetch_text(url, func(ok: bool, text: String) -> void:
		if not ok or not is_inside_tree():
			return
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			return
		var remote := String((parsed as Dictionary).get("version", "")).strip_edges()
		if remote == "" or P.version_compare(remote, P.APP_VERSION) <= 0:
			return
		var fresh := remote != Store.remote_version()
		Store.set_remote_version(remote)
		if fresh:
			Sfx.play("notice")
			show_toast(Loc.t("update_title"), Loc.tf("update_toast", [remote]))
		if screen != null and is_instance_valid(screen) and screen.has_method("rebuild"):
			screen.rebuild())

## Открыть сайт приложения в браузере (кнопка «Обновиться»)
func open_site() -> void:
	var url := Store.site_url()
	if url.strip_edges() != "":
		OS.shell_open(url)
