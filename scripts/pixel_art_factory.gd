extends RefCounted
## Centralized procedural 16-bit pixel art.
## Every visual comes from here so the project runs with zero external assets.
## To swap in hand-drawn art later, replace a function body with a load("res://art/...png").

const PIXEL_SCALE := 4  # one art pixel = 4x4 screen pixels for backgrounds
const SPRITE_SCALE := 2  # ants and queen are drawn at 2x

# --- Sprites (facing right). Each character is one pixel; "." is transparent. ---

const ANT_FRAME_A := [
	"........a.",
	".bbb...hh.",
	"bwbbbtthhh",
	".bbb.tt.h.",
	"..l.l.l...",
	".l..l..l..",
]

const ANT_FRAME_B := [
	"........a.",
	".bbb...hh.",
	"bwbbbtthhh",
	".bbb.tt.h.",
	"...l.l.l..",
	"..l..l..l.",
]

const QUEEN_ROWS := [
	"..............a.",
	"..bbbbbb....hha.",
	".bwwbbbbbtt.hhh.",
	"bbbbbbbbbttthhh.",
	".bbbbbbbbtt..h..",
	"..bbbbbb.l.l.l..",
	"........l..l..l.",
]

const SURFACE_ICON_ROWS := [
	"........yy..",
	"...gg...yy..",
	"..gggg......",
	".gggggg.....",
	"..gggg......",
	"...t...hhh..",
	"...t..hhhhh.",
	"GGGGGGGGGGGG",
	"dddddddddddd",
	"dddddddddddd",
]

const ANT_PALETTE := {
	"a": Color("#4a2010"),
	"b": Color("#8a3e1c"),
	"w": Color("#c46c3c"),
	"t": Color("#7a3418"),
	"h": Color("#6a2c14"),
	"l": Color("#5a2812"),
}

const QUEEN_PALETTE := {
	"a": Color("#4a2010"),
	"b": Color("#a04c22"),
	"w": Color("#d88a50"),
	"t": Color("#82381a"),
	"h": Color("#6a2c14"),
	"l": Color("#5a2812"),
}

const SURFACE_ICON_PALETTE := {
	"y": Color("#f0d050"),
	"g": Color("#5a8f3c"),
	"t": Color("#6a4428"),
	"h": Color("#86a884"),
	"G": Color("#4f7a3a"),
	"d": Color("#6a4429"),
}

# --- Surface presets ---

enum { FOREST, ARID, AUTUMN, URBAN, MEADOW }

const SURFACE_PRESETS := [
	{
		"name": "Lush Forest Floor",
		"sky": [Color("#4f7fa8"), Color("#5f8fb4"), Color("#78a3c0"), Color("#93b8cc"), Color("#aecbd6")],
		"hill_far": Color("#55805a"), "hill_near": Color("#43704a"), "hill_amp": 1.5, "clouds": 1,
		"grass_dark": Color("#3d6b2e"), "grass_light": Color("#5a8f3c"), "grass_chance": 0.6, "blade_max": 3,
		"soil_a": Color("#4a2f1d"), "soil_b": Color("#57381f"),
		"mound": Color("#6a4528"), "mound_top": Color("#83593a"),
	},
	{
		"name": "Arid Backyard",
		"sky": [Color("#7fb0d8"), Color("#94bfdf"), Color("#accee5"), Color("#c6dde9"), Color("#e3e8e0")],
		"hill_far": Color("#c9a878"), "hill_near": Color("#b8955f"), "hill_amp": 0.7, "clouds": 1,
		"grass_dark": Color("#8f8a4a"), "grass_light": Color("#b4a85c"), "grass_chance": 0.22, "blade_max": 2,
		"soil_a": Color("#9a6a3c"), "soil_b": Color("#a87644"),
		"mound": Color("#b07c48"), "mound_top": Color("#c99560"),
	},
	{
		"name": "Autumn Woods",
		"sky": [Color("#7d93ad"), Color("#8fa3b8"), Color("#a6b5c2"), Color("#bfc6c8"), Color("#d6d2c4")],
		"hill_far": Color("#a07a4a"), "hill_near": Color("#8a5f36"), "hill_amp": 1.1, "clouds": 2,
		"grass_dark": Color("#7a6a30"), "grass_light": Color("#a08a3c"), "grass_chance": 0.3, "blade_max": 2,
		"soil_a": Color("#5a3a22"), "soil_b": Color("#66432a"),
		"mound": Color("#7a5330"), "mound_top": Color("#946a40"),
	},
	{
		"name": "Urban Sidewalk",
		"sky": [Color("#7f97b0"), Color("#91a6bb"), Color("#a7b7c6"), Color("#bcc7cf"), Color("#d0d6d8")],
		"hill_far": Color("#8b95a3"), "hill_near": Color("#7e8898"), "hill_amp": 1.0, "clouds": 2,
		"grass_dark": Color("#5a7a3a"), "grass_light": Color("#7a9a48"), "grass_chance": 0.06, "blade_max": 2,
		"soil_a": Color("#5b3a24"), "soil_b": Color("#6a4429"),
		"mound": Color("#8a7a66"), "mound_top": Color("#a09080"),
	},
	{
		"name": "Meadow Overlook",
		"sky": [Color("#6aa6dc"), Color("#80b4e2"), Color("#9ac4e8"), Color("#b6d6ee"), Color("#d2e6f2")],
		"hill_far": Color("#9cc48a"), "hill_near": Color("#84b072"), "hill_amp": 1.3, "clouds": 5,
		"grass_dark": Color("#4f8a3a"), "grass_light": Color("#74ae4e"), "grass_chance": 0.85, "blade_max": 6,
		"soil_a": Color("#5b3a24"), "soil_b": Color("#6a4429"),
		"mound": Color("#7a5330"), "mound_top": Color("#946a40"),
	},
]

