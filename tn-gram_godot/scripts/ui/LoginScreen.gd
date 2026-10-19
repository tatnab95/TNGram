extends ScreenBase
## Экран входа: выбор аккаунта на устройстве, вход, переход к созданию ника.

var password_for := ""   ## если не пусто — показываем шаг ввода пароля
var error_code := ""
var busy := false        ## спрашиваем сервер — кнопку временно не нажимать
var prefill := ""        ## ник, который надо открыть сразу (пришли с экрана создания)

func _ready() -> void:
	if prefill.strip_edges() != "" and password_for == "":
		password_for = prefill.strip_edges()
	build()

## Перерисовать экран (после смены языка и т. п.)
func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	build()

func build() -> void:
	# Раскладка: содержимое по центру окна, шириной 440.
	# Прокрутка нужна на случай маленького окна — тогда ничего не обрежется.
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

	var column := vbox(11)
	column.custom_minimum_size = Vector2(440, 0)
	row.add_child(column)
	row.add_child(spacer())

	outer.add_child(vspacer())

	# Язык (можно переключить ещё до входа)
	column.add_child(lang_row())

	# Иконка и название
	var logo := TextureRect.new()
	logo.texture = load("res://icon.png")
	logo.custom_minimum_size = Vector2(68, 68)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(logo)

	var name_label := heading(Loc.t("app_name"), 30)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)

	var tagline := hint(Loc.t("app_tagline"), 14)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tagline)

	column.add_child(gap(6))

	if password_for == "":
		build_account_list(column)
	else:
		build_password_step(column)

## ------------------------------------------------------------- список аккаунтов

func build_account_list(column: VBoxContainer) -> void:
	column.add_child(title_block(Loc.t("login_title"), Loc.t("login_subtitle")))

	if Store.accounts.is_empty():
		column.add_child(hint(Loc.t("login_no_accounts")))
	else:
		var list := vbox(10)
		for acc in Store.accounts:
			var nick := String(acc.get("nick", ""))
			var subtitle := Loc.t("login_password_hint") if Store.has_password(nick) else ""
			list.add_child(contact_button(nick, subtitle, "", _on_pick_account.bind(nick)))
		column.add_child(list)

	column.add_child(gap(6))
	var create := accent_button(Loc.t("login_create"), func() -> void:
		navigate.emit("new", null))
	create.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(create)

## ------------------------------------------------------------- шаг с паролем

func build_password_step(column: VBoxContainer) -> void:
	column.add_child(avatar(password_for, 64))
	var who := heading(password_for, 24)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(who)

	if error_code != "":
		var err := label(Loc.t(error_code), 14, Color("#ff9a9a"))
		err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(err)

	var field := LineEdit.new()
	field.secret = true
	field.placeholder_text = Loc.t("login_password")
	field.custom_minimum_size = Vector2(0, 46)
	column.add_child(field)

	var enter := accent_button(Loc.t("login_enter"), func() -> void: _try_login(password_for, field.text))
	enter.disabled = busy
	column.add_child(enter)
	if busy:
		var waiting := hint(Loc.t("login_checking"))
		waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(waiting)
	field.text_submitted.connect(func(_t: String) -> void: _try_login(password_for, field.text))

	var back := ghost_button(Loc.t("login_back"), func() -> void:
		password_for = ""
		error_code = ""
		rebuild())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(back)

	field.grab_focus()

## ------------------------------------------------------------- действия

func _on_pick_account(nick: String) -> void:
	if Store.has_password(nick):
		password_for = nick
		error_code = ""
		rebuild()
		return
	_try_login(nick, "")

func _try_login(nick: String, password: String) -> void:
	# Ника на этом устройстве ещё нет. Если он есть в облаке (человек создал его
	# на другом телефоне) — входим, а не создаём второй такой же.
	if not Store.account_exists(nick):
		await _login_cloud_only(nick, password)
		return
	if busy:
		return
	var result := Store.login(nick, password)
	if not bool(result.get("ok", false)):
		error_code = String(result.get("error", ""))
		password_for = nick
		rebuild()
		return
	# Пароль верный на устройстве. Если облако доступно — спрашиваем у него:
	# главное слово за сервером, он знает, чей ник на самом деле.
	if password.strip_edges() != "" and _cloud_ready():
		busy = true
		error_code = ""
		password_for = nick
		rebuild()
		var verdict := await _cloud_login(nick, password)
		if not is_instance_valid(self) or not is_inside_tree():
			return
		busy = false
		if verdict == "wrong":
			Store.logout()
			error_code = "err_pass_wrong"
			password_for = nick
			rebuild()
			return
	navigate.emit("chats", null)

