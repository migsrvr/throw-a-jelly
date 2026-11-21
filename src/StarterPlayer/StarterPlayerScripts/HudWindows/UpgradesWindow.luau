--!strict
--[[
	UpgradesWindow.luau
	Tabbed HUD modal for all Cash & Gem Upgrades (opened by the left-side `⬆️ Upgrades` button).
	Uses 3 tabs — each with its own dedicated glossy Tab Header Banner instead of stacked sections:
	1. ⚡ Power & Training: Throw Power (`power_upgrade` Buy + Buy Max), Pull-Up Bar Tier (`pullup_tier`), x2 Training Power (`boost_double_power`)
	2. 🥕 Bait & Plot: Jelly Bait Quality Tier (`bait_tier`), +4 Slime Slots (`slot_expansion`), x2 Cash (`boost_double_cash`)
	3. 💎 Gem Upgrades: Auto-Throw (`gem_auto_throw`), Lucky Charm (`gem_lucky_charm`), +4 Slime Slots (`gem_slot_expansion`)
	All rows bind through ctx.BindShopLabel / ctx.BuyShopItem so prices and states come from ProgressionLogic.GetShopListing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))
local UiKit = require(Shared:WaitForChild("UiKit"))

local UpgradesWindow = {}

export type UpgradesWindowContext = {
	ModalScrim: Frame,
	BindShopLabel: (
		label: TextLabel?,
		itemId: string,
		optionIndex: number,
		style: "Row" | "RowWide" | "Option"
	) -> (),
	BuyShopItem: (itemId: string, quantity: (number | string)?) -> (),
}

export type UpgradesWindowHandle = {
	Frame: Frame,
	Refresh: (state: any) -> (),
}

type TabKey = "Power" | "Bait" | "Gem"

type TabSpec = {
	Key: TabKey,
	TabButtonText: string,
	TabColor: Color3,
	HeaderTitle: string,
	HeaderSubtitle: string,
	HeaderColor: Color3,
}

local TABS: { TabSpec } = {
	{
		Key = "Power",
		TabButtonText = "⚡ Power & Training",
		TabColor = Color3.fromRGB(235, 140, 35),
		HeaderTitle = "⚡ POWER & TRAINING UPGRADES",
		HeaderSubtitle = "Increase your Throw Power, Pull-Up Bar tier, and 2x Training XP!",
		HeaderColor = Color3.fromRGB(225, 130, 35),
	},
	{
		Key = "Bait",
		TabButtonText = "🥕 Bait & Plot",
		TabColor = Color3.fromRGB(70, 190, 95),
		HeaderTitle = "🥕 BAIT & PLOT UPGRADES",
		HeaderSubtitle = "Upgrade Jelly Bait luck, expand to 12 plot slots, and 2x Cash income!",
		HeaderColor = Color3.fromRGB(60, 175, 90),
	},
	{
		Key = "Gem",
		TabButtonText = "💎 Gem Upgrades",
		TabColor = Color3.fromRGB(55, 175, 245),
		HeaderTitle = "💎 GEM UPGRADES",
		HeaderSubtitle = "Permanent premium convenience unlocks paid with Gems!",
		HeaderColor = Color3.fromRGB(50, 155, 230),
	},
}

