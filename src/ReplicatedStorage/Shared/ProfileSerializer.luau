--!strict
--[[
	ProfileSerializer.luau
	Pure conversion between a live PlayerProfile and the table stored in the DataStore.

	- Serialize: keeps only what can't be derived. Slimes are saved as { Uid, SlimeId, Mutation }, and
	  PlacedSlimesBySlot uses string keys ("1".."12") because DataStores (JSON) can't hold sparse integer keys.
	- Deserialize: starts from a fresh profile and copies over every saved field that is valid, so saves made
	  before a field existed get that field's default. Unknown slime/boost ids are dropped, numbers are
	  clamped, slime stats (income, rarity, name) are rebuilt from GameConfig so tuning applies to old saves.

	No Roblox services: runs in Lune tests (tests/ProfileSerializer.spec.luau).
]]

local GameConfig = if typeof(script) == "Instance"
	then require(script.Parent:WaitForChild("GameConfig"))
	else require("./GameConfig")
local ProgressionLogic = if typeof(script) == "Instance"
	then require(script.Parent:WaitForChild("ProgressionLogic"))
	else require("./ProgressionLogic")

local ProfileSerializer = {}

export type SavedSlime = { Uid: string, SlimeId: string, Mutation: string }

local MAX_NUMBER = 1e300 -- keep everything finite so the DataStore can encode it

local function finite(v: any): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return v
end

local function readNumber(v: any, default: number, minV: number, maxV: number?): number
	local n = finite(v)
	if n == nil then
		return default
	end
	return math.clamp(n, minV, maxV or MAX_NUMBER)
end

local function readInt(v: any, default: number, minV: number, maxV: number?): number
	return math.floor(readNumber(v, default, minV, maxV))
end

local function saveSlime(inst: ProgressionLogic.SlimeInstance): SavedSlime
	return { Uid = inst.Uid, SlimeId = inst.SlimeId, Mutation = inst.Mutation }
end

-- Rebuilds a full SlimeInstance from saved data (stats always come from the current GameConfig).
local function loadSlime(v: any): ProgressionLogic.SlimeInstance?
	if type(v) ~= "table" or type(v.Uid) ~= "string" or type(v.SlimeId) ~= "string" then
		return nil
	end
	local def = GameConfig.SlimesById[v.SlimeId]
	if not def then
		return nil
	end
	local mutDef = GameConfig.MutationsById[v.Mutation] or GameConfig.Mutations[1]
	return {
		Uid = v.Uid,
		SlimeId = def.Id,
		Name = def.Name,
		ShortWord = def.ShortWord,
		Rarity = def.Rarity,
		RarityRank = def.RarityRank,
		Mutation = mutDef.Id,
		IncomePerSec = math.max(1, math.floor(def.IncomePerSec * mutDef.IncomeMultiplier + 0.5)),
		ThrowBonus = def.ThrowBonus,
	}
end

local function uidNumber(uid: string): number
	return tonumber(string.match(uid, "^s_(%d+)$")) or 0
end

