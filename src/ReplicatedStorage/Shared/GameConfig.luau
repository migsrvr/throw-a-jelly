--!strict
--[[
	GameConfig.luau
	Central configuration for Zones, Slimes, Mutations, 9-Segment Vertical Throw Meter,
	Zone Index Trail Bonuses, Shop Featured Eggs & Boosts, Pull-Up Training Tiers,
	Throw Power Upgrades, Plot Slot Expansion, and Physics tuning.
]]

local GameConfig = {}

export type RGB = { number }

export type ZoneDef = {
	Index: number,
	Id: string,
	Name: string,
	Emoji: string,
	StartZ: number,
	EndZ: number,
	FloorY: number,
	RequiredThrowPower: number,
	ClearHalfWidth: number,
	CashPerStud: number,
	ThemeColor: RGB,
	TrailName: string,
	TrailBonusText: string,
	TrailBonusType: "XP" | "Cash" | "Power" | "All",
	TrailMultiplier: number,
}

export type SlimeDef = {
	Id: string,
	Name: string,
	ShortWord: string,
	ZoneIndex: number,
	Rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic",
	RarityRank: number,
	DropWeight: number,
	BaseOdds: number,
	Color: RGB,
	CoreColor: RGB,
	Scale: number,
	IncomePerSec: number,
	ThrowBonus: number,
	Weight: number,
	-- How the slime moves in the catch cutscene (SlimeMotion). nil = "Hop".
	Motion: SlimeMotionStyle?,
}

export type SlimeMotionStyle = "Hop" | "Fly" | "Slide" | "Waddle"

export type MutationDef = {
	Id: "NORMAL" | "EMERALD" | "GOLDEN" | "CRYSTAL" | "RAINBOW",
	Name: string,
	IncomeMultiplier: number,
	Weight: number,
	OddsMultiplier: number,
	Color: RGB,
}

export type MeterSegmentDef = {
	Index: number,
	Color: RGB,
	QualityLabel: string,
	ChargeRatio: number,
	BonusPower: number,
	LuckMultiplier: number,
	IsPerfect: boolean?, -- top band: "PERFECT!" callout
}

export type BaitTierDef = {
	Tier: number,
	Name: string,
	Cost: number,
	LuckMultiplier: number, -- multiplies slime rarity & mutation luck on every throw
	Color: RGB,
}

export type PullUpTierDef = {
	Tier: number,
	Name: string,
	Cost: number,
	XPPerRep: number,
	SpeedMult: number, -- multiplies pull-up rep speed (see GameConfig.PullUp)
}

export type ShopAction =
	"PowerUpgrade"
	| "PullUpTier"
	| "BaitTier"
	| "SlotExpansion"
	| "Boost"
	| "MultiplierTier"
	| "Egg"
	| "FreeGift"

-- Which wallet a shop item is paid from. Featured Eggs use "Robux" (Developer Products).
export type PriceKind = "Cash" | "Gems" | "Robux"

export type MultiplierTrackId = "gems" | "power" | "luck" | "money"

export type MultiplierTierDef = {
	Tier: number,
	Multiplier: number,
	BoostId: string,
	PassId: string,
	Name: string,
	Description: string,
	GemCost: number,
	RobuxPrice: number,
	Color: RGB,
}

export type MultiplierTrackDef = {
	Id: MultiplierTrackId,
	Name: string,
	ShortStat: string,
	Icon: string,
	Color: RGB,
	Tiers: { MultiplierTierDef },
}

export type ShopCatalogItem = {
	Id: string,
	Category: "Upgrade" | "Boost" | "Egg" | "Gift" | "Gem",
	Action: ShopAction,
	Args: { BoostId: string?, EggId: string?, TrackId: string? },
	Icon: string,
	Color: RGB,
	PriceKind: PriceKind,
}

export type ShopBoostDef = {
	Id: string,
	Name: string,
	Description: string,
	Cost: number, -- in the boost's PriceKind currency
	PriceKind: PriceKind,
	Color: RGB,
	LuckMultiplier: number?, -- luck boosts: multiplies every throw's luck
	TrackId: MultiplierTrackId?,
	Tier: number?,
	Multiplier: number?,
}

export type ShopEggItem = {
	SlimeId: string,
	Mutation: "NORMAL" | "EMERALD" | "GOLDEN" | "CRYSTAL" | "RAINBOW",
	ChancePercent: number,
	BonusLabel: string,
}

export type ShopEggDef = {
	Id: string,
	Name: string,
	Tag: string,
	Buy1Robux: number,
	Buy3Robux: number,
	Buy1ProductId: number,
	Buy3ProductId: number,
	AccentColor: RGB,
	Items: { ShopEggItem },
}

export type QuestEventType =
	"Throw"
	| "CatchRarity"
	| "ReachZone"
	| "PullUpRep"
	| "BonusRep"
	| "PerfectThrow"
	| "PlaceSlime"
	| "HatchEgg"
	| "BuyBait"
	| "Discover"
	| "EarnCash"

export type QuestReward = {
	Cash: number?,
	Gems: number?,
}

export type QuestDef = {
	Id: string,
	Title: string,
	Event: QuestEventType,
	Target: number,
	MinRarityRank: number?,
	MinZone: number?,
	MinBaitTier: number?,
	Reward: QuestReward,
}

export type RobuxGemPackDef = {
	Id: string,
	Name: string,
	Gems: number,
	RobuxPrice: number,
	ProductId: number,
	Icon: string,
	Color: RGB,
	BonusTag: string?,
}

export type RobuxPassDef = {
	Id: string,
	Name: string,
	Description: string,
	RobuxPrice: number,
	PassId: number,
	Icon: string,
	Color: RGB,
	Category: ("Core" | "Luck" | "Gems" | "Power")?,
	TrackId: MultiplierTrackId?,
	Tier: number?,
	LuckMultiplier: number?,
	CashMultiplier: number?,
	GemMultiplier: number?,
	PowerMultiplier: number?,
	UnlocksExtraSlots: boolean?,
	UnlocksAutoThrow: boolean?,
	ChatTag: string?,
}

GameConfig.Hub = {
	FloorY = 30.2,
	ThrowLineZ = -3.6,
	ThrowLineMinX = -62.0,
	ThrowLineMaxX = 62.0,
	LaneMinZ = 0.0,
	LaneMaxZ = 1680.0,
	ClearHalfWidth = 22.0,
}

GameConfig.Physics = {
	Gravity = 140.0,
	FixedDt = 1 / 60,
	MaxSimSeconds = 12.0,
	Restitution = 0.28,
	WallRestitution = 0.72,
	GateRestitution = 0.45,
	BounceThresholdVy = 8.0,
	MaxBounces = 2,
	BounceHorizDamping = 0.18,
	RollingFriction = 200.0,
	AirDrag = 0.008,
	StopSpeedThreshold = 1.5,
	MinPitchDeg = 18.0,
	MaxPitchDeg = 55.0,
	DefaultPitchDeg = 40.0,
	MaxYawDeg = 18.0,
	BaseLaunchSpeed = 38.0,
	PowerSpeedScale = 14.5,
	PowerExponent = 0.42,
	MeterChargeMin = 0.60, -- Band 1 minimum charge ratio (Band 9 PERFECT = 1.00)
	-- Calibrated ThrowPower -> Max LaunchSpeed knots aligned to Zone 1..7 StartZ/EndZ boundaries
	-- with solid vertical cliff collisions and sticky jelly bounces so throws land directly on target terrain.
	PowerSpeedKnots = {
		{ Power = 1, Speed = 91.0 },
		{ Power = 5, Speed = 110.0 },
		{ Power = 49, Speed = 164.5 },
		{ Power = 50, Speed = 182.5 },
		{ Power = 249, Speed = 245.5 },
		{ Power = 250, Speed = 259.0 },
		{ Power = 999, Speed = 307.5 },
		{ Power = 1000, Speed = 320.5 },
		{ Power = 4999, Speed = 358.5 },
		{ Power = 5000, Speed = 374.0 },
		{ Power = 19999, Speed = 405.0 },
		{ Power = 20000, Speed = 413.0 }, -- Desert Dunes gate
		{ Power = 79999, Speed = 444.0 },
		{ Power = 80000, Speed = 452.0 }, -- Acid Swamp gate
		{ Power = 400000, Speed = 478.0 },
	},
}

-- Plot Slime Slots: new players strictly cap at 8 slots; Slots 9..12 are locked behind
-- 1-by-1 high-value Gem unlocks (8+ hr F2P grind) OR the "+4 Plot Slots" Robux Game Pass.
GameConfig.Slots = {
	InitialMaxSlimes = 8,
	ExpandedMaxSlimes = 12,
	TotalSlotParts = 12,
	SlotUnlockGemCosts = {
		[9] = 1500,
		[10] = 2500,
		[11] = 4000,
		[12] = 6000,
	} :: { [number]: number },
}

