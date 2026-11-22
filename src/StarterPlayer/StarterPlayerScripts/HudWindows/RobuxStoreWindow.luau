--!strict
--[[
	RobuxStoreWindow.luau
	Shop modal (docs/docs/UI-MOCKUP-SPEC.md 3b, 4c, 4h). Built only from UiKit.
	Scrolls: Featured eggs (full card + compact LIMITED card) -> Game Passes -> Gem Packs -> Free Gift.
	The ODDS button opens the egg odds pop-up (4h). The GIFT! header button only shows when ctx.OnGift is set
	(the gift flow needs server work, see UI-BUILD-ORDER step 9).
	Any Robux item whose ProductId/PassId is 0 shows a grey "Coming soon" button instead of a price.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))
local UiAssets = require(Shared:WaitForChild("UiAssets"))
local UiKit = require(Shared:WaitForChild("UiKit"))
local UiLayout = require(Shared:WaitForChild("UiLayout"))

local RobuxStoreWindow = {}

export type RobuxStoreContext = {
	ModalScrim: Frame,
	OnToast: (message: string, color: Color3?) -> (),
	BindShopEntry: (itemId: string, apply: (entry: ProgressionLogic.ShopListingEntry, state: any) -> ()) -> (),
	BuyShopItem: (itemId: string, quantity: (number | string)?) -> (),
	OnGift: (() -> ())?,
}

export type RobuxStoreHandle = {
	Frame: Frame,
	Refresh: (state: any) -> (),
}

local CARD_TONE: UiKit.Tri = {
	Light = Color3.fromRGB(44, 46, 55),
	Mid = Color3.fromRGB(36, 37, 45),
	Dark = Color3.fromRGB(27, 28, 34),
}

