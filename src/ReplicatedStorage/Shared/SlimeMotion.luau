--!strict
--[[
	SlimeMotion.luau
	Catch-cutscene motion for slimes (client). The authored models are static meshes, so all motion is
	code-driven through SlimeFactory.PositionSlime and its optional pose layer:
	  - per-slime movement style (GameConfig SlimeDef.Motion): Hop (default), Fly, Slide, Waddle
	  - accessory spring: leaves / wings / hats lag and bounce after vertical motion; wings flap while flying
	  - face beats: blinks, and a "surprised" stretch when the slime first spots the bait
	  - eating the bait before the reveal

	Usage (see ThrowController runRevealCutscene):
		local rig = SlimeMotion.NewRig(model, SlimeMotion.GetStyle(slimeId))
		SlimeMotion.Emerge(rig, emergePos, floorY, baitPos, fx)
		SlimeMotion.Approach(rig, fromPos, toPos, baitPos, 0.46, step, fx)
		SlimeMotion.Hold(rig, 0.12)
		SlimeMotion.EatBait(rig, baitModel, slimePos, baitPos)
	Positions are ground-rest centre positions (floorY + 1.22); styles add their own offsets (Fly hovers).
]]

local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local SlimeFactory = require(script.Parent:WaitForChild("SlimeFactory"))

local SlimeMotion = {}

export type Style = GameConfig.SlimeMotionStyle

export type Fx = {
	Color: Color3, -- zone theme colour for ripples / dust
	Ripple: (pos: Vector3, color: Color3, maxDiameter: number, duration: number) -> (),
	Dust: ((pos: Vector3, color: Color3, sparkle: boolean) -> ())?,
	-- called when a walking step lands (not for flyers): ground position + step index (CatchFx landing effects)
	Landed: ((groundPos: Vector3, stepIndex: number) -> ())?,
	-- full-show struggle emergence (EmergeStruggle): prop rumble 0..1 every frame, and the burst moment
	PropShake: ((intensity: number) -> ())?,
	Burst: (() -> ())?,
}

-- How the slime comes out in the full show (CatchFxData zone Emerge)
export type EmergeStyle = "Burrow" | "Mound" | "Pool" | "Geode" | "Box" | "Bush"

export type Rig = {
	Model: Model,
	Style: Style,
	HasAccessories: boolean,
	-- accessory spring
	SpringX: number,
	SpringV: number,
	LastY: number?,
	LastT: number,
	-- face
	BlinkTime: number, -- seconds per blink (sleepy slimes blink slower)
	Bouncy: boolean, -- happy slimes overshoot on the showcase float-up
	BlinkStart: number, -- os.clock() of the current blink (or -1)
	NextBlink: number, -- os.clock() of the next automatic blink (math.huge = off)
	Surprise: number, -- current 0..1
	SurpriseTarget: number,
	-- last drive (for Hold)
	LastCf: CFrame,
	LastSquash: number,
	LastExtraTilt: Vector3?,
	JiggleT0: number, -- os.clock() of the last landing jiggle (-1 = none)
}

SlimeMotion.FLY_HOVER = 2.5 -- studs above the ground-rest height while flying
-- Cartoon exaggeration for squash / stretch, hop height and anticipation crouches
SlimeMotion.EXAGGERATION = 1.6
local EX = SlimeMotion.EXAGGERATION

local SPRING_K = 120
local SPRING_D = 12
local BLINK_TIME = 0.14
local FLAP_HZ = 6

function SlimeMotion.GetStyle(slimeId: string?): Style
	local def = if slimeId then GameConfig.SlimesById[slimeId] else nil
	local m = def and def.Motion
	if m and GameConfig.SlimeMotionStyles[m] then
		return m
	end
	return "Hop"
end

