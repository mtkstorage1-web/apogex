# Parts Shop Redesign (`scripts/ship_builder.gd`)

Modern web-storefront restyle of the whole-ship parts shop while preserving all public methods, state, and runtime behavior.

## Per-Slot Color Tokens & Icons

| Slot | Color Name | Hex | Icon (`HudIcons`) | Usage |
|---|---|---|---|---|
| `keel` | Violet | `#a78bfa` | `ship` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `port` | Cyan | `#22d3ee` | `wrench` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `bridge` | Amber | `#fbbf24` | `crew` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `reactor` | Orange | `#fb923c` | `power` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `battery` | Lime | `#a3e635` | `fuel` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `coolant` | Sky Blue | `#38bdf8` | `heat` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `cargo` | Pink | `#f472b6` | `cargo` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `scrubber` | Teal | `#2dd4bf` | `co2` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `stores` | Emerald | `#34d399` | `health` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `engine` | Coral Rose | `#fb7185` | `evac` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `thruster` | Indigo | `#818cf8` | `ping` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `antenna` | Orchid | `#e879f9` | `comms` | Slot header chip, icon, selected/hover card border & glow, price pill, 3D pulse |
| `preset` | Warm Accent | `#eaa665` | `objective` | `COMPARE ALL` preset cards |

## Tunables

- **Backdrop**:
  - Diagonal base `GradientTexture2D`: `#0d091f` -> `#1a1036` -> `#171230` -> `#0a1c2e`
  - Soft radial orbs: magenta (`0.92, 0.26, 0.60, 0.24`), teal (`0.08, 0.78, 0.76, 0.20`), violet (`0.48, 0.30, 0.94, 0.18`)
  - Grid (`GridBackdrop._draw()`): `48px` spacing, `Color(1, 1, 1, 0.032)`, `1px` line width (redraws on resize only)
- **Glassmorphism Panels**:
  - Corner radius: `16–20px` (`16px` header, `18px` catalog & stats, `20px` 3D showcase)
  - Fill: `Color(0.10–0.11, 0.08–0.085, 0.18–0.19, 0.78–0.80)`
  - Border: `Color(1, 1, 1, 0.14–0.18)`, `1px`; soft shadow `14–20px`
- **Header & Budget Bar**:
  - Credits pill: `#fbbf24` with `HudIcon("credits")`
  - Budget bar (`260x8px`): `UI.GOOD` when `total <= 0.75 * credits`, `UI.WARN` when `total > 0.75 * credits`, `UI.BAD` when `total > credits`; interpolated via `UI.smooth_bar` (`0.14s`)
- **Style Cards**:
  - Minimum size: `106x198px`, `14px` corner radius, `3px` family color stripe (`ShipCatalog.FAMILIES[family]["color"]`), `74px` thumbnail well
  - Price pill: slot-accented rounded pill; delta badge: `UI.GOOD` (`< 0`), `UI.BAD` (`> 0`), `UI.MUTED` (`== 0`); `SELECTED` ribbon when active
  - Hover lift: `0.12s` quad-out tween to `scale = Vector2(1.03, 1.03)` around center pivot
  - Selection pulse: `0.08s` to `1.06` then `0.12s` back to rest scale
  - Unaffordable state: `modulate.a = 0.48` (remains selectable)
- **Sticky Slot Header**:
  - Event-driven via `scroll.get_v_scroll_bar().value_changed` (no per-frame polling)
- **3D Product Showcase & Stat Chips**:
  - Transparent `SubViewport` over radial spotlight (`0.36, 0.25, 0.78, 0.42`) and floor glow (`0.13, 0.82, 0.88, 0.28`) `GradientTexture2D` layers
  - 9 stat chips in a 3-column grid (`STAT_SPECS`: `twr`, `dv`, `cargo`, `power`, `armor`, `turret`, `scan`, `handling`, `mass`) with mini `ProgressBar`s
- **Action Buttons**:
  - `PURCHASE ALL`: `250x50px`, `14px` rounded clip container with `#f97316` -> `#ec4899` linear `GradientTexture2D`; subtle `1.8s` looping sine modulate pulse when affordable; gradient hidden and greyed out when disabled with `reason` text
  - `CANCEL / CLOSE`: `165x50px` ghost style (`Color(1, 1, 1, 0.05)` fill, `Color(1, 1, 1, 0.22)` border, `14px` radius)
- **Performance & Accessibility**:
  - All `StyleBoxFlat` and `GradientTexture2D` instances are cached in `static var _shop_styles` and `static var _shop_gradients`
  - All tweens are created only on state changes and respect `UI.reduced_motion`
  - Zero per-frame allocations in `_process(dt)`
