# T-MINUS Planetary Empire & Flag Warfare

Phase A defines the shared match rules for a 32-seat, 16v16 game in Godot 4.7.2. Each coalition builds its planetary facilities, sends squads through the space corridor, and raids the opposing planet for Science Flags. Captured flags score when delivered to the carrier's own Command Flag Vault.

The simulation lives in `scripts/empire_sim.gd`. Phase A runs the complete match with AI squads. Stage 2 connects scene input, the lobby, HUD and tactical map, and the authoritative ENet session to these rules. Stage 3 gives each coalition a home spaceport on Planet A or Planet B. The live Frontier scene on PLANET C · MOON hosts Arena Clash and the existing playable flag raids. EmpireSim still attributes flag pools and facilities to their owning coalitions.

## Alliances and roster

| Alliance | Raider | Escort | Builder | Defender |
|---|---|---|---|---|
| Planet A Coalition (`planet_a`) | Orange, Your Squad (`kestrel`) | Cyan (`lancer`) | Violet (`hauler`) | Lime (`halo`) |
| Planet B Coalition (`planet_b`) | Crimson (`kestrel`) | Amber (`lancer`) | Obsidian (`hauler`) | Cobalt (`bulwark`) |

Each squad has four seats in this order.

| Seat | Specialist | Duties |
|---|---|---|
| Pilot | Finn | Launch and flight |
| Engineer | Chip | Construction, ship systems and repairs |
| Gunner | Barbara | Ship and ground fire support |
| Raider | Fernando | Flag extraction and structure sabotage |

The simulation tracks one ship and macro state per squad. Squad records include ID, alliance, the Orange player-squad marker, strategy, default ship family, and seat definitions. Live state includes location, phase, progress from 0 to 1, hull and maximum hull up to 100 HP, and carried flag IDs. Personal contribution counters track kills, captures, deliveries, builds and treasury credits earned from deliveries.

Location IDs are `planet_a`, `space_to_b`, `planet_b`, and `space_to_a`. Phase IDs are `build`, `outfit`, `flight`, `raid`, `defend`, and `return`. Space location names identify the leg's destination, so both coalitions can appear in either lane. Each leg's progress measures distance from that leg's origin.

## Match clock and acts

| Preset | Duration | Act II starts | Act III starts | Act IV starts |
|---|---|---|---|---|
| `standard` (default) | 40:00 | 08:00 | 18:00 | 32:00 |
| `short` | 15:00 | 03:00 | 06:45 | 12:00 |
| `classic` | 14:00 | 02:48 | 06:18 | 11:12 |

| Act | Elapsed fraction | Strategic changes |
|---|---|---|
| I · Foundation | 0–20% | Squads construct, outfit and defend at home. |
| II · Corridor Skirmish | 20–45% | Raider and Escort squads launch. Opposing ships exchange fire when they pass each other in the corridor. |
| III · Two-Way Invasion & Siege | 45–80% | Builder squads launch as well. They sabotage the active shield or the defense batteries before extracting. |
| IV · Overdrive Rush | 80–100% | Defender squads can launch. Two Golden Science Cores appear on each planet, and both alliances earn twice their passive income, including refinery bonuses. |

AI squads cycle through build, outfit, flight, raid, return and defend when their strategy can launch. They build or service facilities in strategy-specific priority order, pick higher-value flags first, and can recover space drops near their current leg progress. Damage stops at 1 HP and leaves the squad's phase, location, and cargo intact. AI ships repair during normal home defense. When players defeat all members of a ground raid, the raiding ship withdraws on its normal return leg.

The match defaults to seed `4209` and `standard` difficulty. Difficulty changes Planet B's AI travel time by +15% on `easy` or −15% on `hard`. Both sides use the same base facility stats, flag pools, scoring and initial treasuries.

## Empire slots and treasury

Each planet has the same six slots. Its Command Flag Vault starts at Tier 1. The other five slots start at Tier 0. Each successful purchase spends shared alliance credits, restores the structure to its new maximum HP, and increments the builder's contribution. Tiers cap at 3.

| Slot ID | Facility | Cost by tier | HP by tier | Effect |
|---|---|---|---|---|
| `defense_turrets` | Orbital Defense Batteries | 150 / 260 / 420 | 220 / 360 / 520 | 12 / 22 / 36 defense DPS against enemy raiders while they are exposed during the first and last second of a raid. |
| `shield_gen` | Planetary Shield Generator | 200 / 340 / 520 | 300 / 480 / 700 | Protects vault flags and blocks damage and sabotage to the vault and launch pads, represented by the hangar slot. |
| `refinery` | Resource Extractor & Refinery | 140 / 240 / 380 | 240 / 380 / 540 | Adds 6 / 12 / 20 credits per second while online. |
| `radar` | Deep-Space Radar Relay | 120 / 220 / 340 | 180 / 300 / 440 | Reveals enemy space traffic and flag carriers to the owning alliance while online. |
| `hangar` | Rapid Refit & Repair Hangar | 160 / 280 / 440 | 260 / 420 / 600 | Buildable and sabotageable launch-pad facility. |
| `vault` | Command Flag Vault | Built / 240 / 420 | 400 / 650 / 950 | Home delivery point. Delivery stays available during damage or sabotage. |

