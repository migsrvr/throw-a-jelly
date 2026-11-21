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
local UiKit = require(Shared:WaitForChild("UiKit"))

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

local function setPromptText(active: boolean)
	local bar = getOwnBar()
	local prompt = bar and bar:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ActionText = if active then "Stop Training" else "Start Training"
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

local xpPanel = Instance.new("Frame")
xpPanel.Name = "XpPanel"
xpPanel.AnchorPoint = Vector2.new(0.5, 1)
xpPanel.Position = UDim2.new(0.5, 0, 1, -150)
xpPanel.Size = UDim2.fromOffset(460, 74)
xpPanel.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
xpPanel.BackgroundTransparency = 0.15
xpPanel.Parent = hudGui
UiKit.AddCorner(xpPanel, 14)
UiKit.AddStroke(xpPanel, Color3.fromRGB(12, 14, 20), 3, Enum.ApplyStrokeMode.Border)

local levelLabel = Instance.new("TextLabel")
levelLabel.Position = UDim2.fromOffset(14, 6)
levelLabel.Size = UDim2.fromOffset(150, 28)
levelLabel.BackgroundTransparency = 1
levelLabel.Font = Enum.Font.FredokaOne
levelLabel.TextSize = 26
levelLabel.TextXAlignment = Enum.TextXAlignment.Left
levelLabel.TextColor3 = Color3.fromRGB(255, 225, 75)
levelLabel.Text = "Lv. 1"
levelLabel.Parent = xpPanel
UiKit.AddStroke(levelLabel, Color3.fromRGB(15, 18, 25), 2.4)

local nextRewardLabel = Instance.new("TextLabel")
nextRewardLabel.AnchorPoint = Vector2.new(1, 0)
nextRewardLabel.Position = UDim2.new(1, -14, 0, 8)
nextRewardLabel.Size = UDim2.fromOffset(220, 24)
nextRewardLabel.BackgroundTransparency = 1
nextRewardLabel.Font = Enum.Font.FredokaOne
nextRewardLabel.TextSize = 19
nextRewardLabel.TextXAlignment = Enum.TextXAlignment.Right
nextRewardLabel.TextColor3 = Color3.fromRGB(120, 245, 140)
nextRewardLabel.Text = `Next: +{GameConfig.Training.PowerPerLevel} Power`
nextRewardLabel.Parent = xpPanel
UiKit.AddStroke(nextRewardLabel, Color3.fromRGB(15, 18, 25), 2)

local barBack = Instance.new("Frame")
barBack.Position = UDim2.fromOffset(14, 40)
barBack.Size = UDim2.new(1, -28, 0, 24)
barBack.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
barBack.Parent = xpPanel
UiKit.AddCorner(barBack, 12)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
barFill.Parent = barBack
UiKit.AddCorner(barFill, 12)
UiKit.AddGlossGradient(barFill, Color3.fromRGB(90, 215, 255))

local xpText = Instance.new("TextLabel")
xpText.Size = UDim2.fromScale(1, 1)
xpText.BackgroundTransparency = 1
xpText.Font = Enum.Font.FredokaOne
xpText.TextSize = 17
xpText.TextColor3 = Color3.fromRGB(255, 255, 255)
xpText.Text = "0 / 10 XP"
xpText.ZIndex = 3
xpText.Parent = barBack
UiKit.AddStroke(xpText, Color3.fromRGB(15, 18, 25), 2)

local function setXpBar(level: number, current: number, required: number, animate: boolean)
	levelLabel.Text = `Lv. {level}`
	xpText.Text = `{GameConfig.FormatNumber(current)} / {GameConfig.FormatNumber(required)} XP`
	local ratio = math.clamp(if required > 0 then current / required else 0, 0, 1)
	if animate then
		TweenService:Create(barFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(ratio, 1),
		}):Play()
	else
		barFill.Size = UDim2.fromScale(ratio, 1)
	end
end

local function popCenterText(text: string, color: Color3, size: number, yScale: number)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, yScale)
	label.Size = UDim2.fromOffset(620, 90)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.ZIndex = 20
	label.Parent = hudGui
	UiKit.AddStroke(label, Color3.fromRGB(25, 18, 5), 4)

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

local function celebrateLevelUp(levels: number, powerGained: number)
	local text = if levels > 1
		then `LEVEL UP x{levels}! +{powerGained} POWER`
		else `LEVEL UP! +{powerGained} POWER`
	popCenterText(text, Color3.fromRGB(255, 215, 60), 58, 0.32)
	-- Extra-hard camera punch on top of the normal rep shake
	trauma = 1
	punch = 1
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
	-- Random spot away from the HUD edges and the XP bar
	local pos = UDim2.fromScale(math.random(28, 72) / 100, math.random(26, 56) / 100)
	local btn = UiKit.CreateBevelButton({
		Name = "BonusRepButton",
		Parent = hudGui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(250, 64),
		Color = Color3.fromRGB(255, 185, 35),
		CornerRadius = 14,
		Text = `⚡ BONUS REP! ({multiplier}x XP)`,
		TextSize = 22,
	})
	bonusButton = btn

	-- Bouncy entrance + gentle pulse while it waits
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = btn
	scale.Scale = 0.2
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	btn.Rotation = math.random(-6, 6)

	local claimed = false
	btn.Activated:Connect(function()
		if claimed then
			return
		end
		claimed = true
		requestBonusRep:FireServer({ Id = id })
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.35 }):Play()
		local face = btn:FindFirstChild("Face")
		if face then
			TweenService:Create(face :: Frame, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
		end
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
	CharacterAnimator.StopPullUpLoop()
	stopCamera()
	stopFx()
	clearBonusButton()
	hudGui.Enabled = false
	setPromptText(false)
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
		if type(payload.Interval) == "number" then
			currentInterval = payload.Interval
		end
		CharacterAnimator.StartPullUpLoop(localPlayer.Character, function()
			return currentInterval
		end)
		startCamera()
		startFx()
		setXpBar(tonumber(payload.StrengthLevel) or 1, tonumber(payload.CurrentXP) or 0, tonumber(payload.RequiredXP) or 10, false)
		hudGui.Enabled = true
		setPromptText(true)
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

-- Jumping or trying to walk drops you off the bar
UserInputService.JumpRequest:Connect(requestStop)
RunService.Heartbeat:Connect(function()
	if not isTraining then
		return
	end
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.MoveDirection.Magnitude > 0.5 then
		requestStop()
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
