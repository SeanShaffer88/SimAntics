extends Node2D
## Bottom layer: this colony's nest carved into its soil, plus chamber contents
## (brood, food, fungus, refuse) and the queen. The generated layout is a blueprint:
## a new colony starts as a founding queen in one small chamber, and workers dig the
## rest out node by node (see dig()). Ants navigate only the dug part of the graph.

const SoilArt := preload("res://scripts/soil_art.gd")
const ColonyArt := preload("res://scripts/colony_art.gd")
const NestGenerator := preload("res://scripts/nest_generator.gd")

const ENTRANCE := 0
const SHAFT_RADIUS := 3.5  # art pixels (about 14 screen px wide, a little over an ant height)
const FLOOR := NestGenerator.FLOOR

var nodes: Array[Vector2] = []
var links: Array[Array] = []
var chambers: Dictionary = {}
var dig_faces: Array[int] = []
var entrance_x := 0.0
var entrances: Array[int] = []  # every surface opening, main (node 0) first
var entrance_xs: Array[float] = []
var food_items: Dictionary = {}  # food chamber id -> Array of item sprites in its store
var dug := PackedByteArray()  # per node: 1 once it has been dug out
var dig_work: Dictionary = {}  # chamber id -> digging trips done (chambers open gradually)
var founding_chamber := -1

signal chamber_opened(id: int)
signal entrance_opened(x: float)

const CHAMBER_FILL_START := 0.5  # a chamber appears at half size and widens as it is dug

var _soil_top := 0.0
var _queen_frames: Array[ImageTexture] = []
var _queen_clock := 0.0
var _queen_tween: Tween
var _art_size := Vector2i.ZERO
var _img: Image
var _base: Image
var _mask := PackedByteArray()
var _dist := PackedFloat32Array()
var _air := Color.BLACK
var _rng := RandomNumberGenerator.new()
var _species: Dictionary
var _seed := 0
var _queen_home := -1
var _wall_noise := FastNoiseLite.new()
var _gen: RefCounted
var expansions := 0  # times the colony has extended the nest past its first plan

@onready var _soil: Sprite2D = $Soil
@onready var _items: Node2D = $Items
@onready var _queen: Sprite2D = $Queen


## `dig_state`: dug nodes from a save (see dig_save()); `mature` opens the whole nest at once.
func setup(profile: RefCounted, view_size: Vector2, ground_y: float, soil_top: float,
		dig_state: Dictionary = {}, mature: bool = false) -> void:
	_soil_top = soil_top
	_rng.seed = profile.seed_value + 1
	_species = profile.species
	_seed = profile.seed_value

	_wall_noise.seed = profile.seed_value
	_wall_noise.frequency = 0.3
	var gen := NestGenerator.new()
	_gen = gen
	gen.generate(profile.seed_value, profile.species, view_size, ground_y, soil_top)
	nodes = gen.nodes
	links = gen.links
	chambers = gen.chambers
	dig_faces = gen.dig_faces
	entrance_x = gen.entrance_x
	entrances = gen.entrances
	entrance_xs = gen.entrance_xs
	for i in int(dig_state.get("expansions", 0)):  # replay the colony's later digging
		_apply_expansion(gen.expand(profile.seed_value, i))
	expansions = int(dig_state.get("expansions", 0))
	founding_chamber = _pick_founding_chamber()
	dug.resize(nodes.size())
	dug.fill(0)
	if mature:
		dug.fill(1)
	elif dig_state.has("dug"):
		for id in dig_state["dug"]:
			if int(id) < nodes.size():
				dug[int(id)] = 1
		var work: Dictionary = dig_state.get("work", {})
		for key in work:
			dig_work[int(key)] = int(work[key])
	else:
		_start_founding()

	var px := SoilArt.PIXEL_SCALE
	_art_size = Vector2i(int(view_size.x / px), int((view_size.y - soil_top) / px))
	var strata: Array = profile.soil["strata"]
	_air = (strata[3] as Color).darkened(0.72)
	_base = SoilArt.make_soil_image(_art_size.x, _art_size.y, _rng, strata)
	_img = _base.duplicate()
	_mask.resize(_art_size.x * _art_size.y)
	_mask.fill(0)
	_dist.resize(_mask.size())
	_carve_all()
	var whole := Rect2i(Vector2i.ZERO, _art_size)
	SoilArt.update_distance(_dist, _mask, _art_size.x, _art_size.y, whole)
	SoilArt.paint_tunnels(_img, _base, _mask, _dist, whole, _air)

	_soil.texture = ImageTexture.create_from_image(_img)
	_soil.position = Vector2(0.0, soil_top)
	_soil.scale = Vector2(px, px)
	_build_damp_overlay(view_size)
	_queen_home = _choose_queen_home()
	_place_queen(profile.species)
	_furnish_chambers(mature)


