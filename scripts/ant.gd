extends Node2D
## One worker ant. Its caste sets its body; its role sets its work. Like real workers
## it changes job with age (temporal polyethism): it emerges as a pale callow nurse,
## moves on to nest work, and finishes as a forager. Majors and soldiers stay guards.
##   NURSE   - carries eggs, larvae and pupae; feeds larvae
##   WORKER  - hauls waste to the refuse heap; visits stores, dig faces
##   FORAGER - rests near the top, goes out, brings food home
##   GUARD   - upper chambers and the entrance shaft

const ColonyArt := preload("res://scripts/colony_art.gd")
const Tunnels := preload("res://scripts/subterranean_layer.gd")
const ColonyScript := preload("res://scripts/colony.gd")
const Climate := preload("res://scripts/climate.gd")

enum State { PATROL_TUNNEL, IDLE_CHAMBER, FORAGE_SURFACE, TASK, LEAVING, FLYING }
enum Role { NURSE, WORKER, FORAGER, GUARD, ALATE }

const ROLE_WEIGHTS := {
	Role.NURSE: {"queen": 3.0, "nursery": 5.0, "pupae": 2.0, "fungus": 3.0, "food": 1.0},
	Role.WORKER: {"refuse": 2.0, "food": 2.0, "rest": 1.0, "fungus": 1.5, "nursery": 1.0, "dig": 1.5},
	Role.FORAGER: {"rest": 3.0, "food": 2.0, "surface": 4.0},
	Role.GUARD: {"rest": 3.0, "food": 1.0, "entrance": 3.0, "surface": 1.0},
	Role.ALATE: {},  # winged reproductives stay in their chamber until a nuptial flight
}
const NURSE_UNTIL := 300.0  # seconds of age before a nurse turns to nest work
const WORKER_UNTIL := 700.0  # ...and before a nest worker starts foraging
const CALLOW_TIME := 90.0  # how long a new worker takes to darken
const CALLOW_TINT := Color(1.9, 1.75, 1.55)
const SURFACE_STEP := 260.0
const FRAME_TIME := 0.09
const TURN_RATE := 10.0
const BASE_SPEED := 46.0
const GALLERY_FLOOR_OFFSET := 2.5  # px below a gallery's centre line, where the floor is

var state: State = State.IDLE_CHAMBER
var role: Role = Role.WORKER
var caste_name := ""
var age := 0.0
var lifespan := 3000.0  # seconds; workers live a few times longer than they took to develop

var _tunnels: Tunnels
var _colony: ColonyScript
var _rng := RandomNumberGenerator.new()
var _speed := BASE_SPEED
var _half_height := 8.0
var _half_width := 9.0
var _path: Array[Vector2] = []
var _current_node := 0
var _goal_node := 0
var _state_timer := 0.0
var _pause_timer := 0.0
var _returning := false
var _departing := false
var _ground_y := 0.0
var _surface_x_range := Vector2.ZERO
var _moving := false
var _facing_left := false
var _frames: Array[ImageTexture] = []
var _frame := 0
var _frame_clock := 0.0
var _callow_left := 0.0
var _caste: Dictionary = {}
var _multi_caste := false
var _greet_left := 0.0
var _greet_cooldown := 0.0
var _trail: Node2D  # optional surface pheromone layer (has add_point)
var _dust: Node2D  # optional digging dust layer (has puff)
var _trail_clock := 0.0
var _food_target: Node2D  # a food drop on the surface this ant is heading for
var _harvest_left := -1.0
var _snatched := false
var _dig_left := -1.0  # seconds of digging left at the soil face (-1 when not digging)
var _nuptial := false  # a winged alate heading out on its mating flight
var _attending := false  # one of the queen's attendants right now
var _crop_left := 0.0  # seconds this ant still has liquid food in its crop to share
var _tend_x := INF  # x of the brood item an idle nurse is grooming (or the seed a major mills)
var _milling := false  # a big-headed major cracking seeds in a granary
var _helping := false  # a nurse helping a new adult out of its cocoon
var _aphid_left := -1.0  # seconds left tending aphids on the surface (black garden ants)
var _to_aphids := false
var _groom_left := 0.0  # seconds of grooming left (self-grooming or grooming a nestmate)
var _groom_mode := 0  # GROOM_SELF, GROOM_OTHER (the groomer) or GROOM_RECEIVE
var _groom_x := 0.0  # where the nestmate being groomed (or grooming) stands
var _fight_left := -1.0  # seconds left grappling a rival at the border (pavement ants)
var _to_fight := false
var _to_mob := false  # heading out to mob a spider near the nest
var _mob_left := -1.0
var _drink_target: Node2D = null  # a rain drop this forager is heading to drink from
var _drink_left := -1.0

enum { GROOM_SELF, GROOM_OTHER, GROOM_RECEIVE }

const CROP_TIME := 150.0


## Food in the crop (from feeding at a food drop, delivering food, or a nestmate).
func has_crop() -> bool:
	return _crop_left > 0.0


func fill_crop() -> void:
	_crop_left = CROP_TIME
var _fly_velocity := Vector2.ZERO
var _fly_clock := 0.0
var _task: Dictionary = {}
var _task_stage := 0
var _carried: Sprite2D

@onready var _sprite: Sprite2D = $Sprite


