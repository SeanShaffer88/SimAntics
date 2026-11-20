extends Node
## Colony life cycle and division of labour.
##
## The queen lays eggs beside her. Nurses carry eggs to the nursery egg pile; eggs
## hatch into larvae, which nurses move to the larva pile and feed (seeds, prey, or
## fungus picked from the garden for leafcutters). Well-fed larvae pupate (spinning
## cocoons in Formicinae) and are moved to the pupa pile; pupae emerge as pale callow
## workers. Feeding leaves husks and scraps that nest workers haul to the refuse heap,
## and foragers restock the stores from the surface.
##
## Times are compressed for watching: real development takes weeks.

signal worker_emerged(position: Vector2, chamber: int)

const ColonyArt := preload("res://scripts/colony_art.gd")
const Tunnels := preload("res://scripts/subterranean_layer.gd")

enum Stage { EGG, LARVA, PUPA }

const EGG_TIME := Vector2(60.0, 90.0)
const LARVA_MIN_TIME := 80.0
const FEEDS_TO_PUPATE := 3
const PUPA_TIME := Vector2(90.0, 130.0)
const LAY_INTERVAL := Vector2(10.0, 20.0)
const MAX_QUEEN_EGGS := 14
const MAX_BROOD := 60
const MAX_FOOD_PER_CHAMBER := 110
const MAX_LOOSE_WASTE := 40
const MAX_REFUSE_ITEMS := 60


class Brood:
	var stage := 0
	var age := 0.0
	var duration := 0.0
	var fed := 0
	var chamber := -1
	var zone := ""
	var sprite: Sprite2D
	var reserved := false  # a nurse is on its way to carry or feed it
	var carried := false

	func wants_zone() -> String:
		match stage:
			Stage.EGG:
				return "eggs"
			Stage.LARVA:
				return "larvae"
		return "pupae"


var brood: Array[Brood] = []
var max_workers := 30
var population := 0  # current worker count, kept up to date by Main
var surface_tint := Color.WHITE  # daylight colour, set by the day/night cycle
var night := false  # fewer ants go out after dark
var stats := {}  # job counters, handy for tuning: "<type>_given" / "<type>_done"

var _tunnels: Tunnels
var _species: Dictionary
var _rng := RandomNumberGenerator.new()
var _lay_timer := 0.0
var _nurseries: Array[int] = []
var _pupa_rooms: Array[int] = []
var _waste: Array[Sprite2D] = []  # loose waste waiting to be hauled
var _waste_chamber: Dictionary = {}  # sprite instance id -> chamber id
var _refuse: Array[Sprite2D] = []  # waste already dumped on the refuse heap


## `saved`: this colony's state from a previous session (see to_save()), or empty for a new colony.
func setup(tunnels: Tunnels, species: Dictionary, seed_value: int, worker_cap: int, saved: Dictionary = {}) -> void:
	_tunnels = tunnels
	_species = species
	_rng.seed = seed_value + 404
	max_workers = worker_cap
	_nurseries = _tunnels.chambers_with_role("nursery")
	_pupa_rooms = _tunnels.chambers_with_role("pupae")
	_lay_timer = _rng.randf_range(LAY_INTERVAL.x, LAY_INTERVAL.y)
	if saved.is_empty():
		_seed_initial_brood()
	else:
		_restore(saved)


func _seed_initial_brood() -> void:
	var queen := _tunnels.queen_chamber()
	for i in 8:
		_add_brood(Stage.EGG, queen, "queen_eggs", _rng.randf_range(0.0, EGG_TIME.x))
	for nursery in _nurseries:
		for i in 8:
			_add_brood(Stage.EGG, nursery, "eggs", _rng.randf_range(0.0, EGG_TIME.x))
		for i in 7:
			var larva := _add_brood(Stage.LARVA, nursery, "larvae", _rng.randf_range(0.0, LARVA_MIN_TIME))
			larva.fed = _rng.randi_range(0, FEEDS_TO_PUPATE - 1)
			_refresh_texture(larva)
		for i in 5:
			_add_brood(Stage.PUPA, _pupa_home(nursery), "pupae", _rng.randf_range(0.0, PUPA_TIME.x))


