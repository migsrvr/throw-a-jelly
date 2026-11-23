--!strict
--[[
	CatchSetPieces.luau
	Exaggerated per-zone set pieces for the catch cutscene, hosted by CatchFx (client only). Everything is built
	from plain Parts / particles / beams with textures we already have, owned by the CatchFx session folder and
	removed when CatchFx.Stop() destroys it.

	Each set piece (CatchFxData zone SetPiece) has:
	  Focus(env)          -> Vector3   what the establishing shot looks at
	  Background(env)                  spectacle behind the stage for the whole cutscene (env.Strength 1 full, 0.5 lite)
	  Intro(env)          -> Intro     prop at the emerge spot (full show): :Shake(0..1) every frame, :Burst() once
	  Path(env, pos, step)             reaction on every walking step landing
	  Climax(env, pos)                 showcase climax (full show)

	All props are anchored and animated in code (no physics), so they are cheap and deterministic.
]]

local TweenService = game:GetService("TweenService")

local UiAssets = require(script.Parent:WaitForChild("UiAssets"))
local CatchFlowers = require(script.Parent:WaitForChild("CatchFlowers"))
local DeviceProfile = require(script.Parent:WaitForChild("DeviceProfile"))

-- Detail level of this device: 0 = Low, 1 = Mid, 2 = High (DeviceProfile tier)
local function detail(): number
	return DeviceProfile.Settings().Detail
end

local CatchSetPieces = {}

export type Env = {
	Folder: Folder,
	Camera: Camera,
	StageCenter: Vector3, -- ground-rest centre of the walk
	FloorY: number,
	EmergePos: Vector3, -- ground point where the slime comes out
	BaitPos: Vector3,
	Away: Vector3, -- flat unit vector pointing away from the camera (where backgrounds go)
	Right: Vector3, -- flat unit vector along the walk (toward the bait)
	SlimeSize: number,
	Slime: Model,
	ZoneColor: Color3,
	Strength: number, -- 1 = full show, 0.5 = lite
	Full: boolean,
	AddUpdater: (fn: (t: number, dt: number) -> ()) -> (),
	Emit: (parent: Instance, preset: string, color: Color3?, count: number, overrides: { [string]: any }?) -> ParticleEmitter,
	Shake: (seconds: number) -> (),
	Flash: (color: Color3, alpha: number) -> (),
	Now: () -> number,
}

export type Intro = { Shake: (k: number) -> (), Burst: () -> () }

type SetPiece = {
	Focus: (env: Env) -> Vector3,
	Background: (env: Env) -> (),
	Intro: (env: Env) -> Intro,
	Path: (env: Env, pos: Vector3, step: number) -> (),
	Climax: (env: Env, pos: Vector3) -> (),
}

-- Part budget per cutscene comes from the device tier (DeviceProfile.CutsceneParts: Low 220, Mid 360, High 500).
-- Busiest at High: the Meadow (~400 at the climax) and the volcano (~250 with bombs / splats). Lower tiers also
-- build fewer extras (see detail()), so the budget is rarely hit.

-- ============================================================================
-- Helpers
-- ============================================================================
local partCount: { [Folder]: number } = setmetatable({}, { __mode = "k" }) :: any

-- CLASSIC STUDDED STYLE (matches the map): every set-piece part is a Block with studs on all six faces, in Plastic
-- (Neon / ForceField kept). Shape props are ignored: cylinders are built as Size (len, d, d) * VERTICAL, so they
-- become square columns / flat square plates with the same geometry, and balls become cubes.
local KEEP_MATERIAL = { [Enum.Material.Neon] = true, [Enum.Material.ForceField] = true }
local STUD_FACES = { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }

local function newPart(env: Env, props: { [string]: any }): Part?
	local n = partCount[env.Folder] or 0
	if n >= DeviceProfile.Settings().CutsceneParts then
		return nil
	end
	partCount[env.Folder] = n + 1
	local p = Instance.new("Part")
	local folder = env.Folder
	p.Destroying:Connect(function()
		partCount[folder] = math.max(0, (partCount[folder] or 1) - 1)
	end)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for k, v in props do
		if k ~= "Shape" then
			(p :: any)[k] = v
		end
	end
	if not KEEP_MATERIAL[p.Material] then
		p.Material = Enum.Material.Plastic
	end
	for _, face in STUD_FACES do
		(p :: any)[face] = Enum.SurfaceType.Studs
	end
	p.Parent = env.Folder
	return p
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- cylinders run along X; this stands them up

local function tween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function fadeAway(p: BasePart, delay: number, time: number)
	task.delay(delay, function()
		if p.Parent then
			tween(p, time, { Transparency = 1 })
			task.delay(time, function()
				p:Destroy()
			end)
		end
	end)
end

-- Grow a part up out of the ground: from a flat sliver to `size`, standing on the floor at `basePos`
local function sprout(p: BasePart, basePos: Vector3, size: Vector3, rot: CFrame, time: number)
	p.Size = Vector3.new(size.X, 0.05, size.Z)
	p.CFrame = CFrame.new(basePos) * rot * CFrame.new(0, 0.025, 0)
	tween(p, time, { Size = size, CFrame = CFrame.new(basePos) * rot * CFrame.new(0, size.Y / 2, 0) }, Enum.EasingStyle.Back)
end

-- Same for a vertical cylinder (its length runs along X)
local function sproutColumn(p: BasePart, basePos: Vector3, height: number, diameter: number, time: number)
	p.Size = Vector3.new(0.05, diameter, diameter)
	p.CFrame = CFrame.new(basePos + Vector3.new(0, 0.025, 0)) * VERTICAL
	tween(p, time, { Size = Vector3.new(height, diameter, diameter), CFrame = CFrame.new(basePos + Vector3.new(0, height / 2, 0)) * VERTICAL }, Enum.EasingStyle.Back)
end

-- Ballistic flight with gravity, optional bounces; calls onLand(pos) on every touchdown, then fades
local function launch(
	env: Env,
	p: BasePart,
	velocity: Vector3,
	opts: { Gravity: number?, Bounce: number?, Bounces: number?, Spin: Vector3?, OnLand: ((pos: Vector3) -> ())?, Life: number? }
)
	local g = opts.Gravity or 40
	local bounce = opts.Bounce or 0
	local bouncesLeft = opts.Bounces or 0
	local spin = opts.Spin or Vector3.zero
	local life = opts.Life or 4
	local radius = p.Size.Y / 2
	local pos = p.Position
	local vel = velocity
	local rot = p.CFrame.Rotation
	local t0 = env.Now()
	local landed = false
	env.AddUpdater(function(t, dt)
		if landed or not p.Parent then
			return
		end
		vel += Vector3.new(0, -g * dt, 0)
		pos += vel * dt
		rot = rot * CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt)
		local groundY = env.FloorY + radius
		if pos.Y <= groundY and vel.Y < 0 then
			pos = Vector3.new(pos.X, groundY, pos.Z)
			if opts.OnLand then
				opts.OnLand(pos - Vector3.new(0, radius, 0))
			end
			if bouncesLeft > 0 then
				bouncesLeft -= 1
				vel = Vector3.new(vel.X * 0.7, -vel.Y * bounce, vel.Z * 0.7)
			else
				landed = true
				fadeAway(p, 0.3, 0.4)
			end
		end
		p.CFrame = CFrame.new(pos) * rot
		if t - t0 > life then
			landed = true
			fadeAway(p, 0, 0.3)
		end
	end)
end

-- Random flat direction (unit, XZ)
local function randomFlat(): Vector3
	local a = math.random() * math.pi * 2
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local function groundAt(env: Env, pos: Vector3): Vector3
	return Vector3.new(pos.X, env.FloorY, pos.Z)
end

local function burstAt(env: Env, pos: Vector3, preset: string, color: Color3?, count: number, overrides: { [string]: any }?): Part?
	local anchor = newPart(env, { Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(pos), Transparency = 1 })
	if anchor then
		env.Emit(anchor, preset, color, count, overrides)
		task.delay(4, function()
			anchor:Destroy()
		end)
	end
	return anchor
end

-- A stepped voxel mound: three stacked, shrinking studded blocks (base, 70%, 45%) standing on `centre`, turned to
-- face `facing`. Each tier keeps its home CFrame (for shaking) and size.
type MoundTier = { Part: Part, Home: CFrame, Size: Vector3 }
local function stepMound(env: Env, centre: Vector3, width: number, height: number, color: Color3, facing: Vector3): { MoundTier }
	local tiers: { MoundTier } = {}
	local rot = CFrame.lookAt(Vector3.zero, Vector3.new(facing.X, 0, facing.Z)).Rotation
	local y = 0
	for i, k in { 1, 0.7, 0.45 } do
		local h = height * (if i == 1 then 0.45 elseif i == 2 then 0.32 else 0.23)
		local size = Vector3.new(width * k, h, width * k * (0.9 + math.random() * 0.15))
		local p = newPart(env, {
			Color = color:Lerp(Color3.new(1, 1, 1), (i - 1) * 0.04),
			Size = size,
			CFrame = (rot + centre + Vector3.new(0, y + h / 2, 0)) * CFrame.Angles(0, (math.random() - 0.5) * 0.25, 0),
		})
		if p then
			table.insert(tiers, { Part = p, Home = p.CFrame, Size = size })
		end
		y += h
	end
	return tiers
end

-- A ring of spikes (ice / crystal) that shoot up out of the ground around `centre`
local function spikeRing(env: Env, centre: Vector3, count: number, radius: number, height: number, color: Color3, material: Enum.Material)
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local base = groundAt(env, centre + dir * radius)
		local h = height * (0.7 + math.random() * 0.6)
		local spike = newPart(env, { Color = color, Material = material, Transparency = 0.15 })
		if spike then
			-- lean outward
			local tilt = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(-math.rad(18), 0, 0)
			task.delay(i * 0.025, function()
				if spike.Parent then
					sprout(spike, base, Vector3.new(0.9, h, 0.9), tilt.Rotation, 0.25)
				end
			end)
			fadeAway(spike, 2.6, 0.5)
		end
	end
end

-- ============================================================================
-- Meadow: the slime hides in a bush of tall flowers (rustles, peeks, ducks, bursts out), giant swaying flowers +
-- butterflies behind the stage, real 3D flowers (CatchFlowers) bloom on every step, a ring of big flowers at the end
-- ============================================================================
local FLOWER_COLORS = { rgb(255, 150, 200), rgb(255, 230, 90), rgb(180, 140, 255), rgb(255, 255, 255), rgb(255, 120, 120) }
local FLOWER_UP = Vector3.new(0, 1, 0)

