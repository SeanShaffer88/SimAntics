extends Node2D
## Specks of soil kicked loose by digging ants: a few pixels that spray off the dig
## face, arc under gravity and fade.

const LIFE := 0.6
const GRAVITY := 140.0
const MAX_SPECKS := 300

var _specks: Array[Dictionary] = []  # pos, vel, age
var _colors: Array[Color] = []
var _rng := RandomNumberGenerator.new()


func setup(soil: Color, seed_value: int) -> void:
	_rng.seed = seed_value + 71
	_colors = [soil, soil.lightened(0.18), soil.darkened(0.2)]


## A small puff of specks at `at`, thrown roughly along `dir`.
func puff(at: Vector2, dir: Vector2) -> void:
	for i in _rng.randi_range(1, 3):
		if _specks.size() >= MAX_SPECKS:
			return
		var v := (dir.normalized() * _rng.randf_range(15.0, 40.0)).rotated(_rng.randf_range(-0.9, 0.9))
		v.y -= _rng.randf_range(10.0, 30.0)
		_specks.append({"pos": at, "vel": v, "age": 0.0, "c": _colors[_rng.randi() % _colors.size()]})


func _process(delta: float) -> void:
	if _specks.is_empty():
		return
	for i in range(_specks.size() - 1, -1, -1):
		var s: Dictionary = _specks[i]
		s["age"] += delta
		if s["age"] >= LIFE:
			_specks.remove_at(i)
			continue
		var v: Vector2 = s["vel"]
		v.y += GRAVITY * delta
		s["vel"] = v
		s["pos"] = (s["pos"] as Vector2) + v * delta
	queue_redraw()


func _draw() -> void:
	for s in _specks:
		var c: Color = s["c"]
		c.a = 1.0 - float(s["age"]) / LIFE
		var p: Vector2 = s["pos"]
		draw_rect(Rect2(roundf(p.x), roundf(p.y), 1.0, 1.0), c)
