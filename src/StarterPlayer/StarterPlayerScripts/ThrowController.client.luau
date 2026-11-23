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
local SlimeMotion = require(Shared:WaitForChild("SlimeMotion"))
local CatchFx = require(Shared:WaitForChild("CatchFx"))
local CatchFxData = require(Shared:WaitForChild("CatchFxData"))
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

-- "CAUGHT!" stamp that pops in when the slime floats up into the showcase (under the "1 in X" counter)
local CAUGHT_STAMP_Y = 100
local CAUGHT_STAMP_H = 72
local caughtStamp = Instance.new("TextLabel")
caughtStamp.Name = "CaughtStamp"
caughtStamp.AnchorPoint = Vector2.new(0.5, 0)
caughtStamp.Position = UDim2.new(0.5, 0, 0, CAUGHT_STAMP_Y)
caughtStamp.Size = UDim2.fromOffset(560, CAUGHT_STAMP_H)
caughtStamp.BackgroundTransparency = 1
caughtStamp.Font = Enum.Font.FredokaOne
caughtStamp.TextSize = 64
caughtStamp.TextColor3 = Color3.fromRGB(255, 255, 255)
caughtStamp.Rotation = -4
caughtStamp.Text = "CAUGHT!"
caughtStamp.Visible = false
caughtStamp.Parent = revealRoot
UiKit.ApplyTri(caughtStamp, UiKit.Gradients.Luck)
UiKit.AddTextStroke(caughtStamp)
local caughtStampScale = Instance.new("UIScale")
caughtStampScale.Parent = caughtStamp

local superLuckyLabel = Instance.new("TextLabel")
superLuckyLabel.AnchorPoint = Vector2.new(0.5, 0)
superLuckyLabel.Position = UDim2.new(0.5, 0, 0, CAUGHT_STAMP_Y + CAUGHT_STAMP_H + 4)
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
local finalInfoScale = Instance.new("UIScale") -- "name in" pop (UI-MOTION: 0 -> 1.15 -> 1)
finalInfoScale.Parent = finalInfoFrame

-- Full-screen white flash for Mythic catches (above the reveal content)
local flashFrame = Instance.new("Frame")
flashFrame.Name = "MythicFlash"
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.ZIndex = 19
flashFrame.Active = false
flashFrame.Parent = throwGui

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

-- Burst of zone-coloured dust (or sparkles for flyers) where the slime pops out of the ground
local function spawnEmergeDust(groundPosition: Vector3, color: Color3, sparkle: boolean)
	local anchor = Instance.new("Part")
	anchor.Name = "EmergeDust"
	anchor.Size = Vector3.new(2.5, 0.2, 2.5)
	anchor.CFrame = CFrame.new(groundPosition + Vector3.new(0, 0.2, 0))
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = if sparkle
		then "rbxasset://textures/particles/sparkles_main.dds"
		else "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color)
	emitter.LightEmission = if sparkle then 0.8 else 0.1
	emitter.Size = if sparkle
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 2.2) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.45, 0.85)
	emitter.Speed = NumberRange.new(5, 9)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Drag = 4
	emitter.Acceleration = if sparkle then Vector3.new(0, 2, 0) else Vector3.new(0, -6, 0)
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(18)

	task.delay(1.5, function()
		anchor:Destroy()
	end)
end

-- Catch cutscene walk: number of steps toward the bait, how far away the slime emerges, and step timing
-- (emerge ~1.7s + REVEAL_STEPS x (STEP + HOLD) + eat ~0.55s = ~7.4s)
local REVEAL_STEPS = 8
local REVEAL_EMERGE_DIST = 15
local REVEAL_STEP_TIME = 0.52
local REVEAL_STEP_HOLD = 0.12
local REVEAL_CAM_BIND = "SlimeRevealCam"
local REVEAL_SCREEN_FRACTION = 0.26 -- how much of the screen height the slime fills

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

