extends RefCounted
## Procedural colony art: ants of any caste, the queen and winged alates, brood, food,
## refuse and soil pellets. Everything is drawn at HI times screen resolution from
## smooth, anti-aliased shapes (shaded ellipses and capsules, painted back to front)
## and shown scaled down with filtering, so ants keep fine detail - jointed legs,
## elbowed antennae, glossy segmented gasters - at their real on-screen size.

const HI := 2  # art pixels per screen pixel
const SPRITE_SCALE := 1.0 / HI  # ants and the queen
const ITEM_SCALE := 1.0 / HI  # brood, food, refuse and pellets
const DETAIL := 1.2  # screen px per ant body unit; a size-1 worker is about 19 px long
const FRAMES := 4
const LIGHT := Vector3(-0.45, -0.75, 0.6)
const OUTLINE_ALPHA := 0.55

static var _cache: Dictionary = {}


# ---------------------------------------------------------------------------
# Painting helpers (all in art pixels)
# ---------------------------------------------------------------------------

static func _blank(w: int, h: int) -> Image:
	var img := Image.create_empty(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _texture(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _cached(key: String, build: Callable) -> ImageTexture:
	if not _cache.has(key):
		_cache[key] = _texture(build.call())
	return _cache[key]


static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if c.a <= 0.0:
		return
	img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


static func _shade(n: Vector3, base: Color, dark: Color, light: Color, gloss: float) -> Color:
	var lambert := clampf(n.dot(LIGHT.normalized()), 0.0, 1.0)
	var col := dark.lerp(base, lambert / 0.55) if lambert < 0.55 else base.lerp(light, (lambert - 0.55) / 0.45)
	if gloss > 0.0:
		var spec := smoothstep(0.88, 0.985, lambert)
		col = col.lerp(Color(1, 1, 1), spec * gloss)
	return col


## A lit, anti-aliased ellipse. `bands` draws segment seams across it (gaster tergites,
## larva segments); `rim` darkens the edge into a soft outline.
static func _ellipse(img: Image, c: Vector2, r: Vector2, base: Color, dark: Color, light: Color,
		gloss := 0.6, bands := 0, angle := 0.0, alpha := 1.0, rim := 0.45) -> void:
	var ext := maxf(r.x, r.y) + 1.5
	for y in range(maxi(0, floori(c.y - ext)), mini(img.get_height(), ceili(c.y + ext) + 1)):
		for x in range(maxi(0, floori(c.x - ext)), mini(img.get_width(), ceili(c.x + ext) + 1)):
			var q := (Vector2(x + 0.5, y + 0.5) - c).rotated(-angle)
			var n2 := q / r
			var d := n2.length()
			var cover := clampf(0.5 - (d - 1.0) * minf(r.x, r.y), 0.0, 1.0)
			if cover <= 0.0:
				continue
			var z := sqrt(maxf(0.0, 1.0 - minf(d * d, 1.0)))
			var col := _shade(Vector3(n2.x, n2.y, z).normalized(), base, dark, light, gloss)
			if bands > 0:
				var s := fposmod((n2.x + 1.0) * 0.5 * bands, 1.0)
				if s < 0.14:
					col = col.darkened(0.28 * (1.0 - s / 0.14))
			col = col.darkened(rim * smoothstep(0.72, 1.0, d))
			_put(img, x, y, Color(col, cover * alpha))


## An anti-aliased capsule (a leg segment, an antenna, a mandible), rounded and lit.
static func _capsule(img: Image, a: Vector2, b: Vector2, r: float, col: Color, alpha := 1.0) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (r + 1.5)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (r + 1.5)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	for y in range(maxi(0, floori(lo.y)), mini(img.get_height(), ceili(hi.y) + 1)):
		for x in range(maxi(0, floori(lo.x)), mini(img.get_width(), ceili(hi.x) + 1)):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
			var off := p - (a + ab * t)
			var dist := off.length()
			var cover := clampf(0.5 - (dist - r), 0.0, 1.0)
			if cover <= 0.0:
				continue
			var e := clampf(dist / maxf(r, 0.01), 0.0, 1.0)
			var shade := col.lightened(0.25 * clampf(-off.normalized().y, 0.0, 1.0) * (1.0 - e)).darkened(0.35 * e * e)
			_put(img, x, y, Color(shade, cover * alpha))


## A thin dark outline around the opaque shape, so small sprites read against soil.
static func _outline(img: Image, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var add: Array[Vector3i] = []
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a >= 0.5:
				continue
			var near := 0.0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var px := x + d.x
				var py := y + d.y
				if px >= 0 and py >= 0 and px < w and py < h:
					near = maxf(near, img.get_pixel(px, py).a)
			if near >= 0.5:
				add.append(Vector3i(x, y, int(near * 255.0)))
	for v in add:
		var under := img.get_pixel(v.x, v.y)
		var o := Color(color, OUTLINE_ALPHA * v.z / 255.0)
		img.set_pixel(v.x, v.y, o.blend(under) if under.a > 0.0 else o)


static func _hash(x: float, y: float) -> float:
	return fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)


# ---------------------------------------------------------------------------
# Ants
# ---------------------------------------------------------------------------

## Walk-cycle frames for one body plan. `size` scales the whole ant, `head` the head only.
static func ant_frames(species: Dictionary, size: float, head: float, queen: bool = false,
		wings: bool = false) -> Array[ImageTexture]:
	var key := "%s|%.2f|%.2f|%s|%s" % [species["id"], size, head, queen, wings]
	if _cache.has(key):
		return _cache[key]
	var frames: Array[ImageTexture] = []
	for f in FRAMES:
		frames.append(_texture(_draw_ant(species, size, head, queen, f, wings)))
	_cache[key] = frames
	return frames


static func _draw_ant(species: Dictionary, size: float, head: float, queen: bool, frame: int,
		wings: bool, pupa := false) -> Image:
	var u := size * DETAIL * (1.25 if queen else 1.0) * HI
	var gaster_len := 3.2 * u * (1.45 if queen else 1.0)
	var meso_len := 1.9 * u * (1.3 if queen else 1.0)
	var head_r := Vector2(1.55, 1.35) * u * head
	var top := (3.0 * HI) if wings else 0.0
	var gaster := Vector2(gaster_len + 0.6 * HI, 3.9 * u + top)
	var petiole := Vector2(gaster.x + gaster_len + 0.5 * u, 4.1 * u + top)
	var meso := Vector2(petiole.x + 0.6 * u + meso_len, 3.7 * u + top)
	var head_c := Vector2(meso.x + meso_len + head_r.x * 0.85, 3.4 * u - (head - 1.0) * 0.6 * u + top)
	var width := ceili(head_c.x + head_r.x + 2.8 * u)
	var height := ceili(8.2 * u + maxf(0.0, (head - 1.0) * 0.8 * u) + top)
	var ground := height - 1.0 * HI
	var img := _blank(width, height)

	var body: Color = species["body"]
	var gaster_col: Color = species["gaster"]
	var dark: Color = species["dark"]
	var light: Color = species["light"]
	if pupa:  # a pale, soft pupa: the adult's shape before its cuticle darkens
		body = Color("#efe6d2")
		gaster_col = Color("#ece2cc")
		dark = Color("#b8a888")
		light = Color("#ffffff")
	var leg_col := dark.lerp(body, 0.4)

	if pupa:
		_folded_legs(img, meso, meso_len, u, leg_col.lightened(0.1))
	else:
		_legs(img, meso, meso_len, u, ground, frame + 2, dark.lerp(body, 0.15).darkened(0.15), -0.6 * u)
	# gaster with tergite seams, petiole node, two-part mesosoma, head
	_ellipse(img, gaster, Vector2(gaster_len, 2.3 * u * (1.2 if queen else 1.0)), gaster_col, dark, light,
			0.75, 4 if queen else 3, -0.06)
	_capsule(img, gaster + Vector2(gaster_len * 0.8, -0.2 * u), petiole, 0.45 * u, body.darkened(0.15))
	_ellipse(img, petiole + Vector2(0, -0.25 * u), Vector2(0.65, 0.95) * u, body, dark, light, 0.5)
	_ellipse(img, meso + Vector2(-meso_len * 0.45, 0.1 * u), Vector2(meso_len * 0.55, 1.05 * u), body, dark, light, 0.5)
	_ellipse(img, meso + Vector2(meso_len * 0.3, -0.1 * u), Vector2(meso_len * 0.72, 1.25 * u * (1.25 if queen else 1.0)),
			body, dark, light, 0.6)
	if queen:  # scars where her wings were shed after mating
		_ellipse(img, meso + Vector2(-0.2 * u, -1.0 * u), Vector2(0.35, 0.25) * u, light, body, Color.WHITE, 0.3)
		_ellipse(img, meso + Vector2(0.7 * u, -1.1 * u), Vector2(0.35, 0.25) * u, light, body, Color.WHITE, 0.3)
	_ellipse(img, head_c, head_r, body, dark, light, 0.7)
	# compound eye, mandibles, elbowed antenna with a clubbed tip
	var eye := head_c + Vector2(head_r.x * 0.22, -head_r.y * 0.12)
	_ellipse(img, eye, Vector2(0.42, 0.36) * u, Color("#1a120c"), Color("#050302"), Color("#6a5a4a"), 0.9, 0, 0.0, 1.0, 0.1)
	var jaw := head_c + Vector2(head_r.x * 0.88, head_r.y * 0.38)
	_capsule(img, jaw, jaw + Vector2(1.15 * u, 0.15 * u), 0.26 * u, dark.lerp(body, 0.3))
	_capsule(img, jaw + Vector2(0.9 * u, 0.1 * u), jaw + Vector2(1.2 * u, 0.55 * u), 0.18 * u, dark.lerp(body, 0.3))
	var scape_base := head_c + Vector2(head_r.x * 0.5, -head_r.y * 0.72)
	if pupa:  # antennae folded down along the face
		_capsule(img, scape_base, scape_base + Vector2(0.4 * u, 1.6 * u), 0.22 * u, leg_col)
	else:
		var elbow := scape_base + Vector2(0.45 * u, -1.65 * u)
		var bob := (0.4 if frame % 2 == 0 else -0.2) * u
		var tip := elbow + Vector2(2.0 * u, 1.2 * u + bob)
		_capsule(img, scape_base, elbow, 0.22 * u, leg_col)
		_capsule(img, elbow, tip, 0.19 * u, leg_col)
		_ellipse(img, tip, Vector2(0.38, 0.3) * u, leg_col, dark, light, 0.2, 0, (tip - elbow).angle())
	if not pupa:
		_legs(img, meso, meso_len, u, ground, frame, leg_col, 0.0)
	if wings:
		_wings(img, meso, gaster, queen, u)
	_outline(img, dark.darkened(0.5) if not pupa else Color("#8a7a60"))
	return img


## Three legs on one side in a tripod gait: femur, tibia and tarsus, with knee joints.
static func _legs(img: Image, meso: Vector2, meso_len: float, u: float, ground: float,
		frame: int, color: Color, x_shift: float) -> void:
	const SWING := [-1.0, 0.0, 1.0, 0.0]
	for i in 3:  # hind, mid, fore
		var hip := Vector2(meso.x - meso_len * 0.6 + i * meso_len * 0.6 + x_shift, meso.y + 0.8 * u)
		var reach: float = [-2.5, 0.2, 2.3][i] * u
		var phase: int = (frame + (2 if i == 1 else 0)) % FRAMES
		var swing: float = SWING[phase]
		var foot := Vector2(hip.x + reach + swing * 0.9 * u, ground)
		foot.y -= 0.8 * u if phase == 1 else 0.0  # the swinging leg is lifted
		var knee := Vector2(hip.x + (foot.x - hip.x) * 0.5, hip.y - 0.55 * u)
		var ankle := knee.lerp(foot, 0.72)
		_capsule(img, hip, knee, 0.3 * u, color)
		_capsule(img, knee, ankle, 0.22 * u, color)
		_capsule(img, ankle, foot, 0.15 * u, color.darkened(0.1))


## A pupa's legs, folded tight against the body.
static func _folded_legs(img: Image, meso: Vector2, meso_len: float, u: float, color: Color) -> void:
	for i in 3:
		var hip := Vector2(meso.x - meso_len * 0.5 + i * meso_len * 0.5, meso.y + 0.9 * u)
		_capsule(img, hip, hip + Vector2(-1.2 * u, 1.0 * u), 0.26 * u, color)
		_capsule(img, hip + Vector2(-1.2 * u, 1.0 * u), hip + Vector2(0.3 * u, 1.5 * u), 0.22 * u, color)


## Long translucent wings folded back over the body, with veins and a faint sheen.
static func _wings(img: Image, meso: Vector2, gaster: Vector2, queen: bool, u: float) -> void:
	var root := meso + Vector2(0.2 * u, -1.0 * u)
	var tip := Vector2(gaster.x - (3.2 if queen else 2.4) * u, gaster.y - 2.6 * u)
	var c := (root + tip) * 0.5
	var r := Vector2(root.distance_to(tip) * 0.55, (1.7 if queen else 1.4) * u)
	var ang := (tip - root).angle()
	_ellipse(img, c, r, Color(0.88, 0.92, 0.98), Color(0.7, 0.75, 0.85), Color(1, 1, 1), 0.8, 0, ang, 0.45, 0.25)
	_ellipse(img, c + Vector2(0, 0.8 * u), r * Vector2(0.85, 0.8), Color(0.86, 0.9, 0.96), Color(0.68, 0.72, 0.82),
			Color(1, 1, 1), 0.6, 0, ang, 0.35, 0.25)
	var vein := Color(0.42, 0.36, 0.3)
	_capsule(img, root, root.lerp(tip, 0.95), 0.12 * u, vein, 0.7)
	_capsule(img, root.lerp(tip, 0.35), root.lerp(tip, 0.6) + Vector2(0, -0.9 * u), 0.08 * u, vein, 0.55)


# ---------------------------------------------------------------------------
# Brood
# ---------------------------------------------------------------------------

## A pearly, slightly translucent egg.
static func egg() -> ImageTexture:
	return _cached("egg", func() -> Image:
		var img := _blank(6 * HI, 5 * HI)
		_ellipse(img, Vector2(3, 2.6) * HI, Vector2(2.4, 1.8) * HI, Color("#f4eedf"), Color("#c8bca6"), Color("#ffffff"),
				1.0, 0, -0.2, 0.95, 0.3)
		_outline(img, Color("#8a7c64"))
		return img)


## A larva: a curled, segmented grub that grows with each meal; the gut shows through
## its translucent body once it has been fed.
static func larva(stage: int) -> ImageTexture:
	return _cached("larva%d" % stage, func() -> Image:
		var length := (6.0 + stage * 3.0) * HI
		var img := _blank(ceili(length) + 3 * HI, ceili(length * 0.62) + 3 * HI)
		var segments := 5 + stage * 2
		var mid := Vector2(img.get_width() * 0.5, img.get_height() * 0.5)
		for s in range(segments - 1, -1, -1):  # tail first, head last
			var t := float(s) / (segments - 1)
			var ang := lerpf(PI * 0.12, PI * 1.28, t)
			var at := mid + Vector2(cos(ang), sin(ang)) * Vector2(length * 0.34, length * 0.2)
			var r := lerpf(1.7, 1.05, t) * (1.0 + stage * 0.16) * HI
			_ellipse(img, at, Vector2(r, r * 0.95), Color("#efe5cc"), Color("#bba98a"), Color("#fffaf0"), 0.7, 0, 0.0, 1.0, 0.35)
			if stage > 0 and t > 0.2 and t < 0.75:  # the gut, darkened by food
				_ellipse(img, at, Vector2(r, r) * 0.45, Color(0.55, 0.42, 0.28), Color(0.4, 0.3, 0.2), Color(0.7, 0.55, 0.4),
						0.0, 0, 0.0, 0.35, 0.0)
		var head_ang := PI * 1.28
		var head := mid + Vector2(cos(head_ang), sin(head_ang)) * Vector2(length * 0.34, length * 0.2)
		_ellipse(img, head + Vector2(0.6, -0.3) * HI, Vector2(0.55, 0.45) * HI, Color("#8a6a40"), Color("#5a4428"),
				Color("#c09a6a"), 0.4)  # mouthparts
		_outline(img, Color("#8a7a5c"))
		return img)


## A pupa: a silk cocoon (with the dark meconium spot at one end) for species that
## spin one, otherwise a pale naked pupa showing the adult's folded legs.
static func pupa(cocoon: bool) -> ImageTexture:
	return _cached("pupa%s" % cocoon, func() -> Image:
		if not cocoon:
			var pale := {"id": "pupa", "body": Color("#efe6d2"), "gaster": Color("#ece2cc"),
					"dark": Color("#b8a888"), "light": Color("#ffffff")}
			return _draw_ant(pale, 0.82, 1.0, false, 0, false, true)
		var img := _blank(16 * HI, 9 * HI)
		var c := Vector2(8, 4.4) * HI
		var r := Vector2(7.2, 3.6) * HI
		_ellipse(img, c, r, Color("#d4b882"), Color("#94784e"), Color("#f4e4bc"), 0.35, 0, 0.0, 1.0, 0.35)
		for i in 26:  # loose silk threads over the surface
			var a := Vector2(_hash(i, 1.0) * 2.0 - 1.0, _hash(i, 2.0) * 2.0 - 1.0) * 0.8
			var p := c + Vector2(a.x * r.x, a.y * r.y)
			_capsule(img, p, p + Vector2(_hash(i, 3.0) * 4.0 - 2.0, _hash(i, 4.0) * 2.0 - 1.0) * HI, 0.18 * HI,
					Color("#f2e6c8"), 0.55)
		_ellipse(img, c + Vector2(-r.x * 0.82, 0.2 * HI), Vector2(0.9, 1.0) * HI, Color("#4a3420"), Color("#2a1c10"),
				Color("#6a5034"), 0.2)
		_outline(img, Color("#6a5434"))
		return img)


# ---------------------------------------------------------------------------
# Food, refuse and soil
# ---------------------------------------------------------------------------

const SEED_TONES := [Color("#a07040"), Color("#c09a5a"), Color("#7a5a36"), Color("#d0b070")]


static func _seed(img: Image, c: Vector2, variant: int, angle: float) -> void:
	var base: Color = SEED_TONES[variant % SEED_TONES.size()]
	_ellipse(img, c, Vector2(2.4, 1.6) * HI, base, base.darkened(0.45), base.lightened(0.4), 0.7, 0, angle)
	var along := Vector2.RIGHT.rotated(angle)
	_capsule(img, c - along * 1.3 * HI, c + along * 1.3 * HI, 0.15 * HI, base.darkened(0.3), 0.7)  # the seed's groove


static func seed_texture(variant: int) -> ImageTexture:
	return _cached("seed%d" % variant, func() -> Image:
		var img := _blank(6 * HI, 5 * HI)
		_seed(img, Vector2(3, 2.5) * HI, variant, -0.15 + 0.1 * variant)
		_outline(img, Color("#3a2614"))
		return img)


## A stored seed that got damp and germinated: a pale root and a green shoot.
static func sprouted_seed(variant: int) -> ImageTexture:
	return _cached("sprout%d" % variant, func() -> Image:
		var img := _blank(7 * HI, 9 * HI)
		_seed(img, Vector2(3, 6.8) * HI, variant, 0.1)
		_capsule(img, Vector2(3.4, 6) * HI, Vector2(3.6, 2.6) * HI, 0.3 * HI, Color("#8ac050"))
		_ellipse(img, Vector2(2.6, 2.2) * HI, Vector2(1.1, 0.55) * HI, Color("#7ab848"), Color("#4a8a2a"), Color("#b8e080"), 0.4, 0, -0.5)
		_ellipse(img, Vector2(4.5, 2.0) * HI, Vector2(1.1, 0.55) * HI, Color("#7ab848"), Color("#4a8a2a"), Color("#b8e080"), 0.4, 0, 0.5)
		_capsule(img, Vector2(4.8, 7.4) * HI, Vector2(6.3, 8.3) * HI, 0.18 * HI, Color("#efe6cc"))  # the root
		_outline(img, Color("#2a3a14"))
		return img)


## Bits of insect prey: a beetle chunk with a leg, a veined wing, a caterpillar segment.
static func prey_bit(variant: int) -> ImageTexture:
	return _cached("prey%d" % variant, func() -> Image:
		var img := _blank(10 * HI, 7 * HI)
		var tones := [Color("#3a2a1a"), Color("#5a4a20"), Color("#6a3020"), Color("#2a3a20"), Color("#4a3a30")]
		var base: Color = tones[variant % tones.size()]
		match variant % 3:
			0:
				_capsule(img, Vector2(5.5, 4.2) * HI, Vector2(8.8, 6.0) * HI, 0.3 * HI, base.darkened(0.2))
				_capsule(img, Vector2(4.0, 4.6) * HI, Vector2(2.0, 6.3) * HI, 0.28 * HI, base.darkened(0.2))
				_ellipse(img, Vector2(4.2, 3.4) * HI, Vector2(3.1, 2.1) * HI, base, base.darkened(0.55), base.lightened(0.6), 0.9, 2)
			1:
				_ellipse(img, Vector2(5, 3.4) * HI, Vector2(4.3, 1.8) * HI, Color("#d4d0c2"), Color("#908c7e"),
						Color("#ffffff"), 0.8, 0, -0.1, 0.7, 0.3)
				_capsule(img, Vector2(1.2, 3.6) * HI, Vector2(8.8, 3.0) * HI, 0.13 * HI, Color("#6e6a5c"), 0.8)
				_capsule(img, Vector2(4.0, 3.4) * HI, Vector2(6.5, 2.0) * HI, 0.1 * HI, Color("#6e6a5c"), 0.7)
			2:
				for s in 4:
					_ellipse(img, Vector2(2.0 + s * 2.0, 3.6) * HI, Vector2(1.4, 1.6) * HI, base.lightened(0.4),
							base, base.lightened(0.75), 0.5)
				_ellipse(img, Vector2(5, 3.0) * HI, Vector2(0.5, 0.4) * HI, Color("#f0e0a0"), Color("#c0a060"), Color.WHITE, 0.2)
		_outline(img, Color("#140c06"))
		return img)


## A cut leaf fragment, as carried home by leafcutter foragers: the curved edge their
## mandibles cut, a midrib and side veins.
static func leaf_piece(variant: int) -> ImageTexture:
	return _cached("leaf%d" % variant, func() -> Image:
		var greens := [Color("#5a9a3a"), Color("#6aa848"), Color("#4a8a34"), Color("#8ab84a")]
		var base: Color = greens[variant % greens.size()]
		var img := _blank(9 * HI, 8 * HI)
		var c := Vector2(4.5, 7.2) * HI
		for y in img.get_height():
			for x in img.get_width():
				var p := Vector2(x + 0.5, y + 0.5)
				var q := (p - c) / Vector2(4.2, 6.4) / HI
				var d := q.length()
				var serr := 0.04 * sin(atan2(q.y, q.x) * 18.0)
				var cover := clampf(0.5 - (d - 1.0 - serr) * 4.2 * HI, 0.0, 1.0)
				if cover <= 0.0 or p.y > c.y:
					continue
				var col := base.lightened(0.18 * clampf(-q.y, 0.0, 1.0)).darkened(0.2 * clampf(q.x, 0.0, 1.0))
				_put(img, x, y, Color(col, cover))
		_capsule(img, c, c + Vector2(0, -5.8) * HI, 0.22 * HI, base.darkened(0.25))
		for i in 3:
			var at := c + Vector2(0, -1.5 - i * 1.6) * HI
			_capsule(img, at, at + Vector2(-2.2, -1.1) * HI, 0.12 * HI, base.darkened(0.2), 0.8)
			_capsule(img, at, at + Vector2(2.2, -1.1) * HI, 0.12 * HI, base.darkened(0.2), 0.8)
		_outline(img, Color("#1e3a12"))
		return img)


## A tuft of fungus that nurses pick from the garden to feed larvae.
static func fungus_crumb() -> ImageTexture:
	return _cached("fungus_crumb", func() -> Image:
		var img := _blank(5 * HI, 4 * HI)
		for b: Vector3 in [Vector3(1.6, 2.4, 1.2), Vector3(3.2, 2.5, 1.3), Vector3(2.4, 1.5, 1.2)]:
			_ellipse(img, Vector2(b.x, b.y) * HI, Vector2(b.z, b.z) * HI, Color("#ebe7d8"), Color("#aaa694"), Color("#ffffff"), 0.4)
		_outline(img, Color("#6a6656"))
		return img)


## What is left after feeding: split seed husks, prey exoskeleton or spent fungus substrate.
static func waste_bit(food: String, variant: int) -> ImageTexture:
	return _cached("waste_%s%d" % [food, variant], func() -> Image:
		var img := _blank(6 * HI, 4 * HI)
		var base: Color
		match food:
			"seeds":
				base = [Color("#5a3a20"), Color("#6a4a2a")][variant % 2]
			"fungus":
				base = [Color("#6a5a44"), Color("#5a4c3a")][variant % 2]
			_:
				base = [Color("#2a2018"), Color("#3a2a1e")][variant % 2]
		# two curled halves of a husk or shell
		_capsule(img, Vector2(0.8, 3.0) * HI, Vector2(2.6, 1.2) * HI, 0.4 * HI, base)
		_capsule(img, Vector2(3.0, 1.2) * HI, Vector2(5.0, 2.8) * HI, 0.4 * HI, base.lightened(0.2))
		_outline(img, base.darkened(0.6))
		return img)


## A spongy fungus garden filling the lower part of a chamber (`width`, `height` in
## screen pixels).
static func fungus_garden(width: int, height: int, rng_seed: int) -> ImageTexture:
	var w := width * HI
	var h := height * HI
	var img := _blank(w, h)
	var noise := FastNoiseLite.new()
	noise.seed = rng_seed
	noise.frequency = 0.11 / HI
	noise.fractal_octaves = 3
	for y in h:
		for x in w:
			var nx := (x + 0.5 - w * 0.5) / (w * 0.5)
			var ny := (h - y - 0.5) / h
			var edge := (1.0 - nx * nx) * 0.95 + noise.get_noise_2d(x, 0) * 0.15
			if ny > edge:
				continue
			var n := noise.get_noise_2d(x, y)
			if n < -0.32:
				continue  # the garden is full of holes and galleries
			var c := Color("#dcd8c8").lerp(Color("#9c9886"), clampf(0.5 - n, 0.0, 1.0))
			c = c.lightened(0.12 * clampf(n * 2.0, 0.0, 1.0))
			if n > 0.42:
				c = Color("#f2eee2")  # fresh hyphae, the ants' crop
			var cover := clampf((edge - ny) * h, 0.0, 1.0) * clampf((n + 0.32) * 20.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(c, cover))
	_outline(img, Color("#5a5648"))
	return _texture(img)


## A heap of spent material, husks and exoskeleton pieces (size in screen pixels).
static func refuse_heap(width: int, height: int, rng_seed: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var w := width * HI
	var h := height * HI
	var img := _blank(w, h)
	var tones := [Color("#3a3026"), Color("#4e4232"), Color("#2a221c"), Color("#6a5a40"), Color("#5a2a1a")]
	for i in width * height / 4:
		var x := rng.randf_range(1.0, w - 1.0)
		var nx := (x - w * 0.5) / (w * 0.5)
		var top := h - (1.0 - nx * nx) * h
		var y := rng.randf_range(top, h - 1.0)
		var base: Color = tones[rng.randi() % tones.size()]
		_ellipse(img, Vector2(x, y), Vector2(rng.randf_range(0.6, 1.4), rng.randf_range(0.4, 0.9)) * HI,
				base, base.darkened(0.4), base.lightened(0.3), 0.3, 0, rng.randf() * TAU)
	return _texture(img)


const FOOD_TYPES := ["sugar", "nectar", "fruit", "protein", "seeds"]


## The crumb an ant carries home from a food drop.
static func food_crumb(kind: String, variant: int) -> ImageTexture:
	return _cached("crumb_%s%d" % [kind, variant], func() -> Image:
		var img := _blank(5 * HI, 5 * HI)
		match kind:
			"sugar":  # a sugar crystal: three lit faces
				var c := Vector2(2.5, 2.7) * HI
				var s := 1.7 * HI
				var faces := [
					[PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, -s * 0.45), c + Vector2(0, 0.1 * s), c + Vector2(-s, -s * 0.45)]), Color("#ffffff")],
					[PackedVector2Array([c + Vector2(-s, -s * 0.45), c + Vector2(0, 0.1 * s), c + Vector2(0, s), c + Vector2(-s, s * 0.5)]), Color("#dde4ec")],
					[PackedVector2Array([c + Vector2(0, 0.1 * s), c + Vector2(s, -s * 0.45), c + Vector2(s, s * 0.5), c + Vector2(0, s)]), Color("#b4bec8")]]
				for y in img.get_height():
					for x in img.get_width():
						for f: Array in faces:
							if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), f[0]):
								img.set_pixel(x, y, f[1])
			"nectar":
				_ellipse(img, Vector2(2.5, 2.8) * HI, Vector2(1.9, 1.7) * HI, Color(0.93, 0.66, 0.15), Color(0.72, 0.42, 0.06),
						Color(1.0, 0.9, 0.6), 1.0, 0, 0.0, 0.9)
			"fruit":
				var tones := [Color("#f07828"), Color("#e04030"), Color("#f8a040")]
				var base: Color = tones[variant % tones.size()]
				_ellipse(img, Vector2(2.5, 2.8) * HI, Vector2(2.1, 1.6) * HI, base, base.darkened(0.35), base.lightened(0.45), 0.8, 0, 0.3)
				_ellipse(img, Vector2(1.6, 2.2) * HI, Vector2(0.5, 0.35) * HI, Color("#fff0d8"), Color("#e8c8a0"), Color.WHITE, 0.3)
			"protein":
				var shell := Color("#c8281a") if variant % 2 == 0 else Color("#241a18")
				_ellipse(img, Vector2(2.5, 2.8) * HI, Vector2(2.1, 1.5) * HI, shell, shell.darkened(0.55), shell.lightened(0.5), 1.0)
				_ellipse(img, Vector2(2.0, 2.6) * HI, Vector2(0.45, 0.45) * HI, Color("#100808"), Color.BLACK, Color("#404040"), 0.2)
			_:
				_seed(img, Vector2(2.5, 2.8) * HI, variant, 0.2)
		_outline(img, Color("#1a100a"))
		return img)