function SlimeMotion.NewRig(model: Model, style: Style): Rig
	return {
		Model = model,
		Style = style,
		HasAccessories = SlimeFactory.HasAccessories(model),
		SpringX = 0,
		SpringV = 0,
		LastY = nil,
		LastT = os.clock(),
		BlinkTime = BLINK_TIME,
		Bouncy = false,
		BlinkStart = -1,
		NextBlink = math.huge,
		Surprise = 0,
		SurpriseTarget = 0,
		LastCf = CFrame.new(),
		LastSquash = 0,
		LastExtraTilt = nil,
		JiggleT0 = -1,
	}
end

-- Jelly wobble after a landing (a damped squash oscillation added on top of whatever drives the slime)
function SlimeMotion.Jiggle(rig: Rig)
	rig.JiggleT0 = os.clock()
end

local function blink(rig: Rig)
	rig.BlinkStart = os.clock()
end

local function enableAutoBlink(rig: Rig)
	rig.NextBlink = os.clock() + 0.6 + math.random() * 0.9
end

local function ease(u: number): number
	return 1 - (1 - u) * (1 - u)
end

local function smooth(u: number): number
	return u * u * (3 - 2 * u)
end

-- Apply one frame: updates the accessory spring + face, then positions the model.
-- extraTilt adds a fixed accessory tilt on top (radians: pitch, yaw, roll-mirrored).
local function drive(rig: Rig, cf: CFrame, squash: number, extraTilt: Vector3?)
	local now = os.clock()
	local dt = math.clamp(now - rig.LastT, 1 / 240, 1 / 20)
	rig.LastT = now
	rig.LastCf, rig.LastSquash, rig.LastExtraTilt = cf, squash, extraTilt

	-- Accessory spring: moving up makes accessories droop, stopping makes them bounce
	local y = cf.Position.Y
	local vy = if rig.LastY then (y - rig.LastY) / dt else 0
	rig.LastY = y
	local target = math.clamp(-vy * 0.05, -0.4, 0.4)
	local acc = SPRING_K * (target - rig.SpringX) - SPRING_D * rig.SpringV
	rig.SpringV += acc * dt
	rig.SpringX += rig.SpringV * dt

	-- Face: surprise eases toward its target; blinks squash the face shut briefly
	rig.Surprise += (rig.SurpriseTarget - rig.Surprise) * math.min(1, dt * 10)
	if now >= rig.NextBlink then
		blink(rig)
		rig.NextBlink = now + 1.1 + math.random() * 0.9
	end
	local faceY = 1 + 0.25 * rig.Surprise
	if rig.BlinkStart >= 0 then
		local b = (now - rig.BlinkStart) / rig.BlinkTime
		if b >= 1 then
			rig.BlinkStart = -1
		else
			faceY *= 1 - 0.9 * math.sin(b * math.pi)
		end
	end

	-- Landing jiggle: 0.3 * e^(-8t) * sin(30t)
	if rig.JiggleT0 >= 0 then
		local jt = now - rig.JiggleT0
		if jt > 0.6 then
			rig.JiggleT0 = -1
		else
			squash += 0.3 * math.exp(-8 * jt) * math.sin(30 * jt)
		end
	end

	local pose: SlimeFactory.Pose = { FaceScaleY = faceY }
	if rig.HasAccessories then
		local tilt = Vector3.new(rig.SpringX * 0.6, 0, rig.SpringX * 0.25)
		if rig.Style == "Fly" then
			tilt += Vector3.new(0, 0, 0.45 * math.sin(now * math.pi * 2 * FLAP_HZ))
		end
		if extraTilt then
			tilt += extraTilt
		end
		pose.AccessoryTilt = tilt
		pose.AccessoryLift = rig.SpringX * 0.06
	end
	SlimeFactory.PositionSlime(rig.Model, cf, squash, pose)
end

local function flatLook(pos: Vector3, target: Vector3): CFrame
	local t = Vector3.new(target.X, pos.Y, target.Z)
	if (t - pos).Magnitude < 0.01 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, t)
end