## Call after the ant is in the tree. `start_pos` overrides the floor spot (used for callows).
func setup(tunnels: Tunnels, colony: ColonyScript, species: Dictionary, caste: Dictionary, ant_role: Role,
		start_node: int, ground_y: float, surface_x_range: Vector2, seed_value: int, start_age: float,
		start_pos: Vector2 = Vector2.INF) -> void:
	_tunnels = tunnels
	_colony = colony
	role = ant_role
	age = start_age
	caste_name = caste["name"]
	_caste = caste
	_multi_caste = (species["castes"] as Array).size() > 1
	_ground_y = ground_y
	_surface_x_range = surface_x_range
	_rng.seed = seed_value
	# workers of one caste still vary a little in size (a few size steps keep the art cache small)
	var size_jitter: float = [0.93, 0.97, 1.0, 1.03, 1.07][_rng.randi() % 5] if not caste.get("queen", false) else 1.0
	_frames = ColonyArt.ant_frames(species, float(caste["size"]) * size_jitter, caste["head"], caste.get("queen", false),
			caste.get("wings", false))
	_frame = _rng.randi_range(0, _frames.size() - 1)
	_sprite.texture = _frames[_frame]
	_sprite.scale = Vector2.ONE * ColonyArt.SPRITE_SCALE
	_half_height = _frames[0].get_height() * ColonyArt.SPRITE_SCALE * 0.5
	_half_width = _frames[0].get_width() * ColonyArt.SPRITE_SCALE * 0.5
	_speed = BASE_SPEED * float(species["speed"]) * _rng.randf_range(0.85, 1.15)
	lifespan = _rng.randf_range(1800.0, 3600.0) * (1.3 if float(caste["head"]) >= 1.5 else 1.0)
	_current_node = start_node
	if start_pos == Vector2.INF:
		position = _tunnels.random_floor_point(start_node, _rng, _half_height)
	else:
		position = Vector2(start_pos.x, _tunnels.chamber_floor_y(start_node) - _half_height)
	_facing_left = _rng.randf() < 0.5
	_sprite.flip_h = _facing_left
	_start_idle()
	_state_timer = _rng.randf_range(1.0, 10.0)  # stagger the first departures


## This ant's state for the save file. Ants come back resting in the nearest chamber.
func to_save() -> Dictionary:
	var home := _current_node
	if not _tunnels.is_chamber(home):
		var best := INF
		for id: int in _tunnels.chambers:
			var d := position.distance_squared_to(_tunnels.nodes[id])
			if d < best:
				best = d
				home = id
	return {"caste": _caste, "role": role, "age": age, "callow": _callow_left, "chamber": home,
			"x": position.x if _tunnels.is_chamber(_current_node) else _tunnels.nodes[home].x,
			"departing": _departing, "lifespan": lifespan}


## Restores the callow tint and departure flag from a save.
func restore_extras(callow_left: float, departing: bool) -> void:
	if callow_left > 0.0:
		make_callow()
		_callow_left = callow_left
	_departing = departing


## Which field-guide behaviour this ant is showing right now, or "" (see main.gd BEHAVIORS).
func behavior_key() -> String:
	if state == State.FLYING:
		return "flight"
	if role == Role.ALATE:
		return "alate"
	if _callow_left > 0.0:
		return "callow"
	if _carried != null:
		match str(_carried.get_meta("kind", "")):
			"brood":
				return "carry_brood"
			"waste":
				return "midden" if _task.get("zone") == "midden" else "haul_waste"
			"soil":
				return "carry_soil"
			"corpse":
				return "necrophoresis"
		if _carried.has_meta("cannibal"):
			return "cannibalism"
		return "hitchhiking" if _carried.has_meta("hitchhiker") else "carry_food"
	if _greet_left > 0.0:
		return "trophallaxis" if has_crop() else "antennation"
	if _groom_left > 0.0:
		return "grooming" if _groom_mode == GROOM_SELF else "allogrooming"
	if _fight_left > 0.0:
		return "skirmish"
	if _drink_left > 0.0:
		return "drinking"
	if _mob_left > 0.0:
		return "mobbing"
	if _attending:
		return "retinue"
	if _dig_left > 0.0:
		return "digging"
	if _harvest_left > 0.0:
		return "harvesting"
	if _tend_x != INF and state == State.IDLE_CHAMBER:
		return "milling" if _milling else ("eclosion" if _helping else "tending")
	if _aphid_left > 0.0:
		return "aphids"
	if state == State.FORAGE_SURFACE:
		return "foraging"
	if state == State.IDLE_CHAMBER and _tunnels.chamber_role(_current_node) == "rest":
		return "resting"
	if role == Role.GUARD:
		if _colony != null and _colony.plug_work and _tunnels.is_entrance(_current_node) == false \
				and _tunnels.links[Tunnels.ENTRANCE].has(_current_node):
			return "plugging"
		return "guarding"
	return ""


## One line about this ant for the inspect label, e.g. "Nurse · major · 3 min old · carrying brood".
func describe() -> String:
	var parts: Array[String] = []
	match role:
		Role.NURSE:
			parts.append("Nurse")
		Role.WORKER:
			parts.append("Nest worker")
		Role.FORAGER:
			parts.append("Forager")
		Role.GUARD:
			parts.append("Guard")
		Role.ALATE:
			parts.append("Winged queen" if caste_name == "alate queen" else "Winged male")
	if (_multi_caste or caste_name == "nanitic") and role != Role.ALATE:
		parts.append(caste_name)
	if role != Role.ALATE:
		parts.append("%d min old" % maxi(1, int(age / 60.0)))
	if _callow_left > 0.0:
		parts.append("newly emerged")
	elif _carried != null:
		match str(_carried.get_meta("kind", "")):
			"brood":
				parts.append("carrying brood")
			"waste":
				parts.append("hauling waste")
			"soil":
				parts.append("carrying soil out")
			"corpse":
				parts.append("carrying a dead nestmate out")
			_:
				parts.append("carrying food")
	elif _greet_left > 0.0:
		parts.append("sharing food" if has_crop() else "touching antennae")
	elif _groom_left > 0.0:
		parts.append(["cleaning its antennae", "grooming a nestmate", "being groomed"][_groom_mode])
	elif _fight_left > 0.0:
		parts.append("grappling a rival")
	elif _drink_left > 0.0:
		parts.append("drinking a raindrop")
	elif _mob_left > 0.0:
		parts.append("biting at a spider")
	elif _attending:
		parts.append("attending the queen")
	elif _dig_left > 0.0:
		parts.append("digging")
	elif _tend_x != INF and state == State.IDLE_CHAMBER:
		if _helping:
			parts.append("helping a new worker out of its cocoon" if _colony.cocoons() else "helping a new worker emerge")
		else:
			parts.append("milling seeds" if _milling else "tending the brood")
	elif _aphid_left > 0.0:
		parts.append("tending aphids")
	elif _harvest_left > 0.0:
		parts.append("gathering food")
	elif _food_target != null:
		parts.append("heading for food")
	elif state == State.FORAGE_SURFACE:
		parts.append("foraging outside")
	elif state == State.IDLE_CHAMBER and _tunnels.chamber_role(_current_node) == "rest":
		parts.append("resting")
	return "  ·  ".join(parts)


