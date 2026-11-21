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
}

export type PullUpTierDef = {
	Tier: number,
	Name: string,
	Cost: number,
	XPPerRep: number,
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
	Buy1Cost: number,
	Buy3Cost: number,
	AccentColor: RGB,
	Items: { ShopEggItem },
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
}

-- 9-Segment Vertical Throw Meter (bottom segment 1 = Red -> top segment 9 = Bright Green)
GameConfig.MeterSegments = {
	{ Index = 1, Color = { 235, 65, 55 }, BonusPower = 1, LuckMultiplier = 1.00 },
	{ Index = 2, Color = { 245, 105, 50 }, BonusPower = 3, LuckMultiplier = 1.03 },
	{ Index = 3, Color = { 250, 145, 50 }, BonusPower = 5, LuckMultiplier = 1.06 },
	{ Index = 4, Color = { 255, 185, 55 }, BonusPower = 8, LuckMultiplier = 1.10 },
	{ Index = 5, Color = { 245, 220, 60 }, BonusPower = 11, LuckMultiplier = 1.15 },
	{ Index = 6, Color = { 205, 235, 65 }, BonusPower = 14, LuckMultiplier = 1.22 },
	{ Index = 7, Color = { 160, 240, 75 }, BonusPower = 17, LuckMultiplier = 1.32 },
	{ Index = 8, Color = { 115, 245, 85 }, BonusPower = 21, LuckMultiplier = 1.48 },
	{ Index = 9, Color = { 70, 250, 105 }, BonusPower = 25, LuckMultiplier = 1.75 },
} :: { MeterSegmentDef }

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
	{ Tier = 1, Name = "PULL-UP BAR", Cost = 0, XPPerRep = 2 },
	{ Tier = 2, Name = "IRON BAR", Cost = 75, XPPerRep = 8 },
	{ Tier = 3, Name = "CRYSTAL BAR", Cost = 450, XPPerRep = 32 },
	{ Tier = 4, Name = "MAGMA BAR", Cost = 2500, XPPerRep = 140 },
	{ Tier = 5, Name = "STARLIGHT BAR", Cost = 15000, XPPerRep = 600 },
} :: { PullUpTierDef }

GameConfig.ShopEggs = {
	{
		Id = "enchanted_egg",
		Name = "ENCHANTED EGG",
		Tag = "New!",
		Buy1Cost = 120,
		Buy3Cost = 320,
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
		Buy1Cost = 1500,
		Buy3Cost = 4000,
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
for _, egg in GameConfig.ShopEggs do
	GameConfig.ShopEggsById[egg.Id] = egg
end

GameConfig.ShopBoosts = {
	double_cash = {
		Id = "double_cash",
		Name = "x2 Cash",
		Description = "Double cash from every slime!",
		Cost = 500,
		Color = { 65, 190, 255 },
	},
	double_power = {
		Id = "double_power",
		Name = "x2 Training Power",
		Description = "Double XP on every pull-up!",
		Cost = 750,
		Color = { 165, 110, 255 },
	},
}

GameConfig.FreeGift = {
	SlimeId = "meadow_bloom",
	Mutation = "EMERALD" :: "EMERALD",
	Title = "Free Slime!",
	Subtitle = "Claim your free Emerald Sakura Slime!",
}

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
