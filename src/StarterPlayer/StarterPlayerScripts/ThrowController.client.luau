--!strict
--[[
	ThrowController.client.luau
	Handles client-side throw charging, pitch/yaw aiming, live 3D trajectory
	arc preview at ThrowLine, and 60fps squash-and-stretch bounce animations
	when ThrowBroadcast arrives.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))
local ThrowPhysics = require(Shared:WaitForChild("ThrowPhysics"))

local requestThrow = Remotes.GetEvent("RequestThrow")
local throwBroadcast = Remotes.GetEvent("ThrowBroadcast")
local stateSync = Remotes.GetEvent("PlayerStateSync")

local currentPower = 5
local equippedSlimeId = "meadow_sprout"
local pitchDeg = GameConfig.Physics.DefaultPitchDeg
local yawDeg = 0

local isCharging = false
local chargeTime = 0
local chargeRatio = 0.25
local lastThrowSent = 0

-- Preview dots folder
local previewFolder = Instance.new("Folder")
previewFolder.Name = "ThrowPreviewArc"
previewFolder.Parent = workspace

local NUM_PREVIEW_DOTS = 18
local previewDots: { Part } = {}
for i = 1, NUM_PREVIEW_DOTS do
	local dot = Instance.new("Part")
	dot.Name = `ArcDot_{i}`
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.new(0.9, 0.9, 0.9)
	dot.Material = Enum.Material.Neon
	dot.Color = Color3.fromRGB(125, 245, 255)
	dot.Transparency = 1
	dot.Anchored = true
	dot.CanCollide = false
	dot.CastShadow = false
	dot.Parent = previewFolder
	table.insert(previewDots, dot)
end

local function isNearThrowLine(): (boolean, Vector3)
	local char = localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false, Vector3.new(0, GameConfig.Hub.FloorY + 1.8, GameConfig.Hub.ThrowLineZ)
	end
	local pos = root.Position
	local nearZ = math.abs(pos.Z - GameConfig.Hub.ThrowLineZ) <= 22
	local nearY = pos.Y >= (GameConfig.Hub.FloorY - 6)
	local clampedX = math.clamp(pos.X, -GameConfig.Hub.ClearHalfWidth + 2, GameConfig.Hub.ClearHalfWidth - 2)
	local origin = Vector3.new(clampedX, GameConfig.Hub.FloorY + 1.8, GameConfig.Hub.ThrowLineZ)
	return (nearZ and nearY), origin
end

local function beginCharge()
	if os.clock() - lastThrowSent < 0.75 then
		return
	end
	isCharging = true
	chargeTime = 0
	chargeRatio = 0.2
	localPlayer:SetAttribute("IsCharging", true)
end

local function releaseChargeAndThrow()
	if not isCharging then
		return
	end
	isCharging = false
	lastThrowSent = os.clock()
	local finalCharge = math.clamp(chargeRatio, 0.15, 1.0)
	localPlayer:SetAttribute("IsCharging", false)
	localPlayer:SetAttribute("ThrowChargeRatio", finalCharge)

	requestThrow:FireServer({
		ChargeRatio = finalCharge,
		PitchDeg = pitchDeg,
		YawDeg = yawDeg,
	})
end

-- Expose bindable attributes so HudController's "HOLD TO THROW" button can trigger charging too
localPlayer:SetAttribute("ThrowPitchDeg", pitchDeg)
localPlayer:SetAttribute("ThrowChargeRatio", 0)
localPlayer:SetAttribute("NearThrowLine", false)
localPlayer:SetAttribute("IsCharging", false)