function GameConfig.GetNextSlotGemCost(currentMaxSlimes: number): number?
	local nextSlot = math.floor(currentMaxSlimes) + 1
	return GameConfig.Slots.SlotUnlockGemCosts[nextSlot]
end

GameConfig.Sell = {
	IncomeSecondsMultiplier = 15, -- sells for 15 seconds of that slime's IncomePerSec (mutations included)
	MinSellPrice = 10,
}

-- Gems: the premium currency (see docs/docs/ECONOMY-BASELINE.md).
-- Calibrated so active F2P players accumulate ~1,250 Gems in their first 8 hours, making the
-- cheapest high-value Gem unlock (1,500+ Gems) an authentic 8+ hour grind OR a Robux shortcut.
GameConfig.Gems = {
	-- Paid once each, the first time the Slime Index reaches this many discovered slimes (total 177 base)
	IndexMilestones = {
		{ Discovered = 3, Gems = 5 },
		{ Discovered = 6, Gems = 12 },
		{ Discovered = 9, Gems = 25 },
		{ Discovered = 12, Gems = 45 },
		{ Discovered = 15, Gems = 90 },
		{ Discovered = 21, Gems = 110 },
		{ Discovered = 27, Gems = 150 },
		{ Discovered = 33, Gems = 200 },
		{ Discovered = 42, Gems = 350 },
	},
	-- Zone index -> base Gems paid the first time a throw lands in that zone (total 139 base)
	FirstZoneReach = { 3, 8, 18, 35, 75, 120, 180 },
	-- Daily login streak: day 1..7 base reward; day 8+ keeps paying the last value. Missing a day resets to day 1.
	DailyRewards = { 5, 8, 12, 16, 22, 30, 50 },
	SecondsPerDay = 86400, -- days are counted in UTC from os.time()
	-- Repeatable catch drops from throws (eggs don't pay, so Cash can't be turned into Gems)
	RarityDrops = { Mythic = 1 } :: { [string]: number },
	MutationDrops = { CRYSTAL = 1, RAINBOW = 2 } :: { [string]: number },
}

-- Auto-Throw (bought with Gems): throws by itself whenever you stand idle at the throw line.
-- Uses a server-side shuffled 5-throw bag: 3 PERFECT (Band 9) + 2 GOOD (Band 8) every 5 throws.
GameConfig.AutoThrow = {
	MeterRatio = 0.82, -- fallback GOOD band ratio (Band 8, 1.48x luck)
	PerfectMeterRatio = 1.0, -- Band 9 (PERFECT!, 1.75x luck, 100% reach)
	GoodMeterRatio = 0.82, -- Band 8 (GOOD!, 1.48x luck, ~92% reach)
	BagPerfectCount = 3,
	BagGoodCount = 2,
	IdleDelaySeconds = 0.8, -- wait this long at the throw line before each auto throw
}

-- Saving (DataStoreService). Bump SchemaVersion when the saved shape changes and teach
-- ProfileSerializer.Deserialize to read the older version.
-- Welcome Back (offline income). Design decisions, tune freely: players earn Rate x their income for the time
-- they were away, up to MaxAwaySeconds, and only if they were gone at least MinAwaySeconds.
GameConfig.Offline = {
	MinAwaySeconds = 120,
	MaxAwaySeconds = 4 * 3600,
	Rate = 0.5,
	DoubleProductId = 0, -- developer product for "2X + Robux 25"; 0 = coming soon
	DoubleRobux = 25,
}

GameConfig.Save = {
	DataStoreName = "PlayerProfile_v1",
	KeyPrefix = "Player_",
	SchemaVersion = 1,
	AutosaveSeconds = 60,
	LoadRetries = 3,
	RetryDelaySeconds = 1.5,
}

-- 9-Segment Vertical Throw Meter baseline (bottom segment 1 = Red -> top segment 9 = Bright Green).
-- Every segment defines its exact QualityLabel, ChargeRatio (60%-100% throw distance), BonusPower, and LuckMultiplier.
GameConfig.MeterSegments = {
	{ Index = 1, Color = { 235, 65, 55 }, QualityLabel = "WEAK", ChargeRatio = 0.60, BonusPower = 1, LuckMultiplier = 1.00 },
	{ Index = 2, Color = { 245, 105, 50 }, QualityLabel = "WEAK", ChargeRatio = 0.65, BonusPower = 3, LuckMultiplier = 1.03 },
	{ Index = 3, Color = { 250, 145, 50 }, QualityLabel = "LOW", ChargeRatio = 0.70, BonusPower = 5, LuckMultiplier = 1.06 },
	{ Index = 4, Color = { 255, 185, 55 }, QualityLabel = "OK", ChargeRatio = 0.75, BonusPower = 7, LuckMultiplier = 1.10 },
	{ Index = 5, Color = { 245, 220, 60 }, QualityLabel = "OK", ChargeRatio = 0.80, BonusPower = 9, LuckMultiplier = 1.15 },
	{ Index = 6, Color = { 205, 235, 65 }, QualityLabel = "GOOD", ChargeRatio = 0.85, BonusPower = 12, LuckMultiplier = 1.22 },
	{ Index = 7, Color = { 160, 240, 75 }, QualityLabel = "GOOD!", ChargeRatio = 0.90, BonusPower = 14, LuckMultiplier = 1.32 },
	{ Index = 8, Color = { 115, 245, 85 }, QualityLabel = "GREAT!", ChargeRatio = 0.95, BonusPower = 17, LuckMultiplier = 1.48 },
	{ Index = 9, Color = { 70, 250, 105 }, QualityLabel = "PERFECT!", ChargeRatio = 1.00, BonusPower = 20, LuckMultiplier = 1.75, IsPerfect = true },
} :: { MeterSegmentDef }

-- Live flight luck: distance down the lane x meter band luck x bait quality.
-- Shared by the server (authoritative reward roll) and the client (live "1.XXx LUCK" ticker).
GameConfig.FlightLuck = {
	StudsPerExtraLuck = 350, -- +1.00x luck for every 350 studs of distance
}

function GameConfig.ComputeFlightLuck(distanceStuds: number, meterLuck: number, baitLuck: number): number
	local distMult = 1.0 + math.max(0, distanceStuds) / GameConfig.FlightLuck.StudsPerExtraLuck
	return distMult * math.max(1.0, meterLuck) * math.max(1.0, baitLuck)
end

-- Jelly Bait quality tiers (bought with Cash in Upgrades): multiplies rarity & mutation luck on every throw.
GameConfig.BaitTiers = {
	{ Tier = 1, Name = "Carrot Jelly", Cost = 0, LuckMultiplier = 1.00, Color = { 255, 125, 40 } },
	{ Tier = 2, Name = "Berry Jelly", Cost = 600, LuckMultiplier = 1.35, Color = { 200, 70, 160 } },
	{ Tier = 3, Name = "Crystal Honey", Cost = 8000, LuckMultiplier = 1.85, Color = { 255, 205, 70 } },
	{ Tier = 4, Name = "Magma Tart", Cost = 120000, LuckMultiplier = 2.60, Color = { 255, 95, 45 } },
	{ Tier = 5, Name = "Starlight Cake", Cost = 2000000, LuckMultiplier = 4.00, Color = { 170, 150, 255 } },
} :: { BaitTierDef }

-- Strength levels: pull-up reps give Training XP; every level up gives +PowerPerLevel Throw Power.
GameConfig.Training = {
	PowerPerLevel = 5,
	BonusRepMultiplier = 3, -- XP multiplier for clicking a Bonus Rep pop-up
	BonusRepIntervalMin = 4.0, -- seconds between Bonus Rep offers while training
	BonusRepIntervalMax = 6.0,
	BonusRepWindow = 2.5, -- seconds a Bonus Rep offer stays clickable
	BonusRepServerCooldown = 3.5, -- minimum seconds between two accepted Bonus Reps
}

-- XP needed to go from `level` to `level + 1` (Lv1->2 = 10, Lv5->6 = 87, Lv10->11 = 223, Lv20->21 = 570).
function GameConfig.GetXPRequiredForLevel(level: number): number
	local lvl = math.max(1, math.floor(level))
	return math.floor(10 * (lvl ^ 1.35))
end

function GameConfig.EvaluateMeterRatio(ratio: number): MeterSegmentDef
	local clamped = math.clamp(ratio, 0, 1)
	local count = #GameConfig.MeterSegments
	local idx = math.clamp(math.floor(clamped * count) + 1, 1, count)
	return GameConfig.MeterSegments[idx]
end

