# APOGEX / T-MINUS — HUD Art Direction & Design Tokens

Concrete, code-ready visual specification extending [`scripts/ui.gd`](../scripts/ui.gd) and [`scripts/hud.gd`](../scripts/hud.gd). All values are ready to paste into GDScript (`Color("#...")`, `StyleBoxFlat`, `Tween`, and `Control._draw()`).

---

## 1. Color Tokens

### Core Surfaces, Lines, Text & Semantics
| Token | Hex / RGBA | GDScript Constant | Usage |
|---|---|---|---|
| `BG_DEEP` | `#120d1b` | `Color("#120d1b")` | Deepest modal scrim / radar well |
| `BG` | `#1c1528` | `Color("#1c1528")` | Base dark-violet canvas (`UI.BG`) |
| `PANEL` | `#211930` @ 84% | `Color(0.13, 0.10, 0.19, 0.84)` | Standard HUD glass panel (`UI.PANEL`) |
| `PANEL_SOLID` | `#2a2138` | `Color("#2a2138")` | Opaque shop/overlay panel (`UI.PANEL_SOLID`) |
| `PANEL_TACTICAL` | `#060b10` @ 98% | `Color(0.025, 0.045, 0.065, 0.98)` | Tactical map & vitals console |
| `PANEL_ADVICE` | `#091117` @ 94% | `Color(0.035, 0.065, 0.09, 0.94)` | Crew advisor / orders card |
| `LINE` | `#ffffff` @ 13% | `Color(1, 1, 1, 0.13)` | Default hairline border (`UI.LINE`) |
| `LINE_SUBTLE` | `#ffffff` @ 7% | `Color(1, 1, 1, 0.07)` | Dividers, radar inner rings |
| `LINE_STRONG` | `#ffffff` @ 24% | `Color(1, 1, 1, 0.24)` | Outer radar ring, active dividers |
| `TEXT` | `#f3eef8` | `Color("#f3eef8")` | Primary crisp off-white (`UI.TEXT`) |
| `MUTED` | `#b4a8c6` | `Color("#b4a8c6")` | Captions, secondary readouts (`UI.MUTED`) |
| `DIM` | `#7d7191` | `Color("#7d7191")` | Disabled text, future steps (`UI.DIM`) |
| `ACCENT` | `#eaa665` | `Color("#eaa665")` | Primary warm orange (`UI.ACCENT`) |
| `ACCENT_HOVER` | `#f2bd89` | `Color("#f2bd89")` | Primary hover (`ACCENT.lightened(0.15)`) |
| `ACCENT_PRESSED` | `#d3955b` | `Color("#d3955b")` | Primary pressed (`ACCENT.darkened(0.10)`) |
| `ACCENT_DARK` | `#26190f` | `Color("#26190f")` | Dark ink on `ACCENT` (`UI.ACCENT_DARK`) |
| `GOOD` | `#9cdeb1` | `Color("#9cdeb1")` | Nominal / healthy / ready (`UI.GOOD`) |
| `WARN` | `#f7ce59` | `Color("#f7ce59")` | Caution / low threshold (`UI.WARN`) |
| `BAD` | `#ed7d8d` | `Color("#ed7d8d")` | Critical / damage / <60s clock (`UI.BAD`) |
| `INFO_PWR` | `#68cce2` | `Color("#68cce2")` | Power / energy / ability (`Q`) |
| `INFO_AIR` | `#aabfe4` | `Color("#aabfe4")` | Cabin pressure / cargo |
| `INFO_CO2` | `#b6a7dc` | `Color("#b6a7dc")` | CO₂ / atmosphere telemetry |

### Resource Color Ramps (100% / 60% / 30% / 10%)
Use piecewise step or `Color.lerp` at these exact thresholds:

| Resource | 100% (Nominal) | 60% (Moderate) | 30% (Low / Caution) | 10% (Critical) |
|---|---|---|---|---|
| **Health / Hull** | `#9cdeb1` | `#91dfbd` | `#f7ce59` | `#ed7d8d` |
| **Ammo / Mag** | `#f3eef8` | `#eaa665` | `#f7ce59` | `#ed7d8d` |
| **Fuel / Δv** | `#eaa665` | `#eca262` | `#f7ce59` | `#ed7d8d` |
| **Power / Energy** | `#68cce2` | `#7ec2dc` | `#f7ce59` | `#ed7d8d` |

```gdscript
static func ramp_color(ratio: float, nominal: Color) -> Color:
	if ratio <= 0.10: return BAD
	if ratio <= 0.30: return WARN
	if ratio <= 0.60: return nominal.lerp(WARN, 0.35)
	return nominal
```

