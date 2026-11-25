## Procedural cached 16-bit PCM sound effects for UI, alarms, scanning, and abilities.
class_name SfxGen
extends RefCounted

const MIX_RATE := 22050

static var _cache := {}


static func build_all() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	_cache["ui_click"] = _tone_sweep(0.045, 880.0, 440.0, 0.28, "sine")
	_cache["ui_hover"] = _tone_sweep(0.025, 1320.0, 1180.0, 0.14, "sine")
	_cache["ui_back"] = _tone_sweep(0.07, 520.0, 300.0, 0.22, "sine")
	_cache["ui_buy"] = _two_note(0.14, 587.33, 880.0, 0.32)
	_cache["ui_error"] = _tone_sweep(0.14, 160.0, 110.0, 0.30, "saw")
	_cache["alarm_warn"] = _pulsed_tone(0.18, 960.0, 2.0, 0.28)
	_cache["scan_hum"] = _harmonic_pulse(0.20, 440.0, 660.0, 0.22)
	_cache["ability_cast"] = _tone_sweep(0.18, 320.0, 960.0, 0.30, "sine")
	_cache["ko_chime"] = _chord_seq(0.18, [[1318.5, 1976.0]], 0.30, true)
	_cache["streak_chord_2"] = _chord_seq(0.35, [[392.0, 493.9, 587.3]], 0.30, false)
	_cache["streak_chord_3"] = _chord_seq(0.35, [[523.3, 659.3, 784.0]], 0.30, false)
	_cache["streak_chord_4"] = _chord_seq(0.35, [[659.3, 830.6, 987.8, 1318.5]], 0.30, false)
	_cache["flag_fanfare"] = _chord_seq(0.42, [[523.3], [659.3], [784.0, 1046.5]], 0.30, false)
	_cache["splash"] = _noise_burst(0.14, 0.22, 0.28)
	_cache["ambient_earth"] = _ambient_loop(2.6, 174.6, 261.6, 0.055, 0.045)
	_cache["ambient_flight"] = _ambient_loop(2.4, 65.4, 98.0, 0.065, 0.030)
	_cache["ambient_moon"] = _ambient_loop(2.6, 55.0, 110.0, 0.032, 0.020)
	_cache["sfx_walk"] = _footstep(0.10, 120.0, 0.35, 40.0, 0.45, 0.55)
	_cache["sfx_run"] = _footstep(0.14, 80.0, 0.22, 26.0, 0.80, 0.80)
	_cache["sfx_shoot"] = _blaster(0.26)
	return _cache


## Cached hit-confirm ding (two-tone metallic).
static func ko_chime() -> AudioStreamWAV:
	return build_all()["ko_chime"]


## Cached rising triad; streak 2 = Double, 3 = Triple, 4+ = Unstoppable.
static func streak_chord(streak: int) -> AudioStreamWAV:
	return build_all()["streak_chord_%d" % clampi(streak, 2, 4)]


## Cached bright 3-note rising arpeggio for flag capture / ramp extraction.
static func flag_fanfare() -> AudioStreamWAV:
	return build_all()["flag_fanfare"]