## Brief stop to touch antennae with a nestmate (antennation). Returns false if it can't now.
func greet(other_pos: Vector2) -> bool:
	if _greet_left > 0.0 or _greet_cooldown > 0.0 or state in [State.LEAVING, State.FLYING] or _nuptial:
		return false
	_greet_left = _rng.randf_range(0.5, 1.1)
	_greet_cooldown = _rng.randf_range(6.0, 14.0)
	var dir := other_pos - position
	if absf(dir.x) > 0.5:
		_facing_left = dir.x < 0.0
		_sprite.flip_h = _facing_left
	return true


## True when this ant is idling in a chamber and free to groom or be groomed.
func can_allogroom() -> bool:
	return state == State.IDLE_CHAMBER and _path.is_empty() and not _attending and _tend_x == INF \
			and _greet_left <= 0.0 and _groom_left <= 0.0 and _carried == null and role != Role.ALATE \
			and _tunnels.is_chamber(_current_node)


## Allogrooming: one ant licks and combs a nestmate clean (spreading the colony odour and
## removing fungal spores); the other stands still for it.
func allogroom(other_pos: Vector2, groomer: bool, duration: float) -> void:
	_groom_left = duration
	_groom_mode = GROOM_OTHER if groomer else GROOM_RECEIVE
	_groom_x = other_pos.x
	_facing_left = other_pos.x < position.x
	_sprite.flip_h = _facing_left


func _update_grooming(delta: float) -> void:
	_groom_left -= delta
	match _groom_mode:
		GROOM_SELF:  # forelegs drawn through the mouthparts: the body rocks and the front dips
			_sprite.rotation = (0.12 if _facing_left else -0.12) + sin(age * 11.0) * 0.07
			_sprite.scale.y = ColonyArt.SPRITE_SCALE * (0.9 if int(age * 8.0) % 2 == 0 else 1.0)
		GROOM_OTHER:  # head working along the nestmate's body
			_sprite.rotation = sin(age * 7.0) * 0.12
			position.x += sin(age * 2.5) * 3.0 * delta
		GROOM_RECEIVE:  # still, legs splayed, sometimes lifting a little
			_sprite.rotation = sin(age * 1.5) * 0.04
	if _groom_left <= 0.0:
		_groom_left = 0.0
		_sprite.rotation = 0.0
		_sprite.scale.y = ColonyArt.SPRITE_SCALE


## A freshly emerged worker: pale, and it lingers by the brood for a while first.
func make_callow() -> void:
	_callow_left = CALLOW_TIME
	_sprite.modulate = CALLOW_TINT
	_state_timer = _rng.randf_range(8.0, 15.0)


## A winged alate leaves on its mating flight: out of the nearest entrance and away.
func start_nuptial_flight() -> void:
	if role != Role.ALATE or _nuptial:
		return
	_nuptial = true
	_travel_to(_tunnels.nearest_entrance(position.x))


func _take_off() -> void:
	state = State.FLYING
	_path.clear()
	position = _tunnels.nodes[_current_node] + Vector2(0.0, -_half_height)
	_fly_velocity = Vector2(_rng.randf_range(-45.0, 45.0), _rng.randf_range(-75.0, -55.0))
	_sprite.rotation = 0.0


func _update_flight(delta: float) -> void:
	_fly_clock += delta
	# fluttering, wandering climb: wings beating fast, drifting on the breeze
	position += (_fly_velocity + Vector2(sin(_fly_clock * 3.1) * 25.0, sin(_fly_clock * 11.0) * 18.0)) * delta
	_fly_velocity.y = maxf(_fly_velocity.y - 12.0 * delta, -110.0)
	if absf(_fly_velocity.x) > 0.5:
		_facing_left = _fly_velocity.x < 0.0
		_sprite.flip_h = _facing_left
	_sprite.rotation = (-0.3 if _facing_left else 0.3) * signf(_fly_velocity.x)
	_frame_clock += delta
	if _frame_clock >= 0.05:
		_frame_clock = 0.0
		_frame = (_frame + 1) % _frames.size()
		_sprite.texture = _frames[_frame]
		_sprite.scale.y = ColonyArt.SPRITE_SCALE * (0.85 if _frame % 2 == 0 else 1.0)  # wingbeat
	modulate = _colony.surface_tint if _colony != null else Color.WHITE
	if position.y < -40.0 or position.x < -60.0 or position.x > 1340.0:
		queue_free()


## True for a worker out on the open surface (where a bird can reach it).
func is_exposed() -> bool:
	return state == State.FORAGE_SURFACE and position.y < _ground_y and not _snatched


## Caught by a bird: the ant stops and goes limp; the bird carries it off.
func snatch() -> void:
	_snatched = true
	set_process(false)
	if _carried != null:
		_carried.queue_free()
		_carried = null
	_sprite.texture = _frames[0]
	_sprite.rotation = 0.0


## An old forager that will not come back from its next trip outside.
func depart() -> void:
	_departing = true


