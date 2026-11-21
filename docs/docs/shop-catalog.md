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
  Shop card). Boosts carry their own `PriceKind` in `ShopBoosts`, and a test checks the catalog row matches it.
  The listing then reports `PriceKind = "Gems"`, shows `💎 N`, and checks affordability against `Gems`.
- **Robux later**: a `"Robux"` `PriceKind` would be granted from a `MarketplaceService.ProcessReceipt` handler
  that calls the same reducers (and must save the profile before returning `PurchaseGranted`).

## Wallets

| `PriceKind` | Paid from | Example items |
| --- | --- | --- |
| `Cash` | `profile.Cash` | power upgrade, bars, bait, eggs, x2 boosts, +4 slots ($5K) |
| `Gems` | `profile.Gems` | Auto-Throw, Lucky Charm, +4 slots (60 Gems) |

The +4 slot unlock exists twice (`slot_expansion` for Cash, `gem_slot_expansion` for Gems); buying either one maxes both.