## Where a pupa belongs: the pupa chamber if the nest has one, otherwise its nursery.
func _pupa_home(fallback: int) -> int:
	if _pupa_rooms.is_empty():
		return fallback
	return _pupa_rooms[_rng.randi() % _pupa_rooms.size()]


func _in_brood_chamber(b: Brood) -> bool:
	return _nurseries.has(b.chamber) or _pupa_rooms.has(b.chamber)


func _misplaced(b: Brood) -> bool:
	if b.zone != b.wants_zone():
		return true
	# pupae go to their own chamber; eggs and larvae stay in the nurseries
	if not _pupa_rooms.is_empty():
		return _pupa_rooms.has(b.chamber) != (b.stage == Stage.PUPA)
	return false


func _add_brood(stage: Stage, chamber: int, zone: String, age: float) -> Brood:
	var b := Brood.new()
	b.stage = stage
	b.age = age
	b.duration = _duration_for(stage)
	b.chamber = chamber
	b.zone = zone
	b.sprite = _tunnels.add_item(ColonyArt.egg(), _tunnels.zone_spot(chamber, zone), "brood")
	brood.append(b)
	_refresh_texture(b)
	return b


func _duration_for(stage: int) -> float:
	match stage:
		Stage.EGG:
			return _rng.randf_range(EGG_TIME.x, EGG_TIME.y)
		Stage.PUPA:
			return _rng.randf_range(PUPA_TIME.x, PUPA_TIME.y)
	return LARVA_MIN_TIME


func _refresh_texture(b: Brood) -> void:
	match b.stage:
		Stage.EGG:
			b.sprite.texture = ColonyArt.egg()
		Stage.LARVA:
			b.sprite.texture = ColonyArt.larva(mini(b.fed, 2))  # larvae visibly grow with each meal
		Stage.PUPA:
			b.sprite.texture = ColonyArt.pupa(_species["cocoons"])
	b.sprite.offset = Vector2(0.0, -b.sprite.texture.get_height() * 0.5)


# ---------------------------------------------------------------------------
# Development
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _tunnels == null:
		return
	_lay_timer -= delta
	if _lay_timer <= 0.0:
		# A full colony keeps raising brood at half pace; old foragers leaving keeps its size steady.
		var slow := 2.0 if population >= max_workers else 1.0
		_lay_timer = _rng.randf_range(LAY_INTERVAL.x, LAY_INTERVAL.y) * slow
		# Laying tracks how well the brood is being fed: with a backlog of hungry
		# larvae the nurses feed her less and she lays less.
		if _count_in_zone("queen_eggs") < MAX_QUEEN_EGGS and brood.size() < MAX_BROOD \
				and _hungry_larvae() < 16:
			_add_brood(Stage.EGG, _tunnels.queen_chamber(), "queen_eggs", 0.0)
			_tunnels.queen_lay_pulse()

	for b in brood.duplicate():
		b.age += delta
		if b.carried:
			continue
		match b.stage:
			Stage.EGG:
				if b.age >= b.duration:
					_advance(b, Stage.LARVA)
			Stage.LARVA:
				if b.fed >= FEEDS_TO_PUPATE and b.age >= b.duration:
					_advance(b, Stage.PUPA)
			Stage.PUPA:
				if b.age >= b.duration and not b.reserved:
					_emerge(b)


func _advance(b: Brood, stage: Stage) -> void:
	b.stage = stage
	b.age = 0.0
	b.duration = _duration_for(stage)
	_refresh_texture(b)


