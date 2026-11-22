--!strict
--[[
	TrainingController.client.luau
	Client side of the looping pull-up. The server owns the rep cadence and holds the
	character under the bar (PlotService); this script only:
	  - plays CharacterAnimator's exaggerated pull-up loop at the server's rep interval and
	    phase-locks it so every paid rep lands on the chin-over-bar peak,
	  - frames a fixed FRONT camera while training, with a shake + FOV punch on every rep
	    (player attribute ReduceCameraShake = true turns the shake/punch off),
	  - fires light per-rep effects (dust puff + ring at the bar, sweat, bigger "+X XP" pop),
	  - shows the Strength level + Training XP bar, a LEVEL UP popup, and the server-offered
	    "BONUS REP!" pop-up buttons (click within the window for 3x XP),
	  - asks the server to stop when the player jumps or tries to walk,
	  - flips the bar prompt text between "Start Training" / "Stop Training" (local only).
	Tuning lives in GameConfig.PullUp.Camera / GameConfig.PullUp.Anim.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterAnimator = require(Shared:WaitForChild("CharacterAnimator"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PullUpMotion = require(Shared:WaitForChild("PullUpMotion"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UiAssets = require(Shared:WaitForChild("UiAssets"))
local UiKit = require(Shared:WaitForChild("UiKit"))
local UiLayout = require(Shared:WaitForChild("UiLayout"))

local trainingState = Remotes.GetEvent("TrainingState")
local trainingRep = Remotes.GetEvent("TrainingRep")
local trainingBonus = Remotes.GetEvent("TrainingBonus")
local requestStopTraining = Remotes.GetEvent("RequestStopTraining")
local requestBonusRep = Remotes.GetEvent("RequestBonusRep")

local playerGui = localPlayer:WaitForChild("PlayerGui")

local CAM = GameConfig.PullUp.Camera
local CAMERA_RENDER_STEP = "TrainingFrontCamera"
local CAMERA_BLEND_IN = 0.35 -- seconds to swing from the normal camera into the front shot

local isTraining = false
local stopRequested = false
local walkStopArmed = false
local currentInterval = GameConfig.PullUp.BaseRepSeconds

local function getOwnBar(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	local bases = hub and hub:FindFirstChild("PlayerBases")
	if not bases then
		return nil
	end
	local plotId = localPlayer:GetAttribute("PlotId")
	local uidStr = tostring(localPlayer.UserId)
	for _, plot in bases:GetChildren() do
		if plot:GetAttribute("Owner") == uidStr or (plotId ~= nil and plot:GetAttribute("PlotId") == plotId) then
			local pullUp = plot:FindFirstChild("PullUpBar")
			local bar = pullUp and pullUp:FindFirstChild("Bar")
			return if bar and bar:IsA("BasePart") then bar else nil
		end
	end
	return nil
end

-- Hide the Upgrade Bar prompt on other players' plots locally so only your own bar shows E
local function refreshBarPromptVisibility()
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	local bases = hub and hub:FindFirstChild("PlayerBases")
	if not bases then
		return
	end
	local plotId = localPlayer:GetAttribute("PlotId")
	local uidStr = tostring(localPlayer.UserId)
	for _, plot in bases:GetChildren() do
		local isOwn = plot:GetAttribute("Owner") == uidStr or (plotId ~= nil and plot:GetAttribute("PlotId") == plotId)
		if not isOwn then
			local pullUp = plot:FindFirstChild("PullUpBar")
			local bar = pullUp and pullUp:FindFirstChild("Bar")
			local prompt = bar and bar:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = false
			end
		end
	end
end

local function getRoot(): BasePart?
	local char = localPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function shakeReduced(): boolean
	return localPlayer:GetAttribute("ReduceCameraShake") == true
end

-- ============================================================================
-- FRONT CAMERA + SHAKE
-- ============================================================================
local camActive = false
local savedCameraType: Enum.CameraType = Enum.CameraType.Custom
local savedFov = 70
local blendFromCf = CFrame.identity
local camStartClock = 0
local trauma = 0
local punch = 0
local noiseSeed = 0
local lastCamClock = os.clock()

local function getFrontShot(root: BasePart): CFrame
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)

	local focus = root.Position + Vector3.new(0, CAM.FocusHeight, 0)
	local desired = root.Position + flat * CAM.Distance + Vector3.new(0, CAM.HeightOffset, 0)

	-- Occlusion: pull the camera in instead of clipping behind walls / plot structures
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localPlayer.Character :: Instance }
	local dir = desired - focus
	local hit = workspace:Raycast(focus, dir, params)
	if hit then
		local dist = math.max(CAM.MinDistance, (hit.Position - focus).Magnitude - 0.5)
		desired = focus + dir.Unit * dist
	end
	return CFrame.lookAt(desired, focus)
end

local function updateCamera()
	local cam = workspace.CurrentCamera
	local root = getRoot()
	if not cam or not root then
		return
	end
	local now = os.clock()
	local dt = math.min(now - lastCamClock, 0.1)
	lastCamClock = now

	local target = getFrontShot(root)
	local blend = math.clamp((now - camStartClock) / CAMERA_BLEND_IN, 0, 1)
	local cf = if blend < 1 then blendFromCf:Lerp(target, 1 - (1 - blend) ^ 3) else target

	trauma = math.max(0, trauma - CAM.ShakeDecay * dt)
	punch = math.max(0, punch - dt / CAM.FovPunchTime)

	if not shakeReduced() then
		local s = trauma * trauma
		if s > 0 then
			local t = now * CAM.ShakeFrequency
			local function n(offset: number): number
				return math.noise(noiseSeed + offset, t) * 2 -- math.noise is roughly [-0.5, 0.5]
			end
			local pos = Vector3.new(n(0), n(11), n(23)) * (CAM.ShakePosition * s)
			local rot = math.rad(CAM.ShakeRotation * s)
			cf = cf * CFrame.new(pos) * CFrame.Angles(n(37) * rot, n(51) * rot, n(67) * rot)
		end
		cam.FieldOfView = CAM.FieldOfView - CAM.FovPunch * (1 - (1 - punch) ^ 2)
	else
		cam.FieldOfView = CAM.FieldOfView
	end
	cam.CFrame = cf
end

local function startCamera()
	local cam = workspace.CurrentCamera
	if camActive or not cam then
		return
	end
	camActive = true
	savedCameraType = cam.CameraType
	savedFov = cam.FieldOfView
	blendFromCf = cam.CFrame
	camStartClock = os.clock()
	lastCamClock = camStartClock
	trauma = 0
	punch = 0
	noiseSeed = math.random() * 1000
	cam.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(CAMERA_RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, updateCamera)
end

local function stopCamera()
	if not camActive then
		return
	end
	camActive = false
	RunService:UnbindFromRenderStep(CAMERA_RENDER_STEP)
	local cam = workspace.CurrentCamera
	if cam then
		cam.FieldOfView = savedFov
		-- Never hand back a Scriptable camera (e.g. if training started during a cutscene)
		cam.CameraType = if savedCameraType == Enum.CameraType.Scriptable
			then Enum.CameraType.Custom
			else savedCameraType
	end
end

local function kickCamera(intensity: number)
	trauma = math.min(1, trauma + CAM.ShakeTrauma * intensity)
	punch = 1
end

-- ============================================================================
-- LIGHT PER-REP EFFECTS (all local, scale with intensity)
-- ============================================================================
local fxInstances: { Instance } = {}
local dustEmitter: ParticleEmitter? = nil
local sweatEmitter: ParticleEmitter? = nil

local function makeEmitter(parent: Attachment, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0 -- only bursts via :Emit()
	e.LightEmission = 0.2
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function startFx()
	local bar = getOwnBar()
	if bar then
		local att = Instance.new("Attachment")
		att.Name = "TrainingDustFx"
		att.Parent = bar
		table.insert(fxInstances, att)
		dustEmitter = makeEmitter(att, {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(235, 225, 205)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.35, 0.6),
			Speed = NumberRange.new(4, 8),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 6,
		})
	end

	local char = localPlayer.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if head then
		local att = Instance.new("Attachment")
		att.Name = "TrainingSweatFx"
		att.Position = Vector3.new(0, 0.4, 0)
		att.Parent = head
		table.insert(fxInstances, att)
		sweatEmitter = makeEmitter(att, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(150, 215, 255)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0.12) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.45, 0.7),
			Speed = NumberRange.new(5, 9),
			SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(0, -35, 0),
		})
	end
end

local function stopFx()
	for _, inst in fxInstances do
		inst:Destroy()
	end
	table.clear(fxInstances)
	dustEmitter = nil
	sweatEmitter = nil
end

local function ringPulse(intensity: number)
	local bar = getOwnBar()
	local root = getRoot()
	if not bar or not root then
		return
	end
	local look = root.CFrame.LookVector
	local ring = Instance.new("Part")
	ring.Name = "TrainingRepRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.12, 1.5, 1.5)
	-- Cylinder axis is X; turn it to face the front camera
	ring.CFrame = CFrame.lookAt(bar.Position, bar.Position + look) * CFrame.Angles(0, math.rad(90), 0)
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 230, 110)
	ring.Transparency = 0.3
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = workspace

	local d = 3 + 5 * intensity
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, d, d),
		Transparency = 1,
	}):Play()
	task.delay(0.4, function()
		ring:Destroy()
	end)
