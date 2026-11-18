extends RefCounted
class_name TnCrypt
## Шифрование файла данных на устройстве.
##
## Как устроено:
##   * ключ — 32 случайных байта, лежит отдельным файлом рядом с данными;
##   * данные шифруются AES-256-CBC, случайный IV на каждое сохранение;
##   * поверх шифртекста считается HMAC-SHA256 (сначала шифруем, потом подписываем),
##     поэтому подмена или обрезка файла не пройдёт молча;
##   * в начале файла метка TNG1 — по ней видно, что файл уже зашифрован.
##
## Чего это НЕ делает: ключ лежит в той же папке приложения, поэтому от того,
## у кого есть полный доступ к папке, это не защищает. Защищает от копирования
## одного файла данных, от облачных бэкапов и от чтения переписки «глазами».

const MAGIC := "TNG1"
const KEY_BYTES := 32
const IV_BYTES := 16
const MAC_BYTES := 32
const BLOCK := 16

## Ключ устройства: читаем готовый или создаём новый.
static func load_or_create_key(path: String) -> PackedByteArray:
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var raw := file.get_buffer(KEY_BYTES)
			file.close()
			if raw.size() == KEY_BYTES:
				return raw
	var key := random_bytes(KEY_BYTES)
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out != null:
		out.store_buffer(key)
		out.close()
	return key

static func random_bytes(size: int) -> PackedByteArray:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(size)

## Зашифровать: метка + IV + шифртекст + HMAC.
static func seal(key: PackedByteArray, plain: PackedByteArray) -> PackedByteArray:
	if key.size() != KEY_BYTES:
		return PackedByteArray()
	var iv := random_bytes(IV_BYTES)
	var body := _pad(plain)
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv) != OK:
		return PackedByteArray()
	var cipher := aes.update(body)
	aes.finish()
	if cipher.size() == 0:
		return PackedByteArray()
	var blob := MAGIC.to_utf8_buffer() + iv + cipher
	return blob + _mac(key, blob)

## Расшифровать. Пустой результат — файл не наш, повреждён или ключ не тот.
static func open(key: PackedByteArray, blob: PackedByteArray) -> PackedByteArray:
	if key.size() != KEY_BYTES or blob.size() < MAGIC.length() + IV_BYTES + BLOCK + MAC_BYTES:
		return PackedByteArray()
	if blob.slice(0, MAGIC.length()).get_string_from_ascii() != MAGIC:
		return PackedByteArray()
	var signed := blob.slice(0, blob.size() - MAC_BYTES)
	var mac := blob.slice(blob.size() - MAC_BYTES)
	if not _same(_mac(key, signed), mac):
		return PackedByteArray()
	var iv := blob.slice(MAGIC.length(), MAGIC.length() + IV_BYTES)
	var cipher := blob.slice(MAGIC.length() + IV_BYTES, blob.size() - MAC_BYTES)
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_DECRYPT, key, iv) != OK:
		return PackedByteArray()
	var body := aes.update(cipher)
	aes.finish()
	return _unpad(body)

## Это уже зашифрованный файл? (по метке в начале)
static func looks_sealed(blob: PackedByteArray) -> bool:
	if blob.size() < MAGIC.length():
		return false
	return blob.slice(0, MAGIC.length()).get_string_from_ascii() == MAGIC

## ---- внутреннее ----

## Ключ подписи выводим из ключа шифрования: одна и та же 32-байтная тайна,
## но AES и HMAC не делят ключ напрямую.
static func _mac(key: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	var mac_key := _sha256(key + "tn-mac".to_utf8_buffer())
	var hmac := HMACContext.new()
	hmac.start(HashingContext.HASH_SHA256, mac_key)
	hmac.update(data)
	return hmac.finish()

static func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()

## PKCS#7: добиваем до кратности 16, байт = сколько добавлено.
static func _pad(data: PackedByteArray) -> PackedByteArray:
	var extra := BLOCK - (data.size() % BLOCK)
	var out := data.duplicate()
	for i in extra:
		out.append(extra)
	return out

static func _unpad(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return PackedByteArray()
	var extra := int(data[data.size() - 1])
	if extra < 1 or extra > BLOCK or extra > data.size():
		return PackedByteArray()
	return data.slice(0, data.size() - extra)

## Сравнение без раннего выхода: время не зависит от того, где различие.
static func _same(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= int(a[i]) ^ int(b[i])
	return diff == 0
