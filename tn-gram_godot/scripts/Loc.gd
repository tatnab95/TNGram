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
		"chats_empty": "Пока никого. Нажми «Новый чат» и впиши ник собеседника.",
		"chats_new_nick": "Новый ник",
		"chats_new_chat": "Новый чат",
		"chats_logout": "Выйти",
		"chats_you": "Это ты",
		"chats_no_messages": "Сообщений пока нет",
		"chats_on_device": "Переписка хранится только на этом устройстве",
		"chats_remote": "собеседник по сети",
		"chats_conflict": "Ник «%s» занят ещё кем-то. Пока это так, сообщения могут путаться — смени ник или попроси сменить его.",

		# --- новый чат ---
		"newchat_title": "Новый чат",
		"newchat_subtitle": "Введи ник человека — откроется переписка с ним. Ник должен быть уже создан в Тнграме.",
		"newchat_who": "Кому",
		"newchat_who_hint": "ник собеседника",
		"newchat_open": "Открыть чат",
		"newchat_checking": "Проверяю ник…",
		"newchat_self": "Это твой собственный ник.",
		"newchat_no_such": "Такого ника в Тнграме нет. Проверь написание или открой всё равно.",
		"newchat_open_anyway": "Всё равно открыть",

		# --- чат ---
		"chat_placeholder": "Сообщение…",
		"chat_send": "Отправить",
		"chat_empty": "Напиши первое сообщение",
		"chat_delete": "Удалить переписку",
		"chat_delete_confirm": "Удалить всю переписку с %s? Восстановить её будет нельзя.",
		"chat_with": "Чат с ",

		# --- слабый ИИ (только телефон, работает без интернета) ---
		"ai_title": "ИИ-помощник",
		"ai_subtitle": "Слабый ИИ · работает без интернета",
		"ai_status": "слабый ИИ · офлайн",
		"ai_note": "Помощник отвечает по-своему: вся переписка хранится только на этом устройстве.",
		"ai_typing": "печатает…",
		"ai_empty": "Напиши «привет» — помощник ответит даже без интернета.",

		# --- настройки ---
		"settings": "Настройки",
		"settings_lang": "Язык",
		"settings_theme": "Тема",
		"theme_dark": "Dark",
		"theme_green": "Green",
		"theme_blue": "Blue",
		"settings_account": "Аккаунт",
		"settings_delete_account": "Удалить аккаунт",
		"settings_delete_confirm": "Удалить аккаунт %s и всю его переписку?",
		"settings_about": "О приложении",
		"settings_about_text": "Тнграм ещё в разработке. Сообщение уходит на сервер (свой или облачный), доходит до получателя и удаляется с сервера.",
		"settings_soon_server": "Свой сервер работает внутри одной сети. Для связи из любой точки впиши адрес облака и ключ проекта.",
		"settings_version": "версия %s",
		"settings_news": "Что нового",

		# --- сглаживание ---
		"settings_graphics": "Сглаживание",
		"aa_0": "Выкл",
		"aa_1": "Низкое",
		"aa_2": "Среднее",
		"aa_3": "Высокое",
		"aa_4": "Максимум",
		"settings_graphics_hint": "Мягкость букв и фона. Выключено — резкие пиксельные буквы, Максимум — самые гладкие.",
		"settings_graphics_simple": "Твоя видеокарта работает в простом режиме: сглаживание текста и фона работает, а сглаживание краёв фигур — нет. Хочешь больше — запусти приложение через TNGram-качество.bat.",

		# --- звук ---
		"settings_sound": "Звук",
		"settings_sound_on": "Сигнал на новое сообщение",
		"settings_sound_volume": "Громкость",

		# --- уведомления ---
		"settings_notify": "Уведомления",
		"settings_notify_on": "Карточка о новом сообщении",
		"settings_notify_hint": "Когда приходит сообщение, в углу появляется карточка. Щелчок по ней открывает чат.",
		"settings_notify_os": "Уведомления Windows",
		"settings_notify_os_hint": "Показывать системное уведомление, когда окно свёрнуто или не в фокусе. Его видно поверх других программ.",
		"settings_notify_os_android": "Уведомления телефона",
		"settings_notify_os_android_hint": "Показывать уведомление в шторке телефона, когда приложение свёрнуто. Телефон один раз спросит разрешение.",
		"notify_channel": "Сообщения",

		# --- что нового ---
		"news_title": "Что нового",
		"news_subtitle": "Что изменилось в каждой версии Тнграма.",
		"news_current": "Установлена версия %s — самая свежая.",
		"news_update_title": "Вышла версия %s",
		"news_update_text": "Твоя версия старее. Открой сайт и скачай новую — это бесплатно.",
		"news_update_badge": "вышла версия %s",
		"news_open_site": "Открыть сайт",
		"update_title": "Тнграм",
		"update_toast": "Вышла новая версия %s — нажми, чтобы узнать больше",

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
		"server_cloud": "Сервер: облако Supabase",
		"server_own": "Сервер: свой",
		"ping_line": "Пинг %s мс",
		"ping_wait": "Пинг…",

		# --- ошибки ---
		"err_nick_short": "Ник слишком короткий: нужно хотя бы 2 символа.",
		"err_nick_long": "Ник слишком длинный: максимум 24 символа.",
		"err_nick_used": "Такой ник уже занят — второй такой же создать нельзя. Войди под этим ником.",
		"err_no_account": "Аккаунт не найден.",
		"err_pass_wrong": "Неверный пароль.",
		"err_pass_mismatch": "Пароли не совпадают.",
		"err_pass_short": "Пароль слишком короткий: нужно хотя бы 6 знаков.",
		"login_checking": "Проверяем пароль на сервере…",
		"err_pass_empty_second": "Повтори пароль ещё раз.",
		"err_need_password": "Введи пароль",
		"err_nick_cloud_taken": "Этот ник уже занят другим человеком. Выбери другой.",

		# --- группы ---
		"group_title": "Новая группа",
		"group_name": "Название группы",
		"newgroup_name_hint": "например, Дачники",
		"newgroup_create": "Создать группу",
		"newgroup_members": "Кого добавить",
		"newgroup_who": "Кого добавить",
		"newgroup_nobody": "Пока никого нет — сначала начни чат с человеком, потом собери группу.",
		"newgroup_hint": "Отметь галочками тех, кто будет в группе.",
		"group_members_count": "Участников: %s",
		"chats_new_group": "Группа",
		"err_group_title": "Название группы — хотя бы 2 символа.",
		"err_group_members": "Отметь хотя бы одного человека.",
		"group_invite_hint": "Напиши первое сообщение — группа появится у всех, кого отметил.",

		# --- кто в сети ---
		"status_online": "в сети",
		"status_offline": "не в сети",
		"status_last_seen": "был(а) %s",
		"status_unknown": "когда заходил — не видно",
		"time_now": "только что",
		"time_minutes": "%s мин назад",
		"time_hours": "%s ч назад",
		"time_days": "%s дн назад",

		# --- обновления ---
		"update_available": "Доступна новая версия %s",
		"update_get": "Обновить",
		"update_check": "Проверить обновления",
		"update_checking": "Проверяю…",
		"update_latest": "У тебя последняя версия %s",
		"update_found": "Вышла версия %s — нажми «Обновить».",

		# --- новости из облака ---
		"news_from_server": "Новости Тнграма",
		"news_empty": "Новостей пока нет.",
		"news_no_connection": "Новости появятся, когда будет связь.",

		# --- поиск ---
		"chats_search": "Поиск по чатам",
		"search_nothing": "Ничего не нашлось",

		# --- дни ---
		"day_today": "Сегодня",
		"day_yesterday": "Вчера",

		# --- ник занят ---
		"new_nick_taken_login": "Войти под этим ником",
		"new_nick_taken_hint": "Если это ты — просто войди, ник останется твоим.",
		"err_nick_exists_login": "Такой ник уже есть на этом устройстве. Войди под ним.",
		"err_group_busy": "Группа с таким названием уже есть."
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
		"chats_empty": "Nobody here yet. Tap \"New chat\" and type the other person's nickname.",
		"chats_new_nick": "New nickname",
		"chats_new_chat": "New chat",
		"chats_logout": "Sign out",
		"chats_you": "This is you",
		"chats_no_messages": "No messages yet",
		"chats_on_device": "Chats are stored on this device only",
		"chats_remote": "peer over the network",
		"chats_conflict": "The nickname \"%s\" is also used by someone else. Messages may get mixed up — change it.",

		# --- новый чат ---
		"newchat_title": "New chat",
		"newchat_subtitle": "Type a person's nickname to open a chat with them. The nickname must already exist in Tngram.",
		"newchat_who": "To",
		"newchat_who_hint": "person's nickname",
		"newchat_open": "Open chat",
		"newchat_checking": "Checking…",
		"newchat_self": "That is your own nickname.",
		"newchat_no_such": "No such nickname in Tngram. Check the spelling or open it anyway.",
		"newchat_open_anyway": "Open anyway",

		# --- чат ---
		"chat_placeholder": "Message…",
		"chat_send": "Send",
		"chat_empty": "Write the first message",
		"chat_delete": "Delete chat",
		"chat_delete_confirm": "Delete the whole conversation with %s? It cannot be restored.",
		"chat_with": "Chat with ",

		# --- weak AI (phone only, works offline) ---
		"ai_title": "AI buddy",
		"ai_subtitle": "Weak AI · works offline",
		"ai_status": "weak AI · offline",
		"ai_note": "The buddy replies in its own way: the whole chat stays on this device only.",
		"ai_typing": "typing…",
		"ai_empty": "Say \"hello\" — the buddy answers even without the internet.",

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
		"settings_version": "version %s",
		"settings_news": "What's new",

		# --- сглаживание ---
		"settings_graphics": "Smoothing",
		"aa_0": "Off",
		"aa_1": "Normal",
		"aa_2": "Improved",
		"aa_3": "Maximum",
		"aa_4": "Max",
		"settings_graphics_hint": "How soft letters and the background look. \"Off\" — crisp pixelated letters, \"Maximum\" — the smoothest.",
		"settings_graphics_simple": "Your graphics card is in simple mode: text and background smoothing work, but shape edges are not smoothed. Want more? Start the app via \"TNGram-качество.bat\".",

		# --- звук ---
		"settings_sound": "Sound",
		"settings_sound_on": "Chime on a new message",
		"settings_sound_volume": "Volume",

		# --- уведомления ---
		"settings_notify": "Notifications",
		"settings_notify_on": "Pop-up card on a new message",
		"settings_notify_hint": "When a message arrives, a card appears in the corner. Click it to open the chat.",
		"settings_notify_os": "Windows notifications",
		"settings_notify_os_hint": "Show a system notification when the window is minimised or in the background. It appears above other apps.",
		"settings_notify_os_android": "Phone notifications",
		"settings_notify_os_android_hint": "Show a notification in the phone's shade while the app is minimised. The phone asks for permission once.",
		"notify_channel": "Messages",

		# --- что нового ---
		"news_title": "What's new",
		"news_subtitle": "What changed in each version of Tngram.",
		"news_current": "Version %s is installed — the latest one.",
		"news_update_title": "Version %s is out",
		"news_update_text": "Your version is older. Open the site and download the new one — it's free.",
		"news_update_badge": "version %s is out",
		"news_open_site": "Open the site",
		"update_title": "Tngram",
		"update_toast": "A new version %s is out — click to learn more",

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
		"server_cloud": "Server: Supabase cloud",
		"server_own": "Server: your own",
		"ping_line": "Ping %s ms",
		"ping_wait": "Ping…",

		# --- ошибки ---
		"err_nick_short": "Nickname is too short: at least 2 characters.",
		"err_nick_long": "Nickname is too long: 24 characters maximum.",
		"err_nick_used": "This nickname already exists — you cannot create a second one. Sign in with it.",
		"err_no_account": "Account not found.",
		"err_pass_wrong": "Wrong password.",
		"err_pass_mismatch": "Passwords do not match.",
		"err_pass_short": "Password is too short: at least 6 characters.",
		"login_checking": "Checking your password on the server…",
		"err_pass_empty_second": "Please repeat the password.",
		"err_need_password": "Enter the password",
		"err_nick_cloud_taken": "This nickname is already taken by someone else. Pick another.",

		# --- группы ---
		"group_title": "New group",
		"group_name": "Group name",
		"newgroup_name_hint": "for example, The Dacha",
		"newgroup_create": "Create group",
		"newgroup_members": "Who to add",
		"newgroup_who": "Who to add",
		"newgroup_nobody": "Nobody yet — start a chat with someone first, then gather a group.",
		"newgroup_hint": "Tick the people who should be in the group.",
		"group_members_count": "Members: %s",
		"chats_new_group": "Group",
		"err_group_title": "A group name needs at least 2 characters.",
		"err_group_members": "Tick at least one person.",
		"group_invite_hint": "Write the first message — the group appears for everyone you ticked.",

		# --- кто в сети ---
		"status_online": "online",
		"status_offline": "offline",
		"status_last_seen": "last seen %s",
		"status_unknown": "last seen unknown",
		"time_now": "just now",
		"time_minutes": "%s min ago",
		"time_hours": "%s h ago",
		"time_days": "%s d ago",

		# --- обновления ---
		"update_available": "A new version %s is available",
		"update_get": "Update",
		"update_check": "Check for updates",
		"update_checking": "Checking…",
		"update_latest": "You have the latest version %s",
		"update_found": "Version %s is out — tap \"Update\".",

		# --- новости из облака ---
		"news_from_server": "Tngram news",
		"news_empty": "No news yet.",
		"news_no_connection": "News will appear when there is a connection.",

		# --- поиск ---
		"chats_search": "Search chats",
		"search_nothing": "Nothing found",

		# --- дни ---
		"day_today": "Today",
		"day_yesterday": "Yesterday",

		# --- занятый ник ---
		"new_nick_taken_login": "Sign in with this nickname",
		"new_nick_taken_hint": "The nickname is taken — just sign in with it.",
		"err_nick_exists_login": "This nickname already exists on this device. Sign in with it.",
		"err_group_busy": "A group with this name already exists."
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
