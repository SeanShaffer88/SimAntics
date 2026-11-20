extends RefCounted
## Shared pixel-art data: the five surface presets (names and palettes), UI icons and
## the bird. The surface itself is painted by surface_art.gd, the underground by
## soil_art.gd and the colony's sprites by colony_art.gd.

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
