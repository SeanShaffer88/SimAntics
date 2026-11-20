extends Node2D
## Gentle, occasional rain over the surface: the sky dulls, pixel raindrops fall and
## splash on the ground, and the colony stays underground until it clears.

signal rain_changed(raining: bool)

const DRY_TIME := Vector2(240.0, 540.0)  # seconds between showers
const RAIN_TIME := Vector2(60.0, 130.0)
const FADE := 6.0
const DROPS := 150
const DROP_COLOR := Color(0.72, 0.82, 0.95, 0.65)

var raining := false
var intensity := 0.0  # 0..1, eases in and out so showers start and stop softly
var snow := false  # in winter showers fall as snow
var autumn := false  # leaves drift down
var snow_depth := 0.0  # 0..1 snow lying on the ground; builds in winter, melts after

const SNOW_COLOR := Color(0.95, 0.97, 1.0, 0.95)
const LEAF_TONES := [Color("#d08a2a"), Color("#c0782a"), Color("#a8442a"), Color("#e0b048")]

var _clear_xs: Array[float] = []  # entrances stay open through the snow
var _leaves: Array[Dictionary] = []
var _leaf_clock := 0.0
var _cover_noise: PackedFloat32Array = PackedFloat32Array()

var _clock := 0.0
var _ground_y := 120.0
var _width := 1280.0
var _rng := RandomNumberGenerator.new()
var _drops: Array[Vector3] = []  # x, y, speed
var _splashes: Array[Vector3] = []  # x, y, age


func setup(ground_y: float, width: float, seed_value: int) -> void:
	_ground_y = ground_y
	_width = width
	_rng.seed = seed_value + 913
	_clock = _rng.randf_range(DRY_TIME.x * 0.5, DRY_TIME.y)
	for i in DROPS:
		_drops.append(Vector3(_rng.randf_range(0.0, width), _rng.randf_range(-ground_y, ground_y), _rng.randf_range(260.0, 340.0)))
	_cover_noise.resize(int(width / 2.0) + 1)
	for i in _cover_noise.size():
		_cover_noise[i] = _rng.randf_range(0.6, 1.0)


func set_clear_spots(xs: Array[float]) -> void:
	_clear_xs = xs


## Starts or stops a shower now (also used by tests).
func set_raining(value: bool) -> void:
	if value == raining:
		return
	raining = value
	_clock = _rng.randf_range(RAIN_TIME.x, RAIN_TIME.y) if raining else _rng.randf_range(DRY_TIME.x, DRY_TIME.y)
	rain_changed.emit(raining)


func _process(delta: float) -> void:
	_clock -= delta
	if _clock <= 0.0:
		set_raining(not raining)
	intensity = move_toward(intensity, 1.0 if raining else 0.0, delta / FADE)
	# snow builds up while it snows in winter and melts once the season turns
	if snow and raining:
		snow_depth = minf(1.0, snow_depth + delta / 90.0)
	elif not snow:
		snow_depth = maxf(0.0, snow_depth - delta / 60.0)
	_update_leaves(delta)
	if intensity <= 0.0 and _splashes.is_empty() and _leaves.is_empty() and snow_depth <= 0.0:
		return
	var active := int(DROPS * intensity)
	var fall := 0.28 if snow else 1.0  # flakes drift down slowly
	for i in active:
		var d := _drops[i]
		d.y += d.z * delta * fall
		if snow:
			d.x += sin(d.y * 0.05 + d.z) * 18.0 * delta
		else:
			d.x -= d.z * 0.12 * delta  # a slight slant in the breeze
		if d.y >= _ground_y:
			if not snow and _rng.randf() < 0.5:
				_splashes.append(Vector3(d.x, _ground_y, 0.0))
			d = Vector3(_rng.randf_range(0.0, _width + 40.0), _rng.randf_range(-40.0, -4.0), d.z)
		_drops[i] = d
	for i in range(_splashes.size() - 1, -1, -1):
		var s := _splashes[i]
		s.z += delta
		if s.z > 0.25:
			_splashes.remove_at(i)
		else:
			_splashes[i] = s
	queue_redraw()


func _update_leaves(delta: float) -> void:
	if autumn:
		_leaf_clock -= delta
		if _leaf_clock <= 0.0:
			_leaf_clock = _rng.randf_range(0.8, 2.5)
			_leaves.append({"pos": Vector2(_rng.randf_range(0.0, _width), _rng.randf_range(-10.0, 30.0)),
					"phase": _rng.randf() * TAU, "c": LEAF_TONES[_rng.randi() % LEAF_TONES.size()], "rest": 0.0})
	for i in range(_leaves.size() - 1, -1, -1):
		var leaf: Dictionary = _leaves[i]
		var p: Vector2 = leaf["pos"]
		if p.y < _ground_y - 1.0:
			leaf["phase"] = float(leaf["phase"]) + delta * 2.2
			p += Vector2(sin(float(leaf["phase"])) * 22.0, 16.0) * delta  # see-sawing down
			leaf["pos"] = p
		else:
			leaf["rest"] = float(leaf["rest"]) + delta
			if float(leaf["rest"]) > 12.0:
				_leaves.remove_at(i)


func _draw() -> void:
	if snow_depth > 0.0:
		for i in _cover_noise.size():
			var x := i * 2.0
			var near_hole := false
			for cx in _clear_xs:
				if absf(x - cx) < 10.0:
					near_hole = true
			if near_hole:
				continue
			var h := roundf(_cover_noise[i] * snow_depth * 3.0) * 2.0
			if h > 0.0:
				draw_rect(Rect2(x, _ground_y - h + 1.0, 2.0, h), SNOW_COLOR)
	for leaf in _leaves:
		var p: Vector2 = leaf["pos"]
		var c: Color = leaf["c"]
		c.a = clampf(1.0 - (float(leaf["rest"]) - 9.0) / 3.0, 0.0, 1.0)
		draw_rect(Rect2(roundf(p.x), roundf(p.y), 3.0, 2.0), c)
		draw_rect(Rect2(roundf(p.x) + 1.0, roundf(p.y) - 1.0, 1.0, 1.0), c.lightened(0.2))  # a curled tip
	var active := int(DROPS * intensity)
	for i in active:
		var d := _drops[i]
		if d.y > 0.0:
			if snow:
				draw_circle(Vector2(d.x, d.y), 1.1 + fmod(d.z, 0.6), SNOW_COLOR, true, -1.0, true)
			else:
				draw_line(Vector2(d.x, d.y), Vector2(d.x + 0.6, d.y + 5.0), DROP_COLOR, 1.0, true)
	for s in _splashes:
		var spread := 1.0 + s.z * 12.0
		var a := (1.0 - s.z / 0.25) * 0.6
		draw_circle(Vector2(s.x - spread, s.y - 2.0 - s.z * 6.0), 0.7, Color(DROP_COLOR, a), true, -1.0, true)
		draw_circle(Vector2(s.x + spread, s.y - 2.0 - s.z * 6.0), 0.7, Color(DROP_COLOR, a), true, -1.0, true)
