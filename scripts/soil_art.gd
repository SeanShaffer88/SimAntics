extends RefCounted
## "32-bit" underground art: fine 2x2 pixels, smooth strata blends, noise mottling,
## shaded pebbles and stones, and tunnels with soft ambient occlusion, packed light
## floors and dark interiors. Tunnel painting works on a sub-rectangle so digging
## can repaint just the area it changed.

const PIXEL_SCALE := 2
const AO_RADIUS := 6.0  # art pixels of wall shading around open space
const LIGHT_DIR := Vector2(-0.55, -0.83)  # light from upper left


static func make_soil_image(width: int, height: int, rng: RandomNumberGenerator, strata: Array) -> Image:
	var img := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var mottle := FastNoiseLite.new()
	mottle.seed = rng.randi()
	mottle.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mottle.frequency = 0.035
	mottle.fractal_octaves = 3
	var grain := FastNoiseLite.new()
	grain.seed = rng.randi()
	grain.noise_type = FastNoiseLite.TYPE_VALUE
	grain.frequency = 0.45
	var warp := FastNoiseLite.new()
	warp.seed = rng.randi()
	warp.frequency = 0.012

	var bounds := [0.13, 0.4, 0.72]
	for i in bounds.size():
		bounds[i] = bounds[i] * height + rng.randf_range(-6.0, 6.0)

	for y in height:
		var depth := float(y) / height
		for x in width:
			var wy := y + warp.get_noise_2d(x, y * 0.3) * 9.0
			var c: Color = strata[0]
			for i in bounds.size():
				# smooth 5px blend across each stratum boundary
				var t := smoothstep(bounds[i] - 2.5, bounds[i] + 2.5, wy)
				c = c.lerp(strata[i + 1], t)
			var m := mottle.get_noise_2d(x, y)
			c = c.lightened(m * 0.12) if m > 0.0 else c.darkened(-m * 0.18)
			var g := grain.get_noise_2d(x, y)
			if g > 0.55:
				c = c.lightened(0.08)
			elif g < -0.6:
				c = c.darkened(0.12)
			if rng.randf() < 0.012:
				c = c.lightened(0.18)
			# humus: dark, organic topsoil with fine root litter
			var humus := 9.0 + warp.get_noise_2d(x * 2.0, 50.0) * 4.0
			if wy < humus:
				c = c.darkened(0.42 * (1.0 - wy / humus) + 0.12)
				if rng.randf() < 0.04:
					c = c.lightened(0.25)
			c = c.darkened(depth * 0.22)
			img.set_pixel(x, y, c)

	_paint_pebbles(img, rng)
	_paint_bedrock(img, rng)
	return img


## Stony subsoil along the bottom: big, shaded rocks the colony digs around.
static func _paint_bedrock(img: Image, rng: RandomNumberGenerator) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var x := rng.randf_range(-4.0, 4.0)
	while x < w + 6.0:
		var r := rng.randf_range(4.0, 9.0)
		var cy := h - rng.randf_range(1.0, 7.0)
		_stone(img, Vector2(x, cy), r, rng.randf_range(0.55, 0.85),
				Color.from_hsv(rng.randf_range(0.06, 0.12), rng.randf_range(0.05, 0.18), rng.randf_range(0.42, 0.6)))
		x += r * rng.randf_range(1.2, 1.8)
	for i in 14:  # a few loose stones higher up
		_stone(img, Vector2(rng.randf_range(0.0, w), h - rng.randf_range(10.0, 26.0)), rng.randf_range(2.5, 5.0),
				rng.randf_range(0.6, 0.9),
				Color.from_hsv(rng.randf_range(0.06, 0.12), rng.randf_range(0.05, 0.18), rng.randf_range(0.45, 0.62)))