end

local function popRepGain(gained: number, intensity: number)
	local char = localPlayer.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "RepGainPop"
	bb.Size = UDim2.fromOffset(220, 60)
	bb.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 2.4, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = head
	bb.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = math.floor(30 + 14 * intensity)
	label.TextColor3 = Color3.fromRGB(110, 255, 130)
	label.Text = `+{GameConfig.FormatNumber(gained)} XP`
	label.Parent = bb
	UiKit.AddStroke(label, Color3.fromRGB(15, 20, 15), 2.5)

	-- Pop in with an overshoot, then float up and fade
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bb, info, { StudsOffset = bb.StudsOffset + Vector3.new(0, 2.2, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	task.delay(0.85, function()
		bb:Destroy()
	end)
end

-- ============================================================================
-- TRAINING HUD: Strength level + XP bar, LEVEL UP popup, Bonus Rep pop-ups
-- ============================================================================
local hudGui = Instance.new("ScreenGui")
hudGui.Name = "TrainingHud"
hudGui.ResetOnSpawn = false
hudGui.IgnoreGuiInset = true
hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudGui.DisplayOrder = 5
hudGui.Enabled = false
hudGui.Parent = playerGui
UiKit.AttachResponsiveScale(hudGui)

local isPhone = UiKit.IsPhone()
local CARD_TONE: UiKit.Tri = {
	Light = Color3.fromRGB(44, 46, 55),
	Mid = Color3.fromRGB(36, 37, 45),
	Dark = Color3.fromRGB(27, 28, 34),
}
-- Bar tier pill gradients (spec 3f): Pull-Up grey, Iron steel, Crystal blue, Magma orange, Starlight violet
local TIER_TONES: { UiKit.Tri } = {
	UiKit.Gradients.Grey,
	UiKit.TriFromColor(Color3.fromRGB(140, 160, 185), 0.4, 0.3),
	UiKit.Gradients.Blue,
	UiKit.Gradients.Orange,
	UiKit.Gradients.SlimesNav,
}

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

local function makeCard(parent: Instance, size: UDim2, position: UDim2): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	f.Parent = parent
	UiKit.AddCorner(f, 18)
	UiKit.ApplyTri(f, CARD_TONE)
	UiKit.AddFrameOutline(f, 4)
	return f
end

-- Top centre: bar tier pill + hint (PC only)
local tierPill = Instance.new("Frame")
tierPill.Name = "TierPill"
tierPill.AnchorPoint = Vector2.new(0.5, 0)
tierPill.Position = UDim2.new(0.5, 0, 0, 20)
tierPill.Size = UDim2.fromOffset(300, 52)
tierPill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
tierPill.Parent = hudGui
UiKit.AddCorner(tierPill, 26)
UiKit.ApplyTri(tierPill, TIER_TONES[1])
UiKit.AddFrameOutline(tierPill, 4)
UiKit.AddStripes(tierPill, 26)
local tierLabel = makeLabel(tierPill, 28, "PULL-UP BAR")
tierLabel.Size = UDim2.fromScale(1, 1)
tierLabel.ZIndex = 3

local stopHint = makeLabel(hudGui, 18, "Jump or walk away to stop")
stopHint.AnchorPoint = Vector2.new(0.5, 0)
stopHint.Position = UDim2.new(0.5, 0, 0, 78)
stopHint.Size = UDim2.fromOffset(320, 24)
stopHint.Visible = not isPhone

-- Left panel: "This session"
local sessionPanel = makeCard(hudGui, UDim2.fromOffset(290, 214), UDim2.fromOffset(16, 86))
sessionPanel.Name = "SessionPanel"
local sessionHeader = Instance.new("Frame")
sessionHeader.Size = UDim2.new(1, 0, 0, 44)
sessionHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
sessionHeader.Parent = sessionPanel
UiKit.AddCorner(sessionHeader, 18)
UiKit.ApplyTri(sessionHeader, UiKit.Gradients.Blue)
UiKit.AddStripes(sessionHeader, 18)
local sessionTitle = makeLabel(sessionHeader, 24, "This session")
sessionTitle.Size = UDim2.fromScale(1, 1)
sessionTitle.ZIndex = 3

local sessionValues: { [string]: TextLabel } = {}
local sessionRows = { { "Reps", "Reps" }, { "Power", "Power gained" }, { "Speed", "Speed" }, { "Xp", "XP per second" } }
for i, def in sessionRows do
	local name = makeLabel(sessionPanel, 18, def[2], Enum.TextXAlignment.Left)
	name.Position = UDim2.fromOffset(16, 52 + (i - 1) * 40)
	name.Size = UDim2.fromOffset(150, 36)
	name.TextColor3 = Color3.fromRGB(215, 220, 232)
	local value = makeLabel(sessionPanel, 22, "0", Enum.TextXAlignment.Right)
	value.Position = UDim2.new(1, -150, 0, 52 + (i - 1) * 40)
	value.Size = UDim2.fromOffset(134, 36)
	sessionValues[def[1]] = value
end
UiKit.ApplyTri(sessionValues.Power, UiKit.Gradients.Power)
UiKit.ApplyTri(sessionValues.Xp, UiKit.Gradients.Cash)

-- Right panel: NEXT BAR + UPGRADE (or MAX BAR)
local nextPanel = makeCard(hudGui, UDim2.fromOffset(270, 176), UDim2.new(1, -286, 0, 86))
nextPanel.Name = "NextBarPanel"
local nextKicker = makeLabel(nextPanel, 16, "NEXT BAR")
nextKicker.Position = UDim2.fromOffset(8, 8)
nextKicker.Size = UDim2.new(1, -16, 0, 20)
nextKicker.TextColor3 = Color3.fromRGB(215, 220, 232)
local nextName = makeLabel(nextPanel, 26, "IRON BAR")
nextName.Position = UDim2.fromOffset(8, 28)
nextName.Size = UDim2.new(1, -16, 0, 32)
local nextGain = makeLabel(nextPanel, 17, "")
nextGain.Position = UDim2.fromOffset(8, 62)
nextGain.Size = UDim2.new(1, -16, 0, 24)
UiKit.ApplyTri(nextGain, UiKit.Gradients.Cash)
local upgradeBtn = UiKit.CreateGradientButton({
	Name = "UpgradeBarBtn",
	Parent = nextPanel,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.new(1, -24, 0, 62),
	Kind = "green",
	CornerRadius = 14,
	Text = "UPGRADE",
	TextSize = 26,
})
local upgradeLabel = upgradeBtn:FindFirstChild("Label", true) :: TextLabel
local canUpgrade = false

local latestPlayerState: any = nil
local function refreshNextBar()
	local state = latestPlayerState
	if type(state) ~= "table" then
		return
	end
	local tier = state.PullUpTier or 1
	tierLabel.Text = (GameConfig.PullUpTiers[tier] or GameConfig.PullUpTiers[1]).Name
	UiKit.SetTone(tierPill, TIER_TONES[math.min(tier, #TIER_TONES)])
	local nextTier = GameConfig.PullUpTiers[tier + 1]
	if not nextTier then
		nextName.Text = "MAX BAR"
		nextGain.Text = "Best bar unlocked!"
		UiKit.SetButtonTone(upgradeBtn, UiKit.Gradients.Grey, 0)
		upgradeLabel.Text = "MAX BAR"
		canUpgrade = false
		return
	end
	nextName.Text = nextTier.Name
	nextGain.Text = `+{nextTier.XPPerRep} XP/rep · {nextTier.SpeedMult}x speed`
	local affordable = (state.Cash or 0) >= nextTier.Cost
	canUpgrade = affordable
	UiKit.SetButtonTone(upgradeBtn, if affordable then UiKit.Gradients.Green else UiKit.Gradients.Grey, if affordable then 0 else 0.4)
	upgradeLabel.Text = if affordable then `UPGRADE ${GameConfig.FormatNumber(nextTier.Cost)}` else `${GameConfig.FormatNumber(nextTier.Cost)}`
end
upgradeBtn.Activated:Connect(function()
	if canUpgrade then
		Remotes.GetEvent("RequestPurchase"):FireServer({ ItemId = "pullup_tier", Quantity = 1 })
	end
end)
Remotes.GetEvent("PlayerStateSync").OnClientEvent:Connect(function(state: any)
	latestPlayerState = state
	refreshNextBar()
end)

-- Bottom centre XP bar: Lv badge 70x70, "cur / req XP", "Next: +5 Power", power-gradient fill
local xpPanel = Instance.new("Frame")
xpPanel.Name = "XpPanel"
xpPanel.AnchorPoint = Vector2.new(0.5, 1)
xpPanel.Position = UDim2.new(0.5, 0, 1, -if isPhone then 70 else 40)
xpPanel.Size = UDim2.fromOffset(if isPhone then 560 else 640, 88)
xpPanel.BackgroundTransparency = 1
xpPanel.Parent = hudGui

local lvBadge = Instance.new("Frame")
lvBadge.Size = UDim2.fromOffset(70, 70)
lvBadge.Position = UDim2.fromOffset(0, 9)
lvBadge.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
lvBadge.ZIndex = 3
lvBadge.Parent = xpPanel
UiKit.AddCorner(lvBadge, 20)
UiKit.ApplyTri(lvBadge, UiKit.Gradients.Luck)
UiKit.AddFrameOutline(lvBadge, 4)
local lvKicker = makeLabel(lvBadge, 14, "LV")
lvKicker.Position = UDim2.fromOffset(0, 6)
lvKicker.Size = UDim2.new(1, 0, 0, 16)
lvKicker.ZIndex = 4
local levelLabel = makeLabel(lvBadge, 34, "1")
levelLabel.Position = UDim2.fromOffset(0, 20)
levelLabel.Size = UDim2.new(1, 0, 0, 42)
levelLabel.ZIndex = 4

local nextRewardLabel = makeLabel(xpPanel, 20, `Next: +{GameConfig.Training.PowerPerLevel} Power`, Enum.TextXAlignment.Right)
nextRewardLabel.Position = UDim2.fromOffset(84, 0)
nextRewardLabel.Size = UDim2.new(1, -84, 0, 26)
UiKit.ApplyTri(nextRewardLabel, UiKit.Gradients.Power)

local xpBar = UiKit.CreateProgressBar(xpPanel, UDim2.new(1, -62, 0, 34), UiKit.Gradients.Power)
xpBar.Frame.Position = UDim2.fromOffset(62, 30)
xpBar.Label.TextSize = 20
local xpText = xpBar.Label

local function setXpBar(level: number, current: number, required: number, animate: boolean)
	levelLabel.Text = tostring(level)
	xpText.Text = `{GameConfig.FormatNumber(current)} / {GameConfig.FormatNumber(required)} XP`
	local ratio = math.clamp(if required > 0 then current / required else 0, 0, 1)
	xpBar.SetFraction(ratio, animate)
end

-- Gradient pop-up text (rep XP, bonus XP)
local function popCenterText(text: string, color: Color3, size: number, yScale: number)
	local label = makeLabel(hudGui, size, text)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, yScale)
	label.Size = UDim2.fromOffset(700, 90)
	label.ZIndex = 20
	UiKit.ApplyTri(label, UiKit.TriFromColor(color, 0.5, 0.25))

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.0, function()
		local fade = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, fade, { TextTransparency = 1, Position = label.Position - UDim2.fromOffset(0, 40) }):Play()
		task.delay(0.45, function()
			label:Destroy()
		end)
	end)
end

-- LEVEL UP! popup (spec 3f): gold gradient 64, "+N Power" under it, pop in 0.3 s, fade after 1.2 s
local function celebrateLevelUp(levels: number, powerGained: number)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.32)
	holder.Size = UDim2.fromOffset(700, 130)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 20
	holder.Parent = hudGui
	local big = makeLabel(holder, 64, if levels > 1 then `LEVEL UP x{levels}!` else "LEVEL UP!")
	big.Size = UDim2.new(1, 0, 0, 76)
	big.ZIndex = 21
	UiKit.ApplyTri(big, UiKit.Gradients.Luck)
	local sub = makeLabel(holder, 34, `+{powerGained} Power`)
	sub.Position = UDim2.fromOffset(0, 80)
	sub.Size = UDim2.new(1, 0, 0, 42)
	sub.ZIndex = 21
	UiKit.ApplyTri(sub, UiKit.Gradients.Power)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = holder
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.2, function()
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.delay(0.35, function()
			holder:Destroy()
		end)
	end)
	-- Extra-hard camera punch on top of the normal rep shake
	trauma = 1
	punch = 1
