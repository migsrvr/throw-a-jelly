--!strict
--[[
	HudController.client.luau
	Implements the Clip 2 (19-02-39.mp4) UI & Guidance loop powered by UiKit.luau
	(following the workspace `roblox-ui-luau` skill):
	- Adaptive responsive UIScale for PC, Mobile, Tablet, 4K
	- 3D-Bevel glossy tactile buttons with TweenService spring hover/press animations
	- Live 3D ViewportFrame slime renders in Hotbar tiles, Slime Index cards
	  (including 3D dark silhouettes for ??? locked slimes), and Shop Egg odds cards!
	- Modal spring pop-in animations + dimmed backdrop scrim
	- 3D Bouncing Yellow Arrow (▼) & Golden Floor Chevron Trail (>>>)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterAnimator = require(Shared:WaitForChild("CharacterAnimator"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))
local UiKit = require(Shared:WaitForChild("UiKit"))

local HudWindows = script.Parent:WaitForChild("HudWindows")
local UpgradesWindow = require(HudWindows:WaitForChild("UpgradesWindow"))
local RewardsWindow = require(HudWindows:WaitForChild("RewardsWindow"))
local RobuxStoreWindow = require(HudWindows:WaitForChild("RobuxStoreWindow"))

local stateSync = Remotes.GetEvent("PlayerStateSync")
local toastNotify = Remotes.GetEvent("ToastNotify")
local requestPurchase = Remotes.GetEvent("RequestPurchase")
local requestPlaceBest = Remotes.GetEvent("RequestPlaceBestSlimes")
local requestPlaceOnSlot = Remotes.GetEvent("RequestPlaceOnSlot")
local requestEquipTrail = Remotes.GetEvent("RequestEquipTrail")
local requestClaimDaily = Remotes.GetEvent("RequestClaimDaily")
local requestClaimQuest = Remotes.GetEvent("RequestClaimQuest")

-- ============================================================================
-- SHOP BINDING (logic lives in GameConfig.ShopCatalog + ProgressionLogic.GetShopListing/Purchase)
-- UI code only: (1) fires buyShopItem(itemId, quantity) and (2) registers labels with
-- bindShopLabel so refreshShopLabels() can fill in names/prices/states from the listing.
-- ============================================================================
local function buyShopItem(itemId: string, quantity: (number | string)?)
	requestPurchase:FireServer({ ItemId = itemId, Quantity = quantity or 1 })
end

type ShopLabelBinding = { Label: TextLabel, ItemId: string, OptionIndex: number, Style: "Row" | "RowWide" | "Option" }
local shopLabelBindings: { ShopLabelBinding } = {}

local function bindShopLabel(label: TextLabel?, itemId: string, optionIndex: number, style: "Row" | "RowWide" | "Option")
	if label then
		table.insert(shopLabelBindings, { Label = label, ItemId = itemId, OptionIndex = optionIndex, Style = style })
	end
end

local currentState: any = {
	Cash = 0,
	Gems = 0,
	EffectiveThrowPower = 5,
	PowerUpgradeLevel = 1,
	NextPowerCost = 25,
	PullUpTier = 1,
	MaxSlimes = 8,
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
	TotalThrows = 0,
	TotalPullUps = 0,
	PendingIncome = 0,
	IncomePerSec = 2,
}

local selectedHotbarUid: string? = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ReferenceSlimeHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

UiKit.AttachResponsiveScale(screenGui)

local addCorner = UiKit.AddCorner
local addStroke = UiKit.AddStroke

-- Full-screen dimmed backdrop scrim for modals
local modalScrim = Instance.new("Frame")
modalScrim.Name = "ModalScrim"
modalScrim.Size = UDim2.fromScale(1, 1)
modalScrim.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
modalScrim.BackgroundTransparency = 1
modalScrim.Visible = false
modalScrim.ZIndex = 8
modalScrim.Parent = screenGui

-- ============================================================================
-- 1. TOP-CENTER OBJECTIVE PROMPT & TOAST BANNER
-- ============================================================================
local objectiveLabel = Instance.new("TextLabel")
objectiveLabel.Name = "ObjectivePrompt"
objectiveLabel.AnchorPoint = Vector2.new(0.5, 0)
objectiveLabel.Position = UDim2.new(0.5, 0, 0, 14)
objectiveLabel.Size = UDim2.fromOffset(480, 42)
objectiveLabel.BackgroundTransparency = 1
objectiveLabel.Font = Enum.Font.FredokaOne
objectiveLabel.TextSize = 30
objectiveLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
objectiveLabel.Text = "Walk to the Throw Line!"
objectiveLabel.Parent = screenGui
addStroke(objectiveLabel, Color3.fromRGB(15, 18, 25), 2.8)

local toastLabel = Instance.new("TextLabel")
toastLabel.Name = "ToastBanner"
toastLabel.AnchorPoint = Vector2.new(0.5, 0)
toastLabel.Position = UDim2.new(0.5, 0, 0, 56)
toastLabel.Size = UDim2.fromOffset(520, 32)
toastLabel.BackgroundTransparency = 1
toastLabel.TextTransparency = 1
toastLabel.Font = Enum.Font.FredokaOne
toastLabel.TextSize = 20
toastLabel.TextColor3 = Color3.fromRGB(255, 235, 95)
toastLabel.Text = ""
toastLabel.Parent = screenGui
local toastStroke = addStroke(toastLabel, Color3.fromRGB(15, 18, 25), 2.2)
toastStroke.Transparency = 1

local toastToken = 0
local function showToast(msg: string, color: Color3?)
	toastToken += 1
	local myToken = toastToken
	toastLabel.Text = msg
	toastLabel.TextColor3 = color or Color3.fromRGB(255, 235, 95)
	toastLabel.TextTransparency = 0
	toastStroke.Transparency = 0
	task.delay(2.5, function()
		if toastToken == myToken then
			toastLabel.TextTransparency = 1
			toastStroke.Transparency = 1
		end
	end)
end

toastNotify.OnClientEvent:Connect(function(payload: any)
	if type(payload) == "table" and type(payload.Message) == "string" then
		local kind = payload.Kind
		local col = if kind == "warn"
			then Color3.fromRGB(255, 110, 110)
			elseif kind == "cash" then Color3.fromRGB(105, 255, 130)
			elseif kind == "gems" then Color3.fromRGB(120, 200, 255)
			else Color3.fromRGB(255, 235, 95)
		showToast(payload.Message, col)
	end
end)

-- ============================================================================
-- 2. 3D-BEVEL SQUARE NAVIGATION BUTTON BUILDER (Index, Shop, Slimes)
-- ============================================================================
local function createSquareBevelNavButton(
	name: string,
	iconText: string,
	labelText: string,
	bgColor: Color3,
	pos: UDim2,
	anchor: Vector2,
	onClick: () -> (),
	use3DSlimeIcon: boolean?
): TextButton
	local btn, face = UiKit.CreateBevelButton({
		Name = name,
		Parent = screenGui,
		Position = pos,
		AnchorPoint = anchor,
		Size = UDim2.fromOffset(78, 78),
		Color = bgColor,
		CornerRadius = 15,
		OnClick = onClick,
	})

	if use3DSlimeIcon then
		local vpHolder = Instance.new("Frame")
		vpHolder.AnchorPoint = Vector2.new(0.5, 0)
		vpHolder.Position = UDim2.new(0.5, 0, 0, 2)
		vpHolder.Size = UDim2.fromOffset(52, 48)
		vpHolder.BackgroundTransparency = 1
		vpHolder.Parent = face
		UiKit.CreateSlimeViewport(vpHolder, "meadow_sprout", "EMERALD", false)
	else
		local innerIcon = Instance.new("TextLabel")
		innerIcon.AnchorPoint = Vector2.new(0.5, 0)
		innerIcon.Position = UDim2.new(0.5, 0, 0, 6)
		innerIcon.Size = UDim2.fromOffset(48, 42)
		innerIcon.BackgroundTransparency = 1
		innerIcon.Font = Enum.Font.FredokaOne
		innerIcon.TextSize = 34
		innerIcon.Text = iconText
		innerIcon.Parent = face
	end

	local bottomLbl = Instance.new("TextLabel")
	bottomLbl.AnchorPoint = Vector2.new(0.5, 1)
	bottomLbl.Position = UDim2.new(0.5, 0, 1, -4)
	bottomLbl.Size = UDim2.new(1, -4, 0, 22)
	bottomLbl.BackgroundTransparency = 1
	bottomLbl.Font = Enum.Font.FredokaOne
	bottomLbl.TextSize = 18
	bottomLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	bottomLbl.Text = labelText
	bottomLbl.Parent = face
	addStroke(bottomLbl, Color3.fromRGB(15, 18, 25), 2.2)

	return btn
end

-- ============================================================================
-- 3. BOTTOM-LEFT FLOATING STATS (💪 Power, 💵 Cash)
-- ============================================================================
local bottomLeftStats = Instance.new("Frame")
bottomLeftStats.Name = "BottomLeftStats"
bottomLeftStats.AnchorPoint = Vector2.new(0, 1)
bottomLeftStats.Position = UDim2.new(0, 18, 1, -16)
bottomLeftStats.Size = UDim2.fromOffset(230, 120)
bottomLeftStats.BackgroundTransparency = 1
bottomLeftStats.Parent = screenGui

local powerRowLabel = Instance.new("TextLabel")
powerRowLabel.Position = UDim2.fromOffset(0, 0)
powerRowLabel.Size = UDim2.fromOffset(230, 38)
powerRowLabel.BackgroundTransparency = 1
powerRowLabel.Font = Enum.Font.FredokaOne
powerRowLabel.TextSize = 32
powerRowLabel.TextXAlignment = Enum.TextXAlignment.Left
powerRowLabel.TextColor3 = Color3.fromRGB(65, 205, 255)
powerRowLabel.Text = "💪 5"
powerRowLabel.Parent = bottomLeftStats
addStroke(powerRowLabel, Color3.fromRGB(15, 18, 25), 3)

local cashRowLabel = Instance.new("TextLabel")
cashRowLabel.Position = UDim2.fromOffset(0, 40)
cashRowLabel.Size = UDim2.fromOffset(230, 38)
cashRowLabel.BackgroundTransparency = 1
cashRowLabel.Font = Enum.Font.FredokaOne
cashRowLabel.TextSize = 32
cashRowLabel.TextXAlignment = Enum.TextXAlignment.Left
cashRowLabel.TextColor3 = Color3.fromRGB(85, 245, 95)
cashRowLabel.Text = "💵 $0"
cashRowLabel.Parent = bottomLeftStats
addStroke(cashRowLabel, Color3.fromRGB(15, 18, 25), 3)

local gemsRowLabel = Instance.new("TextLabel")
gemsRowLabel.Name = "GemsRow"
gemsRowLabel.Position = UDim2.fromOffset(0, 80)
gemsRowLabel.Size = UDim2.fromOffset(230, 38)
gemsRowLabel.BackgroundTransparency = 1
gemsRowLabel.Font = Enum.Font.FredokaOne
gemsRowLabel.TextSize = 32
gemsRowLabel.TextXAlignment = Enum.TextXAlignment.Left
gemsRowLabel.TextColor3 = Color3.fromRGB(120, 200, 255)
gemsRowLabel.Text = "💎 0"
gemsRowLabel.Parent = bottomLeftStats
addStroke(gemsRowLabel, Color3.fromRGB(15, 18, 25), 3)

-- ============================================================================
-- 4. BOTTOM-CENTER HOTBAR ([1]..[5]) WITH 3D VIEWPORTFRAME SLIMES
-- ============================================================================
local hotbarContainer = Instance.new("Frame")
hotbarContainer.Name = "HotbarContainer"
hotbarContainer.AnchorPoint = Vector2.new(0.5, 1)
hotbarContainer.Position = UDim2.new(0.5, 0, 1, -12)
hotbarContainer.Size = UDim2.fromOffset(410, 78)
hotbarContainer.BackgroundTransparency = 1
hotbarContainer.Parent = screenGui

local hotbarLayout = Instance.new("UIListLayout")
hotbarLayout.FillDirection = Enum.FillDirection.Horizontal
hotbarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
hotbarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
hotbarLayout.Padding = UDim.new(0, 10)
hotbarLayout.Parent = hotbarContainer

local hotbarArrow = Instance.new("TextLabel")
hotbarArrow.Name = "HotbarGuideArrow"
hotbarArrow.AnchorPoint = Vector2.new(0.5, 1)
hotbarArrow.Position = UDim2.new(0.5, 0, 1, -94)
hotbarArrow.Size = UDim2.fromOffset(48, 48)
hotbarArrow.BackgroundTransparency = 1
hotbarArrow.Font = Enum.Font.FredokaOne
hotbarArrow.TextSize = 38
hotbarArrow.TextColor3 = Color3.fromRGB(255, 215, 45)
hotbarArrow.Text = "▼"
hotbarArrow.Visible = false
hotbarArrow.Parent = screenGui
addStroke(hotbarArrow, Color3.fromRGB(20, 18, 10), 2.8)

local function findFirstFreePlotSlot(): number?
	local placedMap = currentState.PlacedSlimesBySlot or {}
	local maxS = currentState.MaxSlimes or 8
	for s = 1, maxS do
		if not placedMap[tostring(s)] and not placedMap[s] then
			return s
		end
	end
	return nil
end

local quickPlaceBtn = UiKit.CreateBevelButton({
	Name = "QuickPlaceBtn",
	Parent = screenGui,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -100),
	Size = UDim2.fromOffset(245, 44),
	Color = Color3.fromRGB(70, 215, 95),
	CornerRadius = 12,
	Text = "✨ Place Slime on Free Slot",
	TextSize = 19,
	OnClick = function()
		if not selectedHotbarUid then
			return
		end
		local freeSlot = findFirstFreePlotSlot() or 1
		requestPlaceOnSlot:FireServer({
			SlimeUid = selectedHotbarUid,
			SlotIndex = freeSlot,
		})
		selectedHotbarUid = nil
		CharacterAnimator.StopCarrySlime()
	end,
})
quickPlaceBtn.Visible = false

-- ============================================================================
-- 5. SLIME INDEX MODAL ("Index" button — Clip 2 00:16–00:20)
-- ============================================================================
local indexModal = Instance.new("Frame")
indexModal.Name = "SlimeIndexModal"
indexModal.AnchorPoint = Vector2.new(0.5, 0.5)
indexModal.Position = UDim2.fromScale(0.5, 0.5)
indexModal.Size = UDim2.fromOffset(660, 425)
indexModal.BackgroundColor3 = Color3.fromRGB(34, 38, 46)
indexModal.Visible = false
indexModal.ZIndex = 10
indexModal.Parent = screenGui
addCorner(indexModal, 14)
addStroke(indexModal, Color3.fromRGB(15, 18, 24), 3.2, Enum.ApplyStrokeMode.Border)

local indexHeader = Instance.new("Frame")
indexHeader.Size = UDim2.new(1, 0, 0, 54)
indexHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
indexHeader.Parent = indexModal
addCorner(indexHeader, 14)
UiKit.AddGlossGradient(indexHeader, Color3.fromRGB(175, 70, 245))
addStroke(indexHeader, Color3.fromRGB(20, 12, 32), 2.2, Enum.ApplyStrokeMode.Border)

local indexTitle = Instance.new("TextLabel")
indexTitle.Position = UDim2.fromOffset(18, 6)
indexTitle.Size = UDim2.fromOffset(220, 40)
indexTitle.BackgroundTransparency = 1
indexTitle.Font = Enum.Font.FredokaOne
indexTitle.TextSize = 28
indexTitle.TextXAlignment = Enum.TextXAlignment.Left
indexTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
indexTitle.Text = "Slime Index"
indexTitle.Parent = indexHeader
addStroke(indexTitle, Color3.fromRGB(20, 10, 30), 2.5)

UiKit.CreateBevelButton({
	Name = "CloseBtn",
	Parent = indexHeader,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 1),
	Size = UDim2.fromOffset(40, 40),
	Color = Color3.fromRGB(235, 55, 65),
	CornerRadius = 9,
	Text = "X",
	TextSize = 22,
	OnClick = function()
		UiKit.ToggleModalAnimated(indexModal, modalScrim, false)
	end,
})

