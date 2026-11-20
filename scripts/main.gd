extends Node2D
## Root coordinator: loads this player's colony (species, soil, nest seed), builds the
## dual-layer view, spawns the workers and connects the surface picker.

const AntScene := preload("res://scenes/Ant.tscn")
const AntScript := preload("res://scripts/ant.gd")
const ColonyProfile := preload("res://scripts/colony_profile.gd")
const SurfaceLayerScript := preload("res://scripts/surface_layer.gd")
const SubterraneanLayerScript := preload("res://scripts/subterranean_layer.gd")
const SurfaceSelectorScript := preload("res://scripts/surface_selector.gd")
const ColonyScript := preload("res://scripts/colony.gd")
const ObserverScript := preload("res://scripts/observer.gd")
const DayNightScript := preload("res://scripts/day_night.gd")
const TrailLayerScript := preload("res://scripts/trail_layer.gd")
const AmbienceScript := preload("res://scripts/ambience.gd")
const PixelArt := preload("res://scripts/pixel_art_factory.gd")
const GREET_CHECK := 0.3  # seconds between checks for ants meeting head-on

const VIEW_SIZE := Vector2(1280, 720)
const GROUND_Y := 120.0  # where surface ants put their feet
const SOIL_TOP := 128.0  # first screen row of the underground cross-section
const SURFACE_MARGIN := 48.0
const SETTINGS_PATH := "user://simantics.cfg"

var profile: RefCounted
var colony: ColonyScript

var _spawn_rng := RandomNumberGenerator.new()
var _spawned := 0
var _trail: TrailLayerScript
var _day_night: DayNightScript
var _ambience: AmbienceScript
var _greet_clock := 0.0

@onready var _surface: SurfaceLayerScript = $SurfaceLayer
@onready var _subterranean: SubterraneanLayerScript = $SubterraneanLayer
@onready var _ants: Node2D = $Ants
@onready var _selector: SurfaceSelectorScript = $UI/SurfaceSelector
@onready var _title: Label = $UI/ColonyTitle


func _ready() -> void:
	profile = ColonyProfile.load_or_create()
	_subterranean.setup(profile, VIEW_SIZE, GROUND_Y, SOIL_TOP)
	_surface.setup(VIEW_SIZE, GROUND_Y, SOIL_TOP, _subterranean.entrance_xs, profile.seed_value, _load_preset())
	var range_workers: Array = profile.species["workers"]
	colony = ColonyScript.new()
	colony.name = "Colony"
	add_child(colony)
	colony.setup(_subterranean, profile.species, profile.seed_value, int(range_workers[1] * 1.5))
	colony.worker_emerged.connect(_on_worker_emerged)
	_build_ambiance()
	_spawn_colony()

	_selector.setup(_surface.preset_names(), _surface.current_preset)
	_selector.preview_requested.connect(_surface.show_preset)
	_selector.preset_locked.connect(_save_preset)
	_show_title()


func _process(delta: float) -> void:
	if colony != null:
		colony.population = _worker_count()
	if _ambience != null and _day_night != null:
		_ambience.night_level = 1.0 - _day_night.daylight
	_greet_clock -= delta
	if _greet_clock <= 0.0:
		_greet_clock = GREET_CHECK
		_check_greetings()


## Ants that meet head-on pause to touch antennae, as real nestmates do.
func _check_greetings() -> void:
	var ants := _ants.get_children()
	for i in ants.size():
		var a: Node2D = ants[i]
		for j in range(i + 1, ants.size()):
			var b: Node2D = ants[j]
			if a.global_position.distance_squared_to(b.global_position) < 81.0 and _spawn_rng.randf() < 0.5:
				if a.greet(b.global_position):
					b.greet(a.global_position)
				break


## Camera, inspect label, day/night, scent trails, lamp vignette, sound and its mute button.
func _build_ambiance() -> void:
	_day_night = DayNightScript.new()
	_day_night.name = "DayNight"
	add_child(_day_night)
	move_child(_day_night, _surface.get_index() + 1)
	_day_night.setup(_surface, colony, GROUND_Y - 8.0, VIEW_SIZE.x, profile.seed_value)

	_trail = TrailLayerScript.new()
	_trail.name = "Trails"
	add_child(_trail)
	move_child(_trail, _ants.get_index())  # just under the ants

	var camera := Camera2D.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()

	var label := Label.new()
	label.name = "InspectLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.96, 0.9, 0.76))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.1, 0.07, 0.04, 0.82)
	panel.border_color = Color("#b07c48")
	panel.set_border_width_all(1)
	panel.set_content_margin_all(6)
	label.add_theme_stylebox_override("normal", panel)
	$UI.add_child(label)

	var observer := ObserverScript.new()
	observer.name = "Observer"
	add_child(observer)
	move_child(observer, _ants.get_index() + 1)
	observer.setup(camera, _ants, _subterranean, label, VIEW_SIZE)

	# warm desk-lamp falloff: the middle of the farm glows, the corners sink into shadow
	var shade := CanvasLayer.new()
	shade.layer = 5
	add_child(shade)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0.05, 0.02, 0.0, 0.42))
	gradient.add_point(0.6, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.48)
	tex.fill_to = Vector2(1.08, 1.08)
	tex.width = 256
	tex.height = 144
	var vignette := TextureRect.new()
	vignette.texture = tex
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shade.add_child(vignette)

	_ambience = AmbienceScript.new()
	_ambience.name = "Ambience"
	_ambience.muted = _load_setting("audio", "muted", false)
	add_child(_ambience)
	var mute := Button.new()
	mute.name = "MuteButton"
	mute.focus_mode = Control.FOCUS_NONE
	mute.expand_icon = true
	mute.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mute.tooltip_text = "Sound"
	mute.icon = PixelArt.speaker_icon(_ambience.muted)
	mute.theme = _selector.theme
	mute.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mute.offset_left = -120.0
	mute.offset_top = -64.0
	mute.offset_right = -72.0
	mute.offset_bottom = -12.0
	mute.pressed.connect(func():
		_ambience.muted = not _ambience.muted
		mute.icon = PixelArt.speaker_icon(_ambience.muted)
		_save_setting("audio", "muted", _ambience.muted))
	$UI.add_child(mute)


