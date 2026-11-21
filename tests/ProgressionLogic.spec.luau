--!strict
--[[
	tests/ProgressionLogic.spec.luau
	Unit tests for player profile reducers: Pull-Up Bar training, Throw Power & Gym Tier
	upgrades, Plot Slot expansion (+4 SLOTS for $5K), throw rewards, Mutations, "1 in X"
	odds, Slime Index discovery & Zone Trail bonuses, Hotbar-to-Slot manual placement,
	Shop Free Gift claim, and Featured Egg hatching.
]]

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local ProgressionLogic = require("../src/ReplicatedStorage/Shared/ProgressionLogic")

return function(t: any)
	local describe = t.describe
	local it = t.it
	local expect = t.expect

	describe("ProgressionLogic - Initial Profile & Derived Stats", function()
		it("initializes with starter Meadow Sprout slime equipped and placed", function()
			local p = ProgressionLogic.CreateInitialProfile()
			expect(p.Cash).toBe(0)
			expect(p.MaxSlimes).toBe(8)
			expect(p.EquippedSlimeId).toBe("meadow_sprout")
			expect(#p.OwnedSlimes).toBe(1)
			expect(#p.PlacedSlimes).toBe(1)
			expect(ProgressionLogic.GetEffectiveThrowPower(p)).toBe(5)
			expect(ProgressionLogic.GetIncomePerSecond(p)).toBe(2)
		end)
	end)

	describe("ProgressionLogic - Pull-Up Bar Training & Gym Tiers", function()
		it("adds Training XP (not raw power) per rep according to current PullUpTier", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local r1 = ProgressionLogic.ApplyPullUpRep(p)
			expect(r1.XPGained).toBe(GameConfig.PullUpTiers[1].XPPerRep)
			expect(p.TrainingXP).toBe(r1.XPGained)
			expect(r1.LevelsGained).toBe(0)
			expect(p.BaseThrowPower).toBe(5) -- power only comes from level ups now

			p.Cash = GameConfig.PullUpTiers[2].Cost
			local ok = ProgressionLogic.PurchasePullUpTier(p)
			expect(ok).toBe(true)
			expect(p.PullUpTier).toBe(2)
			expect(p.Cash).toBe(0)

			local r2 = ProgressionLogic.ApplyPullUpRep(p)
			expect(r2.XPGained).toBe(GameConfig.PullUpTiers[2].XPPerRep)
			expect(r2.XPGained).toBeGreaterThan(r1.XPGained)
		end)

		it("levels up exactly at the XP threshold and gives +PowerPerLevel Throw Power", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local required = GameConfig.GetXPRequiredForLevel(1)
			local xpPerRep = GameConfig.PullUpTiers[1].XPPerRep
			local repsNeeded = math.ceil(required / xpPerRep)
			for _ = 1, repsNeeded - 1 do
				expect(ProgressionLogic.ApplyPullUpRep(p).LevelsGained).toBe(0)
			end
			expect(p.StrengthLevel).toBe(1)
			local r = ProgressionLogic.ApplyPullUpRep(p)
			expect(r.LevelsGained).toBe(1)
			expect(r.PowerGained).toBe(GameConfig.Training.PowerPerLevel)
			expect(p.StrengthLevel).toBe(2)
			expect(p.BaseThrowPower).toBe(5 + GameConfig.Training.PowerPerLevel)
			expect(p.TrainingXP).toBe(repsNeeded * xpPerRep - required) -- leftover XP carries over
			expect(r.RequiredXP).toBe(GameConfig.GetXPRequiredForLevel(2))
		end)

		it("rolls over multiple levels from one big rep", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.PullUpTier = #GameConfig.PullUpTiers -- 600 XP / rep
			local r = ProgressionLogic.ApplyPullUpRep(p)
			expect(r.LevelsGained).toBeGreaterThan(1)
			expect(p.StrengthLevel).toBe(1 + r.LevelsGained)
			expect(p.BaseThrowPower).toBe(5 + r.LevelsGained * GameConfig.Training.PowerPerLevel)
			expect(p.TrainingXP < GameConfig.GetXPRequiredForLevel(p.StrengthLevel)).toBe(true)
		end)

		it("multiplies XP by the Bonus Rep multiplier", function()
			local a = ProgressionLogic.CreateInitialProfile()
			local b = ProgressionLogic.CreateInitialProfile()
			a.PullUpTier, b.PullUpTier = 3, 3
			local normal = ProgressionLogic.ApplyPullUpRep(a).XPGained
			local bonus = ProgressionLogic.ApplyPullUpRep(b, GameConfig.Training.BonusRepMultiplier).XPGained
			expect(bonus).toBe(normal * GameConfig.Training.BonusRepMultiplier)
		end)

		it("follows the documented XP curve", function()
			expect(GameConfig.GetXPRequiredForLevel(1)).toBe(10)
			expect(GameConfig.GetXPRequiredForLevel(5)).toBe(87)
			expect(GameConfig.GetXPRequiredForLevel(10)).toBe(223)
			expect(GameConfig.GetXPRequiredForLevel(20)).toBe(570)
		end)

		it("rejects Pull-Up Tier upgrade when cash is insufficient or at max tier", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local okLow = ProgressionLogic.PurchasePullUpTier(p)
			expect(okLow).toBe(false)
			expect(p.PullUpTier).toBe(1)

			p.PullUpTier = #GameConfig.PullUpTiers
			p.Cash = 999999
			local okMax = ProgressionLogic.PurchasePullUpTier(p)
			expect(okMax).toBe(false)
		end)
	end)

	describe("ProgressionLogic - Throw Power & Slot Expansion Upgrades", function()
		it("purchases Throw Power upgrades when affordable and increases effective power", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local beforePower = ProgressionLogic.GetEffectiveThrowPower(p)
			local cost = GameConfig.GetPowerUpgradeCost(p.PowerUpgradeLevel)

			local okFail = ProgressionLogic.PurchasePowerUpgrade(p)
			expect(okFail).toBe(false)

			p.Cash = cost + 10
			local okPass = ProgressionLogic.PurchasePowerUpgrade(p)
			expect(okPass).toBe(true)
			expect(p.Cash).toBe(10)
			expect(p.PowerUpgradeLevel).toBe(2)
			expect(ProgressionLogic.GetEffectiveThrowPower(p)).toBeGreaterThan(beforePower)
		end)

		it("expands MaxSlimes from 8 to 12 for $5,000 and prevents duplicate purchase", function()
			local p = ProgressionLogic.CreateInitialProfile()
			expect(p.MaxSlimes).toBe(8)

			p.Cash = 4999
			local okInsufficient = ProgressionLogic.PurchaseSlotExpansion(p)
			expect(okInsufficient).toBe(false)
			expect(p.MaxSlimes).toBe(8)

			p.Cash = 5000
			local okSuccess = ProgressionLogic.PurchaseSlotExpansion(p)
			expect(okSuccess).toBe(true)
			expect(p.Cash).toBe(0)
			expect(p.MaxSlimes).toBe(12)

			p.Cash = 10000
			local okDuplicate = ProgressionLogic.PurchaseSlotExpansion(p)
			expect(okDuplicate).toBe(false)
			expect(p.MaxSlimes).toBe(12)
		end)
	end)

	describe("ProgressionLogic - Throw Rewards, Mutations, '1 in X' Odds & Hotbar Placement", function()
		it("awards zone-scaled cash, rolls mutation & 1-in-X odds, and places in hotbar when requested", function()
			local p = ProgressionLogic.CreateInitialProfile()
			-- Roll rare slime in Zone 2 (unitRandom = 0.95) with EMERALD mutation (mutationRandom = 0.80)
			local outcome = ProgressionLogic.EvaluateThrowReward(p, 320, 2, 0.95, 1.5, 0.80, true)

			expect(outcome.CashEarned).toBeGreaterThan(100)
			expect(outcome.CaughtSlimeDef.ZoneIndex).toBe(2)
			expect(outcome.Mutation).toBe("EMERALD")
			expect(outcome.OddsOneInX).toBeGreaterThanOrEqual(10)
			expect(outcome.IsSuperLucky).toBe(true)
			expect(outcome.IsNewDiscovery).toBe(true)
			expect(#p.UnplacedSlimes).toBe(1)

			-- Second catch of the same slime should have IsNewDiscovery = false
			local outcome2 = ProgressionLogic.EvaluateThrowReward(p, 320, 2, 0.95, 1.5, 0.10, true)
			expect(outcome2.CaughtSlimeId).toBe(outcome.CaughtSlimeId)
			expect(outcome2.IsNewDiscovery).toBe(false)
		end)

		it("places hotbar slime onto a specific plot slot and picks it back up cleanly", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local outcome = ProgressionLogic.EvaluateThrowReward(p, 200, 1, 0.85, 1.2, 0.80, true)
			local caughtUid = outcome.CaughtInstance.Uid
			local baseIncome = ProgressionLogic.GetIncomePerSecond(p)

			local okPlace = ProgressionLogic.PlaceSlimeAtSlot(p, caughtUid, 2)
			expect(okPlace).toBe(true)
			expect(#p.UnplacedSlimes).toBe(0)
			expect(p.PlacedSlimesBySlot[2]).toBeTruthy()
			expect(ProgressionLogic.GetIncomePerSecond(p)).toBe(baseIncome + outcome.CaughtInstance.IncomePerSec)

			local okPickup = ProgressionLogic.PickupSlimeFromSlot(p, 2)
			expect(okPickup).toBe(true)
			expect(#p.UnplacedSlimes).toBe(1)
			expect(p.PlacedSlimesBySlot[2]).toBe(nil)
		end)

		it("accumulates passive income over time and transfers whole dollars on Collect", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local pending = ProgressionLogic.TickPassiveIncome(p, 3.7)
			expect(pending).toBeNear(7.4, 1e-4)

			local collected = ProgressionLogic.CollectPendingIncome(p)
			expect(collected).toBe(7)
			expect(p.Cash).toBe(7)
			expect(p.PendingIncome).toBeNear(0.4, 1e-4)
		end)

		it("sorts and places highest-income slimes when PlaceBestSlimes is called", function()
			local p = ProgressionLogic.CreateInitialProfile()
			table.insert(p.OwnedSlimes, "candy_royal")
			table.insert(p.OwnedSlimes, "crystal_quartz")
			ProgressionLogic.PlaceBestSlimes(p)

			expect(p.PlacedSlimes[1]).toBe("candy_royal")
			expect(p.PlacedSlimes[2]).toBe("crystal_quartz")
			expect(p.PlacedSlimes[3]).toBe("meadow_sprout")
		end)
	end)

	describe("ProgressionLogic - Slime Index, Zone Trails & Shop Actions", function()
		it("calculates Zone Index completion % and unlocks Zone Trail bonus at 100%", function()
			local p = ProgressionLogic.CreateInitialProfile()
			-- Meadow starts with 1/3 discovered (33%)
			local prog1 = ProgressionLogic.GetZoneIndexProgress(p, 1)
			expect(prog1.UnlockedCount).toBe(1)
			expect(prog1.TotalCount).toBe(3)
			expect(prog1.IsComplete).toBe(false)

			local okTrailBefore = ProgressionLogic.EquipZoneTrail(p, 1)
			expect(okTrailBefore).toBe(false)

			p.DiscoveredSlimes["meadow_honey"] = true
			p.DiscoveredSlimes["meadow_bloom"] = true
			local progDone = ProgressionLogic.GetZoneIndexProgress(p, 1)
			expect(progDone.Percent).toBe(100)
			expect(progDone.IsComplete).toBe(true)

			local okTrailAfter = ProgressionLogic.EquipZoneTrail(p, 1)
			expect(okTrailAfter).toBe(true)
			expect(p.EquippedTrailZone).toBe(1)
		end)

		it("claims the Shop Free Gift slime once and hatches Featured Eggs", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local okGift1, _, giftInst = ProgressionLogic.ClaimFreeGiftSlime(p)
			expect(okGift1).toBe(true)
			expect(giftInst).toBeTruthy()
			expect(#p.UnplacedSlimes).toBe(1)

			local okGift2 = ProgressionLogic.ClaimFreeGiftSlime(p)
			expect(okGift2).toBe(false)

			p.Cash = 500
			local okEgg, _, hatched = ProgressionLogic.HatchShopEgg(p, "enchanted_egg", 3, function()
				return 0.5
			end)
			expect(okEgg).toBe(true)
			expect(#hatched).toBe(3)
			expect(#p.UnplacedSlimes).toBe(4)
		end)
	end)

	describe("ProgressionLogic - Jelly Bait Quality & Flight Luck", function()
		it("buys bait tiers in order, charges the cost, and stops at max tier", function()
			local p = ProgressionLogic.CreateInitialProfile()
			expect(p.BaitTier).toBe(1)
			expect((ProgressionLogic.PurchaseBaitTier(p))).toBe(false) -- $0 cash
			expect(p.BaitTier).toBe(1)

			p.Cash = 1e7
			for tier = 2, #GameConfig.BaitTiers do
				local before = p.Cash
				expect((ProgressionLogic.PurchaseBaitTier(p))).toBe(true)
				expect(p.BaitTier).toBe(tier)
				expect(p.Cash).toBe(before - GameConfig.BaitTiers[tier].Cost)
			end
			local cashAtMax = p.Cash
			expect((ProgressionLogic.PurchaseBaitTier(p))).toBe(false)
			expect(p.Cash).toBe(cashAtMax)
		end)

		it("sells bait through the shop catalog with Maxed state at the top tier", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.Cash = GameConfig.BaitTiers[2].Cost
			expect(ProgressionLogic.GetShopListingEntry(p, "bait_tier").Title).toBe(GameConfig.BaitTiers[2].Name)
			expect((ProgressionLogic.Purchase(p, "bait_tier", 1))).toBe(true)
			expect(p.BaitTier).toBe(2)
			p.BaitTier = #GameConfig.BaitTiers
			expect(ProgressionLogic.GetShopListingEntry(p, "bait_tier").State).toBe("Maxed")
		end)

		it("ComputeFlightLuck grows with distance, meter luck and bait luck", function()
			expect(GameConfig.ComputeFlightLuck(0, 1, 1)).toBeNear(1)
			local prev = 0
			for _, d in { 0, 100, 350, 700, 1200 } do
				local v = GameConfig.ComputeFlightLuck(d, 1, 1)
				expect(v > prev).toBe(true)
				prev = v
			end
			expect(GameConfig.ComputeFlightLuck(350, 1, 1)).toBeNear(2)
			expect(GameConfig.ComputeFlightLuck(350, 1.5, 1) > GameConfig.ComputeFlightLuck(350, 1, 1)).toBe(true)
			expect(GameConfig.ComputeFlightLuck(350, 1, 2) > GameConfig.ComputeFlightLuck(350, 1, 1)).toBe(true)
			-- never below 1x even with bad inputs
			expect(GameConfig.ComputeFlightLuck(-50, 0.5, 0.2)).toBeNear(1)
		end)

		it("top meter band is a PERFECT +20", function()
			local top = GameConfig.EvaluateMeterRatio(1.0)
			expect(top.IsPerfect).toBe(true)
			expect(top.BonusPower).toBe(20)
			expect(GameConfig.EvaluateMeterRatio(0.5).IsPerfect == true).toBe(false)
		end)
	end)

	describe("ProgressionLogic - Pull-Up Loop Speed (strength + bar tier)", function()
		local cfg = GameConfig.PullUp

		it("gets faster as strength (BaseThrowPower) grows", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local prev = ProgressionLogic.GetPullUpRepInterval(p)
			for _, power in { 20, 100, 500, 2000 } do
				p.BaseThrowPower = power
				local cur = ProgressionLogic.GetPullUpRepInterval(p)
				expect(cur <= prev).toBe(true)
				prev = cur
			end
			p.BaseThrowPower = 5
			p.PullUpTier = 1
			expect(ProgressionLogic.GetPullUpRepInterval(p)).toBeLessThanOrEqual(cfg.BaseRepSeconds)
			expect(ProgressionLogic.GetPullUpRepInterval(p)).toBeGreaterThan(1.0)
		end)

		it("gets faster with better bar tiers at the same strength", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.BaseThrowPower = 50
			local prev = math.huge
			for tier = 1, #GameConfig.PullUpTiers do
				p.PullUpTier = tier
				local cur = ProgressionLogic.GetPullUpRepInterval(p)
				expect(cur < prev).toBe(true)
				prev = cur
			end
		end)

		it("never goes below MinRepSeconds or above BaseRepSeconds", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.BaseThrowPower = 1e12
			p.PullUpTier = #GameConfig.PullUpTiers
			expect(ProgressionLogic.GetPullUpRepInterval(p)).toBeNear(cfg.MinRepSeconds)
			p.BaseThrowPower = 0
			p.PullUpTier = 1
			expect(ProgressionLogic.GetPullUpRepInterval(p)).toBeLessThanOrEqual(cfg.BaseRepSeconds)
		end)
	end)

	describe("ProgressionLogic - Shop Catalog, Listing & Purchase API", function()
		it("has a valid listing entry for every catalog item", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local listing = ProgressionLogic.GetShopListing(p)
			expect(#listing).toBe(#GameConfig.ShopCatalog)
			for i, entry in listing do
				expect(entry.Id).toBe(GameConfig.ShopCatalog[i].Id)
				expect(entry.Title ~= entry.Id).toBe(true) -- every action filled a real title
				expect(entry.PriceText ~= "").toBe(true)
			end
		end)

		it("reports Unaffordable / Available from cash, and FREE for the gift", function()
			local p = ProgressionLogic.CreateInitialProfile()
			expect(ProgressionLogic.GetShopListingEntry(p, "boost_double_cash").State).toBe("Unaffordable")
			expect(ProgressionLogic.GetShopListingEntry(p, "free_gift").State).toBe("Available")
			expect(ProgressionLogic.GetShopListingEntry(p, "free_gift").PriceText).toBe("FREE")
			p.Cash = 1e6
			expect(ProgressionLogic.GetShopListingEntry(p, "boost_double_cash").State).toBe("Available")
		end)

		it("works with the client's synced state table, not only a full profile", function()
			local synced = { Cash = 100, PowerUpgradeLevel = 1, PullUpTier = 5, MaxSlimes = 12, OwnedBoosts = { double_cash = true }, ClaimedFreeGift = true }
			expect(ProgressionLogic.GetShopListingEntry(synced, "pullup_tier").State).toBe("Maxed")
			expect(ProgressionLogic.GetShopListingEntry(synced, "slot_expansion").State).toBe("Maxed")
			expect(ProgressionLogic.GetShopListingEntry(synced, "boost_double_cash").State).toBe("Owned")
			expect(ProgressionLogic.GetShopListingEntry(synced, "free_gift").State).toBe("Claimed")
			expect(ProgressionLogic.GetShopListingEntry(synced, "power_upgrade").State).toBe("Available")
		end)

		it("buys each upgrade/boost through Purchase and charges the listed price", function()
			for _, id in { "power_upgrade", "pullup_tier", "bait_tier", "slot_expansion", "boost_double_cash", "boost_double_power" } do
				local p = ProgressionLogic.CreateInitialProfile()
				p.Cash = 1e6
				local price = ProgressionLogic.GetShopListingEntry(p, id).Price
				local ok = ProgressionLogic.Purchase(p, id, 1)
				expect(ok).toBe(true)
				expect(p.Cash).toBe(1e6 - price)
			end
		end)

		it("rejects Cash purchases on Robux-only Eggs, hatches Robux Eggs via GrantRobuxEgg, and claims the free gift", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.Cash = 1e6
			-- Featured Eggs are Robux-only and must not be purchasable with Cash ($)
			local okCash1 = ProgressionLogic.Purchase(p, "egg_enchanted", 1)
			expect(okCash1).toBe(false)
			expect(p.Cash).toBe(1e6)

			local ok1, _, h1 = ProgressionLogic.GrantRobuxEgg(p, "enchanted_egg", 1, "rcpt_egg_1")
			expect(ok1).toBe(true)
			expect(#h1).toBe(1)
			expect(p.Cash).toBe(1e6) -- no Cash deducted

			-- Duplicate receipt must be rejected
			local okDup = ProgressionLogic.GrantRobuxEgg(p, "enchanted_egg", 1, "rcpt_egg_1")
			expect(okDup).toBe(false)

			local ok3, _, h3 = ProgressionLogic.GrantRobuxEgg(p, "enchanted_egg", 3, "rcpt_egg_3")
			expect(ok3).toBe(true)
			expect(#h3).toBe(3)

			local okGift, _, gift = ProgressionLogic.Purchase(p, "free_gift")
			expect(okGift).toBe(true)
			expect(#gift).toBe(1)
			expect((ProgressionLogic.Purchase(p, "free_gift"))).toBe(false)
		end)

		it("'max' buys as many power upgrades as cash allows", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.Cash = 1000
			local ok, _, bought = ProgressionLogic.Purchase(p, "power_upgrade", "max")
			expect(ok).toBe(true)
			expect(bought).toBeGreaterThan(1)
			expect(p.Cash < GameConfig.GetPowerUpgradeCost(p.PowerUpgradeLevel)).toBe(true)
			expect((ProgressionLogic.Purchase(p, "power_upgrade", "max"))).toBe(false)
		end)

		it("rejects unknown items, bad quantities, and insufficient cash without charging", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.Cash = 50
			expect((ProgressionLogic.Purchase(p, "not_an_item", 1))).toBe(false)
			expect((ProgressionLogic.Purchase(p, "egg_enchanted", 2))).toBe(false)
			expect((ProgressionLogic.Purchase(p, "boost_double_cash", 3))).toBe(false)
			expect((ProgressionLogic.Purchase(p, "pullup_tier", "max"))).toBe(false)
			expect((ProgressionLogic.Purchase(p, "boost_double_cash", 1))).toBe(false)
			expect(p.Cash).toBe(50)
		end)
	end)
end
