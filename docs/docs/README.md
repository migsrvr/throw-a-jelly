# Project docs: start here

This game is a Roblox "throw bait, catch slimes, earn money" tycoon. The game rules, math and animations
are built. The **screens (UI) are placeholders** made by the programmer to prove the logic works. They need
a real design pass. These documents describe what exists so a designer can start without reading code.

## In one paragraph

Players walk to the Throw Line, stop a moving slider on a nine-colour meter, and throw a carrot-shaped bait
down a long lane. Where it lands decides which slimes can be caught, and a lucky meter stop improves the odds.
A short cutscene shows a slime creeping up to the bait with a rising "1 in X" counter before the reveal.
Caught slimes go to a hotbar and are placed on the player's own plot, where they earn money every second.
Money buys upgrades, boosts and eggs in the shop. Players also train on a pull-up bar to gain Throw Power,
which lets them throw farther into richer zones.

## Which document to read

| You want to... | Read |
| --- | --- |
| Understand the game and what the UI must communicate | [GAME-OVERVIEW.md](GAME-OVERVIEW.md) |
| Design the screens (**main document**) | [UI-HANDOFF.md](UI-HANDOFF.md) |
| Know exactly what information and buttons each screen can use | [UI-DATA-CONTRACT.md](UI-DATA-CONTRACT.md) |
| Get names, numbers, colours and odds for layout and copy | [DATA-REFERENCE.md](DATA-REFERENCE.md) (auto-generated) |
| See what is finished, untested or broken (for the programmer) | [SYSTEMS-STATUS.md](SYSTEMS-STATUS.md) |
| Add or change a shop item (for the programmer) | [shop-catalog.md](shop-catalog.md) |
| See which screenshots are still needed | [screenshots/README.md](screenshots/README.md) |

## Three rules that keep design and logic apart

1. **The UI never decides prices, odds or rules.** It reads them from the game and shows them. So any
   text box that shows a price, a name or a number must be able to hold whatever the game sends.
2. **Every purchase goes through one path.** A button only says "buy item X". The server decides if it works.
3. **The UI can be rebuilt freely** as long as it keeps showing the same information and offering the same
   actions listed in the hand-off document.

## Where things live (for developers)

- `src/ReplicatedStorage/Shared/GameConfig.luau`: every number and name (zones, slimes, prices, speeds).
- `src/ReplicatedStorage/Shared/ProgressionLogic.luau`: the rules (buying, rewards, odds, training speed).
- `src/StarterPlayer/StarterPlayerScripts/HudController.client.luau`: the main HUD, shop, index and backpack screens.
- `src/StarterPlayer/StarterPlayerScripts/ThrowController.client.luau`: throw meter, flight HUD, reveal cutscene.
- `src/StarterPlayer/StarterPlayerScripts/TrainingController.client.luau`: pull-up training on the client.
- `src/ReplicatedStorage/Shared/UiKit.luau`: the small set of reusable UI helpers.
- Tests: `lune run tests/run-tests`. Refresh the generated data tables: `lune run scripts/gen-docs-data`.

Recorded game clips used as visual reference are in `docs/context-clips/`.
