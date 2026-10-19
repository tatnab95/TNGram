extends RefCounted
class_name TnAndroidNotify
## Системные уведомления Android: сообщение видно в шторке телефона — когда
## приложение свёрнуто, а то и при выключенном экране — точно так же, как
## приходят уведомления от обычных мессенджеров.
##
## В самом Godot системных уведомлений для Android нет (на Windows они есть,
## см. TnNotify). Зато движок умеет разговаривать с Java через JavaClassWrapper —
## мост, встроенный в движок. Через него и просим Android показать уведомление
## штатным API телефона: канал, карточка, значок, тап открывает приложение.
##
## Всё максимально аккуратно: если Android откажет (нет разрешения, старая
## версия, чужая прошивка) — молча возвращаем false, и приложение показывает
## свою карточку внутри, как раньше. Ни падений, ни всплывающих ошибок.

## Канал уведомлений. С Android 8 уведомления без канала не показываются;
## канал создаётся один раз, дальше только переиспользуется.
const CHANNEL_ID := "tngram_messages"
## Важность DEFAULT — уведомление со звуком и всплывающей карточкой.
const IMPORTANCE_DEFAULT := 3
## Флаги PendingIntent: обновить уже существующее намерение + намерение
## неизменяемое (на Android 12+ выбор обязателен).
const FLAG_UPDATE_CURRENT := 0x08000000
const FLAG_IMMUTABLE := 0x04000000
## Уведомления без каналов работают до Android 8 (API 26).
const SDK_HAS_CHANNELS := 26
## Разрешение «показывать уведомления» появилось в Android 13 (API 33).
const SDK_NEEDS_PERMISSION := 33

static var _context: Variant = null    ## Android Activity — откуда берём все сервисы
static var _looked_up := false         ## попытка достать Activity уже была
static var _permission_asked := false  ## разрешение уже просили (хоть бы отказали)
static var _sdk := -1                  ## версия Android, запомненная один раз

## Работают ли здесь системные уведомления. Нет — если это не телефон
## (на компьютере свои уведомления, см. TnNotify) или мост до Java не открылся.
static func available() -> bool:
	if not OS.has_feature("android"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return _context_or_null() != null

## Попросить разрешение на уведомления. Делается один раз при запуске:
## до Android 13 спрашивать не о чем, «уже разрешили» тоже проверяем.
static func ensure_permission() -> void:
	if _permission_asked or not OS.has_feature("android"):
		return
	_permission_asked = true
	if _sdk_int() < SDK_NEEDS_PERMISSION:
		return
	if "android.permission.POST_NOTIFICATIONS" in OS.get_granted_permissions():
		return
	OS.request_permission("android.permission.POST_NOTIFICATIONS")

## Показать уведомление в шторке телефона. key — постоянный ключ собеседника
## или группы: по нему Android различает чаты (у каждого свой номер уведомления),
## так что два чата не затрут друг друга. true — уведомление отправлено.
static func post(key: String, title: String, body: String) -> bool:
	if OS.is_debug_build():
		_note("post(" + key + "): доступно=" + str(available()))
	if not available():
		return false
	var context: Variant = _context_or_null()
	if context == null:
		return false
	var manager: Variant = _manager(context)
	if manager == null:
		_note("NotificationManager не получен")
		return false
	_make_channel(manager)
	var builder: Variant = _builder(context)
	if builder == null:
		return false
	builder.setSmallIcon(_icon_id(context))
	builder.setContentTitle(title)
	builder.setContentText(body)
	builder.setAutoCancel(true)  ## тап по уведомлению открывает приложение, уведомление убирается
	var intent: Variant = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName())
	if intent != null:
		var pending: Variant = JavaClassWrapper.wrap("android.app.PendingIntent").getActivity(
			context, 0, intent, FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE)
		if pending != null:
			builder.setContentIntent(pending)
	var notification: Variant = builder.build()
	if notification == null:
		_note("уведомление не собралось")
		return false
	_note("показываю id=" + str(_notification_id(key)) + " заголовок=" + title)
	manager.notify(_notification_id(key), notification)
	return true

## Убрать уведомление этого чата из шторки (например, когда человек открыл чат).
static func cancel(key: String) -> void:
	if not available():
		return
	var context: Variant = _context_or_null()
	if context == null:
		return
	var manager: Variant = _manager(context)
	if manager != null:
		manager.cancel(_notification_id(key))

