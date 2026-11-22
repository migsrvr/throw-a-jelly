# UI mockup spec: HUD + core loop (turn 1)

**For Claude Code.** Build spec for the mockups in `Throw a Jelly UI.dc.html` (design project). Covers the HUD
frame, throw meter, in-flight HUD and reveal cutscene, in two options:

- **A (faithful):** matches the reference screenshots. Dark panels, heavy black outlines, outlined coloured numbers.
- **B (cleaner):** same palette, grouped translucent panels, coloured bevel nav buttons, chips.

**Decision (turn 2): Option A for all four screens, refined as `2a`..`2d`.** Build from turn 2. Option B notes below
are kept for reference only.

Turn 2 changes on top of A:
- Vector icons replace emoji (section 1b).
- Vertical gradients on every button, banner, badge and key number (section 1c).
- HUD nav buttons are colour-filled (A outline + label overlap kept). Hotbar slots are rarity-tinted.
- Throw: **keep the existing in-game meter.** Only the callout, PERFECT tag, hint and AUTO toggle are restyled. Read with [UI-HANDOFF.md](UI-HANDOFF.md) (behaviour) and
[UI-DATA-CONTRACT.md](UI-DATA-CONTRACT.md) (fields). All sample values come from [DATA-REFERENCE.md](DATA-REFERENCE.md).

| Mockup id | Screen | Option |
| --- | --- | --- |
| 1a / 1b | HUD frame | A / B |
| 1c / 1d | Throw meter + Auto | A / B |
| 1e / 1f | In-flight HUD | A / B |
| 1g / 1h | Reveal cutscene | A / B |

---

## 0. How to read the numbers

- Every px value in this file is an **Offset under a `UIScale`**. Build at the design size, then scale.
- **PC:** design space 1366x768, `UIScale.Scale = 1` (keep `UiKit.AttachResponsiveScale`, clamp 0.68-1.18).
- **Phone (touch, landscape):** `UIScale.Scale = 0.68` at 844x390, so the design space is about 1241x574.
  Formula: `scale = math.clamp(viewport.Y / 574, 0.6, 0.8)` when `UserInputService.TouchEnabled and not KeyboardEnabled`.
  This keeps 84 px nav buttons at about 57 pt (above the 44 pt touch minimum).
- `ScreenGui.IgnoreGuiInset = false` for the HUD, so y = 0 sits **below** the Roblox top bar (58 px).
  The mockup draws the top bar as grey ghosts at top-left; keep that corner empty.
- Phone also has ghost circles for the Roblox thumbstick (bottom-left) and jump button (bottom-right). No HUD
  element may sit in those areas on touch.

## 1. Tokens

### Font
`Enum.Font.FredokaOne` everywhere (`Font.fromEnum(Enum.Font.FredokaOne)`). No other weights.

### Colours (`Color3.fromRGB`)

| Token | RGB | Use |
| --- | --- | --- |
| Ink | 5, 5, 7 | A outlines, A strokes |
| InkB | 11, 11, 18 | B outlines, B strokes |
| Panel | 23, 24, 28 | A panel / slot fill |
| PanelInner | 59, 61, 70 | A inner bevel line (inset UIStroke) |
| PanelGlass | 14, 14, 20 @ 0.18 transparency | B grouped panels |
| White | 255, 255, 255 | text |
| Power | 62, 184, 255 | Throw Power number (A) |
| Cash | 184, 242, 51 | Cash number, income (A) |
| Gems | 143, 228, 255 | Gems number |
| Luck | 255, 225, 74 | flight luck number |
| Gold | 255, 215, 65 | PERFECT!, SUPER LUCKY! |
| Green | 76, 219, 22 | positive buttons, selected slot, Auto ON |
| GreenTop / GreenBottom | 98, 242, 30 / 59, 196, 12 | green button UIGradient |
| Orange | 255, 178, 28 | Upgrades (B) |
| Red | 232, 40, 42 | badge, NEW!, close |
| Blue | 46, 155, 255 | Index (B) |
| Magenta | 227, 39, 214 | Rewards (B), window headers |
| Purple | 155, 92, 255 | Slimes (B) |

Zone, rarity, mutation and meter-band colours: use the tables in DATA-REFERENCE.md (read from `GameConfig`, never
hard-code).

### 1b. Icons (replace emoji)