func _emerge(b: Brood) -> void:
	brood.erase(b)
	var pos := b.sprite.position
	b.sprite.queue_free()
	worker_emerged.emit(pos, b.chamber)


func _count_in_zone(zone: String) -> int:
	var n := 0
	for b in brood:
		if b.zone == zone and not b.carried:
			n += 1
	return n


# ---------------------------------------------------------------------------
# Task board. A task is a Dictionary:
#   type: "brood" | "feed" | "waste" | "store"
#   pickup_node, drop_node: chamber ids;  pickup_pos: Vector2 (where the ant stands)
# ---------------------------------------------------------------------------

## Offers a nurse a job. Brood by the queen is collected first; otherwise nurses mostly
## feed larvae and sometimes re-sort brood into the right pile.
func nurse_task() -> Dictionary:
	var by_queen: Array[Brood] = []
	var misplaced: Array[Brood] = []
	var hungry: Array[Brood] = []
	for b in brood:
		if b.reserved or b.carried:
			continue
		if not _in_brood_chamber(b):
			by_queen.append(b)
		elif _misplaced(b):
			misplaced.append(b)
		if b.stage == Stage.LARVA and b.fed < FEEDS_TO_PUPATE and _nurseries.has(b.chamber):
			hungry.append(b)
	if not by_queen.is_empty():
		return _move_task(by_queen[0])
	if not hungry.is_empty() and (misplaced.is_empty() or _rng.randf() < 0.6):
		var feed := _feed_task(hungry[_rng.randi() % hungry.size()])
		if not feed.is_empty():
			return feed
	if not misplaced.is_empty():
		return _move_task(misplaced[_rng.randi() % misplaced.size()])
	return {}


## True when the brood needs more hands than the nurses provide; older workers then
## help with nursing (real colonies shift workers between tasks by demand).
func needs_nurses() -> bool:
	return _hungry_larvae() > 8


func _hungry_larvae() -> int:
	var hungry := 0
	for b in brood:
		if b.stage == Stage.LARVA and b.fed < FEEDS_TO_PUPATE and not b.reserved:
			hungry += 1
	return hungry


func _move_task(b: Brood) -> Dictionary:
	var target: int
	if b.stage == Stage.PUPA and not _pupa_rooms.is_empty():
		target = b.chamber if _pupa_rooms.has(b.chamber) else _pupa_home(-1)
	else:
		target = b.chamber if _nurseries.has(b.chamber) else _nurseries[_rng.randi() % _nurseries.size()]
	b.reserved = true
	return {"type": "brood", "brood": b, "pickup_node": b.chamber, "pickup_pos": b.sprite.position,
			"drop_node": target, "zone": b.wants_zone()}


func _feed_task(larva: Brood) -> Dictionary:
	var source := _food_source()
	if source.is_empty():
		return {}
	larva.reserved = true
	source["type"] = "feed"
	source["brood"] = larva
	source["drop_node"] = larva.chamber
	return source


## Where nurses fetch food: a stored item, or a tuft of fungus from a garden.
func _food_source() -> Dictionary:
	if _species["food"] == "fungus":
		var gardens := _tunnels.chambers_with_role("fungus")
		if gardens.is_empty():
			return {}
		var g: int = gardens[_rng.randi() % gardens.size()]
		return {"pickup_node": g, "pickup_pos": _tunnels.zone_spot(g, "")}
	var stores: Array[int] = []
	for id: int in _tunnels.food_items:
		if not (_tunnels.food_items[id] as Array).is_empty():
			stores.append(id)
	if stores.is_empty():
		return {}
	var store: int = stores[_rng.randi() % stores.size()]
	var items: Array = _tunnels.food_items[store]
	var item: Sprite2D = items.pop_back()  # take from the top of the heap
	return {"pickup_node": store, "pickup_pos": item.position, "food": item}