local indexScroll = Instance.new("ScrollingFrame")
indexScroll.Position = UDim2.fromOffset(14, 64)
indexScroll.Size = UDim2.new(1, -28, 1, -106)
indexScroll.BackgroundTransparency = 1
indexScroll.BorderSizePixel = 0
indexScroll.ScrollBarThickness = 6
indexScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
indexScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
indexScroll.Parent = indexModal

local indexListLayout = Instance.new("UIListLayout")
indexListLayout.Padding = UDim.new(0, 12)
indexListLayout.Parent = indexScroll

local indexFooterLabel = Instance.new("TextLabel")
indexFooterLabel.AnchorPoint = Vector2.new(0.5, 1)
indexFooterLabel.Position = UDim2.new(0.5, 0, 1, -8)
indexFooterLabel.Size = UDim2.fromOffset(260, 28)
indexFooterLabel.BackgroundTransparency = 1
indexFooterLabel.Font = Enum.Font.FredokaOne
indexFooterLabel.TextSize = 22
indexFooterLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
indexFooterLabel.Text = "📘 Unlocked: 1/15"
indexFooterLabel.Parent = indexModal
addStroke(indexFooterLabel, Color3.fromRGB(15, 18, 25), 2.2)

-- ============================================================================
-- 6. SHOP LABEL REFRESH (used by UpgradesWindow & RobuxStoreWindow)
-- ============================================================================
-- Fill every bound shop label from the shared listing (computed locally from synced state)
local function refreshShopLabels()
	local byId: { [string]: ProgressionLogic.ShopListingEntry } = {}
	for _, entry in ProgressionLogic.GetShopListing(currentState) do
		byId[entry.Id] = entry
	end
	for _, b in shopLabelBindings do
		local entry = byId[b.ItemId]
		if entry then
			local opt = entry.Options[b.OptionIndex]
			local soldOut = entry.State == "Owned" or entry.State == "Maxed" or entry.State == "Claimed"
			if b.Style == "RowWide" then
				-- Wide rows have room for the subtitle (e.g. bait "Luck 1x -> 1.35x")
				-- Maxed rows say why in the subtitle; owned/claimed rows just show the name + OWNED
				b.Label.Text = if entry.State == "Maxed"
					then `{entry.Icon} {entry.Subtitle}`
					elseif soldOut then `{entry.Icon} {entry.Title} — {entry.PriceText}`
					else `{entry.Icon} {entry.Title} ({entry.Subtitle}) — {entry.PriceText}`
			elseif b.Style == "Row" then
				b.Label.Text = if soldOut
					then `{entry.Icon} {entry.Title} ({entry.PriceText})`
					else `{entry.Icon} {entry.Title} — {entry.PriceText}`
			else
				b.Label.Text = if soldOut or not opt then entry.PriceText else opt.Label
			end
			b.Label.TextTransparency = if opt and not opt.CanAfford then 0.35 else 0
		end
	end