Both treasuries begin with 300 credits and gain 2 base credits per second. A facility is online at Tier 1 or higher with positive HP and an expired sabotage timer. Ordinary damage lowers HP. Sabotage lowers HP and disables the facility for 30 seconds once cumulative sabotage reaches 100 or HP hits zero. After a disable triggers, sabotage progress resets. An upgrade is blocked during the disable. Repair restores hull up to its maximum while the timer continues. Shields also restore 10 HP per second once the eight-second recharge delay and sabotage timer have elapsed. If shield HP is already positive, its protection resumes as soon as the sabotage timer expires.

### Scene assets

| Slot | GLB path under `assets/models/apogex/` |
|---|---|
| Defense batteries | North: `deployables/mothership_turret_battery.glb`. South on Planet A: `deployables/helion_defense_turret.glb`. South on Planet B: `deployables/cinder_defense_turret.glb`. |
| Shield generator | `deployables/deployable_shield_gen.glb` |
| Refinery | `surface/refinery_tower_cluster.glb` |
| Radar relay | `landmarks/relay_tower.glb` |
| Hangar | `surface/launch_service_tower.glb` |
| Command Flag Vault | `surface/extraction_spire_core.glb` |

## Objective and victory

Each planet starts with 16 one-point Science Flags. Twelve are on the surface and four are at the shield-protected vault. Act IV places two two-point Golden Science Cores on each surface. Flag IDs are `<planet>_flag_01` through `<planet>_flag_16` and `<planet>_gold_01` through `<planet>_gold_02`.

A squad can capture an available or dropped enemy flag on its current planet or in its directional space pool. A dropped flag stays in that pool, and space drops retain the carrier's leg progress. A drop can be captured again. A squad scores by delivering its carried flag at its own vault. Each delivery yields 120 alliance credits, including Golden Core deliveries. Delivered flags are spent for the match.

An alliance wins immediately at 20 points (`knockout`). At the time limit, the higher score wins (`timer`), and an equal score produces `draw`. The clock takes precedence over AI deliveries on the final step.

## Simulation and network contract

`EmpireSim` is a Godot `RefCounted`. Call `setup(seed_val, match_preset, difficulty)` before starting the clock. The host calls `tick(dt)` with time in seconds. The simulation advances in 0.25-second steps, retaining substep time and seeded RNG state so frame rate and snapshot restore preserve the same AI trajectory. Each squad has `ai_enabled` set by default. The scene controller can disable macro movement for squads under scene control while the simulation continues to apply shared world rules.

| API | Result |
|---|---|
| `can_upgrade(alliance, slot_id)` | Quote with `ok`, `reason`, `cost`, and `next_tier`. |
| `build_or_upgrade(alliance, slot_id, by_squad)` | Returns the quote and applies a successful upgrade. Construction is credited to a squad of the owning alliance. |
| `damage_structure(alliance, slot_id, amount, attacker_squad)`, `sabotage_structure(...)` | Return action status, with remaining HP and sabotage timer on success. A supplied attacker must belong to the opposing alliance. |
| `repair_structure(alliance, slot_id, amount, by_squad)` | Returns action status, with remaining HP, HP repaired, and sabotage timer on success. |
| `is_shield_active(alliance)`, `has_radar_intel(alliance)`, `get_defense_dps(alliance)` | Current effects of online facilities. |
| `damage_ship(squad_id, amount)`, `repel_raid(squad_id)` | Apply damage down to 1 HP or send a defeated ground raid on its return leg. |
| `record_flag_captured(squad_id, flag_id)`, `record_flag_delivered(squad_id, flag_id)` | Capture returns success. Delivery returns 0 for an invalid action, 1 for a Science Flag, or 2 for a Golden Core. |
| `record_flag_dropped(squad_id, flag_id)` | Releases carried cargo at its current location and progress. |
| `get_active_invaders(target_planet)`, `get_space_traffic()` | Copies of hostile raiders on the target and all current space traffic, respectively. Traffic includes faction, leg, progress, and carried IDs. |
| `get_hud_summary()` | Remaining clock, act number and name, Overdrive, scores, treasuries, structure tiers, flag counts by origin and state, invaders on A, allies on B, alliance radar contacts, winner, win reason, and the latest 80 events. |
| `to_snapshot()`, `from_snapshot(snap)` | Export an independent versioned state dictionary or restore a validated snapshot. An invalid snapshot returns `false` without changing live state. |

The host owns the clock and validates peer assignments and physical interaction range before calling the rules API. Peer readiness, identity, and the assignment of humans to seats belong to the session layer. Snapshots carry all eight squads and their 32 seats, structures, objectives, economy, scores, events, the current act and outcome, the substep accumulator, and the RNG state. Use Godot Variant serialization so the RNG state retains its 64-bit integer precision. The HUD and traffic queries provide copied data for presentation. Client-facing map views use the alliance's radar contacts to reveal opponents.

## Verification

The headless suite validates the roster, every tier of all six slots on both planets, shield protection and recharge, sabotage cooldowns, radar and defensive fire, surface and corridor drops, non-lethal hull damage, act boundaries, Overdrive, both victory conditions, and deterministic snapshot continuation through a full 40-minute AI match.

```bash
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path . --script tests/empire_sim_test.gd
```
