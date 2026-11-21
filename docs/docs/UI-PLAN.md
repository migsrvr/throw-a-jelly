# UI plan: Robux Store, Upgrades + Gems, Rewards, and a step-on pull-up bar

> Status: **planned, not started** (written 2026-11-22). Build in order: Phase 1, then 2, then 3, with tests passing after each.

## Decisions (from the 2026-11-22 planning session)
- **Four shop-type windows:**
  1. **Robux Store:** things bought with Robux.
  2. **Upgrades:** the Jelly Bait upgrade plus everything bought with Gems (Auto-Throw, Lucky Charm, and more later).
  3. **Rewards:** daily reward claim plus quests.
  4. **Shop (Cash), kept:** eggs, Throw Power, x2 boosts, free gift.
- **The pull-up bar upgrade leaves the shop.** Stepping into range of your own bar starts training automatically (no E). The bar's E prompt becomes **"Upgrade Bar ($X)"**.
- **Robux:** build the UI and the purchase code now, and paste the product ids in later.
- **Daily reward:** manual claim on a 7-day calendar (replaces today's auto-claim on join).
- **Quests:** both a linear quest line and 3 daily quests.
- All new windows use the programmer-placeholder styling (UiKit bevel/gloss) so the designer can restyle them later.

## HUD layout
- Left column (top to bottom): **Index**, **Shop** (Cash), **Upgrades** (🥕 / 💎)
- Right column: **Rewards** (🎁, red "!" badge when something can be claimed), **Robux Store** (R$), **Slimes**
- Only one window open at a time (same as today: the nav handler closes the others, then `UiKit.ToggleModalAnimated`).

To keep `HudController.client.luau` (1,300 lines) from growing, each new window goes in its own ModuleScript under `src/StarterPlayer/StarterPlayerScripts/HudWindows/` (`UpgradesWindow.luau`, `RobuxStoreWindow.luau`, `RewardsWindow.luau`). Each exports `Build(parent, ctx) -> { Frame, Refresh(state) }`, and `ctx` carries `buyShopItem`, `bindShopLabel`, the modal scrim and the remotes. HudController creates the nav buttons, keeps the "one window open" rule, and calls each `Refresh(currentState)` on every `PlayerStateSync`.

## Phase 1: Shop split + step-on bar
**Shop (Cash)** keeps the egg cards, `power_upgrade` (Buy + Buy Max, which the game already supports), `boost_double_cash`, `boost_double_power` and `free_gift`. Remove `pullup_tier`, `bait_tier` and the Gem card from it.

**Upgrades window:**
- *Upgrades* section: `bait_tier` (current to next bait, luck before and after), `slot_expansion` ($5K)
- *Gem Shop* section: every `Category = "Gem"` catalog item (moved from the Shop; same generic loop)
- 💎 balance in the header. Everything goes through `bindShopLabel` / `buyShopItem`, so no prices are hard-coded.

**Step-on pull-up bar** (`PlotService.luau`, `TrainingController.client.luau`, `GameConfig.PullUp`):
- New config: `AutoStartRadius = 6` (studs from `TrainSpot`, or the bar if there's no TrainSpot) and `RearmRadius = 9`.
- Server: a throttled check (every 0.2 s, inside the existing Heartbeat) for each plot's owner. If they're not training, are **armed**, and their root is inside `AutoStartRadius`, call the existing `startTraining`. A session is disarmed by `stopTraining`, and re-armed only after the owner walks out past `RearmRadius`, so jumping off doesn't snap them straight back on.
- Client: walking only counts as "stop" once the move input has been released after the session started (otherwise walking into the zone would stop training on the first frame). Jump still stops right away.
- The bar's `ProximityPrompt` becomes the upgrade: `ActionText = "Upgrade Bar"`, `ObjectText = "<next tier name> ($cost)"`, or disabled at MAX. It calls `PlayerStateService.Purchase(player, "pullup_tier", 1)`. The server refreshes the text in `RefreshPlotVisuals` (which already runs on every sync). For other players' bars the client sets `prompt.Enabled = false` locally. `toggleTraining` and `setPromptText` are removed.
- The bar billboard shows "Walk under the bar to train" plus the tier name (and fixes the `$$75` text there).

## Phase 2: Rewards window (daily calendar + quests)
**Daily reward: manual claim**
- Remove the auto-claim on join and the 60 s loop in `PlayerStateService`. Add a `RequestClaimDaily` remote that calls the existing `ProgressionLogic.ClaimDailyReward`.
- New pure helper `ProgressionLogic.GetDailyStatus(profile, dayNumber) -> { CanClaim, NextStreakDay, WillReset }`. The server sends `DailyCanClaim`, `DailyNextDay` and `SecondsUntilNextDay` in `PlayerStateSync`.
- UI: a 7-tile strip from `GameConfig.Gems.DailyRewards`. Claimed days are ticked, today glows with CLAIM, future days are dimmed, and a "resets in hh:mm" countdown sits underneath.

**Quests** (new pure `src/ReplicatedStorage/Shared/QuestLogic.luau` + `GameConfig.Quests`, tested in Lune)
- Event counters recorded from the existing reducers, so tests cover them: `Throw`, `CatchRarity`, `ReachZone`, `PullUpRep`, `BonusRep`, `PerfectThrow` (recorded in ThrowService), `PlaceSlime`, `HatchEgg`, `BuyBait`, `Discover`, `EarnCash`.
- **Quest line** (never resets, one step at a time, CLAIM to advance), about 12 starter steps that double as the tutorial. For example: throw once, place a slime, train 10 reps, buy Berry Jelly, reach Crystal Cave, discover 5 slimes, land a PERFECT, reach Lava Fields, buy Auto-Throw... Each pays Cash and/or Gems.
- **Daily quests:** 3 per UTC day, picked from a template pool with a seed of (UserId, day) so the pick is deterministic and testable. Progress resets at midnight. Each pays Gems or Cash on claim.
- Profile + serializer fields: `QuestLineStep`, `QuestLineProgress`, `DailyQuestDay`, `DailyQuests = { { Id, Progress, Claimed } }`. New remote `RequestClaimQuest { Kind = "Line" | "Daily", Index }`.
- UI: two tabs, **Daily** (calendar on top, 3 daily quest cards with progress bars below) and **Quest Line** (the current step big, plus the next 2 steps greyed out).
- Rewards button badge = `DailyCanClaim` or any quest ready to claim.

## Phase 3: Robux Store (UI + purchase code, ids later)
- New `GameConfig.Robux`:
  - `GemPacks`: developer products. Suggested: 100 / 550 / 1,200 / 2,600 Gems at 25 / 99 / 199 / 399 R$, `ProductId = 0` for now.
  - `Passes`: game passes. Suggested: **x2 Luck** and **x2 Cash**, plus **VIP** (+10% income and a chat tag), `PassId = 0` for now.
- New server `MonetizationService.luau`:
  - `ProcessReceipt`: find the product, grant Gems to the loaded profile, record the `PurchaseId` in a capped `ProcessedReceipts` list on the profile (so a repeat receipt grants nothing), and **save with `DataService.Save` before returning `PurchaseGranted`**. If the player isn't loaded or the save fails, return `NotProcessedYet`, so Roblox retries.
  - Passes: `UserOwnsGamePassAsync` on join, plus `PromptGamePassPurchaseFinished`, kept in a runtime-only `OwnedPasses` (not saved; Roblox is the source of truth). Pass effects plug into `GetBoostLuckMultiplier` and the cash multipliers.
- Client: cards call `MarketplaceService:PromptProductPurchase` or `PromptGamePassPurchase`. Any item with id `0` shows a disabled **"Coming soon"** button. Owned passes show OWNED.
- Docs: a short "how to create the products and paste the ids" section in `shop-catalog.md`.

## Files
- Edit: `HudController.client.luau`, `TrainingController.client.luau`, `PlotService.luau`, `PlayerStateService.luau`, `ThrowService.luau`, `GameConfig.luau`, `ProgressionLogic.luau`, `ProfileSerializer.luau`, `Remotes.luau`
- New: `HudWindows/UpgradesWindow.luau`, `HudWindows/RewardsWindow.luau`, `HudWindows/RobuxStoreWindow.luau`, `Shared/QuestLogic.luau`, `ServerScriptService/MonetizationService.luau`, `tests/Quests.spec.luau`, plus new cases in `tests/Gems.spec.luau` and `tests/ProfileSerializer.spec.luau`
- Docs: `UI-HANDOFF.md` (new windows and the new bar flow), `UI-DATA-CONTRACT.md`, `shop-catalog.md`, `SYSTEMS-STATUS.md`, `notion.md`; regenerate `DATA-REFERENCE.md` (quests, daily calendar, Robux list)

## Verification
1. `lune run tests/run-tests`: all pass, with new tests for daily status, quest progress/claim/reset, the deterministic daily pick, the receipt dedupe reducer, and the serializer round trip of the new fields.
2. Compile check of every `.luau`, then `rojo build`.
3. Studio:
   - Walk under your bar and training starts. Jump or walk away and it stops, and it doesn't restart until you step out and back in. E at the bar upgrades it.
   - Six nav buttons, one window open at a time.
   - Claim the daily reward, then rejoin and it's still claimed. Complete a quest-line step and a daily quest, then claim them.
   - Robux cards say "Coming soon". With a real test product id, a Studio test purchase grants Gems and they survive a rejoin.

## Open choices (defaults used unless changed)
- Robux gem pack sizes/prices and the pass list (x2 Luck, x2 Cash, VIP) are suggestions.
- Quest line steps and daily quest rewards are suggestions; exact numbers go in `GameConfig.Quests`.
