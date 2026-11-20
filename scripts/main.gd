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
const SaveGame := preload("res://scripts/save_game.gd")
const FoodClusterScript := preload("res://scripts/food_cluster.gd")
const FoodDockScript := preload("res://scripts/food_dock.gd")
const MAX_FOOD_DROPS := 6
const WeatherScript := preload("res://scripts/weather.gd")
const BirdScript := preload("res://scripts/bird_event.gd")
const AUTOSAVE_INTERVAL := 30.0
const MIN_AWAY := 60.0  # shorter absences are not worth a catch-up message

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
var _autosave_clock := AUTOSAVE_INTERVAL
var weather: WeatherScript
var bird: BirdScript
var _food_layer: Node2D
var _dock: FoodDockScript
var _observer: ObserverScript

@onready var _surface: SurfaceLayerScript = $SurfaceLayer
@onready var _subterranean: SubterraneanLayerScript = $SubterraneanLayer
@onready var _ants: Node2D = $Ants
@onready var _selector: SurfaceSelectorScript = $UI/SurfaceSelector
@onready var _title: Label = $UI/ColonyTitle


func _ready() -> void:
	profile = ColonyProfile.load_or_create()
	var saved := {} if profile.is_preview else SaveGame.read(profile.seed_value)
	_subterranean.setup(profile, VIEW_SIZE, GROUND_Y, SOIL_TOP)
	_surface.setup(VIEW_SIZE, GROUND_Y, SOIL_TOP, _subterranean.entrance_xs, profile.seed_value, _load_preset())
	var range_workers: Array = profile.species["workers"]
	colony = ColonyScript.new()
	colony.name = "Colony"
	add_child(colony)
	colony.setup(_subterranean, profile.species, profile.seed_value, int(range_workers[1] * 1.5),
			saved.get("colony", {}))
	colony.worker_emerged.connect(_on_worker_emerged)
	_build_ambiance()
	var away := ""
	if saved.has("ants"):
		_restore_ants(saved)
		_food_restore(saved)
		away = _catch_up(saved)
	else:
		_spawn_colony()

	_selector.setup(_surface.preset_names(), _surface.current_preset)
	_selector.preview_requested.connect(_surface.show_preset)
	_selector.preset_locked.connect(_save_preset)
	_show_title(away)


func _process(delta: float) -> void:
	if colony != null:
		colony.population = _worker_count()
	_autosave_clock -= delta
	if _autosave_clock <= 0.0:
		_autosave_clock = AUTOSAVE_INTERVAL
		save_colony()
	if _ambience != null and _day_night != null:
		_ambience.night_level = 1.0 - _day_night.daylight
	if weather != null:
		colony.raining = weather.raining
		_day_night.overcast = weather.intensity
		_ambience.rain_level = weather.intensity
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
	_build_food_dock(observer)

	weather = WeatherScript.new()
	weather.name = "Weather"
	add_child(weather)
	move_child(weather, _day_night.get_index() + 1)  # rain falls in front of the sky, behind the ants
	weather.setup(GROUND_Y, VIEW_SIZE.x, profile.seed_value)

	bird = BirdScript.new()
	bird.name = "Bird"
	add_child(bird)
	move_child(bird, observer.get_index())  # above the ants it hunts
	bird.setup(_ants, colony, _day_night, GROUND_Y, VIEW_SIZE.x, profile.seed_value)
	observer.bird = bird

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


func _show_title(away: String = "") -> void:
	_title.text = "%s colony  ·  %s soil" % [profile.species["name"], profile.soil["name"]]
	if away != "":
		_title.text += "\n" + away
	_title.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_title, "modulate:a", 1.0, 1.2)
	tween.tween_interval(6.0 if away != "" else 4.0)
	tween.tween_property(_title, "modulate:a", 0.0, 1.5)


# ---------------------------------------------------------------------------
# Saving and restoring
# ---------------------------------------------------------------------------

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			save_colony()


func save_colony() -> void:
	if profile == null or profile.is_preview or colony == null:
		return
	var ants := []
	for ant in _ants.get_children():
		if not ant.is_queued_for_deletion():
			ants.append(ant.to_save())
	SaveGame.write({"seed": profile.seed_value, "colony": colony.to_save(), "ants": ants,
			"time_of_day": _day_night.time_of_day, "spawned": _spawned, "food_drops": _food_save()})