function ProfileSerializer.Serialize(profile: ProgressionLogic.PlayerProfile): { [string]: any }
	local placed: { [string]: SavedSlime } = {}
	for slot, inst in profile.PlacedSlimesBySlot do
		placed[tostring(slot)] = saveSlime(inst)
	end
	local unplaced: { SavedSlime } = {}
	for _, inst in profile.UnplacedSlimes do
		table.insert(unplaced, saveSlime(inst))
	end

	local dailyQuests: { { Id: string, Progress: number, Claimed: boolean } } = {}
	for _, slot in (profile.DailyQuests or {}) do
		if type(slot) == "table" and type(slot.Id) == "string" then
			table.insert(dailyQuests, {
				Id = slot.Id,
				Progress = slot.Progress or 0,
				Claimed = slot.Claimed == true,
			})
		end
	end

	local receipts: { string } = {}
	for _, r in (profile.ProcessedReceipts or {}) do
		if type(r) == "string" and r ~= "" then
			table.insert(receipts, r)
		end
	end

	return {
		SchemaVersion = GameConfig.Save.SchemaVersion,
		Cash = profile.Cash,
		Gems = profile.Gems,
		BaseThrowPower = profile.BaseThrowPower,
		PowerUpgradeLevel = profile.PowerUpgradeLevel,
		PullUpTier = profile.PullUpTier,
		BaitTier = profile.BaitTier,
		StrengthLevel = profile.StrengthLevel,
		TrainingXP = profile.TrainingXP,
		MaxSlimes = profile.MaxSlimes,
		BestDistance = profile.BestDistance,
		EquippedSlimeId = profile.EquippedSlimeId,
		EquippedTrailZone = profile.EquippedTrailZone,
		PlacedSlimesBySlot = placed,
		UnplacedSlimes = unplaced,
		DiscoveredSlimes = table.clone(profile.DiscoveredSlimes),
		OwnedBoosts = table.clone(profile.OwnedBoosts),
		ClaimedFreeGift = profile.ClaimedFreeGift,
		NextUid = profile.NextUid,
		PendingIncome = profile.PendingIncome,
		TotalThrows = profile.TotalThrows,
		TotalPullUps = profile.TotalPullUps,
		IndexMilestonesClaimed = profile.IndexMilestonesClaimed,
		HighestZoneReached = profile.HighestZoneReached,
		LastSeen = profile.LastSeen,
		DailyStreak = profile.DailyStreak,
		LastDailyClaimDay = profile.LastDailyClaimDay,
		QuestLineStep = profile.QuestLineStep,
		QuestLineProgress = profile.QuestLineProgress,
		DailyQuestDay = profile.DailyQuestDay,
		DailyQuests = dailyQuests,
		ProcessedReceipts = receipts,
	}
end

