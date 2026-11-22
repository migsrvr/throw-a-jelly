--!strict
--[[
	ThrowController.client.luau
	Implements the Clip 1 (19-01-59.mp4) throwing & reveal experience with:
	1. ThrowLine stance: holds 3D Jelly Bait in right hand + 9-Segment Vertical Meter
	2. Full-Body Exaggerated Anime Baseball Pitch throw animation + 3/4 Action Camera
	   so you clearly see your avatar's high leg-kick, torso coil, stride, and whip!
	3. Mid-air bait flight camera, trail, ground ring, and top-center "1.XXx LUCK" + Zone Banner
	4. Longer (~4.5s) Slow Underground Peek & Pop-Out + 5-Step Unhurried Creeping Approach
	   to the thrown Jelly Bait (with NO hangman letter animation!), synchronized with the
	   top "1 in X" rarity counter before the explosive reveal!
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
local Remotes = require(Shared:WaitForChild("Remotes"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))
local ThrowPhysics = require(Shared:WaitForChild("ThrowPhysics"))
local UiKit = require(Shared:WaitForChild("UiKit"))
local UiAssets = require(Shared:WaitForChild("UiAssets"))

local requestThrow = Remotes.GetEvent("RequestThrow")
local throwBroadcast = Remotes.GetEvent("ThrowBroadcast")

local isAtThrowLine = false
local isThrowInFlight = false
local isPitchAnimating = false -- true while the local avatar's pitch animation is still playing
local inRevealCutscene = false
local activeThrowToken = 0
local meterClock = 0
local currentMeterRatio = 0.5
local lastThrowTime = 0
local revealTapSignal = Instance.new("BindableEvent")

local throwGui = Instance.new("ScreenGui")
throwGui.Name = "ThrowCutsceneGui"
throwGui.ResetOnSpawn = false
throwGui.IgnoreGuiInset = true
throwGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
throwGui.Parent = playerGui

UiKit.AttachResponsiveScale(throwGui)

local addCorner = UiKit.AddCorner
local addStroke = UiKit.AddStroke

-- Gradient text helper (spec 1c): label stays white, a 3-stop UIGradient carries the colour.
local function applyTone(target: GuiObject, tone: UiKit.Tri)
	local g = target:FindFirstChild("ToneGradient") :: UIGradient?
	if not g then
		g = UiKit.ApplyTri(target, tone)
		return
	end
	(g :: UIGradient).Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, tone.Light),
		ColorSequenceKeypoint.new(0.55, tone.Mid),
		ColorSequenceKeypoint.new(1, tone.Dark),
	})
end

local ZONE_ICON_KEYS = { "zone_meadow", "zone_crystal", "zone_lava", "zone_frost", "zone_candy" }

-- ============================================================================
-- 1. 9-SEGMENT VERTICAL POWER/LUCK METER ("TAP TO THROW!")
-- ============================================================================
local meterRoot = Instance.new("Frame")
meterRoot.Name = "VerticalMeterRoot"
meterRoot.AnchorPoint = Vector2.new(0.5, 0.5)
meterRoot.Position = UDim2.fromScale(0.5, 0.48)
meterRoot.Size = UDim2.fromOffset(230, 350)
meterRoot.BackgroundTransparency = 1
meterRoot.Visible = false
meterRoot.Parent = throwGui

local pillOuter = Instance.new("Frame")
pillOuter.Name = "PillOuter"
pillOuter.AnchorPoint = Vector2.new(0.5, 0)
pillOuter.Position = UDim2.new(0.5, 0, 0, 10)
pillOuter.Size = UDim2.fromOffset(54, 272)
pillOuter.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
pillOuter.Parent = meterRoot
addCorner(pillOuter, 26)
local pillStroke = addStroke(pillOuter, Color3.fromRGB(18, 20, 28), 3.5, Enum.ApplyStrokeMode.Border)

local segmentsContainer = Instance.new("Frame")
segmentsContainer.AnchorPoint = Vector2.new(0.5, 0.5)
segmentsContainer.Position = UDim2.fromScale(0.5, 0.5)
segmentsContainer.Size = UDim2.new(1, -10, 1, -12)
segmentsContainer.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
segmentsContainer.Parent = pillOuter
addCorner(segmentsContainer, 18)

local segCount = #GameConfig.MeterSegments
for i = 1, segCount do
	local segDef = GameConfig.MeterSegments[segCount - i + 1]
	local segFrame = Instance.new("Frame")
	segFrame.Name = `Segment_{segDef.Index}`
	segFrame.Position = UDim2.new(0, 2, (i - 1) / segCount, 2)
	segFrame.Size = UDim2.new(1, -4, 1 / segCount, -4)
	segFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	segFrame.BorderSizePixel = 0
	segFrame.Parent = segmentsContainer
	addCorner(segFrame, 6)
	UiKit.AddGlossGradient(segFrame, SlimeFactory.ToColor3(segDef.Color))
end

local sliderBar = Instance.new("Frame")
sliderBar.Name = "SliderBar"
sliderBar.AnchorPoint = Vector2.new(0.5, 0.5)
sliderBar.Position = UDim2.fromScale(0.5, 0.5)
sliderBar.Size = UDim2.fromOffset(78, 16)
sliderBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
sliderBar.ZIndex = 5
sliderBar.Parent = segmentsContainer
addCorner(sliderBar, 8)
addStroke(sliderBar, Color3.fromRGB(18, 20, 28), 2.8, Enum.ApplyStrokeMode.Border)

local sliderBonusLabel = Instance.new("TextLabel")
sliderBonusLabel.Name = "BonusLabel"
sliderBonusLabel.AnchorPoint = Vector2.new(0, 0.5)
sliderBonusLabel.Position = UDim2.new(1, 10, 0.5, 0)
sliderBonusLabel.Size = UDim2.fromOffset(230, 50)
sliderBonusLabel.BackgroundTransparency = 1
sliderBonusLabel.Font = Enum.Font.FredokaOne
sliderBonusLabel.TextSize = 26
sliderBonusLabel.TextXAlignment = Enum.TextXAlignment.Left
sliderBonusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
sliderBonusLabel.Text = "OK 1.15x"
sliderBonusLabel.ZIndex = 6
sliderBonusLabel.Parent = sliderBar
UiKit.AddTextStroke(sliderBonusLabel)
local lastBandIndex = 0

local tapPromptLabel = Instance.new("TextLabel")
tapPromptLabel.Name = "TapToThrowLabel"
tapPromptLabel.AnchorPoint = Vector2.new(0.5, 1)
tapPromptLabel.Position = UDim2.new(0.5, 0, 1, -6)
tapPromptLabel.Size = UDim2.fromOffset(340, 48)
tapPromptLabel.BackgroundTransparency = 1
tapPromptLabel.Font = Enum.Font.FredokaOne
tapPromptLabel.TextSize = 34
tapPromptLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
-- Hint wording per input device (spec section 3)
local defaultTapPromptText = if UiKit.IsPhone()
	then "TAP TO THROW!"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then "PRESS A TO THROW!"
	else "CLICK TO THROW!"
