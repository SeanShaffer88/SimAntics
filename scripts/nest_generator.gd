extends RefCounted
## Builds an ant-farm nest from a seed. In a thin two-dimensional formicarium, ants dig
## winding galleries down from a few entrances; side branches sprout off them and end
## in small flat-floored chambers, and galleries that meet join into loops, so the nest
## grows like a root system. Chamber roles follow what field studies show: brood in the warm
## upper-middle, the queen deep, food in the middle, refuse away from the brood (deep
## for leafcutters), and shallow chambers for resting foragers.
##
## Output (all positions in screen pixels):
##   nodes: Array[Vector2], links: Array[Array] (adjacency)
##   chambers: {node_id: {"role", "radii": Vector2, "lobes": Array[Vector4], "floor_left", "floor_right"}}
##   dig_faces: Array[int]  - dead-end gallery tips where the nest can keep growing
##   entrance_x: float

## Bump when the layout algorithm changes: saves dug under another version are re-laid.
const VERSION := 2
const FLOOR := 0.5  # chamber floor height as a fraction of its vertical radius
const SIDE_MARGIN := 40.0
const BOTTOM_MARGIN := 34.0  # leaves the stony subsoil at the bottom undug
const NODE_SPACING := 9.0  # px between nodes along a gallery

var nodes: Array[Vector2] = []
var links: Array[Array] = []
var chambers: Dictionary = {}
var dig_faces: Array[int] = []
var entrance_x := 0.0  # the main entrance (node 0)
var entrances: Array[int] = []  # every surface opening, main first
var entrance_xs: Array[float] = []

var _rng := RandomNumberGenerator.new()
var _species: Dictionary
var _soil_top := 0.0
var _soil_bottom := 0.0
var _width := 0.0


func generate(seed_value: int, species: Dictionary, view_size: Vector2, ground_y: float,
		soil_top: float) -> void:
	_species = species
	_soil_top = soil_top
	_soil_bottom = view_size.y - BOTTOM_MARGIN
	_width = view_size.x
	_rng.seed = seed_value * 7919 + 17
	var wanted: int = species["chambers"][0]
	var best := {}
	for attempt in 8:  # keep the attempt with the most chambers, stop once the species minimum is met
		_clear()
		_build(ground_y)
		if best.is_empty() or chambers.size() > best["chambers"].size():
			best = {"nodes": nodes.duplicate(), "links": links.duplicate(true), "chambers": chambers.duplicate(true),
					"dig_faces": dig_faces.duplicate(), "entrance_x": entrance_x,
					"entrances": entrances.duplicate(), "entrance_xs": entrance_xs.duplicate()}
		if chambers.size() >= wanted:
			break
	nodes = best["nodes"]
	links = best["links"]
	chambers = best["chambers"]
	dig_faces = best["dig_faces"]
	entrance_x = best["entrance_x"]
	entrances = best["entrances"]
	entrance_xs = best["entrance_xs"]
	_assign_roles()


## Grows the finished nest a little further: 2-3 new side galleries with rooms, branching
## off the existing ones. Deterministic for (colony seed, index), so a save only needs to
## remember how many expansions happened. Returns the new chamber ids.
func expand(seed_value: int, index: int) -> Array[int]:
	_rng.seed = seed_value * 104729 + index * 7907 + 3
	_rebuild_occupancy()
	_max_depth = _soil_bottom - 10.0  # older nests reach deeper
	var before := chambers.size()
	var queue: Array[Dictionary] = []
	var want := _rng.randi_range(2, 3)
	for attempt in 40:
		if chambers.size() - before >= want:
			break
		var from := _random_gallery_node()
		if from == -1:
			break
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var down := _rng.randf() < 0.35
		var dir := Vector2(_rng.randf_range(-0.4, 0.4), 1.0) if down else Vector2(side, _rng.randf_range(-0.1, 0.4))
		_grow({"from": from, "dir": dir.normalized(), "kind": "trunk" if down else "side", "gen": 4,
				"steps": _rng.randi_range(3, 8)}, queue)
		queue.clear()  # no further sub-branches: expansions stay small
	var added: Array[int] = []
	for id: int in chambers:
		if chambers[id]["role"] == "rest" and not _initial.has(id):
			added.append(id)
			_initial[id] = true
	return added


