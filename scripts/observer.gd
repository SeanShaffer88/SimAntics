extends Node2D
## How the player looks at the farm: tap an ant or chamber to learn about it,
## double-tap / pinch / mouse wheel to zoom in, and drag to pan while zoomed.
## Taps never change the simulation; this is purely for watching.

const TAP_MAX_MOVE := 12.0
const TAP_MAX_TIME := 0.35
const DOUBLE_TAP_TIME := 0.32
const MAX_ZOOM := 3.0
const PICK_RADIUS := 16.0
const LABEL_TIME := 3.5

const CHAMBER_NAMES := {
	"queen": "Queen's chamber", "nursery": "Nursery: eggs and larvae", "pupae": "Pupa chamber",
	"food": "Food store", "fungus": "Fungus garden", "refuse": "Refuse chamber",
	"alates": "Alate chamber: winged queens and males", "rest": "Resting chamber",
}

var _camera: Camera2D
var _ants: Node2D
var _tunnels: Node2D
var _label: Label
var _view := Vector2(1280, 720)
var _touches: Dictionary = {}  # index -> position
var _press_pos := Vector2.ZERO
var _press_time := 0.0
var _last_tap_time := -10.0
var _last_tap_pos := Vector2.ZERO
var _pinch_start_dist := 0.0
var _pinch_start_zoom := 1.0
var _clock := 0.0
var _followed: Node2D
var _label_left := 0.0
var _zoom_tween: Tween


func setup(camera: Camera2D, ants: Node2D, tunnels: Node2D, label: Label, view_size: Vector2) -> void:
	_camera = camera
	_ants = ants
	_tunnels = tunnels
	_label = label
	_view = view_size
	_camera.position = view_size * 0.5
	_label.modulate.a = 0.0


func _process(delta: float) -> void:
	_clock += delta
	if _label_left > 0.0:
		_label_left -= delta
		if _label_left <= 0.0:
			var fade := create_tween()
			fade.tween_property(_label, "modulate:a", 0.0, 0.6)
			_followed = null
	if _followed != null and not is_instance_valid(_followed):
		_followed = null
	if _followed != null:
		_place_label(_followed.global_position)
	queue_redraw()


func _draw() -> void:
	if _followed == null:
		return
	# a soft pulsing ring around the ant being looked at
	var r := 11.0 + sin(_clock * 6.0) * 1.5
	draw_arc(_followed.global_position, r, 0.0, TAU, 32, Color(1.0, 0.92, 0.7, 0.75), 1.0)


var input_blocked := Callable()  # returns true while another control owns the pointer


