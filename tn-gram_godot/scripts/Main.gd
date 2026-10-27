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
	"newgroup": preload("res://scripts/ui/NewGroupScreen.gd"),
	"news": preload("res://scripts/ui/NewsScreen.gd"),
	"settings": preload("res://scripts/ui/SettingsScreen.gd")
}

const P := preload("res://scripts/net/Protocol.gd")

## Как часто говорим облаку «я здесь» и как часто спрашиваем про других.
const PRESENCE_BEAT := 25.0
const PRESENCE_LOOK := 12.0

var current_id := "login"
var current_arg: Variant = null
var screen: Control = null
var background: Control = null
var _nick_checked := ""  ## ник, который уже сверили с облаком (чтобы не дёргать зря)
var _update_checked := false  ## версию на сайте проверяем один раз за запуск
var _update_answer: Callable = Callable()  ## кому сказать, чем кончилась проверка версии
var _presence_beat := 2.0  ## через сколько отметить себя в сети
var _presence_look := 5.0  ## через сколько спросить про остальных
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
	# В отладочной сборке пишем всю сеть в журнал — видно в logcat (телефон)
	# и в консоли (компьютер)
	if OS.is_debug_build():
		Net.debug = true
		Net.notice.connect(func(text: String) -> void: print("[сеть] ", text))
		print("[сеть] запуск: ник=", Store.current_nick, " адрес=", Store.relay_host(),
			" автоподключение=", Store.relay_auto())
	# Периодический замер пинга
	var ping_timer := Timer.new()
	ping_timer.wait_time = 8.0
	ping_timer.timeout.connect(_ping_tick)
	ping_timer.autostart = true
	add_child(ping_timer)
	show_screen("chats" if Store.current_nick != "" else "login", null)
	check_update()
	# На телефоне один раз просим разрешение на уведомления (Android 13+).
	TnAndroidNotify.ensure_permission()

## Когда окно снова в фокусе — убираем уведомление открытого чата из шторки
## (его уже прочитали). На компьютере метод ничего не делает.
func _notification(what: int) -> void:
	var focused := (
		what == NOTIFICATION_WM_WINDOW_FOCUS_IN
		or what == NOTIFICATION_APPLICATION_FOCUS_IN
		or what == NOTIFICATION_APPLICATION_RESUMED
	)
	if focused:
		var peer := current_peer()
		if peer != "":
			TnAndroidNotify.cancel(peer)

func _ping_tick() -> void:
	if not is_inside_tree():
		return
	Net.measure_ping()

## Пульс приложения: «я здесь» для облака и вопрос «кто ещё здесь».
## Работает тихо: если сети нет — просто ничего не делает.
func _process(delta: float) -> void:
	if Store.current_nick == "":
		return
	_presence_beat -= delta
	if _presence_beat <= 0.0:
		_presence_beat = PRESENCE_BEAT
		presence_beat()
	_presence_look -= delta
	if _presence_look <= 0.0:
		_presence_look = PRESENCE_LOOK
		presence_look()

## Отметить себя в сети. Без облака или без входа ничего не делаем.
func presence_beat() -> void:
	if Store.current_nick == "" or OS.get_environment("TNGRAM_PROFILE").strip_edges() != "":
		return
	if not P.is_cloud(Store.relay_host()):
		return
	var nick := Store.current_nick
	Net.cloud_presence_ping(Store.relay_host(), Store.relay_key(), nick, func(ok: bool) -> void:
		if ok and is_inside_tree():
			Store.note_seen(nick, int(Time.get_unix_time_from_system())))

## Спросить облако, кто из знакомых в сети (обновляет зелёные точки)
func presence_look() -> void:
	if Store.current_nick == "" or not P.is_cloud(Store.relay_host()):
		return
	if OS.get_environment("TNGRAM_PROFILE").strip_edges() != "":
		return
	var keys := Store.presence_keys()
	var open_key := P.nick_key(_peer_nick())
	if open_key != "" and not keys.has(open_key):
		keys.append(open_key)
	if keys.is_empty():
		return
	Net.cloud_presence_get(Store.relay_host(), Store.relay_key(), keys, func(ok: bool, found: Dictionary) -> void:
		if ok and is_inside_tree() and not found.is_empty():
			Store.apply_presence(found))

## Ник того, с кем открыт чат (пусто — чат не открыт или это группа)
func _peer_nick() -> String:
	if current_id != "chat" or current_arg == null:
		return ""
	var key := String(current_arg)
	if P.is_ai_key(key):
		return ""
	return "" if Store.is_group(key) else key

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
	elif id == "login" and arg != null:
		# Пришли с экрана создания ника: сразу открываем вход под этим ником
		node.set("prefill", String(arg))
	add_child(node)
	node.navigate.connect(_on_navigate)
	screen = node
	# Плавное появление экрана (на телефоне ещё и подъём снизу)
	Anim.screen_in(node)

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
## Если собеседник — группа, письмо уходит всем участникам (см. send_group_message).
## Собеседник «ИИ-помощник» — локальный: ответ рождается прямо в приложении,
## сеть ему не нужна вообще.
func send_message(peer: String, text: String) -> bool:
	if P.is_ai_key(peer):
		if not Store.send_message(peer, text):
			return false
		Sfx.play("sent")
		_ai_reply_later(text)
		return true
	if Store.is_group(peer):
		return send_group_message(peer, text)
	if not Store.send_message(peer, text):
		return false
	Sfx.play("sent")
	Net.send_message(peer, text)
	return true

