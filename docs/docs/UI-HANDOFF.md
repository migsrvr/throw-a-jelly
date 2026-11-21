# UI hand-off: screen by screen

**For the UI designer.** Every screen below is a programmer placeholder: flat rectangles, emoji icons,
text-only buttons. The logic behind each one already works, so you can redesign freely as long as each screen
keeps showing the same information and offering the same actions.

Read [GAME-OVERVIEW.md](GAME-OVERVIEW.md) first for context. Exact names, numbers and colours are in
[DATA-REFERENCE.md](DATA-REFERENCE.md). Field-level detail is in [UI-DATA-CONTRACT.md](UI-DATA-CONTRACT.md).

> **How this was written:** from the code, not from watching the running game. Where a section says
> "Current state", it describes what the code builds. Screenshots are still to be added (see
> [screenshots/README.md](screenshots/README.md)).

## Global notes for every screen

- **Font:** everything uses Fredoka One with a dark outline. Keep it or replace it everywhere at once.
- **Style today:** chunky "bevel" buttons (a coloured face with a darker lip) with a hover-grow effect, rounded
  corners, gloss gradients. This is the intended personality (bright, toy-like), just not polished.
- **Numbers are shortened:** 1,500 shows as `1.5K`, 2,300,000 as `2.30M`. Allow for short values like `999`
  and long ones like `$20.0K/s`.