func _restore_ants(saved: Dictionary) -> void:
	_spawn_rng.seed = profile.seed_value + 99 + int(saved.get("spawned", 0))
	_spawned = int(saved.get("spawned", 0))
	_day_night.time_of_day = float(saved.get("time_of_day", _day_night.time_of_day))
	for entry: Dictionary in saved["ants"]:
		var chamber := int(entry["chamber"])
		if not _subterranean.chambers.has(chamber):
			chamber = _subterranean.queen_chamber()
		var ant := _spawn_ant(entry["caste"], int(entry["role"]), chamber, float(entry["age"]),
				Vector2(float(entry["x"]), 0.0))
		ant.restore_extras(float(entry.get("callow", 0.0)), bool(entry.get("departing", false)))


## Plays out the time the app was closed. Returns a short "while you were away" line.
func _catch_up(saved: Dictionary) -> String:
	var away := Time.get_unix_time_from_system() - float(saved.get("saved_at", 0.0))
	if away < MIN_AWAY:
		return ""
	var simulated := minf(away, ColonyScript.MAX_CATCH_UP)
	var carers := 0
	for ant in _ants.get_children():
		ant.age += simulated
		if ant.role == AntScript.Role.NURSE:
			carers += 1
	var report := colony.fast_forward(simulated, maxi(carers, 3))
	var emerged := 0
	var full := false
	for e: Dictionary in report["emerged"]:
		if _worker_count() >= colony.max_workers:
			full = true  # the colony was full; older foragers left to make room
			continue
		var caste: Dictionary = profile.pick_caste(_spawn_rng)
		var role := AntScript.Role.GUARD if float(caste["head"]) >= 1.5 else AntScript.Role.NURSE
		var ant := _spawn_ant(caste, role, int(e["chamber"]), float(e["age"]))
		if float(e["age"]) < AntScript.CALLOW_TIME:
			ant.make_callow()
		emerged += 1
	_day_night.time_of_day = fmod(_day_night.time_of_day + simulated / DayNightScript.CYCLE, 1.0)
	var parts: Array[String] = []
	if int(report["laid"]) > 0:
		parts.append("%d eggs laid" % int(report["laid"]))
	var raised: int = (report["emerged"] as Array).size()
	if raised > 0:
		parts.append("%d new workers" % raised)
	if full:
		parts.append("the colony is at full size")
	if parts.is_empty():
		parts.append("the colony rested")
	return "While you were away (%s): %s" % [_duration_text(away), ",  ".join(parts)]


static func _duration_text(seconds: float) -> String:
	var minutes := int(seconds / 60.0)
	if minutes < 60:
		return "%d min" % minutes
	if minutes < 60 * 48:
		return "%d h %d min" % [minutes / 60, minutes % 60]
	return "%d days" % (minutes / 1440)


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


# ---------------------------------------------------------------------------
# Food the player drops on the surface
# ---------------------------------------------------------------------------

func _build_food_dock(observer: ObserverScript) -> void:
	_observer = observer
	_food_layer = Node2D.new()
	_food_layer.name = "FoodDrops"
	add_child(_food_layer)
	move_child(_food_layer, _ants.get_index())  # food sits under the ants

	_dock = FoodDockScript.new()
	_dock.name = "FoodDock"
	_dock.theme = _selector.theme
	_dock.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dock.offset_bottom = -12.0
	$UI.add_child(_dock)
	_dock.dropped.connect(_on_food_dropped)
	observer.input_blocked = _dock.owns_pointer
	_selector.picker_toggled.connect(func(open: bool):
		_dock.visible = not open)  # the surface picker uses the same spot


func _on_food_dropped(kind: String, screen_pos: Vector2) -> void:
	var world := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	# food only lands on the surface (a little leeway into the topsoil for fat fingers)
	if world.y > SOIL_TOP + 24.0 or world.x < SURFACE_MARGIN or world.x > VIEW_SIZE.x - SURFACE_MARGIN:
		return
	_drop_food(kind, world.x)


func _drop_food(kind: String, x: float, crumbs_left: int = -1) -> void:
	var drops := _food_layer.get_children()
	if drops.size() >= MAX_FOOD_DROPS:
		drops[0].queue_free()  # the oldest pile is cleared away
	var cluster := FoodClusterScript.new()
	_food_layer.add_child(cluster)
	cluster.setup(kind, Vector2(x, GROUND_Y), _spawn_rng.randi(), crumbs_left)
	colony.add_cluster(cluster)


func _food_save() -> Array:
	var drops := []
	for c in _food_layer.get_children():
		if not c.is_queued_for_deletion() and not c.is_empty():
			drops.append({"kind": c.kind, "x": c.position.x, "crumbs": c.crumbs})
	return drops


func _food_restore(saved: Dictionary) -> void:
	for d: Dictionary in saved.get("food_drops", []):
		_drop_food(d["kind"], float(d["x"]), int(d["crumbs"]))