Style: **Twemoji** (Twitter/X emoji, CC-BY 4.0; credit "Twemoji by Twitter, Inc and other contributors" in the game
description). Ten are the official Twemoji SVGs (📘 🛒 🎁 💪 💵 💎 🌿 🌋 ❄️ 🍬). `upgrades`, `slimes` and `zone_crystal`
have no matching emoji and are custom-drawn in the same flat Twemoji style (36x36 viewBox, no outlines, two-tone shading).

Source SVGs in `icons/*.svg`, upload-ready PNGs in `icons/png/*.png` (256x256, transparent).
Upload each PNG as a Decal/Image, then use `ImageLabel` with `ScaleType = Fit`, `BackgroundTransparency = 1`.
Keep the asset ids in one table, e.g. `Shared/UiIcons.luau`:

| Key | Used for | Size in HUD |
| --- | --- | --- |
| index | Index nav | 58 |
| shop | Shop nav | 58 |
| upgrades | Upgrades nav | 58 |
| rewards | Rewards nav | 58 |
| slimes | Slimes nav (until the 3D ViewportFrame is in) | 58 |
| power | Throw Power stat | 46 |
| cash | Cash stat, cash chips | 46 |
| gem | Gems stat, reveal `+N` gems | 46 / 38 |
| zone_meadow, zone_crystal, zone_lava, zone_frost, zone_candy | flight zone banner, Index zone cards | 42 |

**Icon contrast rule (applies everywhere).** An icon must never sit on a background of similar hue or value.
- Keep tiles colourful, never plain white or grey. Pick the complementary hue: yellow/orange icons (⚡ 💪 🥕 👑) go on blue
  `184,230,255 → 91,184,255 → 42,127,232`; blue/purple icons go on pink `255,208,236 → 255,143,207 → 224,80,159` or orange; green icons on purple or blue.
- When an icon sits on a coloured header or banner of a similar colour, put it on a dark **icon plate**: round/rounded Frame,
  gradient `52,54,63 → 18,19,24`, UIStroke 3 Ink, icon at about 70% of the plate size.
- Nav buttons use contrasting fills: Index (blue book) on orange, Shop (grey cart) on green, Upgrades (orange arrow) on blue,
  Rewards (red/yellow gift) on teal `168,255,242 → 46,224,207 → 15,154,168`, Slimes (green) on purple.
- Check: icon dominant colour vs background should differ by at least ~40% lightness or sit on opposite sides of the colour wheel.

### Robux glyph
Use Roblox's own asset in Studio, not an upload: `rbxasset://textures/ui/common/robux.png` (white) or the
`ImageLabel` from `MarketplaceService` price displays. `icons/robux.svg` is a mockup-only stand-in of the current hexagon glyph.

### 1c. Gradients (`UIGradient`, `Rotation = 90`, top to bottom)

Three-stop ColorSequence: `light` at 0, `mid` at 0.55, `dark` at 1. Apply to the Frame for buttons/banners.
For gradient text, put the `UIGradient` on the TextLabel (`TextColor3 = 255,255,255`) and keep the black `UIStroke`.

| Use | light | mid | dark |
| --- | --- | --- | --- |
| Index nav | 255,240,122 | 255,178,28 | 240,122,0 |
| Shop nav | 182,255,122 | 76,219,22 | 36,153,12 |
| Upgrades nav | 158,216,255 | 62,162,255 | 26,92,200 |
| Rewards nav | 168,255,242 | 46,224,207 | 15,154,168 |
| Slimes nav | 210,182,255 | 155,92,255 | 90,43,208 |
| Green button / Auto track | 140,255,74 | 76,219,22 | 47,168,15 |
| Red badge / NEW! | 255,122,122 | 232,40,42 | 179,18,44 |
| Power number | 200,240,255 | 62,184,255 | 30,111,224 |
| Cash number, income | 244,255,176 | 184,242,51 | 92,194,26 |
| Gems number | 240,252,255 | 143,228,255 | 58,168,232 |
| Luck number, SUPER LUCKY!, PERFECT! | 255,251,208 | 255,225,74 | 255,159,10 |
| Zone banner | zone colour lightened 50% | zone colour | zone colour darkened 25% |
| Rarity / mutation words | colour lightened 60% | colour | colour darkened 30% |
| Hotbar slot fill | rarity colour lightened 40% | rarity colour | rarity colour darkened 30% |

Gloss on nav buttons: a child Frame at the top 42%, white, `UIGradient` Transparency 0.55 -> 1.
Inner light bevel: `UIStroke` 3 px white at 0.65 transparency on an inset child frame. Bottom lip: 7 px black at 0.75.
Striped banners (Place button, zone banner): a child `ImageLabel` with a diagonal stripe texture at 0.86 transparency
(same look as the reference window headers).

