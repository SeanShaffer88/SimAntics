extends Node2D
## Food the player dropped on the surface: a little heap of detailed pieces (sugar
## grains, nectar beads, orange chunks, ladybugs, seeds...) that shrinks from the top
## as ants carry crumbs away. Each kind has a hidden pull that is never shown
## on screen; players discover the colony's preferences by watching:
##   sugar   - strongest: found from furthest away, recruits the most nestmates
##   nectar  - strong, and quick to collect (ants drink it)
##   fruit   - medium-high: steady group foraging
##   protein - (dead ladybugs) medium: methodical hauling
##   seeds   - weakest: slow, casual gathering

signal depleted

const KINDS := {
	"sugar": {"pull": 1.0, "crumbs": 30, "recruits": 3, "harvest": 1.0},
	"nectar": {"pull": 0.85, "crumbs": 18, "recruits": 3, "harvest": 0.5},
	"fruit": {"pull": 0.7, "crumbs": 24, "recruits": 2, "harvest": 1.4},
	"protein": {"pull": 0.55, "crumbs": 20, "recruits": 2, "harvest": 2.2},
	"seeds": {"pull": 0.35, "crumbs": 26, "recruits": 1, "harvest": 1.8},
	"leaves": {"pull": 0.6, "crumbs": 14, "recruits": 2, "harvest": 2.4},  # leafcutters cut pieces to carry
	"insects": {"pull": 0.5, "crumbs": 10, "recruits": 2, "harvest": 2.0},  # natural finds for predators
}
const UiArt := preload("res://scripts/ui_art.gd")
## Crumbs per visible piece: big pieces (a whole ladybug) stand for several crumbs.
const CRUMBS_PER_PIECE := {"protein": 4, "insects": 2, "fruit": 2, "leaves": 1, "nectar": 1, "sugar": 1, "seeds": 1}

var kind := "sugar"
var crumbs := 0
var max_crumbs := 0

var _pieces: Array[Vector3] = []  # x, y offset (bottom centre) and variant
var _fade: Tween


func setup(food_kind: String, ground_point: Vector2, seed_value: int, crumbs_left: int = -1) -> void:
	kind = food_kind
	position = ground_point.round()
	max_crumbs = KINDS[kind]["crumbs"]
	crumbs = max_crumbs if crumbs_left < 0 else crumbs_left
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# a low heap, densest and highest in the middle
	var count := ceili(float(max_crumbs) / int(CRUMBS_PER_PIECE.get(kind, 1)))
	var spread := 7.0 + count * 0.45
	for i in count:
		var t := rng.randf() + rng.randf() - 1.0
		var height := (1.0 - t * t) * rng.randf_range(0.0, 3.0 + count * 0.2)
		_pieces.append(Vector3(roundf(t * spread), -roundf(height), rng.randi() % 3))
	_pieces.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)  # top of the heap last
	queue_redraw()


## How strongly this food draws foragers (hidden from the player).
func pull() -> float:
	return KINDS[kind]["pull"]


## How many extra nestmates each successful trip recruits.
func recruits_per_trip() -> int:
	return KINDS[kind]["recruits"]


## Seconds an ant spends cutting or drinking before it can carry a crumb away.
func harvest_time() -> float:
	return KINDS[kind]["harvest"]


func is_empty() -> bool:
	return crumbs <= 0


## Takes one crumb if any are left.
func take_crumb() -> bool:
	if crumbs <= 0:
		return false
	crumbs -= 1
	queue_redraw()
	if crumbs <= 0:
		depleted.emit()
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 0.0, 1.5)
		_fade.tween_callback(queue_free)
	return true


func _draw() -> void:
	var shown := ceili(_pieces.size() * float(crumbs) / max_crumbs)
	for i in shown:
		var d := _pieces[i]  # the top of the heap goes first
		var tex := UiArt.food_piece(kind, int(d.z))
		var size := tex.get_size()
		draw_texture(tex, Vector2(d.x - floorf(size.x * 0.5), d.y - size.y + 2.0))