## Облако вообще применимо? В проверках настоящее облако не трогаем.
func _cloud_ready() -> bool:
	if OS.get_environment("TNGRAM_PROFILE").strip_edges() != "":
		return false
	return P.is_cloud(Store.relay_host())

## Спросить сервер, наш ли это ник и пароль. Возвращает:
## "ok" — пустил (пропуск сохранён), "wrong" — пароль не тот, "offline" — молчит.
## Если ника на сервере ещё нет (аккаунт заведён раньше входа), заводим его.
func _cloud_login(nick: String, password: String) -> String:
	var state := { "done": false, "ok": false, "reason": "" }
	Net.cloud_auth_login(Store.relay_host(), Store.relay_key(), nick, password,
		func(ok: bool, reason: String, session: Dictionary) -> void:
			state["done"] = true
			state["ok"] = ok
			state["reason"] = reason
			if ok:
				Store.set_session(nick, session))
	await _await_state(state, 10000)
	if not bool(state["done"]):
		return "offline"
	if bool(state["ok"]):
		return "ok"
	var reason := String(state["reason"])
	if reason != "invalid_credentials" and reason != "user_not_found":
		return "offline"
	# Ника на сервере нет — заводим его с этим же паролем
	var signup := { "done": false, "ok": false, "reason": "" }
	Net.cloud_auth_signup(Store.relay_host(), Store.relay_key(), nick, password,
		func(ok: bool, r: String, session: Dictionary) -> void:
			signup["done"] = true
			signup["ok"] = ok
			signup["reason"] = r
			if ok:
				Store.set_session(nick, session))
	await _await_state(signup, 10000)
	if not bool(signup["done"]):
		return "offline"
	if bool(signup["ok"]):
		return "ok"
	if String(signup["reason"]) == "user_already_exists":
		return "wrong"
	return "offline"

## Вход под ником, которого нет на этом устройстве: спрашиваем облако. Если
## пароль верный — заводим вход здесь. Нового ника не появляется: это тот же ник.
func _login_cloud_only(nick: String, password: String) -> void:
	var clean := nick.strip_edges()
	if OS.get_environment("TNGRAM_PROFILE").strip_edges() != "" or not P.is_cloud(Store.relay_host()):
		error_code = "err_no_account"
		password_for = clean
		rebuild()
		return
	busy = true
	error_code = ""
	password_for = clean
	rebuild()
	var state := { "done": false, "ok": false, "reason": "", "session": {} }
	Net.cloud_auth_login(Store.relay_host(), Store.relay_key(), clean, password,
		func(ok: bool, reason: String, session: Dictionary) -> void:
			state["done"] = true
			state["ok"] = ok
			state["reason"] = reason
			state["session"] = session)
	await _await_state(state, 10000)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	busy = false
	if not bool(state["done"]):
		error_code = "err_no_account"
	elif not bool(state["ok"]):
		var reason := String(state["reason"])
		error_code = "err_pass_wrong" if reason == "invalid_credentials" else "err_no_account"
	if error_code != "":
		rebuild()
		return
	if not Store.account_exists(clean):
		Store.create_account(clean, password)
	Store.set_session(clean, state["session"])
	var result := Store.login(clean, password)
	if bool(result.get("ok", false)):
		navigate.emit("chats", null)
		return
	error_code = String(result.get("error", ""))
	rebuild()

## Ждать ответа сети, но не дольше отведённого срока
func _await_state(state: Dictionary, ms: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var deadline := Time.get_ticks_msec() + ms
	while not bool(state.get("done", false)) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if not is_instance_valid(self):
			return

## ------------------------------------------------------------- вспомогательное

## Небольшой вертикальный отступ
func gap(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node

## Заголовок с подзаголовком
func title_block(title: String, subtitle: String) -> VBoxContainer:
	var box := vbox(4)
	var title_label := heading(title, 24)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	var sub := hint(subtitle, 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	return box

## Переключатель языка
func lang_row() -> HBoxContainer:
	var row := hbox(6)
	row.add_child(spacer())
	for code in ["ru", "en"]:
		var active: bool = Loc.lang == code
		row.add_child(toggle_button(code.to_upper(), active, func() -> void:
			Store.set_lang(code)
			Loc.lang = code
			app().rebuild()))
	return row
