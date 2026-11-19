# Phase 1 performance report

Implemented and verified with Godot 4.7.2, using headless runs only. No GPU timing, battery measurements, or visual comparison was performed.

| Item | Result |
| --- | --- |
| 1 | Done: 2x MSAA, explicit 1.0 3D scale, 120 FPS cap, 2048 directional shadows, soft low filtering. Physics remains 60 Hz. Forward Plus remains selected. |
| 2 | Done: all five authored Environments and Gfx.environment use SSAO radius 0.5 and detail 0.1. Project quality is very low with half size enabled. Glow remains enabled. |
| 3 | Done: Gfx.sun and the three authored Sun nodes use two splits and 90 m distance. Planet A/B scenes have no separate Sun nodes. Existing Gfx.mesh shadow parameter retained; bolts, sparks, flag components and named small fittings do not cast shadows. Existing tracer/exhaust shadow exclusions retained. |
| 4 | Done: incremental sky processing, 0.01 atmosphere/mix dirty threshold, exact atmosphere endpoint updates, cached day endpoint dictionaries. Fog, sun, and star behavior still update continuously. |
| 5 | Done: crosshair dirty check, one bound shop connection per Sim, summary cached by loadout/credits/unconfirmed slots, advice loop, common formatting at 10 Hz with immediate flight health and existing field ammo/health updates. Shared Radar.request_redraw caps requests at 20 Hz for all five level scripts and tactical HUD. main.gd has no direct redraw calls and needed no edit. |
| 6 | Done: unshaded material cache includes color and alpha. Ghost tint and tracer callers only assign materials; they do not mutate them, so shared instances are safe. |
| 7 | Done: bolt palette precomputed when building the ship, and Landing children cached for that ship instance. |
| 8 | Done: backward spark removal without duplicate(), retained spark mesh pool, workshop formatting at 10 Hz. Actual workshop sparks are spheres; their geometry was preserved. Radar requests remain independent of formatting. |
| 9 | Done for impacts: parent-owned particle/light pairs reused after expiry; up to 12 idle bursts retained, with concurrent bursts allowed to overflow so hits are not dropped. Separate exhaust node pooling skipped: exhaust already keeps one particle emitter/light pair per nozzle and reuses them across activation/intensity changes. That lifecycle remains intact; shared soft-particle quad/material resources are now cached. |
| 10 | Done: plugin and _mcp_game_helper retained. No export_presets.cfg exists, so README contains the export note. |

## Files changed

- project.godot
- README.md
- scripts/gfx.gd
- scripts/universe.gd
- scripts/hud.gd
- scripts/planet_a.gd
- scripts/planet_b.gd
- scripts/workshop.gd
- scripts/orbit_ship.gd
- scripts/flight.gd
- scripts/combat_fx.gd
- scripts/exhaust_fx.gd
- scenes/levels/FlightEnvironment.tscn
- scenes/levels/PlanetAEnvironment.tscn
- scenes/levels/PlanetBEnvironment.tscn
- scenes/levels/UniverseEnvironment.tscn
- scenes/levels/WorkshopEnvironment.tscn
- scenes/prefabs/FlagMarker.tscn
- tests/performance_test.gd (new)
- docs/phase-1-performance.md (new)

## Verification

Before edits, copied the original files into /tmp/tminus-phase1-original and ran every existing tests/*.gd script. No Git operations were used for the baseline or comparison.

Every invocation used:

```sh
/Users/kngightzzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/<name>.gd
```

| Test | Baseline | Final |
| --- | --- | --- |
| crew_match_runtime_test | 0 failures | 0 failures |
| crew_match_test | 0 failures | 0 failures |
| editable_scene_test | 0 failed | 0 failed |
| pad_sequence_runtime_test | 0 failures | 0 failures |
| ship_assembly_test | 1903 checks, 0 failures | 1903 checks, 0 failures |
| ship_builder_runtime_test | 0 failures | 0 failures |
| ship_catalog_test | PASS | PASS |
| shop_picker_runtime_test | 0 failures | 0 failures |
| sim_test | PASS | PASS |
| sp_test | PASS | PASS |
| performance_test | New test | 0 failures |

All original 10 scripts exited 0 before edits; all 11 final scripts exited 0. The new test exercises concurrent impact independence, expiry and reuse of particles and lights, state reset, retained exhaust activation, and material cache identity/alpha separation.

Baseline logs: /tmp/tminus-phase1-baseline. Final logs: /tmp/tminus-phase1-after. Existing user:// log-write and macOS certificate errors are unchanged after normalizing timestamps; no new script errors occurred. These environment diagnostics are distinct from test assertion failures.
