# UI data contract

What information the UI can read, and which actions it can trigger. Plain-language tables first; code names
are in the second column so a developer can find them.

> If a screen needs something not listed here, ask the programmer. Do not hard-code it.

## 1. Player information (always available)

The server sends the whole player state to the client every time something changes (while training, every
5th rep). The HUD keeps the latest copy. These are the fields:

| Meaning | Field | Example |
| --- | --- | --- |
| Cash in the wallet | `Cash` | 1250 |
| Gems (premium currency) in the wallet | `Gems` | 35 |
| Index milestones already paid (0-5) | `IndexMilestonesClaimed` | 1 |
| Highest zone a throw has landed in (0 = never thrown) | `HighestZoneReached` | 2 |
| Daily login streak in days (0 = never claimed) | `DailyStreak` | 3 |
| Can the player claim today's daily login reward right now | `DailyCanClaim` | true |
| Which streak day (1-7+) today's claim will pay | `DailyNextDay` | 4 |
| Will claiming today reset a broken streak back to Day 1 | `DailyWillReset` | false |
| Seconds until the next UTC day (daily reward & daily quests reset) | `SecondsUntilNextDay` | 34210 |
| Current step in the linear Quest Line (1-12, or 13 when complete) | `QuestLineStep` | 3 |
| Progress toward the current Quest Line step | `QuestLineProgress` | 6 |
| UTC day number for the current Daily Quests | `DailyQuestDay` | 20780 |
| Today's 3 Daily Quests (`{ { Id, Progress, Claimed } }`) | `DailyQuests` | see `GameConfig.Quests.DailyPool` |
| Owned Robux Game Passes (`true` by pass id, checked live from Roblox) | `OwnedPasses` | `pass_x2_luck = true` |
| Is this session being saved (false = load failed or Studio without API access) | `ProgressSaved` | true |
| Strength used by the throw (after boosts and equipped slime) | `EffectiveThrowPower` | 96 |
| Raw strength gained from training | `BaseThrowPower` | 80 |
| Power upgrade level | `PowerUpgradeLevel` | 3 |
| Price of the next power upgrade | `NextPowerCost` | 68 |
| Current pull-up bar tier (1-5) | `PullUpTier` | 2 |
| Seconds one pull-up rep takes right now | `PullUpRepInterval` | 0.76 |
| Number of unlocked plot slots (8 or 12) | `MaxSlimes` | 8 |
| Longest throw, in studs | `BestDistance` | 412 |
| Money earned per second from placed slimes | `IncomePerSec` | 37 |
| Cash waiting at the collect pad | `PendingIncome` | 120 |
| Slimes caught but not placed (the hotbar / backpack) | `UnplacedSlimes` (list) | see slime record below |
| Slimes placed on slots, by slot number as text ("1", "2", ...) | `PlacedSlimesBySlot` | see below |
| Which slimes have ever been found (true/false by id) | `DiscoveredSlimes` | `meadow_sprout = true` |
| Which zone's trail is equipped (1-5) or nothing | `EquippedTrailZone` | 2 |
| Boosts owned (true/false by boost id) | `OwnedBoosts` | `double_cash = true` |
| Has the free gift been claimed | `ClaimedFreeGift` | false |
| Total throws and pull-up reps ever done | `TotalThrows`, `TotalPullUps` | 14, 62 |
| The slime used for the Throw Power bonus | `EquippedSlimeId` | `meadow_sprout` |

### A slime the player owns

| Meaning | Field | Example |
| --- | --- | --- |
| Unique id of this individual slime | `Uid` | `s_7` |
| Slime kind (look it up in [DATA-REFERENCE.md](DATA-REFERENCE.md)) | `SlimeId` | `meadow_honey` |
| Display name | `Name` | Honey Slime |
| Short word | `ShortWord` | HONEY |
| Rarity name and rank | `Rarity`, `RarityRank` | Uncommon, 2 |
| Mutation | `Mutation` | `NORMAL`, `EMERALD`, `GOLDEN`, `CRYSTAL`, `RAINBOW` |
| Money per second (already includes mutation) | `IncomePerSec` | 7 |
| Throw Power bonus when equipped | `ThrowBonus` | 4 |

## 2. Shop information (read the list, never type prices)

The shop's content is produced by one function from the player information above. Each item comes back with:

| Meaning | Field | Example |
| --- | --- | --- |
| Item id (use this to buy) | `Id` | `boost_double_cash` |
| Group | `Category` | Upgrade, Boost, Egg, Gift, Gem |
| Icon and accent colour (placeholders) | `Icon`, `Color` | 💵, blue |
| Title | `Title` | x2 Cash |
| One-line description | `Subtitle` | Double cash from every slime! |
| Price as a number | `Price` | 500 |
| Which wallet pays | `PriceKind` | `Cash` or `Gems` |
| Price as display text | `PriceText` | `$500`, `💎 150`, `FREE`, `OWNED`, `MAX`, `CLAIMED` |
| State | `State` | `Available`, `Unaffordable`, `Owned`, `Maxed`, `Claimed` |
| Buy buttons this item offers | `Options` (list) | Buy x1 / Buy x3 |

