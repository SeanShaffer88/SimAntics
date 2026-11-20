extends RefCounted
## Procedural "32-bit" colony sprites: ants of any caste, the queen, brood stages,
## food and refuse. Ants are built from shaded ellipses (gaster, petiole, mesosoma,
## head) with elbowed antennae and a 4-frame tripod gait.

const SPRITE_SCALE := 1  # ants and brood are drawn 1:1 on screen (soil uses 2x2 pixels)
const ITEM_SCALE := 1
const DETAIL := 1.2  # art units per ant body unit; a size-1 worker is about 19 px long
const FRAMES := 4
const LIGHT := Vector3(-0.45, -0.7, 0.55)

static var _cache: Dictionary = {}


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
		var img := _draw_ant(species, size, head, queen, f)
		if wings:
			img = _add_wings(img, queen)
		frames.append(ImageTexture.create_from_image(img))
	_cache[key] = frames
	return frames


static func _draw_ant(species: Dictionary, size: float, head: float, queen: bool, frame: int) -> Image:
	var u := size * DETAIL * (1.25 if queen else 1.0)
	var gaster_len := 3.2 * u * (1.45 if queen else 1.0)
	var meso_len := 1.9 * u * (1.3 if queen else 1.0)
	var head_r := Vector2(1.55, 1.35) * u * head
	# lay parts out left (gaster) to right (head)
	var gaster := Vector2(gaster_len + 0.4, 3.9 * u)
	var petiole := Vector2(gaster.x + gaster_len + 0.5 * u, 4.1 * u)
	var meso := Vector2(petiole.x + 0.6 * u + meso_len, 3.7 * u)
	var head_c := Vector2(meso.x + meso_len + head_r.x * 0.85, 3.4 * u - (head - 1.0) * 0.6 * u)
	var width := ceili(head_c.x + head_r.x + 2.8 * u)
	var height := ceili(8.2 * u + maxf(0.0, (head - 1.0) * 0.8 * u))
	var ground := height - 1.0
	var img := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body: Color = species["body"]
	var gaster_col: Color = species["gaster"]
	var dark: Color = species["dark"]
	var light: Color = species["light"]
	var leg_col := dark.lerp(body, 0.35)

	# far legs (darker, opposite phase), then body, then near legs
	_draw_legs(img, meso, meso_len, u, ground, frame + 2, dark.lerp(body, 0.12), -0.6 * u)
	_shade_ellipse(img, gaster, Vector2(gaster_len, 2.3 * u * (1.2 if queen else 1.0)), gaster_col, dark, light)
	_shade_ellipse(img, petiole, Vector2(0.7, 0.9) * u, body, dark, light)
	_shade_ellipse(img, meso, Vector2(meso_len, 1.25 * u * (1.25 if queen else 1.0)), body, dark, light)
	_shade_ellipse(img, head_c, head_r, body, dark, light)
	if queen:  # wing scars where the wings were shed after mating
		_plot(img, Vector2(meso.x - 0.4 * u, meso.y - 1.1 * u), light.lerp(Color.WHITE, 0.3))
		_plot(img, Vector2(meso.x + 0.6 * u, meso.y - 1.2 * u), light.lerp(Color.WHITE, 0.3))
	_draw_legs(img, meso, meso_len, u, ground, frame, leg_col, 0.0)

	# eye, mandibles, elbowed antenna
	_plot(img, head_c + Vector2(head_r.x * 0.25, -head_r.y * 0.15), Color("#0a0604"))
	var jaw := head_c + Vector2(head_r.x * 0.95, head_r.y * 0.35)
	_line(img, jaw, jaw + Vector2(1.2 * u, 0.4 * u), dark)
	var scape_base := head_c + Vector2(head_r.x * 0.55, -head_r.y * 0.7)
	var elbow := scape_base + Vector2(0.5 * u, -1.6 * u)
	var bob := (0.4 if frame % 2 == 0 else -0.2) * u
	var tip := elbow + Vector2(2.0 * u, 1.2 * u + bob)
	_line(img, scape_base, elbow, leg_col)
	_line(img, elbow, tip, leg_col)

	_darken_silhouette_edge(img)
	return img


