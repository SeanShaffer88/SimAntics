extends Node2D
## Root coordinator: loads this player's colony (species, soil, nest seed), builds the
## dual-layer view, spawns the workers and connects the surface picker.

const AntScene := preload("res://scenes/Ant.tscn")
const AntScript := preload("res://scripts/ant.gd")
const ColonyProfile := preload("res://scripts/colony_profile.gd")
const SurfaceLayerScript := preload("res://scripts/surface_layer.gd")
const SubterraneanLayerScript := preload("res://scripts/subterranean_layer.gd")
const NestGenerator := preload("res://scripts/nest_generator.gd")
const UiArt := preload("res://scripts/ui_art.gd")
const SurfaceSelectorScript := preload("res://scripts/surface_selector.gd")
const ColonyScript := preload("res://scripts/colony.gd")
const ObserverScript := preload("res://scripts/observer.gd")
const DayNightScript := preload("res://scripts/day_night.gd")
const TrailLayerScript := preload("res://scripts/trail_layer.gd")
const AmbienceScript := preload("res://scripts/ambience.gd")
const PixelArt := preload("res://scripts/pixel_art_factory.gd")
const ColonyArt := preload("res://scripts/colony_art.gd")
const DustLayerScript := preload("res://scripts/dust_layer.gd")
const GREET_CHECK := 0.3  # seconds between checks for ants meeting head-on
const SaveGame := preload("res://scripts/save_game.gd")
const FoodClusterScript := preload("res://scripts/food_cluster.gd")
const FoodDockScript := preload("res://scripts/food_dock.gd")
const MAX_FOOD_DROPS := 6
const WeatherScript := preload("res://scripts/weather.gd")
const SpoilHeapScript := preload("res://scripts/spoil_heap.gd")
const FOUNDING_WORKERS := 4
const InfoPanelScript := preload("res://scripts/info_panel.gd")
const FieldNotes := preload("res://scripts/field_notes.gd")
const HISTORY_INTERVAL := 60.0  # seconds between population samples for the info graph
const HISTORY_LENGTH := 180
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
var _dust: Node2D
var _day_night: DayNightScript
var _ambience: AmbienceScript
var _greet_clock := 0.0
var _autosave_clock := AUTOSAVE_INTERVAL
var _spoil: SpoilHeapScript
var notes := FieldNotes.new()
var _founded_at := 0.0
var _away_days := 0  # whole days that passed while the app was closed
var _history: Array = []
var _history_clock := 5.0
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
	if saved.has("dig") and int(saved["dig"].get("nest", 1)) != NestGenerator.VERSION:
		saved = _relay_nest(saved)
	# A new colony starts from a founding queen and digs its nest out over time.
	# Saves from before digging existed, and the --mature preview, open the whole nest.
	var mature := OS.get_cmdline_user_args().has("--mature") or (saved.has("ants") and not saved.has("dig"))
	var founding := saved.is_empty() and not mature
	_subterranean.setup(profile, VIEW_SIZE, GROUND_Y, SOIL_TOP, saved.get("dig", {}), mature)
	# the surface art shows the main entrance; others appear (via the spoil heap) once dug
	var drawn_entrances: Array[float] = [_subterranean.entrance_xs[0]]
	if mature:
		drawn_entrances = _subterranean.entrance_xs
	_surface.setup(VIEW_SIZE, GROUND_Y, SOIL_TOP, drawn_entrances, profile.seed_value, _load_preset())
	var range_workers: Array = profile.species["workers"]
	colony = ColonyScript.new()
	colony.name = "Colony"
	add_child(colony)
	colony.setup(_subterranean, profile.species, profile.seed_value, int(range_workers[1] * 1.5),
			saved.get("colony", {}), founding)
	colony.set_soil_color(profile.soil["strata"][1])
	colony.ground_y = GROUND_Y
	colony.nest_bottom = VIEW_SIZE.y - NestGenerator.BOTTOM_MARGIN
	colony.worker_emerged.connect(_on_worker_emerged)
	_build_ambiance()
	_spoil = SpoilHeapScript.new()
	_spoil.name = "SpoilHeap"
	add_child(_spoil)
	move_child(_spoil, _ants.get_index())  # on the surface, under the ants
	_spoil.setup(GROUND_Y, profile.soil["strata"][1], profile.seed_value)
	_spoil.restore(saved.get("spoil", {}))
	colony.soil_dumped.connect(_spoil.add)
	colony.midden_dumped.connect(_spoil.add_chaff)
	colony.corpse_dumped.connect(_on_corpse_dumped)
	_subterranean.entrance_opened.connect(func(x: float):
		_spoil.add_hole(x)
		for i in 10:
			_spoil.add(x + _spawn_rng.randf_range(-14.0, 14.0)))
	if not mature:  # secondary openings dug in earlier sessions
		for i in range(1, _subterranean.entrances.size()):
			if _subterranean.is_dug(_subterranean.entrances[i]):
				_spoil.add_hole(_subterranean.entrance_xs[i])
	var away := ""
	if saved.has("ants"):
		_restore_ants(saved)
		_food_restore(saved)
		away = _catch_up(saved)
	elif founding:
		_spawn_founders()
	else:
		_spawn_colony()

	_founded_at = float(saved.get("founded_at", Time.get_unix_time_from_system()))
	_history = saved.get("history", [])
	notes.restore(saved.get("notes", {}))
	saved["day"] = int(saved.get("day", 0)) + _away_days
	if profile.species["id"] == "garden":
		_build_aphids()
	elif profile.species["id"] == "pavement":
		_build_skirmish()
	wetness = float(saved.get("wetness", 0.0))
	_build_seasons(saved)
	_hook_field_notes(founding)
	if away != "":
		notes.note(away)
	_build_info_panel()

	_selector.setup(_surface.preset_names(), _surface.current_preset)
	_selector.preview_requested.connect(_surface.show_preset)
	_selector.preset_locked.connect(_save_preset)
	_start_tips()
	_apply_safe_area()
	_show_title(away)


