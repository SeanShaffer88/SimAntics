extends Node2D
## A small weed near a black-garden-ant nest with a herd of aphids on its stem. The ants
## stroke the aphids for sugary honeydew and guard them from predators in return.
## Drawn in pixels; it sways a little in the breeze and is bare in winter.

const STEM := Color("#4a7a2a")
const STEM_DARK := Color("#2e5418")
const LEAF := Color("#6aa03a")
const LEAF_LIGHT := Color("#8cc050")
const APHID := Color("#d8ec80")
const APHID_DARK := Color("#3a5214")
const FLOWER := Color("#f0c838")
const FLOWER_DARK := Color("#c89820")
const HONEYDEW := Color(1.0, 0.95, 0.7, 0.9)

var winter := false:
	set(value):
		winter = value
		queue_redraw()

var _height := 34
var _aphids: Array[Vector2i] = []  # (stem row, side) of each aphid
var _clock := 0.0
var _sway := 0


func setup(ground_y: float, x: float, seed_value: int) -> void:
	position = Vector2(roundf(x), ground_y)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3141
	_height = rng.randi_range(44, 56)
	for i in rng.randi_range(6, 10):
		_aphids.append(Vector2i(rng.randi_range(8, _height - 4), -1 if rng.randf() < 0.5 else 1))


func _process(delta: float) -> void:
	_clock += delta
	var s := int(roundf(sin(_clock * 0.9) * 1.2))
	if s != _sway:
		_sway = s
		queue_redraw()


func _stem_x(row: int) -> float:
	return roundf(float(_sway) * float(row) / float(_height))  # the top sways, the base stays put


func _draw() -> void:
	for row in _height:
		var sx := _stem_x(row)
		draw_rect(Rect2(sx, -row - 1, 2, 1), STEM if row % 5 else STEM_DARK)
	if winter:
		return  # the aphids overwinter as eggs; the stem dies back
	for i in 4:  # paired leaves up the stem
		var row := 10 + i * 7
		if row >= _height - 2:
			break
		var sx := _stem_x(row)
		var side := -1 if i % 2 == 0 else 1
		for k in 5:
			var lx := sx + (2 + k if side > 0 else -1 - k)
			draw_rect(Rect2(lx, -row - 1 - (k >> 1), 1, 2), LEAF if k < 3 else LEAF_LIGHT)
	var top := _stem_x(_height)
	draw_rect(Rect2(top - 2, -_height - 4, 6, 4), FLOWER)  # a small yellow flower head
	draw_rect(Rect2(top - 1, -_height - 5, 4, 1), FLOWER)
	draw_rect(Rect2(top, -_height - 3, 2, 2), FLOWER_DARK)
	for a in _aphids:
		var ax := _stem_x(a.x) + (2.0 if a.y > 0 else -2.0)
		var ox := ax + (0.0 if a.y > 0 else -1.0)
		draw_rect(Rect2(ox - 1, -a.x - 3, 5, 4), APHID_DARK)  # outline so they read against the grass
		draw_rect(Rect2(ox, -a.x - 2, 3, 2), APHID)
	# a glint of honeydew now and then
	var glint := int(_clock * 0.5) % maxi(_aphids.size(), 1)
	if fmod(_clock, 2.0) < 0.6 and not _aphids.is_empty():
		var g := _aphids[glint]
		draw_rect(Rect2(_stem_x(g.x) + (4.0 if g.y > 0 else -3.0), -g.x - 1, 1, 1), HONEYDEW)