local function runFor(duration: number, step: (u: number) -> ())
	local t0 = os.clock()
	while true do
		local u = math.clamp((os.clock() - t0) / duration, 0, 1)
		step(u)
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

-- Keep the slime alive (blinks, flaps, spring settling) for `seconds` without moving it
function SlimeMotion.Hold(rig: Rig, seconds: number)
	local cf, squash, extra = rig.LastCf, rig.LastSquash, rig.LastExtraTilt
	local t0 = os.clock()
	runFor(seconds, function()
		local c = cf
		if rig.Style == "Fly" then
			c = cf + Vector3.new(0, 0.12 * math.sin((os.clock() - t0) * math.pi * 2 * 1.4), 0)
		end
		drive(rig, c, squash, extra)
	end)
end

-- Stage A (~1.7s): peek out of the ground, glance at the bait, then pop out (or lift off, for flyers).
-- groundPos = ground-rest centre (floorY + 1.22) of the emerge spot.
function SlimeMotion.Emerge(rig: Rig, groundPos: Vector3, floorY: number, lookTarget: Vector3, fx: Fx)
	local deepY = floorY - 2.7
	local peekY = floorY + 0.15
	local surfaceY = floorY + 1.22
	local popPeakY = floorY + 1.95
	local x, z = groundPos.X, groundPos.Z
	local floorPos = Vector3.new(x, floorY, z)

	fx.Ripple(floorPos, fx.Color, 8.5, 0.75)

	-- Part 1 (0.70s): push the top of the head out of the floor
	runFor(0.70, function(u)
		local curY = deepY + (peekY - deepY) * ease(u)
		drive(rig, flatLook(Vector3.new(x, curY, z), lookTarget), -0.18 * u)
	end)

	-- Part 2 (0.38s): curious peek, glancing left and right; blinks, then spots the bait
	blink(rig)
	runFor(0.38, function(u)
		local glance = math.rad(14 * math.sin(u * math.pi * 2))
		if u > 0.7 then
			rig.SurpriseTarget = 1
		end
		drive(rig, flatLook(Vector3.new(x, peekY, z), lookTarget) * CFrame.Angles(0, glance, 0), 0.10)
	end)

	fx.Ripple(floorPos, fx.Color, 11.0, 0.65)
	if fx.Dust then
		fx.Dust(floorPos, fx.Color, rig.Style == "Fly")
	end

	-- Part 3 (0.62s): pop out (Fly: rise to hover height instead)
	if rig.Style == "Fly" then
		local topY = surfaceY + SlimeMotion.FLY_HOVER
		runFor(0.62, function(u)
			local curY = peekY + (topY - peekY) * ease(u)
			rig.SurpriseTarget = 1 - u
			drive(rig, flatLook(Vector3.new(x, curY, z), lookTarget), -0.2 * math.sin(u * math.pi))
		end)
	else
		runFor(0.62, function(u)
			local curY: number
			local squash: number
			local pitch = 0
			if u < 0.65 then
				local a = u / 0.65
				curY = peekY + (popPeakY - peekY) * ease(a)
				squash = -0.34 * math.sin(a * math.pi)
			else
				local a = (u - 0.65) / 0.35
				curY = popPeakY + (surfaceY - popPeakY) * a
				squash = 0.25 * EX * math.sin(a * math.pi)
				if rig.Style == "Slide" then
					pitch = -math.rad(22) * a -- flop forward onto the belly
				end
			end
			rig.SurpriseTarget = 1 - u
			drive(rig, flatLook(Vector3.new(x, curY, z), lookTarget) * CFrame.Angles(pitch, 0, 0), squash)
		end)
		SlimeMotion.Jiggle(rig)
	end
	rig.SurpriseTarget = 0
	enableAutoBlink(rig)
end