---

## 2. Typography

### Font Pairing (Google Fonts — SIL Open Font License 1.1)
1. **UI Sans — `Space Grotesk`**
   - Files to download into `res://assets/fonts/`:
     - `SpaceGrotesk-Regular.ttf` (400 — body, objectives, advisor)
     - `SpaceGrotesk-Medium.ttf` (500 — button labels, chip tags)
     - `SpaceGrotesk-SemiBold.ttf` (600 — panel headers, role names)
     - `SpaceGrotesk-Bold.ttf` (700 — `APOGEX` brand, banners, phase strip active)
2. **Mono / Telemetry — `JetBrains Mono`**
   - Files to download into `res://assets/fonts/`:
     - `JetBrainsMono-Regular.ttf` (400 — secondary metrics, Δv, coordinates)
     - `JetBrainsMono-Medium.ttf` (500 — table readings, `02 / 24` ammo)
     - `JetBrainsMono-Bold.ttf` (700 — mission clock `14:00`, big `100%` hull/ammo counter)

### Size Scale, Weights & Letter-Spacing
| Token | Size (px) | Font | Weight | Letter-Spacing (`spacing_glyph`) | Usage |
|---|---|---|---|---|---|
| `FONT_XS` | `10` | Space Grotesk | SemiBold | `+1` px (caps) | Micro tags, `CREW LINK`, `HP/PWR/AIR` |
| `FONT_SM` | `12` | Space Grotesk | Medium | `+1` px (caps) | Chips, advisor body, button toggle, footer |
| `FONT_MD` | `14` | Space Grotesk | Regular / SemiBold | `0` px | Objectives, station console, toast, buttons |
| `FONT_BASE` | `15` | Space Grotesk | Regular | `0` px | Default `Theme.default_font_size` |
| `FONT_LG` | `18` | Space Grotesk | Bold | `+1` px | Panel titles, scoreboard digits (`JetBrains Mono`) |
| `FONT_XL` | `24` | Space Grotesk / Mono | Bold | `+2` px (brand) | `APOGEX` brand (`26px`), mission clock (`20px` Mono) |
| `FONT_2XL` | `40` | JetBrains Mono | Bold | `-1` px | Primary hull/ammo counter (`100%`, `02 / 24`) |
| `FONT_HERO` | `54`–`64` | Space Grotesk | Bold | `+2` px | Center phase banner (`54px`), title (`64px`) |

> **Godot 4 Tip:** Create a `FontVariation` resource for uppercase labels with `variation.spacing_glyph = 1` (for `10–12px` caps) or `2` (for `24px+` headings), and `outline_size = 5` with `Color(0.07, 0.05, 0.11, 0.78)` for floating text >= `18px`.

---

## 3. Spacing, Radius, Border, Shadow & Panel Styles

### Core Scales
- **Spacing (px):** `SP_2 = 2`, `SP_4 = 4`, `SP_6 = 6`, `SP_8 = 8`, `SP_12 = 12`, `SP_16 = 16`, `SP_20 = 20`, `SP_24 = 24`, `SP_32 = 32`
- **Corner Radius (px):** `RAD_SM = 2` (bars), `RAD_MD = 4` (buttons/toasts), `RAD_LG = 6` (panels), `RAD_CARD = 10` (cards), `RAD_PILL = 20` (chips)
- **Border Width (px):** `BW_NONE = 0`, `BW_HAIR = 1`, `BW_ACTIVE = 2`, `BW_CARD_TOP = 4`
- **Shadows:**
  - `SHADOW_SUBTLE`: `Color(0, 0, 0, 0.45)`, `size = 8`, `offset = Vector2(0, 4)`
  - `SHADOW_SELECTED`: `Color(accent.r, accent.g, accent.b, 0.35)`, `size = 22`, `offset = Vector2(0, 6)`

