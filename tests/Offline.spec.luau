--!strict
--[[
	tests/Offline.spec.luau
	Welcome Back offline earnings and the unlock pop-up rules (pure ProgressionLogic functions).
]]

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local ProgressionLogic = require("../src/ReplicatedStorage/Shared/ProgressionLogic")
local ProfileSerializer = require("../src/ReplicatedStorage/Shared/ProfileSerializer")

return function(t: any)
	local describe = t.describe
	local it = t.it
	local expect = t.expect

	describe("Offline earnings", function()
		it("pays Rate x income x time", function()
			expect(ProgressionLogic.ComputeOfflineEarnings(10, 1000)).toBe(math.floor(10 * 1000 * GameConfig.Offline.Rate))
		end)
		it("pays nothing when away too briefly or with no income", function()
			expect(ProgressionLogic.ComputeOfflineEarnings(10, GameConfig.Offline.MinAwaySeconds - 1)).toBe(0)
			expect(ProgressionLogic.ComputeOfflineEarnings(0, 5000)).toBe(0)
		end)
		it("caps the time away", function()
			local capped = ProgressionLogic.ComputeOfflineEarnings(10, GameConfig.Offline.MaxAwaySeconds)
			expect(ProgressionLogic.ComputeOfflineEarnings(10, GameConfig.Offline.MaxAwaySeconds * 5)).toBe(capped)
		end)
		it("LastSeen survives a save round trip", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.LastSeen = 1700000000
			local back = ProfileSerializer.Deserialize(ProfileSerializer.Serialize(p))
			expect(back.LastSeen).toBe(1700000000)
		end)
	end)

	describe("Unlock pop-ups", function()
		local fresh = { BaitTierOffered = 1, ZoneSeen = 0 }
		it("offers the next bait once it is affordable, then not again", function()
			local nextCost = GameConfig.BaitTiers[2].Cost
			local none = ProgressionLogic.NextUnlockPopups(nextCost - 1, 1, 0, fresh)
			expect(#none).toBe(0)
			local popups, seen = ProgressionLogic.NextUnlockPopups(nextCost, 1, 0, fresh)
			expect(#popups).toBe(1)
			expect(popups[1].Kind).toBe("bait")
			local again = ProgressionLogic.NextUnlockPopups(nextCost * 2, 1, 0, seen)
			expect(#again).toBe(0)
		end)
		it("announces a newly reached zone once", function()
			local popups, seen = ProgressionLogic.NextUnlockPopups(0, 1, 2, fresh)
			expect(#popups).toBe(1)
			expect(popups[1].Kind).toBe("zone")
			expect(popups[1].Index).toBe(2)
			local again = ProgressionLogic.NextUnlockPopups(0, 1, 2, seen)
			expect(#again).toBe(0)
		end)
	end)
end
