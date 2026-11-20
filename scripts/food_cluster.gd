extends Node2D
## Food the player dropped on the surface: a SimAnt-style cluster of pixel dots that
## shrinks as ants carry crumbs away. Each kind has a hidden pull that is never shown
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
const PIXEL := 2  # matches the surface art's chunky pixels

var kind := "sugar"
var crumbs := 0
var max_crumbs := 0

var _dots: Array[Vector3] = []  # x, y offset and palette index
var _palette: Array[Color] = []
var _fade: Tween


func setup(food_kind: String, ground_point: Vector2, seed_value: int, crumbs_left: int = -1) -> void:
	kind = food_kind
	position = ground_point.round()
	max_crumbs = KINDS[kind]["crumbs"]
	crumbs = max_crumbs if crumbs_left < 0 else crumbs_left
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_palette = _colors(kind)
	# a low heap of dots, densest in the middle; two dots per crumb
	for i in max_crumbs * 2:
		var t := rng.randf() + rng.randf() - 1.0
		var x := roundi(t * 14.0)
		var height := roundi((1.0 - t * t) * rng.randf_range(0.0, 5.5))
		_dots.append(Vector3(x, -height - 1, rng.randi() % _palette.size()))
	_dots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)  # top of the heap last
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
	var visible_dots := ceili(_dots.size() * float(crumbs) / max_crumbs)
	for i in visible_dots:
		var d := _dots[_dots.size() - visible_dots + i]  # crumbs are taken from the top of the heap
		draw_rect(Rect2(d.x * PIXEL, d.y * PIXEL, PIXEL, PIXEL), _palette[int(d.z)])


static func _colors(food_kind: String) -> Array[Color]:
	match food_kind:
		"sugar":
			return [Color("#ffffff"), Color("#eef2f6"), Color("#d8e0e8"), Color("#c0c8d0")]
		"nectar":
			return [Color("#f0b030"), Color("#ffd060"), Color("#e09018"), Color("#fff0b0")]
		"fruit":
			return [Color("#f07828"), Color("#e04030"), Color("#f8a040"), Color("#fff0d8"), Color("#6aa040")]
		"protein":  # a little pile of dead ladybugs: red shells, black spots and heads
			return [Color("#d02818"), Color("#e04030"), Color("#d02818"), Color("#201818"), Color("#ff7058")]
		"leaves":
			return [Color("#5a9a3a"), Color("#6aa848"), Color("#4a8a34"), Color("#8ab84a")]
		"insects":  # natural finds: a few dead insects, browns and blacks
			return [Color("#3a2a1a"), Color("#5a4a20"), Color("#2a2020"), Color("#6a5030")]
	return [Color("#a07040"), Color("#c09a5a"), Color("#7a5a36"), Color("#d0b070")]
