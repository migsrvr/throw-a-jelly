--!strict
--[[
	tests/ProgressionLogic.spec.luau
	Unit tests for player profile reducers: Pull-Up Bar training, Throw Power & Gym Tier
	upgrades, Plot Slot expansion (+4 SLOTS for $5K), throw rewards & slime drops,
	and passive income collection.
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

			-- Upgrade to Tier 2 (Iron Bar)
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

	describe("ProgressionLogic - Throw Rewards, Slime Drops & Passive Income", function()
		it("awards zone-scaled cash, unlocks a zone slime, and auto-places up to MaxSlimes", function()
			local p = ProgressionLogic.CreateInitialProfile()
			-- Roll rare slime in Zone 2 (unitRandom = 0.95)
			local outcome = ProgressionLogic.EvaluateThrowReward(p, 320, 2, 0.95)

			expect(outcome.CashEarned).toBeGreaterThan(100)
			expect(p.Cash).toBe(outcome.CashEarned)
			expect(outcome.IsNewBestDistance).toBe(true)
			expect(p.BestDistance).toBe(320)
			expect(outcome.CaughtSlimeDef.ZoneIndex).toBe(2)
			expect(outcome.AutoPlaced).toBe(true)
			expect(#p.OwnedSlimes).toBe(2)
			expect(#p.PlacedSlimes).toBe(2)
		end)

		it("accumulates passive income over time and transfers whole dollars on Collect", function()
			local p = ProgressionLogic.CreateInitialProfile()
			-- Starter slime makes $2/s
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
end
