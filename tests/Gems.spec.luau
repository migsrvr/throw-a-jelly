--!strict
--[[
	tests/Gems.spec.luau
	Gems premium currency: earning (Index milestones, first zone reach, daily streak, rare catches),
	spending through the single shop purchase path (Auto-Throw, Lucky Charm, gem slot unlock),
	and the shop listing showing the right wallet.
]]

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local ProgressionLogic = require("../src/ReplicatedStorage/Shared/ProgressionLogic")

return function(t: any)
	local describe = t.describe
	local it = t.it
	local expect = t.expect

	local gemsCfg = GameConfig.Gems

	describe("Gems - Earning", function()
		it("starts every profile with 0 Gems and no gem progress", function()
			local p = ProgressionLogic.CreateInitialProfile()
			expect(p.Gems).toBe(0)
			expect(p.IndexMilestonesClaimed).toBe(0)
			expect(p.HighestZoneReached).toBe(0)
			expect(p.DailyStreak).toBe(0)
			expect(p.LastDailyClaimDay).toBe(-1)
		end)

		it("pays each Index milestone exactly once, including several at once", function()
			local p = ProgressionLogic.CreateInitialProfile()
			expect(ProgressionLogic.AwardIndexMilestones(p)).toBe(0) -- 1 discovered, first milestone is 3

			-- Discover 6 slimes in one go: milestones 1 and 2 both pay
			local count = 0
			for _, s in GameConfig.Slimes do
				if count >= 6 then
					break
				end
				p.DiscoveredSlimes[s.Id] = true
				count += 1
			end
			local expected = gemsCfg.IndexMilestones[1].Gems + gemsCfg.IndexMilestones[2].Gems
			expect(ProgressionLogic.AwardIndexMilestones(p)).toBe(expected)
			expect(p.Gems).toBe(expected)
			expect(p.IndexMilestonesClaimed).toBe(2)
			expect(ProgressionLogic.AwardIndexMilestones(p)).toBe(0) -- no double pay
			expect(p.Gems).toBe(expected)
		end)

		it("pays every zone up to the one reached, once", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local r = gemsCfg.FirstZoneReach
			expect(ProgressionLogic.AwardZoneReach(p, 3)).toBe(r[1] + r[2] + r[3])
			expect(p.HighestZoneReached).toBe(3)
			expect(ProgressionLogic.AwardZoneReach(p, 3)).toBe(0)
			expect(ProgressionLogic.AwardZoneReach(p, 2)).toBe(0)
			expect(ProgressionLogic.AwardZoneReach(p, 4)).toBe(r[4])
			expect(p.Gems).toBe(r[1] + r[2] + r[3] + r[4])
		end)

		it("runs the daily streak: once per day, continues on consecutive days, resets after a gap", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local daily = gemsCfg.DailyRewards

			local ok1, g1, s1 = ProgressionLogic.ClaimDailyReward(p, 100)
			expect(ok1).toBe(true)
			expect(g1).toBe(daily[1])
			expect(s1).toBe(1)

			local okSame = ProgressionLogic.ClaimDailyReward(p, 100)
			expect(okSame).toBe(false)
			expect(p.Gems).toBe(daily[1])

			local _, g2, s2 = ProgressionLogic.ClaimDailyReward(p, 101)
			expect(s2).toBe(2)
			expect(g2).toBe(daily[2])

			local _, g3, s3 = ProgressionLogic.ClaimDailyReward(p, 103) -- skipped day 102
			expect(s3).toBe(1)
			expect(g3).toBe(daily[1])
		end)

		it("computes pure daily calendar status (CanClaim, NextStreakDay, WillReset)", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local s0 = ProgressionLogic.GetDailyStatus(p, 100)
			expect(s0.CanClaim).toBe(true)
			expect(s0.NextStreakDay).toBe(1)
			expect(s0.WillReset).toBe(false)

			ProgressionLogic.ClaimDailyReward(p, 100)
			local sSame = ProgressionLogic.GetDailyStatus(p, 100)
			expect(sSame.CanClaim).toBe(false)
			expect(sSame.NextStreakDay).toBe(1)

			local sNext = ProgressionLogic.GetDailyStatus(p, 101)
			expect(sNext.CanClaim).toBe(true)
			expect(sNext.NextStreakDay).toBe(2)
			expect(sNext.WillReset).toBe(false)

			local sGap = ProgressionLogic.GetDailyStatus(p, 105)
			expect(sGap.CanClaim).toBe(true)
			expect(sGap.NextStreakDay).toBe(1)
			expect(sGap.WillReset).toBe(true)
		end)

		it("grants Robux Gem Packs once per receipt PurchaseId and caps ProcessedReceipts", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local pack = GameConfig.Robux.GemPacks[1]
			local ok1, gems1 = ProgressionLogic.GrantRobuxGemPack(p, pack.Id, "receipt_abc")
			expect(ok1).toBe(true)
			expect(gems1).toBe(pack.Gems)
			expect(p.Gems).toBe(pack.Gems)

			-- Duplicate receipt must be rejected without granting Gems again
			local okDup, gemsDup = ProgressionLogic.GrantRobuxGemPack(p, pack.Id, "receipt_abc")
			expect(okDup).toBe(false)
			expect(gemsDup).toBe(0)
			expect(p.Gems).toBe(pack.Gems)

			-- Cap ProcessedReceipts at GameConfig.Robux.MaxProcessedReceipts
			for i = 1, GameConfig.Robux.MaxProcessedReceipts + 5 do
				ProgressionLogic.GrantRobuxGemPack(p, pack.Id, `r_{i}`)
			end
			expect(#p.ProcessedReceipts).toBe(GameConfig.Robux.MaxProcessedReceipts)
		end)

		it("applies owned Robux Game Passes to Luck, Cash, Gems, Power, Slots, and Auto-Throw", function()
			local p = ProgressionLogic.CreateInitialProfile()
			expect(ProgressionLogic.GetBoostLuckMultiplier(p)).toBe(1)
			expect(ProgressionLogic.GetPassCashMultiplier(p)).toBe(1)
			expect(ProgressionLogic.GetGemMultiplier(p)).toBe(1)
			expect(ProgressionLogic.GetTrainingPowerMultiplier(p)).toBe(1)

			p.OwnedPasses.pass_x2_luck = true
			p.OwnedPasses.pass_x2_cash = true
			p.OwnedPasses.pass_vip = true
			p.OwnedPasses.pass_gems_4x = true
			p.OwnedPasses.pass_power_6x = true
			p.OwnedPasses.pass_extra_slots = true
			p.OwnedPasses.pass_auto_throw = true

			expect(ProgressionLogic.GetBoostLuckMultiplier(p)).toBeNear(2.0)
			expect(ProgressionLogic.GetPassCashMultiplier(p)).toBeNear(2.5)
			expect(ProgressionLogic.GetCashMultiplier(p)).toBeNear(2.5)
			expect(ProgressionLogic.GetGemMultiplier(p)).toBeNear(5.0) -- 4x Gems * 1.25 VIP
			expect(ProgressionLogic.GetTrainingPowerMultiplier(p)).toBeNear(6.0)
			expect(ProgressionLogic.GetEffectiveMaxSlimes(p)).toBe(12)
			expect(ProgressionLogic.OwnsAutoThrow(p)).toBe(true)
		end)

		it("keeps paying the last daily value after the streak passes the table length", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local daily = gemsCfg.DailyRewards
			local last = 0
			for day = 1, #daily + 3 do
				local _, g = ProgressionLogic.ClaimDailyReward(p, 500 + day)
				last = g
			end
			expect(p.DailyStreak).toBe(#daily + 3)
			expect(last).toBe(daily[#daily])
		end)

		it("pays Gems for rare catches by rarity and mutation only", function()
			local common = GameConfig.SlimesById.meadow_sprout
			local mythic = GameConfig.SlimesById.candy_royal
			expect(ProgressionLogic.GetCatchGems(common, "NORMAL")).toBe(0)
			expect(ProgressionLogic.GetCatchGems(common, "RAINBOW")).toBe(gemsCfg.MutationDrops.RAINBOW)
			expect(ProgressionLogic.GetCatchGems(mythic, "NORMAL")).toBe(gemsCfg.RarityDrops.Mythic)
			expect(ProgressionLogic.GetCatchGems(mythic, "CRYSTAL")).toBe(gemsCfg.RarityDrops.Mythic + gemsCfg.MutationDrops.CRYSTAL)
		end)

		it("adds first-zone Gems to a throw reward and reports them", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local reward = ProgressionLogic.EvaluateThrowReward(p, 40, 1, 0, 1.0, 0, true) -- common, NORMAL
			expect(reward.Gems.FromCatch).toBe(0)
			expect(reward.Gems.FromZone).toBe(gemsCfg.FirstZoneReach[1])
			expect(reward.Gems.Total).toBe(reward.Gems.FromCatch + reward.Gems.FromZone + reward.Gems.FromIndex)
			expect(p.Gems).toBe(reward.Gems.Total)

			local again = ProgressionLogic.EvaluateThrowReward(p, 40, 1, 0, 1.0, 0, true)
			expect(again.Gems.FromZone).toBe(0)
		end)

		it("pays an Index milestone when an egg hatch completes it", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.DiscoveredSlimes.crystal_quartz = true -- 2 discovered
			p.Cash = 1000
			local ok, msg = ProgressionLogic.HatchShopEgg(p, "enchanted_egg", 1, function()
				return 0 -- first egg item: meadow_honey (new discovery -> 3)
			end)
			expect(ok).toBe(true)
			expect(p.Gems).toBe(gemsCfg.IndexMilestones[1].Gems)
			expect(string.find(msg, "Gems", 1, true) ~= nil).toBe(true)
		end)
	end)

	describe("Gems - Spending through the shop", function()
		it("buys Auto-Throw with Gems only, never Cash", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.Cash = 1e9
			local cost = GameConfig.ShopBoosts.auto_throw.Cost

			local okPoor, msgPoor = ProgressionLogic.Purchase(p, "gem_auto_throw", 1)
			expect(okPoor).toBe(false)
			expect(string.find(msgPoor, "Gems", 1, true) ~= nil).toBe(true)
			expect(p.Cash).toBe(1e9)
			expect(p.OwnedBoosts.auto_throw == true).toBe(false)

			p.Gems = cost + 5
			local ok = ProgressionLogic.Purchase(p, "gem_auto_throw", 1)
			expect(ok).toBe(true)
			expect(p.Gems).toBe(5)
			expect(p.Cash).toBe(1e9)
			expect(p.OwnedBoosts.auto_throw).toBe(true)

			local okAgain = ProgressionLogic.Purchase(p, "gem_auto_throw", 1)
			expect(okAgain).toBe(false)
			expect(p.Gems).toBe(5)
		end)

		it("upgrades tiered 2x-10x Gems, Training Power, Luck, and 2x Money cleanly with highest-tier-wins", function()
			local p = ProgressionLogic.CreateInitialProfile()
			expect(ProgressionLogic.GetGemMultiplier(p)).toBe(1)
			expect(ProgressionLogic.GetTrainingPowerMultiplier(p)).toBe(1)
			expect(ProgressionLogic.GetBoostLuckMultiplier(p)).toBe(1)
			expect(ProgressionLogic.GetCashMultiplier(p)).toBe(1)

			-- Step through the full 2x -> 4x -> 6x -> 8x -> 10x Luck ladder via Gems
			local luckTrack = GameConfig.MultiplierTracksById.luck
			for _, tier in luckTrack.Tiers do
				local entry = ProgressionLogic.GetShopListingEntry(p, "gem_luck_tier")
				expect(entry ~= nil and entry.Price).toBe(tier.GemCost)
				p.Gems = tier.GemCost
				expect((ProgressionLogic.Purchase(p, "gem_luck_tier", 1))).toBe(true)
				expect(p.Gems).toBe(0)
				expect(ProgressionLogic.GetBoostLuckMultiplier(p)).toBe(tier.Multiplier)
			end
			expect(ProgressionLogic.GetShopListingEntry(p, "gem_luck_tier").State).toBe("Maxed")
			p.Gems = 99999
			expect((ProgressionLogic.Purchase(p, "gem_luck_tier", 1))).toBe(false)

			-- Owning the 4x Gems Robux Pass jumps the Gem ladder straight to 6x next (no double-charging)
			local p2 = ProgressionLogic.CreateInitialProfile()
			p2.OwnedPasses.pass_gems_4x = true
			expect(ProgressionLogic.GetGemMultiplier(p2)).toBe(4)
			local nextEntry = ProgressionLogic.GetShopListingEntry(p2, "gem_gems_tier")
			expect(nextEntry ~= nil and nextEntry.Title).toBe("6x Gems")
			-- Verify 4x Gems multiplies in-game earned Gems (zone + daily) but NOT Robux Gem Packs
			local z1Paid = ProgressionLogic.AwardZoneReach(p2, 1)
			expect(z1Paid).toBe(GameConfig.Gems.FirstZoneReach[1] * 4)
			local _, dailyPaid = ProgressionLogic.ClaimDailyReward(p2, 100)
			expect(dailyPaid).toBe(GameConfig.Gems.DailyRewards[1] * 4)
			local pack = GameConfig.Robux.GemPacks[1]
			local _, packPaid = ProgressionLogic.GrantRobuxGemPack(p2, pack.Id, "rcpt_no_mult")
			expect(packPaid).toBe(pack.Gems) -- Robux packs never get multiplied

			-- Training Power 6x multiplies pull-up XP by 6x
			local p3 = ProgressionLogic.CreateInitialProfile()
			p3.OwnedBoosts.power_6x = true
			expect(ProgressionLogic.ApplyPullUpRep(p3).XPGained).toBe(GameConfig.PullUpTiers[1].XPPerRep * 6)

			-- 2x Money doubles passive income
			local p4 = ProgressionLogic.CreateInitialProfile()
			local baseIncome = ProgressionLogic.GetIncomePerSecond(p4)
			p4.Gems = GameConfig.MultiplierTracksById.money.Tiers[1].GemCost
			expect((ProgressionLogic.Purchase(p4, "gem_money_2x", 1))).toBe(true)
			expect(ProgressionLogic.GetIncomePerSecond(p4)).toBe(baseIncome * 2)
			expect(ProgressionLogic.GetShopListingEntry(p4, "gem_money_2x").State).toBe("Maxed")
		end)

		it("unlocks locked Plot Slots 9..12 one-by-one with Gems and maxes via +4 Plot Slots Pass", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.Cash = 1e9
			local cost9 = GameConfig.Slots.SlotUnlockGemCosts[9]
			p.Gems = cost9
			expect((ProgressionLogic.Purchase(p, "gem_slot_unlock", 1))).toBe(true)
			expect(p.MaxSlimes).toBe(9)
			expect(p.Gems).toBe(0)
			expect(p.Cash).toBe(1e9)
			expect(ProgressionLogic.GetShopListingEntry(p, "gem_slot_unlock").Title).toBe("Unlock Plot Slot #10")

			-- Owning the "+4 Plot Slots" Robux Pass immediately maxes Slots to 12/12
			p.OwnedPasses.pass_extra_slots = true
			expect(ProgressionLogic.GetEffectiveMaxSlimes(p)).toBe(12)
			expect(ProgressionLogic.GetShopListingEntry(p, "gem_slot_unlock").State).toBe("Maxed")
			p.Gems = 99999
			expect((ProgressionLogic.Purchase(p, "gem_slot_unlock", 1))).toBe(false)
		end)

		it("enforces the 8+ hour F2P Gem grind floor (all one-time milestones + Day 1 stay below cheapest Gem unlock)", function()
			local oneTimeTotal = 0
			for _, g in GameConfig.Gems.FirstZoneReach do
				oneTimeTotal += g
			end
			for _, m in GameConfig.Gems.IndexMilestones do
				oneTimeTotal += m.Gems
			end
			for _, q in GameConfig.Quests.Line do
				oneTimeTotal += (q.Reward.Gems or 0)
			end
			oneTimeTotal += GameConfig.Gems.DailyRewards[1]

			local cheapestGemUnlock = GameConfig.Slots.SlotUnlockGemCosts[9]
			expect(oneTimeTotal < cheapestGemUnlock).toBe(true)
			expect(cheapestGemUnlock).toBeGreaterThanOrEqual(1500)
		end)

		it("lists gem items in the Gems wallet: price text and affordability", function()
			local state = { Cash = 1e9, Gems = 0, OwnedBoosts = {} }
			local entry = ProgressionLogic.GetShopListingEntry(state, "gem_auto_throw")
			expect(entry ~= nil).toBe(true)
			if entry then
				expect(entry.PriceKind).toBe("Gems")
				expect(string.sub(entry.PriceText, 1, #"💎")).toBe("💎")
				expect(entry.State).toBe("Unaffordable") -- lots of Cash doesn't help
				expect(entry.Options[1].CanAfford).toBe(false)
			end
			local cashEntry = ProgressionLogic.GetShopListingEntry(state, "pullup_tier")
			if cashEntry then
				expect(cashEntry.PriceKind).toBe("Cash")
				expect(cashEntry.State).toBe("Available")
			end
		end)

		it("keeps every Boost catalog row's PriceKind in step with its boost's PriceKind", function()
			for _, item in GameConfig.ShopCatalog do
				if item.Action == "Boost" then
					local boost = GameConfig.ShopBoosts[item.Args.BoostId or ""]
					expect(boost ~= nil).toBe(true)
					if boost then
						expect(item.PriceKind).toBe(boost.PriceKind)
					end
				end
			end
		end)
	end)
end