-- FULL SHOW emergence (~2.1-2.4s): the slime struggles out of the zone's intro prop, then bursts free.
--   Burrow  pokes up, gets stuck, wiggles, sinks back once, then rockets out spinning
--   Mound   starts inside a snow / sand mound, pushes its head out of the top, wiggles free, shakes itself off
--   Pool    rises slowly out of lava / goo, looks around, then jumps clear
--   Geode   hidden inside a crystal cluster that rattles and cracks, then shatters as it pops out
--   Box     a gift box rattles twice, then it springs out like a jack-in-the-box
--   Bush    hiding in a bush of tall flowers: rustles, peeks out and looks around, ducks back, then bursts out
-- fx.PropShake(0..1) is called every frame while the prop should rumble, fx.Burst() once at the burst.
-- Flyers end hovering; everyone else lands with a big squash and a jiggle. Returns when it stands at the spot.
function SlimeMotion.EmergeStruggle(
	rig: Rig,
	groundPos: Vector3,
	floorY: number,
	lookTarget: Vector3,
	fx: Fx,
	style: EmergeStyle
)
	local surfaceY = floorY + 1.22
	local x, z = groundPos.X, groundPos.Z
	local floorPos = Vector3.new(x, floorY, z)
	local function at(y: number): CFrame
		return flatLook(Vector3.new(x, y, z), lookTarget)
	end
	local function shake(k: number)
		if fx.PropShake then
			fx.PropShake(k)
		end
	end

	-- Where it starts and where its head pokes out
	local hiddenY: number
	local peekY: number
	if style == "Burrow" then
		hiddenY, peekY = floorY - 2.7, floorY + 0.15
	elseif style == "Pool" then
		hiddenY, peekY = floorY - 2.4, floorY + 0.6
	elseif style == "Mound" then
		hiddenY, peekY = surfaceY - 0.9, surfaceY + 0.35
	elseif style == "Bush" then
		-- crouched low behind the leafy base; the peek brings its eyes up between the flowers
		hiddenY, peekY = surfaceY - 0.9, surfaceY + 0.25
	else -- Geode / Box: fully hidden inside the prop the whole time until the burst
		hiddenY, peekY = surfaceY - 0.15, surfaceY - 0.15
	end

	fx.Ripple(floorPos, fx.Color, 8.5, 0.75)

	if style == "Bush" then
		-- Something is rustling in there...
		runFor(0.4, function(u)
			shake(0.4)
			drive(rig, at(hiddenY + 0.06 * math.abs(math.sin(u * 28))) * CFrame.Angles(0, 0, math.rad(8 * math.sin(u * 30))), 0.12 * math.sin(u * 26))
		end)
		-- ...it peeks up between the flowers
		runFor(0.3, function(u)
			shake(0.25)
			drive(rig, at(hiddenY + (peekY - hiddenY) * ease(u)), -0.12 * u * EX)
		end)
		blink(rig)
		-- looks left and right
		runFor(0.55, function(u)
			shake(0.2)
			if u > 0.65 then
				rig.SurpriseTarget = 1
			end
			drive(rig, at(peekY) * CFrame.Angles(0, math.rad(24 * math.sin(u * math.pi * 2)), 0), 0.08)
		end)
		-- spotted! ducks back down to hide
		runFor(0.18, function(u)
			shake(0.6)
			drive(rig, at(peekY + (hiddenY - peekY) * ease(u)), 0.25 * u * EX)
		end)
		rig.SurpriseTarget = 0
		-- big rustle, gathering courage
		runFor(0.3, function(u)
			shake(1)
			drive(rig, at(hiddenY + 0.1 * math.abs(math.sin(u * 40))) * CFrame.Angles(0, 0, math.rad(12 * math.sin(u * 36))), 0.3 * math.sin(u * 35))
		end)
		shake(0)
	elseif style == "Geode" or style == "Box" then
		-- Rattle (0.6s), pause, bigger rattle (0.35s): the slime bumps around inside
		runFor(0.6, function(u)
			shake(0.45 * math.sin(u * math.pi))
			drive(rig, at(hiddenY + 0.1 * math.abs(math.sin(u * 30))), 0.2 * math.sin(u * 25))
		end)
		runFor(0.15, function(_u)
			shake(0)
			drive(rig, at(hiddenY), 0)
		end)
		runFor(0.35, function(u)
			shake(1)
			drive(rig, at(hiddenY + 0.15 * math.abs(math.sin(u * 40))), 0.35 * math.sin(u * 35))
		end)
		shake(0)
	else
		-- Push the head out (Pool: slow rise with drips)
		local riseTime = if style == "Pool" then 0.8 else 0.6
		runFor(riseTime, function(u)
			shake(0.3 * u)
			drive(rig, at(hiddenY + (peekY - hiddenY) * ease(u)), -0.18 * u * EX)
		end)
		-- Stuck! wiggle side to side (Pool: looks around instead)
		blink(rig)
		runFor(0.5, function(u)
			if style == "Pool" then
				local glance = math.rad(18 * math.sin(u * math.pi * 2))
				if u > 0.6 then
					rig.SurpriseTarget = 1
				end
				drive(rig, at(peekY) * CFrame.Angles(0, glance, 0), 0.1)
			else
				shake(0.6 + 0.4 * math.sin(u * math.pi))
				local roll = math.rad(16 * math.sin(u * math.pi * 7))
				drive(rig, at(peekY + 0.06 * math.sin(u * math.pi * 14)) * CFrame.Angles(0, 0, roll), 0.18 * math.sin(u * math.pi * 7))
			end
		end)
		if style ~= "Pool" then
			-- ...sinks back a little, gathering strength
			runFor(0.25, function(u)
				shake(0.2)
				drive(rig, at(peekY - 0.45 * math.sin(u * math.pi * 0.5)), 0.3 * EX * u)
			end)
		end
		shake(0)
	end

	-- BURST: rocket up with a full spin and a huge stretch
	rig.SurpriseTarget = 1
	if fx.Burst then
		fx.Burst()
	end
	fx.Ripple(floorPos, fx.Color, 13, 0.6)
	if fx.Dust then
		fx.Dust(floorPos, fx.Color, rig.Style == "Fly")
	end
	local burstFrom = rig.LastCf.Position.Y
	local peak = surfaceY + (if style == "Box" then 3.4 else 2.6)
	runFor(0.45, function(u)
		local y = burstFrom + (peak - burstFrom) * ease(u)
		local spin = math.pi * 2 * ease(u)
		drive(rig, at(y) * CFrame.Angles(0, spin, 0), -0.42 * (1 - u) * EX)
	end)

	if rig.Style == "Fly" then
		-- flyers settle into their hover
		local hoverY = surfaceY + SlimeMotion.FLY_HOVER
		runFor(0.4, function(u)
			drive(rig, at(peak + (hoverY - peak) * smooth(u)), 0)
		end)
	else
		-- fall and SPLAT
		runFor(0.35, function(u)
			drive(rig, at(peak + (surfaceY - peak) * u * u), -0.2 * (1 - u))
		end)
		runFor(0.12, function(u)
			drive(rig, at(surfaceY), 0.5 * math.sin(u * math.pi))
		end)
		SlimeMotion.Jiggle(rig)
		if style == "Mound" then
			-- shake itself clean
			runFor(0.3, function(u)
				local yaw = math.rad(22 * math.sin(u * math.pi * 8) * (1 - u))
				drive(rig, at(surfaceY) * CFrame.Angles(0, yaw, 0), 0.05)
			end)
		end
		fx.Ripple(floorPos, fx.Color, 9, 0.45)
	end
	rig.SurpriseTarget = 0
	enableAutoBlink(rig)
