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
}

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

export type ShopAction = "PowerUpgrade" | "PullUpTier" | "BaitTier" | "SlotExpansion" | "Boost" | "Egg" | "FreeGift"

-- Which wallet a shop item is paid from. Featured Eggs use "Robux" (Developer Products).
export type PriceKind = "Cash" | "Gems" | "Robux"

export type ShopCatalogItem = {
	Id: string,
	Category: "Upgrade" | "Boost" | "Egg" | "Gift" | "Gem",
	Action: ShopAction,
	Args: { BoostId: string?, EggId: string? },
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
	LuckMultiplier: number?,
	CashMultiplier: number?,
	ChatTag: string?,
}

GameConfig.Hub = {
	FloorY = 30.2,
	ThrowLineZ = -3.6,
	ThrowLineMinX = -62.0,
	ThrowLineMaxX = 62.0,
	LaneMinZ = 0.0,
	LaneMaxZ = 1200.0,
	ClearHalfWidth = 22.0,
}

GameConfig.Physics = {
	Gravity = 90.0,
	FixedDt = 1 / 60,
	MaxSimSeconds = 12.0,
	Restitution = 0.56,
	WallRestitution = 0.72,
	GateRestitution = 0.45,
	BounceThresholdVy = 8.0,
	MaxBounces = 6,
	RollingFriction = 22.0,
	AirDrag = 0.04,
	StopSpeedThreshold = 1.5,
	MinPitchDeg = 18.0,
	MaxPitchDeg = 55.0,
	DefaultPitchDeg = 36.0,
	MaxYawDeg = 18.0,
	BaseLaunchSpeed = 38.0,
	PowerSpeedScale = 14.5,
	PowerExponent = 0.42,
}

GameConfig.Slots = {
	InitialMaxSlimes = 8,
	ExpandedMaxSlimes = 12,
	TotalSlotParts = 12,
	ExpansionCost = 5000,
	ExpansionGemCost = 60, -- the same +4 slots, bought with Gems instead of Cash
}

-- Gems: the premium currency. Earned slowly in-game (Index milestones, first time reaching each zone,
-- daily login streak, rare slime catches) and spent on convenience upgrades (Auto-Throw, Lucky Charm,
-- extra slots). Robux gem packs are planned but not built (they need real developer product ids).
GameConfig.Gems = {
	-- Paid once each, the first time the Slime Index reaches this many discovered slimes
	IndexMilestones = {
		{ Discovered = 3, Gems = 10 },
		{ Discovered = 6, Gems = 15 },
		{ Discovered = 9, Gems = 25 },
		{ Discovered = 12, Gems = 40 },
		{ Discovered = 15, Gems = 75 },
	},
	-- Zone index -> Gems paid the first time a throw lands in that zone (reaching zone N pays every zone up to N)
	FirstZoneReach = { 5, 15, 30, 50, 80 },
	-- Daily login streak: day 1..7 reward; day 8+ keeps paying the last value. Missing a day resets to day 1.
	DailyRewards = { 5, 8, 10, 12, 15, 20, 35 },
	SecondsPerDay = 86400, -- days are counted in UTC from os.time()
	-- Rare catches from throws (eggs don't pay, so Cash can't be turned straight into Gems)
	RarityDrops = { Legendary = 3, Mythic = 8 } :: { [string]: number },
	MutationDrops = { CRYSTAL = 3, RAINBOW = 6 } :: { [string]: number },
}

