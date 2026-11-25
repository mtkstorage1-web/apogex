## Global audio: auto-wired UI button SFX, per-mode music (crossfaded), environmental ambience and gameplay SFX.
## Every sound has an immediate synthesized fallback; drop CC0 files into res://assets/audio/ to override:
##   music:    menu_music.ogg  earth_music.ogg  flight_music.ogg  moon_music.ogg  debrief_music.ogg
##   ambience: station_ambience.ogg  earth_wind.ogg  earth_birds.wav  space_engine.ogg  moon_hum.ogg
##   sfx:      sfx_walk.wav  sfx_run.wav  sfx_shoot.wav  ui_hover.wav  ui_click.wav  ui_back.wav
## (.ogg / .wav / .mp3 are all accepted for every name.)
extends Node

const AUDIO_DIR := "res://assets/audio/"
const MUSIC_DB := -12.0
const SILENT_DB := -60.0
const AMBIENCE_DB := -26.0
const WIND_DB := -24.0
const BIRD_DB := -22.0
const ENGINE_DB_MIN := -26.0
const ENGINE_DB_MAX := -12.0
const ENGINE_PITCH_MIN := 0.75
const ENGINE_PITCH_MAX := 1.45
const SFX_POOL := 10
const WIRED_META := &"_audio_mgr_wired"
const MODES := ["menu", "earth", "flight", "moon", "debrief"]

var _mode := ""
var _streams := {}      # layer/music key -> AudioStream
var _sfx := {}          # sfx id -> AudioStream
var _birds: Array[AudioStream] = []

var _music_players: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_tweens: Array[Tween] = [null, null]

var _bed_player: AudioStreamPlayer     # station hum / lunar hum
var _wind_player: AudioStreamPlayer
var _engine_player: AudioStreamPlayer
var _layer_tweens := {}                # player -> Tween
var _engine_fade := 0.0                # linear 0..1 fade for the engine layer
var _engine_fade_tween: Tween
var _engine_throttle := 0.0
var _engine_throttle_smooth := 0.0

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _bird_timer: Timer
var _bird_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()

## Long procedural loops (music / ambience) are synthesized on a WorkerThreadPool task so _ready never stalls.
## stream key -> [custom file base, SfxGen generator key]
const LONG_STREAMS := {
	"menu": ["menu_music", "menu_music"],
	"station": ["station_ambience", "station_ambience"],
	"earth": ["earth_music", "music_earth"],
	"flight": ["flight_music", "music_flight"],
	"moon": ["moon_music", "music_moon"],
	"debrief": ["debrief_music", "music_debrief"],
	"earth_wind": ["earth_wind", "earth_wind"],
	"space_engine": ["space_engine", "space_engine"],
	"moon_hum": ["moon_hum", "moon_hum"],
}
var _synth_task := -1
var _synth_jobs: Array = []          # generator keys the worker must build (read-only while it runs)
var _synth_results := {}             # generator key -> AudioStream, written only by the worker
var _streams_ready := false
## True on the Dummy driver (headless runs / no audio device): nothing is audible, so the endless music and
## ambience loops are never started. AudioServer only frees a stopped playback during a later frame's update(),
## so a loop still running when the engine quits leaks its AudioStreamPlaybackWAV + AudioStreamWAV.
var _silent_backend := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent_backend = AudioServer.get_driver_name() == "Dummy"
	_rng.randomize()
	_load_streams()

	for k in 2:
		_music_players.append(_make_player(null, SILENT_DB))
	_bed_player = _make_player(null, SILENT_DB)
	_wind_player = _make_player(_streams.get("earth_wind"), SILENT_DB)
	_engine_player = _make_player(_streams.get("space_engine"), SILENT_DB)
	_bird_player = _make_player(null, BIRD_DB)
	for k in SFX_POOL:
		_sfx_players.append(_make_player(null, -6.0))

	_bird_timer = Timer.new()
	_bird_timer.one_shot = true
	_bird_timer.timeout.connect(_on_bird_timer)
	add_child(_bird_timer)

	get_tree().node_added.connect(_on_node_added)
	_wire_tree(get_tree().root)
	set_mode("menu", 0.5)


