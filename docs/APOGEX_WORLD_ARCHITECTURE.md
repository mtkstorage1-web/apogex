# APOGEX World Architecture (Vesper-9)

## 1. Scene ownership

`scenes/world/WorldRoot.tscn` (script `scripts/world/WorldRoot.gd`) is the single owner. It builds, wires and drives
every subsystem; subsystems never reach into each other except through WorldRoot.

| Owner | Responsibility |
|---|---|
| `WorldCoordinateSystem` / `FloatingOriginManager` | planet-space <-> render-space, origin shifts (`origin_shifted`) |
| `PlanetGenerator` (+ `PlanetLODManager`, collision) | cube-sphere terrain, biomes, collision |
| `AtmosphereController` | atmosphere shell + cloud shell (3 formations) |
| `SpaceEnvironmentController` | starfield, nebulae, galactic haze, exoplanet + ring |
| `WorldLighting`, Star | sun light, sky/fog environment |
| `SurfacePropScatterer`, `LandmarkManager`, `SurfaceFacilityManager`, `SurfaceEffectsController` | surface content |
| `MothershipManager` | Helion + Cinder motherships |
| `OrbitalEnvironmentManager` (+ `DebrisFieldController`) | orbital structures + debris field |
| `WorldStreamingManager` | regions, threaded loader, residency, LOD |
| `WeatherEffectsController` | dust storms, volcanic plumes, electrical arcs |
| `DestructionStateController` | destructible sections |
| `WorldAudioController` | audio buses, zones, vacuum acoustics |
| `ExplorerController`, `WorldDebugUI` | test camera + HUD / F1 diagnostics / settings |

## 2. Directory layout

```
scripts/coordinates   coordinate math + floating origin
scripts/terrain       planet generation, LOD, collision
scripts/world         WorldRoot, config, lighting, space environment
scripts/atmosphere    AtmosphereController
scripts/environment   facilities, motherships, orbital, weather, destruction, audio
scripts/streaming     SceneChunkLoader, AssetResidencyManager, EnvironmentLODController,
                      RegionStreamingController, WorldStreamingManager
scripts/testing       ExplorerController, WorldDebugUI
scenes/{world,surface,mothership,orbital,terrain,testing}
assets/models/apogex/{landmarks,orbital,...}   Blender GLB kits
shaders/              atmosphere, cloud, terrain, ...
tests/{coordinates,terrain,world_validation,streaming}
```

## 3. Coordinate spaces

* **Planet space**: double-free float vectors centred on the planet (radius 12,000 m; atmosphere shell 13,200 m).
  Altitude = `|p| - planet_radius`.
* **Render space**: `render = planet - current_origin`. The floating origin shifts when the explorer is more than
  2,000 m from it. Every subsystem implements `apply_origin(new_origin)` and keeps its own planet-space
  `base_pos`, so shifts never accumulate error.
* **Local frames**: surface pads use `surface_tangent_basis(unit_dir)`; motherships and orbital structures use a
  tangent basis at their orbital unit direction (+Y away from the planet).
* Camera-relative layers (starfield dome, dust particles, follow-audio) simply follow the camera.

## 4. Blender GLB kits

Models are loaded with `ResourceLoader.exists(path)`; on a miss a multi-part procedural fallback with the exact
GLB bounding dimensions is built, so the world is always complete. Once `Godot --import` runs, the GLBs replace the
fallbacks automatically. Orbital kit (`assets/models/apogex/orbital/`, centred, zero-G):

| GLB | Size (m) |
|---|---|
| broken_satellite | 14 x 6 x 8 |
| solar_array_fragment | 12 x 1.2 x 5 |
| rocket_stage_hulk | 6 x 6 x 22 |
| hull_wreckage_slab | 16 x 4 x 10 |
| abandoned_research_station | 85 x 60 x 85 |
| broken_orbital_refinery | 95 x 55 x 70 |
| nav_beacon_array | 12 x 24 x 12 |
| orbital_docking_hub | 48 x 28 x 48 |

Orbital structures sit 1,800 - 3,200 m above the reference radius. The debris field has four tiers: (1) large
traversable wreckage and (2) medium satellites with `StaticBody3D` collision; (3) small fragments and (4) the distant
dust ring as `MultiMeshInstance3D` with **no collision**. All placement derives from `world_seed`.

