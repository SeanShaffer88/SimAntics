extends PanelContainer
## The minimal food dock: five foods to drag out onto the surface. Dragging shows a
## faint copy under the finger; letting go emits `dropped` with the screen position.

signal dropped(kind: String, screen_pos: Vector2)

const ColonyArt := preload("res://scripts/colony_art.gd")
const SLOT := 40.0
const NAMES := {"sugar": "Sugar cube", "nectar": "Nectar", "fruit": "Fruit slice",
		"protein": "Ladybug", "seeds": "Seeds"}

var dragging := false
var last_drop_msec := -10000


## True while a drag is in progress or just ended (so the drop isn't also read as a tap).
func owns_pointer() -> bool:
	return dragging or Time.get_ticks_msec() - last_drop_msec < 300

var _kind := ""
var _ghost: TextureRect


func _ready() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for kind: String in ColonyArt.FOOD_TYPES:
		var slot := TextureRect.new()
		slot.texture = ColonyArt.food_icon(kind)
		slot.custom_minimum_size = Vector2(SLOT, SLOT)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.tooltip_text = NAMES[kind]
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(_on_slot_input.bind(kind))
		row.add_child(slot)
	_ghost = TextureRect.new()
	_ghost.custom_minimum_size = Vector2(SLOT, SLOT)
	_ghost.size = Vector2(SLOT, SLOT)
	_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.modulate.a = 0.75
	_ghost.top_level = true  # draws over everything, positioned in screen space
	_ghost.visible = false
	add_child(_ghost)


func _on_slot_input(event: InputEvent, kind: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		dragging = true
		_kind = kind
		_ghost.texture = ColonyArt.food_icon(kind)
		_ghost.visible = true
		_move_ghost(get_global_mouse_position())
		accept_event()


func _input(event: InputEvent) -> void:
	if not dragging:
		return
	if event is InputEventMouseMotion:
		_move_ghost(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		last_drop_msec = Time.get_ticks_msec()
		_ghost.visible = false
		dropped.emit(_kind, event.position)
		get_viewport().set_input_as_handled()


func _move_ghost(screen_pos: Vector2) -> void:
	_ghost.global_position = screen_pos - Vector2(SLOT, SLOT) * 0.5 - Vector2(0.0, SLOT * 0.6)
