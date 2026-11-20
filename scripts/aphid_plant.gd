extends Node2D
## A small weed near a black-garden-ant nest with a herd of aphids on its stem. The ants
## stroke the aphids for sugary honeydew and guard them from predators in return.
## It sways in the breeze and is bare in winter.

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


func setup(ground_y: float, x: float, seed_value: int) -> void:
	position = Vector2(roundf(x), ground_y)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3141
	_height = rng.randi_range(44, 56)
	for i in rng.randi_range(6, 10):
		_aphids.append(Vector2i(rng.randi_range(8, _height - 4), -1 if rng.randf() < 0.5 else 1))


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()  # it sways continuously in the breeze


## Where the stem is at a height (0 = ground): it bends more toward the top.
func _stem_at(row: float) -> Vector2:
	var sway := sin(_clock * 0.9) * 1.6 + sin(_clock * 2.3) * 0.3
	var t := row / float(_height)
	return Vector2(sway * t * t, -row)


func _draw() -> void:
	var stem := PackedVector2Array()
	for k in 13:
		stem.append(_stem_at(float(k) / 12.0 * _height))
	draw_polyline(stem, STEM_DARK, 2.4, true)
	draw_polyline(stem, STEM, 1.4, true)
	if winter:
		return  # the aphids overwinter as eggs; the stem dies back
	for i in 4:  # leaves in pairs up the stem: a pointed blade with a midrib
		var row := 10.0 + i * 7.0
		if row >= _height - 2:
			break
		var base := _stem_at(row)
		var side := -1.0 if i % 2 == 0 else 1.0
		var tip := base + Vector2(side * 7.0, -3.5)
		var mid := (base + tip) * 0.5
		var across := (tip - base).orthogonal().normalized() * 1.9
		var blade := PackedVector2Array([base, mid + across, tip, mid - across])
		draw_colored_polygon(blade, LEAF)
		draw_polyline(PackedVector2Array([base, mid - across * 0.4, tip]), LEAF_LIGHT, 0.8, true)
		draw_polyline(PackedVector2Array([base, mid + across, tip, mid - across, base]), STEM_DARK, 0.6, true)
	var top := _stem_at(_height)
	for k in 6:  # a small yellow flower
		var petal := top + Vector2.from_angle(k * TAU / 6.0 + 0.3) * 2.2 + Vector2(0, -1.5)
		draw_circle(petal, 1.5, FLOWER, true, -1.0, true)
	draw_circle(top + Vector2(0, -1.5), 1.3, FLOWER_DARK, true, -1.0, true)
	for a in _aphids:  # aphids clustered on the stem, pear-shaped and pale green
		var at := _stem_at(a.x) + Vector2(2.2 * a.y, 0.0)
		draw_circle(at, 1.9, APHID_DARK, true, -1.0, true)
		draw_circle(at, 1.4, APHID, true, -1.0, true)
		draw_circle(at + Vector2(0.9 * a.y, -0.4), 0.9, APHID.lightened(0.15), true, -1.0, true)
		draw_circle(at + Vector2(-0.4, -0.5), 0.35, Color(1, 1, 1, 0.85), true, -1.0, true)
	# a drop of honeydew glistening now and then
	if fmod(_clock, 2.0) < 0.6 and not _aphids.is_empty():
		var g := _aphids[int(_clock * 0.5) % _aphids.size()]
		draw_circle(_stem_at(g.x) + Vector2(4.0 * g.y, 1.0), 0.8, HONEYDEW, true, -1.0, true)
