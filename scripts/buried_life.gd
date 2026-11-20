extends Node2D
## Creatures living in the soil around the nest, visible through the glass like in a real
## ant farm: scarab grubs, wireworms, moth pupae, ground beetles and earthworms, each in
## its own little soil cell. As the colony digs, it breaks into their cells:
##   grubs, wireworms and pupae can't escape - the ants cut them up and carry them home
##   as protein, piece by piece;
##   beetles and earthworms burrow away deeper into the soil.

signal exposed(kind: String, at: Vector2)

const ColonyArt := preload("res://scripts/colony_art.gd")

const KINDS := {
	"grub": {"weight": 0.28, "meat": 8, "prey": true, "size": Vector2(20, 15)},
	"wireworm": {"weight": 0.18, "meat": 5, "prey": true, "size": Vector2(24, 8)},
	"pupa": {"weight": 0.16, "meat": 6, "prey": true, "size": Vector2(18, 9)},
	"beetle": {"weight": 0.16, "meat": 0, "prey": false, "size": Vector2(18, 11)},
	"worm": {"weight": 0.22, "meat": 0, "prey": false, "size": Vector2(34, 10)},
}
const FIND_RADIUS := 26.0  # digging this close breaks into a creature's cell

enum { BURIED, EXPOSED, GONE }

var critters: Array[Dictionary] = []  # kind, pos, state, meat, sprite, cell
var _clock := 0.0


## Places the creatures for this colony (deterministic per seed). `nodes` is the nest
## blueprint: about half the creatures lie close to where galleries will run.
func generate(seed_value: int, nodes: Array[Vector2], soil_top: float, bottom: float, width: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 3 + 7171
	var count := rng.randi_range(10, 16)
	for i in count:
		var kind := _pick_kind(rng)
		var pos := Vector2.ZERO
		for attempt in 30:
			if i % 2 == 0 and not nodes.is_empty():  # beside a planned gallery
				var n: Vector2 = nodes[rng.randi() % nodes.size()]
				pos = n + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(16.0, 24.0)
			else:
				pos = Vector2(rng.randf_range(50.0, width - 50.0), rng.randf_range(soil_top + 40.0, bottom - 20.0))
			if pos.y > soil_top + 30.0 and pos.y < bottom - 12.0 and _clear_of(pos, nodes, 14.0) and _apart(pos, 30.0):
				break
		critters.append({"kind": kind, "pos": pos.round(), "state": BURIED, "meat": int(KINDS[kind]["meat"]),
				"flip": rng.randf() < 0.5, "sprite": null, "cell": null})


func _pick_kind(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	for k: String in KINDS:
		roll -= float(KINDS[k]["weight"])
		if roll <= 0.0:
			return k
	return "grub"


func _clear_of(p: Vector2, nodes: Array[Vector2], dist: float) -> bool:
	for n in nodes:
		if n.distance_squared_to(p) < dist * dist:
			return false
	return true


func _apart(p: Vector2, dist: float) -> bool:
	for c in critters:
		if (c["pos"] as Vector2).distance_squared_to(p) < dist * dist:
			return false
	return true


## Creates the sprites for creatures still in the soil. `is_open` tells whether a point
## has already been dug (a creature there was found long ago and is gone).
func build(is_open: Callable) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for c in critters:
		if c["state"] == BURIED and is_open.call(c["pos"]):
			c["state"] = GONE
		if c["state"] == EXPOSED and not KINDS[c["kind"]]["prey"]:
			c["state"] = GONE  # it got away while you were gone
		if c["state"] == GONE:
			continue
		var size: Vector2 = KINDS[c["kind"]]["size"]
		var cell := Sprite2D.new()
		cell.texture = ColonyArt.soil_cell(int(size.x + 6), int(size.y + 5))
		cell.scale = Vector2.ONE * ColonyArt.ITEM_SCALE
		cell.position = c["pos"]
		add_child(cell)
		var s := Sprite2D.new()
		s.texture = ColonyArt.critter(c["kind"], 0)
		s.scale = Vector2.ONE * ColonyArt.ITEM_SCALE
		s.position = c["pos"]
		s.flip_h = c["flip"]
		s.modulate = Color(0.82, 0.8, 0.78) if c["state"] == BURIED else Color.WHITE
		add_child(s)
		c["sprite"] = s
		c["cell"] = cell
		if c["meat"] <= 0 and KINDS[c["kind"]]["prey"]:
			_remove(c)


## Digging reached `at`: any creature whose cell is that close is uncovered.
func dug_at(at: Vector2) -> void:
	for c in critters:
		if c["state"] != BURIED or (c["pos"] as Vector2).distance_to(at) > FIND_RADIUS:
			continue
		c["state"] = EXPOSED
		var s: Sprite2D = c["sprite"]
		if s != null:
			s.modulate = Color.WHITE
		exposed.emit(c["kind"], c["pos"])
		if not KINDS[c["kind"]]["prey"]:
			_escape(c, at)


## Beetles and earthworms burrow off, away from the ants, and are gone.
func _escape(c: Dictionary, from: Vector2) -> void:
	var s: Sprite2D = c["sprite"]
	if s == null:
		c["state"] = GONE
		return
	var away := ((c["pos"] as Vector2) - from).normalized()
	if away == Vector2.ZERO:
		away = Vector2.DOWN
	s.flip_h = away.x < 0.0
	var t := s.create_tween()
	t.tween_property(s, "position", s.position + away * 34.0, 6.0)
	t.parallel().tween_property(s, "modulate:a", 0.0, 6.0).set_delay(2.0)
	t.parallel().tween_property(c["cell"], "modulate:a", 0.0, 3.0)
	t.tween_callback(func(): _remove(c))
	c["state"] = GONE


func _remove(c: Dictionary) -> void:
	for key in ["sprite", "cell"]:
		var n: Node = c[key]
		if n != null and is_instance_valid(n):
			n.queue_free()
		c[key] = null
	c["state"] = GONE


## The next helpless creature with meat left on it, or {}: {"index", "pos"}.
func next_meal() -> Dictionary:
	for i in critters.size():
		var c: Dictionary = critters[i]
		if c["state"] == EXPOSED and int(c["meat"]) > 0:
			return {"index": i, "pos": c["pos"]}
	return {}


## Ants take a piece away: the creature shrinks and is gone once eaten.
func take_piece(index: int) -> void:
	var c: Dictionary = critters[index]
	c["meat"] = int(c["meat"]) - 1
	var s: Sprite2D = c["sprite"]
	if s != null:
		var full := float(KINDS[c["kind"]]["meat"])
		s.scale = Vector2.ONE * ColonyArt.ITEM_SCALE * lerpf(0.45, 1.0, float(c["meat"]) / full)
	if int(c["meat"]) <= 0:
		_remove(c)


func _process(delta: float) -> void:
	_clock += delta
	# helpless exposed prey wriggles; buried creatures stir now and then
	var frame := int(_clock * 2.5) % 2
	for c in critters:
		var s: Sprite2D = c["sprite"]
		if s == null:
			continue
		if c["state"] == EXPOSED:
			s.texture = ColonyArt.critter(c["kind"], frame)
		elif c["state"] == BURIED and fmod(_clock + float(c["pos"].x), 9.0) < 0.8:
			s.texture = ColonyArt.critter(c["kind"], frame)


func to_save() -> Array:
	var out := []
	for c in critters:
		out.append([c["state"], c["meat"]])
	return out


func restore(saved: Array) -> void:
	for i in mini(saved.size(), critters.size()):
		var entry: Array = saved[i]
		critters[i]["state"] = int(entry[0])
		critters[i]["meat"] = int(entry[1])