func is_departing() -> bool:
	return _departing


func _process(delta: float) -> void:
	if _tunnels == null:
		return
	age += delta
	if _callow_left > 0.0:
		_callow_left -= delta
		_sprite.modulate = Color.WHITE.lerp(CALLOW_TINT, clampf(_callow_left / CALLOW_TIME, 0.0, 1.0))
	_greet_cooldown -= delta
	_crop_left -= delta
	# above ground the ant shares the sky's light; underground the farm lamp is steady
	modulate = _colony.surface_tint if _colony != null and position.y < _ground_y + 2.0 else Color.WHITE
	if _greet_left > 0.0:
		_greet_left -= delta  # stopped, antennae touching; the legs stay still
		_frame_clock += delta
		if _frame_clock >= 0.15:
			_frame_clock = 0.0
			_sprite.rotation += 0.06 if _frame % 2 == 0 else -0.06  # small head bob
			_frame += 1
		return
	if _groom_left > 0.0:
		_update_grooming(delta)
		return
	match state:
		State.PATROL_TUNNEL:
			if _follow_path(delta):
				_arrive()
		State.IDLE_CHAMBER:
			_update_idle(delta)
		State.FORAGE_SURFACE:
			_update_surface(delta)
		State.TASK:
			if _dig_left > 0.0:
				_dig_left = maxf(_dig_left - delta, 0.0)  # digging: head works at the soil
				_frame_clock += delta
				if _frame_clock >= 0.12:
					_frame_clock = 0.0
					_frame = (_frame + 1) % _frames.size()
					_sprite.texture = _frames[_frame]
					if _dust != null:  # specks of soil fly off the face
						var ahead := Vector2(-1.0 if _facing_left else 1.0, 0.0).rotated(_sprite.rotation)
						_dust.puff(position + ahead * _half_width, -ahead)
				if _dig_left == 0.0:
					_advance_task()
			elif _follow_path(delta):
				_advance_task()
		State.LEAVING:
			if _follow_path(delta):
				queue_free()
		State.FLYING:
			_update_flight(delta)
			return
	_animate(delta)
	if _carried != null:
		# held in the mandibles, just ahead of the head
		var ahead := Vector2((-1.0 if _facing_left else 1.0) * (_half_width + 1.0), _half_height * 0.4)
		_carried.position = ahead.rotated(_sprite.rotation)
		# foragers bringing food home lay a scent trail for nestmates to follow
		if _trail != null and _moving and position.y < _ground_y and _task.get("type") == "store":
			_trail_clock -= delta
			if _trail_clock <= 0.0:
				_trail_clock = 0.12
				_trail.add_point(position + Vector2(0.0, _half_height - 1.0))


func set_trail_layer(layer: Node2D) -> void:
	_trail = layer


func set_dust_layer(layer: Node2D) -> void:
	_dust = layer


# ---------------------------------------------------------------------------
# Choosing what to do next
# ---------------------------------------------------------------------------

func _update_role() -> void:
	if role == Role.NURSE and age > NURSE_UNTIL:
		role = Role.WORKER
	elif role == Role.WORKER and age > WORKER_UNTIL:
		role = Role.FORAGER


## Called whenever the ant finishes what it was doing in a chamber.
func _next_job() -> void:
	if role == Role.ALATE:
		_start_idle()  # alates shuffle about their chamber and wait
		return
	_update_role()
	if age > lifespan and _colony != null and _tunnels.is_chamber(_current_node):
		_die()
		return
	if _colony != null and _colony.winter and _rng.randf() < 0.75:
		# overwintering: most of the colony clusters, torpid, in the deep warm chambers
		var refuge: int = _colony.winter_refuge()
		if refuge != -1 and refuge != _current_node:
			_travel_to(refuge)
			return
		if refuge == _current_node:
			_start_idle()
			return
	if _colony != null and _callow_left <= 0.0 and not _colony.entrances_closed:
		# recruited by a nestmate's trail to food on the surface
		var recruit_chance := {Role.FORAGER: 0.9, Role.WORKER: 0.35, Role.GUARD: 0.2}
		if _rng.randf() < float(recruit_chance.get(role, 0.0)):
			var food := _colony.take_recruit()
			if food != null:
				_food_target = food
				_travel_to(_tunnels.nearest_entrance(food.position.x))
				return
		if _colony.threat != null and role in [Role.GUARD, Role.FORAGER] and _rng.randf() < 0.5:
			_to_mob = true  # alarm pheromone: guards pour out to drive off the spider
			_travel_to(_tunnels.nearest_entrance(_colony.threat.position.x))
			return
		if not is_nan(_colony.skirmish_x) and role in [Role.FORAGER, Role.WORKER] and _rng.randf() < 0.5:
			_to_fight = true  # nestmates rush out to hold the border
			_travel_to(_tunnels.nearest_entrance(_colony.skirmish_x))
			return
		var task := {}
		match role:
			Role.NURSE:
				if _rng.randf() < 0.8:
					task = _colony.nurse_task()
				if task.is_empty() and _colony.has_digging() and _rng.randf() < 0.45:
					task = _colony.dig_task()  # nothing to tend: help dig
			Role.WORKER, Role.FORAGER:
				if _colony.needs_nurses() and _rng.randf() < (0.6 if role == Role.WORKER else 0.3):
					task = _colony.nurse_task()  # pitching in with hungry brood
				elif _colony.has_digging() and _rng.randf() < (0.6 if role == Role.WORKER else 0.2):
					task = _colony.dig_task()  # extend the nest
				elif role == Role.WORKER and _rng.randf() < 0.55:
					task = _colony.waste_task()
		if not task.is_empty():
			_start_task(task)
			return
	_travel_to(_choose_destination())


