extends RefCounted
## Builds an ant-farm nest from a seed. In a thin two-dimensional formicarium, ants dig
## an interconnected web of galleries that spreads through the whole frame, cutting the
## soil into irregular slabs; chambers are widened, flat-floored stretches where
## galleries meet. Chamber roles follow what field studies show: brood in the warm
## upper-middle, the queen deep, food in the middle, refuse away from the brood (deep
## for leafcutters), and shallow chambers for resting foragers.
##
## Output (all positions in screen pixels):
##   nodes: Array[Vector2], links: Array[Array] (adjacency)
##   chambers: {node_id: {"role", "radii": Vector2, "lobes": Array[Vector4], "floor_left", "floor_right"}}
##   dig_faces: Array[int]  - dead-end gallery tips where the nest can keep growing
##   entrance_x: float

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
	entrance_x = roundf(_rng.randf_range(_width * 0.25, _width * 0.75))
	var entrance := _add_node(Vector2(entrance_x, ground_y))  # always node 0

	# Per-colony character: rows of cells, and how much of each cell is hollowed out.
	# Low fill leaves thick soil slabs with narrower galleries; high fill gives big
	# pockets separated by thin walls.
	var rows := _rng.randi_range(3, 4)
	var fill := _rng.randf_range(0.5, 0.92)
	var wall := lerpf(28.0, 12.0, fill)
	var top := _soil_top + 20.0
	var bottom := _soil_bottom - 6.0
	var row_h := (bottom - top) / rows
	var left := SIDE_MARGIN
	var right := _width - SIDE_MARGIN

	# 1. Cells across every row, each hollowed into a rounded, flat-floored chamber.
	var grid: Array[Array] = []
	for r in rows:
		var row_ids: Array[int] = []
		var skipped := false
		var x := left + _rng.randf_range(0.0, 30.0)  # stagger rows like brickwork
		while right - x > 90.0:
			var w := _rng.randf_range(150.0, 250.0)
			if right - (x + w) < 110.0:
				w = right - x  # the last cell takes what is left
			var cell := Vector2(x + w * 0.5, top + row_h * (r + 0.5) + _rng.randf_range(-8.0, 8.0))
			x += w
			if not skipped and not row_ids.is_empty() and right - x > 90.0 and _rng.randf() < 0.12:
				skipped = true
				continue  # at most one solid block per row that the ants have not dug
			var rx := (w - wall) * 0.5 * lerpf(0.55, 1.0, fill) * _rng.randf_range(0.88, 1.0)
			var ry := (row_h - wall) / (1.0 + FLOOR) * lerpf(0.5, 1.0, fill) * _rng.randf_range(0.85, 1.0)
			ry = minf(ry, rx * 0.5)  # wide, lens-shaped pockets rather than tall domes
			# chamber spans centre - ry (roof) to centre + FLOOR * ry (floor); centre it in the cell
			var center := Vector2(cell.x, cell.y + (1.0 - FLOOR) * 0.5 * ry)
			var id := _add_node(center)
			chambers[id] = _make_chamber(center, rx, ry, -1.0 if _rng.randf() < 0.5 else 1.0, true)
			row_ids.append(id)
		grid.append(row_ids)

	# 2. Openings: to side neighbours, and down to the nearest chamber in the row below.
	for r in grid.size():
		var row: Array[int] = grid[r]
		for i in row.size() - 1:
			if _rng.randf() < 0.85:
				_passage(row[i], row[i + 1])
		if r + 1 < grid.size() and not grid[r + 1].is_empty():
			for a in row:
				if _rng.randf() < 0.55:
					_passage(a, _nearest_by_x(grid[r + 1], nodes[a].x))
	_connect_components()

	# 3. Entrances: the main one plus 1-2 smaller openings elsewhere, each with a
	#    foraging gallery down through the crust into the nearest top chamber.
	entrances.append(entrance)
	entrance_xs.append(entrance_x)
	for n in _rng.randi_range(1, 2):
		for attempt in 20:
			var x := roundf(_rng.randf_range(left + 60.0, right - 60.0))
			var clear := true
			for other in entrance_xs:
				if absf(other - x) < 260.0:
					clear = false
			if clear:
				entrances.append(_add_node(Vector2(x, ground_y)))
				entrance_xs.append(x)
				break
	if not grid[0].is_empty():
		for i in entrances.size():
			var ex := entrance_xs[i]
			var first := _nearest_by_x(grid[0], ex)
			var drift := (nodes[first].x - ex) * 0.4
			_chain(entrances[i], [nodes[entrances[i]], Vector2(ex, _soil_top + 8.0),
					Vector2(ex + drift, (_soil_top + nodes[first].y) * 0.5), nodes[first]], first)

	# 4. A few galleries still being dug, pushing out from chambers into solid soil.
	var bounds := Rect2(Vector2(left + 10.0, top), Vector2(right - left - 20.0, bottom - top))
	var all_ids: Array[int] = []
	for row in grid:
		all_ids.append_array(row)
	for n in _rng.randi_range(2, 4):
		var from: int = all_ids[_rng.randi() % all_ids.size()]
		var dir := Vector2.from_angle(_rng.randf_range(-0.3, PI + 0.3))
		var tip := (nodes[from] + dir * _rng.randf_range(50.0, 80.0)).clamp(bounds.position, bounds.end)
		if tip.distance_to(nodes[from]) > 30.0:
			var stub := _chain(from, [nodes[from], tip])
			dig_faces.append(stub[stub.size() - 1])


## A short opening between two chambers.
func _passage(a: int, b: int) -> void:
	if (links[a] as Array).has(b):
		return
	_gallery(a, b)


func _nearest_by_x(ids: Array[int], x: float) -> int:
	var best: int = ids[0]
	for id in ids:
		if absf(nodes[id].x - x) < absf(nodes[best].x - x):
			best = id
	return best


## Makes sure every chamber can be reached: joins separate groups at their closest pair.
func _connect_components() -> void:
	var ids: Array[int] = []
	for id: int in chambers:
		ids.append(id)
	while true:
		var seen := {ids[0]: true}
		var queue: Array[int] = [ids[0]]
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			for nxt: int in links[cur]:
				if not seen.has(nxt):
					seen[nxt] = true
					queue.append(nxt)
		var outside: Array[int] = []
		for id in ids:
			if not seen.has(id):
				outside.append(id)
		if outside.is_empty():
			return
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for a: int in seen:
			if not chambers.has(a):
				continue
			for b in outside:
				var d := nodes[a].distance_to(nodes[b])
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
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
	var rect := Rect2(center - Vector2(rx + 20.0, ry + 16.0), Vector2(rx + 20.0, ry + 16.0) * 2.0)
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
		var dy := absf(inverse_lerp(lo, hi, nodes[id].y) - 0.6)
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
