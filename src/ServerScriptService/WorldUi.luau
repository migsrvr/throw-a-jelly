--!strict
--[[
	WorldUi.luau
	Styled in-world signs (docs/docs/UI-MOCKUP-SPEC.md 3g): plot sign, collect pad, pull-up bar label,
	upgrade stand, and the per-slot signs (filled / locked / empty). Every sign is a BillboardGui with a pixel Size,
	LightInfluence 0, AlwaysOnTop false, MaxDistance 80. The old studs-sized billboards from the place file are removed
	the first time a sign is built. PlotService calls the Set* functions whenever the profile or income changes.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))
local UiKit = require(Shared:WaitForChild("UiKit"))

local WorldUi = {}

local MAX_DISTANCE = 80
-- Slot signs sit close together, so they only show when you are near the plot
local SLOT_MAX_DISTANCE = 40

local TIER_TONES: { UiKit.Tri } = {
	UiKit.Gradients.Grey,
	UiKit.TriFromColor(Color3.fromRGB(140, 160, 185), 0.4, 0.3),
	UiKit.Gradients.Blue,
	UiKit.Gradients.Orange,
	UiKit.Gradients.SlimesNav,
}

local function makeLabel(parent: Instance, size: number, text: string, tone: UiKit.Tri?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.Text = text
	l.Parent = parent
	UiKit.AddTextStroke(l)
	if tone then
		UiKit.ApplyTri(l, tone)
	end
	return l
end

local function makeCard(parent: Instance, tone: UiKit.Tri, radius: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	f.Parent = parent
	UiKit.AddCorner(f, radius)
	UiKit.ApplyTri(f, tone)
	UiKit.AddFrameOutline(f, 4)
	return f
end

local CARD_TONE: UiKit.Tri = {
	Light = Color3.fromRGB(44, 46, 55),
	Mid = Color3.fromRGB(36, 37, 45),
	Dark = Color3.fromRGB(27, 28, 34),
}

-- BillboardGui with a pixel size. Returns its centred "Root" frame (all sign content goes inside it) and whether it was
-- just created. The root carries the UIScale that WorldSignScaler (client) shrinks with camera distance.
local function getBillboard(
	parent: Instance,
	name: string,
	size: Vector2,
	offset: Vector3,
	adornee: BasePart?
): (Frame, boolean)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BillboardGui") then
		return existing:FindFirstChild("Root") :: Frame, false
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Size = UDim2.fromOffset(size.X, size.Y)
	bb.StudsOffset = offset
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.MaxDistance = MAX_DISTANCE
	bb.ResetOnSpawn = false
	if adornee then
		bb.Adornee = adornee
	end
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(size.X, size.Y)
	root.BackgroundTransparency = 1
	root.Parent = bb
	local distanceScale = Instance.new("UIScale")
	distanceScale.Name = "DistanceScale"
	distanceScale.Parent = root
	CollectionService:AddTag(bb, "WorldSign")
	bb.Parent = parent
	return root, true
end

local function setMaxDistance(root: Frame, distance: number)
	local gui = root.Parent
	if gui and gui:IsA("BillboardGui") then
		gui.MaxDistance = distance
	end
end

local function removeOld(parent: Instance?, name: string)
	local old = if parent then parent:FindFirstChild(name) else nil
	if old then
		old:Destroy()
	end
end

local function ownerNameOf(plot: Model): string
	local ownerAttr = plot:GetAttribute("Owner")
	local uid = if type(ownerAttr) == "string" then tonumber(ownerAttr) else nil
	local player = if uid then Players:GetPlayerByUserId(uid) else nil
	return if player then player.DisplayName else "Free Plot"
end

-- ============================================================================
-- Plot sign: green header with the owner name, income below
-- ============================================================================
function WorldUi.SetPlotSign(plot: Model, income: number)
	local sign = plot:FindFirstChild("OwnerSign")
	if not sign or not sign:IsA("BasePart") then
		return
	end
	removeOld(sign, "IncomeBillboard")
	local bb, created = getBillboard(sign, "PlotSign", Vector2.new(290, 120), Vector3.new(0, 4.5, 0), sign)
	if created then
		local card = makeCard(bb, CARD_TONE, 20)
		card.Name = "Card"
		card.Size = UDim2.fromScale(1, 1)
		local header = Instance.new("Frame")
		header.Name = "Header"
		header.Size = UDim2.new(1, 0, 0, 52)
		header.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		header.Parent = card
		UiKit.AddCorner(header, 20)
		UiKit.ApplyTri(header, UiKit.Gradients.Green)
		UiKit.AddStripes(header, 20)
		local name = makeLabel(header, 28, "")
		name.Name = "Owner"
		name.Size = UDim2.fromScale(1, 1)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local inc = makeLabel(card, 36, "", UiKit.Gradients.Cash)
		inc.Name = "Income"
		inc.Position = UDim2.fromOffset(0, 56)
		inc.Size = UDim2.new(1, 0, 0, 52)
	end
	local card = bb:FindFirstChild("Card") :: Frame
	local header = card:FindFirstChild("Header") :: Frame
	local ownerLabel = header:FindFirstChild("Owner") :: TextLabel
	local incomeLabel = card:FindFirstChild("Income") :: TextLabel
	ownerLabel.Text = ownerNameOf(plot)
	incomeLabel.Text = `${GameConfig.FormatNumber(income)}/s`
end

-- ============================================================================
-- Collect pad: pending cash, COLLECT pill, ▼ marker
-- ============================================================================
function WorldUi.SetCollect(plot: Model, pending: number)
	local pad = plot:FindFirstChild("CollectPad")
	if not pad or not pad:IsA("BasePart") then
		return
	end
	removeOld(pad, "CollectBillboard")
	local bb, created = getBillboard(pad, "CollectSign", Vector2.new(220, 130), Vector3.new(0, 3.6, 0), pad)
	if created then
		local cash = makeLabel(bb, 38, "", UiKit.Gradients.Cash)
		cash.Name = "Pending"
		cash.Size = UDim2.new(1, 0, 0, 44)
		local pill = Instance.new("Frame")
		pill.Position = UDim2.fromOffset(20, 48)
		pill.Size = UDim2.new(1, -40, 0, 44)
		pill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		pill.Parent = bb
		UiKit.AddCorner(pill, 22)
		UiKit.ApplyTri(pill, UiKit.Gradients.Green)
		UiKit.AddFrameOutline(pill, 4)
		local lbl = makeLabel(pill, 26, "COLLECT")
		lbl.Size = UDim2.fromScale(1, 1)
		local arrow = makeLabel(bb, 30, "▼", UiKit.Gradients.Luck)
		arrow.Position = UDim2.fromOffset(0, 94)
		arrow.Size = UDim2.new(1, 0, 0, 34)
	end
	local pendingLabel = bb:FindFirstChild("Pending") :: TextLabel
	pendingLabel.Text = `${GameConfig.FormatNumber(math.floor(pending))}`
end

-- ============================================================================
-- Pull-up bar label: tier pill + 2 lines
-- ============================================================================
function WorldUi.SetPullUp(plot: Model, tierIndex: number)
	local pullUp = plot:FindFirstChild("PullUpBar")
	local bar = pullUp and pullUp:FindFirstChild("Bar")
	if not bar or not bar:IsA("BasePart") then
		return
	end
	removeOld(bar, "Billboard")
	local bb, created = getBillboard(bar, "BarSign", Vector2.new(280, 120), Vector3.new(0, 6, 0), bar)
	if created then
		local pill = Instance.new("Frame")
		pill.Name = "Tier"
		pill.Size = UDim2.new(1, 0, 0, 46)
		pill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		pill.Parent = bb
		UiKit.AddCorner(pill, 23)
		UiKit.ApplyTri(pill, TIER_TONES[1])
		UiKit.AddFrameOutline(pill, 4)
		UiKit.AddStripes(pill, 23)
		local lbl = makeLabel(pill, 26, "")
		lbl.Name = "Name"
		lbl.Size = UDim2.fromScale(1, 1)
		local l2 = makeLabel(bb, 20, "Walk under the bar to train", UiKit.Gradients.Luck)
		l2.Position = UDim2.fromOffset(0, 52)
		l2.Size = UDim2.new(1, 0, 0, 28)
		local l3 = makeLabel(bb, 22, "", UiKit.Gradients.Cash)
		l3.Name = "Gain"
		l3.Position = UDim2.fromOffset(0, 82)
		l3.Size = UDim2.new(1, 0, 0, 30)
	end
	local tierDef = GameConfig.PullUpTiers[tierIndex] or GameConfig.PullUpTiers[1]
	local pill = bb:FindFirstChild("Tier") :: Frame
	UiKit.SetTone(pill, TIER_TONES[math.min(tierIndex, #TIER_TONES)])
	local nameLabel = pill:FindFirstChild("Name") :: TextLabel
	local gainLabel = bb:FindFirstChild("Gain") :: TextLabel
	nameLabel.Text = tierDef.Name
	gainLabel.Text = `+{tierDef.XPPerRep} XP / rep`
end

-- ============================================================================
-- Upgrade stand: orange header, "8 ▶ 9", next slot Gem cost + Robux Pass hint
-- ============================================================================
function WorldUi.SetUpgradeStand(plot: Model, maxSlimes: number)
	local stand = plot:FindFirstChild("UpgradeStand")
	local backing = stand and stand:FindFirstChild("Backing")
	if not backing or not backing:IsA("BasePart") then
		return
	end
	local oldSign = plot:FindFirstChild("UpgradeSign")
	local oldGui = oldSign and oldSign:FindFirstChild("SignGui")
	if oldGui and oldGui:IsA("SurfaceGui") then
		oldGui.Enabled = false
	end
	local maxed = maxSlimes >= GameConfig.Slots.ExpandedMaxSlimes
	local bb = backing:FindFirstChild("UpgradeSign")
	if bb then
		bb:Destroy()
	end
	local gui = getBillboard(backing, "UpgradeSign", Vector2.new(270, 152), Vector3.new(0, 4.5, 0), backing)
	local card = makeCard(gui, CARD_TONE, 20)
	card.Size = UDim2.fromScale(1, 1)
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 44)
	header.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	header.Parent = card
	UiKit.AddCorner(header, 20)
	UiKit.ApplyTri(header, UiKit.Gradients.Orange)
	UiKit.AddStripes(header, 20)
	local nextSlot = maxSlimes + 1
	local title = makeLabel(header, 24, if maxed then "MAX SLOTS" else `UNLOCK SLOT #{nextSlot}`)
	title.Size = UDim2.fromScale(1, 1)
	local to = GameConfig.Slots.ExpandedMaxSlimes
	local line = makeLabel(card, 32, if maxed then `{to} / {to}` else `{maxSlimes} ▶ {nextSlot}`, UiKit.Gradients.Green)
	line.Position = UDim2.fromOffset(0, 46)
	line.Size = UDim2.new(1, 0, 0, 36)
	if not maxed then
		local gemCost = GameConfig.GetNextSlotGemCost(maxSlimes) or 1500
		local chips = Instance.new("Frame")
		chips.BackgroundTransparency = 1
		chips.Position = UDim2.fromOffset(0, 84)
		chips.Size = UDim2.new(1, 0, 0, 34)
		chips.Parent = card
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 6)
		layout.Parent = chips
		UiKit.CreateIcon(chips, "gem", 26)
		local gems = makeLabel(chips, 24, `{GameConfig.FormatNumber(gemCost)} Gems`, UiKit.Gradients.Gems)
		gems.AutomaticSize = Enum.AutomaticSize.X
		gems.Size = UDim2.fromOffset(0, 34)

		local hint = makeLabel(card, 16, "or +4 Slots Pass in Shop", UiKit.Gradients.Luck)
		hint.Position = UDim2.fromOffset(0, 120)
		hint.Size = UDim2.new(1, 0, 0, 24)
	end
end

-- ============================================================================
-- Slot signs: filled (rarity gradient), locked (grey + lock + Gem price), empty (gold "Place Slime")
-- ============================================================================
function WorldUi.SetSlot(slotPart: BasePart, slotIdx: number, unlocked: boolean, inst: any?)
	local old = slotPart:FindFirstChild("SlotSign")
	if old then
		old:Destroy()
	end
	if not unlocked then
		local slotCost = GameConfig.Slots.SlotUnlockGemCosts[slotIdx] or 1500
		local bb = getBillboard(slotPart, "SlotSign", Vector2.new(150, 52), Vector3.new(0, 3, 0), slotPart)
		setMaxDistance(bb, SLOT_MAX_DISTANCE)
		local card = makeCard(bb, UiKit.Gradients.Grey, 16)
		card.Size = UDim2.fromScale(1, 1)
		local lock = UiKit.CreateIcon(card, "lock", 28)
		lock.AnchorPoint = Vector2.new(0, 0.5)
		lock.Position = UDim2.new(0, 10, 0.5, 0)
		local gemIcon = UiKit.CreateIcon(card, "gem", 24)
		gemIcon.AnchorPoint = Vector2.new(0, 0.5)
		gemIcon.Position = UDim2.new(0, 42, 0.5, 0)
		local price = makeLabel(card, 22, GameConfig.FormatNumber(slotCost), UiKit.Gradients.Gems)
		price.Position = UDim2.fromOffset(70, 0)
		price.Size = UDim2.new(1, -76, 1, 0)
		price.TextXAlignment = Enum.TextXAlignment.Left
		return
	end
	if not inst then
		local bb = getBillboard(slotPart, "SlotSign", Vector2.new(140, 44), Vector3.new(0, 3, 0), slotPart)
		setMaxDistance(bb, SLOT_MAX_DISTANCE)
		local card = makeCard(bb, UiKit.Gradients.Luck, 27)
		card.Size = UDim2.fromScale(1, 1)
		local lbl = makeLabel(card, 22, "Place Slime")
		lbl.Size = UDim2.fromScale(1, 1)
		return
	end
	local def = GameConfig.SlimesById[inst.SlimeId] or GameConfig.Slimes[1]
	local rarityColor = SlimeFactory.GetRarityColor(def.Rarity)
	local bb = getBillboard(slotPart, "SlotSign", Vector2.new(180, 84), Vector3.new(0, 6, 0), slotPart)
	setMaxDistance(bb, SLOT_MAX_DISTANCE)
	local card = makeCard(bb, UiKit.TriFromColor(rarityColor, 0.4, 0.4), 18)
	card.Size = UDim2.fromScale(1, 1)
	local chip = Instance.new("Frame")
	chip.Position = UDim2.fromOffset(8, 8)
	chip.Size = UDim2.fromOffset(32, 24)
	chip.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	chip.Parent = card
	UiKit.AddCorner(chip, 8)
	UiKit.ApplyTri(chip, UiKit.Gradients.IconPlate)
	UiKit.AddFrameOutline(chip, 2.5)
	local num = makeLabel(chip, 16, tostring(slotIdx))
	num.Size = UDim2.fromScale(1, 1)
	local word = if inst.Mutation ~= "NORMAL" then inst.Mutation else def.Rarity
	local wordColor = if inst.Mutation ~= "NORMAL" then SlimeFactory.GetMutationColor(inst.Mutation) else Color3.fromRGB(255, 255, 255)
	local mut = makeLabel(card, 14, word, UiKit.TriFromColor(wordColor, 0.5, 0.2))
	mut.Position = UDim2.fromOffset(46, 8)
	mut.Size = UDim2.new(1, -54, 0, 24)
	mut.TextXAlignment = Enum.TextXAlignment.Left
	local name = makeLabel(card, 20, inst.Name)
	name.Position = UDim2.fromOffset(8, 32)
	name.Size = UDim2.new(1, -16, 0, 28)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local income = makeLabel(card, 18, `${GameConfig.FormatNumber(inst.IncomePerSec)}/s`, UiKit.Gradients.Cash)
	income.Position = UDim2.fromOffset(8, 60)
	income.Size = UDim2.new(1, -16, 0, 26)
end

return WorldUi
