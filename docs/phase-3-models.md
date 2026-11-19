# Phase 3 models

Implemented and verified headlessly with Godot 4.7.2, Forward Plus retained. All 13 `tests/*.gd` scripts exit 0, with zero assertion failures and no `SCRIPT ERROR`, `Parse Error`, or `WARNING` in their final logs. Headless verification does not establish GPU frame-time neutrality or visual quality; neither a rendered comparison nor a non-headless run was performed.

## Requested items

| Item | Status and implementation |
| --- | --- |
| 1. Material deduplication | Done. Exact serialized StandardMaterial3D property matches were merged without modifying their properties or mesh assignments. This checkout had **118**, rather than the requested description's 324, Kestrel material subresources. Deduplication reduced those to **16**; the final prefab has **28** after adding twelve distinct emissive slot colors. Identical materials in ShipFamiliesPreview were also merged (138 → 36). Other scenes had no exact duplicate material blocks. Runtime industrial materials remain cached by paint, metallic value and roughness. |
| 2. Static instancing | Done for active construction paths. `model_detail.gd` normalizes box, sphere and cylinder dimensions into instance transforms, groups by geometry/material and 40 m spatial cell, and replaces repeated leaf meshes with MultiMeshInstance3D. Active rocks/hills, gantry members, pad ticks, crane braces, robot/booster fittings and new surroundings use batches. Planet B batches after reading gameplay footprints and hiding central rocks; metadata-bearing source nodes survive as Marker3D nodes. Gameplay flags, collectibles, actors, hooks, cables and collision/state hierarchies remain nodes. Universe already used a MultiMesh for its 1,400 stars; its nested authored environment now uses the same static batching. Legacy unused procedural terrain builders were left intact; they are not invoked by current setup paths. Flag bases remain with their independently animated gameplay flag hierarchy. |
| 3. Ship detail | Done for every family and all twelve slots. Exactly two added MeshInstance3D nodes per slot: merged service fittings and merged emissive accents. Includes raised rails, coolant fins, cargo/service hatch frames, bridge mast/dish, engine glow rings at existing nozzle markers, and landing pad tread strips merged into the keel detail. Existing nozzle cores remain emissive. Runtime opaque ship surfaces use the cached Phase 2 industrial material, including shared cellular normal detail, panel seams and adjustable wear roughness. Existing family geometry already differs in silhouette; no additional family redesign was necessary. |
| 4. LOD | Done. New service detail and small ship fittings end at 60 m, with an 8 m self-fade margin; slot accents end at 60 m. Repeated hardware fittings and surroundings use 60 m. Major gantry/crane members use 160 m and large terrain rocks/hills use 900 m. Spatially local batches retain useful culling bounds. Large terrain is deliberately retained past small-detail distance. |
| 5. Workshop/planet props | Done. Batched cable trays, rails, alternating warning plates and emissive lamp heads surround workshop kiosk/pad and planet pads. Robot links gain repeated hose clamps and studs; their fittings move with their existing link roots. Existing crane bracing is batched after creation. Lamp heads use emissive materials rather than new real-time lights. |
| 6. Builder/shop preview | Done. Prefab-authored detail follows module extraction and mixed-family assembly. Preview fitting recursively disables distance cutoffs/fade. Ship builder and shop picker runtime tests pass. |
| 7. Tests and report | Done. New `model_detail_test.gd` checks material reduction, all-family mesh budgets/slot detail, rock/prop MultiMesh use, metadata/footprint preservation and preview cutoff removal. All existing tests pass, including editable scenes and 2,047 ship assembly checks. |

## Counts

Ship counts are complete assembled ships with every slot using the indicated family, including landing gear. Added fittings are merged offline with SurfaceTool: node counts do not scale with strip/fin count.

| Family | Mesh nodes before | After | Increase |
| --- | ---: | ---: | ---: |
| Kestrel | 300 | 324 | 8.0% |
| Lancer | 233 | 257 | 10.3% |
| Hauler | 264 | 288 | 9.1% |
| Halo | 274 | 298 | 8.8% |
| Bulwark | 265 | 289 | 9.1% |

Level counts below isolate the authored environment, including instantiated child scenes, before entry versus after static setup. They exclude variable gameplay actors/ships and runtime machinery. MultiMesh nodes are reported separately from MeshInstance3D nodes; hidden source meshes that remain are counted. Universe includes its nested Planet A/B environments, so those rows overlap.

