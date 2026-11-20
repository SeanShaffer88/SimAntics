extends Node2D
## A slow day/night cycle over the surface: daylight, a warm dusk, a blue night with
## twinkling stars, and dawn. Only the sky and surface change; the farm below stays
## lamp-lit. Ants go out less after dark (see Colony.night).

const CYCLE := 720.0  # seconds for a full day
const DAY_TINT := Color(1.0, 1.0, 1.0)
const DUSK_TINT := Color(1.0, 0.72, 0.55)
const NIGHT_TINT := Color(0.32, 0.38, 0.62)
const STAR_COUNT := 70

var time_of_day := 0.3  # 0 = midnight, 0.25 = dawn, 0.5 = noon, 0.75 = dusk
var daylight := 1.0

var _surface: CanvasItem
var _colony: Node
var _sky_height := 120.0
var _stars: Array[Vector3] = []  # x, y, twinkle phase


func setup(surface: CanvasItem, colony: Node, sky_height: float, width: float, seed_value: int) -> void:
	_surface = surface
	_colony = colony
	_sky_height = sky_height
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 77
	for i in STAR_COUNT:
		_stars.append(Vector3(rng.randf_range(0.0, width), rng.randf_range(4.0, sky_height * 0.62), rng.randf() * TAU))


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / CYCLE, 1.0)
	# daylight: 1 from mid-morning to late afternoon, 0 at night, smooth in between
	var sun := sin((time_of_day - 0.25) * TAU)  # +1 at noon, -1 at midnight
	daylight = smoothstep(-0.25, 0.35, sun)
	var warmth := clampf(1.0 - absf(sun) * 3.0, 0.0, 1.0)  # strongest at sunrise and sunset
	var tint := NIGHT_TINT.lerp(DAY_TINT, daylight).lerp(DUSK_TINT, warmth * 0.6)
	_surface.modulate = tint
	if _colony != null:
		_colony.surface_tint = tint
		_colony.night = daylight < 0.3
	queue_redraw()


func _draw() -> void:
	var visible := 1.0 - daylight
	if visible <= 0.02:
		return
	var t := Time.get_ticks_msec() / 1000.0
	for s in _stars:
		var twinkle := 0.55 + 0.45 * sin(t * 1.7 + s.z)
		var size := 1.0 if s.z < 4.5 else 2.0
		draw_rect(Rect2(s.x, s.y, size, size), Color(1.0, 0.97, 0.88, visible * twinkle * 0.9))
