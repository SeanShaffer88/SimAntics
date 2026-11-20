extends RefCounted
## "32-bit" surface art: the sky, hills, ground line, entrance mound and each preset's
## props, drawn with 2x2 screen pixels (matching the underground) and soft shading
## lit from the upper left. Preset colours and names live in pixel_art_factory.gd.

const PixelArt := preload("res://scripts/pixel_art_factory.gd")

const PIXEL_SCALE := 2
const D := 2  # detail factor: sizes below are written in the old 4x4 units and scaled by D
const LIGHT := Vector2(-0.55, -0.83)
const ENTRANCE_CLEARANCE := 14 * D
const HOLE := Color("#2a1b12")


static func make_surface_image(width: int, height: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator, preset: int, extra_cols: Array = []) -> Image:
	var p: Dictionary = PixelArt.SURFACE_PRESETS[preset]
	var img := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	_sky(img, ground_row, p["sky"])
	if preset == PixelArt.URBAN:
		_buildings(img, width, ground_row, rng, p["sky"])
	else:
		_hills(img, width, ground_row, rng, p["hill_far"], p["hill_near"], p["hill_amp"], p["sky"])
	_clouds(img, width, ground_row, rng, p["clouds"], p["sky"])

	var tree_xs: Array[int] = []
	match preset:
		PixelArt.FOREST:
			tree_xs = _trees(img, width, ground_row, entrance_col, rng, 4, PixelArt.FOREST_CANOPY, 1.0,
					PixelArt.FOREST_TRUNK, PixelArt.FOREST_TRUNK_DARK)
		PixelArt.ARID:
			_fence(img, width, ground_row, rng)
		PixelArt.AUTUMN:
			tree_xs = _trees(img, width, ground_row, entrance_col, rng, 3, PixelArt.AUTUMN_CANOPY, 0.55,
					PixelArt.AUTUMN_TRUNK, PixelArt.AUTUMN_TRUNK_DARK)
		PixelArt.URBAN:
			_curb(img, width, ground_row)

	_ground(img, width, height, ground_row, rng, p)

	match preset:
		PixelArt.FOREST:
			_mossy_roots(img, ground_row, tree_xs, rng)
			_ferns(img, width, ground_row, entrance_col, rng)
		PixelArt.ARID:
			_scrub(img, width, ground_row, entrance_col, rng)
			_stones(img, width, ground_row, entrance_col, rng, 34, PixelArt.STONE_LIGHT)
		PixelArt.AUTUMN:
			_leaf_litter(img, width, ground_row, entrance_col, rng)
		PixelArt.URBAN:
			_sidewalk(img, width, height, ground_row, entrance_col, rng)
			_stones(img, width, ground_row, entrance_col, rng, 44, PixelArt.GRIT_LIGHT)
			_dandelions(img, width, ground_row, entrance_col, rng)
		PixelArt.MEADOW:
			_clover(img, width, ground_row, entrance_col, rng)
			_wildflowers(img, width, ground_row, entrance_col, rng, p["grass_dark"])

	_mound(img, height, ground_row, entrance_col, p["mound"], p["mound_top"], 10 * D, 3 * D, rng)
	for col: int in extra_cols:
		_mound(img, height, ground_row, col, p["mound"], p["mound_top"], 6 * D, 2 * D, rng)
	return img


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


## Blends `c` over what is already there (for soft edges and haze).
static func _blend(img: Image, x: int, y: int, c: Color, amount: float) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, clampf(amount, 0.0, 1.0)))


static func _near_entrance(x: int, entrance_col: int, margin: int = ENTRANCE_CLEARANCE) -> bool:
	return absi(x - entrance_col) < margin


static func _sky_at(bands: Array, t: float) -> Color:
	var pos := clampf(t, 0.0, 0.999) * (bands.size() - 1)
	var i := int(pos)
	return (bands[i] as Color).lerp(bands[i + 1], pos - i)


