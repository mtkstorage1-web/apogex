# T-MINUS — Visually editable Godot 4 scenes

This is an **edit-ready conversion** of the supplied Godot 4.7 project. Previously the game had one almost-empty `main.tscn`: most 3D objects were created from `Gfx.*` functions inside `setup()` calls. The scenery and several major gameplay props now live in `.tscn` files and are **instantiated by the real game scripts**.

## Open the project

1. Extract the ZIP.
2. Open **Godot 4.7** (the original project's requested version).
3. Select **Import**, choose `tminus-godot/project.godot`, and let the 3D assets import.
4. Open the scene you want in the **FileSystem** dock, e.g. `scenes/levels/PlanetAEnvironment.tscn`.
5. Expand the Scene dock: select an object, use W/E/R to move/rotate/scale, or edit properties in the Inspector. In Godot's 3D editor, use **F** to frame a selected object.
6. **Save** the `.tscn`, then **Run Project (F6/F5 as appropriate)** to see the revised objects during gameplay. The game still starts from `main.tscn`.

## The new edit-ready scenes

| Scene | Edit visually | Used in gameplay |
|---|---|---|
| `scenes/levels/PlanetAEnvironment.tscn` | Ground, rocks, planets, pad, gantry, four racks, three console props, delivery pad, rival pad surfaces, sun, sky | **Yes**, built in `PlanetA.setup()` |
| `scenes/levels/PlanetBEnvironment.tscn` | Planet B terrain/rocks, sky, lights, planet backdrop, four landing pads, load ramp | **Yes**, built in `PlanetB.setup()` |
| `scenes/levels/WorkshopEnvironment.tscn` | Ground, ocean, workshop building, kiosk, assembly jig, articulated robot arm, crane hook/cable, gantry/elevator | **Yes**, built in `Workshop.setup()` |
| `scenes/levels/OrbitShipInterior.tscn` | Imported ship interior, room lights, six consoles, objective circles and labels | **Yes**, built in `OrbitShip.setup()` |
| `scenes/levels/FlightEnvironment.tscn` | Space sky, lights, red planet, destination planet | **Yes**, built in `Flight.setup()` |
| `scenes/prefabs/Kestrel.tscn` | 12 individual ship components and 4 landing legs/feet | **Yes**, through `ShipModel.full()`; also the build-stage rocket |
| `scenes/prefabs/FlagMarker.tscn` | Flag crystal, pedestal, scanner ring, pole, banner, label | **Yes**, instantiated once per flag on Planet B |
| `main.tscn` | Main game root and **GameCamera** | **Yes** |

## What to edit first

**Change the launch gantry:** Open `PlanetAEnvironment.tscn` → expand `LaunchPad/Gantry` → select a post or arm → move it. If moving a post, edit its corresponding marker under `CollisionFootprints` too.

**Fix an invisible barrier:** Open `WorkshopEnvironment.tscn` or `PlanetAEnvironment.tscn` → expand `CollisionFootprints` → select a `Marker3D` → change its *Position* or its metadata `footprint` (Vector2: width × depth). The existing custom 2D-footprint collision routines read these values on loading. These footprints are not full `StaticBody3D` physics colliders.

**Fix a Planet B rock collision:** In `PlanetBEnvironment.tscn`, expand `Terrain/TerrainRocks`. Rocks with a `gameplay_radius` metadata field block characters. Move the rock to move its blocking circle; modify or remove the metadata to adjust/remove blocking.

**Edit spacecraft parts:** Open `Kestrel.tscn`. Each gameplay component has the same ID as `Sim.PARTS_DEF` (e.g. `keel`, `port`, `bridge`, `reactor`). You can edit its mesh, colors and detail. The mission simulator still controls each component's stage, availability and assembly state. Avoid deleting or renaming the 12 top-level part nodes, because build progression expects those names.

**Fix the robot arm:** Open `WorkshopEnvironment.tscn` → `WorkshopBuilding/RobotArmPivot`, `RobotArmTip`, `LaunchPad/CraneHook`, `CraneCable`. The launch/workshop code animates those scene nodes.

**Edit interactive ship consoles:** Open `OrbitShipInterior.tscn` → `Stations` and move a room's console root. The game reads each station root's new position for proximity interactions, HUD indicators and beacon positioning. Keep the station root names and `ObjectiveRing`/`StationLabel` children intact.

**Edit the camera:** Open `main.tscn` → `GameCamera`. The project starts from this camera. Beware: gameplay continuously moves/rotates the camera using `main.gd`, so changes to its position will usually be overridden; you can adjust its FOV/far clipping.

## Important remaining limitations

- This is **not** a fully visual/no-code game. The rules, crew navigation, timed missions, AI rivals, combat, dynamic rocket construction, UI, procedural debris and flight control remain written in GDScript. This is intentional: they need runtime state.
- Many interaction locations are **still controlled by constants** (`Sim.RACKS`, `Sim.FLAG_SITES`, `Workshop.KIOSK`, `Workshop.JIG`, etc.). Moving only the corresponding scenery mesh will **not** relocate the associated gameplay target. Keep interactive scene placements at their original positions or update these constants in tandem. The exception is the orbit interior station roots, which were rewired to the edited positions.
- The rocky terrain uses **editor-editable low-poly mesh approximations**, rather than reproducing the exact jittered vertices and pseudorandom positions of the original procedural `Gfx.rock()` output. The original palette, scale and placement style are retained, but the rock silhouettes are not pixel-identical to the supplied screenshots.
- `Kestrel.tscn` contains editable approximations of the original generated 12-part ship, based on `Sim.PARTS_DEF` and `ShipModel.part_mesh`. Flight and rival ships use the shared prefab now. Physics/assembly module positions are still driven by `Sim.PARTS_DEF`; moving an entire ship part in the scene can visually separate it from the assembly placement marker.
- `OrbitShip` sky is built at runtime to distinguish **on-pad** from **in-orbit** conditions. The scene contains the editable room interior and lights; the outside Earth, clouds and EVA objects are still runtime-generated.
- Online multiplayer and unfinished campaign chapters were already unported in the **original** Godot ZIP. This scene conversion does not add them.

## Verify on your own computer

This environment does not have the Godot engine executable, so I could not launch the editor, import assets or run end-to-end gameplay tests. I checked scene syntax structure, local asset references, and connected scene-node paths. **Test the revised project in Godot 4.7** before using it as a production build.

You can perform a quick scene-loading test with:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /path/to/tminus-godot -s tests/editable_scene_test.gd
```

Then run the included rule tests (`tests/sim_test.gd`, `tests/sp_test.gd`) and play through the campaign/competitive match. Use the same Godot executable path that works on your Mac; the `/Applications` example may differ from your installation.
