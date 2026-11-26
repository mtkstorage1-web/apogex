extends Node

# APOGEX (Godot 4.7) × Flagsmith Experimentation Manager
# Connects to Flagsmith Cloud Edge API (POST /api/v1/identities/) when an Environment Key
# is configured, and falls back to deterministic local A/B bucketing when offline/unconfigured.

signal flags_updated(snapshot: Dictionary)
signal telemetry_updated(telemetry: Array)

const DEFAULT_API_BASE := "https://edge.api.flagsmith.com/api/v1"
const CONFIG_PATH := "user://flagsmith.cfg"
const TELEMETRY_PATH := "user://flagsmith_telemetry.json"

const EXPERIMENT_DEFINITIONS := {
	"exp_extraction_balance": {
		"label": "Extraction Balance",
		"variants": ["standard", "fast_blitz", "high_risk_double"],
		"default": "standard",
		"effects": {
			"standard": {"capture_rate": 1.0, "score_multiplier": 1.0, "label": "1.0x speed · 1.0x score"},
			"fast_blitz": {"capture_rate": 1.45, "score_multiplier": 0.9, "label": "1.45x speed · 0.9x score"},
			"high_risk_double": {"capture_rate": 0.8, "score_multiplier": 2.0, "label": "0.8x speed · 2.0x score"},
		},
	},
	"exp_combat_pacing": {
		"label": "Arena Clash Pacing",
		"variants": ["standard", "turbo_clash", "tactical_hardcore"],
		"default": "standard",
		"effects": {
			"standard": {"damage_multiplier": 1.0, "respawn_scale": 1.0, "label": "Standard combat & respawn"},
			"turbo_clash": {"damage_multiplier": 1.2, "respawn_scale": 0.65, "label": "+20% dmg · fast respawn"},
			"tactical_hardcore": {"damage_multiplier": 1.4, "respawn_scale": 1.35, "label": "+40% dmg · longer respawn"},
		},
	},
	"exp_empire_economy": {
		"label": "Empire Economy",
		"variants": ["standard", "overdrive_gold", "scarce_frontier"],
		"default": "standard",
		"effects": {
			"standard": {"treasury_rate": 1.0, "golden_core_points": 2, "label": "1.0x treasury · 2pt Golden Core"},
			"overdrive_gold": {"treasury_rate": 2.0, "golden_core_points": 3, "label": "2.0x treasury · 3pt Golden Core"},
			"scarce_frontier": {"treasury_rate": 0.7, "golden_core_points": 2, "label": "0.7x treasury · scarce resources"},
		},
	},
}

const BOOLEAN_FLAG_DEFAULTS := {
	"feature_moon_low_gravity": {"enabled": false, "label": "Low-Gravity Planet C · Moon"},
	"feature_quick_deploy_default": {"enabled": true, "label": "Quick Deploy Lobby Option"},
	"feature_golden_science_cores": {"enabled": true, "label": "Golden Science Cores"},
}

var environment_key: String = ""
var identity: String = ""
var mode: String = "fallback" # "fallback" | "connecting" | "live"
var last_error: String = ""
var last_synced_at: String = ""

var traits: Dictionary = {
	"mode": "arena_clash",
	"coalition": "ORANGE",
	"matches_played": 0,
	"flags_delivered": 0,
	"eliminations": 0,
	"matches_won": 0,
}

var flags: Dictionary = {}
var telemetry: Dictionary = {}

var _http: HTTPRequest = null
var _hud: CanvasLayer = null

func _ready() -> void:
	_load_config()
	_load_telemetry()
	if identity.is_empty():
		identity = "apogex_%08x" % (randi() & 0x7fffffff)
		_save_config()
	flags = _default_flags_for_identity(identity)
	_http = HTTPRequest.new()
	_http.name = "FlagsmithHTTP"
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	if not DisplayServer.get_name().to_lower().contains("headless"):
		var hud_script := load("res://scripts/flagsmith_hud.gd")
		if hud_script:
			_hud = hud_script.new()
			add_child(_hud)

	if not environment_key.is_empty():
		sync_flags()
	else:
		flags_updated.emit(get_snapshot())

static func fnv1a_32(text: String) -> int:
	var h: int = 2166136261
	var bytes := text.to_utf8_buffer()
	for b in bytes:
		h = (h ^ int(b)) & 0xffffffff
		h = (h * 16777619) & 0xffffffff
	return h