## Offers a nest worker a job hauling waste to the refuse chamber.
func waste_task() -> Dictionary:
	var dumps := _tunnels.chambers_with_role("refuse")
	if _waste.is_empty() or dumps.is_empty():
		return {}
	var item: Sprite2D = _waste.pop_front()
	var chamber: int = _waste_chamber.get(item.get_instance_id(), -1)
	_waste_chamber.erase(item.get_instance_id())
	if chamber == -1:
		item.queue_free()
		return {}
	return {"type": "waste", "item": item, "pickup_node": chamber, "pickup_pos": item.position,
			"drop_node": dumps[0], "zone": "refuse"}


## A forager coming home finds food on the surface; returns its task and the item to carry.
func forage_task() -> Dictionary:
	var targets := _tunnels.chambers_with_role("fungus" if _species["food"] == "fungus" else "food")
	if targets.is_empty():
		return {}
	var target: int = targets[_rng.randi() % targets.size()]
	var item := _tunnels.add_item(_tunnels.food_texture(_species), Vector2.ZERO, "food")
	return {"type": "store", "item": item, "drop_node": target, "zone": "food"}


## The ant has reached the pickup spot: returns the sprite it now carries, or null if
## the job no longer makes sense.
func pick_up(task: Dictionary) -> Sprite2D:
	match task["type"]:
		"brood":
			var b: Brood = task["brood"]
			if not brood.has(b):
				return null
			b.carried = true
			return b.sprite
		"feed":
			if not brood.has(task["brood"]):
				release(task)
				return null
			if task.has("food"):
				return task["food"]
			return _tunnels.add_item(ColonyArt.fungus_crumb(), Vector2.ZERO, "food")
		"waste":
			return task["item"]
	return null


## Where the carried item should be put down.
func drop_position(task: Dictionary) -> Vector2:
	if task["type"] == "feed":
		var b: Brood = task["brood"]
		return b.sprite.position
	return _tunnels.zone_spot(task["drop_node"], task["zone"])


## Tallies a job event in `stats`.
func count(key: String) -> void:
	stats[key] = stats.get(key, 0) + 1


## The ant has arrived with its load.
func drop(task: Dictionary, carried: Sprite2D, at: Vector2) -> void:
	count(task["type"] + "_done")
	match task["type"]:
		"brood":
			var b: Brood = task["brood"]
			b.carried = false
			b.reserved = false
			b.chamber = task["drop_node"]
			b.zone = task["zone"]
			_tunnels.place_item(carried, at)
		"feed":
			var b: Brood = task["brood"]
			carried.queue_free()
			b.reserved = false
			if brood.has(b) and b.stage == Stage.LARVA:
				b.fed += 1
				_refresh_texture(b)
			_leave_waste(b.chamber, at)
		"waste":
			_tunnels.place_item(carried, at)
			_refuse.append(carried)
			while _refuse.size() > MAX_REFUSE_ITEMS:  # older waste packs down into the heap
				_refuse.pop_front().queue_free()
		"store":
			var target: int = task["drop_node"]
			_tunnels.place_item(carried, at)
			if _tunnels.food_items.has(target):
				var store: Array = _tunnels.food_items[target]
				store.append(carried)
				while store.size() > MAX_FOOD_PER_CHAMBER:
					store.pop_front().queue_free()
			else:
				# leaf fragments are chewed into the fungus garden
				var fade := carried.create_tween()
				fade.tween_interval(_rng.randf_range(20.0, 40.0))
				fade.tween_property(carried, "modulate:a", 0.0, 4.0)
				fade.tween_callback(carried.queue_free)


## Called when an ant gives up a job before collecting the item.
func release(task: Dictionary) -> void:
	if task.has("brood"):
		var b: Brood = task["brood"]
		b.reserved = false
		b.carried = false
	if task.get("type") == "feed" and task.has("food") and _tunnels.food_items.has(task["pickup_node"]):
		(_tunnels.food_items[task["pickup_node"]] as Array).append(task["food"])