## Shaded fill of an ellipse lit from the upper left; returns nothing, paints in place.
static func _shaded_ellipse(img: Image, c: Vector2, r: Vector2, tones: Array, density: float = 1.0,
		rng: RandomNumberGenerator = null) -> void:
	for y in range(floori(c.y - r.y), ceili(c.y + r.y) + 1):
		for x in range(floori(c.x - r.x), ceili(c.x + r.x) + 1):
			var n := Vector2((x + 0.5 - c.x) / r.x, (y + 0.5 - c.y) / r.y)
			var d := n.length()
			if d > 1.0:
				continue
			if rng != null and rng.randf() > density:
				continue
			var lambert := -n.dot(LIGHT) * 0.55 + 0.5
			if rng != null:
				lambert += rng.randf_range(-0.22, 0.22)  # individual leaves catch the light
			lambert = clampf(lambert, 0.0, 0.999)
			if d > 0.88:
				lambert *= 0.6  # rim falls into shadow
			_px(img, x, y, tones[int(lambert * tones.size())])


# ---------------------------------------------------------------------------
# Sky, clouds, hills
# ---------------------------------------------------------------------------

## A smooth vertical gradient through the preset's sky colours, brightening a touch
## into a hazy horizon.
static func _sky(img: Image, ground_row: int, bands: Array) -> void:
	var w := img.get_width()
	for y in ground_row:
		var t := float(y) / ground_row
		var c := _sky_at(bands, t)
		c = c.lightened(smoothstep(0.7, 1.0, t) * 0.08)
		for x in w:
			img.set_pixel(x, y, c)


static func _clouds(img: Image, width: int, ground_row: int, rng: RandomNumberGenerator, count: int,
		sky: Array) -> void:
	var tones := [PixelArt.CLOUD_SHADE.darkened(0.06), PixelArt.CLOUD_SHADE, PixelArt.CLOUD_LIGHT.darkened(0.02),
			PixelArt.CLOUD_LIGHT, Color.WHITE]
	for i in count:
		var cx := rng.randf_range(20.0, width - 20.0)
		var cy := rng.randf_range(10.0, ground_row * 0.42)
		var puffs: Array[Vector4] = []
		for p in rng.randi_range(4, 7):
			puffs.append(Vector4(cx + rng.randf_range(-22.0, 22.0), cy + rng.randf_range(-3.0, 3.0),
					rng.randf_range(7.0, 14.0), rng.randf_range(4.0, 7.0)))
		puffs.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y > b.y)  # lower puffs first
		for puff in puffs:
			_shaded_ellipse(img, Vector2(puff.x, puff.y), Vector2(puff.z, puff.w), tones)


## Two ranges of hills: the far one paler and bluer with distance.
static func _hills(img: Image, width: int, ground_row: int, rng: RandomNumberGenerator,
		far: Color, near: Color, amp: float, sky: Array) -> void:
	var haze := _sky_at(sky, 0.85)
	for layer in 2:
		var color: Color = far.lerp(haze, 0.35) if layer == 0 else near
		var scale := (1.35 if layer == 0 else 1.0) * amp * D
		var p1 := rng.randf() * TAU
		var p2 := rng.randf() * TAU
		for x in width:
			var h := (4.0 + 2.5 * sin(x * 0.0175 + p1) + 1.5 * sin(x * 0.055 + p2)) * scale
			if layer == 1:
				h *= 0.7
			var top := ground_row - roundi(h)
			for y in range(top, ground_row):
				var t := float(y - top) / maxf(1.0, h)
				var c := color.lightened(0.1 * (1.0 - t)) if t < 0.25 else color.darkened(0.08 * t)
				_px(img, x, y, c)


static func _buildings(img: Image, width: int, ground_row: int, rng: RandomNumberGenerator, sky: Array) -> void:
	var haze := _sky_at(sky, 0.8)
	var x := -rng.randi_range(0, 20)
	while x < width:
		var bw := rng.randi_range(32, 68)
		var bh := rng.randi_range(mini(20, ground_row - 16), ground_row - 12)
		var wall: Color = (PixelArt.BUILDING_COLORS[rng.randi() % PixelArt.BUILDING_COLORS.size()] as Color).lerp(haze, 0.15)
		var top := ground_row - bh
		var lit := rng.randi_range(0, 4)
		for yy in range(top, ground_row):
			for xx in range(x, x + bw):
				var c := wall
				if yy <= top + 1:
					c = wall.lightened(0.15)  # roof edge
				elif xx >= x + bw - 3:
					c = wall.darkened(0.12)  # shaded side
				var wx := xx - x - 4
				var wy := yy - top - 4
				if wx >= 0 and wy >= 0 and xx < x + bw - 5 and yy < ground_row - 4 and wx % 7 < 3 and wy % 8 < 4:
					var id := int(wx / 7.0) * 7 + int(wy / 8.0) * 13 + lit
					c = PixelArt.WINDOW_LIT if id % 5 == 0 else PixelArt.WINDOW_DARK
					if wy % 8 == 0:
						c = c.darkened(0.2)  # lintel shadow
				_px(img, xx, yy, c)
		x += bw + rng.randi_range(-8, 6)