## A save dug under an older nest layout: keep the colony, its ants and brood, but move
## them into the new layout, opened in full (chamber-specific stores start empty).
func _relay_nest(saved: Dictionary) -> Dictionary:
	saved.erase("dig")  # with ants but no dig state the whole nest opens (see mature)
	saved.erase("spoil")
	var col: Dictionary = saved.get("colony", {})
	col["food"] = {}
	col["waste"] = []
	for entry: Dictionary in col.get("brood", []):
		entry["chamber"] = -1
	return saved


func _process(delta: float) -> void:
	if colony != null:
		colony.population = _worker_count()
	_history_clock -= delta
	if _history_clock <= 0.0:
		_history_clock = HISTORY_INTERVAL
		_history.append(_worker_count())
		if _history.size() > HISTORY_LENGTH:
			_history.pop_front()
		_note_population(_worker_count())
	_autosave_clock -= delta
	if _autosave_clock <= 0.0:
		_autosave_clock = AUTOSAVE_INTERVAL
		save_colony()
	if _ambience != null and _day_night != null:
		_ambience.night_level = 1.0 - _day_night.daylight
	if weather != null:
		colony.raining = weather.raining
		_day_night.overcast = weather.intensity
		_ambience.rain_level = 0.0 if weather.snow else weather.intensity  # snow falls silently
	_update_flights(delta)
	_update_natural_food(delta)
	_update_skirmish(delta)
	_update_expansion(delta)
	_update_wetness(delta)
	_update_spider(delta)
	_update_climate(delta)
	_update_plugs(delta)
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
				# social immunity: a nestmate carrying spores is groomed clean on sight
				var dirty: Node2D = a if a.can_be_cleaned() else (b if b.can_be_cleaned() else null)
				var helper: Node2D = (b if dirty == a else a) if dirty != null else null
				if dirty != null and helper.can_allogroom() and helper.spores <= 0.0 and _spawn_rng.randf() < 0.8:
					var span := _spawn_rng.randf_range(4.0, 7.0)
					helper.allogroom(dirty.global_position, true, span, true)
					dirty.allogroom(helper.global_position, false, span)
				elif a.can_allogroom() and b.can_allogroom() and _spawn_rng.randf() < 0.3:
					var dur := _spawn_rng.randf_range(3.0, 6.0)
					a.allogroom(b.global_position, true, dur)
					b.allogroom(a.global_position, false, dur)
				elif a.greet(b.global_position):
					b.greet(a.global_position)
					if a.has_crop() != b.has_crop():
						_share_food(a, b)
				break


## Trophallaxis: the ant with a full crop passes a droplet of food mouth to mouth.
func _share_food(a: Node2D, b: Node2D) -> void:
	var receiver := b if a.has_crop() else a
	receiver.fill_crop()
	var drop := Sprite2D.new()
	drop.texture = ColonyArt.food_crumb("nectar", 0)
	drop.position = ((a.global_position + b.global_position) * 0.5).round() + Vector2(0.0, -1.0)
	drop.z_index = 2
	add_child(drop)
	var fade := drop.create_tween()
	fade.tween_property(drop, "scale", Vector2.ONE * 0.4, 0.9)
	fade.parallel().tween_property(drop, "modulate:a", 0.0, 0.9)
	fade.tween_callback(drop.queue_free)


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

	_dust = DustLayerScript.new()
	_dust.name = "Dust"
	add_child(_dust)
	move_child(_dust, _ants.get_index() + 1)  # over the ants that kick it up
	_dust.setup(profile.soil["strata"][1], profile.seed_value)

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
	observer.colony = colony
	observer.ant_inspected.connect(_on_ant_inspected)
	_build_food_dock(observer)
	observer.food_layer = _food_layer

	weather = WeatherScript.new()
	weather.name = "Weather"
	add_child(weather)
	move_child(weather, _day_night.get_index() + 1)  # rain falls in front of the sky, behind the ants
	weather.setup(GROUND_Y, VIEW_SIZE.x, profile.seed_value)
	weather.rain_changed.connect(func(raining: bool):
		if not raining:  # alates swarm on the bright, still day after rain
			get_tree().create_timer(12.0).timeout.connect(_maybe_nuptial_flight)
			if not weather.snow:
				water.scatter(_spawn_rng.randi_range(6, 10), _subterranean.entrance_xs))

	water = WaterDropsScript.new()
	water.name = "WaterDrops"
	add_child(water)
	move_child(water, _ants.get_index())
	water.setup(GROUND_Y, VIEW_SIZE.x, profile.seed_value)
	colony.water = water
	_build_spider()

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
	mute.icon = UiArt.speaker_icon(_ambience.muted)
	mute.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mute.theme = _selector.theme
	mute.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mute.offset_left = -152.0  # buttons are 68 px: big enough to tap comfortably
	mute.offset_top = -80.0
	mute.offset_right = -84.0
	mute.offset_bottom = -12.0
	mute.pressed.connect(func():
		_ambience.muted = not _ambience.muted
		mute.icon = UiArt.speaker_icon(_ambience.muted)
		_save_setting("audio", "muted", _ambience.muted))
	$UI.add_child(mute)


func _worker_count() -> int:
	var n := 0
	for ant in _ants.get_children():
		if ant.role != AntScript.Role.ALATE and not ant.is_departing():
			n += 1
	return n


## A new colony: the founding queen's first few workers (small "nanitics" in real
## colonies), all in the founding chamber. Two tend the brood, two start digging.
func _spawn_founders() -> void:
	_spawn_rng.seed = profile.seed_value + 99
	var home := _subterranean.queen_chamber()
	for i in FOUNDING_WORKERS:
		var caste: Dictionary = profile.species["castes"][0]  # the smallest caste
		var role := AntScript.Role.NURSE if i < 2 else AntScript.Role.WORKER
		var age := _spawn_rng.randf_range(30.0, 150.0) if role == AntScript.Role.NURSE \
				else _spawn_rng.randf_range(AntScript.NURSE_UNTIL, AntScript.NURSE_UNTIL + 120.0)
		_spawn_ant(caste, role, home, age)


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
	ant.set_dust_layer(_dust)
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
	if _try_raise_alate():
		return  # this one emerged with wings
	var caste := _caste_for_colony()
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