tapPromptLabel.Text = defaultTapPromptText
tapPromptLabel.Parent = meterRoot
UiKit.AddTextStroke(tapPromptLabel)

-- Auto-Throw toggle (Gem unlock "auto_throw" OR Robux Pass "pass_auto_throw"): shown at the throw line once owned.
-- While ON, the vertical meter stays VISIBLE and smoothly locks onto the exact server-peeked Green/Light-Green band!
local ownsAutoThrow = false
local autoThrowEnabled = false
local autoIdleClock = 0
local nextAutoMeterRatio = GameConfig.AutoThrow.PerfectMeterRatio

-- AUTO toggle (spec section 3): dark gradient pill, "AUTO" + 58x32 track (green when on) with a sliding knob.
local autoThrowButton = Instance.new("TextButton")
autoThrowButton.Name = "AutoThrowToggle"
autoThrowButton.AnchorPoint = Vector2.new(0.5, 0)
autoThrowButton.Position = UDim2.new(0.5, 0, 0.48, 182)
autoThrowButton.Size = UDim2.fromOffset(190, 48)
autoThrowButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
autoThrowButton.AutoButtonColor = false
autoThrowButton.Text = ""
autoThrowButton.Visible = false
autoThrowButton.Parent = throwGui
addCorner(autoThrowButton, 24)
UiKit.AddGradient(autoThrowButton, Color3.fromRGB(52, 54, 63), Color3.fromRGB(36, 38, 44), Color3.fromRGB(23, 24, 28))
UiKit.AddFrameOutline(autoThrowButton, 3)

local autoText = Instance.new("TextLabel")
autoText.AnchorPoint = Vector2.new(0, 0.5)
autoText.Position = UDim2.new(0, 18, 0.5, 0)
autoText.Size = UDim2.fromOffset(70, 30)
autoText.BackgroundTransparency = 1
autoText.Font = Enum.Font.FredokaOne
autoText.TextSize = 22
autoText.TextXAlignment = Enum.TextXAlignment.Left
autoText.TextColor3 = Color3.fromRGB(255, 255, 255)
autoText.Text = "AUTO"
autoText.Parent = autoThrowButton
UiKit.AddTextStroke(autoText)

local autoTrack = Instance.new("Frame")
autoTrack.AnchorPoint = Vector2.new(1, 0.5)
autoTrack.Position = UDim2.new(1, -12, 0.5, 0)
autoTrack.Size = UDim2.fromOffset(58, 32)
autoTrack.BackgroundColor3 = Color3.fromRGB(90, 92, 100)
autoTrack.Parent = autoThrowButton
addCorner(autoTrack, 16)
UiKit.AddFrameOutline(autoTrack, 2.5)

local autoKnob = Instance.new("Frame")
autoKnob.AnchorPoint = Vector2.new(0, 0.5)
autoKnob.Position = UDim2.new(0, 5, 0.5, 0)
autoKnob.Size = UDim2.fromOffset(22, 22)
autoKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
autoKnob.Parent = autoTrack
addCorner(autoKnob, 11)
UiKit.AddGradient(autoKnob, Color3.fromRGB(255, 255, 255), Color3.fromRGB(235, 238, 244), Color3.fromRGB(215, 219, 228))

local autoTrackGradient: UIGradient? = nil
local function refreshAutoThrowButton()
	local on = autoThrowEnabled
	if on and not autoTrackGradient then
		autoTrackGradient = UiKit.ApplyTri(autoTrack, UiKit.Gradients.Green)
	end
	if autoTrackGradient then
		autoTrackGradient.Enabled = on
	end
	autoTrack.BackgroundColor3 = if on then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(90, 92, 100)
	TweenService:Create(
		autoKnob,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = if on then UDim2.new(1, -27, 0.5, 0) else UDim2.new(0, 5, 0.5, 0) }
	):Play()
end
autoThrowButton.Activated:Connect(function()
	autoThrowEnabled = not autoThrowEnabled
	autoIdleClock = 0
	refreshAutoThrowButton()
end)

Remotes.GetEvent("PlayerStateSync").OnClientEvent:Connect(function(state: any)
	if type(state) == "table" then
		local boosts = if type(state.OwnedBoosts) == "table" then state.OwnedBoosts else {}
		local passes = if type(state.OwnedPasses) == "table" then state.OwnedPasses else {}
		ownsAutoThrow = (boosts.auto_throw == true) or (passes.pass_auto_throw == true)
		if type(state.NextAutoMeterRatio) == "number" then
			nextAutoMeterRatio = math.clamp(state.NextAutoMeterRatio, 0, 1)
		end
		if not ownsAutoThrow then
			autoThrowEnabled = false
			refreshAutoThrowButton()
		end
	end
end)

-- ============================================================================
-- 2. MID-AIR FLIGHT HUD ("1.XXx LUCK" + ZONE BANNER)
-- ============================================================================
local flightHud = Instance.new("Frame")
flightHud.Name = "FlightHud"
flightHud.AnchorPoint = Vector2.new(0.5, 0)
flightHud.Position = UDim2.new(0.5, 0, 0, 40)
flightHud.Size = UDim2.fromOffset(460, 250)
flightHud.BackgroundTransparency = 1
flightHud.Visible = false
flightHud.Parent = throwGui

local luckValueLabel = Instance.new("TextLabel")
luckValueLabel.AnchorPoint = Vector2.new(0.5, 0)
luckValueLabel.Position = UDim2.fromScale(0.5, 0)
luckValueLabel.Size = UDim2.fromOffset(420, 92)
luckValueLabel.BackgroundTransparency = 1
luckValueLabel.Font = Enum.Font.FredokaOne
luckValueLabel.TextSize = 88
luckValueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
luckValueLabel.Text = "1.15X"
luckValueLabel.Parent = flightHud
UiKit.ApplyTri(luckValueLabel, UiKit.Gradients.Luck)
UiKit.AddTextStroke(luckValueLabel)

local luckSubLabel = Instance.new("TextLabel")
luckSubLabel.AnchorPoint = Vector2.new(0.5, 0)
luckSubLabel.Position = UDim2.new(0.5, 0, 0, 90)
luckSubLabel.Size = UDim2.fromOffset(200, 38)
luckSubLabel.BackgroundTransparency = 1
luckSubLabel.Font = Enum.Font.FredokaOne
luckSubLabel.TextSize = 32
luckSubLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
luckSubLabel.Text = "LUCK"
luckSubLabel.Parent = flightHud
UiKit.AddTextStroke(luckSubLabel)