### Outlines
- **Text outline A:** `UIStroke` on the TextLabel, `ApplyStrokeMode = Contextual`, `Color = Ink`,
  `Thickness = round(TextSize * 0.085)` (24 px text -> 2, 42 px -> 3.5, 88 px -> 5). The mockup uses CSS
  stroke widths about 2x these numbers because CSS centres the stroke.
- **Text outline B:** same, `Color = InkB`, `Thickness = round(TextSize * 0.06)`. Plain labels on glass panels have no stroke.
- **Frame outline A:** `UIStroke` `ApplyStrokeMode = Border`, `Thickness = 4`, `Color = Ink`.
  Inner bevel: a child Frame inset 3 px with its own `UIStroke` 3 px `PanelInner`.
- **Frame outline B:** `Thickness = 3`, `Color = InkB`.

### Corners (`UICorner.CornerRadius = UDim.new(0, n)`)
Nav button A 22, B 24. Hotbar slot 16. Pill buttons and toggles `UDim.new(0.5, 0)`. Panels B 20-26.

### Bevel buttons
Keep `UiKit.CreateBevelButton`. Face = token colour, bottom lip = a 6-7 px darker strip (`0,0,0` at 0.78
transparency) along the bottom inside the corner, top gloss 3 px (`255,255,255` at 0.65) for B.
Hover: scale 1.06 over 0.12 s. Press: scale 0.94.

---

## 2. HUD frame (1a / 1b)

```
HUD (ScreenGui, ResetOnSpawn=false, ZIndexBehavior=Sibling)
└ Root (Frame, Size 1,0,1,0, transparent) + UIScale
  ├ LeftNav   (Frame) UIListLayout Vertical, Padding A 18 / B 12
  │   Index, Shop, Upgrades (NavButton)
  ├ RightNav  (Frame) UIListLayout Vertical
  │   Rewards (+ Badge), Slimes (NavButton)
  ├ Stats     (Frame) UIListLayout
  │   Power, Cash, Gems (StatRow)
  ├ Objective (Frame) UIListLayout Vertical, Center
  │   ObjectiveText, Toast
  └ Hotbar    (Frame) UIListLayout Vertical, Center
      PlaceButton, Slots (UIListLayout Horizontal) → Slot1..Slot5
```

| Element | AnchorPoint | Position | Size | Notes |
| --- | --- | --- | --- | --- |
| LeftNav | 0, 0.5 | `UDim2.new(0,16,0.5,0)` | 88 x (3*88+2*18) A / 84 x (3*84+2*12) B | |
| RightNav PC | 1, 0.5 | `UDim2.new(1,-16,0.5,0)` | same width | |
| RightNav phone | 1, 0.5 | `UDim2.new(1,-16,0.40,0)` | | moved up to clear the jump button |
| Stats PC | 0, 1 | `UDim2.new(0,16,1,-16)` | auto (AutomaticSize XY) | Vertical list, Padding A 2 / B 6 |
| Stats phone | 1, 0 | `UDim2.new(1,-16,0,10)` | auto | **Horizontal** list, Padding A 22 / B 6; bottom-left is the thumbstick |
| Objective | 0.5, 0 | `UDim2.new(0.5,0,0,64)` (phone 74) | auto | |
| Hotbar | 0.5, 1 | `UDim2.new(0.5,0,1,-16)` | auto | Vertical, Padding A 14 / B 12 |

### NavButton
- **A:** 88x88 Panel fill, frame outline A + inner bevel, `UICorner 22`. Icon TextLabel (emoji placeholder for
  now) TextSize 44, centred, nudged up 7 px. Label TextLabel `Size UDim2.new(1,40,0,26)`, AnchorPoint 0.5,1,
  `Position UDim2.new(0.5,0,1,8)`, TextSize 22, text outline A. The label overlaps the bottom edge (reference look).
- **B:** 84x84, BackgroundColor = button colour (Index Blue, Shop Green, Upgrades Orange, Rewards Magenta,
  Slimes Purple), frame outline B, bevel lip + gloss. Icon TextSize 36, label inside under it, TextSize 15, text outline B.
- **Turn 2 (build this):** A layout, but the fill is the nav gradient from 1c, plus gloss, inner light bevel and
  bottom lip. Icon = ImageLabel 58x58 (1b), nudged up 6 px. Gap between buttons 20.