var _initial := {}  # chamber ids that existed before any expansion (plus those since handed out)


func _rebuild_occupancy() -> void:
	if not _occ.is_empty() and _occ_built:
		return
	_occ.clear()
	for id in nodes.size():
		_occupy(id)
	for id: int in chambers:
		var r: Vector2 = chambers[id]["radii"]
		var c := nodes[id]
		var x := c.x - r.x
		while x <= c.x + r.x:
			var y := c.y - r.y
			while y <= c.y + r.y * FLOOR:
				if not _occ.has(_cell(Vector2(x, y))):
					_occ[_cell(Vector2(x, y))] = id
				y += CELL * 0.5
			x += CELL * 0.5
	for id: int in chambers:
		_initial[id] = true
	_occ_built = true


var _occ_built := false


func is_chamber(id: int) -> bool:
	return chambers.has(id)


## Ids of chambers with a given role ("queen", "nursery", "food", "fungus", "refuse", "rest").
func chambers_with_role(role: String) -> Array[int]:
	var ids: Array[int] = []
	for id: int in chambers:
		if chambers[id]["role"] == role:
			ids.append(id)
	return ids


func _clear() -> void:
	nodes.clear()
	links.clear()
	chambers.clear()
	dig_faces.clear()
	entrances.clear()
	entrance_xs.clear()


func _add_node(p: Vector2) -> int:
	nodes.append(p)
	links.append([])
	return nodes.size() - 1


func _link(a: int, b: int) -> void:
	links[a].append(b)
	links[b].append(a)


func _depth_t(y: float) -> float:
	return clampf((y - _soil_top) / (_soil_bottom - _soil_top), 0.0, 1.0)


# ---------------------------------------------------------------------------
# The gallery web
# ---------------------------------------------------------------------------

func _build(ground_y: float) -> void:
	_occ.clear()
	var left := SIDE_MARGIN
	var right := _width - SIDE_MARGIN
	var d_range: Array = _species["depth"]
	_max_depth = lerpf(_soil_top + 120.0, _soil_bottom - 10.0, _rng.randf_range(float(d_range[0]), float(d_range[1])))
	_wiggle = _rng.randf_range(0.35, 0.6)  # per colony: straighter or twistier galleries
	_branchiness = _rng.randf_range(0.6, 0.95)

	# 1. Entrances: the main one plus 1-2 others, each under its own little mound.
	entrance_x = roundf(_rng.randf_range(_width * 0.3, _width * 0.7))
	entrances.append(_add_node(Vector2(entrance_x, ground_y)))  # always node 0
	entrance_xs.append(entrance_x)
	for n in _rng.randi_range(1, 2):
		for attempt in 20:
			var x := roundf(_rng.randf_range(left + 70.0, right - 70.0))
			var clear := true
			for other in entrance_xs:
				if absf(other - x) < 240.0:
					clear = false
			if clear:
				entrances.append(_add_node(Vector2(x, ground_y)))
				entrance_xs.append(x)
				break

	# 2. From each entrance a main gallery winds down through the soil; branches sprout
	#    off it sideways and end in small chambers, much as real nests grow outward and
	#    down from their entrances. Galleries that run into another one usually join it.
	var queue: Array[Dictionary] = []
	for i in entrances.size():
		var top := _chain(entrances[i], [nodes[entrances[i]], Vector2(entrance_xs[i], _soil_top + 10.0)])
		var top_id: int = top[top.size() - 1]
		_occupy_chain(top)
		queue.append({"from": top_id, "dir": Vector2.DOWN, "kind": "trunk", "gen": 0,
				"steps": int((_max_depth - nodes[top_id].y) / SEG * _rng.randf_range(0.75, 1.0))})
	var wanted: int = int(_species["chambers"][1]) + _rng.randi_range(8, 13)
	var guard := 0
	while not queue.is_empty() and guard < 200:
		guard += 1
		_grow(queue.pop_front(), queue)

	# 3. Keep branching off existing galleries until the colony has dug enough rooms.
	var tries := 0
	while chambers.size() < wanted and tries < 90:
		tries += 1
		var from := _random_gallery_node()
		if from == -1:
			break
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		_grow({"from": from, "dir": Vector2(side, _rng.randf_range(-0.15, 0.35)).normalized(), "kind": "side",
				"gen": 2, "steps": _rng.randi_range(2, 6)}, queue)
		while not queue.is_empty():
			_grow(queue.pop_front(), queue)
	_connect_components()