static func _stone(img: Image, c: Vector2, r: float, squash: float, tone: Color) -> void:
	for y in range(floori(c.y - r * squash), ceili(c.y + r * squash) + 1):
		for x in range(floori(c.x - r), ceili(c.x + r) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var n := Vector2((x + 0.5 - c.x) / r, (y + 0.5 - c.y) / (r * squash))
			var d := n.length()
			if d > 1.0:
				continue
			var lambert := clampf(-n.dot(LIGHT_DIR) * 0.6 + 0.55, 0.0, 1.0)
			var col := tone.darkened(0.4).lerp(tone.lightened(0.3), lambert)
			if d > 0.86:
				col = col.darkened(0.3)
			img.set_pixel(x, y, col)


static func _paint_pebbles(img: Image, rng: RandomNumberGenerator) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for i in 55:
		var cx := rng.randf_range(2.0, w - 2.0)
		var cy := rng.randf_range(10.0, h - 2.0)
		var r := rng.randf_range(0.8, 2.6) if rng.randf() < 0.9 else rng.randf_range(3.0, 5.0)
		var tone := Color.from_hsv(rng.randf_range(0.05, 0.1), rng.randf_range(0.2, 0.4), rng.randf_range(0.4, 0.62))
		var squash := rng.randf_range(0.6, 1.0)
		for y in range(floori(cy - r), ceili(cy + r) + 1):
			for x in range(floori(cx - r), ceili(cx + r) + 1):
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				var n := Vector2((x + 0.5 - cx) / r, (y + 0.5 - cy) / (r * squash))
				var d := n.length()
				if d > 1.0:
					continue
				var lambert := clampf(-n.dot(LIGHT_DIR) * 0.6 + 0.55, 0.0, 1.0)
				var c := tone.darkened(0.35).lerp(tone.lightened(0.25), lambert)
				if d > 0.82:
					c = c.darkened(0.25)
				img.set_pixel(x, y, c)


## Distance (art pixels, capped) from each pixel to the nearest open-air pixel,
## computed with a two-pass chamfer over `rect` (pass the whole image the first time).
static func update_distance(dist: PackedFloat32Array, mask: PackedByteArray, w: int, h: int, rect: Rect2i) -> void:
	var x0 := maxi(rect.position.x, 0)
	var y0 := maxi(rect.position.y, 0)
	var x1 := mini(rect.end.x, w)
	var y1 := mini(rect.end.y, h)
	const DIAG := 1.4142
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := y * w + x
			if mask[i] == 1:
				dist[i] = 0.0
				continue
			var d := AO_RADIUS + 1.0
			if x > x0:
				d = minf(d, dist[i - 1] + 1.0)
			if y > y0:
				d = minf(d, dist[i - w] + 1.0)
				if x > x0:
					d = minf(d, dist[i - w - 1] + DIAG)
				if x < x1 - 1:
					d = minf(d, dist[i - w + 1] + DIAG)
			dist[i] = d
	for y in range(y1 - 1, y0 - 1, -1):
		for x in range(x1 - 1, x0 - 1, -1):
			var i := y * w + x
			var d := dist[i]
			if x < x1 - 1:
				d = minf(d, dist[i + 1] + 1.0)
			if y < y1 - 1:
				d = minf(d, dist[i + w] + 1.0)
				if x < x1 - 1:
					d = minf(d, dist[i + w + 1] + DIAG)
				if x > x0:
					d = minf(d, dist[i + w - 1] + DIAG)
			dist[i] = d


## Repaints `rect` of `img` from the untouched soil `base`, the open-air `mask`
## and the distance field.
static func paint_tunnels(img: Image, base: Image, mask: PackedByteArray, dist: PackedFloat32Array,
		rect: Rect2i, air: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := maxi(rect.position.x, 0)
	var y0 := maxi(rect.position.y, 0)
	var x1 := mini(rect.end.x, w)
	var y1 := mini(rect.end.y, h)
	var air_floor := air.lightened(0.16)
	var air_ceiling := air.darkened(0.35)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := y * w + x
			if mask[i] == 1:
				# open space: darker under the ceiling, faintly lit just above the floor
				var below := 0
				while below < 6 and y + below + 1 < h and mask[i + (below + 1) * w] == 1:
					below += 1
				var above := 0
				while above < 6 and y - above - 1 >= 0 and mask[i - (above + 1) * w] == 1:
					above += 1
				# Through the glass of an ant farm you see the soil at the back of each
				# space, in shadow: darkest under the roof, lighter toward the floor.
				var back := base.get_pixel(x, y).darkened(0.5).lerp(air, 0.25)
				var c := back
				if below < 2:
					c = back.lightened(0.12)
				elif above < 2:
					c = back.darkened(0.45)
				elif above < 4:
					c = back.darkened(0.25)
				img.set_pixel(x, y, c)
				continue
			var soil := base.get_pixel(x, y)
			var d := dist[i]
			if d <= AO_RADIUS:
				soil = soil.darkened(0.42 * pow(1.0 - d / (AO_RADIUS + 1.0), 1.6))
			# (the packed lining along walls and floors is drawn by shaders/soil.gdshader,
			# along the smooth wall rather than the art grid)
			img.set_pixel(x, y, soil)