### Component `StyleBoxFlat` Specs
| Component | Background | Border | Radius | Padding (L/R, T/B) | Shadow |
|---|---|---|---|---|---|
| **Card (Normal)** | `Color(0.105, 0.08, 0.155, 0.96)` | `Color(1,1,1,0.09)`, `1px` | `10` | `16` / `14` | `SHADOW_SUBTLE` |
| **Card (Selected)** | `Color(0.15, 0.115, 0.22, 0.98)` | `ACCENT`, `2px` (`top=4px`) | `10` | `16` / `14` | `SHADOW_SELECTED` |
| **Chip / Pill** | `Color(c.r, c.g, c.b, 0.14)` | `Color(c.r, c.g, c.b, 0.45)`, `1px` | `20` | `9` / `3` | None |
| **Button (Normal)** | `Color(0.16, 0.12, 0.22, 0.88)` | `LINE`, `1px` | `4` | `12` / `8` | None |
| **Button (Hover)** | `Color(0.24, 0.18, 0.32, 0.95)` | `ACCENT`, `1px` | `4` | `12` / `8` | None |
| **Button (Pressed)** | `Color(0.30, 0.22, 0.38, 0.95)` | `ACCENT`, `1px` | `4` | `12` / `8` | None |
| **Button (Disabled)** | `Color(0.12, 0.10, 0.16, 0.60)` | `Color(1,1,1,0.05)`, `1px` | `4` | `12` / `8` | None |
| **Button (Focus)** | `Color(0, 0, 0, 0)` | `ACCENT`, `2px` | `4` | `12` / `8` | None |
| **ProgressBar (Std)** | BG: `Color(1,1,1,0.10)` / Fill: `ACCENT` or metric | `0px` | `2` | `0` / `0` | None |
| **ProgressBar (Seg)** | `Control._draw()` 10–12 segments, `2px` gap, unfilled `Color(1,1,1,0.10)`, filled `metric` | `0px` | `1` | `0` / `0` | None |
| **Tooltip** | `Color(0.08, 0.06, 0.12, 0.96)` | `LINE_STRONG`, `1px` | `4` | `10` / `6` | `SHADOW_SUBTLE` |
| **Toast** | `Color(0.12, 0.09, 0.17, 0.92)` | `LINE`, `1px` | `4` | `14` / `7` | `SHADOW_SUBTLE` |
| **Banner** | Transparent (text only, `outline_size=6` `#120d1bcc`) | None | `0` | `0` / `0` | `outline` |

---

## 4. Procedural Icon Set (24×24 ViewBox, `Control._draw()`)

All 24 icons use a **`24×24` logical grid**, `stroke = 1.75px` (antialiased `true`), rounded caps via `draw_circle` joints where needed, and no external PNG/SVG files. Scale by `target_px / 24.0`.

| # | Name | Procedural Geometry (`24×24` space) |
|---|---|---|
| 1 | `health` | Rounded cross: two rects `(10,4,4,16)` + `(4,10,16,4)` |
| 2 | `ammo` | Two vertical shells: `x=7,14`, body `(x,9,4,11)` + triangle tip `(x,9)->(x+2,4)->(x+4,9)` |
| 3 | `fuel` | Teardrop/canister: polygon `(12,3)->(18,13)->(16,19)->(8,19)->(6,13)` + inner highlight line |
| 4 | `power` | Bolt: `draw_colored_polygon([(14,2),(6,13),(12,13),(10,22),(18,11),(12,11)])` |
| 5 | `heat` | Thermometer: vertical line `(12,4)->(12,15)`, filled bulb `circle((12,17.5), 3.5)`, 3 tick lines on right |
| 6 | `pressure` | Gauge: `draw_arc((12,13), 8, PI*0.8, PI*2.2, 24)` + needle `(12,13)->(17,8)` |
| 7 | `co2` | 3 linked circles: `(8,14, r=3)`, `(16,14, r=3)`, `(12,8, r=3.5)` + connecting lines |
| 8 | `radar` | Concentric arcs `r=9, 5` at `(12,12)` + sweep line `(12,12)->(19,6)` + center dot `r=1.5` |
| 9 | `objective` | Diamond: `[(12,3),(21,12),(12,21),(3,12)]` (stroke) + center diamond `r=3` (filled) |
| 10 | `flag` | Pole `(6,3)->(6,21)` + pennant polygon `[(6,4),(19,7.5),(6,12)]` |
| 11 | `crew` | Helmet circle `(12,8, r=4)` + shoulders arc/trapezoid `[(5,20),(7,14),(17,14),(19,20)]` |
| 12 | `credits` | Hexagon `r=9` at `(12,12)` + inner vertical bar `(12,7)->(12,17)` |
| 13 | `warning` | Triangle `[(12,3),(22,20),(2,20)]` + stem `(12,9)->(12,14)` + dot `(12,17.5, r=1)` |
| 14 | `ship` | Delta hull `[(12,3),(19,18),(12,15),(5,18)]` + nose line `(12,3)->(12,15)` |
| 15 | `cargo` | Isometric cube: outer hex `r=9` + `Y` seams from `(12,12)` to `(12,21)`, `(4,7.5)`, `(20,7.5)` |
| 16 | `wrench` | Diagonal shaft `(6,18)->(15,9)` + open C-arc head at `(17,7, r=3.5)` |
| 17 | `hit_marker` | 4 diagonal ticks: `(5,5)->(9,9)`, `(19,5)->(15,9)`, `(5,19)->(9,15)`, `(19,19)->(15,15)` |
| 18 | `clock` | Circle `(12,12, r=9)` + hands `(12,12)->(12,7)` and `(12,12)->(16,12)` |
| 19 | `lock` | Shackle arc `(12,9, r=4, PI, TAU)` + body rect `(6,10,12,10)` |
| 20 | `check` | Polyline `[(4,12.5),(9.5,18),(20,6.5)]` |
| 21 | `ping` | Center dot `(12,12, r=2)` + two concentric circles `r=5.5`, `r=9.5` |
| 22 | `comms` | Dot `(6,18, r=2)` + 2 quarter-arcs centered `(6,18)` at `r=6` and `r=11` (`-PI/2..0`) |
| 23 | `planet` | Sphere `(12,12, r=6)` + tilted ellipse ring polyline from `(2,15)` to `(22,9)` |
| 24 | `evac` | Double chevron right: `[(6,6),(12,12),(6,18)]` and `[(13,6),(19,12),(13,18)]` |