localPlayer:GetAttributeChangedSignal("HudHoldThrow"):Connect(function()
	local holding = localPlayer:GetAttribute("HudHoldThrow")
	if holding == true then
		beginCharge()
	elseif holding == false and isCharging then
		releaseChargeAndThrow()
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		pitchDeg = math.clamp(pitchDeg - 4, GameConfig.Physics.MinPitchDeg, GameConfig.Physics.MaxPitchDeg)
		localPlayer:SetAttribute("ThrowPitchDeg", pitchDeg)
	elseif input.KeyCode == Enum.KeyCode.E then
		pitchDeg = math.clamp(pitchDeg + 4, GameConfig.Physics.MinPitchDeg, GameConfig.Physics.MaxPitchDeg)
		localPlayer:SetAttribute("ThrowPitchDeg", pitchDeg)
	elseif input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.MouseButton1 then
		local near = isNearThrowLine()
		if near then
			beginCharge()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isCharging then
			releaseChargeAndThrow()
		end
	end
end)

stateSync.OnClientEvent:Connect(function(state: any)
	if type(state) ~= "table" then
		return
	end
	if type(state.EffectiveThrowPower) == "number" then
		currentPower = state.EffectiveThrowPower
	end
	if type(state.EquippedSlimeId) == "string" then
		equippedSlimeId = state.EquippedSlimeId
	end
end)

local function spawnBounceRing(position: Vector3, color: Color3)
	local ring = Instance.new("Part")
	ring.Name = "BouncePulse"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.25, 2.2, 2.2)
	ring.CFrame = CFrame.new(position.X, position.Y - 0.85, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Anchored = true
	ring.CanCollide = false
	ring.CastShadow = false
	ring.Parent = workspace

	local tween = TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, 9.5, 9.5),
		Transparency = 1,
	})
	tween:Play()
	task.delay(0.5, function()
		ring:Destroy()
	end)
end

local function spawnLandingBanner(position: Vector3, payload: any)
	local anchor = Instance.new("Part")
	anchor.Name = "LandingBannerAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position + Vector3.new(0, 2.5, 0)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 95)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 400
	bb.Adornee = anchor
	bb.Parent = anchor

	local line1 = Instance.new("TextLabel")
	line1.Size = UDim2.new(1, 0, 0.36, 0)
	line1.BackgroundTransparency = 1
	line1.Font = Enum.Font.FredokaOne
	line1.TextScaled = true
	line1.TextColor3 = Color3.fromRGB(255, 240, 110)
	line1.Text = `{string.format("%.1f", payload.Distance or 0)}m — {payload.LandedZoneName or "Meadow"}!`
	line1.Parent = bb

	local s1 = Instance.new("UIStroke")
	s1.Thickness = 2
	s1.Parent = line1

	local line2 = Instance.new("TextLabel")
	line2.Position = UDim2.fromScale(0, 0.36)
	line2.Size = UDim2.new(1, 0, 0.34, 0)
	line2.BackgroundTransparency = 1
	line2.Font = Enum.Font.FredokaOne
	line2.TextScaled = true
	line2.TextColor3 = Color3.fromRGB(120, 255, 140)
	line2.Text = `+$${GameConfig.FormatNumber(payload.CashEarned or 0)}  |  +{payload.CaughtSlimeName or "Slime"} [{payload.CaughtSlimeRarity or "Common"}]`
	line2.Parent = bb

	local s2 = s1:Clone()
	s2.Parent = line2

	if payload.HitGate and payload.BlockedByZoneName then
		local line3 = Instance.new("TextLabel")
		line3.Position = UDim2.fromScale(0, 0.70)
		line3.Size = UDim2.new(1, 0, 0.30, 0)
		line3.BackgroundTransparency = 1
		line3.Font = Enum.Font.FredokaOne
		line3.TextScaled = true
		line3.TextColor3 = Color3.fromRGB(255, 105, 105)
		line3.Text = `🔒 Blocked by {payload.BlockedByZoneName} Gate (Need {payload.BlockedRequiredPower} Power)`
		line3.Parent = bb
		local s3 = s1:Clone()
		s3.Parent = line3
	end

	TweenService:Create(anchor, TweenInfo.new(2.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = anchor.Position + Vector3.new(0, 5.5, 0),
	}):Play()

	task.delay(3.0, function()
		anchor:Destroy()
	end)
end

