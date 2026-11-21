--!strict
--[[
	HudController.client.luau
	Constructs the interactive Throw-a-Slime Tycoon ScreenGui HUD:
	- Top Stats Bar: Cash ($), Throw Power, Income ($/s), Best Throw (m)
	- Bottom Throw Dock: Power Charge Meter, Pitch angle controls (Q/E),
	  and interactive "HOLD TO THROW!" button
	- Quick Action Dock: To Throw Line, To My Plot, Pull-Up Rep (+Power),
	  Collect Cash, Upgrades Drawer, and Slime Inventory Modal
	- Toast notifications
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))

local stateSync = Remotes.GetEvent("PlayerStateSync")
local toastNotify = Remotes.GetEvent("ToastNotify")
local throwBroadcast = Remotes.GetEvent("ThrowBroadcast")
local requestUpgrade = Remotes.GetEvent("RequestUpgrade")
local requestTrainRep = Remotes.GetEvent("RequestTrainRep")
local requestEquipSlime = Remotes.GetEvent("RequestEquipSlime")
local requestPlaceBest = Remotes.GetEvent("RequestPlaceBestSlimes")
local requestCollect = Remotes.GetEvent("RequestCollect")
local requestTeleport = Remotes.GetEvent("RequestTeleport")

local currentState: any = {
	Cash = 0,
	EffectiveThrowPower = 5,
	PowerUpgradeLevel = 1,
	NextPowerCost = 25,
	PullUpTier = 1,
	MaxSlimes = 8,
	BestDistance = 0,
	EquippedSlimeId = "meadow_sprout",
	OwnedSlimes = { "meadow_sprout" },
	PlacedSlimes = { "meadow_sprout" },
	PendingIncome = 0,
	IncomePerSec = 2,
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ThrowSlimeHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local function addCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function addStroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

-- 1. TOP STATS BAR
local topBar = Instance.new("Frame")
topBar.Name = "TopStatsBar"
topBar.AnchorPoint = Vector2.new(0.5, 0)
topBar.Position = UDim2.new(0.5, 0, 0, 10)
topBar.Size = UDim2.fromOffset(660, 52)
topBar.BackgroundColor3 = Color3.fromRGB(22, 25, 38)
topBar.BackgroundTransparency = 0.12
topBar.Parent = screenGui
addCorner(topBar, 14)
addStroke(topBar, Color3.fromRGB(70, 85, 130), 2)

local topLayout = Instance.new("UIListLayout")
topLayout.FillDirection = Enum.FillDirection.Horizontal
topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
topLayout.Padding = UDim.new(0, 12)
topLayout.Parent = topBar

local function createStatPill(title: string, accent: Color3): TextLabel
	local pill = Instance.new("Frame")
	pill.Size = UDim2.fromOffset(150, 38)
	pill.BackgroundColor3 = Color3.fromRGB(32, 37, 56)
	pill.Parent = topBar
	addCorner(pill, 10)
	addStroke(pill, accent, 1.5)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextSize = 17
	lbl.TextColor3 = accent
	lbl.Text = title
	lbl.Parent = pill
	return lbl
end

local cashLabel = createStatPill("💵 $0", Color3.fromRGB(120, 255, 140))
local powerLabel = createStatPill("⚡ Power: 5", Color3.fromRGB(255, 200, 85))
local incomeLabel = createStatPill("🟢 +$2/s", Color3.fromRGB(110, 235, 215))
local bestLabel = createStatPill("🏆 Best: 0m", Color3.fromRGB(130, 195, 255))

-- 2. TOAST BANNER
local toastLabel = Instance.new("TextLabel")
toastLabel.Name = "ToastBanner"
toastLabel.AnchorPoint = Vector2.new(0.5, 0)
toastLabel.Position = UDim2.new(0.5, 0, 0, 70)
toastLabel.Size = UDim2.fromOffset(520, 36)
toastLabel.BackgroundColor3 = Color3.fromRGB(28, 34, 52)
toastLabel.BackgroundTransparency = 1
toastLabel.TextTransparency = 1
toastLabel.Font = Enum.Font.FredokaOne
toastLabel.TextSize = 18
toastLabel.TextColor3 = Color3.fromRGB(255, 245, 140)
toastLabel.Text = ""
toastLabel.Parent = screenGui
addCorner(toastLabel, 10)

local toastToken = 0
local function showToast(msg: string, color: Color3?)
	toastToken += 1
	local myToken = toastToken
	toastLabel.Text = msg
	toastLabel.TextColor3 = color or Color3.fromRGB(255, 245, 140)
	toastLabel.BackgroundTransparency = 0.15
	toastLabel.TextTransparency = 0
	task.delay(2.6, function()
		if toastToken == myToken then
			toastLabel.BackgroundTransparency = 1
			toastLabel.TextTransparency = 1
		end
	end)
end

toastNotify.OnClientEvent:Connect(function(payload: any)
	if type(payload) == "table" and type(payload.Message) == "string" then
		local kind = payload.Kind
		local col = if kind == "warn"
			then Color3.fromRGB(255, 120, 120)
			elseif kind == "cash" then Color3.fromRGB(120, 255, 145)
			else Color3.fromRGB(255, 235, 120)
		showToast(payload.Message, col)
	end
end)

throwBroadcast.OnClientEvent:Connect(function(payload: any)
	if type(payload) == "table" and payload.PlayerUserId == localPlayer.UserId then
		local msg = `Threw {string.format("%.1f", payload.Distance or 0)}m ({payload.LandedZoneName})! +$${GameConfig.FormatNumber(payload.CashEarned or 0)} & Caught {payload.CaughtSlimeName}!`
		showToast(msg, Color3.fromRGB(130, 255, 170))
	end
end)

-- 3. LEFT ACTION DOCK
local leftDock = Instance.new("Frame")
leftDock.Name = "LeftActionDock"
leftDock.Position = UDim2.new(0, 14, 0.5, -135)
leftDock.Size = UDim2.fromOffset(185, 270)
leftDock.BackgroundTransparency = 1
leftDock.Parent = screenGui

local leftLayout = Instance.new("UIListLayout")
leftLayout.FillDirection = Enum.FillDirection.Vertical
leftLayout.Padding = UDim.new(0, 8)
leftLayout.Parent = leftDock

local function createActionButton(text: string, bgColor: Color3, onClick: () -> ()): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 38)
	btn.BackgroundColor3 = bgColor
	btn.Font = Enum.Font.FredokaOne
	btn.TextSize = 15
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = text
	btn.AutoButtonColor = true
	btn.Parent = leftDock
	addCorner(btn, 10)
	addStroke(btn, Color3.fromRGB(20, 24, 38), 1.8)
	btn.Activated:Connect(onClick)
	return btn
