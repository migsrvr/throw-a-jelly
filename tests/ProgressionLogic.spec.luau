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
		it("adds XPPerRep on each pull-up rep according to current PullUpTier", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local gain1 = ProgressionLogic.ApplyPullUpRep(p)
			expect(gain1).toBe(GameConfig.PullUpTiers[1].XPPerRep)
			expect(p.BaseThrowPower).toBe(5 + gain1)

			p.Cash = GameConfig.PullUpTiers[2].Cost
			local ok = ProgressionLogic.PurchasePullUpTier(p)
			expect(ok).toBe(true)
			expect(p.PullUpTier).toBe(2)
			expect(p.Cash).toBe(0)

			local gain2 = ProgressionLogic.ApplyPullUpRep(p)
			expect(gain2).toBe(GameConfig.PullUpTiers[2].XPPerRep)
			expect(gain2).toBeGreaterThan(gain1)
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
end