## Which caste a new worker becomes. A founding queen can only raise small "nanitic"
## workers on her body reserves; big majors and soldiers take a lot of protein as
## larvae, so they only appear once the colony is established and well fed.
func _caste_for_colony() -> Dictionary:
	var castes: Array = profile.species["castes"]
	var workers := _worker_count()
	if workers < 10:
		var smallest: Dictionary = castes[0]
		for c: Dictionary in castes:
			if float(c["size"]) < float(smallest["size"]):
				smallest = c
		var nanitic := smallest.duplicate()
		nanitic["name"] = "nanitic"
		nanitic["size"] = snappedf(float(smallest["size"]) * 0.82, 0.01)
		nanitic["head"] = minf(float(smallest["head"]), 1.1)
		return nanitic
	var caste: Dictionary = profile.pick_caste(_spawn_rng)
	if float(caste["head"]) >= 1.5 and (workers < 20 or colony.store_counts().y < 4):
		for c: Dictionary in castes:  # not enough protein for a big-headed larva: a minor instead
			if float(c["head"]) < 1.5:
				return c
	return caste


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
			"time_of_day": _day_night.time_of_day, "spawned": _spawned, "food_drops": _food_save(),
			"dig": _subterranean.dig_save(), "spoil": _spoil.to_save(),
			"founded_at": _founded_at, "history": _history, "notes": notes.to_save(), "day": seasons.day,
			"wetness": wetness})


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
		ant.lifespan = float(entry.get("lifespan", ant.lifespan))
		ant.restore_health(float(entry.get("spores", 0.0)), bool(entry.get("sick", false)))


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
	var diggers := 0
	for ant in _ants.get_children():
		if ant.role == AntScript.Role.WORKER:
			diggers += 1
	var dug := colony.fast_forward_digging(simulated, diggers)
	for i in mini(dug, 400):  # their pellets are on the spoil heap
		_spoil.add(_subterranean.entrance_xs[0] + _spawn_rng.randf_range(-46.0, 46.0))
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
	_away_days = int(_day_night.time_of_day + simulated / DayNightScript.CYCLE)  # midnights passed
	_day_night.time_of_day = fmod(_day_night.time_of_day + simulated / DayNightScript.CYCLE, 1.0)
	var parts: Array[String] = []
	if int(report["laid"]) > 0:
		parts.append("%d eggs laid" % int(report["laid"]))
	var raised: int = (report["emerged"] as Array).size()
	if raised > 0:
		parts.append("%d new workers" % raised)
	if dug > 0:
		parts.append("the nest grew (%d digging trips)" % dug)
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
	_dock.tapped.connect(_on_food_tapped)
	observer.input_blocked = _dock.owns_pointer
	_selector.picker_toggled.connect(func(open: bool):
		_dock.visible = not open)  # the surface picker uses the same spot


## A tap on the dock drops that food somewhere on the surface, clear of the nest openings.
func _on_food_tapped(kind: String) -> void:
	var x := VIEW_SIZE.x * 0.5
	for attempt in 12:
		x = _spawn_rng.randf_range(SURFACE_MARGIN + 20.0, VIEW_SIZE.x - SURFACE_MARGIN - 20.0)
		var clear := true
		for ex in _subterranean.entrance_xs:
			if absf(x - ex) < 40.0:
				clear = false
		for c in _food_layer.get_children():
			if absf(x - c.position.x) < 36.0:
				clear = false
		if not is_nan(colony.aphid_x) and absf(x - colony.aphid_x) < 30.0:
			clear = false
		if clear:
			break
	_drop_food(kind, x, -1, true)