const CLOUD_LIGHT := Color("#eef4f8")
const CLOUD_SHADE := Color("#d3e0ea")

const FOREST_CANOPY := [Color("#6fa04a"), Color("#548a3c"), Color("#3f6f32"), Color("#2f5528")]
const FOREST_TRUNK := Color("#5a3e28")
const FOREST_TRUNK_DARK := Color("#3e2a1a")
const FERN_DARK := Color("#3f7a34")
const FERN_LIGHT := Color("#68a84a")
const MOSS := Color("#5f9a3c")

const FENCE_POST := Color("#9c7f5a")
const FENCE_RAIL := Color("#b0936a")
const FENCE_DARK := Color("#7d6446")
const SCRUB_DARK := Color("#6f7a44")
const SCRUB_LIGHT := Color("#8a9454")
const TWIG := Color("#6a4a2e")
const STONE_LIGHT := Color("#c2b29a")
const STONE_DARK := Color("#968672")

const AUTUMN_CANOPY := [Color("#e0a040"), Color("#c8782a"), Color("#a8502a"), Color("#7a3a22")]
const AUTUMN_TRUNK := Color("#4a3424")
const AUTUMN_TRUNK_DARK := Color("#33241a")
const LEAF_COLORS := [Color("#d08a2a"), Color("#c0782a"), Color("#a8442a"), Color("#e0b048"), Color("#7a4a26")]

const BUILDING_COLORS := [Color("#8b95a3"), Color("#7e8898"), Color("#9aa2ac"), Color("#737d8c")]
const WINDOW_LIT := Color("#e6d9a0")
const WINDOW_DARK := Color("#66707e")
const CURB_TOP := Color("#c4c4bc")
const CURB := Color("#b0b0a8")
const CURB_SHADOW := Color("#8e8e88")
const CONCRETE_TOP := Color("#b8b8b0")
const CONCRETE := Color("#9a9a94")
const CONCRETE_B := Color("#a4a49c")
const SEAM := Color("#6e6e68")
const GRIT_LIGHT := Color("#8a8a84")
const GRIT_DARK := Color("#6a6a64")
const STEM := Color("#5a8a3a")
const DANDELION := Color("#e8c43a")
const DANDELION_LIGHT := Color("#f4d860")
const PUFF := Color("#f0f0ea")

const FLOWER_COLORS := [Color("#e07aa0"), Color("#f0d050"), Color("#f4f0e8"), Color("#9a78d0"), Color("#e8884a")]
const FLOWER_CENTER := Color("#f8e070")
const CLOVER := Color("#5aa048")
const CLOVER_LIGHT := Color("#78bc5c")
const CLOVER_FLOWER := Color("#f4eef0")

# --- Underground palette: [main, variant] per stratum, top to bottom ---