## A pellet of excavated soil, carried up and dropped beside the entrance.
static func soil_pellet(soil: Color) -> ImageTexture:
	return _cached("pellet_" + soil.to_html(false), func() -> Image:
		var img := _blank(5 * HI, 5 * HI)
		_ellipse(img, Vector2(2.5, 2.6) * HI, Vector2(2.0, 1.8) * HI, soil, soil.darkened(0.45), soil.lightened(0.3), 0.15)
		for i in 5:  # grains of sand in the moistened pellet
			var p := Vector2(1.2 + _hash(i, 9.0) * 2.6, 1.4 + _hash(i, 7.0) * 2.4) * HI
			_ellipse(img, p, Vector2(0.35, 0.3) * HI, soil.lightened(0.35), soil.darkened(0.2), Color.WHITE, 0.3)
		_outline(img, soil.darkened(0.6))
		return img)


# ---------------------------------------------------------------------------
# Creatures living in the soil
# ---------------------------------------------------------------------------

## Soil-dwelling insects and worms (frame 0 or 1, for a slow wriggle):
##   grub      - a scarab beetle larva, plump, white and curled into a C
##   wireworm  - a click-beetle larva, slender, tough and orange-brown
##   pupa      - a moth pupa, a glossy brown spindle
##   beetle    - an adult ground beetle, black and shiny
##   worm      - an earthworm, pink, ringed, with its saddle-like clitellum
static func critter(kind: String, frame: int) -> ImageTexture:
	return _cached("critter_%s%d" % [kind, frame], func() -> Image:
		var f := 1.0 if frame == 1 else 0.0
		match kind:
			"grub":
				var img := _blank(20 * HI, 15 * HI)
				var mid := Vector2(10, 7.5) * HI
				for s in range(10, -1, -1):
					var t := s / 10.0
					var ang := lerpf(PI * 0.1, PI * 1.35, t) + f * 0.12
					var at := mid + Vector2(cos(ang), sin(ang)) * Vector2(6.2, 4.6) * HI
					var r := lerpf(3.0, 2.2, t) * HI
					_ellipse(img, at, Vector2(r, r * 0.95), Color("#f2ead6"), Color("#bfae8c"), Color("#fffcf2"), 0.6, 0, 0.0, 1.0, 0.3)
					if t < 0.55:  # the dark hind gut showing through
						_ellipse(img, at, Vector2(r, r) * 0.45, Color(0.45, 0.38, 0.32), Color(0.3, 0.25, 0.2), Color(0.6, 0.5, 0.42), 0.0, 0, 0.0, 0.4, 0.0)
				var head_ang := PI * 1.35 + f * 0.12
				var head := mid + Vector2(cos(head_ang), sin(head_ang)) * Vector2(6.2, 4.6) * HI
				for k in 3:  # three pairs of small legs behind the head
					var leg := head + Vector2(1.2 + k * 1.3, 2.2) * HI
					_capsule(img, leg, leg + Vector2(0.6, 1.6) * HI, 0.3 * HI, Color("#c8924a"))
				_ellipse(img, head, Vector2(2.4, 2.2) * HI, Color("#c8823a"), Color("#7a4a1e"), Color("#f0b878"), 0.8)
				_outline(img, Color("#5a4a34"))
				return img
			"wireworm":
				var img := _blank(24 * HI, 8 * HI)
				for s in range(14, -1, -1):
					var t := s / 14.0
					var at := Vector2(2.5 + t * 19.0, 4.0 + sin(t * PI * 1.6 + f * 1.2) * 1.3) * HI
					_ellipse(img, at, Vector2(1.2, 1.3) * HI, Color("#d0943c"), Color("#8a5a1e"), Color("#f4c878"), 0.9, 0, 0.0, 1.0, 0.4)
				_ellipse(img, Vector2(21.8, 4.0 + sin(PI * 1.6 + f * 1.2) * 1.3) * HI, Vector2(1.3, 1.1) * HI,
						Color("#6a3a14"), Color("#3a1e08"), Color("#a06030"), 0.8)
				_outline(img, Color("#4a2a0c"))
				return img
			"pupa":
				var img := _blank(18 * HI, 9 * HI)
				var c := Vector2(9, 4.5) * HI
				_ellipse(img, c, Vector2(7.6, 3.4) * HI, Color("#8a4a22"), Color("#4a2410"), Color("#d08a50"), 1.0, 5, f * 0.08)
				_ellipse(img, c + Vector2(3.6, -0.6) * HI, Vector2(3.2, 2.4) * HI, Color("#7a4020"), Color("#40200c"),
						Color("#c0804a"), 0.9, 0, 0.0, 0.85)  # folded wing cases
				_outline(img, Color("#2a1408"))
				return img
			"beetle":
				var img := _blank(18 * HI, 11 * HI)
				var body := Vector2(8, 5.2) * HI
				for k in 3:  # legs
					var hip := body + Vector2(-1.5 + k * 2.4, 2.0) * HI
					var foot := hip + Vector2((-2.4 + k * 2.2) + f * (1 - k) * 0.6, 3.0) * HI
					_capsule(img, hip, (hip + foot) * 0.5 + Vector2(0, -0.6) * HI, 0.4 * HI, Color("#1a1614"))
					_capsule(img, (hip + foot) * 0.5 + Vector2(0, -0.6) * HI, foot, 0.3 * HI, Color("#1a1614"))
				_ellipse(img, body, Vector2(5.6, 3.3) * HI, Color("#262428"), Color("#08080a"), Color("#8a8aa0"), 1.0)
				_capsule(img, body + Vector2(-5.0, -0.2) * HI, body + Vector2(4.0, -0.4) * HI, 0.18 * HI, Color("#0a0a0c"))  # wing-case seam
				_ellipse(img, body + Vector2(6.2, -0.4) * HI, Vector2(2.0, 1.9) * HI, Color("#2a282c"), Color("#0a0a0c"), Color("#8a8aa0"), 0.9)
				_ellipse(img, body + Vector2(8.6, -0.2) * HI, Vector2(1.3, 1.2) * HI, Color("#222024"), Color("#08080a"), Color("#7a7a8a"), 0.8)
				_capsule(img, body + Vector2(9.4, -0.8) * HI, body + Vector2(10.8, -3.2) * HI, 0.22 * HI, Color("#1a1614"))
				_capsule(img, body + Vector2(9.6, 0.2) * HI, body + Vector2(11.2, -1.0) * HI, 0.22 * HI, Color("#1a1614"))
				_outline(img, Color("#000000"))
				return img
			"worm":
				var img := _blank(34 * HI, 10 * HI)
				for s in range(30, -1, -1):
					var t := s / 30.0
					var at := Vector2(2.5 + t * 29.0, 5.0 + sin(t * PI * 2.2 + f * 1.4) * 2.2) * HI
					var r := lerpf(1.4, 1.8, sin(t * PI)) * HI
					var base := Color("#d88a84") if absf(t - 0.68) > 0.06 else Color("#c4605a")  # the clitellum
					_ellipse(img, at, Vector2(r, r), base, base.darkened(0.4), base.lightened(0.35), 0.8, 0, 0.0, 1.0, 0.3)
				_outline(img, Color("#6a3430"))
				return img
		return _blank(1, 1))


