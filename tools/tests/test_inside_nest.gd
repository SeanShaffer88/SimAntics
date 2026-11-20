extends SceneTree
## Plays a colony at 10x speed and checks that no ant or brood item ever sits inside
## solid soil (outside the dug tunnels and chambers).
## Run:  godot --path . -s res://tools/tests/test_inside_nest.gd -- --colony-seed=3 [--mature]
## Exits with code 0 when everything passes, 1 otherwise.

const RUN_SECONDS := 60.0  # real time; 10 minutes of colony time

var _main: Node
var _start := 0
var _frames := 0
var _bad := {}


func _initialize() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	_start = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	var real := (Time.get_ticks_msec() - _start) / 1000.0
	Engine.time_scale = 10.0
	if real < 2.0:
		return false
	var nest = _main._subterranean
	_frames += 1
	if _frames % 20 == 0:
		for ant in _main.get_node("Ants").get_children():
			if ant.position.y > 140.0 and nest.is_solid(ant.position) and nest.is_solid(ant.position + Vector2(0, -3)):
				var key := "ant in soil at node %d (chamber %s, state %d, job %s, wall %s)" % [ant._current_node,
						nest.is_chamber(ant._current_node), ant.state, ant._task.get("type", "-"), ant._on_wall]
				_bad[key] = int(_bad.get(key, 0)) + 1
		for b in _main.colony.brood:
			if nest.is_solid(b.sprite.position + Vector2(0, -2)):
				var key := "brood in soil in chamber %d zone %s" % [b.chamber, b.zone]
				_bad[key] = int(_bad.get(key, 0)) + 1
	if real < RUN_SECONDS:
		return false
	Engine.time_scale = 1.0
	if _bad.is_empty():
		print("PASS  everything stayed inside the nest")
		quit(0)
	else:
		for key in _bad:
			print("FAIL  %s  (%d samples)" % [key, _bad[key]])
		quit(1)
	return true