# ---------------------------------------------------------------------------
# Navigation API used by ants
# ---------------------------------------------------------------------------

func is_chamber(id: int) -> bool:
	return chambers.has(id)


func is_entrance(id: int) -> bool:
	return entrances.has(id)


func is_dug(id: int) -> bool:
	return dug[id] == 1


## The open surface entrance closest to a given x (the main one is always open).
func nearest_entrance(x: float) -> int:
	var best := 0
	for i in entrances.size():
		if is_dug(entrances[i]) and absf(entrance_xs[i] - x) < absf(entrance_xs[best] - x):
			best = i
	return entrances[best]


func open_entrances() -> Array[int]:
	var ids: Array[int] = []
	for id in entrances:
		if is_dug(id):
			ids.append(id)
	return ids


func chamber_role(id: int) -> String:
	return chambers[id]["role"] if chambers.has(id) else ""


## Open (fully dug) chambers with a role. Until a colony has dug its nursery, the
## queen's chamber doubles as nursery, as it does in a real young colony.
func chambers_with_role(role: String) -> Array[int]:
	var ids: Array[int] = []
	for id: int in chambers:
		if chambers[id]["role"] == role and is_dug(id):
			ids.append(id)
	if ids.is_empty() and role == "nursery":
		ids.append(_queen_home)
	return ids


func chamber_floor_y(id: int) -> float:
	var radii: Vector2 = chambers[id]["radii"]
	return nodes[id].y + FLOOR * radii.y + 1.0


## A point on a chamber floor for an ant whose sprite is `half_height` tall from centre to feet.
func random_floor_point(id: int, rng: RandomNumberGenerator, half_height: float) -> Vector2:
	if not chambers.has(id):
		return nodes[id]
	var c: Dictionary = chambers[id]
	return Vector2(rng.randf_range(c["floor_left"], c["floor_right"]), chamber_floor_y(id) - half_height)