- **Badge (Rewards):** 30x30 (B 28), AnchorPoint 0.5,0.5 at the top-right corner offset (+-8), Red, outline 3, `UICorner 0.5`.
  A shows `"!"`. B shows the number of claimable things (daily + quests). Visible when
  `DailyCanClaim or any quest claimable`.
- Shop icon is a 🛒 placeholder in the mockup (repo uses `R$`). Slimes uses a 3D ViewportFrame (`UiKit.CreateSlimeViewport`).

### StatRow
- **A:** emoji icon TextSize 40 + number TextSize 42, colour Power / Cash / Gems, text outline A. Gap 10.
- **B:** all three rows sit in one PanelGlass frame, padding 8, `UICorner 20`. Each row: a 36x36 icon tile
  (`UICorner 11`, colour Blue / GreenBottom / 31,179,217) + number TextSize 28 with no stroke, on a tinted row
  (token colour at 0.85 transparency, `UICorner 14`). Cash row also shows `+$<IncomePerSec>/s` TextSize 15, white at 0.3 transparency.
- Bind: `EffectiveThrowPower`, `Cash`, `Gems` via `GameConfig.FormatNumber`. Number width is automatic
  (`AutomaticSize = X`) so `$2.30B` does not clip.

### Objective + Toast
- ObjectiveText: **A** TextSize 32, outline A, no background. **B** glass pill (padding 8/22, `UICorner 0.5`) with a
  34 px Gold circle `"!"` icon and TextSize 24 text.
- Toast (from `ToastNotify`): **A** outlined text TextSize 26 in the kind colour. **B** a pill in the kind colour,
  TextSize 20, outline B. Kind colours: `cash` Green/Cash, `power` Power, `gems` Gems, `success`/`info` Gold,
  `warn` Red. Show 2.5 s, fade 0.25 s.

### Hotbar
- PlaceButton: visible only when a slime is held. **A** height 56, padding 26, green UIGradient (GreenTop -> GreenBottom,
  Rotation 90), outline A 4, `UICorner 16`, TextSize 24, text "Place Slime on Free Slot". **B** height 50, Green, pill,
  TextSize 21, "Place on free slot".
- Slots: 5 always shown (empty ones at 0.4 transparency) so the bar does not jump. Gap A 10 / B 8.
  - **Turn 2 slot (build this):** 82x82, fill = rarity gradient (1c), outline 4 Ink, inner light bevel. Selected:
    outline Gold `255,225,74`, outer glow (`UIStroke` 3 px Ink + an ImageLabel glow), lifted -6 px. Income text white.
  - **A slot** 80x80 Panel, outline 4 Ink (selected: Green), inner bevel. Top: income TextSize 14 green. Middle:
    ViewportFrame 34x26 min (use 44x44 in build). Bottom: mutation word in mutation colour, else rarity word in rarity colour, TextSize 12.
  - **B slot** 78x84, background = rarity colour with a UIGradient fading to 0.33 transparency, outline 3 InkB
    (selected: White and lifted -6 px). Top: short name TextSize 13. Bottom strip: black 0.45 transparency with income TextSize 13.
  - **Key hint (PC only):** A = white 24x24 keycap top-left (offset -10,-10). B = small number top-left. Hidden on touch.
- Empty hotbar: keep the slots visible (dimmed). Hide only PlaceButton.

---

## 3. Throw meter + Auto (1c / 1d)

```
ThrowMeter (Frame) AnchorPoint 0.5,0.5  Position UDim2.new(0.66,0,0.5,0)   (B 0.68; phone Y 0.46)
├ Pill (Frame)  76 x 380 (phone 300)  [B: 60 x 340, phone 270]
│ ├ UIListLayout Vertical, Padding 3 (B 2)
│ ├ Band9..Band1 (Frame, Size 1,0,1/9,-gap)  top to bottom
│ ├ Slider (Frame)  Size UDim2.new(1,40,0,16)  [B 1,24,0,10]
│ ├ Callout (TextLabel) "+14"
│ └ PerfectTag (TextLabel) "PERFECT!"  [B: "PERFECT +20"]
├ Hint (TextLabel)
└ AutoToggle (TextButton)   visible only if OwnedBoosts.auto_throw
```