-- Camera that keeps the slime horizontally centred and sitting right above the reveal name title
-- (finalInfoFrame), seen from the side (viewDir points from the slime toward the camera).
local function frameSlimeAboveTitle(
	cam: Camera,
	target: Vector3,
	slimeSize: number,
	viewDir: Vector3,
	exclude: { Instance },
	fovDeg: number? -- the FOV the framing is meant for (defaults to the camera's current FOV)
): (CFrame, number)
	local vh = math.max(1, cam.ViewportSize.Y)
	local tanHalf = math.tan(math.rad(fovDeg or cam.FieldOfView) * 0.5)
	local dist = math.clamp(slimeSize * 1.1 / (2 * REVEAL_SCREEN_FRACTION * tanHalf), 6, 16)
	local cf = safeRevealCamCFrame(target + viewDir * dist, target, exclude)

	-- Where the title starts on screen (it is laid out even while hidden); fallback = its design position
	local titleTop = finalInfoFrame.AbsolutePosition.Y
	if titleTop <= 0 then
		titleTop = vh - 294
	end
	local cy = math.clamp(titleTop - (REVEAL_SCREEN_FRACTION * 0.5) * vh - 16, 0.32 * vh, 0.62 * vh)
	local ndcY = cy / vh * 2 - 1 -- > 0 = below the screen centre
	-- Pitching the camera up by this angle moves the slime down the screen to cy
	return cf * CFrame.Angles(math.atan(ndcY * tanHalf), 0, 0), cy
end

-- Rarity tiers for how loud the catch highlight is (UI-MOTION: rays Rare+, shake Epic+, flash Mythic)
local RARITY_TIER: { [string]: number } = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }

-- Glow + rotating sunburst rays behind the showcased slime, a pulsing light on it and a sparkle burst.
-- Everything is parented to the slime model, so it is cleaned up when the slime is destroyed.
local function spawnCatchHighlight(model: Model, pos: Vector3, cam: Camera, color: Color3, tier: number)
	local baseSize = (model:GetAttribute("BaseSize") :: number?) or 2.4

	-- Anchor sits behind the slime (away from the camera) so the depth-tested billboard stays behind it
	local away = pos - cam.CFrame.Position
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 0, 1)
	local anchor = Instance.new("Part")
	anchor.Name = "CatchFx"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.CFrame = CFrame.new(pos + away * (baseSize * 1.6))
	anchor.Parent = model

	local bb = Instance.new("BillboardGui")
	bb.Name = "CatchRays"
	bb.Size = UDim2.fromScale(baseSize * 4.5, baseSize * 4.5) -- scale = studs
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Adornee = anchor
	bb.Parent = anchor

	local function addImage(image: string, transparency: number, z: number): ImageLabel
		local img = Instance.new("ImageLabel")
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.Image = image
		img.ImageColor3 = color
		img.ImageTransparency = 1
		img.ZIndex = z
		img.Parent = bb
		TweenService:Create(img, TweenInfo.new(0.25), { ImageTransparency = transparency }):Play()
		return img
	end

	local glow = addImage(UiAssets.Textures.glow, 0.35, 1)
	glow.Size = UDim2.fromScale(0.8, 0.8)
	if tier >= 3 then
		local rays = addImage(UiAssets.Textures.sunburst, 0.55, 2)
		TweenService:Create(rays, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), {
			Rotation = 360,
		}):Play()
	end
	if tier >= 5 then
		local rays2 = addImage(UiAssets.Textures.sunburst, 0.7, 3)
		rays2.Size = UDim2.fromScale(0.75, 0.75)
		rays2.Rotation = 22
		TweenService:Create(rays2, TweenInfo.new(11, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), {
			Rotation = 22 - 360,
		}):Play()
	end

	local root = model.PrimaryPart
	if root then
		local light = Instance.new("PointLight")
		light.Name = "CatchLight"
		light.Color = color
		light.Range = 14
		light.Brightness = 0
		light.Parent = root
		TweenService:Create(light, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = 4,
		}):Play()
		task.delay(0.2, function()
			if light.Parent then
				TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 1.5 }):Play()
			end
		end)
	end

	spawnEmergeDust(pos - Vector3.new(0, baseSize * 0.3, 0), color, true)
end