## `always`: place it regardless of chance (used when restoring a save).
func _leave_waste(chamber: int, at: Vector2, always: bool = false) -> void:
	if (not always and _rng.randf() > 0.6) or _waste.size() >= MAX_LOOSE_WASTE:
		return
	var tex := ColonyArt.waste_bit(_species["food"], _rng.randi_range(0, 1))
	var floor_y := _tunnels.chamber_floor_y(chamber)
	var item := _tunnels.add_item(tex, Vector2(at.x + _rng.randf_range(-8.0, 8.0), floor_y), "waste")
	_waste.append(item)
	_waste_chamber[item.get_instance_id()] = chamber


# ---------------------------------------------------------------------------
# Saving, restoring and catching up on time away
# ---------------------------------------------------------------------------

const MAX_CATCH_UP := 8.0 * 3600.0  # never simulate more than 8 hours of absence
const CATCH_UP_STEP := 5.0


func to_save() -> Dictionary:
	var saved_brood := []
	for b in brood:
		saved_brood.append({"stage": b.stage, "age": b.age, "duration": b.duration, "fed": b.fed,
				"chamber": b.chamber, "zone": b.zone})
	var waste_chambers := []
	for item in _waste:
		waste_chambers.append(_waste_chamber.get(item.get_instance_id(), -1))
	var food := {}
	for id: int in _tunnels.food_items:
		food[str(id)] = (_tunnels.food_items[id] as Array).size()
	return {"brood": saved_brood, "waste": waste_chambers, "food": food, "lay_timer": _lay_timer,
			"stats": stats}


func _restore(saved: Dictionary) -> void:
	for entry: Dictionary in saved.get("brood", []):
		var stage := int(entry["stage"])
		var chamber := int(entry["chamber"])
		var zone: String = entry["zone"]
		if not _tunnels.chambers.has(chamber):  # the layout changed since the save
			chamber = _nurseries[0]
			zone = ["eggs", "larvae", "pupae"][stage]
		var b := _add_brood(stage, chamber, zone, float(entry["age"]))
		b.duration = float(entry["duration"])
		b.fed = int(entry["fed"])
		_refresh_texture(b)
	for chamber in saved.get("waste", []):
		if _tunnels.chambers.has(int(chamber)):
			var c: Dictionary = _tunnels.chambers[int(chamber)]
			_leave_waste(int(chamber), Vector2(_rng.randf_range(c["floor_left"], c["floor_right"]), 0.0), true)
	var food: Dictionary = saved.get("food", {})
	for key: String in food:
		_tunnels.set_food_count(int(key), int(food[key]), _species)
	_lay_timer = float(saved.get("lay_timer", _lay_timer))
	stats = saved.get("stats", {})


## Simulates `seconds` of colony life in coarse steps while the app was closed:
## brood develops, nurses (`carers` of them) keep feeding larvae, the queen keeps
## laying, and pupae emerge. Returns {"emerged": [{chamber, age}], "laid": int}.
func fast_forward(seconds: float, carers: int) -> Dictionary:
	var emerged: Array[Dictionary] = []
	var laid := 0
	var steps := int(minf(seconds, MAX_CATCH_UP) / CATCH_UP_STEP)
	var feed_budget := 0.0
	for s in steps:
		var remaining := (steps - s) * CATCH_UP_STEP  # how long ago this step was
		feed_budget = minf(feed_budget + carers * CATCH_UP_STEP / 35.0, 6.0)
		for b in brood.duplicate():
			b.age += CATCH_UP_STEP
			match b.stage:
				Stage.EGG:
					if b.age >= b.duration:
						_advance(b, Stage.LARVA)
						_relocate(b)
				Stage.LARVA:
					if b.fed < FEEDS_TO_PUPATE and feed_budget >= 1.0:
						b.fed += 1
						feed_budget -= 1.0
						_refresh_texture(b)
					if b.fed >= FEEDS_TO_PUPATE and b.age >= b.duration:
						_advance(b, Stage.PUPA)
						_relocate(b)
				Stage.PUPA:
					if b.age >= b.duration:
						brood.erase(b)
						b.sprite.queue_free()
						emerged.append({"chamber": b.chamber, "age": remaining})
		_lay_timer -= CATCH_UP_STEP
		if _lay_timer <= 0.0:
			_lay_timer = _rng.randf_range(LAY_INTERVAL.x, LAY_INTERVAL.y)
			if brood.size() < MAX_BROOD and _hungry_larvae() < 16:
				# nurses would long since have carried it to a nursery
				var nursery: int = _nurseries[_rng.randi() % _nurseries.size()]
				_add_brood(Stage.EGG, nursery, "eggs", 0.0)
				laid += 1
	return {"emerged": emerged, "laid": laid}


