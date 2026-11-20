extends SceneTree
## Regression tests for the nest generator, across many colony seeds.
## Run:  godot --headless --path . -s res://tools/tests/test_nest_generator.gd
## Exits with code 0 when everything passes, 1 otherwise.

const NestGenerator := preload("res://scripts/nest_generator.gd")
const ColonyProfile := preload("res://scripts/colony_profile.gd")

const SEEDS := 300
const VIEW := Vector2(1280, 720)
const GROUND_Y := 120.0
const SOIL_TOP := 128.0

var _failures: Array[String] = []


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	for seed_value in range(1, SEEDS + 1):
		var profile = ColonyProfile.from_seed(seed_value)
		var gen := NestGenerator.new()
		gen.generate(seed_value, profile.species, VIEW, GROUND_Y, SOIL_TOP)
		_check_reachable(seed_value, gen)
		_check_no_overlap(seed_value, gen)
		_check_in_bounds(seed_value, gen)
		_check_roles(seed_value, gen)
		if seed_value % 25 == 0:
			_check_deterministic(seed_value, profile, gen)
			_check_expansion(seed_value, profile, gen)
	var ms := Time.get_ticks_msec() - started
	if _failures.is_empty():
		print("PASS  nest generator: %d seeds, %d ms" % [SEEDS, ms])
		quit(0)
	else:
		for f in _failures.slice(0, 30):
			print("FAIL  ", f)
		print("%d failures across %d seeds" % [_failures.size(), SEEDS])
		quit(1)


func _fail(seed_value: int, what: String) -> void:
	_failures.append("seed %d: %s" % [seed_value, what])


func _check_reachable(seed_value: int, gen) -> void:
	var seen := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for nxt: int in gen.links[cur]:
			if not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
	for id: int in gen.chambers:
		if not seen.has(id):
			_fail(seed_value, "chamber %d cannot be reached from the entrance" % id)
	for id in gen.entrances:
		if not seen.has(id):
			_fail(seed_value, "entrance %d is not connected" % id)


func _check_no_overlap(seed_value: int, gen) -> void:
	var ids: Array = gen.chambers.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Rect2 = _rect(gen, ids[i])
			var b: Rect2 = _rect(gen, ids[j])
			if a.grow(-2.0).intersects(b.grow(-2.0)):
				_fail(seed_value, "chambers %d and %d overlap" % [ids[i], ids[j]])


func _rect(gen, id: int) -> Rect2:
	var c: Dictionary = gen.chambers[id]
	var r: Vector2 = c["radii"]
	var center: Vector2 = gen.nodes[id]
	return Rect2(Vector2(c["floor_left"], center.y - r.y), Vector2(c["floor_right"] - c["floor_left"], r.y * 1.5))


func _check_in_bounds(seed_value: int, gen) -> void:
	for i in gen.nodes.size():
		var p: Vector2 = gen.nodes[i]
		if p.x < 0.0 or p.x > VIEW.x or p.y < GROUND_Y - 1.0 or p.y > VIEW.y:
			_fail(seed_value, "node %d out of the frame at %s" % [i, p])
			return


func _check_roles(seed_value: int, gen) -> void:
	var counts := {}
	for id: int in gen.chambers:
		var role: String = gen.chambers[id]["role"]
		counts[role] = int(counts.get(role, 0)) + 1
	if int(counts.get("queen", 0)) != 1:
		_fail(seed_value, "expected one queen chamber, found %d" % int(counts.get("queen", 0)))
	if int(counts.get("nursery", 0)) < 1:
		_fail(seed_value, "no nursery")
	if gen.chambers.size() < 5:
		_fail(seed_value, "only %d chambers" % gen.chambers.size())


## Expanding a nest keeps it valid, and replaying the same expansions gives the same nest.
func _check_expansion(seed_value: int, profile, gen) -> void:
	var before: int = gen.chambers.size()
	for i in 3:
		gen.expand(seed_value, i)
	if gen.chambers.size() <= before:
		_fail(seed_value, "expansion added no chambers")
	_check_reachable(seed_value, gen)
	_check_no_overlap(seed_value, gen)
	_check_in_bounds(seed_value, gen)
	var again := NestGenerator.new()
	again.generate(seed_value, profile.species, VIEW, GROUND_Y, SOIL_TOP)
	for i in 3:
		again.expand(seed_value, i)
	if again.nodes != gen.nodes:
		_fail(seed_value, "replaying expansions gave a different nest")


func _check_deterministic(seed_value: int, profile, gen) -> void:
	var again := NestGenerator.new()
	again.generate(seed_value, profile.species, VIEW, GROUND_Y, SOIL_TOP)
	if again.nodes.size() != gen.nodes.size() or again.nodes != gen.nodes or again.chambers.size() != gen.chambers.size():
		_fail(seed_value, "same seed gave a different nest")
