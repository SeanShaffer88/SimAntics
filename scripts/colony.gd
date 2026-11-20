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
signal note(text: String, key: String)  # something worth a field note
signal corpse_dumped(x: float, texture: Texture2D)  # a dead ant left outside on the midden

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
const RESERVE_FEED_INTERVAL := 25.0  # how often a founding queen feeds a larva from her own body
const DIG_TIME := Vector2(1.8, 2.8)  # seconds an ant spends chewing out one pellet of soil
## What each food provides once stored.
const NUTRIENTS := {"sugar": "sugar", "nectar": "sugar", "fruit": "sugar", "protein": "protein",
		"insects": "protein", "seeds": "both", "leaves": "both"}
const SMALL_COLONY := 10  # below this many workers the queen still feeds brood from her reserves


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
var raining := false  # nobody goes out in the rain; food on the surface waits
var winter := false  # the colony overwinters: no laying, brood waits, nobody goes out
var lay_rate := 1.0  # seasonal: higher in spring
var stats := {}  # job counters, handy for tuning: "<type>_given" / "<type>_done"

var _tunnels: Tunnels
var _species: Dictionary
var _rng := RandomNumberGenerator.new()
var _lay_timer := 0.0
var _waste: Array[Sprite2D] = []  # loose waste waiting to be hauled
var _waste_chamber: Dictionary = {}  # sprite instance id -> chamber id
var _refuse: Array[Sprite2D] = []  # waste already dumped on the refuse heap
var _reserve_clock := RESERVE_FEED_INTERVAL
var _upkeep_clock := 60.0

const UPKEEP_INTERVAL := 60.0
const WORKERS_PER_MEAL := 14  # each minute the adults eat one stored item per this many workers


## The adults eat too: each minute a little stored food is used up, leaving waste.
## Stores therefore shrink unless foragers (or the player) keep bringing food in.
func _eat_from_stores() -> void:
	var meals := population / WORKERS_PER_MEAL
	for m in meals:
		var stores: Array[int] = []
		for id: int in _tunnels.food_items:
			if not (_tunnels.food_items[id] as Array).is_empty():
				stores.append(id)
		if stores.is_empty():
			return
		# adult workers run on sugars; they turn to protein only when sugars are gone
		var taken := _take_stored(["sugar", "both"])
		if taken.is_empty():
			taken = _take_stored(["protein"])
			if taken.is_empty():
				return
			count("ate_protein")
			if population >= SMALL_COLONY:
				note.emit("The sugar stores ran out, so the workers are eating protein instead. Sugary food keeps them going.", "no_sugar")
		var item: Sprite2D = taken["item"]
		var at := item.position
		item.queue_free()
		count("eaten")
		_leave_waste(taken["store"], at)
var _dig_claims: Dictionary = {}  # node being dug into -> ants digging it
var _eggs_since_meal := 0
var _clock := 0.0
var _corpses: Array[Dictionary] = []  # dead nestmates waiting to be carried out: sprite, chamber, ready

const EGGS_PER_PROTEIN := 3  # her attendants feed her one protein item for every few eggs


## Egg production runs on protein. A founding queen lives off her own body; after that
## her attendants feed her from the stores, and with no protein she stops laying.
func _queen_fed() -> bool:
	if population < SMALL_COLONY or _species["food"] == "fungus":
		return true  # claustral reserves, or the fungus garden feeds her
	if _eggs_since_meal < EGGS_PER_PROTEIN:
		_eggs_since_meal += 1
		return true
	var taken := _take_stored(["protein", "both"])
	if taken.is_empty():
		count("lay_skipped")
		note.emit("The queen stopped laying: there is no protein in the stores. Dead insects or seeds will start her again.", "queen_no_protein")
		return false
	var item: Sprite2D = taken["item"]
	item.queue_free()
	_eggs_since_meal = 1
	return true


