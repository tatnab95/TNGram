extends ScreenBase
## Экран создания ника: имя + необязательный пароль. Номер телефона не нужен.

var error_code := ""
var typed_nick := ""   ## что ввёл человек, чтобы не потерять при перерисовке

func _ready() -> void:
	build()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	build()

func build() -> void:
	# Прокрутка — на случай маленького окна
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

	# Заголовок
	var title := heading(Loc.t("new_title"), 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var sub := hint(Loc.t("new_subtitle"), 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	column.add_child(gap(8))

	# Поля
	var nick_pair := text_field(Loc.t("new_nick"), Loc.t("new_nick_hint"), false)
	column.add_child(nick_pair[0])
	var pass_pair := text_field(Loc.t("new_password"), Loc.t("new_password_hint"), true)
	column.add_child(pass_pair[0])
	var repeat_pair := text_field(Loc.t("new_password_repeat"), "", true)
	column.add_child(repeat_pair[0])

	var nick_edit: LineEdit = nick_pair[1]
	var pass_edit: LineEdit = pass_pair[1]
	var repeat_edit: LineEdit = repeat_pair[1]
	nick_edit.text = typed_nick

	# Ошибка
	if error_code != "":
		column.add_child(label(Loc.t(error_code), 14, Color("#ff9a9a")))

	# Ник занят: второй такой же создать нельзя — предлагаем просто войти под ним
	if nick_is_taken():
		column.add_child(hint(Loc.t("new_nick_taken_hint"), 13))
		var enter := accent_button(Loc.t("new_nick_taken_login"), func() -> void:
			navigate.emit("login", nick_edit.text.strip_edges()))
		column.add_child(enter)

	# Кнопка создания
	var submit := accent_button(Loc.t("new_submit"), func() -> void:
		_submit(nick_edit.text, pass_edit.text, repeat_edit.text))
	column.add_child(submit)

	var back := ghost_button(Loc.t("back"), func() -> void:
		navigate.emit("login", null))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(back)

	column.add_child(gap(4))
	column.add_child(hint(Loc.t("new_no_password_note"), 13))

	nick_edit.grab_focus()

## ------------------------------------------------------------- действия

## Ник уже существует (здесь или в облаке) — тогда предлагаем войти, а не злиться
func nick_is_taken() -> bool:
	return error_code in ["err_nick_used", "err_nick_cloud_taken", "err_nick_exists_login"]

func _submit(nick: String, password: String, repeat: String) -> void:
	typed_nick = nick.strip_edges()
	if password != repeat:
		error_code = "err_pass_mismatch"
		rebuild()
		return

	if password != "" and password.length() < P.AUTH_MIN_PASSWORD:
		error_code = "err_pass_short"
		rebuild()
		return

	var err := Store.nick_error(nick)
	if err != "":
		error_code = err
		rebuild()
		return

	# Спросить облако: свободен ли ник для всех, а не только на этом устройстве.
	var verdict := await _cloud_verdict(nick, password)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if verdict == "taken":
		error_code = "err_nick_cloud_taken"
		rebuild()
		return
	if verdict == "free":
		# Занимаем ник, чтобы больше никто не смог назваться так же.
		var claimed := await _claim_nick(nick, password)
		if not is_instance_valid(self) or not is_inside_tree():
			return
		if not claimed:
			error_code = "err_nick_cloud_taken"
			rebuild()
			return

	# Заводим вход в облаке: сервер проверит пароль и выдаст пропуск в переписку.
	var auth := { "verdict": "skip", "session": {} }
	if password != "":
		auth = await _cloud_auth(nick, password)
		if not is_instance_valid(self) or not is_inside_tree():
			return
		if String(auth["verdict"]) == "taken":
			error_code = "err_nick_cloud_taken"
			rebuild()
			return

	var result := Store.create_account(nick, password)
	if not bool(result.get("ok", false)):
		error_code = String(result.get("error", ""))
		rebuild()
		return

	# Пропуск кладём только теперь: до создания аккаунта его некуда положить.
	if not (auth["session"] as Dictionary).is_empty():
		Store.set_session(nick, auth["session"])

	var login_result := Store.login(nick, password)
	if bool(login_result.get("ok", false)):
		navigate.emit("chats", null)
		return
	error_code = String(login_result.get("error", ""))
	rebuild()

## ------------------------------------------------------------- облако

## "free" — ник свободен; "mine" — занят, но пароль наш; "taken" — чужой;
## "unknown" — облако не отвечает или не настроено (тогда просто создаём локально).
func _cloud_verdict(nick: String, password: String) -> String:
	var host := Store.relay_host()
	if not P.is_cloud(host):
		return "unknown"
	# В проверках не трогаем настоящее облако — там живут ники живых людей.
	if OS.get_environment("TNGRAM_PROFILE").strip_edges() != "":
		return "unknown"
	var tree := get_tree()
	var state := { "done": false, "ok": false, "taken": false, "hash": "" }
	Net.cloud_lookup_nick(host, Store.relay_key(), nick,
		func(ok: bool, taken: bool, hash: String) -> void:
			state["ok"] = ok
			state["taken"] = taken
			state["hash"] = hash
			state["done"] = true)
	var deadline := Time.get_ticks_msec() + 5000
	while not bool(state["done"]) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if not is_instance_valid(self):
			return "unknown"
	if not bool(state["ok"]):
		return "unknown"
	if not bool(state["taken"]):
		return "free"
	return "mine" if String(state["hash"]) == Store.hash_password(password) else "taken"

func _claim_nick(nick: String, password: String) -> bool:
	var tree := get_tree()
	var state := { "done": false, "ok": false, "busy": false }
	Net.cloud_claim_nick(Store.relay_host(), Store.relay_key(), nick, Store.hash_password(password),
		func(ok: bool, busy: bool) -> void:
			state["ok"] = ok
			state["busy"] = busy
			state["done"] = true)
	var deadline := Time.get_ticks_msec() + 5000
	while not bool(state["done"]) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if not is_instance_valid(self):
			return false
	return bool(state["ok"]) and not bool(state["busy"])

## Завести вход в облаке для нового ника. Возвращает { "verdict", "session" }:
## "ok" — пропуск получен; "taken" — ник за другим человеком (пароль не подошёл);
## "skip" — облака нет или оно не ответило: аккаунт всё равно создастся здесь.
func _cloud_auth(nick: String, password: String) -> Dictionary:
	if not P.is_cloud(Store.relay_host()):
		return { "verdict": "skip", "session": {} }
	if OS.get_environment("TNGRAM_PROFILE").strip_edges() != "":
		return { "verdict": "skip", "session": {} }
	var state := { "done": false, "ok": false, "reason": "", "session": {} }
	Net.cloud_auth_signup(Store.relay_host(), Store.relay_key(), nick, password,
		func(ok: bool, reason: String, session: Dictionary) -> void:
			state["done"] = true
			state["ok"] = ok
			state["reason"] = reason
			state["session"] = session)
	await _await_state(state, 10000)
	if bool(state["ok"]):
		return { "verdict": "ok", "session": state["session"] }
	# Ник на сервере уже есть. Если пароль наш — значит, это мы на другом устройстве.
	if String(state["reason"]) == "user_already_exists":
		var mine := { "done": false, "ok": false, "session": {} }
		Net.cloud_auth_login(Store.relay_host(), Store.relay_key(), nick, password,
			func(ok: bool, _reason: String, session: Dictionary) -> void:
				mine["done"] = true
				mine["ok"] = ok
				mine["session"] = session)
		await _await_state(mine, 10000)
		if bool(mine["ok"]):
			return { "verdict": "ok", "session": mine["session"] }
		if bool(mine["done"]):
			return { "verdict": "taken", "session": {} }
	return { "verdict": "skip", "session": {} }

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

func gap(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node

## Подпись + поле ввода. Возвращает [контейнер, поле]
func text_field(caption: String, placeholder: String, secret: bool) -> Array:
	var box := vbox(6)
	box.add_child(label(caption, 13, pal()["muted"]))

	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.custom_minimum_size = Vector2(0, 46)
	box.add_child(edit)

	return [box, edit]
