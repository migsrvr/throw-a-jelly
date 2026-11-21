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

local function syncLegacyArrays(profile: PlayerProfile)
	local placedIds = {}
	for slot = 1, profile.MaxSlimes do
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
	}
	local starter = makeSlimeInstance(profile, "meadow_sprout", "NORMAL")
	profile.PlacedSlimesBySlot[1] = starter
	syncLegacyArrays(profile)
	return profile
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
	for slot = 1, profile.MaxSlimes do
		local inst = profile.PlacedSlimesBySlot[slot]
		if inst then
			hasPlacedInstances = true
			total += inst.IncomePerSec
		end
	end

	-- Fallback if legacy test mutated PlacedSlimes directly
	if not hasPlacedInstances and #profile.PlacedSlimes > 0 then
		local count = math.min(#profile.PlacedSlimes, profile.MaxSlimes)
		for i = 1, count do
			local def = GameConfig.SlimesById[profile.PlacedSlimes[i]]
			if def then
				total += def.IncomePerSec
			end
		end
	end

	local cashBoost = if profile.OwnedBoosts.double_cash then 2.0 else 1.0
	local trailMult = ProgressionLogic.GetTrailMultiplier(profile, "Cash")
	return math.floor(total * cashBoost * trailMult + 0.5)
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

function ProgressionLogic.ApplyPullUpRep(profile: PlayerProfile): number
	local tierDef = GameConfig.PullUpTiers[profile.PullUpTier] or GameConfig.PullUpTiers[1]
	local xpBoost = if profile.OwnedBoosts.double_power then 2.0 else 1.0
	local trailMult = ProgressionLogic.GetTrailMultiplier(profile, "XP")
	local gained = math.max(1, math.floor(tierDef.XPPerRep * xpBoost * trailMult + 0.5))
	profile.BaseThrowPower += gained
	profile.TotalPullUps += 1
	return gained
end

function ProgressionLogic.PurchasePowerUpgrade(profile: PlayerProfile): (boolean, string)
	local cost = GameConfig.GetPowerUpgradeCost(profile.PowerUpgradeLevel)
	if profile.Cash < cost then
		return false, `Need $${GameConfig.FormatNumber(cost)} Cash`
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
		return false, `Need $${GameConfig.FormatNumber(nextTier.Cost)} Cash`
	end
	profile.Cash -= nextTier.Cost
	profile.PullUpTier = nextTierIndex
	return true, `Unlocked {nextTier.Name} (+{nextTier.XPPerRep} Power/rep)!`
end

function ProgressionLogic.PurchaseSlotExpansion(profile: PlayerProfile): (boolean, string)
	if profile.MaxSlimes >= GameConfig.Slots.ExpandedMaxSlimes then
		return false, "All 12 Slime Slots are already unlocked!"
	end
	local cost = GameConfig.Slots.ExpansionCost
	if profile.Cash < cost then
		return false, `Need $${GameConfig.FormatNumber(cost)} Cash`
	end
	profile.Cash -= cost
	profile.MaxSlimes = GameConfig.Slots.ExpandedMaxSlimes
	return true, "Unlocked +4 Slime Slots (12 Total)!"
end

function ProgressionLogic.RollSlimeForZone(zoneIndex: number, unitRandom: number, luckMultiplier: number?): GameConfig.SlimeDef
	local pool = GameConfig.SlimesByZone[zoneIndex] or GameConfig.SlimesByZone[1]
	local luck = math.max(1.0, luckMultiplier or 1.0)

	local weights = {}
	local totalWeight = 0
	for i, slime in pool do
		-- Higher luck boosts rarer slimes in the zone pool
		local w = if i == 1 then slime.DropWeight else slime.DropWeight * (luck ^ (i - 1))
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

function ProgressionLogic.RollMutation(unitRandom: number, luckMultiplier: number?): GameConfig.MutationDef
	local luck = math.max(1.0, luckMultiplier or 1.0)
	local weights = {}
	local totalWeight = 0
	for i, mut in GameConfig.Mutations do
		local w = if mut.Id == "NORMAL" then mut.Weight else mut.Weight * luck
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
	local cashBoost = if profile.OwnedBoosts.double_cash then 2.0 else 1.0
	local trailMult = ProgressionLogic.GetTrailMultiplier(profile, "Cash")
	local cashEarned = math.max(5, math.floor(cleanDist * zone.CashPerStud * cashBoost * trailMult + 0.5))
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

	local instance = makeSlimeInstance(profile, caughtDef.Id, mutDef.Id)
	local oddsOneInX = math.max(1, math.floor(caughtDef.BaseOdds * mutDef.OddsMultiplier + 0.5))
	local isSuperLucky = (oddsOneInX >= 10) or (mutDef.Id ~= "NORMAL")

	local autoPlaced = false
	if putInHotbarOnly == true then
		table.insert(profile.UnplacedSlimes, instance)
	else
		-- Find first free slot up to profile.MaxSlimes
		local freeSlot: number? = nil
		for slot = 1, profile.MaxSlimes do
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
	}
