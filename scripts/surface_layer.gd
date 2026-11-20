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
	_textures.resize(PixelArt.surface_preset_count())  # each scene is drawn the first time it is shown
	_build_args = [view_size, soil_top, entrance_xs, extra_cols, seed_value]
	for sprite: Sprite2D in [_backdrop, _incoming]:
		sprite.position = Vector2.ZERO
		sprite.scale = Vector2(px, px) / SurfaceArt.SS  # the image is at full screen resolution
	_incoming.modulate.a = 0.0
	show_preset(start_preset, false)


var _build_args := []


func _texture_for(i: int) -> ImageTexture:
	if _textures[i] == null:
		var px := SurfaceArt.PIXEL_SCALE
		var view_size: Vector2 = _build_args[0]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_build_args[4]) + i * 101
		var img := SurfaceArt.make_surface_image(int(view_size.x / px), int(float(_build_args[1]) / px),
				int(_ground_y / px), int((_build_args[2] as Array)[0] / px), rng, i, _build_args[3])
		_textures[i] = ImageTexture.create_from_image(img)
	return _textures[i]


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
		_backdrop.texture = _texture_for(index)
		return
	_incoming.texture = _texture_for(index)
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
