--!strict
--[[
	CharacterAnimator.luau
	Universal R15 & R6 procedural Motor6D animation & prop-holding helper:
	1. StartAimPose / StopAimPose (holds 3D Jelly Bait in right hand & raises arm)
	2. PlayThrowAnimation (overhead wind-up -> forward whip -> release callback -> follow-through)
	3. StartCarrySlime / StopCarrySlime (two-handed front slime carry when hotbar slot equipped)
	4. PlayPullUpAnimation (two-handed overhead pull-up bar rep motion)
]]

local RunService = game:GetService("RunService")
local SlimeFactory = require(script.Parent:WaitForChild("SlimeFactory"))

local CharacterAnimator = {}

local activeAimBait: Model? = nil
local activeAimConn: RBXScriptConnection? = nil
local isThrowing = false

local activeCarryModel: Model? = nil
local activeCarryConn: RBXScriptConnection? = nil

local function getRightHandPart(character: Model): BasePart?
	return (character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

local function getRightShoulderMotor(character: Model): (Motor6D?, boolean)
	local upperArm = character:FindFirstChild("RightUpperArm")
	local r15Motor = upperArm and upperArm:FindFirstChild("RightShoulder") :: Motor6D?
	if r15Motor then
		return r15Motor, true
	end
	local torso = character:FindFirstChild("Torso")
	local r6Motor = torso and torso:FindFirstChild("Right Shoulder") :: Motor6D?
	if r6Motor then
		return r6Motor, false
	end
	return nil, true
end

local function getLeftShoulderMotor(character: Model): (Motor6D?, boolean)
	local upperArm = character:FindFirstChild("LeftUpperArm")
	local r15Motor = upperArm and upperArm:FindFirstChild("LeftShoulder") :: Motor6D?
	if r15Motor then
		return r15Motor, true
	end
	local torso = character:FindFirstChild("Torso")
	local r6Motor = torso and torso:FindFirstChild("Left Shoulder") :: Motor6D?
	if r6Motor then
		return r6Motor, false
	end
	return nil, true
end

local function getWaistMotor(character: Model): Motor6D?
	local upperTorso = character:FindFirstChild("UpperTorso")
	local waist = upperTorso and upperTorso:FindFirstChild("Waist") :: Motor6D?
	if waist then
		return waist
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return (root and root:FindFirstChild("RootJoint")) :: Motor6D?
end

function CharacterAnimator.StartAimPose(character: Model?)
	if not character or isThrowing then
		return
	end
	if activeAimBait and activeAimBait.Parent then
		return
	end

	CharacterAnimator.StopAimPose()

	local bait = SlimeFactory.CreateJellyBaitModel()
	bait.Parent = workspace
	activeAimBait = bait

	activeAimConn = RunService.RenderStepped:Connect(function()
		if not character.Parent or isThrowing then
			return
		end
		local hand = getRightHandPart(character)
		if hand and activeAimBait then
			local holdCf = hand.CFrame * CFrame.new(0, -0.35, -0.65) * CFrame.Angles(math.rad(-20), 0, 0)
			SlimeFactory.PositionBait(activeAimBait, holdCf)
		end

		local rShoulder, isR15 = getRightShoulderMotor(character)
		if rShoulder then
			if isR15 then
				rShoulder.Transform = CFrame.Angles(math.rad(65), math.rad(10), math.rad(12))
			else
				rShoulder.Transform = CFrame.Angles(0, 0, math.rad(65))
			end
		end
	end)
end

function CharacterAnimator.StopAimPose()
	if activeAimConn then
		activeAimConn:Disconnect()
		activeAimConn = nil
	end
	if activeAimBait then
		activeAimBait:Destroy()
		activeAimBait = nil
	end
end

function CharacterAnimator.PlayThrowAnimation(character: Model?, onRelease: (Vector3) -> ())
	if not character then
		onRelease(Vector3.new(0, 32, -3.6))
		return
	end

	isThrowing = true
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		-- Face down the lane (+Z)
		local pos = root.Position
		root.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 20))
	end

	if not activeAimBait or not activeAimBait.Parent then
		activeAimBait = SlimeFactory.CreateJellyBaitModel()
		activeAimBait.Parent = workspace
	end

	local rShoulder, isR15 = getRightShoulderMotor(character)
	local waist = getWaistMotor(character)

	local startClock = os.clock()
	local windupDur = 0.14
	local whipDur = 0.10
	local followDur = 0.18
	local totalDur = windupDur + whipDur + followDur
	local released = false

	local throwConn: RBXScriptConnection? = nil
	throwConn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startClock

		local armPitchDeg = 65
		local waistYawDeg = 0

		if elapsed <= windupDur then
			local a = math.clamp(elapsed / windupDur, 0, 1)
			armPitchDeg = 65 + (145 - 65) * a
			waistYawDeg = -28 * a
		elseif elapsed <= windupDur + whipDur then
			local a = math.clamp((elapsed - windupDur) / whipDur, 0, 1)
			armPitchDeg = 145 + (25 - 145) * a
			waistYawDeg = -28 + (20 - -28) * a

			if a >= 0.45 and not released then
				released = true
				local hand = getRightHandPart(character)
				local releaseOrigin = if hand
					then hand.Position + Vector3.new(0, 0.6, 1.0)
					elseif root then root.Position + Vector3.new(0, 1.8, 1.5)
					else Vector3.new(0, 32, -3.6)

				CharacterAnimator.StopAimPose()
				onRelease(releaseOrigin)
			end
		else
			local a = math.clamp((elapsed - windupDur - whipDur) / followDur, 0, 1)
			armPitchDeg = 25 * (1 - a)
			waistYawDeg = 20 * (1 - a)
		end

		if rShoulder then
			if isR15 then
				rShoulder.Transform = CFrame.Angles(math.rad(armPitchDeg), 0, math.rad(10))
			else
				rShoulder.Transform = CFrame.Angles(0, 0, math.rad(armPitchDeg))
			end
		end
		if waist then
			waist.Transform = CFrame.Angles(0, math.rad(waistYawDeg), 0)
		end

		if not released and activeAimBait then
			local hand = getRightHandPart(character)
			if hand then
				SlimeFactory.PositionBait(activeAimBait, hand.CFrame * CFrame.new(0, -0.3, -0.6))
			end
		end

		if elapsed >= totalDur then
			if throwConn then
				throwConn:Disconnect()
			end
			if rShoulder then
				rShoulder.Transform = CFrame.identity
			end
			if waist then
				waist.Transform = CFrame.identity
			end
			isThrowing = false
		end
	end)