func _drop_food(kind: String, x: float, crumbs_left: int = -1, animate: bool = false,
		natural: bool = false) -> void:
	var drops := _food_layer.get_children()
	if drops.size() >= MAX_FOOD_DROPS:
		drops[0].queue_free()  # the oldest pile is cleared away
	var cluster := FoodClusterScript.new()
	cluster.set_meta("natural", natural)
	_food_layer.add_child(cluster)
	cluster.setup(kind, Vector2(x, GROUND_Y), _spawn_rng.randi(), crumbs_left)
	colony.add_cluster(cluster)
	if animate:  # it falls in from above and settles with a little bounce
		cluster.position.y = GROUND_Y - 70.0
		var fall := cluster.create_tween()
		fall.tween_property(cluster, "position:y", GROUND_Y, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _food_save() -> Array:
	var drops := []
	for c in _food_layer.get_children():
		if not c.is_queued_for_deletion() and not c.is_empty():
			drops.append({"kind": c.kind, "x": c.position.x, "crumbs": c.crumbs,
					"natural": c.get_meta("natural", false)})
	return drops


func _food_restore(saved: Dictionary) -> void:
	for d: Dictionary in saved.get("food_drops", []):
		_drop_food(d["kind"], float(d["x"]), int(d["crumbs"]), false, bool(d.get("natural", false)))


# Natural food: what the surroundings provide for each species, and how much.
const NATURAL_FOOD := {"seeds": ["seeds", 12], "prey": ["insects", 10], "fungus": ["leaves", 14]}
const NATURAL_INTERVAL := Vector2(60.0, 150.0)
const MAX_NATURAL := 2
const NATURAL_NOTES := {"seeds": "A seed head dropped its seeds near the nest.",
		"insects": "A few dead insects lay near the nest.", "leaves": "Fresh leaves lay within reach of the nest."}

var _natural_clock := 20.0


## Every so often the surroundings provide a little food, so the colony forages on
## its own: fallen seeds, dead insects, or leaves for leafcutters to cut.
func _update_natural_food(delta: float) -> void:
	if profile == null:
		return
	_natural_clock -= delta
	if _natural_clock > 0.0:
		return
	_natural_clock = _spawn_rng.randf_range(NATURAL_INTERVAL.x, NATURAL_INTERVAL.y)
	if seasons != null:
		if seasons.is_winter():
			return  # nothing turns up under the snow
		if seasons.season() == SeasonsScript.AUTUMN:
			_natural_clock *= 0.6  # seeds and windfall: autumn is a time of plenty
	var natural := 0
	for c in _food_layer.get_children():
		if c.get_meta("natural", false) and not c.is_queued_for_deletion():
			natural += 1
	if natural >= MAX_NATURAL:
		return
	var spec: Array = NATURAL_FOOD.get(profile.species["food"], ["seeds", 12])
	var x := _spawn_rng.randf_range(SURFACE_MARGIN + 20.0, VIEW_SIZE.x - SURFACE_MARGIN - 20.0)
	for ex in _subterranean.entrance_xs:
		if absf(x - ex) < 40.0:
			x = clampf(x + 80.0, SURFACE_MARGIN, VIEW_SIZE.x - SURFACE_MARGIN)
	_drop_food(spec[0], x, spec[1], false, true)
	notes.note(NATURAL_NOTES.get(spec[0], "Food turned up near the nest."), "natural_" + str(spec[0]))


# ---------------------------------------------------------------------------
# Colony info panel
# ---------------------------------------------------------------------------

func _build_info_panel() -> void:
	var panel := InfoPanelScript.new()
	panel.name = "InfoPanel"
	panel.theme = _selector.theme
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = 12.0
	panel.offset_right = -12.0
	$UI.add_child(panel)
	var keep_on: bool = _load_setting("display", "keep_screen_on", true)
	var speed: float = _load_setting("display", "speed", 1.0)
	_apply_keep_on(keep_on)
	Engine.time_scale = speed
	panel.setup(_colony_stats, func() -> Array: return _history, keep_on, speed)
	panel.new_colony_requested.connect(_start_new_colony)
	panel.notes = func() -> Array: return notes.recent(3)
	panel.keep_screen_on_changed.connect(func(on: bool):
		_apply_keep_on(on)
		_save_setting("display", "keep_screen_on", on))
	panel.speed_changed.connect(func(s: float):
		Engine.time_scale = s
		_save_setting("display", "speed", s))

	var button := Button.new()
	button.name = "InfoButton"
	button.focus_mode = Control.FOCUS_NONE
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.tooltip_text = "Colony"
	button.icon = UiArt.info_icon()
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	button.theme = _selector.theme
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = -224.0
	button.offset_top = -80.0
	button.offset_right = -156.0
	button.offset_bottom = -12.0
	button.pressed.connect(panel.toggle)
	$UI.add_child(button)


## Keeps buttons and panels clear of camera notches and rounded corners on phones.
## Only the part of a cut-out that reaches into the game area (not the letterbox) counts.
func _apply_safe_area() -> void:
	if not OS.get_name() in ["Android", "iOS"]:
		return
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var scale := minf(win.x / VIEW_SIZE.x, win.y / VIEW_SIZE.y)
	var bars := (win - VIEW_SIZE * scale) * 0.5  # letterbox on each side
	var left := maxf(0.0, safe.position.x - bars.x) / scale
	var right := maxf(0.0, (win.x - safe.end.x) - bars.x) / scale
	var top := maxf(0.0, safe.position.y - bars.y) / scale
	var bottom := maxf(0.0, (win.y - safe.end.y) - bars.y) / scale
	if left + right + top + bottom < 0.5:
		return
	for node in $UI.get_children():
		var c := node as Control
		if c == null:
			continue
		if c.anchor_left == 0.0 and c.anchor_right == 1.0:  # full width: shrink inward
			c.offset_left += left
			c.offset_right -= right
		elif c.anchor_left >= 1.0:
			c.offset_left -= right
			c.offset_right -= right
		elif c.anchor_right <= 0.0:
			c.offset_left += left
			c.offset_right += left
		if c.anchor_top == 0.0 and c.anchor_bottom == 1.0:
			c.offset_top += top
			c.offset_bottom -= bottom
		elif c.anchor_top >= 1.0:
			c.offset_top -= bottom
			c.offset_bottom -= bottom
		elif c.anchor_bottom <= 0.0:
			c.offset_top += top
			c.offset_bottom += top


## An ant farm left on a desk shouldn't let the phone go to sleep (if the player agrees).
func _apply_keep_on(on: bool) -> void:
	DisplayServer.screen_set_keep_on(on)


## The figures shown in the info panel.
func _colony_stats() -> Dictionary:
	var roles := [0, 0, 0, 0]
	var alates := 0
	for ant in _ants.get_children():
		if ant.role == AntScript.Role.ALATE:
			alates += 1
		elif ant.role < 4:
			roles[ant.role] += 1
	var brood := [0, 0, 0]
	for b in colony.brood:
		brood[b.stage] += 1
	var food := 0
	for id: int in _subterranean.food_items:
		food += (_subterranean.food_items[id] as Array).size()
	var dug := 0
	for i in _subterranean.dug.size():
		dug += _subterranean.dug[i]
	var open_chambers := 0
	for id: int in _subterranean.chambers:
		if _subterranean.is_dug(id):
			open_chambers += 1
	return {
		"title": "%s colony  ·  %s soil" % [profile.species["name"], profile.soil["name"]],
		"age": "%s  ·  %s, day %d of %d" % [_duration_text(Time.get_unix_time_from_system() - _founded_at + 60.0),
				seasons.season_name(), seasons.day_of_season(), SeasonsScript.DAYS_PER_SEASON],
		"workers": _worker_count(),
		"alates": ("  ·  %d winged alates" % alates) if alates > 0 else "",
		"roles": roles,
		"brood": brood,
		"food": [food, colony.store_counts().x, colony.store_counts().y],
		"climate": [roundi(climate.surface), roundi(climate.at_depth(0.3)), roundi(climate.deep),
				"" if colony.forage_ok else "  ·  no foraging"],
		"nest": [roundi(100.0 * dug / maxi(1, _subterranean.dug.size())), open_chambers, _subterranean.chambers.size()],
		"guide": [notes.count_prefix("seen_"), _guide_total()],
	}


## Replaces this colony with a brand-new one (the player confirmed in the info panel).
func _start_new_colony() -> void:
	if not profile.is_preview:
		ColonyProfile.reset_seed()
		SaveGame.clear()
	profile = null  # nothing more is saved from the old colony
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Alates and nuptial flights
# ---------------------------------------------------------------------------

const MAX_ALATES := 8
const ALATE_SHARE := 0.25  # of new adults in a mature colony
const FLIGHT_MIN_ALATES := 3
const FLIGHT_CHECK := 300.0  # a fine day can also bring a flight without rain first

var _flight_clock := FLIGHT_CHECK


func _alate_count() -> int:
	var n := 0
	for ant in _ants.get_children():
		if ant.role == AntScript.Role.ALATE:
			n += 1
	return n


## A mature colony with an alate chamber raises some winged queens and males.
func _try_raise_alate() -> bool:
	var rooms := _subterranean.chambers_with_role("alates")
	if rooms.is_empty() or _worker_count() < colony.max_workers * 0.8 or _alate_count() >= MAX_ALATES:
		return false
	if _spawn_rng.randf() >= ALATE_SHARE:
		return false
	var queen := _spawn_rng.randf() < 0.4
	var caste := {"name": "alate queen", "size": 1.0, "head": 1.0, "queen": true, "wings": true} if queen \
			else {"name": "male", "size": 0.8, "head": 0.8, "wings": true}
	var ant := _spawn_ant(caste, AntScript.Role.ALATE, rooms[0], 0.0)
	ant.make_callow()
	notes.note("The colony began raising winged queens and males.", "first_alates")
	return true


## After rain on a bright day (or now and then on any fine day), the alates leave
## together on their mating flight to found colonies of their own.
func _maybe_nuptial_flight() -> void:
	if _day_night.daylight < 0.55 or weather.raining or colony.winter:
		return
	var alates: Array[Node] = []
	for ant in _ants.get_children():
		if ant.role == AntScript.Role.ALATE:
			alates.append(ant)
	if alates.size() < FLIGHT_MIN_ALATES:
		return
	_announce("Nuptial flight: the winged queens and males are leaving to found new colonies")
	notes.note("Nuptial flight: %d winged queens and males left to found colonies of their own." % alates.size())
	var delay := 0.0
	for ant in alates:
		delay += _spawn_rng.randf_range(0.8, 3.0)
		var ref: WeakRef = weakref(ant)  # the alate may be gone (a bird, a new colony) before its turn
		get_tree().create_timer(delay).timeout.connect(func():
			var a = ref.get_ref()
			if a != null:
				a.start_nuptial_flight())


func _update_flights(delta: float) -> void:
	_flight_clock -= delta
	if _flight_clock <= 0.0:
		_flight_clock = FLIGHT_CHECK
		var chance := 0.7 if seasons.season() == SeasonsScript.SUMMER else 0.2  # flights peak in summer
		if _alate_count() >= MAX_ALATES - 2 and _spawn_rng.randf() < chance:
			_maybe_nuptial_flight()


func _announce(text: String) -> void:
	_title.text = text
	_title.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_title, "modulate:a", 1.0, 0.8)
	tween.tween_interval(5.0)
	tween.tween_property(_title, "modulate:a", 0.0, 1.5)