- **Turn 2: do not rebuild the Pill or Slider.** Keep the meter the game already has. Restyle only the Callout
  (gradient text, band colours), the PERFECT tag (gold gradient text), the hint and the AutoToggle (dark gradient
  pill `52,54,63 -> 23,24,28`, green gradient track, white -> `215,219,228` knob). Positions stay relative to the meter.
- **A Pill:** White fill, padding 7 (`UIPadding`), outline 5 Ink, `UICorner 0.5`, drop shadow = a second Frame offset
  +6 y, black 0.65 transparency. Bands `UICorner 6`.
- **B Pill:** InkB fill, padding 4, `UICorner 18`, sits inside a glass panel (padding 16/18, `UICorner 26`) that also
  holds the hint and Auto row. Top band gets a soft glow (`UIStroke` 2 px band colour, 0.3 transparency).
  Right of the pill: a 96 px column with "PERFECT +20" (Gold, 15) at the top and the live callout
  "+14" (TextSize 38, band colour) + "1.32x luck" (15, white 0.25) that follows the slider.
- **Slider:** `Position.Y` driven by the sweep (0 = bottom of band 1, 1 = top of band 9). A: white bar, outline 4 Ink,
  wider than the pill by 20 px each side. B: white bar with 3 px InkB stroke.
- **Callout (A):** TextSize 44, colour of the current band, outline A, left of the pill +30, follows the slider.
- **Hint:** A TextSize 34 outlined, `"CLICK TO THROW!"` on PC, `"TAP TO THROW!"` on touch, `"PRESS A TO THROW!"` on gamepad.
  B: keycap "SPACE" (white, `UICorner 8`, InkB text) + "or click to throw"; touch shows "Tap to throw".
- **AutoToggle:** A = Panel pill, "AUTO" TextSize 22 + 58x32 track (Green when on, 90,92,100 when off) with a 22 px
  white knob that tweens left/right 0.15 s. B = full-width row "Auto-Throw" + 52x28 track.
- **PERFECT moment (wanted):** on stop in band 9 pop the PerfectTag to scale 1.4 -> 1 (Back easing, 0.3 s), flash the
  pill stroke Gold, play a sound.

---

## 4. In-flight HUD (1e / 1f)

Shown from `ThrowBroadcast` until the bait lands. Nav and Stats stay visible; Objective and Hotbar hide.

- **A:** stack at `AnchorPoint 0.5,0`, `Position UDim2.new(0.5,0,0,64)`:
  - Luck `"2.49X"` TextSize 88, Luck colour, outline A (5).
  - `"LUCK"` TextSize 32.
  - Zone banner: pill, padding 8/24, BackgroundColor = zone colour, outline 4, bottom lip; zone icon + name
    uppercased, TextSize 30, outline A. Tween colour 0.2 s on zone change and punch scale 1.15 -> 1.
  - Turn 2: luck number uses the Luck gradient. Zone banner uses the zone gradient + stripes and a 42 px zone icon (1b).
  - Distance `"312 studs"` TextSize 22 (wanted in the hand-off; compute on the client from bait position).
- **B:** one glass panel at the same anchor:
  - Row: luck `"2.49x"` TextSize 60 + `"LUCK"` 24.
  - Lane bar 520 px wide: 5 zone segments (`UIListLayout` Horizontal, Padding 4), height 34, `UICorner 10`.
    Reached zones filled with the zone colour (InkB text), unreached = white 0.92 transparency. Current zone has a White 3 px stroke.
    A 6x54 white marker at `Position.X = distance / 1200`.
  - Footer: `"💎 Crystal Cave"` and `"312 studs"`, TextSize 18.

---

## 5. Reveal cutscene (1g / 1h)

Full-screen layer above the HUD. Hide Nav, Stats, Hotbar. Backdrop Frame black-violet `6,4,14` at 0.38 transparency.
Content: one Frame `Size 1,0,1,0` with `UIListLayout` Vertical, `VerticalAlignment Center`, Padding A 4 / B 10.

- **A order:** `"1 in 89"` (76, outline 5) → `"SUPER LUCKY!"` (42, Gold, Rotation -3) → slime ViewportFrame 300x180
  with a ring behind it (ImageLabel ring, mutation colour, 0.45 transparency) and a NEW! sticker (Red, Rotation 10,
  TextSize 28) top-right → mutation word (34, mutation colour) → short word `"AMETHYST"` (84, rarity colour, outline 5)
  → `"$152/s"` (38, Cash) + `"+3 💎"` (32, Gems) → `"tap to continue"` (22, white 0.15).
