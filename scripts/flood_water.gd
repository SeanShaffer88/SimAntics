extends Node2D
## Rainwater standing in flooded chambers: a translucent fill that follows the dug shape
## of each room, with a bright, rippling surface line.

const WATER := Color(0.34, 0.5, 0.62, 0.55)
const SURFACE := Color(0.72, 0.84, 0.92, 0.8)

var _nest: Node2D  # subterranean_layer.gd
var _rows: Dictionary = {}  # chamber id -> Array of Vector3(x_left, x_right, y)
var _clock := 0.0
var _rebuild := 0.0


func setup(nest: Node2D) -> void:
	_nest = nest


func _process(delta: float) -> void:
	_clock += delta
	_rebuild -= delta
	if _rebuild <= 0.0:
		_rebuild = 0.5
		_rows.clear()
		for id: int in _nest.flood:
			var level: float = _nest.flood[id]
			if level > 0.01:
				_rows[id] = _spans(id, level)
	if not _rows.is_empty() or _clock < 1.0:
		queue_redraw()


## Horizontal runs of open space from the chamber floor up to the water line.
func _spans(id: int, level: float) -> Array:
	var center: Vector2 = _nest.nodes[id]
	var radii: Vector2 = _nest.chambers[id]["radii"]
	var floor_y: float = _nest.chamber_floor_y(id)
	var top := floor_y - level * (floor_y - (center.y - radii.y))
	var out := []
	var y := floor_y - 0.5
	while y >= top:
		var left := center.x
		while left > center.x - radii.x * 2.2 and not _nest.is_solid(Vector2(left - 1.0, y)):
			left -= 1.0
		var right := center.x
		while right < center.x + radii.x * 2.2 and not _nest.is_solid(Vector2(right + 1.0, y)):
			right += 1.0
		if right > left:
			out.append(Vector3(left, right, y))
		y -= 1.0
	return out


func _draw() -> void:
	for id: int in _rows:
		var rows: Array = _rows[id]
		for i in rows.size():
			var r: Vector3 = rows[i]
			var deep := 1.0 - float(i) / maxf(1.0, rows.size())
			var col := WATER.darkened(0.15 * deep)
			draw_rect(Rect2(r.x, r.z - 0.5, r.y - r.x + 1.0, 1.0), col)
		if not rows.is_empty():
			var top: Vector3 = rows[rows.size() - 1]
			draw_rect(Rect2(top.x, top.z - 1.0, top.y - top.x + 1.0, 1.0), SURFACE)
			var x := top.x + fposmod(_clock * 9.0, maxf(1.0, top.y - top.x))
			draw_rect(Rect2(x, top.z - 1.0, 4.0, 1.0), Color(1, 1, 1, 0.7))  # a ripple running across