local zoneBanner = Instance.new("Frame")
zoneBanner.Name = "ZoneBanner"
zoneBanner.AnchorPoint = Vector2.new(0.5, 0)
zoneBanner.Position = UDim2.new(0.5, 0, 0, 132)
zoneBanner.Size = UDim2.fromOffset(340, 60)
zoneBanner.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
zoneBanner.BorderSizePixel = 0
zoneBanner.Parent = flightHud
addCorner(zoneBanner, 30)
UiKit.ApplyTri(zoneBanner, UiKit.TriFromColor(Color3.fromRGB(120, 245, 105)))
UiKit.AddFrameOutline(zoneBanner, 4)
UiKit.AddStripes(zoneBanner, 30)
local zoneBannerScale = Instance.new("UIScale")
zoneBannerScale.Parent = zoneBanner

local zoneBannerIcon = UiKit.CreateIcon(zoneBanner, "zone_meadow", 42)
zoneBannerIcon.AnchorPoint = Vector2.new(0, 0.5)
zoneBannerIcon.Position = UDim2.new(0, 14, 0.5, 0)

local zoneBannerText = Instance.new("TextLabel")
zoneBannerText.Size = UDim2.new(1, -70, 1, 0)
zoneBannerText.Position = UDim2.fromOffset(64, 0)
zoneBannerText.BackgroundTransparency = 1
zoneBannerText.Font = Enum.Font.FredokaOne
zoneBannerText.TextSize = 30
zoneBannerText.TextColor3 = Color3.fromRGB(255, 255, 255)
zoneBannerText.TextXAlignment = Enum.TextXAlignment.Left
zoneBannerText.Text = "MEADOW"
zoneBannerText.Parent = zoneBanner
UiKit.AddTextStroke(zoneBannerText)

local distanceLabel = Instance.new("TextLabel")
distanceLabel.Name = "DistanceLabel"
distanceLabel.AnchorPoint = Vector2.new(0.5, 0)
distanceLabel.Position = UDim2.new(0.5, 0, 0, 200)
distanceLabel.Size = UDim2.fromOffset(240, 32)
distanceLabel.BackgroundTransparency = 1
distanceLabel.Font = Enum.Font.FredokaOne
distanceLabel.TextSize = 22
distanceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
distanceLabel.Text = "0 studs"
distanceLabel.Parent = flightHud
UiKit.AddTextStroke(distanceLabel)

local currentZoneIndex = 0

-- ============================================================================
-- 3. CINEMATIC "1 IN X" REVEAL CUTSCENE OVERLAY (NO HANGMAN LETTERS)
-- ============================================================================
local fadeOverlay = Instance.new("Frame")
fadeOverlay.Name = "FadeOverlay"
fadeOverlay.Size = UDim2.fromScale(1, 1)
fadeOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
fadeOverlay.BackgroundTransparency = 1
fadeOverlay.ZIndex = 20
fadeOverlay.Active = false
fadeOverlay.Parent = throwGui

local revealRoot = Instance.new("Frame")
revealRoot.Name = "RevealCutsceneRoot"
revealRoot.Size = UDim2.fromScale(1, 1)
revealRoot.BackgroundColor3 = Color3.fromRGB(6, 4, 14)
revealRoot.BackgroundTransparency = 0.88 -- light tint only: the slime and the world stay visible
revealRoot.Visible = false
revealRoot.ZIndex = 12
revealRoot.Parent = throwGui

local superLuckyLabel = Instance.new("TextLabel")
superLuckyLabel.AnchorPoint = Vector2.new(0.5, 0)
superLuckyLabel.Position = UDim2.new(0.5, 0, 0, 100)
superLuckyLabel.Size = UDim2.fromOffset(560, 56)
superLuckyLabel.BackgroundTransparency = 1
superLuckyLabel.Font = Enum.Font.FredokaOne
superLuckyLabel.TextSize = 42
superLuckyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
superLuckyLabel.Rotation = -3
superLuckyLabel.Text = "SUPER LUCKY!"
superLuckyLabel.Visible = false
superLuckyLabel.Parent = revealRoot
UiKit.ApplyTri(superLuckyLabel, UiKit.Gradients.Luck)
UiKit.AddTextStroke(superLuckyLabel)

-- "1 in N" odds (no pill: spec 5 puts it as 76 px outlined text)
local oddsPill = Instance.new("Frame")
oddsPill.AnchorPoint = Vector2.new(0.5, 0)
oddsPill.Position = UDim2.new(0.5, 0, 0, 18)
oddsPill.Size = UDim2.fromOffset(520, 80)
oddsPill.BackgroundTransparency = 1
oddsPill.Parent = revealRoot

local oddsLabel = Instance.new("TextLabel")
oddsLabel.Size = UDim2.fromScale(1, 1)
oddsLabel.BackgroundTransparency = 1
oddsLabel.Font = Enum.Font.FredokaOne
oddsLabel.TextSize = 76
oddsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
oddsLabel.Text = "1 in 1"
oddsLabel.Parent = oddsPill
UiKit.AddTextStroke(oddsLabel)

local finalInfoFrame = Instance.new("Frame")
finalInfoFrame.AnchorPoint = Vector2.new(0.5, 1)
finalInfoFrame.Position = UDim2.new(0.5, 0, 1, -24)
finalInfoFrame.Size = UDim2.fromOffset(900, 270)
finalInfoFrame.BackgroundTransparency = 1
finalInfoFrame.Visible = false
finalInfoFrame.Parent = revealRoot

local mutationLabel = Instance.new("TextLabel")
mutationLabel.AnchorPoint = Vector2.new(0.5, 0)
mutationLabel.Position = UDim2.new(0.5, 0, 0, 0)
mutationLabel.Size = UDim2.fromOffset(600, 40)
mutationLabel.BackgroundTransparency = 1
mutationLabel.Font = Enum.Font.FredokaOne
mutationLabel.TextSize = 34
mutationLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
mutationLabel.Text = "EMERALD"
mutationLabel.Parent = finalInfoFrame
UiKit.AddTextStroke(mutationLabel)

-- SUGARKING (9 letters) at 84 px has to fit 1241 px: the label is wide and TextScaled-capped
local revealedNameLabel = Instance.new("TextLabel")
revealedNameLabel.AnchorPoint = Vector2.new(0.5, 0)
revealedNameLabel.Position = UDim2.new(0.5, 0, 0, 40)
revealedNameLabel.Size = UDim2.fromOffset(900, 92)
revealedNameLabel.BackgroundTransparency = 1
revealedNameLabel.Font = Enum.Font.FredokaOne
revealedNameLabel.TextSize = 84
revealedNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
revealedNameLabel.Text = "HONEY"
revealedNameLabel.Parent = finalInfoFrame
UiKit.AddTextStroke(revealedNameLabel)

local revealedIncomeLabel = Instance.new("TextLabel")
revealedIncomeLabel.AnchorPoint = Vector2.new(0.5, 0)
revealedIncomeLabel.Position = UDim2.new(0.5, 0, 0, 136)
revealedIncomeLabel.Size = UDim2.fromOffset(400, 46)
revealedIncomeLabel.BackgroundTransparency = 1
revealedIncomeLabel.Font = Enum.Font.FredokaOne
revealedIncomeLabel.TextSize = 38
revealedIncomeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
revealedIncomeLabel.Text = "$10/s"
revealedIncomeLabel.Parent = finalInfoFrame
UiKit.ApplyTri(revealedIncomeLabel, UiKit.Gradients.Cash)
UiKit.AddTextStroke(revealedIncomeLabel)

