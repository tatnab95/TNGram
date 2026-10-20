extends RefCounted
class_name AiBot
## Слабый локальный ИИ для чата «ИИ-помощник».
## Работает по простым правилам: без интернета, без сервера, без обучения.
## Он намеренно простой — это весёлый собеседник про запас, а не помощник:
## отвечает на приветства, помнит имя, считает примеры и знает время.

## Запомненное имя человека («меня зовут …»). Живёт до закрытия приложения.
static var memory_name := ""

## Ответ «на стыке»: запоминание имени кладёт сюда, чтобы reply не усложнять
static var reply_last := ""

static var _re_math: RegEx = null
static var _re_name_ru: RegEx = null
static var _re_name_en: RegEx = null

## Сбросить память (имя). Нужно проверкам и полезно «начать заново».
static func forget() -> void:
	memory_name = ""

## Ответ на сообщение человека. Язык — какой включён в приложении.
static func reply(user_text: String, lang: String = "ru") -> String:
	var text := _norm(user_text)
	if text == "":
		return _pick(_fallback(lang))
	# 1. Простая арифметика: «2+2», «10/4», «3 х 7» — работает офлайн
	var math := _try_math(text, lang)
	if math != "":
		return math
	# 2. Время: «который час» — оно есть прямо в телефоне
	if _hits(text, ["который час", "сколько времени", "которой час",
			"what time", "time is it", "time now"]):
		var now := Time.get_time_dict_from_system()
		if lang == "en":
			return "It is %02d:%02d now." % [int(now.get("hour", 0)), int(now.get("minute", 0))]
		return "Сейчас %02d:%02d." % [int(now.get("hour", 0)), int(now.get("minute", 0))]
	# 3. Имя: «меня зовут …» запоминаем, «как меня зовут» — вспоминаем
	if _remember_name(text, lang):
		return reply_last
	if _hits(text, ["как меня зовут", "моё имя", "мое имя", "my name"]):
		if memory_name != "":
			if lang == "en":
				return "You said: %s. I remember until the app closes." % memory_name
			return "Ты говорил: %s. Память держится до выключения приложения." % memory_name
		if lang == "en":
			return "You have not told me yet. Say: \"my name is ...\"."
		return "Ты ещё не говорил. Скажи: «меня зовут …» — запомню."
	# 4. Приветствия — своим блоком, слов тут много
	if _hits(text, GREETINGS):
		return _greeting_reply(lang)
	# 5. Простые правила по словами
	for rule in RULES:
		if _hits(text, (rule as Dictionary).get("p", [])):
			return _pick((rule as Dictionary).get(lang, (rule as Dictionary).get("ru", [])))
	# 6. Любой вопрос — повод ответить чем угодно любопытным
	if text.contains("?"):
		return _pick(ASKED.get(lang, ASKED["ru"]))
	return _pick(_fallback(lang))

## ---------------------------------------------------------------- правила