## Sequence of steps; each step is a list of simultaneous frequencies. metallic adds inharmonic partial.
static func _chord_seq(dur: float, steps: Array, amp: float, metallic: bool) -> AudioStreamWAV:
	var count := maxi(1, int(dur * MIX_RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var n := steps.size()
	var chord_mode := n == 1 and not metallic
	var seg := float(count) / float(n)
	for i in count:
		var idx := mini(n - 1, int(float(i) / seg))
		var lt := (float(i) - seg * idx) / seg
		var t := float(i) / float(count)
		var env := minf(1.0, lt * 40.0) * pow(maxf(0.0, 1.0 - (t if chord_mode else lt) * (0.9 if chord_mode else 0.6)), 1.5)
		var time := float(i) / float(MIX_RATE)
		var v := 0.0
		var freqs: Array = steps[idx]
		for f in freqs:
			v += sin(time * TAU * f) + 0.3 * sin(time * TAU * f * (2.76 if metallic else 2.0))
		v = v / float(freqs.size()) * (0.5 if chord_mode else 0.8)
		var s := clampf(v * amp * env, -1.0, 1.0)
		data.encode_s16(i * 2, roundi(s * 32767.0))
	return _make_wav(data)


static func _make_wav(samples: PackedByteArray, loop := false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = samples
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size() / 2
	return wav


## Soft filtered noise burst (e.g. pond splash).
static func _noise_burst(dur: float, amp: float, smooth := 0.25) -> AudioStreamWAV:
	var count := maxi(1, int(dur * MIX_RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9041
	var lp := 0.0
	for i in count:
		var t := float(i) / float(count)
		var env := minf(1.0, t * 22.0) * pow(maxf(0.0, 1.0 - t), 1.6)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), smooth)
		var s := clampf(lp * amp * env, -1.0, 1.0)
		data.encode_s16(i * 2, roundi(s * 32767.0))
	return _make_wav(data)


## Seamless looping ambient soundscape (gentle filtered breeze + soft harmonic bed).
static func _ambient_loop(dur: float, f_low: float, f_high: float, bed_amp: float, air_amp: float) -> AudioStreamWAV:
	var count := maxi(1, int(dur * MIX_RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f_low * 100.0)
	var lp := 0.0
	for i in count:
		var t := float(i) / float(count)
		var time := float(i) / float(MIX_RATE)
		# Seamless periodic modulation so loop boundary is click-free.
		var swell := 0.65 + 0.35 * sin(t * TAU)
		var bed := (sin(time * TAU * f_low) * 0.65 + sin(time * TAU * f_high) * 0.35) * bed_amp * swell
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.035)
		var air := lp * air_amp * (0.75 + 0.25 * cos(t * TAU * 2.0))
		var fade := minf(1.0, minf(t, 1.0 - t) * 18.0)
		var s := clampf((bed + air) * fade, -1.0, 1.0)
		data.encode_s16(i * 2, roundi(s * 32767.0))
	return _make_wav(data, true)


static func _osc(phase: float, kind: String) -> float:
	if kind == "saw":
		return 2.0 * fmod(phase, 1.0) - 1.0
	return sin(phase * TAU)


static func _tone_sweep(dur: float, f0: float, f1: float, amp: float, kind: String) -> AudioStreamWAV:
	var count := maxi(1, int(dur * MIX_RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		var env := minf(1.0, t * 14.0) * pow(maxf(0.0, 1.0 - t), 1.4)
		var freq := lerpf(f0, f1, t)
		phase += freq / float(MIX_RATE)
		var s := clampf(_osc(phase, kind) * amp * env, -1.0, 1.0)
		data.encode_s16(i * 2, roundi(s * 32767.0))
	return _make_wav(data)


static func _two_note(dur: float, f0: float, f1: float, amp: float) -> AudioStreamWAV:
	var count := maxi(1, int(dur * MIX_RATE))
	var split := count / 2
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var local_t := float(i if i < split else i - split) / float(maxi(1, split))
		var env := minf(1.0, local_t * 16.0) * pow(maxf(0.0, 1.0 - local_t), 1.2)
		var freq := f0 if i < split else f1
		phase += freq / float(MIX_RATE)
		var s := clampf((sin(phase * TAU) + 0.25 * sin(phase * TAU * 2.0)) * amp * env, -1.0, 1.0)
		data.encode_s16(i * 2, roundi(s * 32767.0))
	return _make_wav(data)


static func _pulsed_tone(dur: float, freq: float, pulses: float, amp: float) -> AudioStreamWAV:
	var count := maxi(1, int(dur * MIX_RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		var gate := 1.0 if fmod(t * pulses, 1.0) < 0.65 else 0.15
		var env := minf(1.0, t * 20.0) * (1.0 - t * 0.3) * gate
		phase += freq / float(MIX_RATE)
		var s := clampf(sin(phase * TAU) * amp * env, -1.0, 1.0)
		data.encode_s16(i * 2, roundi(s * 32767.0))
	return _make_wav(data)


static func _harmonic_pulse(dur: float, f0: float, f1: float, amp: float) -> AudioStreamWAV:
	var count := maxi(1, int(dur * MIX_RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var p0 := 0.0
	var p1 := 0.0
	for i in count:
		var t := float(i) / float(count)
		var env := sin(t * PI)
		p0 += f0 / float(MIX_RATE)
		p1 += f1 / float(MIX_RATE)
		var s := clampf((0.65 * sin(p0 * TAU) + 0.35 * sin(p1 * TAU)) * amp * env, -1.0, 1.0)
		data.encode_s16(i * 2, roundi(s * 32767.0))
	return _make_wav(data)


static var _long_cache := {}

## Lazily built long loops by key: music_earth, music_flight, music_moon, music_debrief,
## earth_wind, space_engine, moon_hum. (menu music / station hum have their own accessors.)
static func long_stream(key: String) -> AudioStreamWAV:
	if _long_cache.has(key):
		return _long_cache[key]
	var wav: AudioStreamWAV
	match key:
		"music_earth": wav = _earth_music_loop(8.0)
		"music_flight": wav = _flight_music_loop(8.0)
		"music_moon": wav = _moon_music_loop(8.0)
		"music_debrief": wav = _debrief_music_loop(12.0)
		"earth_wind": wav = _wind_loop(4.0)
		"space_engine": wav = _engine_loop(2.0)
		"moon_hum": wav = _ambient_loop(2.6, 55.0, 110.0, 0.032, 0.020)
		_: return null
	_long_cache[key] = wav
	return wav


## Short bird chirp variants (0..2) for the earth ambience timer.
static func bird_chirp(variant: int) -> AudioStreamWAV:
	var key := "bird_%d" % (variant % 3)
	if not _long_cache.has(key):
		_long_cache[key] = _bird_chirp(variant % 3)
	return _long_cache[key]


static func _write(data: PackedByteArray, i: int, s: float) -> void:
	data.encode_s16(i * 2, roundi(clampf(s, -1.0, 1.0) * 32767.0))


## Soft footstep: filtered noise scuff + low thump.
static func _footstep(dur: float, thump_hz: float, smooth: float, decay: float, noise_amp: float, thump_amp: float) -> AudioStreamWAV:
	var count := maxi(1, int(dur * MIX_RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(thump_hz) + 31
	var lp := 0.0
	for i in count:
		var time := float(i) / float(MIX_RATE)
		var atk := minf(1.0, time * 600.0)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), smooth)
		var scuff := lp * exp(-time * decay) * noise_amp
		var thump := sin(time * TAU * thump_hz * (1.0 - 0.3 * time / dur)) * exp(-time * decay * 1.3) * thump_amp
		_write(data, i, (scuff + thump) * atk * 0.7)
	return _make_wav(data)


## Punchy sci-fi blaster: fast downward saw/square sweep + noise crack.
static func _blaster(dur: float) -> AudioStreamWAV:
	var count := maxi(1, int(dur * MIX_RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var phase := 0.0
	for i in count:
		var time := float(i) / float(MIX_RATE)
		var freq := 140.0 + 1060.0 * exp(-time * 18.0)
		phase += freq / float(MIX_RATE)
		var body := (_osc(phase, "saw") * 0.6 + (1.0 if fmod(phase, 1.0) < 0.5 else -1.0) * 0.25) * exp(-time * 10.0)
		var crack := rng.randf_range(-1.0, 1.0) * exp(-time * 32.0) * 0.5
		var atk := minf(1.0, time * 1500.0)
		_write(data, i, (body + crack) * atk * 0.55)
	return _make_wav(data)


## One short bird call: 2-3 quick rising/falling sine chirps.
static func _bird_chirp(variant: int) -> AudioStreamWAV:
	var dur := 0.38
	var count := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var bases := [2600.0, 3200.0, 2100.0]
	var counts := [3, 2, 3]
	var base: float = bases[variant]
	var n: int = counts[variant]
	var phase := 0.0
	for i in count:
		var time := float(i) / float(MIX_RATE)
		var slot := 0.12
		var ci := int(time / slot)
		var s := 0.0
		if ci < n:
			var lt := (time - ci * slot) / 0.07
			if lt < 1.0:
				var rising := (ci + variant) % 2 == 0
				var freq := base * (1.0 + (0.35 if rising else -0.25) * lt + 0.05 * ci)
				phase += freq / float(MIX_RATE)
				s = (sin(phase * TAU) + 0.2 * sin(phase * TAU * 2.0)) * sin(lt * PI) * 0.22
		_write(data, i, s)
	return _make_wav(data)


## Gentle outdoor wind: two-stage low-passed noise with slow gust swells (4 s loop).
static func _wind_loop(dur: float) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var lp1 := 0.0
	var lp2 := 0.0
	var whistle := _snap(330.0, dur)
	for i in count:
		var t := float(i) / float(count)
		var time := float(i) / float(MIX_RATE)
		lp1 = lerpf(lp1, rng.randf_range(-1.0, 1.0), 0.06)
		lp2 = lerpf(lp2, lp1, 0.25)
		var gust := 0.55 + 0.30 * sin(t * TAU) + 0.15 * sin(t * TAU * 3.0 + 1.3)
		var wh := sin(time * TAU * whistle) * 0.006 * maxf(0.0, sin(t * TAU * 2.0))
		var edge := minf(1.0, minf(t, 1.0 - t) * dur / 0.02)
		_write(data, i, (lp2 * 0.55 * gust + wh) * edge)
	return _make_wav(data, true)


## Deep ion/rocket engine rumble with a faint whine (2 s seamless loop).
static func _engine_loop(dur: float) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var lp := 0.0
	var f1 := _snap(46.0, dur)
	var f2 := _snap(69.0, dur)
	var f3 := _snap(138.0, dur)
	var whine := _snap(520.0, dur)
	for i in count:
		var t := float(i) / float(count)
		var time := float(i) / float(MIX_RATE)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.09)
		var flutter := 0.85 + 0.15 * sin(t * TAU * 4.0)
		var body := (sin(time * TAU * f1) * 0.35 + sin(time * TAU * f2) * 0.22 + sin(time * TAU * f3) * 0.10) * flutter
		var hiss := lp * 0.22
		var ion := sin(time * TAU * whine) * 0.02
		var edge := minf(1.0, minf(t, 1.0 - t) * dur / 0.015)
		_write(data, i, (body + hiss + ion) * edge * 0.8)
	return _make_wav(data, true)


## Bright atmospheric pad: C - G - Am - F with sparkling bell arp (8 s).
static func _earth_music_loop(dur: float) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var chords := [
		[130.81, 261.63, 329.63, 392.0, 587.33],
		[98.0, 196.0, 293.66, 392.0, 493.88],
		[110.0, 220.0, 261.63, 329.63, 523.25],
		[87.31, 174.61, 261.63, 349.23, 440.0],
	]
	var arps := [[523.25, 659.25, 783.99], [587.33, 783.99, 987.77], [659.25, 783.99, 1046.5], [523.25, 698.46, 880.0]]
	for c in chords.size():
		for k in chords[c].size():
			chords[c][k] = _snap(chords[c][k], dur)
	var seg_len := count / 4
	var step_len := count / 32
	for i in count:
		var t := float(i) / float(count)
		var time := float(i) / float(MIX_RATE)
		var ci := mini(3, i / seg_len)
		var lt := float(i - ci * seg_len) / float(seg_len)
		var xenv := minf(1.0, minf(lt, 1.0 - lt) * 4.0)
		var pad := 0.0
		for f in chords[ci]:
			pad += sin(time * TAU * f) + 0.3 * sin(time * TAU * f * 2.0 + 0.5)
		pad = pad / float(chords[ci].size()) * 0.16 * xenv * (0.85 + 0.15 * sin(t * TAU * 4.0))
		var si := mini(31, i / step_len)
		var sl := float(i - si * step_len) / float(step_len)
		var af: float = arps[ci][si % 3]
		var bell := (sin(time * TAU * af) + 0.25 * sin(time * TAU * af * 2.76)) * minf(1.0, sl * 40.0) * pow(maxf(0.0, 1.0 - sl), 2.2) * 0.05
		var edge := minf(1.0, minf(t, 1.0 - t) * dur / 0.02)
		_write(data, i, (pad + bell) * edge)
	return _make_wav(data, true)


## Driving synthwave pulse at 120 BPM: kick, offbeat hats, saw bass, pentatonic arp (8 s = 4 bars).
static func _flight_music_loop(dur: float) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 120
	var roots := [55.0, 55.0, 43.65, 49.0]
	var arp := [440.0, 523.25, 659.25, 523.25, 783.99, 659.25, 523.25, 659.25]
	var beat_len := count / 16
	var step_len := count / 32
	var bar_len := count / 4
	var lp := 0.0
	for i in count:
		var t := float(i) / float(count)
		var time := float(i) / float(MIX_RATE)
		var si := mini(31, i / step_len)
		var sl := float(i - si * step_len) / float(step_len)
		var bar := mini(3, i / bar_len)
		var bf: float = roots[bar]
		var benv := minf(1.0, sl * 50.0) * (1.0 - sl * 0.6) * (1.0 if sl < 0.9 else (1.0 - sl) * 10.0)
		var bph := time * bf
		var bass := (sin(bph * TAU) * 0.7 + (2.0 * fmod(bph, 1.0) - 1.0) * 0.3) * benv
		var bi := mini(15, i / beat_len)
		var r := i - bi * beat_len
		var kt := float(r) / float(MIX_RATE)
		var kick := sin(TAU * (45.0 * kt + 75.0 * 0.03 * (1.0 - exp(-kt / 0.03)))) * exp(-kt * 14.0)
		var n := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, n, 0.5)
		var hat := 0.0
		if r >= beat_len / 2:
			var ht := float(r - beat_len / 2) / float(MIX_RATE)
			hat = (n - lp) * exp(-ht * 55.0)
		var af: float = arp[si % arp.size()]
		var aph := time * af
		var arp_v := (sin(aph * TAU) + 0.3 * (2.0 * fmod(aph, 1.0) - 1.0)) * minf(1.0, sl * 40.0) * pow(maxf(0.0, 1.0 - sl), 1.8)
		var edge := minf(1.0, minf(t, 1.0 - t) * dur / 0.01)
		_write(data, i, (bass * 0.20 + kick * 0.45 + hat * 0.10 + arp_v * 0.05) * edge)
	return _make_wav(data, true)


## Tense tactical combat: dissonant sub drone, lub-dub pulse at 75 BPM, sparse high pings (8 s).
static func _moon_music_loop(dur: float) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1969
	var d1 := _snap(55.0, dur)
	var d2 := _snap(58.27, dur)
	var d3 := _snap(82.41, dur)
	var beat_len := count / 10
	var lp := 0.0
	var pings := [[0.30, 1318.5], [0.70, 1244.5]]
	for i in count:
		var t := float(i) / float(count)
		var time := float(i) / float(MIX_RATE)
		var drone := (sin(time * TAU * d1) * 0.5 + sin(time * TAU * d2) * 0.4 + sin(time * TAU * d3) * 0.25) * (0.7 + 0.3 * sin(t * TAU * 2.0))
		var r := i % beat_len
		var bt := float(r) / float(MIX_RATE)
		var thump := sin(bt * TAU * 62.0) * exp(-bt * 16.0)
		var bt2 := bt - 0.18
		if bt2 > 0.0:
			thump += sin(bt2 * TAU * 52.0) * exp(-bt2 * 18.0) * 0.7
		var ping := 0.0
		for p in pings:
			var pt: float = time - float(p[0]) * dur
			if pt >= 0.0:
				ping += sin(pt * TAU * float(p[1])) * exp(-pt * 4.0) * 0.05
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.04)
		var edge := minf(1.0, minf(t, 1.0 - t) * dur / 0.02)
		_write(data, i, (drone * 0.14 + thump * 0.30 + ping + lp * 0.03) * edge)
	return _make_wav(data, true)


## Calm triumphant pad: Fmaj7 - G - Cmaj9 with soft bells at each chord change (12 s).
static func _debrief_music_loop(dur: float) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var chords := [
		[87.31, 174.61, 220.0, 261.63, 329.63],
		[98.0, 196.0, 246.94, 293.66, 392.0],
		[130.81, 196.0, 261.63, 329.63, 392.0, 587.33],
	]
	var bells := [880.0, 987.77, 1046.5]
	for c in chords.size():
		for k in chords[c].size():
			chords[c][k] = _snap(chords[c][k], dur)
	var seg_len := count / 3
	for i in count:
		var t := float(i) / float(count)
		var time := float(i) / float(MIX_RATE)
		var ci := mini(2, i / seg_len)
		var lt := float(i - ci * seg_len) / float(seg_len)
		var xenv := minf(1.0, minf(lt, 1.0 - lt) * 3.5)
		var pad := 0.0
		for f in chords[ci]:
			pad += sin(time * TAU * f) + 0.25 * sin(time * TAU * f * 2.0 + 0.4)
		pad = pad / float(chords[ci].size()) * 0.17 * xenv
		var bf: float = bells[ci]
		var bt := lt * dur / 3.0
		var bell := (sin(time * TAU * bf) + 0.2 * sin(time * TAU * bf * 2.76)) * minf(1.0, bt * 60.0) * exp(-bt * 1.4) * 0.05
		var edge := minf(1.0, minf(t, 1.0 - t) * dur / 0.02)
		_write(data, i, (pad + bell) * edge)
	return _make_wav(data, true)


## Looping sci-fi menu music: slow pad chord progression + sparkle arp over a sub drone (8 s, seamless).
static func menu_music() -> AudioStreamWAV:
	if not _long_cache.has("menu_music"):
		_long_cache["menu_music"] = _menu_music_loop(16.0)
	return _long_cache["menu_music"]


## Looping station hum: low machinery drone + airy filtered noise (6 s, seamless).
static func station_ambience() -> AudioStreamWAV:
	if not _long_cache.has("station_ambience"):
		_long_cache["station_ambience"] = _station_hum_loop(6.0)
	return _long_cache["station_ambience"]


## Snap a frequency to a whole number of cycles per loop so the loop point is click-free.
static func _snap(freq: float, dur: float) -> float:
	return maxf(1.0, roundf(freq * dur)) / dur


static func _menu_music_loop(dur: float) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	# 4 chords (Am9 - Fmaj7 - Cmaj7 - Gsus2), 4 s each.
	var chords := [
		[110.0, 220.0, 261.63, 329.63, 493.88],
		[87.31, 174.61, 261.63, 329.63, 440.0],
		[130.81, 196.0, 261.63, 329.63, 493.88],
		[98.0, 196.0, 293.66, 392.0, 440.0],
	]
	var arp := [880.0, 1046.5, 1318.5, 1046.5, 1568.0, 1318.5, 1046.5, 1318.5]
	var seg_len := count / chords.size()
	var step_len := count / 32
	for c in chords.size():
		for k in chords[c].size():
			chords[c][k] = _snap(chords[c][k], dur)
	for k in arp.size():
		arp[k] = _snap(arp[k], dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var lp := 0.0
	for i in count:
		var t := float(i) / float(count)
		var time := float(i) / float(MIX_RATE)
		var ci := mini(chords.size() - 1, i / seg_len)
		var lt := float(i - ci * seg_len) / float(seg_len)
		var xenv := minf(1.0, minf(lt, 1.0 - lt) * 5.0) # soft cross-fade per chord
		var pad := 0.0
		for f in chords[ci]:
			pad += sin(time * TAU * f) + 0.35 * sin(time * TAU * f * 2.0 + 0.7)
		pad = pad / float(chords[ci].size()) * 0.17 * xenv * (0.8 + 0.2 * sin(t * TAU * 4.0))
		var drone := sin(time * TAU * _snap(55.0, dur)) * 0.10
		var si := i / step_len
		var sl := float(i - si * step_len) / float(step_len)
		var af: float = arp[si % arp.size()]
		var aenv := minf(1.0, sl * 30.0) * pow(maxf(0.0, 1.0 - sl), 2.5)
		var spark := sin(time * TAU * af) * 0.045 * aenv * (1.0 if si % 2 == 0 else 0.5)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.03)
		var air := lp * 0.025
		# Loop end is not guaranteed continuous for noise/spark tails, so fade the last/first few ms.
		var edge := minf(1.0, minf(t, 1.0 - t) * dur / 0.02)
		var s := clampf((pad + drone + spark + air) * edge, -1.0, 1.0)
		data.encode_s16(i * 2, roundi(s * 32767.0))
	return _make_wav(data, true)


static func _station_hum_loop(dur: float) -> AudioStreamWAV:
	var count := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var lp := 0.0
	var f1 := _snap(60.0, dur)
	var f2 := _snap(120.0, dur)
	var f3 := _snap(180.5, dur)
	for i in count:
		var t := float(i) / float(count)
		var time := float(i) / float(MIX_RATE)
		var hum := sin(time * TAU * f1) * 0.10 + sin(time * TAU * f2) * 0.05 + sin(time * TAU * f3) * 0.025
		hum *= 0.8 + 0.2 * sin(t * TAU * 2.0)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.05)
		var air := lp * 0.05 * (0.7 + 0.3 * cos(t * TAU * 3.0))
		var edge := minf(1.0, minf(t, 1.0 - t) * dur / 0.02)
		var s := clampf((hum + air) * edge, -1.0, 1.0)
		data.encode_s16(i * 2, roundi(s * 32767.0))
	return _make_wav(data, true)
