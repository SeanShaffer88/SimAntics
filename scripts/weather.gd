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
	if intensity <= 0.0 and _splashes.is_empty():
		return
	var active := int(DROPS * intensity)
	for i in active:
		var d := _drops[i]
		d.y += d.z * delta
		d.x -= d.z * 0.12 * delta  # a slight slant in the breeze
		if d.y >= _ground_y:
			if _rng.randf() < 0.5:
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


func _draw() -> void:
	var active := int(DROPS * intensity)
	for i in active:
		var d := _drops[i]
		if d.y > 0.0:
			draw_rect(Rect2(roundf(d.x), roundf(d.y), 1.0, 5.0), DROP_COLOR)
	for s in _splashes:
		var spread := 1.0 + s.z * 12.0
		var a := (1.0 - s.z / 0.25) * 0.6
		draw_rect(Rect2(s.x - spread, s.y - 2.0, 1.0, 1.0), Color(DROP_COLOR, a))
		draw_rect(Rect2(s.x + spread, s.y - 2.0, 1.0, 1.0), Color(DROP_COLOR, a))
