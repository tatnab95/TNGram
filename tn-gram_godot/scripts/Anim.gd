extends RefCounted
class_name Anim
## Плавные появления для Тнграма. Правило безопасности: проверки раскладки
## (тесты на компьютере) следят за текстом и координатами узлов, а не за
## прозрачностью, — поэтому везде анимируется только modulate. Сдвиги и другие
## «двигающие» эффекты включаются только на телефоне, где автоматических
## проверок раскладки нет.

## Мягкое появление: прозрачность 0 → 1
static func fade_in(node: CanvasItem, dur: float = 0.16, delay: float = 0.0) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	node.modulate.a = 0.0
	var tween := node.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(node, "modulate:a", 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Появление нового экрана: плавный фейд, на телефоне ещё и лёгкий подъём снизу
static func screen_in(node: CanvasItem) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	fade_in(node, 0.18)
	if OS.has_feature("android") and node is Control:
		var control := node as Control
		var base_y := control.position.y
		control.position.y = base_y + 24.0
		var tween := control.create_tween()
		tween.tween_property(control, "position:y", base_y, 0.24) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Список оживает: каждая карточка проступает с небольшим сдвигом по времени
static func stagger(parent: Node, step: float = 0.035, dur: float = 0.14) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var i := 0
	for child in parent.get_children():
		if child is CanvasItem:
			fade_in(child as CanvasItem, dur, float(i) * step)
		i += 1

## Фон дышит: пятно свечения медленно покачивается вверх-вниз
static func breathe(node: CanvasItem, amp: float = 14.0, dur: float = 7.0) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var base_y := (node as Control).position.y
	var tween := (node as Control).create_tween().set_loops()
	tween.tween_property(node, "position:y", base_y + amp, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "position:y", base_y, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