GameConfig.Mutations = {
	{
		Id = "NORMAL",
		Name = "",
		IncomeMultiplier = 1.0,
		Weight = 72,
		OddsMultiplier = 1,
		Color = { 240, 245, 255 },
	},
	{
		Id = "EMERALD",
		Name = "EMERALD",
		IncomeMultiplier = 1.5,
		Weight = 16,
		OddsMultiplier = 4,
		Color = { 80, 255, 135 },
	},
	{
		Id = "GOLDEN",
		Name = "GOLDEN",
		IncomeMultiplier = 2.5,
		Weight = 7,
		OddsMultiplier = 12,
		Color = { 255, 215, 65 },
	},
	{
		Id = "CRYSTAL",
		Name = "CRYSTAL",
		IncomeMultiplier = 4.0,
		Weight = 3.5,
		OddsMultiplier = 25,
		Color = { 105, 230, 255 },
	},
	{
		Id = "RAINBOW",
		Name = "RAINBOW",
		IncomeMultiplier = 7.5,
		Weight = 1.5,
		OddsMultiplier = 60,
		Color = { 255, 120, 220 },
	},
} :: { MutationDef }

GameConfig.MutationsById = {} :: { [string]: MutationDef }
for _, mut in GameConfig.Mutations do
	GameConfig.MutationsById[mut.Id] = mut
end

GameConfig.Zones = {
	{
		Index = 1,
		Id = "1_Meadow",
		Name = "Meadow",
		Emoji = "🌿",
		StartZ = 0,
		EndZ = 240,
		FloorY = 0,
		RequiredThrowPower = 0,
		ClearHalfWidth = 22,
		CashPerStud = 0.25,
		ThemeColor = { 124, 255, 138 },
		TrailName = "Leaf Trail",
		TrailBonusText = "+15% XP",
		TrailBonusType = "XP",
		TrailMultiplier = 1.15,
	},
	{
		Index = 2,
		Id = "2_CrystalCave",
		Name = "Crystal Cave",
		Emoji = "💎",
		StartZ = 240,
		EndZ = 480,
		FloorY = 6,
		RequiredThrowPower = 50,
		ClearHalfWidth = 22,
		CashPerStud = 0.75,
		ThemeColor = { 111, 195, 255 },
		TrailName = "Crystal Trail",
		TrailBonusText = "+20% Cash",
		TrailBonusType = "Cash",
		TrailMultiplier = 1.20,
	},
	{
		Index = 3,
		Id = "3_LavaFields",
		Name = "Lava Fields",
		Emoji = "🌋",
		StartZ = 480,
		EndZ = 720,
		FloorY = 12,
		RequiredThrowPower = 250,
		ClearHalfWidth = 22,
		CashPerStud = 2.2,
		ThemeColor = { 255, 132, 74 },
		TrailName = "Magma Trail",
		TrailBonusText = "+25% Power",
		TrailBonusType = "Power",
		TrailMultiplier = 1.25,
	},
	{
		Index = 4,
		Id = "4_FrostPeaks",
		Name = "Frost Peaks",
		Emoji = "❄️",
		StartZ = 720,
		EndZ = 960,
		FloorY = 18,
		RequiredThrowPower = 1000,
		ClearHalfWidth = 22,
		CashPerStud = 6.5,
		ThemeColor = { 165, 235, 255 },
		TrailName = "Frost Trail",
		TrailBonusText = "+35% Cash",
		TrailBonusType = "Cash",
		TrailMultiplier = 1.35,
	},
	{
		Index = 5,
		Id = "5_CandyLand",
		Name = "Candy Land",
		Emoji = "🍬",
		StartZ = 960,
		EndZ = 1200,
		FloorY = 24,
		RequiredThrowPower = 5000,
		ClearHalfWidth = 22,
		CashPerStud = 20.0,
		ThemeColor = { 255, 122, 184 },
		TrailName = "Sugar Trail",
		TrailBonusText = "+50% All",
		TrailBonusType = "All",
		TrailMultiplier = 1.50,
	},
	{
		Index = 6,
		Id = "6_DesertDunes",
		Name = "Desert Dunes",
		Emoji = "🏜️",
		StartZ = 1200,
		EndZ = 1440,
		FloorY = 30,
		RequiredThrowPower = 20000,
		ClearHalfWidth = 22,
		CashPerStud = 60.0,
		ThemeColor = { 255, 205, 110 },
		TrailName = "Dune Trail",
		TrailBonusText = "+65% Power",
		TrailBonusType = "Power",
		TrailMultiplier = 1.65,
	},
	{
		Index = 7,
		Id = "7_AcidSwamp",
		Name = "Acid Swamp",
		Emoji = "☣️",
		StartZ = 1440,
		EndZ = 1680,
		FloorY = 36,
		RequiredThrowPower = 80000,
		ClearHalfWidth = 22,
		CashPerStud = 180.0,
		ThemeColor = { 150, 235, 70 },
		TrailName = "Toxic Trail",
		TrailBonusText = "+80% All",
		TrailBonusType = "All",
		TrailMultiplier = 1.80,
	},
} :: { ZoneDef }