end

-- ============================================================================
-- 7. SLIMES BACKPACK MODAL ("Slimes" button on Right)
-- ============================================================================
local slimesModal = Instance.new("Frame")
slimesModal.Name = "SlimesModal"
slimesModal.AnchorPoint = Vector2.new(0.5, 0.5)
slimesModal.Position = UDim2.fromScale(0.5, 0.5)
slimesModal.Size = UDim2.fromOffset(530, 380)
slimesModal.BackgroundColor3 = Color3.fromRGB(34, 38, 46)
slimesModal.Visible = false
slimesModal.ZIndex = 10
slimesModal.Parent = screenGui
addCorner(slimesModal, 14)
addStroke(slimesModal, Color3.fromRGB(15, 18, 24), 3.2, Enum.ApplyStrokeMode.Border)

local slimesHeader = Instance.new("Frame")
slimesHeader.Size = UDim2.new(1, 0, 0, 52)
slimesHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
slimesHeader.Parent = slimesModal
addCorner(slimesHeader, 14)
UiKit.AddGlossGradient(slimesHeader, Color3.fromRGB(225, 130, 35))
addStroke(slimesHeader, Color3.fromRGB(25, 15, 10), 2.2, Enum.ApplyStrokeMode.Border)

local slimesTitle = Instance.new("TextLabel")
slimesTitle.Position = UDim2.fromOffset(18, 5)
slimesTitle.Size = UDim2.fromOffset(320, 40)
slimesTitle.BackgroundTransparency = 1
slimesTitle.Font = Enum.Font.FredokaOne
slimesTitle.TextSize = 25
slimesTitle.TextXAlignment = Enum.TextXAlignment.Left
slimesTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
slimesTitle.Text = "My Slimes Backpack"
slimesTitle.Parent = slimesHeader
addStroke(slimesTitle, Color3.fromRGB(25, 15, 10), 2.2)

