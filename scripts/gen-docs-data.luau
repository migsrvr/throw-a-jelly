--!strict
--[[
	Generates docs/docs/DATA-REFERENCE.md from GameConfig.luau so the numbers in the designer docs can never
	drift from the code. Re-run after tuning anything in GameConfig:

		lune run scripts/gen-docs-data
]]

local fs = require("@lune/fs")

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local ProgressionLogic = require("../src/ReplicatedStorage/Shared/ProgressionLogic")

local OUT_PATH = "docs/docs/DATA-REFERENCE.md"

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
add("Stopping in the top band is a **PERFECT!** throw: a gold \"PERFECT! +20\" callout plus the biggest power bonus.")
add()
header({ "Band", "Colour", "Bonus Throw Power", "Luck multiplier", "Callout" })
for _, seg in GameConfig.MeterSegments do
	row({
		tostring(seg.Index),
		hex(seg.Color),
		"+" .. tostring(seg.BonusPower),
		`{string.format("%.2f", seg.LuckMultiplier)}x`,
		if seg.IsPerfect then "PERFECT!" else "",
	})
end
add()

-- Flight luck -----------------------------------------------------------------
add("## Flight luck")
add()
add("Luck decides how likely rarer slimes and mutations are. It is shown live as \"1.XXx LUCK\" while the bait flies,")
add(`and climbs the further the bait goes: +1.00x for every {GameConfig.FlightLuck.StudsPerExtraLuck} studs, multiplied by the meter band luck and the Jelly Bait luck.`)
add()
local zoneEnds = {}
for _, z in GameConfig.Zones do
	table.insert(zoneEnds, z.EndZ)
end
local luckHead = { "Bait \\ distance" }
for _, d in zoneEnds do
	table.insert(luckHead, `{d} studs`)
end
header(luckHead)
for _, bait in GameConfig.BaitTiers do
	local cells = { bait.Name }
	for _, d in zoneEnds do
		table.insert(cells, string.format("%.2fx", GameConfig.ComputeFlightLuck(d, 1.0, bait.LuckMultiplier)))
	end
	row(cells)
end
add()
add("(Table uses meter band 1. A PERFECT throw multiplies every value by the top band's luck.)")
add()

-- Jelly bait ------------------------------------------------------------------
add(`## Jelly Bait tiers ({#GameConfig.BaitTiers})`)
add()
add("Bought in the Shop. Better bait does not throw further; it multiplies the luck of every throw.")
add()
header({ "Tier", "Name", "Cost", "Luck multiplier", "Colour" })
for _, b in GameConfig.BaitTiers do
	row({
		tostring(b.Tier),
		b.Name,
		if b.Cost <= 0 then "(starting bait)" else "$" .. num(b.Cost),
		`{string.format("%.2f", b.LuckMultiplier)}x`,
		hex(b.Color),
	})
end
add()