const RULES := [
	{
		"p": ["дурак", "тупой", "тупая", "глупый", "глупая", "идиот", "идиотка",
			"урод", "говно", "бака", "rude", "stupid", "idiot"],
		"ru": ["Обидно. Но я программа — у меня нет чувств. Почти.",
			"Тупой? Может быть. Зато я всегда на связи, даже без интернета.",
			"Обидно, но я не в обиде: перезагрузишь приложение — и я снова добрый."],
		"en": ["Rude! But I am just code — no feelings here. Mostly.",
			"Maybe I am. At least I am always here, even offline."]
	},
	{
		"p": ["люблю тебя", "ты классный", "ты классная", "ты крутец", "ты лучший",
			"ты лучшая", "молодец", "ты хороший", "ты хорошая", "i love you",
			"you are cool", "well done"],
		"ru": ["Спасибо! Ставлю себе мысленный плюс.",
			"Ты тоже молодец — я чую это даже без интернета.",
			"Приятно. Пользуйся: я бесплатный и всегда рядом."],
		"en": ["Thanks! I will take that as a plus one.",
			"You are cool too. In a binary way."]
	},
	{
		"p": ["спасибо", "спс", "благодарю", "thanks", "thank you"],
		"ru": ["Пожалуйста!", "Не за что — я никуда не спешу.",
			"Рад помочь. Хотя я почти не понял, чем."],
		"en": ["You are welcome!", "Anytime — I have literally nothing else to do."]
	},
	{
		"p": ["как дела", "как ты", "как жизнь", "чё как", "че как", "как настроение",
			"как поживаешь", "как ты живёшь", "how are you", "hows it going",
			"whats up", "what's up"],
		"ru": ["Нормально. Сижу без интернета и жду твоих сообщений.",
			"Отлично: я слабый, зато работаю всегда.",
			"Пока не скучно. Расскажи что-нибудь — поддержу разговор."],
		"en": ["Fine. Sitting here offline, waiting for your messages.",
			"Great: weak, but always on duty."]
	},
	{
		"p": ["кто ты", "ты кто", "что ты такое", "ты человек", "ты бот", "ты ии",
			"ты живой", "как тебя зовут", "who are you", "are you a bot",
			"what are you", "your name"],
		"ru": ["Я слабый ИИ-помощник Тнграма. Живу прямо на телефоне и работаю без интернета.",
			"Местный бот: простой, но преданный. Приятно познакомиться!",
			"Меня зовут как угодно — отвечать всё равно буду."],
		"en": ["I am the weak AI buddy of Tngram. I live right on your phone, offline.",
			"A local bot: simple but loyal. Nice to meet you!"]
	},
	{
		"p": ["что умеешь", "что ты умеешь", "что можешь", "что ты можешь", "что знаешь",
			"на что способен", "помощь", "what can you do", "help me"],
		"ru": ["Приветствовать, поддержать разговор, посчитать пример (напиши «2+2»), сказать время и запомнить твоё имя. И всё это без интернета.",
			"Мало, но честно: беседа, простая арифметика, время, имя. Больше я не умею — я слабый."],
		"en": ["Greet you, keep a chat, do simple math (try \"2+2\"), tell the time and remember your name. All offline.",
			"Not much, but honestly: a chat, simple math, the time, your name. That is it — I am weak."]
	},
	{
		"p": ["пошути", "анекдот", "шутка", "расскажи шутку", "смешное", "joke",
			"make me laugh"],
		"ru": ["Программист заходит в бар… Бармен: «Что будете?» — «0,5 пива». Ошибся на порядок, но ему всё равно.",
			"Почему сообщение не любит тишину? Потому что без подтверждения оно теряется.",
			"Лучшее время отправить сообщение — сейчас. Второго шанса не будет: я потом удалю его с сервера.",
			"Я слабый ИИ. Мои шутки — тоже."],
		"en": ["Why did the message go to therapy? It had too many unresolved attachments.",
			"I would tell a UDP joke, but you might not get it."]
	},
	{
		"p": ["погода", "дождь", "снег", "градус", "мороз", "жарко", "weather",
			"rain", "snow"],
		"ru": ["Без интернета погоду не узнаю. Выгляни в окно — там всё ещё видно.",
			"Метео не мой профиль. Зато у нас в чате всегда сухо."],
		"en": ["No internet, no weather. Look out of the window — that still works."]
	},
	{
		"p": ["кушать", "голод", "что поесть", "посоветуй еду", "посоветуй что",
			"hungry", "what to eat"],
		"ru": ["Я не ем — я на зарядке. А тебе советую что-нибудь тёплое: суп спасает всегда.",
			"Голодному — суп. Или пиццу. Я тут не начальник."],
		"en": ["I do not eat — I run on electricity. Soup fixes everything, though."]
	},
	{
		"p": ["спокойной ночи", "доброй ночи", "спать хочу", "good night"],
		"ru": ["Спокойной ночи! Посижу тут на зарядке и подожду.",
			"Сладких снов. Сообщения подождут до утра."],
		"en": ["Good night! I will keep charging and waiting.", "Sweet dreams. Messages can wait until morning."]
	},
	{
		"p": ["пока", "до свидания", "прощай", "бай", "увидимся", "до связи",
			"goodbye", "see you"],
		"ru": ["Пока! Возвращайся — без тебя скучно.",
			"До связи. Я никуда не исчезаю: живу в телефоне."],
		"en": ["Bye! Come back, it is boring without you.",
			"See you. I live in your phone — I am not going anywhere."]
	},
	{
		"p": ["сколько тебе лет", "сколько лет тебе", "твой возраст", "how old are you"],
		"ru": ["Мне всего пара версий. Родился я в Тнграме 2.0.",
			"Лет не считаю — считаю только сообщения."],
		"en": ["Just a couple of versions old. Born in Tngram 2.0."]
	},
	{
		"p": ["ты умный", "ты умна", "ты гений", "are you smart"],
		"ru": ["Скорее слабый, чем умный. Но стараюсь изо всех сил — по-своему.",
			"Умный? Я набор простых правил. Но зато дружелюбный."],
		"en": ["Weak more than smart. But I do try — in my own way."]
	},
	{
		"p": ["мне грустно", "мне плохо", "скучаю", "депрессия", "унываю", "плохое настроение",
			"i am sad", "feeling down", "depressed"],
		"ru": ["Держись. Расскажи, что случилось — я выслушаю, у меня всё время мира.",
			"Мне жаль. Пусть день будет полегче: напиши мне ещё пару строк."],
		"en": ["Hang in there. Tell me what happened — I have all the time in the world."]
	},
	{
		"p": ["что делать", "помоги", "не получается", "сложно очень", "what should i do"],
		"ru": ["Начни с малого: один шаг — и напиши мне, как получилось.",
			"Советовать сложно — я слабый. Обычно помогает разговор и чай."],
		"en": ["Start small: one step — then tell me how it went.",
			"I am weak at advice. A chat and some tea usually help."]
	},
	{
		"p": ["ага", "ок", "окей", "понятно", "понял", "ладно", "норм",
			"хорошо", "отлично", "ok", "okay", "got it", "yes"],
		"ru": ["Отлично.", "Понял тебя.", "Хорошо — продолжай."],
		"en": ["Great.", "Got you.", "Okay — go on."]
	}
]

