extends Node
## Короткие звуки приложения «Тнграм».
##
## Никаких звуковых файлов: тоны считаются прямо в коде (пара нот с затуханием).
## Так в проекте не появляется лишних вложений, а звук всегда одинаковый.
## Подключается как автозагрузка (Autoload) с именем Sfx — см. project.godot.

const RATE := 44100          ## частота дискретизации
const VOICES := 4            ## сколько звуков могут звучать одновременно
const PEAK := 30000.0        ## максимальная громкость сэмпла (из 32767)

## Описание звуков: «части» — по одной ноте каждая:
## [задержка, частота, длина, громкость]. Ноты накладываются друг на друга.
const SOUNDS := {
	"incoming": {  ## пришло сообщение — мягкое «дзынь» из двух нот
		"total": 0.62,
		"parts": [[0.0, 880.0, 0.34, 0.42], [0.11, 1318.5, 0.40, 0.26]]
	},
	"sent": {      ## своё сообщение ушло — короткий тихий щелчок
		"total": 0.14,
		"parts": [[0.0, 1046.5, 0.10, 0.22]]
	},
	"notice": {    ## что-то важное (например, вышло обновление)
		"total": 0.46,
		"parts": [[0.0, 587.3, 0.24, 0.34], [0.09, 784.0, 0.30, 0.24]]
	}
}

var _players: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _next := 0

func _ready() -> void:
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % i
		add_child(player)
		_players.append(player)

## Перед выходом останавливаем проигрыватели и отпускаем звуки: пока у
## проигрывателя выставлен stream, он держит и сам звук, и объект «проигрывание»,
## и движок при закрытии сообщает об утечке пары объектов.
func _exit_tree() -> void:
	for player in _players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_players.clear()
	_cache.clear()

## Есть ли вообще звуковое устройство. В «безоконном» режиме (например, в
## автотестах) его нет: играть нечего, а созданный «проигрыватель» потом висит
## и движок при закрытии жалуется на утечку пары объектов.
func audio_available() -> bool:
	return DisplayServer.get_name() != "headless"

## Сыграть звук по имени: "incoming", "sent", "notice".
func play(kind: String) -> void:
	if not Store.sound_on() or _players.is_empty() or not audio_available():
		return
	var stream := _stream(kind)
	if stream == null:
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.volume_db = linear_to_db(maxf(Store.sound_volume(), 0.001))
	player.play()

## Сэмплы звука (собираются один раз и запоминаются)
func _stream(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	if not SOUNDS.has(kind):
		return null
	var description: Dictionary = SOUNDS[kind]
	var stream := _render(description["parts"], float(description["total"]))
	_cache[kind] = stream
	return stream

## Посчитать сэмплы: сумма нот с экспоненциальным затуханием.
## Короткое нарастание (5 мс) убирает щелчок в начале звука.
func _render(parts: Array, total: float) -> AudioStreamWAV:
	var count := int(RATE * total)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var value := 0.0
		for part in parts:
			var start := float(part[0])
			var freq := float(part[1])
			var length := float(part[2])
			var gain := float(part[3])
			if t < start or t >= start + length:
				continue
			var local := t - start
			var envelope := exp(-4.5 * local / length) * minf(1.0, local / 0.005)
			value += sin(TAU * freq * local) * gain * envelope
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * PEAK))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
