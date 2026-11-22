# Data reference (names, numbers, colours)

> **Generated file. Do not edit by hand.** It is produced from the game's configuration by
> `lune run scripts/gen-docs-data`, so it always matches the game. Colours are given as hex codes.
> If a number looks wrong, it is tuned in `src/ReplicatedStorage/Shared/GameConfig.luau`, not here.

Use this for layout and copywriting: longest names, how many items fit in a row, which colours go with what.

## Zones (5)

A zone is a stretch of the throwing lane. Where the bait lands decides which slimes can be caught.
Reaching a zone needs enough Throw Power. Catching every slime in a zone unlocks that zone's trail.

| # | Name | Icon | Colour | Lane distance (studs) | Throw Power needed | Cash per stud | Trail | Trail bonus |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Meadow | 🌿 | #7CFF8A | 0 - 240 | 0 | 0.25 | Leaf Trail | +15% XP |
| 2 | Crystal Cave | 💎 | #6FC3FF | 240 - 480 | 50 | 0.75 | Crystal Trail | +20% Cash |
| 3 | Lava Fields | 🌋 | #FF844A | 480 - 720 | 250 | 2.2 | Magma Trail | +25% Power |
| 4 | Frost Peaks | ❄️ | #A5EBFF | 720 - 960 | 1.0K | 6.5 | Frost Trail | +35% Cash |
| 5 | Candy Land | 🍬 | #FF7AB8 | 960 - 1200 | 5.0K | 20 | Sugar Trail | +50% All |

## Rarity colours

Used for slime card backgrounds, names and borders. Six levels, from most to least common.

| Rarity | Colour |
| --- | --- |
| Common | #C8EBC8 |
| Uncommon | #78F091 |
| Rare | #64C3FF |
| Epic | #CD82FF |
| Legendary | #FFCD46 |
| Mythic | #FF6EC3 |

## Slimes (15)

Each zone has three slimes. "Chance" is the share of catches in that zone before any luck bonus.
"Income" is what a normal (non-mutated) slime earns per second while placed on a plot slot.
"Short word" is the big word shown in the reveal screen.

| Zone | Name | Short word | Rarity | Chance in zone | Income / sec | Throw Power bonus | Body colour | Core colour |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 🌿 Meadow | Sprout Slime | SPROUT | Common | 65% | $2 | +0 | #6EEB73 | #C3FFAF |
| 🌿 Meadow | Honey Slime | HONEY | Uncommon | 27% | $5 | +4 | #FFC841 | #FFF096 |
| 🌿 Meadow | Sakura Bloom Slime | SAKURA | Rare | 8% | $12 | +10 | #FF91C3 | #FFDCF0 |
| 💎 Crystal Cave | Quartz Slime | QUARTZ | Uncommon | 62% | $18 | +15 | #6ECDFF | #C8F5FF |
| 💎 Crystal Cave | Amethyst Slime | AMETHYST | Rare | 28% | $38 | +32 | #B473FF | #EBC3FF |
| 💎 Crystal Cave | Prism Geode Slime | PRISM | Epic | 10% | $75 | +60 | #55FFE6 | #FFFFFF |
| 🌋 Lava Fields | Ember Slime | EMBER | Rare | 62% | $110 | +95 | #FF7337 | #FFD75F |
| 🌋 Lava Fields | Obsidian Core Slime | OBSIDIAN | Epic | 28% | $220 | +180 | #4B375F | #FF5F28 |
| 🌋 Lava Fields | Solar Flare Slime | SOLAR | Legendary | 10% | $450 | +340 | #FFCD32 | #FFFFDC |
| ❄️ Frost Peaks | Glacier Slime | GLACIER | Epic | 62% | $650 | +480 | #87E1FF | #E1FAFF |
| ❄️ Frost Peaks | Aurora Borealis Slime | AURORA | Legendary | 28% | $1.4K | +900 | #5AFFC3 | #C38CFF |
| ❄️ Frost Peaks | Cryo Monarch Slime | MONARCH | Mythic | 10% | $2.8K | +1.6K | #46A5FF | #FFFFFF |
| 🍬 Candy Land | Gumdrop Slime | GUMDROP | Legendary | 62% | $4.2K | +2.4K | #FF78BE | #FFE1F0 |
| 🍬 Candy Land | Cotton Cloud Slime | COTTON | Mythic | 28% | $9.0K | +4.2K | #C391FF | #82EBFF |
| 🍬 Candy Land | Royal Sugar King Slime | SUGARKING | Mythic | 10% | $20.0K | +7.5K | #FFD74B | #FF69B9 |

