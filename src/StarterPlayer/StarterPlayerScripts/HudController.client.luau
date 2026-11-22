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
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterAnimator = require(Shared:WaitForChild("CharacterAnimator"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))
local UiAssets = require(Shared:WaitForChild("UiAssets"))
local UiKit = require(Shared:WaitForChild("UiKit"))
local UiLayout = require(Shared:WaitForChild("UiLayout"))

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

-- Structured bindings: the callback receives the whole listing entry plus the synced state
type ShopEntryBinding = { ItemId: string, Apply: (entry: ProgressionLogic.ShopListingEntry, state: any) -> () }
local shopEntryBindings: { ShopEntryBinding } = {}

local function bindShopEntry(itemId: string, apply: (entry: ProgressionLogic.ShopListingEntry, state: any) -> ())
	table.insert(shopEntryBindings, { ItemId = itemId, Apply = apply })
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
-- HUD FRAME (docs/docs/UI-MOCKUP-SPEC.md section 2, mockups 2a / 5a). Offsets are design pixels
-- under the root UIScale (phone 0.68, set by UiKit.AttachResponsiveScale).
-- ============================================================================
local isPhone = UiKit.IsPhone()
local hasKeyboard = UserInputService.KeyboardEnabled
local Colors = UiKit.Colors

local function makeList(parent: Instance, direction: Enum.FillDirection, padding: number, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction
	l.Padding = UDim.new(0, padding)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	if hAlign then
		l.HorizontalAlignment = hAlign
	end
	if vAlign then
		l.VerticalAlignment = vAlign
	end
	l.Parent = parent
	return l
end

local function setGradientTone(g: UIGradient, t: UiKit.Tri)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, t.Light),
		ColorSequenceKeypoint.new(0.55, t.Mid),
		ColorSequenceKeypoint.new(1, t.Dark),
	})
end

-- ----------------------------------------------------------------------------
-- Objective + Toast (top centre, y 64 / phone 74)
-- ----------------------------------------------------------------------------
local objectiveGroup = Instance.new("Frame")
objectiveGroup.Name = "Objective"
objectiveGroup.AnchorPoint = Vector2.new(0.5, 0)
objectiveGroup.Position = UDim2.new(0.5, 0, 0, if isPhone then 74 else 64)
objectiveGroup.Size = UDim2.fromOffset(0, 0)
objectiveGroup.AutomaticSize = Enum.AutomaticSize.XY
objectiveGroup.BackgroundTransparency = 1
objectiveGroup.Parent = screenGui
makeList(objectiveGroup, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center)

local objectiveLabel = Instance.new("TextLabel")
objectiveLabel.Name = "ObjectivePrompt"
objectiveLabel.LayoutOrder = 1
objectiveLabel.Size = UDim2.fromOffset(0, 0)
objectiveLabel.AutomaticSize = Enum.AutomaticSize.XY
objectiveLabel.BackgroundTransparency = 1
objectiveLabel.Font = Enum.Font.FredokaOne
objectiveLabel.TextSize = 32
objectiveLabel.TextColor3 = Colors.White
objectiveLabel.Text = "Walk to the Throw Line!"
objectiveLabel.Parent = objectiveGroup
UiKit.AddTextStroke(objectiveLabel)

local toastHolder = Instance.new("Frame")
toastHolder.Name = "ToastHolder"
toastHolder.LayoutOrder = 2
toastHolder.Size = UDim2.fromOffset(0, 36)
toastHolder.AutomaticSize = Enum.AutomaticSize.X
toastHolder.BackgroundTransparency = 1
toastHolder.Parent = objectiveGroup