## A worker died of old age in the nest. Its body lies where it fell until the smell of
## decay (oleic acid) builds up, then a nestmate carries it to the refuse pile.
func ant_died(at: Vector2, chamber: int, texture: Texture2D) -> void:
	count("died")
	var floor_y := _tunnels.chamber_floor_y(chamber) if _tunnels.is_chamber(chamber) else at.y + 4.0
	var body := _tunnels.add_item(texture, Vector2(at.x, floor_y), "corpse", 1)
	body.flip_v = true  # on its back, legs curled
	body.modulate = Color(0.55, 0.5, 0.48)
	_corpses.append({"sprite": body, "chamber": chamber, "ready": _clock + _rng.randf_range(20.0, 45.0)})
	note.emit("A worker died of old age. Its nestmates left the body for a while, then carried it to the refuse pile.", "first_death")


## A body that has started to smell, ready to be carried out, as a waste task (or {}).
func _corpse_task() -> Dictionary:
	for i in _corpses.size():
		var c: Dictionary = _corpses[i]
		var body: Sprite2D = c["sprite"]
		if not is_instance_valid(body):
			_corpses.remove_at(i)
			return {}
		if _clock < float(c["ready"]) or not _tunnels.is_chamber(int(c["chamber"])):
			continue
		_corpses.remove_at(i)
		var midden: bool = _species["id"] == "harvester"
		var dumps := _tunnels.chambers_with_role("refuse")
		if dumps.is_empty() and not midden:
			midden = true  # no graveyard chamber yet: out it goes
		var drop: int = _tunnels.nearest_entrance(body.position.x) if midden else dumps[0]
		return {"type": "waste", "item": body, "pickup_node": int(c["chamber"]), "pickup_pos": body.position,
				"drop_node": drop, "zone": "midden" if midden else "refuse"}
	return {}
var _retinue := 0  # nurses currently attending the queen

const RETINUE_SIZE := 4


func describe_queen() -> String:
	var laid := int(stats.get("laid", 0))
	var resting := _count_in_zone("queen_eggs")
	return "The queen  ·  %d eggs laid  ·  %d beside her now" % [laid, resting] if laid > 0 \
			else "The queen  ·  mother of the whole colony"


## The brood item nearest `at` within `radius` px, or null.
func brood_near(at: Vector2, radius: float) -> Brood:
	var best: Brood = null
	var best_d := radius
	for b in brood:
		if b.carried:
			continue
		var d := (b.sprite.position + Vector2(0.0, -2.0)).distance_to(at)
		if d < best_d:
			best_d = d
			best = b
	return best


func describe_brood(b: Brood) -> String:
	match b.stage:
		Stage.EGG:
			return "Egg  ·  hatching soon" if b.age > b.duration * 0.7 else "Egg"
		Stage.LARVA:
			if b.fed >= FEEDS_TO_PUPATE:
				return "Larva  ·  well fed, about to pupate"
			return "Larva  ·  fed %d of %d meals" % [b.fed, FEEDS_TO_PUPATE]
	var kind := "Pupa in its cocoon" if _species["cocoons"] else "Pupa"
	return "%s  ·  emerging soon" % kind if b.age > b.duration * 0.75 else kind


func species_id() -> String:
	return _species["id"]


## A stored food item's position in a chamber (for a major milling seeds), or INF.
func food_position_in(chamber: int) -> Vector2:
	if not _tunnels.food_items.has(chamber):
		return Vector2.INF
	var store: Array = _tunnels.food_items[chamber]
	if store.is_empty():
		return Vector2.INF
	return (store[_rng.randi() % store.size()] as Sprite2D).position


var climate: RefCounted = null  # climate.gd, set by Main
var entrances_closed := false  # sealed for the night or the weather
var plug_work := false  # workers are sealing or reopening the entrances right now
var _sprout_clock := 30.0
var forage_ok := true  # the surface is within this species' foraging temperatures
var ground_y := 120.0
var nest_bottom := 686.0
var threat: Node2D = null  # a spider prowling the surface that the ants will mob, or null
var soil_wetness := 0.0  # 0..1, from recent rain
var water: Node2D = null  # rain drops on the surface (water_drops.gd), or null
var skirmish_x := NAN  # border where pavement ants are fighting a rival colony (NAN if none)
var aphid_x := NAN  # where a garden-ant colony tends its aphids on the surface (NAN if none)


