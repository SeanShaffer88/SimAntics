extends Node2D
## An occasional visitor: a small songbird swoops down by day, hops toward an ant on
## the surface and carries it off. Tapping the bird three times startles it away
## early. The colony makes up the loss through its normal brood cycle.

signal ant_taken
signal scared_off

const PixelArt := preload("res://scripts/pixel_art_factory.gd")

enum State { WAITING, SWOOP, HOP, SNATCH, LEAVE, SCARED }

const INTERVAL := Vector2(150.0, 360.0)  # seconds between visits
const RETRY := 20.0  # check again soon if nobody is outside
const SCALE := 2.0
const TAPS_TO_SCARE := 3
const HIT_RADIUS := 26.0

var state: State = State.WAITING

var _ants: Node2D
var _colony: Node
var _day_night: Node
var _ground_y := 120.0
var _width := 1280.0
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _t := 0.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _target: Node2D
var _carried: Node2D
var _taps := 0
var _hops_left := 0
var _sprite: Sprite2D


func setup(ants: Node2D, colony: Node, day_night: Node, ground_y: float, width: float, seed_value: int) -> void:
	_ants = ants
	_colony = colony
	_day_night = day_night
	_ground_y = ground_y
	_width = width
	_rng.seed = seed_value + 3101
	_clock = _rng.randf_range(INTERVAL.x * 0.5, INTERVAL.y)
	_sprite = Sprite2D.new()
	_sprite.scale = Vector2.ONE * SCALE
	_sprite.texture = PixelArt.bird_frame("perched")
	add_child(_sprite)
	visible = false


## Starts a visit right away if an ant is outside (also used by tests).
func visit_now() -> bool:
	var ant := _pick_ant(-1.0)
	if ant == null:
		return false
	_begin(ant)
	return true


## A tap at `world`: returns true if it hit the bird.
func try_tap(world: Vector2) -> bool:
	if state in [State.WAITING, State.SCARED] or not visible:
		return false
	if world.distance_to(global_position) > HIT_RADIUS:
		return false
	_taps += 1
	if _taps >= TAPS_TO_SCARE:
		_scare()
	else:
		var flinch := create_tween()  # a startled little jump
		flinch.tween_property(_sprite, "position:y", -8.0, 0.08)
		flinch.tween_property(_sprite, "position:y", 0.0, 0.12)
	return true


func _process(delta: float) -> void:
	match state:
		State.WAITING:
			_clock -= delta
			if _clock <= 0.0:
				var calm: bool = not _colony.raining and _day_night.daylight > 0.6
				if not (calm and visit_now()):
					_clock = RETRY
		State.SWOOP:
			_t += delta / 1.6
			var mid := Vector2((_from.x + _to.x) * 0.5, _to.y - 70.0)
			position = _from.lerp(mid, _t).lerp(mid.lerp(_to, _t), _t)  # quadratic arc
			_flap(_t * 10.0)
			if _t >= 1.0:
				position = _to
				state = State.HOP
				_t = -_rng.randf_range(0.3, 0.8)  # look around first
				_sprite.texture = PixelArt.bird_frame("perched")
		State.HOP:
			_update_hop(delta)
		State.SNATCH:
			_t += delta
			if _t >= 0.35:
				_fly_off(false)
		State.LEAVE, State.SCARED:
			_t += delta / (0.9 if state == State.SCARED else 1.8)
			position = _from.lerp(_to, ease(_t, 0.6))
			_flap(_t * (16.0 if state == State.SCARED else 10.0))
			if _t >= 1.0:
				_finish()


func _update_hop(delta: float) -> void:
	_t += delta
	if _t < 0.0:
		return  # pausing: a peck or a glance about
	if _target == null or not is_instance_valid(_target) or not _target.is_exposed():
		_target = _pick_ant(position.x)
		if _target == null:
			_fly_off(false)
			return
	var gap := _target.global_position.x - position.x
	_face(gap)
	if absf(gap) < 16.0:
		_grab()
		return
	# one hop: a short arc toward the ant, then a pause
	var hop := 0.18
	var p := clampf(_t / hop, 0.0, 1.0)
	_sprite.texture = PixelArt.bird_frame("hop")
	position.x += signf(gap) * 70.0 * delta
	_sprite.position.y = -sin(p * PI) * 6.0
	if _t >= hop:
		_sprite.position.y = 0.0
		_sprite.texture = PixelArt.bird_frame("perched")
		_t = -_rng.randf_range(0.35, 0.9)


func _grab() -> void:
	_target.snatch()
	_target.get_parent().remove_child(_target)
	add_child(_target)
	_target.position = Vector2(0.0, 10.0)
	_carried = _target
	_target = null
	state = State.SNATCH
	_t = 0.0
	ant_taken.emit()


func _scare() -> void:
	scared_off.emit()
	_fly_off(true)


func _fly_off(scared: bool) -> void:
	state = State.SCARED if scared else State.LEAVE
	_t = 0.0
	_from = position
	var side := -1.0 if position.x < _width * 0.5 else 1.0
	if scared:
		side = -side if _rng.randf() < 0.5 else side
	_to = Vector2(_width * 0.5 + side * (_width * 0.5 + 80.0), -60.0)
	_face(_to.x - position.x)


func _finish() -> void:
	if _carried != null and is_instance_valid(_carried):
		_carried.queue_free()
	_carried = null
	visible = false
	state = State.WAITING
	_clock = _rng.randf_range(INTERVAL.x, INTERVAL.y)


func _begin(ant: Node2D) -> void:
	_target = ant
	_taps = 0
	var ant_x := ant.global_position.x
	var side := 1.0 if ant_x < _width * 0.5 else -1.0  # come in from the far side
	_from = Vector2(ant_x + side * 520.0, -40.0)
	_to = Vector2(clampf(ant_x + side * _rng.randf_range(60.0, 110.0), 20.0, _width - 20.0), _ground_y - 9.0)
	position = _from
	_t = 0.0
	state = State.SWOOP
	visible = true
	_face(_to.x - _from.x)


func _pick_ant(near_x: float) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for ant in _ants.get_children():
		if not ant.is_exposed():
			continue
		var d := absf(ant.global_position.x - near_x) if near_x >= 0.0 else _rng.randf()
		if near_x >= 0.0 and d > 320.0:
			continue
		if d < best_d:
			best_d = d
			best = ant
	return best


func _flap(phase: float) -> void:
	_sprite.texture = PixelArt.bird_frame("flap_up" if int(phase) % 2 == 0 else "flap_down")
	_sprite.position.y = 0.0


func _face(dx: float) -> void:
	if absf(dx) > 0.5:
		_sprite.flip_h = dx < 0.0