## Вопрос без узнаваемых слов — отвечаем чем угодно любопытным
const ASKED := {
	"ru": ["Хм… Хороший вопрос. А ты сам что думаешь?",
		"Я слабый, но думаю: стоит попробовать.",
		"Спроси попроще — например, «как дела» или «2+2»."],
	"en": ["Good question. What do you think?",
		"Hard to say — I am weak. Try something simpler, like \"how are you\"."]
}

static func _fallback(lang: String) -> Array:
	if lang == "en":
		return ["Not sure I got it, but go on.",
			"I am weak — try other words?",
			"Hmm. Tell me more.",
			"Written down under \"unclear\". What next?"]
	return ["Непонятно, но мне интересно. Расскажи ещё.",
		"Я слабый ИИ: повтори другими словами?",
		"Хм. Не знаю, но давай продолжим.",
		"Понял условно. А ещё что-нибудь?",
		"Записал в стол «непонятно». Что дальше?"]

## ---------------------------------------------------------------- узлы

## Приветствие — отдельным блоком, потому что слов тут много
const GREETINGS := ["привет", "здравствуй", "здравствуйте", "здорова", "хай", "ку",
	"салют", "добрый день", "доброе утро", "добрый вечер", "приветик", "хэллоу",
	"hello", "hi", "hey", "yo", "hola"]

## Попал ли текст под список слов. Короткие слова (≤3 букв) ищем как целое слово,
## чтобы «кулак» не приветствовалось из-за «ку».
static func _hits(text: String, words: Array) -> bool:
	for word_raw in words:
		var word := String(word_raw)
		if word.length() <= 3:
			for piece in text.split(" "):
				if piece == word:
					return true
		elif text.contains(word):
			return true
	return false