-- One animated flower in the cutscene's garden (posed every frame by the garden updater)
type Plant = {
	F: CatchFlowers.Flower,
	T0: number, -- when it starts growing (session time)
	GrowTime: number,
	OpenDelay: number, -- after T0
	OpenTime: number,
	Life: number?, -- after T0 it closes and sinks back into the ground (0.4s), then is removed
	SwayAmp: number,
	SwayHz: number,
	Phase: number,
	Extra: ((t: number) -> CFrame)?, -- extra bend at the stem base (bush rustle / parting)
	Settled: boolean?, -- grown, open and still: no need to pose it again
}

local gardens: { [Folder]: { Plant } } = setmetatable({}, { __mode = "k" }) :: any

local function easeBack(u: number): number
	local c1 = 1.70158
	local v = u - 1
	return 1 + (c1 + 1) * v * v * v + c1 * v * v
end

local function smoothstep(u: number): number
	return u * u * (3 - 2 * u)
end

-- The cutscene's flowers, all posed by one updater and moved with a single BulkMoveTo per frame
local function garden(env: Env): { Plant }
	local existing = gardens[env.Folder]
	if existing then
		return existing
	end
	local list: { Plant } = {}
	gardens[env.Folder] = list
	env.AddUpdater(function(t, _dt)
		local parts: { BasePart } = {}
		local cfs: { CFrame } = {}
		local swayOn = DeviceProfile.Settings().Sway
		local i = 1
		while i <= #list do
			local p = list[i]
			local lt = t - p.T0
			local grow, open = 0, 0
			local alive = true
			if lt > 0 then
				grow = easeBack(math.clamp(lt / p.GrowTime, 0, 1))
				open = smoothstep(math.clamp((lt - p.OpenDelay) / p.OpenTime, 0, 1))
				local life = p.Life
				if life and lt > life then
					local k = math.clamp((lt - life) / 0.4, 0, 1)
					grow *= 1 - k
					open *= 1 - k
					alive = k < 1
				end
			end
			if alive then
				-- a fully grown flower with nothing moving it is posed once and then skipped (Low tier: no sway)
				local sway = if swayOn then p.SwayAmp else 0
				local settled = sway == 0 and p.Extra == nil and grow == 1 and open == 1
				if not (settled and p.Settled) then
					local bend = if sway == 0
						then CFrame.identity
						else CFrame.Angles(sway * math.sin(t * p.SwayHz + p.Phase), 0, sway * 0.7 * math.sin(t * p.SwayHz * 1.3 + p.Phase * 1.7))
					if p.Extra then
						bend = p.Extra(t) * bend
					end
					CatchFlowers.Pose(p.F, grow, open, bend, parts, cfs)
					p.Settled = settled
				end
				i += 1
			else
				CatchFlowers.Destroy(p.F)
				table.remove(list, i)
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
	return list
end

type PlantOpts = {
	Facing: Vector3?,
	Scale: number?,
	Height: number?,
	Color: Color3?,
	Delay: number?,
	GrowTime: number?,
	OpenDelay: number?,
	OpenTime: number?,
	Life: number?,
	SwayAmp: number?,
	SwayHz: number?,
	Grown: boolean?, -- already fully grown and open
}

local function plant(env: Env, kind: CatchFlowers.Kind, pos: Vector3, opts: PlantOpts): Plant
	-- face the camera, turned a little at random so they don't all look identical
	local facing = CFrame.Angles(0, (math.random() - 0.5) * 0.7, 0):VectorToWorldSpace(opts.Facing or -env.Away)
	local f = CatchFlowers.Build(function(props)
		return newPart(env, props)
	end, kind, { Pos = pos, Facing = facing, Scale = opts.Scale, Height = opts.Height, Color = opts.Color })
	local p: Plant = {
		F = f,
		T0 = env.Now() + (opts.Delay or 0) - (if opts.Grown then 100 else 0),
		GrowTime = opts.GrowTime or 0.35,
		OpenDelay = opts.OpenDelay or 0.2,
		OpenTime = opts.OpenTime or 0.35,
		Life = opts.Life,
		SwayAmp = opts.SwayAmp or 0.04,
		SwayHz = opts.SwayHz or 1.4,
		Phase = math.random() * 6.28,
		Extra = nil,
	}
	table.insert(garden(env), p)
	return p
end

local function petalPuff(env: Env, pos: Vector3, count: number, speed: { number })
	local anchor = burstAt(env, pos, "Petals", FLOWER_COLORS[math.random(1, #FLOWER_COLORS)], count, { Speed = speed, Spread = 70 })
	if anchor then
		env.Emit(anchor, "Petals", FLOWER_COLORS[math.random(1, #FLOWER_COLORS)], count, { Speed = speed, Spread = 70 })
		env.Emit(anchor, "Glints", rgb(255, 240, 150), math.ceil(count * 0.6), { Speed = { 1, 3 } })
	end
end

local GIANTS: { CatchFlowers.Kind } = { "Lupin", "Sunflower", "Tulip", "Daisy", "Lupin" }
local BUSH_FRONT: { CatchFlowers.Kind } = { "Cosmos", "Daisy", "Tulip" } -- short heads, so the peek stays visible
local BUSH_BACK: { CatchFlowers.Kind } = { "Sunflower", "Lupin", "Tulip", "Rose" }

local Meadow: SetPiece = {
	Focus = function(env)
		return env.StageCenter + env.Away * 6
	end,
	Background = function(env)
		-- giant flowers swaying behind the stage
		for i, kind in GIANTS do
			if detail() == 0 and i % 2 == 0 then
				continue -- Low: 3 giant flowers
			end
			local base = groundAt(env, env.StageCenter + env.Away * (11 + (i % 2) * 3.5) + env.Right * ((i - 3) * 7.5))
			plant(env, kind, base, { Scale = 3 + math.random() * 0.4, GrowTime = 0.6, OpenDelay = 0.3, OpenTime = 0.5, SwayAmp = 0.06, SwayHz = 1 })
		end
		-- butterflies fluttering in figure-8s
		for i = 1, math.max(1, math.floor(4 * env.Strength)) do
			local anchor = newPart(env, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
			if anchor then
				env.Emit(anchor, "Sparkle", FLOWER_COLORS[i], 0, { Rate = 24, Life = { 0.2, 0.35 }, Speed = { 0, 0.2 }, Size = { 0.45, 0 } })
				local c = env.StageCenter + env.Away * (3 + i * 1.5) + Vector3.new(0, 2 + i * 0.4, 0)
				local ph = i * 2.1
				env.AddUpdater(function(t, _dt)
					local a = t * 1.3 + ph
					anchor.CFrame = CFrame.new(c + env.Right * (math.sin(a) * 6) + env.Away * (math.sin(a * 2) * 1.5) + Vector3.new(0, math.sin(a * 5) * 0.4, 0))
				end)
			end
		end
	end,
	Intro = function(env)
		-- a bush of tall flowers the slime hides in (SlimeMotion "Bush" emergence)
		local s = env.SlimeSize
		local c = env.EmergePos
		local toCam = -env.Away
		local side = env.Right
		local make = function(props: { [string]: any }): Part?
			return newPart(env, props)
		end
		local bush = { Rustle = 0, BurstAt = -1 }

		local plants: { Plant } = {}
		local count = if detail() == 0 then 6 else 10 -- Low: a smaller bush
		for i = 1, count do
			local a = (i / count) * math.pi * 2 + (math.random() - 0.5) * 0.4
			local dir = toCam * math.cos(a) + side * math.sin(a)
			dir = if dir.Magnitude > 0.01 then dir.Unit else toCam
			local front = dir:Dot(toCam) > 0.3
			local kinds = if front then BUSH_FRONT else BUSH_BACK
			local height = s * (if front then 1.25 + math.random() * 0.15 else 1.5 + math.random() * 0.25)
			local p = plant(env, kinds[math.random(1, #kinds)], groundAt(env, c + dir * s * (0.45 + math.random() * 0.35)), {
				Scale = s / 2.4 * 1.6,
				Height = height,
				Grown = true,
				SwayAmp = 0.03,
				SwayHz = 1.2,
			})
			local axis = FLOWER_UP:Cross(dir).Unit
			local ph = math.random() * 6.28
			p.Extra = function(t)
				local r = bush.Rustle
				local cf = CFrame.Angles(0.22 * r * math.sin(t * 23 + ph), 0, 0.22 * r * math.sin(t * 19 + ph * 2))
				if bush.BurstAt >= 0 then
					-- spring outward (overshoots to ~40 deg), settle parted at ~29 deg
					local u = t - bush.BurstAt
					cf = CFrame.fromAxisAngle(axis, 0.5 * (1 - math.exp(-u * 3) * math.cos(u * 10))) * cf
				end
				return cf
			end
			table.insert(plants, p)
		end

		-- leafy blobs at the base hide the slime's body (the biggest on the camera side)
		local blobs: { { Part: Part, Home: CFrame, Size: Vector3 } } = {}
		local function blob(pos: Vector3, size: Vector3, crown: boolean)
			local p = CatchFlowers.Ellipsoid(make, {
				Material = Enum.Material.Grass,
				Color = rgb(78, 160, 64),
				Size = size,
				CFrame = CFrame.lookAt(pos, pos + toCam),
			})
			if p then
				table.insert(blobs, { Part = p, Home = p.CFrame, Size = size })
			end
			if not crown then
				return
			end
			-- a smaller block on top: a blocky bush silhouette like the map's trees
			local topSize = Vector3.new(size.X * 0.6, size.Y * 0.55, size.Z * 0.65)
			local top = CatchFlowers.Blob(make, {
				Color = rgb(96, 180, 74),
				Size = topSize,
				CFrame = CFrame.lookAt(pos, pos + toCam) * CFrame.new((math.random() - 0.5) * size.X * 0.2, (size.Y + topSize.Y) * 0.5 - 0.05, 0),
			})
			if top then
				table.insert(blobs, { Part = top, Home = top.CFrame, Size = topSize })
			end
		end
		blob(c + toCam * s * 0.5 + Vector3.new(0, s * 0.3, 0), Vector3.new(s * 1.5, s * 0.75, s * 0.8), false) -- no crown: the peek shows over it
		blob(c - side * s * 0.55 - toCam * s * 0.25 + Vector3.new(0, s * 0.28, 0), Vector3.new(s * 1, s * 0.7, s * 1.1), true)
		blob(c + side * s * 0.55 - toCam * s * 0.25 + Vector3.new(0, s * 0.28, 0), Vector3.new(s * 1, s * 0.7, s * 1.1), true)

		-- big leaves fanned out on the ground
		local leaves: { Part } = {}
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2 + 0.3
			local d = Vector3.new(math.cos(a), 0, math.sin(a))
			local len = s * 0.9
			local p = CatchFlowers.Ellipsoid(make, {
				Color = rgb(70, 155, 62),
				Size = Vector3.new(s * 0.38, 0.06, len),
				CFrame = CFrame.lookAt(c, c + d) * CFrame.Angles(0.3, 0, 0) * CFrame.new(0, 0.05, -len / 2),
			})
			if p then
				table.insert(leaves, p)
			end
		end

		return {
			Shake = function(k)
				bush.Rustle = k
				for _, b in blobs do
					if b.Part.Parent then
						b.Part.CFrame = b.Home * CFrame.new((math.random() - 0.5) * 0.12 * k, (math.random() - 0.5) * 0.05 * k, (math.random() - 0.5) * 0.12 * k)
					end
				end
				if k > 0.6 and math.random() < 0.12 then
					burstAt(env, c + Vector3.new(0, s * 1.4, 0), "Petals", FLOWER_COLORS[math.random(1, #FLOWER_COLORS)], 2, { Speed = { 2, 4 }, Spread = 60 })
				end
			end,
			Burst = function()
				bush.Rustle = 0
				local now = env.Now()
				bush.BurstAt = now
				-- the bush stays parted a moment, then sinks back into the ground
				for _, p in plants do
					p.Life = (now - p.T0) + 2.5
				end
				for _, b in blobs do
					local part = b.Part
					tween(part, 0.3, { Size = b.Size * 1.3, Transparency = 1 })
					task.delay(0.32, function()
						part:Destroy()
					end)
				end
				for _, l in leaves do
					fadeAway(l, 2.5, 0.5)
				end
				petalPuff(env, c + Vector3.new(0, s * 0.8, 0), 25, { 8, 14 })
				burstAt(env, c + Vector3.new(0, s * 0.6, 0), "Leaves", nil, 25, { Speed = { 8, 13 }, Dir = Enum.NormalId.Top, Spread = 70 })
			end,
		}
	end,
	Path = function(env, pos, _step)
		-- three flowers bloom around every step: one each side, one a little further out (Low: two, shorter-lived)
		local d = detail()
		local life = if d == 0 then 2.4 elseif d == 1 then 2.8 else 3.2
		local toCam = -env.Away
		for k = 1, (if d == 0 then 2 else 3) do
			local off: Vector3
			local allowTall = true
			local scale = 1 + math.random() * 0.4
			if k == 1 then
				off = env.Away * (1.7 + math.random() * 0.4)
			elseif k == 2 then
				-- camera side: smaller, never tall, so it doesn't hide the slime
				off = toCam * (1.6 + math.random() * 0.3)
				allowTall = false
				scale = 0.85 + math.random() * 0.2
			else
				local far = math.random() < 0.6
				off = env.Away * ((if far then 1 else -1) * (2.6 + math.random() * 0.9))
				allowTall = far
			end
			off += env.Right * ((math.random() - 0.5) * 1.4)
			local kind, color = CatchFlowers.Random(allowTall)
			plant(env, kind, groundAt(env, pos + off), { Scale = scale, Color = color, Delay = (k - 1) * 0.07, Life = life, SwayAmp = 0.05 })
		end
		petalPuff(env, groundAt(env, pos) + Vector3.new(0, 0.6, 0), 3, { 2, 4 })
	end,
	Climax = function(env, pos)
		-- a ring of big flowers blooms in a wave around the slime
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2
			local kind, color = CatchFlowers.Random(true)
			plant(env, kind, groundAt(env, pos + Vector3.new(math.cos(a), 0, math.sin(a)) * 3.4), {
				Scale = 1.6,
				Color = color,
				Delay = i * 0.04,
				GrowTime = 0.4,
				OpenDelay = 0.25,
				OpenTime = 0.4,
				SwayAmp = 0.04,
			})
		end
		petalPuff(env, groundAt(env, pos) + Vector3.new(0, 1, 0), 22, { 6, 11 })
	end,
}

-- ============================================================================
-- Crystal Cave: geode shatters, pulsing crystal pillars + glitter drips, crystals sprout, giant spike ring
-- ============================================================================
local CRYSTAL_COLORS = { rgb(130, 230, 255), rgb(200, 140, 255), rgb(255, 160, 230) }

local Crystal: SetPiece = {
	Focus = function(env)
		return env.StageCenter + env.Away * 6
	end,
	Background = function(env)
		local pillars: { Part } = {}
		for i = 1, 4 do
			local base = groundAt(env, env.StageCenter + env.Away * (9 + (i % 2) * 4) + env.Right * ((i - 2.5) * 7))
			local h = 7 + math.random() * 5
			local p = newPart(env, { Color = CRYSTAL_COLORS[i % 3 + 1], Material = Enum.Material.Neon, Transparency = 0.35 })
			if p then
				local tilt = CFrame.Angles(math.rad((math.random() - 0.5) * 20), math.random() * 3, math.rad((math.random() - 0.5) * 20))
				sprout(p, base, Vector3.new(1.6, h, 1.6), tilt, 0.6)
				table.insert(pillars, p)
			end
		end
		env.AddUpdater(function(t, _dt)
			for i, p in pillars do
				if p.Parent then
					p.Transparency = 0.25 + 0.45 * (0.5 + 0.5 * math.sin(t * 2.4 - i * 1.4))
				end
			end
		end)
		-- glittering drips from above
		local box = newPart(env, {
			Size = Vector3.new(30, 0.2, 10),
			CFrame = CFrame.new(env.StageCenter + env.Away * 5 + Vector3.new(0, 11, 0)),
			Transparency = 1,
		})
		if box then
			env.Emit(box, "Glints", CRYSTAL_COLORS[1], 0, {
				Rate = 10 * env.Strength,
				Dir = Enum.NormalId.Bottom,
				Speed = { 6, 9 },
				Life = { 1.2, 1.6 },
				Spread = 0,
				Size = { 0.3, 0.1 },
			})
		end
	end,
	Intro = function(env)
		local size = env.SlimeSize
		local shards: { Part } = {}
		local homes: { CFrame } = {}
		for i = 1, 7 do
			local a = i / 7 * math.pi * 2
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local base = env.EmergePos + dir * size * 0.45
			local lean = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(-math.rad(25), 0, 0)
			local h = size * (1.3 + math.random() * 0.5)
			local p = newPart(env, {
				Color = CRYSTAL_COLORS[i % 3 + 1],
				Material = Enum.Material.Glass,
				Transparency = 0.1,
				Size = Vector3.new(size * 0.55, h, size * 0.55),
				CFrame = CFrame.new(base) * lean.Rotation * CFrame.new(0, h / 2, 0),
			})
			if p then
				table.insert(shards, p)
				table.insert(homes, p.CFrame)
			end
		end
		return {
			Shake = function(k)
				for i, p in shards do
					if p.Parent then
						p.CFrame = homes[i] * CFrame.Angles((math.random() - 0.5) * 0.12 * k, 0, (math.random() - 0.5) * 0.12 * k)
						p.Material = if k > 0.7 then Enum.Material.Neon else Enum.Material.Plastic
					end
				end
			end,
			Burst = function()
				for _, p in shards do
					local dir = (p.Position - env.EmergePos)
					dir = Vector3.new(dir.X, 0, dir.Z)
					dir = if dir.Magnitude > 0.01 then dir.Unit else randomFlat()
					p.Material = Enum.Material.Neon
					launch(env, p, dir * 12 + Vector3.new(0, 16, 0), { Spin = Vector3.new(9, 3, 7), Life = 2.2 })
				end
				burstAt(env, env.EmergePos + Vector3.new(0, 1, 0), "Stars", CRYSTAL_COLORS[2], 30, { Speed = { 8, 14 } })
				env.Flash(CRYSTAL_COLORS[1], 0.35)
			end,
		}
	end,
	Path = function(env, pos, step)
		local side = if step % 2 == 0 then 1 else -1
		local base = groundAt(env, pos + env.Away * (side * 1.7))
		local p = newPart(env, { Color = CRYSTAL_COLORS[step % 3 + 1], Material = Enum.Material.Neon, Transparency = 0.1 })
		if p then
			sprout(p, base, Vector3.new(0.5, 1.4 + math.random(), 0.5), CFrame.Angles(math.rad(side * 15), math.random() * 3, 0), 0.25)
			task.delay(0.8, function()
				if p.Parent then
					p.Material = Enum.Material.Plastic
				end
			end)
		end
	end,
	Climax = function(env, pos)
		spikeRing(env, pos, 8, 3.6, 6, CRYSTAL_COLORS[2], Enum.Material.Neon)
		env.Flash(CRYSTAL_COLORS[2], 0.4)
	end,
}

-- ============================================================================
-- Lava Fields: a classic studded voxel volcano with a glowing crater, lava runs down its steps into pools that feed
-- winding crusted lava rivers; eruptions charge up, blow a lava fountain and rain trailing lava bombs that
-- splat and scorch the ground. The climax is a full eruption with a lava pillar and a ground shockwave.
-- ============================================================================
local LAVA = rgb(255, 120, 30)
local LAVA_HOT = rgb(255, 200, 80)
local LAVA_COOL = rgb(120, 30, 20)
local ROCK = { rgb(58, 40, 36), rgb(74, 50, 42), rgb(48, 34, 32), rgb(92, 78, 72), rgb(38, 28, 26) }
local STREAM_THETAS = { -0.42, 0, 0.42 } -- lava streams down the camera-facing side
local BANK = rgb(40, 30, 30)
local UP = Vector3.new(0, 1, 0)

-- Mountain profile { height, radius }: concave (wide flared base, steep top), crater at the top
local VOLCANO_PROFILE = { { 0, 15 }, { 8, 10 }, { 17, 6.5 }, { 24, 4.5 } }
local VOLCANO_TOP = 22 -- crater lava level: eruptions, the pillar and the smoke start here
local CHARGE_TIME = 0.6 -- the crater glows up and rumbles this long before each eruption

type River = { Pts: { Vector3 }, Lens: { number }, Total: number, Cores: { Part }, Plates: { { Part: Part, S: number, Speed: number, Yaw: number } } }
type VolcanoState = {
	Base: Vector3,
	Crater: Vector3,
	Heat: number,
	ChargeUntil: number,
	Streams: { Part },
	StreamJ: { number }, -- index of each lava cap / drip from the crater down (drives the flowing glow wave)
	StreamSize: { Vector3 },
	Fissures: { Part }, -- magma veins in the column sides (pulse with the crater heat)
}

local volcanoStates: { [Folder]: VolcanoState } = setmetatable({}, { __mode = "k" }) :: any

local function volcanoPos(env: Env): Vector3
	return groundAt(env, env.StageCenter + env.Away * 30 - env.Right * 3)
end

-- Flat direction around the volcano: theta 0 faces the camera, + goes along the walk
local function aroundDir(env: Env, theta: number): Vector3
	local d = -env.Away * math.cos(theta) + env.Right * math.sin(theta)
	return if d.Magnitude > 0.01 then d.Unit else -env.Away
end

-- ---------------------------------------------------------------------------
-- Classic voxel volcano: a grid of studded block columns stepping up to a crater (matches the map's blocky style)
-- ---------------------------------------------------------------------------
local CELL_SIZE = 2.5 -- column width (studs); Low tier uses CELL_SIZE_LOW (about half the columns)
local CELL_SIZE_LOW = 3.5
local VOXEL_R = 15.5 -- mountain radius
local CRATER_R = 4.5 -- columns closer than this form the crater floor
local CRATER_FLOOR = 21 -- top of the crater floor columns (the lava lake sits on it)
local VOLCANO_COLORS = {
	Low = { rgb(52, 40, 40), rgb(42, 36, 40) },
	Mid = { rgb(55, 48, 52), rgb(62, 50, 48) },
	Top = { rgb(82, 72, 72), rgb(74, 64, 64) },
	Rim = rgb(40, 30, 30),
}

type Voxel = { I: number, J: number, H: number, Capped: boolean }

-- Mountain height at distance r from its centre (inverse of VOLCANO_PROFILE)
local function volcanoHeightAt(r: number): number
	for i = 1, #VOLCANO_PROFILE - 1 do
		local a, b = VOLCANO_PROFILE[i], VOLCANO_PROFILE[i + 1]
		if r >= b[2] then
			return a[1] + (b[1] - a[1]) * math.clamp((a[2] - r) / (a[2] - b[2]), 0, 1)
		end
	end
	return VOLCANO_PROFILE[#VOLCANO_PROFILE][1]
end

-- Builds the stepped mountain, the crater lava lake, lava running down the steps into map-style lava pools,
-- magma veins and MagmaRock clusters round the foot. Returns the crater lava slab (pulses with the heat).
local function buildVoxelVolcano(env: Env, st: VolcanoState, base: Vector3): Part?
	local CELL = if detail() == 0 then CELL_SIZE_LOW else CELL_SIZE
	local frame = CFrame.lookAt(base, base - env.Away) -- grid axes: local -Z faces the camera
	local rot = frame.Rotation
	local function world(x: number, y: number, z: number): Vector3
		return frame * Vector3.new(x, y, z)
	end

	-- columns
	local cells: { [string]: Voxel } = {}
	local n = math.ceil(VOXEL_R / CELL)
	for i = -n, n do
		for j = -n, n do
			local r = math.sqrt(i * i + j * j) * CELL
			if r <= VOXEL_R then
				local h: number
				local color: Color3
				if r < CRATER_R then
					h = CRATER_FLOOR
					color = VOLCANO_COLORS.Rim
				elseif r < CRATER_R + 1.6 then
					h = 24 + math.random() * 1.5 -- jagged crater rim
					color = VOLCANO_COLORS.Rim
				else
					h = volcanoHeightAt(r) + math.random(-1, 1)
					if math.random() < 0.1 then
						h += 2 -- a crag
					end
					local band = if h < 7 then VOLCANO_COLORS.Low elseif h < 15 then VOLCANO_COLORS.Mid else VOLCANO_COLORS.Top
					color = band[math.random(1, #band)]
				end
				h = math.max(1, math.floor(h + 0.5))
				newPart(env, {
					Color = color,
					Size = Vector3.new(CELL, h + 2, CELL), -- 2 studs below the floor so there are no gaps
					CFrame = rot + world(i * CELL, (h - 2) / 2, j * CELL),
				})
				cells[i .. "," .. j] = { I = i, J = j, H = h, Capped = false }
			end
		end
	end

	-- crater lava lake
	local lake = newPart(env, {
		Material = Enum.Material.Neon,
		Color = LAVA,
		Size = Vector3.new(CELL * 3, 0.8, CELL * 3),
		CFrame = rot + world(0, CRATER_FLOOR + 0.3, 0),
	})

	-- lava runs down the steps: a Neon cap on every column it crosses, a drip down every step face
	for _, theta in STREAM_THETAS do
		local dirW = aroundDir(env, theta)
		local dirL = frame:VectorToObjectSpace(dirW)
		local prev: Voxel? = nil
		local visited: { [string]: boolean } = {}
		local order = 0
		local r = CRATER_R + 0.6
		while r <= VOXEL_R do
			local ci = math.floor(dirL.X * r / CELL + 0.5)
			local cj = math.floor(dirL.Z * r / CELL + 0.5)
			local key = ci .. "," .. cj
			local cell = cells[key]
			if cell and not visited[key] then
				visited[key] = true
				order += 1
				if not cell.Capped then
					cell.Capped = true
					local cap = newPart(env, {
						Material = Enum.Material.Neon,
						Color = LAVA,
						Size = Vector3.new(CELL * 0.8, 0.35, CELL * 0.8),
						CFrame = rot + world(ci * CELL, cell.H + 0.15, cj * CELL),
					})
					if cap then
						table.insert(st.Streams, cap)
						table.insert(st.StreamJ, order)
						table.insert(st.StreamSize, cap.Size)
						if order == 3 then
							env.Emit(cap, "Embers", nil, 0, { Rate = 3 * env.Strength, Spread = 60, Speed = { 0.5, 1.5 } })
						end
					end
				end
				if prev and prev.H > cell.H then
					local drop = prev.H - cell.H
					local edge = world((prev.I + ci) * 0.5 * CELL, (prev.H + cell.H) * 0.5, (prev.J + cj) * 0.5 * CELL)
					local d = frame:VectorToWorldSpace(Vector3.new(ci - prev.I, 0, cj - prev.J))
					if d.Magnitude > 0.01 then
						local drip = newPart(env, {
							Material = Enum.Material.Neon,
							Color = LAVA,
							Size = Vector3.new(CELL * 0.6, drop + 0.3, 0.3),
							CFrame = CFrame.lookAt(edge, edge + d.Unit),
						})
						if drip then
							table.insert(st.Streams, drip)
							table.insert(st.StreamJ, order - 0.5)
							table.insert(st.StreamSize, drip.Size)
						end
					end
				end
				prev = cell
			end
			r += CELL * 0.5
		end

		-- map-style LavaPool at the foot: dark rim block with a Neon block in it
		local poolPos = groundAt(env, base + dirW * (VOXEL_R + 2))
		local k = if theta == 0 then 1.3 else 1
		local poolCf = CFrame.lookAt(poolPos, poolPos + dirW)
		newPart(env, { Color = BANK, Size = Vector3.new(6.5, 0.8, 5) * Vector3.new(k, 1, k), CFrame = poolCf + Vector3.new(0, 0.4, 0) })
		newPart(env, {
			Material = Enum.Material.Neon,
			Color = LAVA,
			Size = Vector3.new(5, 0.85, 3.6) * Vector3.new(k, 1, k),
			CFrame = poolCf + Vector3.new(0, 0.45, 0),
		})
	end

	-- magma veins: Neon stripes set into the camera-facing sides of some columns
	local candidates: { Voxel } = {}
	for _, cell in cells do
		local r = math.sqrt(cell.I * cell.I + cell.J * cell.J) * CELL
		if not cell.Capped and cell.J < 0 and cell.H >= 3 and cell.H <= 15 and r > CRATER_R + 2 then
			table.insert(candidates, cell)
		end
	end
	for _ = 1, math.min(8, #candidates) do
		local cell = table.remove(candidates, math.random(1, #candidates)) :: Voxel
		local y = 1 + math.random() * (cell.H - 2)
		local alongX = math.abs(cell.I) > math.abs(cell.J)
		local sx = if cell.I >= 0 then 1 else -1
		local pos = if alongX
			then world(cell.I * CELL + sx * (CELL / 2 + 0.05), y, cell.J * CELL)
			else world(cell.I * CELL, y, cell.J * CELL - (CELL / 2 + 0.05))
		local seam = newPart(env, {
			Material = Enum.Material.Neon,
			Color = LAVA,
			Transparency = 0.35,
			Size = if alongX then Vector3.new(0.15, 0.5, CELL * 0.6) else Vector3.new(CELL * 0.6, 0.5, 0.15),
			CFrame = rot + pos,
		})
		if seam then
			table.insert(st.Fissures, seam)
		end
	end

	-- MagmaRock clusters round the foot (like the map's props): dark block, smaller ash block, glowing plate
	for _, theta in { -0.8, 0.8, 1.7, 2.7, -1.7, -2.7 } do
		local g = groundAt(env, base + aroundDir(env, theta) * (VOXEL_R + 1.5))
		local cf = rot * CFrame.Angles(0, math.random(0, 3) * math.pi / 2, 0) + g
		newPart(env, { Material = Enum.Material.Neon, Color = rgb(255, 100, 20), Size = Vector3.new(6.6, 0.5, 5.8), CFrame = cf + Vector3.new(0, 0.25, 0) })
		newPart(env, { Color = rgb(52, 40, 40), Size = Vector3.new(6.4, 4, 5.6), CFrame = cf + Vector3.new(0, 2, 0) })
		newPart(env, { Color = rgb(82, 72, 72), Size = Vector3.new(4, 2.4, 3.2), CFrame = cf * CFrame.new(0.8, 5.2, -0.4) })
	end

	return lake
end

-- Camera-facing glow sprite (heat halo over the crater, sky glow)
local function glowBillboard(parent: BasePart, size: number, color: Color3, transparency: number, offsetY: number): ImageLabel
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(size, size) -- scale = studs
	bb.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.Adornee = parent
	bb.Parent = parent
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = UiAssets.Textures.glow
	img.ImageColor3 = color
	img.ImageTransparency = transparency
	img.Parent = bb
	return img
end

-- A lava bubble that swells up and pops
local function blorp(env: Env, pos: Vector3, size: number)
	local ball = newPart(env, {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = LAVA_HOT,
		Size = Vector3.new(0.15, 0.15, 0.15),
		CFrame = CFrame.new(pos),
	})
	if not ball then
		return
	end
	tween(ball, 0.3, { Size = Vector3.new(size, size * 0.8, size) }, Enum.EasingStyle.Back)
	task.delay(0.32, function()
		if ball.Parent then
			burstAt(env, pos + Vector3.new(0, size * 0.3, 0), "Fire", LAVA, 5, { Speed = { 2, 4 }, Spread = 40 })
			ball:Destroy()
		end
	end)
end

-- Winding lava river along `pts` (ground points): glowing Neon core over a wider dark crust bank, with crust
-- plates drifting down it
local function lavaRiver(env: Env, pts: { Vector3 }, width: number, plates: number): River
	local r: River = { Pts = pts, Lens = {}, Total = 0, Cores = {}, Plates = {} }
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude
		r.Lens[i] = len
		r.Total += len
		local mid = (a + b) * 0.5
		local w = width * (0.85 + math.random() * 0.3)
		newPart(env, {
			Material = Enum.Material.Basalt,
			Color = BANK,
			Size = Vector3.new(w + 1.4, 0.14, len + 1),
			CFrame = CFrame.lookAt(mid + UP * 0.07, b + UP * 0.07),
		})
		local core = newPart(env, {
			Material = Enum.Material.Neon,
			Color = LAVA,
			Size = Vector3.new(w, 0.1, len + 0.6),
			CFrame = CFrame.lookAt(mid + UP * 0.12, b + UP * 0.12),
		})
		if core then
			table.insert(r.Cores, core)
			if i % 2 == 0 then
				env.Emit(core, "Embers", nil, 0, { Rate = 2 * env.Strength, Spread = 30 })
			end
		end
	end
	for i = 1, plates do
		local s = math.random() * 0.7 + 0.5
		local plate = newPart(env, {
			Material = Enum.Material.CrackedLava,
			Color = rgb(62, 36, 30),
			Size = Vector3.new(width * 0.45 * s, 0.08, 1.1 * s),
		})
		if plate then
			table.insert(r.Plates, { Part = plate, S = r.Total * (i - 1) / plates, Speed = 2.5 + math.random() * 1.5, Yaw = math.random() * 6.28 })
		end
	end
	return r
end

-- Point + direction at distance s along a river
local function riverSample(r: River, s: number): (Vector3, Vector3)
	for i, len in r.Lens do
		if s <= len or i == #r.Lens then
			local a, b = r.Pts[i], r.Pts[i + 1]
			return a:Lerp(b, math.clamp(s / len, 0, 1)), (b - a).Unit
		end
		s -= len
	end
	return r.Pts[1], Vector3.new(1, 0, 0)
end

local function lavaSplat(env: Env, ground: Vector3, size: number)
	local anchor = burstAt(env, ground + Vector3.new(0, 0.3, 0), "Fire", LAVA, 14, { Speed = { 3, 7 }, Spread = 60, Size = { 1.2, 0.2 } })
	if anchor then
		env.Emit(anchor, "Embers", nil, 10, { Speed = { 4, 8 }, Spread = 70 })
	end
	local disc = newPart(env, {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = LAVA_HOT,
		Size = Vector3.new(0.1, 0.5, 0.5),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.07, 0)) * VERTICAL,
	})
	if disc then
		tween(disc, 0.2, { Size = Vector3.new(0.1, size * 3, size * 3), Color = LAVA })
		fadeAway(disc, 0.5, 0.7)
	end
	-- the scorch mark stays a while
	local scorch = newPart(env, {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Basalt,
		Color = rgb(35, 25, 22),
		Size = Vector3.new(0.06, size * 2.4, size * 2.4),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.04, 0)) * VERTICAL,
	})
	if scorch then
		fadeAway(scorch, 3, 1)
	end
	-- rock chips
	for _ = 1, 2 do
		local chip = newPart(env, {
			Material = Enum.Material.Basalt,
			Color = ROCK[math.random(1, #ROCK)],
			Size = Vector3.new(1, 1, 1) * (0.35 + math.random() * 0.3),
			CFrame = CFrame.new(ground + Vector3.new(0, 0.5, 0)),
		})
		if chip then
			launch(env, chip, randomFlat() * (4 + math.random() * 3) + Vector3.new(0, 8, 0), { Spin = Vector3.new(8, 5, 6), Life = 1.2 })
		end
	end
end

local function lavaBomb(env: Env, from: Vector3, target: Vector3, flight: number, size: number)
	local bomb = newPart(env, {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = LAVA_HOT,
		Size = Vector3.new(size, size, size),
		CFrame = CFrame.new(from),
	})
	if not bomb then
		return
	end
	-- glowing streak behind it + smoke and fire trailing off
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(-size * 0.45, 0, 0)
	a0.Parent = bomb
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(size * 0.45, 0, 0)
	a1.Parent = bomb
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.Lifetime = 0.45
	trail.LightEmission = 0.8
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, LAVA_HOT),
		ColorSequenceKeypoint.new(0.5, LAVA),
		ColorSequenceKeypoint.new(1, rgb(70, 40, 35)),
	})
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = bomb
	env.Emit(bomb, "Fire", LAVA, 0, { Rate = 25, Speed = { 0, 1 }, Size = { size, 0.1 }, Life = { 0.25, 0.4 } })
	env.Emit(bomb, "Smoke", rgb(60, 50, 48), 0, { Rate = 14, Speed = { 0, 0.5 }, Size = { size * 0.8, size * 2.2 }, Life = { 0.7, 1.1 }, Trans = { 0.35, 1 } })
	local g = 40
	local d = target - from
	local vel = Vector3.new(d.X / flight, (d.Y + 0.5 * g * flight * flight) / flight, d.Z / flight)
	launch(env, bomb, vel, {
		Gravity = g,
		Spin = Vector3.new(3, 2, 4), -- studded lava cubes tumble
		Life = flight + 1,
		OnLand = function(p)
			lavaSplat(env, p, size)
		end,
	})
end

-- The crater glows up and the ground rumbles before an eruption
local function charge(env: Env, st: VolcanoState, seconds: number, rumble: boolean)
	st.ChargeUntil = env.Now() + seconds
	burstAt(env, st.Crater, "Smoke", rgb(80, 65, 60), 6, { Speed = { 4, 7 }, Spread = 20, Size = { 3, 8 }, Life = { 1.5, 2.5 } })
	if rumble then
		env.Shake(seconds)
	end
end

local function erupt(env: Env, st: VolcanoState, bombs: number, big: boolean)
	local crater = st.Crater
	st.Heat = 1
	-- lava fountain: fast fire that arcs back down, sparks, a thick smoke burst
	burstAt(env, crater, "Fire", LAVA, if big then 90 else 40, {
		Speed = if big then { 28, 42 } else { 20, 32 },
		Spread = 14,
		Accel = Vector3.new(0, -28, 0),
		Size = { 2.4, 0.5 },
		Life = { 1.2, 1.8 },
	})
	burstAt(env, crater, "Sparks", nil, if big then 50 else 20, { Speed = { 15, 25 }, Spread = 35, Life = { 1, 1.6 }, Size = { 0.5, 0 } })
	burstAt(env, crater, "Smoke", rgb(55, 45, 45), if big then 26 else 10, {
		Speed = { 8, 14 },
		Spread = 25,
		Size = { 4, 12 },
		Life = { 2, 3.5 },
		Trans = { 0.3, 1 },
	})
	for i = 1, bombs do
		-- half land near the stage (they show in the walk shots), half across the lava field behind it
		local target = if i % 2 == 0
			then env.StageCenter + env.Right * ((if math.random() < 0.5 then -1 else 1) * (6 + math.random() * 8)) + env.Away * (1 + math.random() * 7)
			else env.StageCenter + env.Right * ((math.random() - 0.5) * 30) + env.Away * (7 + math.random() * 6)
		lavaBomb(env, crater, groundAt(env, target) + Vector3.new(0, 0.6, 0), 1.3 + math.random() * 0.5, 0.9 + math.random() * 0.9)
	end
	env.Shake(if big then 0.6 else 0.2)
end

local Volcano: SetPiece = {
	Focus = function(env)
		return (env.StageCenter + volcanoPos(env)) * 0.5 + Vector3.new(0, 6, 0)
	end,
	Background = function(env)
		local base = volcanoPos(env)
		local st: VolcanoState = {
			Base = base,
			Crater = base + Vector3.new(0, VOLCANO_TOP, 0),
			Heat = 0,
			ChargeUntil = -1,
			Streams = {},
			StreamJ = {},
			StreamSize = {},
			Fissures = {},
		}
		volcanoStates[env.Folder] = st

		-- the mountain: classic studded voxel columns stepping up to a crater, lava down the steps into pools
		local disc = buildVoxelVolcano(env, st, base)

		-- crater: a big light, heat glow, smoke plume and embers
		local core = newPart(env, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(st.Crater + Vector3.new(0, 0.8, 0)) })
		local light: PointLight? = nil
		local halo: ImageLabel? = nil
		local sky: ImageLabel? = nil
		if core then
			local l = Instance.new("PointLight")
			l.Color = LAVA
			l.Range = 45
			l.Brightness = 3
			l.Parent = core
			light = l
			halo = glowBillboard(core, 20, LAVA, 0.4, 1)
			sky = glowBillboard(core, 55, rgb(255, 90, 30), 0.75, 8)
			-- smoke plume: lit orange at the bottom, dark grey above, drifting with the wind
			env.Emit(core, "Smoke", nil, 0, {
				Rate = 1 + 3 * env.Strength,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, rgb(255, 140, 60)),
					ColorSequenceKeypoint.new(0.15, rgb(90, 60, 50)),
					ColorSequenceKeypoint.new(1, rgb(45, 40, 40)),
				}),
				Size = { 5, 16 },
				Life = { 4, 6 },
				Speed = { 5, 8 },
				Spread = 12,
				Accel = env.Right * 1.2 + Vector3.new(0, 0.5, 0),
				Drag = 0.3,
				Trans = { 0.25, 1 },
			})
			env.Emit(core, "Embers", nil, 0, {
				Rate = 14 * env.Strength,
				Speed = { 8, 14 },
				Spread = 25,
				Life = { 1.5, 2.5 },
				Accel = Vector3.new(0, -4, 0),
				Size = { 0.45, 0 },
			})
		end

		-- lava rivers: a near one right behind the walk, and two branches flowing out of the volcano's pool
		local function at(away: number, right: number): Vector3
			return groundAt(env, env.StageCenter + env.Away * away + env.Right * right)
		end
		local near: { Vector3 } = {}
		for i = 0, 8 do
			local x = -24 + i * 6
			table.insert(near, at(6 + 1.2 * math.sin(x * 0.22 + 0.7), x))
		end
		local low = detail() == 0
		local rivers: { River } = { lavaRiver(env, near, 2.6, if low then 0 else 5) }
		if not low then -- Low tier: only the near river, no crust plates, no bubbles
			table.insert(rivers, lavaRiver(env, { at(12.75, -3), at(11.5, -8), at(10.8, -14), at(11.5, -20), at(12.5, -27) }, 2, 3))
			table.insert(rivers, lavaRiver(env, { at(12.75, -3), at(11.2, 2), at(10.5, 8), at(11.2, 14), at(12.2, 21), at(12.8, 28) }, 2, 3))
		end

		-- per frame: crater heat (charges before eruptions), flowing glow waves, drifting crust, bubbles
		local nextBubble = if low then math.huge else 0.3
		local bubbleEvery = if env.Full then 0.45 else 0.9
		env.AddUpdater(function(t, dt)
			if t < st.ChargeUntil then
				st.Heat = math.min(1, st.Heat + dt * 3)
			else
				st.Heat = math.max(0, st.Heat - dt * 0.7)
			end
			local k = math.clamp(0.25 + 0.25 * math.sin(t * 2.2) + st.Heat * 0.75, 0, 1)
			if disc and disc.Parent then
				disc.Color = LAVA:Lerp(LAVA_HOT, k)
			end
			if light then
				light.Brightness = 2 + 6 * k
			end
			if halo then
				halo.ImageTransparency = 0.5 - 0.35 * k
			end
			if sky then
				sky.ImageTransparency = 0.8 - 0.2 * k
			end
			for _, seam in st.Fissures do
				if seam.Parent then
					seam.Color = LAVA_COOL:Lerp(LAVA_HOT, 0.3 + 0.7 * k)
					seam.Transparency = 0.45 - 0.35 * k
				end
			end
			for i, p in st.Streams do
				if p.Parent then
					p.Color = LAVA:Lerp(LAVA_HOT, math.clamp(0.5 + 0.5 * math.sin(t * 4 - st.StreamJ[i] * 1.1) + st.Heat * 0.4, 0, 1))
				end
			end
			for _, r in rivers do
				for i, c in r.Cores do
					if c.Parent then
						c.Color = LAVA:Lerp(LAVA_HOT, 0.35 + 0.35 * math.sin(t * 2.6 - i * 0.9))
					end
				end
				for _, pl in r.Plates do
					if pl.Part.Parent and r.Total > 0 then
						pl.S = (pl.S + dt * pl.Speed) % r.Total
						local pos, dir = riverSample(r, pl.S)
						local at0 = pos + UP * 0.2
						pl.Part.CFrame = CFrame.lookAt(at0, at0 + dir) * CFrame.Angles(0, pl.Yaw + t * 0.2, 0)
					end
				end
			end
			if t >= nextBubble then
				nextBubble = t + bubbleEvery
				local r = rivers[math.random(1, #rivers)]
				if r.Total > 0 then
					local pos = riverSample(r, math.random() * r.Total)
					blorp(env, pos + UP * 0.2, 0.7 + math.random() * 0.6)
				end
			end
		end)

		-- periodic eruptions: charge up (glow + rumble), then blow
		local interval = if env.Full then 2.6 else 4.5
		local nextAt = 1.0
		local charged = false
		env.AddUpdater(function(t, _dt)
			if not charged and t >= nextAt - CHARGE_TIME then
				charged = true
				charge(env, st, CHARGE_TIME, env.Full)
			end
			if t >= nextAt then
				nextAt = t + interval
				charged = false
				erupt(env, st, if env.Full then 3 else 1, false)
			end
		end)
	end,
	Intro = function(env)
		local size = env.SlimeSize
		-- a dark crust rim around the bubbling pool
		local rim = newPart(env, {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Basalt,
			Color = BANK,
			Size = Vector3.new(0.16, size * 3, size * 3),
			CFrame = CFrame.new(env.EmergePos + Vector3.new(0, 0.06, 0)) * VERTICAL,
		})
		local pool = newPart(env, {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Neon,
			Color = LAVA,
			Size = Vector3.new(0.2, size * 2.4, size * 2.4),
			CFrame = CFrame.new(env.EmergePos + Vector3.new(0, 0.1, 0)) * VERTICAL,
		})
		local anchor = newPart(env, { Size = Vector3.new(size * 2, 0.2, size * 2), Transparency = 1, CFrame = CFrame.new(env.EmergePos + Vector3.new(0, 0.2, 0)) })
		if anchor then
			env.Emit(anchor, "Bubbles", LAVA_HOT, 0, { Rate = 14, Spread = 10, Speed = { 1, 2 } })
			env.Emit(anchor, "Embers", nil, 0, { Rate = 10 })
		end
		return {
			Shake = function(k)
				if pool and pool.Parent then
					pool.Color = LAVA:Lerp(LAVA_HOT, k)
					if math.random() < 0.06 + k * 0.15 then
						local off = randomFlat() * (math.random() * size * 0.9)
						blorp(env, env.EmergePos + off + Vector3.new(0, 0.2, 0), 0.5 + math.random() * 0.4 + k * 0.3)
					end
				end
			end,
			Burst = function()
				burstAt(env, env.EmergePos + Vector3.new(0, 0.5, 0), "Fire", LAVA, 40, { Speed = { 8, 14 }, Spread = 45 })
				burstAt(env, env.EmergePos + Vector3.new(0, 0.5, 0), "Sparks", nil, 30)
				-- lava drips off the slime for a moment
				local body = env.Slime.PrimaryPart
				if body then
					local a = Instance.new("Attachment")
					a.Parent = body
					local e = env.Emit(a, "Fire", LAVA, 0, { Rate = 25, Dir = Enum.NormalId.Bottom, Speed = { 1, 2 }, Size = { 0.5, 0.1 }, Life = { 0.3, 0.6 } })
					task.delay(2, function()
						e.Enabled = false
					end)
				end
				if pool then
					fadeAway(pool, 1.2, 1)
				end
				if rim then
					fadeAway(rim, 1.6, 1)
				end
				if anchor then
					task.delay(1.2, function()
						anchor:Destroy()
					end)
				end
			end,
		}
	end,
	Path = function(env, pos, _step)
		-- the ground cracks open in glowing branches that cool down to dark red
		local g = groundAt(env, pos)
		for i = 1, 3 do
			local yaw = (i / 3) * math.pi * 2 + math.random() * 0.8
			local p0 = g
			for seg = 1, 2 do
				local len = (if seg == 1 then 1.1 else 0.7) + math.random() * 0.8
				local crack = newPart(env, { Material = Enum.Material.Neon, Color = LAVA_HOT, Size = Vector3.new(0.16, 0.06, len) })
				if not crack then
					break
				end
				crack.CFrame = CFrame.new(p0 + UP * 0.04) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -len / 2)
				p0 = (crack.CFrame * CFrame.new(0, 0, -len / 2)).Position - UP * 0.04
				yaw += (math.random() - 0.5) * 1.2
				tween(crack, 1, { Color = LAVA_COOL })
				fadeAway(crack, 1, 0.8)
			end
		end
		burstAt(env, g + Vector3.new(0, 0.2, 0), "Fire", LAVA, 6, { Speed = { 2, 5 }, Spread = 30 })
	end,
	Climax = function(env, pos)
		local st = volcanoStates[env.Folder]
		if not st then
			erupt(env, {
				Base = volcanoPos(env),
				Crater = volcanoPos(env) + Vector3.new(0, VOLCANO_TOP, 0),
				Heat = 0,
				ChargeUntil = -1,
				Streams = {},
				StreamJ = {},
				StreamSize = {},
				Fissures = {},
			}, 8, true)
			env.Flash(rgb(255, 80, 30), 0.45)
			return
		end
		-- charge: heavy rumble, crater white-hot
		charge(env, st, 0.35, true)
		task.delay(0.35, function()
			if not env.Folder.Parent then
				return
			end
			erupt(env, st, 10, true)
			-- lava pillar shooting out of the crater
			local pillar = newPart(env, { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = LAVA_HOT, Transparency = 0.1 })
			if pillar then
				sproutColumn(pillar, st.Crater - Vector3.new(0, 1, 0), 32, 3.4, 0.3)
				fadeAway(pillar, 0.9, 0.6)
			end
			-- the streams flare wide and bright
			for i, slab in st.Streams do
				if slab.Parent then
					local size = st.StreamSize[i]
					tween(slab, 0.25, { Size = size * Vector3.new(1.3, 1, 1.3) })
					task.delay(0.6, function()
						if slab.Parent then
							tween(slab, 1.2, { Size = size })
						end
					end)
				end
			end
			-- a glowing shockwave ring races out across the ground from the volcano
			local ring = newPart(env, {
				Size = Vector3.new(30, 0.1, 30),
				Transparency = 1,
				CFrame = CFrame.new(st.Base + Vector3.new(0, 0.15, 0)),
			})
			if ring then
				local decal = Instance.new("Decal")
				decal.Face = Enum.NormalId.Top
				decal.Texture = UiAssets.Textures.ring
				decal.Color3 = LAVA_HOT
				decal.Transparency = 0.1
				decal.Parent = ring
				tween(ring, 0.9, { Size = Vector3.new(110, 0.1, 110) })
				tween(decal, 0.9, { Transparency = 1 })
				task.delay(1, function()
					ring:Destroy()
				end)
			end
			-- fire pillar behind the slime
			burstAt(env, groundAt(env, pos + env.Away * 4), "Fire", LAVA, 60, { Speed = { 18, 28 }, Spread = 8, Size = { 2.6, 0.4 }, Life = { 0.6, 0.9 } })
			env.Flash(rgb(255, 80, 30), 0.45)
		end)
	end,
}

-- ============================================================================
-- Frost Peaks: snow mound it crawls out of, blizzard gusts + snow drifts, footprints, ice spike ring
-- ============================================================================
local SNOW = rgb(245, 250, 255)
local ICE = rgb(180, 225, 255)

local Blizzard: SetPiece = {
	Focus = function(env)
		return env.StageCenter + env.Away * 5
	end,
	Background = function(env)
		-- heavy snowfall blown sideways
		local box = newPart(env, {
			Size = Vector3.new(40, 0.2, 22),
			CFrame = CFrame.new(env.StageCenter + env.Away * 3 + Vector3.new(0, 11, 0)),
			Transparency = 1,
		})
		if box then
			env.Emit(box, "Snow", nil, 0, { Rate = 45 * env.Strength, Accel = env.Right * 4 + Vector3.new(0, -2, 0), Life = { 3, 4 } })
		end
		-- stepped snow drifts in the background
		for i = 1, 3 do
			stepMound(env, groundAt(env, env.StageCenter + env.Away * (9 + i * 2) + env.Right * ((i - 2) * 11)), 9, 4, SNOW, -env.Away)
		end
		-- gusts: a wave of blowing snow every ~2s
		local nextAt = 0.4
		local interval = if env.Full then 2 else 3.5
		env.AddUpdater(function(t, _dt)
			if t >= nextAt then
				nextAt = t + interval
				local from = env.StageCenter - env.Right * 16 + Vector3.new(0, 1.5, 0) + env.Away * 2
				local anchor = newPart(env, {
					Size = Vector3.new(0.5, 4, 10),
					Transparency = 1,
					CFrame = CFrame.lookAt(from, from + env.Right) * CFrame.Angles(0, math.pi / 2, 0),
				})
				if anchor then
					env.Emit(anchor, "Smoke", SNOW, 18, { Dir = Enum.NormalId.Right, Speed = { 18, 26 }, Spread = 6, Size = { 1.5, 3 }, Life = { 1, 1.4 }, Trans = { 0.5, 1 } })
					task.delay(2, function()
						anchor:Destroy()
					end)
				end
			end
		end)
	end,
	Intro = function(env)
		local size = env.SlimeSize
		-- a stepped snow mound (the slime's head pokes just out of the top tier)
		local tiers = stepMound(env, env.EmergePos, size * 2, size * 1.05, SNOW, -env.Away)
		return {
			Shake = function(k)
				for i, tier in tiers do
					if tier.Part.Parent then
						local a = 0.35 * k * (1 - (i - 1) * 0.2)
						tier.Part.CFrame = tier.Home * CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * 0.1 * k, (math.random() - 0.5) * a)
					end
				end
				if k > 0.5 and math.random() < 0.15 then
					burstAt(env, env.EmergePos + Vector3.new(0, size * 0.9, 0), "Snow", nil, 3, { Speed = { 2, 4 }, Dir = Enum.NormalId.Top })
				end
			end,
			Burst = function()
				-- the mound cracks into chunks that fly off
				for _ = 1, 10 do
					local chunk = newPart(env, {
						Shape = Enum.PartType.Ball,
						Material = Enum.Material.Snow,
						Color = SNOW,
						Size = Vector3.new(1, 1, 1) * (0.5 + math.random() * 0.8),
						CFrame = CFrame.new(env.EmergePos + Vector3.new(0, size * 0.6, 0)),
					})
					if chunk then
						launch(env, chunk, randomFlat() * (6 + math.random() * 6) + Vector3.new(0, 12 + math.random() * 6, 0), {
							Spin = Vector3.new(6, 2, 5),
							Life = 2,
							OnLand = function(p)
								burstAt(env, p, "Snow", nil, 4, { Speed = { 2, 4 }, Dir = Enum.NormalId.Top })
							end,
						})
					end
				end
				for _, tier in tiers do
					tier.Part:Destroy()
				end
				burstAt(env, env.EmergePos + Vector3.new(0, 1, 0), "Snow", nil, 40, { Speed = { 6, 12 }, Dir = Enum.NormalId.Top, Spread = 70 })
				burstAt(env, env.EmergePos + Vector3.new(0, 0.5, 0), "Smoke", SNOW, 14, { Speed = { 4, 8 }, Spread = 80 })
			end,
		}
	end,
	Path = function(env, pos, _step)
		local footprint = newPart(env, {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Snow,
			Color = rgb(210, 220, 235),
			Size = Vector3.new(0.08, 1.4, 1.4),
			CFrame = CFrame.new(groundAt(env, pos) + Vector3.new(0, 0.04, 0)) * VERTICAL,
		})
		if footprint then
			fadeAway(footprint, 3, 1)
		end
		burstAt(env, groundAt(env, pos) + Vector3.new(0, 0.3, 0), "Smoke", SNOW, 5, { Speed = { 2, 4 }, Spread = 80 })
	end,
	Climax = function(env, pos)
		spikeRing(env, pos, 9, 3.4, 5.5, ICE, Enum.Material.Ice)
		env.Flash(SNOW, 0.35)
	end,
}

-- ============================================================================
-- Candy Land: gift box jack-in-the-box, spinning giant lollipops, candy canes + bouncing gumdrops
-- ============================================================================
local CANDY = { rgb(255, 120, 190), rgb(120, 220, 255), rgb(255, 230, 100), rgb(160, 255, 150), rgb(200, 140, 255) }

local function lollipop(env: Env, base: Vector3, height: number, color: Color3, time: number): Part?
	local stick = newPart(env, { Shape = Enum.PartType.Cylinder, Color = rgb(250, 250, 250) })
	if stick then
		sproutColumn(stick, base, height, 0.35, time)
	end
	local disc = newPart(env, { Shape = Enum.PartType.Cylinder, Color = color, Material = Enum.Material.SmoothPlastic })
	if disc then
		local d = height * 0.55
		disc.Size = Vector3.new(0.3, 0.05, 0.05)
		local cf = CFrame.lookAt(base + Vector3.new(0, height, 0), base + Vector3.new(0, height, 0) + env.Away)
			* CFrame.Angles(0, math.pi / 2, 0)
		disc.CFrame = cf
		tween(disc, time * 1.2, { Size = Vector3.new(0.3, d, d) }, Enum.EasingStyle.Back)
		local stripe = newPart(env, { Shape = Enum.PartType.Cylinder, Color = rgb(255, 255, 255), Size = Vector3.new(0.32, 0.05, 0.05), CFrame = cf })
		if stripe then
			tween(stripe, time * 1.2, { Size = Vector3.new(0.32, d * 0.5, d * 0.5) }, Enum.EasingStyle.Back)
		end
	end
	return disc
end

local function gumdrop(env: Env, from: Vector3, vel: Vector3)
	local g = newPart(env, {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Glass,
		Color = CANDY[math.random(1, #CANDY)],
		Size = Vector3.new(0.9, 0.9, 0.9),
		CFrame = CFrame.new(from),
	})
	if g then
		launch(env, g, vel, { Bounce = 0.6, Bounces = 3, Spin = Vector3.new(3, 5, 2), Life = 4 })
	end
end

local Candy: SetPiece = {
	Focus = function(env)
		return env.StageCenter + env.Away * 6
	end,
	Background = function(env)
		local discs: { Part } = {}
		for i = 1, 3 do
			local base = groundAt(env, env.StageCenter + env.Away * (10 + (i % 2) * 3) + env.Right * ((i - 2) * 10))
			local d = lollipop(env, base, 6 + i, CANDY[i], 0.6)
			if d then
				table.insert(discs, d)
			end
		end
		env.AddUpdater(function(_t, dt)
			for i, d in discs do
				if d.Parent then
					d.CFrame = d.CFrame * CFrame.Angles(dt * (1 + i * 0.4), 0, 0)
				end
			end
		end)
	end,
	Intro = function(env)
		local size = env.SlimeSize * 1.45
		local base = env.EmergePos
		local box = newPart(env, {
			Color = CANDY[1],
			Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(base + Vector3.new(0, size / 2, 0)),
		})
		local ribbonA = newPart(env, { Color = rgb(255, 245, 120), Size = Vector3.new(size + 0.05, size + 0.05, size * 0.18), CFrame = CFrame.new(base + Vector3.new(0, size / 2, 0)) })
		local ribbonB = newPart(env, { Color = rgb(255, 245, 120), Size = Vector3.new(size * 0.18, size + 0.05, size + 0.05), CFrame = CFrame.new(base + Vector3.new(0, size / 2, 0)) })
		local lid = newPart(env, { Color = CANDY[2], Size = Vector3.new(size * 1.1, size * 0.22, size * 1.1), CFrame = CFrame.new(base + Vector3.new(0, size + size * 0.11, 0)) })
		local parts = { box, ribbonA, ribbonB, lid }
		local homes: { CFrame } = {}
		for i, p in parts do
			homes[i] = if p then p.CFrame else CFrame.identity
		end
		return {
			Shake = function(k)
				local rot = CFrame.Angles(0, 0, math.rad((math.random() - 0.5) * 14 * k))
				for i, p in parts do
					if p and p.Parent then
						p.CFrame = CFrame.new(base) * rot * CFrame.new(base):Inverse() * homes[i] + Vector3.new(0, math.abs(math.sin(os.clock() * 40)) * 0.15 * k, 0)
					end
				end
			end,
			Burst = function()
				if lid then
					launch(env, lid, randomFlat() * 4 + Vector3.new(0, 22, 0), { Spin = Vector3.new(6, 9, 4), Life = 2.5 })
				end
				for i = 1, 3 do
					local p = parts[i]
					if p then
						tween(p, 0.3, { Size = Vector3.new(p.Size.X * 1.2, 0.1, p.Size.Z * 1.2), Transparency = 1 })
						task.delay(0.35, function()
							p:Destroy()
						end)
					end
				end
				burstAt(env, base + Vector3.new(0, size, 0), "Confetti", nil, 50, { Speed = { 10, 16 }, Spread = 40 })
			end,
		}
	end,
	Path = function(env, pos, step)
		-- a candy cane sprouts, and every other step a gumdrop rains in
		local base = groundAt(env, pos + env.Away * (if step % 2 == 0 then 1.9 else -1.9))
		for seg = 0, 2 do
			local p = newPart(env, { Shape = Enum.PartType.Cylinder, Color = if seg % 2 == 0 then rgb(255, 70, 90) else rgb(255, 255, 255) })
			if p then
				task.delay(seg * 0.06, function()
					if p.Parent then
						p.Size = Vector3.new(0.05, 0.35, 0.35)
						p.CFrame = CFrame.new(base + Vector3.new(0, seg * 0.45 + 0.225, 0)) * VERTICAL
						tween(p, 0.15, { Size = Vector3.new(0.45, 0.35, 0.35) }, Enum.EasingStyle.Back)
					end
				end)
			end
		end
		if step % 2 == 1 then
			gumdrop(env, pos + Vector3.new(0, 9, 0) + env.Away * 2 + env.Right * (math.random() - 0.5) * 4, Vector3.new(0, -2, 0))
		end
	end,
	Climax = function(env, pos)
		for _ = 1, 10 do
			gumdrop(env, pos + Vector3.new(0, 10, 0) + randomFlat() * (math.random() * 4), randomFlat() * 3)
		end
		for i = 1, 3 do
			local a = (i / 3) * math.pi * 2 + 0.5
			local base = groundAt(env, pos + Vector3.new(math.cos(a), 0, math.sin(a)) * 4)
			lollipop(env, base, 3.2, CANDY[i + 1], 0.35)
		end
	end,
}

-- ============================================================================
-- Desert Dunes: sand dune collapses, sandstorm wall + tumbleweeds, sand sprays, rising pyramid
-- ============================================================================
local SAND = rgb(225, 195, 135)

local function tumbleweed(env: Env)
	local from = env.StageCenter - env.Right * 22 + env.Away * (1 + math.random() * 6)
	local w = newPart(env, {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Fabric,
		Color = rgb(150, 115, 70),
		Transparency = 0.15,
		Size = Vector3.new(1.6, 1.6, 1.6),
		CFrame = CFrame.new(groundAt(env, from) + Vector3.new(0, 0.8, 0)),
	})
	if w then
		launch(env, w, env.Right * 14 + Vector3.new(0, 6, 0), { Bounce = 0.55, Bounces = 6, Spin = Vector3.new(0, 0, -10), Life = 3.5 })
	end
end

local Desert: SetPiece = {
	Focus = function(env)
		return env.StageCenter + env.Away * 6
	end,
	Background = function(env)
		-- sandstorm wall sweeping across
		local wall = newPart(env, { Size = Vector3.new(2, 6, 14), Transparency = 1 })
		if wall then
			env.Emit(wall, "Sand", nil, 0, { Rate = 30 * env.Strength, Dir = Enum.NormalId.Right, Speed = { 10, 16 }, Size = { 1.5, 3.5 }, Life = { 1, 1.6 } })
			env.AddUpdater(function(t, _dt)
				local x = ((t * 6) % 50) - 25
				local c = env.StageCenter + env.Right * x + env.Away * 7 + Vector3.new(0, 2, 0)
				wall.CFrame = CFrame.lookAt(c, c + env.Right) * CFrame.Angles(0, math.pi / 2, 0)
			end)
		end
		-- tumbleweeds rolling through
		local nextAt = 0.3
		local interval = if env.Full then 2.4 else 4
		env.AddUpdater(function(t, _dt)
			if t >= nextAt then
				nextAt = t + interval
				tumbleweed(env)
			end
		end)
	end,
	Intro = function(env)
		local size = env.SlimeSize
		-- a stepped sand dune
		local tiers = stepMound(env, env.EmergePos, size * 2.1, size * 1.05, SAND, -env.Away)
		local top = tiers[#tiers]
		if top then
			env.Emit(top.Part, "Sand", nil, 0, { Rate = 4, Dir = Enum.NormalId.Top, Speed = { 1, 2 }, Spread = 60 })
		end
		return {
			Shake = function(k)
				for _, tier in tiers do
					if tier.Part.Parent then
						tier.Part.CFrame = tier.Home * CFrame.new((math.random() - 0.5) * 0.3 * k, 0, (math.random() - 0.5) * 0.3 * k)
					end
				end
			end,
			Burst = function()
				-- the dune collapses tier by tier and pours away
				for i, tier in tiers do
					local p = tier.Part
					tween(p, 0.45 + i * 0.05, {
						Size = Vector3.new(tier.Size.X * 1.4, 0.2, tier.Size.Z * 1.4),
						CFrame = tier.Home.Rotation + (env.EmergePos + Vector3.new(0, 0.1 + i * 0.05, 0)),
					})
					fadeAway(p, 0.6, 0.8)
				end
				burstAt(env, env.EmergePos + Vector3.new(0, 1, 0), "Sand", nil, 30, { Speed = { 6, 12 }, Dir = Enum.NormalId.Top, Spread = 80 })
			end,
		}
	end,
	Path = function(env, pos, _step)
		burstAt(env, groundAt(env, pos) + Vector3.new(0, 0.3, 0), "Sand", nil, 6, { Speed = { 3, 6 }, Dir = Enum.NormalId.Top, Spread = 70 })
	end,
	Climax = function(env, pos)
		-- a stepped pyramid rises behind the slime
		local base = groundAt(env, pos + env.Away * 12)
		for i = 0, 4 do
			local w = 14 - i * 2.8
			local block = newPart(env, { Material = Enum.Material.Sandstone, Color = rgb(215, 180, 110) })
			if block then
				task.delay(i * 0.08, function()
					if block.Parent then
						block.Size = Vector3.new(w, 1.8, w)
						block.CFrame = CFrame.new(base + Vector3.new(0, i * 1.8 - 1.8, 0))
						tween(block, 0.45, { CFrame = CFrame.new(base + Vector3.new(0, i * 1.8 + 0.9, 0)) }, Enum.EasingStyle.Back)
					end
				end)
			end
		end
		env.Shake(0.3)
	end,
}

-- ============================================================================
-- Acid Swamp: toxic pool, erupting acid geysers, path spurts, giant geyser climax
-- ============================================================================
local ACID = rgb(120, 255, 90)

local function geyser(env: Env, base: Vector3, height: number, width: number)
	local col = newPart(env, { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = ACID, Transparency = 0.25 })
	if not col then
		return
	end
	sproutColumn(col, base, height, width, 0.25)
	burstAt(env, base + Vector3.new(0, height, 0), "Bubbles", ACID, math.floor(height * 3), { Speed = { 4, 8 }, Spread = 50 })
	burstAt(env, base + Vector3.new(0, 0.3, 0), "Smoke", rgb(120, 200, 90), 6, { Speed = { 2, 4 }, Spread = 80 })
	task.delay(0.6, function()
		if col.Parent then
			tween(col, 0.35, { Size = Vector3.new(0.05, width * 0.6, width * 0.6), CFrame = CFrame.new(base + Vector3.new(0, 0.03, 0)) * VERTICAL })
			task.delay(0.4, function()
				col:Destroy()
			end)
		end
	end)
end

local Acid: SetPiece = {
	Focus = function(env)
		return env.StageCenter + env.Away * 6
	end,
	Background = function(env)
		local spots: { Vector3 } = {}
		for i = 1, 3 do
			local base = groundAt(env, env.StageCenter + env.Away * (8 + i * 3) + env.Right * ((i - 2) * 10))
			table.insert(spots, base)
			-- a toxic puddle that the geyser comes out of
			newPart(env, {
				Shape = Enum.PartType.Cylinder,
				Material = Enum.Material.Neon,
				Color = rgb(80, 200, 60),
				Size = Vector3.new(0.1, 4, 4),
				CFrame = CFrame.new(base + Vector3.new(0, 0.05, 0)) * VERTICAL,
			})
		end
		local nextAt = 0.5
		local idx = 0
		local interval = if env.Full then 1.1 else 2.2
		env.AddUpdater(function(t, _dt)
			if t >= nextAt then
				nextAt = t + interval
				idx = idx % #spots + 1
				geyser(env, spots[idx], 7 + math.random() * 4, 1.6)
			end
		end)
	end,
	Intro = function(env)
		local size = env.SlimeSize
		local pool = newPart(env, {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Neon,
			Color = rgb(80, 200, 60),
			Size = Vector3.new(0.2, size * 2.4, size * 2.4),
			CFrame = CFrame.new(env.EmergePos + Vector3.new(0, 0.08, 0)) * VERTICAL,
		})
		if pool then
			env.Emit(pool, "Bubbles", ACID, 0, { Rate = 16, Spread = 15 })
		end
		return {
			Shake = function(k)
				if pool and pool.Parent then
					pool.Color = rgb(80, 200, 60):Lerp(ACID, k)
				end
			end,
			Burst = function()
				burstAt(env, env.EmergePos + Vector3.new(0, 0.5, 0), "Bubbles", ACID, 40, { Speed = { 6, 12 }, Spread = 50 })
				burstAt(env, env.EmergePos + Vector3.new(0, 0.5, 0), "Smoke", rgb(120, 200, 90), 12, { Speed = { 4, 8 }, Spread = 80 })
				local body = env.Slime.PrimaryPart
				if body then
					local a = Instance.new("Attachment")
					a.Parent = body
					local e = env.Emit(a, "Bubbles", ACID, 0, { Rate = 18, Dir = Enum.NormalId.Bottom, Speed = { 1, 2 }, Accel = Vector3.new(0, -6, 0) })
					task.delay(2, function()
						e.Enabled = false
					end)
				end
				if pool then
					fadeAway(pool, 1.2, 1)
				end
			end,
		}
	end,
	Path = function(env, pos, step)
		if step % 2 == 0 then
			geyser(env, groundAt(env, pos + env.Away * 2.2 + env.Right * 0.5), 2.5, 0.6)
		end
	end,
	Climax = function(env, pos)
		geyser(env, groundAt(env, pos + env.Away * 6), 16, 3.2)
		env.Flash(ACID, 0.4)
		env.Shake(0.3)
	end,
}

CatchSetPieces.Pieces = {
	Meadow = Meadow,
	Crystal = Crystal,
	Volcano = Volcano,
	Blizzard = Blizzard,
	Candy = Candy,
	Desert = Desert,
	Acid = Acid,
} :: { [string]: SetPiece }

return CatchSetPieces
