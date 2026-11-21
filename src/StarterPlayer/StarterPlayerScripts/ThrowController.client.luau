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

local requestThrow = Remotes.GetEvent("RequestThrow")
local throwBroadcast = Remotes.GetEvent("ThrowBroadcast")

print("[ThrowController] loaded pitch-v3")

local isAtThrowLine = false
local isThrowInFlight = false
local isPitchAnimating = false -- true while the local avatar's pitch animation is still playing
local inRevealCutscene = false
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
addStroke(pillOuter, Color3.fromRGB(18, 20, 28), 3.5, Enum.ApplyStrokeMode.Border)

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
sliderBar.Parent = pillOuter
addCorner(sliderBar, 8)
addStroke(sliderBar, Color3.fromRGB(18, 20, 28), 2.8, Enum.ApplyStrokeMode.Border)

local sliderBonusLabel = Instance.new("TextLabel")
sliderBonusLabel.Name = "BonusLabel"
sliderBonusLabel.AnchorPoint = Vector2.new(0, 0.5)
sliderBonusLabel.Position = UDim2.new(1, 10, 0.5, 0)
sliderBonusLabel.Size = UDim2.fromOffset(80, 36)
sliderBonusLabel.BackgroundTransparency = 1
sliderBonusLabel.Font = Enum.Font.FredokaOne
sliderBonusLabel.TextSize = 28
sliderBonusLabel.TextXAlignment = Enum.TextXAlignment.Left
sliderBonusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
sliderBonusLabel.Text = "+11"
sliderBonusLabel.ZIndex = 6
sliderBonusLabel.Parent = sliderBar
addStroke(sliderBonusLabel, Color3.fromRGB(15, 18, 25), 2.8)

local tapPromptLabel = Instance.new("TextLabel")
tapPromptLabel.Name = "TapToThrowLabel"
tapPromptLabel.AnchorPoint = Vector2.new(0.5, 1)
tapPromptLabel.Position = UDim2.new(0.5, 0, 1, -6)
tapPromptLabel.Size = UDim2.fromOffset(270, 44)
tapPromptLabel.BackgroundTransparency = 1
tapPromptLabel.Font = Enum.Font.FredokaOne
tapPromptLabel.TextSize = 30
tapPromptLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
tapPromptLabel.Text = "TAP TO THROW!"
tapPromptLabel.Parent = meterRoot
addStroke(tapPromptLabel, Color3.fromRGB(15, 18, 25), 3.2)

-- ============================================================================
-- 2. MID-AIR FLIGHT HUD ("1.XXx LUCK" + ZONE BANNER)
-- ============================================================================
local flightHud = Instance.new("Frame")
flightHud.Name = "FlightHud"
flightHud.AnchorPoint = Vector2.new(0.5, 0)
flightHud.Position = UDim2.new(0.5, 0, 0, 18)
flightHud.Size = UDim2.fromOffset(360, 110)
flightHud.BackgroundTransparency = 1
flightHud.Visible = false
flightHud.Parent = throwGui

local luckValueLabel = Instance.new("TextLabel")
luckValueLabel.AnchorPoint = Vector2.new(0.5, 0)
luckValueLabel.Position = UDim2.fromScale(0.5, 0)
luckValueLabel.Size = UDim2.fromOffset(220, 38)
luckValueLabel.BackgroundTransparency = 1
luckValueLabel.Font = Enum.Font.FredokaOne
luckValueLabel.TextSize = 34
luckValueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
luckValueLabel.Text = "1.15X"
luckValueLabel.Parent = flightHud
addStroke(luckValueLabel, Color3.fromRGB(15, 18, 25), 3)

local luckSubLabel = Instance.new("TextLabel")
luckSubLabel.AnchorPoint = Vector2.new(0.5, 0)
luckSubLabel.Position = UDim2.new(0.5, 0, 0, 32)
luckSubLabel.Size = UDim2.fromOffset(140, 22)
luckSubLabel.BackgroundTransparency = 1
luckSubLabel.Font = Enum.Font.FredokaOne
luckSubLabel.TextSize = 18
luckSubLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
luckSubLabel.Text = "LUCK"
luckSubLabel.Parent = flightHud
addStroke(luckSubLabel, Color3.fromRGB(15, 18, 25), 2.2)

local zoneBanner = Instance.new("Frame")
zoneBanner.AnchorPoint = Vector2.new(0.5, 0)
zoneBanner.Position = UDim2.new(0.5, 0, 0, 62)
zoneBanner.Size = UDim2.fromOffset(310, 42)
zoneBanner.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
zoneBanner.BackgroundTransparency = 0.38
zoneBanner.BorderSizePixel = 0
zoneBanner.Parent = flightHud
addCorner(zoneBanner, 10)
addStroke(zoneBanner, Color3.fromRGB(15, 18, 25), 2, Enum.ApplyStrokeMode.Border)