## Breadth-first route through the tunnel graph, including both end nodes.
func find_path(from_id: int, to_id: int) -> Array[int]:
	var route: Array[int] = []
	var came_from := {from_id: -1}
	var queue: Array[int] = [from_id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if current == to_id:
			break
		for next: int in links[current]:
			if not came_from.has(next) and dug[next] == 1:
				came_from[next] = current
				queue.append(next)
	if not came_from.has(to_id):
		return route
	var step: int = to_id
	while step != -1:
		route.push_front(step)
		step = came_from[step]
	return route


# ---------------------------------------------------------------------------
# Carving
# ---------------------------------------------------------------------------

func _carve_all() -> void:
	for a in nodes.size():
		for b: int in links[a]:
			if b > a and dug[a] == 1 and dug[b] == 1:
				_carve_segment(_to_art(nodes[a]), _to_art(nodes[b]), SHAFT_RADIUS)
	for id: int in chambers:
		if dug[id] == 1:
			_carve_chamber(id, 1.0)
		elif dig_work.has(id):
			_carve_chamber(id, _chamber_fill(id))
	for id in dig_faces:
		if dug[id] == 1:
			_carve_disc(_to_art(nodes[id]), SHAFT_RADIUS + 0.8)


# ---------------------------------------------------------------------------
# Digging
# ---------------------------------------------------------------------------

## Every place digging can continue: [dug node, undug neighbour] pairs.
func frontier() -> Array[Vector2i]:
	var edges: Array[Vector2i] = []
	for a in nodes.size():
		if dug[a] != 1:
			continue
		for b: int in links[a]:
			if dug[b] != 1:
				edges.append(Vector2i(a, b))
	return edges


## Trips needed to dig out a chamber (bigger rooms take longer).
func chamber_work(id: int) -> int:
	var r: Vector2 = chambers[id]["radii"]
	return clampi(int(r.x * r.y * PI / 700.0), 4, 14)


## One digging trip from dug node `from_id` into `id`: a gallery advances one node, a
## chamber widens a little and opens once finished. Returns true when `id` is now open.
func dig(id: int, from_id: int) -> bool:
	if dug[id] == 1:
		return true
	var opened := true
	if chambers.has(id):
		dig_work[id] = int(dig_work.get(id, 0)) + 1
		opened = dig_work[id] >= chamber_work(id)
	var a := _to_art(nodes[from_id])
	var b := _to_art(nodes[id])
	_carve_segment(a, b, SHAFT_RADIUS)
	var area := Rect2(a, Vector2.ZERO).expand(b).grow(SHAFT_RADIUS + 1.0)
	if chambers.has(id):
		_carve_chamber(id, 1.0 if opened else _chamber_fill(id))
		var r: Vector2 = chambers[id]["radii"]
		area = area.merge(Rect2(b - r / SoilArt.PIXEL_SCALE * 1.6, r / SoilArt.PIXEL_SCALE * 3.2))
	elif dig_faces.has(id):
		_carve_disc(b, SHAFT_RADIUS + 0.8)
	_repaint(Rect2i(Vector2i(area.position.floor()), Vector2i(area.size.ceil()) + Vector2i.ONE))
	if opened:
		dug[id] = 1
		if chambers.has(id):
			_on_chamber_opened(id)
		elif entrances.has(id):
			entrance_opened.emit(nodes[id].x)  # broke through to the surface
	return opened


func _chamber_fill(id: int) -> float:
	return lerpf(CHAMBER_FILL_START, 1.0, float(dig_work.get(id, 0)) / chamber_work(id))


## Recomputes wall shading and repaints just the part of the soil that changed.
func _repaint(changed: Rect2i) -> void:
	var margin := int(SoilArt.AO_RADIUS) + 2
	var whole := Rect2i(Vector2i.ZERO, _art_size)
	var dist_rect := changed.grow(margin * 2).intersection(whole)
	var paint_rect := changed.grow(margin).intersection(whole)
	SoilArt.update_distance(_dist, _mask, _art_size.x, _art_size.y, dist_rect)
	SoilArt.paint_tunnels(_img, _base, _mask, _dist, paint_rect, _air)
	(_soil.texture as ImageTexture).update(_img)


func _on_chamber_opened(id: int) -> void:
	_furnish(id, false)
	if chambers[id]["role"] == "queen":
		_move_queen(id)
	chamber_opened.emit(id)


## Digging state for the save file.
func dig_save() -> Dictionary:
	var open := []
	for id in nodes.size():
		if dug[id] == 1:
			open.append(id)
	var work := {}
	for id: int in dig_work:
		work[str(id)] = dig_work[id]
	return {"dug": open, "work": work, "nest": NestGenerator.VERSION, "expansions": expansions}


var _damp: Sprite2D


## Rain soaking into the topsoil darkens it from the surface down.
func _build_damp_overlay(view_size: Vector2) -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.08, 0.05, 0.03, 0.42))
	grad.set_color(1, Color(0.08, 0.05, 0.03, 0.0))
	grad.add_point(0.55, Color(0.08, 0.05, 0.03, 0.18))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 4
	tex.height = 128
	_damp = Sprite2D.new()
	_damp.name = "Damp"
	_damp.texture = tex
	_damp.centered = false
	_damp.position = Vector2(0.0, _soil_top)
	_damp.scale = Vector2(view_size.x / 4.0, 1.0)
	_damp.modulate.a = 0.0
	add_child(_damp)
	move_child(_damp, _soil.get_index() + 1)


