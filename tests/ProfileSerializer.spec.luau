--!strict
--[[
	tests/ProfileSerializer.spec.luau
	Saving: profile -> DataStore table -> profile, through a real JSON round trip (DataStores store JSON),
	plus defaults for old saves and clean-up of bad data.
]]

local serde = require("@lune/serde")

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local ProgressionLogic = require("../src/ReplicatedStorage/Shared/ProgressionLogic")
local ProfileSerializer = require("../src/ReplicatedStorage/Shared/ProfileSerializer")

return function(t: any)
	local describe = t.describe
	local it = t.it
	local expect = t.expect

	local function jsonRoundTrip(data: any): any
		return serde.decode("json", serde.encode("json", data))
	end

	local function busyProfile(): ProgressionLogic.PlayerProfile
		local p = ProgressionLogic.CreateInitialProfile()
		p.Cash = 12345.5
		p.Gems = 77
		p.BaseThrowPower = 40
		p.PowerUpgradeLevel = 6
		p.PullUpTier = 3
		p.BaitTier = 2
		p.StrengthLevel = 8
		p.TrainingXP = 31
		p.MaxSlimes = GameConfig.Slots.ExpandedMaxSlimes
		p.BestDistance = 512.25
		p.OwnedBoosts.money_2x = true
		p.OwnedBoosts.gems_4x = true
		p.OwnedBoosts.auto_throw = true
		p.ClaimedFreeGift = true
		p.TotalThrows = 9
		p.TotalPullUps = 120
		p.IndexMilestonesClaimed = 1
		p.HighestZoneReached = 2
		p.DailyStreak = 4
		p.LastDailyClaimDay = 20000
		-- A throw catch into the hotbar, then place it on a non-contiguous slot (sparse keys)
		ProgressionLogic.EvaluateThrowReward(p, 300, 2, 0.99, 1.0, 0, true)
		local caught = p.UnplacedSlimes[1]
		ProgressionLogic.PlaceSlimeAtSlot(p, caught.Uid, 7)
		ProgressionLogic.EvaluateThrowReward(p, 60, 1, 0, 1.0, 0, true) -- one left in the hotbar
		p.QuestLineStep = 3
		p.QuestLineProgress = 6
		p.DailyQuestDay = 20000
		p.DailyQuests = {
			{ Id = "daily_throws_5", Progress = 4, Claimed = false },
			{ Id = "daily_reps_25", Progress = 25, Claimed = true },
		}
		p.ProcessedReceipts = { "rcpt_101", "rcpt_102" }
		return p
	end

	describe("ProfileSerializer - Round trip", function()
		it("restores every saved field after a JSON round trip", function()
			local p = busyProfile()
			local loaded = ProfileSerializer.Deserialize(jsonRoundTrip(ProfileSerializer.Serialize(p)))

			for _, field in {
				"Cash",
				"Gems",
				"BaseThrowPower",
				"PowerUpgradeLevel",
				"PullUpTier",
				"BaitTier",
				"StrengthLevel",
				"TrainingXP",
				"MaxSlimes",
				"BestDistance",
				"ClaimedFreeGift",
				"TotalThrows",
				"TotalPullUps",
				"IndexMilestonesClaimed",
				"HighestZoneReached",
				"DailyStreak",
				"LastDailyClaimDay",
				"QuestLineStep",
				"QuestLineProgress",
				"DailyQuestDay",
				"NextUid",
				"EquippedSlimeId",
			} do
				expect((loaded :: any)[field]).toBe((p :: any)[field])
			end
			expect(#loaded.DailyQuests).toBe(2)
			expect(loaded.DailyQuests[1].Id).toBe("daily_throws_5")
			expect(loaded.DailyQuests[1].Progress).toBe(4)
			expect(loaded.DailyQuests[1].Claimed).toBe(false)
			expect(loaded.DailyQuests[2].Claimed).toBe(true)
			expect(#loaded.ProcessedReceipts).toBe(2)
			expect(loaded.ProcessedReceipts[1]).toBe("rcpt_101")
			expect(loaded.OwnedPasses.pass_vip == nil).toBe(true) -- passes are checked live from Roblox, not saved
			expect(loaded.OwnedBoosts.money_2x).toBe(true)
			expect(loaded.OwnedBoosts.gems_4x).toBe(true)
			expect(loaded.OwnedBoosts.auto_throw).toBe(true)
			for id in p.DiscoveredSlimes do
				expect(loaded.DiscoveredSlimes[id]).toBe(true)
			end
		end)

		it("keeps slimes on their exact slots (sparse) and in the hotbar", function()
			local p = busyProfile()
			local loaded = ProfileSerializer.Deserialize(jsonRoundTrip(ProfileSerializer.Serialize(p)))
			for slot, inst in p.PlacedSlimesBySlot do
				local got = loaded.PlacedSlimesBySlot[slot]
				expect(got ~= nil).toBe(true)
				if got then
					expect(got.Uid).toBe(inst.Uid)
					expect(got.SlimeId).toBe(inst.SlimeId)
					expect(got.Mutation).toBe(inst.Mutation)
					expect(got.IncomePerSec).toBe(inst.IncomePerSec)
				end
			end
			expect(loaded.PlacedSlimesBySlot[7] ~= nil).toBe(true)
			expect(#loaded.UnplacedSlimes).toBe(#p.UnplacedSlimes)
			expect(#loaded.OwnedSlimes).toBe(#p.OwnedSlimes)
			expect(ProgressionLogic.GetIncomePerSecond(loaded)).toBe(ProgressionLogic.GetIncomePerSecond(p))
		end)

		it("stores slot keys as strings so the DataStore keeps sparse slots", function()
			local data = ProfileSerializer.Serialize(busyProfile())
			expect(data.SchemaVersion).toBe(GameConfig.Save.SchemaVersion)
			for key in data.PlacedSlimesBySlot do
				expect(type(key)).toBe("string")
			end
		end)
	end)

	describe("ProfileSerializer - Old and bad saves", function()
		it("gives a fresh profile for no save or a non-table", function()
			for _, data in { false, 42, "oops", true, "nil" } do
				local p = ProfileSerializer.Deserialize(if data == "nil" then nil else data)
				expect(p.Cash).toBe(0)
				expect(p.Gems).toBe(0)
				expect(#p.OwnedSlimes).toBe(1)
			end
		end)

		it("fills fields an older save didn't have with their defaults", function()
			local p = ProfileSerializer.Deserialize({ Cash = 250, PowerUpgradeLevel = 3 })
			expect(p.Cash).toBe(250)
			expect(p.PowerUpgradeLevel).toBe(3)
			expect(p.Gems).toBe(0)
			expect(p.StrengthLevel).toBe(1)
			expect(p.BaitTier).toBe(1)
			expect(p.LastDailyClaimDay).toBe(-1)
			expect(#p.PlacedSlimes).toBe(1) -- starter slime kept when the save has no slime data
		end)

		it("clamps out-of-range and non-finite numbers", function()
			local nan = 0 / 0
			local p = ProfileSerializer.Deserialize({
				Cash = -50,
				Gems = nan,
				BaitTier = 99,
				PullUpTier = 0,
				MaxSlimes = 500,
				StrengthLevel = math.huge,
				IndexMilestonesClaimed = 999,
			})
			expect(p.Cash).toBe(0)
			expect(p.Gems).toBe(0)
			expect(p.BaitTier).toBe(#GameConfig.BaitTiers)
			expect(p.PullUpTier).toBe(1)
			expect(p.MaxSlimes).toBe(GameConfig.Slots.ExpandedMaxSlimes)
			expect(p.StrengthLevel).toBe(1)
			expect(p.IndexMilestonesClaimed).toBe(#GameConfig.Gems.IndexMilestones)
		end)

		it("drops unknown slimes and boosts, and re-equips an owned slime", function()
			local p = ProfileSerializer.Deserialize({
				PlacedSlimesBySlot = {
					["1"] = { Uid = "s_1", SlimeId = "meadow_sprout", Mutation = "NORMAL" },
					["2"] = { Uid = "s_2", SlimeId = "deleted_slime", Mutation = "NORMAL" },
				},
				UnplacedSlimes = {},
				OwnedBoosts = { double_cash = true, removed_boost = true },
				DiscoveredSlimes = { meadow_sprout = true, deleted_slime = true },
				EquippedSlimeId = "deleted_slime",
			})
			expect(p.PlacedSlimesBySlot[2] == nil).toBe(true)
			expect(#p.OwnedSlimes).toBe(1)
			expect(p.OwnedBoosts.money_2x).toBe(true) -- legacy double_cash migrates cleanly to money_2x
			expect((p.OwnedBoosts :: any).removed_boost == nil).toBe(true)
			expect((p.DiscoveredSlimes :: any).deleted_slime == nil).toBe(true)
			expect(p.EquippedSlimeId).toBe("meadow_sprout")
		end)

		it("moves slimes on locked or duplicate slots to the hotbar and drops duplicate uids", function()
			local p = ProfileSerializer.Deserialize({
				MaxSlimes = GameConfig.Slots.InitialMaxSlimes,
				PlacedSlimesBySlot = {
					["1"] = { Uid = "s_1", SlimeId = "meadow_sprout", Mutation = "NORMAL" },
					["11"] = { Uid = "s_2", SlimeId = "meadow_honey", Mutation = "GOLDEN" }, -- locked slot
				},
				UnplacedSlimes = {
					{ Uid = "s_1", SlimeId = "meadow_sprout", Mutation = "NORMAL" }, -- duplicate uid
				},
			})
			expect(p.PlacedSlimesBySlot[11] == nil).toBe(true)
			expect(#p.UnplacedSlimes).toBe(1)
			expect(p.UnplacedSlimes[1].Uid).toBe("s_2")
			expect(p.UnplacedSlimes[1].Mutation).toBe("GOLDEN")
		end)

		it("keeps NextUid ahead of every saved slime uid", function()
			local p = ProfileSerializer.Deserialize({
				NextUid = 2,
				UnplacedSlimes = { { Uid = "s_40", SlimeId = "meadow_sprout", Mutation = "NORMAL" } },
				PlacedSlimesBySlot = {},
			})
			expect(p.NextUid).toBe(41)
		end)
	end)
end