end

-- Touch: red STOP circle
if isPhone then
	local stopBtn = UiKit.CreateGradientButton({
		Name = "StopBtn",
		Parent = hudGui,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -50, 1, -110),
		Size = UDim2.fromOffset(120, 120),
		Kind = "red",
		CornerRadius = 60,
		Text = "STOP",
		TextSize = 30,
		OnClick = function()
			requestStopTraining:FireServer()
		end,
	})
	stopBtn.Name = "StopBtn"
end

-- Session stats (left panel)
local sessionReps = 0
local sessionPower = 0
local sessionXp = 0
local sessionStart = os.clock()
local function refreshSession()
	sessionValues.Reps.Text = GameConfig.FormatNumber(sessionReps)
	sessionValues.Power.Text = `+{GameConfig.FormatNumber(sessionPower)}`
	sessionValues.Speed.Text = string.format("%.2fs / rep", currentInterval)
	sessionValues.Xp.Text = GameConfig.FormatNumber(UiLayout.PerSecond(sessionXp, os.clock() - sessionStart))
end
local function resetSession()
	sessionReps, sessionPower, sessionXp = 0, 0, 0
	sessionStart = os.clock()
	refreshSession()
end

-- Bonus Rep pop-up (offered by the server every few seconds; click within the window for bonus XP)
local bonusButton: TextButton? = nil

