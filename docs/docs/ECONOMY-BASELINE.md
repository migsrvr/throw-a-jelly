# Currency, Progression & Monetization Baseline — *Throw Jelly for Slimes*

> **Authoritative Economy Design Reference**
> Single source of truth for hourly F2P accumulation targets (`Cash/hr`, `Throw Power/hr`, `Gems/hr`), first-run addiction pacing, the **8+ hour F2P Gem grind floor**, strict **8-slot starter cap** (Slots 9–12 locked behind Gems or Robux), and the **`2x–10x` Multiplier Shop**.
> All runtime values live in [`src/ReplicatedStorage/Shared/GameConfig.luau`](../../src/ReplicatedStorage/Shared/GameConfig.luau) and [`src/ReplicatedStorage/Shared/ProgressionLogic.luau`](../../src/ReplicatedStorage/Shared/ProgressionLogic.luau).

---

## 1. Core Design Philosophy

1. **Addictive First-Run Hook (Minutes 0–60)**:
   - Every 2–5 minutes delivers a tangible dopamine hit: catching rarer slimes, filling all **8 starter plot slots**, watching passive `$/s` climb visibly on `CollectPad`, leveling up on the Pull-Up Bar (`LEVEL UP! +5 POWER`), clicking `3x` Bonus Rep pop-ups, completing linear Quest Line steps, and upgrading Bars & Jelly Bait.
   - The **Free Gift** (`Emerald Honey Slime`, `$8/s`) gives an exciting 4x jump over the starter `$2/s` slime without letting new players bypass Zone 1 in 20 seconds.
2. **Clean Two-Currency Split (Cash vs. Gems / Robux)**:
   - **Cash (`$`)** drives the core gameplay loop: **Throw Power Upgrades (`Lv.1–40+`)**, **Pull-Up Bar Tiers (`1–5`)**, and **Jelly Bait Tiers (`1–5`)**. Cash scales smoothly from `$60` to `$1.6B+`.
   - **Gems (`💎`) & Robux (`R$`)** exclusively own all **permanent multipliers (`2x–10x Gems`, `2x–10x Training Power`, `2x Money`, `2x–10x Luck`)**, **Auto-Throw**, and **Locked Plot Slots 9–12**.