## Where a resting item of brood lies in a chamber (for an idle nurse to groom), or INF.
func brood_position_in(chamber: int) -> Vector2:
	var here: Array[Brood] = []
	for b in brood:
		if b.chamber == chamber and not b.carried:
			here.append(b)
	if here.is_empty():
		return Vector2.INF
	return here[_rng.randi() % here.size()].sprite.position


## Where a pupa nearly ready to emerge lies in a chamber, or INF. Nurses help new adults
## out: they tear open the cocoon (or peel off the pupal skin) and pull the callow free.
func emerging_pupa_in(chamber: int) -> Vector2:
	for b in brood:
		if b.chamber == chamber and b.stage == Stage.PUPA and not b.carried and b.age >= b.duration * 0.8:
			return b.sprite.position
	return Vector2.INF


## A nurse works at an emerging pupa: the help brings emergence a little closer.
func help_emerge(at: Vector2) -> void:
	for b in brood:
		if b.stage == Stage.PUPA and not b.carried and b.sprite.position.distance_to(at) < 3.0:
			b.age += 4.0
			count("helped_emerge")
			return


func cocoons() -> bool:
	return _species["cocoons"]


## A nurse in the queen's chamber asks to join her retinue of attendants.
func join_retinue() -> bool:
	if _retinue >= RETINUE_SIZE:
		return false
	_retinue += 1
	return true


func leave_retinue() -> void:
	_retinue = maxi(0, _retinue - 1)


signal soil_dumped(x: float)
signal food_found(kind: String)
signal midden_dumped(x: float)

## `saved`: this colony's state from a previous session (see to_save()), or empty for a new
## colony. `founding`: a brand-new colony that starts as a queen and her first brood.
func setup(tunnels: Tunnels, species: Dictionary, seed_value: int, worker_cap: int, saved: Dictionary = {},
		founding: bool = false) -> void:
	_tunnels = tunnels
	_species = species
	_rng.seed = seed_value + 404
	max_workers = worker_cap
	_lay_timer = _rng.randf_range(LAY_INTERVAL.x, LAY_INTERVAL.y)
	if saved.is_empty():
		if founding:
			_seed_founding_brood()
		else:
			_seed_initial_brood()
	else:
		_restore(saved)


func _nursery_ids() -> Array[int]:
	return _tunnels.chambers_with_role("nursery")


func _pupa_room_ids() -> Array[int]:
	return _tunnels.chambers_with_role("pupae")


## A founding queen's first clutch, all kept beside her in the founding chamber.
func _seed_founding_brood() -> void:
	var home := _tunnels.queen_chamber()
	for i in 6:
		_add_brood(Stage.EGG, home, "queen_eggs", _rng.randf_range(0.0, EGG_TIME.x))
	for i in 3:
		_add_brood(Stage.LARVA, home, "larvae", _rng.randf_range(0.0, LARVA_MIN_TIME))
	for i in 2:
		_add_brood(Stage.PUPA, home, "pupae", _rng.randf_range(0.0, PUPA_TIME.x))


func _seed_initial_brood() -> void:
	var queen := _tunnels.queen_chamber()
	for i in 8:
		_add_brood(Stage.EGG, queen, "queen_eggs", _rng.randf_range(0.0, EGG_TIME.x))
	for nursery in _nursery_ids():
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
	if _pupa_room_ids().is_empty():
		return fallback
	return _pupa_room_ids()[_rng.randi() % _pupa_room_ids().size()]


func _in_brood_chamber(b: Brood) -> bool:
	return _nursery_ids().has(b.chamber) or _pupa_room_ids().has(b.chamber)


