extends RefCounted
class_name TnNotify
## Системные уведомления Windows: всплывашка в правом нижнем углу, которая видна,
## даже когда окно программы свёрнуто (и остаётся в «Центре уведомлений»).
##
## В самом Godot такого нет, поэтому просим Windows показать уведомление через
## встроенный PowerShell. Делается это в фоне и ни на что не влияет: если не
## получилось — останется обычная карточка внутри программы.
##
## Команда PowerShell передаётся в кодировке base64 (UTF-16LE), поэтому кириллица
## и любые кавычки не ломаются.

## Насколько длинный текст показываем (в уведомлении всё равно одна-две строки).
const MAX_TITLE := 60
const MAX_BODY := 180

## Готовое уведомление показывать не нужно в автотестах (там нет ни окна, ни
## рабочего стола) — иначе тест «дёргает» лишние процессы.
static func available() -> bool:
	return OS.has_feature("windows") and DisplayServer.get_name() != "headless"

## Код PowerShell для показа уведомления. Заголовок и текст — уже подготовлены.
static func build_script(title: String, body: String) -> String:
	var t := _quote(title)
	var b := _quote(body)
	return (
		"$ErrorActionPreference = 'Stop';"
		+ "try {"
		+ "[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime];"
		+ "[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime];"
		+ "$manager = [Windows.UI.Notifications.ToastNotificationManager];"
		+ "$xml = $manager::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);"
		+ "$nodes = $xml.GetElementsByTagName('text');"
		+ "[void]$nodes.Item(0).AppendChild($xml.CreateTextNode(%s));" % t
		+ "[void]$nodes.Item(1).AppendChild($xml.CreateTextNode(%s));" % b
		+ "$toast = [Windows.UI.Notifications.ToastNotification]::new($xml);"
		+ "$appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe';"
		+ "$manager::CreateToastNotifier($appId).Show($toast);"
		+ "} catch { }"
	)

## Показать системное уведомление. false — не получилось (тогда покажем карточку
## внутри программы).
static func toast(title: String, body: String) -> bool:
	if not available():
		return false
	var script := build_script(_clean(title, MAX_TITLE), _clean(body, MAX_BODY))
	OS.create_process("powershell.exe", [
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden", "-EncodedCommand", _encode_command(script),
	])
	return true

## Строка в кавычках для PowerShell: одинарная кавычка внутри удваивается.
static func _quote(text: String) -> String:
	return "'" + text.replace("'", "''") + "'"

## Убираем переносы строк и лишние пробелы, обрезаем длину.
static func _clean(text: String, limit: int) -> String:
	var s := text.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	s = s.strip_edges()
	if s == "":
		s = " "
	if s.length() > limit:
		s = s.substr(0, limit - 1) + "…"
	return s

## Знакомый PowerShell формат: base64 от UTF-16LE (младший байт, затем старший).
## Символы вне «основной плоскости» (например, эмодзи) превращаем в суррогатную
## пару — иначе они бы испортились.
static func _encode_command(code: String) -> String:
	var bytes := PackedByteArray()
	for i in code.length():
		var c := code.unicode_at(i)
		if c > 0xFFFF:
			c -= 0x10000
			_append_unit(bytes, 0xD800 + (c >> 10))
			_append_unit(bytes, 0xDC00 + (c & 0x3FF))
		else:
			_append_unit(bytes, c)
	return Marshalls.raw_to_base64(bytes)

static func _append_unit(bytes: PackedByteArray, unit: int) -> void:
	bytes.append(unit & 0xFF)
	bytes.append((unit >> 8) & 0xFF)

## Обратное преобразование — нужно только проверкам, чтобы убедиться, что
## кириллица и эмодзи переживают кодирование.
static func _decode_command(encoded: String) -> String:
	var bytes := Marshalls.base64_to_raw(encoded)
	var units := PackedInt32Array()
	var i := 0
	while i + 1 < bytes.size():
		units.append(bytes[i] | (bytes[i + 1] << 8))
		i += 2
	var out := ""
	var k := 0
	while k < units.size():
		var u := units[k]
		if u >= 0xD800 and u <= 0xDBFF and k + 1 < units.size() and units[k + 1] >= 0xDC00 and units[k + 1] <= 0xDFFF:
			out += String.chr(0x10000 + ((u - 0xD800) << 10) + (units[k + 1] - 0xDC00))
			k += 2
		else:
			out += String.chr(u)
			k += 1
	return out
