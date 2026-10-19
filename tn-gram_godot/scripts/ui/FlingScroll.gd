extends Node
class_name FlingScroll
## Разгон списка после того, как палец отпустили, и пропуск касаний сквозь кнопки.
##
## Зачем: движок сам двигает список за пальцем, но отпускает его мгновенно —
## на телефоне это выглядит «плохой прокруткой». Здесь мы меряем скорость
## пальца и после отпускания докатываем список с затуханием, как в обычных
## приложениях. Заодно касания, начатые на кнопке, доходят до списка: крутить
## можно с любого места, а не только с пустого фона.
##
## Узел живёт рядом со списком, а не внутри него: у ScrollContainer дети должны
## быть только Control.

## Список, которым управляем (ставится до add_child).
var target: ScrollContainer = null
## Как быстро гаснет разгон: больше — тормозит резче.
var friction := 5.5
## Медленнее этого не разгоняем (пикселей в секунду).
var min_speed := 90.0
## Ограничение сверху, чтобы «рывок» пальцем не улетал через пол-списка.
var max_speed := 4200.0

var _velocity := 0.0
var _last_y := 0.0
var _last_ms := 0
var _dragging := false
var _active := false

func _ready() -> void:
	if target == null and get_parent() is ScrollContainer:
		target = get_parent()
	if target == null or not is_instance_valid(target):
		set_process(false)
		return
	if not target.scroll_started.is_connected(_on_scroll_started):
		target.scroll_started.connect(_on_scroll_started)
	if not target.scroll_ended.is_connected(_on_scroll_ended):
		target.scroll_ended.connect(_on_scroll_ended)
	if not target.child_entered_tree.is_connected(_on_child_entered):
		target.child_entered_tree.connect(_on_child_entered)
	_last_y = float(target.scroll_vertical)
	pass_through(target)

## Пропустить касания сквозь строки: кнопка остаётся нажимаемой, а список
## всё равно получает движение пальца. Ползунки трогать нельзя — иначе они
## будут ездить вместе со списком.
func pass_through(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			var control := child as Control
			var keep := control is HSlider or control is VSlider or control is ScrollBar
			if not keep and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				control.mouse_filter = Control.MOUSE_FILTER_PASS
		pass_through(child)

func _on_child_entered(_node: Node) -> void:
	# Содержимое списка перерисовывается при новых сообщениях — новые строки
	# тоже должны пропускать касания.
	pass_through.call_deferred(target)

func _on_scroll_started() -> void:
	_dragging = true
	_active = false
	_velocity = 0.0
	_last_y = float(target.scroll_vertical)
	_last_ms = Time.get_ticks_msec()

func _on_scroll_ended() -> void:
	_dragging = false
	var speed := clampf(_velocity, -max_speed, max_speed)
	if absf(speed) >= min_speed:
		_velocity = speed
		_active = true
	else:
		_velocity = 0.0
		_active = false
	_last_y = float(target.scroll_vertical)
	_last_ms = Time.get_ticks_msec()

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _dragging:
		var now := Time.get_ticks_msec()
		var y := float(target.scroll_vertical)
		var dt := float(now - _last_ms) / 1000.0
		if dt > 0.0:
			_velocity = (y - _last_y) / dt
		_last_y = y
		_last_ms = now
		return
	if not _active:
		return
	_velocity *= exp(-friction * delta)
	if absf(_velocity) < min_speed:
		_velocity = 0.0
		_active = false
		return
	var limit := _scroll_limit()
	var moved := float(target.scroll_vertical) + _velocity * delta
	if moved <= 0.0 or moved >= limit:
		moved = clampf(moved, 0.0, limit)
		_velocity = 0.0
		_active = false
	target.scroll_vertical = int(round(moved))

## Докуда вообще можно прокрутить этот список
func _scroll_limit() -> float:
	var bar := target.get_v_scroll_bar()
	if bar == null:
		return 0.0
	return maxf(float(bar.max_value - bar.page), 0.0)