local zoneBannerText = Instance.new("TextLabel")
zoneBannerText.Size = UDim2.fromScale(1, 1)
zoneBannerText.BackgroundTransparency = 1
zoneBannerText.Font = Enum.Font.FredokaOne
zoneBannerText.TextSize = 28
zoneBannerText.TextColor3 = Color3.fromRGB(120, 245, 105)
zoneBannerText.Text = "Meadow 🌿"
zoneBannerText.Parent = zoneBanner
addStroke(zoneBannerText, Color3.fromRGB(15, 20, 15), 2.5)

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
revealRoot.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
revealRoot.BackgroundTransparency = 0.65
revealRoot.Visible = false
revealRoot.ZIndex = 12
revealRoot.Parent = throwGui

local superLuckyLabel = Instance.new("TextLabel")
superLuckyLabel.AnchorPoint = Vector2.new(0.5, 0)
superLuckyLabel.Position = UDim2.new(0.5, 0, 0, 18)
superLuckyLabel.Size = UDim2.fromOffset(360, 44)
superLuckyLabel.BackgroundTransparency = 1
superLuckyLabel.Font = Enum.Font.FredokaOne
superLuckyLabel.TextSize = 36
superLuckyLabel.TextColor3 = Color3.fromRGB(255, 85, 110)
superLuckyLabel.Rotation = -4
superLuckyLabel.Text = "SUPER LUCKY!"
superLuckyLabel.Visible = false
superLuckyLabel.Parent = revealRoot
addStroke(superLuckyLabel, Color3.fromRGB(20, 10, 15), 3)

local oddsPill = Instance.new("Frame")
oddsPill.AnchorPoint = Vector2.new(0.5, 0)
oddsPill.Position = UDim2.new(0.5, 0, 0, 62)
oddsPill.Size = UDim2.fromOffset(186, 56)
oddsPill.BackgroundColor3 = Color3.fromRGB(45, 35, 20)
oddsPill.BackgroundTransparency = 0.22
oddsPill.Parent = revealRoot
addCorner(oddsPill, 28)
addStroke(oddsPill, Color3.fromRGB(95, 75, 40), 2, Enum.ApplyStrokeMode.Border)

local oddsLabel = Instance.new("TextLabel")
oddsLabel.Size = UDim2.fromScale(1, 1)
oddsLabel.BackgroundTransparency = 1
oddsLabel.Font = Enum.Font.FredokaOne
oddsLabel.TextSize = 36
oddsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
oddsLabel.Text = "1 in 1"
oddsLabel.Parent = oddsPill
addStroke(oddsLabel, Color3.fromRGB(15, 15, 20), 3)

local finalInfoFrame = Instance.new("Frame")
finalInfoFrame.AnchorPoint = Vector2.new(0.5, 1)
finalInfoFrame.Position = UDim2.new(0.5, 0, 1, -24)
finalInfoFrame.Size = UDim2.fromOffset(480, 185)
finalInfoFrame.BackgroundTransparency = 1
finalInfoFrame.Visible = false
finalInfoFrame.Parent = revealRoot

local mutationLabel = Instance.new("TextLabel")
mutationLabel.AnchorPoint = Vector2.new(0.5, 0)
mutationLabel.Position = UDim2.new(0.5, 0, 0, 0)
mutationLabel.Size = UDim2.fromOffset(300, 30)
mutationLabel.BackgroundTransparency = 1
mutationLabel.Font = Enum.Font.FredokaOne
mutationLabel.TextSize = 24
mutationLabel.TextColor3 = Color3.fromRGB(100, 255, 140)
mutationLabel.Text = "EMERALD"
mutationLabel.Parent = finalInfoFrame
addStroke(mutationLabel, Color3.fromRGB(15, 20, 15), 2.5)

local revealedNameLabel = Instance.new("TextLabel")
revealedNameLabel.AnchorPoint = Vector2.new(0.5, 0)
revealedNameLabel.Position = UDim2.new(0.5, 0, 0, 28)
revealedNameLabel.Size = UDim2.fromOffset(440, 58)
revealedNameLabel.BackgroundTransparency = 1
revealedNameLabel.Font = Enum.Font.FredokaOne
revealedNameLabel.TextSize = 52
revealedNameLabel.TextColor3 = Color3.fromRGB(115, 255, 130)
revealedNameLabel.Text = "HONEY"
revealedNameLabel.Parent = finalInfoFrame
addStroke(revealedNameLabel, Color3.fromRGB(15, 20, 15), 3.5)