static func _draw_legs(img: Image, meso: Vector2, meso_len: float, u: float, ground: float,
		frame: int, color: Color, x_shift: float) -> void:
	const SWING := [-1.0, 0.0, 1.0, 0.0]
	for i in 3:  # hind, mid, fore
		var hip := Vector2(meso.x - meso_len * 0.6 + i * meso_len * 0.6 + x_shift, meso.y + 0.8 * u)
		var reach: float = [-2.4, 0.2, 2.3][i] * u
		var phase: int = (frame + (2 if i == 1 else 0)) % FRAMES
		var swing: float = SWING[phase]
		var foot := Vector2(hip.x + reach + swing * 0.9 * u, ground)
		var lift := 0.8 * u if phase == 1 else 0.0  # swinging leg is lifted
		foot.y -= lift
		var knee := Vector2(hip.x + (foot.x - hip.x) * 0.55, hip.y - 0.3 * u)
		_line(img, hip, knee, color)
		_line(img, knee, foot, color)


## Folded translucent wings lying back over the body, as on alates (virgin queens and males).
static func _add_wings(body: Image, queen: bool) -> Image:
	var w := body.get_width()
	var h := body.get_height()
	var top := 3
	var img := _blank(w, h + top)
	img.blit_rect(body, Rect2i(0, 0, w, h), Vector2i(0, top))
	var root := Vector2(w * 0.62, top + h * 0.3)  # where the wings join the thorax
	var tip := Vector2(w * (0.02 if queen else 0.08), top + h * 0.15)
	var membrane := Color(0.86, 0.9, 0.95, 0.55)
	var vein := Color(0.45, 0.4, 0.35, 0.8)
	for y in img.get_height():
		for x in w:
			# a long ellipse from the wing root back past the gaster
			var c := (root + tip) * 0.5
			var r := Vector2(root.distance_to(tip) * 0.5, 2.6 if queen else 2.1)
			var nx := (x + 0.5 - c.x) / r.x
			var ny := (y + 0.5 - c.y) / r.y
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(membrane))
	_line(img, root, tip, vein)
	return img