## Ответ слабого ИИ: через мгновение в чат приходит локальное сообщение.
## Если человек уже ушёл из чата — просто загорится значок непрочитанного.
func _ai_reply_later(asked: String) -> void:
	var answer := AiBot.reply(asked, Loc.lang)
	var nick := Store.current_nick
	var timer := get_tree().create_timer(0.75)
	timer.timeout.connect(func() -> void:
		if not is_inside_tree() or nick == "" or Store.current_nick != nick:
			return
		if Store.receive_message(P.AI_KEY, answer):
			Sfx.play("incoming"))

## Отправить в группу: сохраняем у себя, а каждому участнику уходит копия.
## Название группы и её состав едут вместе с текстом — получатель заводит
## такую же группу у себя, поэтому отдельных таблиц для групп не нужно.
func send_group_message(key: String, text: String) -> bool:
	if not Store.send_group_message(key, text):
		return false
	Sfx.play("sent")
	var title := Store.group_title(key)
	var owner_nick := String(Store.group_info(key).get("owner", ""))
	# В шапку едет полный состав (включая создателя и меня), а уходит копия
	# всем, кроме меня. Так у каждого участника группа выглядит одинаково
	# и ответ доходит до всех.
	var packed := P.encode_group(key, title, Store.group_roster(key), text, owner_nick)
	for member in Store.group_members(key):
		Net.send_message(member, packed)
	return true

## Входящее сообщение из сети: сохраняем у себя и только тогда подтверждаем — сервер удалит.
func _on_net_message(from_nick: String, text: String, ts: int, net_id: String) -> bool:
	if OS.is_debug_build():
		print("[сеть] входящее от ", from_nick, ": ", text)
	var group := P.decode_group(text)
	if not group.is_empty():
		return _take_group_message(from_nick, group, ts, net_id)
	var saved := Store.receive_message(from_nick, text, ts, net_id)
	if saved:
		notify_new_message(from_nick, text)
	return saved

## Сообщение из группы: заводим группу (если впервые слышим) и записываем текст
func _take_group_message(from_nick: String, group: Dictionary, ts: int, net_id: String) -> bool:
	var key := String(group.get("key", ""))
	var title := String(group.get("title", ""))
	var body := String(group.get("text", ""))
	if body.strip_edges() == "":
		return true
	var raw_members: Variant = group.get("members", [])
	var roster: Array = raw_members if typeof(raw_members) == TYPE_ARRAY else []
	var owner_nick := String(group.get("owner", ""))
	var saved := Store.receive_group_message(from_nick, key, title, roster, body, ts, net_id, owner_nick)
	if saved:
		notify_new_message(title if title != "" else key, body, from_nick)
	return saved

## Выйти на связь, если это включено в настройках и мы уже вошли
func maybe_connect() -> void:
	if Store.current_nick == "" or not Store.relay_auto():
		if OS.is_debug_build():
			print("[сеть] подключение пропущено: ник=", Store.current_nick,
				" автоподключение=", Store.relay_auto())
		return
	if OS.is_debug_build():
		print("[сеть] подключаемся: ", Store.relay_host(), " от лица ", Store.current_nick)
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
	# Фон мягко дышит: пятно медленно покачивается вверх-вниз
	Anim.breathe(blob, 14.0, 7.0 + randf() * 4.0)

## ---------------------------------------------------------------- звук

## Звук нового сообщения. Если сейчас открыт именно этот чат — карточку не
## показываем (и так всё видно), но звук оставляем.
## group_title не пустой, если сообщение пришло в группу: тогда карточка
## подписывается названием группы, а внутри видно, кто написал.
func notify_new_message(from_nick: String, text: String, group_title: String = "") -> void:
	Sfx.play("incoming")
	var peer := group_title if group_title != "" else from_nick
	var open := current_peer()
	if _same_peer(open, peer):
		return
	if not Store.notify_on():
		return
	var in_group := group_title != ""
	var title := peer
	var body := (from_nick + ": " + text) if in_group else text
	# Свёрнутое окно или другое приложение поверх — сообщение всё равно заметят:
	# на телефоне уведомление уходит в шторку, на Windows всплывает системное
	# уведомление, на телефоне дополнительно вибрация.
	var hidden := not has_focus()
	if OS.is_debug_build():
		print("[уведомления] сообщение: чат=", peer, " свёрнуто=", hidden,
			" android=", OS.has_feature("android"),
			" готово=", TnAndroidNotify.available(),
			" настройка=", Store.notify_os())
	# На Android уведомление в шторке нужно всегда, когда чат не открыт
	if Store.notify_os() and OS.has_feature("android") and TnAndroidNotify.available():
		if TnAndroidNotify.post(peer, title, body):
			if hidden and OS.has_feature("mobile"):
				Input.vibrate_handheld(220)
			if hidden:
				DisplayServer.window_request_attention()
			return
	if Store.notify_os() and hidden and OS.has_feature("android") and TnAndroidNotify.post(peer, title, body):
		return
	if Store.notify_os() and hidden and TnNotify.toast(title, body):
		DisplayServer.window_request_attention()
		return
	if hidden and OS.has_feature("mobile"):
		Input.vibrate_handheld(220)
	show_toast(peer, text, from_nick if in_group else "")
	DisplayServer.window_request_attention()