UiKit.CreateBevelButton({
	Name = "CloseBtn",
	Parent = slimesHeader,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 1),
	Size = UDim2.fromOffset(38, 38),
	Color = Color3.fromRGB(235, 55, 65),
	CornerRadius = 9,
	Text = "X",
	TextSize = 20,
	OnClick = function()
		UiKit.ToggleModalAnimated(slimesModal, modalScrim, false)
	end,
})

local slimesScroll = Instance.new("ScrollingFrame")
slimesScroll.Position = UDim2.fromOffset(14, 60)
slimesScroll.Size = UDim2.new(1, -28, 1, -120)
slimesScroll.BackgroundTransparency = 1
slimesScroll.BorderSizePixel = 0
slimesScroll.ScrollBarThickness = 6
slimesScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
slimesScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
slimesScroll.Parent = slimesModal

local slimesListLayout = Instance.new("UIListLayout")
slimesListLayout.Padding = UDim.new(0, 8)
slimesListLayout.Parent = slimesScroll

UiKit.CreateBevelButton({
	Name = "AutoPlaceBestBtn",
	Parent = slimesModal,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(300, 42),
	Color = Color3.fromRGB(75, 215, 95),
	CornerRadius = 10,
	Text = "✨ Auto-Place Best Slimes on Plot",
	TextSize = 18,
	OnClick = function()
		requestPlaceBest:FireServer()
		selectedHotbarUid = nil
		CharacterAnimator.StopCarrySlime()
		quickPlaceBtn.Visible = false
	end,
})

-- Build Modular HUD Windows (Tabbed Upgrades, Rewards + Quests, Unified Left-Side Robux Shop)
local upgradesWin = UpgradesWindow.Build(screenGui, {
	ModalScrim = modalScrim,
	BindShopLabel = bindShopLabel,
	BuyShopItem = buyShopItem,
})

local rewardsWin = RewardsWindow.Build(screenGui, {
	ModalScrim = modalScrim,
	OnClaimDaily = function()
		requestClaimDaily:FireServer()
	end,
	OnClaimQuest = function(kind: "Line" | "Daily", index: number?)
		requestClaimQuest:FireServer({ Kind = kind, Index = index })
	end,
})