GameConfig.Slimes = {
	-- Zone 1: Meadow
	{
		Id = "meadow_sprout",
		Name = "Sprout Slime",
		ShortWord = "SPROUT",
		ZoneIndex = 1,
		Rarity = "Common",
		RarityRank = 1,
		DropWeight = 36,
		BaseOdds = 2,
		Color = { 110, 235, 115 },
		CoreColor = { 195, 255, 175 },
		Scale = 1,
		IncomePerSec = 2,
		ThrowBonus = 0,
		Weight = 1,
	},
	{
		Id = "meadow_clover",
		Name = "Clover Slime",
		ShortWord = "CLOVER",
		ZoneIndex = 1,
		Rarity = "Common",
		RarityRank = 2,
		DropWeight = 26,
		BaseOdds = 3,
		Color = { 70, 200, 110 },
		CoreColor = { 170, 245, 170 },
		Scale = 1.04,
		IncomePerSec = 3,
		ThrowBonus = 1,
		Weight = 0.98,
	},
	{
		Id = "meadow_dandelion",
		Name = "Dandelion Slime",
		ShortWord = "DANDELION",
		ZoneIndex = 1,
		Rarity = "Uncommon",
		RarityRank = 3,
		DropWeight = 18,
		BaseOdds = 4,
		Color = { 255, 225, 95 },
		CoreColor = { 255, 250, 200 },
		Scale = 1.06,
		IncomePerSec = 4,
		ThrowBonus = 2,
		Weight = 0.97,
	},
	{
		Id = "meadow_honey",
		Name = "Honey Slime",
		ShortWord = "HONEY",
		ZoneIndex = 1,
		Rarity = "Uncommon",
		RarityRank = 4,
		DropWeight = 11,
		BaseOdds = 5,
		Color = { 255, 200, 65 },
		CoreColor = { 255, 240, 150 },
		Scale = 1.08,
		IncomePerSec = 5,
		ThrowBonus = 4,
		Weight = 0.96,
	},
	{
		Id = "meadow_mushroom",
		Name = "Mushroom Slime",
		ShortWord = "MUSHROOM",
		ZoneIndex = 1,
		Rarity = "Rare",
		RarityRank = 5,
		DropWeight = 6,
		BaseOdds = 9,
		Color = { 225, 95, 95 },
		CoreColor = { 255, 225, 215 },
		Scale = 1.12,
		IncomePerSec = 8,
		ThrowBonus = 7,
		Weight = 0.94,
	},
	{
		Id = "meadow_bloom",
		Name = "Sakura Bloom Slime",
		ShortWord = "SAKURA",
		ZoneIndex = 1,
		Rarity = "Rare",
		RarityRank = 6,
		DropWeight = 3,
		BaseOdds = 16,
		Color = { 255, 145, 195 },
		CoreColor = { 255, 220, 240 },
		Scale = 1.15,
		IncomePerSec = 12,
		ThrowBonus = 10,
		Weight = 0.92,
	},

	-- Zone 2: Crystal Cave
	{
		Id = "crystal_pebble",
		Name = "Pebble Slime",
		ShortWord = "PEBBLE",
		ZoneIndex = 2,
		Rarity = "Uncommon",
		RarityRank = 7,
		DropWeight = 36,
		BaseOdds = 2,
		Color = { 150, 160, 185 },
		CoreColor = { 215, 225, 245 },
		Scale = 1.06,
		IncomePerSec = 14,
		ThrowBonus = 11,
		Weight = 1,
	},
	{
		Id = "crystal_quartz",
		Name = "Quartz Slime",
		ShortWord = "QUARTZ",
		ZoneIndex = 2,
		Rarity = "Uncommon",
		RarityRank = 8,
		DropWeight = 26,
		BaseOdds = 3,
		Color = { 110, 205, 255 },
		CoreColor = { 200, 245, 255 },
		Scale = 1.1,
		IncomePerSec = 18,
		ThrowBonus = 15,
		Weight = 1,
	},
	{
		Id = "crystal_glowcap",
		Name = "Glowcap Slime",
		ShortWord = "GLOWCAP",
		ZoneIndex = 2,
		Rarity = "Rare",
		RarityRank = 9,
		DropWeight = 18,
		BaseOdds = 5,
		Color = { 90, 230, 200 },
		CoreColor = { 200, 255, 240 },
		Scale = 1.14,
		IncomePerSec = 26,
		ThrowBonus = 22,
		Weight = 0.97,
	},
	{
		Id = "crystal_amethyst",
		Name = "Amethyst Slime",
		ShortWord = "AMETHYST",
		ZoneIndex = 2,
		Rarity = "Rare",
		RarityRank = 10,
		DropWeight = 11,
		BaseOdds = 8,
		Color = { 180, 115, 255 },
		CoreColor = { 235, 195, 255 },
		Scale = 1.18,
		IncomePerSec = 38,
		ThrowBonus = 32,
		Weight = 0.94,
	},
	{
		Id = "crystal_bat",
		Motion = "Fly",
		Name = "Bat Slime",
		ShortWord = "BAT",
		ZoneIndex = 2,
		Rarity = "Epic",
		RarityRank = 11,
		DropWeight = 6,
		BaseOdds = 14,
		Color = { 120, 90, 175 },
		CoreColor = { 225, 195, 255 },
		Scale = 1.22,
		IncomePerSec = 52,
		ThrowBonus = 45,
		Weight = 0.91,
	},
	{
		Id = "crystal_prism",
		Name = "Prism Geode Slime",
		ShortWord = "PRISM",
		ZoneIndex = 2,
		Rarity = "Epic",
		RarityRank = 12,
		DropWeight = 3,
		BaseOdds = 24,
		Color = { 85, 255, 230 },
		CoreColor = { 255, 255, 255 },
		Scale = 1.25,
		IncomePerSec = 75,
		ThrowBonus = 60,
		Weight = 0.88,
	},

	-- Zone 3: Lava Fields
	{
		Id = "lava_ember",
		Name = "Ember Slime",
		ShortWord = "EMBER",
		ZoneIndex = 3,
		Rarity = "Rare",
		RarityRank = 13,
		DropWeight = 36,
		BaseOdds = 4,
		Color = { 255, 115, 55 },
		CoreColor = { 255, 215, 95 },
		Scale = 1.15,
		IncomePerSec = 110,
		ThrowBonus = 95,
		Weight = 0.95,
	},
	{
		Id = "lava_salamander",
		Name = "Salamander Slime",
		ShortWord = "SALAMANDER",
		ZoneIndex = 3,
		Rarity = "Rare",
		RarityRank = 14,
		DropWeight = 26,
		BaseOdds = 6,
		Color = { 255, 150, 60 },
		CoreColor = { 255, 225, 120 },
		Scale = 1.17,
		IncomePerSec = 150,
		ThrowBonus = 125,
		Weight = 0.93,
	},
	{
		Id = "lava_volcano",
		Name = "Volcano Slime",
		ShortWord = "VOLCANO",
		ZoneIndex = 3,
		Rarity = "Epic",
		RarityRank = 15,
		DropWeight = 18,
		BaseOdds = 9,
		Color = { 190, 70, 50 },
		CoreColor = { 255, 160, 70 },
		Scale = 1.2,
		IncomePerSec = 190,
		ThrowBonus = 150,
		Weight = 0.92,
	},
	{
		Id = "lava_obsidian",
		Name = "Obsidian Core Slime",
		ShortWord = "OBSIDIAN",
		ZoneIndex = 3,
		Rarity = "Epic",
		RarityRank = 16,
		DropWeight = 11,
		BaseOdds = 12,
		Color = { 75, 55, 95 },
		CoreColor = { 255, 95, 40 },
		Scale = 1.24,
		IncomePerSec = 220,
		ThrowBonus = 180,
		Weight = 0.9,
	},
	{
		Id = "lava_phoenix",
		Motion = "Fly",
		Name = "Phoenix Slime",
		ShortWord = "PHOENIX",
		ZoneIndex = 3,
		Rarity = "Legendary",
		RarityRank = 17,
		DropWeight = 6,
		BaseOdds = 20,
		Color = { 255, 95, 70 },
		CoreColor = { 255, 230, 120 },
		Scale = 1.28,
		IncomePerSec = 320,
		ThrowBonus = 250,
		Weight = 0.87,
	},
	{
		Id = "lava_solar",
		Name = "Solar Flare Slime",
		ShortWord = "SOLAR",
		ZoneIndex = 3,
		Rarity = "Legendary",
		RarityRank = 18,
		DropWeight = 3,
		BaseOdds = 35,
		Color = { 255, 205, 50 },
		CoreColor = { 255, 255, 220 },
		Scale = 1.32,
		IncomePerSec = 450,
		ThrowBonus = 340,
		Weight = 0.84,
	},

	-- Zone 4: Frost Peaks
	{
		Id = "frost_snowball",
		Name = "Snowball Slime",
		ShortWord = "SNOWBALL",
		ZoneIndex = 4,
		Rarity = "Epic",
		RarityRank = 19,
		DropWeight = 36,
		BaseOdds = 5,
		Color = { 230, 245, 255 },
		CoreColor = { 255, 255, 255 },
		Scale = 1.12,
		IncomePerSec = 520,
		ThrowBonus = 380,
		Weight = 0.95,
	},
	{
		Id = "frost_glacier",
		Motion = "Slide",
		Name = "Glacier Slime",
		ShortWord = "GLACIER",
		ZoneIndex = 4,
		Rarity = "Epic",
		RarityRank = 20,
		DropWeight = 26,
		BaseOdds = 6,
		Color = { 135, 225, 255 },
		CoreColor = { 225, 250, 255 },
		Scale = 1.2,
		IncomePerSec = 650,
		ThrowBonus = 480,
		Weight = 0.92,
	},
	{
		Id = "frost_penguin",
		Motion = "Slide",
		Name = "Penguin Slime",
		ShortWord = "PENGUIN",
		ZoneIndex = 4,
		Rarity = "Legendary",
		RarityRank = 21,
		DropWeight = 18,
		BaseOdds = 10,
		Color = { 70, 90, 130 },
		CoreColor = { 200, 225, 255 },
		Scale = 1.24,
		IncomePerSec = 950,
		ThrowBonus = 650,
		Weight = 0.89,
	},
	{
		Id = "frost_aurora",
		Motion = "Fly",
		Name = "Aurora Borealis Slime",
		ShortWord = "AURORA",
		ZoneIndex = 4,
		Rarity = "Legendary",
		RarityRank = 22,
		DropWeight = 11,
		BaseOdds = 18,
		Color = { 90, 255, 195 },
		CoreColor = { 195, 140, 255 },
		Scale = 1.28,
		IncomePerSec = 1350,
		ThrowBonus = 900,
		Weight = 0.86,
	},
	{
		Id = "frost_yeti",
		Motion = "Waddle",
		Name = "Yeti Slime",
		ShortWord = "YETI",
		ZoneIndex = 4,
		Rarity = "Mythic",
		RarityRank = 23,
		DropWeight = 6,
		BaseOdds = 32,
		Color = { 200, 225, 245 },
		CoreColor = { 150, 200, 245 },
		Scale = 1.33,
		IncomePerSec = 1900,
		ThrowBonus = 1200,
		Weight = 0.83,
	},
	{
		Id = "frost_cryo",
		Name = "Cryo Monarch Slime",
		ShortWord = "MONARCH",
		ZoneIndex = 4,
		Rarity = "Mythic",
		RarityRank = 24,
		DropWeight = 3,
		BaseOdds = 55,
		Color = { 70, 165, 255 },
		CoreColor = { 255, 255, 255 },
		Scale = 1.38,
		IncomePerSec = 2800,
		ThrowBonus = 1650,
		Weight = 0.8,
	},

	-- Zone 5: Candy Land
	{
		Id = "candy_gumdrop",
		Name = "Gumdrop Slime",
		ShortWord = "GUMDROP",
		ZoneIndex = 5,
		Rarity = "Legendary",
		RarityRank = 25,
		DropWeight = 36,
		BaseOdds = 10,
		Color = { 255, 120, 190 },
		CoreColor = { 255, 225, 240 },
		Scale = 1.25,
		IncomePerSec = 4200,
		ThrowBonus = 2400,
		Weight = 0.88,
	},
	{
		Id = "candy_cupcake",
		Name = "Cupcake Slime",
		ShortWord = "CUPCAKE",
		ZoneIndex = 5,
		Rarity = "Legendary",
		RarityRank = 26,
		DropWeight = 26,
		BaseOdds = 14,
		Color = { 255, 170, 205 },
		CoreColor = { 255, 235, 200 },
		Scale = 1.28,
		IncomePerSec = 5300,
		ThrowBonus = 2900,
		Weight = 0.86,
	},
	{
		Id = "candy_bubblegum",
		Name = "Bubblegum Slime",
		ShortWord = "BUBBLEGUM",
		ZoneIndex = 5,
		Rarity = "Legendary",
		RarityRank = 27,
		DropWeight = 18,
		BaseOdds = 20,
		Color = { 255, 125, 205 },
		CoreColor = { 255, 210, 240 },
		Scale = 1.31,
		IncomePerSec = 6800,
		ThrowBonus = 3500,
		Weight = 0.85,
	},
	{
		Id = "candy_cotton",
		Motion = "Fly",
		Name = "Cotton Cloud Slime",
		ShortWord = "COTTON",
		ZoneIndex = 5,
		Rarity = "Mythic",
		RarityRank = 28,
		DropWeight = 11,
		BaseOdds = 30,
		Color = { 195, 145, 255 },
		CoreColor = { 130, 235, 255 },
		Scale = 1.35,
		IncomePerSec = 9000,
		ThrowBonus = 4200,
		Weight = 0.82,
	},
	{
		Id = "candy_lollipop",
		Name = "Lollipop Slime",
		ShortWord = "LOLLIPOP",
		ZoneIndex = 5,
		Rarity = "Mythic",
		RarityRank = 29,
		DropWeight = 6,
		BaseOdds = 50,
		Color = { 255, 115, 150 },
		CoreColor = { 255, 215, 100 },
		Scale = 1.4,
		IncomePerSec = 13000,
		ThrowBonus = 5600,
		Weight = 0.79,
	},
	{
		Id = "candy_royal",
		Motion = "Waddle",
		Name = "Royal Sugar King Slime",
		ShortWord = "SUGARKING",
		ZoneIndex = 5,
		Rarity = "Mythic",
		RarityRank = 30,
		DropWeight = 3,
		BaseOdds = 95,
		Color = { 255, 215, 75 },
		CoreColor = { 255, 105, 185 },
		Scale = 1.48,
		IncomePerSec = 20000,
		ThrowBonus = 7500,
		Weight = 0.76,
	},

	-- Zone 6: Desert Dunes
	{
		Id = "desert_sand",
		Name = "Sand Slime",
		ShortWord = "SAND",
		ZoneIndex = 6,
		Rarity = "Legendary",
		RarityRank = 31,
		DropWeight = 36,
		BaseOdds = 14,
		Color = { 235, 205, 135 },
		CoreColor = { 255, 240, 195 },
		Scale = 1.4,
		IncomePerSec = 26000,
		ThrowBonus = 8600,
		Weight = 0.8,
	},
	{
		Id = "desert_cactus",
		Name = "Cactus Slime",
		ShortWord = "CACTUS",
		ZoneIndex = 6,
		Rarity = "Legendary",
		RarityRank = 32,
		DropWeight = 26,
		BaseOdds = 20,
		Color = { 110, 180, 95 },
		CoreColor = { 200, 240, 160 },
		Scale = 1.44,
		IncomePerSec = 34000,
		ThrowBonus = 11000,
		Weight = 0.78,
	},
	{
		Id = "desert_mummy",
		Motion = "Waddle",
		Name = "Mummy Slime",
		ShortWord = "MUMMY",
		ZoneIndex = 6,
		Rarity = "Legendary",
		RarityRank = 33,
		DropWeight = 18,
		BaseOdds = 30,
		Color = { 225, 215, 190 },
		CoreColor = { 255, 250, 225 },
		Scale = 1.48,
		IncomePerSec = 45000,
		ThrowBonus = 14500,
		Weight = 0.76,
	},
	{
		Id = "desert_scarab",
		Name = "Scarab Slime",
		ShortWord = "SCARAB",
		ZoneIndex = 6,
		Rarity = "Mythic",
		RarityRank = 34,
		DropWeight = 11,
		BaseOdds = 45,
		Color = { 60, 160, 150 },
		CoreColor = { 120, 255, 220 },
		Scale = 1.52,
		IncomePerSec = 60000,
		ThrowBonus = 18500,
		Weight = 0.74,
	},
	{
		Id = "desert_djinn",
		Motion = "Fly",
		Name = "Djinn Slime",
		ShortWord = "DJINN",
		ZoneIndex = 6,
		Rarity = "Mythic",
		RarityRank = 35,
		DropWeight = 6,
		BaseOdds = 70,
		Color = { 95, 120, 235 },
		CoreColor = { 190, 215, 255 },
		Scale = 1.56,
		IncomePerSec = 85000,
		ThrowBonus = 25000,
		Weight = 0.72,
	},
	{
		Id = "desert_pharaoh",
		Motion = "Waddle",
		Name = "Pharaoh Slime",
		ShortWord = "PHARAOH",
		ZoneIndex = 6,
		Rarity = "Mythic",
		RarityRank = 36,
		DropWeight = 3,
		BaseOdds = 120,
		Color = { 240, 190, 50 },
		CoreColor = { 80, 170, 255 },
		Scale = 1.62,
		IncomePerSec = 120000,
		ThrowBonus = 33000,
		Weight = 0.7,
	},

	-- Zone 7: Acid Swamp
	{
		Id = "acid_sludge",
		Motion = "Slide",
		Name = "Sludge Slime",
		ShortWord = "SLUDGE",
		ZoneIndex = 7,
		Rarity = "Legendary",
		RarityRank = 37,
		DropWeight = 36,
		BaseOdds = 22,
		Color = { 120, 150, 50 },
		CoreColor = { 200, 235, 100 },
		Scale = 1.5,
		IncomePerSec = 150000,
		ThrowBonus = 40000,
		Weight = 0.72,
	},
	{
		Id = "acid_bubbling",
		Name = "Bubbling Slime",
		ShortWord = "BUBBLING",
		ZoneIndex = 7,
		Rarity = "Legendary",
		RarityRank = 38,
		DropWeight = 26,
		BaseOdds = 32,
		Color = { 150, 235, 70 },
		CoreColor = { 230, 255, 150 },
		Scale = 1.54,
		IncomePerSec = 190000,
		ThrowBonus = 50000,
		Weight = 0.7,
	},
	{
		Id = "acid_hazmat",
		Name = "Hazmat Slime",
		ShortWord = "HAZMAT",
		ZoneIndex = 7,
		Rarity = "Mythic",
		RarityRank = 39,
		DropWeight = 18,
		BaseOdds = 48,
		Color = { 240, 215, 70 },
		CoreColor = { 255, 255, 170 },
		Scale = 1.58,
		IncomePerSec = 250000,
		ThrowBonus = 64000,
		Weight = 0.68,
	},
	{
		Id = "acid_mutant",
		Name = "Mutant Slime",
		ShortWord = "MUTANT",
		ZoneIndex = 7,
		Rarity = "Mythic",
		RarityRank = 40,
		DropWeight = 11,
		BaseOdds = 75,
		Color = { 120, 235, 90 },
		CoreColor = { 255, 120, 230 },
		Scale = 1.62,
		IncomePerSec = 330000,
		ThrowBonus = 82000,
		Weight = 0.66,
	},
	{
		Id = "acid_scientist",
		Motion = "Waddle",
		Name = "Mad Scientist Slime",
		ShortWord = "SCIENTIST",
		ZoneIndex = 7,
		Rarity = "Mythic",
		RarityRank = 41,
		DropWeight = 6,
		BaseOdds = 120,
		Color = { 90, 235, 190 },
		CoreColor = { 200, 255, 245 },
		Scale = 1.68,
		IncomePerSec = 450000,
		ThrowBonus = 105000,
		Weight = 0.64,
	},
	{
		Id = "acid_nuclear",
		Name = "Nuclear Core Slime",
		ShortWord = "NUCLEAR",
		ZoneIndex = 7,
		Rarity = "Mythic",
		RarityRank = 42,
		DropWeight = 3,
		BaseOdds = 200,
		Color = { 170, 255, 60 },
		CoreColor = { 255, 255, 255 },
		Scale = 1.75,
		IncomePerSec = 650000,
		ThrowBonus = 140000,
		Weight = 0.62,
	},
} :: { SlimeDef }