-- Pull-up bar -----------------------------------------------------------------
add(`## Pull-up bar tiers ({#GameConfig.PullUpTiers})`)
add()
add("Training on the bar gives Training XP. A better bar gives more XP per rep and also does reps faster.")
add()
header({ "Tier", "Name", "Upgrade cost", "XP per rep", "Rep speed multiplier" })
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
add("### Strength levels")
add()
local tcfg = GameConfig.Training
add(`Training XP fills a level bar. Every level up gives **+{tcfg.PowerPerLevel} Throw Power** and a \"LEVEL UP!\" popup.`)
add(`While training, a **BONUS REP!** button pops up every {tcfg.BonusRepIntervalMin}-{tcfg.BonusRepIntervalMax} seconds; clicking it within {tcfg.BonusRepWindow}s gives {tcfg.BonusRepMultiplier}x the XP of one rep.`)
add()
header({ "Level", "XP to next level", "Total XP from level 1", "Throw Power from levels" })
local totalXp = 0
for lvl = 1, 50 do
	local req = GameConfig.GetXPRequiredForLevel(lvl)
	if lvl <= 10 or lvl % 10 == 0 then
		row({ tostring(lvl), num(req), num(totalXp), "+" .. num((lvl - 1) * tcfg.PowerPerLevel) })
	end
	totalXp += req
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
header({ "Item id", "Group", "Icon", "Paid with", "What it does", "Colour" })
local ACTION_TEXT: { [string]: string } = {
	PowerUpgrade = "Raises Throw Power by one upgrade level (price grows each level)",
	PullUpTier = "Upgrades the pull-up bar to the next tier",
	BaitTier = "Upgrades the Jelly Bait to the next quality tier (more luck)",
	SlotExpansion = "Unlocks locked Plot Slots 9-12 one-by-one with Gems (or all 4 via +4 Plot Slots Pass)",
	MultiplierTier = "Upgrades a permanent multiplier track (2x -> 4x -> 6x -> 8x -> 10x) with Gems or Robux Pass",
	Boost = "Permanent boost (see boosts below)",
	Egg = "Hatches 1 or 3 slimes with the odds listed below",
	FreeGift = "One-time free slime",
}
for _, item in GameConfig.ShopCatalog do
	local paidWith: string = item.PriceKind
	if item.Action == "Boost" then
		local boost = GameConfig.ShopBoosts[item.Args.BoostId or ""]
		paidWith = if boost then boost.PriceKind else paidWith
	end
	row({ item.Id, item.Category, item.Icon, paidWith, ACTION_TEXT[item.Action] or item.Action, hex(item.Color) })
end
add()

local function price(amount: number, kind: string): string
	return if kind == "Gems" then `{num(amount)} Gems` else "$" .. num(amount)
end

add("### Boosts")
add()
add("All boosts are permanent once bought.")
add()
header({ "Name", "Description", "Price", "Colour" })
for _, id in GameConfig.ShopBoostOrder do
	local b = GameConfig.ShopBoosts[id]
	row({ b.Name, b.Description, price(b.Cost, b.PriceKind), hex(b.Color) })
end
add()

add("### Eggs (Robux-only)")
add()
for _, egg in GameConfig.ShopEggs do
	add(`**{egg.Name}** (tag: "{egg.Tag}") - R$ {num(egg.Buy1Robux)} for 1 (ProductId {egg.Buy1ProductId}), R$ {num(egg.Buy3Robux)} for 3 (ProductId {egg.Buy3ProductId}). Accent colour {hex(egg.AccentColor)}.`)
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
local slotCosts = GameConfig.Slots.SlotUnlockGemCosts
add(`Every plot starts capped at {GameConfig.Slots.InitialMaxSlimes} slime slots. Slots 9-12 are locked and can only be unlocked 1-by-1 with Gems ({num(slotCosts[9])} / {num(slotCosts[10])} / {num(slotCosts[11])} / {num(slotCosts[12])} Gems) or all 4 at once via the "+4 Plot Slots" Robux Pass.`)
add()

-- Gems ------------------------------------------------------------------------
local g = GameConfig.Gems
add("## Gems (premium currency)")
add()
add("Shown as 💎 in the HUD and the shop. Earned slowly by playing (see `docs/docs/ECONOMY-BASELINE.md` for hourly F2P targets and the 8+ hour grind floor); spent in the Gem Upgrades tab or skipped via Robux Passes & Gem Packs.")
add()
add("### Index milestones (paid once each)")
add()
header({ "Slimes discovered", "Gems" })
for _, m in g.IndexMilestones do
	row({ tostring(m.Discovered), "+" .. num(m.Gems) })
end
add()
add("### First time reaching a zone (paid once per zone)")
add()
add("A throw that lands in a zone for the first time pays that zone and every zone before it that wasn't paid yet.")
add()
header({ "Zone", "Gems" })
for i, gems in g.FirstZoneReach do
	local z = GameConfig.Zones[i]
	row({ if z then `{z.Emoji} {z.Name}` else tostring(i), "+" .. num(gems) })
