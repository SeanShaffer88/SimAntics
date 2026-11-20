extends Node2D
## Pebbles and stones in the soil, drawn as crisp hi-res sprites over the soil texture.
## When digging opens out right through a pebble the ants carry it away; stones that only
## jut into a gallery stay, as they do in a real ant farm.

const ColonyArt := preload("res://scripts/colony_art.gd")

var _stones: Array[Dictionary] = []  # screen-space centre, size, tone, variant
var _is_open: Callable


## `stones` from SoilArt.make_stones (art pixels); `px` art pixel size; `top` soil top.
func setup(stones: Array[Dictionary], px: float, top: float, is_open: Callable) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_is_open = is_open
	for i in stones.size():
		var st: Dictionary = stones[i]
		var c: Vector2 = st["c"] * px + Vector2(0.0, top)
		var r: float = float(st["r"]) * px
		_stones.append({"c": c, "size": Vector2(r * 2.0, r * 2.0 * float(st["squash"])) * 1.08,
				"tone": (st["tone"] as Color).lightened(0.12), "v": i % 3})
	_prune()


## Removes pebbles a tunnel now runs straight through.
func dug_near(area: Rect2) -> void:
	var removed := false
	for i in range(_stones.size() - 1, -1, -1):
		var st: Dictionary = _stones[i]
		if area.has_point(st["c"]) and _is_open.call(st["c"]):
			_stones.remove_at(i)
			removed = true
	if removed:
		queue_redraw()


func _prune() -> void:
	for i in range(_stones.size() - 1, -1, -1):
		if _is_open.call(_stones[i]["c"]):
			_stones.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for st in _stones:
		var size: Vector2 = st["size"]
		draw_texture_rect(ColonyArt.stone(int(st["v"])), Rect2(st["c"] - size * 0.5, size), false, st["tone"])