func _misplaced(b: Brood) -> bool:
	if b.zone != b.wants_zone():
		return true
	# pupae go to their own chamber; eggs and larvae stay in the nurseries
	if not _pupa_room_ids().is_empty():
		if _pupa_room_ids().has(b.chamber) != (b.stage == Stage.PUPA):
			return true
	# eggs and larvae follow the warmth: nurses keep them in the warm nursery
	var warm := _warm_nursery()
	if warm != -1 and b.stage != Stage.PUPA and _nursery_ids().has(b.chamber) and b.chamber != warm:
		return true
	return false


## The nursery the brood should be in right now: brood is carried up into warm shallow
## soil by day and back down to the steadier deep soil at night, as real nurses do.
## -1 when the colony has only one nursery.
## The nursery whose temperature is closest to what brood develops best at (about
## 28 deg C). Upper chambers win on warm days, deeper ones on cold nights, so the
## nurses carry the brood up and down with the weather, as real ants do.
func _warm_nursery() -> int:
	var ids := _nursery_ids()
	if ids.size() < 2 or climate == null:
		return -1
	var pick: int = ids[0]
	var best := INF
	for id in ids:
		var miss := absf(temperature_at(_tunnels.nodes[id].y) - BROOD_IDEAL)
		if miss < best - 0.5:  # a clear difference only, so brood is not shuffled back and forth
			best = miss
			pick = id
	return pick


const BROOD_IDEAL := 28.0


## Temperature (deg C) at a height on screen: the ground surface above ground level,
## the soil at that depth below it.
func temperature_at(y: float) -> float:
	if climate == null:
		return 20.0
	if y <= ground_y + 2.0:
		return climate.surface
	return climate.at_depth((y - ground_y) / maxf(nest_bottom - ground_y, 1.0))


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
	_clock += delta
	_sprout_clock -= delta
	if _sprout_clock <= 0.0:
		_sprout_clock = 30.0
		_sprout_damp_seeds()
	_lay_timer -= delta
	if _lay_timer <= 0.0:
		# A full colony keeps raising brood at half pace; old foragers leaving keeps its size steady.
		var slow := 2.0 if population >= max_workers else 1.0
		_lay_timer = _rng.randf_range(LAY_INTERVAL.x, LAY_INTERVAL.y) * slow / lay_rate
		# Laying tracks how well the brood is being fed: with a backlog of hungry
		# larvae the nurses feed her less and she lays less. In winter she rests.
		if not winter and _count_in_zone("queen_eggs") < MAX_QUEEN_EGGS and brood.size() < MAX_BROOD \
				and _hungry_larvae() < 16:
			if _queen_fed():
				_add_brood(Stage.EGG, _tunnels.queen_chamber(), "queen_eggs", 0.0)
				count("laid")
				_tunnels.queen_lay_pulse()

	_reserve_clock -= delta
	if _reserve_clock <= 0.0:
		_reserve_clock = RESERVE_FEED_INTERVAL * (0.4 if population < SMALL_COLONY else 1.0)
		_feed_from_reserves()
	_upkeep_clock -= delta
	if _upkeep_clock <= 0.0:
		_upkeep_clock = UPKEEP_INTERVAL * (2.0 if winter else 1.0)  # cold ants need little food
		_eat_from_stores()

	for b in brood.duplicate():
		if not winter:  # in the cold, brood development pauses until spring
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
		if b.stage == Stage.LARVA and b.fed < FEEDS_TO_PUPATE and _nursery_ids().has(b.chamber):
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
	if b.stage == Stage.PUPA and not _pupa_room_ids().is_empty():
		target = b.chamber if _pupa_room_ids().has(b.chamber) else _pupa_home(-1)
	elif _warm_nursery() != -1:
		target = _warm_nursery()
	else:
		target = b.chamber if _nursery_ids().has(b.chamber) else _nursery_ids()[_rng.randi() % _nursery_ids().size()]
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
	# larvae grow on protein; a larva given only sugar is kept alive but does not develop
	var taken := _take_stored(["protein", "both"])
	var sugar_only := false
	if taken.is_empty() and population >= SMALL_COLONY and _rng.randf() < 0.5:
		var egg := _spare_egg()
		if egg != null:  # no protein anywhere: an egg becomes a larva's meal
			brood.erase(egg)
			egg.sprite.set_meta("kind", "food")
			egg.sprite.set_meta("cannibal", true)
			return {"pickup_node": egg.chamber, "pickup_pos": egg.sprite.position, "food": egg.sprite, "cannibal": true}
	if taken.is_empty():
		taken = _take_stored(["sugar"])
		sugar_only = true
		if taken.is_empty():
			return {}
	var item: Sprite2D = taken["item"]
	return {"pickup_node": taken["store"], "pickup_pos": item.position, "food": item, "sugar_only": sugar_only}


