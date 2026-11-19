# T-MINUS / APOGEX — Godot 4.7 port

Godot recreation of the **offline crew match** from `TMINUS-Final-v` v5.7.0 (the web build's
"Competitive / Offline practice" mode): build on Planet A, capture Science Flags on Planet B, bring them home.

## Run

Open the folder in Godot 4.7, or:

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path ~/tminus-godot
```

## Modes

- **Single player campaign** — mission select → briefing → equipment design (budget, 850 kg launcher limit, power margin)
  → **workshop**: walk to the PARTS SHOP kiosk and press E to buy each piece. Machines do the assembly: robots frame the
  hull, the robot arm bolts each module on the jig, the pad crane stacks the core stage, both side boosters, the
  spacecraft and the fairing → board at the gantry elevator → preflight checks inside the ship → staged launch
  (liftoff, booster separation, core separation, orbit) → orbit mission (solar wings, autopilot, calibration,
  observations, eclipse circuit fault, downlink windows, return) → report. Mission 02 adds rendezvous and an EVA.
  Rules: `scripts/campaign.gd` (port of `campaign-core.js`). Progress saves to `user://campaign_progress.json`.
- **Competitive / offline practice** — the crew match below.
- **Mission design & science simulator** — Mission Control: pick objective, bus, array, battery, radio, payload,
  orbit, launcher, propellant, days and hours; live checks; run day by day with operations policies; chart and
  scored report. Rules: `scripts/mission_control.gd` (port of `engineering.js`).

Single-player controls: WASD move · E buy / operate · TAB next task at a station · mouse wheel and Q/F set dials ·
C crew command · X conservation mode · F5 time ×4 · during EVA Space up, Ctrl down.

## Match flow

Home → Assemble your crew (specialist, difficulty, length, hands-on/fast assembly) → Build manifest
(upgrades, design sheet, part assignments) → **BUILD** → **OUTFIT** → **ROUTE** → GO/NO-GO →
launch → **FLIGHT** → **PLANET B** → return flight → **DELIVER** → debrief.

Three AI rival crews (Cyan, Violet, Lime) race for the same 12 finite flags.
Only flags delivered to Planet A score.

## Offline crew match improvements

**Quick Deploy** in the crew lobby starts a paid, completed ship in flight and launches rivals at the same time. The full construction expedition remains available.

Planet B is now an editable three-lane research compound: Storage, Reactor, and Relay, connected by gates and flank routes. Barricades and walls block movement, cameras, and shots. Friendly and rival raiders use terrain-aware routes. The arena is `scenes/levels/FrontierArena.tscn`; cover meshes use `arena_cover` and `cover_size` metadata.

- **B** draws or holsters your firearm. Hands return to their idle animation when holstered. Draw/holster, recoil, and reload poses use the character's hand bone. First-person view has a separate arms model.
- **C** cycles Escort, Recover, and Regroup. **Z** marks a priority sample for Fernando. Recover also sends available crew after dropped samples.
- **M** opens the live tactical map, including cover and numbered sample locations. The match continues while it is open.
- Carbine, arc projector, and repeater have different damage and fire rates. Distance reduces damage; headshots multiply damage by 1.5. Shots stop at cover. Reload with **R**.
- Suits have independent health for each specialist, visible health bars, hit reactions, and a knockout/recovery sequence. Health regenerates after six seconds without damage, faster near Chip. Chip's Q restores nearby suits; Finn's Q boosts ground movement; Barbara's Q increases fire rate.
- A sample carrier moves more slowly. Departure is blocked while any teammate carries a sample. Empty departure requires a second T press.
- The HUD uses compact sample slots, large ammo counts, suit/system bars, contextual prompts, and a short mission advisor. **H** opens the full manual.
- Exhaust uses transparent animated shaders and particles anchored to the actual nozzles. Weapon impacts and explosions use short spark bursts.
- Debrief includes crew contributions and a same-seed rematch. Rival crews prioritize targets differently and receive a closing return window warning.

Additional validation:

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/crew_match_test.gd
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/crew_match_runtime_test.gd
```

## Controls

| Phase | Keys |
|---|---|
| Everywhere | WASD move · Shift sprint · Space jump · mouse look · V 1st/3rd person · 1–4 switch specialist · H manual · Esc pause |
| Build | E pick up module at your rack (costs credits) · R rotate until the ghost turns green · E set in slot · hold LMB on 3 bolts |
| Outfit | E carry supply case → E stow at aft hatch · checks: wheel or Q/F set reading, hold LMB inside the GO band |
| Flight | 1 Pilot: WASD dodge, Q afterburner · 2 Engineer: W/S system, hold LMB service, wheel reactor · 3 Gunner: mouse aim, LMB turret · 4 Raider: W/S plate, E remove, hold LMB fit spare · F ultimate |
| Planet B | Raider: hold LMB facing a flag (scan → stabilize → extract, 5 s) · E recover/load at ramp · G drop · T depart · others: B draw/holster, LMB blaster, R reload (stunned rivals drop flags) |
| Deliver | Hold E on the delivery pad · F5 fast-forward once finished |

## Layout

| File | Role |
|---|---|
| `scripts/sim.gd` | Offline crew rules, adapted from `expedition-core.js` + `science-match.js` (parts, credits, bolts, cargo, checks, route Δv budget, flight systems/faults, flag pool, rival AI, scoring, debrief) |
| `scripts/main.gd` | Flow, menus, input, camera, cinematics, audio |
| `scripts/planet_a.gd` | Pad, racks, cargo, consoles, delivery pad, rival pads, crew bots, menu hangar |
| `scripts/flight.gd` | Debris, raider drones, turret, systems, hull plates |
| `scripts/planet_b.gd` | Flag sites, scanning, rival raiders, blasters, departure |
| `scripts/campaign.gd`, `workshop.gd`, `orbit_ship.gd` | Single-player rules, workshop + launch pad + launch cinematic, ship interior mission |
| `scripts/mission_control.gd` | Mission Control simulator rules (UI is in `main.gd`) |
| `scripts/hud.gd`, `ui.gd` | APOGEX HUD + UI kit |
| `scripts/actor.gd`, `ship.gd`, `gfx.gd` | Characters, the Kestrel ship, procedural low-poly helpers |
| `assets/` | Original GLB characters/props/weapons and Kenney audio from the web build |

## Tests

```bash
# Rules only (headless)
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path ~/tminus-godot -s tests/sim_test.gd
```

```bash
# Single-player rules + simulator (headless)
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path ~/tminus-godot -s tests/sp_test.gd
```

```bash
# Single-player scripted playthrough (workshop → launch → orbit → report → simulator)
~/Downloads/Godot.app/Contents/MacOS/Godot --path ~/tminus-godot -- --autotest-sp
```

```bash
# Full scripted playthrough with screenshots in shots/
~/Downloads/Godot.app/Contents/MacOS/Godot --path ~/tminus-godot -- --autotest
```

## Not ported

Online multiplayer (expedition server, accounts) and campaign chapters 03–09 (not playable in the web build either).

## Visual editing upgrade

The new `scenes/levels/` and `scenes/prefabs/` directories contain **real, editable `.tscn` scenes**, and the runtime GDScript now instantiates them for the launch spaceport, Planet B, workshop, interior, flight background, Kestrel spacecraft, and scan flags. See **[EDITABLE_SCENES_GUIDE.md](EDITABLE_SCENES_GUIDE.md)** for the file-by-file instructions, caveats, collision marker workflow, and testing command.

Export note: when creating export_presets.cfg, exclude the editor-only godot_ai tooling and _mcp_game_helper autoload from release builds as appropriate. Keep both available in the development project.
