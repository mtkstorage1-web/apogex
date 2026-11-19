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
	return _cache


static func _make_wav(samples: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = samples
	return wav


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