throwBroadcast.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end

	local sim = ThrowPhysics.Simulate({
		Origin = payload.Origin,
		ThrowPower = payload.ThrowPower or 5,
		ChargeRatio = payload.ChargeRatio or 0.75,
		PitchDeg = payload.PitchDeg or GameConfig.Physics.DefaultPitchDeg,
		YawDeg = payload.YawDeg or 0,
		SlimeWeight = payload.SlimeWeight or 1.0,
	})

	local slimeId = payload.SlimeId or "meadow_sprout"
	local def = GameConfig.SlimesById[slimeId] or GameConfig.Slimes[1]
	local pulseColor = SlimeFactory.ToColor3(def.Color)
	local model = SlimeFactory.CreateSlimeModel(slimeId, false)
	model.Parent = workspace

	local samples = sim.Samples
	local totalSamples = #samples
	local startClock = os.clock()
	local lastBounceIdx = 0

	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startClock
		local frameIdx = math.min(totalSamples, math.max(1, math.floor(elapsed / GameConfig.Physics.FixedDt) + 1))
		local sample = samples[frameIdx]

		if sample then
			local pos = Vector3.new(sample.Position.X, sample.Position.Y, sample.Position.Z)
			local vel = Vector3.new(sample.Velocity.X, 0, sample.Velocity.Z)
			local lookDir = if vel.Magnitude > 0.5 then vel.Unit else Vector3.new(0, 0, 1)
			local cf = CFrame.lookAt(pos, pos + lookDir)
			SlimeFactory.PositionSlime(model, cf, sample.Squash)

			if sample.Bounced and frameIdx > lastBounceIdx then
				lastBounceIdx = frameIdx
				spawnBounceRing(pos, pulseColor)
			end
		end

		if frameIdx >= totalSamples then
			if conn then
				conn:Disconnect()
			end
			local finalPos = Vector3.new(sim.FinalPosition.X, sim.FinalPosition.Y, sim.FinalPosition.Z)
			spawnBounceRing(finalPos, pulseColor)
			spawnLandingBanner(finalPos, payload)
			task.delay(1.8, function()
				model:Destroy()
			end)
		end
	end)
end)

-- Live charge oscillation & 3D trajectory preview loop
RunService.RenderStepped:Connect(function(dt: number)
	local near, origin = isNearThrowLine()
	localPlayer:SetAttribute("NearThrowLine", near)

	if isCharging then
		chargeTime += dt
		-- Smooth triangle wave oscillating between 0.18 and 1.0
		local wave = 0.5 - 0.5 * math.cos(chargeTime * 4.2)
		chargeRatio = 0.18 + 0.82 * wave
		localPlayer:SetAttribute("ThrowChargeRatio", chargeRatio)
	end

	if near or isCharging then
		local def = GameConfig.SlimesById[equippedSlimeId] or GameConfig.Slimes[1]
		local previewCharge = if isCharging then chargeRatio else 0.75
		local sim = ThrowPhysics.Simulate({
			Origin = origin,
			ThrowPower = currentPower,
			ChargeRatio = previewCharge,
			PitchDeg = pitchDeg,
			YawDeg = yawDeg,
			SlimeWeight = def.Weight,
		})

		local samples = sim.Samples
		local maxPreviewIdx = math.min(#samples, 95)
		for i = 1, NUM_PREVIEW_DOTS do
			local dot = previewDots[i]
			local sampleIdx = math.max(1, math.floor((i / NUM_PREVIEW_DOTS) * maxPreviewIdx))
			local s = samples[sampleIdx]
			if s then
				dot.Position = Vector3.new(s.Position.X, s.Position.Y, s.Position.Z)
				dot.Transparency = 0.15 + (i / NUM_PREVIEW_DOTS) * 0.55
				dot.Color = if sim.HitGate
					then Color3.fromRGB(255, 110, 110)
					else SlimeFactory.ToColor3(def.Color)
			else
				dot.Transparency = 1
			end
		end
	else
		for _, dot in previewDots do
			dot.Transparency = 1
		end
	end
end)