# ---------------------------------------------------------------------------
# Ground and mound
# ---------------------------------------------------------------------------

static func _ground(img: Image, width: int, height: int, ground_row: int, rng: RandomNumberGenerator,
		p: Dictionary) -> void:
	var soil_a: Color = p["soil_a"]
	var soil_b: Color = p["soil_b"]
	var dark: Color = p["grass_dark"]
	var light: Color = p["grass_light"]
	var blade_max: int = int(p["blade_max"]) * D
	var chance: float = p["grass_chance"]
	for y in range(ground_row, height):
		for x in width:
			var c := soil_a if rng.randf() < 0.7 else soil_b
			if y == ground_row + 1:
				c = c.darkened(0.12)  # shadow under the turf
			img.set_pixel(x, y, c)
	for x in width:
		img.set_pixel(x, ground_row, dark if rng.randf() < 0.6 else light)
		if rng.randf() < chance * 1.4:
			var blade := rng.randi_range(1, blade_max)
			var lean := rng.randf_range(-0.35, 0.35)
			for k in range(1, blade + 1):
				var t := float(k) / blade
				var bx := x + roundi(lean * k)
				_px(img, bx, ground_row - k, dark.lerp(light, t).lightened(0.12 * t * t))


## The ring of excavated soil around an opening, shaded and speckled with pellets.
static func _mound(img: Image, height: int, ground_row: int, col: int, mound: Color, top: Color,
		half_width: int, tall: int, rng: RandomNumberGenerator) -> void:
	for dx in range(-half_width, half_width + 1):
		var t := float(dx) / half_width
		var mh := roundi(tall * (1.0 - t * t))
		for k in range(0, mh + 1):
			var lit := clampf(0.5 - t * 0.45 + float(k) / maxf(1.0, mh) * 0.3, 0.0, 1.0)
			var c := mound.darkened(0.25).lerp(top.lightened(0.1), lit)
			if rng.randf() < 0.12:
				c = c.lightened(0.15)  # a pellet catching the light
			_px(img, col + dx, ground_row - k, c)
	var hole := 2 * D if tall >= 3 * D else D + 1
	for x in range(col - hole, col + hole + 1):
		for y in range(ground_row - tall, height):
			var edge := absi(x - col) == hole
			_px(img, x, y, HOLE.lightened(0.08) if edge else HOLE)


# ---------------------------------------------------------------------------
# Trees (forest, autumn)
# ---------------------------------------------------------------------------

static func _trees(img: Image, width: int, ground_row: int, entrance_col: int, rng: RandomNumberGenerator,
		count: int, canopy: Array, density: float, trunk: Color, trunk_dark: Color) -> Array[int]:
	var xs: Array[int] = []
	var segment := float(width) / count
	for i in count:
		var x := roundi(segment * i + rng.randf_range(segment * 0.2, segment * 0.8))
		if _near_entrance(x, entrance_col, 30 * D):
			x += 34 * D if x >= entrance_col else -34 * D
		xs.append(x)
		_tree(img, x, ground_row, rng, canopy, density, trunk, trunk_dark)
	return xs


