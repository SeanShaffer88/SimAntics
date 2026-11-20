extends Node2D
## Bottom layer: this colony's generated nest carved into its soil, plus chamber
## contents (brood, food, fungus, refuse) and the queen. Ants navigate `nodes` /
## `links` with find_path() and ask for chamber floor points to stand on.

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

@onready var _soil: Sprite2D = $Soil
@onready var _items: Node2D = $Items
@onready var _queen: Sprite2D = $Queen


func setup(profile: RefCounted, view_size: Vector2, ground_y: float, soil_top: float) -> void:
	_soil_top = soil_top
	_rng.seed = profile.seed_value + 1

	var gen := NestGenerator.new()
	gen.generate(profile.seed_value, profile.species, view_size, ground_y, soil_top)
	nodes = gen.nodes
	links = gen.links
	chambers = gen.chambers
	dig_faces = gen.dig_faces
	entrance_x = gen.entrance_x
	entrances = gen.entrances
	entrance_xs = gen.entrance_xs

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
	_place_queen(profile.species)
	_furnish_chambers(profile)


# ---------------------------------------------------------------------------
# Navigation API used by ants
# ---------------------------------------------------------------------------

func is_chamber(id: int) -> bool:
	return chambers.has(id)


func is_entrance(id: int) -> bool:
	return entrances.has(id)


## The surface opening closest to a given x.
func nearest_entrance(x: float) -> int:
	var best := 0
	for i in entrances.size():
		if absf(entrance_xs[i] - x) < absf(entrance_xs[best] - x):
			best = i
	return entrances[best]


func chamber_role(id: int) -> String:
	return chambers[id]["role"] if chambers.has(id) else ""


func chambers_with_role(role: String) -> Array[int]:
	var ids: Array[int] = []
	for id: int in chambers:
		if chambers[id]["role"] == role:
			ids.append(id)
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
			if not came_from.has(next):
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
			if b > a:
				_carve_segment(_to_art(nodes[a]), _to_art(nodes[b]), SHAFT_RADIUS)
	for id: int in chambers:
		_carve_chamber(id)
	for id in dig_faces:
		_carve_disc(_to_art(nodes[id]), SHAFT_RADIUS + 0.8)


func _to_art(p: Vector2) -> Vector2:
	var px := float(SoilArt.PIXEL_SCALE)
	return Vector2(p.x / px, (p.y - _soil_top) / px)


func _carve_segment(a: Vector2, b: Vector2, r: float) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) / 0.75))
	for s in steps + 1:
		_carve_disc(a.lerp(b, float(s) / steps), r)


func _carve_disc(c: Vector2, r: float) -> void:
	for y in range(maxi(0, floori(c.y - r)), mini(_art_size.y, ceili(c.y + r) + 1)):
		for x in range(maxi(0, floori(c.x - r)), mini(_art_size.x, ceili(c.x + r) + 1)):
			var dx := x + 0.5 - c.x
			var dy := y + 0.5 - c.y
			if dx * dx + dy * dy <= r * r:
				_mask[y * _art_size.x + x] = 1


## Each lobe is a flattened ellipse cut off flat at the shared floor.
func _carve_chamber(id: int) -> void:
	var px := float(SoilArt.PIXEL_SCALE)
	var center := _to_art(nodes[id])
	var floor_art := _to_art(Vector2(0.0, chamber_floor_y(id))).y
	for lobe: Vector4 in chambers[id]["lobes"]:
		var c := center + Vector2(lobe.x, lobe.y) / px
		var r := Vector2(lobe.z, lobe.w) / px
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


func _furnish_chambers(profile: RefCounted) -> void:
	var species: Dictionary = profile.species
	for id: int in chambers:
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
				var count := 70 if species["food"] == "seeds" else 24
				for i in count:
					food_items[id].append(add_item(food_texture(species), zone_spot(id, "food"), "food"))
				var waste_food: String = species["food"]
				_scatter(left, right, floor_y, 8, func(): return ColonyArt.waste_bit(waste_food, _rng.randi_range(0, 1)))
			"fungus":
				var w := int(span / SoilArt.PIXEL_SCALE * 0.85)
				var h := int(ceiling / SoilArt.PIXEL_SCALE * 1.5)
				add_item(ColonyArt.fungus_garden(w, h, profile.seed_value + id), Vector2(mid, floor_y),
						"fungus", SoilArt.PIXEL_SCALE)
			"refuse":
				var w := int(span / SoilArt.PIXEL_SCALE * 0.6)
				var h := int(ceiling / SoilArt.PIXEL_SCALE * 1.2)
				add_item(ColonyArt.refuse_heap(w, h, profile.seed_value + id), Vector2(mid, floor_y),
						"refuse", SoilArt.PIXEL_SCALE)
				_scatter(left, right, floor_y, 12, func(): return ColonyArt.prey_bit(_rng.randi_range(0, 4)))


## Sets how much food a store holds (used when restoring a save).
func set_food_count(id: int, count: int, species: Dictionary) -> void:
	if not food_items.has(id):
		return
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


func queen_chamber() -> int:
	return chambers_with_role("queen")[0]


## A small heave of the queen's body as she lays.
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
	var id := queen_chamber()
	var c: Dictionary = chambers[id]
	var x := (float(c["floor_left"]) + float(c["floor_right"])) * 0.5 + 10.0
	_queen.position = Vector2(x, chamber_floor_y(id) - _queen.texture.get_height() * ColonyArt.SPRITE_SCALE * 0.5)