## Это один и тот же чат? Регистр букв не важен.
func _same_peer(a: String, b: String) -> bool:
	return a != "" and b != "" and P.nick_key(a) == P.nick_key(b)

## Ник открытого сейчас чата ("" — открыт не чат)
func current_peer() -> String:
	if current_id != "chat" or current_arg == null:
		return ""
	return String(current_arg)

## ---------------------------------------------------------------- уведомления

## Всплывающая карточка «пришло сообщение». Сама исчезает через несколько секунд,
## щелчок открывает чат с этим человеком (или с группой).
## author не пустой у групп: «название группы» + «кто написал: текст».
func show_toast(peer: String, text: String, author: String = "") -> void:
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
	title.text = peer
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", p["a2"])
	box.add_child(title)

	var body := Label.new()
	body.text = (author + ": " + text) if author != "" else text
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
		show_screen("chat", peer))
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

## Проверить, не вышла ли новая версия: сначала сайт, потом облако (таблица
## version). Тихо ничего не делает, если ни того, ни другого нет: обновление —
## не повод мешать работать. answer — кому сообщить, чем кончилось (для кнопки
## «Проверить обновления» в настройках).
func check_update(force: bool = false, answer: Callable = Callable()) -> void:
	if force:
		_update_checked = false
	if _update_checked:
		return
	# В проверках настоящее облако и сайт не трогаем
	if OS.get_environment("TNGRAM_PROFILE").strip_edges() != "":
		return
	_update_checked = true
	_update_answer = answer
	# Страховка: если ни сайт, ни облако не ответили, всё равно сообщаем, что
	# проверка закончилась — иначе кнопка так и останется «Проверяю…».
	var watchdog := get_tree().create_timer(4.0)
	watchdog.timeout.connect(func() -> void: _report_update(Store.remote_version()))
	var base := Store.site_url()
	if base.strip_edges() != "":
		var url := base.trim_suffix("/") + "/" + P.UPDATE_FILE
		Net.fetch_text(url, func(ok: bool, text: String) -> void:
			if not ok:
				return
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				take_update(parsed as Dictionary))
	Net.cloud_fetch_version(Store.cloud_url(), Store.cloud_key(), func(ok: bool, info: Dictionary) -> void:
		if ok:
			take_update(info))

## Запомнить увиденную версию и, если она новее нашей, сказать об этом.
func take_update(info: Dictionary) -> void:
	if not is_inside_tree():
		return
	var remote := String(info.get("version", "")).strip_edges()
	var url := String(info.get("url", "")).strip_edges()
	if url != "":
		Store.set_update_url(url)
	if remote == "" or P.version_compare(remote, P.APP_VERSION) <= 0:
		_report_update(remote)
		return
	# Держим самый свежий из увиденных номеров: сайт и облако могут ответить врозь
	if P.version_compare(remote, Store.remote_version()) > 0:
		Store.set_remote_version(remote)
	var already := remote == Store.last_seen_version()
	Store.set_last_seen_version(remote)
	if not already:
		Sfx.play("notice")
		show_toast(Loc.t("update_title"), Loc.tf("update_toast", [remote]))
	if screen != null and is_instance_valid(screen) and screen.has_method("rebuild"):
		screen.rebuild()
	_report_update(remote)

func _report_update(remote: String) -> void:
	if _update_answer.is_valid():
		var said := _update_answer
		_update_answer = Callable()
		said.call(remote)

## Открыть страницу обновления (кнопка «Обновить»).
## На телефоне — сразу скачивание установщика: компьютер не нужен,
## готовый APK скачается с сайта и встанет поверх старой версии.
func open_update() -> void:
	if OS.has_feature("android"):
		OS.shell_open(P.apk_url())
		return
	var url := Store.update_url()
	if url.strip_edges() != "":
		OS.shell_open(url)

## Открыть сайт приложения в браузере (кнопка «Обновиться»)
func open_site() -> void:
	var url := Store.site_url()
	if url.strip_edges() != "":
		OS.shell_open(url)