local robuxWin = RobuxStoreWindow.Build(screenGui, {
	ModalScrim = modalScrim,
	OnToast = showToast,
	BindShopLabel = bindShopLabel,
	BuyShopItem = buyShopItem,
})

local allModals: { Frame } = {
	indexModal,
	robuxWin.Frame,
	upgradesWin.Frame,
	rewardsWin.Frame,
	slimesModal,
}

local function toggleExclusiveModal(target: Frame)
	local willOpen = not target.Visible
	for _, m in allModals do
		if m ~= target then
			m.Visible = false
		end
	end
	UiKit.ToggleModalAnimated(target, modalScrim, willOpen)
end

-- Left Column (3 buttons, top to bottom): Index (📘), Shop (R$ Robux Shop), Upgrades (⬆️)
createSquareBevelNavButton(
	"IndexNavBtn",
	"📘",
	"Index",
	Color3.fromRGB(45, 140, 235),
	UDim2.new(0, 16, 0.5, -90),
	Vector2.new(0, 0.5),
	function()
		toggleExclusiveModal(indexModal)
	end,
	false
)

createSquareBevelNavButton(
	"ShopNavBtn",
	"R$",
	"Shop",
	Color3.fromRGB(220, 55, 55),
	UDim2.new(0, 16, 0.5, 0),
	Vector2.new(0, 0.5),
	function()
		toggleExclusiveModal(robuxWin.Frame)
	end,
	false
)

createSquareBevelNavButton(
	"UpgradesNavBtn",
	"⬆️",
	"Upgrades",
	Color3.fromRGB(55, 175, 235),
	UDim2.new(0, 16, 0.5, 90),
	Vector2.new(0, 0.5),
	function()
		toggleExclusiveModal(upgradesWin.Frame)
	end,
	false
)

-- Right Column (2 buttons, top to bottom): Rewards (🎁, with red "!" badge) and Slimes
local rewardsNavBtn = createSquareBevelNavButton(
	"RewardsNavBtn",
	"🎁",
	"Rewards",
	Color3.fromRGB(245, 155, 45),
	UDim2.new(1, -16, 0.5, -46),
	Vector2.new(1, 0.5),
	function()
		toggleExclusiveModal(rewardsWin.Frame)
	end,
	false
)

local rewardsBadge = Instance.new("TextLabel")
rewardsBadge.Name = "ClaimBadge"
rewardsBadge.AnchorPoint = Vector2.new(0.5, 0.5)
rewardsBadge.Position = UDim2.new(1, -6, 0, 6)
rewardsBadge.Size = UDim2.fromOffset(26, 26)
rewardsBadge.BackgroundColor3 = Color3.fromRGB(245, 45, 55)
rewardsBadge.Font = Enum.Font.FredokaOne
rewardsBadge.TextSize = 18
rewardsBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
rewardsBadge.Text = "!"
rewardsBadge.ZIndex = 6
rewardsBadge.Visible = false
rewardsBadge.Parent = rewardsNavBtn
addCorner(rewardsBadge, 13)
addStroke(rewardsBadge, Color3.fromRGB(20, 10, 12), 2)

createSquareBevelNavButton(
	"SlimesNavBtn",
	"",
	"Slimes",
	Color3.fromRGB(225, 130, 35),
	UDim2.new(1, -16, 0.5, 46),
	Vector2.new(1, 0.5),
	function()
		toggleExclusiveModal(slimesModal)
	end,
	true
)

-- ============================================================================
-- 8. REFRESH UI FUNCTIONS (HOTBAR WITH 3D VIEWPORTS, INDEX, SHOP, BACKPACK)
-- ============================================================================
local function selectHotbarSlime(inst: any)
	if selectedHotbarUid == inst.Uid then
		selectedHotbarUid = nil
		CharacterAnimator.StopCarrySlime()
		quickPlaceBtn.Visible = false
	else
		selectedHotbarUid = inst.Uid
		CharacterAnimator.StartCarrySlime(localPlayer.Character, inst.SlimeId, inst.Mutation)
		quickPlaceBtn.Visible = true
	end
end