-- Pop a UIScale from 0 to `peak` and back to 1 (Back Out), like the motion spec's "name in"
local function popScale(scale: UIScale, peak: number, duration: number)
	scale.Scale = 0
	local up = TweenService:Create(scale, TweenInfo.new(duration * 0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = peak,
	})
	up.Completed:Connect(function()
		TweenService:Create(scale, TweenInfo.new(duration * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end)
	up:Play()
end

local function runRevealCutscene(finalPos: Vector3, baitModel: Model, payload: any)
	inRevealCutscene = true
	localPlayer:SetAttribute("InRevealCutscene", true)
	flightHud.Visible = false

	local slimeModel: Model? = nil
	local cam = workspace.CurrentCamera
	local baseFov = if cam then cam.FieldOfView else 70 -- restored in the teardown (the shot director changes it)
	local showcaseActive = false -- keeps the hovering showcase loop (SlimeMotion.Showcase) running

	local ok, err = pcall(function()
		TweenService:Create(fadeOverlay, TweenInfo.new(0.22), { BackgroundTransparency = 0 }):Play()
		task.wait(0.24)

		local landedZone = ThrowPhysics.GetZoneAtZ(math.max(0, finalPos.Z))
		local floorY = landedZone.FloorY
		-- Clamp staging strictly inside the open lane corridor and away from cliff walls
		-- (the emerge spot is REVEAL_EMERGE_DIST studs to the -X side of the bait, so keep that much room)
		local stageX = math.clamp(
			finalPos.X,
			-(landedZone.ClearHalfWidth - (REVEAL_EMERGE_DIST + 2)),
			landedZone.ClearHalfWidth - 4
		)
		local stageZ = math.clamp(finalPos.Z, landedZone.StartZ + 3.0, landedZone.EndZ - 3.0)
		-- If near the far cliff edge of a zone (or Zone 5 end wall), flip camera to the open -Z side!
		local camSideZ = if stageZ > landedZone.EndZ - 14.0 then -1 else 1
		local emergeDz = if camSideZ > 0 then -1 else 1

		local baitGroundPos = Vector3.new(stageX + 1.5, floorY + 0.55, stageZ)

		-- REVEAL_STEPS + 1 waypoints: emerge ~15 studs away, then steps that get shorter as it creeps up on
		-- the bait, along a gentle curve. hopWaypoints[1] = emerge spot, hopWaypoints[REVEAL_STEPS + 1] = beside the bait.
		local hopWaypoints: { Vector3 } = {}
		for i = 0, REVEAL_STEPS do
			local a = i / REVEAL_STEPS
			local e = 1 - (1 - a) ^ 1.4
			local x = (stageX - REVEAL_EMERGE_DIST) + ((stageX - 1.1) - (stageX - REVEAL_EMERGE_DIST)) * e
			local zOff = (2.0 + (0.1 - 2.0) * e) + 1.0 * math.sin(a * math.pi)
			table.insert(hopWaypoints, Vector3.new(x, floorY + 1.22, stageZ + zOff * emergeDz))
		end

		SlimeFactory.PositionBait(baitModel, CFrame.new(baitGroundPos) * CFrame.Angles(0, math.rad(35), 0))

		local slimeId = payload.CaughtSlimeId or "meadow_sprout"
		local mutId = payload.CaughtMutation or "NORMAL"
		local def = GameConfig.SlimesById[slimeId] or GameConfig.Slimes[1]
		local tier = RARITY_TIER[def.Rarity] or 1
		local createdSlime = SlimeFactory.CreateSlimeModel(slimeId, false, mutId, payload.CaughtIncomePerSec)
		slimeModel = createdSlime
		-- Slimes the player already discovered are shown in full colour the whole time; only new ones start
		-- as a black silhouette that clears up as they get closer to the bait.
		local isNew = payload.IsNewDiscovery == true
		-- New discoveries and Rare+ get the full exaggerated show; repeat Common/Uncommon catches the lite one
		local full = isNew or tier >= CatchFxData.FullShowMinTier
		if isNew then
			SlimeFactory.BeginWorldSilhouette(createdSlime)
		end
		local rig = SlimeMotion.NewRig(createdSlime, SlimeMotion.GetStyle(slimeId))
		-- Face personality (CatchFxData.Personality): sleepy slimes blink slowly, happy ones bounce on the float-up
		local personality = CatchFx.GetPersonality(createdSlime)
		if personality == "Sleepy" then
			rig.BlinkTime = 0.32
		elseif personality == "Happy" then
			rig.Bouncy = true
		end
		local fx: SlimeMotion.Fx = {
			Color = SlimeFactory.ToColor3(landedZone.ThemeColor),
			Ripple = spawnGroundRipple,
			Dust = spawnEmergeDust,
			Landed = CatchFx.Landed,
		}
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

		-- SHOT DIRECTOR: the camera works through a shot list (CatchFxData.Shots) - establishing wide shot,
		-- ground-level close-up, side tracking, over-the-bait, close-up, then the showcase framing above the
		-- name title. The same per-frame step clears the silhouette as the slime closes in on the bait.
		local restY = floorY + 1.22
		local emergeSpot = hopWaypoints[1]
		local walkDist = math.max(1, (Vector3.new(emergeSpot.X, 0, emergeSpot.Z) - Vector3.new(baitGroundPos.X, 0, baitGroundPos.Z)).Magnitude)
		local slimeSize = (createdSlime:GetAttribute("BaseSize") :: number?) or 2.4
		local viewDir = Vector3.new(0.25, 0.32, camSideZ).Unit
		local camTarget = Vector3.new(emergeSpot.X, restY, emergeSpot.Z)
		local camSnapped = false
		local revealStarted = false -- stops the gradual silhouette so it does not fight the reveal fade
		-- Showcase: the camera freezes (so the float-up shows on screen) and can shake on big catches
		local camLocked = false
		local lockedCf = CFrame.identity
		local shakeUntil = 0
		local shakeLength = 0.3
		local walkCy = 0 -- screen Y (px) the walk framing keeps the slime at
		if cam then
			cam.CameraType = Enum.CameraType.Scriptable
		end

		-- Zone screen mood + per-slime effects (CatchFxData). DebugForceZoneFx (Studio only) swaps the zone look.
		local fxZone = landedZone.Index
		if RunService:IsStudio() then
			local forced = ReplicatedStorage:GetAttribute("DebugForceZoneFx")
			if type(forced) == "number" and forced >= 1 and forced <= #GameConfig.Zones then
				fxZone = math.floor(forced)
			end
		end
		local stageCenter = (hopWaypoints[1] + hopWaypoints[REVEAL_STEPS + 1]) * 0.5
		local zonePreset = CatchFxData.Zones[fxZone] or CatchFxData.Zones[1]
		if cam then
			CatchFx.Start({
				Model = createdSlime,
				SlimeId = slimeId,
				ZoneIndex = fxZone,
				StageCenter = stageCenter,
				FloorY = floorY,
				Camera = cam,
				RevealRoot = revealRoot,
				Shake = function(seconds: number)
					shakeLength = math.max(0.05, seconds)
					shakeUntil = os.clock() + shakeLength
				end,
				Full = full,
				EmergePos = Vector3.new(emergeSpot.X, floorY, emergeSpot.Z),
				BaitPos = baitGroundPos,
				ViewDir = viewDir,
			})
			if not isNew then
				CatchFx.BeginWalk() -- known slimes are visible from the start
			end
		end

		-- Shot parameters: CatchFxData.Shots[kind] with the zone's overrides on top
		local function shotParams(kind: string): { [string]: number }
			local merged: { [string]: number } = {}
			for k, v in (CatchFxData.Shots :: any)[kind] or {} do
				merged[k] = v
			end
			local overrides = zonePreset.Shots and zonePreset.Shots[kind]
			if overrides then
				for k, v in overrides do
					merged[k] = v
				end
			end
			return merged
		end

		local flatView = Vector3.new(viewDir.X, 0, viewDir.Z).Unit
		local walkRight = Vector3.new(baitGroundPos.X - emergeSpot.X, 0, baitGroundPos.Z - emergeSpot.Z)
		walkRight = if walkRight.Magnitude > 0.01 then walkRight.Unit else Vector3.new(1, 0, 0)
		local shotKind = if full then "Establish" else "Track"
		local shotT0 = os.clock()
		local shotBlend = 0
		local shotCut = true
		local camBase = if cam then cam.CFrame else CFrame.identity
		local curFov = baseFov
		local punchKind = ""
		local punchT0 = -1

		local function setShot(kind: string, blend: number)
			shotKind = kind
			shotT0 = os.clock()
			shotBlend = blend
			if blend <= 0 then
				shotCut = true
			end
		end
		-- FOV punches: "Burst" (pull in, then kick out wide) and "Hero" (wide, settling back)
		local function punch(kind: string)
			punchKind = kind
			punchT0 = os.clock()
		end
		local function punchOffset(): number
			if punchT0 < 0 then
				return 0
			end
			local t = os.clock() - punchT0
			if punchKind == "Burst" then
				if t < 0.1 then
					return -8 * (t / 0.1)
				elseif t < 0.25 then
					return -8 + 18 * ((t - 0.1) / 0.15)
				elseif t < 0.8 then
					return 10 * (1 - (t - 0.25) / 0.55)
				end
				return 0
			end
			if t < 0.9 then
				return 12 * (1 - t / 0.9) ^ 2
			end
			return 0
		end
		local function shakeOffset(): CFrame
			local left = shakeUntil - os.clock()
			if left <= 0 then
				return CFrame.identity
			end
			local k = 0.3 * (left / shakeLength)
			return CFrame.new((math.random() * 2 - 1) * k, (math.random() * 2 - 1) * k, 0)
		end
		local function withDutch(cf: CFrame, deg: number?): CFrame
			return if deg and deg ~= 0 then cf * CFrame.Angles(0, 0, math.rad(deg)) else cf
		end

		-- Where the current shot wants the camera (and its FOV)
		local function shotGoal(c: Camera, t: number): (CFrame, number)
			local prm = shotParams(shotKind)
			if shotKind == "Establish" then
				local focus = CatchFx.GetFocus() or stageCenter
				local mid = (focus + stageCenter) * 0.5
				local back = (prm.Back or 22) * (1 - (prm.Push or 0) * math.clamp(t / 0.9, 0, 1))
				local pos = mid + flatView * back + Vector3.new(0, prm.Up or 10, 0)
				return safeRevealCamCFrame(pos, mid, rayExclude), prm.Fov or 60
			elseif shotKind == "Ground" then
				local spot = Vector3.new(emergeSpot.X, floorY, emergeSpot.Z)
				local pos = spot + flatView * (prm.Back or 5) - walkRight * (prm.Side or 1.5) + Vector3.new(0, prm.Up or 0.7, 0)
				local look = Vector3.new(spot.X, math.max(floorY + 1, camTarget.Y), spot.Z)
				return withDutch(safeRevealCamCFrame(pos, look, rayExclude), prm.Dutch), prm.Fov or 55
			elseif shotKind == "Front" then
				local toBait = Vector3.new(baitGroundPos.X - camTarget.X, 0, baitGroundPos.Z - camTarget.Z)
				toBait = if toBait.Magnitude > 0.01 then toBait.Unit else walkRight
				local pos = Vector3.new(baitGroundPos.X, floorY, baitGroundPos.Z)
					+ toBait * (prm.Back or 3.6)
					+ flatView * (prm.Side or 0.9)
					+ Vector3.new(0, prm.Up or 1.3, 0)
				return withDutch(safeRevealCamCFrame(pos, camTarget + Vector3.new(0, 0.3, 0), rayExclude), prm.Dutch), prm.Fov or 62
			elseif shotKind == "Close" then
				-- Zoom-out: fast whoosh back, then settle (Push still works as a negative pull)
				local k = math.clamp(t / (prm.PullTime or 0.7), 0, 1)
				local eased = 1 - (1 - k) ^ 3
				local pull = (prm.Pull or 0) - (prm.Push or 0)
				local back = (prm.Back or 6) * (1 + pull * eased)
				local pos = camTarget + viewDir * back + Vector3.new(0, prm.Up or 1.8, 0)
				return safeRevealCamCFrame(pos, camTarget + Vector3.new(0, 0.2, 0), rayExclude), prm.Fov or 60
			end
			-- Track / AboveTitle: keep the slime centred above the name title
			local goal, cy = frameSlimeAboveTitle(c, camTarget, slimeSize, viewDir, rayExclude, baseFov)
			walkCy = cy
			local sway = if shotKind == "Track" then (prm.Sway or 0) else 0
			if sway > 0 then
				goal = goal * CFrame.new(math.sin(t * 1.3) * sway, math.sin(t * 1.9) * sway * 0.6, 0)
			end
			return goal, baseFov
		end

		RunService:BindToRenderStep(REVEAL_CAM_BIND, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
			CatchFx.Update(dt)
			if camLocked then
				if cam then
					camBase = camBase:Lerp(lockedCf, 1 - math.exp(-dt * 10))
					cam.CFrame = camBase * shakeOffset()
					cam.FieldOfView = baseFov + punchOffset() + CatchFx.GetFovOffset()
				end
				return
			end
			local root = createdSlime.PrimaryPart
			if not root or not createdSlime.Parent then
				return
			end
			local p = root.Position
			-- Never aim below the ground line (the slime starts buried); smooth Y harder so flyer bobs stay calm
			local want = Vector3.new(p.X, math.max(p.Y, restY), p.Z)
			local a = 1 - math.exp(-dt * 6)
			local ay = 1 - math.exp(-dt * 3)
			camTarget = Vector3.new(
				camTarget.X + (want.X - camTarget.X) * a,
				camTarget.Y + (want.Y - camTarget.Y) * ay,
				camTarget.Z + (want.Z - camTarget.Z) * a
			)
			if cam then
				local goal, goalFov = shotGoal(cam, os.clock() - shotT0)
				if shotCut or not camSnapped then
					camBase = goal
					curFov = goalFov
					shotCut = false
					camSnapped = true
				else
					local k = if shotBlend > 0 then 3 / shotBlend else 8
					local b = 1 - math.exp(-dt * k)
					camBase = camBase:Lerp(goal, b)
					curFov += (goalFov - curFov) * b
				end
				cam.CFrame = camBase * shakeOffset()
				cam.FieldOfView = curFov + punchOffset() + CatchFx.GetFovOffset()
			end

			if isNew and not revealStarted and createdSlime:FindFirstChild("RevealShade") then
				local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(baitGroundPos.X, 0, baitGroundPos.Z)).Magnitude
				local progress = math.clamp(1 - d / walkDist, 0, 1)
				local s = progress * progress * (3 - 2 * progress)
				SlimeFactory.SetSilhouetteAmount(createdSlime, 1 - 0.8 * s)
				-- its own effects (spinning halo, glowing caps...) switch on once it is half visible
				if progress >= 0.45 then
					CatchFx.BeginWalk()
				end
			end
		end)

		local targetOdds = math.max(1, tonumber(payload.OddsOneInX) or 4)
		local shortWord = tostring(payload.CaughtShortWord or "SLIME")
		superLuckyLabel.Visible = false
		caughtStamp.Visible = false
		finalInfoFrame.Visible = false
		finalInfoScale.Scale = 1
		oddsLabel.Text = "1 in 1"
		revealRoot.Visible = true

		-- Full show: the zone's intro prop (snow mound, lava pool, gift box...) is in place before the fade-in
		if full then
			CatchFx.IntroBuild()
		end

		TweenService:Create(fadeOverlay, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()

		if full then
			-- SHOT 1 (0.9s): wide establishing shot over the stage and the zone set piece (volcano, blizzard...)
			task.wait(0.9)
			-- SHOT 2: hard cut to ground level; the slime struggles out of the prop, SHOT 3 punches on the burst
			setShot("Ground", 0)
			fx.PropShake = CatchFx.IntroShake
			fx.Burst = function()
				CatchFx.IntroBurst()
				punch("Burst")
				shakeLength = 0.25
				shakeUntil = os.clock() + shakeLength
			end
			local style = (zonePreset.Emerge or "Burrow") :: SlimeMotion.EmergeStyle
			SlimeMotion.EmergeStruggle(rig, hopWaypoints[1], floorY, baitGroundPos, fx, style)
			-- SHOT 4: blend out to the side tracking shot for the walk
			setShot("Track", 0.35)
		else
			-- Lite show: today's burrow pop-out with the side tracking shot
			SlimeMotion.Emerge(rig, hopWaypoints[1], floorY, baitGroundPos, fx)
		end

		-- STAGE B (~5.1s): REVEAL_STEPS steps toward the bait in the slime's own style (hop / fly / slide / waddle);
		-- the "1 in X" counter climbs along the same curve as before
		for step = 1, REVEAL_STEPS do
			local odds = math.max(1, math.floor(targetOdds * 0.88 * (step / REVEAL_STEPS) ^ 1.25))
			oddsLabel.Text = `1 in {odds}`
			if full then
				-- SHOT 5: cut behind the bait as it creeps toward the camera; SHOT 6: tight close-up for the last step
				if step == CatchFxData.ShotBeats.Front then
					setShot("Front", 0)
				elseif step == CatchFxData.ShotBeats.Close then
					setShot("Close", 0)
				end
			end
			SlimeMotion.Approach(
				rig,
				hopWaypoints[step],
				hopWaypoints[step + 1],
				baitGroundPos,
				REVEAL_STEP_TIME,
				step,
				fx
			)
			SlimeMotion.Hold(rig, REVEAL_STEP_HOLD)
		end

		-- Eat the bait (~0.55s): lean in, gulp, bounce (flyers land first). SHOT 7: the camera blends to the
		-- showcase framing above the name title meanwhile.
		setShot("AboveTitle", if full then 0.4 else 0.25)
		local finalSlimePos = hopWaypoints[REVEAL_STEPS + 1]
		SlimeMotion.EatBait(rig, baitModel, finalSlimePos, baitGroundPos)

		-- STAGE C: CATCH SHOWCASE. The camera freezes and the slime floats up (spinning) into the middle of the
		-- screen, right above the name title. New slimes burst from silhouette into colour on the way up.
		local mutColor = if mutId ~= "NORMAL"
			then SlimeFactory.GetMutationColor(mutId)
			else SlimeFactory.GetRarityColor(def.Rarity)

		oddsLabel.Text = `1 in {targetOdds}`
		superLuckyLabel.Visible = (payload.IsSuperLucky == true)

		revealStarted = true
		if isNew then
			SlimeFactory.RevealFromSilhouette(createdSlime, 0.35)
		end

		local rise = 1.6
		local faceCam = finalSlimePos + viewDir * 10
		if cam then
			-- Lock on the exact showcase framing (the camera finishes blending there while the slime floats)
			local goal, cy = frameSlimeAboveTitle(cam, camTarget, slimeSize, viewDir, rayExclude, baseFov)
			lockedCf = goal
			walkCy = cy
			camLocked = true
			if full then
				punch("Hero")
			end
			faceCam = lockedCf.Position
			-- How far to float so the slime ends ~70 px above the name title, below "CAUGHT!" / SUPER LUCKY
			local vh = math.max(1, cam.ViewportSize.Y)
			local tanHalf = math.tan(math.rad(baseFov) * 0.5)
			local camDist = math.max(1, (lockedCf.Position - finalSlimePos).Magnitude)
			local pxPerStud = vh / (2 * camDist * tanHalf)
			local halfSlimePx = slimeSize * 1.08 * 0.5 * pxPerStud
			local titleTop = finalInfoFrame.AbsolutePosition.Y
			if titleTop <= 0 then
				titleTop = vh - 294
			end
			local labelsBottom = CAUGHT_STAMP_Y + CAUGHT_STAMP_H + (if superLuckyLabel.Visible then 60 else 0)
			local cyShow = math.max(titleTop - halfSlimePx - 70, labelsBottom + halfSlimePx + 8)
			cyShow = math.min(cyShow, walkCy)
			rise = math.clamp((walkCy - cyShow) / pxPerStud, 0.6, 4)
		end
		local topPos = finalSlimePos + Vector3.new(0, rise, 0)
		SlimeMotion.FloatUp(rig, finalSlimePos, topPos, faceCam, 0.7)

		-- Hover in place until the player continues
		showcaseActive = true
		task.spawn(SlimeMotion.Showcase, rig, topPos, faceCam, function()
			return showcaseActive
		end)

		-- Highlight the catch: glow / rays / light / sparkles, rings, CAUGHT! stamp, rarity shake + Mythic flash
		if cam then
			spawnCatchHighlight(createdSlime, topPos, cam, mutColor, tier)
		end
		CatchFx.Showcase() -- zone burst + personality + the slime's signature moment
		playShockwaveRings()
		caughtStamp.Visible = true
		popScale(caughtStampScale, 1.25, 0.35)
		if tier >= 4 then
			shakeLength = if tier >= 6 then 0.6 else 0.3
			shakeUntil = os.clock() + shakeLength
		end
		if tier >= 6 then
			flashFrame.BackgroundTransparency = 0
			TweenService:Create(flashFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
			}):Play()
		end

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
		popScale(finalInfoScale, 1.15, 0.35)

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
		showcaseActive = false
	end)

	if not ok then
		warn("[ThrowController] reveal cutscene error:", err)
	end

	-- Guaranteed teardown so fadeOverlay never sticks as a black screen
	pcall(function()
		RunService:UnbindFromRenderStep(REVEAL_CAM_BIND)
	end)
	pcall(CatchFx.Stop)
	if cam then
		cam.FieldOfView = baseFov
	end
	showcaseActive = false
	flashFrame.BackgroundTransparency = 1
	caughtStamp.Visible = false
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