end

createActionButton("🎯 To Throw Line", Color3.fromRGB(55, 145, 240), function()
	requestTeleport:FireServer({ Target = "ThrowLine" })
end)

createActionButton("🏠 To My Plot", Color3.fromRGB(70, 175, 115), function()
	requestTeleport:FireServer({ Target = "Plot" })
end)

local trainBtn = createActionButton("💪 Pull-Up (+2 Power)", Color3.fromRGB(225, 130, 45), function()
	requestTrainRep:FireServer()
end)

local collectBtn = createActionButton("💰 Collect ($0)", Color3.fromRGB(45, 185, 125), function()
	requestCollect:FireServer()
end)

-- 4. UPGRADES & SLIMES MODAL PANELS
local upgradesPanel = Instance.new("Frame")
upgradesPanel.Name = "UpgradesPanel"
upgradesPanel.AnchorPoint = Vector2.new(0.5, 0.5)
upgradesPanel.Position = UDim2.fromScale(0.5, 0.5)
upgradesPanel.Size = UDim2.fromOffset(420, 290)
upgradesPanel.BackgroundColor3 = Color3.fromRGB(24, 28, 44)
upgradesPanel.Visible = false
upgradesPanel.Parent = screenGui
addCorner(upgradesPanel, 14)
addStroke(upgradesPanel, Color3.fromRGB(255, 195, 75), 2.2)

local upgTitle = Instance.new("TextLabel")
upgTitle.Size = UDim2.new(1, 0, 0, 42)
upgTitle.BackgroundTransparency = 1
upgTitle.Font = Enum.Font.FredokaOne
upgTitle.TextSize = 22
upgTitle.TextColor3 = Color3.fromRGB(255, 215, 95)
upgTitle.Text = "⚡ JELLY SHOP & UPGRADES"
upgTitle.Parent = upgradesPanel

