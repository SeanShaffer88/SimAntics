extends RefCounted
## High-detail procedural art for the UI and the food: anti-aliased shapes rendered with
## 4x4 supersampling, soft shading, specular highlights, a dark sticker outline and a
## drop shadow so icons read clearly on any background. Everything is cached.

const SS := 4  # supersamples per axis
const OUTLINE := Color("#1c1009")

static var _cache: Dictionary = {}


static func _cached(key: String, build: Callable) -> ImageTexture:
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(build.call())
	return _cache[key]


## Renders `shade(p) -> Color` (p in pixel units, transparent outside the shape) with
## supersampling. Colours are averaged premultiplied so edges blend cleanly.
static func render(w: int, h: int, shade: Callable) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var n := float(SS * SS)
	for y in h:
		for x in w:
			var r := 0.0
			var g := 0.0
			var b := 0.0
			var a := 0.0
			for sy in SS:
				for sx in SS:
					var c: Color = shade.call(Vector2(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS))
					r += c.r * c.a
					g += c.g * c.a
					b += c.b * c.a
					a += c.a
			if a > 0.0:
				img.set_pixel(x, y, Color(r / a, g / a, b / a, a / n))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img


## Adds a 1px dark outline around the opaque shape and a soft shadow below it.
static func finish(img: Image, outline := true, shadow := true) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	if shadow:
		for y in h:
			for x in w:
				var sx := x - 1
				var sy := y - 2
				if sx >= 0 and sy >= 0:
					var a := img.get_pixel(sx, sy).a
					if a > 0.0:
						out.set_pixel(x, y, Color(0, 0, 0, a * 0.35))
	if outline:
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
					out.set_pixel(x, y, _over(out.get_pixel(x, y), Color(OUTLINE, near * 0.9)))
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, _over(out.get_pixel(x, y), c))
	return out


static func _over(dst: Color, src: Color) -> Color:
	var a := src.a + dst.a * (1.0 - src.a)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var rgb := (Vector3(src.r, src.g, src.b) * src.a + Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)) / a
	return Color(rgb.x, rgb.y, rgb.z, a)


static func _hash(p: Vector2) -> float:
	return fposmod(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453, 1.0)


static func _in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---------------------------------------------------------------------------
# Food icons (40x40) for the food dock
# ---------------------------------------------------------------------------

static func food_icon(kind: String) -> ImageTexture:
	return _cached("icon_" + kind, func() -> Image:
		match kind:
			"sugar":
				return finish(render(40, 40, _sugar_cube.bind(Vector2(20, 21), 12.0)))
			"nectar":
				return finish(render(40, 40, _nectar_drop))
			"fruit":
				return finish(render(40, 40, _orange_slice))
			"protein":
				return finish(render(40, 40, _ladybug.bind(Vector2(20, 21), 13.0)))
		return finish(render(40, 40, _seed_pile)))


## An isometric sugar cube: three lit faces with a crystalline grain and sparkles.
static func _sugar_cube(p: Vector2, c: Vector2, s: float) -> Color:
	var top := c + Vector2(0, -s)
	var left := c + Vector2(-s * 0.95, -s * 0.45)
	var right := c + Vector2(s * 0.95, -s * 0.45)
	var mid := c + Vector2(0, s * 0.1)
	var bl := left + Vector2(0, s * 1.05)
	var br := right + Vector2(0, s * 1.05)
	var bot := mid + Vector2(0, s * 1.05)
	var grain := (_hash((p * 1.7).floor()) - 0.5) * 0.06
	if _in_poly(p, PackedVector2Array([top, right, mid, left])):
		var t := clampf((p.y - top.y) / (mid.y - top.y), 0.0, 1.0)
		var col := Color("#ffffff").lerp(Color("#eef3f8"), t)
		if _seg_dist(p, left, top) < 0.8 or _seg_dist(p, top, right) < 0.8:
			col = Color("#ffffff")
		return col.lightened(grain)
	if _in_poly(p, PackedVector2Array([left, mid, bot, bl])):
		var t := clampf((p.y - left.y) / (bl.y - left.y), 0.0, 1.0)
		var col := Color("#e2e9f0").lerp(Color("#cdd6df"), t)
		if _seg_dist(p, left, mid) < 0.7:
			col = Color("#f8fbff")
		return col.lightened(grain)
	if _in_poly(p, PackedVector2Array([mid, right, br, bot])):
		var t := clampf((p.y - right.y) / (br.y - right.y), 0.0, 1.0)
		var col := Color("#bcc6d2").lerp(Color("#a2adbb"), t)
		if _seg_dist(p, mid, right) < 0.7:
			col = Color("#dfe6ee")
		return col.lightened(grain)
	# sparkles
	for sp: Vector3 in [Vector3(c.x - s * 0.45, c.y - s * 0.55, 3.0), Vector3(c.x + s * 1.05, c.y - s * 1.0, 2.5)]:
		var d := p - Vector2(sp.x, sp.y)
		if (absf(d.x) < 0.5 and absf(d.y) < sp.z) or (absf(d.y) < 0.5 and absf(d.x) < sp.z):
			return Color(1, 1, 1, 0.95)
	return Color(0, 0, 0, 0)