# ---------------------------------------------------------------------------
# Field notes
# ---------------------------------------------------------------------------

const FOOD_NAMES := {"sugar": "the sugar", "nectar": "the nectar", "fruit": "the fruit",
		"protein": "the ladybugs", "seeds": "the seeds"}
const CHAMBER_NOTES := {
	"nursery": "Workers finished a new nursery chamber.",
	"pupae": "A chamber was dug just for the pupae.",
	"food": "A new food store was dug out.",
	"fungus": "A chamber was opened for a fungus garden.",
	"refuse": "The colony dug a refuse chamber, well away from the brood.",
	"alates": "A chamber for winged alates was dug.",
	"rest": "Another resting chamber was dug.",
}
const POPULATION_MARKS := [10, 25, 40, 60]


## Writes the colony's journal as things happen (see field_notes.gd).
func _hook_field_notes(founding: bool) -> void:
	if founding:
		notes.note("A mated queen sealed herself into a small chamber below the surface, with her first brood and a few workers.", "founded")
	colony.note.connect(func(text: String, key: String): notes.note(text, key))
	colony.worker_emerged.connect(func(_pos: Vector2, _chamber: int):
		notes.note("The first new worker emerged, pale and soft.", "first_worker"))
	_subterranean.chamber_opened.connect(func(id: int):
		var role: String = _subterranean.chambers[id]["role"]
		if role == "queen":
			notes.note("The queen moved down into her deep chamber; nurses carried the brood after her.", "queen_moved")
		else:
			notes.note(CHAMBER_NOTES.get(role, "A new chamber was dug.")))
	_subterranean.entrance_opened.connect(func(_x: float):
		notes.note("Diggers broke through to the surface: the nest has a new entrance."))
	colony.food_found.connect(func(kind: String):
		notes.note("Foragers found %s and began recruiting nestmates." % FOOD_NAMES.get(kind, "food"), "found_" + kind))
	weather.rain_changed.connect(func(raining: bool):
		if raining:
			if weather.snow:
				notes.note("Snow is falling over the nest.")
			else:
				notes.note("Rain. Every forager hurried home and the colony stayed underground."))
	bird.ant_taken.connect(func():
		notes.note("A bird hopped down and carried off a forager."))
	bird.scared_off.connect(func():
		notes.note("You startled a hunting bird away."))


