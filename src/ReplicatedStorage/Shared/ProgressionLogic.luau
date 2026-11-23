--!strict
--[[
	ProgressionLogic.luau
	Pure business-logic reducers for player profiles:
	- Pull-Up Bar rep training & tier upgrades
	- Throw Power upgrades & 2x Shop Boosts
	- Plot Slot expansion (+4 SLOTS for $5K: 8 -> 12)
	- Throw landing Cash, Slime rarity + Mutation rolls, and "1 in X" odds
	- Slime Index discovery tracking, Zone Completion %, and Zone Trail bonuses
	- Hotbar (UnplacedSlimes) <-> Plot Slot (PlacedSlimesBySlot) manual & auto placement
	- Shop Free Gift claim & Featured Egg hatching
	- Contextual Objective / Tutorial step resolver
]]

local GameConfig = if typeof(script) == "Instance"
	then require(script.Parent:WaitForChild("GameConfig"))
	else require("./GameConfig")
local QuestLogic = if typeof(script) == "Instance"
	then require(script.Parent:WaitForChild("QuestLogic"))
	else require("./QuestLogic")

local ProgressionLogic = {}

export type SlimeInstance = {
	Uid: string,
	SlimeId: string,
	Name: string,
	ShortWord: string,
	Rarity: string,
	RarityRank: number,
	Mutation: "NORMAL" | "EMERALD" | "GOLDEN" | "CRYSTAL" | "RAINBOW",
	IncomePerSec: number,
	ThrowBonus: number,
}