end

function ProgressionLogic.PlaceSlimeAtSlot(profile: PlayerProfile, slimeUid: string, slotIndex: number): (boolean, string)
	local slot = math.floor(slotIndex)
	if slot < 1 or slot > profile.MaxSlimes then
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
	return true, `Placed {foundInst.Name} (+$${GameConfig.FormatNumber(foundInst.IncomePerSec)}/s)!`
end

function ProgressionLogic.PickupSlimeFromSlot(profile: PlayerProfile, slotIndex: number): (boolean, string)
	local slot = math.floor(slotIndex)
	local existing = profile.PlacedSlimesBySlot[slot]
	if not existing then
		return false, "Slot is empty"
	end
	profile.PlacedSlimesBySlot[slot] = nil
	table.insert(profile.UnplacedSlimes, existing)
	syncLegacyArrays(profile)
	return true, `Picked up {existing.Name} into your hotbar!`
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
	return true, `Claimed free {inst.Mutation} {inst.Name} (+$${inst.IncomePerSec}/s)!`, inst
end

function ProgressionLogic.PurchaseShopBoost(profile: PlayerProfile, boostId: string): (boolean, string)
	local boost = (GameConfig.ShopBoosts :: any)[boostId]
	if not boost then
		return false, "Unknown boost"
	end
	if profile.OwnedBoosts[boostId] then
		return false, `You already own {boost.Name}!`
	end
	if profile.Cash < boost.Cost then
		return false, `Need $${GameConfig.FormatNumber(boost.Cost)} Cash`
	end
	profile.Cash -= boost.Cost
	profile.OwnedBoosts[boostId] = true
	return true, `Unlocked {boost.Name}!`
end

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
	local cost = if num == 3 then egg.Buy3Cost else egg.Buy1Cost
	if profile.Cash < cost then
		return false, `Need $${GameConfig.FormatNumber(cost)} Cash`, {}
	end
	profile.Cash -= cost

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
	local first = hatched[1]
	local summary = if num == 1
		then `Hatched {first.Mutation ~= "NORMAL" and (first.Mutation .. " ") or ""}{first.Name} (+$${first.IncomePerSec}/s)!`
		else `Hatched {num}x Slimes from {egg.Name}!`
	return true, summary, hatched
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

	for i, inst in allInstances do
		if i <= profile.MaxSlimes then
			profile.PlacedSlimesBySlot[i] = inst
		else
			table.insert(profile.UnplacedSlimes, inst)
		end
	end
	syncLegacyArrays(profile)
end

function ProgressionLogic.GetCurrentObjective(
	profile: PlayerProfile,
	hasSelectedHotbarSlime: boolean
): { Text: string, TargetType: "ThrowLine" | "Hotbar" | "PlotSlot" | "PullUpBar" }
	if #profile.UnplacedSlimes > 0 then
		local freeSlotExists = false
		for s = 1, profile.MaxSlimes do
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