func _choose_destination() -> int:
	var options: Array[int] = []
	var weights: Array[float] = []
	var table: Dictionary = ROLE_WEIGHTS[role]
	for key: String in table:
		var ids: Array[int] = []
		match key:
			"surface":
				ids = _tunnels.open_entrances()
			"entrance":
				ids = [_tunnels.links[Tunnels.ENTRANCE][0]]  # first node down the shaft
			"dig":
				for id in _tunnels.dig_faces:
					if _tunnels.is_dug(id):
						ids.append(id)
			_:
				ids = _tunnels.chambers_with_role(key)
		ids.erase(_current_node)
		for id in ids:
			options.append(id)
			var night_factor := 1.0
			if key == "surface" and _colony != null:
				night_factor = 0.0 if _colony.raining or _colony.winter or not _colony.forage_ok \
						or _colony.entrances_closed else (0.15 if _colony.night else 1.0)
			elif _colony != null and _colony.winter and _tunnels.is_chamber(id):
				# overwintering: the colony packs into the deepest, warmest chambers
				var depth := clampf((_tunnels.nodes[id].y - _colony.ground_y) / (_colony.nest_bottom - _colony.ground_y), 0.0, 1.0)
				night_factor = 0.15 + 3.0 * depth * depth
			weights.append(float(table[key]) * night_factor / ids.size())
	if options.is_empty():
		return Tunnels.ENTRANCE
	var total := 0.0
	for w in weights:
		total += w
	var roll := _rng.randf() * total
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			return options[i]
	return options[options.size() - 1]


# ---------------------------------------------------------------------------
# Tasks: walk to the item, pick it up, carry it to another chamber, put it down
# ---------------------------------------------------------------------------

func _start_task(task: Dictionary) -> void:
	_task = task
	_colony.count(task["type"] + "_given")
	if task.has("pickup_node"):
		_task_stage = 0
		_travel_to(task["pickup_node"])
	else:
		_task_stage = 2  # already holding it (a forager's find)
		_travel_to(task["drop_node"])


func _advance_task() -> void:
	match _task_stage:
		0:  # in the pickup chamber: walk to the item
			_task_stage = 1
			state = State.TASK
			if _task["type"] == "dig":
				_path.append(_task["pickup_pos"])  # right up to the soil face
			else:
				_path.append(_stand_at(_task["pickup_pos"], _task["pickup_node"]))
		1:  # at the item: pick it up
			if _task["type"] == "dig" and _dig_left < 0.0:
				_dig_left = _task["dig_time"]  # chew out a pellet first
				var face: Vector2 = _tunnels.nodes[_task["dig_into"]] - position
				if absf(face.x) > 0.5:
					_facing_left = face.x < 0.0
					_sprite.flip_h = _facing_left
				_sprite.rotation = _angle_for(face.normalized())
				return
			_dig_left = -1.0
			var item: Sprite2D = _colony.pick_up(_task)
			if item == null:
				_finish_task()
				return
			_hold(item)
			_task_stage = 2
			_travel_to(_task["drop_node"])
		2:  # in the drop chamber: walk to the spot
			_task_stage = 3
			state = State.TASK
			_task["drop_pos"] = _colony.drop_position(_task)
			_path.append(_stand_at(_task["drop_pos"], _task["drop_node"]))
		3:  # put it down
			var item := _carried
			_carried = null
			if _task["type"] == "store":
				fill_crop()  # foragers come home with a full crop to share
			_colony.drop(_task, item, _task["drop_pos"])
			_finish_task()


func _finish_task() -> void:
	_task = {}
	_start_idle()
	_state_timer = _rng.randf_range(0.5, 2.5)  # busy workers move straight on to the next job


func _stand_at(item_pos: Vector2, chamber: int) -> Vector2:
	var floor_y := _tunnels.chamber_floor_y(chamber) if _tunnels.is_chamber(chamber) else item_pos.y
	return Vector2(item_pos.x, floor_y - _half_height)


func _hold(item: Sprite2D) -> void:
	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	add_child(item)
	item.z_index = 1
	_carried = item


# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------

func _travel_to(goal: int) -> void:
	var route := _tunnels.find_path(_current_node, goal)
	if route.is_empty() and goal != _current_node:
		# not dug through yet: give up the job and stay where it is
		if not _task.is_empty():
			if _carried != null:
				_carried.queue_free()
				_carried = null
			_colony.release(_task)
			_task = {}
		_food_target = null
		_start_idle()
		return
	_goal_node = goal
	_path.clear()
	for id in route:
		_path.append(_walk_point(id))
	state = State.PATROL_TUNNEL


## Where an ant actually walks past a node: on the chamber floor in rooms, and a
## little below the centre line in galleries, so it treads the floor, not mid-air.
func _walk_point(id: int) -> Vector2:
	var p: Vector2 = _tunnels.nodes[id]
	if _tunnels.is_chamber(id):
		return Vector2(p.x, _tunnels.chamber_floor_y(id) - _half_height)
	if _tunnels.is_entrance(id):
		return p
	return p + Vector2(0.0, GALLERY_FLOOR_OFFSET)


func _arrive() -> void:
	_current_node = _goal_node
	if _nuptial and _tunnels.is_entrance(_current_node):
		_take_off()
		return
	if not _task.is_empty():
		_advance_task()
	elif _tunnels.is_entrance(_current_node):
		_start_surface_trip()
	else:
		_start_idle()