## Puts brood straight into the pile it belongs in (used while catching up).
func _relocate(b: Brood) -> void:
	if b.stage == Stage.PUPA and not _pupa_rooms.is_empty():
		if not _pupa_rooms.has(b.chamber):
			b.chamber = _pupa_home(-1)
	elif not _nurseries.has(b.chamber):
		b.chamber = _nurseries[_rng.randi() % _nurseries.size()]
	b.zone = b.wants_zone()
	b.sprite.position = _tunnels.zone_spot(b.chamber, b.zone).round()


# ---------------------------------------------------------------------------
# Food the player drops on the surface
# ---------------------------------------------------------------------------

var clusters: Array[Node2D] = []
var _recruits: Dictionary = {}  # cluster instance id -> nestmates still to send


func add_cluster(cluster: Node2D) -> void:
	clusters.append(cluster)
	cluster.tree_exiting.connect(func():
		clusters.erase(cluster)
		_recruits.erase(cluster.get_instance_id()))


## The most tempting food a surface ant at `x` can sense, or null. Stronger foods are
## noticed from further away and win over closer, plainer ones.
func sense_food(x: float) -> Node2D:
	var best: Node2D = null
	var best_score := 0.0
	for c in clusters:
		if not is_instance_valid(c) or c.is_empty():
			continue
		var reach: float = 170.0 + 360.0 * c.pull()
		var dist := absf(c.position.x - x)
		if dist > reach:
			continue
		var score: float = c.pull() / (1.0 + dist / 200.0)
		if score > best_score:
			best_score = score
			best = c
	return best


## A forager came home with a crumb: its trail recruits more nestmates to that food.
func report_find(cluster: Node2D) -> void:
	var id := cluster.get_instance_id()
	_recruits[id] = mini(int(_recruits.get(id, 0)) + cluster.recruits_per_trip(), cluster.crumbs)


## A food that still needs hands, for an ant leaving the nest, or null.
func take_recruit() -> Node2D:
	if night:
		return null
	var options: Array[Node2D] = []
	for c in clusters:
		if is_instance_valid(c) and not c.is_empty() and int(_recruits.get(c.get_instance_id(), 0)) > 0:
			options.append(c)
	if options.is_empty():
		return null
	options.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.pull() > b.pull())
	var pick := options[0]
	_recruits[pick.get_instance_id()] = int(_recruits[pick.get_instance_id()]) - 1
	return pick


## The crumb an ant carries home from a food drop, and where it goes.
func crumb_task(kind: String) -> Dictionary:
	var targets := _tunnels.chambers_with_role("fungus" if _species["food"] == "fungus" else "food")
	if targets.is_empty():
		targets = _tunnels.chambers_with_role("nursery")
	var item := _tunnels.add_item(ColonyArt.food_crumb(kind, _rng.randi_range(0, 2)), Vector2.ZERO, "food")
	count("crumb_" + kind)
	return {"type": "store", "item": item, "drop_node": targets[_rng.randi() % targets.size()], "zone": "food"}