local upgList = Instance.new("Frame")
upgList.Position = UDim2.fromOffset(18, 48)
upgList.Size = UDim2.new(1, -36, 1, -62)
upgList.BackgroundTransparency = 1
upgList.Parent = upgradesPanel

local upgLayout = Instance.new("UIListLayout")
upgLayout.Padding = UDim.new(0, 10)
upgLayout.Parent = upgList

local function createModalButton(parent: Instance, text: string, color: Color3, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 48)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.FredokaOne
	b.TextSize = 16
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Text = text
	b.Parent = parent
	addCorner(b, 10)
	addStroke(b, Color3.fromRGB(15, 18, 28), 1.5)
	b.Activated:Connect(onClick)
	return b
end

local buyPowerBtn = createModalButton(upgList, "Upgrade Throw Power (Lv.1) — $25", Color3.fromRGB(215, 130, 40), function()
	requestUpgrade:FireServer({ UpgradeType = "ThrowPower" })
end)

local buyPullUpBtn = createModalButton(upgList, "Upgrade Pull-Up Bar (Tier 2) — $75", Color3.fromRGB(65, 150, 235), function()
	requestUpgrade:FireServer({ UpgradeType = "PullUpTier" })
end)

local buySlotsBtn = createModalButton(upgList, "Unlock +4 Slime Slots (8 -> 12) — $5.0K", Color3.fromRGB(70, 185, 110), function()
	requestUpgrade:FireServer({ UpgradeType = "SlotExpansion" })
end)

createModalButton(upgList, "Close", Color3.fromRGB(75, 80, 105), function()
	upgradesPanel.Visible = false
end)

-- Slimes Inventory Panel
local slimesPanel = Instance.new("Frame")
slimesPanel.Name = "SlimesPanel"
slimesPanel.AnchorPoint = Vector2.new(0.5, 0.5)
slimesPanel.Position = UDim2.fromScale(0.5, 0.5)
slimesPanel.Size = UDim2.fromOffset(460, 340)
slimesPanel.BackgroundColor3 = Color3.fromRGB(24, 28, 44)
slimesPanel.Visible = false
slimesPanel.Parent = screenGui
addCorner(slimesPanel, 14)
addStroke(slimesPanel, Color3.fromRGB(120, 245, 165), 2.2)

local slimesTitle = Instance.new("TextLabel")
slimesTitle.Size = UDim2.new(1, 0, 0, 40)
slimesTitle.BackgroundTransparency = 1
slimesTitle.Font = Enum.Font.FredokaOne
slimesTitle.TextSize = 21
slimesTitle.TextColor3 = Color3.fromRGB(130, 255, 175)
slimesTitle.Text = "🟢 MY SLIMES (Click to Equip for Throwing)"
slimesTitle.Parent = slimesPanel

local slimesScroll = Instance.new("ScrollingFrame")
slimesScroll.Position = UDim2.fromOffset(16, 44)
slimesScroll.Size = UDim2.new(1, -32, 1, -104)
slimesScroll.BackgroundColor3 = Color3.fromRGB(18, 21, 34)
slimesScroll.BorderSizePixel = 0
slimesScroll.ScrollBarThickness = 6
slimesScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
slimesScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
slimesScroll.Parent = slimesPanel
addCorner(slimesScroll, 10)

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.Padding = UDim.new(0, 6)
scrollLayout.Parent = slimesScroll

local placeBestBtn = Instance.new("TextButton")
placeBestBtn.Position = UDim2.new(0, 16, 1, -50)
placeBestBtn.Size = UDim2.fromOffset(260, 38)
placeBestBtn.BackgroundColor3 = Color3.fromRGB(60, 185, 115)
placeBestBtn.Font = Enum.Font.FredokaOne
placeBestBtn.TextSize = 15
placeBestBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
placeBestBtn.Text = "✨ Auto-Place Best Slimes on Plot"
placeBestBtn.Parent = slimesPanel
addCorner(placeBestBtn, 8)
placeBestBtn.Activated:Connect(function()
	requestPlaceBest:FireServer()
end)

