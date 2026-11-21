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

| Band | Colour | Bonus Throw Power | Luck multiplier |
| --- | --- | --- | --- |
| 1 | #EB4137 | +1 | 1.00x |
| 2 | #F56932 | +3 | 1.03x |
| 3 | #FA9132 | +5 | 1.06x |
| 4 | #FFB937 | +8 | 1.10x |
| 5 | #F5DC3C | +11 | 1.15x |
| 6 | #CDEB41 | +14 | 1.22x |
| 7 | #A0F04B | +17 | 1.32x |
| 8 | #73F555 | +21 | 1.48x |
| 9 | #46FA69 | +25 | 1.75x |

## Pull-up bar tiers (5)

Training on the bar adds Throw Power. A better bar gives more power per rep and also does reps faster.

| Tier | Name | Upgrade cost | Power per rep | Rep speed multiplier |
| --- | --- | --- | --- | --- |
| 1 | PULL-UP BAR | (starting bar) | +2 | x1 |
| 2 | IRON BAR | $75 | +8 | x1.15 |
| 3 | CRYSTAL BAR | $450 | +32 | x1.3 |
| 4 | MAGMA BAR | $2.5K | +140 | x1.5 |
| 5 | STARLIGHT BAR | $15.0K | +600 | x1.75 |

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

| Item id | Group | Icon | What it does | Colour |
| --- | --- | --- | --- | --- |
| power_upgrade | Upgrade | ⚡ | Raises Throw Power by one upgrade level (price grows each level) | #EB962D |
| pullup_tier | Upgrade | 💪 | Upgrades the pull-up bar to the next tier | #379BF0 |
| slot_expansion | Upgrade | 🧺 | Adds 4 more slime slots to the plot (8 to 12) | #5FC878 |
| boost_double_cash | Boost | 💵 | Permanent boost (see boosts below) | #2DB9EB |
| boost_double_power | Boost | 💪 | Permanent boost (see boosts below) | #A55FF5 |
| egg_enchanted | Egg | 🥚 | Hatches 1 or 3 slimes with the odds listed below | #AF6EFF |
| egg_rainbow | Egg | 🌈 | Hatches 1 or 3 slimes with the odds listed below | #FF78C8 |
| free_gift | Gift | 🎁 | One-time free slime | #FFCD37 |

### Boosts

| Name | Description | Price | Colour |
| --- | --- | --- | --- |
| x2 Cash | Double cash from every slime! | $500 | #41BEFF |
| x2 Training Power | Double XP on every pull-up! | $750 | #A56EFF |

### Eggs

**ENCHANTED EGG** (tag: "New!") - $120 for 1, $320 for 3. Accent colour #AF6EFF.

| Slime | Mutation | Chance | Bonus label shown on the card |
| --- | --- | --- | --- |
| Honey Slime | EMERALD | 40% | 150% |
| Sakura Bloom Slime | NORMAL | 27% | 175% |
| Quartz Slime | EMERALD | 18% | 250% |
| Amethyst Slime | GOLDEN | 10% | 350% |
| Prism Geode Slime | CRYSTAL | 4% | 550% |
| Solar Flare Slime | RAINBOW | 1% | 900% |

**RAINBOW EGG** (tag: "LIMITED") - $1.5K for 1, $4.0K for 3. Accent colour #FF78C8.

| Slime | Mutation | Chance | Bonus label shown on the card |
| --- | --- | --- | --- |
| Prism Geode Slime | RAINBOW | 45% | 750% |
| Obsidian Core Slime | RAINBOW | 28% | 750% |
| Solar Flare Slime | RAINBOW | 16% | 750% |
| Aurora Borealis Slime | RAINBOW | 8% | 750% |
| Cotton Cloud Slime | RAINBOW | 2.5% | 750% |
| Royal Sugar King Slime | RAINBOW | 0.5% | 999% |

### Free gift

"Free Slime!" - "Claim your free Emerald Sakura Slime!" (Sakura Bloom Slime, EMERALD). Can be claimed once per player.

## Plot slots

Every plot starts with 8 slime slots; a one-time purchase of $5.0K unlocks all 12.