-- "+N" followed by the gem icon (38 px)
local gemsRow = Instance.new("Frame")
gemsRow.Name = "GemsRow"
gemsRow.AnchorPoint = Vector2.new(0.5, 0)
gemsRow.Position = UDim2.new(0.5, 0, 0, 186)
gemsRow.Size = UDim2.fromOffset(200, 40)
gemsRow.BackgroundTransparency = 1
gemsRow.Visible = false
gemsRow.Parent = finalInfoFrame
local gemsLayout = Instance.new("UIListLayout")
gemsLayout.FillDirection = Enum.FillDirection.Horizontal
gemsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gemsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
gemsLayout.Padding = UDim.new(0, 6)
gemsLayout.Parent = gemsRow

local gemsLabel = Instance.new("TextLabel")
gemsLabel.AutomaticSize = Enum.AutomaticSize.X
gemsLabel.Size = UDim2.fromOffset(0, 40)
gemsLabel.BackgroundTransparency = 1
gemsLabel.Font = Enum.Font.FredokaOne
gemsLabel.TextSize = 32
gemsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
gemsLabel.Text = "+3"
gemsLabel.LayoutOrder = 1
gemsLabel.Parent = gemsRow
UiKit.ApplyTri(gemsLabel, UiKit.Gradients.Gems)
UiKit.AddTextStroke(gemsLabel)
local gemsIcon = UiKit.CreateIcon(gemsRow, "gem", 38)
gemsIcon.LayoutOrder = 2

local newBadge = Instance.new("Frame")
newBadge.AnchorPoint = Vector2.new(0, 0.5)
newBadge.Position = UDim2.new(0.5, 250, 0, 80)
newBadge.Size = UDim2.fromOffset(110, 50)
newBadge.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
newBadge.Rotation = 10
newBadge.Parent = finalInfoFrame
addCorner(newBadge, 12)
UiKit.ApplyTri(newBadge, UiKit.Gradients.Red)
UiKit.AddFrameOutline(newBadge, 3)

local newBadgeText = Instance.new("TextLabel")
newBadgeText.Size = UDim2.fromScale(1, 1)
newBadgeText.BackgroundTransparency = 1
newBadgeText.Font = Enum.Font.FredokaOne
newBadgeText.TextSize = 28
newBadgeText.TextColor3 = Color3.fromRGB(255, 255, 255)
newBadgeText.Text = "NEW!"
newBadgeText.Parent = newBadge
UiKit.AddTextStroke(newBadgeText)

local tapContinueLabel = Instance.new("TextLabel")
tapContinueLabel.AnchorPoint = Vector2.new(0.5, 1)
tapContinueLabel.Position = UDim2.new(0.5, 0, 1, 0)
tapContinueLabel.Size = UDim2.fromOffset(380, 28)
tapContinueLabel.BackgroundTransparency = 1
tapContinueLabel.Font = Enum.Font.FredokaOne
tapContinueLabel.TextSize = 22
tapContinueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
tapContinueLabel.TextTransparency = 0.15
tapContinueLabel.Text = if UiKit.IsPhone() then "Tap to continue (3s)" else "Click to continue (3s)"
tapContinueLabel.Parent = finalInfoFrame

local function playShockwaveRings()
	for i = 1, 3 do
		task.delay((i - 1) * 0.1, function()
			local ring = Instance.new("Frame")
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.45)
			ring.Size = UDim2.fromOffset(40, 40)
			ring.BackgroundTransparency = 1
			ring.ZIndex = 15
			ring.Parent = revealRoot
			addCorner(ring, 400)
			local stroke = Instance.new("UIStroke")
			stroke.Color = if i % 2 == 1
				then Color3.fromRGB(255, 95, 155)
				else Color3.fromRGB(255, 225, 95)
			stroke.Thickness = 6
			stroke.Parent = ring

			local tw = TweenService:Create(ring, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(680, 680),
			})
			TweenService:Create(stroke, TweenInfo.new(0.55), {
				Transparency = 1,
				Thickness = 1,
			}):Play()
			tw:Play()
			task.delay(0.6, function()
				ring:Destroy()
			end)
		end)
	end
end

local function spawnGroundRipple(groundPosition: Vector3, color: Color3, maxDiameter: number, duration: number)
	local ring = Instance.new("Part")
	ring.Name = "EmergenceRipple"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.18, 1.5, 1.5)
	ring.CFrame = CFrame.new(groundPosition + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide = false
	ring.CastShadow = false
	ring.Parent = workspace

	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, maxDiameter, maxDiameter),
		Transparency = 1,
	}):Play()
	task.delay(duration + 0.05, function()
		ring:Destroy()
	end)
end

local function checkNearThrowLine(): boolean
	local char = localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local pos = root.Position
	local nearZ = pos.Z >= (GameConfig.Hub.ThrowLineZ - 9) and pos.Z <= (GameConfig.Hub.ThrowLineZ + 6)
	local nearY = pos.Y >= (GameConfig.Hub.FloorY - 5)
	local nearX = pos.X >= GameConfig.Hub.ThrowLineMinX and pos.X <= GameConfig.Hub.ThrowLineMaxX
	return nearZ and nearY and nearX
end

-- Bold quality callout matching the exact meter band where the throw locked (WEAK -> OK -> GOOD -> GREAT! -> PERFECT!)
local function showThrowQualityCallout(qualityLabel: string, luckMult: number, colorRgb: { number }?, isPerfect: boolean)
	local label = Instance.new("TextLabel")
	label.Name = if isPerfect then "PerfectCallout" else "QualityCallout"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.48, -200)
	label.Size = UDim2.fromOffset(500, 80)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = if isPerfect then 64 else 48
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = string.format("%s %.2fx", qualityLabel, luckMult)
	label.Rotation = if isPerfect then -6 else -3
	label.ZIndex = 15
	label.Parent = throwGui
	local tone = if isPerfect
		then UiKit.Gradients.Luck
		elseif colorRgb then UiKit.TriFromColor(SlimeFactory.ToColor3(colorRgb), 0.45, 0.25)
		else UiKit.Gradients.Green
	UiKit.ApplyTri(label, tone)
	UiKit.AddTextStroke(label)

	-- Pop 1.4 -> 1 with Back easing, flash pill outline
	local scale = Instance.new("UIScale")
	scale.Scale = 1.4
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	pillStroke.Color = if isPerfect
		then UiKit.Colors.Gold
		elseif colorRgb then SlimeFactory.ToColor3(colorRgb)
		else UiKit.Colors.Green
	task.delay(0.5, function()
		pillStroke.Color = Color3.fromRGB(18, 20, 28)
	end)
	task.delay(0.9, function()
		local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, fade, { TextTransparency = 1, Position = label.Position - UDim2.fromOffset(0, 30) }):Play()
		task.delay(0.4, function()
			label:Destroy()
		end)
	end)