## A small hollow in the soil, the cell a buried creature lives in.
static func soil_cell(w: int, h: int) -> ImageTexture:
	return _cached("cell_%d_%d" % [w, h], func() -> Image:
		var img := _blank(w * HI, h * HI)
		_ellipse(img, Vector2(w, h) * HI * 0.5, Vector2(w, h) * HI * 0.48, Color(0.12, 0.08, 0.05), Color(0.05, 0.03, 0.02),
				Color(0.2, 0.14, 0.1), 0.0, 0, 0.0, 0.55, 0.0)
		return img)


# ---------------------------------------------------------------------------
# The bird that hunts foragers on the surface
# ---------------------------------------------------------------------------

## A sparrow, facing right, about 30 x 20 screen px: "perched", "hop", "flap_up", "flap_down".
static func bird(pose: String) -> ImageTexture:
	return _cached("bird_" + pose, func() -> Image:
		var img := _blank(32 * HI, 22 * HI)
		var o := Vector2(0, 2) if pose in ["flap_up", "flap_down"] else Vector2.ZERO
		var brown := Color("#8a6440")
		var dark := Color("#4a3220")
		var light := Color("#c89a68")
		# legs (none while flying)
		if pose == "perched":
			for x: float in [13.0, 16.5]:
				_capsule(img, Vector2(x, 15.5) * HI, Vector2(x, 19.5) * HI, 0.4 * HI, Color("#c89a78"))
				_capsule(img, Vector2(x - 1.2, 19.6) * HI, Vector2(x + 1.4, 19.6) * HI, 0.3 * HI, Color("#b08060"))
		elif pose == "hop":
			_capsule(img, Vector2(13.0, 15.5) * HI, Vector2(11.5, 18.5) * HI, 0.4 * HI, Color("#c89a78"))
			_capsule(img, Vector2(16.5, 15.5) * HI, Vector2(18.5, 18.5) * HI, 0.4 * HI, Color("#c89a78"))
		# tail, body, cream breast
		_capsule(img, (Vector2(8.5, 11.5) + o) * HI, (Vector2(1.5, 8.0) + o) * HI, 1.6 * HI, dark.lerp(brown, 0.4))
		_ellipse(img, (Vector2(14, 11.5) + o) * HI, Vector2(7.5, 4.8) * HI, brown, dark, light, 0.4, 0, -0.18)
		_ellipse(img, (Vector2(17, 13.2) + o) * HI, Vector2(5.0, 3.2) * HI, Color("#e8dcc4"), Color("#b8a888"),
				Color("#fff8ea"), 0.3, 0, -0.2)
		# streaked back
		for i in 4:
			var at := (Vector2(9.5 + i * 2.2, 9.2 + (i % 2) * 0.8) + o) * HI
			_capsule(img, at, at + Vector2(1.6, 0.4) * HI, 0.35 * HI, dark, 0.8)
		# head: chestnut crown, grey cheek, eye, beak
		var head := (Vector2(22, 7.6) + o) * HI
		_ellipse(img, head, Vector2(3.9, 3.6) * HI, Color("#9a6a40"), Color("#5a3a20"), Color("#d09a68"), 0.4)
		_ellipse(img, head + Vector2(0.8, 1.3) * HI, Vector2(2.4, 1.6) * HI, Color("#b8b0a4"), Color("#8a8278"), Color("#e0d8cc"), 0.2)
		_ellipse(img, head + Vector2(1.6, -0.4) * HI, Vector2(0.75, 0.75) * HI, Color("#141010"), Color("#000000"), Color("#606060"), 1.0, 0, 0.0, 1.0, 0.0)
		_ellipse(img, head + Vector2(1.4, -0.7) * HI, Vector2(0.22, 0.22) * HI, Color.WHITE, Color.WHITE, Color.WHITE, 0.0)
		var beak := head + Vector2(3.4, 0.4) * HI
		_capsule(img, beak, beak + Vector2(2.4, 0.5) * HI, 0.75 * HI, Color("#d8a840"))
		_capsule(img, beak + Vector2(0, 0.5) * HI, beak + Vector2(2.0, 0.9) * HI, 0.45 * HI, Color("#b08028"))
		# wing: folded along the side, or raised / lowered in a wingbeat
		var wing_c := (Vector2(13.5, 10.8) + o) * HI
		var wing_ang := -0.15
		var wing_r := Vector2(5.6, 2.6) * HI
		if pose == "flap_up":
			wing_c = (Vector2(13, 4.5) + o) * HI
			wing_ang = -1.15
			wing_r = Vector2(6.5, 2.4) * HI
		elif pose == "flap_down":
			wing_c = (Vector2(14, 17) + o) * HI
			wing_ang = 1.0
			wing_r = Vector2(6.5, 2.4) * HI
		_ellipse(img, wing_c, wing_r, Color("#7a5634"), Color("#3e2a18"), Color("#b88a58"), 0.3, 4, wing_ang)
		var bar := wing_c + Vector2(1.0, -0.4).rotated(wing_ang) * HI
		_capsule(img, bar - Vector2(2.4, 0).rotated(wing_ang) * HI, bar + Vector2(2.4, 0).rotated(wing_ang) * HI,
				0.35 * HI, Color("#efe4cc"), 0.9)  # pale wing bar
		_outline(img, Color("#2a1c10"))
		return img)


