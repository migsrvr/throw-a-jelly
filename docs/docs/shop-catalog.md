# Shop catalog: how buying works

Everything purchasable goes through **one** path:

```
UI button ──► RequestPurchase { ItemId, Quantity } ──► PlayerStateService.Purchase
                                                   ──► ProgressionLogic.Purchase(profile, itemId, quantity)
                                                   ──► existing reducer (PurchasePowerUpgrade, HatchShopEgg, ...)
```

Prompts in the world (JellyShop, plot UpgradeStand) call `PlayerStateService.Purchase` too, so the rules are
identical everywhere (rate limit, toast, sync).

## Files

| What | Where |
| --- | --- |
| The list of items (id, category, icon, colour) | `GameConfig.ShopCatalog` |
| Prices / names / effects (single source of truth) | `GameConfig.PullUpTiers`, `ShopBoosts`, `ShopEggs`, `Slots`, `GetPowerUpgradeCost`, `FreeGift` |
| Labels, prices, states for the UI | `ProgressionLogic.GetShopListing(state)` / `GetShopListingEntry(state, id)` |
| Buying | `ProgressionLogic.Purchase(profile, itemId, quantity)` |
| Tests | `tests/ProgressionLogic.spec.luau` ("Shop Catalog, Listing & Purchase API"), `tests/Gems.spec.luau` (Gem items) |

## For UI work

UI code never hard-codes prices or rules. It only needs two things:

```lua
-- 1. render: computed locally from the synced state, no extra network traffic
for _, entry in ProgressionLogic.GetShopListing(currentState) do
	-- entry.Title, entry.Subtitle, entry.Icon, entry.Color, entry.PriceText
	-- entry.State: "Available" | "Unaffordable" | "Owned" | "Maxed" | "Claimed"
	-- entry.Options: { { Quantity, Label, Price, CanAfford } }  -- one button per option
end

-- 2. buy
requestPurchase:FireServer({ ItemId = entry.Id, Quantity = option.Quantity })
```

In `HudController.client.luau`, `buyShopItem(itemId, quantity)` and `bindShopLabel(label, itemId, optionIndex, style)`
do exactly this for the current shop layout. Restyle or move the buttons freely; keep the `ItemId`.

## Quantities

| Item action | Allowed `Quantity` |
| --- | --- |
| `PowerUpgrade` | `1` or `"max"` (buys as many as the player can afford) |
| `Egg` | `1` or `3` |
| everything else | `1` |

Anything else is rejected without charging.

## Adding things

- **New egg**: add it to `GameConfig.ShopEggs`, then add a catalog row
  `{ Id = "egg_x", Category = "Egg", Action = "Egg", Args = { EggId = "x_egg" }, Icon = "🥚", Color = {...}, PriceKind = "Cash" }`.
  The shop builds egg cards from `ShopEggs`, so the card appears automatically.
- **New boost**: add it to `GameConfig.ShopBoosts` (and apply its effect in `ProgressionLogic`), then add a catalog row with
  `Action = "Boost", Args = { BoostId = "..." }`.
- **New kind of purchase**: add an `Action` value to `GameConfig.ShopAction`, handle it in `buildListingEntry` and
  `ProgressionLogic.Purchase`, and add a test.
- **New Gem item**: set `PriceKind = "Gems"` on the catalog row (and `Category = "Gem"` so it shows in the Gem
  Shop card in `UpgradesWindow`). Boosts carry their own `PriceKind` in `ShopBoosts`, and a test checks the catalog row matches it.
  The listing then reports `PriceKind = "Gems"`, shows `💎 N`, and checks affordability against `Gems`.
- **Robux Gem Packs & Game Passes (`GameConfig.Robux` + `MonetizationService.luau`)**:
  1. In Roblox Creator Dashboard (or Studio **Game Settings -> Monetization**), create the **Developer Products** for the 4 Gem Packs (`100 / 550 / 1,200 / 2,600 Gems`) and the **Game Passes** (`x2 Luck`, `x2 Cash`, `VIP`).
  2. Copy each asset ID into `GameConfig.Robux.GemPacks` (`ProductId`) and `GameConfig.Robux.Passes` (`PassId`) in `src/ReplicatedStorage/Shared/GameConfig.luau`.
  3. Any entry whose ID is `0` automatically shows a disabled `"Coming soon (R$X)"` button in `RobuxStoreWindow.luau`. As soon as a non-zero ID is set, the button turns green (`"R$ X"`), prompts `MarketplaceService`, and `MonetizationService.ProcessReceipt` grants the Gems, records `PurchaseId` in `profile.ProcessedReceipts`, and saves via `DataService.Save` before returning `PurchaseGranted`.

## Wallets

| `PriceKind` | Paid from | Example items |
| --- | --- | --- |
| `Cash` | `profile.Cash` | power upgrade, bars, bait, x2 boosts, +4 slots ($5K) |
| `Gems` | `profile.Gems` | Auto-Throw, Lucky Charm, +4 slots (60 Gems) |
| `Robux` | Roblox Developer Products (`MonetizationService.ProcessReceipt`) | Featured Slime Eggs (`Enchanted Egg [New!]`, `Rainbow Egg [LIMITED]`) |

The +4 slot unlock exists twice (`slot_expansion` for Cash, `gem_slot_expansion` for Gems); buying either one maxes both.