GameConfig.SlimesById = {} :: { [string]: SlimeDef }
GameConfig.SlimesByZone = {} :: { [number]: { SlimeDef } }

for _, slime in GameConfig.Slimes do
	slime.Name = string.gsub(slime.Name, "^%s+", "")
	GameConfig.SlimesById[slime.Id] = slime
	if not GameConfig.SlimesByZone[slime.ZoneIndex] then
		GameConfig.SlimesByZone[slime.ZoneIndex] = {}
	end
	table.insert(GameConfig.SlimesByZone[slime.ZoneIndex], slime)
end

-- Catch-cutscene movement styles a SlimeDef.Motion may use (SlimeMotion.luau implements each one)
GameConfig.SlimeMotionStyles = { Hop = true, Fly = true, Slide = true, Waddle = true } :: { [string]: boolean }

GameConfig.PullUpTiers = {
	{ Tier = 1, Name = "PULL-UP BAR", Cost = 0, XPPerRep = 2, SpeedMult = 1.0 },
	{ Tier = 2, Name = "IRON BAR", Cost = 350, XPPerRep = 8, SpeedMult = 1.15 },
	{ Tier = 3, Name = "CRYSTAL BAR", Cost = 4500, XPPerRep = 32, SpeedMult = 1.3 },
	{ Tier = 4, Name = "MAGMA BAR", Cost = 75000, XPPerRep = 140, SpeedMult = 1.5 },
	{ Tier = 5, Name = "STARLIGHT BAR", Cost = 1200000, XPPerRep = 600, SpeedMult = 1.75 },
} :: { PullUpTierDef }

