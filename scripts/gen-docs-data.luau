--!strict
--[[
	Generates docs/DATA-REFERENCE.md from GameConfig.luau so the numbers in the designer docs can never
	drift from the code. Re-run after tuning anything in GameConfig:

		lune run scripts/gen-docs-data
]]

local fs = require("@lune/fs")

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local ProgressionLogic = require("../src/ReplicatedStorage/Shared/ProgressionLogic")

local OUT_PATH = "docs/DATA-REFERENCE.md"

-- Copied from SlimeFactory.RARITY_COLORS (that module needs Roblox services, so Lune can't load it).
-- If you change rarity colours in SlimeFactory.luau, change them here too.
local RARITY_COLORS: { [string]: { number } } = {
	Common = { 200, 235, 200 },
	Uncommon = { 120, 240, 145 },
	Rare = { 100, 195, 255 },
	Epic = { 205, 130, 255 },
	Legendary = { 255, 205, 70 },
	Mythic = { 255, 110, 195 },
}
local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

local lines: { string } = {}
local function add(s: string?)
	table.insert(lines, s or "")
end

local function hex(rgb: { number }): string
	return string.format("#%02X%02X%02X", rgb[1] or 255, rgb[2] or 255, rgb[3] or 255)
end

local function num(n: number): string
	return GameConfig.FormatNumber(n)
end

local function pct(n: number): string
	return string.format("%g%%", n)
end

local function row(cells: { string })
	add("| " .. table.concat(cells, " | ") .. " |")
end

local function header(cells: { string })
	row(cells)
	local seps = {}
	for _ = 1, #cells do
		table.insert(seps, "---")
	end
	row(seps)
end

-- ---------------------------------------------------------------------------
add("# Data reference (names, numbers, colours)")
add()
add("> **Generated file. Do not edit by hand.** It is produced from the game's configuration by")
add("> `lune run scripts/gen-docs-data`, so it always matches the game. Colours are given as hex codes.")
add("> If a number looks wrong, it is tuned in `src/ReplicatedStorage/Shared/GameConfig.luau`, not here.")
add()
add("Use this for layout and copywriting: longest names, how many items fit in a row, which colours go with what.")
add()

-- Zones -----------------------------------------------------------------------
add("## Zones (5)")
add()
add("A zone is a stretch of the throwing lane. Where the bait lands decides which slimes can be caught.")
add("Reaching a zone needs enough Throw Power. Catching every slime in a zone unlocks that zone's trail.")
add()
header({ "#", "Name", "Icon", "Colour", "Lane distance (studs)", "Throw Power needed", "Cash per stud", "Trail", "Trail bonus" })
for _, z in GameConfig.Zones do
	row({
		tostring(z.Index),
		z.Name,
		z.Emoji,
		hex(z.ThemeColor),
		`{z.StartZ} - {z.EndZ}`,
		num(z.RequiredThrowPower),
		tostring(z.CashPerStud),
		z.TrailName,
		z.TrailBonusText,
	})
end
add()

-- Rarity ----------------------------------------------------------------------
add("## Rarity colours")
add()
add("Used for slime card backgrounds, names and borders. Six levels, from most to least common.")
add()
header({ "Rarity", "Colour" })
for _, r in RARITY_ORDER do
	row({ r, hex(RARITY_COLORS[r]) })
end
add()

-- Slimes ----------------------------------------------------------------------
add(`## Slimes ({#GameConfig.Slimes})`)
add()
add("Each zone has three slimes. \"Chance\" is the share of catches in that zone before any luck bonus.")
add("\"Income\" is what a normal (non-mutated) slime earns per second while placed on a plot slot.")
add("\"Short word\" is the big word shown in the reveal screen.")
add()
header({ "Zone", "Name", "Short word", "Rarity", "Chance in zone", "Income / sec", "Throw Power bonus", "Body colour", "Core colour" })
for _, z in GameConfig.Zones do
	local pool = GameConfig.SlimesByZone[z.Index] or {}
	local total = 0
	for _, s in pool do
		total += s.DropWeight
	end
	for _, s in pool do
		row({
			`{z.Emoji} {z.Name}`,
			s.Name,
			s.ShortWord,
			s.Rarity,
			pct(math.floor(s.DropWeight / total * 1000 + 0.5) / 10),
			"$" .. num(s.IncomePerSec),
			"+" .. num(s.ThrowBonus),
			hex(s.Color),
			hex(s.CoreColor),
		})
	end
end
add()

-- Mutations -------------------------------------------------------------------
add(`## Mutations ({#GameConfig.Mutations})`)
add()
add("A mutation is a bonus variant that any slime can roll. It tints the slime and multiplies its income.")
add("\"Normal\" has no name or label in the UI.")
add()
header({ "Mutation", "Income multiplier", "Roll weight", "\"1 in X\" odds get this much longer", "Colour" })
for _, m in GameConfig.Mutations do
	row({
		if m.Name == "" then "(Normal - no label)" else m.Name,
		`x{m.IncomeMultiplier}`,
		tostring(m.Weight),
		`x{m.OddsMultiplier}`,
		hex(m.Color),
	})
end
add()

-- Meter -----------------------------------------------------------------------
add(`## Throw meter segments ({#GameConfig.MeterSegments})`)
add()
add("The vertical meter has nine coloured bands. Where the slider stops decides the bonus. Bottom = band 1 (worst).")
add()
header({ "Band", "Colour", "Bonus Throw Power", "Luck multiplier" })
for _, seg in GameConfig.MeterSegments do
	row({ tostring(seg.Index), hex(seg.Color), "+" .. tostring(seg.BonusPower), `{string.format("%.2f", seg.LuckMultiplier)}x` })
end
add()

-- Pull-up bar -----------------------------------------------------------------
add(`## Pull-up bar tiers ({#GameConfig.PullUpTiers})`)
add()
add("Training on the bar adds Throw Power. A better bar gives more power per rep and also does reps faster.")
add()
header({ "Tier", "Name", "Upgrade cost", "Power per rep", "Rep speed multiplier" })
for _, t in GameConfig.PullUpTiers do
	row({
		tostring(t.Tier),
		t.Name,
		if t.Cost <= 0 then "(starting bar)" else "$" .. num(t.Cost),
		"+" .. num(t.XPPerRep),
		`x{t.SpeedMult}`,
	})
end
add()
add("### How long one pull-up takes")
add()
add(`Seconds per rep. It gets faster as the player gets stronger and with better bars, never slower than {GameConfig.PullUp.BaseRepSeconds}s and never faster than {GameConfig.PullUp.MinRepSeconds}s.`)
add("The rep animation is played at exactly this speed.")
add()
local powers = { 5, 50, 200, 1000, 5000, 20000 }
local head = { "Throw Power (strength)" }
for _, t in GameConfig.PullUpTiers do
	table.insert(head, t.Name)
end
header(head)
for _, p in powers do
	local cells = { num(p) }
	for tierIndex = 1, #GameConfig.PullUpTiers do
		local sec = ProgressionLogic.GetPullUpRepInterval({ BaseThrowPower = p, PullUpTier = tierIndex })
		table.insert(cells, string.format("%.2fs", sec))
	end
	row(cells)
end
add()

-- Shop ------------------------------------------------------------------------
add("## Shop")
add()
add("### Shop items in display order")
add()
add("These are the shop's building blocks. A button or card in the shop = one row here.")
add()
header({ "Item id", "Group", "Icon", "What it does", "Colour" })
local ACTION_TEXT: { [string]: string } = {
	PowerUpgrade = "Raises Throw Power by one upgrade level (price grows each level)",
	PullUpTier = "Upgrades the pull-up bar to the next tier",
	SlotExpansion = "Adds 4 more slime slots to the plot (8 to 12)",
	Boost = "Permanent boost (see boosts below)",
	Egg = "Hatches 1 or 3 slimes with the odds listed below",
	FreeGift = "One-time free slime",
}
for _, item in GameConfig.ShopCatalog do
	row({ item.Id, item.Category, item.Icon, ACTION_TEXT[item.Action] or item.Action, hex(item.Color) })
end
add()

add("### Boosts")
add()
header({ "Name", "Description", "Price", "Colour" })
for _, id in { "double_cash", "double_power" } do
	local b = (GameConfig.ShopBoosts :: any)[id]
	row({ b.Name, b.Description, "$" .. num(b.Cost), hex(b.Color) })
end
add()

add("### Eggs")
add()
for _, egg in GameConfig.ShopEggs do
	add(`**{egg.Name}** (tag: "{egg.Tag}") - ${num(egg.Buy1Cost)} for 1, ${num(egg.Buy3Cost)} for 3. Accent colour {hex(egg.AccentColor)}.`)
	add()
	header({ "Slime", "Mutation", "Chance", "Bonus label shown on the card" })
	for _, item in egg.Items do
		local def = GameConfig.SlimesById[item.SlimeId]
		row({ if def then def.Name else item.SlimeId, item.Mutation, pct(item.ChancePercent), item.BonusLabel })
	end
	add()
end

add("### Free gift")
add()
local gift = GameConfig.FreeGift
local giftDef = GameConfig.SlimesById[gift.SlimeId]
add(`"{gift.Title}" - "{gift.Subtitle}" ({if giftDef then giftDef.Name else gift.SlimeId}, {gift.Mutation}). Can be claimed once per player.`)
add()

-- Plot ------------------------------------------------------------------------
add("## Plot slots")
add()
add(`Every plot starts with {GameConfig.Slots.InitialMaxSlimes} slime slots; a one-time purchase of ${num(GameConfig.Slots.ExpansionCost)} unlocks all {GameConfig.Slots.ExpandedMaxSlimes}.`)
add()

fs.writeFile(OUT_PATH, table.concat(lines, "\n") .. "\n")
print(`Wrote {OUT_PATH} ({#lines} lines)`)