const SEG := 20.0  # px per growth step of a gallery
const CLEAR := 22.0  # galleries keep this far apart unless they join
const CELL := 10.0

var _occ: Dictionary = {}  # Vector2i cell -> node id, for keeping galleries apart
var _max_depth := 0.0
var _wiggle := 0.35
var _branchiness := 0.6


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func _occupy(id: int) -> void:
	_occ[_cell(nodes[id])] = id


func _occupy_chain(ids: Array[int]) -> void:
	for id in ids:
		_occupy(id)


## The nearest dug node within CLEAR of p that is not in `own`, or -1.
func _hit(p: Vector2, own: Dictionary) -> int:
	var c := _cell(p)
	var best := -1
	var best_d := CLEAR
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var id: int = _occ.get(c + Vector2i(dx, dy), -1)
			if id == -1 or own.has(id):
				continue
			var d := nodes[id].distance_to(p)
			if d < best_d:
				best_d = d
				best = id
	return best


func _random_gallery_node() -> int:
	var keys := _occ.keys()
	for attempt in 30:
		var id: int = _occ[keys[_rng.randi() % keys.size()]]
		if not chambers.has(id) and not entrances.has(id) and nodes[id].y > _soil_top + 24.0 \
				and (links[id] as Array).size() == 2:
			return id
	return -1


## Grows one gallery from an existing node, step by step, then decides how it ends.
func _grow(g: Dictionary, queue: Array[Dictionary]) -> void:
	var start: int = g["from"]
	var kind: String = g["kind"]
	var gen: int = g["gen"]
	var heading: Vector2 = g["dir"]
	var steps: int = g["steps"]
	var points: Array[Vector2] = [nodes[start]]
	var own := {start: true}
	for n: int in links[start]:  # don't collide with the gallery we branch from
		own[n] = true
		for m: int in links[n]:
			own[m] = true
	var joined := -1
	var p := nodes[start]
	for i in steps:
		heading = heading.rotated(_rng.randf_range(-_wiggle, _wiggle))
		if kind == "trunk":  # keep heading down, wandering side to side
			heading = heading.lerp(Vector2(heading.x * 0.6, 1.0), 0.35).normalized()
		else:  # side branches run roughly level, sagging a little
			var sx := signf(heading.x) if heading.x != 0.0 else 1.0
			heading = heading.lerp(Vector2(sx, 0.12), 0.3).normalized()
		var next := p + heading * SEG * _rng.randf_range(0.85, 1.15)
		if next.x < SIDE_MARGIN + 10.0 or next.x > _width - SIDE_MARGIN - 10.0 \
				or next.y < _soil_top + 14.0 or next.y > _max_depth:
			break
		var hit := _hit(next, own)
		if hit == -1:
			hit = _hit((p + next) * 0.5, own)
		if hit != -1:
			if not chambers.has(hit) and i > 0 and _rng.randf() < 0.75:
				joined = hit  # broke into a neighbouring gallery: a loop
			break
		points.append(next)
		p = next
	if points.size() < 2 and joined == -1:
		return
	var ids := _chain(start, points)
	if joined != -1:
		var tail: int = ids[ids.size() - 1]
		var extra := _chain(tail, [nodes[tail], nodes[joined]], joined)
		ids.append_array(extra.slice(1))
	for id in ids:
		own[id] = true
	_occupy_chain(ids)
	if joined != -1:
		return
	var tip: int = ids[ids.size() - 1]

	# side branches and forks sprouting along this gallery
	var since := 0
	for k in range(2, ids.size() - 2):
		since += 1
		if since < 4 or _rng.randf() > _branchiness * 0.55:
			continue
		since = 0
		var at: int = ids[k]
		if kind == "trunk" or gen < 4:
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			if kind != "trunk" and _rng.randf() < 0.45:
				queue.append({"from": at, "dir": Vector2(_rng.randf_range(-0.4, 0.4), 1.0).normalized(),
						"kind": "trunk", "gen": gen + 1, "steps": _rng.randi_range(3, 8)})
			else:
				queue.append({"from": at, "dir": Vector2(side, _rng.randf_range(-0.2, 0.3)).normalized(),
						"kind": "side", "gen": gen + 1, "steps": _rng.randi_range(3, 11)})

	# how the gallery ends: a chamber hanging below it, a chamber at its end, or a dig face
	var roll := _rng.randf()
	if kind == "trunk" or roll < 0.55:
		if _hang_chamber(tip, own, kind == "trunk"):
			return
	elif roll < 0.85:
		if _end_chamber(tip, heading, own):
			return
	dig_faces.append(tip)


