# Systems status (for the programmer)

Snapshot of what is built, what is tested, what is only written but never seen running, and what is missing.
Written from the code and test runs. **Nothing here was verified by playing the game**, so "built" does not
mean "looks right in Studio". Update this file as items get confirmed.

Legend: ✅ built and covered by automated tests · 🟡 built, **not yet confirmed in Studio** · 🔴 known problem · ⬜ not built

## Server systems

| System | Status | Notes |
| --- | --- | --- |
| Player profile (cash, power, slimes, boosts, discoveries) | ✅ | `ProgressionLogic.luau`; created fresh on join |
| **Saving progress** | ⬜ | **Nothing is saved.** No DataStore anywhere; progress resets every session. Biggest gap before any real playtest |
| Throw validation and landing/reward | ✅ | `ThrowService.luau` + `ThrowPhysics.luau`; server re-simulates the throw |
| Zone gating by Throw Power | ✅ | tested in `ThrowPhysics.spec` |
| Slime roll, mutation roll, "1 in X", super lucky | ✅ | `EvaluateThrowReward` |
| Slime Index discovery and zone trails | ✅ | trail bonus applies to XP / cash / power |
| Place / pick up slimes on plot slots, auto-place best | ✅ | |
| Passive income (every second) and collect pad | ✅ | cash goes straight to the wallet; collect pad also works |
| Plot assignment per player | 🟡 | `PlotAssignment.server.luau`; legacy script, not covered by tests |
| Pull-up training loop (toggle, cadence, anti-cheat) | 🟡 | `PlotService.luau`; speed rule is tested, the loop itself is not |
| Shop catalog + single purchase path | ✅ | `RequestPurchase`; 7 purchase tests; see [shop-catalog.md](shop-catalog.md) |
| Leaderboards in the hub | 🟡 | refreshed from `PlotService.luau`; untested |
| Map clean-up (flicker/shadow fixes) | 🟡 | `MapOptimizer.luau`, runs once on start; edits ~13,000 map parts |
| Robux purchases (passes, products) | ⬜ | catalog has a reserved `PriceKind`, no code |

## Client systems

| System | Status | Notes |
| --- | --- | --- |
| HUD, hotbar, objective arrow | 🟡 | `HudController.client.luau`; placeholder styling, see [UI-HANDOFF.md](UI-HANDOFF.md) |
| Shop window | 🟡 | now driven by the shared shop list; prices no longer typed in UI code |
| Slime Index, Slimes backpack | 🟡 | placeholder styling |
| Throw meter, flight HUD, reveal cutscene | 🟡 | `ThrowController.client.luau`; closest to final |
| Training controller (floating "+X", stop on jump/walk) | 🟡 | `TrainingController.client.luau` |
| Sound | ⬜ | none |
| Mobile layout / controller support | ⬜ | scales to window only |

## Animations

| Animation | R6 | R15 | Notes |
| --- | --- | --- | --- |
| Baseball pitch (wind-up, whip, follow-through) | ✅ confirmed working in Studio | 🟡 | root cause of the earlier "nothing moves" bug was unconfirmed; fix was posing joints in two frame stages and handling both joint types |
| Aim pose + bait in hand | 🟡 | 🟡 | |
| Carry a slime in front | 🟡 | 🟡 | pauses during throws and pull-ups |
| Pull-up loop | 🟡 reported frozen once, fix applied | 🟡 | R6 has no elbows so arms cannot fold; being reworked in a parallel session (`PullUpMotion.luau`, exaggerated motion, rep paid at the top of the pull). Re-check after that lands |

How joints are driven: `CharacterAnimator.luau` writes joint offsets (`Motor6D.C0`) every frame on the client only.
The server never animates; it only holds the character under the bar with physics constraints (not anchoring,
because anchoring made the server own the body and froze the client animation).

## Tests

`lune run tests/run-tests` -> **31 tests, all passing** at the time of writing.
- Throw physics (trajectory, bounces, zone gating)
- Profile logic: rewards, mutation and odds, hotbar and slots, index and trails, power and bar upgrades
- Pull-up rep speed (monotonic in strength and tier, floors at the minimum)
- Shop: list states, every purchase path, bad ids and quantities rejected without charging
- Not covered: anything that needs Roblox itself (animations, UI, plot objects, the training loop, prompts)

The generated data tables in [DATA-REFERENCE.md](DATA-REFERENCE.md) come from `lune run scripts/gen-docs-data`.

## Known problems

1. 🔴 **Double dollar sign in text** (for example `$$25`). The text templates use `$${...}`, which prints two
   dollar signs. About 22 places across `ProgressionLogic.luau`, `PlotService.luau`, `HudController.client.luau`,
   `ThrowController.client.luau`, `SlimeFactory.luau`. Shop prices from the new shop list are correct; error
   messages like "Need $$25 Cash" and the bar billboard "Upgrade: $$75" are not. Fix: replace `$${` with `${`.
2. 🔴 **No saving** (above).
3. 🟡 **Debug output still on:** `DEBUG = true` in `CharacterAnimator.luau`, the `[ThrowController] loaded` print in
   `ThrowController.client.luau`, and the `[TrainingController] TrainingState` print in `TrainingController.client.luau`.
4. 🟡 **Old scripts inside the place file.** `docs/place-hierarchy.txt` lists a `Server` script and a `Client` local
   script that are not in the repo. The Rojo project keeps unknown instances, so they may still run and interfere. Check
   the Explorer in Studio and delete them if they are leftovers.
5. 🟡 **Old remotes may linger** in Studio (`RequestUpgrade`, `RequestHatchEgg`, `RequestBuyBoost`,
   `RequestClaimFreeGift`, `RequestTrainRep`). Nothing uses them any more; safe to delete.
6. 🟡 **Pull-up bar geometry unverified.** The hang position is computed from the bar's size and the plot's `TrainSpot`
   part; checked for none of the five plots.
7. 🟡 **Economy is first-pass.** Tier XP per rep rises 4x per tier, costs rise ~6x; zone cash per stud rises 80x from
   first to last. Nobody has played through it. A pull-up at the best bar with high strength earns up to ~1,700 power
   per second, so the economy should be simulated before tuning UI around it.
8. 🟡 **Hub Jelly Shop prompt** buys one Power Upgrade directly instead of opening the shop window.
9. 🟡 **Hotbar shows at most 5 slimes** (extra slimes are only visible in the Slimes window).

## Not built (decisions for you)

Saving, sound, Robux monetization, tutorial beyond one line of text, settings, daily rewards, achievements, player stats
screen, phone layout, controller support, a rebirth/prestige system if the design wants one.

## Git state

Last commit: "Working throw and slime animations". Not committed yet: the pull-up training loop, the shop catalog and
`RequestPurchase`, `TrainingController`, `PullUpMotion` and these docs.