## Population milestones, checked with each history sample.
func _note_population(count: int) -> void:
	for mark in POPULATION_MARKS:
		if count >= mark:
			notes.note("The colony reached %d workers." % mark, "pop_%d" % mark)
	var all_dug := true
	for id: int in _subterranean.chambers:
		if not _subterranean.is_dug(id):
			all_dug = false
			break
	if all_dug and _subterranean.chambers.size() > 0:
		notes.note("Every chamber of the nest has now been dug.", "nest_complete")


# ---------------------------------------------------------------------------
# First-launch tips
# ---------------------------------------------------------------------------

const TIPS := [
	"Tap any ant or chamber to see what is going on.",
	"Tap a food below to drop it on the surface, then watch who finds it.",
	"Double-tap or pinch to zoom in, and drag to look around.",
	"Tap the i button for colony stats and field notes.",
]
const TIP_START := 8.0
const TIP_GAP := 15.0
const TIP_SHOW := 8.0


## A few gentle hints, shown once on a player's first launch.
func _start_tips() -> void:
	if _load_setting("tips", "shown", false):
		return
	var tip := Label.new()
	tip.name = "Tip"
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 16)
	tip.add_theme_color_override("font_color", Color(0.96, 0.9, 0.76))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.1, 0.07, 0.04, 0.82)
	panel.border_color = Color("#b07c48")
	panel.set_border_width_all(1)
	panel.set_content_margin_all(8)
	tip.add_theme_stylebox_override("normal", panel)
	tip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tip.offset_bottom = -88.0
	tip.modulate.a = 0.0
	$UI.add_child(tip)
	var seq := create_tween()
	seq.tween_interval(TIP_START)
	for text: String in TIPS:
		seq.tween_callback(func(): tip.text = text)
		seq.tween_property(tip, "modulate:a", 1.0, 0.6)
		seq.tween_interval(TIP_SHOW)
		seq.tween_property(tip, "modulate:a", 0.0, 0.8)
		seq.tween_interval(TIP_GAP - TIP_SHOW - 1.4)
	seq.tween_callback(tip.queue_free)
	if not profile.is_preview:
		_save_setting("tips", "shown", true)


# ---------------------------------------------------------------------------
# Behaviour field guide: real ant behaviours a player discovers by tapping an ant
# while it is doing them.
# ---------------------------------------------------------------------------

const BEHAVIORS := {
	"digging": ["Digging", "You watched a worker chew out a pellet of soil to extend the nest."],
	"carry_soil": ["Carrying spoil", "You watched a digger carry excavated soil up to the mound."],
	"carry_brood": ["Moving brood", "You watched a nurse carry brood to a better spot in the nest."],
	"tending": ["Tending brood", "You watched a nurse groom the brood, licking it clean."],
	"midden": ["Building the midden", "A harvester carried seed husks up and out to the midden beside the mound."],
	"milling": ["Milling seeds", "A big-headed major cracked seeds open with its huge jaws for its nestmates."],
	"hitchhiking": ["Hitchhiker", "A tiny minima rode home on a leaf, guarding the carrier from parasitic flies."],
	"grooming": ["Self-grooming", "An ant stopped to comb its antennae clean with its forelegs."],
	"allogrooming": ["Allogrooming", "One ant licked a nestmate clean, sharing the colony's scent."],
	"skirmish": ["Border war", "Pavement ants grappled with a rival colony to settle their territory."],
	"eclosion": ["Helping out", "A nurse helped a new worker out of its pupal case."],
	"mobbing": ["Mobbing", "Workers swarmed a wolf spider, biting its legs until it fled."],
	"necrophoresis": ["Necrophoresis", "A worker carried a dead nestmate to the refuse pile, as ants do once a body starts to smell."],
	"cannibalism": ["Recycling eggs", "Short of protein, a nurse fed an egg to a larva."],
	"plugging": ["Sealing up", "Guards heaped soil into the entrance to close the nest for the night."],
	"spore_grooming": ["Social immunity", "Nestmates groomed fungal spores off a forager before they could infect it."],
	"self_removal": ["Leaving to die", "An infected worker walked out of the nest to die alone, protecting the colony."],
	"drinking": ["Drinking", "A forager drank from a raindrop on the grass and carried the water home."],
	"aphids": ["Herding aphids", "A garden ant stroked aphids with its antennae and drank their sweet honeydew."],
	"retinue": ["Queen's retinue", "You watched an attendant grooming and feeding the queen."],
	"trophallaxis": ["Trophallaxis", "You watched two ants share food mouth to mouth."],
	"antennation": ["Antennation", "You watched two nestmates touch antennae to recognise each other."],
	"carry_food": ["Bringing food home", "You watched a forager carry food down to the stores."],
	"harvesting": ["Harvesting", "You watched a forager cut or drink food before carrying it home."],
	"foraging": ["Foraging", "You watched a forager search the surface for food."],
	"haul_waste": ["Nest hygiene", "You watched a worker haul waste to the refuse heap."],
	"resting": ["Resting", "You watched a worker resting; many workers in a real colony are idle."],
	"callow": ["A callow worker", "You watched a newly emerged worker, still pale and soft."],
	"guarding": ["Guarding", "You watched a big-headed defender on guard."],
	"alate": ["Winged alate", "You watched a winged queen or male waiting for its mating flight."],
	"flight": ["Nuptial flight", "You watched an alate take to the air on its mating flight."],
}


func _on_ant_inspected(ant: Node2D) -> void:
	if ant == null:
		return
	var key: String = ant.behavior_key()
	if key == "" or not BEHAVIORS.has(key) or notes.has_noted("seen_" + key):
		return
	notes.note(BEHAVIORS[key][1], "seen_" + key)
	_announce("Behaviour observed: %s  (%d of %d)" % [BEHAVIORS[key][0], notes.count_prefix("seen_"),
			_guide_total()])


# ---------------------------------------------------------------------------
# Seasons
# ---------------------------------------------------------------------------