func _start_idle() -> void:
	state = State.IDLE_CHAMBER
	_pause_timer = 0.0
	_tend_x = INF
	if role == Role.NURSE and _current_node == _tunnels.queen_chamber() and _colony != null \
			and _callow_left <= 0.0 and _colony.join_retinue():
		# one of the queen's attendants: stand beside her, facing her, grooming and feeding
		_attending = true
		_state_timer = _rng.randf_range(20.0, 45.0)
		_path.append(_tunnels.queen_attend_spot(_rng, _half_height))
		return
	if _tunnels.is_chamber(_current_node):
		# Real colonies have many idle workers; in rest chambers they settle for a long while.
		var resting := _tunnels.chamber_role(_current_node) == "rest"
		_state_timer = _rng.randf_range(15.0, 40.0) if resting else _rng.randf_range(5.0, 15.0)
		if _colony != null and _colony.winter:
			_state_timer *= 2.5  # torpid in the cold: long rests
		_path.append(_tunnels.random_floor_point(_current_node, _rng, _half_height))
	else:
		_state_timer = _rng.randf_range(1.5, 5.0)  # inspecting a dig face or standing guard


func _update_idle(delta: float) -> void:
	_state_timer -= delta
	if not _follow_path(delta):
		return
	if _state_timer <= 0.0:
		if _attending:
			_attending = false
			_colony.leave_retinue()
		_next_job()
		return
	if _attending:
		# face the queen and tend her: small head movements, no wandering off
		var dx := _tunnels.queen_position().x - position.x
		if absf(dx) > 0.5 and (dx < 0.0) != _facing_left:
			_facing_left = dx < 0.0
			_sprite.flip_h = _facing_left
		_sprite.rotation = sin(age * 5.0) * 0.08
		return
	_pause_timer -= delta
	if _pause_timer <= 0.0:
		var resting := _tunnels.chamber_role(_current_node) == "rest"
		_pause_timer = _rng.randf_range(4.0, 12.0) if resting else _rng.randf_range(0.6, 3.0)
		_tend_x = INF
		if role == Role.GUARD and _colony != null and _colony.species_id() == "bigheaded" \
				and _tunnels.chamber_role(_current_node) == "food":
			# Pheidole majors use their huge heads and jaws to crack and mill seeds
			var seed_at: Vector2 = _colony.food_position_in(_current_node)
			if seed_at != Vector2.INF:
				_tend_x = seed_at.x
				_milling = true
				_pause_timer = _rng.randf_range(4.0, 9.0)
				_path.append(Vector2(seed_at.x + _rng.randf_range(-6.0, 6.0),
						_tunnels.chamber_floor_y(_current_node) - _half_height))
				return
		_milling = false
		_helping = false
		if role == Role.NURSE and _colony != null and _rng.randf() < 0.85:
			var emerging: Vector2 = _colony.emerging_pupa_in(_current_node)
			if emerging != Vector2.INF:
				_tend_x = emerging.x
				_helping = true
				_pause_timer = _rng.randf_range(3.0, 6.0)
				_colony.help_emerge(emerging)
				_path.append(Vector2(emerging.x + _rng.randf_range(-5.0, 5.0),
						_tunnels.chamber_floor_y(_current_node) - _half_height))
				return
		if _rng.randf() < 0.12 and role != Role.ALATE:
			# ants groom themselves often: forelegs comb the antennae and are cleaned in turn
			_groom_left = _rng.randf_range(2.0, 4.0)
			_groom_mode = GROOM_SELF
			return
		if role == Role.NURSE and _colony != null and _rng.randf() < 0.75:
			# idle nurses groom and lick the brood: go to one and work over it
			var brood_at: Vector2 = _colony.brood_position_in(_current_node)
			if brood_at != Vector2.INF:
				_tend_x = brood_at.x
				_pause_timer = _rng.randf_range(2.5, 6.0)
				_path.append(Vector2(brood_at.x + _rng.randf_range(-7.0, 7.0),
						_tunnels.chamber_floor_y(_current_node) - _half_height))
				return
		if _tunnels.is_chamber(_current_node) and _rng.randf() < (0.3 if resting else 0.65):
			_path.append(_tunnels.random_floor_point(_current_node, _rng, _half_height))
	elif _tend_x != INF:
		var dx := _tend_x - position.x
		if absf(dx) > 0.5 and (dx < 0.0) != _facing_left:
			_facing_left = dx < 0.0
			_sprite.flip_h = _facing_left
		_sprite.rotation = sin(age * 6.0) * 0.1  # head working over the brood


var _warmth_cache := 1.0
var _warmth_clock := 0.0


## Speed factor from the temperature where the ant is (refreshed a few times a second).
func _warmth() -> float:
	if _colony == null or _colony.climate == null:
		return 1.0
	_warmth_clock -= get_process_delta_time()
	if _warmth_clock <= 0.0:
		_warmth_clock = 0.4
		_warmth_cache = Climate.activity(_colony.temperature_at(position.y))
	return _warmth_cache


## Old age: the ant stops where it is and dies; nestmates will carry the body out.
func _die() -> void:
	if _attending:
		_attending = false
		_colony.leave_retinue()
	_colony.ant_died(position, _current_node, _frames[0])
	queue_free()


func _start_surface_trip() -> void:
	state = State.FORAGE_SURFACE
	if age > lifespan * 0.92 and not _departing:
		depart()  # most old foragers die out on a trip and never come home
	_returning = false
	_state_timer = _rng.randf_range(10.0, 24.0)
	_pause_timer = 0.0
	_path.append(Vector2(position.x, _ground_y - _half_height))
	if _food_target != null and is_instance_valid(_food_target):
		_state_timer = 60.0  # straight to the food, then home
		_path.append(Vector2(_food_target.position.x + _rng.randf_range(-6.0, 6.0), _ground_y - _half_height))
	elif _to_mob and _colony != null and _colony.threat != null:
		_state_timer = 20.0
		_path.append(Vector2(_colony.threat.position.x + _rng.randf_range(-12.0, 12.0), _ground_y - _half_height))
	elif _colony != null and not is_nan(_colony.skirmish_x) and role in [Role.FORAGER, Role.WORKER] \
			and (_to_fight or _rng.randf() < 0.6):
		_to_fight = true
		_state_timer = 20.0
		_path.append(Vector2(_fight_spot(), _ground_y - _half_height))
	elif _colony != null and not is_nan(_colony.aphid_x) and not _colony.winter \
			and role in [Role.FORAGER, Role.WORKER] and _rng.randf() < 0.4:
		# garden ants herd aphids on a nearby plant and milk them for honeydew
		_to_aphids = true
		_state_timer = 60.0
		_path.append(Vector2(_colony.aphid_x + _rng.randf_range(-5.0, 5.0), _ground_y - _half_height))