- **Turn 2:** SUPER LUCKY!, mutation word, short word and income use gradients (1c). The slime ring gets a rotating
  sunburst ImageLabel behind it (mutation colour, 0.7 transparency, `Rotation` tween 360 over 8 s). NEW! sticker uses the
  red gradient. The gems value is `+N` followed by the gem icon (38 px). Backdrop = radial vignette
  (`40,10,70` centre at 0.45 → `6,4,14` edges at 0.15).
- **B order:** chips row `"1 in 89"` (glass, 40) + `"SUPER LUCKY!"` (Gold pill, InkB text, 28) → slime 300x170 with a
  radial glow → result card 520 wide (`UICorner 24`, fill 21,21,28): header strip in the mutation colour (or rarity colour
  if NORMAL) `"CRYSTAL · RARE"` + NEW! pill; body `"Amethyst Slime"` (30, rarity colour) and three chips:
  income, gems, cash from throw (`+$234`) → `"Click or Space to continue"` / `"Tap to continue"` (18).
- Phone: the column must fit 574 design px. Don't add rows; if more space is needed, shrink the ViewportFrame first.
- Bind (from `ThrowBroadcast`): `OneInX`, `SuperLucky`, caught slime `Name`/`ShortWord`/`Mutation`/`Rarity`/`IncomePerSec`,
  `IsNewDiscovery`, `GemsEarned`, cash earned. Hide the mutation word for `NORMAL`; show the rarity word instead.
- Rarity scaling (wanted): Common = no ring, no SUPER LUCKY; Rare+ ring; Legendary/Mythic add a second ring and
  a screen shake (camera offset 0.3 s). Auto-continue after 3 s.

---

## 6. States checklist for this turn

| Screen | States to build |
| --- | --- |
| HUD | badge on/off, slot selected/unselected/empty, PlaceButton shown/hidden, toast kinds (6), long numbers (`$2.30B`) |
| Throw | slider moving, band 9 PERFECT pop, Auto on/off/not owned, PC/touch/gamepad hint |
| Flight | each zone colour, zone-change punch |
| Reveal | NORMAL vs mutation, NEW vs not, SUPER LUCKY vs not, longest name `SUGARKING` must fit at TextSize 84 within 1241 px |

## 7. Turn 3: windows and world UI (3a-3h)

### Shared window chrome
```
<Name>Window (Frame) AnchorPoint 0.5,0.5  Position UDim2.new(0.5,0,0.52,0)  Size 960x540 (Slimes 600x540)
├ UIStroke 5 Ink, UICorner 28, UIGradient body 34,35,43 -> 18,19,24
├ Header (Frame) Size UDim2.new(1,0,0,84)  bottom border 5 Ink (child Frame)
│ ├ UIGradient (window colour, 3 stops)  + Stripes ImageLabel (0.86) + Gloss (top 45%, white 0.65 -> 1)
│ ├ Title (TextLabel) TextSize 46, outline 4.5, left 24
│ ├ HeaderExtras (UIListLayout Horizontal, right-aligned)
│ └ Close (TextButton) 60x60, red gradient, "✕" TextSize 34
└ Body (Frame) padding 16/20/18
```
Phone: same window, same Offsets; the root UIScale (0.68) shrinks it. Do not build a second layout.

| Window | Header gradient (light / mid / dark) | Header extras |
| --- | --- | --- |
| Upgrades | 156,255,90 / 76,219,22 / 42,158,14 | Cash pill, Gems pill |
| Shop | 255,213,74 / 255,165,28 / 240,122,0 | GIFT! (blue gradient) |
| Rewards | 143,214,255 / 62,162,255 / 26,111,224 | none |
| Slime Index | 242,122,255 / 194,60,240 / 122,31,200 | none |
| My Slimes | 255,122,234 / 236,31,216 / 168,18,184 | plot pill `<placed>/<MaxSlimes>` |

Shared parts: **Tab** 48 high, `UICorner 14`, active = green gradient, inactive = dark gradient 58,61,76 -> 38,40,54 at 0.2 transparency.
**Card** dark gradient 44,46,55 -> 27,28,34, UIStroke 4 Ink, `UICorner 18`. **Divider pill** ("Featured") dark gradient, 3 px stroke, lines either side.
**Progress bar** 26-30 high, track 11,11,16, fill = green gradient (quests, index) or power gradient (XP), label centred with outline.