## A glossy drop of nectar: amber glass with a bright rim, specular highlight and a
## warm glow where light passes through.
static func _nectar_drop(p: Vector2) -> Color:
	var c := Vector2(20, 25)
	var r := 11.5
	var d := p.distance_to(c)
	var tip := Vector2(20, 4)
	var inside := d <= r
	if not inside and p.y < c.y:
		var t := (p.y - tip.y) / (c.y - tip.y)  # 0 at the tip, 1 at the centre
		var half := r * sqrt(clampf(t, 0.0, 1.0)) * (0.55 + 0.45 * t)
		inside = t >= 0.0 and absf(p.x - c.x) <= half
	if not inside:
		return Color(0, 0, 0, 0)
	var n := (p - c) / r
	var col := Color("#c26a0a").lerp(Color("#f6b02a"), clampf(0.6 - n.y * 0.5, 0.0, 1.0))
	col = col.lerp(Color("#ffd86a"), clampf(1.0 - (p - Vector2(23, 29)).length() / 8.0, 0.0, 1.0) * 0.7)  # glow
	if d > r - 1.6 and p.y > c.y - 2.0:
		col = col.darkened(0.25)
	if (p - Vector2(15.5, 20.0)).length() < 2.6 or _seg_dist(p, Vector2(15, 14), Vector2(16, 18)) < 1.0:
		col = Color("#fffbe8")
	elif (p - Vector2(25.5, 31.0)).length() < 1.2:
		col = Color("#fff0c0")
	return Color(col, 0.97)


## An orange wedge: dimpled peel, white pith, juicy segments.
static func _orange_slice(p: Vector2) -> Color:
	var c := Vector2(20, 30)
	var d := p.distance_to(c)
	if p.y > c.y + 0.5 or d > 17.0:
		if p.y > c.y + 0.5 and p.y < c.y + 3.0 and absf(p.x - c.x) < 17.0 - (p.y - c.y):
			return Color("#d8541a").darkened(0.15)  # the cut base of the peel
		return Color(0, 0, 0, 0)
	if d > 15.2:
		var dimple := _hash((p * 1.3).floor()) * 0.12
		return Color("#ef7a1c").lerp(Color("#c24c10"), clampf((p.y - (c.y - 17.0)) / 17.0, 0.0, 1.0) * 0.5).darkened(dimple)
	if d > 13.6:
		return Color("#fff3dc")
	var ang := atan2(p.y - c.y, p.x - c.x)  # -PI (left) .. 0 (right) across the top
	var seg := fposmod(ang * 5.0 / PI, 1.0)
	if seg < 0.07 or seg > 0.93 or d < 2.2:
		return Color("#fff0d4")
	var juice := _hash((p * 0.9).floor())
	var col := Color("#f9a23a").lerp(Color("#f27c1e"), d / 13.6)
	if juice > 0.86:
		col = col.lightened(0.35)
	return col