## ---------------------------------------------------------------- внутреннее

## Номер уведомления: постоянный по ключу чата, всегда положительный
## (отрицательные Android зарезервировал под свои цели).
static func _notification_id(key: String) -> int:
	return absi(hash(key.to_lower())) & 0x7FFFFFFF

## Сервис уведомлений Android.
static func _manager(context: Variant) -> Variant:
	return context.getSystemService(JavaClassWrapper.wrap("android.content.Context").NOTIFICATION_SERVICE)

## Канал уведомлений: создаётся один раз, повторное создание с тем же идентификатором
## ничего не меняет (кроме названия — оно может быть переведено на другой язык).
static func _make_channel(manager: Variant) -> void:
	if _sdk_int() < SDK_HAS_CHANNELS:
		return
	var cls: Variant = JavaClassWrapper.wrap("android.app.NotificationChannel")
	if cls == null:
		return
	# Конструктор Java-класса движок зовёт по последнему имени класса
	# (у NotificationChannel оно и есть «NotificationChannel»).
	var channel: Variant = cls.callv("NotificationChannel", [CHANNEL_ID, Loc.t("notify_channel"), IMPORTANCE_DEFAULT])
	if channel == null:
		_note("канал не создался: " + str(JavaClassWrapper.get_exception()))
		return
	channel.enableVibration(true)
	manager.createNotificationChannel(channel)

## Карточка уведомления: на новых телефонах (8+) — с каналом, на старых (7) —
## без него (тогда каналы ещё не существовали). У вложенного класса
## Notification.Builder конструктор зовут «Notification$Builder» — так и зовём
## (имя содержит «$», поэтому обычным точечным вызовом его не написать).
static func _builder(context: Variant) -> Variant:
	var cls: Variant = JavaClassWrapper.wrap("android.app.Notification$Builder")
	if cls == null:
		return null
	var made: Variant = null
	if _sdk_int() >= SDK_HAS_CHANNELS:
		made = cls.callv("Notification$Builder", [context, CHANNEL_ID])
	else:
		made = cls.callv("Notification$Builder", [context])
	if made == null:
		_note("Builder не создался: " + str(JavaClassWrapper.get_exception()))
	return made

## Иконка уведомления — та же, что у приложения (она же в ленте задач).
## Если вдруг имя найти не вышло — берём стандартный значок Android.
static func _icon_id(context: Variant) -> int:
	var found := int(context.getResources().getIdentifier("icon", "mipmap", context.getPackageName()))
	if found != 0:
		return found
	var r: Variant = JavaClassWrapper.wrap("android.R$drawable")
	return int(r.stat_notify_chat)

## Версия Android (24, 26, 33…), запомненная один раз.
static func _sdk_int() -> int:
	if _sdk >= 0:
		return _sdk
	_sdk = 0
	if ClassDB.class_exists("JavaClassWrapper") and OS.has_feature("android"):
		_sdk = int(JavaClassWrapper.wrap("android.os.Build$VERSION").SDK_INT)
	return _sdk

## Android Activity: движок сам отдаёт её — объект движка лежит в движке под
## именем «AndroidRuntime», у него есть getActivity(). Никакого зеркального
## «доставания Context из недр Java» не нужно. Один раз достали — дальше
## переиспользуем.
static func _context_or_null() -> Variant:
	if _context != null:
		return _context
	if _looked_up:
		return null
	_looked_up = true
	if not Engine.has_singleton("AndroidRuntime"):
		_note("нет синглтона AndroidRuntime")
		return null
	var runtime: Variant = Engine.get_singleton("AndroidRuntime")
	if runtime == null:
		_note("синглтон AndroidRuntime пуст")
		return null
	var activity: Variant = runtime.getActivity()
	if activity != null:
		_context = activity
		_note("Activity получена напрямую")
		return _context
	# Если Activity ещё не достали (движок только просыпается) — хватит и
	# контекста приложения: уведомлениям нужен просто Context.
	var app_ctx: Variant = runtime.getApplicationContext()
	if app_ctx != null:
		_context = app_ctx
		_note("Context приложения получен")
		return _context
	_note("и Activity, и Context пусты")
	return null

## Отладочные строки — только в отладочной сборке (видно в logcat).
static func _note(text: String) -> void:
	if OS.is_debug_build():
		print("[уведомления] ", text)