end

local function resetThrowState()
	activeThrowToken += 1
	isThrowInFlight = false
	isPitchAnimating = false
	inRevealCutscene = false
	flightHud.Visible = false
	revealRoot.Visible = false
	fadeOverlay.BackgroundTransparency = 1
	localPlayer:SetAttribute("InThrow", false)
	localPlayer:SetAttribute("InRevealCutscene", false)
	CharacterAnimator.StopAimPose()
	if (localPlayer:GetAttribute("InTraining") :: boolean?) ~= true then
		local cam = workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Custom
		end
	end
end

localPlayer.CharacterRemoving:Connect(resetThrowState)
localPlayer.CharacterAdded:Connect(resetThrowState)

local function triggerThrowFromMeter(isAuto: boolean?)
	if isThrowInFlight or inRevealCutscene then
		return
	end
	if (localPlayer:GetAttribute("ModalOpen") :: boolean?) == true then
		return
	end
	local now = os.clock()
	if now - lastThrowTime < 1.1 then
		return
	end
	lastThrowTime = now
	activeThrowToken += 1
	local myToken = activeThrowToken
	isThrowInFlight = true
	localPlayer:SetAttribute("InThrow", true)
	meterRoot.Visible = false
	autoThrowButton.Visible = false

	-- Auto throws draw their PERFECT/GREAT outcome from the server's shuffled 5-throw bag (callout fires on ThrowBroadcast)
	local lockedRatio = if isAuto then GameConfig.AutoThrow.MeterRatio else currentMeterRatio
	if not isAuto then
		local lockedSeg = GameConfig.EvaluateMeterRatio(lockedRatio)
		showThrowQualityCallout(lockedSeg.QualityLabel, lockedSeg.LuckMultiplier, lockedSeg.Color, lockedSeg.IsPerfect == true)
	end
	local char = localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cam = workspace.CurrentCamera

	-- Frame a dramatic 3/4 side-front Anime Pitcher Action Camera during the wind-up and stride!
	if cam and root then
		cam.CameraType = Enum.CameraType.Scriptable
		local pitcherPos = root.Position
		local camPos = pitcherPos + Vector3.new(7.2, 2.0, 5.6)
		local lookTarget = pitcherPos + Vector3.new(0, 0.8, 0.6)
		TweenService:Create(cam, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(camPos, lookTarget),
		}):Play()
	end

	isPitchAnimating = true
	local releaseSent = false
	CharacterAnimator.PlayThrowAnimation(char, function()
		releaseSent = true
		requestThrow:FireServer({
			ChargeRatio = lockedRatio,
			PitchDeg = GameConfig.Physics.DefaultPitchDeg,
			YawDeg = 0,
			Auto = isAuto == true,
		})
		-- Watchdog: if the server drops or rejects the throw, recover the camera so the player never soft-locks
		task.delay(4.0, function()
			if activeThrowToken == myToken and isThrowInFlight and not inRevealCutscene then
				resetThrowState()
			end
		end)
	end, function()
		isPitchAnimating = false
		-- Pitch was cut short (e.g. character reset) before release: unlock the throw line again
		if not releaseSent and activeThrowToken == myToken then
			resetThrowState()
		end
	end)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if inRevealCutscene then
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			revealTapSignal:Fire()
		end
		return
	end

	if gameProcessed then
		return
	end

	if (localPlayer:GetAttribute("ModalOpen") :: boolean?) == true then
		return
	end

	if
		isAtThrowLine
		and not isThrowInFlight
		and not (ownsAutoThrow and autoThrowEnabled)
		and (
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.ButtonA
		)
	then
		triggerThrowFromMeter()
	end
end)

-- Stage A: Longer (~1.65s) Slow Underground Peek & Full Pop-Out!
local function animateLongerUndergroundEmergence(
	slimeModel: Model,
	emergeXZ: Vector3,
	floorY: number,
	lookTarget: Vector3
)
	local deepY = floorY - 2.7
	local peekY = floorY + 0.15 -- Top half of head peeking out of the floor!
	local surfaceY = floorY + 1.22
	local popPeakY = floorY + 1.95

	-- Wave 1 ripple as head pushes up
	spawnGroundRipple(Vector3.new(emergeXZ.X, floorY, emergeXZ.Z), Color3.fromRGB(115, 255, 145), 8.5, 0.75)

	-- Part 1 (0.70s): Slowly push top of head out to peek above the floor
	local t0 = os.clock()
	while true do
		local u = math.clamp((os.clock() - t0) / 0.70, 0, 1)
		local ease = 1 - ((1 - u) ^ 2)
		local curY = deepY + (peekY - deepY) * ease
		local pos = Vector3.new(emergeXZ.X, curY, emergeXZ.Z)
		local lookPos = Vector3.new(lookTarget.X, curY, lookTarget.Z)
		SlimeFactory.PositionSlime(slimeModel, CFrame.lookAt(pos, lookPos), -0.18 * u)
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end

	-- Part 2 (0.38s): Curious peek pause — looks slightly left & right toward the landed bait!
	local t1 = os.clock()
	while true do
		local u = math.clamp((os.clock() - t1) / 0.38, 0, 1)
		local yawGlance = math.rad(14 * math.sin(u * math.pi * 2))
		local pos = Vector3.new(emergeXZ.X, peekY, emergeXZ.Z)
		local lookPos = Vector3.new(lookTarget.X, peekY, lookTarget.Z)
		SlimeFactory.PositionSlime(slimeModel, CFrame.lookAt(pos, lookPos) * CFrame.Angles(0, yawGlance, 0), 0.10)
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end

	-- Wave 2 ripple as the full body squeezes out of the ground!
	spawnGroundRipple(Vector3.new(emergeXZ.X, floorY, emergeXZ.Z), Color3.fromRGB(115, 255, 145), 11.0, 0.65)

	-- Part 3 (0.62s): Squeeze & pop the rest of the jelly body out onto the surface
	local t2 = os.clock()
	while true do
		local u = math.clamp((os.clock() - t2) / 0.62, 0, 1)
		local curY: number
		local squash: number
		if u < 0.65 then
			local a = u / 0.65
			curY = peekY + (popPeakY - peekY) * (1 - ((1 - a) ^ 2))
			squash = -0.34 * math.sin(a * math.pi)
		else
			local a = (u - 0.65) / 0.35
			curY = popPeakY + (surfaceY - popPeakY) * a
			squash = 0.25 * math.sin(a * math.pi)
		end
		local pos = Vector3.new(emergeXZ.X, curY, emergeXZ.Z)
		local lookPos = Vector3.new(lookTarget.X, curY, lookTarget.Z)
		SlimeFactory.PositionSlime(slimeModel, CFrame.lookAt(pos, lookPos), squash)
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

