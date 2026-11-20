extends Control
## Unobtrusive surface picker. A small corner button opens a bar for cycling presets
## (arrow buttons, a horizontal swipe, or the arrow keys); OK locks the choice, and
## tapping the corner button again closes the bar and reverts to the locked preset.

signal preview_requested(index: int)
signal preset_locked(index: int)
signal picker_toggled(open: bool)

const PixelArt := preload("res://scripts/pixel_art_factory.gd")
const UiArt := preload("res://scripts/ui_art.gd")

const SWIPE_DISTANCE := 80.0
const PANEL_FADE := 0.2
const TEXT_COLOR := Color("#f0dcb4")
const BORDER := Color("#b07c48")

var _names := PackedStringArray()
var _locked := 0
var _preview := 0
var _open := false
var _touch_start := Vector2.ZERO
var _touch_active := false
var _panel_tween: Tween

@onready var _toggle: Button = $ToggleButton
@onready var _picker: PanelContainer = $Picker
@onready var _prev: Button = $Picker/Row/PrevButton
@onready var _name_label: Label = $Picker/Row/NameLabel
@onready var _next: Button = $Picker/Row/NextButton
@onready var _confirm: Button = $Picker/Row/ConfirmButton


func _ready() -> void:
	theme = _build_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_toggle.icon = UiArt.surface_icon()
	_toggle.pressed.connect(_on_toggle_pressed)
	_prev.pressed.connect(_step.bind(-1))
	_next.pressed.connect(_step.bind(1))
	_confirm.pressed.connect(_lock_choice)
	_picker.visible = false
	_picker.modulate.a = 0.0


func setup(names: PackedStringArray, locked_index: int) -> void:
	_names = names
	_locked = locked_index
	_preview = locked_index
	_refresh_label()


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_start = touch.position
			_touch_active = true
		elif _touch_active:
			_touch_active = false
			var drag := touch.position - _touch_start
			if absf(drag.x) >= SWIPE_DISTANCE and absf(drag.x) > absf(drag.y) * 1.5:
				_step(-1 if drag.x > 0.0 else 1)  # swipe left shows the next preset
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_step(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_lock_choice()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()


func _on_toggle_pressed() -> void:
	if _open:
		_cancel()
	else:
		_open_picker()


func _open_picker() -> void:
	_open = true
	_preview = _locked
	_refresh_label()
	_picker.visible = true
	_fade_picker(1.0)
	picker_toggled.emit(true)


func _close_picker() -> void:
	_open = false
	_touch_active = false
	_fade_picker(0.0)
	picker_toggled.emit(false)


func _fade_picker(target: float) -> void:
	if _panel_tween != null:
		_panel_tween.kill()
	_panel_tween = create_tween()
	_panel_tween.tween_property(_picker, "modulate:a", target, PANEL_FADE)
	if target <= 0.0:
		_panel_tween.tween_callback(_picker.hide)


func _step(direction: int) -> void:
	if _names.is_empty():
		return
	_preview = wrapi(_preview + direction, 0, _names.size())
	_refresh_label()
	preview_requested.emit(_preview)


func _lock_choice() -> void:
	_locked = _preview
	preset_locked.emit(_locked)
	_close_picker()


func _cancel() -> void:
	if _preview != _locked:
		_preview = _locked
		preview_requested.emit(_locked)
	_close_picker()


func _refresh_label() -> void:
	if _names.is_empty():
		return
	_name_label.text = "%s  %d/%d" % [_names[_preview], _preview + 1, _names.size()]


# ---------------------------------------------------------------------------
# Pixel-styled theme (square corners, earth tones)
# ---------------------------------------------------------------------------

func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_stylebox("panel", "PanelContainer", UiArt.frame_style("panel"))
	t.set_stylebox("normal", "Button", UiArt.frame_style("normal"))
	t.set_stylebox("hover", "Button", UiArt.frame_style("hover"))
	t.set_stylebox("pressed", "Button", UiArt.frame_style("pressed"))
	t.set_stylebox("disabled", "Button", _box(Color(0.22, 0.14, 0.08, 0.5), Color("#8a5a2e")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "Button", TEXT_COLOR)
	t.set_color("font_color", "Label", TEXT_COLOR)
	return t


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(2)
	box.set_content_margin_all(6)
	return box