Each buy option has: quantity (`1`, `3` or `"max"`), a button label, its price, and whether the player can afford it.

Items today: see "Shop items in display order" in [DATA-REFERENCE.md](DATA-REFERENCE.md). Eggs also need the
list of possible slimes with chances; that comes from the egg table, shown in the same file.

## 3. Things the player can do (actions)

The UI asks, the server decides. A refused request does nothing except send back a message.

| What the player does | Request name | What to send | Notes |
| --- | --- | --- | --- |
| Buy anything in the shop | `RequestPurchase` | item id, quantity (1, 3 or "max") | rate limited to ~6 per second |
| Place a slime from the hotbar on a slot | `RequestPlaceOnSlot` | slime `Uid`, slot number | |
| Pick a slime up from a slot | `RequestPickupFromSlot` | slot number | goes back to the hotbar |
| Auto-place best slimes | `RequestPlaceBestSlimes` | nothing | |
| Use a slime for the throw bonus | `RequestEquipSlime` | slime kind id | no button yet |
| Equip a zone trail | `RequestEquipTrail` | zone number 1-5 | needs 100% of the zone |
| Collect cash at the pad | `RequestCollect` | nothing | no button yet; today the pad is collected by walking onto it |
| Teleport to throw line or plot | `RequestTeleport` | "ThrowLine" or "Plot" | no button exists yet |
| Throw | `RequestThrow` | meter value 0-1, and `Auto = true` for Auto-Throw | sent automatically by the throw animation; auto throws need the `auto_throw` boost and always use the fixed Auto-Throw meter value |
| Stop pull-up training | `RequestStopTraining` | nothing | also happens on jump/walk |
| Claim a Bonus Rep during pull-up training | `RequestBonusRep` | `{ Id = number }` | must match the server's currently active `TrainingBonus` offer id within its window |
| Claim today's daily login reward | `RequestClaimDaily` | nothing | manual claim from the 7-day calendar in `RewardsWindow` |
| Claim a completed quest | `RequestClaimQuest` | `{ Kind = "Line" \| "Daily", Index = number? }` | advances `QuestLineStep` or marks `DailyQuests[Index].Claimed = true` and pays Cash/Gems |

Pull-up training starts automatically when the plot owner walks within `GameConfig.PullUp.AutoStartRadius` (6 studs) of their bar's `TrainSpot`, and re-arms after walking out past `RearmRadius` (9 studs). The bar's **E key / ProximityPrompt** upgrades the pull-up bar tier (`pullup_tier`).

## 4. Things the game tells the UI (events)

| What happened | Event name | What it contains | Today's reaction |
| --- | --- | --- | --- |
| Show a message | `ToastNotify` | message text, kind (`info`, `success`, `warn`, `cash`, `power`, `gems`) | yellow/red/green/blue banner at top; `gems` is used for the daily reward |
| Player state changed | `PlayerStateSync` | the player information in section 1 | all screens refresh |
| Training started or stopped | `TrainingState` | active yes/no, seconds per rep | plays/stops the animation |
| A pull-up rep was paid | `TrainingRep` | power gained, new total, seconds per rep | floating "+X" |
| Someone threw | `ThrowBroadcast` | origin, luck (meter, bait, `BoostLuck` from Lucky Charm), zone landed, caught slime (id, name, mutation, income), "1 in X", super lucky, new discovery, cash earned, Gems earned (`GemsEarned` total, split into `GemsFromCatch`, `GemsFromZone`, `GemsFromIndex`), `IsAuto` | flight HUD and reveal cutscene; the reveal shows "+N 💎" next to the income |

Message kinds `success` and `info` currently look the same (yellow); `power` has no colour of its own. A designer
can give each kind its own look.

## 5. Look-and-feel pieces that already exist

Reuse these or replace them in one place.

| Piece | Where | What it does |
| --- | --- | --- |
| Bevel button | `UiKit.CreateBevelButton` | chunky two-tone button, hover grow, click press |
| Gloss gradient | `UiKit.AddGlossGradient` | glossy highlight on a card |
| Outline | `UiKit.AddStroke` | dark outline on text and frames |
| Rounded corners | `UiKit.AddCorner` | |
| Window open/close | `UiKit.ToggleModalAnimated` | window pops in with the dim backdrop |
| 3D slime preview | `UiKit.CreateSlimeViewport` | live rotating 3D slime inside a card, or a dark silhouette |
| Responsive scale | `UiKit.AttachResponsiveScale` | scales a whole screen to the window size |
| Colours by rarity, mutation, zone | in the game's configuration | see [DATA-REFERENCE.md](DATA-REFERENCE.md) |
| Number shortening | `GameConfig.FormatNumber` | 1500 becomes 1.5K |