-- Stage B: Slow, deliberate squash-hop toward the thrown bait with curious head tilt!
local function animateSlowHopTowardBait(
	slimeModel: Model,
	startPos: Vector3,
	endPos: Vector3,
	baitPos: Vector3,
	hopDuration: number,
	stepIndex: number
)
	local startClock = os.clock()
	local hopHeight = 0.85
	local tiltDir = if stepIndex % 2 == 1 then 1 else -1

	while true do
		local elapsed = os.clock() - startClock
		local u = math.clamp(elapsed / hopDuration, 0, 1)

		local pos: Vector3
		local squash: number
		local headTiltRad = 0

		if u < 0.24 then
			local a = u / 0.24
			pos = startPos
			squash = 0.25 * a
		elseif u < 0.78 then
			local a = (u - 0.24) / 0.54
			local horiz = startPos:Lerp(endPos, a)
			local arcY = math.sin(a * math.pi) * hopHeight
			pos = horiz + Vector3.new(0, arcY, 0)
			squash = -0.20 * math.sin(a * math.pi)
			headTiltRad = math.rad(9 * tiltDir * math.sin(a * math.pi))
		else
			local a = (u - 0.78) / 0.22
			pos = endPos
			squash = 0.22 * (1 - a)
			headTiltRad = math.rad(11 * tiltDir * math.sin(a * math.pi))
		end

		local lookAtPos = Vector3.new(baitPos.X, pos.Y, baitPos.Z)
		local cf = CFrame.lookAt(pos, lookAtPos) * CFrame.Angles(0, 0, headTiltRad)
		SlimeFactory.PositionSlime(slimeModel, cf, squash)

		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end

	spawnGroundRipple(
		Vector3.new(endPos.X, endPos.Y - 1.22, endPos.Z),
		Color3.fromRGB(115, 255, 145),
		5.0,
		0.35
	)
end

-- Casts from lookTarget -> desiredPos so the reveal camera never clips inside a zone cliff or prop
local function safeRevealCamCFrame(desiredPos: Vector3, lookTarget: Vector3, exclude: { Instance }): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local dir = desiredPos - lookTarget
	local dist = dir.Magnitude
	if dist > 0.5 then
		local hit = workspace:Raycast(lookTarget, dir, params)
		if hit then
			local safeDist = math.max(4.5, (hit.Position - lookTarget).Magnitude - 0.8)
			desiredPos = lookTarget + dir.Unit * safeDist
		end
	end
	return CFrame.lookAt(desiredPos, lookTarget)
end

