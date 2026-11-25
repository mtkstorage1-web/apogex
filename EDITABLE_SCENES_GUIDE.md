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
| `scenes/levels/PlanetAEnvironment.tscn` | Terrain, launch and rival pads, gantry, racks, consoles, delivery pad, parts shop, cranes, spaceport campus, Empire districts and raid landing zones | **Yes**, loaded by `PlanetA.setup()` |
| `scenes/levels/PlanetBEnvironment.tscn` | PLANET C · MOON terrain/rocks, sky, lights, planet backdrop, four landing pads, load ramp | **Yes**, built in `PlanetB.setup()` |
| `scenes/levels/WorkshopEnvironment.tscn` | Ground, ocean, workshop building, kiosk, assembly jig, articulated robot arm, crane hook/cable, gantry/elevator | **Yes**, built in `Workshop.setup()` |
| `scenes/levels/OrbitShipInterior.tscn` | Imported ship interior, room lights, six consoles, objective circles and labels | **Yes**, built in `OrbitShip.setup()` |
| `scenes/levels/FlightEnvironment.tscn` | Space sky, lights, red planet, destination planet | **Yes**, built in `Flight.setup()` |
| `scenes/prefabs/Kestrel.tscn` | 12 individual ship components and 4 landing legs/feet | **Yes**, through `ShipModel.full()`; also the build-stage rocket |
| `scenes/prefabs/FlagMarker.tscn` | Flag crystal, pedestal, scanner ring, pole, banner, label | **Yes**, instantiated once per flag on PLANET C · MOON |
| `main.tscn` | Main game root and **GameCamera** | **Yes** |

## What to edit first

**Change the launch gantry:** Open `PlanetAEnvironment.tscn` → expand `LaunchPad/Gantry` → select a post or arm → move it. If moving a post, edit its corresponding marker under `CollisionFootprints` too.

**Fix an invisible barrier:** Open `WorkshopEnvironment.tscn` or `PlanetAEnvironment.tscn` → expand `CollisionFootprints` → select a `Marker3D` → change its *Position* or its metadata `footprint` (Vector2: width × depth). The existing custom 2D-footprint collision routines read these values on loading. These footprints are not full `StaticBody3D` physics colliders.

**Fix a PLANET C · MOON rock collision:** In `PlanetBEnvironment.tscn`, expand `Terrain/TerrainRocks`. Rocks with a `gameplay_radius` metadata field block characters. Move the rock to move its blocking circle; modify or remove the metadata to adjust/remove blocking.

**Edit spacecraft parts:** Open `Kestrel.tscn`. Each gameplay component has the same ID as `Sim.PARTS_DEF` (e.g. `keel`, `port`, `bridge`, `reactor`). You can edit its mesh, colors and detail. The mission simulator still controls each component's stage, availability and assembly state. Avoid deleting or renaming the 12 top-level part nodes, because build progression expects those names.

**Fix the robot arm:** Open `WorkshopEnvironment.tscn` → `WorkshopBuilding/RobotArmPivot`, `RobotArmTip`, `LaunchPad/CraneHook`, `CraneCable`. The launch/workshop code animates those scene nodes.

**Edit interactive ship consoles:** Open `OrbitShipInterior.tscn` → `Stations` and move a room's console root. The game reads each station root's new position for proximity interactions, HUD indicators and beacon positioning. Keep the station root names and `ObjectiveRing`/`StationLabel` children intact.

**Edit the camera:** Open `main.tscn` → `GameCamera`. The project starts from this camera. Beware: gameplay continuously moves/rotates the camera using `main.gd`, so changes to its position will usually be overridden; you can adjust its FOV/far clipping.

## Editing Planet A Spaceport & Empire Districts

1. Open `res://scenes/levels/PlanetAEnvironment.tscn` in Godot and switch to the **3D** view. All paths below are relative to the `PlanetAEnvironment` root in the Scene dock.
2. Select the node you want to move, then drag its move gizmo in the viewport. Select an Empire slot such as `EmpireDistricts/refinery` to move its foundation, building, and `E` terminal together. Select `EmpireDistricts/refinery/Terminal` to reposition that kiosk and its interaction point independently.
3. Press **Cmd+S**. The game reads the saved layout when it loads Planet A. Buildings and turrets follow their slots, the shield dome follows `EmpireDistricts/vault`, and incoming raids land at the saved raid markers.

| What to move | Scene Tree paths |
|---|---|
| Allied towers | `SpaceportCampus/AlliedTower_NW`, `SpaceportCampus/AlliedTower_NE`, `SpaceportCampus/AlliedTower_N` |
| Tank farm and motor pool | `SpaceportCampus/TankFarm`, `SpaceportCampus/FleetMotorPool` |
| Parked vehicles | `SpaceportCampus/FleetMotorPool/ParkedDropship`, `SpaceportCampus/FleetMotorPool/ParkedRover` |
| Roads | `SpaceportCampus/WestAvenue`, `SpaceportCampus/WestTrunkRoad`, `SpaceportCampus/EastAvenue`, `SpaceportCampus/EastTrunkRoad` |
| Empire slots | `EmpireDistricts/defense_turrets`, `EmpireDistricts/shield_gen`, `EmpireDistricts/refinery`, `EmpireDistricts/radar`, `EmpireDistricts/hangar`, `EmpireDistricts/vault`. Each slot has `FoundationPad` and `Terminal` children. |
| Raid landing zones | `EmpireDistricts/RaidLandingZones/RaidZone0`, `EmpireDistricts/RaidLandingZones/RaidZone1`, `EmpireDistricts/RaidLandingZones/RaidZone2`, `EmpireDistricts/RaidLandingZones/RaidZone3` |
| Parts shop and rival pads | `Buildings/PartsShop`, `RivalLandingPads/Rival1Pad`, `RivalLandingPads/Rival2Pad`, `RivalLandingPads/Rival3Pad` |
| Cranes and ground support | `Cranes/Pedestals`, `Cranes/Elevators`, `Cranes/Conveyors`, `Cranes/PickupBays`, `Cranes/ScannerArches` |
| Infrastructure and terrain | `Infrastructure/Fence`, `Terrain/Ground`, `Terrain/Rocks`, `Terrain/RoadMarkings` |

**Keep your edits.** Avoid running `tools/bake_planet_a_scene.gd -- --force` after hand-editing. The forced bake resets the layout to defaults.

## Important remaining limitations

- This is **not** a fully visual/no-code game. The rules, crew navigation, timed missions, AI rivals, combat, dynamic rocket construction, UI, procedural debris and flight control remain written in GDScript. This is intentional: they need runtime state.
- Some interaction locations are still controlled by constants, including `Sim.FLAG_SITES`. For Planet A and ship interior interactions that read scene positions, move the named slot, terminal, station, or marker node to relocate the gameplay point.
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