function UpgradesWindow.Build(parent: Instance, ctx: UpgradesWindowContext): UpgradesWindowHandle
	local addCorner = UiKit.AddCorner
	local addStroke = UiKit.AddStroke

	local modal = Instance.new("Frame")
	modal.Name = "UpgradesModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(660, 445)
	modal.BackgroundColor3 = Color3.fromRGB(34, 38, 46)
	modal.Visible = false
	modal.ZIndex = 10
	modal.Parent = parent
	addCorner(modal, 14)
	addStroke(modal, Color3.fromRGB(15, 18, 24), 3.2, Enum.ApplyStrokeMode.Border)

	-- Top Window Bar
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 54)
	header.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	header.Parent = modal
	addCorner(header, 14)
	UiKit.AddGlossGradient(header, Color3.fromRGB(55, 165, 235))
	addStroke(header, Color3.fromRGB(14, 24, 38), 2.2, Enum.ApplyStrokeMode.Border)

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(18, 6)
	title.Size = UDim2.fromOffset(230, 40)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 28
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "⬆️ Upgrades"
	title.Parent = header
	addStroke(title, Color3.fromRGB(12, 20, 32), 2.5)

	local cashBadge = Instance.new("Frame")
	cashBadge.AnchorPoint = Vector2.new(1, 0.5)
	cashBadge.Position = UDim2.new(1, -205, 0.5, 0)
	cashBadge.Size = UDim2.fromOffset(138, 36)
	cashBadge.BackgroundColor3 = Color3.fromRGB(20, 36, 26)
	cashBadge.Parent = header
	addCorner(cashBadge, 10)
	addStroke(cashBadge, Color3.fromRGB(90, 235, 110), 2, Enum.ApplyStrokeMode.Border)

	local cashBalanceLabel = Instance.new("TextLabel")
	cashBalanceLabel.Size = UDim2.fromScale(1, 1)
	cashBalanceLabel.BackgroundTransparency = 1
	cashBalanceLabel.Font = Enum.Font.FredokaOne
	cashBalanceLabel.TextSize = 19
	cashBalanceLabel.TextColor3 = Color3.fromRGB(105, 250, 120)
	cashBalanceLabel.Text = "💵 $0"
	cashBalanceLabel.Parent = cashBadge
	addStroke(cashBalanceLabel, Color3.fromRGB(12, 20, 14), 2)

	local gemBadge = Instance.new("Frame")
	gemBadge.AnchorPoint = Vector2.new(1, 0.5)
	gemBadge.Position = UDim2.new(1, -58, 0.5, 0)
	gemBadge.Size = UDim2.fromOffset(138, 36)
	gemBadge.BackgroundColor3 = Color3.fromRGB(22, 32, 48)
	gemBadge.Parent = header
	addCorner(gemBadge, 10)
	addStroke(gemBadge, Color3.fromRGB(95, 195, 255), 2, Enum.ApplyStrokeMode.Border)

	local gemBalanceLabel = Instance.new("TextLabel")
	gemBalanceLabel.Size = UDim2.fromScale(1, 1)
	gemBalanceLabel.BackgroundTransparency = 1
	gemBalanceLabel.Font = Enum.Font.FredokaOne
	gemBalanceLabel.TextSize = 19
	gemBalanceLabel.TextColor3 = Color3.fromRGB(120, 210, 255)
	gemBalanceLabel.Text = "💎 0"
	gemBalanceLabel.Parent = gemBadge
	addStroke(gemBalanceLabel, Color3.fromRGB(12, 18, 28), 2)

	UiKit.CreateBevelButton({
		Name = "CloseBtn",
		Parent = header,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 1),
		Size = UDim2.fromOffset(40, 40),
		Color = Color3.fromRGB(235, 55, 65),
		CornerRadius = 9,
		Text = "X",
		TextSize = 22,
		OnClick = function()
			UiKit.ToggleModalAnimated(modal, ctx.ModalScrim, false)
		end,
	})

	-- ============================================================================
	-- TAB BAR + DEDICATED PER-TAB HEADER BANNER
	-- ============================================================================
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Position = UDim2.fromOffset(14, 62)
	tabBar.Size = UDim2.new(1, -28, 0, 40)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = modal

	local tabBarLayout = Instance.new("UIListLayout")
	tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
	tabBarLayout.Padding = UDim.new(0, 10)
	tabBarLayout.Parent = tabBar

	local tabHeaderBanner = Instance.new("Frame")
	tabHeaderBanner.Name = "ActiveTabHeader"
	tabHeaderBanner.Position = UDim2.fromOffset(14, 110)
	tabHeaderBanner.Size = UDim2.new(1, -28, 0, 64)
	tabHeaderBanner.BackgroundColor3 = TABS[1].HeaderColor
	tabHeaderBanner.Parent = modal
	addCorner(tabHeaderBanner, 12)
	addStroke(tabHeaderBanner, Color3.fromRGB(16, 18, 26), 2.2, Enum.ApplyStrokeMode.Border)

	local tabHeaderTitle = Instance.new("TextLabel")
	tabHeaderTitle.Position = UDim2.fromOffset(16, 6)
	tabHeaderTitle.Size = UDim2.new(1, -32, 0, 28)
	tabHeaderTitle.BackgroundTransparency = 1
	tabHeaderTitle.Font = Enum.Font.FredokaOne
	tabHeaderTitle.TextSize = 23
	tabHeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
	tabHeaderTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	tabHeaderTitle.Text = TABS[1].HeaderTitle
	tabHeaderTitle.Parent = tabHeaderBanner
	addStroke(tabHeaderTitle, Color3.fromRGB(15, 18, 25), 2.2)

	local tabHeaderSubtitle = Instance.new("TextLabel")
	tabHeaderSubtitle.Position = UDim2.fromOffset(16, 34)
	tabHeaderSubtitle.Size = UDim2.new(1, -32, 0, 22)
	tabHeaderSubtitle.BackgroundTransparency = 1
	tabHeaderSubtitle.Font = Enum.Font.FredokaOne
	tabHeaderSubtitle.TextSize = 16
	tabHeaderSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	tabHeaderSubtitle.TextColor3 = Color3.fromRGB(240, 245, 255)
	tabHeaderSubtitle.Text = TABS[1].HeaderSubtitle
	tabHeaderSubtitle.Parent = tabHeaderBanner
	addStroke(tabHeaderSubtitle, Color3.fromRGB(15, 18, 25), 1.6)

	local pages: { [TabKey]: Frame } = {}
	local tabFaces: { [TabKey]: Frame } = {}

	local function makeTabPage(key: TabKey): Frame
		local page = Instance.new("Frame")
		page.Name = `{key}TabPage`
		page.Position = UDim2.fromOffset(14, 184)
		page.Size = UDim2.new(1, -28, 1, -196)
		page.BackgroundColor3 = Color3.fromRGB(26, 30, 38)
		page.Visible = false
		page.Parent = modal
		addCorner(page, 12)
		addStroke(page, Color3.fromRGB(16, 18, 24), 2.2, Enum.ApplyStrokeMode.Border)
		pages[key] = page
		return page
	end

	local function selectTab(activeSpec: TabSpec)
		tabHeaderBanner.BackgroundColor3 = activeSpec.HeaderColor
		tabHeaderTitle.Text = activeSpec.HeaderTitle
		tabHeaderSubtitle.Text = activeSpec.HeaderSubtitle
		for _, spec in TABS do
			local page = pages[spec.Key]
			if page then
				page.Visible = (spec.Key == activeSpec.Key)
			end
			local face = tabFaces[spec.Key]
			if face then
				face.BackgroundColor3 = if spec.Key == activeSpec.Key
					then spec.TabColor
					else spec.TabColor:Lerp(Color3.fromRGB(30, 34, 44), 0.55)
			end
		end
	end

	for _, spec in TABS do
		local specCopy = spec
		local _, btnFace = UiKit.CreateBevelButton({
			Name = `TabBtn_{spec.Key}`,
			Parent = tabBar,
			Size = UDim2.fromOffset(204, 38),
			Color = spec.TabColor,
			CornerRadius = 10,
			Text = spec.TabButtonText,
			TextSize = 18,
			OnClick = function()
				selectTab(specCopy)
			end,
		})
		tabFaces[spec.Key] = btnFace
	end

	local function addWideShopButton(page: Frame, itemId: string, rowIdx: number)
		local item = GameConfig.ShopCatalogById[itemId]
		if not item then
			return
		end
		local _, _, lbl = UiKit.CreateBevelButton({
			Name = `Buy_{item.Id}`,
			Parent = page,
			Position = UDim2.fromOffset(14, 14 + (rowIdx - 1) * 58),
			Size = UDim2.new(1, -28, 0, 48),
			Color = SlimeFactory.ToColor3(item.Color),
			CornerRadius = 10,
			Text = item.Icon,
			TextSize = 18,
			OnClick = function()
				ctx.BuyShopItem(item.Id, 1)
			end,
		})
		ctx.BindShopLabel(lbl, item.Id, 1, "RowWide")
	end

	-- ============================================================================
	-- TAB 1: ⚡ POWER & TRAINING (Throw Power Buy + Buy Max, Pull-Up Bar Tier, x2 Training Power)
	-- ============================================================================
	local powerPage = makeTabPage("Power")
	local powerItem = GameConfig.ShopCatalogById["power_upgrade"]
	if powerItem then
		local _, _, buy1PowerLbl = UiKit.CreateBevelButton({
			Name = "Buy_power_upgrade_1",
			Parent = powerPage,
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.new(0.68, -18, 0, 48),
			Color = SlimeFactory.ToColor3(powerItem.Color),
			CornerRadius = 10,
			Text = powerItem.Icon,
			TextSize = 18,
			OnClick = function()
				ctx.BuyShopItem("power_upgrade", 1)
			end,
		})
		ctx.BindShopLabel(buy1PowerLbl, "power_upgrade", 1, "RowWide")

		local _, _, buyMaxPowerLbl = UiKit.CreateBevelButton({
			Name = "Buy_power_upgrade_max",
			Parent = powerPage,
			Position = UDim2.new(0.68, 4, 0, 14),
			Size = UDim2.new(0.32, -18, 0, 48),
			Color = Color3.fromRGB(55, 195, 95),
			CornerRadius = 10,
			Text = "Buy Max",
			TextSize = 18,
			OnClick = function()
				ctx.BuyShopItem("power_upgrade", "max")
			end,
		})
		ctx.BindShopLabel(buyMaxPowerLbl, "power_upgrade", 2, "Option")
	end
	addWideShopButton(powerPage, "pullup_tier", 2)
	addWideShopButton(powerPage, "boost_double_power", 3)

	-- ============================================================================
	-- TAB 2: 🥕 BAIT & PLOT (Jelly Bait Tier, +4 Slime Slots, x2 Cash)
	-- ============================================================================
	local baitPage = makeTabPage("Bait")
	addWideShopButton(baitPage, "bait_tier", 1)
	addWideShopButton(baitPage, "slot_expansion", 2)
	addWideShopButton(baitPage, "boost_double_cash", 3)

	-- ============================================================================
	-- TAB 3: 💎 GEM UPGRADES (Auto-Throw, Lucky Charm, +4 Slime Slots)
	-- ============================================================================
	local gemPage = makeTabPage("Gem")
	local gemRow = 0
	for _, item in GameConfig.ShopCatalog do
		if item.Category == "Gem" then
			gemRow += 1
			addWideShopButton(gemPage, item.Id, gemRow)
		end
	end

	selectTab(TABS[1])

	local function refresh(state: any)
		cashBalanceLabel.Text = `💵 ${GameConfig.FormatNumber(state.Cash or 0)}`
		gemBalanceLabel.Text = `💎 {GameConfig.FormatNumber(state.Gems or 0)}`
	end

	return {
		Frame = modal,
		Refresh = refresh,
	}
end

return UpgradesWindow
