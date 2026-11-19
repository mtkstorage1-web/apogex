# Ship variants: Part B handoff

Implemented in `scripts/ship_catalog.gd` and `scripts/sim.gd`, with gameplay multipliers in `flight.gd` and `planet_b.gd`. Prefabs, tools, shop UI, main UI, and visuals were not edited.

## Balance

All-family designs at 1x (including set bonuses, before optional upgrades):

| Family | Credits | Wet kg | Thrust kN | TWR | Fuel kg | Delta-v m/s | Flags | Damage taken | Turret | Scan | Handling |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Kestrel | 3060 | 750 | 10.4 | 1.414 | 80 | 398.2 | 6 | 1.00 | 1.00 | 1.00 | 1.00 |
| Lancer | 1989 | 641 | 13.6 | 2.164 | 67 | 389.8 | 4 | 1.15 | 0.90 | 1.15 | 1.33 |
| Hauler | 2551 | 954 | 9.2 | 0.983 | 140 | 560.3 | 13 | 1.05 | 0.80 | 0.88 | 0.88 |
| Halo | 5508 | 825 | 9.6 | 1.187 | 107 | 662.1 | 7 | 1.08 | 1.10 | 1.53 | 1.08 |
| Bulwark | 5355 | 962 | 11.4 | 1.208 | 76 | 290.5 | 5 | 0.48 | 1.65 | 1.10 | 0.94 |

Lancer buys speed with reduced cargo, reserves, cooling, life support and protection. Hauler buys capacity and endurance with mass and low acceleration (the existing slow-climb fuel penalty still applies). Halo maximizes endurance, generation, battery and scanning at a premium price. Bulwark trades mass, cargo and range for protection and turret output. Kestrel retains the exact original prices, stats, route budgets and neutral multipliers.

The cheapest slot-by-slot set costs 1978 (Lancer except Hauler keel); the most expensive set costs 5508. Both full premium families exceed the 4800 starting budget. No slot variant Pareto-dominates another when price, mass, electrical draw and all performance deltas are considered. Set bonuses activate once at three parts: Lancer +0.05 handling; Hauler +1 flag; Halo +0.03 exhaust multiplier; Bulwark -0.03 damage multiplier. Kestrel stays neutral for compatibility. Multiplier deltas add to 1.0, rather than compounding. Lower armor values mean less damage taken.

## Part C API

- `ShipCatalog.FAMILIES[family_id]`: id, name/display_name, tagline, color/colour, prefab_path. Kestrel points to `res://scenes/prefabs/Kestrel.tscn`; other families point to `res://scenes/prefabs/ships/<id>.tscn`.
- `ShipCatalog.VARIANTS[slot_id][family_id]`: immutable catalog data. `variant(slot, family)` returns a deep copy, or `{}` for invalid ids. Slots `engine` and `thruster` retain their legacy meanings: dorsal turret and starboard propulsion respectively.
- `default_loadout()` returns a fresh dictionary with all twelve slots set to Kestrel. `loadout_cost(loadout)` and `loadout_stats(loadout)` preview any mixture. Missing/null/invalid selections preview as Kestrel.
- Aggregated keys: `mass_kg` (dry), `wet_mass`/`total_mass` (dry + fuel), `fuel`, `thrust_kn`, `gen_kw`, `load_kw`, `power_margin`, `cargo_capacity`, `battery_kwh`, `radiator`, `life`, `exhaust_mult`, `exhaust`, `armor`, `turret_damage_mult`, `scan_mult`, `handling`, `twr`, `dv`, `cost`, `dominant_family`, `design_name`, `synergy`. These previews exclude optional upgrades. Family ties use FAMILIES iteration order.
- `sim.loadout[slot_id]` is the selected family id. Default choices are Kestrel; `purchased` remains separate on `sim.parts`. Use `set_variant(slot_id, family_id)` to confirm and purchase. Initial confirmation charges full price; purchased shelf swaps charge/refund only the price difference. Failure leaves state unchanged. Choices lock when auto-build is enabled or any manual assembly begins. Check the boolean result before updating the picker.
- `sim.part_price(slot_id)` and each live part's `price` expose the chosen price; `PARTS_DEF.price` remains baseline metadata. `buy_part()`, reserved credits, manual assembly and auto-build use variant prices. Auto-build confirms absent selections as Kestrel. `all_parts_bought()` requires a confirmed purchased selection in every slot.
- `sim.design_sheet()` retains all original keys and adds name, family, synergy, cost, armor, turret, scan, handling and exhaust. Existing upgrades stack with variant stats. Exposed gameplay variables: `armor_mult`, `turret_mult`, `scan_mult`, `handling_mult`, `thrust_kn`, `generation_kw`, `load_kw`, `exhaust_velocity`, `radiator_mult`, `life_mult`.
- For custom save/restore, persist `loadout` as a plain dictionary. On a fresh Sim, assign the restored loadout and call `refresh_loadout()` **before** restoring runtime quantities such as fuel and wet mass. Repeated refreshes are idempotent and preserve upgrade effects and spent fuel. There was no Sim save-file schema to migrate; existing campaign persistence is unchanged.
- Rival teams expose `teams[i].loadout` and `teams[i].stats`. They use a separate seeded RNG, preserving the gameplay RNG sequence. Their capacity, scan rate and travel duration use their design stats. Part C can assemble rival ships from these same dictionaries.
- For 3D assembly, look up each slot's family in the loadout, then resolve that family's prefab_path; use existing slot ids to match modules. Prefab creation and visual assembly remain outside Part B.