func _update_surface(delta: float) -> void:
	_state_timer -= delta
	if _colony != null and (_colony.raining or _colony.winter or not _colony.forage_ok) \
			and not _returning and not _departing:
		# rain: drop whatever it was doing and hurry home
		_food_target = null
		_harvest_left = -1.0
		_to_aphids = false
		_aphid_left = -1.0
		_to_fight = false
		_fight_left = -1.0
		_drink_target = null
		_drink_left = -1.0
		_to_mob = false
		_mob_left = -1.0
		_path.clear()
		_state_timer = 0.0
	if not _follow_path(delta):
		return
	if _to_aphids and not _returning and _update_aphids(delta):
		return
	if _to_fight and not _returning and _update_fight(delta):
		return
	if _to_mob and not _returning and _update_mob(delta):
		return
	if _drink_target != null and not _returning and _update_drink(delta):
		return
	if not _returning and _food_target != null and _update_harvest(delta):
		return
	if _returning:
		_returning = false
		var found := _task
		_task = {}
		if not found.is_empty():
			_start_task(found)
			return
		var goal := _choose_destination()
		if _tunnels.is_entrance(goal):  # never bounce straight back out
			goal = _tunnels.queen_chamber()
		_travel_to(goal)
		return
	if _state_timer <= 0.0:
		if _departing:
			_leave_for_good()
			return
		_returning = true
		# now and then a forager comes back with something small it found off-screen;
		# most food comes from piles you can see
		if role == Role.FORAGER and _colony != null and _task.is_empty() and _rng.randf() < 0.45:
			var find := _colony.forage_task()  # it found something worth carrying home
			if not find.is_empty():
				_hold(find["item"])
				_task = find
		_current_node = _tunnels.nearest_entrance(position.x)  # home through the closest opening
		var entrance := _tunnels.nodes[_current_node]
		_path.append(Vector2(entrance.x, _ground_y - _half_height))
		_path.append(entrance)
		return
	_pause_timer -= delta
	if _pause_timer <= 0.0:
		_pause_timer = _rng.randf_range(0.3, 1.8)
		if _colony != null and _colony.threat != null and role != Role.NURSE \
				and absf(_colony.threat.position.x - position.x) < 260.0 and _rng.randf() < 0.6:
			_to_mob = true  # an intruder near the nest: go for it
			_path.append(Vector2(_colony.threat.position.x + _rng.randf_range(-12.0, 12.0), _ground_y - _half_height))
			return
		if _colony != null and _colony.water != null and not has_crop() and _drink_target == null \
				and _rng.randf() < 0.5:
			var drop: Node2D = _colony.water.nearest(position.x, 220.0)
			if drop != null:
				_drink_target = drop  # thirsty: water beading on the grass after rain
				_path.append(Vector2(drop.position.x + _rng.randf_range(-4.0, 4.0), _ground_y - _half_height))
				return
		var sensed: Node2D = _colony.sense_food(position.x) if _colony != null and role != Role.NURSE else null
		if sensed != null:
			_food_target = sensed  # caught the scent of something good
			_state_timer = maxf(_state_timer, 40.0)
			_path.append(Vector2(sensed.position.x + _rng.randf_range(-6.0, 6.0), _ground_y - _half_height))
			return
		var x := clampf(position.x + _rng.randf_range(-SURFACE_STEP, SURFACE_STEP),
				_surface_x_range.x, _surface_x_range.y)
		_path.append(Vector2(x, _ground_y - _half_height))


## At the food: cut or drink for a moment, then take a crumb and head home.
## Returns true while the ant is busy with it.
func _update_harvest(delta: float) -> bool:
	if not is_instance_valid(_food_target) or _food_target.is_empty():
		_food_target = null
		_harvest_left = -1.0
		return false
	if absf(position.x - _food_target.position.x) > 12.0:
		_path.append(Vector2(_food_target.position.x + _rng.randf_range(-6.0, 6.0), _ground_y - _half_height))
		return true
	if _harvest_left < 0.0:
		_harvest_left = _food_target.harvest_time() * _rng.randf_range(0.8, 1.3)
		_facing_left = _food_target.position.x < position.x
		_sprite.flip_h = _facing_left
		_sprite.rotation = 0.0
	_harvest_left -= delta
	if _harvest_left > 0.0:
		return true
	_harvest_left = -1.0
	var food := _food_target
	_food_target = null
	if food.take_crumb():
		fill_crop()  # it drank or nibbled while gathering
		_colony.report_find(food)
		var task := _colony.crumb_task(food.kind)
		_hold(task["item"])
		_task = task
		_state_timer = 0.0  # head straight home with it
	return false


## At the aphid plant: stroke the aphids with the antennae until they release honeydew,
## drink it into the crop, then head home to share it. Returns true while busy.
func _update_aphids(delta: float) -> bool:
	if absf(position.x - _colony.aphid_x) > 10.0 and _aphid_left < 0.0:
		_path.append(Vector2(_colony.aphid_x + _rng.randf_range(-5.0, 5.0), _ground_y - _half_height))
		return true
	if _aphid_left < 0.0:
		_aphid_left = _rng.randf_range(6.0, 12.0)
		_facing_left = _colony.aphid_x < position.x
		_sprite.flip_h = _facing_left
		_sprite.rotation = 0.0
	_aphid_left -= delta
	if _aphid_left > 0.0:
		return true
	_aphid_left = -1.0
	_to_aphids = false
	fill_crop()
	_colony.count("honeydew")
	if _task.is_empty():
		var load := _colony.honeydew_task()  # the honeydew goes into the colony's stores
		if not load.is_empty():
			_hold(load["item"])
			_task = load
	_state_timer = 0.0
	return false