## 0 (dry) .. 1 (soaked): how far down and how dark the damp shows.
func set_wetness(value: float) -> void:
	if _damp == null:
		return
	_damp.modulate.a = value
	_damp.scale.y = (60.0 + value * 140.0) / 128.0


## The colony outgrows its nest: plan a few new galleries and rooms off the existing
## ones (left undug for the workers to excavate). Returns how many rooms were planned.
func expand() -> int:
	var added: Array[int] = _gen.expand(_seed, expansions)
	expansions += 1
	_apply_expansion(added)
	dug.resize(nodes.size())  # new nodes start undug (resize fills with 0)
	return added.size()


func _apply_expansion(added: Array[int]) -> void:
	for i in added.size():
		var role := "rest"
		if i == 0:  # the first new room of each expansion holds stores
			role = "fungus" if _species["food"] == "fungus" else "food"
		chambers[added[i]]["role"] = role


## The founding chamber: the room closest to the main entrance, where the queen
## sealed herself in after her mating flight.
func _pick_founding_chamber() -> int:
	var best := -1
	var best_len := 1 << 30
	for id: int in chambers:
		var hops := _blueprint_path(ENTRANCE, id).size()
		if hops > 0 and hops < best_len:
			best_len = hops
			best = id
	return best


func _start_founding() -> void:
	for id in _blueprint_path(ENTRANCE, founding_chamber):
		dug[id] = 1
	dig_work[founding_chamber] = chamber_work(founding_chamber)


## Route through the whole blueprint, dug or not.
func _blueprint_path(from_id: int, to_id: int) -> Array[int]:
	var came_from := {from_id: -1}
	var queue: Array[int] = [from_id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if current == to_id:
			break
		for next: int in links[current]:
			if not came_from.has(next):
				came_from[next] = current
				queue.append(next)
	var route: Array[int] = []
	if not came_from.has(to_id):
		return route
	var step: int = to_id
	while step != -1:
		route.push_front(step)
		step = came_from[step]
	return route


func _to_art(p: Vector2) -> Vector2:
	var px := float(SoilArt.PIXEL_SCALE)
	return Vector2(p.x / px, (p.y - _soil_top) / px)


## Galleries are hand-dug: their width wobbles a little along their length.
func _carve_segment(a: Vector2, b: Vector2, r: float) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) / 0.75))
	for s in steps + 1:
		var c := a.lerp(b, float(s) / steps)
		_carve_disc(c, r * (0.74 + 0.42 * (_wall_noise.get_noise_2dv(c) + 1.0) * 0.5))


func _carve_disc(c: Vector2, r: float) -> void:
	for y in range(maxi(0, floori(c.y - r)), mini(_art_size.y, ceili(c.y + r) + 1)):
		for x in range(maxi(0, floori(c.x - r)), mini(_art_size.x, ceili(c.x + r) + 1)):
			var dx := x + 0.5 - c.x
			var dy := y + 0.5 - c.y
			if dx * dx + dy * dy <= r * r:
				_mask[y * _art_size.x + x] = 1


## Each lobe is a flattened ellipse cut off flat at the shared floor.
func _carve_chamber(id: int, fill: float) -> void:
	var px := float(SoilArt.PIXEL_SCALE)
	var center := _to_art(nodes[id])
	var floor_art := _to_art(Vector2(0.0, chamber_floor_y(id))).y
	for lobe: Vector4 in chambers[id]["lobes"]:
		var c := center + Vector2(lobe.x * fill, lobe.y) / px
		var r := Vector2(lobe.z, lobe.w) * fill / px
		for y in range(maxi(0, floori(c.y - r.y)), mini(_art_size.y, ceili(floor_art))):
			for x in range(maxi(0, floori(c.x - r.x)), mini(_art_size.x, ceili(c.x + r.x) + 1)):
				var nx := (x + 0.5 - c.x) / r.x
				var ny := (y + 0.5 - c.y) / r.y
				if nx * nx + ny * ny <= 1.0:
					_mask[y * _art_size.x + x] = 1