local function runRevealCutscene(finalPos: Vector3, baitModel: Model, payload: any)
	inRevealCutscene = true
	localPlayer:SetAttribute("InRevealCutscene", true)
	flightHud.Visible = false

	local slimeModel: Model? = nil
	local cam = workspace.CurrentCamera

	local ok, err = pcall(function()
		TweenService:Create(fadeOverlay, TweenInfo.new(0.22), { BackgroundTransparency = 0 }):Play()
		task.wait(0.24)

		local landedZone = ThrowPhysics.GetZoneAtZ(math.max(0, finalPos.Z))
		local floorY = landedZone.FloorY
		-- Clamp staging strictly inside the open lane corridor and away from cliff walls
		local stageX = math.clamp(finalPos.X, -(landedZone.ClearHalfWidth - 11), landedZone.ClearHalfWidth - 4)
		local stageZ = math.clamp(finalPos.Z, landedZone.StartZ + 3.0, landedZone.EndZ - 3.0)
		-- If near the far cliff edge of a zone (or Zone 5 end wall), flip camera to the open -Z side!
		local camSideZ = if stageZ > landedZone.EndZ - 14.0 then -1 else 1
		local emergeDz = if camSideZ > 0 then -1 else 1

		local baitGroundPos = Vector3.new(stageX + 1.5, floorY + 0.55, stageZ)

		-- 6 waypoints (Emergence at 10.5 studs away + 5 slow hops right up to the thrown bait!)
		local hopWaypoints = {
			Vector3.new(stageX - 9.0, floorY + 1.22, stageZ + 1.4 * emergeDz), -- 1. Emergence spot
			Vector3.new(stageX - 7.1, floorY + 1.22, stageZ + 1.1 * emergeDz), -- 2. After Hop 1
			Vector3.new(stageX - 5.3, floorY + 1.22, stageZ + 0.8 * emergeDz), -- 3. After Hop 2
			Vector3.new(stageX - 3.7, floorY + 1.22, stageZ + 0.5 * emergeDz), -- 4. After Hop 3
			Vector3.new(stageX - 2.3, floorY + 1.22, stageZ + 0.3 * emergeDz), -- 5. After Hop 4
			Vector3.new(stageX - 1.1, floorY + 1.22, stageZ + 0.1 * emergeDz), -- 6. After Hop 5 (right beside the bait!)
		}

		SlimeFactory.PositionBait(baitModel, CFrame.new(baitGroundPos) * CFrame.Angles(0, math.rad(35), 0))

		local slimeId = payload.CaughtSlimeId or "meadow_sprout"
		local mutId = payload.CaughtMutation or "NORMAL"
		local createdSlime = SlimeFactory.CreateSlimeModel(slimeId, false, mutId, payload.CaughtIncomePerSec)
		slimeModel = createdSlime
		SlimeFactory.SetSilhouetteMode(createdSlime, true)
		SlimeFactory.PositionSlime(
			createdSlime,
			CFrame.lookAt(
				Vector3.new(hopWaypoints[1].X, floorY - 2.7, hopWaypoints[1].Z),
				Vector3.new(baitGroundPos.X, floorY - 2.7, baitGroundPos.Z)
			),
			0
		)
		createdSlime.Parent = workspace

		local rayExclude: { Instance } = { createdSlime, baitModel }
		if localPlayer.Character then
			table.insert(rayExclude, localPlayer.Character)
		end

		if cam then
			cam.CameraType = Enum.CameraType.Scriptable
			local camPos = Vector3.new(stageX - 2.4, floorY + 3.6, stageZ + 11.2 * camSideZ)
			local lookTarget = Vector3.new(stageX - 2.8, floorY + 1.1, stageZ + 0.3 * emergeDz)
			cam.CFrame = safeRevealCamCFrame(camPos, lookTarget, rayExclude)
		end

		local targetOdds = math.max(1, tonumber(payload.OddsOneInX) or 4)
		local shortWord = tostring(payload.CaughtShortWord or "SLIME")
		superLuckyLabel.Visible = false
		finalInfoFrame.Visible = false
		oddsLabel.Text = "1 in 1"
		revealRoot.Visible = true

		TweenService:Create(fadeOverlay, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()

		-- STAGE A: Longer (~1.70s) Slow Underground Peek & Pop-Out!
		animateLongerUndergroundEmergence(createdSlime, hopWaypoints[1], floorY, baitGroundPos)

		-- STAGE B: 5 slow, unhurried hops creeping toward the thrown Jelly Bait (~2.85s)!
		local oddsSteps = {
			math.max(1, math.floor(targetOdds * 0.12)),
			math.max(1, math.floor(targetOdds * 0.26)),
			math.max(1, math.floor(targetOdds * 0.45)),
			math.max(1, math.floor(targetOdds * 0.68)),
			math.max(1, math.floor(targetOdds * 0.88)),
		}

		for step = 1, 5 do
			oddsLabel.Text = `1 in {oddsSteps[step]}`

			if cam then
				local targetCamPos = Vector3.new(
					stageX - 2.2 + step * 0.36,
					floorY + 3.5 - step * 0.08,
					stageZ + (10.8 - step * 0.45) * camSideZ
				)
				local targetLook = Vector3.new(stageX - 2.4 + step * 0.38, floorY + 1.15, stageZ)
				TweenService:Create(cam, TweenInfo.new(0.46, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					CFrame = safeRevealCamCFrame(targetCamPos, targetLook, rayExclude),
				}):Play()
			end

			animateSlowHopTowardBait(
				createdSlime,
				hopWaypoints[step],
				hopWaypoints[step + 1],
				baitGroundPos,
				0.46,
				step
			)

			task.wait(0.12)
		end

		-- Curious sniff lean toward the bait right before the burst!
		local finalSlimePos = hopWaypoints[6]
		SlimeFactory.PositionSlime(
			createdSlime,
			CFrame.lookAt(finalSlimePos + Vector3.new(0.35, 0, 0), baitGroundPos),
			-0.15
		)
		task.wait(0.32)

		-- STAGE C: EXPLOSIVE REVEAL right next to the bait!
		SlimeFactory.SetSilhouetteMode(createdSlime, false)
		if cam then
			SlimeFactory.PositionSlime(
				createdSlime,
				CFrame.lookAt(
					finalSlimePos + Vector3.new(0, 0.5, 0),
					Vector3.new(cam.CFrame.Position.X, finalSlimePos.Y, cam.CFrame.Position.Z)
				),
				-0.30
			)
			task.delay(0.15, function()
				if createdSlime.Parent and cam then
					SlimeFactory.PositionSlime(
						createdSlime,
						CFrame.lookAt(
							finalSlimePos,
							Vector3.new(cam.CFrame.Position.X, finalSlimePos.Y, cam.CFrame.Position.Z)
						),
						0.18
					)
				end
			end)
		end

		playShockwaveRings()

		oddsLabel.Text = `1 in {targetOdds}`
		superLuckyLabel.Visible = (payload.IsSuperLucky == true)

		local def = GameConfig.SlimesById[slimeId] or GameConfig.Slimes[1]
		local mutColor = if mutId ~= "NORMAL"
			then SlimeFactory.GetMutationColor(mutId)
			else SlimeFactory.GetRarityColor(def.Rarity)

		mutationLabel.Text = if mutId ~= "NORMAL" then mutId else string.upper(def.Rarity)
		applyTone(mutationLabel, UiKit.TriFromColor(mutColor, 0.6, 0.3))
		revealedNameLabel.Text = shortWord
		applyTone(revealedNameLabel, UiKit.TriFromColor(SlimeFactory.ToColor3(def.Color), 0.6, 0.3))
		local gemsEarned = tonumber(payload.GemsEarned) or 0
		revealedIncomeLabel.Text = `${GameConfig.FormatNumber(payload.CaughtIncomePerSec or def.IncomePerSec)}/s`
		gemsLabel.Text = `+{gemsEarned}`
		gemsRow.Visible = gemsEarned > 0
		newBadge.Visible = (payload.IsNewDiscovery == true)
		finalInfoFrame.Visible = true

		-- Click/tap skips immediately, or auto-dismisses cleanly after 3.0s so AFK auto-throw keeps looping
		local done = false
		local doneConn = revealTapSignal.Event:Connect(function()
			done = true
		end)
		local continuePrefix = if UiKit.IsPhone() then "Tap to continue" else "Click to continue"
		local waitStart = os.clock()
		local AUTO_DISMISS_SECONDS = 3.0
		while not done do
			local remaining = AUTO_DISMISS_SECONDS - (os.clock() - waitStart)
			if remaining <= 0 then
				break
			end
			tapContinueLabel.Text = `{continuePrefix} ({math.ceil(remaining)}s)`
			task.wait(0.05)
		end
		doneConn:Disconnect()

		TweenService:Create(fadeOverlay, TweenInfo.new(0.22), { BackgroundTransparency = 0 }):Play()
		task.wait(0.24)
	end)

	if not ok then
		warn("[ThrowController] reveal cutscene error:", err)
	end

	-- Guaranteed teardown so fadeOverlay never sticks as a black screen
	revealRoot.Visible = false
	if slimeModel then
		slimeModel:Destroy()
	end
	if baitModel.Parent then
		baitModel:Destroy()
	end

	if cam and (localPlayer:GetAttribute("InTraining") :: boolean?) ~= true then
		cam.CameraType = Enum.CameraType.Custom
	end

	TweenService:Create(fadeOverlay, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	inRevealCutscene = false
	isThrowInFlight = false
	localPlayer:SetAttribute("InThrow", false)
	localPlayer:SetAttribute("InRevealCutscene", false)
end

throwBroadcast.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end

	local isLocal = (payload.PlayerUserId == localPlayer.UserId)
	if isLocal then
		-- Disarm the pre-flight server-drop watchdog once ThrowBroadcast arrives
		activeThrowToken += 1
		if type(payload.NextAutoMeterRatio) == "number" then
			nextAutoMeterRatio = math.clamp(payload.NextAutoMeterRatio, 0, 1)
		end
		if payload.IsAuto == true then
			local isPerf = payload.IsPerfect == true
			local qLabel = if type(payload.QualityLabel) == "string"
				then payload.QualityLabel
				elseif isPerf then "PERFECT!"
				else "GREAT!"
			showThrowQualityCallout(qLabel, tonumber(payload.MeterLuck) or 1.48, payload.QualityColor, isPerf)
		end
	end

	local sim = ThrowPhysics.Simulate({
		Origin = payload.Origin,
		ThrowPower = payload.ThrowPower or 5,
		ChargeRatio = payload.ChargeRatio or 0.75,
		PitchDeg = payload.PitchDeg or GameConfig.Physics.DefaultPitchDeg,
		YawDeg = payload.YawDeg or 0,
		SlimeWeight = payload.SlimeWeight or 1.0,
	})

	local baitModel = SlimeFactory.CreateJellyBaitModel()
	baitModel.Parent = workspace

	-- Live luck ticker: replays the server's GameConfig.ComputeFlightLuck as the bait flies, so the
	-- top-centre "1.XXx LUCK" climbs with distance and ends exactly on the server's LuckMultiplier.
	local meterLuck = tonumber(payload.MeterLuck) or tonumber(payload.LuckMultiplier) or 1.0
	-- Gem luck boosts (Lucky Charm) are folded into the bait factor, exactly as ThrowService does
	local baitLuck = (tonumber(payload.BaitLuck) or 1.0) * (tonumber(payload.BoostLuck) or 1.0)
	local finalLuck = tonumber(payload.LuckMultiplier) or 1.0
	local maxDistance = 0
	if isLocal then
		luckValueLabel.Text = string.format("%.2fX", GameConfig.ComputeFlightLuck(0, meterLuck, baitLuck))
		currentZoneIndex = 0
		distanceLabel.Text = "0 studs"
		flightHud.Visible = true
	end

	local samples = sim.Samples
	local totalSamples = #samples
	local startClock = os.clock()
	local cam = workspace.CurrentCamera
	local chaseBlendStart: number? = nil
	local chaseFromCf = CFrame.identity

	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startClock
		local frameIdx = math.min(totalSamples, math.max(1, math.floor(elapsed / GameConfig.Physics.FixedDt) + 1))
		local sample = samples[frameIdx]

		if sample then
			local pos = Vector3.new(sample.Position.X, sample.Position.Y, sample.Position.Z)
			local spinCf = CFrame.new(pos) * CFrame.Angles(elapsed * 9, 0, elapsed * 4.5)
			SlimeFactory.PositionBait(baitModel, spinCf)

			if isLocal then
				maxDistance = math.max(maxDistance, math.clamp(pos.Z, 0, GameConfig.Hub.LaneMaxZ))
				local liveLuck = math.min(finalLuck, GameConfig.ComputeFlightLuck(maxDistance, meterLuck, baitLuck))
				luckValueLabel.Text = string.format("%.2fX", liveLuck)
			end

			if isLocal and cam then
				local zoneDef = ThrowPhysics.GetZoneAtZ(math.max(0, pos.Z))
				distanceLabel.Text = `{math.floor(maxDistance)} studs`
				if zoneDef.Index ~= currentZoneIndex then
					currentZoneIndex = zoneDef.Index
					zoneBannerText.Text = string.upper(zoneDef.Name)
					applyTone(zoneBanner, UiKit.TriFromColor(SlimeFactory.ToColor3(zoneDef.ThemeColor)))
					zoneBannerIcon.Image = (UiAssets.Icons :: any)[ZONE_ICON_KEYS[zoneDef.Index] or ""] or ""
					zoneBannerScale.Scale = 1.15
					TweenService:Create(
						zoneBannerScale,
						TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Scale = 1 }
					):Play()
				end

				-- Hold the 3/4 pitcher shot until the follow-through finishes, then blend to chase the bait
				if not isPitchAnimating then
					cam.CameraType = Enum.CameraType.Scriptable
					local chasePos = pos + Vector3.new(0, 8.5, -18.5)
					local chaseCf = CFrame.lookAt(chasePos, pos + Vector3.new(0, 0.5, 8))
					if not chaseBlendStart then
						chaseBlendStart = os.clock()
						chaseFromCf = cam.CFrame
					end
					local blend = math.clamp((os.clock() - chaseBlendStart) / 0.25, 0, 1)
					cam.CFrame = chaseFromCf:Lerp(chaseCf, 1 - (1 - blend) ^ 2)
				end
			end
		end

		if frameIdx >= totalSamples then
			if conn then
				conn:Disconnect()
			end
			if isLocal then
				luckValueLabel.Text = string.format("%.2fX", finalLuck) -- land exactly on the server value
			end
			local finalPos = Vector3.new(sim.FinalPosition.X, sim.FinalPosition.Y, sim.FinalPosition.Z)

			if isLocal then
				task.spawn(function()
					runRevealCutscene(finalPos, baitModel, payload)
				end)
			else
				task.delay(1.2, function()
					baitModel:Destroy()
				end)
			end
		end
	end)