static func _tree(img: Image, x: int, ground_row: int, rng: RandomNumberGenerator, canopy: Array,
		density: float, trunk: Color, trunk_dark: Color) -> void:
	var height := rng.randi_range(int(ground_row * 0.62), maxi(int(ground_row * 0.62) + 1, ground_row - 12))
	var top := ground_row - height
	# trunk: a shaded cylinder, lit on the left, flaring at the base
	for y in range(top + 8, ground_row):
		var flare := 2 if y > ground_row - 4 else 0
		for dx in range(-3 - flare, 3 + flare):
			var t := float(dx + 3 + flare) / (6 + flare * 2)
			var c := trunk.lightened(0.18).lerp(trunk_dark, t)
			if (y + dx) % 7 == 0:
				c = c.darkened(0.15)  # bark grooves
			_px(img, x + dx, y, c)
	var tones: Array[Color] = []
	for c: Color in canopy:
		tones.push_front(c)  # canopy colours run light to dark; the shading wants dark to light
	for b in rng.randi_range(3, 5):
		var by := rng.randi_range(top + 8, top + 30)
		var side := -1 if b % 2 == 0 else 1
		for t in rng.randi_range(8, 18):
			var px := x + side * (3 + t)
			var py := by - int(t * 0.5)
			_px(img, px, py, trunk_dark)
			if t < 6:
				_px(img, px, py + 1, trunk_dark)
	for blob in rng.randi_range(5, 8):
		var c := Vector2(x + rng.randf_range(-20.0, 20.0), top + rng.randf_range(-2.0, 16.0))
		var r := rng.randf_range(10.0, 18.0)
		_shaded_ellipse(img, c, Vector2(r, r * 0.82), tones, density, rng)


static func _mossy_roots(img: Image, ground_row: int, tree_xs: Array[int], rng: RandomNumberGenerator) -> void:
	for x in tree_xs:
		for side: int in [-1, 1]:
			for t in 14:
				var rx := x + side * (4 + t)
				var lift := 2 if t >= 2 and t <= 9 else (1 if t < 12 else 0)
				_px(img, rx, ground_row - 1 - lift, PixelArt.FOREST_TRUNK_DARK)
				_px(img, rx, ground_row - lift, PixelArt.FOREST_TRUNK)
				if rng.randf() < 0.6:
					_px(img, rx, ground_row - 2 - lift, PixelArt.MOSS.lightened(rng.randf_range(0.0, 0.15)))


static func _ferns(img: Image, width: int, ground_row: int, entrance_col: int, rng: RandomNumberGenerator) -> void:
	for i in 14:
		var x := rng.randi_range(8, width - 9)
		if _near_entrance(x, entrance_col, 18 * D):
			continue
		var h := rng.randi_range(8, 14)
		for k in h - 4:
			_px(img, x, ground_row - 1 - k, PixelArt.FERN_DARK)
		for side: int in [-1, 1]:
			for frond in 2:
				var length := rng.randi_range(10, 18) - frond * 4
				var frond_h := h - frond * 4
				for t in length:
					var u := float(t) / length
					var lift := frond_h * (1.0 - pow(2.0 * u - 0.6, 2.0))
					var y := ground_row - 1 - maxi(0, roundi(lift))
					_px(img, x + side * t, y, PixelArt.FERN_DARK)
					if t % 2 == 1:  # leaflets, lighter on top
						_px(img, x + side * t, y - 1, PixelArt.FERN_LIGHT)
						_px(img, x + side * t, y + 1, PixelArt.FERN_DARK.darkened(0.2))


static func _leaf_litter(img: Image, width: int, ground_row: int, entrance_col: int, rng: RandomNumberGenerator) -> void:
	for i in width * 2:
		var x := rng.randi_range(0, width - 2)
		if _near_entrance(x, entrance_col, 12 * D):
			continue
		var y := ground_row - rng.randi_range(0, 4)
		var c: Color = PixelArt.LEAF_COLORS[rng.randi() % PixelArt.LEAF_COLORS.size()]
		_px(img, x, y, c)
		_px(img, x + 1, y, c.darkened(0.15))  # little curled leaves, two pixels wide
	for i in 14:
		var x := rng.randi_range(0, width - 12)
		if _near_entrance(x, entrance_col, 16 * D):
			continue
		for t in rng.randi_range(6, 12):
			_px(img, x + t, ground_row - 1 - int(t * 0.4), PixelArt.AUTUMN_TRUNK_DARK)


# ---------------------------------------------------------------------------
# Arid backyard
# ---------------------------------------------------------------------------