## Mutations (5)

A mutation is a bonus variant that any slime can roll. It tints the slime and multiplies its income.
"Normal" has no name or label in the UI.

| Mutation | Income multiplier | Roll weight | "1 in X" odds get this much longer | Colour |
| --- | --- | --- | --- | --- |
| (Normal - no label) | x1 | 72 | x1 | #F0F5FF |
| EMERALD | x1.5 | 16 | x4 | #50FF87 |
| GOLDEN | x2.5 | 7 | x12 | #FFD741 |
| CRYSTAL | x4 | 3.5 | x25 | #69E6FF |
| RAINBOW | x7.5 | 1.5 | x60 | #FF78DC |

## Throw meter segments (9)

The vertical meter has nine coloured bands. Where the slider stops decides the bonus. Bottom = band 1 (worst).
Stopping in the top band is a **PERFECT!** throw: a gold "PERFECT! +20" callout plus the biggest power bonus.

| Band | Colour | Bonus Throw Power | Luck multiplier | Callout |
| --- | --- | --- | --- | --- |
| 1 | #EB4137 | +1 | 1.00x |  |
| 2 | #F56932 | +3 | 1.03x |  |
| 3 | #FA9132 | +5 | 1.06x |  |
| 4 | #FFB937 | +7 | 1.10x |  |
| 5 | #F5DC3C | +9 | 1.15x |  |
| 6 | #CDEB41 | +12 | 1.22x |  |
| 7 | #A0F04B | +14 | 1.32x |  |
| 8 | #73F555 | +17 | 1.48x |  |
| 9 | #46FA69 | +20 | 1.75x | PERFECT! |

## Flight luck

Luck decides how likely rarer slimes and mutations are. It is shown live as "1.XXx LUCK" while the bait flies,
and climbs the further the bait goes: +1.00x for every 350 studs, multiplied by the meter band luck and the Jelly Bait luck.

| Bait \ distance | 240 studs | 480 studs | 720 studs | 960 studs | 1200 studs |
| --- | --- | --- | --- | --- | --- |
| Carrot Jelly | 1.69x | 2.37x | 3.06x | 3.74x | 4.43x |
| Berry Jelly | 2.28x | 3.20x | 4.13x | 5.05x | 5.98x |
| Crystal Honey | 3.12x | 4.39x | 5.66x | 6.92x | 8.19x |
| Magma Tart | 4.38x | 6.17x | 7.95x | 9.73x | 11.51x |
| Starlight Cake | 6.74x | 9.49x | 12.23x | 14.97x | 17.71x |

