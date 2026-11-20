extends Node2D
## Excavated soil piled up around the nest entrances. Each pellet a digger drops adds
## to a column; a column that gets much taller than its neighbours slumps sideways,
## so the spoil settles into a low, natural mound (the nest's tumulus).

const PIXEL := 2
const MAX_HEIGHT := 9  # in pixels of PIXEL size

const HOLE_COLOR := Color("#2a1b12")

var _ground_y := 120.0
var _columns: Dictionary = {}  # column index -> height
var _holes: Array[float] = []  # entrances opened from below after the surface was drawn
var _colors: Array[Color] = []
var _rng := RandomNumberGenerator.new()


func setup(ground_y: float, soil: Color, seed_value: int) -> void:
	_ground_y = ground_y
	_rng.seed = seed_value + 55
	_colors = [soil, soil.darkened(0.15), soil.lightened(0.12), soil.darkened(0.3)]


## Drops one pellet of soil at x.
func add(x: float) -> void:
	var col := int(roundf(x / PIXEL))
	for i in 6:  # roll down the slope until it settles
		var h := int(_columns.get(col, 0))
		var left := int(_columns.get(col - 1, 0))
		var right := int(_columns.get(col + 1, 0))
		if h >= MAX_HEIGHT or h > mini(left, right) + 1:
			col += -1 if left < right or (left == right and _rng.randf() < 0.5) else 1
			continue
		break
	_columns[col] = mini(int(_columns.get(col, 0)) + 1, MAX_HEIGHT)
	queue_redraw()


## A new opening to the surface, dug from below.
func add_hole(x: float) -> void:
	if not _holes.has(x):
		_holes.append(x)
		queue_redraw()


func _draw() -> void:
	for x in _holes:
		draw_rect(Rect2(roundf(x) - 4.0, _ground_y - 2.0, 8.0, 10.0), HOLE_COLOR)
	for col: int in _columns:
		var h: int = _columns[col]
		for row in h:
			var c := _colors[(col * 7 + row * 3) % _colors.size()]
			draw_rect(Rect2(col * PIXEL, _ground_y - (row + 1) * PIXEL, PIXEL, PIXEL), c)


func to_save() -> Dictionary:
	var out := {}
	for col: int in _columns:
		out[str(col)] = _columns[col]
	return {"columns": out, "holes": _holes}


func restore(saved: Dictionary) -> void:
	var cols: Dictionary = saved.get("columns", {})
	for key in cols:
		_columns[int(key)] = int(cols[key])
	for x in saved.get("holes", []):
		_holes.append(float(x))
	queue_redraw()
