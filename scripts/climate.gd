extends RefCounted
## Temperature, which governs nearly everything an ant does: they are cold-blooded, so
## they walk faster when warm and grind to a halt in the cold; each species forages only
## within its own temperature window; and nurses keep the brood where it is warmest.
##
## Air temperature follows the season's mean with a daily swing (coolest before dawn,
## warmest mid-afternoon). Bare ground in sunshine runs hotter than the air, rain cools
## it. Below ground the daily swing fades quickly with depth, so the deep nest stays
## close to the season's average while the upper chambers warm by day and cool at night.

const MEAN := [15.0, 25.0, 13.0, 1.0]  # daily mean air temperature by season (spring..winter), deg C
const SWING := [7.0, 9.0, 6.0, 4.0]  # half the day-night range
const SOIL_DAMPING := 3.2  # how fast the daily swing fades with depth (per nest depth)

var air := 18.0
var surface := 20.0  # ground surface, where foragers walk
var deep := 16.0  # soil at the bottom of the nest

var _ready := false


## `season_t` is how far through the season (0..1); `time_of_day` 0 = midnight.
func update(season: int, season_t: float, time_of_day: float, daylight: float, rain: float,
		snow_cover: float, delta: float) -> void:
	# seasons blend into each other over the last fifth of each season
	var next := (season + 1) % 4
	var blend := smoothstep(0.8, 1.0, season_t)
	var mean := lerpf(MEAN[season], MEAN[next], blend)
	var swing := lerpf(SWING[season], SWING[next], blend)
	air = mean + swing * sin((time_of_day - 0.375) * TAU) - rain * 3.0
	var sun := daylight * swing * 0.7 * (1.0 - rain)  # sunlit ground heats above the air
	var target := air + sun
	if snow_cover > 0.0:
		target = minf(target, 0.5)  # snow holds the ground near freezing
	if not _ready:
		_ready = true
		surface = target
		deep = mean - 1.0
		return
	surface = lerpf(surface, target, minf(1.0, delta / 40.0))
	deep = lerpf(deep, mean - 1.0, minf(1.0, delta / 1500.0))  # deep soil lags the seasons


## Soil temperature at a depth fraction (0 = surface, 1 = bottom of the nest).
func at_depth(depth: float) -> float:
	return deep + (surface - deep) * exp(-clampf(depth, 0.0, 1.0) * SOIL_DAMPING)


## How briskly an ant moves at a temperature: barely at all near freezing, full speed
## in the warm, a little slower again when it is fiercely hot.
static func activity(temp: float) -> float:
	if temp >= 40.0:
		return lerpf(1.0, 0.7, clampf((temp - 40.0) / 12.0, 0.0, 1.0))
	return clampf((temp - 3.0) / 25.0, 0.12, 1.0)