| Environment | Mesh nodes before | After | MultiMesh nodes after |
| --- | ---: | ---: | ---: |
| Planet A | 205 | 132 | 24 |
| Planet B | 119 | 53 | 28 |
| Workshop | 81 | 72 | 4 |
| Universe | 326 | 253 | 24 |
| Flight | 10 | 10 | 0 |
| Orbit ship interior | 81 | 81 | 0 |
| Frontier arena | 184 | 184 | 0 |

Runtime surroundings add zero MeshInstance3D nodes after batching, with one set on each planet and two sets in the workshop. Workshop crane braces and hardware batching provide additional reductions beyond the authored environment table. Universe's existing star batch is also outside that table.

`phase-3-baseline.json` records original textual scene counts and exact material deduplication counts (textual counts exclude instanced subscenes). `phase-3-counts.json` records the instantiated counts above. The baseline source snapshot is `/private/tmp/p3_original`; no Git repository was present.

## Performance and editing

- Setup and offline authoring perform the allocations; no new `_process`, `_physics_process`, tick callbacks or per-frame material/geometry allocation was added.
- Small details and batched props do not cast shadows. Major unbatched hardware retains its original shadows. No extra shadow-casting lights or textures were added.
- Repeated geometry shares meshes through MultiMesh; material grouping prevents per-instance material mutation. Ship industrial surfaces use the existing material cache and shared normal texture.
- Authored environment nodes remain editable in their source scenes; selected static render nodes are replaced only in runtime instances. Edit static source geometry there, not in the transient batches.
- `tools/build_model_detail.gd` regenerates ship details idempotently and saves them in each prefab. It computes bounds in module-local coordinates and preserves slot transforms and nozzle markers. Run it headlessly after changing the underlying hull dimensions.
- `wear_amount` in `assets/shaders/industrial.gdshader` defaults to 0.25 and changes roughness using object-space position, without vertex attributes, TIME or animation.
- GPU time, startup cost, transparency fade cost and visual placement remain unmeasured in this headless environment. The node budget and structural batching are verified; performance neutrality requires a later GPU comparison.

## Files changed

- `scripts/model_detail.gd` (new): batching, spatial grouping and surroundings.
- `scripts/textured_environment.gd`: authored static setup.
- `scripts/planet_a.gd`, `scripts/planet_b.gd`, `scripts/workshop.gd`: active pad/prop/gantry setup.
- `scripts/industrial_hardware.gd`: robot fittings and small hardware batching.
- `scripts/ship.gd`: cached industrial surfaces and small-fitting visibility/shadows.
- `scripts/shop_preview.gd`: disable preview distance LOD.
- `assets/shaders/industrial.gdshader`: uniform wear roughness.
- `scenes/prefabs/Kestrel.tscn`, `scenes/prefabs/ships/{lancer,hauler,halo,bulwark}.tscn`: saved merged detail and shared materials.
- `scenes/ShipFamiliesPreview.tscn`: duplicate material consolidation.
- `tools/build_model_detail.gd` (new): repeatable offline detail authoring.
- `tests/model_detail_test.gd` (new).
- `docs/phase-3-models.md`, `docs/phase-3-baseline.json`, `docs/phase-3-counts.json`, `docs/phase-3-tests.json` (new).

## Verification

Each script used exactly this invocation pattern:

```sh
/Users/kngightzzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /private/tmp/p3_<name>.log --script tests/<name>.gd
```

Passing: crew_match_runtime_test, crew_match_test, editable_scene_test, model_detail_test, pad_sequence_runtime_test, performance_test, ship_assembly_test, ship_builder_runtime_test, ship_catalog_test, shop_picker_runtime_test, sim_test, sp_test, textures_test.

Machine-readable exit codes and diagnostic scans are in `phase-3-tests.json`. Final logs are `/private/tmp/p3_<name>.log`; stdout copies are `/private/tmp/p3_<name>.stdout`. The pre-existing macOS certificate diagnostic (`get_system_ca_certificates`, `ret != noErr`) still occurs; it is an engine environment error, not a script/parse error or warning. All requested script/parse/warning scans are empty.