const STRATA := [
	[Color("#5b3a24"), Color("#52331f")],
	[Color("#8a5a2e"), Color("#7e522a")],
	[Color("#6e4a2e"), Color("#654429")],
	[Color("#3f2a1c"), Color("#38251a")],
]
const STRATA_DEPTHS := [20.0, 56.0, 94.0]  # art-pixel rows of the stratum boundaries
const PEBBLE_LIGHT := Color("#a39079")
const PEBBLE_DARK := Color("#76665a")
const ROOT := Color("#3a2616")
const ROOT_LIGHT := Color("#4e3420")
const TUNNEL_AIR := Color("#2a1b12")
const TUNNEL_AIR_B := Color("#2e1e14")

const ENTRANCE_CLEARANCE := 14  # art pixels kept clear of props around the nest entrance

static var _ant_frames: Array[ImageTexture] = []
static var _queen_texture: ImageTexture
static var _surface_icon: ImageTexture


static func texture_from_rows(rows: Array, palette: Dictionary) -> ImageTexture:
	var width := 0
	for row: String in rows:
		width = maxi(width, row.length())
	var img := Image.create_empty(width, rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var key := row[x]
			if palette.has(key):
				img.set_pixel(x, y, palette[key])
	return ImageTexture.create_from_image(img)


## Two walk-cycle frames shared by every worker ant.
static func ant_frames() -> Array[ImageTexture]:
	if _ant_frames.is_empty():
		_ant_frames.append(texture_from_rows(ANT_FRAME_A, ANT_PALETTE))
		_ant_frames.append(texture_from_rows(ANT_FRAME_B, ANT_PALETTE))
	return _ant_frames


static func queen_texture() -> ImageTexture:
	if _queen_texture == null:
		_queen_texture = texture_from_rows(QUEEN_ROWS, QUEEN_PALETTE)
	return _queen_texture


## Small landscape glyph for the surface-picker toggle button.
const SPEAKER_ROWS := [
	"............",
	"....s....w..",
	"...ss.....w.",
	"bbsss..w..w.",
	"bbsss...w..w",
	"bbsss...w..w",
	"bbsss..w..w.",
	"...ss.....w.",
	"....s....w..",
	"............",
]
const SPEAKER_MUTED_ROWS := [
	"............",
	"....s.......",
	"...ss.......",
	"bbsss..x..x.",
	"bbsss...xx..",
	"bbsss...xx..",
	"bbsss..x..x.",
	"...ss.......",
	"....s.......",
	"............",
]
const SPEAKER_PALETTE := {
	"b": Color("#c49a62"), "s": Color("#e0c08a"), "w": Color("#f0dcb4"), "x": Color("#c0583a"),
}

static var _speaker_icons: Dictionary = {}


## Speaker glyph for the sound toggle, crossed out when muted.
static func speaker_icon(muted: bool) -> ImageTexture:
	if not _speaker_icons.has(muted):
		_speaker_icons[muted] = texture_from_rows(SPEAKER_MUTED_ROWS if muted else SPEAKER_ROWS, SPEAKER_PALETTE)
	return _speaker_icons[muted]


static func surface_icon() -> ImageTexture:
	if _surface_icon == null:
		_surface_icon = texture_from_rows(SURFACE_ICON_ROWS, SURFACE_ICON_PALETTE)
	return _surface_icon


static func surface_preset_count() -> int:
	return SURFACE_PRESETS.size()


static func surface_preset_name(index: int) -> String:
	return SURFACE_PRESETS[index]["name"]


## Bounds-checked pixel write, so props can safely spill past the image edges.
static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _near_entrance(x: int, entrance_col: int, margin: int = ENTRANCE_CLEARANCE) -> bool:
	return absi(x - entrance_col) < margin


# ---------------------------------------------------------------------------
# Surface
# ---------------------------------------------------------------------------

static func make_surface_image(width: int, height: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator, preset: int = FOREST, extra_cols: Array = []) -> Image:
	var p: Dictionary = SURFACE_PRESETS[preset]
	var img := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	_paint_sky(img, width, ground_row, p["sky"])
	if preset == URBAN:
		_paint_buildings(img, width, ground_row, rng)
	else:
		_paint_hills(img, width, ground_row, rng, p["hill_far"], p["hill_near"], p["hill_amp"])
	_paint_clouds(img, width, ground_row, rng, p["clouds"])

	# Background props, standing behind the ground line.
	var tree_xs: Array[int] = []
	match preset:
		FOREST:
			tree_xs = _paint_trees(img, width, ground_row, entrance_col, rng, 4, FOREST_CANOPY, 1.0,
					FOREST_TRUNK, FOREST_TRUNK_DARK)
		ARID:
			_paint_fence(img, width, ground_row, rng)
		AUTUMN:
			tree_xs = _paint_trees(img, width, ground_row, entrance_col, rng, 3, AUTUMN_CANOPY, 0.5,
					AUTUMN_TRUNK, AUTUMN_TRUNK_DARK)
		URBAN:
			_paint_curb(img, width, ground_row)

	_paint_ground(img, width, height, ground_row, rng, p)

	# Foreground details on the ground line.
	match preset:
		FOREST:
			_paint_mossy_roots(img, ground_row, tree_xs, rng)
			_paint_ferns(img, width, ground_row, entrance_col, rng)
		ARID:
			_paint_scrub(img, width, ground_row, entrance_col, rng)
			_paint_ground_stones(img, width, ground_row, entrance_col, rng, 30, STONE_LIGHT, STONE_DARK)
		AUTUMN:
			_paint_leaf_litter(img, width, ground_row, entrance_col, rng)
		URBAN:
			_paint_sidewalk(img, width, height, ground_row, entrance_col, rng)
			_paint_ground_stones(img, width, ground_row, entrance_col, rng, 40, GRIT_LIGHT, GRIT_DARK)
			_paint_dandelions(img, width, ground_row, entrance_col, rng)
		MEADOW:
			_paint_clover(img, width, ground_row, entrance_col, rng)
			_paint_wildflowers(img, width, ground_row, entrance_col, rng, p["grass_dark"])

	_paint_mound(img, height, ground_row, entrance_col, p["mound"], p["mound_top"])
	for col: int in extra_cols:
		_paint_mound(img, height, ground_row, col, p["mound"], p["mound_top"], 6, 2)
	return img


static func _paint_sky(img: Image, width: int, ground_row: int, bands: Array) -> void:
	var band_height := float(ground_row) / bands.size()
	for y in ground_row:
		var pos := y / band_height
		var band := int(pos)
		var frac := pos - band
		for x in width:
			var b := band
			if frac > 0.65 and (x + y) % 2 == 0:
				b += 1  # checker dither into the next band
			img.set_pixel(x, y, bands[mini(b, bands.size() - 1)])


static func _paint_hills(img: Image, width: int, ground_row: int, rng: RandomNumberGenerator,
		far: Color, near: Color, amp: float) -> void:
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	for x in width:
		var hill := (4.0 + 2.5 * sin(x * 0.035 + p1) + 1.5 * sin(x * 0.11 + p2)) * amp
		var top := ground_row - roundi(hill)
		for y in range(top, ground_row):
			_px(img, x, y, far if y < top + 2 else near)


static func _paint_clouds(img: Image, width: int, ground_row: int, rng: RandomNumberGenerator,
		count: int) -> void:
	for i in count:
		var cx := rng.randf_range(10.0, width - 10.0)
		var cy := rng.randf_range(5.0, ground_row * 0.45)
		for p in rng.randi_range(3, 5):
			var px := cx + rng.randf_range(-10.0, 10.0)
			var py := cy + rng.randf_range(-1.5, 1.5)
			var rx := rng.randf_range(3.5, 7.0)
			var ry := rng.randf_range(2.0, 3.5)
			for y in range(floori(py - ry), ceili(py + ry) + 1):
				for x in range(floori(px - rx), ceili(px + rx) + 1):
					if y >= ground_row:
						continue
					var nx := (x + 0.5 - px) / rx
					var ny := (y + 0.5 - py) / ry
					if nx * nx + ny * ny <= 1.0:
						_px(img, x, y, CLOUD_SHADE if ny > 0.35 else CLOUD_LIGHT)


static func _paint_ground(img: Image, width: int, height: int, ground_row: int,
		rng: RandomNumberGenerator, p: Dictionary) -> void:
	var soil_a: Color = p["soil_a"]
	var soil_b: Color = p["soil_b"]
	var grass_dark: Color = p["grass_dark"]
	var grass_light: Color = p["grass_light"]
	var blade_max: int = p["blade_max"]
	var grass_chance: float = p["grass_chance"]
	for y in range(ground_row, height):
		for x in width:
			img.set_pixel(x, y, soil_a if rng.randf() < 0.7 else soil_b)
	for x in width:
		img.set_pixel(x, ground_row, grass_dark if rng.randf() < 0.6 else grass_light)
		if rng.randf() < grass_chance:
			var blade := rng.randi_range(1, blade_max)
			for k in range(1, blade + 1):
				_px(img, x, ground_row - k, grass_light if k == blade else grass_dark)


## A ring of excavated soil around a nest opening. Secondary openings get a smaller one.
static func _paint_mound(img: Image, height: int, ground_row: int, entrance_col: int,
		mound: Color, mound_top: Color, half_width: int = 10, tall: int = 3) -> void:
	for dx in range(-half_width, half_width + 1):
		var t := float(dx) / half_width
		var mound_height := roundi(tall * (1.0 - t * t))
		for k in range(0, mound_height + 1):
			_px(img, entrance_col + dx, ground_row - k, mound_top if k == mound_height else mound)
	var hole := 2 if tall >= 3 else 1
	for x in range(entrance_col - hole, entrance_col + hole + 1):
		for y in range(ground_row - tall, height):
			_px(img, x, y, TUNNEL_AIR)


static func _paint_ground_stones(img: Image, width: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator, count: int, light: Color, dark: Color) -> void:
	for i in count:
		var x := rng.randi_range(0, width - 2)
		if _near_entrance(x, entrance_col, 12):
			continue
		_px(img, x, ground_row - 1, light)
		if rng.randf() < 0.4:
			_px(img, x + 1, ground_row - 1, dark)


# --- Forest and autumn trees ---

## Spreads `count` trees across the width (clear of the entrance) and returns their trunk columns.
static func _paint_trees(img: Image, width: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator, count: int, canopy: Array, density: float,
		trunk: Color, trunk_dark: Color) -> Array[int]:
	var xs: Array[int] = []
	var segment := float(width) / count
	for i in count:
		var x := roundi(segment * i + rng.randf_range(segment * 0.2, segment * 0.8))
		if _near_entrance(x, entrance_col, 30):
			x += 34 if x >= entrance_col else -34
		xs.append(x)
		_paint_tree(img, x, ground_row, rng, canopy, density, trunk, trunk_dark)
	return xs


static func _paint_tree(img: Image, x: int, ground_row: int, rng: RandomNumberGenerator,
		canopy: Array, density: float, trunk: Color, trunk_dark: Color) -> void:
	# trees fill most of the sky band, leaving a little headroom for the canopy
	var top := ground_row - rng.randi_range(int(ground_row * 0.62), maxi(int(ground_row * 0.62) + 1, ground_row - 6))
	for y in range(top + 4, ground_row):
		for dx in range(-1, 2):
			_px(img, x + dx, y, trunk_dark if dx == -1 else trunk)
	_px(img, x - 2, ground_row - 1, trunk_dark)
	_px(img, x + 2, ground_row - 1, trunk)
	for b in rng.randi_range(3, 5):
		var by := rng.randi_range(top + 4, top + 16)
		var side := -1 if b % 2 == 0 else 1
		for t in rng.randi_range(4, 9):
			_px(img, x + side * (2 + t), by - int(t * 0.5), trunk_dark)
	for blob in rng.randi_range(4, 6):
		var cx := x + rng.randf_range(-9.0, 9.0)
		var cy := top + rng.randf_range(-2.0, 8.0)
		var r := rng.randf_range(5.0, 9.0)
		for yy in range(floori(cy - r), ceili(cy + r) + 1):
			for xx in range(floori(cx - r), ceili(cx + r) + 1):
				var d := Vector2(xx + 0.5 - cx, (yy + 0.5 - cy) * 1.2).length()
				if d > r or rng.randf() > density:
					continue
				var shade := clampf((yy - (cy - r)) / (2.0 * r), 0.0, 0.999)
				var idx := int(shade * canopy.size())
				if (xx + yy) % 2 == 0 and d > r - 1.5:
					idx = mini(idx + 1, canopy.size() - 1)
				_px(img, xx, yy, canopy[idx])


static func _paint_mossy_roots(img: Image, ground_row: int, tree_xs: Array[int],
		rng: RandomNumberGenerator) -> void:
	for x in tree_xs:
		for side: int in [-1, 1]:
			for t in 6:
				var rx := x + side * (2 + t)
				var lift := 1 if t >= 1 and t <= 3 else 0
				_px(img, rx, ground_row - 1 - lift, FOREST_TRUNK_DARK)
				if rng.randf() < 0.6:
					_px(img, rx, ground_row - 2 - lift, MOSS)


static func _paint_ferns(img: Image, width: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator) -> void:
	for i in 14:
		var x := rng.randi_range(4, width - 5)
		if _near_entrance(x, entrance_col, 18):
			continue
		var h := rng.randi_range(4, 7)
		for k in h - 2:
			_px(img, x, ground_row - 1 - k, FERN_DARK)
		for side: int in [-1, 1]:
			for frond in 2:
				var length := rng.randi_range(5, 9) - frond * 2
				var frond_h := h - frond * 2
				for t in length:
					var u := float(t) / length
					var lift := frond_h * (1.0 - pow(2.0 * u - 0.6, 2.0))
					var y := ground_row - 1 - maxi(0, roundi(lift))
					_px(img, x + side * t, y, FERN_DARK)
					if t % 2 == 1:
						_px(img, x + side * t, y - 1, FERN_LIGHT)


static func _paint_leaf_litter(img: Image, width: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator) -> void:
	for x in width:
		if _near_entrance(x, entrance_col, 12):
			continue
		for k in rng.randi_range(0, 2) + 1:
			if rng.randf() < 0.7:
				_px(img, x, ground_row - k, LEAF_COLORS[rng.randi() % LEAF_COLORS.size()])
	for i in 12:
		var x := rng.randi_range(0, width - 6)
		if _near_entrance(x, entrance_col, 16):
			continue
		for t in rng.randi_range(3, 6):
			_px(img, x + t, ground_row - 1 - int(t * 0.5), AUTUMN_TRUNK_DARK)


# --- Arid backyard ---

static func _paint_fence(img: Image, width: int, ground_row: int, rng: RandomNumberGenerator) -> void:
	const POST_HEIGHT := 15
	const POST_SPACING := 14
	for x in width:
		for rail_y: int in [ground_row - 12, ground_row - 5]:
			if rng.randf() > 0.04:
				_px(img, x, rail_y, FENCE_RAIL)
				_px(img, x, rail_y + 1, FENCE_DARK)
	var x := rng.randi_range(0, 6)
	while x < width:
		for y in range(ground_row - POST_HEIGHT, ground_row):
			_px(img, x, y, FENCE_POST)
			_px(img, x + 1, y, FENCE_DARK)
		_px(img, x, ground_row - POST_HEIGHT - 1, FENCE_POST)
		x += POST_SPACING


static func _paint_scrub(img: Image, width: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator) -> void:
	for i in 6:
		var x := rng.randi_range(6, width - 7)
		if _near_entrance(x, entrance_col, 22):
			continue
		var rw := rng.randi_range(4, 8)
		var rh := rng.randi_range(3, 5)
		for yy in range(ground_row - rh, ground_row):
			for xx in range(x - rw, x + rw + 1):
				var nx := float(xx - x) / rw
				var ny := (ground_row - yy - 0.5) / rh
				if nx * nx + ny * ny > 1.0 or rng.randf() < 0.15:
					continue
				_px(img, xx, yy, SCRUB_LIGHT if ny > 0.6 else SCRUB_DARK)
		for t in 3:
			_px(img, x + rng.randi_range(-rw, rw), ground_row - rh - rng.randi_range(0, 1), TWIG)


# --- Urban sidewalk ---

static func _paint_buildings(img: Image, width: int, ground_row: int, rng: RandomNumberGenerator) -> void:
	var x := -rng.randi_range(0, 10)
	while x < width:
		var bw := rng.randi_range(16, 34)
		var bh := rng.randi_range(mini(10, ground_row - 8), ground_row - 6)
		var wall: Color = BUILDING_COLORS[rng.randi() % BUILDING_COLORS.size()]
		var top := ground_row - bh
		var lit_seed := rng.randi_range(0, 4)
		for yy in range(top, ground_row):
			for xx in range(x, x + bw):
				var c := wall.lightened(0.12) if yy == top else wall
				var wx := xx - x - 2
				var wy := yy - top - 2
				if wx >= 0 and wy >= 0 and xx < x + bw - 2 and yy < ground_row - 2 \
						and wx % 4 < 2 and wy % 4 < 2:
					var window_id := int(wx / 4.0) * 7 + int(wy / 4.0) * 13 + lit_seed
					c = WINDOW_LIT if window_id % 5 == 0 else WINDOW_DARK
				_px(img, xx, yy, c)
		x += bw + rng.randi_range(-4, 3)


static func _paint_curb(img: Image, width: int, ground_row: int) -> void:
	for x in width:
		_px(img, x, ground_row - 3, CURB_TOP)
		_px(img, x, ground_row - 2, CURB)
		_px(img, x, ground_row - 1, CURB_SHADOW)


static func _paint_sidewalk(img: Image, width: int, height: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator) -> void:
	var gap_left := entrance_col - ENTRANCE_CLEARANCE
	var gap_right := entrance_col + ENTRANCE_CLEARANCE
	for x in width:
		if x >= gap_left and x <= gap_right:
			continue
		var seam := x % 32 == 0 or x == gap_left - 1 or x == gap_right + 1
		for y in range(ground_row, height):
			var c := CONCRETE_TOP if y == ground_row else (CONCRETE if rng.randf() < 0.8 else CONCRETE_B)
			_px(img, x, y, SEAM if seam else c)
	for i in 7:
		var x := rng.randi_range(0, width - 8)
		if x + 7 >= gap_left and x <= gap_right:
			continue
		var y := ground_row
		for t in rng.randi_range(3, 7):
			_px(img, x + t, y, SEAM)
			if rng.randf() < 0.5:
				y = clampi(y + rng.randi_range(-1, 1), ground_row, height - 1)


static func _paint_dandelions(img: Image, width: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator) -> void:
	for i in 10:
		var x: int
		if i < 4:  # weeds love the slab edge by the nest
			var offset := rng.randi_range(ENTRANCE_CLEARANCE - 2, ENTRANCE_CLEARANCE)
			x = entrance_col + (offset if i % 2 == 0 else -offset)
		else:
			x = rng.randi_range(2, width - 3)
		if _near_entrance(x, entrance_col, 11):
			continue
		var h := rng.randi_range(3, 6)
		for k in range(1, h):
			_px(img, x, ground_row - k, STEM)
		_px(img, x - 1, ground_row - 1, STEM)
		_px(img, x + 1, ground_row - 1, STEM)
		if rng.randf() < 0.3:
			for d: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				_px(img, x + d.x, ground_row - h - 1 + d.y, PUFF)
		else:
			_px(img, x, ground_row - h, DANDELION)
			_px(img, x + 1, ground_row - h, DANDELION)
			_px(img, x, ground_row - h - 1, DANDELION_LIGHT)
			_px(img, x + 1, ground_row - h - 1, DANDELION)


# --- Meadow ---

static func _paint_wildflowers(img: Image, width: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator, stem: Color) -> void:
	for i in 42:
		var x := rng.randi_range(1, width - 2)
		if _near_entrance(x, entrance_col, 13):
			continue
		var h := rng.randi_range(3, 8)
		var petal: Color = FLOWER_COLORS[rng.randi() % FLOWER_COLORS.size()]
		for k in range(1, h):
			_px(img, x, ground_row - k, stem)
		if h < 5:
			_px(img, x, ground_row - h, petal)
		else:
			_px(img, x - 1, ground_row - h, petal)
			_px(img, x + 1, ground_row - h, petal)
			_px(img, x, ground_row - h - 1, petal)
			_px(img, x, ground_row - h + 1, petal)
			_px(img, x, ground_row - h, FLOWER_CENTER)


static func _paint_clover(img: Image, width: int, ground_row: int, entrance_col: int,
		rng: RandomNumberGenerator) -> void:
	for i in 12:
		var x := rng.randi_range(0, width - 5)
		if _near_entrance(x, entrance_col, 16):
			continue
		for t in 4:
			_px(img, x + t, ground_row - 1, CLOVER)
			if rng.randf() < 0.6:
				_px(img, x + t, ground_row - 2, CLOVER_LIGHT)
		if rng.randf() < 0.5:
			_px(img, x + 1, ground_row - 3, CLOVER_FLOWER)


# ---------------------------------------------------------------------------
# Underground
# ---------------------------------------------------------------------------

static func make_soil_image(width: int, height: int, rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var phases: Array[Vector2] = []
	for i in STRATA_DEPTHS.size():
		phases.append(Vector2(rng.randf() * TAU, rng.randf() * TAU))

	for x in width:
		var bounds: Array[float] = []
		for i in STRATA_DEPTHS.size():
			bounds.append(STRATA_DEPTHS[i] + 2.5 * sin(x * 0.045 + phases[i].x) + 1.2 * sin(x * 0.13 + phases[i].y))
		for y in height:
			# Sampling half the pixels slightly up/down gives a checker dither at each boundary.
			var sample := y + 0.5 + (0.9 if (x + y) % 2 == 0 else -0.9)
			var layer := 0
			for b in bounds:
				if sample > b:
					layer += 1
			var pair: Array = STRATA[layer]
			var c: Color = pair[0] if rng.randf() < 0.72 else pair[1]
			if rng.randf() < 0.02:
				c = c.lightened(0.12)
			img.set_pixel(x, y, c)

	_paint_pebbles(img, width, height, rng)
	_paint_roots(img, width, rng)
	return img


static func _paint_pebbles(img: Image, width: int, height: int, rng: RandomNumberGenerator) -> void:
	for i in 55:
		var px := rng.randi_range(0, width - 4)
		var py := rng.randi_range(6, height - 3)
		var pw := rng.randi_range(1, 3)
		var ph := rng.randi_range(1, 2)
		for y in range(py, py + ph):
			for x in range(px, px + pw):
				img.set_pixel(x, y, PEBBLE_LIGHT if y == py else PEBBLE_DARK)


static func _paint_roots(img: Image, width: int, rng: RandomNumberGenerator) -> void:
	for i in 7:
		var fx := float(rng.randi_range(4, width - 5))
		var drift := rng.randf_range(-0.6, 0.6)
		for y in rng.randi_range(8, 26):
			fx += drift + rng.randf_range(-0.7, 0.7)
			var ix := clampi(int(fx), 0, width - 1)
			img.set_pixel(ix, y, ROOT)
			if rng.randf() < 0.12:
				img.set_pixel(clampi(ix + 1, 0, width - 1), y, ROOT_LIGHT)


## Paints carved tunnels (mask value 1) as open air, with a packed light floor,
## a shadowed ceiling and darker side walls.
static func paint_tunnels(img: Image, mask: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var i := y * w + x
			if mask[i] == 1:
				img.set_pixel(x, y, TUNNEL_AIR if rng.randf() < 0.85 else TUNNEL_AIR_B)
				continue
			var air_above := y > 0 and mask[i - w] == 1
			var air_below := y < h - 1 and mask[i + w] == 1
			var air_side := (x > 0 and mask[i - 1] == 1) or (x < w - 1 and mask[i + 1] == 1)
			if air_above:
				img.set_pixel(x, y, img.get_pixel(x, y).lightened(0.22))
			elif air_below:
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.35))
			elif air_side:
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.2))


