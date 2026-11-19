# Phase 4 HUD polish

Authoritative reference: [HUD art direction](hud-art-direction.md). Verified using Godot 4.7.2 headless only.

| Item | Status | Implementation / limits |
| --- | --- | --- |
| 1 Colors | Done | Existing names retained; new surface, semantic, spacing, radius and typography tokens. `UI.ramp_color(ratio, nominal = GOOD)` uses the specified inclusive 10/30/60% thresholds. Health, ammo, fuel and power bars use the ramp; ammo counter and metric readings carry warnings. |
| 2 Fonts | Download skipped; fallback done | GitHub downloads of both variable font families and both OFL files failed with curl error 6 (DNS resolution). No font or license files were fabricated. `UI.font()` checks ResourceLoader.exists and caches FontVariation with the default font fallback. Supports assets/fonts/SpaceGrotesk.ttf and JetBrainsMono.ttf; loaded FontFiles enable MSDF and disable mipmaps. Clock, ammo and metric readings use mono_label; small UI labels use +1 glyph spacing. Named individual weight files and actual custom-font rendering remain unverified because no fonts were downloaded. |
| 3 Styles | Done | Shared cached style resources; card states and shadows, pills, five button states (including 2px keyboard focus), progress fill/background, tooltip, toast and transparent banner. SegmentedBar provides 12 rounded segments with 2px gaps. Shared styles are immutable to callers after configuration. |
| 4 Icons | Done | HudIcons has all 24 procedural geometries on a scalable 24px grid. HudIcon Control provides minimum size, tint and draw counting. HUD uses icons for metrics, ammo, fuel, power, shop credits, objectives, advisor warning and radar. |
| 5 Motion | Done | State-triggered, replaceable Tweens implement toast entrance/exit, banner entrance/exit, button hover tint, bar interpolation, damage flash and low-health pulse. UI.reduced_motion bypasses animated effects on subsequent state updates. |
| 6 Layout | Done, headless rect validation | Edge/center anchors retained, safe margins, tactical panel 520px square with 480px radar. Scoreboard telemetry wraps within its column. Added pixel snapping. Bounds checks at 1280×720 and 3004×1805 cover crosshair, status, radar, board, advisor, role bar, tactical panel and banner. Existing builder tests cover its two resolutions. No visual screenshot QA was performed. |
| 7 Radar | Done | Strong/subtle rings, terrain fills, optional sweep at 90 degrees/sec, solid/ring entities, player chevron; priority-sized rings receive expanding second ring. Terrain and chevron packed arrays reused. Radar requests retain the 20 Hz throttle. Tactical labels use UI sans. |
| 8 Consistency | Done | Main/menu, builder and picker inherit shared theme/fonts/buttons. Modal scrims use BG_DEEP, campaign mint accents use ACCENT, builder cards use cached card styles, picker purchase button uses shared primary states. |
| 9 Tests | Done | All 14 tests/*.gd scripts pass; no SCRIPT ERROR, Parse Error or WARNING in test logs. See results below. |

## Tunables

- `UI.reduced_motion`: set before the next motion trigger/value update. Existing loops settle on the next health update.
- `UI.ramp_color`: nominal color plus inclusive ratios 0.10, 0.30, 0.60; moderate color is nominal.lerp(WARN, 0.35).
- Font paths: `UI.font`; missing files always fall back. Download OFL licenses alongside fonts when network access is available.
- `UI.smooth_bar`: 0.14 seconds, cubic out; same target is ignored, previous Tween killed on replacement.
- HUD toast: 0.18 seconds cubic out, 8px rise; 0.22 seconds quadratic in exit. Queue capped at five messages.
- Banner: 0.25 seconds exponential out, scale 0.96 to 1; last 0.50 seconds linear fade.
- Button: 0.10 seconds quadratic out tint; keyboard focus enabled, no resizing.
- Damage: peak alpha capped at 0.35, 0.30 seconds exponential out.
- Health pulse: 0.90 second cycle at <=30%, 0.55 second cycle at <=10%, sine in/out, alpha 0.45–1.
- `SegmentedBar.segments`: 12 by default; gap 2px, radius 1px.
- Radar redraw accumulator: 0.05 seconds; common HUD accumulator: 0.10 seconds with selected/phase bypass. Immediate flight hull updates retained.
- No StyleBox construction, bound Callable creation or theme override occurs in HUD tick. State and color changes dirty-check before replacing styles. Style resources cache by arguments; do not mutate returned resources.

## Changed files

- scripts/ui.gd
- scripts/hud.gd
- scripts/hud_icons.gd (new)
- scripts/hud_icon.gd (new)
- scripts/segmented_bar.gd (new)
- scripts/main.gd
- scripts/ship_builder.gd
- scripts/ship_picker.gd
- project.godot
- tests/hud_style_test.gd (new)
- docs/phase-4-hud.md (new)

Godot also generates .gd.uid metadata for new scripts.

## Results

Every invocation used:

```sh
/Users/kngightzzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /private/tmp/p4_<name>.log --script tests/<name>.gd
```

| Test | Result |
| --- | --- |
| crew_match_runtime_test | exit 0, 0 failures |
| crew_match_test | exit 0, 0 failures |
| editable_scene_test | exit 0, 0 failed |
| hud_style_test | exit 0, 0 failures |
| model_detail_test | exit 0 |
| pad_sequence_runtime_test | exit 0, 0 failures |
| performance_test | exit 0, 0 failures |
| ship_assembly_test | exit 0, 0 failures |
| ship_builder_runtime_test | exit 0, 0 failures |
| ship_catalog_test | exit 0, PASS |
| shop_picker_runtime_test | exit 0, 0 failures |
| sim_test | exit 0, PASS |
| sp_test | exit 0, PASS |
| textures_test | exit 0 |

New coverage includes inclusive ramp thresholds, cached theme/card identity, missing-font fallback and configured font resolution, focus border, static tick allocation contract, all 24 icon draws in a SubViewport, reduced-motion damage behavior and HUD bounds at both sizes. Actual downloaded-font loading could not be tested.

Each test still reports the existing macOS get_system_ca_certificates `ret != noErr` environment error. This is not a script error or warning and was not suppressed. There were no non-headless runs.