local toastLabel = Instance.new("TextLabel")
toastLabel.Name = "ToastBanner"
toastLabel.Size = UDim2.new(0, 0, 1, 0)
toastLabel.AutomaticSize = Enum.AutomaticSize.X
toastLabel.BackgroundTransparency = 1
toastLabel.TextTransparency = 1
toastLabel.Font = Enum.Font.FredokaOne
toastLabel.TextSize = 26
toastLabel.TextColor3 = Colors.White
toastLabel.Text = ""
toastLabel.Parent = toastHolder
local toastStroke = UiKit.AddTextStroke(toastLabel)
toastStroke.Transparency = 1
local toastGradient = UiKit.ApplyTri(toastLabel, UiKit.Gradients.Luck)

local TOAST_TONES: { [string]: UiKit.Tri } = {
	cash = UiKit.Gradients.Cash,
	power = UiKit.Gradients.Power,
	gems = UiKit.Gradients.Gems,
	gold = UiKit.Gradients.Luck,
	red = UiKit.Gradients.Red,
}

local toastToken = 0
-- `tone` is a ToastKey, or a Color3 for callers that pass their own colour (RobuxStoreWindow "coming soon").
local function showToast(msg: string, tone: (UiLayout.ToastKey | Color3)?)
	toastToken += 1
	local myToken = toastToken
	local t: UiKit.Tri = if typeof(tone) == "Color3"
		then UiKit.TriFromColor(tone, 0.5, 0.25)
		elseif tone then TOAST_TONES[tone]
		else TOAST_TONES.gold
	setGradientTone(toastGradient, t)
	toastLabel.Text = msg
	toastLabel.Position = UDim2.fromOffset(0, -20)
	toastLabel.TextTransparency = 1
	toastStroke.Transparency = 1
	-- Toast in: Position.Y -20 -> 0, transparency 1 -> 0, 0.2 s Back Out
	local tin = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(toastLabel, tin, { Position = UDim2.fromOffset(0, 0), TextTransparency = 0 }):Play()
	TweenService:Create(toastStroke, tin, { Transparency = 0 }):Play()
	task.delay(2.5, function()
		if toastToken ~= myToken then
			return
		end
		-- Toast out: fade 0.25 s Quad In
		local tout = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(toastLabel, tout, { TextTransparency = 1 }):Play()
		TweenService:Create(toastStroke, tout, { Transparency = 1 }):Play()
	end)
end

toastNotify.OnClientEvent:Connect(function(payload: any)
	if type(payload) == "table" and type(payload.Message) == "string" then
		showToast(payload.Message, UiLayout.ToastKey(payload.Kind))
	end
end)

-- ----------------------------------------------------------------------------
-- Nav buttons: 88x88 gradient face, gloss, bevel, lip, 58 px icon, label overlapping the bottom edge
-- ----------------------------------------------------------------------------
local function createNavButton(
	parent: Instance,
	name: string,
	iconKey: string,
	labelText: string,
	kind: UiKit.ButtonKind,
	order: number,
	onClick: () -> (),
	use3DSlimeIcon: boolean?
): TextButton
	local btn, face = UiKit.CreateGradientButton({
		Name = name,
		Parent = parent,
		Size = UDim2.fromOffset(88, 88),
		Kind = kind,
		CornerRadius = 22,
		LayoutOrder = order,
		OnClick = onClick,
	})

	if use3DSlimeIcon then
		local vpHolder = Instance.new("Frame")
		vpHolder.Name = "SlimeIcon"
		vpHolder.AnchorPoint = Vector2.new(0.5, 0)
		vpHolder.Position = UDim2.new(0.5, 0, 0, 6)
		vpHolder.Size = UDim2.fromOffset(58, 58)
		vpHolder.BackgroundTransparency = 1
		vpHolder.ZIndex = 3
		vpHolder.Parent = face
		UiKit.CreateSlimeViewport(vpHolder, "meadow_sprout", "EMERALD", false)
	else
		local icon = UiKit.CreateIcon(face, iconKey, 58)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 6)
		icon.ZIndex = 3
	end

	local bottomLbl = Instance.new("TextLabel")
	bottomLbl.Name = "NavLabel"
	bottomLbl.AnchorPoint = Vector2.new(0.5, 1)
	bottomLbl.Position = UDim2.new(0.5, 0, 1, 8)
	bottomLbl.Size = UDim2.new(1, 40, 0, 26)
	bottomLbl.BackgroundTransparency = 1
	bottomLbl.Font = Enum.Font.FredokaOne
	bottomLbl.TextSize = 22
	bottomLbl.TextColor3 = Colors.White
	bottomLbl.Text = labelText
	bottomLbl.ZIndex = 6
	bottomLbl.Parent = btn
	UiKit.AddTextStroke(bottomLbl)

	return btn