func _process(delta: float) -> void:
	if _synth_task != -1 and WorkerThreadPool.is_task_completed(_synth_task):
		_finish_synthesis()
	if _engine_player.playing:
		_engine_throttle_smooth = lerpf(_engine_throttle_smooth, _engine_throttle, clampf(delta * 6.0, 0.0, 1.0))
		_engine_player.pitch_scale = lerpf(ENGINE_PITCH_MIN, ENGINE_PITCH_MAX, _engine_throttle_smooth)
		var base := lerpf(ENGINE_DB_MIN, ENGINE_DB_MAX, _engine_throttle_smooth)
		_engine_player.volume_db = base + linear_to_db(maxf(_engine_fade, 0.0001))


# --- Loading -----------------------------------------------------------------

## Short SFX and any custom audio files load synchronously (cheap); missing long loops are queued for
## background synthesis and swapped in by _finish_synthesis() on the main thread.
func _load_streams() -> void:
	var gen := SfxGen.build_all()
	_sfx["hover"] = _load_or("ui_hover", gen["ui_hover"])
	_sfx["click"] = _load_or("ui_click", gen["ui_click"])
	_sfx["back"] = _load_or("ui_back", gen["ui_back"])
	_sfx["walk"] = _load_or("sfx_walk", gen["sfx_walk"])
	_sfx["run"] = _load_or("sfx_run", gen["sfx_run"])
	_sfx["shoot"] = _load_or("sfx_shoot", gen["sfx_shoot"])
	for id in ["ui_buy", "ui_error", "alarm_warn", "scan_hum", "ability_cast", "ko_chime", "flag_fanfare", "splash"]:
		_sfx[id] = gen[id]

	for key in LONG_STREAMS:
		var custom := _load_or(LONG_STREAMS[key][0], null, true)
		if custom:
			_streams[key] = custom
		else:
			_synth_jobs.append(LONG_STREAMS[key][1])

	var custom_birds := _load_or("earth_birds", null)
	if custom_birds:
		_birds.append(custom_birds)
	else:
		for v in 3:
			_synth_jobs.append("bird_%d" % v)

	if _synth_jobs.is_empty():
		_streams_ready = true
	else:
		_synth_task = WorkerThreadPool.add_task(_synthesize_worker, false, "AudioManager synth")


## Runs on a worker thread: only touches SfxGen's long-loop cache (used solely by this manager) and
## _synth_results, which the main thread reads after the task completes.
func _synthesize_worker() -> void:
	for job: String in _synth_jobs:
		var wav: AudioStream
		match job:
			"menu_music": wav = SfxGen.menu_music()
			"station_ambience": wav = SfxGen.station_ambience()
			_:
				if job.begins_with("bird_"):
					wav = SfxGen.bird_chirp(int(job.trim_prefix("bird_")))
				else:
					wav = SfxGen.long_stream(job)
		if wav:
			_synth_results[job] = wav


## Main thread: collect the worker's streams, wire them to players and re-apply the current mode.
func _finish_synthesis() -> void:
	WorkerThreadPool.wait_for_task_completion(_synth_task)
	_synth_task = -1
	for key in LONG_STREAMS:
		if _streams.has(key):
			continue
		var wav: AudioStream = _synth_results.get(LONG_STREAMS[key][1])
		if wav:
			_loopify(wav)
			_streams[key] = wav
	for v in 3:
		var chirp: AudioStream = _synth_results.get("bird_%d" % v)
		if chirp:
			_birds.append(chirp)
	_synth_results.clear()
	_streams_ready = true
	if _wind_player.stream == null:
		_wind_player.stream = _streams.get("earth_wind")
	if _engine_player.stream == null:
		_engine_player.stream = _streams.get("space_engine")
	if _mode != "":
		_apply_mode(_mode, 0.8)


func _exit_tree() -> void:
	if _synth_task != -1:
		WorkerThreadPool.wait_for_task_completion(_synth_task)
		_synth_task = -1
	# Release every stream / playback so no AudioStreamWAV(Playback) outlives the tree at shutdown.
	for t in _music_tweens:
		if t != null and t.is_valid():
			t.kill()
	for t in _layer_tweens.values():
		if t != null and t.is_valid():
			t.kill()
	if _engine_fade_tween != null and _engine_fade_tween.is_valid():
		_engine_fade_tween.kill()
	_music_tweens = [null, null]
	_layer_tweens.clear()
	_engine_fade_tween = null
	if _bird_timer != null:
		_bird_timer.stop()
	var players: Array = []
	players.append_array(_music_players)
	players.append_array(_sfx_players)
	players.append_array([_bed_player, _wind_player, _engine_player, _bird_player])
	for p in players:
		if p != null and is_instance_valid(p):
			p.stop()
			p.stream = null
	_streams.clear()
	_sfx.clear()
	_birds.clear()
	_synth_jobs.clear()
	_synth_results.clear()
	_streams_ready = false


