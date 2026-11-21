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
	StrengthLevel: number, -- pull-up level; each level up = +GameConfig.Training.PowerPerLevel Throw Power
	TrainingXP: number, -- XP toward the next StrengthLevel
	BaitTier: number, -- index into GameConfig.BaitTiers
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
		StrengthLevel = 1,
		TrainingXP = 0,
		BaitTier = 1,
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

-- One pull-up rep: adds Training XP (bar tier XPPerRep x x2 boost x trail x repMultiplier), then levels
-- up as many times as the XP covers. Each level up adds GameConfig.Training.PowerPerLevel Throw Power.
-- repMultiplier is GameConfig.Training.BonusRepMultiplier for a clicked Bonus Rep.
function ProgressionLogic.ApplyPullUpRep(profile: PlayerProfile, repMultiplier: number?): PullUpRepResult
	local tierDef = GameConfig.PullUpTiers[profile.PullUpTier] or GameConfig.PullUpTiers[1]
	local xpBoost = if profile.OwnedBoosts.double_power then 2.0 else 1.0
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
		return false, `Need $${GameConfig.FormatNumber(nextTier.Cost)} Cash`
	end
	profile.Cash -= nextTier.Cost
	profile.BaitTier += 1
	return true, `Unlocked {nextTier.Name} ({nextTier.LuckMultiplier}x Luck)!`
end

function ProgressionLogic.GetBaitDef(profile: { BaitTier: number? }): GameConfig.BaitTierDef
	return GameConfig.BaitTiers[profile.BaitTier or 1] or GameConfig.BaitTiers[1]
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
	return true, `Unlocked {nextTier.Name} (+{nextTier.XPPerRep} XP/rep)!`
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
	PriceText: string,
	State: ShopState,
	Options: { ShopOption },
}

-- Anything with these fields works: the server PlayerProfile OR the client's synced state table.
export type ShopStateInput = {
	Cash: number?,
	PowerUpgradeLevel: number?,
	PullUpTier: number?,
	BaitTier: number?,
	MaxSlimes: number?,
	OwnedBoosts: { [string]: boolean }?,
	ClaimedFreeGift: boolean?,
}

local function priceText(price: number): string
	return if price <= 0 then "FREE" else `${GameConfig.FormatNumber(price)}`
end

local function option(quantity: ShopQuantity, label: string, price: number, cash: number): ShopOption
	return { Quantity = quantity, Label = label, Price = price, CanAfford = cash >= price }
end

local function buildListingEntry(item: GameConfig.ShopCatalogItem, s: ShopStateInput): ShopListingEntry
	local cash = s.Cash or 0
	local entry: ShopListingEntry = {
		Id = item.Id,
		Category = item.Category,
		Icon = item.Icon,
		Color = item.Color,
		Title = item.Id,
		Subtitle = "",
		Price = 0,
		PriceText = "",
		State = "Available",
		Options = {},
	}

	local function setPrice(price: number)
		entry.Price = price
		entry.PriceText = priceText(price)
		entry.State = if cash >= price then "Available" else "Unaffordable"
	end

	if item.Action == "PowerUpgrade" then
		local lvl = s.PowerUpgradeLevel or 1
		local cost = GameConfig.GetPowerUpgradeCost(lvl)
		local gain = GameConfig.GetPowerUpgradeBonus(lvl + 1) - GameConfig.GetPowerUpgradeBonus(lvl)
		entry.Title = `Upgrade Power (Lv.{lvl})`
		entry.Subtitle = `+{GameConfig.FormatNumber(gain)} Throw Power`
		setPrice(cost)
		entry.Options = { option(1, "Buy", cost, cash), option("max", "Buy Max", cost, cash) }
	elseif item.Action == "PullUpTier" then
		local nextTier = GameConfig.PullUpTiers[(s.PullUpTier or 1) + 1]
		if nextTier then
			entry.Title = nextTier.Name
			entry.Subtitle = `+{nextTier.XPPerRep} XP/rep, {nextTier.SpeedMult}x rep speed`
			setPrice(nextTier.Cost)
			entry.Options = { option(1, "Buy", nextTier.Cost, cash) }
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
			entry.Options = { option(1, "Buy", nextTier.Cost, cash) }
		else
			entry.Title = curTier.Name
			entry.Subtitle = `Jelly Bait is at MAX TIER ({curTier.LuckMultiplier}x Luck)`
			entry.State = "Maxed"
			entry.PriceText = "MAX"
		end
	elseif item.Action == "SlotExpansion" then
		local cost = GameConfig.Slots.ExpansionCost
		entry.Title = `+{GameConfig.Slots.ExpandedMaxSlimes - GameConfig.Slots.InitialMaxSlimes} Slime Slots`
		entry.Subtitle = `Plot capacity {GameConfig.Slots.InitialMaxSlimes} -> {GameConfig.Slots.ExpandedMaxSlimes}`
		if (s.MaxSlimes or GameConfig.Slots.InitialMaxSlimes) >= GameConfig.Slots.ExpandedMaxSlimes then
			entry.State = "Maxed"
			entry.PriceText = "MAX"
		else
			setPrice(cost)
			entry.Options = { option(1, "Buy", cost, cash) }
		end
	elseif item.Action == "Boost" then
		local boostId = item.Args.BoostId or ""
		local boost = (GameConfig.ShopBoosts :: any)[boostId]
		if boost then
			entry.Title = boost.Name
			entry.Subtitle = boost.Description
			if s.OwnedBoosts and s.OwnedBoosts[boostId] then
				entry.State = "Owned"
				entry.PriceText = "OWNED"
			else
				setPrice(boost.Cost)
				entry.Options = { option(1, "Buy", boost.Cost, cash) }
			end
		end
	elseif item.Action == "Egg" then
		local egg = GameConfig.ShopEggsById[item.Args.EggId or ""]
		if egg then
			entry.Title = egg.Name
			entry.Subtitle = egg.Tag
			setPrice(egg.Buy1Cost)
			entry.Options = {
				option(1, `Buy x1 ({priceText(egg.Buy1Cost)})`, egg.Buy1Cost, cash),
				option(3, `Buy x3 ({priceText(egg.Buy3Cost)})`, egg.Buy3Cost, cash),
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
			entry.Options = { option(1, "CLAIM!", 0, cash) }
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
	elseif item.Action == "Egg" then
		if qty == 1 or qty == 3 then
			local ok, msg, hatched = ProgressionLogic.HatchShopEgg(profile, item.Args.EggId or "", qty :: number, nil)
			return ok, msg, hatched
		end
	elseif qty == 1 then
		if item.Action == "PullUpTier" then
			local ok, msg = ProgressionLogic.PurchasePullUpTier(profile)
			return ok, msg, nil
		elseif item.Action == "BaitTier" then
			local ok, msg = ProgressionLogic.PurchaseBaitTier(profile)
			return ok, msg, nil
		elseif item.Action == "SlotExpansion" then
			local ok, msg = ProgressionLogic.PurchaseSlotExpansion(profile)
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