## A ladybug seen from above: glossy red elytra with black spots, white-marked pronotum.
static func _ladybug(p: Vector2, c: Vector2, r: float) -> Color:
	var head := c + Vector2(r * 0.95, 0)
	# legs and antennae
	for i in 3:
		var base := c + Vector2(-r * 0.35 + i * r * 0.4, 0)
		for side: float in [-1.0, 1.0]:
			var foot := base + Vector2(-r * 0.15, side * r * 0.95)
			if _seg_dist(p, base + Vector2(0, side * r * 0.5), foot) < 0.7:
				return Color("#181010")
	for side: float in [-1.0, 1.0]:
		if _seg_dist(p, head + Vector2(r * 0.2, side * r * 0.12), head + Vector2(r * 0.55, side * r * 0.42)) < 0.55:
			return Color("#181010")
	var e := (p - c) / Vector2(r * 0.85, r * 0.78)
	if e.length() <= 1.0:
		if absf(p.y - c.y) < 0.6:
			return Color("#2a0806")  # the seam between the wing cases
		for s: Vector2 in [Vector2(-0.45, -0.42), Vector2(0.15, -0.5), Vector2(-0.4, 0.42), Vector2(0.18, 0.5), Vector2(-0.75, 0.0)]:
			if (e - s).length() < 0.2:
				return Color("#150a08")
		var col := Color("#e8301c").lerp(Color("#8e140a"), clampf((e.length() - 0.2) * 1.1 + e.y * 0.3, 0.0, 1.0))
		if (e - Vector2(-0.2, -0.45)).length() < 0.22:
			col = col.lerp(Color("#ffb4a4"), 0.85)  # gloss
		return col
	var hp := (p - head) / Vector2(r * 0.42, r * 0.5)
	if hp.length() <= 1.0:
		if (hp - Vector2(-0.1, 0.5)).length() < 0.3 or (hp - Vector2(-0.1, -0.5)).length() < 0.3:
			return Color("#f2ece0")
		return Color("#1c1414").lerp(Color("#4a4040"), clampf(-hp.y * 0.5, 0.0, 1.0))
	return Color(0, 0, 0, 0)


## A small pile of striped sunflower seeds.
static func _seed_pile(p: Vector2) -> Color:
	var seeds := [Vector4(12, 27, -0.5, 0), Vector4(26, 28, 0.6, 1), Vector4(19, 30, 0.1, 2),
			Vector4(15, 18, 0.9, 3), Vector4(25, 17, -0.8, 4)]
	var hit := Color(0, 0, 0, 0)
	for s: Vector4 in seeds:
		var col := _seed_shape(p, Vector2(s.x, s.y), s.z, 7.5, 4.2)
		if col.a > 0.0:
			hit = col  # later seeds lie on top
	return hit


static func _seed_shape(p: Vector2, c: Vector2, angle: float, length: float, width: float) -> Color:
	var q := (p - c).rotated(-angle)
	var t := q.x / length  # -1 (blunt end) .. 1 (pointed end)
	if absf(t) > 1.0:
		return Color(0, 0, 0, 0)
	var half := width * sqrt(1.0 - t * t) * (1.0 - 0.35 * maxf(t, 0.0))
	if absf(q.y) > half:
		return Color(0, 0, 0, 0)
	var v := q.y / maxf(half, 0.01)  # -1..1 across the seed
	var col := Color("#2e2a28").lerp(Color("#55504a"), clampf(-v * 0.6 + 0.4, 0.0, 1.0))
	if absf(v) < 0.12 or absf(absf(v) - 0.6) < 0.1:
		col = Color("#d9d0bc")  # pale stripes
	if v < -0.5 and t < 0.3:
		col = col.lightened(0.25)
	return col


# ---------------------------------------------------------------------------
# Food pieces for the piles on the surface (small, detailed)
# ---------------------------------------------------------------------------