local revealedIncomeLabel = Instance.new("TextLabel")
revealedIncomeLabel.AnchorPoint = Vector2.new(0.5, 0)
revealedIncomeLabel.Position = UDim2.new(0.5, 0, 0, 88)
revealedIncomeLabel.Size = UDim2.fromOffset(240, 38)
revealedIncomeLabel.BackgroundTransparency = 1
revealedIncomeLabel.Font = Enum.Font.FredokaOne
revealedIncomeLabel.TextSize = 32
revealedIncomeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
revealedIncomeLabel.Text = "$10/s"
revealedIncomeLabel.Parent = finalInfoFrame
addStroke(revealedIncomeLabel, Color3.fromRGB(15, 18, 25), 2.8)

local newBadge = Instance.new("Frame")
newBadge.AnchorPoint = Vector2.new(0, 0.5)
newBadge.Position = UDim2.new(0.5, 125, 0, 68)
newBadge.Size = UDim2.fromOffset(96, 44)
newBadge.BackgroundColor3 = Color3.fromRGB(255, 205, 55)
newBadge.Rotation = -12
newBadge.Parent = finalInfoFrame
addCorner(newBadge, 10)
addStroke(newBadge, Color3.fromRGB(25, 20, 10), 3, Enum.ApplyStrokeMode.Border)

local newBadgeText = Instance.new("TextLabel")
newBadgeText.Size = UDim2.fromScale(1, 1)
newBadgeText.BackgroundTransparency = 1
newBadgeText.Font = Enum.Font.FredokaOne
newBadgeText.TextSize = 26
newBadgeText.TextColor3 = Color3.fromRGB(255, 255, 255)
newBadgeText.Text = "NEW!"
newBadgeText.Parent = newBadge
addStroke(newBadgeText, Color3.fromRGB(25, 20, 10), 2.5)

local tapContinueLabel = Instance.new("TextLabel")
tapContinueLabel.AnchorPoint = Vector2.new(0.5, 1)
tapContinueLabel.Position = UDim2.new(0.5, 0, 1, 0)
tapContinueLabel.Size = UDim2.fromOffset(260, 26)
tapContinueLabel.BackgroundTransparency = 1
tapContinueLabel.Font = Enum.Font.FredokaOne
tapContinueLabel.TextSize = 18
tapContinueLabel.TextColor3 = Color3.fromRGB(220, 225, 235)
tapContinueLabel.TextTransparency = 0.25
tapContinueLabel.Text = "tap to continue"
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
	return nearZ and nearY
end

-- Bold golden "PERFECT! +20" pop above the throw meter when the slider stops in the top band
local function showPerfectCallout(bonusPower: number)
	local label = Instance.new("TextLabel")
	label.Name = "PerfectCallout"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.48, -200)
	label.Size = UDim2.fromOffset(420, 80)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 64
	label.TextColor3 = Color3.fromRGB(255, 215, 60)
	label.Text = `PERFECT! +{bonusPower}`
	label.Rotation = -6
	label.ZIndex = 15
	label.Parent = throwGui
	addStroke(label, Color3.fromRGB(60, 35, 5), 4)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.15 }):Play()
	task.delay(0.22, function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	task.delay(0.9, function()
		local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, fade, { TextTransparency = 1, Position = label.Position - UDim2.fromOffset(0, 30) }):Play()
		task.delay(0.4, function()
			label:Destroy()
		end)
	end)
end