local function clearBonusButton()
	if bonusButton then
		bonusButton:Destroy()
		bonusButton = nil
	end
end

local function showBonusButton(id: number, window: number, multiplier: number)
	clearBonusButton()
	-- Spec: UDim2.new(0.66, 0, 0.55, 0), a little jitter so repeats do not stack
	local pos = UDim2.fromScale(0.66 + math.random(-6, 6) / 100, 0.55 + math.random(-4, 4) / 100)
	local btn, face = UiKit.CreateGradientButton({
		Name = "BonusRepButton",
		Parent = hudGui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(270, 72),
		Kind = "orange",
		Gradient = UiKit.Gradients.Luck,
		CornerRadius = 18,
		Text = `BONUS REP! ({multiplier}x XP)`,
		TextSize = 24,
	})
	bonusButton = btn
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, 120, 1, 120)
	glow.BackgroundTransparency = 1
	glow.Image = UiAssets.Textures.glow
	glow.ImageColor3 = Color3.fromRGB(255, 225, 74)
	glow.ImageTransparency = 0.35
	glow.ZIndex = 0
	glow.Parent = btn

	-- 150 px timer bar under the button, emptying over the window
	local timer = Instance.new("Frame")
	timer.AnchorPoint = Vector2.new(0.5, 0)
	timer.Position = UDim2.new(0.5, 0, 1, 10)
	timer.Size = UDim2.fromOffset(150, 10)
	timer.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	timer.Parent = btn
	UiKit.AddCorner(timer, 5)
	UiKit.AddStroke(timer, UiKit.Colors.Ink, 2.5, Enum.ApplyStrokeMode.Border)
	local timerFill = Instance.new("Frame")
	timerFill.Size = UDim2.fromScale(1, 1)
	timerFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	timerFill.Parent = timer
	UiKit.AddCorner(timerFill, 5)
	UiKit.ApplyTri(timerFill, UiKit.Gradients.Luck)
	TweenService:Create(timerFill, TweenInfo.new(window, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()

	-- Bouncy entrance, tilted 5 degrees
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = btn
	scale.Scale = 0.2
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	btn.Rotation = 5

	local claimed = false
	btn.Activated:Connect(function()
		if claimed then
			return
		end
		claimed = true
		requestBonusRep:FireServer({ Id = id })
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.35 }):Play()
		TweenService:Create(face, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
		task.delay(0.16, function()
			if bonusButton == btn then
				clearBonusButton()
			end
		end)
	end)

	-- Auto-expire if missed
	task.delay(window, function()
		if bonusButton == btn and not claimed then
			TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
			task.delay(0.16, function()
				if bonusButton == btn then
					clearBonusButton()
				end
			end)
		end
	end)
end

-- Everything that should land on the chin-over-bar peak
local function onRepPeak(gained: number?)
	local intensity = PullUpMotion.Intensity(currentInterval)
	CharacterAnimator.SyncPullUpRep()
	kickCamera(intensity)
	ringPulse(intensity)
	if dustEmitter then
		dustEmitter:Emit(math.max(2, math.floor(8 * intensity)))
	end
	if sweatEmitter then
		sweatEmitter:Emit(math.max(1, math.floor(5 * intensity)))
	end
	if gained then
		popRepGain(gained, intensity)
	end
end

-- ============================================================================
-- START / STOP
-- ============================================================================
local function endTrainingLocal()
	isTraining = false
	stopRequested = false
	walkStopArmed = false
	CharacterAnimator.StopPullUpLoop()
	stopCamera()
	stopFx()
	clearBonusButton()
	hudGui.Enabled = false
	localPlayer:SetAttribute("InTraining", false)
end

local function requestStop()
	if isTraining and not stopRequested then
		stopRequested = true
		requestStopTraining:FireServer()
	end
end

trainingState.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	-- Temporary diagnostics (remove with CharacterAnimator's DEBUG prints)
	print("[TrainingController] TrainingState", payload.Active, payload.Interval, payload.Reason)
	if payload.Active then
		isTraining = true
		stopRequested = false
		walkStopArmed = false
		if type(payload.Interval) == "number" then
			currentInterval = payload.Interval
		end
		CharacterAnimator.StartPullUpLoop(localPlayer.Character, function()
			return currentInterval
		end)
		startCamera()
		startFx()
		setXpBar(tonumber(payload.StrengthLevel) or 1, tonumber(payload.CurrentXP) or 0, tonumber(payload.RequiredXP) or 10, false)
		resetSession()
		refreshNextBar()
		hudGui.Enabled = true
		localPlayer:SetAttribute("InTraining", true)
	else
		endTrainingLocal()
	end
end)

trainingRep.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" or not isTraining then
		return
	end
	if type(payload.Interval) == "number" then
		-- Strength just went up: the loop speeds up from the next frame on
		currentInterval = payload.Interval
	end
	local xp = if type(payload.XPGained) == "number" then payload.XPGained else nil
	if not payload.IsBonus then
		sessionReps += 1
	end
	sessionXp += xp or 0
	sessionPower += tonumber(payload.PowerGained) or 0
	refreshSession()

	if payload.IsBonus then
		-- Bonus Rep: not a rep cycle, so no phase sync / ring; just the burst + a small kick
		kickCamera(0.6)
		if xp then
			popCenterText(`+{GameConfig.FormatNumber(xp)} XP ({GameConfig.Training.BonusRepMultiplier}x)!`, Color3.fromRGB(255, 200, 60), 44, 0.42)
		end
	else
		onRepPeak(xp)
	end

	if type(payload.StrengthLevel) == "number" then
		setXpBar(payload.StrengthLevel, tonumber(payload.CurrentXP) or 0, tonumber(payload.RequiredXP) or 1, true)
	end
	local levels = tonumber(payload.LevelsGained) or 0
	if levels > 0 then
		celebrateLevelUp(levels, tonumber(payload.PowerGained) or levels * GameConfig.Training.PowerPerLevel)
	end
end)

