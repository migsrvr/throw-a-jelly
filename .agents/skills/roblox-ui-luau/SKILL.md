---
name: roblox-ui-luau
description: Use when building, redesigning, or reviewing Roblox UI (ScreenGui, BillboardGui, SurfaceGui, HUD, modals) or Luau gameplay scripts in Roblox Studio / Rojo projects.
---

# Roblox UI & Luau Engineering Best Practices

## Overview

Deliver top-chart Roblox UI craft (tactile 3D-bevel depth, live 3D `ViewportFrame` previews, responsive multi-device `UIScale`, and juicy spring micro-interactions) paired with strict, server-authoritative, unit-tested Luau architecture.

## When to Use

- Creating or redesigning any `ScreenGui`, `BillboardGui`, `SurfaceGui`, HUD, hotbar, shop, or index modal
- Building procedural 3D character animations (`Motor6D`), camera cutscenes, or VFX feedback in Luau
- Structuring Roblox client/server services, RemoteEvents, or pure logic modules for Lune unit tests

**Do not use for:** Non-Roblox web/Flutter UI (use `frontend-design`, `impeccable`, or `flutter-build-responsive-layout` instead).

---

## 1. Roblox UI Craft Floor (Visual Polish & Juice)

Never ship flat, single-color rectangles with unstyled default text. Apply these four craft layers to every primary UI element:

1. **Layered 3D-Bevel Depth & Gloss**:
   - Give interactive buttons and cards a **3D bottom bevel lip** (an outer backing frame colored 25–35% darker than the face, with the inner `Face` frame offset upward by `-4px` and pressing down to `-1px` on click).
   - Apply a subtle vertical `UIGradient` (`Rotation = 90`, top 10% brighter → bottom 10% richer) and crisp dark `UIStroke` (`ApplyStrokeMode.Border` on frames, `ApplyStrokeMode.Contextual` on text).
2. **Real 3D Previews (`ViewportFrame` + `WorldModel`)**:
   - In Hotbar tiles, Index cards, and Shop Egg odds tiles, render the actual 3D model inside a `ViewportFrame` (with a `WorldModel` and dedicated `Camera`) rather than relying solely on Unicode emojis that render inconsistently across Windows, iOS, and Android.
   - For undiscovered/locked Index entries (`???`), render the 3D model in dark silhouette mode (`Color3.fromRGB(18, 22, 28)`) inside the `ViewportFrame`.
3. **Tactile Micro-Interactions (`TweenService` Spring Juice)**:
   - Attach a child `UIScale` to every button and modal:
     - **Hover**: tween `UIScale.Scale` to `1.06` (`0.12s`, `Enum.EasingStyle.Quad`).
     - **Press**: tween `UIScale.Scale` to `0.93` and shift the inner bevel `Face` down (`0.07s`).
     - **Release**: bounce `UIScale.Scale` back to `1.0` (`0.18s`, `Enum.EasingStyle.Back`, `Enum.EasingDirection.Out`).
   - **Modal Open/Close**: pop modals in from `UIScale.Scale = 0.82 -> 1.0` with `EasingStyle.Back` while fading a dark full-screen backdrop scrim (`BackgroundTransparency = 0.42`).
4. **High-Contrast Typography**:
   - Use bold display fonts (`Enum.Font.FredokaOne` or `GothamBlack`) with dark `UIStroke` (`Thickness = 2..3`).
   - Pair `TextScaled = true` with a `UITextSizeConstraint` (`MinTextSize`, `MaxTextSize`) so text never overflows on narrow screens or becomes unreadably tiny.
   - Format all large numbers with suffix helpers (`$1.2K`, `$4.5M`, `1.25x`).

See [references/ui-primitives.md](./references/ui-primitives.md) for reusable `UiKit.luau` implementations.

---

## 2. Responsive Multi-Device Layout (PC, Mobile, Tablet, Console)

- **Adaptive Root `UIScale`**: Bind `workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize")` to compute a proportional scale factor (`math.clamp(math.min(vp.X / 1366, vp.Y / 768), 0.68, 1.18)`).
- **Safe Zones**:
  - Keep top-left clear of Roblox CoreGui topbar buttons (`Y >= 12` with `IgnoreGuiInset = false`, or `Y >= 56` if `IgnoreGuiInset = true`).
  - Keep bottom-left and bottom-right clear of mobile thumbstick and jump button zones; anchor side navigation buttons near vertical center (`0.45..0.55 Y`) and hotbars at bottom-center.

---

## 3. Industry-Standard Luau Architecture

1. **Strict Typing (`--!strict`)**:
   - Every `.luau` file begins with `--!strict` and exports explicit `export type` contracts for state, configs, and payloads.
2. **Pure Core Logic + Lune Unit Testing**:
   - Decouple physics simulations (`ThrowPhysics.luau`), economy/inventory reducers (`ProgressionLogic.luau`), and static tables (`GameConfig.luau`) from live Roblox services (`Players`, `Workspace`, `RunService`) so they can be verified deterministically in the terminal via `lune run tests/run-tests`.
3. **Server-Authoritative RemoteEvents**:
   - Never trust client-sent currency, power, or item IDs. Validate `type(payload) == "table"`, clamp numerical inputs (`math.clamp`), enforce per-player rate-limit cooldowns (`os.clock()`), and compute rewards authoritatively on the server.
4. **Modern Task & Lifecycle Hygiene**:
   - Always use `task.wait`, `task.spawn`, `task.defer`, and `task.delay` (never legacy `wait()` or `spawn()`).
   - Disconnect temporary `RenderStepped` / `Heartbeat` connections and destroy temporary VFX instances once their tween/animation completes.

See [references/luau-patterns.md](./references/luau-patterns.md) for architecture and dual-runtime test patterns.

---

## Common Mistakes to Avoid

| Mistake | Fix |
| :--- | :--- |
| Flat `Frame` buttons with no bevel, stroke, or press feedback | Use `UiKit.CreateBevelButton` with 3D lip + `UIScale` spring tweens |
| Fixed pixel modals (`650x420`) overflowing on mobile phones | Attach `UiKit.AttachResponsiveScale(screenGui)` to scale proportionally |
| Relying on raw Unicode emojis for core item/slime icons | Render live 3D models inside a `ViewportFrame` (`UiKit.CreateSlimeViewport`) |
| Coupling economy/physics math to `Players` or `Workspace` | Keep reducers pure and test with `lune run tests/run-tests` |
| Unbounded `RenderStepped` loops leaking after cutscene ends | Disconnect connections cleanly on completion and restore `CameraType.Custom` |