(Table uses meter band 1. A PERFECT throw multiplies every value by the top band's luck.)

## Jelly Bait tiers (5)

Bought in the Shop. Better bait does not throw further; it multiplies the luck of every throw.

| Tier | Name | Cost | Luck multiplier | Colour |
| --- | --- | --- | --- | --- |
| 1 | Carrot Jelly | (starting bait) | 1.00x | #FF7D28 |
| 2 | Berry Jelly | $600 | 1.35x | #C846A0 |
| 3 | Crystal Honey | $8.0K | 1.85x | #FFCD46 |
| 4 | Magma Tart | $120.0K | 2.60x | #FF5F2D |
| 5 | Starlight Cake | $2.00M | 4.00x | #AA96FF |

## Pull-up bar tiers (5)

Training on the bar gives Training XP. A better bar gives more XP per rep and also does reps faster.

| Tier | Name | Upgrade cost | XP per rep | Rep speed multiplier |
| --- | --- | --- | --- | --- |
| 1 | PULL-UP BAR | (starting bar) | +2 | x1 |
| 2 | IRON BAR | $350 | +8 | x1.15 |
| 3 | CRYSTAL BAR | $4.5K | +32 | x1.3 |
| 4 | MAGMA BAR | $75.0K | +140 | x1.5 |
| 5 | STARLIGHT BAR | $1.20M | +600 | x1.75 |

### Strength levels

Training XP fills a level bar. Every level up gives **+5 Throw Power** and a "LEVEL UP!" popup.
While training, a **BONUS REP!** button pops up every 4-6 seconds; clicking it within 2.5s gives 3x the XP of one rep.

| Level | XP to next level | Total XP from level 1 | Throw Power from levels |
| --- | --- | --- | --- |
| 1 | 10 | 0 | +0 |
| 2 | 25 | 10 | +5 |
| 3 | 44 | 35 | +10 |
| 4 | 64 | 79 | +15 |
| 5 | 87 | 143 | +20 |
| 6 | 112 | 230 | +25 |
| 7 | 138 | 342 | +30 |
| 8 | 165 | 480 | +35 |
| 9 | 194 | 645 | +40 |
| 10 | 223 | 839 | +45 |
| 20 | 570 | 4.6K | +95 |
| 30 | 986 | 12.1K | +145 |
| 40 | 1.5K | 24.0K | +195 |
| 50 | 2.0K | 40.8K | +245 |

### How long one pull-up takes

Seconds per rep. It gets faster as the player gets stronger and with better bars, never slower than 1.6s and never faster than 0.35s.
The rep animation is played at exactly this speed.

| Throw Power (strength) | PULL-UP BAR | IRON BAR | CRYSTAL BAR | MAGMA BAR | STARLIGHT BAR |
| --- | --- | --- | --- | --- | --- |
| 5 | 1.29s | 1.12s | 0.99s | 0.86s | 0.74s |
| 50 | 0.87s | 0.76s | 0.67s | 0.58s | 0.50s |
| 200 | 0.70s | 0.61s | 0.54s | 0.47s | 0.40s |
| 1.0K | 0.56s | 0.49s | 0.43s | 0.38s | 0.35s |
| 5.0K | 0.47s | 0.41s | 0.36s | 0.35s | 0.35s |
| 20.0K | 0.41s | 0.36s | 0.35s | 0.35s | 0.35s |

## Shop

### Shop items in display order

These are the shop's building blocks. A button or card in the shop = one row here.

| Item id | Group | Icon | Paid with | What it does | Colour |
| --- | --- | --- | --- | --- | --- |
| power_upgrade | Upgrade | ⚡ | Cash | Raises Throw Power by one upgrade level (price grows each level) | #EB962D |
| pullup_tier | Upgrade | 💪 | Cash | Upgrades the pull-up bar to the next tier | #379BF0 |
| bait_tier | Upgrade | 🥕 | Cash | Upgrades the Jelly Bait to the next quality tier (more luck) | #FF7D28 |
| egg_enchanted | Egg | 🥚 | Robux | Hatches 1 or 3 slimes with the odds listed below | #AF6EFF |
| egg_rainbow | Egg | 🌈 | Robux | Hatches 1 or 3 slimes with the odds listed below | #FF78C8 |
| free_gift | Gift | 🎁 | Cash | One-time free slime | #FFCD37 |
| gem_slot_unlock | Gem | 🧺 | Gems | Unlocks locked Plot Slots 9-12 one-by-one with Gems (or all 4 via +4 Plot Slots Pass) | #5FC878 |
| gem_auto_throw | Gem | 🤖 | Gems | Permanent boost (see boosts below) | #50D2E6 |
| gem_money_2x | Gem | 💵 | Gems | Upgrades a permanent multiplier track (2x -> 4x -> 6x -> 8x -> 10x) with Gems or Robux Pass | #37C3FA |
| gem_gems_tier | Gem | 💎 | Gems | Upgrades a permanent multiplier track (2x -> 4x -> 6x -> 8x -> 10x) with Gems or Robux Pass | #4BD2FF |
| gem_power_tier | Gem | 💪 | Gems | Upgrades a permanent multiplier track (2x -> 4x -> 6x -> 8x -> 10x) with Gems or Robux Pass | #AA69FF |
| gem_luck_tier | Gem | 🍀 | Gems | Upgrades a permanent multiplier track (2x -> 4x -> 6x -> 8x -> 10x) with Gems or Robux Pass | #55E173 |

### Boosts

All boosts are permanent once bought.

| Name | Description | Price | Colour |
| --- | --- | --- | --- |
| Auto-Throw | Throws automatically at the line (3 PERFECT / 2 GREAT bag)! | 2.0K Gems | #50D2E6 |
| 2x Gems | 2x Gems from catches, quests, zones & daily! | 2.5K Gems | #46C8FF |
| 4x Gems | 4x Gems from catches, quests, zones & daily! | 6.0K Gems | #37AFFF |
| 6x Gems | 6x Gems from catches, quests, zones & daily! | 12.0K Gems | #6991FF |
| 8x Gems | 8x Gems from catches, quests, zones & daily! | 22.0K Gems | #A06EFF |
| 10x Gems | MAX 10x Gems from every in-game source! | 38.0K Gems | #EB64FF |
| 2x Training Power | 2x Pull-Up XP on every rep! | 1.8K Gems | #A56EFF |
| 4x Training Power | 4x Pull-Up XP on every rep! | 4.5K Gems | #C35FFF |
| 6x Training Power | 6x Pull-Up XP on every rep! | 9.5K Gems | #EB5FD7 |
| 8x Training Power | 8x Pull-Up XP on every rep! | 17.5K Gems | #FF6E91 |
| 10x Training Power | MAX 10x Pull-Up XP on every rep! | 30.0K Gems | #FF9641 |
| 2x Luck | Permanent 2x Luck on every throw! | 2.0K Gems | #5AE178 |
| 4x Lucky | Permanent 4x Luck for rare & Rainbow slimes! | 5.0K Gems | #41EB9B |
| 6x Lucky | Permanent 6x Luck for Mythic & Rainbow rolls! | 10.5K Gems | #37E1D2 |
| 8x Lucky | Permanent 8x Luck on every throw! | 19.0K Gems | #82C8FF |
| 10x Luck | MAX 10x Luck on every throw! | 32.0K Gems | #FFCD3C |
| 2x Money | Permanent 2x Cash from slimes & throws! | 2.2K Gems | #37C3FA |

### Eggs (Robux-only)

**ENCHANTED EGG** (tag: "New!") - R$ 49 for 1 (ProductId 0), R$ 129 for 3 (ProductId 0). Accent colour #AF6EFF.

| Slime | Mutation | Chance | Bonus label shown on the card |
| --- | --- | --- | --- |
| Honey Slime | EMERALD | 40% | 150% |
| Sakura Bloom Slime | NORMAL | 27% | 175% |
| Quartz Slime | EMERALD | 18% | 250% |
| Amethyst Slime | GOLDEN | 10% | 350% |
| Prism Geode Slime | CRYSTAL | 4% | 550% |
| Solar Flare Slime | RAINBOW | 1% | 900% |

**RAINBOW EGG** (tag: "LIMITED") - R$ 149 for 1 (ProductId 0), R$ 399 for 3 (ProductId 0). Accent colour #FF78C8.

| Slime | Mutation | Chance | Bonus label shown on the card |
| --- | --- | --- | --- |
| Prism Geode Slime | RAINBOW | 45% | 750% |
| Obsidian Core Slime | RAINBOW | 28% | 750% |
| Solar Flare Slime | RAINBOW | 16% | 750% |
| Aurora Borealis Slime | RAINBOW | 8% | 750% |
| Cotton Cloud Slime | RAINBOW | 2.5% | 750% |
| Royal Sugar King Slime | RAINBOW | 0.5% | 999% |

### Free gift

"Free Slime!" - "Claim your free Emerald Honey Slime!" (Honey Slime, EMERALD). Can be claimed once per player.

## Plot slots

Every plot starts capped at 8 slime slots. Slots 9-12 are locked and can only be unlocked 1-by-1 with Gems (1.5K / 2.5K / 4.0K / 6.0K Gems) or all 4 at once via the "+4 Plot Slots" Robux Pass.

## Gems (premium currency)

Shown as 💎 in the HUD and the shop. Earned slowly by playing (see `docs/docs/ECONOMY-BASELINE.md` for hourly F2P targets and the 8+ hour grind floor); spent in the Gem Upgrades tab or skipped via Robux Passes & Gem Packs.

### Index milestones (paid once each)

| Slimes discovered | Gems |
| --- | --- |
| 3 | +5 |
| 6 | +12 |
| 9 | +25 |
| 12 | +45 |
| 15 | +90 |

### First time reaching a zone (paid once per zone)

A throw that lands in a zone for the first time pays that zone and every zone before it that wasn't paid yet.

| Zone | Gems |
| --- | --- |
| 🌿 Meadow | +3 |
| 💎 Crystal Cave | +8 |
| 🌋 Lava Fields | +18 |
| ❄️ Frost Peaks | +35 |
| 🍬 Candy Land | +75 |

### Daily login streak

Claimed manually once per UTC day in the Rewards window (7-day calendar). Missing a day restarts at day 1.
After day 7 the streak keeps paying the day-7 amount.

| Streak day | Gems |
| --- | --- |
| 1 | +5 |
| 2 | +8 |
| 3 | +12 |
| 4 | +16 |
| 5 | +22 |
| 6 | +30 |
| 7 | +50 |

### Rare catches (throws only, not eggs)

A caught slime pays its rarity amount plus its mutation amount (multiplied by owned 2x-10x Gems tiers & VIP). Anything not listed pays 0.

| Rarity or mutation | Gems |
| --- | --- |
| Mythic | +1 |
| CRYSTAL | +1 |
| RAINBOW | +2 |

### Auto-Throw

Once unlocked (via Gems or the Auto-Throw Robux Pass), an AUTO toggle appears under the visible vertical throw meter.
While ON, the meter smoothly locks onto the next target from a server-shuffled 5-throw bag (3 PERFECT + 2 GREAT per 5 throws) and fires after 0.8s.

## Quests

### Quest Line (12 steps, linear, never resets)

| Step | Id | Title | Event | Target | Reward |
| --- | --- | --- | --- | --- | --- |
| 1 | line_throw_1 | Throw Jelly Once | Throw | 1 | 3 Gems + $40 |
| 2 | line_place_1 | Place a Slime on Your Plot | PlaceSlime | 1 | 3 Gems + $75 |
| 3 | line_reps_10 | Train 10 Pull-Up Reps | PullUpRep | 10 | 5 Gems + $120 |
| 4 | line_bonus_1 | Tap a Bonus Rep Pop-Up | BonusRep | 1 | 5 Gems + $200 |
| 5 | line_bait_2 | Buy Berry Jelly Bait | BuyBait | 2 | 8 Gems + $350 |
| 6 | line_zone_2 | Reach Crystal Cave (Zone 2) | ReachZone | 2 | 10 Gems + $750 |
| 7 | line_discover_5 | Discover 5 Slimes in the Index | Discover | 5 | 12 Gems + $1.5K |
| 8 | line_perfect_1 | Land a PERFECT! Throw | PerfectThrow | 1 | 15 Gems + $2.5K |
| 9 | line_place_3 | Place 3 Slimes on Your Plot | PlaceSlime | 3 | 15 Gems + $4.0K |
| 10 | line_zone_3 | Reach Lava Fields (Zone 3) | ReachZone | 3 | 20 Gems + $12.0K |
| 11 | line_reps_100 | Complete 100 Pull-Up Reps | PullUpRep | 100 | 25 Gems + $25.0K |
| 12 | line_zone_4 | Reach Frost Peaks (Zone 4) | ReachZone | 4 | 40 Gems + $80.0K |

### Daily Quest Pool (8 templates, 3 picked per UTC day)

| Id | Title | Event | Target | Reward |
| --- | --- | --- | --- | --- |
| daily_throws_5 | Throw Jelly 5 Times | Throw | 5 | 5 Gems |
| daily_throws_15 | Throw Jelly 15 Times | Throw | 15 | 8 Gems |
| daily_reps_25 | Do 25 Pull-Up Reps | PullUpRep | 25 | 6 Gems |
| daily_bonus_3 | Hit 3 Bonus Rep Pop-Ups | BonusRep | 3 | 8 Gems |
| daily_perfect_2 | Land 2 PERFECT! Throws | PerfectThrow | 2 | 10 Gems |
| daily_rare_2 | Catch 2 Rare+ Slimes | CatchRarity | 2 | 10 Gems |
| daily_place_2 | Place 2 Slimes on Your Plot | PlaceSlime | 2 | 6 Gems + $500 |
| daily_cash_500 | Earn $500 Cash from Throws | EarnCash | 500 | 7 Gems |

## Robux Store

### Game Passes

| Id | Name | Icon | Robux (R$) | PassId | Effect | Colour |
| --- | --- | --- | --- | --- | --- | --- |
| pass_extra_slots | +4 Plot Slots | 🧺 | 249 | 0 | Instantly unlock all 4 locked plot slots (8 -> 12 Slimes)! | #5FD77D |
| pass_auto_throw | Auto-Throw | 🤖 | 199 | 0 | Auto-throws at the line with a 3 PERFECT / 2 GREAT bag! | #50D2E6 |
| pass_x2_cash | 2x Money | 💵 | 199 | 0 | Permanent 2x Cash from slimes & throws! | #37C3FA |
| pass_vip | VIP | 👑 | 299 | 0 | +25% Cash, +25% Earned Gems & [VIP] chat tag! | #FFC332 |
| pass_x2_luck | 2x Luck | 🍀 | 179 | 0 | Permanent 2x Luck on every throw! | #5AE178 |
| pass_luck_4x | 4x Lucky | 🍀 | 349 | 0 | Permanent 4x Luck for rare & Rainbow slimes! | #41EB9B |
| pass_luck_6x | 6x Lucky | 🍀 | 549 | 0 | Permanent 6x Luck for Mythic & Rainbow rolls! | #37E1D2 |
| pass_luck_8x | 8x Lucky | 🍀 | 799 | 0 | Permanent 8x Luck on every throw! | #82C8FF |
| pass_luck_10x | 10x Luck | 🍀 | 1199 | 0 | MAX 10x Luck on every throw! | #FFCD3C |
| pass_gems_2x | 2x Gems | 💎 | 199 | 0 | 2x Gems from catches, quests, zones & daily! | #46C8FF |
| pass_gems_4x | 4x Gems | 💎 | 349 | 0 | 4x Gems from catches, quests, zones & daily! | #37AFFF |
| pass_gems_6x | 6x Gems | 💎 | 549 | 0 | 6x Gems from catches, quests, zones & daily! | #6991FF |
| pass_gems_8x | 8x Gems | 💎 | 799 | 0 | 8x Gems from catches, quests, zones & daily! | #A06EFF |
| pass_gems_10x | 10x Gems | 💎 | 1199 | 0 | MAX 10x Gems from every in-game source! | #EB64FF |
| pass_power_2x | 2x Training Power | 💪 | 149 | 0 | 2x Pull-Up XP on every rep! | #A56EFF |
| pass_power_4x | 4x Training Power | 💪 | 299 | 0 | 4x Pull-Up XP on every rep! | #C35FFF |
| pass_power_6x | 6x Training Power | 💪 | 499 | 0 | 6x Pull-Up XP on every rep! | #EB5FD7 |
| pass_power_8x | 8x Training Power | 💪 | 749 | 0 | 8x Pull-Up XP on every rep! | #FF6E91 |
| pass_power_10x | 10x Training Power | 💪 | 1099 | 0 | MAX 10x Pull-Up XP on every rep! | #FF9641 |

### Gem Packs (Developer Products)

| Id | Name | Tag | Gems | Robux (R$) | ProductId |
| --- | --- | --- | --- | --- | --- |
| pack_500 | 500 Gems | — | +500 | 79 | 0 |
| pack_1500 | 1,500 Gems | +20% Bonus | +1.5K | 199 | 0 |
| pack_4000 | 4,000 Gems | +30% Bonus | +4.0K | 499 | 0 |
| pack_10000 | 10,000 Gems | Best Value | +10.0K | 999 | 0 |

## Saving

Progress autosaves every 60 seconds, when the player leaves, and when the server shuts down.
If a save can't be loaded, the player can still play but gets a "Progress can't be saved this session." message.