## Seeds stored in damp soil start to germinate. Harvester ants pick sprouting seeds out
## of their granaries and throw them away, so they don't take root inside the nest.
func _sprout_damp_seeds() -> void:
	if _species["food"] != "seeds" or soil_wetness < 0.45:
		return
	for id: int in _tunnels.food_items:
		var items: Array = _tunnels.food_items[id]
		if items.is_empty() or _rng.randf() > soil_wetness * 0.5:
			continue
		var i := _rng.randi() % items.size()
		var seed: Sprite2D = items[i]
		if _nutrient(seed) == "sugar":
			continue
		items.remove_at(i)
		seed.texture = ColonyArt.sprouted_seed(_rng.randi_range(0, 3))
		seed.offset = Vector2(0.0, -seed.texture.get_height() * 0.5)
		seed.set_meta("kind", "waste")
		seed.set_meta("sprouted", true)
		_waste.append(seed)
		_waste_chamber[seed.get_instance_id()] = id
		count("sprouted")
		note.emit("The granary got damp and some seeds began to sprout. The workers picked them out and threw them away.", "sprouted")


## A chamber among the deepest third of the nest (not the refuse pile), where the
## colony huddles through winter, or -1.
func winter_refuge() -> int:
	var ids: Array[int] = []
	for id: int in _tunnels.chambers:
		if _tunnels.is_dug(id) and _tunnels.chamber_role(id) != "refuse":
			ids.append(id)
	if ids.is_empty():
		return -1
	ids.sort_custom(func(a: int, b: int) -> bool: return _tunnels.nodes[a].y > _tunnels.nodes[b].y)
	var deep := ids.slice(0, maxi(2, ids.size() / 3))
	return deep[_rng.randi() % deep.size()]


## An egg nobody is handling, preferring the nursery pile over the queen's own clutch.
func _spare_egg() -> Brood:
	var pick: Brood = null
	for b in brood:
		if b.stage == Stage.EGG and not b.carried and not b.reserved:
			pick = b
			if b.zone == "eggs":
				break
	return pick


## What a stored food item is worth to the colony: "sugar", "protein" or "both".
func _nutrient(item: Sprite2D) -> String:
	if item.has_meta("nutrient"):
		return item.get_meta("nutrient")
	return "protein" if _species["food"] == "prey" else "both"  # seeds hold starch and protein


## Takes a stored item of one of the given nutrient kinds from the top of any store.
## Returns {"store", "item"} or {}.
func _take_stored(kinds: Array) -> Dictionary:
	var options: Array[Dictionary] = []
	for id: int in _tunnels.food_items:
		var items: Array = _tunnels.food_items[id]
		for i in range(items.size() - 1, -1, -1):
			if kinds.has(_nutrient(items[i])):
				options.append({"store": id, "index": i})
				break
	if options.is_empty():
		return {}
	var pick: Dictionary = options[_rng.randi() % options.size()]
	var items: Array = _tunnels.food_items[pick["store"]]
	var item: Sprite2D = items[pick["index"]]
	items.remove_at(pick["index"])
	return {"store": pick["store"], "item": item}


## Stored food, counted by what it provides: x = sugars, y = protein (seeds count for both).
func store_counts() -> Vector2i:
	var out := Vector2i.ZERO
	for id: int in _tunnels.food_items:
		for item: Sprite2D in _tunnels.food_items[id]:
			var n := _nutrient(item)
			if n != "protein":
				out.x += 1
			if n != "sugar":
				out.y += 1
	return out


