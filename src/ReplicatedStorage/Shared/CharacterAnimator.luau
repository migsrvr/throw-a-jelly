--!strict
--[[
	CharacterAnimator.luau
	Universal R15 & R6 procedural full-body animation & prop-holding controller.

	Joints are posed as `Motor6D.C0 = OrigC0 * PoseOffset` (Humanoid.Animator never writes C0),
	with `Motor6D.Transform` forced to identity on the posed joints every Stepped (the documented
	point where scripts can override animation output). Rigs that use AnimationConstraint joints
	instead of Motor6D are posed through `AnimationConstraint.Transform`.

	The pose is applied from both RunService.Stepped and a BindToRenderStep at the LAST priority so
	no other per-frame writer (carry pose, aim pose, Animate script) can win during the pitch.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SlimeFactory = require(script.Parent:WaitForChild("SlimeFactory"))
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local PullUpMotion = require(script.Parent:WaitForChild("PullUpMotion"))

-- Temporary diagnostics for the "pitch does nothing" bug. Set to false once confirmed fixed.
local DEBUG = false
local VERSION = "pitch-v3"
local PITCH_RENDER_STEP = "CharacterAnimatorPitchPose"

local function dprint(...: any)
	if DEBUG then
		print("[CharacterAnimator]", ...)
	end
end

dprint("loaded", VERSION, if RunService:IsClient() then "(client)" else "(server)")

local CharacterAnimator = {}

local activeAimBait: Model? = nil
local activeAimConn: RBXScriptConnection? = nil
local activeAimRig: RigMotors? = nil
local isThrowing = false
local isPullingUp = false -- true while the pull-up loop owns the joints
local activeThrowCleanup: (() -> ())? = nil

local activeCarryModel: Model? = nil
local activeCarryConn: RBXScriptConnection? = nil
local activeCarryRig: RigMotors? = nil

-- Cache original Motor6D.C0 per Motor6D instance so we never drift or lose the avatar's proportions
local origC0Cache: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
-- Last C0 this module wrote, used by the debug watcher to detect other scripts overwriting joints
local lastWrittenC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

-- Each joint is a Motor6D or an AnimationConstraint (both are posed through `setMotorPose`)
export type RigMotors = {
	IsR15: boolean,
	Root: Instance?,
	Waist: Instance?,
	Neck: Instance?,
	RightShoulder: Instance?,
	RightElbow: Instance?,
	LeftShoulder: Instance?,
	LeftElbow: Instance?,
	LeftHip: Instance?,
	LeftKnee: Instance?,
	RightHip: Instance?,
	RightKnee: Instance?,
}

local JOINT_KEYS = {
	"Root",
	"Waist",
	"Neck",
	"RightShoulder",
	"RightElbow",
	"LeftShoulder",
	"LeftElbow",
	"LeftHip",
	"LeftKnee",
	"RightHip",
	"RightKnee",
}

local function getRightHandPart(character: Model): BasePart?
	return (character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

local function isPoseableJoint(inst: Instance?): boolean
	return inst ~= nil and (inst:IsA("Motor6D") or inst:IsA("AnimationConstraint"))
end

local function findMotor(character: Model, parent: Instance?, name: string): Instance?
	local joint = if parent then parent:FindFirstChild(name) else nil
	if not isPoseableJoint(joint) then
		-- Fallback: some avatars keep joints elsewhere in the model or use AnimationConstraints
		joint = nil
		for _, d in character:GetDescendants() do
			if d.Name == name and isPoseableJoint(d) then
				joint = d
				break
			end
		end
	end
	if joint and joint:IsA("Motor6D") and not origC0Cache[joint] then
		origC0Cache[joint] = joint.C0
	end
	return joint
end

local function setMotorPose(joint: Instance?, poseOffset: CFrame)
	if not joint then
		return
	end
	if joint:IsA("Motor6D") then
		local base = origC0Cache[joint]
		if not base then
			base = joint.C0
			origC0Cache[joint] = base
		end
		local c0 = base * poseOffset
		lastWrittenC0[joint] = c0
		joint.C0 = c0
		joint.Transform = CFrame.identity
	elseif joint:IsA("AnimationConstraint") then
		joint.Transform = poseOffset
	end
end

local function getRigMotors(character: Model): RigMotors
	local upperTorso = character:FindFirstChild("UpperTorso")
	local lowerTorso = character:FindFirstChild("LowerTorso")
	if upperTorso or lowerTorso then
		return {
			IsR15 = true,
			Root = findMotor(character, lowerTorso, "Root"),
			Waist = findMotor(character, upperTorso, "Waist"),
			Neck = findMotor(character, character:FindFirstChild("Head"), "Neck"),
			RightShoulder = findMotor(character, character:FindFirstChild("RightUpperArm"), "RightShoulder"),
			RightElbow = findMotor(character, character:FindFirstChild("RightLowerArm"), "RightElbow"),
			LeftShoulder = findMotor(character, character:FindFirstChild("LeftUpperArm"), "LeftShoulder"),
			LeftElbow = findMotor(character, character:FindFirstChild("LeftLowerArm"), "LeftElbow"),
			LeftHip = findMotor(character, character:FindFirstChild("LeftUpperLeg"), "LeftHip"),
			LeftKnee = findMotor(character, character:FindFirstChild("LeftLowerLeg"), "LeftKnee"),
			RightHip = findMotor(character, character:FindFirstChild("RightUpperLeg"), "RightHip"),
			RightKnee = findMotor(character, character:FindFirstChild("RightLowerLeg"), "RightKnee"),
		}
	else
		local torso = character:FindFirstChild("Torso")
		local root = character:FindFirstChild("HumanoidRootPart")
		return {
			IsR15 = false,
			Root = findMotor(character, root, "RootJoint"),
			Waist = nil,
			Neck = findMotor(character, torso, "Neck"),
			RightShoulder = findMotor(character, torso, "Right Shoulder"),
			RightElbow = nil,
			LeftShoulder = findMotor(character, torso, "Left Shoulder"),
			LeftElbow = nil,
			LeftHip = findMotor(character, torso, "Left Hip"),
			LeftKnee = nil,
			RightHip = findMotor(character, torso, "Right Hip"),
			RightKnee = nil,
		}
	end
end

local function rigJoints(rig: RigMotors): { Instance }
	local list = {}
	local r = rig :: any
	for _, key in JOINT_KEYS do
		local j = r[key]
		if j then
			table.insert(list, j)
		end
	end
	return list
end

local function resetRigMotors(rig: RigMotors)
	for _, j in rigJoints(rig) do
		if j:IsA("Motor6D") then
			local orig = origC0Cache[j]
			if orig then
				lastWrittenC0[j] = orig
				j.C0 = orig
			end
		elseif j:IsA("AnimationConstraint") then
			j.Transform = CFrame.identity
		end
	end
end

-- Speed-0 pause (not Stop) keeps the Animate script's internal state valid so idle resumes cleanly.
-- The posed joints are still fully overridden because setMotorPose forces Transform every Stepped.
local function pauseActiveAnimationTracks(character: Model): { { Track: AnimationTrack, Speed: number } }
	local paused = {}
	local hum = character:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			table.insert(paused, { Track = track, Speed = track.Speed })
			track:AdjustSpeed(0)
		end
	end
	return paused
end

local function resumeAnimationTracks(paused: { { Track: AnimationTrack, Speed: number } })
	for _, item in paused do
		pcall(function()
			item.Track:AdjustSpeed(item.Speed)
		end)
	end
end

local function sameCFrame(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-3
		and a.LookVector:Dot(b.LookVector) > 0.9999
		and a.UpVector:Dot(b.UpVector) > 0.9999
end

local function describeJoint(label: string, joint: Instance?): string
	if not joint then
		return `{label}=MISSING`
	end
	if joint:IsA("Motor6D") then
		local orig = origC0Cache[joint] or joint.C0
		local _, angle = (orig:Inverse() * joint.C0):ToAxisAngle()
		local p0, p1 = joint.Part0, joint.Part1
		local err = -1
		local anchored = "?"
		if p0 and p1 then
			local expected = p0.CFrame * joint.C0 * joint.Transform * joint.C1:Inverse()
			err = (expected.Position - p1.Position).Magnitude
			anchored = tostring(p1.Anchored)
		end
		return string.format(
			"%s=Motor6D(C0 offset %.0fdeg, Part1 err %.2f studs, Enabled=%s, Part1Anchored=%s)",
			label,
			math.deg(angle),
			err,
			tostring(joint.Enabled),
			anchored
		)
	end
	return `{label}={joint.ClassName}`
end

local function spawnAnimeChargeAura(footPosition: Vector3)
	for i = 1, 2 do
		task.delay((i - 1) * 0.12, function()
			local ring = Instance.new("Part")
			ring.Name = "AnimePitchAura"
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(0.25, 2.8, 2.8)
			ring.CFrame = CFrame.new(footPosition) * CFrame.Angles(0, 0, math.rad(90))
			ring.Material = Enum.Material.Neon
			ring.Color = if i == 1 then Color3.fromRGB(255, 225, 85) else Color3.fromRGB(110, 235, 255)
			ring.Transparency = 0.15
			ring.Anchored = true
			ring.CanCollide = false
			ring.CastShadow = false
			ring.Parent = workspace

			TweenService:Create(ring, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.08, 14.0, 14.0),
				Transparency = 1,
			}):Play()
			task.delay(0.42, function()
				ring:Destroy()
			end)
		end)
	end
end

local function spawnAnimeReleaseSonicBoom(releasePosition: Vector3)
	for i = 1, 2 do
		local ring = Instance.new("Part")
		ring.Name = "AnimeSonicBoom"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.24, 2.0, 2.0)
		ring.CFrame = CFrame.new(releasePosition + Vector3.new(0, 0, (i - 1) * 1.5))
			* CFrame.Angles(0, math.rad(90), 0)
		ring.Material = Enum.Material.Neon
		ring.Color = if i == 1 then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(110, 235, 255)
		ring.Transparency = 0.08
		ring.Anchored = true
		ring.CanCollide = false
		ring.CastShadow = false
		ring.Parent = workspace

		TweenService:Create(ring, TweenInfo.new(0.42, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.08, 12.5 - i * 2, 12.5 - i * 2),
			Transparency = 1,
		}):Play()
		task.delay(0.45, function()
			ring:Destroy()
		end)
	end
