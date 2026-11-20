extends Node2D
## Some species seal their nest at night and in bad weather: workers heap soil pellets
## and small pebbles into the entrance holes once the last foragers are home, and clear
## them again in the morning. Red harvester ants are known for it, and leafcutters close
## their entrances against cold and rain.

const PIXEL := 2.0

var _xs: Array[float] = []
var _amount: PackedFloat32Array = PackedFloat32Array()  # 0 open .. 1 sealed, per entrance
var _target := 0.0
var _ground_y := 120.0
var _colors: Array[Color] = []
var _pellets: Array[Vector3] = []  # x offset, height, colour index: the order pellets go in


func setup(ground_y: float, soil: Color, seed_value: int) -> void:
	_ground_y = ground_y
	_colors = [soil, soil.darkened(0.2), soil.lightened(0.15), Color("#8a8478"), Color("#6e6a62")]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 808
	for row in 10:  # fill from the bottom of the hole up to a low cap above the ground
		var cols := 9 if row < 9 else 7
		for c in cols:
			_pellets.append(Vector3(float(c - (cols >> 1)), float(row), rng.randi() % _colors.size()))


func set_entrances(xs: Array[float]) -> void:
	_xs = xs
	_amount.resize(xs.size())


## True while the colony wants its entrances sealed.
func set_closed(closed: bool) -> void:
	_target = 1.0 if closed else 0.0


## Workers seal or open the holes over half a minute or so; `allow_close` is false while
## foragers are still outside (nobody is shut out).
func advance(delta: float, allow_close: bool) -> void:
	for i in _amount.size():
		if _target > _amount[i] and not allow_close:
			continue
		_amount[i] = move_toward(_amount[i], _target, delta / 30.0)
	queue_redraw()


func is_working() -> bool:
	for a in _amount:
		if absf(a - _target) > 0.01:
			return true
	return false


func is_sealed() -> bool:
	for a in _amount:
		if a < 0.99:
			return false
	return not _amount.is_empty()


func _draw() -> void:
	for i in _xs.size():
		var shown := int(roundf(_amount[i] * _pellets.size()))
		for k in shown:
			var p := _pellets[k]
			var x := roundf(_xs[i] / PIXEL + p.x) * PIXEL
			var y := _ground_y + 8.0 - p.y * PIXEL
			draw_rect(Rect2(x, y, PIXEL, PIXEL), _colors[int(p.z)])