export type PlayerProfile = {
	Cash: number,
	BaseThrowPower: number,
	PowerUpgradeLevel: number,
	PullUpTier: number,
	MaxSlimes: number,
	BestDistance: number,
	EquippedSlimeId: string,
	OwnedSlimes: { string },
	PlacedSlimes: { string },
	UnplacedSlimes: { SlimeInstance },
	PlacedSlimesBySlot: { [number]: SlimeInstance },
	DiscoveredSlimes: { [string]: boolean },
	EquippedTrailZone: number?,
	ClaimedFreeGift: boolean,
	OwnedBoosts: { [string]: boolean },
	NextUid: number,
	PendingIncome: number,
	TotalThrows: number,
	TotalPullUps: number,
	StrengthLevel: number, -- pull-up level; each level up = +GameConfig.Training.PowerPerLevel Throw Power
	TrainingXP: number, -- XP toward the next StrengthLevel
	BaitTier: number, -- index into GameConfig.BaitTiers
	Gems: number, -- premium currency (see GameConfig.Gems)
	IndexMilestonesClaimed: number, -- how many GameConfig.Gems.IndexMilestones have been paid
	HighestZoneReached: number, -- highest zone a throw has landed in (0 = never thrown); pays FirstZoneReach
	DailyStreak: number, -- consecutive daily-reward days (0 = never claimed)
	LastDailyClaimDay: number, -- UTC day number (os.time() // SecondsPerDay) of the last daily claim; -1 = never
	QuestLineStep: number, -- current 1-based step in GameConfig.Quests.Line
	QuestLineProgress: number, -- progress toward current QuestLineStep
	DailyQuestDay: number, -- UTC day number for DailyQuests
	DailyQuests: { QuestLogic.DailyQuestSlot }, -- today's 3 daily quests
	ProcessedReceipts: { string }, -- capped recent Developer Product PurchaseIds (saved to DataStore)
	OwnedPasses: { [string]: boolean }, -- runtime-only Game Pass ownership map (not saved to DataStore)
	LastSeen: number, -- os.time() of the last save (0 = never); drives Welcome Back offline income
	GraphicsMode: string, -- "Auto" | "Low" | "High" (Settings window; DeviceProfile picks the detail tier)
	MusicOn: boolean, -- Settings window music switch (MusicController)
}

export type GemAward = {
	Total: number,
	FromCatch: number,
	FromZone: number,
	FromIndex: number,
}

export type PullUpRepResult = {
	XPGained: number,
	LevelsGained: number,
	PowerGained: number,
	NewLevel: number,
	CurrentXP: number,
	RequiredXP: number,
}

export type ThrowRewardOutcome = {
	CashEarned: number,
	CaughtSlimeId: string,
	CaughtSlimeDef: GameConfig.SlimeDef,
	CaughtInstance: SlimeInstance,
	Mutation: string,
	OddsOneInX: number,
	IsSuperLucky: boolean,
	IsNewDiscovery: boolean,
	AutoPlaced: boolean,
	IsNewBestDistance: boolean,
	Gems: GemAward, -- Gems paid by this throw (rare catch + first zone reach + Index milestones)
}

local function makeSlimeInstance(
	profile: PlayerProfile,
	slimeId: string,
	mutationId: ("NORMAL" | "EMERALD" | "GOLDEN" | "CRYSTAL" | "RAINBOW")?
): SlimeInstance
	local def = GameConfig.SlimesById[slimeId] or GameConfig.Slimes[1]
	local mutId: "NORMAL" | "EMERALD" | "GOLDEN" | "CRYSTAL" | "RAINBOW" = mutationId or "NORMAL"
	local mutDef = GameConfig.MutationsById[mutId] or GameConfig.Mutations[1]
	local uid = `s_{profile.NextUid}`
	profile.NextUid += 1

	local income = math.max(1, math.floor(def.IncomePerSec * mutDef.IncomeMultiplier + 0.5))
	return {
		Uid = uid,
		SlimeId = def.Id,
		Name = def.Name,
		ShortWord = def.ShortWord,
		Rarity = def.Rarity,
		RarityRank = def.RarityRank,
		Mutation = mutId,
		IncomePerSec = income,
		ThrowBonus = def.ThrowBonus,
	}
end

-- Rebuilds the derived PlacedSlimes / OwnedSlimes id lists from the slot map + hotbar.
-- Exposed as ProgressionLogic.SyncLegacyArrays so loading a saved profile can rebuild them too.
local function syncLegacyArrays(profile: PlayerProfile)
	local placedIds = {}
	local maxSlots = if profile.OwnedPasses and profile.OwnedPasses.pass_extra_slots == true
		then GameConfig.Slots.ExpandedMaxSlimes
		else math.clamp(math.floor(profile.MaxSlimes or GameConfig.Slots.InitialMaxSlimes), GameConfig.Slots.InitialMaxSlimes, GameConfig.Slots.ExpandedMaxSlimes)
	for slot = 1, maxSlots do
		local inst = profile.PlacedSlimesBySlot[slot]
		if inst then
			table.insert(placedIds, inst.SlimeId)
		end
	end
	profile.PlacedSlimes = placedIds

	local ownedIds = table.clone(placedIds)
	for _, inst in profile.UnplacedSlimes do
		table.insert(ownedIds, inst.SlimeId)
	end
	profile.OwnedSlimes = ownedIds
end

function ProgressionLogic.CreateInitialProfile(): PlayerProfile
	local profile: PlayerProfile = {
		Cash = 0,
		BaseThrowPower = 5,
		PowerUpgradeLevel = 1,
		PullUpTier = 1,
		MaxSlimes = GameConfig.Slots.InitialMaxSlimes,
		BestDistance = 0,
		EquippedSlimeId = "meadow_sprout",
		OwnedSlimes = { "meadow_sprout" },
		PlacedSlimes = { "meadow_sprout" },
		UnplacedSlimes = {},
		PlacedSlimesBySlot = {},
		DiscoveredSlimes = { meadow_sprout = true },
		EquippedTrailZone = nil,
		ClaimedFreeGift = false,
		OwnedBoosts = {},
		NextUid = 1,
		PendingIncome = 0,
		TotalThrows = 0,
		TotalPullUps = 0,
		StrengthLevel = 1,
		TrainingXP = 0,
		BaitTier = 1,
		Gems = 0,
		IndexMilestonesClaimed = 0,
		HighestZoneReached = 0,
		DailyStreak = 0,
		LastDailyClaimDay = -1,
		QuestLineStep = 1,
		QuestLineProgress = 0,
		DailyQuestDay = -1,
		DailyQuests = {},
		ProcessedReceipts = {},
		OwnedPasses = {},
		LastSeen = 0,
		GraphicsMode = "Auto",
		MusicOn = true,
	}
	local starter = makeSlimeInstance(profile, "meadow_sprout", "NORMAL")
	profile.PlacedSlimesBySlot[1] = starter
	syncLegacyArrays(profile)
	return profile
end

ProgressionLogic.SyncLegacyArrays = syncLegacyArrays

-- ============================================================================
-- WALLETS (Cash / Gems)
-- ============================================================================

function ProgressionLogic.GetBalance(profile: { Cash: number?, Gems: number? }, kind: GameConfig.PriceKind): number
	return if kind == "Gems" then (profile.Gems or 0) else (profile.Cash or 0)
end

local function spend(profile: PlayerProfile, kind: GameConfig.PriceKind, amount: number)
	if kind == "Gems" then
		profile.Gems -= amount
	else
		profile.Cash -= amount
	end
end

local function needText(kind: GameConfig.PriceKind, amount: number): string
	return if kind == "Gems"
		then `Need {GameConfig.FormatNumber(amount)} Gems`
		else `Need ${GameConfig.FormatNumber(amount)} Cash`
end

-- ============================================================================
-- MULTIPLIERS & EFFECTIVE CAP (Gems / Training Power / Luck / Money / Slots / Auto)
-- Highest owned tier across Gem Upgrades (OwnedBoosts) OR Robux Game Passes (OwnedPasses) wins,
-- capped at 10x max per track so players never pay twice. VIP (+25% Cash & Gems) stacks on top.
-- ============================================================================

export type MultiplierProfileLike = {
	OwnedBoosts: { [string]: boolean }?,
	OwnedPasses: { [string]: boolean }?,
}

function ProgressionLogic.GetTrackMultiplier(
	profile: MultiplierProfileLike,
	trackId: GameConfig.MultiplierTrackId
): number
	local track = GameConfig.MultiplierTracksById[trackId]
	if not track then
		return 1.0
	end
	local owned = profile.OwnedBoosts or {}
	local passes = profile.OwnedPasses or {}
	local best = 1.0
	for _, tier in track.Tiers do
		if owned[tier.BoostId] == true or passes[tier.PassId] == true then
			if tier.Multiplier > best then
				best = tier.Multiplier
			end
		end
	end
	-- Legacy saved boost aliases
	if trackId == "money" and owned.double_cash == true then
		best = math.max(best, 2.0)
	elseif trackId == "power" and owned.double_power == true then
		best = math.max(best, 2.0)
	elseif trackId == "luck" and owned.lucky_charm == true then
		best = math.max(best, 1.5)
	end
	return best
end

function ProgressionLogic.GetNextMultiplierTier(
	profile: MultiplierProfileLike,
	trackId: GameConfig.MultiplierTrackId
): (GameConfig.MultiplierTierDef?, number)
	local track = GameConfig.MultiplierTracksById[trackId]
	if not track then
		return nil, 1.0
	end
	local currentMult = ProgressionLogic.GetTrackMultiplier(profile, trackId)
	for _, tier in track.Tiers do
		if tier.Multiplier > currentMult then
			return tier, currentMult
		end
	end
	return nil, currentMult
end

function ProgressionLogic.GetGemMultiplier(profile: MultiplierProfileLike): number
	local base = ProgressionLogic.GetTrackMultiplier(profile, "gems")
	local passes = profile.OwnedPasses or {}
	local vip = GameConfig.RobuxPassesById.pass_vip
	local vipMult = if passes.pass_vip == true and vip and vip.GemMultiplier then vip.GemMultiplier else 1.0
	return base * vipMult
end

function ProgressionLogic.GetTrainingPowerMultiplier(profile: MultiplierProfileLike): number
	return ProgressionLogic.GetTrackMultiplier(profile, "power")
end

function ProgressionLogic.GetCashMultiplier(profile: MultiplierProfileLike): number
	local base = ProgressionLogic.GetTrackMultiplier(profile, "money")
	local passes = profile.OwnedPasses or {}
	local vip = GameConfig.RobuxPassesById.pass_vip
	local vipMult = if passes.pass_vip == true and vip and vip.CashMultiplier then vip.CashMultiplier else 1.0
	return base * vipMult
end

-- Effective Cash multiplier granted by owned Robux Passes (kept for compatibility with UI/tests).
function ProgressionLogic.GetPassCashMultiplier(profile: { OwnedPasses: { [string]: boolean }? }): number
	local passes = profile.OwnedPasses or {}
	local mult = 1.0
	local moneyPass = GameConfig.RobuxPassesById.pass_x2_cash
	if passes.pass_x2_cash == true and moneyPass and moneyPass.CashMultiplier then
		mult *= moneyPass.CashMultiplier
	end
	local vip = GameConfig.RobuxPassesById.pass_vip
	if passes.pass_vip == true and vip and vip.CashMultiplier then
		mult *= vip.CashMultiplier
	end
	return mult
end

function ProgressionLogic.GetBoostLuckMultiplier(profile: MultiplierProfileLike): number
	return ProgressionLogic.GetTrackMultiplier(profile, "luck")
end

function ProgressionLogic.GetEffectiveMaxSlimes(
	profile: { MaxSlimes: number?, OwnedPasses: { [string]: boolean }? }
): number
	local passes = profile.OwnedPasses or {}
	if passes.pass_extra_slots == true then
		return GameConfig.Slots.ExpandedMaxSlimes
	end
	local raw = profile.MaxSlimes or GameConfig.Slots.InitialMaxSlimes
	return math.clamp(math.floor(raw), GameConfig.Slots.InitialMaxSlimes, GameConfig.Slots.ExpandedMaxSlimes)
end

function ProgressionLogic.OwnsAutoThrow(profile: MultiplierProfileLike): boolean
	local owned = profile.OwnedBoosts or {}
	local passes = profile.OwnedPasses or {}
	return owned.auto_throw == true or passes.pass_auto_throw == true
end

local function scaleEarnedGems(profile: PlayerProfile, baseGems: number): number
	if baseGems <= 0 then
		return 0
	end
	return math.max(1, math.floor(baseGems * ProgressionLogic.GetGemMultiplier(profile) + 0.5))
end

-- ============================================================================
-- GEMS: earning
-- ============================================================================

local function countDiscovered(profile: PlayerProfile): number
	local n = 0
	for _, found in profile.DiscoveredSlimes do
		if found then
			n += 1
		end
	end
	return n
end

-- Pays every Index milestone the discovered count has reached but that hasn't been paid yet.
function ProgressionLogic.AwardIndexMilestones(profile: PlayerProfile): number
	local milestones = GameConfig.Gems.IndexMilestones
	local discovered = countDiscovered(profile)
	local basePaid = 0
	while true do
		local nextMilestone = milestones[profile.IndexMilestonesClaimed + 1]
		if not nextMilestone or discovered < nextMilestone.Discovered then
			break
		end
		profile.IndexMilestonesClaimed += 1
		basePaid += nextMilestone.Gems
	end
	local paid = scaleEarnedGems(profile, basePaid)
	profile.Gems += paid
	return paid
end

-- First time a throw lands in zone N: pays FirstZoneReach for every zone up to N not paid before.
function ProgressionLogic.AwardZoneReach(profile: PlayerProfile, zoneIndex: number): number
	local rewards = GameConfig.Gems.FirstZoneReach
	local target = math.clamp(math.floor(zoneIndex), 0, #rewards)
	local basePaid = 0
	while profile.HighestZoneReached < target do
		profile.HighestZoneReached += 1
		basePaid += rewards[profile.HighestZoneReached] or 0
	end
	local paid = scaleEarnedGems(profile, basePaid)
	profile.Gems += paid
	return paid
end

-- Base Gems for a rare catch from a throw (multiplied by GetGemMultiplier when paid).
function ProgressionLogic.GetCatchGems(slimeDef: GameConfig.SlimeDef, mutationId: string): number
	local cfg = GameConfig.Gems
	return (cfg.RarityDrops[slimeDef.Rarity] or 0) + (cfg.MutationDrops[mutationId] or 0)
end

-- Welcome Back: cash earned while away. Pure. 0 when never seen, away too short, or no income.
function ProgressionLogic.ComputeOfflineEarnings(incomePerSec: number, awaySeconds: number): number
	local cfg = GameConfig.Offline
	if incomePerSec <= 0 or awaySeconds < cfg.MinAwaySeconds then
		return 0
	end
	return math.floor(incomePerSec * math.min(awaySeconds, cfg.MaxAwaySeconds) * cfg.Rate)
end

-- Unlock pop-ups (spec 4f). Returns the pop-ups to show now and the updated "already told" markers.
-- `seen.BaitTierOffered` = highest bait tier we already announced as affordable; `seen.ZoneSeen` = highest zone announced.
export type UnlockSeen = { BaitTierOffered: number, ZoneSeen: number }
export type UnlockPopup = { Kind: "bait" | "zone", Index: number }

function ProgressionLogic.NextUnlockPopups(
	cash: number,
	baitTier: number,
	highestZone: number,
	seen: UnlockSeen
): ({ UnlockPopup }, UnlockSeen)
	local popups: { UnlockPopup } = {}
	local out: UnlockSeen = { BaitTierOffered = seen.BaitTierOffered, ZoneSeen = seen.ZoneSeen }
	local nextBait = GameConfig.BaitTiers[baitTier + 1]
	if nextBait and cash >= nextBait.Cost and out.BaitTierOffered < baitTier + 1 then
		out.BaitTierOffered = baitTier + 1
		table.insert(popups, { Kind = "bait", Index = baitTier + 1 })
	end
	if highestZone > out.ZoneSeen then
		out.ZoneSeen = highestZone
		table.insert(popups, { Kind = "zone", Index = highestZone })
	end
	return popups, out
end

function ProgressionLogic.GetDayNumber(unixSeconds: number): number
	return math.floor(unixSeconds / GameConfig.Gems.SecondsPerDay)
end

-- Pure status check for the 7-day Daily Reward calendar UI.
function ProgressionLogic.GetDailyStatus(
	profile: PlayerProfile,
	dayNumber: number
): { CanClaim: boolean, NextStreakDay: number, WillReset: boolean }
	if profile.LastDailyClaimDay >= dayNumber then
		return {
			CanClaim = false,
			NextStreakDay = math.max(1, profile.DailyStreak),
			WillReset = false,
		}
	elseif profile.LastDailyClaimDay >= 0 and dayNumber == profile.LastDailyClaimDay + 1 then
		return {
			CanClaim = true,
			NextStreakDay = profile.DailyStreak + 1,
			WillReset = false,
		}
	else
		return {
			CanClaim = true,
			NextStreakDay = 1,
			WillReset = profile.DailyStreak > 0,
		}
	end
end

-- Daily login reward. `dayNumber` is ProgressionLogic.GetDayNumber(os.time()), passed in so this stays pure.
-- Returns (claimed, gemsPaid, streakDay). Claiming on the day after the last claim continues the streak;
-- any longer gap restarts it at day 1.
function ProgressionLogic.ClaimDailyReward(profile: PlayerProfile, dayNumber: number): (boolean, number, number)
	if profile.LastDailyClaimDay >= dayNumber then
		return false, 0, profile.DailyStreak
	end
	if profile.LastDailyClaimDay >= 0 and dayNumber == profile.LastDailyClaimDay + 1 then
		profile.DailyStreak += 1
	else
		profile.DailyStreak = 1
	end
	profile.LastDailyClaimDay = dayNumber
	local rewards = GameConfig.Gems.DailyRewards
	local baseGems = rewards[math.min(profile.DailyStreak, #rewards)]
	local gems = scaleEarnedGems(profile, baseGems)
	profile.Gems += gems
	return true, gems, profile.DailyStreak
end

-- Grants a Robux Gem Pack once per unique PurchaseId, keeping a capped dedupe history on the profile.
-- Robux Gem Packs are NOT multiplied by in-game Gem multipliers.
function ProgressionLogic.GrantRobuxGemPack(
	profile: PlayerProfile,
	packId: string,
	purchaseId: string
): (boolean, number, string)
	local pack = GameConfig.RobuxGemPacksById[packId]
	if not pack or type(purchaseId) ~= "string" or purchaseId == "" then
		return false, 0, "Invalid Robux pack or receipt"
	end
	profile.ProcessedReceipts = profile.ProcessedReceipts or {}
	if table.find(profile.ProcessedReceipts, purchaseId) then
		return false, 0, "Receipt already processed"
	end
	table.insert(profile.ProcessedReceipts, purchaseId)
	while #profile.ProcessedReceipts > GameConfig.Robux.MaxProcessedReceipts do
		table.remove(profile.ProcessedReceipts, 1)
	end
	profile.Gems += pack.Gems
	return true, pack.Gems, `Purchased {pack.Name} (+{GameConfig.FormatNumber(pack.Gems)} Gems)!`
end

local function milestoneSuffix(gems: number): string
	return if gems > 0 then ` +{gems} Gems (Index milestone)!` else ""
end

function ProgressionLogic.GetTrailMultiplier(profile: PlayerProfile, bonusType: "XP" | "Cash" | "Power"): number
	local zIdx = profile.EquippedTrailZone
	if not zIdx then
		return 1.0
	end
	local zDef = GameConfig.Zones[zIdx]
	if not zDef then
		return 1.0
	end
	if zDef.TrailBonusType == bonusType or zDef.TrailBonusType == "All" then
		return zDef.TrailMultiplier
	end
	return 1.0
end

function ProgressionLogic.GetEffectiveThrowPower(profile: PlayerProfile): number
	local upgradeBonus = GameConfig.GetPowerUpgradeBonus(profile.PowerUpgradeLevel)
	local equippedDef = GameConfig.SlimesById[profile.EquippedSlimeId]
	local slimeBonus = if equippedDef then equippedDef.ThrowBonus else 0
	local raw = profile.BaseThrowPower + upgradeBonus + slimeBonus
	local trailMult = ProgressionLogic.GetTrailMultiplier(profile, "Power")
	return math.max(1, math.floor(raw * trailMult + 0.5))
end

function ProgressionLogic.GetIncomePerSecond(profile: PlayerProfile): number
	local total = 0
	local hasPlacedInstances = false
	local maxSlots = ProgressionLogic.GetEffectiveMaxSlimes(profile)
	for slot = 1, maxSlots do
		local inst = profile.PlacedSlimesBySlot[slot]
		if inst then
			hasPlacedInstances = true
			total += inst.IncomePerSec
		end
	end

	-- Fallback if legacy test mutated PlacedSlimes directly
	if not hasPlacedInstances and #profile.PlacedSlimes > 0 then
		local count = math.min(#profile.PlacedSlimes, maxSlots)
		for i = 1, count do
			local def = GameConfig.SlimesById[profile.PlacedSlimes[i]]
			if def then
				total += def.IncomePerSec
			end
		end
	end

	local cashMult = ProgressionLogic.GetCashMultiplier(profile)
	local trailMult = ProgressionLogic.GetTrailMultiplier(profile, "Cash")
	return math.floor(total * cashMult * trailMult + 0.5)
end

function ProgressionLogic.GetRarestSlimeDef(profile: PlayerProfile): GameConfig.SlimeDef
	local bestDef = GameConfig.Slimes[1]
	for _, slimeId in profile.OwnedSlimes do
		local def = GameConfig.SlimesById[slimeId]
		if def and def.RarityRank > bestDef.RarityRank then
			bestDef = def
		end
	end
	return bestDef
end

-- One pull-up rep: adds Training XP (bar tier XPPerRep x Training Power tier x trail x repMultiplier),
-- then levels up as many times as the XP covers. Each level up adds GameConfig.Training.PowerPerLevel Throw Power.
-- repMultiplier is GameConfig.Training.BonusRepMultiplier for a clicked Bonus Rep.
function ProgressionLogic.ApplyPullUpRep(profile: PlayerProfile, repMultiplier: number?): PullUpRepResult
	local tierDef = GameConfig.PullUpTiers[profile.PullUpTier] or GameConfig.PullUpTiers[1]
	local xpBoost = ProgressionLogic.GetTrainingPowerMultiplier(profile)
	local trailMult = ProgressionLogic.GetTrailMultiplier(profile, "XP")
	local mult = math.max(0, repMultiplier or 1)
	local xpGained = math.max(1, math.floor(tierDef.XPPerRep * mult * xpBoost * trailMult + 0.5))

	profile.TrainingXP += xpGained
	profile.TotalPullUps += 1

	local levels = 0
	local required = GameConfig.GetXPRequiredForLevel(profile.StrengthLevel)
	while profile.TrainingXP >= required do
		profile.TrainingXP -= required
		profile.StrengthLevel += 1
		levels += 1
		required = GameConfig.GetXPRequiredForLevel(profile.StrengthLevel)
	end
	local powerGained = levels * GameConfig.Training.PowerPerLevel
	profile.BaseThrowPower += powerGained

	QuestLogic.RecordEvent(profile, "PullUpRep", 1)
	if (repMultiplier or 1) > 1 then
		QuestLogic.RecordEvent(profile, "BonusRep", 1)
	end

	return {
		XPGained = xpGained,
		LevelsGained = levels,
		PowerGained = powerGained,
		NewLevel = profile.StrengthLevel,
		CurrentXP = profile.TrainingXP,
		RequiredXP = required,
	}
end

function ProgressionLogic.PurchaseBaitTier(profile: PlayerProfile): (boolean, string)
	local nextTier = GameConfig.BaitTiers[profile.BaitTier + 1]
	if not nextTier then
		return false, "Your Jelly Bait is already at Max Tier!"
	end
	if profile.Cash < nextTier.Cost then
		return false, `Need ${GameConfig.FormatNumber(nextTier.Cost)} Cash`
	end
	profile.Cash -= nextTier.Cost
	profile.BaitTier += 1
	QuestLogic.RecordEvent(profile, "BuyBait", profile.BaitTier, { BaitTier = profile.BaitTier })
	return true, `Unlocked {nextTier.Name} ({nextTier.LuckMultiplier}x Luck)!`
end

function ProgressionLogic.GetBaitDef(profile: { BaitTier: number? }): GameConfig.BaitTierDef
	return GameConfig.BaitTiers[profile.BaitTier or 1] or GameConfig.BaitTiers[1]
end

function ProgressionLogic.PurchasePowerUpgrade(profile: PlayerProfile): (boolean, string)
	local cost = GameConfig.GetPowerUpgradeCost(profile.PowerUpgradeLevel)
	if profile.Cash < cost then
		return false, `Need ${GameConfig.FormatNumber(cost)} Cash`
	end
	profile.Cash -= cost
	profile.PowerUpgradeLevel += 1
	return true, `Throw Power upgraded to Lv.{profile.PowerUpgradeLevel}!`
end

function ProgressionLogic.PurchasePullUpTier(profile: PlayerProfile): (boolean, string)
	local nextTierIndex = profile.PullUpTier + 1
	local nextTier = GameConfig.PullUpTiers[nextTierIndex]
	if not nextTier then
		return false, "Pull-Up Bar is already at Max Tier!"
	end
	if profile.Cash < nextTier.Cost then
		return false, `Need ${GameConfig.FormatNumber(nextTier.Cost)} Cash`
	end
	profile.Cash -= nextTier.Cost
	profile.PullUpTier = nextTierIndex
	return true, `Unlocked {nextTier.Name} (+{nextTier.XPPerRep} XP/rep)!`
end

-- Locked Plot Slots (9..12): strictly unlocked 1-by-1 with Gems OR all 4 at once via "+4 Plot Slots" Robux Pass.
-- Cash can never unlock extra plot slots.
function ProgressionLogic.GetSlotExpansionCost(currentMaxSlimes: number?): number?
	local cur = currentMaxSlimes or GameConfig.Slots.InitialMaxSlimes
	return GameConfig.GetNextSlotGemCost(cur)
end

function ProgressionLogic.PurchaseSlotExpansion(profile: PlayerProfile, priceKind: GameConfig.PriceKind?): (boolean, string)
	if priceKind ~= nil and priceKind ~= "Gems" then
		return false, "Extra plot slots can only be unlocked with Gems or the +4 Plot Slots Pass!"
	end
	local effMax = ProgressionLogic.GetEffectiveMaxSlimes(profile)
	if effMax >= GameConfig.Slots.ExpandedMaxSlimes then
		return false, "All 12 Slime Slots are already unlocked!"
	end
	local cost = GameConfig.GetNextSlotGemCost(effMax)
	if not cost then
		return false, "All 12 Slime Slots are already unlocked!"
	end
	if profile.Gems < cost then
		return false, needText("Gems", cost)
	end
	profile.Gems -= cost
	profile.MaxSlimes = effMax + 1
	return true, `Unlocked Plot Slot #{profile.MaxSlimes} ({profile.MaxSlimes}/{GameConfig.Slots.ExpandedMaxSlimes})!`
end

function ProgressionLogic.PurchaseMultiplierTier(
	profile: PlayerProfile,
	trackId: GameConfig.MultiplierTrackId
): (boolean, string)
	local track = GameConfig.MultiplierTracksById[trackId]
	if not track then
		return false, "Unknown multiplier upgrade"
	end
	local nextTier, curMult = ProgressionLogic.GetNextMultiplierTier(profile, trackId)
	if not nextTier then
		return false, `{track.Name} is already at MAX ({curMult}x)!`
	end
	if profile.Gems < nextTier.GemCost then
		return false, needText("Gems", nextTier.GemCost)
	end
	profile.Gems -= nextTier.GemCost
	profile.OwnedBoosts[nextTier.BoostId] = true
	return true, `Unlocked {nextTier.Name}!`
end

function ProgressionLogic.RollSlimeForZone(zoneIndex: number, unitRandom: number, luckMultiplier: number?): GameConfig.SlimeDef
	local pool = GameConfig.SlimesByZone[zoneIndex] or GameConfig.SlimesByZone[1]
	local luck = math.max(1.0, luckMultiplier or 1.0)

	local weights = {}
	local totalWeight = 0
	-- Calibrated exponent so 2x -> 10x Luck visibly boosts rarest slimes across all zones. The rarest slime
	-- always gets luck^1.1 (the 3-slime calibration: 0.55 per step); with more slimes per zone the step shrinks.
	local luckStep = 1.1 / math.max(1, #pool - 1)
	for i, slime in pool do
		local w = if i == 1 then slime.DropWeight else slime.DropWeight * (luck ^ (luckStep * (i - 1)))
		weights[i] = w
		totalWeight += w
	end

	local r = math.clamp(unitRandom, 0, 0.999999) * totalWeight
	local accum = 0
	for i, slime in pool do
		accum += weights[i]
		if r <= accum then
			return slime
		end
	end
	return pool[#pool]
end

local MUTATION_LUCK_EXPONENT: { [string]: number } = {
	NORMAL = 0,
	EMERALD = 0.45,
	GOLDEN = 0.65,
	CRYSTAL = 0.85,
	RAINBOW = 1.05,
}

function ProgressionLogic.RollMutation(unitRandom: number, luckMultiplier: number?): GameConfig.MutationDef
	local luck = math.max(1.0, luckMultiplier or 1.0)
	local weights = {}
	local totalWeight = 0
	for i, mut in GameConfig.Mutations do
		local exp = MUTATION_LUCK_EXPONENT[mut.Id] or 0
		local w = if exp <= 0 then mut.Weight else mut.Weight * (luck ^ exp)
		weights[i] = w
		totalWeight += w
	end

	local r = math.clamp(unitRandom, 0, 0.999999) * totalWeight
	local accum = 0
	for i, mut in GameConfig.Mutations do
		accum += weights[i]
		if r <= accum then
			return mut
		end
	end
	return GameConfig.Mutations[1]
end

function ProgressionLogic.EvaluateThrowReward(
	profile: PlayerProfile,
	distance: number,
	landedZoneIndex: number,
	unitRandom: number?,
	luckMultiplier: number?,
	mutationRandom: number?,
	putInHotbarOnly: boolean?
): ThrowRewardOutcome
	local zone = GameConfig.Zones[landedZoneIndex] or GameConfig.Zones[1]
	local cleanDist = math.max(1, distance)
	local cashMult = ProgressionLogic.GetCashMultiplier(profile)
	local trailMult = ProgressionLogic.GetTrailMultiplier(profile, "Cash")
	local cashEarned = math.max(5, math.floor(cleanDist * zone.CashPerStud * cashMult * trailMult + 0.5))
	profile.Cash += cashEarned
	profile.TotalThrows += 1

	local isNewBest = false
	if distance > profile.BestDistance then
		profile.BestDistance = distance
		isNewBest = true
	end

	local luck = math.max(1.0, luckMultiplier or 1.0)
	local rng1 = if unitRandom ~= nil then unitRandom else math.random()
	local rng2 = if mutationRandom ~= nil then mutationRandom else math.random()

	local caughtDef = ProgressionLogic.RollSlimeForZone(zone.Index, rng1, luck)
	local mutDef = ProgressionLogic.RollMutation(rng2, luck)

	local isNewDiscovery = not profile.DiscoveredSlimes[caughtDef.Id]
	profile.DiscoveredSlimes[caughtDef.Id] = true

	-- Gems: rare catch + first time reaching this zone + any Index milestone the catch completed
	local catchGems = scaleEarnedGems(profile, ProgressionLogic.GetCatchGems(caughtDef, mutDef.Id))
	profile.Gems += catchGems
	local zoneGems = ProgressionLogic.AwardZoneReach(profile, zone.Index)
	local indexGems = ProgressionLogic.AwardIndexMilestones(profile)
	local gems: GemAward = {
		Total = catchGems + zoneGems + indexGems,
		FromCatch = catchGems,
		FromZone = zoneGems,
		FromIndex = indexGems,
	}

	local instance = makeSlimeInstance(profile, caughtDef.Id, mutDef.Id)
	local oddsOneInX = math.max(1, math.floor(caughtDef.BaseOdds * mutDef.OddsMultiplier + 0.5))
	local isSuperLucky = (oddsOneInX >= 10) or (mutDef.Id ~= "NORMAL")

	local autoPlaced = false
	local maxSlots = ProgressionLogic.GetEffectiveMaxSlimes(profile)
	if putInHotbarOnly == true then
		table.insert(profile.UnplacedSlimes, instance)
	else
		-- Find first free slot up to effective MaxSlimes
		local freeSlot: number? = nil
		for slot = 1, maxSlots do
			if not profile.PlacedSlimesBySlot[slot] then
				freeSlot = slot
				break
			end
		end
		if freeSlot then
			profile.PlacedSlimesBySlot[freeSlot] = instance
			autoPlaced = true
		else
			table.insert(profile.UnplacedSlimes, instance)
		end
	end

	syncLegacyArrays(profile)

	QuestLogic.RecordEvent(profile, "Throw", 1)
	QuestLogic.RecordEvent(profile, "EarnCash", cashEarned)
	QuestLogic.RecordEvent(profile, "CatchRarity", 1, { RarityRank = caughtDef.RarityRank })
	QuestLogic.RecordEvent(profile, "ReachZone", zone.Index, { ZoneIndex = zone.Index })
	QuestLogic.RecordEvent(profile, "Discover", countDiscovered(profile), { DiscoveredCount = countDiscovered(profile) })

	return {
		CashEarned = cashEarned,
		CaughtSlimeId = caughtDef.Id,
		CaughtSlimeDef = caughtDef,
		CaughtInstance = instance,
		Mutation = mutDef.Id,
		OddsOneInX = oddsOneInX,
		IsSuperLucky = isSuperLucky,
		IsNewDiscovery = isNewDiscovery,
		AutoPlaced = autoPlaced,
		IsNewBestDistance = isNewBest,
		Gems = gems,
	}
end

function ProgressionLogic.PlaceSlimeAtSlot(profile: PlayerProfile, slimeUid: string, slotIndex: number): (boolean, string)
	if type(slotIndex) ~= "number" or slotIndex ~= slotIndex or math.abs(slotIndex) == math.huge then
		return false, "That slot is locked!"
	end
	local slot = math.floor(slotIndex)
	local maxSlots = ProgressionLogic.GetEffectiveMaxSlimes(profile)
	if slot < 1 or slot > maxSlots then
		return false, "That slot is locked!"
	end

	local foundIdx: number? = nil
	local foundInst: SlimeInstance? = nil
	for i, inst in profile.UnplacedSlimes do
		if inst.Uid == slimeUid then
			foundIdx = i
			foundInst = inst
			break
		end
	end

	if not foundIdx or not foundInst then
		return false, "Select a slime from your hotbar first!"
	end

	table.remove(profile.UnplacedSlimes, foundIdx)
	local existing = profile.PlacedSlimesBySlot[slot]
	if existing then
		table.insert(profile.UnplacedSlimes, existing)
	end
	profile.PlacedSlimesBySlot[slot] = foundInst
	syncLegacyArrays(profile)
	QuestLogic.RecordEvent(profile, "PlaceSlime", 1)
	return true, `Placed {foundInst.Name} (+${GameConfig.FormatNumber(foundInst.IncomePerSec)}/s)!`
end

function ProgressionLogic.PickupSlimeFromSlot(profile: PlayerProfile, slotIndex: number): (boolean, string)
	if type(slotIndex) ~= "number" or slotIndex ~= slotIndex or math.abs(slotIndex) == math.huge then
		return false, "Slot is empty"
	end
	local slot = math.floor(slotIndex)
	if slot < 1 or slot > GameConfig.Slots.ExpandedMaxSlimes then
		return false, "Slot is empty"
	end
	local existing = profile.PlacedSlimesBySlot[slot]
	if not existing then
		return false, "Slot is empty"
	end
	profile.PlacedSlimesBySlot[slot] = nil
	table.insert(profile.UnplacedSlimes, existing)
	syncLegacyArrays(profile)
	return true, `Picked up {existing.Name} into your hotbar!`
end

function ProgressionLogic.GetSlimeSellPrice(inst: SlimeInstance): number
	local cfg = GameConfig.Sell
	return math.max(cfg.MinSellPrice, math.floor((inst.IncomePerSec or 0) * cfg.IncomeSecondsMultiplier + 0.5))
end

local function ensureValidEquippedSlime(profile: PlayerProfile)
	for _, id in profile.OwnedSlimes do
		if id == profile.EquippedSlimeId then
			return
		end
	end
	if #profile.OwnedSlimes > 0 then
		profile.EquippedSlimeId = ProgressionLogic.GetRarestSlimeDef(profile).Id
	else
		profile.EquippedSlimeId = GameConfig.Slimes[1].Id
	end
end

function ProgressionLogic.SellSlime(profile: PlayerProfile, slimeUid: string): (boolean, string, number)
	if type(slimeUid) ~= "string" or slimeUid == "" then
		return false, "Invalid slime", 0
	end
	local foundIdx: number? = nil
	local foundInst: SlimeInstance? = nil
	for i, inst in profile.UnplacedSlimes do
		if inst.Uid == slimeUid then
			foundIdx = i
			foundInst = inst
			break
		end
	end
	if not foundIdx or not foundInst then
		return false, "Pick up the slime from your plot before selling it!", 0
	end
	local price = ProgressionLogic.GetSlimeSellPrice(foundInst)
	table.remove(profile.UnplacedSlimes, foundIdx)
	profile.Cash += price
	syncLegacyArrays(profile)
	ensureValidEquippedSlime(profile)
	QuestLogic.RecordEvent(profile, "EarnCash", price)
	return true, `Sold {foundInst.Name} for +${GameConfig.FormatNumber(price)}!`, price
end

function ProgressionLogic.SellAllUnplacedSlimes(profile: PlayerProfile): (boolean, string, number, number)
	local count = #profile.UnplacedSlimes
	if count == 0 then
		return false, "No slimes in your backpack to sell!", 0, 0
	end
	local totalCash = 0
	for _, inst in profile.UnplacedSlimes do
		totalCash += ProgressionLogic.GetSlimeSellPrice(inst)
	end
	profile.UnplacedSlimes = {}
	profile.Cash += totalCash
	syncLegacyArrays(profile)
	ensureValidEquippedSlime(profile)
	QuestLogic.RecordEvent(profile, "EarnCash", totalCash)
	return true, `Sold {count} slime{if count == 1 then "" else "s"} for +${GameConfig.FormatNumber(totalCash)}!`, totalCash, count
end

function ProgressionLogic.GetZoneIndexProgress(profile: PlayerProfile, zoneIndex: number): {
	UnlockedCount: number,
	TotalCount: number,
	Percent: number,
	IsComplete: boolean,
}
	local pool = GameConfig.SlimesByZone[zoneIndex] or {}
	local total = #pool
	local unlocked = 0
	for _, slime in pool do
		if profile.DiscoveredSlimes[slime.Id] then
			unlocked += 1
		end
	end
	local pct = if total > 0 then math.floor((unlocked / total) * 100 + 0.5) else 0
	return {
		UnlockedCount = unlocked,
		TotalCount = total,
		Percent = pct,
		IsComplete = (total > 0 and unlocked >= total),
	}
end

function ProgressionLogic.EquipZoneTrail(profile: PlayerProfile, zoneIndex: number): (boolean, string)
	local prog = ProgressionLogic.GetZoneIndexProgress(profile, zoneIndex)
	if not prog.IsComplete then
		return false, "Discover all slimes in this zone to unlock its Trail!"
	end
	local zoneDef = GameConfig.Zones[zoneIndex]
	if not zoneDef then
		return false, "Invalid zone"
	end
	profile.EquippedTrailZone = zoneIndex
	return true, `Equipped {zoneDef.TrailName} ({zoneDef.TrailBonusText})!`
end

function ProgressionLogic.ClaimFreeGiftSlime(profile: PlayerProfile): (boolean, string, SlimeInstance?)
	if profile.ClaimedFreeGift then
		return false, "You already claimed your free bonus slime!", nil
	end
	profile.ClaimedFreeGift = true
	local gift = GameConfig.FreeGift
	profile.DiscoveredSlimes[gift.SlimeId] = true
	local inst = makeSlimeInstance(profile, gift.SlimeId, gift.Mutation)
	table.insert(profile.UnplacedSlimes, inst)
	syncLegacyArrays(profile)
	local indexGems = ProgressionLogic.AwardIndexMilestones(profile)
	QuestLogic.RecordEvent(profile, "Discover", countDiscovered(profile), { DiscoveredCount = countDiscovered(profile) })
	return true, `Claimed free {inst.Mutation} {inst.Name} (+${inst.IncomePerSec}/s)!{milestoneSuffix(indexGems)}`, inst
end

-- Boosts are paid in their own PriceKind (Auto-Throw / multipliers = Gems).
function ProgressionLogic.PurchaseShopBoost(profile: PlayerProfile, boostId: string): (boolean, string)
	local boost = GameConfig.ShopBoosts[boostId]
	if not boost then
		return false, "Unknown boost"
	end
	if profile.OwnedBoosts[boostId] or (boostId == "auto_throw" and ProgressionLogic.OwnsAutoThrow(profile)) then
		return false, `You already own {boost.Name}!`
	end
	if ProgressionLogic.GetBalance(profile, boost.PriceKind) < boost.Cost then
		return false, needText(boost.PriceKind, boost.Cost)
	end
	spend(profile, boost.PriceKind, boost.Cost)
	profile.OwnedBoosts[boostId] = true
	return true, `Unlocked {boost.Name}!`
end

-- Hatches 1 or 3 slimes from a Featured Robux Shop Egg (no Cash cost; granted by Robux receipt or direct test).
function ProgressionLogic.HatchShopEgg(
	profile: PlayerProfile,
	eggId: string,
	count: number,
	unitRandomFn: (() -> number)?
): (boolean, string, { SlimeInstance })
	local egg = GameConfig.ShopEggsById[eggId]
	if not egg then
		return false, "Unknown egg", {}
	end
	local num = if count == 3 then 3 else 1

	local rng = unitRandomFn or math.random
	local hatched: { SlimeInstance } = {}

	for _ = 1, num do
		local roll = math.clamp(rng(), 0, 0.999999) * 100
		local accum = 0
		local picked = egg.Items[1]
		for _, item in egg.Items do
			accum += item.ChancePercent
			if roll <= accum then
				picked = item
				break
			end
		end
		profile.DiscoveredSlimes[picked.SlimeId] = true
		local inst = makeSlimeInstance(profile, picked.SlimeId, picked.Mutation)
		table.insert(profile.UnplacedSlimes, inst)
		table.insert(hatched, inst)
	end

	syncLegacyArrays(profile)
	local indexGems = ProgressionLogic.AwardIndexMilestones(profile)
	QuestLogic.RecordEvent(profile, "HatchEgg", num)
	QuestLogic.RecordEvent(profile, "Discover", countDiscovered(profile), { DiscoveredCount = countDiscovered(profile) })
	local first = hatched[1]
	local summary = if num == 1
		then `Hatched {first.Mutation ~= "NORMAL" and (first.Mutation .. " ") or ""}{first.Name} (+${first.IncomePerSec}/s)!`
		else `Hatched {num}x Slimes from {egg.Name}!`
	return true, summary .. milestoneSuffix(indexGems), hatched
end

-- Grants a Robux Featured Egg purchase (1x or 3x) once per unique PurchaseId receipt.
function ProgressionLogic.GrantRobuxEgg(
	profile: PlayerProfile,
	eggId: string,
	count: number,
	purchaseId: string,
	unitRandomFn: (() -> number)?
): (boolean, string, { SlimeInstance })
	local egg = GameConfig.ShopEggsById[eggId]
	if not egg or type(purchaseId) ~= "string" or purchaseId == "" then
		return false, "Invalid Robux egg or receipt", {}
	end
	profile.ProcessedReceipts = profile.ProcessedReceipts or {}
	if table.find(profile.ProcessedReceipts, purchaseId) then
		return false, "Receipt already processed", {}
	end
	table.insert(profile.ProcessedReceipts, purchaseId)
	while #profile.ProcessedReceipts > GameConfig.Robux.MaxProcessedReceipts do
		table.remove(profile.ProcessedReceipts, 1)
	end
	return ProgressionLogic.HatchShopEgg(profile, eggId, count, unitRandomFn)
end

-- ============================================================================
-- PULL-UP LOOP SPEED (strength + bar tier)
-- ============================================================================

-- Seconds per pull-up rep. Shrinks with strength (BaseThrowPower) and the bar tier's SpeedMult,
-- clamped to [MinRepSeconds, BaseRepSeconds]. Each rep still pays the tier's XPPerRep, so
-- faster reps mean more XP per second.
function ProgressionLogic.GetPullUpRepInterval(profile: { BaseThrowPower: number, PullUpTier: number }): number
	local cfg = GameConfig.PullUp
	local tierDef = GameConfig.PullUpTiers[profile.PullUpTier] or GameConfig.PullUpTiers[1]
	local power = math.max(0, profile.BaseThrowPower or 0)
	local strengthSpeed = 1 + cfg.StrengthLogScale * math.log10(1 + power / cfg.StrengthRef)
	local interval = cfg.BaseRepSeconds / (tierDef.SpeedMult * strengthSpeed)
	return math.clamp(interval, cfg.MinRepSeconds, cfg.BaseRepSeconds)
end

-- ============================================================================
-- SHOP: one listing for the UI + one purchase entry point
-- ============================================================================

export type ShopQuantity = number | "max"

export type ShopOption = {
	Quantity: ShopQuantity,
	Label: string,
	Price: number,
	CanAfford: boolean,
}

export type ShopState = "Available" | "Unaffordable" | "Owned" | "Maxed" | "Claimed"

export type ShopListingEntry = {
	Id: string,
	Category: string,
	Icon: string,
	Color: { number },
	Title: string,
	Subtitle: string,
	Price: number,
	PriceKind: GameConfig.PriceKind, -- which wallet pays (Price and CanAfford are in this currency)
	PriceText: string,
	State: ShopState,
	Options: { ShopOption },
}

-- Anything with these fields works: the server PlayerProfile OR the client's synced state table.
export type ShopStateInput = {
	Cash: number?,
	Gems: number?,
	PowerUpgradeLevel: number?,
	PullUpTier: number?,
	BaitTier: number?,
	MaxSlimes: number?,
	OwnedBoosts: { [string]: boolean }?,
	OwnedPasses: { [string]: boolean }?,
	ClaimedFreeGift: boolean?,
}

local function priceText(price: number, kind: GameConfig.PriceKind?): string
	if price <= 0 then
		return "FREE"
	end
	if kind == "Robux" then
		return `R$ {GameConfig.FormatNumber(price)}`
	elseif kind == "Gems" then
		return `💎 {GameConfig.FormatNumber(price)}`
	else
		return `${GameConfig.FormatNumber(price)}`
	end
end

local function option(quantity: ShopQuantity, label: string, price: number, balance: number): ShopOption
	return { Quantity = quantity, Label = label, Price = price, CanAfford = balance >= price }
end

local function buildListingEntry(item: GameConfig.ShopCatalogItem, s: ShopStateInput): ShopListingEntry
	-- Boosts are priced in their own currency; everything else uses the catalog row's PriceKind
	local priceKind: GameConfig.PriceKind = item.PriceKind
	if item.Action == "Boost" then
		local boostDef = GameConfig.ShopBoosts[item.Args.BoostId or ""]
		if boostDef then
			priceKind = boostDef.PriceKind
		end
	end
	local balance = ProgressionLogic.GetBalance(s, priceKind) -- balance of the wallet this item is paid from
	local entry: ShopListingEntry = {
		Id = item.Id,
		Category = item.Category,
		Icon = item.Icon,
		Color = item.Color,
		Title = item.Id,
		Subtitle = "",
		Price = 0,
		PriceKind = priceKind,
		PriceText = "",
		State = "Available",
		Options = {},
	}

	local function setPrice(price: number)
		entry.Price = price
		entry.PriceText = priceText(price, priceKind)
		entry.State = if balance >= price then "Available" else "Unaffordable"
	end

	if item.Action == "PowerUpgrade" then
		local lvl = s.PowerUpgradeLevel or 1
		local cost = GameConfig.GetPowerUpgradeCost(lvl)
		local gain = GameConfig.GetPowerUpgradeBonus(lvl + 1) - GameConfig.GetPowerUpgradeBonus(lvl)
		entry.Title = `Upgrade Power (Lv.{lvl})`
		entry.Subtitle = `+{GameConfig.FormatNumber(gain)} Throw Power`
		setPrice(cost)
		entry.Options = { option(1, "Buy", cost, balance), option("max", "Buy Max", cost, balance) }
	elseif item.Action == "PullUpTier" then
		local nextTier = GameConfig.PullUpTiers[(s.PullUpTier or 1) + 1]
		if nextTier then
			entry.Title = nextTier.Name
			entry.Subtitle = `+{nextTier.XPPerRep} XP/rep, {nextTier.SpeedMult}x rep speed`
			setPrice(nextTier.Cost)
			entry.Options = { option(1, "Buy", nextTier.Cost, balance) }
		else
			local cur = GameConfig.PullUpTiers[#GameConfig.PullUpTiers]
			entry.Title = cur.Name
			entry.Subtitle = "Pull-Up Bar is at MAX TIER"
			entry.State = "Maxed"
			entry.PriceText = "MAX"
		end
	elseif item.Action == "BaitTier" then
		local curTier = GameConfig.BaitTiers[s.BaitTier or 1] or GameConfig.BaitTiers[1]
		local nextTier = GameConfig.BaitTiers[(s.BaitTier or 1) + 1]
		if nextTier then
			entry.Title = nextTier.Name
			entry.Subtitle = `Bait Luck {curTier.LuckMultiplier}x -> {nextTier.LuckMultiplier}x`
			setPrice(nextTier.Cost)
			entry.Options = { option(1, "Buy", nextTier.Cost, balance) }
		else
			entry.Title = curTier.Name
			entry.Subtitle = `Jelly Bait is at MAX TIER ({curTier.LuckMultiplier}x Luck)`
			entry.State = "Maxed"
			entry.PriceText = "MAX"
		end
	elseif item.Action == "SlotExpansion" then
		local curMax = ProgressionLogic.GetEffectiveMaxSlimes(s)
		local nextSlot = curMax + 1
		local cost = GameConfig.GetNextSlotGemCost(curMax)
		if curMax >= GameConfig.Slots.ExpandedMaxSlimes or not cost then
			entry.Title = `Plot Slots ({GameConfig.Slots.ExpandedMaxSlimes}/{GameConfig.Slots.ExpandedMaxSlimes})`
			entry.Subtitle = `All {GameConfig.Slots.ExpandedMaxSlimes} slime slots unlocked`
			entry.State = "Maxed"
			entry.PriceText = "MAX"
		else
			entry.Title = `Unlock Plot Slot #{nextSlot}`
			entry.Subtitle = `Plot capacity {curMax} -> {nextSlot} (or +4 Slots Robux Pass)`
			setPrice(cost)
			entry.Options = { option(1, "Unlock", cost, balance) }
		end
	elseif item.Action == "MultiplierTier" then
		local trackId = (item.Args.TrackId or "") :: GameConfig.MultiplierTrackId
		local track = GameConfig.MultiplierTracksById[trackId]
		if track then
			local nextTier, curMult = ProgressionLogic.GetNextMultiplierTier(s, trackId)
			if nextTier then
				entry.Title = nextTier.Name
				entry.Subtitle = `{curMult}x -> {nextTier.Multiplier}x {track.ShortStat}`
				setPrice(nextTier.GemCost)
				entry.Options = { option(1, "Upgrade", nextTier.GemCost, balance) }
			else
				local top = track.Tiers[#track.Tiers]
				entry.Title = top.Name
				entry.Subtitle = `{track.ShortStat} at MAX ({top.Multiplier}x)`
				entry.State = "Maxed"
				entry.PriceText = "MAX"
			end
		end
	elseif item.Action == "Boost" then
		local boostId = item.Args.BoostId or ""
		local boost = GameConfig.ShopBoosts[boostId]
		if boost then
			entry.Title = boost.Name
			entry.Subtitle = boost.Description
			local owned = (s.OwnedBoosts and s.OwnedBoosts[boostId] == true)
				or (boostId == "auto_throw" and ProgressionLogic.OwnsAutoThrow(s))
			if owned then
				entry.State = "Owned"
				entry.PriceText = "OWNED"
			else
				setPrice(boost.Cost)
				entry.Options = { option(1, "Buy", boost.Cost, balance) }
			end
		end
	elseif item.Action == "Egg" then
		local egg = GameConfig.ShopEggsById[item.Args.EggId or ""]
		if egg then
			entry.Title = egg.Name
			entry.Subtitle = egg.Tag
			entry.Price = egg.Buy1Robux
			entry.PriceText = priceText(egg.Buy1Robux, "Robux")
			entry.State = "Available"
			entry.Options = {
				{ Quantity = 1, Label = `Buy x1 ({priceText(egg.Buy1Robux, "Robux")})`, Price = egg.Buy1Robux, CanAfford = true },
				{ Quantity = 3, Label = `Buy x3 ({priceText(egg.Buy3Robux, "Robux")})`, Price = egg.Buy3Robux, CanAfford = true },
			}
		end
	elseif item.Action == "FreeGift" then
		entry.Title = GameConfig.FreeGift.Title
		entry.Subtitle = GameConfig.FreeGift.Subtitle
		if s.ClaimedFreeGift then
			entry.State = "Claimed"
			entry.PriceText = "CLAIMED"
		else
			setPrice(0)
			entry.Options = { option(1, "CLAIM!", 0, balance) }
		end
	end

	return entry
end

-- Everything the shop UI needs to render, in catalog order. Pure: safe on client and server.
function ProgressionLogic.GetShopListing(state: ShopStateInput): { ShopListingEntry }
	local list = {}
	for _, item in GameConfig.ShopCatalog do
		table.insert(list, buildListingEntry(item, state))
	end
	return list
end

function ProgressionLogic.GetShopListingEntry(state: ShopStateInput, itemId: string): ShopListingEntry?
	local item = GameConfig.ShopCatalogById[itemId]
	return if item then buildListingEntry(item, state) else nil
end

local MAX_BULK_BUYS = 200

-- The single purchase entry point. Validates the item id + quantity, then dispatches to the
-- existing reducers (PurchasePowerUpgrade, HatchShopEgg, ...). Returns (ok, message, result):
-- result is the hatched/claimed SlimeInstances for eggs/gift, or the number of upgrades bought.
function ProgressionLogic.Purchase(profile: PlayerProfile, itemId: string, quantity: ShopQuantity?): (boolean, string, any)
	local item = GameConfig.ShopCatalogById[itemId]
	if not item then
		return false, "Unknown shop item", nil
	end
	local qty: ShopQuantity = if quantity == nil then 1 else quantity

	if item.Action == "PowerUpgrade" then
		if qty == 1 then
			local ok, msg = ProgressionLogic.PurchasePowerUpgrade(profile)
			return ok, msg, if ok then 1 else 0
		elseif qty == "max" then
			local bought = 0
			local lastMsg = ""
			while bought < MAX_BULK_BUYS do
				local ok, msg = ProgressionLogic.PurchasePowerUpgrade(profile)
				if not ok then
					lastMsg = msg
					break
				end
				bought += 1
			end
			if bought == 0 then
				return false, lastMsg, 0
			end
			return true, `Bought {bought}x Power Upgrades (Lv.{profile.PowerUpgradeLevel})!`, bought
		end
	elseif item.Action == "Egg" or item.PriceKind == "Robux" then
		return false, "Featured Eggs can only be purchased with Robux!", nil
	elseif qty == 1 then
		if item.Action == "PullUpTier" then
			local ok, msg = ProgressionLogic.PurchasePullUpTier(profile)
			return ok, msg, nil
		elseif item.Action == "BaitTier" then
			local ok, msg = ProgressionLogic.PurchaseBaitTier(profile)
			return ok, msg, nil
		elseif item.Action == "SlotExpansion" then
			local ok, msg = ProgressionLogic.PurchaseSlotExpansion(profile, item.PriceKind)
			return ok, msg, nil
		elseif item.Action == "MultiplierTier" then
			local trackId = (item.Args.TrackId or "") :: GameConfig.MultiplierTrackId
			local ok, msg = ProgressionLogic.PurchaseMultiplierTier(profile, trackId)
			return ok, msg, nil
		elseif item.Action == "Boost" then
			local ok, msg = ProgressionLogic.PurchaseShopBoost(profile, item.Args.BoostId or "")
			return ok, msg, nil
		elseif item.Action == "FreeGift" then
			local ok, msg, inst = ProgressionLogic.ClaimFreeGiftSlime(profile)
			return ok, msg, if inst then { inst } else nil
		end
	end

	return false, "Invalid quantity for this item", nil
end

function ProgressionLogic.TickPassiveIncome(profile: PlayerProfile, dtSeconds: number): number
	local rate = ProgressionLogic.GetIncomePerSecond(profile)
	local added = math.max(0, rate * dtSeconds)
	profile.PendingIncome += added
	return profile.PendingIncome
end

function ProgressionLogic.CollectPendingIncome(profile: PlayerProfile): number
	local wholeCash = math.floor(profile.PendingIncome)
	if wholeCash <= 0 then
		return 0
	end
	profile.PendingIncome -= wholeCash
	profile.Cash += wholeCash
	QuestLogic.RecordEvent(profile, "EarnCash", wholeCash)
	return wholeCash
end

function ProgressionLogic.EquipSlime(profile: PlayerProfile, slimeId: string): (boolean, string)
	if not GameConfig.SlimesById[slimeId] then
		return false, "Unknown slime ID"
	end
	local owns = false
	for _, id in profile.OwnedSlimes do
		if id == slimeId then
			owns = true
			break
		end
	end
	if not owns then
		return false, "You don't own that slime yet"
	end
	profile.EquippedSlimeId = slimeId
	return true, `Equipped {GameConfig.SlimesById[slimeId].Name}!`
end

function ProgressionLogic.PlaceBestSlimes(profile: PlayerProfile)
	-- Collect all instances from slots + unplaced, or rebuild from OwnedSlimes if legacy test edited OwnedSlimes directly
	local allInstances: { SlimeInstance } = {}
	for _, inst in profile.UnplacedSlimes do
		table.insert(allInstances, inst)
	end
	for _, inst in profile.PlacedSlimesBySlot do
		table.insert(allInstances, inst)
	end

	if #allInstances < #profile.OwnedSlimes then
		allInstances = {}
		for _, slimeId in profile.OwnedSlimes do
			table.insert(allInstances, makeSlimeInstance(profile, slimeId, "NORMAL"))
		end
	end

	table.sort(allInstances, function(a, b)
		if a.IncomePerSec == b.IncomePerSec then
			return a.SlimeId < b.SlimeId
		end
		return a.IncomePerSec > b.IncomePerSec
	end)

	profile.PlacedSlimesBySlot = {}
	profile.UnplacedSlimes = {}

	local placedCount = 0
	local maxSlots = ProgressionLogic.GetEffectiveMaxSlimes(profile)
	for i, inst in allInstances do
		if i <= maxSlots then
			profile.PlacedSlimesBySlot[i] = inst
			placedCount += 1
		else
			table.insert(profile.UnplacedSlimes, inst)
		end
	end
	syncLegacyArrays(profile)
	if placedCount > 0 then
		QuestLogic.RecordEvent(profile, "PlaceSlime", placedCount)
	end
end

function ProgressionLogic.GetCurrentObjective(
	profile: PlayerProfile,
	hasSelectedHotbarSlime: boolean
): { Text: string, TargetType: "ThrowLine" | "Hotbar" | "PlotSlot" | "PullUpBar" }
	if #profile.UnplacedSlimes > 0 then
		local freeSlotExists = false
		local maxSlots = ProgressionLogic.GetEffectiveMaxSlimes(profile)
		for s = 1, maxSlots do
			if not profile.PlacedSlimesBySlot[s] then
				freeSlotExists = true
				break
			end
		end
		if freeSlotExists then
			if not hasSelectedHotbarSlime then
				return { Text = "Pick your slime", TargetType = "Hotbar" }
			else
				return { Text = "Place your slime", TargetType = "PlotSlot" }
			end
		end
	end

	if profile.TotalThrows == 0 then
		return { Text = "Walk to the Throw Line!", TargetType = "ThrowLine" }
	elseif profile.TotalPullUps < 3 then
		return { Text = "Train at your pull-up bar!", TargetType = "PullUpBar" }
	else
		return { Text = "Throw bait to catch rarer slimes!", TargetType = "ThrowLine" }
	end
end

return ProgressionLogic