static func _fence(img: Image, width: int, ground_row: int, rng: RandomNumberGenerator) -> void:
	var post_h := 30
	for x in width:
		for rail_y: int in [ground_row - 24, ground_row - 10]:
			if rng.randf() > 0.03:
				_px(img, x, rail_y, PixelArt.FENCE_RAIL.lightened(0.08))
				_px(img, x, rail_y + 1, PixelArt.FENCE_RAIL)
				_px(img, x, rail_y + 2, PixelArt.FENCE_DARK)
	var x := rng.randi_range(0, 12)
	while x < width:
		for y in range(ground_row - post_h, ground_row):
			_px(img, x, y, PixelArt.FENCE_POST.lightened(0.1))
			_px(img, x + 1, y, PixelArt.FENCE_POST)
			_px(img, x + 2, y, PixelArt.FENCE_POST.darkened(0.08))
			_px(img, x + 3, y, PixelArt.FENCE_DARK)
			if rng.randf() < 0.05:
				_px(img, x + 1, y, PixelArt.FENCE_DARK)  # wood grain
		_px(img, x + 1, ground_row - post_h - 1, PixelArt.FENCE_POST)
		_px(img, x + 2, ground_row - post_h - 1, PixelArt.FENCE_POST)
		x += 28


static func _scrub(img: Image, width: int, ground_row: int, entrance_col: int, rng: RandomNumberGenerator) -> void:
	var tones := [PixelArt.SCRUB_DARK.darkened(0.2), PixelArt.SCRUB_DARK, PixelArt.SCRUB_LIGHT,
			PixelArt.SCRUB_LIGHT.lightened(0.12)]
	for i in 6:
		var x := rng.randi_range(12, width - 13)
		if _near_entrance(x, entrance_col, 22 * D):
			continue
		var rx := rng.randf_range(8.0, 16.0)
		var ry := rng.randf_range(6.0, 10.0)
		_shaded_ellipse(img, Vector2(x, ground_row - ry * 0.55), Vector2(rx, ry), tones, 0.85, rng)
		for t in 6:
			_px(img, x + rng.randi_range(-int(rx), int(rx)), ground_row - int(ry * 1.4) - rng.randi_range(0, 2),
					PixelArt.TWIG)


## Small shaded stones or grit along the ground line.
static func _stones(img: Image, width: int, ground_row: int, entrance_col: int, rng: RandomNumberGenerator,
		count: int, tone: Color) -> void:
	var tones := [tone.darkened(0.35), tone.darkened(0.15), tone, tone.lightened(0.18)]
	for i in count:
		var x := rng.randi_range(2, width - 3)
		if _near_entrance(x, entrance_col, 12 * D):
			continue
		var r := rng.randf_range(1.2, 2.8)
		_shaded_ellipse(img, Vector2(x, ground_row - r * 0.4), Vector2(r, r * 0.7), tones)


# ---------------------------------------------------------------------------
# Urban sidewalk
# ---------------------------------------------------------------------------

static func _curb(img: Image, width: int, ground_row: int) -> void:
	for x in width:
		_px(img, x, ground_row - 6, PixelArt.CURB_TOP.lightened(0.06))
		_px(img, x, ground_row - 5, PixelArt.CURB_TOP)
		for y in range(ground_row - 4, ground_row - 1):
			_px(img, x, y, PixelArt.CURB)
		_px(img, x, ground_row - 1, PixelArt.CURB_SHADOW)


static func _sidewalk(img: Image, width: int, height: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator) -> void:
	var gap_left := entrance_col - ENTRANCE_CLEARANCE
	var gap_right := entrance_col + ENTRANCE_CLEARANCE
	for x in width:
		if x >= gap_left and x <= gap_right:
			continue
		var seam := x % 64 == 0 or x == gap_left - 1 or x == gap_right + 1
		for y in range(ground_row, height):
			var c := PixelArt.CONCRETE if rng.randf() < 0.8 else PixelArt.CONCRETE_B
			if y == ground_row:
				c = PixelArt.CONCRETE_TOP.lightened(0.05)
			elif y == ground_row + 1:
				c = PixelArt.CONCRETE_TOP
			if rng.randf() < 0.04:
				c = c.darkened(0.15)  # aggregate speckle
			_px(img, x, y, PixelArt.SEAM if seam else c)
	for i in 8:
		var x := rng.randi_range(0, width - 16)
		if x + 15 >= gap_left and x <= gap_right:
			continue
		var y := ground_row
		for t in rng.randi_range(6, 14):
			_px(img, x + t, y, PixelArt.SEAM)
			if rng.randf() < 0.5:
				y = clampi(y + rng.randi_range(-1, 1), ground_row, height - 1)