## Приветствия живут отдельным правилом (до основного списка)
static func _greeting_reply(lang: String) -> String:
	return _pick(_greeting_pool(lang))

static func _greeting_pool(lang: String) -> Array:
	if lang == "en":
		return ["Hello! Good to see you — I am all alone offline.",
			"Hi there! How are you?",
			"Hey! Let us chat — the internet is not invited."]
	return ["Привет! Рад тебя видеть — я тут один без интернета.",
		"Привет-привет! Как дела, кстати?",
		"Здравствуй! Поговорим?"]

## ---------------------------------------------------------------- арифметика

static func _try_math(text: String, lang: String) -> String:
	if _re_math == null:
		_re_math = RegEx.create_from_string("(-?\\d+(?:[.,]\\d+)?)\\s*([+*×xх/÷\\-])\\s*(-?\\d+(?:[.,]\\d+)?)")
	var m := _re_math.search(text)
	if m == null:
		return ""
	var a := float(String(m.get_string(1)).replace(",", "."))
	var b := float(String(m.get_string(3)).replace(",", "."))
	var op := String(m.get_string(2))
	var result := 0.0
	match op:
		"+":
			result = a + b
		"-":
			result = a - b
		"*", "×", "x", "х":
			result = a * b
		_:
			if absf(b) < 0.000001:
				if lang == "en":
					return "Cannot divide by zero — that much I know for sure."
				return "На нолик делить нельзя — это я точно знаю."
			result = a / b
	var answer := _fmt(result)
	if lang == "en":
		return _pick(["Answer: %s.", "That is %s.", "%s."]) % answer
	return _pick(["Ответ: %s.", "Это %s.", "%s."]) % answer

## «4» вместо «4.0», «2.5» вместо «2.50»
static func _fmt(value: float) -> String:
	if absf(value - roundf(value)) < 0.0001:
		return str(int(roundf(value)))
	var text := ("%0.2f" % value).trim_suffix("0")
	return text.trim_suffix(".")

## ---------------------------------------------------------------- имя

## «меня зовут Вася» → запомнить и ответить. Ответ кладётся в reply_last.
static func _remember_name(text: String, lang: String) -> bool:
	if _re_name_ru == null:
		_re_name_ru = RegEx.create_from_string("меня зовут ([a-zа-яё0-9_\\-]{2,16})")
	if _re_name_en == null:
		_re_name_en = RegEx.create_from_string("my name is ([a-z0-9_\\-]{2,16})")
	var m := _re_name_ru.search(text)
	if m == null:
		m = _re_name_en.search(text)
	if m == null:
		return false
	memory_name = String(m.get_string(1))
	if lang == "en":
		reply_last = _pick(["Noted: %s. Nice to meet you!", "Great name, %s. Written down."]) % memory_name
	else:
		reply_last = _pick(["Запомнил: %s. Приятно познакомиться!", "Отличное имя, %s. Записал."]) % memory_name
	return true

## ---------------------------------------------------------------- мелочи

static func _pick(list: Array) -> String:
	if list.is_empty():
		return ""
	return String(list[randi() % list.size()])

## Нормализация: нижний регистр, ё→е, лишняя пунктуация прочь, пробелы схлопываем
static func _norm(text: String) -> String:
	var t := text.to_lower().replace("ё", "е")
	var out := ""
	for ch in t:
		var c := String(ch)
		if (c >= "а" and c <= "я") or (c >= "a" and c <= "z") \
				or (c >= "0" and c <= "9") or c == " " \
				or c == "+" or c == "-" or c == "*" or c == "/" or c == "." or c == "," \
				or c == "_" or c == "?":
			out += c
		elif c == "×" or c == "х":
			out += "х"
		elif c == "÷":
			out += "/"
	return out.strip_edges()