## Offers a nest worker a job hauling waste to the refuse chamber.
func waste_task() -> Dictionary:
	# Harvester ants carry seed chaff out and dump it on a midden beside the nest
	# mound; other species keep refuse in a chamber away from the brood.
	var corpse := _corpse_task()
	if not corpse.is_empty() and corpse["zone"] == "midden" and entrances_closed:
		_corpses.append({"sprite": corpse["item"], "chamber": corpse["pickup_node"], "ready": _clock + 30.0})
		corpse = {}  # the nest is sealed: it waits inside until morning
	if not corpse.is_empty():
		count("necrophoresis")
		return corpse
	var midden: bool = _species["id"] == "harvester"
	var dumps := _tunnels.chambers_with_role("refuse")
	if midden and entrances_closed:
		return {}  # husks wait inside until the entrances are opened
	if _waste.is_empty() or (dumps.is_empty() and not midden):
		return {}
	var item: Sprite2D = _waste.pop_front()
	var chamber: int = _waste_chamber.get(item.get_instance_id(), -1)
	_waste_chamber.erase(item.get_instance_id())
	if chamber == -1:
		item.queue_free()
		return {}
	var drop: int = _tunnels.nearest_entrance(item.position.x) if midden else dumps[0]
	return {"type": "waste", "item": item, "pickup_node": chamber, "pickup_pos": item.position,
			"drop_node": drop, "zone": "midden" if midden else "refuse"}


## A forager coming home finds food on the surface; returns its task and the item to carry.
func forage_task() -> Dictionary:
	var targets := _tunnels.chambers_with_role("fungus" if _species["food"] == "fungus" else "food")
	if targets.is_empty():
		return {}
	var target: int = targets[_rng.randi() % targets.size()]
	if _species["food"] == "prey" and _rng.randf() < 0.45:
		# insect hunters are omnivores too: they also bring home honeydew and nectar
		var drop := _tunnels.add_item(ColonyArt.food_crumb("nectar", 0), Vector2.ZERO, "food")
		drop.set_meta("nutrient", "sugar")
		return {"type": "store", "item": drop, "drop_node": target, "zone": "food"}
	var item := _tunnels.add_item(_tunnels.food_texture(_species), Vector2.ZERO, "food")
	return {"type": "store", "item": item, "drop_node": target, "zone": "food"}


## Honeydew from the aphids, brought home to the stores (sugars for the workers).
func honeydew_task() -> Dictionary:
	var targets := _tunnels.chambers_with_role("food")
	if targets.is_empty():
		return {}
	var drop := _tunnels.add_item(ColonyArt.food_crumb("nectar", 0), Vector2.ZERO, "food")
	drop.set_meta("nutrient", "sugar")
	return {"type": "store", "item": drop, "drop_node": targets[_rng.randi() % targets.size()], "zone": "food"}


## The ant has reached the pickup spot: returns the sprite it now carries, or null if
## the job no longer makes sense.
func pick_up(task: Dictionary) -> Sprite2D:
	match task["type"]:
		"dig":
			_release_dig(task)
			# one pellet's worth: a gallery advances up to three nodes, a chamber widens a bit
			var from: int = task["pickup_node"]
			var into: int = task["dig_into"]
			for n in 3:
				if not _tunnels.dig(into, from) or _tunnels.is_chamber(into):
					break
				var next := -1
				for c: int in _tunnels.links[into]:
					if not _tunnels.is_dug(c) and not _dig_claims.has(c):
						next = c
						break
				if next == -1:
					break
				from = into
				into = next
			count("dig_trips")
			return _tunnels.add_item(ColonyArt.soil_pellet(_soil_color), Vector2.ZERO, "soil")
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
	if task["type"] == "dig" or task.get("zone") == "midden":  # dumped beside the entrance
		var entrance := _tunnels.nodes[task["drop_node"]]
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		return Vector2(entrance.x + side * _rng.randf_range(16.0, 46.0), entrance.y)
	if task["type"] == "feed":
		var b: Brood = task["brood"]
		return b.sprite.position
	if task.has("brood") and task["zone"] == "larvae":
		var larva: Brood = task["brood"]
		return _tunnels.zone_spot(task["drop_node"], "larvae", float(larva.fed) / FEEDS_TO_PUPATE)
	return _tunnels.zone_spot(task["drop_node"], task["zone"])


