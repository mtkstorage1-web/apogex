# Phase 2 textures

Implemented for Godot 4.7 Forward Plus. All verification was headless on Godot 4.7.2. Appearance and GPU upload/frame timing need a later visual check on a machine that supports rendering; no non-headless runs were made.

| Requested item | Result |
| --- | --- |
| 1. Cached procedural textures | Done. ProcTex shares six 512×512 seamless, mipmapped NoiseTexture2D resources with deterministic FastNoiseLite seeds. Ground/rock neutral albedo, ground/rock normal, cellular metal normal, and shared sky noise. Generation uses NoiseTexture2D's background worker; no synchronous image generation or startup image reads in gameplay. Tint arguments deliberately share neutral textures; material albedo applies tint once. |
| 2. Ground and rock | Done. Authored Workshop/Planet A/Planet B terrain and fallback Workshop/Planet A builders use cached StandardMaterial3D materials with world triplanar sampling, anisotropic linear mip filtering, existing color tint, and normal maps. Gfx.rock uses the rock setup. |
| 3. Sky | Done. Authored ProceduralSkyMaterial resources remain as editable palette sources with tuned curves. Runtime uses one small sky shader for a gradient, two static noise samples for clouds/nebula, static hashed stars, and a fixed subtle glow. Space/orbit selects stars; day selects clouds. Universe blends through its existing 0.01 dirty threshold; workshop launch now uses the same threshold and exact endpoints. Automatic processing and 64 radiance are explicit. No TIME, POSITION or live light dependency in the sky shader. |
| 4. Planets | Done. Lit spatial shader on BodyA/BodyB, Gfx.planet, flight scene planet cores, and universe distant planet/moon. Triplanar noise, bands, three palette colors, clouds and Fresnel rim emission. Old cylinder bands are omitted in code and hidden in authored flight scenery. Optional TIME rotation skipped to keep the materials static. |
| 5. Industrial | Done. Existing grain retained; optional panel seams and sampled cellular normal give bevel/scratch detail with trilinear mip filtering. IndustrialHardware caches materials by paint/metal/finish and binds the shared normal. |
| 6. Reusable resources/budget | Done. Static ground, rock and metal templates in assets/materials; generated textures remain in code. Six RGBA8 512px mip chains would occupy about 8 MiB total (actual scalar noise may use less), below 16 MiB. This counts new sampled textures, excluding engine sky radiance/render targets. |
| 7. Tests/documentation | Done. All 12 tests/*.gd scripts exit 0, with no assertion failures. New textures_test checks cache identity, settings, authored body assignment, generated mip chains, retained SSAO and sky settings. |

## Tunables

- `scripts/proc_tex.gd`: deterministic seeds, frequency (ground/sky 0.018, rock 0.035, cellular metal 0.025), four octaves, normal bump strength (5 terrain, 2 metal). Albedo ramp is neutral 0.68–1.0 to preserve color identity. Generation starts once on first request and textures appear when the worker completes; there is no blocking wait in gameplay.
- `assets/materials/ground.tres`: `uv1_scale = (0.08, 0.08, 0.08)` gives a 12.5 m repeat, roughness 0.95, normal scale 0.6, world triplanar enabled. `rock.tres` is the independent rock template; `Gfx.terrain_mat` sets rock frequency to 0.3 (3.33 m repeat). Cached material tints come from the original authored albedo colors. Shared resources should not be mutated per instance.
- `scripts/textured_environment.gd`: root setup runs once on entry; assigns ground/rock by Terrain hierarchy and planet shaders by BodyA/BodyB/Core name. Applies to authored scenes, including nested scenes. Planet A/B have no active independent WorldEnvironment; they use the shared Universe sky.
- `scripts/gfx.gd`: `terrain_mat` and `planet_mat` cache by palette/detail. `textured_sky` copies authored top/horizon/bottom colors. Gfx.environment chooses space when top luminance is below 0.12 (covers orbit interior). Sky resources are per environment because their atmosphere parameters differ.
- `assets/shaders/sky_space.gdshader`: `atmosphere` blends static star/nebula versus subtle clouds. Gradient exponents 0.45/0.55 control horizon rolloff; star cell density is 650, threshold 0.9985. Fixed glow direction and strength are editable in the shader. Runtime sun references are intentionally absent so moving gameplay lights cannot invalidate radiance each frame. Authored procedural curves are retained as fallback settings; runtime gradient exponents control the shader appearance.
- `scripts/universe.gd`: DAY/SPACE palette dictionaries still control atmosphere blending and retain the Phase 1 0.01 dirty threshold and endpoint behavior. Fog and lighting behavior remain continuous.
- `assets/shaders/planet.gdshader`: `palette_a/b/c`, `clouds` (0.18), `atmosphere` rim strength (0.18), band frequency 26, noise repeat 2. Defaults are purple; each authored planet derives its palette from its existing color, while Gfx.planet uses the caller's original base/band pair. Geometry stays lit by the sun; only the rim emits.
- `assets/materials/metal.tres` / `industrial.gdshader`: `panel_detail` 0.35 (zero disables detail), `panel_scale` 0.5; paint/metal/finish remain caller tunables. Normal sampler has `hint_normal` neutral default when unbound, and `filter_linear_mipmap`.

## Validation

Every script was run with:

```sh
/Users/kngightzzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/<name>.gd
```

Passing scripts: crew_match_runtime_test, crew_match_test, editable_scene_test, pad_sequence_runtime_test, performance_test, ship_assembly_test (1903 checks), ship_builder_runtime_test, ship_catalog_test, shop_picker_runtime_test, sim_test, sp_test, textures_test.

Texture request setup measured 0.03 ms in the initial successful texture test. This measures main-thread resource setup, not worker completion or GPU upload; a <50 ms rendered frame guarantee cannot be measured with the headless dummy renderer. Test waits for generated images without blocking gameplay. Logs: `/tmp/tminus-phase2-tests`. Existing user:// log-write and macOS certificate diagnostics persist; there are no new script errors in the final tests.

Phase 1 constraints retained: Forward Plus and project quality settings unchanged; SSAO radius 0.5/detail 0.1 unchanged; no per-frame material creation; material caching expanded; no realtime sky. Automatic sky processing replaces Phase 1 incremental processing as requested, without time-dependent shader inputs.

## Files changed

- New: scripts/proc_tex.gd, scripts/textured_environment.gd
- Updated: scripts/gfx.gd, scripts/universe.gd, scripts/workshop.gd, scripts/planet_a.gd, scripts/industrial_hardware.gd
- New: assets/shaders/planet.gdshader, assets/shaders/sky_space.gdshader
- Updated: assets/shaders/industrial.gdshader
- New: assets/materials/ground.tres, assets/materials/rock.tres, assets/materials/metal.tres
- Updated: scenes/levels/{Workshop,PlanetA,PlanetB,Flight,Universe}Environment.tscn
- New: tests/textures_test.gd, docs/phase-2-textures.md
