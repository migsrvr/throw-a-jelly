# UI motion spec

Timings for Claude Code. All tweens use `TweenService`. "Back" = `Enum.EasingStyle.Back`, "Quad" = `Enum.EasingStyle.Quad`.
Respect reduced motion: if the player turns off "Reduce motion" in Settings (future), skip scale pops and shakes, keep fades.

| What | Property | From → To | Time | Easing | Notes |
| --- | --- | --- | --- | --- | --- |
| Window open | UIScale.Scale, backdrop BackgroundTransparency | 0.85 → 1, 1 → 0.45 | 0.22 s | Back Out | content fades in over the same time |
| Window close | UIScale.Scale, backdrop | 1 → 0.9, 0.45 → 1 | 0.14 s | Quad In | destroy/hide on complete |
| Button hover (PC) | UIScale.Scale | 1 → 1.06 | 0.12 s | Quad Out | reverse on leave |
| Button press | UIScale.Scale | 1 → 0.94 → 1 | 0.06 s + 0.12 s | Quad Out, then Back Out | play click sound on down |
| Tab switch | body Position.X + transparency | ±24 px → 0, 1 → 0 | 0.18 s | Quad Out | direction follows the tab order |
| Toast in | Position.Y, transparency | -20 px → 0, 1 → 0 | 0.2 s | Back Out | stays 2.5 s |
| Toast out | transparency | 0 → 1 | 0.25 s | Quad In | |
| Unlock pop-up | Position.Y | -140 px → 72 px | 0.35 s | Back Out | timer bar empties over 5 s, then slide up 0.25 s |
| Cash counter | displayed number | old → new | 0.4 s (max 0.8 s) | Quad Out | number only; never animate on the server |
| Cash gained pulse | stat UIScale | 1 → 1.15 → 1 | 0.25 s | Back Out | also flash the gradient lighter |
| Hotbar select | Position.Y, glow transparency | 0 → -6 px, 1 → 0 | 0.15 s | Back Out | |
| Tutorial arrow | Position.Y | 0 → -12 px, loop | 0.6 s each way | Sine InOut | reverses forever |
| Throw callout follow | callout Position.Y | tracks slider | per frame | none | colour snaps to band |
| PERFECT! | UIScale | 0 → 1.4 → 1 | 0.3 s | Back Out | gold stroke flash on the meter 0.2 s |
| Zone change (flight) | banner UIScale, colour | 1 → 1.15 → 1, old → new | 0.2 s | Back Out | |
| Reveal: odds climb | "1 in X" number | 1 → X | 1.2 s | Quad Out | starts as the silhouette hops |
| Reveal: name in | UIScale | 0 → 1.15 → 1 | 0.35 s | Back Out | after the ring burst |
| Reveal: rays | sunburst Rotation | 0 → 360 | 8 s loop | Linear | Rare and above |
| Reveal: shake | Camera offset | random ±0.3 studs | 0.3 s (Mythic 0.6 s) | decay | Epic and above |
| Reveal: flash | full-screen white transparency | 0 → 1 | 0.4 s | Quad Out | Mythic only |
| Reveal length | whole cutscene | | Common 2 s, Rare 3 s, Mythic 4 s | | tap skips after 0.8 s |
| BONUS REP! | UIScale loop + timer bar | 1 → 1.08, bar 100% → 0 | 0.4 s pulse, 2.5 s bar | Sine InOut / Linear | pop out at 0 if missed |
| LEVEL UP! | UIScale, transparency | 0 → 1.2 → 1, hold 1.2 s, fade | 0.3 s + 0.3 s | Back Out / Quad In | |
| Training XP bar | fill Size.X | old → new | 0.2 s per rep | Quad Out | |
| Daily "today" tile | glow transparency loop | 0.2 ↔ 0.6 | 0.8 s | Sine InOut | |
| Claim (any) | reward icons fly to the stat | tile → stat position | 0.5 s | Quad In | spawn 5-8 icons, then cash pulse |