end

-- Stage B: one step toward the bait (call 5 times). from/to are ground-rest centre positions.
function SlimeMotion.Approach(
	rig: Rig,
	from: Vector3,
	to: Vector3,
	baitPos: Vector3,
	duration: number,
	stepIndex: number,
	fx: Fx
)
	local tiltDir = if stepIndex % 2 == 1 then 1 else -1
	local style = rig.Style

	if style == "Fly" then
		local hover = Vector3.new(0, SlimeMotion.FLY_HOVER, 0)
		runFor(duration, function(u)
			local horiz = from:Lerp(to, smooth(u))
			local bob = 0.35 * math.sin((stepIndex - 1 + u) * math.pi * 1.8)
			local pos = horiz + hover + Vector3.new(0, bob, 0)
			local bank = math.rad(8) * tiltDir * math.sin(u * math.pi)
			drive(rig, flatLook(pos, baitPos) * CFrame.Angles(math.rad(-6), 0, bank), 0)
		end)
		return
	end

	if style == "Slide" then
		local lean = -math.rad(22)
		runFor(duration, function(u)
			local pos = from:Lerp(to, smooth(u)) + Vector3.new(0, -0.15, 0)
			local wobble = math.rad(5) * math.sin((stepIndex - 1 + u) * math.pi * 2)
			-- accessories stream backwards with speed
			local speed = math.sin(u * math.pi)
			drive(
				rig,
				flatLook(pos, baitPos) * CFrame.Angles(lean, 0, wobble),
				0.12 * EX,
				Vector3.new(0.25 * speed, 0, 0)
			)
		end)
		SlimeMotion.Jiggle(rig)
		fx.Ripple(Vector3.new(to.X, to.Y - 1.22, to.Z), fx.Color, 3.5, 0.3)
		if fx.Landed then
			fx.Landed(Vector3.new(to.X, to.Y - 1.22, to.Z), stepIndex)
		end
		return
	end

	-- Hop and Waddle share the squash-hop shape; Waddle is low and rocks side to side
	local isWaddle = style == "Waddle"
	local hopHeight = (if isWaddle then 0.3 else 0.85) * EX
	local squashK = (if isWaddle then 0.5 else 1) * EX
	runFor(duration, function(u)
		local pos: Vector3
		local squash: number
		local roll = 0
		if u < 0.24 then
			local a = u / 0.24
			pos = from
			squash = 0.25 * a * squashK
		elseif u < 0.78 then
			local a = (u - 0.24) / 0.54
			pos = from:Lerp(to, a) + Vector3.new(0, math.sin(a * math.pi) * hopHeight, 0)
			squash = -0.20 * math.sin(a * math.pi) * squashK
			roll = math.rad((if isWaddle then 12 else 9) * tiltDir * math.sin(a * math.pi))
		else
			local a = (u - 0.78) / 0.22
			pos = to
			squash = 0.22 * (1 - a) * squashK
			roll = math.rad((if isWaddle then 4 else 11) * tiltDir * math.sin(a * math.pi))
		end
		drive(rig, flatLook(pos, baitPos) * CFrame.Angles(0, 0, roll), squash)
	end)
	SlimeMotion.Jiggle(rig)
	fx.Ripple(Vector3.new(to.X, to.Y - 1.22, to.Z), fx.Color, if isWaddle then 3.5 else 5.0, 0.35)
	if fx.Landed then
		fx.Landed(Vector3.new(to.X, to.Y - 1.22, to.Z), stepIndex)
	end