- **Text length is not fixed:** names come from the game (for example "Aurora Borealis Slime" or "Royal Sugar
  King Slime"). Design for the longest name in [DATA-REFERENCE.md](DATA-REFERENCE.md).
- **Screen sizes:** the HUD scales to the window (designed around 1366x768, scales between 0.68x and 1.18x).
  **There is no phone-specific layout yet.** Roblox players on phones are a large share, so this needs a decision.
- **Placeholders you can ignore:** emoji used as icons (🌿 💎 🌋 ❄️ 🍬 💪 💵 ⚡ 🥚 🌈 🎁 📘 🧰) are stand-ins for real icons.

## Priority order (suggested)

1. Shop (the screen players use to spend money, most visibly unfinished)
2. Pull-up bar training HUD (brand new, nothing exists beyond a floating number)
3. Slime Index
4. HUD frame (stats, hotbar, buttons, objective text)
5. Slimes backpack
6. Throw meter, flight HUD and reveal cutscene (closest to final, polish)
7. World signs and prompts
8. Screens that do not exist yet (last section)

---

## 1. HUD frame (always visible)

**What it is.** The permanent layer on top of the game.

**Current state.**
- Top centre: one line of objective text, and under it a short-lived message banner ("toast").
- Bottom-left: three big numbers, Throw Power (💪, blue), Cash (💵, green), and Gems (💎, light blue).
- Bottom-centre: the hotbar, up to **5 slots** showing slimes the player has caught but not placed yet.
- Left column (3 buttons, top to bottom): **Index** (`📘`), **Shop** (`R$`, Robux Shop), and **Upgrades** (`⬆️`).
- Right column (2 buttons, top to bottom): **Rewards** (`🎁`, with a red `"!"` badge when the daily reward or any quest is ready to claim) and **Slimes** (3D slime icon). Each is a square 78 px bevel button.
- A bouncing yellow arrow above the hotbar when the objective is "pick your slime".
- A dark dim layer behind any open window (only one window open at a time).

**Information it must show.** Cash, Throw Power, the current objective, the hotbar slimes, and messages.

**Actions.**
- Click a nav button: opens that window (only one window open at a time; clicking again closes it).
- Click a hotbar slot or press keys **1-5**: picks up that slime (the avatar carries it in front of them).
  Click again to put it back.
- "Place Slime on Free Slot" button appears (above the hotbar) once a slime is picked up. It places the slime
  on the first free slot of the plot.

**Hotbar slot contents today** (72 px square): live 3D preview of the slime, income per second on top ("$5/s"),
the short name in the middle, and the number plus mutation (or rarity if none) at the bottom. Selected slot has a
green border.

**States to design.**
- Empty hotbar (no uncaught slimes). Today it simply disappears.
- Slot selected vs unselected.
- Message banner kinds: success (yellow today), warning/error (red), cash gained (green), power gained.
- Objective text changing through the five tutorial lines.
- Low vs high numbers (cash can reach billions).

**Missing / wanted.**
- Icons and a proper stat panel (also: Best throw distance and income per second are available but not shown).
- A visible way to use the hotbar on touch screens (keys 1-5 do not exist on phones; tapping works).
- Sound and animation feedback when cash changes.

**Source:** `HudController.client.luau`, sections 1-4 and 8-9.

---

## 2. Shop (Robux), Upgrades (`⬆️`), and Rewards (`🎁`) windows

### 2a. Shop (`R$`) window (`HudWindows/RobuxStoreWindow.luau`)
- Opened by the left **"Shop" (`R$`)** button.
- Contains:
  1. **Featured Robux Slime Eggs** (Enchanted Egg `[New!]`, Rainbow Egg `[LIMITED]`): 6 odds tiles with live 3D slime previews, `%` chance, bonus label, and Robux-only **Buy x1 (`R$`)** / **Buy x3 (`R$`)** buttons (`PriceKind = "Robux"`).
  2. **Permanent Game Passes** (`GameConfig.Robux.Passes`): `x2 Luck`, `x2 Cash`, `VIP`.
  3. **Robux Gem Packs** (`GameConfig.Robux.GemPacks`): `100 / 550 / 1,200 / 2,600 Gems`.
  4. **Free Gift card**: 3D preview of Emerald Sakura Slime + **CLAIM!** button.

### 2b. Tabbed Upgrades (`⬆️`) window (`HudWindows/UpgradesWindow.luau`)
- Opened by the left **"Upgrades" (`⬆️`)** button.
- Header shows `"⬆️ Upgrades"` plus live `💵 $Cash` and `💎 Gems` balance pills.
- Uses **3 switchable tabs**, each with its own dedicated glossy **Tab Header Banner**:
  1. **`⚡ Power & Training`**: Throw Power (`power_upgrade`: **Buy** + **Buy Max**), Pull-Up Bar Tier (`pullup_tier`), and `x2 Training Power` (`boost_double_power`).
  2. **`🥕 Bait & Plot`**: Jelly Bait quality tier (`bait_tier`, showing `Bait Luck Xx -> Yx`), `+4 Slime Slots` (`slot_expansion`, `$5K`), and `x2 Cash` (`boost_double_cash`).
  3. **`💎 Gem Upgrades`**: every catalog item with `Category = "Gem"` (`gem_auto_throw`, `gem_lucky_charm`, `gem_slot_expansion`).

### 2c. Rewards & Quests window (`HudWindows/RewardsWindow.luau`)
- Opened by the right **"Rewards" (`🎁`)** button (shows a red `"!"` badge when `DailyCanClaim` or any quest can be claimed).
- Two tabs:
  1. **📅 Daily Rewards**: 7-tile login streak strip on top (`Day 1`..`Day 7` from `GameConfig.Gems.DailyRewards`, ticked claimed days, glowing today tile with **CLAIM!**, dimmed future days, and `"Resets in HHh MMm"` countdown) + **3 Daily Quest cards** below with progress bars and **CLAIM!** buttons.
  2. **🏆 Quest Line**: large hero card for the current step (`Step X / 12`) with progress bar and **CLAIM!**, plus 2 dimmed preview cards for the upcoming steps.

---

## 3. Slime Index window

**What it is.** A collection book. Opened by the left "Index" button.

**Current state.** A scrolling window with one **row per zone** (five rows). Each row has, left to right:
a zone card (name, big emoji, completion percentage), three slime cards, and a trail panel (trail name, its
bonus text, and a button). Under the slime cards is a progress bar with "2/3". A footer says "Unlocked: X/15".

Each slime card shows a live 3D preview (a flat dark silhouette if not discovered yet), the short name
("SPROUT", or "???" if undiscovered) and the rarity word. It is tinted with the rarity colour. It does **not**
show income or mutations yet.

The trail button reads **LOCKED** (grey) until the zone is 100% complete, then **EQUIP** (green), then
**EQUIPPED** (blue). Only one trail can be equipped at a time.

**Information it must show.**
- Per zone: name, icon, theme colour, % complete and "X/3".
- Per slime: discovered or not, short name, rarity, and its picture. (Wanted: income.)
- Overall progress (X of 15).
- Per zone: trail name, its bonus ("+15% XP") and whether it is locked, ready, or equipped.

**Actions.** Equip a zone's trail (only once the zone is 100% complete). Equipping another replaces the first.

**States to design.** Undiscovered / discovered slime; zone incomplete / complete / trail equipped; very long slime
names; mutation variants (a slime can be found as Emerald, Golden, etc. but the book does not show this yet).

**Missing / wanted.**
- Rarity colour language on cards (the rarity colours exist in [DATA-REFERENCE.md](DATA-REFERENCE.md)).
- A **detail view** for one slime (bigger preview, drop chance, income, mutations found).
- Show which **mutations** the player has found for each slime.
- Clearer trail reward presentation (what it does, locked/unlocked).

**Source:** `HudController.client.luau` section 5 and `rebuildSlimeIndexModal`.

---

## 4. Slimes (backpack) window

**What it is.** The list of slimes the player has caught but not placed yet. Opened by the right "Slimes" button.

**Current state.** A small window (530x380) with a scrolling list of rows, one per unplaced slime, each a button
reading like "🟢 [EMERALD] Honey Slime +$7/s (Click to Place)". At the bottom: "Auto-Place Best Slimes on Plot".

**Information it must show.** Each unplaced slime: picture, name, mutation, rarity, income per second.

**Actions.**
- Click a row: place that slime on the first free slot.
- "Auto-Place Best": the game places the highest-earning slimes into slots and sends the rest back to the list.

**States to design.** Empty backpack, many slimes (scrolling), plot full (no free slot), selected slime.

**Missing / wanted.** Sorting and filtering (by income, rarity, newest), rarity styling, pick-which-slot
interaction, "sell" or "lock" if those ever exist.

**Source:** `HudController.client.luau` section 7 and `rebuildBackpackModal`.

---

## 5. Pull-up bar and training (step-on auto-start + E to upgrade)

**What it is.** The strength-training system. Each player's plot has a pull-up bar.

**Current state.**
- **World label above the bar** (three lines of text): the bar's tier name, `"Walk under the bar to train"`, and `"+<XP> XP / rep"`.
- **Step-on auto-start:** walking within 6 studs (`GameConfig.PullUp.AutoStartRadius`) of your own bar's `TrainSpot` starts training automatically (no key press). Jumping or walking away stops training and disarms the bar until you walk out past 9 studs (`RearmRadius`).
- **Interaction prompt on the bar (E):** upgrades the bar (`ActionText = "Upgrade Bar"`, `ObjectText = "<Next Tier Name> ($cost)"`, disabled at MAX TIER, hidden on other players' bars).
- While training: the avatar hangs in a front-camera view with per-rep shake, dust/sweat/ring effects, a bottom XP bar (`Lv. N`, `current / required XP`, `Next: +5 Power`), `"LEVEL UP!"` pop-ups, and server-offered `"⚡ BONUS REP! (3x XP)"` buttons every 4-6 seconds.

**Information it must show** (designer's wish list; nothing of this exists on screen yet):
- Reps done this session and total.
- Throw Power and power gained this session.
- Current speed (seconds per rep) and power per second.
- How to stop ("Press E or jump to stop").
- Current bar name and what the next bar gives and costs.

**Actions.** Start/stop training (E, tap the prompt, or an on-screen button for phones). Jump or walk to stop.
Upgrading the bar happens in the Shop today; a button at the bar itself would be better.

**States to design.** Not training / training / just stopped, bar at max tier, not enough cash for the upgrade,
looking at someone else's bar (training is only allowed on your own plot; the game shows "Train on your own pull-up bar!").
Also the five bar looks: Pull-Up Bar, Iron, Crystal, Magma, Starlight.

**Missing / wanted.**
- A **training HUD** (see above) while hanging.
- A better **bar upgrade UI** (and visuals for each bar tier on the bar itself).
- A phone-friendly start/stop button.
- Feedback when speed increases (a "faster!" moment after buying a bar).

**Source:** `PlotService.luau` (bar label and prompt), `TrainingController.client.luau` (floating number and stop input).

---

## 6. Throwing flow

Three connected screens. They are the closest to the target look, so mostly polish.

### 6a. Throw meter ("TAP TO THROW!")
- **When:** the player stands at the Throw Line. The avatar holds the bait and raises the arm.
- **Shows:** a tall white pill with nine colour bands (red bottom to bright green top), a slider bar that sweeps up
  and down, and next to the slider the bonus ("+11"). Text under it: "TAP TO THROW!".
- **Action:** click, tap or press Space to stop the slider and throw.
- **States:** hidden when away from the line or after throwing; slider position changes continuously.
- **Wanted:** a stronger "perfect" moment (top band), keyboard/touch hint text per device, sound.

### 6b. In-flight HUD
- **When:** after the throw, while the bait flies.
- **Shows (top centre):** a big luck number such as "1.32X", the word LUCK, and a banner with the zone the bait is
  currently over (name plus icon, tinted in the zone colour). The zone name updates as it flies.
- **Wanted:** distance counter, a zone-change flash.

### 6c. Reveal cutscene overlay
- **When:** the bait lands. The screen fades, then a silhouette slime pops from the ground and hops to the bait.
- **Shows:** at top, a "1 in X" counter that climbs while the slime approaches; "SUPER LUCKY!" when the odds are
  1 in 10 or rarer, or the slime has any mutation;
  at the end at the bottom the rarity or mutation word, the slime's big name, income per second, a "NEW!" badge
  for first discoveries, and "tap to continue". Ring effects burst at the reveal.
- **Actions:** tap, click or Space to continue (auto-continues after 3 seconds).
- **States:** normal / mutation (name and colour change) / new discovery / super lucky.
- **Wanted:** rarity-specific celebration (Common should feel small, Mythic huge), mutation colour treatment,
  a summary of cash/power gained from the throw.

**Source:** `ThrowController.client.luau`.

---

## 7. World UI (signs, prompts, boards)

These live on objects in the 3D world, not on the screen.

| Where | What it shows today | Wanted |
| --- | --- | --- |
| Plot owner sign | "<Name>'s Base" and income per second | consistent look with HUD |
| Collect pad | "COLLECT" and the pending cash | clear call to action |
| Slime slots (1-12) | a prompt "Place Slime" / "Swap / Pick Up Slime", slot number, slime name and income; locked slots are grey | locked-slot look with price hint |
| Upgrade stand sign | "8 > 12" and the price, or "MAX SLOTS" | clearer upgrade presentation |
| Pull-up bar label | see section 5 | see section 5 |
| Jelly Shop (hub) | one prompt "Upgrade Throw Power" | open the real shop window |
| Hub leaderboards (4) | richest, best throws, strongest, rarest slime | visual design |
| Interaction prompts | Roblox default (white pill with E) | custom prompt style |

**Source:** `PlotService.luau`.

---

## 8. Screens that do not exist yet

None of these have any code. Tell the programmer which you want and what they should contain.

- Settings (sound, graphics)
- First-time tutorial beyond the single objective line
- Daily rewards / login streak
- Robux shop (game passes, developer products)
- Phone-specific layout and controller navigation
- Loading screen and death/respawn feedback
- Player profile / stats screen (total throws, total pull-ups, best distance are tracked)
- Achievements
- Sound design and haptics for everything above
