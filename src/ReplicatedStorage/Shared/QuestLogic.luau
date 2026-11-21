--!strict
--[[
	QuestLogic.luau
	Pure quest progression engine:
	- Linear Quest Line (12 tutorial/progression steps, never resets, CLAIM to advance)
	- Daily Quests (3 deterministic quests per UTC day seeded by (UserId, dayNumber))
	- Event recording hooks called from ProgressionLogic reducers & ThrowService
	No Roblox service dependencies: runs in Lune unit tests (tests/Quests.spec.luau).
]]

local GameConfig = if typeof(script) == "Instance"
	then require(script.Parent:WaitForChild("GameConfig"))
	else require("./GameConfig")

local QuestLogic = {}

export type DailyQuestSlot = {
	Id: string,
	Progress: number,
	Claimed: boolean,
}

export type QuestEventMeta = {
	RarityRank: number?,
	ZoneIndex: number?,
	BaitTier: number?,
	DiscoveredCount: number?,
}

local function countDiscoveredSlimes(profile: any): number
	local n = 0
	if type(profile.DiscoveredSlimes) == "table" then
		for _, found in profile.DiscoveredSlimes do
			if found then
				n += 1
			end
		end
	end
	return n
end

-- Deterministic 32-bit LCG step so daily quest picks are identical across runtimes and tests
local function nextSeed(state: number): number
	return (state * 1664525 + 1013904223) % 4294967296
end

