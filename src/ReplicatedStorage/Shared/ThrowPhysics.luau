--!strict
--[[
	ThrowPhysics.luau
	Deterministic custom projectile, zone-floor bounce, locked-gate rebound,
	lateral wall bounce, and ground rolling simulator.
	Runs identically on Roblox Server, Roblox Client, and Lune unit tests.
]]

local GameConfig = if typeof(script) == "Instance"
	then require(script.Parent:WaitForChild("GameConfig"))
	else require("./GameConfig")

local ThrowPhysics = {}

export type Vec3 = {
	X: number,
	Y: number,
	Z: number,
}

export type TrajectorySample = {
	Time: number,
	Position: Vec3,
	Velocity: Vec3,
	Squash: number,
	Bounced: boolean,
}

export type ThrowSimParams = {
	Origin: Vec3?,
	ThrowPower: number,
	ChargeRatio: number,
	PitchDeg: number?,
	YawDeg: number?,
	SlimeWeight: number?,
}

export type ThrowSimResult = {
	Samples: { TrajectorySample },
	BounceTimes: { number },
	FinalPosition: Vec3,
	Distance: number,
	LandedZoneIndex: number,
	HitGate: boolean,
	BlockedByZoneIndex: number?,
	TotalDuration: number,
	LaunchSpeed: number,
}

local function makeVec3(x: number, y: number, z: number): Vec3
	if typeof(Vector3) == "table" and type((Vector3 :: any).new) == "function" then
		return (Vector3 :: any).new(x, y, z)
	end
	return { X = x, Y = y, Z = z }
end

ThrowPhysics.Vec3 = makeVec3

function ThrowPhysics.GetZoneAtZ(z: number): GameConfig.ZoneDef
	local zones = GameConfig.Zones
	for i = #zones, 1, -1 do
		local zone = zones[i]
		if z >= zone.StartZ then
			return zone
		end
	end
	return zones[1]
end

function ThrowPhysics.GetFloorYAtZ(z: number): number
	if z < 0 then
		return GameConfig.Hub.FloorY
	end
	local zone = ThrowPhysics.GetZoneAtZ(z)
	return zone.FloorY
end

function ThrowPhysics.GetFirstLockedGate(throwPower: number): (number, number?)
	local p = math.max(0, throwPower)
	for _, zone in GameConfig.Zones do
		if zone.RequiredThrowPower > p then
			return zone.StartZ, zone.Index
		end
	end
	return GameConfig.Hub.LaneMaxZ, nil
end

