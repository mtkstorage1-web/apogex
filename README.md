# T-MINUS / APOGEX

T-MINUS is a Godot 4.7 game spanning two Earth spaceports, a shared space map, and a Moon arena.

## Play

1. Start **Arena Clash**, the default lobby mode. Choose a coalition and build on its home planet. At the Parts Shop, order a **reactor**, **engine**, and **bridge**. Extra modules improve combat health, shield, damage, or respawn time.
2. Walk beside the cockpit and press **E** when the ship is flight-capable. The crew boards with you. Tap **Space** for a short vertical lift or hold it to climb. Release it to hover and hold **W** to tilt the nacelles forward and accelerate.
3. Climb past **650 m** to enter space. Planet markers and distances help you navigate to any world. Press **L** when the landing prompt appears.
4. You arrive above the destination's landing zone with flight controls. Fly down to the terrain or press **L** again once you are low and close to the pad for auto-touchdown. The ship stops without touchdown damage. Press **E** when stopped to walk, or board again at the cockpit.
5. Fight on **Planet C · Moon**. Squads join combat as they land. After an elimination, the player respawns at their coalition's arena spawn. The match clock runs from the start. Standard is 8 minutes or 60 eliminations, and Short is 4 minutes or 30 eliminations. The higher score wins at time, with a draw for equal scores.

| World | Landing zone |
|---|---|
| Planet A · Earth | Home pad for Orange, Cyan, Violet, and Lime |
| Planet B | Earth twin and home pad for Crimson, Amber, Obsidian, and Cobalt |
| Planet C · Moon | Coalition landing bays beside the Frontier Arena |

Quick Deploy, where offered in the lobby, starts with the pilot seated in a flight-capable ship on the home pad.

## Controls

| Action | Keyboard and mouse | Touch |
|---|---|---|
| Walk and look | WASD and mouse | Move stick and drag |
| Board or exit a stopped ship | E | Tap the prompt |
| Forward thrust / brake and slow reverse | Hold W / S | Stick forward / back |
| Steer | Mouse pitch and yaw. Left/Right arrows yaw when the cursor is free | Drag to pitch and yaw |
| Roll | Hold A / D | Stick left / right |
| Boost forward | Hold Shift with W | Hold BOOST with the stick forward |
| Lift / descend | Tap or hold Space / hold Ctrl or C | Tap or hold LIFT / hold DOWN |
| Request landing or auto-touchdown | L when prompted | Land or tap the prompt |
| Ground combat | B draw or holster, left click fire, R reload, V view | Gun, Fire, Reload, View |
| Menu | Esc | Menu button |

**W FORWARD · S BRAKE/REVERSE · A/D ROLL · MOUSE STEER · SPACE LIFT · CTRL DOWN · SHIFT BOOST · L LAND · E EXIT**

Holding **S** brakes to a stop, then engages slow reverse. Surface roll is limited to 60° and levels when released. Space roll can turn through a full 360° and holds its angle until landing. Surface lift and descent follow world up. In space they follow the ship’s rolled up axis. Release lift or descent on a surface with no forward input to hold altitude.

Space cruise reaches 4,800 m/s and boost reaches 6,200 m/s. Approach limits reduce speed near terrain and planets.

## Other modes

- **Competitive / offline practice** keeps the Science Flag crew match. The Raider extracts flags on the Moon. Load them at the ship with **E**, fly home, then hold **E** at the delivery pad to score. **C** changes crew orders, **Z** marks a priority flag, and **M** opens the tactical map.
- **Planetary Empire & Flag Warfare** keeps the strategic rules, facility terminals, Moon vault sabotage, home delivery, and ENet lobby. Only home delivery scores. The Standard match runs for 40 minutes or until an alliance scores 20 points. Overdrive introduces two-point Golden Science Cores and doubles passive treasury income. Its AI still simulates rival construction, travel, raids, and returns. [Game plan](docs/MULTIPLAYER_EMPIRE_GAME_PLAN.md)
- In the flag modes, **I** or **Tab** opens the walkable cabin in space. Crew can service ship systems while the ship holds its course.
- **Mission Control** is a separate design and science simulator with mission budgets, operations policies, and a scored report.

The Moon uses the editable three-lane compound in `scenes/levels/FrontierArena.tscn`. Barricades and walls block movement, cameras, and shots. Cover meshes use `arena_cover` and `cover_size` metadata. Field weapons have distinct damage and fire rates. Suits track health per specialist, and ship hull damage stops at 1 HP.

## Run and test

Open the folder in Godot 4.7 or run these commands from the project root.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path .
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/open_world_flight_test.gd
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/run_empire_suite.gd
```

## Visual editing upgrade

The new `scenes/levels/` and `scenes/prefabs/` directories contain **real, editable `.tscn` scenes**, and the runtime GDScript now instantiates them for both home spaceports, Planet C, the Kestrel spacecraft, and Science Flags. See **[EDITABLE_SCENES_GUIDE.md](EDITABLE_SCENES_GUIDE.md)** for the file-by-file instructions, caveats, collision marker workflow, and testing command.

Export note: when creating export_presets.cfg, exclude the editor-only godot_ai tooling and _mcp_game_helper autoload from release builds as appropriate. Keep both available in the development project.