end

local leftNav = Instance.new("Frame")
leftNav.Name = "LeftNav"
leftNav.AnchorPoint = Vector2.new(0, 0.5)
leftNav.Position = UDim2.new(0, 16, 0.5, 0)
leftNav.Size = UDim2.fromOffset(88, 3 * 88 + 2 * 18)
leftNav.BackgroundTransparency = 1
leftNav.Parent = screenGui
makeList(leftNav, Enum.FillDirection.Vertical, 18)

local rightNav = Instance.new("Frame")
rightNav.Name = "RightNav"
rightNav.AnchorPoint = Vector2.new(1, 0.5)
-- Phone: moved up to clear the Roblox jump button
rightNav.Position = UDim2.new(1, -16, if isPhone then 0.40 else 0.5, 0)
rightNav.Size = UDim2.fromOffset(88, 2 * 88 + 18)
rightNav.BackgroundTransparency = 1
rightNav.Parent = screenGui
makeList(rightNav, Enum.FillDirection.Vertical, 18)

-- ----------------------------------------------------------------------------
-- Stats: Power, Cash, Gems. PC bottom-left (vertical). Phone top-right (horizontal), bottom-left is the thumbstick.
-- ----------------------------------------------------------------------------
local statsGroup = Instance.new("Frame")
statsGroup.Name = "Stats"
statsGroup.Size = UDim2.fromOffset(0, 0)
statsGroup.AutomaticSize = Enum.AutomaticSize.XY
statsGroup.BackgroundTransparency = 1
statsGroup.Parent = screenGui
if isPhone then
	statsGroup.AnchorPoint = Vector2.new(1, 0)
	statsGroup.Position = UDim2.new(1, -16, 0, 10)
	makeList(statsGroup, Enum.FillDirection.Horizontal, 22, nil, Enum.VerticalAlignment.Center)
else
	statsGroup.AnchorPoint = Vector2.new(0, 1)
	statsGroup.Position = UDim2.new(0, 16, 1, -16)
	makeList(statsGroup, Enum.FillDirection.Vertical, 2)
end

type Counter = {
	Label: TextLabel,
	Prefix: string,
	Value: NumberValue,
	Tween: Tween?,
	Ready: boolean,
	Pulse: (() -> ())?,
}