local closeSlimesBtn = Instance.new("TextButton")
closeSlimesBtn.Position = UDim2.new(1, -166, 1, -50)
closeSlimesBtn.Size = UDim2.fromOffset(150, 38)
closeSlimesBtn.BackgroundColor3 = Color3.fromRGB(75, 80, 105)
closeSlimesBtn.Font = Enum.Font.FredokaOne
closeSlimesBtn.TextSize = 15
closeSlimesBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeSlimesBtn.Text = "Close"
closeSlimesBtn.Parent = slimesPanel
addCorner(closeSlimesBtn, 8)
closeSlimesBtn.Activated:Connect(function()
	slimesPanel.Visible = false
end)

createActionButton("⚡ Upgrades & Shop", Color3.fromRGB(155, 95, 235), function()
	slimesPanel.Visible = false
	upgradesPanel.Visible = not upgradesPanel.Visible
end)

local slimesBtn = createActionButton("🟢 Slimes (1/8)", Color3.fromRGB(50, 165, 155), function()
	upgradesPanel.Visible = false
	slimesPanel.Visible = not slimesPanel.Visible
end)

-- 5. BOTTOM THROW CHARGE & AIM DOCK
local throwDock = Instance.new("Frame")
throwDock.Name = "ThrowDock"
throwDock.AnchorPoint = Vector2.new(0.5, 1)
throwDock.Position = UDim2.new(0.5, 0, 1, -14)
throwDock.Size = UDim2.fromOffset(460, 96)
throwDock.BackgroundColor3 = Color3.fromRGB(22, 26, 40)
throwDock.BackgroundTransparency = 0.1
throwDock.Parent = screenGui
addCorner(throwDock, 14)
addStroke(throwDock, Color3.fromRGB(95, 195, 255), 2)

local equippedInfoLabel = Instance.new("TextLabel")
equippedInfoLabel.Position = UDim2.fromOffset(14, 6)
equippedInfoLabel.Size = UDim2.new(1, -28, 0, 22)
equippedInfoLabel.BackgroundTransparency = 1
equippedInfoLabel.Font = Enum.Font.FredokaOne
equippedInfoLabel.TextSize = 15
equippedInfoLabel.TextColor3 = Color3.fromRGB(215, 235, 255)
equippedInfoLabel.Text = "Equipped: Sprout Slime  |  Angle (Q/E): 36°"
equippedInfoLabel.Parent = throwDock

local meterBg = Instance.new("Frame")
meterBg.Position = UDim2.fromOffset(14, 32)
meterBg.Size = UDim2.new(1, -28, 0, 18)
meterBg.BackgroundColor3 = Color3.fromRGB(40, 46, 68)
meterBg.Parent = throwDock
addCorner(meterBg, 9)

local meterFill = Instance.new("Frame")
meterFill.Size = UDim2.fromScale(0.25, 1)
meterFill.BackgroundColor3 = Color3.fromRGB(110, 245, 145)
meterFill.Parent = meterBg
addCorner(meterFill, 9)

local holdThrowBtn = Instance.new("TextButton")
holdThrowBtn.Position = UDim2.fromOffset(14, 55)
holdThrowBtn.Size = UDim2.new(1, -28, 0, 34)
holdThrowBtn.BackgroundColor3 = Color3.fromRGB(255, 145, 55)
holdThrowBtn.Font = Enum.Font.FredokaOne
holdThrowBtn.TextSize = 17
holdThrowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
holdThrowBtn.Text = "🚀 HOLD TO CHARGE & THROW (or Hold Space at Line)"
holdThrowBtn.Parent = throwDock
addCorner(holdThrowBtn, 9)

holdThrowBtn.MouseButton1Down:Connect(function()
	localPlayer:SetAttribute("HudHoldThrow", true)
end)

holdThrowBtn.MouseButton1Up:Connect(function()
	localPlayer:SetAttribute("HudHoldThrow", false)
end)