-- Pull-up loop tuning. Rep time shrinks with strength (BaseThrowPower) and bar tier SpeedMult:
--   interval = clamp(BaseRepSeconds / (SpeedMult * (1 + StrengthLogScale * log10(1 + power / StrengthRef))),
--                    MinRepSeconds, BaseRepSeconds)
GameConfig.PullUp = {
	BaseRepSeconds = 1.6,
	MinRepSeconds = 0.35,
	StrengthLogScale = 0.8,
	StrengthRef = 5,
	MaxTrainDistance = 16, -- studs from the bar before training auto-stops
	AutoStartRadius = 6, -- studs from TrainSpot (or Bar) to auto-start training
	RearmRadius = 9, -- studs owner must walk out to re-arm auto-start after stopping
	SyncEveryReps = 5, -- full PlayerStateSync cadence while training (TrainingRep fires every rep)

	-- Exaggerated rep motion (degrees / studs at full intensity; see PullUpMotion.luau)
	Anim = {
		Rise = 2.4, -- studs the body rises at the chin-over-bar peak
		StretchDip = 0.15, -- fraction of Rise the body sinks below the hang in the anticipation stretch
		Overshoot = 0.1, -- fraction of Rise the pull overshoots before settling into the hold
		HoldFraction = 0.08, -- fraction of the cycle spent holding at the top
		ShoulderHang = 175, -- arms straight overhead in the dead hang
		ShoulderTopR15 = 105, -- R15 shoulder angle at the peak (elbows do the rest)
		ShoulderTopR6 = 130, -- R6 has no elbows, so the shoulders swing further
		ElbowTop = 150, -- R15 elbow fold at the peak
		LeanBack = 10, -- torso lean back at the peak
		NeckTilt = 25, -- chin-up head tilt at the peak
		Roll = 6, -- body roll at the peak, alternating left/right each rep
		KneeTuck = 70, -- knee tuck at the peak
		LegSwing = 22, -- pendulum leg swing on the way down
	},

	-- Front camera + per-rep shake (TrainingController.client.luau)
	Camera = {
		Distance = 10, -- studs in front of the character
		HeightOffset = 0.5, -- camera height above the HumanoidRootPart (low angle)
		FocusHeight = 1.8, -- look-at point above the HumanoidRootPart (face / bar)
		MinDistance = 4, -- closest the occlusion pull-in may bring the camera
		FieldOfView = 70,
		FovPunch = 6, -- degrees the FOV dips at each rep peak
		FovPunchTime = 0.25, -- seconds for the FOV punch to recover
		ShakeTrauma = 0.55, -- trauma added per rep (x intensity), capped at 1
		ShakeDecay = 3.5, -- trauma lost per second
		ShakePosition = 0.35, -- studs of positional shake at full trauma
		ShakeRotation = 1.8, -- degrees of rotational shake at full trauma
		ShakeFrequency = 18, -- noise speed
	},
}

GameConfig.ShopEggs = {
	{
		Id = "enchanted_egg",
		Name = "ENCHANTED EGG",
		Tag = "New!",
		Buy1Robux = 49,
		Buy3Robux = 129,
		Buy1ProductId = 0,
		Buy3ProductId = 0,
		AccentColor = { 175, 110, 255 },
		Items = {
			{ SlimeId = "meadow_honey", Mutation = "EMERALD", ChancePercent = 40, BonusLabel = "150%" },
			{ SlimeId = "meadow_bloom", Mutation = "NORMAL", ChancePercent = 27, BonusLabel = "175%" },
			{ SlimeId = "crystal_quartz", Mutation = "EMERALD", ChancePercent = 18, BonusLabel = "250%" },
			{ SlimeId = "crystal_amethyst", Mutation = "GOLDEN", ChancePercent = 10, BonusLabel = "350%" },
			{ SlimeId = "crystal_prism", Mutation = "CRYSTAL", ChancePercent = 4, BonusLabel = "550%" },
			{ SlimeId = "lava_solar", Mutation = "RAINBOW", ChancePercent = 1, BonusLabel = "900%" },
		},
	},
	{
		Id = "rainbow_egg",
		Name = "RAINBOW EGG",
		Tag = "LIMITED",
		Buy1Robux = 149,
		Buy3Robux = 399,
		Buy1ProductId = 0,
		Buy3ProductId = 0,
		AccentColor = { 255, 120, 200 },
		Items = {
			{ SlimeId = "crystal_prism", Mutation = "RAINBOW", ChancePercent = 45, BonusLabel = "750%" },
			{ SlimeId = "lava_obsidian", Mutation = "RAINBOW", ChancePercent = 28, BonusLabel = "750%" },
			{ SlimeId = "lava_solar", Mutation = "RAINBOW", ChancePercent = 16, BonusLabel = "750%" },
			{ SlimeId = "frost_aurora", Mutation = "RAINBOW", ChancePercent = 8, BonusLabel = "750%" },
			{ SlimeId = "candy_cotton", Mutation = "RAINBOW", ChancePercent = 2.5, BonusLabel = "750%" },
			{ SlimeId = "candy_royal", Mutation = "RAINBOW", ChancePercent = 0.5, BonusLabel = "999%" },
		},
	},
} :: { ShopEggDef }

GameConfig.ShopEggsById = {} :: { [string]: ShopEggDef }
GameConfig.RobuxEggsByProductId = {} :: { [number]: { EggId: string, Count: number } }
for _, egg in GameConfig.ShopEggs do
	GameConfig.ShopEggsById[egg.Id] = egg
	if egg.Buy1ProductId > 0 then
		GameConfig.RobuxEggsByProductId[egg.Buy1ProductId] = { EggId = egg.Id, Count = 1 }
	end
	if egg.Buy3ProductId > 0 then
		GameConfig.RobuxEggsByProductId[egg.Buy3ProductId] = { EggId = egg.Id, Count = 3 }
	end
end

-- Tiered Permanent Multipliers (buyable via high-value Gems in Upgrades OR directly with Robux Passes).
-- Highest tier owned across Gems or Robux Passes applies (capped at 10x max; never double-charges).
GameConfig.MultiplierTracks = {
	{
		Id = "gems",
		Name = "Gems Multiplier",
		ShortStat = "Earned Gems",
		Icon = "gem",
		Color = { 75, 210, 255 },
		Tiers = {
			{ Tier = 1, Multiplier = 2, BoostId = "gems_2x", PassId = "pass_gems_2x", Name = "2x Gems", Description = "2x Gems from catches, quests, zones & daily!", GemCost = 2500, RobuxPrice = 199, Color = { 70, 200, 255 } },
			{ Tier = 2, Multiplier = 4, BoostId = "gems_4x", PassId = "pass_gems_4x", Name = "4x Gems", Description = "4x Gems from catches, quests, zones & daily!", GemCost = 6000, RobuxPrice = 349, Color = { 55, 175, 255 } },
			{ Tier = 3, Multiplier = 6, BoostId = "gems_6x", PassId = "pass_gems_6x", Name = "6x Gems", Description = "6x Gems from catches, quests, zones & daily!", GemCost = 12000, RobuxPrice = 549, Color = { 105, 145, 255 } },
			{ Tier = 4, Multiplier = 8, BoostId = "gems_8x", PassId = "pass_gems_8x", Name = "8x Gems", Description = "8x Gems from catches, quests, zones & daily!", GemCost = 22000, RobuxPrice = 799, Color = { 160, 110, 255 } },
			{ Tier = 5, Multiplier = 10, BoostId = "gems_10x", PassId = "pass_gems_10x", Name = "10x Gems", Description = "MAX 10x Gems from every in-game source!", GemCost = 38000, RobuxPrice = 1199, Color = { 235, 100, 255 } },
		},
	},
	{
		Id = "power",
		Name = "Training Power",
		ShortStat = "Pull-Up XP",
		Icon = "power",
		Color = { 170, 105, 255 },
		Tiers = {
			{ Tier = 1, Multiplier = 2, BoostId = "power_2x", PassId = "pass_power_2x", Name = "2x Training Power", Description = "2x Pull-Up XP on every rep!", GemCost = 1800, RobuxPrice = 149, Color = { 165, 110, 255 } },
			{ Tier = 2, Multiplier = 4, BoostId = "power_4x", PassId = "pass_power_4x", Name = "4x Training Power", Description = "4x Pull-Up XP on every rep!", GemCost = 4500, RobuxPrice = 299, Color = { 195, 95, 255 } },
			{ Tier = 3, Multiplier = 6, BoostId = "power_6x", PassId = "pass_power_6x", Name = "6x Training Power", Description = "6x Pull-Up XP on every rep!", GemCost = 9500, RobuxPrice = 499, Color = { 235, 95, 215 } },
			{ Tier = 4, Multiplier = 8, BoostId = "power_8x", PassId = "pass_power_8x", Name = "8x Training Power", Description = "8x Pull-Up XP on every rep!", GemCost = 17500, RobuxPrice = 749, Color = { 255, 110, 145 } },
			{ Tier = 5, Multiplier = 10, BoostId = "power_10x", PassId = "pass_power_10x", Name = "10x Training Power", Description = "MAX 10x Pull-Up XP on every rep!", GemCost = 30000, RobuxPrice = 1099, Color = { 255, 150, 65 } },
		},
	},
	{
		Id = "luck",
		Name = "Throw Luck",
		ShortStat = "Throw Luck",
		Icon = "clover",
		Color = { 85, 225, 115 },
		Tiers = {
			{ Tier = 1, Multiplier = 2, BoostId = "luck_2x", PassId = "pass_x2_luck", Name = "2x Luck", Description = "Permanent 2x Luck on every throw!", GemCost = 2000, RobuxPrice = 179, Color = { 90, 225, 120 } },
			{ Tier = 2, Multiplier = 4, BoostId = "luck_4x", PassId = "pass_luck_4x", Name = "4x Lucky", Description = "Permanent 4x Luck for rare & Rainbow slimes!", GemCost = 5000, RobuxPrice = 349, Color = { 65, 235, 155 } },
			{ Tier = 3, Multiplier = 6, BoostId = "luck_6x", PassId = "pass_luck_6x", Name = "6x Lucky", Description = "Permanent 6x Luck for Mythic & Rainbow rolls!", GemCost = 10500, RobuxPrice = 549, Color = { 55, 225, 210 } },
			{ Tier = 4, Multiplier = 8, BoostId = "luck_8x", PassId = "pass_luck_8x", Name = "8x Lucky", Description = "Permanent 8x Luck on every throw!", GemCost = 19000, RobuxPrice = 799, Color = { 130, 200, 255 } },
			{ Tier = 5, Multiplier = 10, BoostId = "luck_10x", PassId = "pass_luck_10x", Name = "10x Luck", Description = "MAX 10x Luck on every throw!", GemCost = 32000, RobuxPrice = 1199, Color = { 255, 205, 60 } },
		},
	},
	{
		Id = "money",
		Name = "2x Money",
		ShortStat = "Cash Income",
		Icon = "cash",
		Color = { 55, 195, 250 },
		Tiers = {
			{ Tier = 1, Multiplier = 2, BoostId = "money_2x", PassId = "pass_x2_cash", Name = "2x Money", Description = "Permanent 2x Cash from slimes & throws!", GemCost = 2200, RobuxPrice = 199, Color = { 55, 195, 250 } },
		},
	},
} :: { MultiplierTrackDef }