-- Icons sit on a dark plate: the HUD floats over grass, sky and lava, so a bare icon can match its background.
local function createStatRow(name: string, iconKey: string, tone: UiKit.Tri, prefix: string, order: number, pulses: boolean): Counter
	local row = Instance.new("Frame")
	row.Name = name
	row.LayoutOrder = order
	row.Size = UDim2.fromOffset(0, 62)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.BackgroundTransparency = 1
	row.Parent = statsGroup
	makeList(row, Enum.FillDirection.Horizontal, 10, nil, Enum.VerticalAlignment.Center)

	local plate = UiKit.CreateIconPlate(row, iconKey, 62, 0.74)
	plate.LayoutOrder = 1

	local number = Instance.new("TextLabel")
	number.Name = "Number"
	number.LayoutOrder = 2
	number.Size = UDim2.fromOffset(0, 62)
	number.AutomaticSize = Enum.AutomaticSize.X
	number.BackgroundTransparency = 1
	number.Font = Enum.Font.FredokaOne
	number.TextSize = 42
	number.TextXAlignment = Enum.TextXAlignment.Left
	number.TextColor3 = Colors.White
	number.Text = prefix .. "0"
	number.Parent = row
	UiKit.AddTextStroke(number)
	UiKit.ApplyTri(number, tone)

	local counter: Counter = {
		Label = number,
		Prefix = prefix,
		Value = Instance.new("NumberValue"),
		Tween = nil,
		Ready = false,
		Pulse = nil,
	}
	counter.Value.Changed:Connect(function(v: number)
		number.Text = prefix .. GameConfig.FormatNumber(v)
	end)

	if pulses then
		-- Cash gained pulse: stat UIScale 1 -> 1.15 -> 1, 0.25 s Back Out
		local pulseScale = Instance.new("UIScale")
		pulseScale.Parent = row
		counter.Pulse = function()
			pulseScale.Scale = 1.15
			TweenService:Create(pulseScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	end
	return counter
end

local powerCounter = createStatRow("Power", "power", UiKit.Gradients.Power, "", 1, false)
local cashCounter = createStatRow("Cash", "cash", UiKit.Gradients.Cash, "$", 2, true)
local gemsCounter = createStatRow("Gems", "gem", UiKit.Gradients.Gems, "", 3, false)

-- Cash counter: displayed number tweens old -> new over 0.4 s Quad Out (client only, never on the server)
local function setCounter(c: Counter, target: number)
	local old = c.Value.Value
	if not c.Ready then
		c.Ready = true
		c.Value.Value = target
		c.Label.Text = c.Prefix .. GameConfig.FormatNumber(target)
		return
	end
	if target == old and c.Tween == nil then
		return
	end
	if c.Tween then
		c.Tween:Cancel()
		c.Tween = nil
	end
	if c.Pulse and target > old then
		c.Pulse()
	end
	local duration = UiLayout.CounterDuration(old, target)
	if duration == 0 then
		c.Value.Value = target
	else
		local tw = TweenService:Create(c.Value, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Value = target,
		})
		c.Tween = tw
		tw.Completed:Connect(function()
			if c.Tween == tw then
				c.Tween = nil
			end
		end)
		tw:Play()
	end
end

-- ----------------------------------------------------------------------------
-- Hotbar: tutorial arrow, PlaceButton (only while a slime is held), 5 always-visible slots
-- ----------------------------------------------------------------------------
local hotbarGroup = Instance.new("Frame")
hotbarGroup.Name = "Hotbar"
hotbarGroup.AnchorPoint = Vector2.new(0.5, 1)
hotbarGroup.Position = UDim2.new(0.5, 0, 1, -16)
hotbarGroup.Size = UDim2.fromOffset(0, 0)
hotbarGroup.AutomaticSize = Enum.AutomaticSize.XY
hotbarGroup.BackgroundTransparency = 1
hotbarGroup.Parent = screenGui
makeList(hotbarGroup, Enum.FillDirection.Vertical, 14, Enum.HorizontalAlignment.Center)

local hotbarArrowHolder = Instance.new("Frame")
hotbarArrowHolder.Name = "HotbarGuideArrow"
hotbarArrowHolder.LayoutOrder = 0
hotbarArrowHolder.Size = UDim2.fromOffset(56, 44)
hotbarArrowHolder.BackgroundTransparency = 1
hotbarArrowHolder.Visible = false
hotbarArrowHolder.Parent = hotbarGroup