local function refreshSlimeInventoryUI()
	for _, child in slimesScroll:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	-- Group counts by slimeId
	local counts: { [string]: number } = {}
	for _, id in currentState.OwnedSlimes or {} do
		counts[id] = (counts[id] or 0) + 1
	end

	local uniqueIds = {}
	for id in counts do
		table.insert(uniqueIds, id)
	end
	table.sort(uniqueIds, function(a, b)
		local da = GameConfig.SlimesById[a]
		local db = GameConfig.SlimesById[b]
		local ra = if da then da.RarityRank else 0
		local rb = if db then db.RarityRank else 0
		return ra > rb
	end)

	for _, id in uniqueIds do
		local def = GameConfig.SlimesById[id]
		if def then
			local isEquipped = (currentState.EquippedSlimeId == id)
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, -10, 0, 42)
			row.BackgroundColor3 = if isEquipped
				then Color3.fromRGB(48, 95, 72)
				else Color3.fromRGB(34, 40, 62)
			row.Font = Enum.Font.FredokaOne
			row.TextSize = 15
			row.TextColor3 = SlimeFactory.GetRarityColor(def.Rarity)
			row.Text = `{if isEquipped then "⭐ [EQUIPPED] " else ""}{def.Name} [{def.Rarity}] x{counts[id]}  —  +$${GameConfig.FormatNumber(def.IncomePerSec)}/s  |  +{def.ThrowBonus} Power`
			row.Parent = slimesScroll
			addCorner(row, 8)
			row.Activated:Connect(function()
				requestEquipSlime:FireServer({ SlimeId = id })
			end)
		end
	end
end

local function refreshHud()
	cashLabel.Text = `💵 $${GameConfig.FormatNumber(currentState.Cash or 0)}`
	powerLabel.Text = `⚡ Power: {GameConfig.FormatNumber(currentState.EffectiveThrowPower or 5)}`
	incomeLabel.Text = `🟢 +$${GameConfig.FormatNumber(currentState.IncomePerSec or 0)}/s`
	bestLabel.Text = `🏆 Best: {string.format("%.0f", currentState.BestDistance or 0)}m`

	local tierIdx = currentState.PullUpTier or 1
	local tierDef = GameConfig.PullUpTiers[tierIdx] or GameConfig.PullUpTiers[1]
	trainBtn.Text = `💪 Pull-Up (+{tierDef.XPPerRep} Power)`
	collectBtn.Text = `💰 Collect ($${GameConfig.FormatNumber(currentState.PendingIncome or 0)})`

	local placedCount = #(currentState.PlacedSlimes or {})
	local maxSlimes = currentState.MaxSlimes or 8
	slimesBtn.Text = `🟢 Slimes ({placedCount}/{maxSlimes})`

	buyPowerBtn.Text = `Upgrade Throw Power (Lv.{currentState.PowerUpgradeLevel or 1}) — $${GameConfig.FormatNumber(currentState.NextPowerCost or 25)}`

	local nextTier = GameConfig.PullUpTiers[tierIdx + 1]
	if nextTier then
		buyPullUpBtn.Text = `Upgrade to {nextTier.Name} (+{nextTier.XPPerRep}/rep) — $${GameConfig.FormatNumber(nextTier.Cost)}`
	else
		buyPullUpBtn.Text = "Pull-Up Bar: MAX TIER REACHED"
	end

	if maxSlimes >= GameConfig.Slots.ExpandedMaxSlimes then
		buySlotsBtn.Text = "Plot Slime Slots: MAX (12 / 12)"
	else
		buySlotsBtn.Text = `Unlock +4 Slime Slots (8 -> 12) — $${GameConfig.FormatNumber(GameConfig.Slots.ExpansionCost)}`
	end

	refreshSlimeInventoryUI()
end

stateSync.OnClientEvent:Connect(function(newState: any)
	if type(newState) == "table" then
		currentState = newState
		refreshHud()
	end
end)

RunService.RenderStepped:Connect(function()
	local ratio = (localPlayer:GetAttribute("ThrowChargeRatio") :: number?) or 0
	local pitch = (localPlayer:GetAttribute("ThrowPitchDeg") :: number?) or GameConfig.Physics.DefaultPitchDeg
	local charging = (localPlayer:GetAttribute("IsCharging") :: boolean?) or false
	local def = GameConfig.SlimesById[currentState.EquippedSlimeId] or GameConfig.Slimes[1]

	equippedInfoLabel.Text = `Equipped: {def.Name} (+{def.ThrowBonus} Power)  |  Pitch Angle (Q/E): {math.floor(pitch)}°  |  Charge: {math.floor(ratio * 100)}%`
	meterFill.Size = UDim2.fromScale(math.clamp(ratio, 0.04, 1.0), 1)
	meterFill.BackgroundColor3 = if charging
		then Color3.fromRGB(255, 210, 75)
		else Color3.fromRGB(110, 245, 145)
end)

refreshHud()
