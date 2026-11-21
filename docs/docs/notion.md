## Concept

**Working title: Throw Jelly for Slimes**
A Roblox simulator in the "Throw X for Y" genre. Throw jelly as far as you can, attract slimes that land where it lands, and earn passive money from them. Spend money on better jelly to attract rarer slimes, train Throw Power, and unlock new zones.

## Core Loop

1. Tap to throw jelly. A vertical power meter decides the distance.
2. Slimes spawn where the jelly lands, and each earns passive $/s.
3. Spend money in the Jelly Shop on higher-tier jelly, which attracts rarer slimes.
4. Hold on pull-up bars to train Throw Power (XP levels, Stop button).
5. Throw Power unlocks new zones with stronger, rarer slimes.
6. The Slime Index tracks collection progress, with silhouettes for undiscovered slimes.

## Subject: Slimes

- One base slime model, varied by color, size, accessories and particle effects.
- Rarity tiers: Common, Uncommon, Rare, Epic, then higher (Legendary, Mythic, Secret).
- Why slimes: cheap to build at scale (an Index of 100+ entries without 100 unique models), and a glossy translucent look that pops against the lime voxel world.
- **Evolution and absorb mechanic (from Miggy's feedback):** inspired by the "slime that absorbs and evolves" fantasy (Rimuru-style). Slimes can merge or absorb duplicates to evolve into stronger forms, and top-tier slimes gain humanoid forms and abilities.
- This is inspiration only. We use our own original slime designs and names, with no Rimuru character, art or names, to stay clear of IP issues on Roblox.
- Not yet taken in the genre. Taken subjects: Animals, Spooky Animals, Lucky Blocks, Dragons, Plants/Seeds, Cars.

## Zones (draft)

Zones are drawn as a tiered "staircase" of terrain in the thumbnail style.

- Meadow (grass), Cave, Lava, Ice, Candy Land (names are placeholders)
- Optional themed variants, like the spooky night version seen in competitors

## Visual Direction

- Voxel / Lego-stud look: studded blocky terrain, brown dirt walls, bright lime checkerboard floor, blocky trees.
- Chunky UI: purple gradient headers, big rounded buttons (green EQUIP, red price), a Tier label on each item.
- Left side: Index and Shop buttons. Right side: Slimes button. Bottom-left: Throw Power and Money counters.
- Juice: "NEW!" reveal pop-ups, a Luck multiplier banner, a zone-name banner, a live leaderboard (Money, Throw Power, $/s).
- Thumbnail formula: the avatar throws jelly in a glowing arc, the subject is a black "?" silhouette, a huge $/s number or "1 in N" odds line sits in the corner, and the terrain steps up in colored tiers.

## Reference Games

- Throw Food For Animals (main reference, 227K players)
- Throw Food For Dragons, Throw Food For Spooky Animals, Throw Lucky Block For Animals
- Throw Seeds For Plants, Throw a Seed, Throw Key for Cars
- Reference gameplay recording: Screen Recording 2026-11-17 at 4.02.25 PM.mov (on the Desktop)

## Monetization Ideas

- Luck boosts, extra slime slots, faster hatching, auto-throw, Robux-only jelly tiers.
- **Gems (from Miggy's feedback):** a premium currency that buys the big convenience upgrades, like Auto-Throw, Luck boosts and extra slime slots.
- Gems are earned in-game, but slowly, from Index milestones, first clears of each zone, daily rewards and rare slime drops. That makes the grind real but achievable.
- Gems can also be bought with Robux to skip the grind. Robux stays the shortcut, and free players can still get everything.

## Open Questions

- Final zone list and slime roster
- Currency and rebirth system
- Art pipeline: how we build the voxel terrain and the base slime model

## Decisions Log

- 2026-11-17: Dropped brainrot. Chose "Throw Jelly for Slimes" with the Throw Food For Animals loop and voxel visual style.
- 2026-11-17: This Notion page replaces CLAUDE.md for project context.
- 2026-11-17: Built the first greybox map in Studio (Workspace.Map). Throw lane runs along +Z. Hub (spawn, throw pad, Jelly Shop, pull-up bar training, leaderboard) sits behind the throw line at Z=19. Five 200-stud zones follow, each 10 studs higher than the last: Meadow, Cave (50 TP), Lava (250 TP), Ice (1000 TP), Candy Land (5000 TP). Throw Power gates are placeholders. Each zone folder has the attributes RequiredThrowPower, StartZ/EndZ and FloorY, plus a LandingArea part for slime spawns.
- 2026-11-17 (map v2, replaces the greybox above): Rebuilt the map to match the visual reference, in the Game 02 place. The hub is a raised plateau (Y=30) with a checkered throw line at the cliff edge. The throw lane is a voxel canyon below it: stepped dirt walls, dripping grass edges, lane lines, and distance markers on the floor. Five zones (Meadow, Crystal Cave 50 TP, Lava Fields 250 TP, Frost Peaks 1000 TP, Candy Land 5000 TP), each 240 studs long and 6 studs higher than the last, sit behind hazard-striped locked gates. Player bases are 8 fenced slime pens (Hub.PlayerBases.Plot1-8). Each pen has 12 slime slots (9-12 locked), an owner sign, a $/s billboard, a claim pad, a collect pad and a hut. Also in the hub: 4 framed leaderboards, a gym with pull-up bars in 4 price tiers, Jelly Shop, slime fountain, Index kiosk, and lamps.
- 2026-11-17: Cut player bases from 8 to 5 (Hub.PlayerBases.Plot1-5). They now sit side by side in one row behind the cross path, with gates facing the hub. No plot is in front of or behind another.
- 2026-11-17: Hub tightened. Slime Index is GUI-only, so the kiosk and the fountain were removed. The hub was shortened to Z -125..0, and the 5 bases now sit right behind the throw line (gates at Z=-46, a walkway in front). The separate gym was removed. Each plot now has its own pull-up bar in front of its gate (Plot.PullUpBar, attributes PlotId/Tier/XPPerRep). The leaderboards moved to the front, beside the throw line on the right side of the field (looking down the lane). Jelly Shop is in the matching spot on the left. Spawn sits between the bases and the throw line, facing the field.
- 2026-11-17: Removed the visible slime slot pads and padlocks from the bases to cut visual clutter. Capacity is handled in code: Plot attribute MaxSlimes (default 8), and a future prompt tells the player to upgrade when they're full. Slot1-12 are kept as invisible, non-collidable spawn points for where slimes stand.
- 2026-11-17: Tried studs on every part (kept, user liked it). Each part stores its original surfaces in an OrigSurfaces attribute, so the change can be reverted. Added a Details folder to every zone: themed props along the lane edges and on both cliff tiers, a themed waterfall on each canyon wall (water / crystal water / lava / ice / chocolate), and a backdrop of big voxel mountains (snowy peaks, purple crystal peaks, glowing volcanoes, icy peaks, cake-and-frosting peaks). Meadow has windmills, Cave has minecarts, and Ice has igloos. The middle of each lane stays clear for landing.
- 2026-11-17: Throwing is always straight down the middle (no left/right sway; only throw strength matters). So each lane keeps a clear strip of about 24 studs in the center (|x| < 12) for landing and slime spawns. Both sides of the lane floor are now filled with themed props (Zone.Details.LaneProps).
- 2026-11-17: Decluttered the lanes. The clear center corridor is now 44 studs wide (|x| < 22) so slimes have room to walk up to the jelly during the landing cutscene. Each zone has a ClearHalfWidth = 22 attribute, and LandingArea matches the corridor width. About half the side props and most of the small ground clutter were removed.
- **Trees redesigned (stylized voxel):** All trees rebuilt in the "classic stylized" Lego style. Meadow and hub trees use 3 random variants: (1) branchy with tilted leaf cubes, (2) layered flat tops with a side branch, (3) cube-cluster bush, sometimes with red fruit. Pines are 7-tier stepped pyramids, and Frost Peaks pines have snow lips on every tier. Lava dead trees are dark trunks with forked, angled branches. Candy lollipop trees are unchanged. Each tree stores its build settings as `T_*` attributes, and the old trees are backed up in ServerStorage.OldTreesBackup.
- **All materials studded:** Wood, metal, ice, glass, fabric and smooth plastic were all switched to studded plastic. Each changed part has an `OrigMaterial` attribute so it can be reverted. Neon and the force-field barriers were kept so they still glow.
- **Spawn in your base:** There is no hub spawn any more. Each plot has a SpawnPad with a PlotSpawn spawner just inside the gate, facing the throwing field. A new server script, ServerScriptService.PlotAssignment, gives each joining player the first free plot. It sets the plot's Owner, the player's PlotId attribute and RespawnLocation, and changes the gate sign to "<Name>'s Base". The plot is freed when the player leaves.
- **Throw line on the cliff edge:** The checkered throw line, glow strip and posts were moved about 11 studs forward so the line sits right at the cliff edge (z≈0). The ThrowTrigger and ThrowOrigin were moved to match. The invisible EdgeGuard still stops players from falling off.
- **Spawn outside the base, invisible:** Each PlotSpawn is now invisible (no visible pad), with collisions and touch turned off. It sits on the walkway just outside its base's gate (z=-39), facing the throwing field. The stepping stones inside the base were put back.
- **Collect billboard:** The flat COLLECT and  $text on each CollectPad was replaced with a floating CollectBillboard (BillboardGui) about 3.6 studs above the pad. It shows a green "$" over "COLLECT" in FredokaOne with a dark green outline, visible within 120 studs.
- 2026-11-19: Adopted Miggy's feedback. Gems become the premium currency (earnable with a long grind, buyable with Robux) and unlock Auto-Throw. Slimes get an evolve/absorb system with original designs inspired by the Rimuru fantasy.

## Update

**2026-11-21: game logic and animations are built; the screens are still placeholders.** Everything below is written from the code and the automated tests (39 passing). Nothing here has been confirmed by playing in Studio except where it says so.

### What is built

- **Throw flow:** a 9-band meter with luck multiplier (1.00x to 1.75x), a full baseball-pitch avatar animation (works in Studio on the R6 avatar), bait flight with the luck number and zone banner, then the reveal cutscene: silhouette slime pops up and hops to the bait while a "1 in X" counter climbs, then the reveal with NEW! and SUPER LUCKY! badges.
- **Slimes:** 15 slimes (3 per zone), 5 mutations (Emerald x1.5, Golden x2.5, Crystal x4, Rainbow x7.5 income), hotbar of up to 5 uncaught slimes, placing onto plot slots (8, with a one-time +4 unlock to 12), passive income every second, Slime Index with silhouettes and per-zone trail bonuses.
- **Pull-up training:** press E at your own bar to start a looping pull-up (E again, jump or walk to stop). Rep speed depends on strength and bar tier, from about 1.3 s per rep down to 0.35 s. Each rep adds Throw Power. There are 5 bars (Pull-Up, Iron, Crystal, Magma, Starlight) with more power per rep and faster reps. The server controls the timing, so it can't be sped up. The animation is exaggerated, the server pays each rep at the top of the pull, and while training the camera takes a low front view with a small shake on every rep, plus dust, ring, sweat and "+X" effects. (Not yet confirmed in Studio.)
- **Shop:** one catalog and one purchase path. A UI button only says "buy item X". Prices and rules live in one config, and the shop reads them. Items: 2 eggs (buy 1 or 3), Throw Power upgrade (buy 1 or buy max), bar upgrade, +4 slots, x2 Cash, x2 Training Power, and a one-time free gift.

### What is not built yet

- **Gems, Auto-Throw and the evolve/absorb system from the 2026-11-19 entry:** no code exists for any of them yet. They are design decisions only. The shop catalog already has a reserved price-type field so Gems and Robux items can be added without rebuilding the shop.
- **Saving:** progress is not saved; everything resets each session.
- **Sound, phone layout, settings** (including a toggle to turn camera shake off), tutorial beyond one line of text, daily rewards.
- **Training screen:** nothing on screen shows reps, power gained or seconds per rep while hanging.

### UI status (for the designer)

The Shop, Slime Index, Slimes window, pull-up bar label and HUD are programmer placeholders: flat frames, emoji icons, text-only buttons. The logic behind each one works, so they can be redesigned freely as long as they keep the same information and actions. Priority order: Shop, then the training screen, then the Index, then the HUD. The throw meter and reveal are the closest to final.

### Known issues

- Some prices show a double dollar sign (for example `$$25`). This is a known text bug and will be fixed in code, so don't design around it.
- Old leftover scripts (`Server`, `Client`) may still sit inside the place file and could interfere. They need checking in Studio.
- Economy numbers (costs, power per rep, cash per stud) are a first pass and untuned.

### Where the details are

The full hand-off is in the repo under `docs/docs/`: `UI-HANDOFF.md` (screen by screen), `UI-DATA-CONTRACT.md` (what each screen can read and do), `DATA-REFERENCE.md` (auto-generated names, numbers and colours), `GAME-OVERVIEW.md`, and `SYSTEMS-STATUS.md`.