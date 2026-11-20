extends Node2D
## A wolf spider that now and then prowls the ground near the nest, hoping to ambush a
## forager. Ants that find it mob it, biting its legs (and spraying formic acid, for
## species that can), and once enough of them are harrying it the spider gives up and
## bolts off the edge of the farm. Nobody is harmed: the colony simply drives it away.

signal driven_off

const WALK_SPEED := 26.0
const FLEE_SPEED := 130.0
const GIVE_UP := 7.0  # seconds of mobbing (summed over ants) before it flees
const BODY := Color("#94785a")
const BODY_DARK := Color("#4a3828")
const STRIPE := Color("#d8c098")
const LEG := Color("#6e5a44")

var active := false
var fleeing := false

var _ground_y := 120.0
var _width := 1280.0
var _rng := RandomNumberGenerator.new()
var _target_x := 0.0
var _home_x := 0.0  # the entrance it lurks near
var _pause := 0.0
var _stay := 0.0
var _harass := 0.0
var _phase := 0.0
var _moving := false
var _facing := 1.0
var _tint := Color.WHITE


func setup(ground_y: float, width: float, seed_value: int) -> void:
	_ground_y = ground_y
	_width = width
	_rng.seed = seed_value + 6060
	scale = Vector2.ONE * 1.7  # a wolf spider dwarfs the ants
	visible = false


## Walks in from one side to lurk near the entrance at `lurk_x`.
func start(from_left: bool, lurk_x: float) -> void:
	active = true
	fleeing = false
	visible = true
	_harass = 0.0
	_home_x = lurk_x
	_stay = _rng.randf_range(60.0, 100.0)
	position = Vector2(-30.0 if from_left else _width + 30.0, _ground_y)
	_target_x = clampf(lurk_x + (-1.0 if from_left else 1.0) * _rng.randf_range(35.0, 70.0), 30.0, _width - 30.0)


## Called by ants biting at it (seconds of mobbing).
func harass(amount: float) -> void:
	if not active or fleeing:
		return
	_harass += amount
	if _harass >= GIVE_UP:
		_flee()


func _flee() -> void:
	fleeing = true
	_target_x = -50.0 if position.x < _width * 0.5 else _width + 50.0
	driven_off.emit()


func set_tint(tint: Color) -> void:
	_tint = tint


func _process(delta: float) -> void:
	if not active:
		return
	modulate = _tint
	_harass = maxf(0.0, _harass - delta * 0.3)  # it shrugs off the odd bite
	if not fleeing:
		_stay -= delta
		if _stay <= 0.0:  # nothing caught: it wanders off on its own
			fleeing = true
			_target_x = -50.0 if position.x < _width * 0.5 else _width + 50.0
	var speed := FLEE_SPEED if fleeing else WALK_SPEED
	var dx := _target_x - position.x
	_moving = absf(dx) > 1.0 and _pause <= 0.0
	if _pause > 0.0:
		_pause -= delta
	elif absf(dx) > 1.0:
		position.x += signf(dx) * minf(absf(dx), speed * delta)
		_facing = signf(dx)
	elif fleeing:
		active = false
		visible = false
		return
	else:
		# stalk: stop dead for a while, then creep to a new spot near the entrance
		_pause = _rng.randf_range(2.0, 6.0)
		_target_x = clampf(_home_x + _rng.randf_range(-90.0, 90.0), 30.0, _width - 30.0)
	if _moving:
		_phase += delta * (18.0 if fleeing else 9.0)
	queue_redraw()


func _draw() -> void:
	var f := _facing
	var thorax := Vector2(3.0 * f, -8.0)
	var abdomen := Vector2(-5.5 * f, -8.5)
	# eight long legs, side view: the far side drawn first and darker. Each leg rises
	# from the cephalothorax to a high knee, then down to a foot splayed front to back.
	var feet := [13.0, 6.5, -4.0, -12.0]
	for far: int in [1, 0]:
		var col := LEG.darkened(0.35) if far == 1 else LEG
		for i in 4:
			var step := sin(_phase + i * 1.7 + far * PI) * (2.5 if _moving else 0.0)
			var lift := maxf(0.0, cos(_phase + i * 1.7 + far * PI)) * (1.5 if _moving else 0.0)
			var hip := thorax + Vector2((1.5 - i) * 1.2 * f, 1.0)
			var foot := Vector2((float(feet[i]) + step + far * 1.5) * f, -lift)
			var knee := Vector2((hip.x + foot.x) * 0.5 + (2.0 if i < 2 else -2.0) * f, -15.0 + absf(1.5 - i) * 0.8)
			draw_line(hip, knee, col, 1.8, true)
			draw_line(knee, foot, col.darkened(0.15), 1.4, true)
	# abdomen, behind, with the wolf spider's pale cardiac stripe
	draw_set_transform(abdomen, 0.0, Vector2(1.0, 0.78))
	draw_circle(Vector2.ZERO, 6.2, BODY_DARK, true, -1.0, true)
	draw_circle(Vector2(0.6 * f, -0.9), 5.2, BODY, true, -1.0, true)
	draw_line(Vector2(-3.8, -2.2), Vector2(3.8, -2.2), STRIPE, 1.4, true)
	# cephalothorax, in front
	draw_set_transform(thorax, 0.0, Vector2(1.0, 0.8))
	draw_circle(Vector2.ZERO, 4.4, BODY_DARK, true, -1.0, true)
	draw_circle(Vector2(0.5 * f, -0.7), 3.6, BODY, true, -1.0, true)
	draw_line(Vector2(-2.6, -1.8), Vector2(2.6, -1.8), STRIPE, 1.1, true)
	draw_set_transform(Vector2.ZERO)
	# the big front eyes catch the light; pedipalps hang in front
	draw_circle(thorax + Vector2(3.6 * f, -2.4), 1.0, Color(0.1, 0.07, 0.05), true, -1.0, true)
	draw_circle(thorax + Vector2(3.9 * f, -2.7), 0.45, Color(0.95, 0.9, 0.7), true, -1.0, true)
	draw_line(thorax + Vector2(4.0 * f, 0.5), thorax + Vector2(6.0 * f, 3.5), LEG, 1.2, true)