## Tallies a job event in `stats`.
func count(key: String) -> void:
	stats[key] = stats.get(key, 0) + 1


## The ant has arrived with its load.
func drop(task: Dictionary, carried: Sprite2D, at: Vector2) -> void:
	count(task["type"] + "_done")
	match task["type"]:
		"dig":
			carried.queue_free()
			soil_dumped.emit(at.x)
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
				if task.get("sugar_only", false):
					count("sugar_fed")  # keeps it alive, but larvae need protein to grow
					if population >= SMALL_COLONY:
						note.emit("Protein ran short: nurses fed the larvae sugar, which keeps them alive but they stopped growing. Insects and seeds are protein.", "larvae_no_protein")
				else:
					b.fed += 1
					_refresh_texture(b)
					if b.zone == "larvae" and _tunnels.is_chamber(b.chamber):  # bigger now: nudged outward
						b.sprite.position = _tunnels.zone_spot(b.chamber, "larvae", float(b.fed) / FEEDS_TO_PUPATE).round()
				if task.get("cannibal", false):
					count("ate_eggs")
					note.emit("Starved of protein, the nurses fed some of the eggs to the larvae. Real colonies recycle eggs like this in lean times.", "egg_cannibalism")
			_leave_waste(b.chamber, at)
		"waste":
			if task["zone"] == "midden":
				if str(carried.get_meta("kind", "")) == "corpse":
					corpse_dumped.emit(at.x, carried.texture)
				else:
					midden_dumped.emit(at.x)
				carried.queue_free()
				return
			_tunnels.place_item(carried, at)
			_refuse.append(carried)
			while _refuse.size() > MAX_REFUSE_ITEMS:  # older waste packs down into the heap
				_refuse.pop_front().queue_free()
		"store":
			var target: int = task["drop_node"]
			if carried.has_meta("hitchhiker"):  # the rider climbs off once home
				carried.remove_meta("hitchhiker")
				var rider := carried.get_node_or_null("Hitchhiker")
				if rider != null:
					rider.queue_free()
			_tunnels.place_item(carried, at)
			if not _tunnels.food_items.has(target) and _species["food"] != "fungus":
				_tunnels.food_items[target] = []  # the queen's chamber keeps a small store at first
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
	if task.get("type") == "dig":
		_release_dig(task)
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
			chamber = _nursery_ids()[0]
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
				var nursery: int = _nursery_ids()[_rng.randi() % _nursery_ids().size()]
				_add_brood(Stage.EGG, nursery, "eggs", 0.0)
				laid += 1
	return {"emerged": emerged, "laid": laid}


## Puts brood straight into the pile it belongs in (used while catching up).
func _relocate(b: Brood) -> void:
	if b.stage == Stage.PUPA and not _pupa_room_ids().is_empty():
		if not _pupa_room_ids().has(b.chamber):
			b.chamber = _pupa_home(-1)
	elif not _nursery_ids().has(b.chamber):
		b.chamber = _nursery_ids()[_rng.randi() % _nursery_ids().size()]
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
	if raining or winter:
		return null
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
	food_found.emit(cluster.kind)
	var id := cluster.get_instance_id()
	_recruits[id] = mini(int(_recruits.get(id, 0)) + cluster.recruits_per_trip(), cluster.crumbs)