## Mobbing a spider: dash in, bite at its legs, back off, repeat until it bolts.
func _update_mob(delta: float) -> bool:
	var spider := _colony.threat
	if spider == null or not is_instance_valid(spider):
		_to_mob = false
		_mob_left = -1.0
		_sprite.rotation = 0.0
		_state_timer = minf(_state_timer, 3.0)
		return false
	_state_timer = maxf(_state_timer, 5.0)
	if absf(position.x - spider.position.x) > 16.0:
		_mob_left = -1.0
		_path.append(Vector2(spider.position.x + _rng.randf_range(-12.0, 12.0), _ground_y - _half_height))
		return true
	if _mob_left < 0.0:
		_mob_left = _rng.randf_range(1.5, 3.5)
	_facing_left = spider.position.x < position.x
	_sprite.flip_h = _facing_left
	_sprite.rotation = sin(age * 16.0) * 0.3  # lunging and biting
	spider.harass(delta)
	_mob_left -= delta
	if _mob_left <= 0.0:
		_mob_left = -1.0
		_sprite.rotation = 0.0
		var back := 14.0 if position.x > spider.position.x else -14.0  # dart back, then go again
		_path.append(Vector2(position.x + back, _ground_y - _half_height))
	return true


## At a rain drop: drink for a few seconds, filling the crop to share at home.
func _update_drink(delta: float) -> bool:
	if not is_instance_valid(_drink_target):
		_drink_target = null
		_drink_left = -1.0
		return false
	if _drink_left < 0.0:
		if absf(position.x - _drink_target.position.x) > 8.0:
			_path.append(Vector2(_drink_target.position.x, _ground_y - _half_height))
			return true
		_drink_left = _rng.randf_range(2.0, 4.0)
		_facing_left = _drink_target.position.x < position.x
		_sprite.flip_h = _facing_left
		_sprite.rotation = 0.15 if _facing_left else -0.15  # head down to the water
	_drink_left -= delta
	if _drink_left > 0.0:
		return true
	_drink_left = -1.0
	_sprite.rotation = 0.0
	_colony.water.sip(_drink_target)
	_drink_target = null
	fill_crop()
	_colony.count("drank")
	return false


## A spot on this colony's side of the border where rival workers are pushing in.
func _fight_spot() -> float:
	var home_side := 1.0 if _colony.skirmish_x < 640.0 else -1.0
	return _colony.skirmish_x + home_side * _rng.randf_range(-6.0, 20.0)


## Pavement-ant border fight: grapple a rival for a few seconds, let go, find another,
## until the rivals withdraw. Returns true while the ant is still at the border.
func _update_fight(delta: float) -> bool:
	if is_nan(_colony.skirmish_x):  # it's over: everyone goes home
		_to_fight = false
		_fight_left = -1.0
		_sprite.rotation = 0.0
		_state_timer = minf(_state_timer, 2.0)
		return false
	_state_timer = maxf(_state_timer, 5.0)
	if _fight_left < 0.0:
		if absf(position.x - _colony.skirmish_x) > 30.0:
			_path.append(Vector2(_fight_spot(), _ground_y - _half_height))
			return true
		_fight_left = _rng.randf_range(4.0, 9.0)
		_facing_left = _colony.skirmish_x < position.x
		_sprite.flip_h = _facing_left
	_fight_left -= delta
	_sprite.rotation = sin(age * 13.0) * 0.22  # locked mandible to mandible, twisting
	position.x += sin(age * 9.0) * 8.0 * delta
	if _fight_left <= 0.0:
		_fight_left = -1.0
		_sprite.rotation = 0.0
		_path.append(Vector2(_fight_spot(), _ground_y - _half_height))
	return true


## Walks off the edge of the world and is removed (colony turnover once it is full).
func _leave_for_good() -> void:
	state = State.LEAVING
	var edge := -40.0 if position.x < 640.0 else 1320.0
	_path.append(Vector2(edge, _ground_y - _half_height))


# ---------------------------------------------------------------------------
# Movement and animation
# ---------------------------------------------------------------------------

## Advances along _path; returns true once the path is empty.
func _follow_path(delta: float) -> bool:
	_moving = false
	var step := _speed * delta * _warmth()  # cold-blooded: slow in the cold, brisk in the warm
	while step > 0.0 and not _path.is_empty():
		var to_target := _path[0] - position
		var dist := to_target.length()
		if dist <= step:
			position = _path[0]
			step -= dist
			_path.remove_at(0)
		else:
			var dir := to_target / dist
			position += dir * step
			_face(dir, delta)
			_moving = true
			step = 0.0
	return _path.is_empty()


## Sprite art faces right. Mirror it for leftward travel so the ant never walks upside down.
func _face(dir: Vector2, delta: float) -> void:
	if absf(dir.x) > 0.25:
		var left := dir.x < 0.0
		if left != _facing_left:
			_facing_left = left
			_sprite.flip_h = left
			_sprite.rotation = _angle_for(dir)
			return
	_sprite.rotation = lerp_angle(_sprite.rotation, _angle_for(dir), clampf(delta * TURN_RATE, 0.0, 1.0))


func _angle_for(dir: Vector2) -> float:
	return (-dir).angle() if _facing_left else dir.angle()


func _animate(delta: float) -> void:
	if not _moving:
		return
	_frame_clock += delta * (_speed / BASE_SPEED)
	if _frame_clock >= FRAME_TIME:
		_frame_clock -= FRAME_TIME
		_frame = (_frame + 1) % _frames.size()
		_sprite.texture = _frames[_frame]
