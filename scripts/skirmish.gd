extends Node2D
## Pavement-ant "sidewalk wars": now and then workers from a neighbouring colony march in
## from the edge of the farm and meet this colony's workers at the border. They grapple
## and shove in pairs for a while (it is mostly ritual: few ants are ever hurt), then the
## rivals withdraw. Real Tetramorium colonies settle their territory borders this way.

signal ended

const ColonyArt := preload("res://scripts/colony_art.gd")
const RIVAL_TINT := Color(0.72, 0.66, 0.66)  # a slightly different colony odour and shade
const SPEED := 40.0
const FRAME_TIME := 0.09

var active := false
var border_x := NAN

var _frames: Array[ImageTexture] = []
var _rivals: Array[Dictionary] = []  # sprite, target, frame_clock, frame
var _ground_y := 120.0
var _width := 1280.0
var _left := 0.0
var _leaving := false
var _rng := RandomNumberGenerator.new()
var _tint := Color.WHITE


func setup(species: Dictionary, ground_y: float, width: float, seed_value: int) -> void:
	var caste: Dictionary = (species["castes"] as Array)[0]
	_frames = ColonyArt.ant_frames(species, caste["size"], caste["head"])
	_ground_y = ground_y
	_width = width
	_rng.seed = seed_value + 777


## Rivals arrive from one side of the farm and hold the border for a while.
func start(from_left: bool) -> void:
	if active:
		return
	active = true
	_leaving = false
	_left = _rng.randf_range(45.0, 75.0)
	border_x = _rng.randf_range(120.0, 220.0)
	if not from_left:
		border_x = _width - border_x
	var half_h := _frames[0].get_height() * 0.5
	for i in _rng.randi_range(7, 11):
		var s := Sprite2D.new()
		s.texture = _frames[0]
		var start_x := (-20.0 - i * 9.0) if from_left else (_width + 20.0 + i * 9.0)
		s.position = Vector2(start_x, _ground_y - half_h)
		add_child(s)
		_rivals.append({"sprite": s, "target": _front_spot(from_left), "clock": 0.0, "frame": i})


func _front_spot(from_left: bool) -> float:
	# rivals hold their own side of the border, with a few pushing across it
	var depth := _rng.randf_range(-6.0, 26.0)
	return border_x - depth if from_left else border_x + depth


## True while rivals are at the border (not yet withdrawing).
func is_holding() -> bool:
	return active and not _leaving


func set_tint(tint: Color) -> void:
	_tint = tint


func _process(delta: float) -> void:
	if not active:
		return
	_left -= delta
	if _left <= 0.0 and not _leaving:
		_leaving = true  # the border is settled for now: they head home
		for r in _rivals:
			r["target"] = -40.0 if border_x < _width * 0.5 else _width + 40.0
	var gone := true
	for r in _rivals:
		var s: Sprite2D = r["sprite"]
		s.modulate = RIVAL_TINT * _tint
		var target: float = r["target"]
		var dx := target - s.position.x
		if absf(dx) > 1.5:
			s.position.x += signf(dx) * minf(absf(dx), SPEED * delta)
			s.flip_h = dx < 0.0
			s.rotation = 0.0
			r["clock"] = float(r["clock"]) + delta
			if float(r["clock"]) >= FRAME_TIME:
				r["clock"] = 0.0
				r["frame"] = (int(r["frame"]) + 1) % _frames.size()
				s.texture = _frames[int(r["frame"])]
		elif not _leaving:
			# at the front: grappling, shoving, mandibles locked on a leg
			s.rotation = sin(Time.get_ticks_msec() * 0.012 + float(r["frame"])) * 0.25
			s.position.x += sin(Time.get_ticks_msec() * 0.008 + float(r["frame"]) * 2.0) * 6.0 * delta
			if _rng.randf() < delta * 0.15:
				r["target"] = _front_spot(border_x < _width * 0.5)
		if _leaving and s.position.x > -30.0 and s.position.x < _width + 30.0:
			gone = false
		elif not _leaving:
			gone = false
	if gone:
		for r in _rivals:
			(r["sprite"] as Sprite2D).queue_free()
		_rivals.clear()
		active = false
		border_x = NAN
		ended.emit()