func _unhandled_input(event: InputEvent) -> void:
	if input_blocked.is_valid() and input_blocked.call():
		_touches.clear()
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(_camera.zoom.x * 1.15, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(_camera.zoom.x / 1.15, mb.position)


func _on_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		_touches[touch.index] = touch.position
		if _touches.size() == 1:
			_press_pos = touch.position
			_press_time = _clock
		elif _touches.size() == 2:
			var pts := _touches.values()
			_pinch_start_dist = (pts[0] as Vector2).distance_to(pts[1])
			_pinch_start_zoom = _camera.zoom.x
		return
	var was_single := _touches.size() == 1
	_touches.erase(touch.index)
	if not was_single:
		return
	if touch.position.distance_to(_press_pos) > TAP_MAX_MOVE or _clock - _press_time > TAP_MAX_TIME:
		return
	if _clock - _last_tap_time < DOUBLE_TAP_TIME and touch.position.distance_to(_last_tap_pos) < 40.0:
		_last_tap_time = -10.0
		_toggle_zoom(touch.position)
	else:
		_last_tap_time = _clock
		_last_tap_pos = touch.position
		_inspect(_to_world(touch.position))


func _on_drag(drag: InputEventScreenDrag) -> void:
	_touches[drag.index] = drag.position
	if _touches.size() >= 2:
		var pts := _touches.values()
		var dist := (pts[0] as Vector2).distance_to(pts[1])
		if _pinch_start_dist > 0.0:
			var mid := ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
			_zoom_at(_pinch_start_zoom * dist / _pinch_start_dist, mid)
	elif _camera.zoom.x > 1.01:
		_set_camera(_camera.position - drag.relative / _camera.zoom.x)


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------

func _to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _toggle_zoom(screen_pos: Vector2) -> void:
	var target := 2.2 if _camera.zoom.x < 1.5 else 1.0
	var world := _to_world(screen_pos)
	var end_pos := world if target > 1.0 else _view * 0.5
	if _zoom_tween != null:
		_zoom_tween.kill()
	_zoom_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_property(_camera, "zoom", Vector2.ONE * target, 0.45)
	_zoom_tween.tween_method(_set_camera, _camera.position, _clamped(end_pos, target), 0.45)


## Zooms so the world point under `screen_pos` stays under the finger/cursor.
func _zoom_at(new_zoom: float, screen_pos: Vector2) -> void:
	new_zoom = clampf(new_zoom, 1.0, MAX_ZOOM)
	var before := _to_world(screen_pos)
	_camera.zoom = Vector2.ONE * new_zoom
	_camera.force_update_scroll()
	var after := _to_world(screen_pos)
	_set_camera(_camera.position + (before - after))


func _set_camera(pos: Vector2) -> void:
	_camera.position = _clamped(pos, _camera.zoom.x)


func _clamped(pos: Vector2, zoom: float) -> Vector2:
	var half := _view * 0.5 / zoom
	return Vector2(clampf(pos.x, half.x, _view.x - half.x), clampf(pos.y, half.y, _view.y - half.y))


# ---------------------------------------------------------------------------
# Inspecting
# ---------------------------------------------------------------------------

var bird: Node2D  # taps on the bird startle it instead of inspecting
var colony: Node  # for describing the queen and brood
var food_layer: Node2D  # food piles on the surface

signal ant_inspected(ant: Node2D)


func _inspect(world: Vector2) -> void:
	if bird != null and bird.try_tap(world):
		return
	var best: Node2D = null
	var best_d := PICK_RADIUS / maxf(1.0, _camera.zoom.x * 0.6)
	for ant: Node2D in _ants.get_children():
		var d := ant.global_position.distance_to(world)
		if d < best_d:
			best_d = d
			best = ant
	var queen_d := world.distance_to(_tunnels.queen_position())
	if queen_d < 18.0 and (best == null or queen_d < best_d):
		_followed = null  # the queen is bigger than her attendants: the closer one wins
		_show(colony.describe_queen(), _tunnels.queen_position())
		return
	if best != null:
		_followed = best
		_show(best.describe(), best.global_position)
		ant_inspected.emit(best)
		return
	_followed = null
	var b = colony.brood_near(world, 7.0)
	if b != null:
		_show(colony.describe_brood(b), b.sprite.position)
		return
	if food_layer != null:
		for pile: Node2D in food_layer.get_children():
			if absf(pile.position.x - world.x) < 22.0 and absf(pile.position.y - 6.0 - world.y) < 16.0:
				_show(_describe_food(pile), pile.position)
				return
	for id: int in _tunnels.chambers:
		var c: Dictionary = _tunnels.chambers[id]
		var center: Vector2 = _tunnels.nodes[id]
		var r: Vector2 = c["radii"]
		if world.x >= float(c["floor_left"]) - 10.0 and world.x <= float(c["floor_right"]) + 10.0 \
				and world.y >= center.y - r.y and world.y <= _tunnels.chamber_floor_y(id) + 4.0:
			_show(CHAMBER_NAMES.get(c["role"], "Chamber"), world)
			return


const FOOD_LABELS := {"sugar": "Sugar cube", "nectar": "Nectar", "fruit": "Fruit slice",
		"protein": "Dead ladybugs", "seeds": "Seeds", "leaves": "Fresh leaves", "insects": "Dead insects"}


## What a food pile is and how much is left (its pull on the colony stays hidden).
func _describe_food(pile: Node2D) -> String:
	var name: String = FOOD_LABELS.get(pile.kind, "Food")
	if pile.get_meta("natural", false) and pile.kind == "seeds":
		name = "Fallen seeds"
	return "%s  ·  %d crumbs left" % [name, pile.crumbs]


func _show(text: String, world: Vector2) -> void:
	_label.text = text
	_label.reset_size()
	_place_label(world)
	_label_left = LABEL_TIME
	var fade := create_tween()
	fade.tween_property(_label, "modulate:a", 1.0, 0.2)


func _place_label(world: Vector2) -> void:
	var screen := get_viewport().get_canvas_transform() * world
	var pos := screen + Vector2(-_label.size.x * 0.5, -_label.size.y - 18.0)
	pos.x = clampf(pos.x, 8.0, _view.x - _label.size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, _view.y - _label.size.y - 8.0)
	_label.position = pos
