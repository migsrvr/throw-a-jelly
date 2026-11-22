--!strict
--[[
	tests/Quests.spec.luau
	Unit tests for QuestLogic:
	- Linear 12-step Quest Line progression, snapshot auto-fill, and claiming
	- Deterministic 3-per-day Daily Quest selection from (UserId, dayNumber)
	- Event recording from ProgressionLogic reducers (Throw, PlaceSlime, PullUpRep, BonusRep, BuyBait, HatchEgg, Discover, EarnCash, CatchRarity, ReachZone)
	- Midnight daily quest rollover & HasAnyClaimableQuest badge flag
]]

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local ProgressionLogic = require("../src/ReplicatedStorage/Shared/ProgressionLogic")
local QuestLogic = require("../src/ReplicatedStorage/Shared/QuestLogic")

return function(t: any)
	local describe = t.describe
	local it = t.it
	local expect = t.expect

	describe("Quests - Quest Line", function()
		it("starts every profile at step 1 with 0 progress", function()
			local p = ProgressionLogic.CreateInitialProfile()
			expect(p.QuestLineStep).toBe(1)
			expect(p.QuestLineProgress).toBe(0)
			expect(QuestLogic.CanClaimLineQuest(p)).toBe(false)
		end)

		it("advances step 1 (Throw bait 1 time) on a throw and pays Gems on claim", function()
			local p = ProgressionLogic.CreateInitialProfile()
			local step1 = GameConfig.Quests.Line[1]
			ProgressionLogic.EvaluateThrowReward(p, 40, 1, 0, 1.0, 0, true)
			expect(p.QuestLineProgress).toBe(step1.Target)
			expect(QuestLogic.CanClaimLineQuest(p)).toBe(true)

			local gemsBefore = p.Gems
			local ok, _, reward = QuestLogic.ClaimLineQuest(p)
			expect(ok).toBe(true)
			expect(reward ~= nil).toBe(true)
			expect(p.Gems).toBe(gemsBefore + (step1.Reward.Gems or 0))
			expect(p.QuestLineStep).toBe(2)
			expect(p.QuestLineProgress).toBe(0)
		end)

		it("auto-fills snapshot quests when advancing to a step the player already satisfied", function()
			local p = ProgressionLogic.CreateInitialProfile()
			-- Pre-upgrade bait to Tier 2 (Berry Jelly) and reach Crystal Cave (Zone 2) before reaching steps 4 and 5
			p.Cash = 10000
			ProgressionLogic.PurchaseBaitTier(p) -- BaitTier = 2
			ProgressionLogic.EvaluateThrowReward(p, 260, 2, 0, 1.0, 0, true) -- HighestZoneReached = 2, also completes step 1

			-- Claim Step 1 (Throw 1 time) -> Step 2 (Place a slime)
			expect(QuestLogic.ClaimLineQuest(p)).toBe(true)
			expect(p.QuestLineStep).toBe(2)
			local caught = p.UnplacedSlimes[1]
			ProgressionLogic.PlaceSlimeAtSlot(p, caught.Uid, 2)
			expect(QuestLogic.ClaimLineQuest(p)).toBe(true)

			-- Step 3: Complete 10 pull-up reps
			expect(p.QuestLineStep).toBe(3)
			for _ = 1, 10 do
				ProgressionLogic.ApplyPullUpRep(p)
			end
			expect(QuestLogic.ClaimLineQuest(p)).toBe(true)

			-- Step 4: Tap a Bonus Rep Pop-Up
			expect(p.QuestLineStep).toBe(4)
			ProgressionLogic.ApplyPullUpRep(p, GameConfig.Training.BonusRepMultiplier)
			expect(QuestLogic.ClaimLineQuest(p)).toBe(true)

			-- Step 5 is BuyBait (Target 2) — should immediately be ready because BaitTier is already 2!
			expect(p.QuestLineStep).toBe(5)
			expect(QuestLogic.CanClaimLineQuest(p)).toBe(true)
			expect(QuestLogic.ClaimLineQuest(p)).toBe(true)

			-- Step 6 is ReachZone (Target 2) — should immediately be ready because HighestZoneReached is already 2!
			expect(p.QuestLineStep).toBe(6)
			expect(QuestLogic.CanClaimLineQuest(p)).toBe(true)
		end)
	end)

	describe("Quests - Daily Quests", function()
		it("deterministically picks 3 distinct daily quests per (userId, dayNumber)", function()
			local pickA1 = QuestLogic.PickDailyQuests(123456, 20500)
			local pickA2 = QuestLogic.PickDailyQuests(123456, 20500)
			local pickNextDay = QuestLogic.PickDailyQuests(123456, 20501)

			expect(#pickA1).toBe(GameConfig.Quests.DailyCount)
			local seen: { [string]: boolean } = {}
			for i, q in pickA1 do
				expect(q.Id).toBe(pickA2[i].Id)
				expect(seen[q.Id] == nil).toBe(true)
				seen[q.Id] = true
			end

			local sameAll = true
			for i = 1, #pickA1 do
				if pickA1[i].Id ~= pickNextDay[i].Id then
					sameAll = false
					break
				end
			end
			expect(sameAll).toBe(false)
		end)

		it("tracks daily quest progress, pays reward once on claim, and resets on a new UTC day", function()
			local p = ProgressionLogic.CreateInitialProfile()
			QuestLogic.EnsureDailyQuests(p, 999, 100)
			expect(p.DailyQuestDay).toBe(100)
			expect(#p.DailyQuests).toBe(3)

			-- Force slot 1 to a known daily quest ("daily_throws_5")
			p.DailyQuests[1] = { Id = "daily_throws_5", Progress = 0, Claimed = false }
			for _ = 1, 5 do
				QuestLogic.RecordEvent(p, "Throw", 1)
			end
			expect(p.DailyQuests[1].Progress).toBe(5)
			expect(QuestLogic.CanClaimDailyQuest(p, 1)).toBe(true)
			expect(QuestLogic.HasAnyClaimableQuest(p)).toBe(true)

			local gemsBefore = p.Gems
			local ok = QuestLogic.ClaimDailyQuest(p, 1)
			expect(ok).toBe(true)
			expect(p.DailyQuests[1].Claimed).toBe(true)
			expect(p.Gems).toBe(gemsBefore + (GameConfig.QuestsById.daily_throws_5.Reward.Gems or 0))
			expect(QuestLogic.ClaimDailyQuest(p, 1)).toBe(false) -- cannot double claim

			-- Next UTC day rolls a fresh set of 3 unclaimed daily quests
			QuestLogic.EnsureDailyQuests(p, 999, 101)
			expect(p.DailyQuestDay).toBe(101)
			for _, slot in p.DailyQuests do
				expect(slot.Progress).toBe(0)
				expect(slot.Claimed).toBe(false)
			end
		end)

		it("scales Quest Line and Daily Quest Gem rewards by GetGemMultiplier", function()
			local p = ProgressionLogic.CreateInitialProfile()
			p.OwnedBoosts.gems_4x = true
			local mult = ProgressionLogic.GetGemMultiplier(p)
			expect(mult).toBe(4)

			local step1 = GameConfig.Quests.Line[1]
			p.QuestLineProgress = step1.Target
			local gemsBefore = p.Gems
			local ok, _, paid = QuestLogic.ClaimLineQuest(p, mult)
			expect(ok).toBe(true)
			expect(paid and paid.Gems).toBe((step1.Reward.Gems or 0) * 4)
			expect(p.Gems).toBe(gemsBefore + (step1.Reward.Gems or 0) * 4)

			p.DailyQuests = { { Id = "daily_throws_5", Progress = 5, Claimed = false } }
			local dailyBase = GameConfig.QuestsById.daily_throws_5.Reward.Gems or 0
			local beforeDaily = p.Gems
			local okDaily, _, paidDaily = QuestLogic.ClaimDailyQuest(p, 1, mult)
			expect(okDaily).toBe(true)
			expect(paidDaily and paidDaily.Gems).toBe(dailyBase * 4)
			expect(p.Gems).toBe(beforeDaily + dailyBase * 4)
		end)
	end)
end