local function rebuildHotbar()
	for _, child in hotbarContainer:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local unplaced = currentState.UnplacedSlimes or {}
	local count = math.min(5, #unplaced)

	for i = 1, count do
		local inst = unplaced[i]
		local def = GameConfig.SlimesById[inst.SlimeId] or GameConfig.Slimes[1]
		local isSelected = (selectedHotbarUid == inst.Uid)

		local tile = Instance.new("TextButton")
		tile.Name = `HotbarSlot_{i}`
		tile.Size = UDim2.fromOffset(72, 72)
		tile.BackgroundColor3 = if isSelected
			then Color3.fromRGB(48, 110, 68)
			else Color3.fromRGB(22, 25, 34)
		tile.BackgroundTransparency = 0.12
		tile.AutoButtonColor = false
		tile.Text = ""
		tile.Parent = hotbarContainer
		addCorner(tile, 11)
		addStroke(
			tile,
			if isSelected then Color3.fromRGB(115, 255, 130) else Color3.fromRGB(240, 245, 255),
			if isSelected then 3.2 else 2.2,
			Enum.ApplyStrokeMode.Border
		)
		UiKit.AttachButtonJuice(tile, nil)

		-- Real 3D ViewportFrame preview of the caught slime inside the Hotbar tile!
		local vpHolder = Instance.new("Frame")
		vpHolder.AnchorPoint = Vector2.new(0.5, 0.5)
		vpHolder.Position = UDim2.fromScale(0.5, 0.5)
		vpHolder.Size = UDim2.fromOffset(52, 48)
		vpHolder.BackgroundTransparency = 1
		vpHolder.Parent = tile
		UiKit.CreateSlimeViewport(vpHolder, inst.SlimeId, inst.Mutation, false)

		local topIncome = Instance.new("TextLabel")
		topIncome.Position = UDim2.fromOffset(2, 2)
		topIncome.Size = UDim2.new(1, -4, 0, 17)
		topIncome.BackgroundTransparency = 1
		topIncome.Font = Enum.Font.FredokaOne
		topIncome.TextSize = 14
		topIncome.TextColor3 = Color3.fromRGB(115, 255, 130)
		topIncome.Text = `${GameConfig.FormatNumber(inst.IncomePerSec)}/s`
		topIncome.ZIndex = 3
		topIncome.Parent = tile
		addStroke(topIncome, Color3.fromRGB(15, 18, 25), 1.6)

		local midName = Instance.new("TextLabel")
		midName.Position = UDim2.fromOffset(2, 34)
		midName.Size = UDim2.new(1, -4, 0, 18)
		midName.BackgroundTransparency = 1
		midName.Font = Enum.Font.FredokaOne
		midName.TextScaled = true
		midName.TextColor3 = Color3.fromRGB(255, 255, 255)
		midName.Text = inst.ShortWord or def.ShortWord
		midName.ZIndex = 3
		midName.Parent = tile
		addStroke(midName, Color3.fromRGB(15, 18, 25), 1.6)

		local botMut = Instance.new("TextLabel")
		botMut.Position = UDim2.fromOffset(2, 52)
		botMut.Size = UDim2.new(1, -4, 0, 17)
		botMut.BackgroundTransparency = 1
		botMut.Font = Enum.Font.FredokaOne
		botMut.TextSize = 12
		botMut.TextColor3 = SlimeFactory.GetMutationColor(inst.Mutation)
		botMut.Text = `{i} {if inst.Mutation ~= "NORMAL" then inst.Mutation else def.Rarity}`
		botMut.ZIndex = 3
		botMut.Parent = tile
		addStroke(botMut, Color3.fromRGB(15, 18, 25), 1.5)

		tile.Activated:Connect(function()
			selectHotbarSlime(inst)
			rebuildHotbar()
		end)
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	local keyMap: { [Enum.KeyCode]: number } = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4,
		[Enum.KeyCode.Five] = 5,
	}
	local idx = keyMap[input.KeyCode]
	if idx then
		local unplaced = currentState.UnplacedSlimes or {}
		if unplaced[idx] then
			selectHotbarSlime(unplaced[idx])
			rebuildHotbar()
		end
	end
end)

