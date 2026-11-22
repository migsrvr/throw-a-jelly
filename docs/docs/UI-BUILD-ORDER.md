# UI build order

For Claude Code. Build in this order; each step is shippable. Mockup ids refer to `Throw a Jelly UI.dc.html`.
Read [UI-MOCKUP-SPEC.md](UI-MOCKUP-SPEC.md) for sizes and colours, [UI-MOTION.md](UI-MOTION.md) for timings.

## 0. Foundations (do first)
- `src/ReplicatedStorage/Shared/UiAssets.luau`: fill in asset ids after uploading `icons/png` and `textures`.
- Extend `UiKit`: `CreateGradientButton(kind)` (green / orange / blue / red / grey), `AddGradient(frame, light, mid, dark)`, `AddStripes(frame)`,
  `CreateIconPlate(icon, size)`, `CreateWindow(title, headerColours, size)` (header + stripes + gloss + close), `CreateTabs(list)`, `CreateProgressBar()`.
  Every screen below uses only these.
- Phone UIScale rule (spec section 0).

## 1. HUD (2a, 5a)
Files: `HudController.client.luau`. Nav buttons, stats, objective + toasts (all 6 kinds), hotbar with slot states, PlaceButton, tutorial arrow.

## 2. Throw loop (2b, 2c, 2d, 5c)
Files: `ThrowController.client.luau`. Restyle the callout, PERFECT tag, hint and AUTO toggle around the existing meter. Flight banner. Reveal with rarity tiers.

## 3. Upgrades (3a, 4a, 4b)
Files: `HudWindows/UpgradesWindow.luau`. Window, 3 tabs, tab banners, item rows, button states from `State`.

## 4. Slimes + Index (3d, 3e, 5b)
Files: `HudController.client.luau` (sections 5 and 7). Backpack rows, sorting, empty and plot-full states; Index rows, detail panel, trail states, complete zone.

## 5. Training (3f, 5d)
Files: `TrainingController.client.luau`, `PlotService.luau` (labels). Training HUD, next-bar card, BONUS REP!, LEVEL UP!, summary, tier pills.

## 6. Rewards (3c, 4d)
Files: `HudWindows/RewardsWindow.luau`. Daily strip, daily quests, Quest Line track and hero card.

## 7. Shop + pop-ups (3b, 4c, 4h, 4g)
Files: `HudWindows/RobuxStoreWindow.luau`. Eggs, passes, gem packs, free gift, odds pop-up. Gift picker needs new server work (gift purchase flow).

## 8. World UI (3g, 3h)
Files: `PlotService.luau` and a new `LeaderboardService.luau`. Billboards, custom ProximityPrompt, hub boards.

## 9. New systems (4e, 4f)
Welcome Back needs offline income on the server. Unlock pop-ups need a server event for "bait affordable" and "first zone reached".

---

## Status (all steps built)

Steps 0-9 are in. Notes on what differs from the mockups or needs a decision:

- **Welcome Back** (`GameConfig.Offline`): pays 50% of income for the time away, min 2 min, capped at 4 h. Edit `Rate`, `MinAwaySeconds`, `MaxAwaySeconds`. The 2X button stays grey until `DoubleProductId` is a real developer product id (the server already handles that receipt).
- **Gifting**: the whole flow exists (picker, `RequestGift`, receipt grants to the target). The GIFT! button in the Shop only appears once at least one gem pack or egg has a real `ProductId`.
- **Unlock pop-ups**: server-driven from `PlayerStateService.Sync` (next bait affordable, first zone reached). Rules are in `ProgressionLogic.NextUnlockPopups`.
- **Leaderboards**: show the players in the current server and refresh every 60 s. Rows are 32 px high (the panel is 16x22 studs, so the spec's 42 px rows do not fit). Cross-server boards would need OrderedDataStores.
- **Throw reveal**: no slime ViewportFrame, rarity rings or screen shake (the slime is a 3D model in the world).
- **Custom prompt**: the hold ring is a fade plus a thin progress bar, not a true conic ring.
- **Slot signs**: filled slot signs replace the slime model's own billboard.