GameConfig.MultiplierTracksById = {} :: { [string]: MultiplierTrackDef }
for _, track in GameConfig.MultiplierTracks do
	GameConfig.MultiplierTracksById[track.Id] = track
end

GameConfig.ShopBoosts = {
	auto_throw = {
		Id = "auto_throw",
		Name = "Auto-Throw",
		Description = "Throws automatically at the line (3 PERFECT / 2 GREAT bag)!",
		Cost = 2000,
		PriceKind = "Gems",
		Color = { 80, 210, 230 },
	},
} :: { [string]: ShopBoostDef }

GameConfig.ShopBoostOrder = { "auto_throw" }
for _, track in GameConfig.MultiplierTracks do
	for _, tier in track.Tiers do
		GameConfig.ShopBoosts[tier.BoostId] = {
			Id = tier.BoostId,
			Name = tier.Name,
			Description = tier.Description,
			Cost = tier.GemCost,
			PriceKind = "Gems",
			Color = tier.Color,
			LuckMultiplier = if track.Id == "luck" then tier.Multiplier else nil,
			TrackId = track.Id,
			Tier = tier.Tier,
			Multiplier = tier.Multiplier,
		}
		table.insert(GameConfig.ShopBoostOrder, tier.BoostId)
	end
end

GameConfig.FreeGift = {
	SlimeId = "meadow_honey",
	Mutation = "EMERALD" :: "EMERALD",
	Title = "Free Slime!",
	Subtitle = "Claim your free Emerald Honey Slime!",
}

--[[
	Shop catalog: the single list of everything purchasable. Prices/names are NOT stored here;
	they are read from the tables above (PullUpTiers, BaitTiers, MultiplierTracks, ShopBoosts,
	ShopEggs, Slots, GetPowerUpgradeCost) by ProgressionLogic.GetShopListing.
	Cash buys core progression (Power, Bars, Bait); Gems & Robux own Multipliers, Auto-Throw,
	and locked Plot Slots 9-12. See docs/docs/ECONOMY-BASELINE.md & docs/docs/shop-catalog.md.
]]
GameConfig.ShopCatalog = {
	{ Id = "power_upgrade", Category = "Upgrade", Action = "PowerUpgrade", Args = {}, Icon = "⚡", Color = { 235, 150, 45 }, PriceKind = "Cash" },
	{ Id = "pullup_tier", Category = "Upgrade", Action = "PullUpTier", Args = {}, Icon = "💪", Color = { 55, 155, 240 }, PriceKind = "Cash" },
	{ Id = "bait_tier", Category = "Upgrade", Action = "BaitTier", Args = {}, Icon = "🥕", Color = { 255, 125, 40 }, PriceKind = "Cash" },
	{ Id = "egg_enchanted", Category = "Egg", Action = "Egg", Args = { EggId = "enchanted_egg" }, Icon = "🥚", Color = { 175, 110, 255 }, PriceKind = "Robux" },
	{ Id = "egg_rainbow", Category = "Egg", Action = "Egg", Args = { EggId = "rainbow_egg" }, Icon = "🌈", Color = { 255, 120, 200 }, PriceKind = "Robux" },
	{ Id = "free_gift", Category = "Gift", Action = "FreeGift", Args = {}, Icon = "🎁", Color = { 255, 205, 55 }, PriceKind = "Cash" },
	-- Premium Gem items (8+ hour F2P grind OR direct Robux Pass / Gem Packs)
	{ Id = "gem_slot_unlock", Category = "Gem", Action = "SlotExpansion", Args = {}, Icon = "🧺", Color = { 95, 200, 120 }, PriceKind = "Gems" },
	{ Id = "gem_auto_throw", Category = "Gem", Action = "Boost", Args = { BoostId = "auto_throw" }, Icon = "🤖", Color = { 80, 210, 230 }, PriceKind = "Gems" },
	{ Id = "gem_money_2x", Category = "Gem", Action = "MultiplierTier", Args = { TrackId = "money" }, Icon = "💵", Color = { 55, 195, 250 }, PriceKind = "Gems" },
	{ Id = "gem_gems_tier", Category = "Gem", Action = "MultiplierTier", Args = { TrackId = "gems" }, Icon = "💎", Color = { 75, 210, 255 }, PriceKind = "Gems" },
	{ Id = "gem_power_tier", Category = "Gem", Action = "MultiplierTier", Args = { TrackId = "power" }, Icon = "💪", Color = { 170, 105, 255 }, PriceKind = "Gems" },
	{ Id = "gem_luck_tier", Category = "Gem", Action = "MultiplierTier", Args = { TrackId = "luck" }, Icon = "🍀", Color = { 85, 225, 115 }, PriceKind = "Gems" },
} :: { ShopCatalogItem }

GameConfig.ShopCatalogById = {} :: { [string]: ShopCatalogItem }
for _, item in GameConfig.ShopCatalog do
	GameConfig.ShopCatalogById[item.Id] = item
end

