extends Node2D
## Water left on the grass after a shower: small glistening drops that slowly evaporate
## (faster in sunshine). Foragers stop to drink from them, as real ants do, and carry the
## water home in their crops.

const UiArt := preload("res://scripts/ui_art.gd")
const MAX_DROPS := 12

var _drops: Array[Dictionary] = []  # sprite, water (0..1), life
var _rng := RandomNumberGenerator.new()
var _ground_y := 120.0
var _width := 1280.0
var daylight := 1.0  # from the day/night cycle; drops dry faster in sun


func setup(ground_y: float, width: float, seed_value: int) -> void:
	_ground_y = ground_y
	_width = width
	_rng.seed = seed_value + 4242


## Leaves fresh drops on the grass, away from the given x positions (entrances).
func scatter(count: int, avoid: Array[float]) -> void:
	for i in count:
		if _drops.size() >= MAX_DROPS:
			return
		var x := _rng.randf_range(60.0, _width - 60.0)
		var clear := true
		for a in avoid:
			if absf(a - x) < 24.0:
				clear = false
		if not clear:
			continue
		var s := Sprite2D.new()
		s.texture = UiArt.water_bead(_rng.randi() % 2)
		s.position = Vector2(roundf(x), _ground_y - 2.0 - _rng.randi_range(0, 3))
		add_child(s)
		_drops.append({"sprite": s, "water": 1.0, "life": _rng.randf_range(260.0, 420.0)})


func count() -> int:
	return _drops.size()


## The nearest drop within `reach` px of x, or null.
func nearest(x: float, reach: float) -> Node2D:
	var best: Node2D = null
	var best_d := reach
	for d in _drops:
		var s: Sprite2D = d["sprite"]
		var dist := absf(s.position.x - x)
		if dist < best_d:
			best_d = dist
			best = s
	return best


## An ant drinks from a drop: it shrinks, and is gone after a few visits.
func sip(drop: Node2D) -> bool:
	for i in _drops.size():
		if _drops[i]["sprite"] == drop:
			_drops[i]["water"] = float(_drops[i]["water"]) - 0.34
			if float(_drops[i]["water"]) <= 0.0:
				_remove(i)
			return true
	return false


func _remove(i: int) -> void:
	(_drops[i]["sprite"] as Sprite2D).queue_free()
	_drops.remove_at(i)


func _process(delta: float) -> void:
	for i in range(_drops.size() - 1, -1, -1):
		var d := _drops[i]
		d["life"] = float(d["life"]) - delta * (0.4 + daylight)
		var s: Sprite2D = d["sprite"]
		var left := minf(float(d["water"]), float(d["life"]) / 60.0)
		s.scale = Vector2.ONE * clampf(0.5 + left * 0.5, 0.5, 1.0)
		s.modulate.a = clampf(left * 2.0, 0.0, 1.0)
		if float(d["life"]) <= 0.0:
			_remove(i)