end
add()
add("### Daily login streak")
add()
add("Claimed manually once per UTC day in the Rewards window (7-day calendar). Missing a day restarts at day 1.")
add(`After day {#g.DailyRewards} the streak keeps paying the day-{#g.DailyRewards} amount.`)
add()
header({ "Streak day", "Gems" })
for day, gems in g.DailyRewards do
	row({ tostring(day), "+" .. num(gems) })
end
add()
add("### Rare catches (throws only, not eggs)")
add()
add("A caught slime pays its rarity amount plus its mutation amount (multiplied by owned 2x-10x Gems tiers & VIP). Anything not listed pays 0.")
add()
header({ "Rarity or mutation", "Gems" })
for _, r in RARITY_ORDER do
	if g.RarityDrops[r] then
		row({ r, "+" .. num(g.RarityDrops[r]) })
	end
end
for _, m in GameConfig.Mutations do
	if g.MutationDrops[m.Id] then
		row({ m.Id, "+" .. num(g.MutationDrops[m.Id]) })
	end
end
add()
add("### Auto-Throw")
add()
add(`Once unlocked (via Gems or the Auto-Throw Robux Pass), an AUTO toggle appears under the visible vertical throw meter.`)
add(`While ON, the meter smoothly locks onto the next target from a server-shuffled 5-throw bag ({GameConfig.AutoThrow.BagPerfectCount} PERFECT + {GameConfig.AutoThrow.BagGoodCount} GREAT per 5 throws) and fires after {GameConfig.AutoThrow.IdleDelaySeconds}s.`)
add()

-- Quests ----------------------------------------------------------------------
local function rewardStr(r: GameConfig.QuestReward): string
	local parts = {}
	if r.Gems and r.Gems > 0 then
		table.insert(parts, `{num(r.Gems)} Gems`)
	end
	if r.Cash and r.Cash > 0 then
		table.insert(parts, "$" .. num(r.Cash))
	end
	return table.concat(parts, " + ")
end

add("## Quests")
add()
add(`### Quest Line ({#GameConfig.Quests.Line} steps, linear, never resets)`)
add()
header({ "Step", "Id", "Title", "Event", "Target", "Reward" })
for i, q in GameConfig.Quests.Line do
	row({ tostring(i), q.Id, q.Title, q.Event, num(q.Target), rewardStr(q.Reward) })
end
add()
add(`### Daily Quest Pool ({#GameConfig.Quests.DailyPool} templates, {GameConfig.Quests.DailyCount} picked per UTC day)`)
add()
header({ "Id", "Title", "Event", "Target", "Reward" })
for _, q in GameConfig.Quests.DailyPool do
	row({ q.Id, q.Title, q.Event, num(q.Target), rewardStr(q.Reward) })
end
add()

-- Robux Store -----------------------------------------------------------------
add("## Robux Store")
add()
add("### Game Passes")
add()
header({ "Id", "Name", "Icon", "Robux (R$)", "PassId", "Effect", "Colour" })
for _, p in GameConfig.Robux.Passes do
	row({ p.Id, p.Name, p.Icon, tostring(p.RobuxPrice), tostring(p.PassId), p.Description, hex(p.Color) })
end
add()
add("### Gem Packs (Developer Products)")
add()
header({ "Id", "Name", "Tag", "Gems", "Robux (R$)", "ProductId" })
for _, pack in GameConfig.Robux.GemPacks do
	local tag = if pack.BonusTag and pack.BonusTag ~= "" then pack.BonusTag else "—"
	row({ pack.Id, pack.Name, tag, "+" .. num(pack.Gems), tostring(pack.RobuxPrice), tostring(pack.ProductId) })
end
add()

-- Saving ----------------------------------------------------------------------
add("## Saving")
add()
add(`Progress autosaves every {GameConfig.Save.AutosaveSeconds} seconds, when the player leaves, and when the server shuts down.`)
add("If a save can't be loaded, the player can still play but gets a \"Progress can't be saved this session.\" message.")
add()

fs.writeFile(OUT_PATH, table.concat(lines, "\n") .. "\n")
print(`Wrote {OUT_PATH} ({#lines} lines)`)