## 5. Streaming states

`RegionStreamingController.ChunkState`: `UNLOADED -> REQUESTED -> LOADING -> READY -> ACTIVE -> RETIRING -> UNLOADED`.

* 8 regions: Central Terminus, North Highlands, East Iron Desert, West Obsidian, South Ashen, Helion Orbit,
  Cinder Orbit, Orbital Debris Belt.
* Each region has an enter radius below `0.8 x` its exit radius (hysteresis). Enter uses a velocity /
  look-direction lookahead point; exit uses the real focus.
* `max_activations_per_frame` (1 LOW/MEDIUM, 2 HIGH, 3 ULTRA) prevents activation spikes; activation also needs
  residency budget (256 / 512 / 1024 / 2048 MB).
* `SceneChunkLoader` wraps `ResourceLoader.load_threaded_*`; finished resources are handed back only from main-thread
  calls, so the SceneTree is never mutated off-thread.
* `AssetResidencyManager` keeps authoritative world state separately from visual instances, so retire/reload preserves it.
* `EnvironmentLODController` applies distance/altitude tiers with a 12% hysteresis band.
* `WorldStreamingManager.update_streaming(...)` / `get_streaming_stats()` is the public entry point.

## 6. Destruction framework

`DestructionStateController.DestructionState { INTACT, DAMAGED, CRITICAL, DESTROYED }`. Sections (stable StringName ids):
`terminus_outer_perimeter`, `refinery_conduit_array`, `mining_derrick_rig`, `settlement_power_grid`,
`launch_pad_blast_shield`. API: `set_section_state(id, state)`, `cycle_all_states()`, `get_states()`. State lives in a
dictionary independent from the visuals (indicator pylon colour, scorch decal, smoke, sparks, rubble collision), so
`unload_section_visual` / `load_section_visual` restores identical looks. Transitions emit `audio_event`.

## 7. Audio buses

`Environment`, `Machinery`, `Weather`, `Ambience` (created on demand, routed to Master). Spatial hooks
(`AudioStreamPlayer3D` over procedural looping `AudioStreamWAV`, so no files can be missing): hangar machinery, reactor
room, mining refinery, surface wind, dust storm, lava fissure, underground tunnel, launch facility, orbital debris
impact. A quality-based budget (4/6/8/9) limits simultaneously playing zones.

**Vacuum acoustics**: the atmosphere factor is 1 below 600 m and fades smoothly to 0 at 1,100 m. Environment, Weather
and Ambience fall toward -60 dB; Machinery keeps -30 dB of structure-borne vibration. Inside mothership interiors
the cabin air is pressurised: Ambience stays at 0 dB and Environment/Weather hold a hull-muted -12 dB.

## 8. Quality presets

`LOW / MEDIUM / HIGH / ULTRA` (`WorldRoot.set_quality_preset`) scale terrain LOD, atmosphere scattering steps, the three cloud
formations (high wisps, storm bands, volcanic plumes), starfield + haze, debris fragment / dust counts, satellite
count, weather particle counts, spark counts, audio zone budget, streaming activation cap and residency budget.

## 9. Explorer controls

WASD move, Space/Ctrl up/down, Shift fast, Wheel speed, C camera mode, F walk/fly, G gravity alignment, M map,
P settings panel, F1 diagnostics (streaming, destruction, audio vacuum, orbital count, storm), F2 wireframe, F3
collision debug, F4 LOD heatmap, F5 regenerate, F6 next landmark, F7 orbit/surface, H hangar doors,
**K cycle destruction states**, Esc mouse capture. The settings panel adds orbital landmark buttons, hangar doors,
Cycle Destruction and a storm-intensity indicator.

## 10. Tests

```
Godot --headless --path . -s res://tests/coordinates/test_coordinates.gd
Godot --headless --path . -s res://tests/terrain/test_terrain_determinism.gd
Godot --headless --path . -s res://tests/world_validation/test_world_bootstrap.gd
Godot --headless --path . -s res://tests/world_validation/test_surface_facilities.gd
Godot --headless --path . -s res://tests/world_validation/test_motherships.gd
Godot --headless --path . -s res://tests/streaming/test_world_streaming.gd
Godot --headless --path . -s res://tests/world_validation/test_acceptance_25.gd
```