-- Auto-Throw (bought with Gems): throws by itself whenever you stand idle at the throw line.
-- It always stops the meter at MeterRatio, so a timed PERFECT by hand stays better.
GameConfig.AutoThrow = {
	MeterRatio = 0.5, -- band 5 (+9 power, 1.15x luck)
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

-- 9-Segment Vertical Throw Meter (bottom segment 1 = Red -> top segment 9 = Bright Green).
-- Bonus Throw Power runs 0-20; stopping in the top band is a "PERFECT!" (+20).
GameConfig.MeterSegments = {
	{ Index = 1, Color = { 235, 65, 55 }, BonusPower = 1, LuckMultiplier = 1.00 },
	{ Index = 2, Color = { 245, 105, 50 }, BonusPower = 3, LuckMultiplier = 1.03 },
	{ Index = 3, Color = { 250, 145, 50 }, BonusPower = 5, LuckMultiplier = 1.06 },
	{ Index = 4, Color = { 255, 185, 55 }, BonusPower = 7, LuckMultiplier = 1.10 },
	{ Index = 5, Color = { 245, 220, 60 }, BonusPower = 9, LuckMultiplier = 1.15 },
	{ Index = 6, Color = { 205, 235, 65 }, BonusPower = 12, LuckMultiplier = 1.22 },
	{ Index = 7, Color = { 160, 240, 75 }, BonusPower = 14, LuckMultiplier = 1.32 },
	{ Index = 8, Color = { 115, 245, 85 }, BonusPower = 17, LuckMultiplier = 1.48 },
	{ Index = 9, Color = { 70, 250, 105 }, BonusPower = 20, LuckMultiplier = 1.75, IsPerfect = true },
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

-- Jelly Bait quality tiers (bought in the Shop): multiplies rarity & mutation luck inside the zone you reach.
GameConfig.BaitTiers = {
	{ Tier = 1, Name = "Carrot Jelly", Cost = 0, LuckMultiplier = 1.00, Color = { 255, 125, 40 } },
	{ Tier = 2, Name = "Berry Jelly", Cost = 150, LuckMultiplier = 1.35, Color = { 200, 70, 160 } },
	{ Tier = 3, Name = "Crystal Honey", Cost = 900, LuckMultiplier = 1.85, Color = { 255, 205, 70 } },
	{ Tier = 4, Name = "Magma Tart", Cost = 4500, LuckMultiplier = 2.60, Color = { 255, 95, 45 } },
	{ Tier = 5, Name = "Starlight Cake", Cost = 22000, LuckMultiplier = 4.00, Color = { 170, 150, 255 } },
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
		DropWeight = 65,
		BaseOdds = 2,
		Color = { 110, 235, 115 },
		CoreColor = { 195, 255, 175 },
		Scale = 1.0,
		IncomePerSec = 2,
		ThrowBonus = 0,
		Weight = 1.0,
	},
	{
		Id = "meadow_honey",
		Name = "Honey Slime",
		ShortWord = "HONEY",
		ZoneIndex = 1,
		Rarity = "Uncommon",
		RarityRank = 2,
		DropWeight = 27,
		BaseOdds = 5,
		Color = { 255, 200, 65 },
		CoreColor = { 255, 240, 150 },
		Scale = 1.08,
		IncomePerSec = 5,
		ThrowBonus = 4,
		Weight = 0.96,
	},
	{
		Id = "meadow_bloom",
		Name = "Sakura Bloom Slime",
		ShortWord = "SAKURA",
		ZoneIndex = 1,
		Rarity = "Rare",
		RarityRank = 3,
		DropWeight = 8,
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
		Id = "crystal_quartz",
		Name = "Quartz Slime",
		ShortWord = "QUARTZ",
		ZoneIndex = 2,
		Rarity = "Uncommon",
		RarityRank = 4,
		DropWeight = 62,
		BaseOdds = 3,
		Color = { 110, 205, 255 },
		CoreColor = { 200, 245, 255 },
		Scale = 1.1,
		IncomePerSec = 18,
		ThrowBonus = 15,
		Weight = 1.0,
	},
	{
		Id = "crystal_amethyst",
		Name = "Amethyst Slime",
		ShortWord = "AMETHYST",
		ZoneIndex = 2,
		Rarity = "Rare",
		RarityRank = 5,
		DropWeight = 28,
		BaseOdds = 8,
		Color = { 180, 115, 255 },
		CoreColor = { 235, 195, 255 },
		Scale = 1.18,
		IncomePerSec = 38,
		ThrowBonus = 32,
		Weight = 0.94,
	},
	{
		Id = "crystal_prism",
		Name = "Prism Geode Slime",
		ShortWord = "PRISM",
		ZoneIndex = 2,
		Rarity = "Epic",
		RarityRank = 6,
		DropWeight = 10,
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
		RarityRank = 7,
		DropWeight = 62,
		BaseOdds = 4,
		Color = { 255, 115, 55 },
		CoreColor = { 255, 215, 95 },
		Scale = 1.15,
		IncomePerSec = 110,
		ThrowBonus = 95,
		Weight = 0.95,
	},
	{
		Id = "lava_obsidian",
		Name = "Obsidian Core Slime",
		ShortWord = "OBSIDIAN",
		ZoneIndex = 3,
		Rarity = "Epic",
		RarityRank = 8,
		DropWeight = 28,
		BaseOdds = 12,
		Color = { 75, 55, 95 },
		CoreColor = { 255, 95, 40 },
		Scale = 1.24,
		IncomePerSec = 220,
		ThrowBonus = 180,
		Weight = 0.90,
	},
	{
		Id = "lava_solar",
		Name = "Solar Flare Slime",
		ShortWord = "SOLAR",
		ZoneIndex = 3,
		Rarity = "Legendary",
		RarityRank = 9,
		DropWeight = 10,
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
		Id = "frost_glacier",
		Name = "Glacier Slime",
		ShortWord = "GLACIER",
		ZoneIndex = 4,
		Rarity = "Epic",
		RarityRank = 10,
		DropWeight = 62,
		BaseOdds = 6,
		Color = { 135, 225, 255 },
		CoreColor = { 225, 250, 255 },
		Scale = 1.2,
		IncomePerSec = 650,
		ThrowBonus = 480,
		Weight = 0.92,
	},
	{
		Id = "frost_aurora",
		Name = "Aurora Borealis Slime",
		ShortWord = "AURORA",
		ZoneIndex = 4,
		Rarity = "Legendary",
		RarityRank = 11,
		DropWeight = 28,
		BaseOdds = 18,
		Color = { 90, 255, 195 },
		CoreColor = { 195, 140, 255 },
		Scale = 1.28,
		IncomePerSec = 1350,
		ThrowBonus = 900,
		Weight = 0.86,
	},
	{
		Id = "frost_cryo",
		Name = "Cryo Monarch Slime",
		ShortWord = "MONARCH",
		ZoneIndex = 4,
		Rarity = "Mythic",
		RarityRank = 12,
		DropWeight = 10,
		BaseOdds = 55,
		Color = { 70, 165, 255 },
		CoreColor = { 255, 255, 255 },
		Scale = 1.38,
		IncomePerSec = 2800,
		ThrowBonus = 1650,
		Weight = 0.80,
	},

	-- Zone 5: Candy Land
	{
		Id = "candy_gumdrop",
		Name = "Gumdrop Slime",
		ShortWord = "GUMDROP",
		ZoneIndex = 5,
		Rarity = "Legendary",
		RarityRank = 13,
		DropWeight = 62,
		BaseOdds = 10,
		Color = { 255, 120, 190 },
		CoreColor = { 255, 225, 240 },
		Scale = 1.25,
		IncomePerSec = 4200,
		ThrowBonus = 2400,
		Weight = 0.88,
	},
	{
		Id = "candy_cotton",
		Name = "Cotton Cloud Slime",
		ShortWord = "COTTON",
		ZoneIndex = 5,
		Rarity = "Mythic",
		RarityRank = 14,
		DropWeight = 28,
		BaseOdds = 30,
		Color = { 195, 145, 255 },
		CoreColor = { 130, 235, 255 },
		Scale = 1.35,
		IncomePerSec = 9000,
		ThrowBonus = 4200,
		Weight = 0.82,
	},
	{
		Id = "candy_royal",
		Name = "Royal Sugar King Slime",
		ShortWord = "SUGARKING",
		ZoneIndex = 5,
		Rarity = "Mythic",
		RarityRank = 15,
		DropWeight = 10,
		BaseOdds = 95,
		Color = { 255, 215, 75 },
		CoreColor = { 255, 105, 185 },
		Scale = 1.48,
		IncomePerSec = 20000,
		ThrowBonus = 7500,
		Weight = 0.76,
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

GameConfig.PullUpTiers = {
	{ Tier = 1, Name = "PULL-UP BAR", Cost = 0, XPPerRep = 2, SpeedMult = 1.0 },
	{ Tier = 2, Name = "IRON BAR", Cost = 75, XPPerRep = 8, SpeedMult = 1.15 },
	{ Tier = 3, Name = "CRYSTAL BAR", Cost = 450, XPPerRep = 32, SpeedMult = 1.3 },
	{ Tier = 4, Name = "MAGMA BAR", Cost = 2500, XPPerRep = 140, SpeedMult = 1.5 },
	{ Tier = 5, Name = "STARLIGHT BAR", Cost = 15000, XPPerRep = 600, SpeedMult = 1.75 },
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

GameConfig.ShopBoosts = {
	double_cash = {
		Id = "double_cash",
		Name = "x2 Cash",
		Description = "Double cash from every slime!",
		Cost = 500,
		PriceKind = "Cash",
		Color = { 65, 190, 255 },
	},
	double_power = {
		Id = "double_power",
		Name = "x2 Training Power",
		Description = "Double XP on every pull-up!",
		Cost = 750,
		PriceKind = "Cash",
		Color = { 165, 110, 255 },
	},
	auto_throw = {
		Id = "auto_throw",
		Name = "Auto-Throw",
		Description = "Throws for you while you stand at the throw line!",
		Cost = 150,
		PriceKind = "Gems",
		Color = { 80, 210, 230 },
	},
	lucky_charm = {
		Id = "lucky_charm",
		Name = "Lucky Charm",
		Description = "x1.5 Luck on every throw!",
		Cost = 120,
		PriceKind = "Gems",
		Color = { 90, 225, 120 },
		LuckMultiplier = 1.5,
	},
} :: { [string]: ShopBoostDef }

-- Display order for boost tables (ShopBoosts is keyed by id, so it has no order of its own)
GameConfig.ShopBoostOrder = { "double_cash", "double_power", "auto_throw", "lucky_charm" }

GameConfig.FreeGift = {
	SlimeId = "meadow_bloom",
	Mutation = "EMERALD" :: "EMERALD",
	Title = "Free Slime!",
	Subtitle = "Claim your free Emerald Sakura Slime!",
}

--[[
	Shop catalog: the single list of everything purchasable. Prices/names are NOT stored here;
	they are read from the tables above (PullUpTiers, ShopEggs, ShopBoosts, Slots, GetPowerUpgradeCost)
	by ProgressionLogic.GetShopListing, so each number lives in exactly one place.
	Adding an item = add a row here (+ its data in the table it points to). See docs/shop-catalog.md.
]]
GameConfig.ShopCatalog = {
	{ Id = "power_upgrade", Category = "Upgrade", Action = "PowerUpgrade", Args = {}, Icon = "⚡", Color = { 235, 150, 45 }, PriceKind = "Cash" },
	{ Id = "pullup_tier", Category = "Upgrade", Action = "PullUpTier", Args = {}, Icon = "💪", Color = { 55, 155, 240 }, PriceKind = "Cash" },
	{ Id = "bait_tier", Category = "Upgrade", Action = "BaitTier", Args = {}, Icon = "🥕", Color = { 255, 125, 40 }, PriceKind = "Cash" },
	{ Id = "slot_expansion", Category = "Upgrade", Action = "SlotExpansion", Args = {}, Icon = "🧺", Color = { 95, 200, 120 }, PriceKind = "Cash" },
	{ Id = "boost_double_cash", Category = "Boost", Action = "Boost", Args = { BoostId = "double_cash" }, Icon = "💵", Color = { 45, 185, 235 }, PriceKind = "Cash" },
	{ Id = "boost_double_power", Category = "Boost", Action = "Boost", Args = { BoostId = "double_power" }, Icon = "💪", Color = { 165, 95, 245 }, PriceKind = "Cash" },
	{ Id = "egg_enchanted", Category = "Egg", Action = "Egg", Args = { EggId = "enchanted_egg" }, Icon = "🥚", Color = { 175, 110, 255 }, PriceKind = "Robux" },
	{ Id = "egg_rainbow", Category = "Egg", Action = "Egg", Args = { EggId = "rainbow_egg" }, Icon = "🌈", Color = { 255, 120, 200 }, PriceKind = "Robux" },
	{ Id = "free_gift", Category = "Gift", Action = "FreeGift", Args = {}, Icon = "🎁", Color = { 255, 205, 55 }, PriceKind = "Cash" },
	-- Gem items (PriceKind = "Gems": paid from the Gems wallet)
	{ Id = "gem_auto_throw", Category = "Gem", Action = "Boost", Args = { BoostId = "auto_throw" }, Icon = "🤖", Color = { 80, 210, 230 }, PriceKind = "Gems" },
	{ Id = "gem_lucky_charm", Category = "Gem", Action = "Boost", Args = { BoostId = "lucky_charm" }, Icon = "🍀", Color = { 90, 225, 120 }, PriceKind = "Gems" },
	{ Id = "gem_slot_expansion", Category = "Gem", Action = "SlotExpansion", Args = {}, Icon = "🧺", Color = { 95, 200, 120 }, PriceKind = "Gems" },
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
		{ Id = "line_throw_1", Title = "Throw Jelly Once", Event = "Throw", Target = 1, Reward = { Cash = 25, Gems = 5 } },
		{ Id = "line_place_1", Title = "Place a Slime on Your Plot", Event = "PlaceSlime", Target = 1, Reward = { Cash = 50, Gems = 5 } },
		{ Id = "line_reps_10", Title = "Train 10 Pull-Up Reps", Event = "PullUpRep", Target = 10, Reward = { Cash = 75, Gems = 8 } },
		{ Id = "line_bonus_1", Title = "Tap a Bonus Rep Pop-Up", Event = "BonusRep", Target = 1, Reward = { Cash = 100, Gems = 10 } },
		{ Id = "line_bait_2", Title = "Buy Berry Jelly Bait", Event = "BuyBait", Target = 2, MinBaitTier = 2, Reward = { Cash = 150, Gems = 10 } },
		{ Id = "line_zone_2", Title = "Reach Crystal Cave (Zone 2)", Event = "ReachZone", Target = 2, MinZone = 2, Reward = { Cash = 250, Gems = 15 } },
		{ Id = "line_discover_5", Title = "Discover 5 Slimes in the Index", Event = "Discover", Target = 5, Reward = { Cash = 400, Gems = 15 } },
		{ Id = "line_perfect_1", Title = "Land a PERFECT! Throw", Event = "PerfectThrow", Target = 1, Reward = { Cash = 600, Gems = 20 } },
		{ Id = "line_place_3", Title = "Place 3 Slimes on Your Plot", Event = "PlaceSlime", Target = 3, Reward = { Cash = 1000, Gems = 20 } },
		{ Id = "line_zone_3", Title = "Reach Lava Fields (Zone 3)", Event = "ReachZone", Target = 3, MinZone = 3, Reward = { Cash = 2000, Gems = 30 } },
		{ Id = "line_reps_100", Title = "Complete 100 Pull-Up Reps", Event = "PullUpRep", Target = 100, Reward = { Cash = 4000, Gems = 40 } },
		{ Id = "line_zone_4", Title = "Reach Frost Peaks (Zone 4)", Event = "ReachZone", Target = 4, MinZone = 4, Reward = { Cash = 10000, Gems = 60 } },
	} :: { QuestDef },
	DailyPool = {
		{ Id = "daily_throws_5", Title = "Throw Jelly 5 Times", Event = "Throw", Target = 5, Reward = { Gems = 8 } },
		{ Id = "daily_throws_15", Title = "Throw Jelly 15 Times", Event = "Throw", Target = 15, Reward = { Gems = 15 } },
		{ Id = "daily_reps_25", Title = "Do 25 Pull-Up Reps", Event = "PullUpRep", Target = 25, Reward = { Gems = 10 } },
		{ Id = "daily_bonus_3", Title = "Hit 3 Bonus Rep Pop-Ups", Event = "BonusRep", Target = 3, Reward = { Gems = 12 } },
		{ Id = "daily_perfect_2", Title = "Land 2 PERFECT! Throws", Event = "PerfectThrow", Target = 2, Reward = { Gems = 15 } },
		{ Id = "daily_rare_2", Title = "Catch 2 Rare+ Slimes", Event = "CatchRarity", Target = 2, MinRarityRank = 3, Reward = { Gems = 15 } },
		{ Id = "daily_place_2", Title = "Place 2 Slimes on Your Plot", Event = "PlaceSlime", Target = 2, Reward = { Cash = 300, Gems = 10 } },
		{ Id = "daily_cash_500", Title = "Earn $500 Cash from Throws", Event = "EarnCash", Target = 500, Reward = { Gems = 10 } },
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
GameConfig.Robux = {
	MaxProcessedReceipts = 50,
	GemPacks = {
		{ Id = "pack_100", Name = "100 Gems", Gems = 100, RobuxPrice = 25, ProductId = 0, Icon = "💎", Color = { 80, 185, 255 } },
		{ Id = "pack_550", Name = "550 Gems", Gems = 550, RobuxPrice = 99, ProductId = 0, Icon = "💎", Color = { 65, 155, 245 }, BonusTag = "+10% Bonus" },
		{ Id = "pack_1200", Name = "1,200 Gems", Gems = 1200, RobuxPrice = 199, ProductId = 0, Icon = "💎", Color = { 145, 95, 250 }, BonusTag = "+20% Bonus" },
		{ Id = "pack_2600", Name = "2,600 Gems", Gems = 2600, RobuxPrice = 399, ProductId = 0, Icon = "💎", Color = { 255, 120, 210 }, BonusTag = "Best Value" },
	} :: { RobuxGemPackDef },
	Passes = {
		{ Id = "pass_x2_luck", Name = "x2 Luck", Description = "Permanent 2x Luck on every throw!", RobuxPrice = 149, PassId = 0, Icon = "🍀", Color = { 85, 225, 115 }, LuckMultiplier = 2.0 },
		{ Id = "pass_x2_cash", Name = "x2 Cash", Description = "Permanent 2x Cash from slimes & throws!", RobuxPrice = 149, PassId = 0, Icon = "💵", Color = { 55, 190, 250 }, CashMultiplier = 2.0 },
		{ Id = "pass_vip", Name = "VIP", Description = "+10% Cash income and [VIP] chat tag!", RobuxPrice = 249, PassId = 0, Icon = "👑", Color = { 255, 195, 50 }, CashMultiplier = 1.10, ChatTag = "[VIP]" },
	} :: { RobuxPassDef },
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
	return math.floor(25 * (1.65 ^ (lvl - 1)))
end

function GameConfig.GetPowerUpgradeBonus(level: number): number
	local lvl = math.max(1, math.floor(level))
	if lvl <= 1 then
		return 0
	end
	return math.floor(12 * ((lvl - 1) ^ 1.55))
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

return GameConfig