---

## 5. Motion & Performance Rules

### Performance Budget
- **Zero per-frame `StyleBoxFlat.new()` or `Label` allocations** inside `_process` / `tick`. Pre-cache styleboxes per state.
- **Radar redraw cap:** Max **20 Hz** (`0.05s` accumulator via `Radar.request_redraw()`).
- **Common HUD telemetry cap:** **10 Hz** (`0.10s` accumulator in `Hud.update_common()`), with immediate bypass only on `selected` or `phase` change.

### Tween Durations & Easing
| Element | Trigger | Duration | Transition / Ease | Behavior |
|---|---|---|---|---|
| **Toast In** | `toast()` | `0.18s` | `TRANS_CUBIC` / `EASE_OUT` | `modulate.a: 0->1`, `position.y: +8->0` |
| **Toast Out** | `toast_time <= 0` | `0.22s` | `TRANS_QUAD` / `EASE_IN` | `modulate.a: 1->0` |
| **Banner In** | `show_banner()` | `0.25s` | `TRANS_EXPO` / `EASE_OUT` | `modulate.a: 0->1`, `scale: 0.96->1.0` |
| **Banner Out** | Last `0.50s` | `0.50s` | `TRANS_LINEAR` | `modulate.a: 1->0` |
| **Button Hover** | `mouse_entered` | `0.10s` | `TRANS_QUAD` / `EASE_OUT` | Border/bg tint shift (no layout resize) |
| **Bar Fill** | Value change | `0.14s` | `TRANS_CUBIC` / `EASE_OUT` | Smooth `ProgressBar.value` interpolation |
| **Damage Flash** | `hurt()` | `0.30s` | `TRANS_EXPO` / `EASE_OUT` | `alpha` peaks `0.35`, decays at `1.2/s` |
| **Low-Health Pulse** | `hp <= 30%` | `0.90s` loop | `TRANS_SINE` / `EASE_IN_OUT` | `vitals` border/alpha `0.45 <-> 1.0` (`0.55s` loop if `<= 10%`) |

---

## 6. Layout & Responsive Scaling

### Godot 4 Project Scaling Rules (`project.godot`)
- `display/window/stretch/mode = "canvas_items"`
- `display/window/stretch/aspect = "expand"`
- `gui/common/snap_controls_to_pixels = true`
- **Anchor rule:** Use `PRESET_*` anchors + `offset_left/top/right/bottom` relative to viewport edges rather than fixed `position` from top-left for right/bottom/center widgets so `1280×720` and `3004×1805` scale cleanly without clipping.

### Safe Margins & Widget Placement
- **Safe Margins:** `24px` horizontal, `16px` vertical (at `1280×720` reference; ~`56px` H / `40px` V in native pixels at `3004×1805`, or automatic via `canvas_items` stretch).

