--!strict
-- UiAssets: one place for every uploaded UI image.
-- Upload icons/png/*.png and textures/*.png (Asset Manager > Bulk Import), then paste the ids.
-- An id of 0 falls back to "" so missing art shows as empty instead of erroring.

local function id(n: number): string
	return if n == 0 then "" else "rbxassetid://" .. tostring(n)
end

local UiAssets = {}

UiAssets.Icons = {
	index = id(122964266056932),
	shop = id(115112628386837),
	upgrades = id(75049193734130),
	rewards = id(88086443908676),
	slimes = id(138692596543810),
	power = id(129385194558302),
	cash = id(95843756371445),
	gem = id(84852266184858),
	zone_meadow = id(95833572234056),
	zone_crystal = id(81011430503497),
	zone_lava = id(112516957372348),
	zone_frost = id(102027763007984),
	zone_candy = id(84189071484928),
	bolt = id(125165565486798),
	carrot = id(107343863504493),
	basket = id(102413380212113),
	robot = id(73777254553497),
	clover = id(95634176177918),
	crown = id(98063841395892),
	egg = id(113108961459378),
	rainbow = id(102563244473385),
	trophy = id(96299827636195),
	calendar = id(122268750286565),
	lock = id(118514275005016),
	check = id(126456008811565),
	star = id(102499238695699),
	world = id(132848839816984),
	lifter = id(72727052766774),
	clock = id(82458070721320),
	target = id(100323479606616),
	berry = id(118900445671999),
}

-- Custom Robux glyph (uploaded from assets/icons/robux_custom.png).
UiAssets.Robux = id(132883787627644)

UiAssets.Textures = {
	stripes = id(103666276895962), -- 256x256 tile. ImageLabel ScaleType=Tile, TileSize=UDim2.fromOffset(64,64), ImageTransparency=0.86
	sunburst = id(135080991548463), -- 512x512. Behind reveal slime and egg art, ImageTransparency=0.7, rotate 360 over 8 s
	glow = id(124543793891483), -- 256x256 radial. Selected slots, BONUS REP!, today tile. ImageColor3 = accent
	ring = id(92980164547029), -- 256x256. Reveal rings, hold-prompt progress (with UIGradient rotation)
	gloss = id(80213238149141), -- 64x128 vertical fade. Top 42% of nav buttons, ImageTransparency=0.45
}

return UiAssets