const SeasonsScript := preload("res://scripts/seasons.gd")
## Behaviours only one species shows; the others never count toward a colony's guide.
const SPECIES_BEHAVIORS := {"midden": "harvester", "milling": "bigheaded",
		"hitchhiking": "leafcutter", "aphids": "garden", "skirmish": "pavement",
		"plugging": ["harvester", "leafcutter"]}


func _guide_total() -> int:
	var total := 0
	for key in BEHAVIORS:
		var owner = SPECIES_BEHAVIORS.get(key, profile.species["id"])
		if (owner is Array and (owner as Array).has(profile.species["id"])) \
				or (owner is String and owner == profile.species["id"]):
			total += 1
	return total


var _remains: Node2D  # bodies carried out onto the midden


## Harvester ants leave their dead on the midden outside, among the seed husks.
func _on_corpse_dumped(x: float, texture: Texture2D) -> void:
	if _remains == null:
		_remains = Node2D.new()
		_remains.name = "Remains"
		add_child(_remains)
		move_child(_remains, _ants.get_index())
	var body := Sprite2D.new()
	body.texture = texture
	body.flip_v = true
	body.modulate = Color(0.5, 0.46, 0.44)
	body.position = Vector2(roundf(x + _spawn_rng.randf_range(-6.0, 6.0)), GROUND_Y - texture.get_height() * 0.5 + 1.0)
	_remains.add_child(body)
	if _remains.get_child_count() > 8:
		_remains.get_child(0).queue_free()  # older remains break down
	var fade := body.create_tween()
	fade.tween_interval(240.0)
	fade.tween_property(body, "modulate:a", 0.0, 20.0)
	fade.tween_callback(body.queue_free)


const EntrancePlugsScript := preload("res://scripts/entrance_plugs.gd")
var _plugs: Node2D


## Harvesters and leafcutters seal their entrances at night, in rain and in the cold, once
## every forager is home, and open them again when it is fine.
func _update_plugs(delta: float) -> void:
	if not profile.species.get("plugs_entrances", false):
		return
	if _plugs == null:
		_plugs = EntrancePlugsScript.new()
		_plugs.name = "EntrancePlugs"
		add_child(_plugs)
		move_child(_plugs, _ants.get_index())
		_plugs.setup(GROUND_Y, profile.soil["strata"][1], profile.seed_value)
	var open_xs: Array[float] = []
	for id in _subterranean.open_entrances():
		open_xs.append(_subterranean.nodes[id].x)
	_plugs.set_entrances(open_xs)
	var close := colony.night or colony.raining or colony.winter or not colony.forage_ok
	_plugs.set_closed(close)
	_plugs.modulate = colony.surface_tint
	var outside := 0
	for ant in _ants.get_children():
		if ant.state == AntScript.State.FORAGE_SURFACE:
			outside += 1
	_plugs.advance(delta, outside == 0)
	var was := colony.entrances_closed
	colony.entrances_closed = close and outside == 0
	colony.plug_work = _plugs.is_working()
	if _plugs.is_sealed() and not was:
		notes.note("At dusk the workers plugged the entrances with soil and pebbles, sealing the nest for the night.", "plugged")


const ClimateScript := preload("res://scripts/climate.gd")
var climate := ClimateScript.new()


## Advances the weather's temperatures and decides whether it is foraging weather for
## this species (with a degree of slack either way so foragers don't dither).
func _update_climate(delta: float) -> void:
	if seasons == null or weather == null:
		return
	climate.update(seasons.season(), seasons.progress(), _day_night.time_of_day, _day_night.daylight,
			weather.intensity if not weather.snow else 0.0, weather.snow_depth, delta)
	colony.climate = climate
	var window: Array = profile.species.get("forage_temp", [10.0, 40.0])
	var t := climate.surface
	if colony.forage_ok and (t < float(window[0]) - 1.0 or t > float(window[1]) + 1.0):
		colony.forage_ok = false
		if t > float(window[1]):
			notes.note("Too hot to forage: at %d deg C the ground was above what %s ants will cross, so they waited underground for it to cool." % [roundi(t), profile.species["name"].to_lower().replace(" ant", "")], "too_hot")
		elif not colony.winter:
			notes.note("Too cold to forage: at %d deg C the ants were too sluggish to go out." % roundi(t), "too_cold")
	elif not colony.forage_ok and t >= float(window[0]) + 1.0 and t <= float(window[1]) - 1.0:
		colony.forage_ok = true


const SpiderScript := preload("res://scripts/spider.gd")
const SPIDER_INTERVAL := Vector2(360.0, 720.0)
var spider: Node2D
var _spider_clock := 0.0


func _build_spider() -> void:
	spider = SpiderScript.new()
	spider.name = "Spider"
	add_child(spider)
	move_child(spider, _ants.get_index())
	spider.setup(GROUND_Y, VIEW_SIZE.x, profile.seed_value)
	spider.driven_off.connect(func():
		_announce("The ants drove the spider off!")
		notes.note("A wolf spider prowled near the nest until a crowd of workers mobbed it and drove it away.", "first_spider"))
	_spider_clock = _spawn_rng.randf_range(SPIDER_INTERVAL.x * 0.5, SPIDER_INTERVAL.y)


func _update_spider(delta: float) -> void:
	if spider == null:
		return
	spider.set_tint(colony.surface_tint)
	colony.threat = spider if spider.active and not spider.fleeing else null
	if spider.active:
		return
	_spider_clock -= delta
	if _spider_clock <= 0.0:
		_spider_clock = _spawn_rng.randf_range(SPIDER_INTERVAL.x, SPIDER_INTERVAL.y)
		if not colony.raining and not colony.winter and _worker_count() >= 8:
			start_spider()


## A wolf spider walks in from the nearer edge to lurk near one of the open entrances.
func start_spider() -> void:
	var open: Array[int] = _subterranean.open_entrances()
	var lurk: float = _subterranean.nodes[open[_spawn_rng.randi() % open.size()]].x
	spider.start(lurk < VIEW_SIZE.x * 0.5, lurk)