# ---------------------------------------------------------------------------
# Bird (a small sparrow-like songbird), facing right
# ---------------------------------------------------------------------------

const BIRD_PERCHED := [
	"..........hh..",
	".........hheh.",
	"........hhhhhb",
	"..ttwwwwwhhhh.",
	".ttwwwwwwcccc.",
	"tt.wwwwwwccc..",
	"....wwwwccc...",
	".....l...l....",
	".....l...l....",
]
const BIRD_HOP := [
	"..........hh..",
	".........hheh.",
	"........hhhhhb",
	"..ttwwwwwhhhh.",
	".ttwwwwwwcccc.",
	"tt.wwwwwwccc..",
	"....wwwwccc...",
	"....l.....l...",
	"..............",
]
const BIRD_FLAP_UP := [
	"....ww........",
	"....www...hh..",
	".....www.hheh.",
	"......wwhhhhhb",
	"..tt.wwwwhhhh.",
	".ttwwwwwwcccc.",
	"tt..wwwwccc...",
	"..............",
	"..............",
]
const BIRD_FLAP_DOWN := [
	"..........hh..",
	".........hheh.",
	"........hhhhhb",
	"..ttwwwwwhhhh.",
	".ttwwwwwwcccc.",
	"tt..wwwwccc...",
	".....www......",
	"......www.....",
	".......ww.....",
]
const BIRD_PALETTE := {
	"h": Color("#7a5a3a"), "e": Color("#101010"), "b": Color("#e0b040"), "t": Color("#5a4028"),
	"w": Color("#9a7448"), "c": Color("#e8dcc4"), "l": Color("#c8a070"),
}

static var _bird_frames: Dictionary = {}


## Bird frames: "perched", "hop", "flap_up", "flap_down".
static func bird_frame(pose: String) -> ImageTexture:
	if _bird_frames.is_empty():
		_bird_frames["perched"] = texture_from_rows(BIRD_PERCHED, BIRD_PALETTE)
		_bird_frames["hop"] = texture_from_rows(BIRD_HOP, BIRD_PALETTE)
		_bird_frames["flap_up"] = texture_from_rows(BIRD_FLAP_UP, BIRD_PALETTE)
		_bird_frames["flap_down"] = texture_from_rows(BIRD_FLAP_DOWN, BIRD_PALETTE)
	return _bird_frames[pose]