## Loads res://assets/audio/<base>.(ogg|wav|mp3) if present, else the synthesized fallback.
func _load_or(base: String, fallback: AudioStream, loop := false) -> AudioStream:
	var result: AudioStream = fallback
	for ext in [".ogg", ".wav", ".mp3"]:
		var path: String = AUDIO_DIR + base + ext
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is AudioStream:
				result = res
				break
	if loop and result:
		_loopify(result)
	return result


func _loopify(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		var frame := (2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if stream.stereo else 1)
		stream.loop_end = stream.data.size() / frame


func _make_player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


# --- Mode switching ----------------------------------------------------------

func get_mode() -> String:
	return _mode


## Crossfades music and swaps ambience layers for the given mode:
## "menu", "earth", "flight", "moon" or "debrief". Unknown names are ignored.
func set_mode(mode_name: String, fade_seconds: float = 1.2) -> void:
	if not MODES.has(mode_name) or mode_name == _mode:
		return
	_mode = mode_name
	_apply_mode(mode_name, maxf(fade_seconds, 0.0))


## Streams that are still synthesizing are null here; _finish_synthesis() calls this again once they exist.
func _apply_mode(mode_name: String, secs: float) -> void:
	if _silent_backend:
		return
	_crossfade_music(_streams.get(mode_name), secs)

	match mode_name:
		"menu":
			_set_bed(_streams.get("station"), AMBIENCE_DB, secs)
		"moon":
			_set_bed(_streams.get("moon_hum"), AMBIENCE_DB - 4.0, secs)
		_:
			_set_bed(null, AMBIENCE_DB, secs)
	_fade_layer(_wind_player, WIND_DB if mode_name == "earth" else SILENT_DB, secs)
	_fade_engine(mode_name == "flight", secs)

	if mode_name == "earth":
		_schedule_bird(2.0)
	else:
		_bird_timer.stop()


## Backwards compatible: main menu / lobby music.
func play_menu_music(fade_seconds: float = 2.0) -> void:
	set_mode("menu", fade_seconds)


## Backwards compatible: fades everything out (no mode active).
func stop_menu_music(fade_seconds: float = 1.0) -> void:
	_mode = ""
	_bird_timer.stop()
	var secs := maxf(fade_seconds, 0.0)
	for k in 2:
		_fade_music_player(k, SILENT_DB, secs, true)
	_fade_layer(_bed_player, SILENT_DB, secs)
	_fade_layer(_wind_player, SILENT_DB, secs)
	_fade_engine(false, secs)


## Space engine thruster: 0.0 = idle, 1.0 = full boost. Shifts pitch (0.75..1.45) and volume.
func set_engine_throttle(throttle: float) -> void:
	_engine_throttle = clampf(throttle, 0.0, 1.0)


func _crossfade_music(stream: AudioStream, secs: float) -> void:
	if stream == null:
		_fade_music_player(_music_active, SILENT_DB, secs, true)
		return
	var current := _music_players[_music_active]
	if current.playing and current.stream == stream:
		_fade_music_player(_music_active, MUSIC_DB, secs, false)
		return
	var old := _music_active
	_music_active = 1 - _music_active
	var incoming := _music_players[_music_active]
	incoming.stream = stream
	incoming.volume_db = SILENT_DB if secs > 0.0 else MUSIC_DB
	incoming.play()
	_fade_music_player(_music_active, MUSIC_DB, secs, false)
	_fade_music_player(old, SILENT_DB, secs, true)


func _fade_music_player(idx: int, target_db: float, secs: float, stop_after: bool) -> void:
	var p := _music_players[idx]
	var old_tw := _music_tweens[idx]
	if old_tw and old_tw.is_valid():
		old_tw.kill()
	if not p.playing:
		return
	if secs <= 0.0:
		p.volume_db = target_db
		if stop_after:
			p.stop()
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", target_db, secs).set_trans(Tween.TRANS_SINE)
	if stop_after:
		tw.tween_callback(p.stop)
	_music_tweens[idx] = tw


func _set_bed(stream: AudioStream, db: float, secs: float) -> void:
	if stream == null:
		_fade_layer(_bed_player, SILENT_DB, secs)
		return
	if _bed_player.stream != stream or not _bed_player.playing:
		_bed_player.stream = stream
		_bed_player.volume_db = SILENT_DB
		_bed_player.play()
	_fade_layer(_bed_player, db, secs)


## Fades a looping layer to target_db; stops it once it reaches silence.
func _fade_layer(p: AudioStreamPlayer, target_db: float, secs: float) -> void:
	var old_tw: Tween = _layer_tweens.get(p)
	if old_tw and old_tw.is_valid():
		old_tw.kill()
	var silent := target_db <= SILENT_DB
	if not p.playing:
		if silent or p.stream == null:
			return
		p.volume_db = SILENT_DB
		p.play()
	if secs <= 0.0:
		p.volume_db = target_db
		if silent:
			p.stop()
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", target_db, secs).set_trans(Tween.TRANS_SINE)
	if silent:
		tw.tween_callback(p.stop)
	_layer_tweens[p] = tw


## Engine volume is driven in _process (throttle + fade), so only the linear fade is tweened here.
func _fade_engine(on: bool, secs: float) -> void:
	if _engine_fade_tween and _engine_fade_tween.is_valid():
		_engine_fade_tween.kill()
	if on and not _engine_player.playing and _engine_player.stream != null:
		_engine_fade = 0.0
		_engine_player.volume_db = SILENT_DB
		_engine_player.play()
	if not _engine_player.playing:
		return
	var target := 1.0 if on else 0.0
	if secs <= 0.0:
		_engine_fade = target
		if not on:
			_engine_player.stop()
		return
	_engine_fade_tween = create_tween()
	_engine_fade_tween.tween_property(self, "_engine_fade", target, secs)
	if not on:
		_engine_fade_tween.tween_callback(_engine_player.stop)


# --- Birds -------------------------------------------------------------------

func _schedule_bird(min_wait: float = 3.5) -> void:
	_bird_timer.start(_rng.randf_range(min_wait, min_wait + 5.5))


func _on_bird_timer() -> void:
	if _mode != "earth":
		return
	if not _birds.is_empty():
		_bird_player.stream = _birds[_rng.randi() % _birds.size()]
		_bird_player.volume_db = BIRD_DB + _rng.randf_range(-3.0, 1.0)
		_bird_player.pitch_scale = _rng.randf_range(0.9, 1.15)
		_bird_player.play()
	_schedule_bird()


# --- SFX ---------------------------------------------------------------------

## Plays a one-shot by id: walk, run, shoot, hover, click, back (plus ui_buy, ui_error, alarm_warn,
## scan_hum, ability_cast, ko_chime, flag_fanfare, splash). Unknown ids are ignored.
func play_sfx(id: String, db: float = -6.0, pitch_jitter: float = 0.08) -> void:
	var stream: AudioStream = _sfx.get(id)
	if stream == null or _sfx_players.is_empty():
		return
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()


# --- UI sounds ---------------------------------------------------------------

func play_hover() -> void:
	play_sfx("hover", -14.0, 0.0)


func play_click() -> void:
	play_sfx("click", -8.0, 0.0)


func play_back() -> void:
	play_sfx("back", -9.0, 0.0)


func _wire_tree(node: Node) -> void:
	_wire_button(node)
	for child in node.get_children():
		_wire_tree(child)


func _on_node_added(node: Node) -> void:
	_wire_button(node)


func _wire_button(node: Node) -> void:
	if not node is BaseButton or node.has_meta(WIRED_META):
		return
	node.set_meta(WIRED_META, true)
	var btn := node as BaseButton
	btn.mouse_entered.connect(_on_button_hover.bind(btn))
	btn.pressed.connect(_on_button_pressed.bind(btn))


func _on_button_hover(btn: BaseButton) -> void:
	if is_instance_valid(btn) and not btn.disabled:
		play_hover()


func _on_button_pressed(btn: BaseButton) -> void:
	if not is_instance_valid(btn) or btn.disabled:
		return
	var label := ""
	if btn is Button:
		label = (btn as Button).text.to_upper()
	if label.contains("BACK") or label.contains("CANCEL"):
		play_back()
	else:
		play_click()
