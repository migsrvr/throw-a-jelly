# Game overview (plain language)

Numbers quoted here are the current first-pass values. Exact tables are in [DATA-REFERENCE.md](DATA-REFERENCE.md).

## The loop in six steps

1. **Throw.** At the Throw Line the player taps (mouse click, touch or Space) to stop a slider on a vertical
   meter with nine colour bands, from red (worst) at the bottom to bright green (best) at the top. The band
   gives bonus Throw Power and a **luck multiplier** (1.00x up to 1.75x). The avatar does a full baseball-pitch
   animation and the bait flies down the lane.
2. **Land.** The lane is split into five zones: Meadow, Crystal Cave, Lava Fields, Frost Peaks, Candy Land.
   Where the bait stops decides which slimes can be caught. Farther zones need more Throw Power and give more
   money per stud. The player sees the luck number and the current zone name while the bait is in the air.
3. **Reveal.** A cutscene shows a dark silhouette slime rising from the floor and hopping toward the bait while
   a "1 in X" counter climbs. At the end the slime is revealed with its name, rarity or mutation, how much money
   it earns per second, and a "NEW!" badge if it is the first of its kind. A result that is "1 in 10" or rarer, or
   any mutation, also shows "SUPER LUCKY!". Every throw also pays some cash right away, based on how far it went.
4. **Place.** The new slime appears in the hotbar. The player picks it up (it floats in front of the avatar) and
   places it on a free slot on their own plot. A plot has 8 slots; a one-time purchase unlocks 4 more (12 total).
5. **Earn.** Every placed slime earns money every second. The plot shows total income per second and a collect pad.
   Cash also flows directly into the player's wallet.
6. **Spend and grow.** Cash buys power upgrades, better pull-up bars, boosts, eggs (random slimes), and a one-time
   free gift. Training on the pull-up bar raises Throw Power so the player can throw farther.

## Things the player collects

- **Slimes (15).** Three per zone. Each has a rarity: Common, Uncommon, Rare, Epic, Legendary, Mythic.
  Rarer slimes earn more money per second and add Throw Power when equipped.
- **Mutations (5).** Normal, Emerald, Golden, Crystal, Rainbow. Any slime can roll one. A mutation tints the slime,
  multiplies its income (from x1.5 up to x7.5), and makes the "1 in X" odds much bigger (a Rainbow is x60 rarer).
- **Slime Index.** A book of every slime. Undiscovered ones show as dark silhouettes. Finishing a zone's page
  (100%) unlocks that zone's **trail**, a permanent bonus the player can equip: Leaf (+15% training XP),
  Crystal (+20% cash), Magma (+25% power), Frost (+35% cash), Sugar (+50% everything).

## Pull-up training (new)

- The player walks to **their own** pull-up bar and presses **E** (or taps the prompt on mobile).
- The avatar hangs from the bar and does pull-ups on a loop. Each finished rep adds Throw Power and pops a
  floating "+X" over the avatar.
- **E again, jumping, or walking away stops it.**
- Rep speed depends on both strength and the bar tier: a beginner takes about 1.3 seconds per rep, a strong player
  on the best bar about 0.35 seconds. Faster reps mean more power per second. See the speed table in
  [DATA-REFERENCE.md](DATA-REFERENCE.md).
- Five bars: Pull-Up Bar, Iron, Crystal, Magma, Starlight. Each costs more and gives more power per rep and faster reps.

## The shop

- **Eggs:** Enchanted Egg and Rainbow Egg. Buy 1 or 3. Each card shows its possible slimes and their odds.
- **Upgrades:** Throw Power (price rises each level; can buy several at once), pull-up bar tier, +4 plot slots.
- **Boosts (permanent, one each):** x2 Cash, x2 Training Power.
- **Free gift:** one free Emerald Sakura slime, claimable once.

## What the guide arrow and top text do

A text line at the top tells new players what to do next ("Walk to the Throw Line!", "Pick your slime",
"Place your slime", "Train at your pull-up bar!", "Throw bait to catch rarer slimes!"), and a bouncing yellow
arrow in the world points at the matching place. This is a lightweight tutorial and can be redesigned.

## Money terms used in the UI

- **Cash:** the wallet. Shown as `$` plus a short number (1.5K, 2.30M).
- **Throw Power:** strength. Shown with a muscle icon.
- **Income per second:** shown on slimes, the plot sign and slime cards.
- **Luck:** the multiplier from the throw meter, shown during flight as e.g. "1.32X LUCK".