static func _shade_ellipse(img: Image, c: Vector2, r: Vector2, base: Color, dark: Color, light: Color) -> void:
	var lnorm := LIGHT.normalized()
	for y in range(floori(c.y - r.y), ceili(c.y + r.y) + 1):
		for x in range(floori(c.x - r.x), ceili(c.x + r.x) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var nx := (x + 0.5 - c.x) / r.x
			var ny := (y + 0.5 - c.y) / r.y
			var d2 := nx * nx + ny * ny
			if d2 > 1.0:
				continue
			var n := Vector3(nx, ny, sqrt(1.0 - d2))
			var lambert := clampf(n.dot(lnorm), 0.0, 1.0)
			var col: Color
			if lambert < 0.55:
				col = dark.lerp(base, lambert / 0.55)
			else:
				col = base.lerp(light, (lambert - 0.55) / 0.45)
			if lambert > 0.94:
				col = light.lerp(Color.WHITE, 0.55)  # glossy cuticle highlight
			img.set_pixel(x, y, col)


static func _darken_silhouette_edge(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var edges: Array[Vector2i] = []
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a == 0.0:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h or img.get_pixel(nx, ny).a == 0.0:
					edges.append(Vector2i(x, y))
					break
	for p in edges:
		img.set_pixel(p.x, p.y, img.get_pixel(p.x, p.y).darkened(0.3))


static func _plot(img: Image, p: Vector2, c: Color) -> void:
	var x := floori(p.x)
	var y := floori(p.y)
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps := maxi(1, ceili(maxf(absf(b.x - a.x), absf(b.y - a.y))))
	for s in steps + 1:
		_plot(img, a.lerp(b, float(s) / steps), c)


# ---------------------------------------------------------------------------
# Brood, food and refuse
# ---------------------------------------------------------------------------

static func egg() -> ImageTexture:
	return _cached("egg", func() -> Image:
		var img := _blank(5, 4)
		_shade_ellipse(img, Vector2(2.5, 2), Vector2(2.3, 1.7), Color("#efe8d8"), Color("#bdb2a0"), Color("#ffffff"))
		return img)


static func larva(stage: int) -> ImageTexture:
	return _cached("larva%d" % stage, func() -> Image:
		var length := 6.0 + stage * 3.0
		var img := _blank(ceili(length) + 2, ceili(length * 0.6) + 2)
		# C-shaped grub: a chain of shrinking segments curling under
		var segments := 4 + stage
		for s in segments:
			var t := float(s) / (segments - 1)
			var ang := lerpf(PI * 0.15, PI * 1.25, t)
			var center := Vector2(img.get_width() * 0.5, img.get_height() * 0.5) \
					+ Vector2(cos(ang), sin(ang)) * Vector2(length * 0.35, length * 0.2)
			var r := lerpf(1.6, 1.0, t) * (1.0 + stage * 0.15)
			_shade_ellipse(img, center, Vector2(r, r), Color("#ece2c8"), Color("#b8a888"), Color("#fffaf0"))
		_darken_silhouette_edge(img)
		return img)


static func pupa(cocoon: bool) -> ImageTexture:
	return _cached("pupa%s" % cocoon, func() -> Image:
		const S := 1.5  # pupae are about worker-sized
		var img := _blank(15, 8)
		if cocoon:
			_shade_ellipse(img, Vector2(5, 2.5) * S, Vector2(4.6, 2.3) * S, Color("#c8aa78"), Color("#8a7048"), Color("#eedcb0"))
			_plot(img, Vector2(1, 2) * S, Color("#5a4428"))  # meconium spot
		else:
			# naked pupa: pale ant shape with folded legs
			var pale := [Color("#f0e6d0"), Color("#bfb098"), Color("#ffffff")]
			_shade_ellipse(img, Vector2(3, 2.6) * S, Vector2(2.6, 1.9) * S, pale[0], pale[1], pale[2])
			_shade_ellipse(img, Vector2(6.3, 2.4) * S, Vector2(1.3, 1.1) * S, pale[0], pale[1], pale[2])
			_shade_ellipse(img, Vector2(8.2, 2.2) * S, Vector2(1.2, 1.2) * S, pale[0], pale[1], pale[2])
			_line(img, Vector2(5.5, 3.8) * S, Vector2(8.5, 4.0) * S, Color("#c8b89c"))
			_line(img, Vector2(5.0, 3.6) * S, Vector2(6.5, 4.4) * S, Color("#c8b89c"))
		_darken_silhouette_edge(img)
		return img)


static func seed_texture(variant: int) -> ImageTexture:
	return _cached("seed%d" % variant, func() -> Image:
		var tones := [Color("#a07040"), Color("#c09a5a"), Color("#7a5a36"), Color("#d0b070")]
		var img := _blank(5, 4)
		var base: Color = tones[variant % tones.size()]
		_shade_ellipse(img, Vector2(2.5, 2), Vector2(2.3, 1.6), base, base.darkened(0.45), base.lightened(0.35))
		return img)


static func prey_bit(variant: int) -> ImageTexture:
	return _cached("prey%d" % variant, func() -> Image:
		var img := _blank(9, 6)
		var tones := [Color("#3a2a1a"), Color("#5a4a20"), Color("#6a3020"), Color("#2a3a20"), Color("#4a3a30")]
		var base: Color = tones[variant % tones.size()]
		match variant % 3:
			0:  # beetle or cricket chunk with a leg
				_shade_ellipse(img, Vector2(3.5, 3), Vector2(3.0, 2.0), base, base.darkened(0.5), base.lightened(0.45))
				_line(img, Vector2(5, 4), Vector2(8, 5.5), base.darkened(0.3))
			1:  # translucent wing piece
				_shade_ellipse(img, Vector2(4.5, 3), Vector2(4.0, 1.6), Color("#c8c4b4"), Color("#8a8678"), Color("#f0eee6"))
				_line(img, Vector2(1, 3), Vector2(8, 3), Color("#7a7668"))
			2:  # larva or caterpillar segment
				for s in 3:
					_shade_ellipse(img, Vector2(2 + s * 2.2, 3), Vector2(1.5, 1.6), base.lightened(0.35), base, base.lightened(0.7))
		return img)


## A cut leaf fragment, as carried home by leafcutter foragers.
static func leaf_piece(variant: int) -> ImageTexture:
	return _cached("leaf%d" % variant, func() -> Image:
		var greens := [Color("#5a9a3a"), Color("#6aa848"), Color("#4a8a34"), Color("#8ab84a")]
		var base: Color = greens[variant % greens.size()]
		var img := _blank(8, 7)
		for y in 7:
			for x in 8:
				# a rough half-disc: the arc the ant cut with its mandibles
				var nx := (x + 0.5 - 4.0) / 4.0
				var ny := (y + 0.5 - 6.0) / 6.0
				if nx * nx + ny * ny <= 1.0 and not (variant % 2 == 0 and x == 7 and y < 3):
					img.set_pixel(x, y, base.lightened(0.15) if y < 3 else base)
		_line(img, Vector2(4, 6), Vector2(4, 1), base.darkened(0.3))  # midrib
		return img)


## A tuft of fungus that nurses pick from the garden to feed larvae.
static func fungus_crumb() -> ImageTexture:
	return _cached("fungus_crumb", func() -> Image:
		var img := _blank(4, 3)
		_shade_ellipse(img, Vector2(2, 1.5), Vector2(1.9, 1.4), Color("#e4e0d0"), Color("#a8a492"), Color("#ffffff"))
		return img)


## What is left after feeding: split seed husks, prey exoskeleton or spent fungus substrate.
static func waste_bit(food: String, variant: int) -> ImageTexture:
	return _cached("waste_%s%d" % [food, variant], func() -> Image:
		var img := _blank(5, 3)
		var base: Color
		match food:
			"seeds":
				base = [Color("#5a3a20"), Color("#6a4a2a")][variant % 2]
			"fungus":
				base = [Color("#6a5a44"), Color("#5a4c3a")][variant % 2]
			_:
				base = [Color("#2a2018"), Color("#3a2a1e")][variant % 2]
		_line(img, Vector2(0, 2), Vector2(2, 0), base)
		_line(img, Vector2(2, 0), Vector2(4, 2), base.lightened(0.2))
		_plot(img, Vector2(2, 1), base.darkened(0.3))
		return img)


## A spongy fungus garden filling the lower part of a chamber.
static func fungus_garden(width: int, height: int, rng_seed: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var img := _blank(width, height)
	var noise := FastNoiseLite.new()
	noise.seed = rng_seed
	noise.frequency = 0.22
	for y in height:
		for x in width:
			var nx := (x + 0.5 - width * 0.5) / (width * 0.5)
			var ny := (height - y - 0.5) / height
			if ny > (1.0 - nx * nx) * 0.95 + noise.get_noise_2d(x, 0) * 0.15:
				continue
			var n := noise.get_noise_2d(x, y)
			if n < -0.35:
				continue  # the garden is full of holes and galleries
			var c := Color("#d8d4c4").lerp(Color("#9c9886"), clampf(0.5 - n, 0.0, 1.0))
			if n > 0.45:
				c = Color("#eeeadc")  # fresh hyphae
			img.set_pixel(x, y, c)
	_darken_silhouette_edge(img)
	return ImageTexture.create_from_image(img)


## A heap of spent material, husks and exoskeleton pieces.
static func refuse_heap(width: int, height: int, rng_seed: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var img := _blank(width, height)
	var tones := [Color("#3a3026"), Color("#4e4232"), Color("#2a221c"), Color("#6a5a40"), Color("#5a2a1a")]
	for i in width * height / 3:
		var x := rng.randi_range(0, width - 1)
		var nx := (x + 0.5 - width * 0.5) / (width * 0.5)
		var top := height - (1.0 - nx * nx) * height
		var y := rng.randi_range(int(top), height - 1)
		img.set_pixel(x, y, tones[rng.randi() % tones.size()])
	return ImageTexture.create_from_image(img)


static func _blank(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _cached(key: String, build: Callable) -> ImageTexture:
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(build.call())
	return _cache[key]


# ---------------------------------------------------------------------------
# Player food: dock icons and the crumbs ants carry home
# ---------------------------------------------------------------------------

const FOOD_TYPES := ["sugar", "nectar", "fruit", "protein", "seeds"]


## A 16x16 icon for the food dock.
static func food_icon(kind: String) -> ImageTexture:
	return _cached("icon_" + kind, func() -> Image:
		var img := _blank(16, 16)
		match kind:
			"sugar":  # a sugar cube, lit from the top left
				for y in range(4, 13):
					for x in range(3, 12):
						var c := Color("#f4f6f8")
						if x == 3 or y == 4:
							c = Color("#ffffff")
						elif x == 11 or y == 12:
							c = Color("#b8c0c8")
						elif (x + y) % 5 == 0:
							c = Color("#dde4ea")
						img.set_pixel(x, y, c)
				for i in 3:  # top face
					_line(img, Vector2(4 + i, 3 - i), Vector2(12 + i, 3 - i), Color("#ffffff"))
					_line(img, Vector2(12 + i, 3 - i), Vector2(12 + i, 11 - i), Color("#c8d0d8"))
			"nectar":  # a glossy droplet
				for y in 16:
					for x in 16:
						var nx := (x + 0.5 - 8.0) / 5.0
						var ny := (y + 0.5 - 10.0) / 5.0
						var tip := y < 10 and absf(x + 0.5 - 8.0) < (y - 1.0) * 0.55
						if nx * nx + ny * ny <= 1.0 or tip:
							img.set_pixel(x, y, Color("#e8a020").lerp(Color("#ffd870"), clampf(1.0 - ny, 0.0, 1.0) * 0.6))
				img.set_pixel(6, 9, Color("#fff4d0"))
				img.set_pixel(6, 10, Color("#fff4d0"))
			"fruit":  # an orange slice
				for y in 16:
					for x in 16:
						var d := Vector2(x + 0.5 - 8.0, y + 0.5 - 13.0)
						if y <= 13 and d.length() <= 7.5:
							var c := Color("#f07828")
							if d.length() > 6.5:
								c = Color("#e85c18")
							elif d.length() > 5.6:
								c = Color("#fff0d8")
							elif int(atan2(d.y, d.x) * 4.0) % 2 == 0:
								c = Color("#f8a040")
							img.set_pixel(x, y, c)
			"protein":  # a dead ladybug
				_ladybug(img, Vector2(8, 9), 6.0)
			"seeds":
				for s: Vector3 in [Vector3(5, 10, 0), Vector3(10, 11, 1), Vector3(8, 6, 2), Vector3(12, 6, 3)]:
					var base: Color = [Color("#a07040"), Color("#c09a5a"), Color("#7a5a36"), Color("#d0b070")][int(s.z)]
					_shade_ellipse(img, Vector2(s.x, s.y), Vector2(2.6, 1.8), base, base.darkened(0.45), base.lightened(0.35))
		_darken_silhouette_edge(img)
		return img)


static func _ladybug(img: Image, c: Vector2, r: float) -> void:
	_shade_ellipse(img, c, Vector2(r, r * 0.8), Color("#d02818"), Color("#701008"), Color("#ff7058"))
	_shade_ellipse(img, c + Vector2(r * 0.95, r * 0.15), Vector2(r * 0.35, r * 0.35), Color("#201818"), Color("#000000"), Color("#606060"))
	_line(img, c + Vector2(0, -r * 0.8), c + Vector2(0, r * 0.8), Color("#401008"))
	for p: Vector2 in [Vector2(-0.45, -0.3), Vector2(0.4, -0.35), Vector2(-0.3, 0.35), Vector2(0.45, 0.3)]:
		_plot(img, c + p * r, Color("#100808"))
		_plot(img, c + p * r + Vector2(1, 0), Color("#100808"))
	for i in 3:  # legs curled underneath
		_plot(img, c + Vector2(-r * 0.4 + i * r * 0.4, r * 0.85), Color("#100808"))


## The crumb an ant carries home from a food drop.
static func food_crumb(kind: String, variant: int) -> ImageTexture:
	return _cached("crumb_%s%d" % [kind, variant], func() -> Image:
		var img := _blank(4, 4)
		match kind:
			"sugar":
				img.fill_rect(Rect2i(0, 1, 3, 3), Color("#f0f4f8"))
				img.set_pixel(0, 1, Color("#ffffff"))
				img.set_pixel(2, 3, Color("#b8c0c8"))
			"nectar":
				_shade_ellipse(img, Vector2(2, 2), Vector2(1.8, 1.8), Color(0.93, 0.66, 0.15, 0.9),
						Color(0.75, 0.45, 0.08, 0.9), Color(1.0, 0.9, 0.6, 0.95))
			"fruit":
				var tones := [Color("#f07828"), Color("#e04030"), Color("#f8a040")]
				img.fill_rect(Rect2i(0, 1, 4, 3), tones[variant % tones.size()])
				img.set_pixel(0, 1, Color("#fff0d8"))
			"protein":
				img.fill_rect(Rect2i(0, 1, 4, 3), Color("#c02818") if variant % 2 == 0 else Color("#201818"))
				img.set_pixel(1, 2, Color("#100808"))
			_:
				var base: Color = [Color("#a07040"), Color("#c09a5a"), Color("#7a5a36")][variant % 3]
				_shade_ellipse(img, Vector2(2, 2.5), Vector2(1.9, 1.3), base, base.darkened(0.45), base.lightened(0.35))
		return img)


## A pellet of excavated soil, carried up and dropped beside the entrance.
static func soil_pellet(soil: Color) -> ImageTexture:
	return _cached("pellet_" + soil.to_html(false), func() -> Image:
		var img := _blank(4, 4)
		_shade_ellipse(img, Vector2(2, 2), Vector2(1.9, 1.7), soil, soil.darkened(0.4), soil.lightened(0.3))
		return img)