| Widget | Anchor | 1280×720 Reference Rect / Offset | 3004×1805 Native Equivalent |
|---|---|---|---|
| **Brand + Objectives** | `TOP_LEFT` | Brand `(24, 16)`, Title `(24, 58)`, Panel `(20, 122)`, `w=300` | Scaled `~2.35×` (`56, 38`), Panel `w=704` (max `340` ref width) |
| **Phase Strip + Clock** | `CENTER_TOP` | `offset_left=-330, top=10`, `660×40` | Centered; `w=1550` scaled (`660` ref) |
| **Crew Cards** | `CENTER_TOP` | `offset_left=-310, top=58`, `4×150×52` | Centered below strip |
| **Radar** | `TOP_RIGHT` | `offset_right=-16, top=14`, `220×220` (`190×190` disc) | Top-right `516×516` scaled (`220` ref) |
| **Scoreboard** | `TOP_RIGHT` | Stacked `8px` below Radar, `w=220` | Stacked `19px` below Radar |
| **Vitals / Status** | `BOTTOM_RIGHT` | `offset_right=-20, bottom=-20`, `w=250` | Bottom-right `offset=-47` |
| **Ammo / Weapon** | `BOTTOM_RIGHT` | Inside `visual_status` top (`40px` Mono counter) | Inside `visual_status` top |
| **Advisor** | `BOTTOM_LEFT` | `offset_left=20, bottom=-150` (above role bar), `w=340` | Bottom-left `offset_left=47, bottom=-352` |
| **Role Bar** | `CENTER_BOTTOM` | `offset_left=-230, bottom=-62`, `4×104×40` | Centered above `24px` footer |
| **Crosshair** | `CENTER` | `40×40` centered (`-20, -20`) | Centered `94×94` scaled |

---

## 7. Radar & Tactical Map Style

- **Disc Background:** `Color(0.08, 0.06, 0.12, 0.80)` (`#140f1f` @ 80%)
- **Rings & Axes:**
  - Outer range ring (`r`): `LINE_STRONG` (`Color(1,1,1,0.24)`), `1.5px`
  - Half-range ring (`0.5 * r`): `LINE_SUBTLE` (`Color(1,1,1,0.08)`), `1.0px`
  - Cardinal crosshairs: `Color(1,1,1,0.06)`, `1.0px`
- **Cover / Terrain Polygons:** `Color(0.30, 0.50, 0.56, 0.22)` fill (`#4d808f`)
- **Radar Sweep:** Optional 20° trailing wedge rotating at `90°/s` (updated at 20 Hz), `Color(0.92, 0.65, 0.40, 0.09)` fading to `0.0`.
- **Entity Blip Shapes:**
  - **Player:** Filled triangle chevron `[(0,-8),(5,5),(-5,5)]`, `ACCENT` (`#eaa665`)
  - **Captured / Active Sample & Crew:** Solid circle (`r=3..4px`), faction/role color
  - **Ships / Raiders / Loose Samples:** Hollow ring (`draw_arc`, `2.0px` stroke), faction color or `WARN`
  - **Priority Target (`Z` Ping):** Expanding double ring in `ACCENT` / `WARN`
- **Tactical Map (`M`):** `520×520` panel (`PANEL_TACTICAL`), `480×480` radar, `show_labels = true` (`12px` `Space Grotesk`), `range_m = 95.0`.

---

## 8. Appendix: Per-Environment Palettes

Values extracted from [`scripts/universe.gd`](../scripts/universe.gd) and [`scenes/levels/`](../scenes/levels/) for HUD contrast alignment:

| Environment | Sky Zenith (`sky_top`) | Sky Horizon (`sky_horizon`) | Ground / Bottom | Fog (`fog_light`) | Sun / Key Light | Ambient Energy |
|---|---|---|---|---|---|---|
| **Workshop** | `#7fb2e2` | `#cfe2f2` | `#556b47` (`#6f8a5c` turf) | `#cfe2f2` (`0.0025`) | `#fff5e6` | `1.00` (Sky) |
| **Planet A** | `#b9d6cf` | `#e6eee8` | `#3d3258` | `#dfe8e4` (`0.0035`) | `#fff2e0` (`1.25`) | `0.90` (Sky) |
| **Planet B** | `#173544` | `#4d7c80` | `#3d3258` | `#3c6366` (`0.0040`) | `#ffe9d9` (`1.35`) | `1.00` (Sky) |
| **Orbit / Flight** | `#0d1626` | `#1d3047` | `#0b1220` | Disabled (`0.0`) | `#ffe9d9` | `0.55` (Sky) |
| **Universe** | Lerps `#b9d6cf` → `#0d1626` → `#173544` | Lerps `#e6eee8` → `#1d3047` → `#4d7c80` | Lerps `#3d3258` ↔ `#0b1220` | Lerps A ↔ B, drops `>2600m` | Lerps A ↔ B | `0.55`–`1.00` |
