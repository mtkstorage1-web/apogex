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