function QuestLogic.PickDailyQuests(userId: number, dayNumber: number): { DailyQuestSlot }
	local pool = GameConfig.Quests.DailyPool
	local want = math.min(GameConfig.Quests.DailyCount, #pool)
	local available = {}
	for i, def in pool do
		available[i] = def.Id
	end

	local uidPart = math.abs(math.floor(userId)) % 2147483647
	local dayPart = math.abs(math.floor(dayNumber)) % 2147483647
	local seed = nextSeed(uidPart * 7919 + dayPart * 104729 + 17)
	seed = nextSeed(seed)

	local picked: { DailyQuestSlot } = {}
	for _ = 1, want do
		seed = nextSeed(seed)
		local idx = (seed % #available) + 1
		local questId = table.remove(available, idx) :: string
		table.insert(picked, {
			Id = questId,
			Progress = 0,
			Claimed = false,
		})
	end

	return picked
end

function QuestLogic.EnsureDailyQuests(profile: any, userId: number, dayNumber: number): boolean
	if profile.DailyQuestDay == dayNumber and type(profile.DailyQuests) == "table" and #profile.DailyQuests > 0 then
		return false
	end
	profile.DailyQuestDay = dayNumber
	profile.DailyQuests = QuestLogic.PickDailyQuests(userId, dayNumber)
	return true
end

-- For state-based milestones on the linear Quest Line (ReachZone, BuyBait, Discover),
-- pre-populate progress if the player has already passed that threshold.
function QuestLogic.SyncSnapshotProgress(profile: any)
	local stepIdx = profile.QuestLineStep or 1
	local def = GameConfig.Quests.Line[stepIdx]
	if not def then
		return
	end

	if def.Event == "ReachZone" then
		local highest = profile.HighestZoneReached or 0
		if highest >= (def.MinZone or def.Target) then
			profile.QuestLineProgress = def.Target
		end
	elseif def.Event == "BuyBait" then
		local baitTier = profile.BaitTier or 1
		if baitTier >= (def.MinBaitTier or def.Target) then
			profile.QuestLineProgress = def.Target
		end
	elseif def.Event == "Discover" then
		local disc = countDiscoveredSlimes(profile)
		profile.QuestLineProgress = math.min(def.Target, math.max(profile.QuestLineProgress or 0, disc))
	end
end

local function matchesDef(
	def: GameConfig.QuestDef,
	eventType: GameConfig.QuestEventType,
	amount: number,
	meta: QuestEventMeta?
): (boolean, number, boolean)
	if def.Event ~= eventType then
		return false, 0, false
	end
	if eventType == "CatchRarity" then
		local rank = if meta and meta.RarityRank then meta.RarityRank else 1
		if def.MinRarityRank and rank < def.MinRarityRank then
			return false, 0, false
		end
		return true, amount, false
	elseif eventType == "ReachZone" then
		local z = if meta and meta.ZoneIndex then meta.ZoneIndex else amount
		if def.MinZone and z < def.MinZone then
			return false, 0, false
		end
		return true, z, true -- absolute snapshot value
	elseif eventType == "BuyBait" then
		local tier = if meta and meta.BaitTier then meta.BaitTier else amount
		if def.MinBaitTier and tier < def.MinBaitTier then
			return false, 0, false
		end
		return true, tier, true
	elseif eventType == "Discover" then
		local count = if meta and meta.DiscoveredCount then meta.DiscoveredCount else amount
		return true, count, true
	end
	return true, amount, false
end

function QuestLogic.RecordEvent(
	profile: any,
	eventType: GameConfig.QuestEventType,
	amount: number?,
	meta: QuestEventMeta?
)
	local amt = math.max(0, amount or 1)

	-- 1. Linear Quest Line (only the currently active step advances)
	local stepIdx = profile.QuestLineStep or 1
	local lineDef = GameConfig.Quests.Line[stepIdx]
	if lineDef then
		local matched, delta, isAbsolute = matchesDef(lineDef, eventType, amt, meta)
		if matched then
			local cur = profile.QuestLineProgress or 0
			local nextVal = if isAbsolute then math.max(cur, delta) else cur + delta
			profile.QuestLineProgress = math.min(lineDef.Target, nextVal)
		end
	end

	-- 2. Daily Quests
	if type(profile.DailyQuests) == "table" then
		for _, slot in profile.DailyQuests do
			if not slot.Claimed then
				local def = GameConfig.QuestsById[slot.Id]
				if def then
					local matched, delta, isAbsolute = matchesDef(def, eventType, amt, meta)
					if matched then
						local cur = slot.Progress or 0
						local nextVal = if isAbsolute then math.max(cur, delta) else cur + delta
						slot.Progress = math.min(def.Target, nextVal)
					end
				end
			end
		end
	end
end

local function payQuestReward(profile: any, reward: GameConfig.QuestReward): string
	local parts = {}
	if reward.Cash and reward.Cash > 0 then
		profile.Cash = (profile.Cash or 0) + reward.Cash
		table.insert(parts, `+${GameConfig.FormatNumber(reward.Cash)} Cash`)
	end
	if reward.Gems and reward.Gems > 0 then
		profile.Gems = (profile.Gems or 0) + reward.Gems
		table.insert(parts, `+{GameConfig.FormatNumber(reward.Gems)} Gems`)
	end
	return table.concat(parts, " & ")
end

function QuestLogic.CanClaimLineQuest(profile: any): boolean
	local stepIdx = profile.QuestLineStep or 1
	local def = GameConfig.Quests.Line[stepIdx]
	if not def then
		return false
	end
	QuestLogic.SyncSnapshotProgress(profile)
	return (profile.QuestLineProgress or 0) >= def.Target
end

function QuestLogic.ClaimLineQuest(profile: any): (boolean, string, GameConfig.QuestReward?)
	local stepIdx = profile.QuestLineStep or 1
	local def = GameConfig.Quests.Line[stepIdx]
	if not def then
		return false, "All Quest Line steps are complete!", nil
	end
	QuestLogic.SyncSnapshotProgress(profile)
	if (profile.QuestLineProgress or 0) < def.Target then
		return false, "Quest is not complete yet!", nil
	end

	local rewardStr = payQuestReward(profile, def.Reward)
	profile.QuestLineStep = stepIdx + 1
	profile.QuestLineProgress = 0
	QuestLogic.SyncSnapshotProgress(profile)
	return true, `Quest Complete: {def.Title} ({rewardStr})!`, def.Reward
end

function QuestLogic.CanClaimDailyQuest(profile: any, index: number): boolean
	local list = profile.DailyQuests
	if type(list) ~= "table" then
		return false
	end
	local slot = list[index]
	if not slot or slot.Claimed then
		return false
	end
	local def = GameConfig.QuestsById[slot.Id]
	if not def then
		return false
	end
	return (slot.Progress or 0) >= def.Target
end

function QuestLogic.ClaimDailyQuest(profile: any, index: number): (boolean, string, GameConfig.QuestReward?)
	local list = profile.DailyQuests
	if type(list) ~= "table" then
		return false, "No daily quests available", nil
	end
	local slot = list[index]
	if not slot then
		return false, "Invalid daily quest", nil
	end
	if slot.Claimed then
		return false, "Already claimed today!", nil
	end
	local def = GameConfig.QuestsById[slot.Id]
	if not def then
		return false, "Unknown quest", nil
	end
	if (slot.Progress or 0) < def.Target then
		return false, "Daily quest is not complete yet!", nil
	end

	slot.Claimed = true
	local rewardStr = payQuestReward(profile, def.Reward)
	return true, `Daily Quest Complete: {def.Title} ({rewardStr})!`, def.Reward
end

function QuestLogic.HasAnyClaimableQuest(profile: any): boolean
	if QuestLogic.CanClaimLineQuest(profile) then
		return true
	end
	if type(profile.DailyQuests) == "table" then
		for i = 1, #profile.DailyQuests do
			if QuestLogic.CanClaimDailyQuest(profile, i) then
				return true
			end
		end
	end
	return false
end

return QuestLogic