static func _dandelions(img: Image, width: int, ground_row: int, entrance_col: int, rng: RandomNumberGenerator) -> void:
	var heads := [PixelArt.DANDELION.darkened(0.15), PixelArt.DANDELION, PixelArt.DANDELION_LIGHT, Color("#fff4b0")]
	var puffs := [Color("#c8c8c0"), Color("#e0e0d8"), PixelArt.PUFF, Color.WHITE]
	for i in 10:
		var x: int
		if i < 4:  # weeds love the slab edge by the nest
			var offset := rng.randi_range(ENTRANCE_CLEARANCE - 4, ENTRANCE_CLEARANCE)
			x = entrance_col + (offset if i % 2 == 0 else -offset)
		else:
			x = rng.randi_range(4, width - 5)
		if _near_entrance(x, entrance_col, 11 * D):
			continue
		var h := rng.randi_range(6, 12)
		for k in range(1, h):
			_px(img, x, ground_row - k, PixelArt.STEM)
		for side: int in [-1, 1]:  # serrated leaves at the base
			for t in 4:
				_px(img, x + side * (t + 1), ground_row - 1 - int(t * 0.5), PixelArt.STEM.darkened(0.1 if t % 2 == 0 else 0.0))
		var puff := rng.randf() < 0.3
		var r := 3.0 if puff else 2.4
		_shaded_ellipse(img, Vector2(x + 0.5, ground_row - h - r * 0.6), Vector2(r, r), puffs if puff else heads)


# ---------------------------------------------------------------------------
# Meadow
# ---------------------------------------------------------------------------

static func _wildflowers(img: Image, width: int, ground_row: int, entrance_col: int, rng: RandomNumberGenerator,
		stem: Color) -> void:
	for i in 60:
		var x := rng.randi_range(2, width - 3)
		if _near_entrance(x, entrance_col, 13 * D):
			continue
		var h := rng.randi_range(6, 16)
		var petal: Color = PixelArt.FLOWER_COLORS[rng.randi() % PixelArt.FLOWER_COLORS.size()]
		var sway := rng.randf_range(-0.2, 0.2)
		for k in range(1, h):
			_px(img, x + roundi(sway * k), ground_row - k, stem)
		var hx := x + roundi(sway * h)
		var hy := ground_row - h
		if h < 9:  # a bud
			_px(img, hx, hy, petal)
			_px(img, hx, hy - 1, petal.lightened(0.2))
		else:
			for d: Vector2i in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2),
					Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
				_px(img, hx + d.x, hy + d.y, petal if d.y <= 0 else petal.darkened(0.15))
			_px(img, hx, hy, PixelArt.FLOWER_CENTER)
			_px(img, hx - 1, hy - 2, petal.lightened(0.25))  # light catching a petal


static func _clover(img: Image, width: int, ground_row: int, entrance_col: int, rng: RandomNumberGenerator) -> void:
	for i in 14:
		var x := rng.randi_range(0, width - 10)
		if _near_entrance(x, entrance_col, 16 * D):
			continue
		for t in 4:  # trefoil leaves along a runner
			var lx := x + t * 2
			var ly := ground_row - 2 - (t % 2)
			_px(img, lx, ly, PixelArt.CLOVER_LIGHT)
			_px(img, lx + 1, ly, PixelArt.CLOVER)
			_px(img, lx, ly + 1, PixelArt.CLOVER)
			_px(img, lx + 1, ly + 1, PixelArt.CLOVER.darkened(0.15))
		if rng.randf() < 0.5:
			var fx := x + 3
			_px(img, fx, ground_row - 6, PixelArt.CLOVER_FLOWER)
			_px(img, fx + 1, ground_row - 6, PixelArt.CLOVER_FLOWER.darkened(0.08))
			_px(img, fx, ground_row - 7, PixelArt.CLOVER_FLOWER.lightened(0.1))
			_px(img, fx, ground_row - 5, PixelArt.STEM)
			_px(img, fx, ground_row - 4, PixelArt.STEM)
