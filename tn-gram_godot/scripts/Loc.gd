extends Node
## Переводы интерфейса приложения. Меняй тексты прямо здесь.
## Подключается как автозагрузка (Autoload) с именем Loc.

var lang := "ru"

const STRINGS := {
	"ru": {
		# --- общее ---
		"app_name": "Тнграм",
		"app_tagline": "Приватный мессенджер",
		"ok": "Готово",
		"cancel": "Отмена",
		"back": "Назад",
		"soon": "Скоро",
		"delete": "Удалить",

		# --- вход ---
		"login_title": "Кто ты?",
		"login_subtitle": "Выбери аккаунт или создай новый ник. Номер телефона не нужен.",
		"login_pick": "Аккаунты на этом устройстве",
		"login_enter": "Войти",
		"login_create": "Создать ник",
		"login_no_accounts": "Аккаунтов пока нет — создай первый ник.",
		"login_password": "Пароль",
		"login_password_hint": "Если у ника есть пароль",
		"login_back": "К списку аккаунтов",

		# --- создание ника ---
		"new_title": "Новый ник",
		"new_subtitle": "Ник — это твой адрес в Тнграме. Телефон и почта не нужны.",
		"new_nick": "Ник",
		"new_nick_hint": "например, твой_ник",
		"new_password": "Пароль (не обязательно)",
		"new_password_hint": "придумай пароль, если хочешь защитить ник",
		"new_password_repeat": "Повтори пароль",
		"new_submit": "Создать и войти",
		"new_no_password_note": "Без пароля в аккаунт сможет войти любой, у кого есть это устройство.",

		# --- чаты ---
		"chats_title": "Чаты",
		"chats_empty": "Пока никого. Создай второй ник — и сможешь проверить переписку.",
		"chats_new_nick": "Новый ник",
		"chats_logout": "Выйти",
		"chats_you": "Это ты",
		"chats_no_messages": "Сообщений пока нет",
		"chats_on_device": "Переписка хранится только на этом устройстве",
		"chats_remote": "собеседник по сети",

		# --- чат ---
		"chat_placeholder": "Сообщение…",
		"chat_send": "Отправить",
		"chat_empty": "Напиши первое сообщение",
		"chat_delete": "Удалить переписку",
		"chat_delete_confirm": "Удалить всю переписку с %s? Восстановить её будет нельзя.",
		"chat_with": "Чат с ",

		# --- настройки ---
		"settings": "Настройки",
		"settings_lang": "Язык",
		"settings_theme": "Тема",
		"theme_dark": "Тёмная",
		"theme_green": "Зелёная",
		"theme_blue": "Синяя",
		"settings_account": "Аккаунт",
		"settings_delete_account": "Удалить аккаунт",
		"settings_delete_confirm": "Удалить аккаунт %s и всю его переписку?",
		"settings_about": "О приложении",
		"settings_about_text": "Тнграм ещё в разработке. Сообщение уходит на сервер (свой или облачный), доходит до получателя и удаляется с сервера.",
		"settings_soon_server": "Свой сервер работает внутри одной сети. Для связи из любой точки впиши адрес облака и ключ проекта.",

		# --- связь ---
		"net": "Связь",
		"net_host_hint": "127.0.0.1:7777 или https://проект.supabase.co",
		"net_key_hint": "ключ проекта: sb_publishable_…",
		"net_auto": "Подключаться при входе",
		"net_connect": "Подключиться",
		"net_disconnect": "Отключиться",
		"net_off": "Не подключено",
		"net_connecting": "Подключаюсь к %s…",
		"net_hello": "Здороваюсь с сервером…",
		"net_online": "На связи как %s",
		"net_failed": "Не удалось подключиться к %s",
		"net_lost": "Связь с %s потеряна, пробую снова",
		"net_server_error": "Сервер: %s",
		"net_note_online": "Связь есть: сообщение уйдёт на сервер, дойдёт до получателя и удалится с сервера.",
		"net_note_offline": "Связи нет: сообщение пока сохранится только у тебя на устройстве.",
		"net_bad_address": "Не понял адрес. Нужно «127.0.0.1:7777» или «https://проект.supabase.co»",

		# --- ошибки ---
		"err_nick_short": "Ник слишком короткий: нужно хотя бы 2 символа.",
		"err_nick_long": "Ник слишком длинный: максимум 24 символа.",
		"err_nick_used": "Такой ник уже занят.",
		"err_no_account": "Аккаунт не найден.",
		"err_pass_wrong": "Неверный пароль.",
		"err_pass_mismatch": "Пароли не совпадают.",
		"err_pass_empty_second": "Повтори пароль ещё раз.",
		"err_need_password": "Введи пароль"
	},
	"en": {
		# --- общее ---
		"app_name": "Tngram",
		"app_tagline": "A private messenger",
		"ok": "Done",
		"cancel": "Cancel",
		"back": "Back",
		"soon": "Coming soon",
		"delete": "Delete",

		# --- вход ---
		"login_title": "Who are you?",
		"login_subtitle": "Pick an account or create a new nickname. No phone number needed.",
		"login_pick": "Accounts on this device",
		"login_enter": "Sign in",
		"login_create": "Create nickname",
		"login_no_accounts": "No accounts yet — create your first nickname.",
		"login_password": "Password",
		"login_password_hint": "If the nickname has a password",
		"login_back": "Back to accounts",

		# --- создание ника ---
		"new_title": "New nickname",
		"new_subtitle": "A nickname is your address in Tngram. No phone, no email.",
		"new_nick": "Nickname",
		"new_nick_hint": "for example, your_nick",
		"new_password": "Password (optional)",
		"new_password_hint": "set a password if you want to protect the nickname",
		"new_password_repeat": "Repeat password",
		"new_submit": "Create and sign in",
		"new_no_password_note": "Without a password anyone with this device can sign in.",

		# --- чаты ---
		"chats_title": "Chats",
		"chats_empty": "Nobody here yet. Create a second nickname to try messaging.",
		"chats_new_nick": "New nickname",
		"chats_logout": "Sign out",
		"chats_you": "This is you",
		"chats_no_messages": "No messages yet",
		"chats_on_device": "Chats are stored on this device only",
		"chats_remote": "peer over the network",

		# --- чат ---
		"chat_placeholder": "Message…",
		"chat_send": "Send",
		"chat_empty": "Write the first message",
		"chat_delete": "Delete chat",
		"chat_delete_confirm": "Delete the whole conversation with %s? It cannot be restored.",
		"chat_with": "Chat with ",

		# --- настройки ---
		"settings": "Settings",
		"settings_lang": "Language",
		"settings_theme": "Theme",
		"theme_dark": "Dark",
		"theme_green": "Green",
		"theme_blue": "Blue",
		"settings_account": "Account",
		"settings_delete_account": "Delete account",
		"settings_delete_confirm": "Delete account %s and all its chats?",
		"settings_about": "About",
		"settings_about_text": "Tngram is still in development. A message goes to the server (yours or the cloud), reaches the recipient and is deleted from the server.",
		"settings_soon_server": "Your own server works inside one network. For delivery anywhere, enter the cloud address and the project key.",

		# --- связь ---
		"net": "Connection",
		"net_host_hint": "127.0.0.1:7777 or https://project.supabase.co",
		"net_key_hint": "project key: sb_publishable_…",
		"net_auto": "Connect on sign-in",
		"net_connect": "Connect",
		"net_disconnect": "Disconnect",
		"net_off": "Not connected",
		"net_connecting": "Connecting to %s…",
		"net_hello": "Saying hello to the server…",
		"net_online": "Online as %s",
		"net_failed": "Cannot connect to %s",
		"net_lost": "Lost connection to %s, trying again",
		"net_server_error": "Server: %s",
		"net_note_online": "Connected: the message goes to the server, reaches the recipient and is deleted from the server.",
		"net_note_offline": "No connection: the message is stored on your device only.",
		"net_bad_address": "Cannot read the address. Use \"127.0.0.1:7777\" or \"https://project.supabase.co\"",

		# --- ошибки ---
		"err_nick_short": "Nickname is too short: at least 2 characters.",
		"err_nick_long": "Nickname is too long: 24 characters maximum.",
		"err_nick_used": "This nickname is already taken.",
		"err_no_account": "Account not found.",
		"err_pass_wrong": "Wrong password.",
		"err_pass_mismatch": "Passwords do not match.",
		"err_pass_empty_second": "Please repeat the password.",
		"err_need_password": "Enter the password"
	}
}

## Текст по ключу. Неизвестный ключ возвращаем как есть — так сразу видно ошибку.
func t(key: String) -> String:
	var table: Dictionary = STRINGS.get(lang, STRINGS["ru"])
	return String(table.get(key, key))

## Текст с подстановкой: Loc.tf("chat_with", [nick])
func tf(key: String, values: Array) -> String:
	var text := t(key)
	for value in values:
		text = text.replace("%s", String(value))
	return text