## A food that still needs hands, for an ant leaving the nest, or null.
func take_recruit() -> Node2D:
	if night or raining or winter:
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
	var tex: Texture2D
	match kind:
		"leaves":
			tex = ColonyArt.leaf_piece(_rng.randi_range(0, 3))
		"insects":
			tex = ColonyArt.prey_bit(_rng.randi_range(0, 4))
		_:
			tex = ColonyArt.food_crumb(kind, _rng.randi_range(0, 2))
	var item := _tunnels.add_item(tex, Vector2.ZERO, "food")
	item.set_meta("nutrient", NUTRIENTS.get(kind, "both"))
	if kind == "leaves" and _species["id"] == "leafcutter" and _rng.randf() < 0.3:
		# a tiny minima rides on the leaf, guarding the carrier from parasitic flies
		var rider := Sprite2D.new()
		var castes: Array = _species["castes"]
		rider.texture = ColonyArt.ant_frames(_species, castes[0]["size"], castes[0]["head"])[0]
		rider.position = Vector2(0.0, -tex.get_height() * 0.5 - 2.0)
		rider.name = "Hitchhiker"
		item.add_child(rider)
		item.set_meta("hitchhiker", true)
		count("hitchhikers")
	count("crumb_" + kind)
	return {"type": "store", "item": item, "drop_node": targets[_rng.randi() % targets.size()], "zone": "food"}



# ---------------------------------------------------------------------------
# Digging the nest out
# ---------------------------------------------------------------------------

var _soil_color := Color("#7e5432")


func set_soil_color(c: Color) -> void:
	_soil_color = c


## A digging job at the edge of the dug nest, or {} if there is nothing left to dig.
## Rooms already started are favoured, so chambers get finished.
func dig_task() -> Dictionary:
	var options: Array[Vector2i] = []
	var weights: Array[float] = []
	for edge in _tunnels.frontier():
		var limit := 2 if _tunnels.is_chamber(edge.y) else 1
		if int(_dig_claims.get(edge.y, 0)) >= limit:
			continue
		options.append(edge)
		var w := 1.0
		if _tunnels.is_chamber(edge.y):
			w = 6.0 if _tunnels.dig_work.has(edge.y) else 3.0
		weights.append(w)
	if options.is_empty():
		return {}
	var total := 0.0
	for w in weights:
		total += w
	var roll := _rng.randf() * total
	var pick := options[options.size() - 1]
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			pick = options[i]
			break
	_dig_claims[pick.y] = int(_dig_claims.get(pick.y, 0)) + 1
	var from := _tunnels.nodes[pick.x]
	return {"type": "dig", "pickup_node": pick.x, "pickup_pos": from, "dig_into": pick.y,
			"dig_time": _rng.randf_range(DIG_TIME.x, DIG_TIME.y) * (1.0 - 0.4 * soil_wetness),  # damp soil digs easier
			"drop_node": _tunnels.nearest_entrance(from.x)}


func has_digging() -> bool:
	return not _tunnels.frontier().is_empty()


func _release_dig(task: Dictionary) -> void:
	var id: int = task["dig_into"]
	if _dig_claims.has(id):
		_dig_claims[id] = int(_dig_claims[id]) - 1
		if _dig_claims[id] <= 0:
			_dig_claims.erase(id)


## Founding: with no food in the nest yet, the queen feeds a larva from her own body
## reserves (her flight muscles and fat), as claustral queens do.
func _feed_from_reserves() -> void:
	if population < SMALL_COLONY or not _food_source_available():
		for b in brood:
			if b.stage == Stage.LARVA and b.fed < FEEDS_TO_PUPATE and not b.reserved and not b.carried:
				b.fed += 1
				_refresh_texture(b)
				return


func _food_source_available() -> bool:
	if _species["food"] == "fungus":
		return not _tunnels.chambers_with_role("fungus").is_empty()
	for id: int in _tunnels.food_items:
		if not (_tunnels.food_items[id] as Array).is_empty():
			return true
	return false


## Digging that happened while the app was closed: `diggers` workers each finish a
## trip every ~40 s. Returns how many trips were made.
func fast_forward_digging(seconds: float, diggers: int) -> int:
	var trips := int(minf(seconds, MAX_CATCH_UP) * diggers / 40.0)
	var done := 0
	for i in trips:
		var options := _tunnels.frontier()
		if options.is_empty():
			break
		var edge: Vector2i = options[_rng.randi() % options.size()]
		_tunnels.dig(edge.y, edge.x)
		done += 1
	return done