# ---------------------------------------------------------------------------
# Chamber contents
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# the queen mostly rests, shifting her legs now and then
	if _queen_frames.is_empty():
		return
	_queen_clock -= delta
	if _queen_clock <= 0.0:
		_queen_clock = _rng.randf_range(2.0, 6.0)
		_queen.texture = _queen_frames[_rng.randi() % _queen_frames.size()]


## `stocked`: a mature nest starts with full stores; a growing one fills them itself.
func _furnish_chambers(stocked: bool) -> void:
	for id: int in chambers:
		if is_dug(id):
			_furnish(id, stocked)


func _furnish(id: int, stocked: bool) -> void:
	var species := _species
	var floor_y := chamber_floor_y(id)
	var c: Dictionary = chambers[id]
	var left: float = c["floor_left"]
	var right: float = c["floor_right"]
	var span := right - left
	var mid := (left + right) * 0.5
	var ceiling := heap_ceiling(id)
	match c["role"]:
		"food":
			food_items[id] = []
			var count := (70 if species["food"] == "seeds" else 24) if stocked else 0
			for i in count:
				food_items[id].append(add_item(food_texture(species), zone_spot(id, "food"), "food"))
			var waste_food: String = species["food"]
			if stocked:
				_scatter(left, right, floor_y, 8, func(): return ColonyArt.waste_bit(waste_food, _rng.randi_range(0, 1)))
		"fungus":
			var w := int(span / SoilArt.PIXEL_SCALE * 0.85)
			var h := int(ceiling / SoilArt.PIXEL_SCALE * 1.5)
			add_item(ColonyArt.fungus_garden(w, h, _seed + id), Vector2(mid, floor_y),
					"fungus", SoilArt.PIXEL_SCALE)
		"refuse":
			var w := int(span / SoilArt.PIXEL_SCALE * 0.6)
			var h := int(ceiling / SoilArt.PIXEL_SCALE * 1.2)
			if stocked:
				add_item(ColonyArt.refuse_heap(w, h, _seed + id), Vector2(mid, floor_y),
						"refuse", SoilArt.PIXEL_SCALE)
				_scatter(left, right, floor_y, 12, func(): return ColonyArt.prey_bit(_rng.randi_range(0, 4)))


## Sets how much food a store holds (used when restoring a save).
func set_food_count(id: int, count: int, species: Dictionary) -> void:
	if not food_items.has(id):
		if not chambers.has(id) or not is_dug(id):
			return
		food_items[id] = []  # e.g. the founding chamber's small store
	var store: Array = food_items[id]
	while store.size() > count:
		store.pop_back().queue_free()
	while store.size() < count:
		store.append(add_item(food_texture(species), zone_spot(id, "food"), "food"))


## A texture for one unit of this species' stored food.
func food_texture(species: Dictionary) -> Texture2D:
	match species["food"]:
		"seeds":
			return ColonyArt.seed_texture(_rng.randi_range(0, 3))
		"fungus":
			return ColonyArt.leaf_piece(_rng.randi_range(0, 3))
	return ColonyArt.prey_bit(_rng.randi_range(0, 4))


func heap_ceiling(id: int) -> float:
	return chambers[id]["radii"].y * (1.0 + FLOOR) * 0.55


## Where a new item should sit in a chamber zone. Items heap up toward each zone's centre:
##   queen_eggs - beside the queen's gaster   eggs / larvae / pupae - the sorted brood piles
##   food - the store heap                    refuse - the waste heap
func zone_spot(id: int, zone: String) -> Vector2:
	var c: Dictionary = chambers[id]
	var left: float = c["floor_left"]
	var right: float = c["floor_right"]
	var span := right - left
	var center := (left + right) * 0.5
	var half := span * 0.3
	var height := heap_ceiling(id)
	match zone:
		"queen_eggs":
			center = _queen.position.x - _queen.texture.get_width() * 0.5 - 10.0
			half = 10.0
			height = minf(height, 9.0)
		"eggs":
			center = left + span * 0.2
			half = span * 0.13
			height = minf(height, 10.0)
		"larvae":
			center = left + span * 0.52
			half = span * 0.16
			height = minf(height, 12.0)
		"pupae":
			if c["role"] == "pupae":  # a whole chamber given over to pupae
				half = span * 0.36
			else:
				center = left + span * 0.84
				half = span * 0.12
			height = minf(height, 14.0)
		"food":
			height = minf(height, 16.0)
		"refuse":
			half = span * 0.25
			height = minf(height, 10.0)
		_:
			height = 0.0
	var t := _rng.randf() + _rng.randf() - 1.0  # triangular: denser in the middle
	var lift := height * (1.0 - t * t) * sqrt(_rng.randf())
	return Vector2(clampf(center + t * half, left, right), chamber_floor_y(id) - lift)