static func food_piece(kind: String, variant: int) -> ImageTexture:
	return _cached("piece_%s%d" % [kind, variant], func() -> Image:
		var v := float(variant)
		match kind:
			"sugar":
				return finish(render(7, 7, _sugar_cube.bind(Vector2(3.5, 3.6), 2.6 + v * 0.2)), true, false)
			"nectar":
				return finish(render(7, 6, func(p: Vector2) -> Color:
					var e := (p - Vector2(3.5, 3.4)) / Vector2(3.1 - v * 0.3, 2.4)
					if e.length() > 1.0:
						return Color(0, 0, 0, 0)
					var col := Color("#d07a10").lerp(Color("#ffc848"), clampf(0.6 - e.y * 0.6, 0.0, 1.0))
					if (e - Vector2(-0.35, -0.4)).length() < 0.32:
						col = Color("#fff6d8")
					return Color(col, 0.95)), true, false)
			"fruit":
				return finish(render(7, 7, func(p: Vector2) -> Color:
					var poly := PackedVector2Array([Vector2(0.6, 2.0 + v * 0.3), Vector2(5.5, 0.8), Vector2(6.5, 5.6), Vector2(1.5, 6.4)])
					if not _in_poly(p, poly):
						return Color(0, 0, 0, 0)
					if p.y < 2.0 + v * 0.2:
						return Color("#e8641a")  # peel edge
					var col := Color("#f9a23a").lerp(Color("#ec7420"), p.y / 7.0)
					return col.lightened(0.3) if _hash(p.floor() + Vector2(v, v)) > 0.85 else col), true, false)
			"protein":
				return finish(render(10, 8, _ladybug.bind(Vector2(4.6, 4.0), 3.4)), true, false)
			"leaves":
				return finish(render(8, 7, func(p: Vector2) -> Color:
					var q := (p - Vector2(4, 3.5)).rotated(0.5 - v * 0.4)
					var e := q / Vector2(3.6, 2.2)
					if e.length() > 1.0 or (q.x > 1.0 and q.y > 0.6 and variant % 2 == 0):
						return Color(0, 0, 0, 0)  # a bite cut out of it
					if absf(q.y) < 0.35:
						return Color("#a8cc6a")  # midrib
					return Color("#4e8e32").lerp(Color("#76b048"), clampf(-e.y * 0.5 + 0.4, 0.0, 1.0))), true, false)
			"insects":
				return finish(render(9, 6, func(p: Vector2) -> Color:
					var c := Vector2(4.2, 3.0)
					if _seg_dist(p, Vector2(2.0, 1.0), Vector2(6.5, 5.2)) < 0.4 or _seg_dist(p, Vector2(2.0, 5.0), Vector2(6.5, 0.8)) < 0.4:
						return Color("#140c08")  # legs
					var e := (p - c) / Vector2(3.4, 2.2)
					if e.length() <= 1.0:
						var col := Color("#5a3e20").lerp(Color("#2a1a10"), clampf(e.length() + e.y * 0.3, 0.0, 1.0))
						if (e - Vector2(-0.3, -0.4)).length() < 0.25:
							col = Color("#a88a5a")
						return col
					if (p - (c + Vector2(3.6, 0))).length() < 1.3:
						return Color("#1a120c")
					return Color(0, 0, 0, 0)), true, false)
		return finish(render(8, 6, func(p: Vector2) -> Color:
			return _seed_shape(p, Vector2(4, 3), -0.3 + v * 0.45, 3.4, 1.9)), true, false))


## A bead of rainwater on the grass: clear, with a bright highlight and a dark rim.
static func water_bead(variant: int) -> ImageTexture:
	return _cached("bead%d" % variant, func() -> Image:
		var w := 6 + variant
		return render(w, 5, func(p: Vector2) -> Color:
			var e := (p - Vector2(w * 0.5, 3.0)) / Vector2(w * 0.5 - 0.3, 2.3)
			if e.length() > 1.0 or p.y > 4.6:
				return Color(0, 0, 0, 0)
			if (e - Vector2(-0.35, -0.45)).length() < 0.3:
				return Color(1, 1, 1, 0.95)
			if e.length() > 0.75:
				return Color(0.55, 0.7, 0.85, 0.75)
			return Color(0.78, 0.9, 1.0, 0.45).lerp(Color(0.92, 0.97, 1.0, 0.6), clampf(e.y, 0.0, 1.0))))


# ---------------------------------------------------------------------------
# Buttons and panels
# ---------------------------------------------------------------------------

## A 9-slice frame: rounded corners, bronze bevelled border and a dark wood fill.
## `state` is "normal", "hover", "pressed" or "panel".
static func frame_texture(state: String) -> ImageTexture:
	return _cached("frame_" + state, func() -> Image:
		var size := 32.0
		var radius := 8.0
		var fill_top := Color("#3b2718")
		var fill_bottom := Color("#24170d")
		var rim_top := Color("#e2b072")
		var rim_bottom := Color("#8a5a2e")
		var alpha := 0.94
		match state:
			"hover":
				fill_top = Color("#4a3220")
				fill_bottom = Color("#2e1d11")
				rim_top = Color("#f4c88a")
			"pressed":
				fill_top = Color("#1a100a")
				fill_bottom = Color("#2c1c10")
				rim_top = Color("#8a5a2e")
				rim_bottom = Color("#c08a50")
			"panel":
				alpha = 0.88
		return render(32, 32, func(p: Vector2) -> Color:
			var q := (p - Vector2(size, size) * 0.5).abs() - Vector2(size * 0.5 - radius - 1.0, size * 0.5 - radius - 1.0)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			if d > 0.0:
				return Color(0, 0, 0, 0)
			var t := p.y / size
			if d > -1.0:
				return Color(OUTLINE, alpha)
			if d > -3.0:
				return Color(rim_top.lerp(rim_bottom, t), alpha)
			if d > -4.0 and p.y < size * 0.5:
				return Color(fill_top.lightened(0.18), alpha)  # inner top highlight
			return Color(fill_top.lerp(fill_bottom, t), alpha)))