end

-- Stage C (~0.55s): lean in, gulp the bait down, satisfied bounce. Destroys baitModel.
-- slimePos = ground-rest centre next to the bait (flyers land here while leaning in).
function SlimeMotion.EatBait(rig: Rig, baitModel: Model, slimePos: Vector3, baitPos: Vector3)
	local startPos = rig.LastCf.Position
	local baseSize = (rig.Model:GetAttribute("BaseSize") :: number?) or 2.4
	local look = flatLook(slimePos, baitPos)
	local mouth = slimePos + look.LookVector * (baseSize * 0.38) + Vector3.new(0, -0.1, 0)

	local baitParts: { { Part: BasePart, Cf: CFrame, Size: Vector3 } } = {}
	for _, d in baitModel:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(baitParts, { Part = d, Cf = d.CFrame, Size = d.Size })
		end
	end

	-- Lean in (0.18s); flyers descend to the ground at the same time
	runFor(0.18, function(u)
		local e = ease(u)
		local pos = startPos:Lerp(slimePos, e)
		drive(rig, flatLook(pos, baitPos) * CFrame.Angles(-math.rad(14) * e, 0, 0), -0.15 * e)
	end)

	-- Gulp (0.20s): bait shrinks into the mouth
	blink(rig)
	runFor(0.20, function(u)
		local e = ease(u)
		for _, b in baitParts do
			if b.Part.Parent then
				local p = b.Cf.Position:Lerp(mouth, e)
				b.Part.CFrame = CFrame.new(p) * b.Cf.Rotation
				b.Part.Size = b.Size:Lerp(Vector3.new(0.05, 0.05, 0.05), e)
			end
		end
		local lean = -math.rad(14) * (1 - e)
		drive(rig, look * CFrame.Angles(lean, 0, 0), -0.15 + 0.5 * e)
	end)
	baitModel:Destroy()

	-- Satisfied bounce (0.17s)
	runFor(0.17, function(u)
		local squash = 0.35 * math.cos(u * math.pi * 1.5) * (1 - u)
		drive(rig, look, squash)
	end)