function ThrowPhysics.ComputeLaunchSpeed(throwPower: number, chargeRatio: number, slimeWeight: number?): number
	local phys = GameConfig.Physics
	local p = math.max(1, throwPower)
	local charge = math.clamp(chargeRatio, 0.15, 1.0)
	local weight = math.clamp(slimeWeight or 1.0, 0.5, 2.0)

	local knots = phys.PowerSpeedKnots
	local rawSpeed = knots[#knots].Speed
	if p <= knots[1].Power then
		rawSpeed = knots[1].Speed
	elseif p >= knots[#knots].Power then
		-- Gentle diminishing tail above the highest calibrated knot (25K+)
		rawSpeed = knots[#knots].Speed + 6.0 * math.log10(p / knots[#knots].Power)
	else
		for i = 1, #knots - 1 do
			local a = knots[i]
			local b = knots[i + 1]
			if p >= a.Power and p <= b.Power then
				local t = (math.log(p) - math.log(a.Power)) / (math.log(b.Power) - math.log(a.Power))
				rawSpeed = a.Speed + (b.Speed - a.Speed) * t
				break
			end
		end
	end
	return (rawSpeed * (0.35 + 0.65 * charge)) / weight
end

local function ensureAutoThrowBag(bag: { number }, rngFn: (() -> number)?)
	local cfg = GameConfig.AutoThrow
	if #bag == 0 then
		for _ = 1, cfg.BagPerfectCount do
			table.insert(bag, cfg.PerfectMeterRatio)
		end
		for _ = 1, cfg.BagGoodCount do
			table.insert(bag, cfg.GoodMeterRatio)
		end
		local rng = rngFn or math.random
		for i = #bag, 2, -1 do
			local j = math.clamp(math.floor(rng() * i) + 1, 1, i)
			bag[i], bag[j] = bag[j], bag[i]
		end
	end
end

-- Non-destructive peek at the next Auto-Throw target ratio so the client's visible vertical meter
-- can smoothly glide and lock onto the exact Green / Light-Green band before releasing.
function ThrowPhysics.PeekAutoThrowRatio(bag: { number }, rngFn: (() -> number)?): (number, boolean)
	ensureAutoThrowBag(bag, rngFn)
	local ratio = bag[#bag]
	local seg = GameConfig.EvaluateMeterRatio(ratio)
	return ratio, seg.IsPerfect == true
end

-- Shuffled 5-throw Auto-Throw bag: guarantees BagPerfectCount (3) PERFECT throws and BagGoodCount (2) GOOD
-- throws in every 5-throw cycle in randomized order.
function ThrowPhysics.NextAutoThrowRatio(bag: { number }, rngFn: (() -> number)?): (number, boolean)
	ensureAutoThrowBag(bag, rngFn)
	local ratio = table.remove(bag) :: number
	local seg = GameConfig.EvaluateMeterRatio(ratio)
	return ratio, seg.IsPerfect == true
end

function ThrowPhysics.Simulate(params: ThrowSimParams): ThrowSimResult
	local phys = GameConfig.Physics
	local hub = GameConfig.Hub

	local origin = params.Origin or makeVec3(0, hub.FloorY + 1.5, hub.ThrowLineZ)
	local throwPower = math.max(1, params.ThrowPower)
	local chargeRatio = math.clamp(params.ChargeRatio, 0.15, 1.0)
	local pitchDeg = math.clamp(params.PitchDeg or phys.DefaultPitchDeg, phys.MinPitchDeg, phys.MaxPitchDeg)
	local yawDeg = math.clamp(params.YawDeg or 0, -phys.MaxYawDeg, phys.MaxYawDeg)
	local slimeWeight = math.clamp(params.SlimeWeight or 1.0, 0.5, 2.0)

	local launchSpeed = ThrowPhysics.ComputeLaunchSpeed(throwPower, chargeRatio, slimeWeight)
	local pitchRad = math.rad(pitchDeg)
	local yawRad = math.rad(yawDeg)

	local horizSpeed = launchSpeed * math.cos(pitchRad)
	local vx = horizSpeed * math.sin(yawRad)
	local vy = launchSpeed * math.sin(pitchRad)
	local vz = horizSpeed * math.cos(yawRad)

	local gateZ, blockedByZone = ThrowPhysics.GetFirstLockedGate(throwPower)
	local halfWidth = hub.ClearHalfWidth - 1.0

	local x = math.clamp(origin.X, -halfWidth, halfWidth)
	local y = origin.Y
	local z = origin.Z

	local dt = phys.FixedDt
	local maxSteps = math.floor(phys.MaxSimSeconds / dt)
	local t = 0
	local bounces = 0
	local isRolling = false
	local hitGate = false
	local squash = 0

	local samples: { TrajectorySample } = {}
	local bounceTimes: { number } = {}

	table.insert(samples, {
		Time = 0,
		Position = makeVec3(x, y, z),
		Velocity = makeVec3(vx, vy, vz),
		Squash = 0,
		Bounced = false,
	})

	for step = 1, maxSteps do
		t = step * dt
		local bouncedThisStep = false
		local prevFloorY = ThrowPhysics.GetFloorYAtZ(math.max(0, z)) + 1.0

		-- Exponential decay of squash effect
		squash = squash * math.max(0, 1 - dt * 10)

		if not isRolling then
			vy -= phys.Gravity * dt
			vx *= (1 - phys.AirDrag * dt)
			vz *= (1 - phys.AirDrag * dt)
		else
			local horizMag = math.sqrt(vx * vx + vz * vz)
			if horizMag <= phys.StopSpeedThreshold then
				vx = 0
				vy = 0
				vz = 0
				break
			end
			local decel = phys.RollingFriction * dt
			local newMag = math.max(0, horizMag - decel)
			local scale = newMag / horizMag
			vx *= scale
			vz *= scale
			vy = 0
		end

		local nextX = x + vx * dt
		local nextY = y + vy * dt
		local nextZ = z + vz * dt

		-- Lateral wall collision
		if nextX > halfWidth then
			nextX = halfWidth
			vx = -math.abs(vx) * phys.WallRestitution
		elseif nextX < -halfWidth then
			nextX = -halfWidth
			vx = math.abs(vx) * phys.WallRestitution
		end

		-- Locked Zone Gate collision or end-of-map boundary
		if nextZ >= gateZ then
			nextZ = gateZ - 0.5
			if blockedByZone ~= nil then
				hitGate = true
				vz = -math.min(math.abs(vz) * phys.GateRestitution, 18.0)
				vx *= 0.5
			else
				-- Reached the end of Zone 5 (1200 studs): stop forward motion at the finish wall
				vz = 0
				vx *= 0.3
			end
			squash = 0.45
			bouncedThisStep = true
		elseif nextZ < hub.ThrowLineZ - 5 then
			nextZ = hub.ThrowLineZ - 5
			vz = 0
		end

		-- Solid vertical cliff wall collision between stepped zones (Z = 240, 480, 720, 960):
		-- if the bait crosses forward onto a higher zone while BELOW its top surface, bonk softly off the
		-- vertical cliff wall and stay on the lower terrain instead of teleporting +6 studs upward!
		local floorY = ThrowPhysics.GetFloorYAtZ(math.max(0, nextZ)) + 1.0
		if floorY > prevFloorY + 0.1 then
			local stepZone = ThrowPhysics.GetZoneAtZ(math.max(0, nextZ))
			local stepZ = stepZone.StartZ
			local dz = nextZ - z
			local frac = if dz > 1e-4 then math.clamp((stepZ - z) / dz, 0, 1) else 0
			local yAtCliff = y + (nextY - y) * frac
			if yAtCliff < floorY - 0.15 then
				nextZ = stepZ - 0.6
				vz = -math.min(math.abs(vz) * 0.20, 5.0)
				vx *= 0.5
				squash = 0.35
				bouncedThisStep = true
				floorY = prevFloorY
			end
		end

		-- Floor collision
		if isRolling and nextY > floorY + 0.05 then
			isRolling = false
		end
		if nextY <= floorY then
			nextY = floorY
			if not isRolling then
				if vy <= 0 and math.abs(vy) > phys.BounceThresholdVy and bounces < phys.MaxBounces then
					bounces += 1
					vy = math.abs(vy) * (phys.Restitution ^ (0.85 + 0.15 * bounces))
					local horizDamp = phys.BounceHorizDamping or 0.18
					vx *= horizDamp
					vz *= horizDamp
					squash = math.clamp(math.abs(vy) / 55, 0.2, 0.65)
					bouncedThisStep = true
					table.insert(bounceTimes, t)
				elseif vy <= 0 then
					isRolling = true
					vy = 0
					squash = 0.18
				end
			end
		end

		x, y, z = nextX, nextY, nextZ

		-- Record sample every frame (60 Hz)
		table.insert(samples, {
			Time = t,
			Position = makeVec3(x, y, z),
			Velocity = makeVec3(vx, vy, vz),
			Squash = squash,
			Bounced = bouncedThisStep,
		})

		if isRolling and (vx * vx + vz * vz) <= (phys.StopSpeedThreshold * phys.StopSpeedThreshold) then
			break
		end
	end

	local clampedFinalZ = math.clamp(z, 0, hub.LaneMaxZ)
	local finalFloorY = ThrowPhysics.GetFloorYAtZ(clampedFinalZ) + 1.0
	local finalPos = makeVec3(x, finalFloorY, clampedFinalZ)
	local landedZone = ThrowPhysics.GetZoneAtZ(clampedFinalZ)
	local distance = math.max(0, math.floor(clampedFinalZ * 10 + 0.5) / 10)

	return {
		Samples = samples,
		BounceTimes = bounceTimes,
		FinalPosition = finalPos,
		Distance = distance,
		LandedZoneIndex = landedZone.Index,
		HitGate = hitGate,
		BlockedByZoneIndex = if hitGate then blockedByZone else nil,
		TotalDuration = t,
		LaunchSpeed = launchSpeed,
	}
end

return ThrowPhysics
