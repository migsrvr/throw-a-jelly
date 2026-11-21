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

	local rawSpeed = phys.BaseLaunchSpeed + phys.PowerSpeedScale * (p ^ phys.PowerExponent)
	return (rawSpeed * (0.35 + 0.65 * charge)) / weight
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
	local vz = horizSpeed * math.cos(pitchRad)

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

		-- Floor collision
		local floorY = ThrowPhysics.GetFloorYAtZ(math.max(0, nextZ)) + 1.0
		if nextY <= floorY then
			nextY = floorY
			if not isRolling then
				if math.abs(vy) > phys.BounceThresholdVy and bounces < phys.MaxBounces then
					bounces += 1
					vy = math.abs(vy) * (phys.Restitution ^ (0.85 + 0.15 * bounces))
					vx *= 0.86
					vz *= 0.88
					squash = math.clamp(math.abs(vy) / 55, 0.2, 0.65)
					bouncedThisStep = true
					table.insert(bounceTimes, t)
				else
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