### 3a Upgrades
Tabs (`bolt` Power & Training / `carrot` Bait & Plot / `gem` Gem Upgrades) → tab banner 56 high in the tab's colour with stripes, title TextSize 28 + tagline → one 84 high row per shop item:
icon tile 62 (item `Color` as gradient), Title + level tag (Gold), `from ▶ to` line, buttons from `Options` (min 118 wide, label 14 + price 23).
`power_upgrade` shows Buy (green) + Buy Max (orange). States from `State`: Unaffordable = button at 0.4 transparency, Owned/Maxed = grey gradient with `PriceText`.

### 3b Robux Shop
Scrolling (`ScrollingFrame`, `AutomaticCanvasSize Y`, thin white scrollbar). Order: Featured → egg cards → Game Passes → Gem Packs → Free Gift.
Egg card 272 high: diagonal gradient from the egg `Color`, sunburst ImageLabel behind the egg (0.86), title in gold gradient text TextSize 38, tag pill (New! rainbow gradient / LIMITED dark), ODDS button.
Odds tiles 84x92 inside a 3 px frame (rarest tile = rainbow UIGradient frame): % on top (Gold), ViewportFrame with mutation ring, bonus chip at the bottom.
Buy buttons: label above, green gradient, Robux glyph (`icons/robux`) + price TextSize 30. Product id 0 → grey "Coming soon".
Pass cards 130 high in the pass colour gradient, icon 60. Owned → replace price with OWNED.

### 3c Rewards & Quests
Tabs (`calendar` Daily Rewards / `trophy` Quest Line). Section row "Daily Login · Day N" + `clock` "Resets in HHh MMm".
7 day tiles (equal width, 124 high): claimed = 0.45 transparency + `check` icon at the top-right corner; today = gold gradient, white stroke, glow, CLAIM! button; future = dark 0.2; Day 7 = epic gradient with a bigger gem.
3 quest cards: title + reward (`+N` gem), progress bar, CLAIM! (green when `Progress >= Target`, grey otherwise).
Quest Line tab (not drawn yet): one large card for `QuestLineStep` with the same bar + CLAIM!, two dimmed preview cards.

### 3d Slime Index
Left: ScrollingFrame, one row per zone: zone card 132x248 (zone gradient, white 4 px stroke + black outer, zone icon 78, %), 3 slime cards (rarity gradient always; undiscovered = black silhouette + "???"), progress bar `X/3`.
Footer 50 high: book icon + "Unlocked: X/15" with a green fill to `X/15`.
Right column 270: detail card for the selected slime (preview, name, `Rarity · chance in zone`, income + power bonus, mutation chips: found = mutation colour, not found = "?"), and the trail card (zone icon, name, bonus, LOCKED grey / EQUIP green / EQUIPPED blue).

### 3e Slimes window
Title row "IN YOUR BACKPACK N" + sort chips (Income / Rarity / Newest, active = green). Rows 84 high with a white 4 px stroke and a black outer stroke:
rarity tile 64 + ViewportFrame, mutation word (or rarity) 14, name 24, income 19, PLACE (blue gradient). Plot full → PLACE grey with "PLOT FULL".
Bottom: AUTO-PLACE BEST, orange gradient + stripes, 64 high. Empty backpack: replace the list with "Throw jelly to catch slimes!".

### 3f Pull-up training HUD
Shown while `TrainingState.active`. Hide Nav, Stats and Hotbar.
- Top centre: bar tier pill (tier gradient: Pull-Up grey, Iron steel, Crystal blue, Magma orange, Starlight violet) + "Jump or walk away to stop" (PC only).
- Left panel 290 wide at `UDim2.new(0,16,0,86)`: "This session" striped blue header, rows Reps (total), Power gained, Speed (`PullUpRepInterval`), XP per second.
- Right panel 270 wide: NEXT BAR name + gain + UPGRADE button (green, `RequestPurchase("pullup_tier",1)`). Max tier → "MAX BAR" grey.
- BONUS REP! button (gold gradient, glow, Rotation 5) at `UDim2.new(0.66,0,0.55,0)`, a 150 px timer bar under it that empties over 2.5 s → `RequestBonusRep`.
- LEVEL UP! popup: gold gradient text TextSize 64, "+5 Power" under it, pop in 0.3 s then fade after 1.2 s.
- XP bar at the bottom centre, 640 wide (phone 560): Lv badge 70x70 + "cur / req XP", "Next: +5 Power", power-gradient fill.
- Touch: red STOP circle 120 at `UDim2.new(1,-50,1,-110)`, AnchorPoint 1,1 → `RequestStopTraining`.