## A chamber hanging from the end of a gallery, entered through its roof.
func _hang_chamber(tip: int, own: Dictionary, big: bool) -> bool:
	for attempt in 3:
		var rx := _rng.randf_range(28.0, 40.0) if big else _rng.randf_range(18.0, 30.0)
		rx *= 1.0 - attempt * 0.2
		var ry := minf(rx * _rng.randf_range(0.55, 0.75), 22.0)
		var drop := _rng.randf_range(6.0, 16.0)
		var center := nodes[tip] + Vector2(_rng.randf_range(-rx * 0.3, rx * 0.3), drop + ry)
		if _place_chamber(tip, center, rx, ry, own):
			return true
	return false


## A chamber at the end of a level gallery, entered from the side.
func _end_chamber(tip: int, heading: Vector2, own: Dictionary) -> bool:
	for attempt in 3:
		var rx := _rng.randf_range(18.0, 28.0) * (1.0 - attempt * 0.2)
		var ry := minf(rx * _rng.randf_range(0.55, 0.75), 20.0)
		var side := signf(heading.x) if heading.x != 0.0 else 1.0
		var center := nodes[tip] + Vector2(side * (rx * 0.7), ry * 0.3)
		if _place_chamber(tip, center, rx, ry, own):
			return true
	return false


func _place_chamber(tip: int, center: Vector2, rx: float, ry: float, own: Dictionary) -> bool:
	center = center.round()
	if not _fits(center, rx, ry):
		return false
	# no other gallery may pass through the room
	var x := center.x - rx - 6.0
	while x <= center.x + rx + 6.0:
		var y := center.y - ry - 6.0
		while y <= center.y + ry * FLOOR + 6.0:
			var hit := _hit(Vector2(x, y), own)
			if hit != -1 and nodes[hit].distance_to(Vector2(x, y)) < 10.0:
				return false
			y += CELL
		x += CELL
	var id := _add_node(center)
	chambers[id] = _make_chamber(center, rx, ry, -1.0 if _rng.randf() < 0.5 else 1.0, true)
	var path := _chain(tip, [nodes[tip], center], id)
	_occupy_chain(path)
	# reserve the room's footprint so later galleries steer around it
	x = center.x - rx
	while x <= center.x + rx:
		var y := center.y - ry
		while y <= center.y + ry * FLOOR:
			if not _occ.has(_cell(Vector2(x, y))):
				_occ[_cell(Vector2(x, y))] = id
			y += CELL * 0.5
		x += CELL * 0.5
	return true