const WaterDropsScript := preload("res://scripts/water_drops.gd")
var water: Node2D
var wetness := 0.0  # 0..1: how damp the topsoil is after rain or melting snow


func _update_wetness(delta: float) -> void:
	if weather == null:
		return
	if weather.raining and not weather.snow:
		wetness = minf(1.0, wetness + delta * weather.intensity / 90.0)
	elif not weather.snow and weather.snow_depth > 0.0:
		wetness = minf(1.0, wetness + delta / 200.0)  # snowmelt
	else:
		wetness = maxf(0.0, wetness - delta / (600.0 if colony.winter else 420.0))
	colony.soil_wetness = wetness
	_subterranean.set_wetness(wetness)
	water.daylight = _day_night.daylight
	if wetness > 0.6:
		notes.note("Rain soaked into the topsoil. Damp soil is easier to dig, and the ants dig faster.", "wet_soil")


const EXPAND_CHECK := 300.0  # seconds between checks for a crowded, fully dug nest
const MAX_EXPANSIONS := 8
var _expand_clock := EXPAND_CHECK


## Real nests keep growing with the colony: once every planned room is dug, the
## workers start new galleries off the old ones.
func _update_expansion(delta: float) -> void:
	_expand_clock -= delta
	if _expand_clock > 0.0:
		return
	_expand_clock = EXPAND_CHECK
	if colony.winter or colony.has_digging() or _subterranean.expansions >= MAX_EXPANSIONS \
			or _worker_count() < 15:
		return
	if _subterranean.expand() > 0:
		notes.note("The colony outgrew its nest and started digging new galleries.", "first_expansion")


const SkirmishScript := preload("res://scripts/skirmish.gd")
const SKIRMISH_INTERVAL := Vector2(300.0, 600.0)

var skirmish: Node2D = null
var _skirmish_clock := 0.0


## Pavement ants hold their territory against neighbouring colonies in ritual border fights.
func _build_skirmish() -> void:
	skirmish = SkirmishScript.new()
	skirmish.name = "Skirmish"
	add_child(skirmish)
	move_child(skirmish, _ants.get_index())
	skirmish.setup(profile.species, GROUND_Y, VIEW_SIZE.x, profile.seed_value)
	_skirmish_clock = _spawn_rng.randf_range(SKIRMISH_INTERVAL.x * 0.4, SKIRMISH_INTERVAL.y)


func _update_skirmish(delta: float) -> void:
	if skirmish == null:
		return
	skirmish.set_tint(colony.surface_tint)
	colony.skirmish_x = skirmish.border_x if skirmish.is_holding() else NAN
	if skirmish.active:
		return
	_skirmish_clock -= delta
	if _skirmish_clock <= 0.0:
		_skirmish_clock = _spawn_rng.randf_range(SKIRMISH_INTERVAL.x, SKIRMISH_INTERVAL.y)
		if not colony.night and not colony.raining and not colony.winter and _worker_count() >= 12:
			start_skirmish(_spawn_rng.randf() < 0.5)


## Rival workers march in from one edge to fight at the border.
func start_skirmish(from_left: bool) -> void:
	skirmish.start(from_left)
	_announce("Rival pavement ants at the border!")
	notes.note("A neighbouring pavement-ant colony marched up to the border and the workers grappled there until the rivals withdrew.",
			"first_skirmish")


const AphidPlantScript := preload("res://scripts/aphid_plant.gd")

var _aphid_plant: Node2D = null


## Black garden ants keep a herd of aphids on a weed near the nest (always the same spot
## for a given colony).
func _build_aphids() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.seed_value + 404
	var x := VIEW_SIZE.x * 0.5
	for attempt in 20:
		x = rng.randf_range(SURFACE_MARGIN + 60.0, VIEW_SIZE.x - SURFACE_MARGIN - 60.0)
		var clear := true
		for ex in _subterranean.entrance_xs:
			if absf(x - ex) < 70.0:
				clear = false
		if clear:
			break
	_aphid_plant = AphidPlantScript.new()
	_aphid_plant.name = "AphidPlant"
	add_child(_aphid_plant)
	move_child(_aphid_plant, _food_layer.get_index())
	_aphid_plant.setup(GROUND_Y, x, profile.seed_value)
	colony.aphid_x = x
const SEASON_NOTES := [
	"Spring: the soil warms and the queen lays faster.",
	"Summer: long warm days; mature colonies send out their alates.",
	"Autumn: leaves fall and foragers gather what they can before the cold.",
	"Winter: the colony withdraws deep into the nest. The queen rests and the brood waits for spring.",
]

var seasons: SeasonsScript


func _build_seasons(saved: Dictionary) -> void:
	seasons = SeasonsScript.new()
	seasons.name = "Seasons"
	add_child(seasons)
	seasons.setup(_day_night, int(saved.get("day", 0)))
	seasons.season_changed.connect(func(s: int):
		_apply_season()
		notes.note(SEASON_NOTES[s])
		_announce(SeasonsScript.NAMES[s]))
	_update_clear_spots()
	_subterranean.entrance_opened.connect(func(_x: float): _update_clear_spots())
	_apply_season()


func _apply_season() -> void:
	var s := seasons.season()
	colony.winter = s == SeasonsScript.WINTER
	colony.lay_rate = 1.4 if s == SeasonsScript.SPRING else 1.0
	weather.snow = colony.winter
	weather.autumn = s == SeasonsScript.AUTUMN
	if _aphid_plant != null:
		_aphid_plant.winter = colony.winter
	_day_night.season_tint = [Color(1.0, 1.0, 0.97), Color(1.03, 1.0, 0.92), Color(1.0, 0.9, 0.78),
			Color(0.84, 0.9, 1.02)][s]


## Snow never covers an open entrance (the ants keep them clear).
func _update_clear_spots() -> void:
	var xs: Array[float] = []
	for i in _subterranean.entrances.size():
		if _subterranean.is_dug(_subterranean.entrances[i]):
			xs.append(_subterranean.entrance_xs[i])
	weather.set_clear_spots(xs)