-- Always returns a usable profile. `data` may be nil (new player) or any shape (old / corrupt save).
function ProfileSerializer.Deserialize(data: any): ProgressionLogic.PlayerProfile
	local p = ProgressionLogic.CreateInitialProfile()
	if type(data) ~= "table" then
		return p
	end

	p.Cash = readNumber(data.Cash, p.Cash, 0)
	p.Gems = readInt(data.Gems, p.Gems, 0)
	p.BaseThrowPower = readNumber(data.BaseThrowPower, p.BaseThrowPower, 1)
	p.PowerUpgradeLevel = readInt(data.PowerUpgradeLevel, p.PowerUpgradeLevel, 1)
	p.PullUpTier = readInt(data.PullUpTier, p.PullUpTier, 1, #GameConfig.PullUpTiers)
	p.BaitTier = readInt(data.BaitTier, p.BaitTier, 1, #GameConfig.BaitTiers)
	p.StrengthLevel = readInt(data.StrengthLevel, p.StrengthLevel, 1)
	p.TrainingXP = readNumber(data.TrainingXP, p.TrainingXP, 0)
	p.MaxSlimes = readInt(data.MaxSlimes, p.MaxSlimes, GameConfig.Slots.InitialMaxSlimes, GameConfig.Slots.ExpandedMaxSlimes)
	p.BestDistance = readNumber(data.BestDistance, p.BestDistance, 0)
	p.PendingIncome = readNumber(data.PendingIncome, 0, 0)
	p.TotalThrows = readInt(data.TotalThrows, 0, 0)
	p.TotalPullUps = readInt(data.TotalPullUps, 0, 0)
	p.IndexMilestonesClaimed = readInt(data.IndexMilestonesClaimed, 0, 0, #GameConfig.Gems.IndexMilestones)
	p.HighestZoneReached = readInt(data.HighestZoneReached, 0, 0, #GameConfig.Zones)
	p.LastSeen = readInt(data.LastSeen, 0, 0)
	p.DailyStreak = readInt(data.DailyStreak, 0, 0)
	p.LastDailyClaimDay = readInt(data.LastDailyClaimDay, -1, -1)
	p.ClaimedFreeGift = data.ClaimedFreeGift == true
	p.QuestLineStep = readInt(data.QuestLineStep, 1, 1, #GameConfig.Quests.Line + 1)
	local curLineDef = GameConfig.Quests.Line[p.QuestLineStep]
	p.QuestLineProgress = readNumber(data.QuestLineProgress, 0, 0, if curLineDef then curLineDef.Target else 0)
	p.DailyQuestDay = readInt(data.DailyQuestDay, -1, -1)

	if type(data.DailyQuests) == "table" then
		local dailyById: { [string]: GameConfig.QuestDef } = {}
		for _, q in GameConfig.Quests.DailyPool do
			dailyById[q.Id] = q
		end
		local loadedDaily = {}
		for _, raw in data.DailyQuests do
			if type(raw) == "table" and type(raw.Id) == "string" then
				local qDef = dailyById[raw.Id]
				if qDef then
					table.insert(loadedDaily, {
						Id = qDef.Id,
						Progress = readNumber(raw.Progress, 0, 0, qDef.Target),
						Claimed = raw.Claimed == true,
					})
				end
			end
			if #loadedDaily >= GameConfig.Quests.DailyCount then
				break
			end
		end
		p.DailyQuests = loadedDaily
	end

	if type(data.ProcessedReceipts) == "table" then
		local loadedReceipts = {}
		for _, r in data.ProcessedReceipts do
			if type(r) == "string" and r ~= "" and not table.find(loadedReceipts, r) then
				table.insert(loadedReceipts, r)
			end
		end
		while #loadedReceipts > GameConfig.Robux.MaxProcessedReceipts do
			table.remove(loadedReceipts, 1)
		end
		p.ProcessedReceipts = loadedReceipts
	end

	-- Index discoveries (known slimes only; the starter stays discovered)
	if type(data.DiscoveredSlimes) == "table" then
		for id, found in data.DiscoveredSlimes do
			if found == true and type(id) == "string" and GameConfig.SlimesById[id] then
				p.DiscoveredSlimes[id] = true
			end
		end
	end

	-- Boosts (known ids only)
	if type(data.OwnedBoosts) == "table" then
		for id, owned in data.OwnedBoosts do
			if owned == true and type(id) == "string" and GameConfig.ShopBoosts[id] then
				p.OwnedBoosts[id] = true
			end
		end
	end

	-- Slimes. Only replace the starter setup when the save actually holds slime data.
	local hasSlimeData = type(data.PlacedSlimesBySlot) == "table" or type(data.UnplacedSlimes) == "table"
	if hasSlimeData then
		p.PlacedSlimesBySlot = {}
		p.UnplacedSlimes = {}
		local seenUids: { [string]: boolean } = {}
		local maxUid = 0

		local function accept(inst: ProgressionLogic.SlimeInstance?): ProgressionLogic.SlimeInstance?
			if not inst or seenUids[inst.Uid] then
				return nil
			end
			seenUids[inst.Uid] = true
			maxUid = math.max(maxUid, uidNumber(inst.Uid))
			p.DiscoveredSlimes[inst.SlimeId] = true
			return inst
		end

		if type(data.PlacedSlimesBySlot) == "table" then
			for key, saved in data.PlacedSlimesBySlot do
				local slot = tonumber(key)
				local inst = accept(loadSlime(saved))
				if inst then
					if slot and slot == math.floor(slot) and slot >= 1 and slot <= p.MaxSlimes and not p.PlacedSlimesBySlot[slot] then
						p.PlacedSlimesBySlot[slot] = inst
					else
						table.insert(p.UnplacedSlimes, inst) -- bad / locked slot: keep the slime in the hotbar
					end
				end
			end
		end
		if type(data.UnplacedSlimes) == "table" then
			for _, saved in data.UnplacedSlimes do
				local inst = accept(loadSlime(saved))
				if inst then
					table.insert(p.UnplacedSlimes, inst)
				end
			end
		end
		-- NextUid must stay ahead of every saved uid so new slimes never reuse one
		p.NextUid = math.max(readInt(data.NextUid, 1, 1), maxUid + 1)
	end
	ProgressionLogic.SyncLegacyArrays(p)

	-- Equipped slime must be one the player still owns
	local equipped = data.EquippedSlimeId
	if type(equipped) == "string" and table.find(p.OwnedSlimes, equipped) then
		p.EquippedSlimeId = equipped
	else
		p.EquippedSlimeId = p.OwnedSlimes[1] or "meadow_sprout"
	end

	local trail = finite(data.EquippedTrailZone)
	if trail and GameConfig.Zones[math.floor(trail)] then
		p.EquippedTrailZone = math.floor(trail)
	end

	return p
end

return ProfileSerializer