end

function CharacterAnimator.IsThrowing(): boolean
	return isThrowing
end

function CharacterAnimator.StartAimPose(character: Model?)
	if not character or isThrowing or isPullingUp then
		return
	end
	-- Always put away any carried hotbar slime when entering the throw-line aim stance
	CharacterAnimator.StopCarrySlime()
	if activeAimBait and activeAimBait.Parent then
		return
	end

	CharacterAnimator.StopAimPose()

	local bait = SlimeFactory.CreateJellyBaitModel()
	bait.Parent = workspace
	activeAimBait = bait

	local rig = getRigMotors(character)
	activeAimRig = rig

	activeAimConn = RunService.Stepped:Connect(function()
		if not character.Parent or isThrowing then
			return
		end
		local hand = getRightHandPart(character)
		if hand and activeAimBait then
			local holdCf = hand.CFrame * CFrame.new(0, -0.35, -0.65) * CFrame.Angles(math.rad(-20), 0, 0)
			SlimeFactory.PositionBait(activeAimBait, holdCf)
		end

		local bob = math.sin(os.clock() * 4.5) * 5
		if rig.IsR15 then
			setMotorPose(rig.RightShoulder, CFrame.Angles(math.rad(72 + bob), math.rad(12), math.rad(16)))
			setMotorPose(rig.RightElbow, CFrame.Angles(math.rad(42), 0, 0))
		else
			setMotorPose(rig.RightShoulder, CFrame.Angles(0, 0, math.rad(72 + bob)))
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
	-- Put the raised aim-arm back down (the throw resets the whole rig itself when it finishes)
	if activeAimRig and not isThrowing then
		resetRigMotors(activeAimRig)
	end
	activeAimRig = nil
end

type ThrowPose = {
	rootShiftZ: number,
	rootShiftY: number,
	rootYaw: number,
	rootPitch: number,
	waistYaw: number,
	waistPitch: number,
	neckYaw: number,
	rArmPitch: number,
	rArmRoll: number,
	rElbowPitch: number,
	lArmPitch: number,
	lArmRoll: number,
	lElbowPitch: number,
	lHipPitch: number,
	lKneePitch: number,
	rHipPitch: number,
	rKneePitch: number,
}

local WINDUP_DUR = 0.5 -- Phase 1: High anime knee-kick, pelvis drop & deep coil
local WHIP_DUR = 0.2 -- Phase 2: Explosive forward stride lunge & overhead whip
local FOLLOW_DUR = 0.35 -- Phase 3: Cross-body follow-through & back-leg high kick
local THROW_TOTAL_DUR = WINDUP_DUR + WHIP_DUR + FOLLOW_DUR
local RELEASE_AT = WINDUP_DUR + WHIP_DUR * 0.55

local function computeThrowPose(elapsed: number): ThrowPose
	local p: ThrowPose = {
		rootShiftZ = 0,
		rootShiftY = 0,
		rootYaw = 0,
		rootPitch = 0,
		waistYaw = 0,
		waistPitch = 0,
		neckYaw = 0,
		rArmPitch = 72,
		rArmRoll = 16,
		rElbowPitch = 42,
		lArmPitch = 0,
		lArmRoll = 0,
		lElbowPitch = 0,
		lHipPitch = 0,
		lKneePitch = 0,
		rHipPitch = 0,
		rKneePitch = 0,
	}

	if elapsed <= WINDUP_DUR then
		-- Phase 1: Exaggerated Anime Pitcher High Leg-Kick & Deep Full-Body Coil
		local u = math.clamp(elapsed / WINDUP_DUR, 0, 1)
		local a = 1 - ((1 - u) ^ 2)

		p.rootShiftZ = 1.1 * a -- Shift backward on the mound (+Z in local rig space is back)
		p.rootShiftY = -0.45 * a -- Drop pelvis into coiled crouch
		p.rootYaw = -65 * a
		p.rootPitch = 22 * a -- Lean whole body backward!

		p.waistYaw = -24 * a
		p.waistPitch = 12 * a
		p.neckYaw = 68 * a -- Keep eyes glaring forward down the lane!

		p.rArmPitch = 72 + (168 - 72) * a
		p.rArmRoll = 16 + (44 - 16) * a
		p.rElbowPitch = 42 + (78 - 42) * a

		p.lArmPitch = 96 * a -- Left glove-arm pointing straight at target!
		p.lArmRoll = -26 * a
		p.lElbowPitch = 18 * a

		p.lHipPitch = 115 * a -- Huge anime knee kick up into chest!
		p.lKneePitch = -120 * a
		p.rHipPitch = -26 * a
		p.rKneePitch = -36 * a
	elseif elapsed <= WINDUP_DUR + WHIP_DUR then
		-- Phase 2: Explosive Forward Power Stride & Violent Overhead Whip
		local a = math.clamp((elapsed - WINDUP_DUR) / WHIP_DUR, 0, 1)

		p.rootShiftZ = 1.1 + (-2.2 - 1.1) * a -- Lunge 2.2 studs forward toward the lane!
		p.rootShiftY = -0.45 + (-0.70 - -0.45) * a
		p.rootYaw = -65 + (52 - -65) * a
		p.rootPitch = 22 + (-30 - 22) * a -- Explosive forward torso tilt!

		p.waistYaw = -24 + (26 - -24) * a
		p.waistPitch = 12 + (-16 - 12) * a
		p.neckYaw = 68 * (1 - a)

		p.rArmPitch = 168 + (12 - 168) * a
		p.rArmRoll = 44 + (-25 - 44) * a
		p.rElbowPitch = 78 * (1 - a)

		p.lArmPitch = 96 + (22 - 96) * a -- Snap glove-arm into ribs!
		p.lArmRoll = -26 + (-52 - -26) * a
		p.lElbowPitch = 18 + (90 - 18) * a

		p.lHipPitch = 115 + (52 - 115) * a -- Plant front stride leg forward!
		p.lKneePitch = -120 + (-28 - -120) * a
		p.rHipPitch = -26 + (-68 - -26) * a -- Drive off back leg!
		p.rKneePitch = -36 + (-48 - -36) * a
	else
		-- Phase 3: Sweeping Cross-Body Follow-Through & Back-Leg High Kick
		local u = math.clamp((elapsed - WINDUP_DUR - WHIP_DUR) / FOLLOW_DUR, 0, 1)
		local a = 1 - u
		local kickWave = math.sin(u * math.pi)

		p.rootShiftZ = -2.2 * a
		p.rootShiftY = -0.70 * a
		p.rootYaw = 52 * a
		p.rootPitch = (-30 - 12 * kickWave) * a

		p.waistYaw = 26 * a
		p.waistPitch = -16 * a
		p.neckYaw = 0

		p.rArmPitch = (12 - 42 * kickWave) * a
		p.rArmRoll = -42 * a
		p.rElbowPitch = 36 * a

		p.lArmPitch = 22 * a
		p.lArmRoll = -52 * a
		p.lElbowPitch = 90 * a

		p.lHipPitch = 52 * a
		p.lKneePitch = -28 * a
		p.rHipPitch = (-68 - 28 * kickWave) * a -- Back leg kicks high behind!
		p.rKneePitch = (-48 - 32 * kickWave) * a
	end

	return p
end

local function applyThrowPose(rig: RigMotors, p: ThrowPose)
	if rig.IsR15 then
		setMotorPose(
			rig.Root,
			CFrame.new(0, p.rootShiftY, p.rootShiftZ) * CFrame.Angles(math.rad(p.rootPitch), math.rad(p.rootYaw), 0)
		)
		setMotorPose(rig.Waist, CFrame.Angles(math.rad(p.waistPitch), math.rad(p.waistYaw), 0))
		setMotorPose(rig.Neck, CFrame.Angles(math.rad(-p.rootPitch * 0.5), math.rad(p.neckYaw), 0))
		setMotorPose(rig.RightShoulder, CFrame.Angles(math.rad(p.rArmPitch), 0, math.rad(p.rArmRoll)))
		setMotorPose(rig.RightElbow, CFrame.Angles(math.rad(p.rElbowPitch), 0, 0))
		setMotorPose(rig.LeftShoulder, CFrame.Angles(math.rad(p.lArmPitch), 0, math.rad(p.lArmRoll)))
		setMotorPose(rig.LeftElbow, CFrame.Angles(math.rad(p.lElbowPitch), 0, 0))
		setMotorPose(rig.LeftHip, CFrame.Angles(math.rad(p.lHipPitch), 0, 0))
		setMotorPose(rig.LeftKnee, CFrame.Angles(math.rad(p.lKneePitch), 0, 0))
		setMotorPose(rig.RightHip, CFrame.Angles(math.rad(p.rHipPitch), 0, 0))
		setMotorPose(rig.RightKnee, CFrame.Angles(math.rad(p.rKneePitch), 0, 0))
	else
		-- R6 RootJoint has rotated local axes
		setMotorPose(
			rig.Root,
			CFrame.new(0, -p.rootShiftZ, p.rootShiftY) * CFrame.Angles(math.rad(-p.rootPitch), 0, math.rad(-p.rootYaw))
		)
		setMotorPose(rig.RightShoulder, CFrame.Angles(0, 0, math.rad(p.rArmPitch)))
		setMotorPose(rig.LeftShoulder, CFrame.Angles(0, 0, math.rad(-p.lArmPitch)))
		setMotorPose(rig.LeftHip, CFrame.Angles(0, 0, math.rad(-p.lHipPitch)))
		setMotorPose(rig.RightHip, CFrame.Angles(0, 0, math.rad(p.rHipPitch)))
	end
end

function CharacterAnimator.PlayThrowAnimation(character: Model?, onRelease: (Vector3) -> (), onFinished: (() -> ())?)
	if activeThrowCleanup then
		activeThrowCleanup()
	end

	if not character then
		onRelease(Vector3.new(0, 32, -3.6))
		if onFinished then
			onFinished()
		end
		return
	end

	isThrowing = true
	local hum = character:FindFirstChildOfClass("Humanoid")
	local savedWalkSpeed, savedJumpPower, savedJumpHeight = 16, 50, 7.2
	if hum then
		hum.AutoRotate = false
		-- Plant the pitcher: stops walk/jump animations from kicking in mid-pitch
		savedWalkSpeed, savedJumpPower, savedJumpHeight = hum.WalkSpeed, hum.JumpPower, hum.JumpHeight
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
	end
	local pausedTracks = pauseActiveAnimationTracks(character)

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then
		local pos = rootPart.Position
		rootPart.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 25))
		spawnAnimeChargeAura(pos - Vector3.new(0, 2.7, 0))
	end

	if not activeAimBait or not activeAimBait.Parent then
		local bait = SlimeFactory.CreateJellyBaitModel()
		bait.Parent = workspace
		activeAimBait = bait
	end

	local rig = getRigMotors(character)

	local watchConns: { RBXScriptConnection } = {}
	if DEBUG then
		local missing = {}
		local r = rig :: any
		for _, key in JOINT_KEYS do
			if r[key] == nil then
				table.insert(missing, key)
			end
		end
		dprint(
			`throw start | rig={if rig.IsR15 then "R15" else "R6"} | missing=[{table.concat(missing, ", ")}]`,
			"|",
			describeJoint("Root", rig.Root),
			"|",
			describeJoint("RightShoulder", rig.RightShoulder)
		)

		-- Detect any other script writing these joints' C0 during the pitch
		for _, j in rigJoints(rig) do
			if j:IsA("Motor6D") then
				local motor = j
				local reported = false
				table.insert(
					watchConns,
					motor:GetPropertyChangedSignal("C0"):Connect(function()
						local mine = lastWrittenC0[motor]
						if not reported and mine and not sameCFrame(motor.C0, mine) then
							reported = true
							dprint(`WARNING: another script overwrote {motor:GetFullName()}.C0 during the pitch`)
						end
					end)
				)
			end
		end
	end

	local startClock = os.clock()
	local released = false
	local finished = false
	local debugReported = false
	local stepConn: RBXScriptConnection? = nil

	local function finish()
		if finished then
			return
		end
		finished = true
		if stepConn then
			stepConn:Disconnect()
			stepConn = nil
		end
		if RunService:IsClient() then
			RunService:UnbindFromRenderStep(PITCH_RENDER_STEP)
		end
		for _, c in watchConns do
			c:Disconnect()
		end
		resetRigMotors(rig)
		resumeAnimationTracks(pausedTracks)
		if hum then
			hum.AutoRotate = true
			hum.WalkSpeed = savedWalkSpeed
			hum.JumpPower = savedJumpPower
			hum.JumpHeight = savedJumpHeight
		end
		isThrowing = false
		activeThrowCleanup = nil
		dprint("throw finished")
		if onFinished then
			task.spawn(onFinished)
		end
	end
	activeThrowCleanup = finish

	stepConn = RunService.Stepped:Connect(function()
		if not character.Parent then
			finish()
			return
		end
		local elapsed = os.clock() - startClock
		applyThrowPose(rig, computeThrowPose(math.min(elapsed, THROW_TOTAL_DUR)))

		if not released and elapsed >= RELEASE_AT then
			released = true
			local hand = getRightHandPart(character)
			local releaseOrigin = if hand
				then hand.Position + Vector3.new(0, 0.8, 1.5)
				elseif rootPart then rootPart.Position + Vector3.new(0, 1.8, 2.0)
				else Vector3.new(0, 32, -3.6)

			spawnAnimeReleaseSonicBoom(releaseOrigin)
			CharacterAnimator.StopAimPose()
			onRelease(releaseOrigin)
		end

		if not released and activeAimBait then
			local hand = getRightHandPart(character)
			if hand then
				SlimeFactory.PositionBait(activeAimBait, hand.CFrame * CFrame.new(0, -0.3, -0.6))
			end
		end

		if elapsed >= THROW_TOTAL_DUR then
			finish()
		end
	end)

	if RunService:IsClient() then
		RunService:BindToRenderStep(PITCH_RENDER_STEP, Enum.RenderPriority.Last.Value, function()
			if finished then
				return
			end
			local elapsed = os.clock() - startClock
			if DEBUG and not debugReported and elapsed >= 0.2 then
				-- Checked before re-applying, so this reflects what physics actually did with our C0
				debugReported = true
				dprint(
					"t=0.2s |",
					describeJoint("Root", rig.Root),
					"|",
					describeJoint("RightShoulder", rig.RightShoulder),
					"|",
					describeJoint("LeftHip", rig.LeftHip)
				)
			end
			applyThrowPose(rig, computeThrowPose(math.min(elapsed, THROW_TOTAL_DUR)))
		end)
	end
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

	local rig = getRigMotors(character)
	activeCarryRig = rig

	activeCarryConn = RunService.Stepped:Connect(function()
		-- Never fight the pitch for the shoulder joints
		if not character.Parent or not activeCarryModel or isThrowing or isPullingUp then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local carryCf = root.CFrame * CFrame.new(0, 0.3, -2.1)
			SlimeFactory.PositionSlime(activeCarryModel, carryCf, 0.08 * math.sin(os.clock() * 6))
		end

		if rig.IsR15 then
			setMotorPose(rig.RightShoulder, CFrame.Angles(math.rad(75), 0, math.rad(-18)))
			setMotorPose(rig.LeftShoulder, CFrame.Angles(math.rad(75), 0, math.rad(18)))
		else
			setMotorPose(rig.RightShoulder, CFrame.Angles(0, 0, math.rad(75)))
			setMotorPose(rig.LeftShoulder, CFrame.Angles(0, 0, math.rad(-75)))
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
	if activeCarryRig and not isThrowing and not isPullingUp then
		resetRigMotors(activeCarryRig)
	end
	activeCarryRig = nil
end

-- ============================================================================
-- LOOPING PULL-UP (client-side only; the server holds the character under the bar
-- and owns the rep cadence). One full cycle = one rep = `getInterval()` seconds.
-- The exaggerated motion curve + pose live in PullUpMotion (pure, unit-tested).
-- Peak (chin over bar) is phase 0.5; the server pays the first rep at half an interval,
-- and CharacterAnimator.SyncPullUpRep() nudges the phase so every paid rep lands on the peak.
-- ============================================================================
local PULLUP_RENDER_STEP = "CharacterAnimatorPullUp"
local PULLUP_SYNC_STRENGTH = 0.35 -- fraction of the phase error corrected per paid rep
local pullUpStop: (() -> ())? = nil -- soft stop: ease down, then release joints
local pullUpKill: (() -> ())? = nil -- hard stop: release joints immediately
local pullUpSync: (() -> ())? = nil -- phase-lock to a server rep

local function applyPullUpPose(rig: RigMotors, p: PullUpMotion.Pose)
	if rig.IsR15 then
		-- Body rises/leans/rolls from the pelvis; arms fold at the elbows to "pull" the body up
		setMotorPose(rig.Root, CFrame.new(0, p.Rise, 0) * CFrame.Angles(math.rad(p.Lean), 0, math.rad(p.Roll)))
		setMotorPose(rig.Waist, CFrame.Angles(math.rad(p.Lean * 0.5), 0, 0))
		setMotorPose(rig.Neck, CFrame.Angles(math.rad(p.Neck), 0, 0))
		setMotorPose(rig.RightShoulder, CFrame.Angles(math.rad(p.ShoulderR15), 0, math.rad(-8)))
		setMotorPose(rig.LeftShoulder, CFrame.Angles(math.rad(p.ShoulderR15), 0, math.rad(8)))
		setMotorPose(rig.RightElbow, CFrame.Angles(math.rad(p.Elbow), 0, 0))
		setMotorPose(rig.LeftElbow, CFrame.Angles(math.rad(p.Elbow), 0, 0))
		setMotorPose(rig.LeftHip, CFrame.Angles(math.rad(p.HipL), 0, 0))
		setMotorPose(rig.RightHip, CFrame.Angles(math.rad(p.HipR), 0, 0))
		setMotorPose(rig.LeftKnee, CFrame.Angles(math.rad(-p.KneeL), 0, 0))
		setMotorPose(rig.RightKnee, CFrame.Angles(math.rad(-p.KneeR), 0, 0))
	else
		-- R6 RootJoint axes are rotated (local Z = up, local Y = forward); no elbows/knees, so the
		-- shoulders swing further and the hips take the knee tuck.
		setMotorPose(
			rig.Root,
			CFrame.new(0, 0, p.Rise) * CFrame.Angles(math.rad(-p.Lean), math.rad(p.Roll), 0)
		)
		setMotorPose(rig.Neck, CFrame.Angles(math.rad(-p.Neck), 0, 0))
		setMotorPose(rig.RightShoulder, CFrame.Angles(0, 0, math.rad(p.ShoulderR6)))
		setMotorPose(rig.LeftShoulder, CFrame.Angles(0, 0, math.rad(-p.ShoulderR6)))
		setMotorPose(rig.LeftHip, CFrame.Angles(0, 0, math.rad(-(p.HipL + 0.5 * p.KneeL))))
		setMotorPose(rig.RightHip, CFrame.Angles(0, 0, math.rad(p.HipR + 0.5 * p.KneeR)))
	end
end

-- Call when the server pays a rep (TrainingRep): pulls the animation phase toward the peak.
function CharacterAnimator.SyncPullUpRep()
	if pullUpSync then
		pullUpSync()
	end
end

function CharacterAnimator.IsPullUpLooping(): boolean
	return pullUpStop ~= nil
end

function CharacterAnimator.StartPullUpLoop(character: Model?, getInterval: () -> number)
	if pullUpKill then
		pullUpKill()
	end
	if not character or not RunService:IsClient() then
		return
	end

	-- Yield the arms/legs: no aim pose or carried slime while hanging on the bar
	CharacterAnimator.StopAimPose()
	CharacterAnimator.StopCarrySlime()

	local rig = getRigMotors(character)
	local pausedTracks = pauseActiveAnimationTracks(character)
	local phase = 0
	local stopping = false
	local stopBlend = 1
	local lastClock = os.clock()

	if DEBUG then
		local missing = {}
		local r = rig :: any
		for _, key in JOINT_KEYS do
			if r[key] == nil then
				table.insert(missing, key)
			end
		end
		dprint(
			`pull-up start | rig={if rig.IsR15 then "R15" else "R6"} | missing=[{table.concat(missing, ", ")}]`,
			string.format("| interval=%.2fs", getInterval())
		)
	end

	local animCfg = GameConfig.PullUp.Anim
	local startClock = os.clock()
	local debugReported = false
	local stepConn: RBXScriptConnection? = nil
	local repIndex = 0
	local currentPose = PullUpMotion.Pose(0, 0, 0, 0, animCfg)

	local stopped = false
	local function stop()
		if stopped then
			return
		end
		stopped = true
		if stepConn then
			stepConn:Disconnect()
			stepConn = nil
		end
		RunService:UnbindFromRenderStep(PULLUP_RENDER_STEP)
		resetRigMotors(rig)
		resumeAnimationTracks(pausedTracks)
		pullUpStop = nil
		pullUpKill = nil
		pullUpSync = nil
		isPullingUp = false
		dprint("pull-up stopped")
	end
	pullUpKill = stop
	isPullingUp = true

	-- Advance the cycle and pose the joints. Runs in Stepped (before physics, like the working
	-- pitch); the render step below only re-applies the same pose so nothing else can win.
	stepConn = RunService.Stepped:Connect(function()
		local now = os.clock()
		local dt = math.min(now - lastClock, 0.1)
		lastClock = now
		if not character.Parent then
			stop()
			return
		end

		local interval = math.max(0.1, getInterval())
		local nextPhase = phase + dt / interval
		if nextPhase >= 1 then
			repIndex += 1 -- alternates the body roll each rep
		end
		phase = nextPhase % 1

		if stopping then
			-- Ease back down to the hang/rest over ~0.2s before handing joints back
			stopBlend = math.max(0, stopBlend - dt / 0.2)
			if stopBlend <= 0 then
				stop()
				return
			end
		end
		local scale = PullUpMotion.Intensity(interval) * stopBlend
		currentPose = PullUpMotion.Pose(phase, scale, repIndex, now, animCfg)
		applyPullUpPose(rig, currentPose)
	end)

	RunService:BindToRenderStep(PULLUP_RENDER_STEP, Enum.RenderPriority.Last.Value, function()
		if stopped then
			return
		end
		if DEBUG and not debugReported and os.clock() - startClock >= 0.5 then
			-- Checked before re-applying, so this reflects what physics actually did with our C0
			debugReported = true
			dprint(
				string.format("pull-up t=0.5s lift=%.2f |", currentPose.Lift),
				describeJoint("Root", rig.Root),
				"|",
				describeJoint("RightShoulder", rig.RightShoulder)
			)
		end
		applyPullUpPose(rig, currentPose)
	end)

	pullUpStop = function()
		stopping = true
	end
	pullUpSync = function()
		if not stopping then
			phase = (phase + PullUpMotion.PhaseDelta(phase, PullUpMotion.PEAK) * PULLUP_SYNC_STRENGTH) % 1
		end
	end
end

function CharacterAnimator.StopPullUpLoop()
	if pullUpStop then
		pullUpStop()
	end
end

return CharacterAnimator
