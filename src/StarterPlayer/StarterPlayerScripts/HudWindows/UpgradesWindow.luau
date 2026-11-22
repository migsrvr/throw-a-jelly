--!strict
--[[
	UpgradesWindow.luau
	Tabbed HUD modal for all Cash & Gem Upgrades (docs/docs/UI-MOCKUP-SPEC.md 3a, 4a, 4b).
	Built only from UiKit: CreateWindow, CreateTabs, CreateGradientButton, icon tiles.
	1. Power & Training: Throw Power (`power_upgrade` Buy + Buy Max), Pull-Up Bar Tier (`pullup_tier`), x2 Training Power (`boost_double_power`)
	2. Bait & Plot: Jelly Bait Quality Tier (`bait_tier`), +4 Slime Slots (`slot_expansion`), x2 Cash (`boost_double_cash`)
	3. Gem Upgrades: Auto-Throw (`gem_auto_throw`), Lucky Charm (`gem_lucky_charm`), +4 Slime Slots (`gem_slot_expansion`)
	Rows bind through ctx.BindShopEntry / ctx.BuyShopItem, so names, prices and states come from
	ProgressionLogic.GetShopListing (no price logic lives here).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local UiKit = require(Shared:WaitForChild("UiKit"))
local UiLayout = require(Shared:WaitForChild("UiLayout"))

local UpgradesWindow = {}

export type UpgradesWindowContext = {
	ModalScrim: Frame,
	-- Register a callback that runs on every state sync with this item's listing entry
	BindShopEntry: (itemId: string, apply: (entry: ProgressionLogic.ShopListingEntry, state: any) -> ()) -> (),
	BuyShopItem: (itemId: string, quantity: (number | string)?) -> (),
}

export type UpgradesWindowHandle = {
	Frame: Frame,
	Refresh: (state: any) -> (),
}

type TabKey = "Power" | "Bait" | "Gem"

type TabSpec = {
	Key: TabKey,
	Text: string,
	Icon: string,
	Tone: UiKit.Tri,
	Title: string,
	Tagline: string,
	Items: { string },
}

local TEAL: UiKit.Tri = UiKit.Gradients.RewardsNav

local TABS: { TabSpec } = {
	{
		Key = "Power",
		Text = "Power & Bars",
		Icon = "bolt",
		Tone = UiKit.Gradients.Blue,
		Title = "Power & Pull-Up Bars",
		Tagline = "Spend Cash to raise Throw Power and upgrade your Pull-Up Bar!",
		Items = { "power_upgrade", "pullup_tier" },
	},
	{
		Key = "Bait",
		Text = "Jelly Bait",
		Icon = "carrot",
		Tone = UiKit.Gradients.Orange,
		Title = "Jelly Bait Quality",
		Tagline = "Upgrade Jelly Bait with Cash to multiply rarity & Rainbow luck!",
		Items = { "bait_tier" },
	},
	{
		Key = "Gem",
		Text = "Gem Upgrades",
		Icon = "gem",
		Tone = TEAL,
		Title = "Gem Upgrades (Long Grind)",
		Tagline = "Permanent 2x-10x multipliers, Auto-Throw & Plot Slots 9-12!",
		Items = {}, -- filled from the catalog (Category = "Gem")
	},
}

-- Twemoji icon key per catalog item (spec 1b replaces the emoji in GameConfig.ShopCatalog)
local ITEM_ICONS: { [string]: string } = {
	power_upgrade = "bolt",
	pullup_tier = "lifter",
	bait_tier = "carrot",
	gem_slot_unlock = "basket",
	gem_auto_throw = "robot",
	gem_money_2x = "cash",
	gem_gems_tier = "gem",
	gem_power_tier = "power",
	gem_luck_tier = "clover",
}

local CARD_TONE: UiKit.Tri = {
	Light = Color3.fromRGB(44, 46, 55),
	Mid = Color3.fromRGB(36, 37, 45),
	Dark = Color3.fromRGB(27, 28, 34),
}

local ROW_HEIGHT = 84
local BUTTON_WIDTH = 128

local function makeLabel(parent: Instance, size: number, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.Text = text
	l.Parent = parent
	UiKit.AddTextStroke(l)
	return l
end

-- Header currency pill: dark plate, icon, gradient number
local function makePill(parent: Instance, iconKey: string, tone: UiKit.Tri, rightOffset: number): TextLabel
	local pill = Instance.new("Frame")
	pill.Name = iconKey .. "Pill"
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -rightOffset, 0.5, 0)
	pill.Size = UDim2.fromOffset(156, 40)
	pill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	pill.ZIndex = 4
	pill.Parent = parent
	UiKit.AddCorner(pill, 20)
	UiKit.ApplyTri(pill, UiKit.Gradients.IconPlate)
	UiKit.AddFrameOutline(pill, 3)

	local icon = UiKit.CreateIcon(pill, iconKey, 30)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	icon.ZIndex = 5

	local value = makeLabel(pill, 22, "0")
	value.Position = UDim2.fromOffset(44, 0)
	value.Size = UDim2.new(1, -52, 1, 0)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.ZIndex = 5
	UiKit.ApplyTri(value, tone)
	return value
end

function UpgradesWindow.Build(parent: Instance, ctx: UpgradesWindowContext): UpgradesWindowHandle
	local win = UiKit.CreateWindow({
		Name = "UpgradesModal",
		Parent = parent,
		Title = "Upgrades",
		Size = UDim2.fromOffset(960, 540),
		Position = UDim2.fromScale(0.5, 0.52),
		Header = {
			Light = Color3.fromRGB(156, 255, 90),
			Mid = Color3.fromRGB(76, 219, 22),
			Dark = Color3.fromRGB(42, 158, 14),
		},
	})
	local modal = win.Frame
	win.Close.Activated:Connect(function()
		UiKit.ToggleModalAnimated(modal, ctx.ModalScrim, false)
	end)

	local gemsValue = makePill(win.Header, "gem", UiKit.Gradients.Gems, 70)
	local cashValue = makePill(win.Header, "cash", UiKit.Gradients.Cash, 70 + 156 + 10)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(20, 14)
	content.Size = UDim2.new(1, -40, 1, -30)
	content.BackgroundTransparency = 1
	content.Parent = win.Body

	local pages: { [string]: ScrollingFrame } = {}

	-- Tab banner: tab colour + stripes, title 28 and tagline
	local banner = Instance.new("Frame")
	banner.Name = "TabBanner"
	banner.Position = UDim2.fromOffset(0, 60)
	banner.Size = UDim2.new(1, 0, 0, 56)
	banner.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	banner.Parent = content
	UiKit.AddCorner(banner, 14)
	UiKit.ApplyTri(banner, TABS[1].Tone)
	UiKit.AddFrameOutline(banner, 3)
	UiKit.AddStripes(banner, 14)
	local bannerTitle = makeLabel(banner, 28, TABS[1].Title)
	bannerTitle.Position = UDim2.fromOffset(18, 2)
	bannerTitle.Size = UDim2.new(1, -36, 0, 32)
	bannerTitle.TextXAlignment = Enum.TextXAlignment.Left
	local bannerTagline = makeLabel(banner, 16, TABS[1].Tagline)
	bannerTagline.Position = UDim2.fromOffset(18, 32)
	bannerTagline.Size = UDim2.new(1, -36, 0, 20)
	bannerTagline.TextXAlignment = Enum.TextXAlignment.Left

	local tabList: { UiKit.TabDef } = {}
	for _, spec in TABS do
		table.insert(tabList, { Id = spec.Key, Text = spec.Text, Icon = spec.Icon, Gradient = spec.Tone })
	end
	local tabs = UiKit.CreateTabs(content, tabList, function(id: string)
		for _, spec in TABS do
			local page = pages[spec.Key]
			if page then
				page.Visible = spec.Key == id
			end
			if spec.Key == id then
				UiKit.SetTone(banner, spec.Tone)
				bannerTitle.Text = spec.Title
				bannerTagline.Text = spec.Tagline
			end
		end
	end)
	tabs.Frame.Position = UDim2.fromOffset(0, 0)

	local gemItems: { string } = {}
	for _, item in GameConfig.ShopCatalog do
		if item.Category == "Gem" then
			table.insert(gemItems, item.Id)
		end
	end

	local function makePage(key: string): ScrollingFrame
		local page = Instance.new("ScrollingFrame")
		page.Name = key .. "Page"
		page.Position = UDim2.fromOffset(0, 126)
		page.Size = UDim2.new(1, 0, 1, -126)
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.ScrollBarThickness = 5
		page.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
		page.CanvasSize = UDim2.new()
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.ScrollingDirection = Enum.ScrollingDirection.Y
		page.Visible = false
		page.Parent = content
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = page
		local pad = Instance.new("UIPadding")
		pad.PaddingRight = UDim.new(0, 10)
		pad.PaddingTop = UDim.new(0, 3)
		pad.PaddingBottom = UDim.new(0, 6)
		pad.PaddingLeft = UDim.new(0, 3)
		pad.Parent = page
		pages[key] = page
		return page
	end

	-- One 84 px row: icon tile, title + level tag, "from > to" line, option buttons
	local function buildRow(page: ScrollingFrame, itemId: string, order: number)
		local item = GameConfig.ShopCatalogById[itemId]
		if not item then
			return
		end
		local buttonCount = if item.Action == "PowerUpgrade" then 2 else 1
		local itemColor = Color3.fromRGB(item.Color[1], item.Color[2], item.Color[3])

		local row = Instance.new("Frame")
		row.Name = "Row_" .. itemId
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		row.Parent = page
		UiKit.AddCorner(row, 18)
		UiKit.ApplyTri(row, CARD_TONE)
		UiKit.AddFrameOutline(row, 4)

		local tile = Instance.new("Frame")
		tile.Name = "IconTile"
		tile.Position = UDim2.fromOffset(12, 11)
		tile.Size = UDim2.fromOffset(62, 62)
		tile.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		tile.Parent = row
		UiKit.AddCorner(tile, 16)
		UiKit.ApplyTri(tile, UiKit.TriFromColor(itemColor, 0.4, 0.3))
		UiKit.AddStroke(tile, UiKit.Colors.Ink, 3, Enum.ApplyStrokeMode.Border)
		local icon = UiKit.CreateIcon(tile, ITEM_ICONS[itemId] or "star", 44)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)

		local textWidth = buttonCount * (BUTTON_WIDTH + 10) + 96
		local textHolder = Instance.new("Frame")
		textHolder.Name = "Text"
		textHolder.Position = UDim2.fromOffset(88, 8)
		textHolder.Size = UDim2.new(1, -textWidth, 1, -16)
		textHolder.BackgroundTransparency = 1
		textHolder.Parent = row

		local titleRow = Instance.new("Frame")
		titleRow.Size = UDim2.new(1, 0, 0, 32)
		titleRow.BackgroundTransparency = 1
		titleRow.Parent = textHolder
		local titleLayout = Instance.new("UIListLayout")
		titleLayout.FillDirection = Enum.FillDirection.Horizontal
		titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		titleLayout.Padding = UDim.new(0, 8)
		titleLayout.Parent = titleRow

		local titleLabel = makeLabel(titleRow, 24, itemId)
		titleLabel.AutomaticSize = Enum.AutomaticSize.X
		titleLabel.Size = UDim2.fromOffset(0, 32)
		titleLabel.LayoutOrder = 1
		local tagLabel = makeLabel(titleRow, 20, "")
		tagLabel.AutomaticSize = Enum.AutomaticSize.X
		tagLabel.Size = UDim2.fromOffset(0, 32)
		tagLabel.LayoutOrder = 2
		UiKit.ApplyTri(tagLabel, UiKit.Gradients.Luck)

		local subLabel = makeLabel(textHolder, 17, "")
		subLabel.Position = UDim2.fromOffset(0, 34)
		subLabel.Size = UDim2.new(1, 0, 0, 24)
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextColor3 = Color3.fromRGB(222, 228, 240)
		subLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local holder = Instance.new("Frame")
		holder.Name = "Buttons"
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position = UDim2.new(1, -12, 0.5, 0)
		holder.Size = UDim2.fromOffset(buttonCount * (BUTTON_WIDTH + 10) - 10, 64)
		holder.BackgroundTransparency = 1
		holder.Parent = row
		local holderLayout = Instance.new("UIListLayout")
		holderLayout.FillDirection = Enum.FillDirection.Horizontal
		holderLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		holderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		holderLayout.Padding = UDim.new(0, 10)
		holderLayout.SortOrder = Enum.SortOrder.LayoutOrder
		holderLayout.Parent = holder

		local latest: ProgressionLogic.ShopListingEntry? = nil
		type OptionButton = { Button: TextButton, Top: TextLabel, Price: TextLabel }
		local optionButtons: { OptionButton } = {}
		for i = 1, buttonCount do
			local btn, face = UiKit.CreateGradientButton({
				Name = "Option" .. i,
				Parent = holder,
				Size = UDim2.fromOffset(BUTTON_WIDTH, 62),
				Kind = if i == 2 then "orange" else "green",
				CornerRadius = 14,
				LayoutOrder = i,
				OnClick = function()
					local entry = latest
					local opt = entry and entry.Options[i]
					if entry and opt and UiLayout.ShopButtonState(entry.State, opt.CanAfford) ~= "locked" then
						ctx.BuyShopItem(itemId, opt.Quantity)
					end
				end,
			})
			local top = makeLabel(face, 14, "Buy")
			top.Position = UDim2.fromOffset(0, 5)
			top.Size = UDim2.new(1, 0, 0, 18)
			top.ZIndex = 3
			local price = makeLabel(face, 23, "")
			price.Position = UDim2.fromOffset(0, 21)
			price.Size = UDim2.new(1, 0, 0, 30)
			price.ZIndex = 3
			table.insert(optionButtons, { Button = btn, Top = top, Price = price })
		end

		ctx.BindShopEntry(itemId, function(entry: ProgressionLogic.ShopListingEntry, state: any)
			latest = entry
			local name, level = string.match(entry.Title, "^(.-)%s*%((Lv%.%d+)%)$")
			titleLabel.Text = name or entry.Title
			tagLabel.Text = level or ""
			subLabel.Text = string.gsub(entry.Subtitle, "%->", "▶")
			local balance = ProgressionLogic.GetBalance(state, entry.PriceKind)

			for i, ob in optionButtons do
				local opt = entry.Options[i]
				local locked = entry.State == "Owned" or entry.State == "Maxed" or entry.State == "Claimed"
				if i > 1 and (locked or not opt) then
					ob.Button.Visible = false
					continue
				end
				ob.Button.Visible = true
				local view = UiLayout.ShopButtonState(entry.State, if opt then opt.CanAfford else false)
				if view == "locked" or not opt then
					UiKit.SetButtonTone(ob.Button, UiKit.Gradients.Grey, 0)
					ob.Top.Text = "Permanent"
					ob.Price.Text = entry.PriceText
				else
					local priceText = if opt.Quantity == "max"
						then "MAX"
						elseif entry.PriceKind == "Gems" then `{GameConfig.FormatNumber(opt.Price)} Gems`
						else `${GameConfig.FormatNumber(opt.Price)}`
					ob.Price.Text = priceText
					if view == "unaffordable" then
						UiKit.SetButtonTone(ob.Button, UiKit.Gradients.Grey, 0.4)
						ob.Top.Text = `Need {GameConfig.FormatNumber(math.max(1, math.ceil(opt.Price - balance)))} more`
					else
						UiKit.SetButtonTone(ob.Button, if i == 2 then UiKit.Gradients.Orange else UiKit.Gradients.Green, 0)
						ob.Top.Text = opt.Label
					end
				end
			end
		end)
	end

	for _, spec in TABS do
		local page = makePage(spec.Key)
		local items = if spec.Key == "Gem" then gemItems else spec.Items
		for order, itemId in items do
			buildRow(page, itemId, order)
		end
	end

	tabs.Select("Power")

	local function refresh(state: any)
		cashValue.Text = `${GameConfig.FormatNumber(state.Cash or 0)}`
		gemsValue.Text = GameConfig.FormatNumber(state.Gems or 0)
	end

	return {
		Frame = modal,
		Refresh = refresh,
	}
end

return UpgradesWindow