3. **Strict 8+ Hour F2P Grind Floor for Premium Gem Unlocks**:
   - An active, non-stop F2P player accumulates **`~1,250 Gems`** across their first **8 hours** (combining rare catches, first zone reaches, Index milestones, Quest Line, and Day 1 daily login/quests).
   - The cheapest premium Gem unlock starts at **`1,500 Gems`** (Slot #9), and flagship unlocks sit at **`1,800–2,500 Gems`** (`2x Power`, `Auto-Throw`, `2x Luck`, `2x Money`, `2x Gems`).
   - Result: **zero premium Gem unlocks can be bought in the first 8 hours F2P**, making Gems genuinely prestigious while creating a clear choice between **grinding into Hours 9–50+** or **buying the Robux Pass / Gem Pack shortcut**.
4. **Tiered Snowball Endgame (`2x → 4x → 6x → 8x → 10x`)**:
   - Each multiplier track replaces/upgrades up to **`10x` max** (highest tier owned across Gems OR Robux Passes wins; players never pay twice).
   - Unlocking `2x Gems` doubles all in-game Gem earnings (`~235/hr → ~470/hr` in Zone 5), allowing committed F2P players to legitimately snowball up the `4x → 6x → 8x → 10x` ladder over days and weeks.

---

## 2. Active F2P Baseline Assumptions (`1x` Multipliers)

- **Throw Cycle**: `~10 seconds/throw` (pitch wind-up `0.6s`, flight `2.5s`, emergence + 5 hops `4.8s`, quick click or 3s AFK dismiss). Pure throwing ≈ `300 throws/hr`; realistic active play (40% pull-up training + 60% throwing/selling/plot management) ≈ **`150–190 throws/hr`**.
- **Pull-Up Training**: Auto-rep interval shrinks from `1.60s/rep` to `0.35s/rep` via strength and bar tier `SpeedMult`. Active players click `~75%` of `3x XP` Bonus Rep pop-ups (`4–6s` interval).
- **Gem Sources (Base `1x`, all multiplied by `GetGemMultiplier(profile)` except Robux Gem Packs)**:
  - **First Zone Reach**: `3 / 8 / 18 / 35 / 75` = **`139` base Gems** (one-time)
  - **Index Milestones (3 / 6 / 9 / 12 / 15 slimes)**: `5 / 12 / 25 / 45 / 90` = **`177` base Gems** (one-time)
  - **12-Step Linear Quest Line**: `3 / 3 / 5 / 5 / 8 / 10 / 12 / 15 / 15 / 20 / 25 / 40` = **`161` base Gems** (one-time)
  - **Daily Login Streak (Day 1–7)**: `5 / 8 / 12 / 16 / 22 / 30 / 50` Gems (`Day 1 = 5`)
  - **3 Daily Quests / UTC Day**: `5–10 Gems` each (`~22 Gems/day`)
  - **Repeatable Rare Throw Catches**: `Mythic = +1 Gem`, `CRYSTAL mutation = +1 Gem`, `RAINBOW mutation = +2 Gems` (eggs never drop catch Gems)

---

## 3. Hourly Accumulation Baseline Table (`1x` F2P Active Grind)

| Playtime | Active Zone | Throw Power Range | Est. Cash/hr (8-Slot Plot + Throws) | Est. Repeatable Gems/hr (Catches) | Cumulative F2P Gems (All Sources) | Key Milestones Reached |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **0 – 15 min** | **Z1: Meadow** | `5 → 50 TP` | `$5K → $120K/hr` | `~14 Gems/hr` | `~35 Gems` | Starter loop, Free Gift (`$8/s`), Iron Bar (`$350`), Berry Jelly (`$600`), 8 slots filled, unlock **Zone 2** |
| **15 – 45 min** | **Z2: Crystal Cave** | `50 → 250 TP` | `$900K → $2.3M/hr` | `~25 Gems/hr` | `~110 Gems` | Crystal Bar (`$4.5K`), Crystal Honey (`$8K`), Power Lv.10 (`$3.1K`), unlock **Zone 3** |
| **0.75 – 2.5 hr** | **Z3: Lava Fields** | `250 → 1,000 TP` | `$5.4M → $16M/hr` | `~39 Gems/hr` | `~315 Gems` | Magma Bar (`$75K`), Magma Tart (`$120K`), Power Lv.20 (`$250K`), unlock **Zone 4** |
| **2.5 – 5.5 hr** | **Z4: Frost Peaks** | `1,000 → 5,000 TP` | `$36M → $108M/hr` | `~138/hr` (throws) / `~75/hr` mixed | `~700 Gems` | Starlight Bar (`$1.2M`), Starlight Cake (`$2.0M`), Cryo Monarch (`+1,650 TP`), unlock **Zone 5** |
| **5.5 – 8.0 hr** | **Z5: Candy Land** | `5,000 → 10K+ TP` | `$250M → $1.5B+/hr` | `~235 Gems/hr` | **`~1,250 Gems`** | Endgame Mythic/Rainbow farm, Power Lv.32–40+, **83% toward Slot #9 (`1,500 Gems`)** |
| **8.5 – 14 hr** | **Z5 Endgame (`1x→2x`)** | `10K → 25K+ TP` | `$1.5B+/hr` | `235/hr` → `470/hr` (w/ `2x Gems`) | `1,500 → 2,500+ Gems` | First prestige unlock (**Slot #9**, **2x Power**, **Auto-Throw**, **2x Luck**, **2x Money**, or **2x Gems**) |
| **15 – 60+ hr** | **Z5 Prestige Snowball** | `25K+ TP` | `$3B–$15B+/hr` | `470/hr` → **`2,350/hr`** (w/ `10x Gems`) | `6K → 100K+ Gems` | Climbing `4x → 6x → 8x → 10x` tracks + unlocking Slots 10, 11, and 12 |

---

## 4. Core Cash Loop Pricing (`Upgrades` Tabs 1 & 2)

### Pull-Up Bar Tiers (`pullup_tier`)
| Tier | Name | Cash Cost | XP / Rep | Speed Mult | Est. Unlock Time |
| :---: | :--- | :---: | :---: | :---: | :--- |
| 1 | PULL-UP BAR | Free (`$0`) | `2 XP` | `1.00x` | Minute 0 |
| 2 | IRON BAR | `$350` | `8 XP` | `1.15x` | ~Minute 3 |
| 3 | CRYSTAL BAR | `$4,500` | `32 XP` | `1.30x` | ~Minute 18 |
| 4 | MAGMA BAR | `$75,000` | `140 XP` | `1.50x` | ~Hour 1.0 |
| 5 | STARLIGHT BAR | `$1,200,000` | `600 XP` | `1.75x` | ~Hour 3.2 |

### Jelly Bait Tiers (`bait_tier`)
| Tier | Name | Cash Cost | Luck Mult | Est. Unlock Time |
| :---: | :--- | :---: | :---: | :--- |
| 1 | Carrot Jelly | Free (`$0`) | `1.00x` | Minute 0 |
| 2 | Berry Jelly | `$600` | `1.35x` | ~Minute 5 |
| 3 | Crystal Honey | `$8,000` | `1.85x` | ~Minute 25 |
| 4 | Magma Tart | `$120,000` | `2.60x` | ~Hour 1.2 |
| 5 | Starlight Cake | `$2,000,000` | `4.00x` | ~Hour 4.0 |

### Throw Power Upgrades (`power_upgrade`)
- **Cost**: `floor(60 * 1.55^(Lv - 1))` (`$60` Lv.1 → `$346` Lv.5 → `$3.1K` Lv.10 → `$250K` Lv.20 → `$19.9M` Lv.30 → `$1.59B` Lv.40)
- **Bonus**: `floor(8 * (Lv - 1)^1.55)` (`+8` Lv.2 → `+68` Lv.5 → `+241` Lv.10 → `+768` Lv.20 → `+1,478` Lv.30 → `+2,340` Lv.40)

---

## 5. Premium Shop Pricing (Dual-Path: High-Value Gems OR Direct Robux)

### A. Plot Slots (Strict 8-Slot Starter Cap, Slots 9–12 Locked)
| Slot | Unlock Method (Gems — 1-by-1) | Est. F2P Grind (`1x` Gems) | Robux Shortcut |
| :---: | :---: | :--- | :--- |
| **Slots 1–8** | Free starter cap (`InitialMaxSlimes = 8`) | Minute 0 | Included |
| **Slot #9** | **`1,500 Gems`** | ~9 hrs | Included in **`+4 Plot Slots` Pass (`R$ 249`)** |
| **Slot #10** | **`2,500 Gems`** | ~16 hrs | Included in **`+4 Plot Slots` Pass (`R$ 249`)** |
| **Slot #11** | **`4,000 Gems`** | ~25 hrs | Included in **`+4 Plot Slots` Pass (`R$ 249`)** |
| **Slot #12** | **`6,000 Gems`** | ~38 hrs | Included in **`+4 Plot Slots` Pass (`R$ 249`)** |

*Cash can NEVER unlock extra plot slots. Buying the `+4 Plot Slots` Robux Pass immediately expands capacity to 12/12.*

### B. Core Premium Unlocks
| Item | Effect | Gem Cost | Est. F2P Time | Direct Robux Pass |
| :--- | :--- | :---: | :---: | :---: |
| **Auto-Throw** | Visible green-lock Auto-Throw (3 PERFECT / 2 GREAT 5-throw bag) | **`2,000 Gems`** | ~11 hrs | **`R$ 199`** (`pass_auto_throw`) |
| **2x Money** | Permanent `2x` Cash from Slimes, Throws & Collect | **`2,200 Gems`** | ~12 hrs | **`R$ 199`** (`pass_x2_cash`) |
| **VIP Pass** | `+25%` Cash, `+25%` Earned Gems, `[VIP]` chat tag | Robux-only | — | **`R$ 299`** (`pass_vip`) |

### C. Tiered `2x–10x` Multiplier Ladders (Highest Owned Tier Wins, Max `10x`)
| Track | `2x` Tier | `4x` Tier | `6x` Tier | `8x` Tier | `10x` Tier |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Gems (`2x–10x`)** | `2,500 💎` / `R$ 199` | `6,000 💎` / `R$ 349` | `12,000 💎` / `R$ 549` | `22,000 💎` / `R$ 799` | `38,000 💎` / `R$ 1,199` |
| **Training Power (`2x–10x`)** | `1,800 💎` / `R$ 149` | `4,500 💎` / `R$ 299` | `9,500 💎` / `R$ 499` | `17,500 💎` / `R$ 749` | `30,000 💎` / `R$ 1,099` |
| **Throw Luck (`2x–10x`)** | `2,000 💎` / `R$ 179` | `5,000 💎` / `R$ 349` | `10,500 💎` / `R$ 549` | `19,000 💎` / `R$ 799` | `32,000 💎` / `R$ 1,199` |

### D. Robux Gem Packs
| Pack | Gems | Robux | Bonus Tag |
| :--- | :---: | :---: | :--- |
| Starter Pack | `500 Gems` | `R$ 79` | — |
| Grinder Pack | `1,500 Gems` | `R$ 199` | `+20% Bonus` |
| Mega Pack | `4,000 Gems` | `R$ 499` | `+30% Bonus` |
| Ultimate Pack | `10,000 Gems` | `R$ 999` | `Best Value` |

---

## 6. Luck & Mutation Scaling Curve (`RollSlimeForZone` & `RollMutation`)

To guarantee that every Luck tier (`2x → 4x → 6x → 8x → 10x`) delivers a dramatic, unmistakable upgrade in rare slimes and Rainbow mutations:
- **Zone Slime Pool**: `weight(i) = baseWeight * (luck ^ (0.55 * (i - 1)))`
- **Mutations**: `NORMAL = 72`, `EMERALD = 16 * luck^0.45`, `GOLDEN = 7 * luck^0.65`, `CRYSTAL = 3.5 * luck^0.85`, `RAINBOW = 1.5 * luck^1.05`

| Scenario (Zone 5 Starlight Cake) | Total Flight Luck | Top Slime (`Royal Sugar King`) | `CRYSTAL` Rate | `RAINBOW` (`7.5x $/s`) Rate | Repeatable Gems/hr (`1x` Gems) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Base (`1x` Luck) | `~16x` | `52.5%` | `15.7%` | `11.7%` | `~235/hr` |
| **`2x Luck`** | `~32x` | `64.4%` | `19.7%` | `16.9%` | `~275/hr` |
| **`4x Luck`** | `~64x` | `74.2%` | `23.1%` | `22.8%` | `~312/hr` |
| **`6x Luck`** | `~96x` | `78.8%` | `24.8%` | `26.5%` | `~332/hr` |
| **`8x Luck`** | `~128x` | `81.7%` | `25.8%` | `29.2%` | `~345/hr` |
| **`10x Luck`** | `~160x` | `83.7%` | `26.4%` | `31.3%` | `~355/hr` |
