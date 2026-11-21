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

		it("Lucky Charm multiplies throw luck", function()
			local p = ProgressionLogic.CreateInitialProfile()
			expect(ProgressionLogic.GetBoostLuckMultiplier(p)).toBe(1)
			p.Gems = GameConfig.ShopBoosts.lucky_charm.Cost
			expect(ProgressionLogic.Purchase(p, "gem_lucky_charm", 1)).toBe(true)
			expect(ProgressionLogic.GetBoostLuckMultiplier(p)).toBeNear(GameConfig.ShopBoosts.lucky_charm.LuckMultiplier or 0)
			expect(p.Gems).toBe(0)
		end)

		it("unlocks the +4 slots with Gems, which also maxes the Cash version", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.Cash = 1e9
			p.Gems = GameConfig.Slots.ExpansionGemCost
			expect(ProgressionLogic.Purchase(p, "gem_slot_expansion", 1)).toBe(true)
			expect(p.MaxSlimes).toBe(GameConfig.Slots.ExpandedMaxSlimes)
			expect(p.Gems).toBe(0)
			expect(p.Cash).toBe(1e9)
			expect(ProgressionLogic.Purchase(p, "slot_expansion", 1)).toBe(false)
			expect(ProgressionLogic.GetShopListingEntry(p, "slot_expansion").State).toBe("Maxed")
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
			local cashEntry = ProgressionLogic.GetShopListingEntry(state, "boost_double_cash")
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
