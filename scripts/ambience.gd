extends AudioStreamPlayer
## Soft generated ambience, no audio files: a slow, breathy wind by day and a
## chorus of crickets after dark. Mixed quietly so it sits in the background.

const MIX_RATE := 22050.0
const CRICKET_HZ := 4300.0

var night_level := 0.0  # 0 by day, 1 at full night (set from the day/night cycle)
var rain_level := 0.0  # 0 dry, 1 full shower (set from the weather)
var _rain := 0.0
var muted := false:
	set(value):
		muted = value
		volume_db = -80.0 if value else -14.0

var _playback: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _wind := 0.0  # low-passed noise
var _wind_slow := 0.0
var _gust_phase := 0.0
var _crickets: Array[Dictionary] = []


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.25
	stream = gen
	volume_db = -80.0 if muted else -14.0
	_rng.randomize()
	for i in 3:  # a few crickets, each with its own pitch and rhythm
		_crickets.append({"hz": CRICKET_HZ * _rng.randf_range(0.9, 1.12), "rate": _rng.randf_range(0.7, 1.4),
				"phase": _rng.randf(), "pan": _rng.randf_range(-0.6, 0.6)})
	play()
	_playback = get_stream_playback()


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	var dt := 1.0 / MIX_RATE
	for f in frames:
		_t += dt
		# wind: brown-ish noise, swelling in slow gusts, quieter at night
		_wind += (_rng.randf_range(-1.0, 1.0) - _wind) * 0.02
		_wind_slow += (_wind - _wind_slow) * 0.05
		var gust := 0.55 + 0.45 * sin(_t * 0.23 + sin(_t * 0.07) * 2.0)
		var wind := _wind_slow * gust * (1.0 - night_level * 0.6) * 0.9
		var left := wind
		var right := wind
		if rain_level > 0.01:
			# rain: soft hiss with the odd heavier drop
			_rain += (_rng.randf_range(-1.0, 1.0) - _rain) * 0.35
			var hiss := _rain * 0.16 * rain_level
			if _rng.randf() < 0.0004 * rain_level:
				hiss += _rng.randf_range(0.15, 0.3) * rain_level
			left += hiss
			right += hiss * _rng.randf_range(0.8, 1.0)
		if night_level > 0.01:
			for c in _crickets:
				# chirps: trains of three quick pulses, repeating
				var cycle := fmod(_t * float(c["rate"]) + float(c["phase"]), 1.0)
				var pulse := 0.0
				if cycle < 0.18:
					var within := fmod(cycle, 0.06) / 0.06
					pulse = sin(within * PI)
				var tone := sin(_t * TAU * float(c["hz"])) * pulse * 0.05 * night_level * (1.0 - rain_level)
				left += tone * (1.0 - float(c["pan"]))
				right += tone * (1.0 + float(c["pan"]))
		_playback.push_frame(Vector2(left, right))