trainingBonus.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" or not isTraining or type(payload.Id) ~= "number" then
		return
	end
	showBonusButton(
		payload.Id,
		tonumber(payload.Window) or GameConfig.Training.BonusRepWindow,
		tonumber(payload.Multiplier) or GameConfig.Training.BonusRepMultiplier
	)
end)

-- Jumping or trying to walk drops you off the bar.
-- Walking only triggers stop once move input has been released (<= 0.1) at least once after
-- the session started, so walking onto the pad doesn't immediately stop on the first frame.
UserInputService.JumpRequest:Connect(requestStop)
local promptCheckAccum = 0
RunService.Heartbeat:Connect(function(dt: number)
	promptCheckAccum += dt
	if promptCheckAccum >= 1.0 then
		promptCheckAccum = 0
		refreshBarPromptVisibility()
	end
	if not isTraining then
		return
	end
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local mag = hum.MoveDirection.Magnitude
		if mag <= 0.1 then
			walkStopArmed = true
		elseif walkStopArmed and mag > 0.5 then
			requestStop()
		end
	end
end)

-- Death / respawn mid-training must never leave the camera or effects stuck
localPlayer.CharacterAdded:Connect(function()
	if isTraining or camActive then
		endTrainingLocal()
	end
end)
localPlayer.CharacterRemoving:Connect(function()
	if isTraining or camActive then
		endTrainingLocal()
	end
end)