## Loose items lying flat across the floor.
func _scatter(left: float, right: float, floor_y: float, count: int, make: Callable) -> void:
	for i in count:
		add_item(make.call(), Vector2(_rng.randf_range(left, right), floor_y), "item")


## Adds an item sprite whose bottom-centre sits at `bottom_center`.
func add_item(tex: Texture2D, bottom_center: Vector2, kind: String, item_scale: int = ColonyArt.ITEM_SCALE) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.scale = Vector2.ONE * item_scale
	sprite.centered = true
	sprite.offset = Vector2(0.0, -tex.get_height() * 0.5)
	sprite.position = bottom_center.round()
	sprite.flip_h = _rng.randf() < 0.5
	sprite.set_meta("kind", kind)
	_items.add_child(sprite)
	return sprite


## Puts an existing item sprite (for example one an ant was carrying) back on a floor.
func place_item(sprite: Sprite2D, bottom_center: Vector2) -> void:
	if sprite.get_parent() != null:
		sprite.get_parent().remove_child(sprite)
	sprite.rotation = 0.0
	sprite.position = bottom_center.round()
	sprite.z_index = 0
	_items.add_child(sprite)


## Where the queen lives now: her own deep chamber once it is dug, the founding chamber until then.
func queen_chamber() -> int:
	return _queen_home


func _choose_queen_home() -> int:
	for id: int in chambers:
		if chambers[id]["role"] == "queen" and is_dug(id):
			return id
	return founding_chamber


## The queen moves down into her new chamber (nurses will bring the brood after her).
func _move_queen(id: int) -> void:
	_queen_home = id
	var fade := create_tween()
	fade.tween_property(_queen, "modulate:a", 0.0, 0.6)
	fade.tween_callback(func(): _set_queen_position(id))
	fade.tween_property(_queen, "modulate:a", 1.0, 0.6)


func _set_queen_position(id: int) -> void:
	var c: Dictionary = chambers[id]
	var x := (float(c["floor_left"]) + float(c["floor_right"])) * 0.5 + 10.0
	_queen.position = Vector2(x, chamber_floor_y(id) - _queen.texture.get_height() * ColonyArt.SPRITE_SCALE * 0.5)


## A small heave of the queen's body as she lays.
## A spot on the floor right beside the queen, for an attendant nurse.
func queen_attend_spot(rng: RandomNumberGenerator, half_height: float) -> Vector2:
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var reach := _queen.texture.get_width() * ColonyArt.SPRITE_SCALE * 0.5 + rng.randf_range(4.0, 12.0)
	return Vector2(_queen.position.x + side * reach, chamber_floor_y(queen_chamber()) - half_height)


func queen_position() -> Vector2:
	return _queen.position


func queen_lay_pulse() -> void:
	if _queen_tween != null:
		_queen_tween.kill()
	var rest_y := chamber_floor_y(queen_chamber()) - _queen.texture.get_height() * ColonyArt.SPRITE_SCALE * 0.5
	_queen.position.y = rest_y
	_queen_tween = create_tween()
	_queen_tween.tween_property(_queen, "position:y", rest_y - 1.0, 0.25)
	_queen_tween.tween_property(_queen, "position:y", rest_y, 0.35)


func _place_queen(species: Dictionary) -> void:
	_queen_frames = ColonyArt.ant_frames(species, 1.0, 1.0, true)
	_queen.texture = _queen_frames[0]
	_queen.scale = Vector2.ONE * ColonyArt.SPRITE_SCALE
	_set_queen_position(queen_chamber())
