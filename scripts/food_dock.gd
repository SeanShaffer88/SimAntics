extends PanelContainer
## The minimal food dock: five foods. Tapping one drops it at a random spot on the
## surface; the icon gives a small press so the tap feels answered.

signal tapped(kind: String)

const ColonyArt := preload("res://scripts/colony_art.gd")
const UiArt := preload("res://scripts/ui_art.gd")
const SLOT := 57.0  # 30% bigger than before, easier to tap
const NAMES := {"sugar": "Sugar cube", "nectar": "Nectar", "fruit": "Fruit slice",
		"protein": "Ladybug", "seeds": "Seeds"}

var last_tap_msec := -10000


## True just after a tap, so the same touch isn't also read as a tap on the colony.
func owns_pointer() -> bool:
	return Time.get_ticks_msec() - last_tap_msec < 300


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # smooth, detailed icons
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for kind: String in ColonyArt.FOOD_TYPES:
		var slot := TextureRect.new()
		slot.texture = UiArt.food_icon(kind)
		slot.custom_minimum_size = Vector2(SLOT, SLOT)
		slot.pivot_offset = Vector2(SLOT, SLOT) * 0.5
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.tooltip_text = NAMES[kind]
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(_on_slot_input.bind(kind, slot))
		row.add_child(slot)


func _on_slot_input(event: InputEvent, kind: String, slot: TextureRect) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		last_tap_msec = Time.get_ticks_msec()
		var press := slot.create_tween()
		press.tween_property(slot, "scale", Vector2.ONE * 0.82, 0.06)
		press.tween_property(slot, "scale", Vector2.ONE, 0.12)
		tapped.emit(kind)
		accept_event()
