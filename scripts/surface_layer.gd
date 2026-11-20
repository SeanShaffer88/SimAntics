extends Node2D
## Top layer: sky, backdrop props, ground line and the entrance mound for one of five
## surface presets. Changing preset cross-fades a second sprite in with a Tween.

const PixelArt := preload("res://scripts/pixel_art_factory.gd")
const SurfaceArt := preload("res://scripts/surface_art.gd")

const ANT_HALF_HEIGHT := 6.0
const FADE_TIME := 0.9

var current_preset := -1

var _ground_y := 0.0
var _textures: Array[ImageTexture] = []
var _tween: Tween

@onready var _backdrop: Sprite2D = $Backdrop
@onready var _incoming: Sprite2D = $Incoming


## `entrance_xs`: every nest opening, the main one first.
func setup(view_size: Vector2, ground_y: float, soil_top: float, entrance_xs: Array[float], seed_value: int,
		start_preset: int = 0) -> void:
	_ground_y = ground_y
	var px := SurfaceArt.PIXEL_SCALE
	var extra_cols := []
	for x in entrance_xs.slice(1):
		extra_cols.append(int(x / px))
	_textures.clear()
	for i in PixelArt.surface_preset_count():
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value + i * 101
		var img := SurfaceArt.make_surface_image(int(view_size.x / px), int(soil_top / px), int(ground_y / px),
				int(entrance_xs[0] / px), rng, i, extra_cols)
		_textures.append(ImageTexture.create_from_image(img))
	for sprite: Sprite2D in [_backdrop, _incoming]:
		sprite.position = Vector2.ZERO
		sprite.scale = Vector2(px, px)
	_incoming.modulate.a = 0.0
	show_preset(start_preset, false)


func preset_names() -> PackedStringArray:
	var names := PackedStringArray()
	for i in _textures.size():
		names.append(PixelArt.surface_preset_name(i))
	return names


## Shows a preset, cross-fading from the current one unless `fade` is false.
func show_preset(index: int, fade: bool = true) -> void:
	index = wrapi(index, 0, _textures.size())
	if index == current_preset:
		return
	_interrupt_fade()
	current_preset = index
	if not fade:
		_backdrop.texture = _textures[index]
		return
	_incoming.texture = _textures[index]
	_incoming.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_incoming, "modulate:a", 1.0, FADE_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_on_fade_finished)


## Y position (sprite centre) at which an ant walks along the ground.
func get_walk_y() -> float:
	return _ground_y - ANT_HALF_HEIGHT


## A new preset was picked mid-fade: settle on whichever image is mostly visible.
func _interrupt_fade() -> void:
	if _tween == null:
		return
	_tween.kill()
	_tween = null
	if _incoming.modulate.a >= 0.5:
		_backdrop.texture = _incoming.texture
	_clear_incoming()


func _on_fade_finished() -> void:
	_tween = null
	_backdrop.texture = _incoming.texture
	_clear_incoming()


func _clear_incoming() -> void:
	_incoming.texture = null
	_incoming.modulate.a = 0.0
