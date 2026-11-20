extends SceneTree
## Regenerates the app icons from the procedural ant art.
## Run from the project folder:  godot --headless --path . -s res://tools/make_icons.gd

const ColonyArt := preload("res://scripts/colony_art.gd")
const ColonyProfile := preload("res://scripts/colony_profile.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://icons"))
	var species: Dictionary = ColonyProfile.SPECIES[0]  # red harvester: reads well at small sizes
	var ant := ColonyArt.ant_frames(species, 1.0, 1.1)[0].get_image()

	var background := _soil(432)
	background.save_png("res://icons/icon_background.png")

	# adaptive foreground: the ant inside the central 66% safe zone
	var foreground := Image.create_empty(432, 432, false, Image.FORMAT_RGBA8)
	foreground.fill(Color(0, 0, 0, 0))
	_stamp(foreground, ant, 240, Vector2i(216, 222))
	foreground.save_png("res://icons/icon_foreground.png")

	# legacy square icon: soil with the ant on top
	var icon := _soil(192)
	_stamp(icon, ant, 150, Vector2i(96, 100))
	icon.save_png("res://icon.png")
	print("icons written")
	quit()


## Warm soil with a lit tunnel band, matching the farm's palette.
func _soil(size: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var px := maxi(2, size / 72)  # chunky pixels like the game
	for y in range(0, size, px):
		for x in range(0, size, px):
			var t := float(y) / size
			var c := Color("#7e5432").lerp(Color("#4a3020"), t)
			if absf(t - 0.52) < 0.16:
				c = Color("#2e1e14").lerp(c, absf(t - 0.52) / 0.16 * 0.5)  # tunnel
			if rng.randf() < 0.08:
				c = c.lightened(0.15)
			img.fill_rect(Rect2i(x, y, px, px), c)
	return img


## Scales `sprite` to `width` px with nearest-neighbour and centres it at `center`.
func _stamp(target: Image, sprite: Image, width: int, center: Vector2i) -> void:
	var s := sprite.duplicate() as Image
	var scale := float(width) / s.get_width()
	s.resize(width, int(s.get_height() * scale), Image.INTERPOLATE_NEAREST)
	target.blend_rect(s, Rect2i(Vector2i.ZERO, s.get_size()), center - s.get_size() / 2)