static func frame_style(state: String) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = frame_texture(state)
	box.set_texture_margin_all(10.0)
	box.set_content_margin_all(8.0)
	if state == "pressed":
		box.content_margin_top = 9.0
		box.content_margin_bottom = 7.0
	return box


const GLYPH := Color("#f3e2bf")
const GLYPH_SHADE := Color("#c9a774")


## The "i" glyph for the colony info button.
static func info_icon() -> ImageTexture:
	return _cached("info", func() -> Image:
		return finish(render(32, 32, func(p: Vector2) -> Color:
			var d := p.distance_to(Vector2(16, 16))
			if d > 13.0:
				return Color(0, 0, 0, 0)
			if d > 10.8:
				return GLYPH.lerp(GLYPH_SHADE, p.y / 32.0)
			if p.distance_to(Vector2(16, 9.5)) < 2.2:
				return GLYPH
			if _seg_dist(p, Vector2(16, 14.5), Vector2(16, 22.5)) < 2.0:
				return GLYPH.lerp(GLYPH_SHADE, (p.y - 13.0) / 12.0)
			return Color(0, 0, 0, 0)), true, true))


## Speaker glyph for the sound toggle, crossed out when muted.
static func speaker_icon(muted: bool) -> ImageTexture:
	return _cached("speaker_%s" % muted, func() -> Image:
		return finish(render(32, 32, func(p: Vector2) -> Color:
			var body := PackedVector2Array([Vector2(4, 12), Vector2(10, 12), Vector2(17, 6), Vector2(17, 26),
					Vector2(10, 20), Vector2(4, 20)])
			if _in_poly(p, body):
				return GLYPH.lerp(GLYPH_SHADE, p.y / 32.0)
			if muted:
				if _seg_dist(p, Vector2(21, 12), Vector2(29, 20)) < 1.6 or _seg_dist(p, Vector2(29, 12), Vector2(21, 20)) < 1.6:
					return Color("#e0664a")
				return Color(0, 0, 0, 0)
			var rel := p - Vector2(17, 16)
			var ang := absf(atan2(rel.y, rel.x))
			for r: float in [6.0, 11.0]:
				if ang < 0.85 and absf(rel.length() - r) < 1.3:
					return GLYPH
			return Color(0, 0, 0, 0)), true, true))


## A little landscape for the surface-scene picker: sky, sun, hill and a tree.
static func surface_icon() -> ImageTexture:
	return _cached("surface", func() -> Image:
		return finish(render(32, 32, func(p: Vector2) -> Color:
			var q := (p - Vector2(16, 16)).abs() - Vector2(8, 8)
			var box := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 6.0
			if box > 0.0:
				return Color(0, 0, 0, 0)
			if p.y > 24.0:
				return Color("#6a4428").lerp(Color("#4a2e1a"), (p.y - 24.0) / 6.0)  # soil
			var hill := 21.0 - 4.0 * sin((p.x - 2.0) / 28.0 * PI)
			if p.y > hill:
				return Color("#6aa848").lerp(Color("#4a8632"), (p.y - hill) / 6.0)
			if _seg_dist(p, Vector2(11, 20), Vector2(11, 13)) < 1.2:
				return Color("#6a4428")
			if p.distance_to(Vector2(11, 11)) < 4.5 or p.distance_to(Vector2(8.5, 13)) < 3.2 or p.distance_to(Vector2(13.5, 13)) < 3.2:
				return Color("#3e8a3a").lerp(Color("#62b04e"), clampf((14.0 - p.y) / 7.0, 0.0, 1.0))
			if p.distance_to(Vector2(23, 9)) < 3.2:
				return Color("#ffe27a")
			return Color("#8cc8ec").lerp(Color("#cfe9f6"), p.y / 22.0)), true, true))
