extends Node2D
## Faint pheromone trail on the surface, laid by foragers carrying food home.
## Each scent mark fades over half a minute, so busy routes show up as dotted paths.

const LIFETIME := 30.0
const MAX_POINTS := 900
const COLOR := Color(0.95, 0.85, 0.55)

var _points: Array[Vector3] = []  # x, y, age


func add_point(p: Vector2) -> void:
	_points.append(Vector3(p.x, p.y, 0.0))
	if _points.size() > MAX_POINTS:
		_points.pop_front()


func _process(delta: float) -> void:
	if _points.is_empty():
		return
	for i in _points.size():
		var p := _points[i]
		p.z += delta
		_points[i] = p
	while not _points.is_empty() and _points[0].z > LIFETIME:
		_points.pop_front()
	queue_redraw()


func _draw() -> void:
	for p in _points:
		var a := (1.0 - p.z / LIFETIME) * 0.45
		draw_rect(Rect2(roundf(p.x), roundf(p.y), 1.0, 1.0), Color(COLOR, a))