## A neutral pebble (tinted per stone when drawn): rounded, lit from the upper left,
## speckled with mineral grains, with a soft outline.
static func stone(variant: int) -> ImageTexture:
	return _cached("stone%d" % variant, func() -> Image:
		var s := 24
		var img := _blank(s * HI, s * HI)
		var c := Vector2(s, s) * HI * 0.5
		var r := Vector2(s * 0.46, s * 0.46) * HI
		_ellipse(img, c, r, Color(0.86, 0.85, 0.83), Color(0.42, 0.41, 0.4), Color(1, 1, 1), 0.35, 0, variant * 0.7)
		for i in 14 + variant * 3:
			var p := c + Vector2(_hash(i, variant + 1.0) - 0.5, _hash(i + 40.0, variant + 2.0) - 0.5) * r * 1.4
			if p.distance_to(c) < r.x * 0.8:
				var shade := 0.55 + _hash(i, 99.0) * 0.5
				_ellipse(img, p, Vector2(0.5, 0.4) * HI * (1.0 + _hash(i, 5.0)), Color(shade, shade * 0.98, shade * 0.95),
						Color(shade * 0.7, shade * 0.7, shade * 0.7), Color.WHITE, 0.2, 0, 0.0, 0.7, 0.0)
		_outline(img, Color(0.25, 0.22, 0.2))
		return img)