local function triggerThrowFromMeter()
	if isThrowInFlight or inRevealCutscene then
		return
	end
	local now = os.clock()
	if now - lastThrowTime < 1.1 then
		return
	end
	lastThrowTime = now
	isThrowInFlight = true
	meterRoot.Visible = false

	local lockedRatio = currentMeterRatio
	local lockedSeg = GameConfig.EvaluateMeterRatio(lockedRatio)
	if lockedSeg.IsPerfect then
		showPerfectCallout(lockedSeg.BonusPower)
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
		})
	end, function()
		isPitchAnimating = false
		-- Pitch was cut short (e.g. character reset) before release: unlock the throw line again
		if not releaseSent then
			isThrowInFlight = false
			if cam then
				cam.CameraType = Enum.CameraType.Custom
			end
		end
	end)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if inRevealCutscene then
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.Space
		then
			revealTapSignal:Fire()
		end
		return
	end

	if gameProcessed then
		return
	end

	if
		isAtThrowLine
		and not isThrowInFlight
		and (
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.Space
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

local function runRevealCutscene(finalPos: Vector3, baitModel: Model, payload: any)
	inRevealCutscene = true
	localPlayer:SetAttribute("InRevealCutscene", true)
	flightHud.Visible = false

	TweenService:Create(fadeOverlay, TweenInfo.new(0.22), { BackgroundTransparency = 0 }):Play()
	task.wait(0.24)

	local floorY = ThrowPhysics.GetFloorYAtZ(math.max(0, finalPos.Z))
	local baitGroundPos = Vector3.new(finalPos.X + 1.5, floorY + 0.55, finalPos.Z)

	-- 6 waypoints (Emergence at 10.5 studs away + 5 slow hops right up to the thrown bait!)
	local hopWaypoints = {
		Vector3.new(finalPos.X - 9.0, floorY + 1.22, finalPos.Z - 1.4), -- 1. Emergence spot
		Vector3.new(finalPos.X - 7.1, floorY + 1.22, finalPos.Z - 1.1), -- 2. After Hop 1
		Vector3.new(finalPos.X - 5.3, floorY + 1.22, finalPos.Z - 0.8), -- 3. After Hop 2
		Vector3.new(finalPos.X - 3.7, floorY + 1.22, finalPos.Z - 0.5), -- 4. After Hop 3
		Vector3.new(finalPos.X - 2.3, floorY + 1.22, finalPos.Z - 0.3), -- 5. After Hop 4
		Vector3.new(finalPos.X - 1.1, floorY + 1.22, finalPos.Z - 0.1), -- 6. After Hop 5 (right beside the bait!)
	}

	SlimeFactory.PositionBait(baitModel, CFrame.new(baitGroundPos) * CFrame.Angles(0, math.rad(35), 0))

	local slimeId = payload.CaughtSlimeId or "meadow_sprout"
	local mutId = payload.CaughtMutation or "NORMAL"
	local slimeModel = SlimeFactory.CreateSlimeModel(slimeId, false, mutId, payload.CaughtIncomePerSec)
	SlimeFactory.SetSilhouetteMode(slimeModel, true)
	SlimeFactory.PositionSlime(
		slimeModel,
		CFrame.lookAt(
			Vector3.new(hopWaypoints[1].X, floorY - 2.7, hopWaypoints[1].Z),
			Vector3.new(baitGroundPos.X, floorY - 2.7, baitGroundPos.Z)
		),
		0
	)
	slimeModel.Parent = workspace

	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
		local camPos = Vector3.new(finalPos.X - 2.4, floorY + 3.6, finalPos.Z + 11.2)
		local lookTarget = Vector3.new(finalPos.X - 2.8, floorY + 1.1, finalPos.Z - 0.3)
		cam.CFrame = CFrame.lookAt(camPos, lookTarget)
	end

	local targetOdds = math.max(1, tonumber(payload.OddsOneInX) or 4)
	local shortWord = tostring(payload.CaughtShortWord or "SLIME")
	superLuckyLabel.Visible = false
	finalInfoFrame.Visible = false
	oddsLabel.Text = "1 in 1"
	revealRoot.Visible = true

	TweenService:Create(fadeOverlay, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()

	-- STAGE A: Longer (~1.70s) Slow Underground Peek & Pop-Out!
	animateLongerUndergroundEmergence(slimeModel, hopWaypoints[1], floorY, baitGroundPos)

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
				finalPos.X - 2.2 + step * 0.36,
				floorY + 3.5 - step * 0.08,
				finalPos.Z + 10.8 - step * 0.45
			)
			local targetLook = Vector3.new(finalPos.X - 2.4 + step * 0.38, floorY + 1.15, finalPos.Z)
			TweenService:Create(cam, TweenInfo.new(0.46, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				CFrame = CFrame.lookAt(targetCamPos, targetLook),
			}):Play()
		end

		animateSlowHopTowardBait(
			slimeModel,
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
		slimeModel,
		CFrame.lookAt(finalSlimePos + Vector3.new(0.35, 0, 0), baitGroundPos),
		-0.15
	)
	task.wait(0.32)

	-- STAGE C: EXPLOSIVE REVEAL right next to the bait!
	SlimeFactory.SetSilhouetteMode(slimeModel, false)
	if cam then
		SlimeFactory.PositionSlime(
			slimeModel,
			CFrame.lookAt(
				finalSlimePos + Vector3.new(0, 0.5, 0),
				Vector3.new(cam.CFrame.Position.X, finalSlimePos.Y, cam.CFrame.Position.Z)
			),
			-0.30
		)
		task.delay(0.15, function()
			if slimeModel.Parent and cam then
				SlimeFactory.PositionSlime(
					slimeModel,
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
	mutationLabel.TextColor3 = mutColor
	revealedNameLabel.Text = shortWord
	revealedNameLabel.TextColor3 = SlimeFactory.ToColor3(def.Color)
	revealedIncomeLabel.Text = `$${GameConfig.FormatNumber(payload.CaughtIncomePerSec or def.IncomePerSec)}/s`
	newBadge.Visible = (payload.IsNewDiscovery == true)
	finalInfoFrame.Visible = true

	-- Wait for "tap to continue" (or 3.0s timeout)
	local done = false
	local doneConn = revealTapSignal.Event:Connect(function()
		done = true
	end)
	local elapsed = 0
	while not done and elapsed < 3.0 do
		elapsed += task.wait(0.04)
	end
	doneConn:Disconnect()

	TweenService:Create(fadeOverlay, TweenInfo.new(0.22), { BackgroundTransparency = 0 }):Play()
	task.wait(0.24)

	revealRoot.Visible = false
	slimeModel:Destroy()
	baitModel:Destroy()

	if cam then
		cam.CameraType = Enum.CameraType.Custom
	end

	TweenService:Create(fadeOverlay, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	inRevealCutscene = false
	isThrowInFlight = false
	localPlayer:SetAttribute("InRevealCutscene", false)
end

throwBroadcast.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end

	local isLocal = (payload.PlayerUserId == localPlayer.UserId)

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

	local groundRing = Instance.new("Part")
	groundRing.Name = "BaitGroundRing"
	groundRing.Shape = Enum.PartType.Cylinder
	groundRing.Size = Vector3.new(0.2, 11, 11)
	groundRing.Material = Enum.Material.Neon
	groundRing.Color = Color3.fromRGB(245, 255, 240)
	groundRing.Transparency = 0.45
	groundRing.Anchored = true
	groundRing.CanCollide = false
	groundRing.CastShadow = false
	groundRing.Parent = workspace

	-- Live luck ticker: replays the server's GameConfig.ComputeFlightLuck as the bait flies, so the
	-- top-centre "1.XXx LUCK" climbs with distance and ends exactly on the server's LuckMultiplier.
	local meterLuck = tonumber(payload.MeterLuck) or tonumber(payload.LuckMultiplier) or 1.0
	local baitLuck = tonumber(payload.BaitLuck) or 1.0
	local finalLuck = tonumber(payload.LuckMultiplier) or 1.0
	local maxDistance = 0
	if isLocal then
		luckValueLabel.Text = string.format("%.2fX", GameConfig.ComputeFlightLuck(0, meterLuck, baitLuck))
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

			local floorY = ThrowPhysics.GetFloorYAtZ(math.max(0, pos.Z))
			groundRing.CFrame = CFrame.new(pos.X, floorY + 0.15, pos.Z) * CFrame.Angles(0, 0, math.rad(90))

			if isLocal then
				maxDistance = math.max(maxDistance, math.clamp(pos.Z, 0, GameConfig.Hub.LaneMaxZ))
				local liveLuck = math.min(finalLuck, GameConfig.ComputeFlightLuck(maxDistance, meterLuck, baitLuck))
				luckValueLabel.Text = string.format("%.2fX", liveLuck)
			end

			if isLocal and cam then
				local zoneDef = ThrowPhysics.GetZoneAtZ(math.max(0, pos.Z))
				zoneBannerText.Text = `{zoneDef.Name} {zoneDef.Emoji}`
				zoneBannerText.TextColor3 = SlimeFactory.ToColor3(zoneDef.ThemeColor)

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
			groundRing:Destroy()
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
	isAtThrowLine = near
	localPlayer:SetAttribute("NearThrowLine", near)

	if near and not isThrowInFlight and not inRevealCutscene then
		CharacterAnimator.StartAimPose(localPlayer.Character)
		meterRoot.Visible = true

		meterClock += dt
		currentMeterRatio = 0.5 - 0.5 * math.cos(meterClock * 4.4)
		local segDef = GameConfig.EvaluateMeterRatio(currentMeterRatio)

		local yScale = 0.94 - currentMeterRatio * 0.88
		sliderBar.Position = UDim2.fromScale(0.5, yScale)
		sliderBonusLabel.Text = `+{segDef.BonusPower}`
		sliderBonusLabel.TextColor3 = SlimeFactory.ToColor3(segDef.Color)
	else
		meterRoot.Visible = false
		if not isThrowInFlight then
			CharacterAnimator.StopAimPose()
		end
	end
end)