local function rebuildSlimeIndexModal()
	for _, child in indexScroll:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local discovered = currentState.DiscoveredSlimes or {}
	local totalUnlocked = 0
	for _ in discovered do
		totalUnlocked += 1
	end
	indexFooterLabel.Text = `📘 Unlocked: {totalUnlocked}/{#GameConfig.Slimes}`

	for _, zone in GameConfig.Zones do
		local pool = GameConfig.SlimesByZone[zone.Index] or {}
		local zoneUnlocked = 0
		for _, s in pool do
			if discovered[s.Id] then
				zoneUnlocked += 1
			end
		end
		local pct = if #pool > 0 then math.floor((zoneUnlocked / #pool) * 100 + 0.5) else 0
		local isComplete = (#pool > 0 and zoneUnlocked >= #pool)

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -10, 0, 134)
		row.BackgroundColor3 = Color3.fromRGB(26, 30, 38)
		row.Parent = indexScroll
		addCorner(row, 12)
		addStroke(row, Color3.fromRGB(18, 20, 26), 2.2, Enum.ApplyStrokeMode.Border)

		-- Left Zone Card
		local zCard = Instance.new("Frame")
		zCard.Position = UDim2.fromOffset(10, 10)
		zCard.Size = UDim2.fromOffset(112, 114)
		zCard.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		zCard.Parent = row
		addCorner(zCard, 10)
		UiKit.AddGlossGradient(zCard, SlimeFactory.ToColor3(zone.ThemeColor):Lerp(Color3.fromRGB(30, 35, 45), 0.35))
		addStroke(zCard, Color3.fromRGB(15, 18, 25), 2.2, Enum.ApplyStrokeMode.Border)

		local zTitle = Instance.new("TextLabel")
		zTitle.Position = UDim2.fromOffset(4, 6)
		zTitle.Size = UDim2.new(1, -8, 0, 24)
		zTitle.BackgroundTransparency = 1
		zTitle.Font = Enum.Font.FredokaOne
		zTitle.TextScaled = true
		zTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
		zTitle.Text = zone.Name
		zTitle.Parent = zCard
		addStroke(zTitle, Color3.fromRGB(15, 18, 25), 1.8)

		local zEmoji = Instance.new("TextLabel")
		zEmoji.Position = UDim2.fromOffset(0, 34)
		zEmoji.Size = UDim2.new(1, 0, 0, 42)
		zEmoji.BackgroundTransparency = 1
		zEmoji.Font = Enum.Font.FredokaOne
		zEmoji.TextSize = 34
		zEmoji.Text = zone.Emoji
		zEmoji.Parent = zCard

		local zPct = Instance.new("TextLabel")
		zPct.Position = UDim2.fromOffset(0, 80)
		zPct.Size = UDim2.new(1, 0, 0, 26)
		zPct.BackgroundTransparency = 1
		zPct.Font = Enum.Font.FredokaOne
		zPct.TextSize = 20
		zPct.TextColor3 = Color3.fromRGB(255, 255, 255)
		zPct.Text = `({pct}%)`
		zPct.Parent = zCard
		addStroke(zPct, Color3.fromRGB(15, 18, 25), 1.8)

		-- Center Slime Cards with live 3D ViewportFrame (or 3D Dark Silhouette when locked!)
		for idx, sDef in pool do
			local isDiscovered = (discovered[sDef.Id] == true)
			local sCard = Instance.new("Frame")
			sCard.Position = UDim2.fromOffset(132 + (idx - 1) * 112, 10)
			sCard.Size = UDim2.fromOffset(104, 82)
			sCard.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			sCard.Parent = row
			addCorner(sCard, 9)
			UiKit.AddGlossGradient(sCard, SlimeFactory.GetRarityColor(sDef.Rarity))
			addStroke(sCard, Color3.fromRGB(15, 18, 25), 2, Enum.ApplyStrokeMode.Border)

			local vpHolder = Instance.new("Frame")
			vpHolder.AnchorPoint = Vector2.new(0.5, 0.5)
			vpHolder.Position = UDim2.fromScale(0.5, 0.45)
			vpHolder.Size = UDim2.fromOffset(56, 52)
			vpHolder.BackgroundTransparency = 1
			vpHolder.Parent = sCard
			UiKit.CreateSlimeViewport(vpHolder, sDef.Id, "NORMAL", not isDiscovered)

			local sName = Instance.new("TextLabel")
			sName.Position = UDim2.fromOffset(4, 2)
			sName.Size = UDim2.new(1, -8, 0, 20)
			sName.BackgroundTransparency = 1
			sName.Font = Enum.Font.FredokaOne
			sName.TextScaled = true
			sName.TextColor3 = Color3.fromRGB(255, 255, 255)
			sName.Text = if isDiscovered then sDef.ShortWord else "???"
			sName.ZIndex = 3
			sName.Parent = sCard
			addStroke(sName, Color3.fromRGB(15, 18, 25), 1.6)

			local sRarity = Instance.new("TextLabel")
			sRarity.Position = UDim2.fromOffset(4, 58)
			sRarity.Size = UDim2.new(1, -8, 0, 20)
			sRarity.BackgroundTransparency = 1
			sRarity.Font = Enum.Font.FredokaOne
			sRarity.TextSize = 14
			sRarity.TextColor3 = Color3.fromRGB(255, 255, 255)
			sRarity.Text = sDef.Rarity
			sRarity.ZIndex = 3
			sRarity.Parent = sCard
			addStroke(sRarity, Color3.fromRGB(15, 18, 25), 1.5)
		end

		local progBg = Instance.new("Frame")
		progBg.Position = UDim2.fromOffset(132, 98)
		progBg.Size = UDim2.fromOffset(328, 22)
		progBg.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
		progBg.Parent = row
		addCorner(progBg, 8)
		addStroke(progBg, Color3.fromRGB(12, 14, 18), 1.6, Enum.ApplyStrokeMode.Border)

		local progFill = Instance.new("Frame")
		progFill.Size = UDim2.fromScale(if #pool > 0 then zoneUnlocked / #pool else 0, 1)
		progFill.BackgroundColor3 = Color3.fromRGB(95, 245, 75)
		progFill.Parent = progBg
		addCorner(progFill, 8)

		local progTxt = Instance.new("TextLabel")
		progTxt.Size = UDim2.fromScale(1, 1)
		progTxt.BackgroundTransparency = 1
		progTxt.Font = Enum.Font.FredokaOne
		progTxt.TextSize = 15
		progTxt.TextColor3 = Color3.fromRGB(255, 255, 255)
		progTxt.Text = `{zoneUnlocked}/{#pool}`
		progTxt.Parent = progBg
		addStroke(progTxt, Color3.fromRGB(15, 18, 25), 1.5)

		-- Right Zone Trail Bonus Panel
		local trailLbl = Instance.new("TextLabel")
		trailLbl.Position = UDim2.fromOffset(472, 12)
		trailLbl.Size = UDim2.fromOffset(132, 52)
		trailLbl.BackgroundTransparency = 1
		trailLbl.Font = Enum.Font.FredokaOne
		trailLbl.TextSize = 16
		trailLbl.TextColor3 = Color3.fromRGB(120, 255, 135)
		trailLbl.Text = `{zone.TrailName}\n{zone.TrailBonusText}`
		trailLbl.Parent = row
		addStroke(trailLbl, Color3.fromRGB(15, 18, 25), 1.6)

		local isEquippedTrail = (currentState.EquippedTrailZone == zone.Index)
		UiKit.CreateBevelButton({
			Name = "TrailEquipBtn",
			Parent = row,
			Position = UDim2.fromOffset(478, 76),
			Size = UDim2.fromOffset(122, 40),
			Color = if isEquippedTrail
				then Color3.fromRGB(65, 185, 245)
				elseif isComplete then Color3.fromRGB(85, 235, 95)
				else Color3.fromRGB(70, 75, 88),
			CornerRadius = 9,
			Text = if isEquippedTrail then "EQUIPPED" elseif isComplete then "EQUIP" else "LOCKED",
			TextSize = 18,
			OnClick = function()
				requestEquipTrail:FireServer({ ZoneIndex = zone.Index })
			end,
		})
	end
end

local function rebuildBackpackModal()
	for _, child in slimesScroll:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local unplaced = currentState.UnplacedSlimes or {}
	for _, inst in unplaced do
		local def = GameConfig.SlimesById[inst.SlimeId] or GameConfig.Slimes[1]
		local mutTag = if inst.Mutation ~= "NORMAL" then `[{inst.Mutation}] ` else ""
		UiKit.CreateBevelButton({
			Name = `SlimeRow_{inst.Uid}`,
			Parent = slimesScroll,
			Size = UDim2.new(1, -10, 0, 44),
			Color = SlimeFactory.GetRarityColor(def.Rarity):Lerp(Color3.fromRGB(38, 44, 58), 0.55),
			CornerRadius = 9,
			Text = `🟢 {mutTag}{inst.Name} — +${GameConfig.FormatNumber(inst.IncomePerSec)}/s  (Click to Place)`,
			TextSize = 16,
			OnClick = function()
				local freeSlot = findFirstFreePlotSlot() or 1
				requestPlaceOnSlot:FireServer({
					SlimeUid = inst.Uid,
					SlotIndex = freeSlot,
				})
			end,
		})
	end
end

local function refreshAllUi()
	powerRowLabel.Text = `💪 {GameConfig.FormatNumber(currentState.EffectiveThrowPower or 5)}`
	cashRowLabel.Text = `💵 ${GameConfig.FormatNumber(currentState.Cash or 0)}`
	gemsRowLabel.Text = `💎 {GameConfig.FormatNumber(currentState.Gems or 0)}`

	refreshShopLabels()
	upgradesWin.Refresh(currentState)
	rewardsBadge.Visible = rewardsWin.Refresh(currentState)
	robuxWin.Refresh(currentState)

	rebuildHotbar()
	rebuildSlimeIndexModal()
	rebuildBackpackModal()
end

stateSync.OnClientEvent:Connect(function(newState: any)
	if type(newState) == "table" then
		currentState = newState
		if selectedHotbarUid then
			local stillThere = false
			for _, inst in currentState.UnplacedSlimes or {} do
				if inst.Uid == selectedHotbarUid then
					stillThere = true
					break
				end
			end
			if not stillThere then
				selectedHotbarUid = nil
				CharacterAnimator.StopCarrySlime()
				quickPlaceBtn.Visible = false
			end
		end
		refreshAllUi()
	end
end)

-- ============================================================================
-- 9. 3D BOUNCING YELLOW OBJECTIVE ARROW (▼) & GOLDEN CHEVRON TRAIL (>>>)
-- ============================================================================
local guideFolder = Instance.new("Folder")
guideFolder.Name = "ObjectiveGuideVisuals"
guideFolder.Parent = workspace

local arrowPart = Instance.new("WedgePart")
arrowPart.Name = "BouncingObjectiveArrow"
arrowPart.Size = Vector3.new(1.2, 3.2, 3.2)
arrowPart.Color = Color3.fromRGB(255, 215, 35)
arrowPart.Material = Enum.Material.Neon
arrowPart.Anchored = true
arrowPart.CanCollide = false
arrowPart.CastShadow = false
arrowPart.Parent = guideFolder

local NUM_CHEVRONS = 10
local chevrons: { Part } = {}
for i = 1, NUM_CHEVRONS do
	local p = Instance.new("Part")
	p.Name = `TrailChevron_{i}`
	p.Size = Vector3.new(2.2, 0.25, 2.2)
	p.Color = Color3.fromRGB(255, 215, 35)
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Parent = guideFolder
	table.insert(chevrons, p)
end

local function findLocalPlayerPlot(): Model?
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	local bases = hub and hub:FindFirstChild("PlayerBases")
	if not bases then
		return nil
	end
	local uidStr = tostring(localPlayer.UserId)
	local plotIdAttr = localPlayer:GetAttribute("PlotId")
	for _, plot in bases:GetChildren() do
		if plot:IsA("Model") then
			if plot:GetAttribute("Owner") == uidStr or (plotIdAttr and plot:GetAttribute("PlotId") == plotIdAttr) then
				return plot
			end
		end
	end
	return nil
end

local function resolveObjectiveWorldTarget(targetType: string): Vector3?
	if targetType == "ThrowLine" then
		return Vector3.new(0, GameConfig.Hub.FloorY + 4.5, GameConfig.Hub.ThrowLineZ)
	end
	local plot = findLocalPlayerPlot()
	if not plot then
		return Vector3.new(0, GameConfig.Hub.FloorY + 4.5, GameConfig.Hub.ThrowLineZ)
	end
	if targetType == "PlotSlot" then
		local freeIdx = findFirstFreePlotSlot() or 1
		local slots = plot:FindFirstChild("SlimeSlots")
		local slotPart = slots and slots:FindFirstChild(`Slot{freeIdx}`) :: BasePart?
		if slotPart then
			return slotPart.Position + Vector3.new(0, 4.5, 0)
		end
	elseif targetType == "PullUpBar" then
		local pullUp = plot:FindFirstChild("PullUpBar")
		local bar = pullUp and pullUp:FindFirstChild("Bar") :: BasePart?
		if bar then
			return bar.Position + Vector3.new(0, 4.5, 0)
		end
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	local inCutscene = (localPlayer:GetAttribute("InRevealCutscene") :: boolean?) == true
	screenGui.Enabled = not inCutscene
	if inCutscene then
		return
	end

	local obj = ProgressionLogic.GetCurrentObjective(currentState, selectedHotbarUid ~= nil)
	objectiveLabel.Text = obj.Text

	local now = os.clock()
	local bounceOffset = math.sin(now * 5.5) * 1.1

	if obj.TargetType == "Hotbar" then
		hotbarArrow.Visible = true
		hotbarArrow.Position = UDim2.new(0.5, 0, 1, -90 - math.floor(bounceOffset * 6))
	else
		hotbarArrow.Visible = false
	end

	local worldTarget = resolveObjectiveWorldTarget(obj.TargetType)
	local char = localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

	if worldTarget and root then
		arrowPart.Transparency = 0
		arrowPart.CFrame = CFrame.new(worldTarget + Vector3.new(0, bounceOffset, 0))
			* CFrame.Angles(math.rad(180), now * 2.2, 0)

		local startPos = Vector3.new(root.Position.X, GameConfig.Hub.FloorY + 0.3, root.Position.Z)
		local endPos = Vector3.new(worldTarget.X, GameConfig.Hub.FloorY + 0.3, worldTarget.Z)
		local dist = (endPos - startPos).Magnitude

		for i = 1, NUM_CHEVRONS do
			local chev = chevrons[i]
			if dist > 6 then
				local frac = ((i - 1) / NUM_CHEVRONS + (now * 0.45) % (1 / NUM_CHEVRONS))
				local p = startPos:Lerp(endPos, math.clamp(frac, 0.08, 0.95))
				chev.Transparency = 0.15
				chev.CFrame = CFrame.lookAt(p, endPos) * CFrame.Angles(0, math.rad(45), 0)
			else
				chev.Transparency = 1
			end
		end
	else
		arrowPart.Transparency = 1
		for _, chev in chevrons do
			chev.Transparency = 1
		end
	end
end)

refreshAllUi()