## Makes sure every room and entrance can be reached from the main entrance: joins
## separate networks at their closest pair of nodes.
func _connect_components() -> void:
	for guard in 8:
		var seen := {0: true}
		var queue: Array[int] = [0]
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			for nxt: int in links[cur]:
				if not seen.has(nxt):
					seen[nxt] = true
					queue.append(nxt)
		if seen.size() == nodes.size():
			return
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for a in range(0, nodes.size(), 2):
			if not seen.has(a) or chambers.has(a) or entrances.has(a):
				continue
			for b in range(1, nodes.size(), 2):
				if seen.has(b) or chambers.has(b) or entrances.has(b):
					continue
				var d := nodes[a].distance_squared_to(nodes[b])
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
		if best_a == -1:
			return
		_gallery(best_a, best_b)


## A slightly curving gallery between two existing nodes.
func _gallery(a: int, b: int) -> void:
	var pa := nodes[a]
	var pb := nodes[b]
	var bend := (pb - pa).orthogonal().normalized() * pa.distance_to(pb) * _rng.randf_range(-0.1, 0.1)
	_chain(a, [pa, (pa + pb) * 0.5 + bend, pb], b)


## Joins `points` (points[0] is node `start`) with a smooth Catmull-Rom curve of nodes
## about NODE_SPACING apart. If `end` is given, the last point is that existing node.
## Returns the node ids at each point, starting with `start`.
func _chain(start: int, points: Array[Vector2], end: int = -1) -> Array[int]:
	var ids: Array[int] = [start]
	var prev := start
	for i in points.size() - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, points.size() - 1)]
		var samples := maxi(1, ceili(p1.distance_to(p2) / NODE_SPACING))
		for k in range(1, samples + 1):
			var id: int
			if end != -1 and i == points.size() - 2 and k == samples:
				id = end
			else:
				id = _add_node(_catmull_rom(p0, p1, p2, p3, float(k) / samples))
			_link(prev, id)
			prev = id
		ids.append(prev)
	return ids


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 \
			+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _fits(center: Vector2, rx: float, ry: float) -> bool:
	if center.x - rx < SIDE_MARGIN or center.x + rx > _width - SIDE_MARGIN:
		return false
	if center.y - ry < _soil_top + 12.0 or center.y + ry > _soil_bottom:
		return false
	var rect := Rect2(center - Vector2(rx + 14.0, ry + 12.0), Vector2(rx + 14.0, ry + 12.0) * 2.0)
	for id: int in chambers:
		var r: Vector2 = chambers[id]["radii"]
		if rect.intersects(Rect2(nodes[id] - r, r * 2.0)):
			return false
	return true


## Real chambers are lobed: a main flattened ellipse plus 0-2 smaller side lobes on one floor.
## `compact` keeps the lobes inside the main outline (for chambers packed into cells),
## giving a bumpy, hand-dug roof instead of side extensions.
func _make_chamber(center: Vector2, rx: float, ry: float, side: float, compact: bool = false) -> Dictionary:
	var lobes: Array[Vector4] = [Vector4(0.0, 0.0, rx, ry)]
	for i in _rng.randi_range(1 if compact else 0, 2):
		var lobe_rx := rx * (_rng.randf_range(0.4, 0.55) if compact else _rng.randf_range(0.4, 0.65))
		var lobe_ry := ry * (_rng.randf_range(0.85, 1.1) if compact else _rng.randf_range(0.7, 0.95))
		var spread := _rng.randf_range(0.3, 0.45) if compact else _rng.randf_range(0.55, 0.85)
		var dx := side * rx * spread * (1.0 if i == 0 else -0.8)
		var floor_dy := FLOOR * (ry - lobe_ry)  # keep every lobe's floor level with the main floor
		lobes.append(Vector4(dx, floor_dy, lobe_rx, lobe_ry))
	var left := INF
	var right := -INF
	var half_floor := sqrt(1.0 - FLOOR * FLOOR)  # ellipse half-width at floor height
	for lobe in lobes:
		left = minf(left, center.x + lobe.x - lobe.z * half_floor * 0.85)
		right = maxf(right, center.x + lobe.x + lobe.z * half_floor * 0.85)
	return {
		"role": "rest", "radii": Vector2(rx, ry), "lobes": lobes,
		"floor_left": left, "floor_right": right,
	}