end)

RunService.RenderStepped:Connect(function(dt: number)
	local near = checkNearThrowLine()
	local modalOpen = (localPlayer:GetAttribute("ModalOpen") :: boolean?) == true
	isAtThrowLine = near
	localPlayer:SetAttribute("NearThrowLine", near)

	if near and not modalOpen and not isThrowInFlight and not inRevealCutscene then
		CharacterAnimator.StartAimPose(localPlayer.Character)
		autoThrowButton.Visible = ownsAutoThrow
		meterRoot.Visible = true

		if ownsAutoThrow and autoThrowEnabled then
			-- Keep the 9-segment vertical meter VISIBLE while AUTO is active and smoothly lock the slider
			-- onto the exact server-peeked Green (Band 9 PERFECT!) or Light-Green (Band 8 GREAT!) segment!
			tapPromptLabel.Text = "AUTO-THROWING..."
			autoIdleClock += dt
			local delaySec = GameConfig.AutoThrow.IdleDelaySeconds
			local glideSec = math.max(0.05, delaySec * 0.72)
			local targetSeg = GameConfig.EvaluateMeterRatio(nextAutoMeterRatio)
			local targetVisualRatio = (targetSeg.Index - 0.5) / segCount
			local u = math.clamp(autoIdleClock / glideSec, 0, 1)
			local eased = 1 - ((1 - u) ^ 3)
			currentMeterRatio = 0.30 + (targetVisualRatio - 0.30) * eased

			local segDef = GameConfig.EvaluateMeterRatio(currentMeterRatio)
			local yScale = math.clamp(1 - currentMeterRatio, 0.04, 0.96)
			sliderBar.Position = UDim2.fromScale(0.5, yScale)
			sliderBonusLabel.Text = string.format("%s %.2fx", segDef.QualityLabel, segDef.LuckMultiplier)
			if segDef.Index ~= lastBandIndex then
				lastBandIndex = segDef.Index
				applyTone(sliderBonusLabel, UiKit.TriFromColor(SlimeFactory.ToColor3(segDef.Color)))
			end

			if autoIdleClock >= delaySec then
				autoIdleClock = 0
				triggerThrowFromMeter(true)
			end
		else
			tapPromptLabel.Text = defaultTapPromptText
			autoIdleClock = 0

			meterClock += dt
			currentMeterRatio = 0.5 - 0.5 * math.cos(meterClock * 4.4)
			local segDef = GameConfig.EvaluateMeterRatio(currentMeterRatio)

			-- Exact 1:1 alignment inside segmentsContainer (top = 0.0 -> Band 9 Green, bottom = 1.0 -> Band 1 Red)
			local yScale = math.clamp(1 - currentMeterRatio, 0.04, 0.96)
			sliderBar.Position = UDim2.fromScale(0.5, yScale)
			sliderBonusLabel.Text = string.format("%s %.2fx", segDef.QualityLabel, segDef.LuckMultiplier)
			if segDef.Index ~= lastBandIndex then
				lastBandIndex = segDef.Index
				applyTone(sliderBonusLabel, UiKit.TriFromColor(SlimeFactory.ToColor3(segDef.Color)))
			end
		end
	else
		meterRoot.Visible = false
		autoThrowButton.Visible = false
		autoIdleClock = 0
		if not isThrowInFlight then
			CharacterAnimator.StopAimPose()
		end
	end
end)