## Catalog

Numbers below are baseline deltas except prices. Exhaust, armor, turret, scan, handling, radiator and life percentages are additive multiplier deltas. Kestrel has zero deltas.

| Slot | Family | Name | Credits | Stat deltas |
|---|---|---|---:|---|
| keel | kestrel | Kestrel Standard Pressure Keel | 220 | +0 kg dry mass |
| keel | lancer | Lancer Needle Pressure Keel | 143 | -8 kg dry mass, -8 kg fuel, +15% damage taken |
| keel | hauler | Hauler Atlas Pressure Keel | 132 | +12 kg dry mass, +35 kg fuel, +5% damage taken |
| keel | halo | Halo Farstar Pressure Keel | 396 | +4 kg dry mass, +15 kg fuel, +8% damage taken |
| keel | bulwark | Bulwark Bastion Pressure Keel | 385 | +18 kg dry mass, -4 kg fuel, -22% damage taken |
| port | kestrel | Kestrel Standard Vector Drive | 180 | +0 kg dry mass |
| port | lancer | Lancer Needle Vector Drive | 117 | -8 kg dry mass, +1.6 kN thrust, +0.25 kW draw |
| port | hauler | Hauler Atlas Vector Drive | 140 | +12 kg dry mass, -0.6 kN thrust, -0.15 kW draw |
| port | halo | Halo Farstar Vector Drive | 324 | +4 kg dry mass, -0.4 kN thrust, -0.1 kW draw, +16% exhaust velocity |
| port | bulwark | Bulwark Bastion Vector Drive | 315 | +18 kg dry mass, +0.5 kN thrust, +0.4 kW draw, -3% damage taken |
| bridge | kestrel | Kestrel Standard Navigator | 300 | +0 kg dry mass |
| bridge | lancer | Lancer Needle Navigator | 195 | -8 kg dry mass, +0.15 kW draw, +28% handling |
| bridge | hauler | Hauler Atlas Navigator | 234 | +12 kg dry mass, -0.15 kW draw, -12% handling |
| bridge | halo | Halo Farstar Navigator | 540 | +4 kg dry mass, +8% scan speed, +8% handling |
| bridge | bulwark | Bulwark Bastion Navigator | 525 | +18 kg dry mass, -6% damage taken, -6% handling |
| reactor | kestrel | Kestrel Standard Bus Core | 400 | +0 kg dry mass |
| reactor | lancer | Lancer Needle Bus Core | 260 | -8 kg dry mass, -0.8 kW generation, -0.1 kW draw |
| reactor | hauler | Hauler Atlas Bus Core | 312 | +12 kg dry mass, +1 kW generation, +0.3 kW draw |
| reactor | halo | Halo Farstar Bus Core | 720 | +4 kg dry mass, +4 kW generation, +0.15 kW draw |
| reactor | bulwark | Bulwark Bastion Bus Core | 700 | +18 kg dry mass, +2 kW generation, +0.6 kW draw |
| battery | kestrel | Kestrel Standard Cell Bank | 280 | +0 kg dry mass |
| battery | lancer | Lancer Needle Cell Bank | 182 | -8 kg dry mass, -0.1 kW draw, -1.2 kWh battery |
| battery | hauler | Hauler Atlas Cell Bank | 218 | +12 kg dry mass, +0.1 kW draw, +1 kWh battery |
| battery | halo | Halo Farstar Cell Bank | 504 | +4 kg dry mass, -0.15 kW draw, +4 kWh battery |
| battery | bulwark | Bulwark Bastion Cell Bank | 490 | +18 kg dry mass, +0.2 kW draw, +2 kWh battery |
| coolant | kestrel | Kestrel Standard Heat Wing | 240 | +0 kg dry mass |
| coolant | lancer | Lancer Needle Heat Wing | 156 | -8 kg dry mass, -0.1 kW draw, -15% cooling |
| coolant | hauler | Hauler Atlas Heat Wing | 187 | +12 kg dry mass, +0.1 kW draw, +10% cooling |
| coolant | halo | Halo Farstar Heat Wing | 432 | +4 kg dry mass, +0.1 kW draw, +40% cooling |
| coolant | bulwark | Bulwark Bastion Heat Wing | 420 | +18 kg dry mass, +0.2 kW draw, +25% cooling |
| cargo | kestrel | Kestrel Standard Sample Rack | 200 | +0 kg dry mass |
| cargo | lancer | Lancer Needle Sample Rack | 130 | -8 kg dry mass, -0.1 kW draw, -2  flag capacity |
| cargo | hauler | Hauler Atlas Sample Rack | 360 | +12 kg dry mass, +0.3 kW draw, +6  flag capacity |
| cargo | halo | Halo Farstar Sample Rack | 360 | +4 kg dry mass, -0.05 kW draw, +1  flag capacity |
| cargo | bulwark | Bulwark Bastion Sample Rack | 350 | +18 kg dry mass, -1  flag capacity, -8% damage taken |
| scrubber | kestrel | Kestrel Standard Breather | 260 | +0 kg dry mass |
| scrubber | lancer | Lancer Needle Breather | 169 | -8 kg dry mass, -0.15 kW draw, -15% life resilience |
| scrubber | hauler | Hauler Atlas Breather | 203 | +12 kg dry mass, +0.1 kW draw, +10% life resilience |
| scrubber | halo | Halo Farstar Breather | 468 | +4 kg dry mass, -0.1 kW draw, +40% life resilience |
| scrubber | bulwark | Bulwark Bastion Breather | 455 | +18 kg dry mass, +0.2 kW draw, +20% life resilience |
| stores | kestrel | Kestrel Standard Trail Stores | 120 | +0 kg dry mass |
| stores | lancer | Lancer Needle Trail Stores | 78 | -8 kg dry mass, -5 kg fuel, -10% life resilience |
| stores | hauler | Hauler Atlas Trail Stores | 94 | +12 kg dry mass, +25 kg fuel, +10% life resilience |
| stores | halo | Halo Farstar Trail Stores | 216 | +4 kg dry mass, +12 kg fuel, +30% life resilience |
| stores | bulwark | Bulwark Bastion Trail Stores | 210 | +18 kg dry mass, +20% life resilience, -4% damage taken |
| engine | kestrel | Kestrel Standard Dorsal Cannon | 360 | +0 kg dry mass |
| engine | lancer | Lancer Needle Dorsal Cannon | 234 | -8 kg dry mass, -0.2 kW draw, -10% turret output |
| engine | hauler | Hauler Atlas Dorsal Cannon | 281 | +12 kg dry mass, -0.3 kW draw, -20% turret output |
| engine | halo | Halo Farstar Dorsal Cannon | 648 | +4 kg dry mass, -0.1 kW draw, +10% turret output |
| engine | bulwark | Bulwark Bastion Dorsal Cannon | 630 | +18 kg dry mass, +0.8 kW draw, +65% turret output |
| thruster | kestrel | Kestrel Standard Impulse Drive | 300 | +0 kg dry mass |
| thruster | lancer | Lancer Needle Impulse Drive | 195 | -8 kg dry mass, +1.6 kN thrust, +0.25 kW draw |
| thruster | hauler | Hauler Atlas Impulse Drive | 234 | +12 kg dry mass, -0.6 kN thrust, -0.15 kW draw |
| thruster | halo | Halo Farstar Impulse Drive | 540 | +4 kg dry mass, -0.4 kN thrust, -0.1 kW draw, +16% exhaust velocity |
| thruster | bulwark | Bulwark Bastion Impulse Drive | 525 | +18 kg dry mass, +0.5 kN thrust, +0.4 kW draw, -3% damage taken |
| antenna | kestrel | Kestrel Standard Signal Crown | 200 | +0 kg dry mass |
| antenna | lancer | Lancer Needle Signal Crown | 130 | -8 kg dry mass, +0.1 kW draw, +15% scan speed |
| antenna | hauler | Hauler Atlas Signal Crown | 156 | +12 kg dry mass, -0.15 kW draw, -12% scan speed |
| antenna | halo | Halo Farstar Signal Crown | 360 | +4 kg dry mass, +0.15 kW draw, +45% scan speed |
| antenna | bulwark | Bulwark Bastion Signal Crown | 350 | +18 kg dry mass, -3% damage taken, +10% scan speed |

## Verification

Ran with Godot 4.7.2 headless using `--path . --script <file>`:

| Check | Result |
|---|---|
| tests/ship_catalog_test.gd | PASS |
| tests/sim_test.gd | PASS |
| tests/sp_test.gd | PASS |
| tests/crew_match_test.gd | PASS |
| tests/crew_match_runtime_test.gd | PASS |
| tests/editable_scene_test.gd | PASS |
| tests/pad_sequence_runtime_test.gd | PASS |
| tools/check_hardware_runtime.gd | PASS |

All eight exited 0 with no script errors. The catalog suite covers all 60 unique variants, all 240 directed pairwise dominance comparisons, original prices/masses/TWR/delta-v/route budgets, mixed design stats, price bounds, purchase/refund/charge/failure paths, build locking, unset-choice auto-build, damage mitigation, battery/exhaust effects, upgrade stacking, idempotent refresh, fuel preservation, JSON loadout round trips and deterministic rivals.