-- ============================================================================
-- QUESTS: Linear Quest Line (12 steps) + Daily Quest Pool (3 picked per UTC day)
-- ============================================================================
GameConfig.Quests = {
	DailyCount = 3,
	Line = {
		{ Id = "line_throw_1", Title = "Throw Jelly Once", Event = "Throw", Target = 1, Reward = { Cash = 40, Gems = 3 } },
		{ Id = "line_place_1", Title = "Place a Slime on Your Plot", Event = "PlaceSlime", Target = 1, Reward = { Cash = 75, Gems = 3 } },
		{ Id = "line_reps_10", Title = "Train 10 Pull-Up Reps", Event = "PullUpRep", Target = 10, Reward = { Cash = 120, Gems = 5 } },
		{ Id = "line_bonus_1", Title = "Tap a Bonus Rep Pop-Up", Event = "BonusRep", Target = 1, Reward = { Cash = 200, Gems = 5 } },
		{ Id = "line_bait_2", Title = "Buy Berry Jelly Bait", Event = "BuyBait", Target = 2, MinBaitTier = 2, Reward = { Cash = 350, Gems = 8 } },
		{ Id = "line_zone_2", Title = "Reach Crystal Cave (Zone 2)", Event = "ReachZone", Target = 2, MinZone = 2, Reward = { Cash = 750, Gems = 10 } },
		{ Id = "line_discover_5", Title = "Discover 5 Slimes in the Index", Event = "Discover", Target = 5, Reward = { Cash = 1500, Gems = 12 } },
		{ Id = "line_perfect_1", Title = "Land a PERFECT! Throw", Event = "PerfectThrow", Target = 1, Reward = { Cash = 2500, Gems = 15 } },
		{ Id = "line_place_3", Title = "Place 3 Slimes on Your Plot", Event = "PlaceSlime", Target = 3, Reward = { Cash = 4000, Gems = 15 } },
		{ Id = "line_zone_3", Title = "Reach Lava Fields (Zone 3)", Event = "ReachZone", Target = 3, MinZone = 3, Reward = { Cash = 12000, Gems = 20 } },
		{ Id = "line_reps_100", Title = "Complete 100 Pull-Up Reps", Event = "PullUpRep", Target = 100, Reward = { Cash = 25000, Gems = 25 } },
		{ Id = "line_zone_4", Title = "Reach Frost Peaks (Zone 4)", Event = "ReachZone", Target = 4, MinZone = 4, Reward = { Cash = 80000, Gems = 40 } },
	} :: { QuestDef },
	DailyPool = {
		{ Id = "daily_throws_5", Title = "Throw Jelly 5 Times", Event = "Throw", Target = 5, Reward = { Gems = 5 } },
		{ Id = "daily_throws_15", Title = "Throw Jelly 15 Times", Event = "Throw", Target = 15, Reward = { Gems = 8 } },
		{ Id = "daily_reps_25", Title = "Do 25 Pull-Up Reps", Event = "PullUpRep", Target = 25, Reward = { Gems = 6 } },
		{ Id = "daily_bonus_3", Title = "Hit 3 Bonus Rep Pop-Ups", Event = "BonusRep", Target = 3, Reward = { Gems = 8 } },
		{ Id = "daily_perfect_2", Title = "Land 2 PERFECT! Throws", Event = "PerfectThrow", Target = 2, Reward = { Gems = 10 } },
		{ Id = "daily_rare_2", Title = "Catch 2 Rare+ Slimes", Event = "CatchRarity", Target = 2, MinRarityRank = 5, Reward = { Gems = 10 } },
		{ Id = "daily_place_2", Title = "Place 2 Slimes on Your Plot", Event = "PlaceSlime", Target = 2, Reward = { Cash = 500, Gems = 6 } },
		{ Id = "daily_cash_500", Title = "Earn $500 Cash from Throws", Event = "EarnCash", Target = 500, Reward = { Gems = 7 } },
	} :: { QuestDef },
}

GameConfig.QuestsById = {} :: { [string]: QuestDef }
for _, q in GameConfig.Quests.Line do
	GameConfig.QuestsById[q.Id] = q
end
for _, q in GameConfig.Quests.DailyPool do
	GameConfig.QuestsById[q.Id] = q
end

-- ============================================================================
-- ROBUX STORE: Developer Product Gem Packs & Game Passes (ProductId / PassId = 0 until published)
-- ============================================================================
local robuxPasses: { RobuxPassDef } = {
	{
		Id = "pass_extra_slots",
		Name = "+4 Plot Slots",
		Description = "Instantly unlock all 4 locked plot slots (8 -> 12 Slimes)!",
		RobuxPrice = 249,
		PassId = 0,
		Icon = "🧺",
		Color = { 95, 215, 125 },
		Category = "Core",
		UnlocksExtraSlots = true,
	},
	{
		Id = "pass_auto_throw",
		Name = "Auto-Throw",
		Description = "Auto-throws at the line with a 3 PERFECT / 2 GREAT bag!",
		RobuxPrice = 199,
		PassId = 0,
		Icon = "🤖",
		Color = { 80, 210, 230 },
		Category = "Core",
		UnlocksAutoThrow = true,
	},
	{
		Id = "pass_x2_cash",
		Name = "2x Money",
		Description = "Permanent 2x Cash from slimes & throws!",
		RobuxPrice = 199,
		PassId = 0,
		Icon = "💵",
		Color = { 55, 195, 250 },
		Category = "Core",
		TrackId = "money",
		Tier = 1,
		CashMultiplier = 2.0,
	},
	{
		Id = "pass_vip",
		Name = "VIP",
		Description = "+25% Cash, +25% Earned Gems & [VIP] chat tag!",
		RobuxPrice = 299,
		PassId = 0,
		Icon = "👑",
		Color = { 255, 195, 50 },
		Category = "Core",
		CashMultiplier = 1.25,
		GemMultiplier = 1.25,
		ChatTag = "[VIP]",
	},
}

-- Append tiered Luck, Gems & Training Power Game Passes directly from MultiplierTracks (single source of truth)
local trackPassCategory: { [string]: "Luck" | "Gems" | "Power" } = {
	luck = "Luck",
	gems = "Gems",
	power = "Power",
}
for _, trackId in { "luck", "gems", "power" } do
	local track = GameConfig.MultiplierTracksById[trackId]
	if track then
		local cat = trackPassCategory[trackId]
		for _, tier in track.Tiers do
			table.insert(robuxPasses, {
				Id = tier.PassId,
				Name = tier.Name,
				Description = tier.Description,
				RobuxPrice = tier.RobuxPrice,
				PassId = 0,
				Icon = if trackId == "luck" then "🍀" elseif trackId == "gems" then "💎" else "💪",
				Color = tier.Color,
				Category = cat,
				TrackId = track.Id,
				Tier = tier.Tier,
				LuckMultiplier = if trackId == "luck" then tier.Multiplier else nil,
				GemMultiplier = if trackId == "gems" then tier.Multiplier else nil,
				PowerMultiplier = if trackId == "power" then tier.Multiplier else nil,
			})
		end
	end
end

GameConfig.Robux = {
	MaxProcessedReceipts = 50,
	GemPacks = {
		{ Id = "pack_500", Name = "500 Gems", Gems = 500, RobuxPrice = 79, ProductId = 0, Icon = "💎", Color = { 80, 185, 255 } },
		{ Id = "pack_1500", Name = "1,500 Gems", Gems = 1500, RobuxPrice = 199, ProductId = 0, Icon = "💎", Color = { 65, 155, 245 }, BonusTag = "+20% Bonus" },
		{ Id = "pack_4000", Name = "4,000 Gems", Gems = 4000, RobuxPrice = 499, ProductId = 0, Icon = "💎", Color = { 145, 95, 250 }, BonusTag = "+30% Bonus" },
		{ Id = "pack_10000", Name = "10,000 Gems", Gems = 10000, RobuxPrice = 999, ProductId = 0, Icon = "💎", Color = { 255, 120, 210 }, BonusTag = "Best Value" },
	} :: { RobuxGemPackDef },
	Passes = robuxPasses,
}

GameConfig.RobuxGemPacksById = {} :: { [string]: RobuxGemPackDef }
GameConfig.RobuxGemPacksByProductId = {} :: { [number]: RobuxGemPackDef }
for _, pack in GameConfig.Robux.GemPacks do
	GameConfig.RobuxGemPacksById[pack.Id] = pack
	if pack.ProductId > 0 then
		GameConfig.RobuxGemPacksByProductId[pack.ProductId] = pack
	end
end

GameConfig.RobuxPassesById = {} :: { [string]: RobuxPassDef }
GameConfig.RobuxPassesByPassId = {} :: { [number]: RobuxPassDef }
for _, pass in GameConfig.Robux.Passes do
	GameConfig.RobuxPassesById[pass.Id] = pass
	if pass.PassId > 0 then
		GameConfig.RobuxPassesByPassId[pass.PassId] = pass
	end
end

function GameConfig.GetPowerUpgradeCost(currentLevel: number): number
	local lvl = math.max(1, math.floor(currentLevel))
	return math.floor(60 * (1.55 ^ (lvl - 1)))
end

function GameConfig.GetPowerUpgradeBonus(level: number): number
	local lvl = math.max(1, math.floor(level))
	if lvl <= 1 then
		return 0
	end
	return math.floor(8 * ((lvl - 1) ^ 1.55))
end

function GameConfig.FormatNumber(n: number): string
	local absN = math.abs(n)
	local sign = if n < 0 then "-" else ""
	if absN >= 1e9 then
		return string.format("%s%.2fB", sign, absN / 1e9)
	elseif absN >= 1e6 then
		return string.format("%s%.2fM", sign, absN / 1e6)
	elseif absN >= 1e3 then
		return string.format("%s%.1fK", sign, absN / 1e3)
	else
		return string.format("%s%d", sign, math.floor(absN + 0.5))
	end
end

-- Background music (MusicController.client.luau). Add Roblox audio asset ids (numbers) to Tracks; they play in a
-- shuffled loop. Empty = no music (the Settings window Music switch is still shown and saved).
GameConfig.Music = {
	Tracks = {} :: { number },
	Volume = 0.35,
}

return GameConfig