func _worker_count() -> int:
	var n := 0
	for ant in _ants.get_children():
		if ant.role != AntScript.Role.ALATE and not ant.is_departing():
			n += 1
	return n


func _spawn_colony() -> void:
	_spawn_rng.seed = profile.seed_value + 99
	for i in profile.worker_count:
		var caste: Dictionary = profile.pick_caste(_spawn_rng)
		var role := _role_for(caste, _spawn_rng)
		var homes := _homes_for(role)
		_spawn_ant(caste, role, homes[_spawn_rng.randi() % homes.size()], _age_for(role))
	# Winged reproductives waiting for their nuptial flight: virgin queens and smaller males.
	for chamber in _subterranean.chambers_with_role("alates"):
		for i in _spawn_rng.randi_range(2, 3):
			_spawn_ant({"name": "alate queen", "size": 1.0, "head": 1.0, "queen": true, "wings": true},
					AntScript.Role.ALATE, chamber, 0.0)
		for i in _spawn_rng.randi_range(3, 4):
			_spawn_ant({"name": "male", "size": 0.8, "head": 0.8, "wings": true},
					AntScript.Role.ALATE, chamber, 0.0)


func _spawn_ant(caste: Dictionary, role: AntScript.Role, start_node: int, start_age: float,
		start_pos: Vector2 = Vector2.INF) -> Node2D:
	var ant := AntScene.instantiate()
	_ants.add_child(ant)
	ant.setup(_subterranean, colony, profile.species, caste, role, start_node, GROUND_Y,
			Vector2(SURFACE_MARGIN, VIEW_SIZE.x - SURFACE_MARGIN), profile.seed_value * 31 + _spawned,
			start_age, start_pos)
	ant.set_trail_layer(_trail)
	_spawned += 1
	return ant


## Starting ages that match each job, so the colony has a natural age spread.
func _age_for(role: AntScript.Role) -> float:
	match role:
		AntScript.Role.NURSE:
			return _spawn_rng.randf_range(0.0, AntScript.NURSE_UNTIL * 0.9)
		AntScript.Role.WORKER:
			return _spawn_rng.randf_range(AntScript.NURSE_UNTIL, AntScript.WORKER_UNTIL * 0.95)
	return _spawn_rng.randf_range(AntScript.WORKER_UNTIL, AntScript.WORKER_UNTIL * 2.0)


## A pupa has emerged: a pale callow worker joins the nurses. Once the colony is full,
## the oldest forager leaves on its next trip outside and does not return.
func _on_worker_emerged(pos: Vector2, chamber: int) -> void:
	var caste: Dictionary = profile.pick_caste(_spawn_rng)
	var role := AntScript.Role.GUARD if float(caste["head"]) >= 1.5 else AntScript.Role.NURSE
	var ant := _spawn_ant(caste, role, chamber, 0.0, pos)
	ant.make_callow()
	if _worker_count() > colony.max_workers:
		var oldest: Node2D = null
		for other in _ants.get_children():
			if other.role == AntScript.Role.FORAGER and not other.is_departing() \
					and (oldest == null or other.age > oldest.age):
				oldest = other
		if oldest != null:
			oldest.depart()


## Big-headed majors and soldiers guard; small minima tend brood and fungus;
## the rest split between nest work and foraging.
func _role_for(caste: Dictionary, rng: RandomNumberGenerator) -> AntScript.Role:
	if float(caste["head"]) >= 1.5:
		return AntScript.Role.GUARD
	if float(caste["size"]) <= 0.75 and profile.species["food"] == "fungus":
		return AntScript.Role.NURSE
	var roll := rng.randf()
	if roll < 0.35:
		return AntScript.Role.NURSE
	if roll < 0.65:
		return AntScript.Role.WORKER
	return AntScript.Role.FORAGER


func _homes_for(role: AntScript.Role) -> Array[int]:
	var wanted: Array[String] = ["rest"]
	match role:
		AntScript.Role.NURSE:
			wanted = ["nursery", "queen", "fungus"]
		AntScript.Role.WORKER:
			wanted = ["food", "refuse", "rest"]
	var homes: Array[int] = []
	for r in wanted:
		homes.append_array(_subterranean.chambers_with_role(r))
	if homes.is_empty():
		homes = _subterranean.chambers_with_role("queen")
	return homes


func _show_title() -> void:
	_title.text = "%s colony  ·  %s soil" % [profile.species["name"], profile.soil["name"]]
	_title.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_title, "modulate:a", 1.0, 1.2)
	tween.tween_interval(4.0)
	tween.tween_property(_title, "modulate:a", 0.0, 1.5)


func _load_preset() -> int:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return 0
	return int(config.get_value("surface", "preset", 0))


func _save_preset(index: int) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep the colony seed and other settings
	config.set_value("surface", "preset", index)
	config.save(SETTINGS_PATH)


func _load_setting(section: String, key: String, default: Variant) -> Variant:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return default
	return config.get_value(section, key, default)


func _save_setting(section: String, key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep the colony seed and other settings
	config.set_value(section, key, value)
	config.save(SETTINGS_PATH)