local hotbarArrow = Instance.new("TextLabel")
hotbarArrow.AnchorPoint = Vector2.new(0.5, 0)
hotbarArrow.Position = UDim2.new(0.5, 0, 0, 12)
hotbarArrow.Size = UDim2.fromOffset(56, 44)
hotbarArrow.BackgroundTransparency = 1
hotbarArrow.Font = Enum.Font.FredokaOne
hotbarArrow.TextSize = 40
hotbarArrow.TextColor3 = Colors.Gold
hotbarArrow.Text = "▼"
hotbarArrow.Parent = hotbarArrowHolder
UiKit.AddTextStroke(hotbarArrow, 3.5)
-- Tutorial arrow: Position.Y 0 -> -12, 0.6 s each way, Sine InOut, reverses forever
TweenService:Create(hotbarArrow, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Position = UDim2.new(0.5, 0, 0, 0),
}):Play()

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

local quickPlaceBtn = UiKit.CreateGradientButton({
	Name = "QuickPlaceBtn",
	Parent = hotbarGroup,
	LayoutOrder = 1,
	Size = UDim2.fromOffset(0, 56),
	AutomaticSize = Enum.AutomaticSize.X,
	Kind = "green",
	CornerRadius = 16,
	Text = "Place Slime on Free Slot",
	TextSize = 24,
	PaddingX = 26,
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

local slotsRow = Instance.new("Frame")
slotsRow.Name = "Slots"
slotsRow.LayoutOrder = 2
slotsRow.Size = UDim2.fromOffset(0, 82)
slotsRow.AutomaticSize = Enum.AutomaticSize.X
slotsRow.BackgroundTransparency = 1
slotsRow.Parent = hotbarGroup
makeList(slotsRow, Enum.FillDirection.Horizontal, 10)

type HotbarSlot = {
	Button: TextButton,
	Stroke: UIStroke,
	Tone: UIGradient,
	Glow: ImageLabel,
	Holder: Frame,
	Income: TextLabel,
	Word: TextLabel,
	Uid: string?,
	Selected: boolean,
	Inst: any,
}
local hotbarSlots: { HotbarSlot } = {}
local EMPTY_SLOT_TONE = UiKit.TriFromColor(Colors.Panel, 0.25, 0.25)

local function createHotbarSlot(i: number): HotbarSlot
	local root = Instance.new("Frame")
	root.Name = `HotbarSlot_{i}`
	root.LayoutOrder = i
	root.Size = UDim2.fromOffset(82, 82)
	root.BackgroundTransparency = 1
	root.Parent = slotsRow

	-- Selected glow (ImageColor3 = accent), sits behind the slot
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromOffset(150, 150)
	glow.BackgroundTransparency = 1
	glow.Image = UiAssets.Textures.glow
	glow.ImageColor3 = Colors.Gold
	glow.ImageTransparency = 1
	glow.Active = false
	glow.ZIndex = 1
	glow.Parent = root

	local btn = Instance.new("TextButton")
	btn.Name = "Slot"
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundColor3 = Colors.White
	btn.BackgroundTransparency = 0.4
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.ZIndex = 2
	btn.Parent = root
	UiKit.AddCorner(btn, 16)
	local stroke = UiKit.AddFrameOutline(btn)
	local tone = UiKit.ApplyTri(btn, EMPTY_SLOT_TONE)
	UiKit.AddBevel(btn, 16)
	UiKit.AttachButtonJuice(btn, nil)

	local holder = Instance.new("Frame")
	holder.Name = "SlimeHolder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(60, 52)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 3
	holder.Parent = btn

	local income = Instance.new("TextLabel")
	income.Name = "Income"
	income.Position = UDim2.fromOffset(2, 4)
	income.Size = UDim2.new(1, -4, 0, 18)
	income.BackgroundTransparency = 1
	income.Font = Enum.Font.FredokaOne
	income.TextSize = 15
	income.TextColor3 = Colors.White
	income.Text = ""
	income.ZIndex = 4
	income.Parent = btn
	UiKit.AddTextStroke(income)

	local word = Instance.new("TextLabel")
	word.Name = "Word"
	word.AnchorPoint = Vector2.new(0, 1)
	word.Position = UDim2.new(0, 2, 1, -4)
	word.Size = UDim2.new(1, -4, 0, 16)
	word.BackgroundTransparency = 1
	word.Font = Enum.Font.FredokaOne
	word.TextSize = 13
	word.TextColor3 = Colors.White
	word.Text = ""
	word.ZIndex = 4
	word.Parent = btn
	UiKit.AddTextStroke(word)

	-- Key hint (PC only): white 24x24 keycap, top-left. Hidden on touch.
	if hasKeyboard then
		local key = Instance.new("Frame")
		key.Name = "KeyHint"
		key.Position = UDim2.fromOffset(-10, -10)
		key.Size = UDim2.fromOffset(24, 24)
		key.BackgroundColor3 = Colors.White
		key.ZIndex = 6
		key.Parent = btn
		UiKit.AddCorner(key, 6)
		UiKit.AddStroke(key, Colors.Ink, 2.5, Enum.ApplyStrokeMode.Border)
		local keyText = Instance.new("TextLabel")
		keyText.Size = UDim2.fromScale(1, 1)
		keyText.BackgroundTransparency = 1
		keyText.Font = Enum.Font.FredokaOne
		keyText.TextSize = 16
		keyText.TextColor3 = Colors.Ink
		keyText.Text = tostring(i)
		keyText.ZIndex = 7
		keyText.Parent = key
	end

	return {
		Button = btn,
		Stroke = stroke,
		Tone = tone,
		Glow = glow,
		Holder = holder,
		Income = income,
		Word = word,
		Uid = nil,
		Selected = false,
		Inst = nil,
	}
end

for i = 1, UiLayout.HotbarSlots do
	table.insert(hotbarSlots, createHotbarSlot(i))
end

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
	for _, b in shopEntryBindings do
		local entry = byId[b.ItemId]
		if entry then
			b.Apply(entry, currentState)
		end
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
	BindShopEntry = bindShopEntry,
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

-- Left Column (3 buttons, top to bottom): Index, Shop, Upgrades
createNavButton(leftNav, "IndexNavBtn", "index", "Index", "indexnav", 1, function()
	toggleExclusiveModal(indexModal)
end)

createNavButton(leftNav, "ShopNavBtn", "shop", "Shop", "shopnav", 2, function()
	toggleExclusiveModal(robuxWin.Frame)
end)

createNavButton(leftNav, "UpgradesNavBtn", "upgrades", "Upgrades", "upgradesnav", 3, function()
	toggleExclusiveModal(upgradesWin.Frame)
end)

-- Right Column (2 buttons, top to bottom): Rewards (with red badge) and Slimes (live 3D slime)
local rewardsNavBtn = createNavButton(rightNav, "RewardsNavBtn", "rewards", "Rewards", "rewardsnav", 1, function()
	toggleExclusiveModal(rewardsWin.Frame)
end)

-- Badge: 30x30 red gradient, outline 3, "!" when the daily reward or any quest can be claimed
local rewardsBadge = Instance.new("Frame")
rewardsBadge.Name = "ClaimBadge"
rewardsBadge.AnchorPoint = Vector2.new(0.5, 0.5)
rewardsBadge.Position = UDim2.new(1, -6, 0, 6)
rewardsBadge.Size = UDim2.fromOffset(30, 30)
rewardsBadge.BackgroundColor3 = Colors.White
rewardsBadge.ZIndex = 8
rewardsBadge.Visible = false
rewardsBadge.Parent = rewardsNavBtn
addCorner(rewardsBadge, 15)
addStroke(rewardsBadge, Colors.Ink, 3, Enum.ApplyStrokeMode.Border)
UiKit.ApplyTri(rewardsBadge, UiKit.Gradients.Red)
local badgeText = Instance.new("TextLabel")
badgeText.Size = UDim2.fromScale(1, 1)
badgeText.BackgroundTransparency = 1
badgeText.Font = Enum.Font.FredokaOne
badgeText.TextSize = 20
badgeText.TextColor3 = Colors.White
badgeText.Text = "!"
badgeText.ZIndex = 9
badgeText.Parent = rewardsBadge

createNavButton(rightNav, "SlimesNavBtn", "slimes", "Slimes", "slimesnav", 2, function()
	toggleExclusiveModal(slimesModal)
end, true)


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

-- Fill one of the 5 persistent slots. The 3D viewport is only rebuilt when the slime in the slot changes.
local function renderHotbarSlot(slot: HotbarSlot, inst: any, isSelected: boolean)
	slot.Inst = inst
	if inst == nil then
		slot.Uid = nil
		slot.Holder:ClearAllChildren()
		setGradientTone(slot.Tone, EMPTY_SLOT_TONE)
		slot.Button.BackgroundTransparency = 0.4
		slot.Income.Text = ""
		slot.Word.Text = ""
	else
		local def = GameConfig.SlimesById[inst.SlimeId] or GameConfig.Slimes[1]
		if slot.Uid ~= inst.Uid then
			slot.Holder:ClearAllChildren()
			UiKit.CreateSlimeViewport(slot.Holder, inst.SlimeId, inst.Mutation, false)
			slot.Uid = inst.Uid
		end
		-- Rarity-tinted fill: rarity lightened 40% / rarity / darkened 30%
		setGradientTone(slot.Tone, UiKit.TriFromColor(SlimeFactory.GetRarityColor(def.Rarity), 0.4, 0.3))
		slot.Button.BackgroundTransparency = 0
		slot.Income.Text = `${GameConfig.FormatNumber(inst.IncomePerSec)}/s`
		if inst.Mutation ~= "NORMAL" then
			slot.Word.Text = inst.Mutation
			slot.Word.TextColor3 = SlimeFactory.GetMutationColor(inst.Mutation)
		else
			slot.Word.Text = def.Rarity
			slot.Word.TextColor3 = Colors.White
		end
	end

	isSelected = isSelected and inst ~= nil
	if slot.Selected ~= isSelected then
		slot.Selected = isSelected
		slot.Stroke.Color = if isSelected then Colors.Luck else Colors.Ink
		-- Hotbar select: lift 0 -> -6 px and glow 1 -> 0, 0.15 s Back Out
		local info = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(slot.Button, info, { Position = UDim2.fromOffset(0, if isSelected then -6 else 0) }):Play()
		TweenService:Create(slot.Glow, info, { ImageTransparency = if isSelected then 0 else 1 }):Play()
	end
end

local function rebuildHotbar()
	local unplaced = currentState.UnplacedSlimes or {}
	for i, slot in hotbarSlots do
		local inst = unplaced[i]
		renderHotbarSlot(slot, inst, inst ~= nil and selectedHotbarUid == inst.Uid)
	end
end

for i, slot in hotbarSlots do
	slot.Button.Activated:Connect(function()
		local inst = (currentState.UnplacedSlimes or {})[i]
		if inst then
			selectHotbarSlime(inst)
			rebuildHotbar()
		end
	end)
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
	setCounter(powerCounter, currentState.EffectiveThrowPower or 5)
	setCounter(cashCounter, currentState.Cash or 0)
	setCounter(gemsCounter, currentState.Gems or 0)

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

	-- Spec 4: Objective and Hotbar hide while the bait is in flight (ThrowController sets the attribute)
	local inThrow = (localPlayer:GetAttribute("InThrow") :: boolean?) == true
	objectiveGroup.Visible = not inThrow
	hotbarGroup.Visible = not inThrow

	local obj = ProgressionLogic.GetCurrentObjective(currentState, selectedHotbarUid ~= nil)
	objectiveLabel.Text = obj.Text

	local now = os.clock()
	local bounceOffset = math.sin(now * 5.5) * 1.1

	hotbarArrowHolder.Visible = obj.TargetType == "Hotbar"

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