static func pick_deterministic_variant(id_str: String, flag_name: String, variants: Array) -> String:
	if variants.is_empty():
		return ""
	var idx: int = fnv1a_32("%s:%s" % [id_str, flag_name]) % variants.size()
	return str(variants[idx])

func _default_flags_for_identity(id_str: String) -> Dictionary:
	var out: Dictionary = {}
	for flag_name in EXPERIMENT_DEFINITIONS.keys():
		var def: Dictionary = EXPERIMENT_DEFINITIONS[flag_name]
		out[flag_name] = {
			"enabled": true,
			"value": pick_deterministic_variant(id_str, flag_name, def["variants"]),
			"source": "fallback",
		}
	for flag_name in BOOLEAN_FLAG_DEFAULTS.keys():
		var def: Dictionary = BOOLEAN_FLAG_DEFAULTS[flag_name]
		out[flag_name] = {
			"enabled": bool(def["enabled"]),
			"value": null,
			"source": "fallback",
		}
	return out

func _load_config() -> void:
	var env_val := OS.get_environment("FLAGSMITH_ENV_KEY").strip_edges()
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		environment_key = str(cfg.get_value("flagsmith", "environment_key", "")).strip_edges()
		identity = str(cfg.get_value("flagsmith", "identity", "")).strip_edges()
	if not env_val.is_empty():
		environment_key = env_val

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("flagsmith", "environment_key", environment_key)
	cfg.set_value("flagsmith", "identity", identity)
	cfg.save(CONFIG_PATH)

func _load_telemetry() -> void:
	if not FileAccess.file_exists(TELEMETRY_PATH):
		telemetry = {}
		return
	var text := FileAccess.get_file_as_string(TELEMETRY_PATH)
	var parsed = JSON.parse_string(text)
	telemetry = parsed if parsed is Dictionary else {}

func _save_telemetry() -> void:
	var f := FileAccess.open(TELEMETRY_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(telemetry))
		f.close()

func set_environment_key(key: String) -> void:
	environment_key = key.strip_edges()
	_save_config()
	if environment_key.is_empty():
		flags = _default_flags_for_identity(identity)
		mode = "fallback"
		last_error = ""
		flags_updated.emit(get_snapshot())
	else:
		sync_flags()

func set_trait(trait_key: String, trait_value: Variant, should_sync: bool = true) -> void:
	traits[trait_key] = trait_value
	if should_sync and not environment_key.is_empty():
		sync_flags()
	else:
		flags_updated.emit(get_snapshot())

func set_local_override(flag_name: String, enabled: bool, value: Variant = null) -> void:
	flags[flag_name] = {
		"enabled": enabled,
		"value": value,
		"source": "local-override",
	}
	flags_updated.emit(get_snapshot())

func is_enabled(flag_name: String, default_val: bool = false) -> bool:
	if flags.has(flag_name):
		return bool(flags[flag_name].get("enabled", default_val))
	return default_val

func get_flag_value(flag_name: String, default_val: Variant = null) -> Variant:
	if not flags.has(flag_name):
		return default_val
	var v = flags[flag_name].get("value", null)
	if v == null or (v is String and v.is_empty()):
		return default_val
	return v

func get_modifiers() -> Dictionary:
	var ext_v: String = str(get_flag_value("exp_extraction_balance", "standard"))
	var combat_v: String = str(get_flag_value("exp_combat_pacing", "standard"))
	var econ_v: String = str(get_flag_value("exp_empire_economy", "standard"))

	var ext_eff: Dictionary = EXPERIMENT_DEFINITIONS["exp_extraction_balance"]["effects"].get(
		ext_v, EXPERIMENT_DEFINITIONS["exp_extraction_balance"]["effects"]["standard"]
	)
	var combat_eff: Dictionary = EXPERIMENT_DEFINITIONS["exp_combat_pacing"]["effects"].get(
		combat_v, EXPERIMENT_DEFINITIONS["exp_combat_pacing"]["effects"]["standard"]
	)
	var econ_eff: Dictionary = EXPERIMENT_DEFINITIONS["exp_empire_economy"]["effects"].get(
		econ_v, EXPERIMENT_DEFINITIONS["exp_empire_economy"]["effects"]["standard"]
	)

	return {
		"extraction_variant": ext_v,
		"combat_variant": combat_v,
		"economy_variant": econ_v,
		"capture_rate": float(ext_eff["capture_rate"]),
		"score_multiplier": float(ext_eff["score_multiplier"]),
		"damage_multiplier": float(combat_eff["damage_multiplier"]),
		"respawn_scale": float(combat_eff["respawn_scale"]),
		"treasury_rate": float(econ_eff["treasury_rate"]),
		"golden_core_points": int(econ_eff["golden_core_points"]),
		"moon_low_gravity": is_enabled("feature_moon_low_gravity", false),
		"quick_deploy_default": is_enabled("feature_quick_deploy_default", true),
		"golden_science_cores": is_enabled("feature_golden_science_cores", true),
	}