local PASS_ICONS: { [string]: string } = {
	pass_extra_slots = "basket",
	pass_auto_throw = "robot",
	pass_x2_cash = "cash",
	pass_vip = "crown",
	pass_x2_luck = "clover",
	pass_luck_4x = "clover",
	pass_luck_6x = "clover",
	pass_luck_8x = "clover",
	pass_luck_10x = "clover",
	pass_gems_2x = "gem",
	pass_gems_4x = "gem",
	pass_gems_6x = "gem",
	pass_gems_8x = "gem",
	pass_gems_10x = "gem",
	pass_power_2x = "power",
	pass_power_4x = "power",
	pass_power_6x = "power",
	pass_power_8x = "power",
	pass_power_10x = "power",
}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 84, 84)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(110, 235, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 200, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(150, 100, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 210)),
})

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function makeLabel(parent: Instance, size: number, text: string, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.Text = text
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = parent
	UiKit.AddTextStroke(l)
	return l
end

local function makeCard(parent: Instance, radius: number, tone: UiKit.Tri?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	f.Parent = parent
	UiKit.AddCorner(f, radius)
	UiKit.ApplyTri(f, tone or CARD_TONE)
	UiKit.AddFrameOutline(f, 4)
	return f
end

-- Buy button: label above (14), Robux glyph + price (30), green gradient. Product id 0 = grey "Coming soon".
local function makeBuyButton(
	parent: Instance,
	size: UDim2,
	topText: string,
	robux: number,
	available: boolean,
	onClick: () -> ()
): (TextButton, (owned: boolean) -> ())
	local isOwned = false
	local btn, face = UiKit.CreateGradientButton({
		Parent = parent,
		Size = size,
		Kind = if available then "green" else "grey",
		CornerRadius = 16,
		OnClick = function()
			if not isOwned then
				onClick()
			end
		end,
	})
	local top = makeLabel(face, 14, if available then topText else "Coming soon")
	top.Position = UDim2.fromOffset(0, 5)
	top.Size = UDim2.new(1, 0, 0, 18)
	top.ZIndex = 3

	local priceRow = Instance.new("Frame")
	priceRow.BackgroundTransparency = 1
	priceRow.Position = UDim2.fromOffset(0, 22)
	priceRow.Size = UDim2.new(1, 0, 1, -26)
	priceRow.ZIndex = 3
	priceRow.Parent = face
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = priceRow
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "RobuxGlyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromOffset(26, 26)
	glyph.Image = UiAssets.Robux
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.LayoutOrder = 1
	glyph.ZIndex = 3
	glyph.Visible = available
	glyph.Parent = priceRow
	local price = makeLabel(priceRow, 30, if available then tostring(robux) else `R$ {robux}`)
	price.AutomaticSize = Enum.AutomaticSize.X
	price.Size = UDim2.fromOffset(0, 34)
	price.LayoutOrder = 2
	price.ZIndex = 3
	if not available then
		price.TextSize = 20
		price.TextTransparency = 0.25
	end
	local function setOwned(owned: boolean)
		isOwned = owned
		if owned then
			top.Text = "Permanent"
			glyph.Visible = false
			price.Text = "OWNED"
			price.TextSize = 24
			UiKit.SetButtonTone(btn, UiKit.Gradients.Blue, 0)
		end
	end
	return btn, setOwned
end

local function divider(parent: Instance, text: string, order: number)
	local row = Instance.new("Frame")
	row.Name = "Divider_" .. text
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundTransparency = 1
	row.Parent = parent
	for _, side in { -1, 1 } do
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(if side < 0 then 0 else 1, 0.5)
		line.Position = UDim2.new(if side < 0 then 0 else 1, 0, 0.5, 0)
		line.Size = UDim2.new(0.5, -162, 0, 4)
		line.BackgroundColor3 = Color3.fromRGB(70, 72, 84)
		line.BorderSizePixel = 0
		line.Parent = row
		UiKit.AddCorner(line, 2)
	end
	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromOffset(296, 38)
	pill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	pill.Parent = row
	UiKit.AddCorner(pill, 19)
	UiKit.ApplyTri(pill, UiKit.Gradients.IconPlate)
	UiKit.AddFrameOutline(pill, 3)
	local lbl = makeLabel(pill, 22, text)
	lbl.Size = UDim2.fromScale(1, 1)
end

-- One odds tile: % (gold) on top, slime in a mutation ring, bonus chip at the bottom. Rarest = rainbow frame.
local function makeOddsTile(parent: Instance, item: GameConfig.ShopEggItem, rarest: boolean, width: number, height: number): Frame
	local sDef = GameConfig.SlimesById[item.SlimeId] or GameConfig.Slimes[1]
	local tile = Instance.new("Frame")
	tile.Size = UDim2.fromOffset(width, height)
	tile.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tile.Parent = parent
	UiKit.AddCorner(tile, 14)
	UiKit.ApplyTri(tile, UiKit.TriFromColor(SlimeFactory.GetRarityColor(sDef.Rarity), 0.2, 0.5))
	local stroke = UiKit.AddStroke(tile, UiKit.Colors.Ink, 3, Enum.ApplyStrokeMode.Border)
	if rarest then
		local g = Instance.new("UIGradient")
		g.Color = RAINBOW
		g.Rotation = 45
		g.Parent = stroke
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 4
	end

	local ring = Instance.new("ImageLabel")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(width - 16, width - 16)
	ring.BackgroundTransparency = 1
	ring.Image = UiAssets.Textures.ring
	ring.ImageColor3 = SlimeFactory.GetMutationColor(item.Mutation)
	ring.ImageTransparency = 0.45
	ring.Parent = tile
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(width - 24, width - 30)
	holder.BackgroundTransparency = 1
	holder.Parent = tile
	UiKit.CreateSlimeViewport(holder, item.SlimeId, item.Mutation, false)

	local pct = makeLabel(tile, 17, `{item.ChancePercent}%`)
	pct.Position = UDim2.fromOffset(0, 3)
	pct.Size = UDim2.new(1, 0, 0, 20)
	pct.ZIndex = 3
	UiKit.ApplyTri(pct, UiKit.Gradients.Luck)
	local chip = makeLabel(tile, 14, item.BonusLabel)
	chip.AnchorPoint = Vector2.new(0.5, 1)
	chip.Position = UDim2.new(0.5, 0, 1, -3)
	chip.Size = UDim2.new(1, -8, 0, 18)
	chip.ZIndex = 3
	UiKit.ApplyTri(chip, UiKit.Gradients.Cash)
	return tile
end

local function rarestIndex(egg: GameConfig.ShopEggDef): number
	local best, bestChance = 1, math.huge
	for i, item in egg.Items do
		if item.ChancePercent < bestChance then
			best, bestChance = i, item.ChancePercent
		end
	end
	return best
end

function RobuxStoreWindow.Build(parent: Instance, ctx: RobuxStoreContext): RobuxStoreHandle
	local win = UiKit.CreateWindow({
		Name = "RobuxStoreModal",
		Parent = parent,
		Title = "Shop",
		Size = UDim2.fromOffset(960, 540),
		Position = UDim2.fromScale(0.5, 0.52),
		Header = {
			Light = Color3.fromRGB(255, 213, 74),
			Mid = Color3.fromRGB(255, 165, 28),
			Dark = Color3.fromRGB(240, 122, 0),
		},
	})
	local modal = win.Frame
	win.Close.Activated:Connect(function()
		UiKit.ToggleModalAnimated(modal, ctx.ModalScrim, false)
	end)

	if ctx.OnGift then
		local gift = UiKit.CreateGradientButton({
			Name = "GiftBtn",
			Parent = win.Header,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -70, 0.5, 0),
			Size = UDim2.fromOffset(130, 44),
			Kind = "blue",
			CornerRadius = 14,
			Text = "GIFT!",
			TextSize = 24,
			OnClick = ctx.OnGift,
		})
		gift.ZIndex = 4
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Position = UDim2.fromOffset(20, 12)
	scroll.Size = UDim2.new(1, -40, 1, -24)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = win.Body
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 12)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 3)
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = scroll

	-- ============================================================================
	-- EGG ODDS POP-UP (4h): purple window, one 58 high row per egg entry
	-- ============================================================================
	local odds = UiKit.CreateWindow({
		Name = "EggOddsModal",
		Parent = parent,
		Title = "Egg Odds",
		Size = UDim2.fromOffset(700, 540),
		Position = UDim2.fromScale(0.5, 0.52),
		Header = {
			Light = Color3.fromRGB(210, 150, 255),
			Mid = Color3.fromRGB(155, 92, 255),
			Dark = Color3.fromRGB(90, 43, 208),
		},
	})
	odds.Frame.ZIndex = 30
	odds.Close.Activated:Connect(function()
		UiKit.ToggleModalAnimated(odds.Frame, nil, false)
	end)
	modal:GetPropertyChangedSignal("Visible"):Connect(function()
		if not modal.Visible and odds.Frame.Visible then
			UiKit.ToggleModalAnimated(odds.Frame, nil, false)
		end
	end)
	local oddsIcon = UiKit.CreateIconPlate(odds.Header, "egg", 48)
	oddsIcon.AnchorPoint = Vector2.new(1, 0.5)
	oddsIcon.Position = UDim2.new(1, -70, 0.5, 0)
	oddsIcon.ZIndex = 4
	local oddsList = Instance.new("ScrollingFrame")
	oddsList.Position = UDim2.fromOffset(20, 12)
	oddsList.Size = UDim2.new(1, -40, 1, -24)
	oddsList.BackgroundTransparency = 1
	oddsList.BorderSizePixel = 0
	oddsList.ScrollBarThickness = 5
	oddsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	oddsList.CanvasSize = UDim2.new()
	oddsList.Parent = odds.Body
	local oddsLayout = Instance.new("UIListLayout")
	oddsLayout.Padding = UDim.new(0, 8)
	oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	oddsLayout.Parent = oddsList
	local oddsPad = Instance.new("UIPadding")
	oddsPad.PaddingRight = UDim.new(0, 10)
	oddsPad.PaddingLeft = UDim.new(0, 3)
	oddsPad.PaddingTop = UDim.new(0, 3)
	oddsPad.Parent = oddsList

	local function openOdds(egg: GameConfig.ShopEggDef)
		odds.Title.Text = `{egg.Name} Odds`
		for _, c in oddsList:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local topChance = 0
		for _, item in egg.Items do
			topChance = math.max(topChance, item.ChancePercent)
		end
		local rarest = rarestIndex(egg)
		for i, item in egg.Items do
			local sDef = GameConfig.SlimesById[item.SlimeId] or GameConfig.Slimes[1]
			local row = makeCard(oddsList, 16)
			row.LayoutOrder = i
			row.Size = UDim2.new(1, 0, 0, 62)
			if i == rarest then
				local stroke = row:FindFirstChildOfClass("UIStroke") :: UIStroke
				local g = Instance.new("UIGradient")
				g.Color = RAINBOW
				g.Rotation = 20
				g.Parent = stroke
				stroke.Color = Color3.fromRGB(255, 255, 255)
			end
			local tile = Instance.new("Frame")
			tile.Position = UDim2.fromOffset(8, 5)
			tile.Size = UDim2.fromOffset(52, 52)
			tile.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			tile.Parent = row
			UiKit.AddCorner(tile, 12)
			UiKit.ApplyTri(tile, UiKit.TriFromColor(SlimeFactory.GetRarityColor(sDef.Rarity), 0.4, 0.3))
			UiKit.AddStroke(tile, UiKit.Colors.Ink, 3, Enum.ApplyStrokeMode.Border)
			local ring = Instance.new("ImageLabel")
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.5)
			ring.Size = UDim2.fromScale(1, 1)
			ring.BackgroundTransparency = 1
			ring.Image = UiAssets.Textures.ring
			ring.ImageColor3 = SlimeFactory.GetMutationColor(item.Mutation)
			ring.ImageTransparency = 0.4
			ring.Parent = tile
			local holder = Instance.new("Frame")
			holder.Size = UDim2.fromScale(1, 1)
			holder.BackgroundTransparency = 1
			holder.Parent = tile
			UiKit.CreateSlimeViewport(holder, item.SlimeId, item.Mutation, false)

			local mutName = if item.Mutation == "NORMAL" then "Normal" else item.Mutation
			local kicker = makeLabel(row, 14, `{mutName} · {sDef.Rarity}`, Enum.TextXAlignment.Left)
			kicker.Position = UDim2.fromOffset(70, 6)
			kicker.Size = UDim2.fromOffset(200, 18)
			kicker.TextColor3 = Color3.fromRGB(215, 220, 232)
			local name = makeLabel(row, 20, sDef.Name, Enum.TextXAlignment.Left)
			name.Position = UDim2.fromOffset(70, 24)
			name.Size = UDim2.fromOffset(200, 30)
			name.TextTruncate = Enum.TextTruncate.AtEnd

			local bonus = makeLabel(row, 18, item.BonusLabel)
			bonus.Position = UDim2.fromOffset(280, 14)
			bonus.Size = UDim2.fromOffset(70, 32)
			UiKit.ApplyTri(bonus, UiKit.Gradients.Cash)

			local bar = UiKit.CreateProgressBar(row, UDim2.fromOffset(150, 20), UiKit.Gradients.Luck)
			bar.Frame.Position = UDim2.fromOffset(360, 21)
			bar.SetFraction(UiLayout.ChanceBarFraction(item.ChancePercent, topChance))
			local pct = makeLabel(row, 22, `{item.ChancePercent}%`, Enum.TextXAlignment.Right)
			pct.AnchorPoint = Vector2.new(1, 0.5)
			pct.Position = UDim2.new(1, -14, 0.5, 0)
			pct.Size = UDim2.fromOffset(110, 34)
			UiKit.ApplyTri(pct, UiKit.Gradients.Luck)
		end
		UiKit.ToggleModalAnimated(odds.Frame, nil, true)
	end

	-- ============================================================================
	-- FEATURED EGGS: first = full 272 card, others = compact 150 card (LIMITED)
	-- ============================================================================
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	divider(scroll, "Featured", nextOrder())

	for eggIndex, egg in GameConfig.ShopEggs do
		local compact = eggIndex > 1
		local accent = rgb(egg.AccentColor)
		local card = Instance.new("Frame")
		card.Name = `EggCard_{egg.Id}`
		card.LayoutOrder = nextOrder()
		card.Size = UDim2.new(1, 0, 0, if compact then 160 else 272)
		card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		card.Parent = scroll
		UiKit.AddCorner(card, 20)
		local g = UiKit.ApplyTri(card, UiKit.TriFromColor(accent, 0.25, 0.55))
		g.Rotation = 35
		if egg.Tag == "LIMITED" then
			-- Rainbow diagonal with a dark overlay for text contrast (spec 4c)
			g.Color = RAINBOW
		end
		UiKit.AddFrameOutline(card, 4)
		UiKit.AddStripes(card, 20)
		if egg.Tag == "LIMITED" then
			local shade = Instance.new("Frame")
			shade.Size = UDim2.fromScale(1, 1)
			shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			shade.BackgroundTransparency = 0.7
			shade.BorderSizePixel = 0
			shade.Active = false
			shade.Parent = card
			UiKit.AddCorner(shade, 20)
		end

		if not compact then
			local sun = Instance.new("ImageLabel")
			sun.AnchorPoint = Vector2.new(0.5, 0.5)
			sun.Position = UDim2.fromOffset(110, 140)
			sun.Size = UDim2.fromOffset(260, 260)
			sun.BackgroundTransparency = 1
			sun.Image = UiAssets.Textures.sunburst
			sun.ImageTransparency = 0.86
			sun.Parent = card
			local eggIcon = UiKit.CreateIcon(card, "egg", 150)
			eggIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			eggIcon.Position = UDim2.fromOffset(110, 140)
		end

		local titleX = if compact then 20 else 210
		local title = makeLabel(card, 38, egg.Name, Enum.TextXAlignment.Left)
		title.Position = UDim2.fromOffset(titleX, 8)
		title.Size = UDim2.fromOffset(380, 48)
		UiKit.ApplyTri(title, UiKit.Gradients.Luck)

		-- tag pill: New! = rainbow, LIMITED = dark
		local tagPill = Instance.new("Frame")
		tagPill.Position = UDim2.fromOffset(titleX + 330, 16)
		tagPill.Size = UDim2.fromOffset(110, 32)
		tagPill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		tagPill.Parent = card
		UiKit.AddCorner(tagPill, 16)
		if egg.Tag == "LIMITED" then
			UiKit.ApplyTri(tagPill, UiKit.Gradients.IconPlate)
		else
			local tg = Instance.new("UIGradient")
			tg.Color = RAINBOW
			tg.Parent = tagPill
		end
		UiKit.AddFrameOutline(tagPill, 3)
		local tagLabel = makeLabel(tagPill, 18, egg.Tag)
		tagLabel.Size = UDim2.fromScale(1, 1)

		local eggCopy = egg
		UiKit.CreateGradientButton({
			Name = "OddsBtn",
			Parent = card,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 14),
			Size = UDim2.fromOffset(110, 38),
			Kind = "blue",
			CornerRadius = 12,
			Text = "ODDS",
			TextSize = 20,
			OnClick = function()
				openOdds(eggCopy)
			end,
		})

		local rarest = rarestIndex(egg)
		local tilesY = if compact then 58 else 66
		local tileH = if compact then 92 else 100
		local tileW = if compact then 84 else 92
		local tiles = Instance.new("Frame")
		tiles.BackgroundTransparency = 1
		tiles.Position = UDim2.fromOffset(titleX, tilesY)
		tiles.Size = UDim2.fromOffset(#egg.Items * (tileW + 6), tileH)
		tiles.Parent = card
		local tl = Instance.new("UIListLayout")
		tl.FillDirection = Enum.FillDirection.Horizontal
		tl.Padding = UDim.new(0, 6)
		tl.Parent = tiles
		for i, item in egg.Items do
			makeOddsTile(tiles, item, i == rarest, tileW, tileH)
		end

		local function buy(count: number, productId: number, robux: number)
			if productId <= 0 then
				ctx.OnToast(`{eggCopy.Name} (x{count} — R${robux}) is coming soon!`, Color3.fromRGB(255, 215, 85))
				return
			end
			MarketplaceService:PromptProductPurchase(localPlayer, productId)
		end
		local buy1 = makeBuyButton(card, UDim2.fromOffset(150, 66), "Buy x1", egg.Buy1Robux, egg.Buy1ProductId > 0, function()
			buy(1, eggCopy.Buy1ProductId, eggCopy.Buy1Robux)
		end)
		local buy3 = makeBuyButton(card, UDim2.fromOffset(150, 66), "Buy x3", egg.Buy3Robux, egg.Buy3ProductId > 0, function()
			buy(3, eggCopy.Buy3ProductId, eggCopy.Buy3Robux)
		end)
		if compact then
			buy1.AnchorPoint = Vector2.new(1, 0)
			buy1.Position = UDim2.new(1, -176, 0, 66)
			buy3.AnchorPoint = Vector2.new(1, 0)
			buy3.Position = UDim2.new(1, -16, 0, 66)
		else
			buy1.Position = UDim2.fromOffset(210, 190)
			buy3.Position = UDim2.fromOffset(372, 190)
		end
	end

	-- ============================================================================
	-- GAME PASSES: Core wide cards + compact 2-column grids for Luck / Gems / Power (2x-10x)
	-- ============================================================================
	type PassUi = { Pass: GameConfig.RobuxPassDef, SetOwned: (boolean) -> () }
	local passUis: { PassUi } = {}

	local passGroups: { { Category: string, Title: string, Wide: boolean } } = {
		{ Category = "Core", Title = "Core Passes", Wide = true },
		{ Category = "Luck", Title = "Luck Passes (2x–10x)", Wide = false },
		{ Category = "Gems", Title = "Gems Passes (2x–10x)", Wide = false },
		{ Category = "Power", Title = "Power Passes (2x–10x)", Wide = false },
	}

	for _, group in passGroups do
		local passesInGroup: { GameConfig.RobuxPassDef } = {}
		for _, pass in GameConfig.Robux.Passes do
			if (pass.Category or "Core") == group.Category then
				table.insert(passesInGroup, pass)
			end
		end
		if #passesInGroup == 0 then
			continue
		end

		divider(scroll, group.Title, nextOrder())

		if group.Wide then
			for _, pass in passesInGroup do
				local card = Instance.new("Frame")
				card.Name = "Pass_" .. pass.Id
				card.LayoutOrder = nextOrder()
				card.Size = UDim2.new(1, 0, 0, 124)
				card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				card.Parent = scroll
				UiKit.AddCorner(card, 20)
				UiKit.ApplyTri(card, UiKit.TriFromColor(rgb(pass.Color), 0.3, 0.45))
				UiKit.AddFrameOutline(card, 4)
				UiKit.AddStripes(card, 20)
				local plate = UiKit.CreateIconPlate(card, PASS_ICONS[pass.Id] or "star", 86)
				plate.Position = UDim2.fromOffset(20, 19)
				local name = makeLabel(card, 32, pass.Name, Enum.TextXAlignment.Left)
				name.Position = UDim2.fromOffset(124, 20)
				name.Size = UDim2.fromOffset(420, 40)
				local desc = makeLabel(card, 18, pass.Description, Enum.TextXAlignment.Left)
				desc.Position = UDim2.fromOffset(124, 64)
				desc.Size = UDim2.new(1, -360, 0, 42)
				desc.TextWrapped = true
				desc.TextYAlignment = Enum.TextYAlignment.Top
				local passCopy = pass
				local btn, setOwned = makeBuyButton(card, UDim2.fromOffset(190, 72), "Buy", pass.RobuxPrice, pass.PassId > 0, function()
					if passCopy.PassId <= 0 then
						ctx.OnToast(`{passCopy.Name} is coming soon!`, Color3.fromRGB(255, 215, 85))
						return
					end
					MarketplaceService:PromptGamePassPurchase(localPlayer, passCopy.PassId)
				end)
				btn.AnchorPoint = Vector2.new(1, 0.5)
				btn.Position = UDim2.new(1, -22, 0.5, 0)
				table.insert(passUis, { Pass = pass, SetOwned = setOwned })
			end
		else
			local rows = math.ceil(#passesInGroup / 2)
			local cellH = 104
			local padY = 10
			local gridHolder = Instance.new("Frame")
			gridHolder.Name = "PassGrid_" .. group.Category
			gridHolder.LayoutOrder = nextOrder()
			gridHolder.Size = UDim2.new(1, 0, 0, rows * cellH + math.max(0, rows - 1) * padY)
			gridHolder.BackgroundTransparency = 1
			gridHolder.Parent = scroll
			local grid = Instance.new("UIGridLayout")
			grid.CellSize = UDim2.new(0.5, -6, 0, cellH)
			grid.CellPadding = UDim2.fromOffset(12, padY)
			grid.SortOrder = Enum.SortOrder.LayoutOrder
			grid.Parent = gridHolder

			for i, pass in passesInGroup do
				local card = Instance.new("Frame")
				card.Name = "Pass_" .. pass.Id
				card.LayoutOrder = i
				card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				card.Parent = gridHolder
				UiKit.AddCorner(card, 18)
				UiKit.ApplyTri(card, UiKit.TriFromColor(rgb(pass.Color), 0.3, 0.45))
				UiKit.AddFrameOutline(card, 3.5)
				UiKit.AddStripes(card, 18)

				local plate = UiKit.CreateIconPlate(card, PASS_ICONS[pass.Id] or "star", 68)
				plate.Position = UDim2.fromOffset(14, 18)
				local name = makeLabel(card, 24, pass.Name, Enum.TextXAlignment.Left)
				name.Position = UDim2.fromOffset(94, 14)
				name.Size = UDim2.new(1, -248, 0, 32)
				name.TextTruncate = Enum.TextTruncate.AtEnd
				local desc = makeLabel(card, 14, pass.Description, Enum.TextXAlignment.Left)
				desc.Position = UDim2.fromOffset(94, 48)
				desc.Size = UDim2.new(1, -248, 0, 42)
				desc.TextWrapped = true
				desc.TextYAlignment = Enum.TextYAlignment.Top

				local passCopy = pass
				local btn, setOwned = makeBuyButton(card, UDim2.fromOffset(136, 66), "Buy", pass.RobuxPrice, pass.PassId > 0, function()
					if passCopy.PassId <= 0 then
						ctx.OnToast(`{passCopy.Name} is coming soon!`, Color3.fromRGB(255, 215, 85))
						return
					end
					MarketplaceService:PromptGamePassPurchase(localPlayer, passCopy.PassId)
				end)
				btn.AnchorPoint = Vector2.new(1, 0.5)
				btn.Position = UDim2.new(1, -14, 0.5, 0)
				table.insert(passUis, { Pass = pass, SetOwned = setOwned })
			end
		end
	end

	-- ============================================================================
	-- GEM PACKS: 4 cards across, gem icon grows 40 -> 58, rotated red tag
	-- ============================================================================
	divider(scroll, "Gem Packs", nextOrder())
	local packRow = Instance.new("Frame")
	packRow.Name = "GemPacks"
	packRow.LayoutOrder = nextOrder()
	packRow.Size = UDim2.new(1, 0, 0, 214)
	packRow.BackgroundTransparency = 1
	packRow.Parent = scroll
	local packLayout = Instance.new("UIGridLayout")
	packLayout.CellSize = UDim2.new(0.25, -9, 0, 206)
	packLayout.CellPadding = UDim2.fromOffset(12, 0)
	packLayout.SortOrder = Enum.SortOrder.LayoutOrder
	packLayout.Parent = packRow
	local packCount = #GameConfig.Robux.GemPacks
	for i, pack in GameConfig.Robux.GemPacks do
		local card = Instance.new("Frame")
		card.Name = "Pack_" .. pack.Id
		card.LayoutOrder = i
		card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		card.Parent = packRow
		UiKit.AddCorner(card, 20)
		UiKit.ApplyTri(card, UiKit.TriFromColor(rgb(pack.Color), 0.3, 0.5))
		UiKit.AddFrameOutline(card, 4)
		UiKit.AddStripes(card, 20)
		local iconSize = 40 + math.floor((i - 1) * 18 / math.max(1, packCount - 1))
		local gem = UiKit.CreateIcon(card, "gem", iconSize + 30)
		gem.AnchorPoint = Vector2.new(0.5, 0)
		gem.Position = UDim2.new(0.5, 0, 0, 22 + (58 - iconSize) * 0.5)
		local amount = makeLabel(card, 28, GameConfig.FormatNumber(pack.Gems))
		amount.Position = UDim2.fromOffset(0, 108)
		amount.Size = UDim2.new(1, 0, 0, 34)
		UiKit.ApplyTri(amount, UiKit.Gradients.Gems)
		if pack.BonusTag and pack.BonusTag ~= "" then
			local tag = Instance.new("Frame")
			tag.AnchorPoint = Vector2.new(1, 0)
			tag.Position = UDim2.new(1, -6, 0, 6)
			tag.Size = UDim2.fromOffset(88, 26)
			tag.Rotation = 8
			tag.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			tag.ZIndex = 5
			tag.Parent = card
			UiKit.AddCorner(tag, 8)
			UiKit.ApplyTri(tag, UiKit.Gradients.Red)
			UiKit.AddFrameOutline(tag, 2.5)
			local tl = makeLabel(tag, 13, pack.BonusTag)
			tl.Size = UDim2.fromScale(1, 1)
			tl.ZIndex = 6
		end
		local packCopy = pack
		local btn = makeBuyButton(card, UDim2.new(1, -24, 0, 54), "Buy", pack.RobuxPrice, pack.ProductId > 0, function()
			if packCopy.ProductId <= 0 then
				ctx.OnToast(`{packCopy.Name} is coming soon!`, Color3.fromRGB(255, 215, 85))
				return
			end
			MarketplaceService:PromptProductPurchase(localPlayer, packCopy.ProductId)
		end)
		btn.AnchorPoint = Vector2.new(0.5, 1)
		btn.Position = UDim2.new(0.5, 0, 1, -12)
	end

	-- ============================================================================
	-- FREE GIFT: gold striped card, preview slime, CLAIM! (hidden once claimed)
	-- ============================================================================
	local giftCard = Instance.new("Frame")
	giftCard.Name = "FreeGiftCard"
	giftCard.LayoutOrder = nextOrder()
	giftCard.Size = UDim2.new(1, 0, 0, 120)
	giftCard.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	giftCard.Parent = scroll
	UiKit.AddCorner(giftCard, 20)
	UiKit.ApplyTri(giftCard, UiKit.Gradients.Luck)
	UiKit.AddFrameOutline(giftCard, 4)
	UiKit.AddStripes(giftCard, 20)
	local giftTile = Instance.new("Frame")
	giftTile.Position = UDim2.fromOffset(16, 14)
	giftTile.Size = UDim2.fromOffset(92, 92)
	giftTile.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	giftTile.Parent = giftCard
	UiKit.AddCorner(giftTile, 18)
	UiKit.ApplyTri(giftTile, UiKit.Gradients.IconPlate)
	UiKit.AddStroke(giftTile, UiKit.Colors.Ink, 3, Enum.ApplyStrokeMode.Border)
	local giftHolder = Instance.new("Frame")
	giftHolder.Size = UDim2.fromScale(1, 1)
	giftHolder.BackgroundTransparency = 1
	giftHolder.Parent = giftTile
	UiKit.CreateSlimeViewport(giftHolder, GameConfig.FreeGift.SlimeId, GameConfig.FreeGift.Mutation, false)
	local giftTitle = makeLabel(giftCard, 34, GameConfig.FreeGift.Title, Enum.TextXAlignment.Left)
	giftTitle.Position = UDim2.fromOffset(126, 18)
	giftTitle.Size = UDim2.fromOffset(500, 42)
	local giftSub = makeLabel(giftCard, 20, GameConfig.FreeGift.Subtitle, Enum.TextXAlignment.Left)
	giftSub.Position = UDim2.fromOffset(126, 64)
	giftSub.Size = UDim2.new(1, -360, 0, 30)
	giftSub.TextTruncate = Enum.TextTruncate.AtEnd
	local claim = UiKit.CreateGradientButton({
		Name = "FreeClaimBtn",
		Parent = giftCard,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -22, 0.5, 0),
		Size = UDim2.fromOffset(190, 70),
		Kind = "green",
		CornerRadius = 18,
		Text = "CLAIM!",
		TextSize = 30,
		OnClick = function()
			ctx.BuyShopItem("free_gift", 1)
		end,
	})
	ctx.BindShopEntry("free_gift", function(entry: ProgressionLogic.ShopListingEntry)
		giftCard.Visible = entry.State ~= "Claimed"
	end)

	local function refresh(state: any)
		local ownedPasses = if type(state.OwnedPasses) == "table" then state.OwnedPasses else {}
		for _, p in passUis do
			local pass = p.Pass
			local owned = ownedPasses[pass.Id] == true
			if not owned then
				if pass.UnlocksExtraSlots then
					owned = ProgressionLogic.GetEffectiveMaxSlimes(state) >= GameConfig.Slots.ExpandedMaxSlimes
				elseif pass.UnlocksAutoThrow then
					owned = ProgressionLogic.OwnsAutoThrow(state)
				elseif pass.TrackId then
					local needed = pass.LuckMultiplier
						or pass.GemMultiplier
						or pass.PowerMultiplier
						or pass.CashMultiplier
						or 2
					owned = ProgressionLogic.GetTrackMultiplier(state, pass.TrackId) >= needed
				end
			end
			p.SetOwned(owned)
		end
	end

	return { Frame = modal, Refresh = refresh }
end

return RobuxStoreWindow