end

-- Stage D (~0.7s): float up to toPos with one full spin, ending face-on to faceTarget, with a squash-stretch
-- lift-off and a small size pop (BaseSize x1.15 at the peak, settling to x1.08 for the showcase).
function SlimeMotion.FloatUp(rig: Rig, fromPos: Vector3, toPos: Vector3, faceTarget: Vector3, duration: number)
	local model = rig.Model
	local baseSize = (model:GetAttribute("BaseSize") :: number?) or 2.4
	rig.SurpriseTarget = 1
	runFor(duration, function(u)
		local e = ease(u)
		local posE = e
		if rig.Bouncy then
			-- Back-out: overshoot ~10% above the target, then settle
			local c1 = 1.9
			posE = 1 + (c1 + 1) * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
		end
		local pos = fromPos:Lerp(toPos, posE)
		local spin = math.pi * 2 * (1 - e)
		local squash = if u < 0.3 then -0.25 * math.sin(u / 0.3 * math.pi) else 0.1 * math.sin((u - 0.3) / 0.7 * math.pi)
		-- size pop: up to x1.15 around 70% of the float, settling to x1.08
		local pop = if u < 0.7 then 1 + 0.15 * smooth(u / 0.7) else 1.15 - 0.07 * smooth((u - 0.7) / 0.3)
		model:SetAttribute("BaseSize", baseSize * pop)
		if u > 0.6 then
			rig.SurpriseTarget = 0
		end
		drive(rig, flatLook(pos, faceTarget) * CFrame.Angles(0, spin, 0), squash)
	end)
	blink(rig)
end

-- Stage E: hover in place (bob, gentle sway, breathing) while keepGoing() returns true. Run it in its own
-- thread (task.spawn); it stops on its own when the model is destroyed.
function SlimeMotion.Showcase(rig: Rig, center: Vector3, faceTarget: Vector3, keepGoing: () -> boolean)
	local t0 = os.clock()
	while keepGoing() and rig.Model.Parent do
		local t = os.clock() - t0
		local pos = center + Vector3.new(0, 0.22 * math.sin(t * math.pi * 2 * 0.8), 0)
		local sway = math.rad(12) * math.sin(t * math.pi * 2 * 0.35)
		local squash = 0.06 * math.sin(t * math.pi * 2 * 1.2)
		drive(rig, flatLook(pos, faceTarget) * CFrame.Angles(0, sway, 0), squash)
		RunService.RenderStepped:Wait()
	end
end

return SlimeMotion