### 3g World signs (BillboardGui / SurfaceGui)
All use the same tokens. `BillboardGui.Size = UDim2.fromOffset(w,h)` with `LightInfluence = 0`, `AlwaysOnTop = false`, `MaxDistance = 80`.
Plot sign 290 wide (green header with owner name, income below). Collect pad: pending cash + COLLECT pill + bouncing ▼. Filled slot 200 wide (rarity gradient, slot number chip, mutation, name, income).
Locked slot grey with lock icon and price. Empty slot gold "Place Slime". Upgrade stand: orange header, `8 ▶ 12`, Cash and Gem price chips. Pull-up bar label: tier pill + 2 lines.
Custom ProximityPrompt (`Style = Custom`): dark pill, keycap E inside a hold-progress ring (gold conic → use a radial ImageLabel + UIGradient rotation), ObjectText 14 above ActionText 22.

### 3h Hub leaderboards (SurfaceGui, 310 wide each)
Header 96 high in the board colour (Richest green, Best Throws blue, Strongest orange, Rarest Slime purple) with icon + title + subtitle.
10 rows 42 high: rank medal (gold / silver / bronze gradients for 1-3, dark after), avatar headshot (`Players:GetUserThumbnailAsync`), name (truncate), value in the board colour. Rows 1-3 get a faded tint. Footer "Updates every 60 seconds".

## 8. Turn 4: states and pop-ups (4a-4h)

**Button states (all shop rows).** Available = green. Unaffordable = grey gradient at 0.45 transparency, top label "Need N more".
Owned / Maxed = grey, label "Permanent", price text `OWNED` / `MAX` (from `PriceText`). Robux item with id 0 = grey, "Coming soon", no Robux glyph.

- **4a Bait & Plot tab:** banner orange. Rows `bait_tier` (current name, `luck ▶ next name · luck`), `slot_expansion`, `boost_double_cash`.
- **4b Gem Upgrades tab:** banner teal `168,255,242 → 46,224,207 → 15,154,168`. Rows `gem_auto_throw`, `gem_lucky_charm`, `gem_slot_expansion`. Gem prices read "120 Gems".
- **4c Shop lower half:** Rainbow Egg = compact 150 high card, rainbow diagonal gradient with a 0.3 dark overlay for text contrast, LIMITED tag, Buy x1/x3 on the right.
  Gem Packs: 4 cards, gem icon grows with the pack (40 → 58), red rotated tag for `Tag`. Free Gift: gold striped card, Emerald Sakura preview, CLAIM! (hide the card once `ClaimedFreeGift`).
- **4d Quest Line tab:** 12-segment track (done green, current orange with glow, future dark). Hero card 178 high, gold diagonal gradient, white stroke + glow when claimable;
  step icon tile, title TextSize 32, progress bar, reward chips, CLAIM! 150x70. "COMING UP": next 2 steps at 0.3 transparency with lock plates. Step 13 = "All quests done!" card.
- **4e Welcome Back** (660x460, no close button, centred title 58): shown on join when offline earnings > 0. Big cash figure in gradient text 84, "Away for Xm".
  CLAIM (green) and 2X + Robux 25 (orange, developer product). **New server work:** offline income (cap and rate are design decisions; not in GameConfig yet).
- **4f Unlock pop-ups** (640 wide, top 72, no dim): striped header in kind colour + small close, 110 tile (contrasting colour), kicker / name 42 / detail,
  optional SHOP button, 8 px orange timer bar (auto-dismiss 5 s). Triggers: next `bait_tier` becomes affordable, first `ReachZone` of a zone (pays `GemsFromZone`).
  Stack up to 2, newest on top.
- **4g Gift picker** (600x540, blue header + gift icon): item chip, "Who do you want to gift?", one 88 high row per other player (headshot, DisplayName, @Name, GIFT blue).
  Gifting needs a new server flow (`MarketplaceService` purchase on behalf of a target).
- **4h Egg odds** (700x540, purple header + egg icon): one 58 high row per egg entry: rarity tile + preview with mutation ring, mutation · rarity / name,
  cash bonus chip, chance bar (gold gradient, width relative to the top chance), % in gold. Rarest row framed with a rainbow UIGradient.

## 9. Still to do

HUD toast variants, empty/plot-full Slimes states, Index EQUIP/EQUIPPED, Settings, loading screen, profile, achievements, tutorial, motion specs.