# ---------------------------------------------------------------------------
# Chamber roles
# ---------------------------------------------------------------------------

## Chamber roles, laid out like a mature nest: the queen in a central chamber with
## the brood around her (larvae and pupae kept in separate chambers), alates waiting
## in an upper chamber, food and fungus in the middle, refuse well away from the brood
## (deep for leafcutters), and the rest as resting space for workers.
func _assign_roles() -> void:
	var ids: Array[int] = []
	for id: int in chambers:
		ids.append(id)
	ids.sort_custom(func(a: int, b: int) -> bool: return nodes[a].y < nodes[b].y)
	var free := ids.duplicate()
	var lo := nodes[ids[0]].y
	var hi := nodes[ids[ids.size() - 1]].y

	# queen: near the middle of the frame, a little over half way down
	var queen: int = free[0]
	var best_score := INF
	for id: int in free:
		var dx := absf(nodes[id].x - _width * 0.5) / _width
		var dy := absf(inverse_lerp(lo, hi, nodes[id].y) - 0.75)
		if dx + dy < best_score:
			best_score = dx + dy
			queen = id
	chambers[queen]["role"] = "queen"
	free.erase(queen)

	# nurseries and the pupa chamber: the chambers closest to the queen
	var by_queen := free.duplicate()
	by_queen.sort_custom(func(a: int, b: int) -> bool:
		return nodes[a].distance_to(nodes[queen]) < nodes[b].distance_to(nodes[queen]))
	var nursery_count := clampi(ids.size() / 7, 1, 3)
	for n in nursery_count:
		chambers[by_queen[n]]["role"] = "nursery"
		free.erase(by_queen[n])
	if ids.size() >= 8:
		chambers[by_queen[nursery_count]]["role"] = "pupae"
		free.erase(by_queen[nursery_count])

	# alates wait in an upper chamber until their nuptial flight
	if ids.size() >= 9:
		var alate := _closest_to_depth(free, 0.15)
		chambers[alate]["role"] = "alates"
		free.erase(alate)

	if _species["refuse_deep"]:
		var deep: int = free.pop_back()
		chambers[deep]["role"] = "refuse"
	else:
		var far := -1
		var best := -1.0
		for id: int in free.slice(1):  # never the top chamber, foragers rest there
			var d := nodes[id].distance_to(nodes[queen])
			if d > best:
				best = d
				far = id
		if far != -1:
			chambers[far]["role"] = "refuse"
			free.erase(far)

	var garden_count: int = _species["fungus_gardens"]
	if garden_count > 0:
		garden_count += ids.size() / 7
	for n in garden_count:
		if free.size() <= 2:
			break
		var pick := _closest_to_depth(free, 0.45 + 0.1 * (n % 3))
		chambers[pick]["role"] = "fungus"
		free.erase(pick)

	var food_count: int = maxi(1, _species["granaries"]) + ids.size() / 8
	if _species["food"] == "fungus":
		food_count = 0
	for n in food_count:
		if free.size() <= 2:
			break
		var pick := _closest_to_depth(free, 0.45 + 0.15 * (n % 3))
		chambers[pick]["role"] = "food"
		free.erase(pick)
	# Whatever remains is resting space for workers.


func _closest_to_depth(candidates: Array, depth_fraction: float) -> int:
	var lo := INF
	var hi := -INF
	for id: int in chambers:
		lo = minf(lo, nodes[id].y)
		hi = maxf(hi, nodes[id].y)
	var target := lerpf(lo, hi, depth_fraction)
	var best: int = candidates[0]
	for id: int in candidates:
		if absf(nodes[id].y - target) < absf(nodes[best].y - target):
			best = id
	return best