func apply_flagsmith_payload(payload: Variant) -> void:
	var next := _default_flags_for_identity(identity)
	var list: Array = []
	if payload is Array:
		list = payload
	elif payload is Dictionary and payload.has("flags") and payload["flags"] is Array:
		list = payload["flags"]

	for item in list:
		if not (item is Dictionary):
			continue
		var fname := ""
		if item.has("feature") and item["feature"] is Dictionary:
			fname = str(item["feature"].get("name", ""))
		elif item.has("name"):
			fname = str(item.get("name", ""))
		if fname.is_empty():
			continue
		next[fname] = {
			"enabled": bool(item.get("enabled", false)),
			"value": item.get("feature_state_value", item.get("value", null)),
			"source": "flagsmith-cloud",
		}
	flags = next

func sync_flags() -> void:
	if environment_key.is_empty() or _http == null:
		mode = "fallback"
		last_error = ""
		flags_updated.emit(get_snapshot())
		return

	mode = "connecting"
	flags_updated.emit(get_snapshot())

	var trait_list: Array = []
	for k in traits.keys():
		trait_list.append({"trait_key": str(k), "trait_value": traits[k]})

	var body := JSON.stringify({"identifier": identity, "traits": trait_list})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Environment-Key: " + environment_key,
	])
	var err := _http.request(DEFAULT_API_BASE + "/identities/", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		mode = "fallback"
		last_error = "HTTPRequest error: %d" % err
		flags_updated.emit(get_snapshot())

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		mode = "fallback"
		last_error = "Flagsmith API HTTP %d" % response_code
		flags_updated.emit(get_snapshot())
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null:
		mode = "fallback"
		last_error = "Invalid JSON from Flagsmith"
		flags_updated.emit(get_snapshot())
		return

	apply_flagsmith_payload(parsed)
	mode = "live"
	last_error = ""
	last_synced_at = Time.get_datetime_string_from_system(true)
	flags_updated.emit(get_snapshot())

func _ensure_bucket(exp_name: String, variant: String) -> Dictionary:
	var key := "%s:%s" % [exp_name, variant]
	if not telemetry.has(key):
		telemetry[key] = {
			"experiment": exp_name,
			"variant": variant,
			"starts": 0,
			"deliveries": 0,
			"wins": 0,
			"losses": 0,
		}
	return telemetry[key]

func track_event(event_name: String, payload: Dictionary = {}) -> void:
	var mods := get_modifiers()
	var pairs := [
		["exp_extraction_balance", mods["extraction_variant"]],
		["exp_combat_pacing", mods["combat_variant"]],
		["exp_empire_economy", mods["economy_variant"]],
	]

	if event_name == "match_started":
		traits["matches_played"] = int(traits.get("matches_played", 0)) + 1
		for p in pairs:
			_ensure_bucket(p[0], p[1])["starts"] += 1
	elif event_name == "flag_delivered":
		var count: int = int(payload.get("count", 1))
		traits["flags_delivered"] = int(traits.get("flags_delivered", 0)) + count
		for p in pairs:
			_ensure_bucket(p[0], p[1])["deliveries"] += count
	elif event_name == "elimination":
		traits["eliminations"] = int(traits.get("eliminations", 0)) + int(payload.get("count", 1))
	elif event_name == "match_ended":
		var won: bool = bool(payload.get("won", false))
		if won:
			traits["matches_won"] = int(traits.get("matches_won", 0)) + 1
		for p in pairs:
			var b := _ensure_bucket(p[0], p[1])
			if won:
				b["wins"] += 1
			else:
				b["losses"] += 1
		if not environment_key.is_empty():
			sync_flags()

	_save_telemetry()
	telemetry_updated.emit(telemetry.values())
	flags_updated.emit(get_snapshot())

func get_snapshot() -> Dictionary:
	return {
		"mode": mode,
		"environment_key": environment_key,
		"has_key": not environment_key.is_empty(),
		"identity": identity,
		"traits": traits.duplicate(true),
		"flags": flags.duplicate(true),
		"modifiers": get_modifiers(),
		"telemetry": telemetry.values(),
		"last_error": last_error,
		"last_synced_at": last_synced_at,
	}