end

function CharacterAnimator.StartCarrySlime(character: Model?, slimeId: string, mutationId: string?)
	CharacterAnimator.StopCarrySlime()
	if not character then
		return
	end

	local mdl = SlimeFactory.CreateSlimeModel(slimeId, false, mutationId)
	mdl:SetAttribute("BaseSize", 1.7)
	mdl.Parent = workspace
	activeCarryModel = mdl

	activeCarryConn = RunService.RenderStepped:Connect(function()
		if not character.Parent or not activeCarryModel then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local carryCf = root.CFrame * CFrame.new(0, 0.3, -2.1)
			SlimeFactory.PositionSlime(activeCarryModel, carryCf, 0.08 * math.sin(os.clock() * 6))
		end

		local rShoulder, isR15 = getRightShoulderMotor(character)
		local lShoulder, isL15 = getLeftShoulderMotor(character)
		if rShoulder then
			rShoulder.Transform = if isR15
				then CFrame.Angles(math.rad(75), 0, math.rad(-18))
				else CFrame.Angles(0, 0, math.rad(75))
		end
		if lShoulder then
			lShoulder.Transform = if isL15
				then CFrame.Angles(math.rad(75), 0, math.rad(18))
				else CFrame.Angles(0, 0, math.rad(-75))
		end
	end)
end

function CharacterAnimator.StopCarrySlime()
	if activeCarryConn then
		activeCarryConn:Disconnect()
		activeCarryConn = nil
	end
	if activeCarryModel then
		activeCarryModel:Destroy()
		activeCarryModel = nil
	end
end

function CharacterAnimator.PlayPullUpAnimation(character: Model?)
	if not character then
		return
	end
	local rShoulder, isR15 = getRightShoulderMotor(character)
	local lShoulder, isL15 = getLeftShoulderMotor(character)
	local startClock = os.clock()
	local dur = 0.36

	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - startClock
		local a = math.sin(math.clamp(t / dur, 0, 1) * math.pi)
		local angle = math.rad(155 * a)
		if rShoulder then
			rShoulder.Transform = if isR15 then CFrame.Angles(angle, 0, 0) else CFrame.Angles(0, 0, angle)
		end
		if lShoulder then
			lShoulder.Transform = if isL15 then CFrame.Angles(angle, 0, 0) else CFrame.Angles(0, 0, -angle)
		end
		if t >= dur then
			if conn then
				conn:Disconnect()
			end
			if rShoulder then
				rShoulder.Transform = CFrame.identity
			end
			if lShoulder then
				lShoulder.Transform = CFrame.identity
			end
		end
	end)
end

return CharacterAnimator
