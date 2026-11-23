--!strict
--[[
	CatchFx.luau
	Client runtime for the catch-cutscene effects designed in CatchFxData.luau: zone screen mood, face
	personality and per-slime signatures (spinning halos, orbiting gems, eruptions, confetti...).

	Lifecycle (ThrowController runRevealCutscene):
		CatchFx.Start(ctx)          zone grade + screen edges + zone ambient (after the fade-in)
		CatchFx.BeginWalk()         personality + signature Walk ops (once the slime is visible)
		CatchFx.Landed(groundPos)   Land ops (SlimeMotion fx.Landed)
		CatchFx.Showcase(showPos)   Show ops for zone + personality + signature
		CatchFx.Update(dt)          every frame (drives part motions, pulses, beams)
		CatchFx.Stop()              guaranteed teardown: destroys everything, restores the camera FOV

	Everything is client-side. World objects live in one Folder, screen objects in one Frame under the reveal
	root, post effects on the Camera; Stop() removes all of them.
]]

local TweenService = game:GetService("TweenService")

local CatchFxData = require(script.Parent:WaitForChild("CatchFxData"))
local CatchSetPieces = require(script.Parent:WaitForChild("CatchSetPieces"))
local SlimeFactory = require(script.Parent:WaitForChild("SlimeFactory"))
local UiAssets = require(script.Parent:WaitForChild("UiAssets"))

local CatchFx = {}

export type Ctx = {
	Model: Model,
	SlimeId: string,
	ZoneIndex: number,
	StageCenter: Vector3, -- ground-rest centre of the walk (floorY + 1.22)
	FloorY: number,
	Camera: Camera,
	RevealRoot: GuiObject,
	Shake: (seconds: number) -> (),
	-- exaggerated show (CatchSetPieces)
	Full: boolean, -- full show (intro prop + climax) vs lite (background at half strength)
	EmergePos: Vector3, -- ground point where the slime comes out
	BaitPos: Vector3,
	ViewDir: Vector3, -- direction from the stage toward the camera (backgrounds go the other way)
}

type Op = CatchFxData.Op
type Updater = (t: number, dt: number) -> ()
type MotionAcc = { Rot: CFrame, Pos: Vector3, Scale: number }

-- ============================================================================
-- Textures
-- ============================================================================
local TEX = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Sparks = "rbxasset://textures/particles/fire_sparks_main.dds",
	Glow = UiAssets.Textures.glow,
	Ring = UiAssets.Textures.ring,
	Sunburst = UiAssets.Textures.sunburst,
	Stripes = UiAssets.Textures.stripes,
}

local function iconTex(name: string?): string
	local icons = UiAssets.Icons :: any
	return (name and icons[name]) or icons.star
end

local function rgb(c: CatchFxData.RGB?, fallback: Color3): Color3
	if c then
		return Color3.fromRGB(c[1] or 255, c[2] or 255, c[3] or 255)
	end
	return fallback
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 180, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(110, 255, 130)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 120, 255)),
})

-- ============================================================================
-- Particle presets
-- ============================================================================
type Spec = {
	Tex: string,
	Color: ColorSequence,
	Size: { number },
	Life: { number },
	Speed: { number },
	Spread: number,
	Dir: Enum.NormalId,
	Accel: Vector3,
	Drag: number,
	Light: number,
	Rot: { number },
	Spin: { number },
	Trans: { number },
	Rate: number,
}

local function spec(tex: string, color: ColorSequence, overrides: { [string]: any }): Spec
	local s: Spec = {
		Tex = tex,
		Color = color,
		Size = { 0.4, 0 },
		Life = { 0.6, 1.2 },
		Speed = { 1, 3 },
		Spread = 180,
		Dir = Enum.NormalId.Top,
		Accel = Vector3.zero,
		Drag = 0,
		Light = 0,
		Rot = { 0, 0 },
		Spin = { 0, 0 },
		Trans = { 0.1, 1 },
		Rate = 6,
	}
	for k, v in overrides do
		(s :: any)[k] = v
	end
	return s
end

local function presetSpec(name: string, color: Color3?, texName: string?): Spec
	local function cs(default: Color3): ColorSequence
		return ColorSequence.new(color or default)
	end
	if name == "Sparkle" then
		return spec(TEX.Sparkle, cs(Color3.new(1, 1, 1)), { Size = { 0.35, 0 }, Light = 0.8 })
	elseif name == "Glints" then
		return spec(
			TEX.Sparkle,
			if color then ColorSequence.new(color) else RAINBOW,
			{ Size = { 0.5, 0 }, Life = { 0.25, 0.55 }, Speed = { 0, 0.3 }, Light = 1, Rate = 4 }
		)
	elseif name == "Smoke" then
		return spec(
			TEX.Smoke,
			cs(Color3.fromRGB(230, 230, 230)),
			{ Size = { 0.8, 2.2 }, Life = { 0.7, 1.3 }, Speed = { 1.5, 3.5 }, Spread = 45, Trans = { 0.45, 1 }, Drag = 2 }
		)
	elseif name == "Dust" then
		return spec(
			TEX.Smoke,
			cs(Color3.fromRGB(200, 180, 150)),
			{ Size = { 0.6, 1.6 }, Life = { 0.5, 0.9 }, Speed = { 2, 4 }, Spread = 75, Trans = { 0.5, 1 }, Drag = 4 }
		)
	elseif name == "Fire" then
		return spec(
			TEX.Fire,
			cs(Color3.fromRGB(255, 140, 40)),
			{ Size = { 0.8, 0.1 }, Life = { 0.3, 0.6 }, Speed = { 2, 4 }, Spread = 18, Light = 1, Trans = { 0.2, 1 }, Rate = 18 }
		)
	elseif name == "Embers" then
		return spec(
			TEX.Sparks,
			cs(Color3.fromRGB(255, 150, 60)),
			{ Size = { 0.25, 0 }, Life = { 1, 2 }, Speed = { 1, 3 }, Spread = 60, Accel = Vector3.new(0, 2, 0), Light = 1 }
		)
	elseif name == "Sparks" then
		return spec(
			TEX.Sparks,
			cs(Color3.fromRGB(255, 200, 90)),
			{ Size = { 0.3, 0 }, Life = { 0.4, 0.8 }, Speed = { 6, 11 }, Spread = 70, Accel = Vector3.new(0, -12, 0), Light = 1 }
		)
	elseif name == "Bubbles" then
		return spec(
			TEX.Ring,
			cs(Color3.fromRGB(180, 230, 255)),
			{
				Size = { 0.25, 0.5 },
				Life = { 1.2, 2.2 },
				Speed = { 0.8, 2 },
				Spread = 35,
				Accel = Vector3.new(0, 1.5, 0),
				Light = 0.3,
				Trans = { 0.15, 1 },
			}
		)
	elseif name == "Snow" then
		return spec(
			TEX.Glow,
			cs(Color3.new(1, 1, 1)),
			{
				Size = { 0.22, 0.15 },
				Life = { 3, 5 },
				Speed = { 0.4, 1 },
				Spread = 25,
				Dir = Enum.NormalId.Bottom,
				Accel = Vector3.new(0.3, -1, 0),
				Trans = { 0.05, 0.6 },
			}
		)
	elseif name == "Leaves" then
		return spec(
			iconTex("clover"),
			cs(Color3.fromRGB(150, 230, 110)),
			{
				Size = { 0.5, 0.4 },
				Life = { 3, 5 },
				Speed = { 0.5, 1.5 },
				Spread = 30,
				Dir = Enum.NormalId.Bottom,
				Accel = Vector3.new(0.6, -0.8, 0),
				Rot = { 0, 360 },
				Spin = { -90, 90 },
				Trans = { 0.05, 0.8 },
			}
		)
	elseif name == "Petals" then
		return spec(
			TEX.Glow,
			cs(Color3.fromRGB(255, 170, 210)),
			{
				Size = { 0.32, 0.25 },
				Life = { 3, 5 },
				Speed = { 0.5, 1.5 },
				Spread = 40,
				Dir = Enum.NormalId.Bottom,
				Accel = Vector3.new(0.7, -0.7, 0),
				Rot = { 0, 360 },
				Spin = { -120, 120 },
				Trans = { 0.05, 0.8 },
			}
		)
	elseif name == "Stars" or name == "Icon" then
		return spec(
			if name == "Icon" then iconTex(texName) else iconTex("star"),
			if color then ColorSequence.new(color) elseif name == "Icon" then cs(Color3.new(1, 1, 1)) else RAINBOW,
			{ Size = { 0.6, 0 }, Life = { 0.7, 1.2 }, Speed = { 4, 8 }, Spin = { -180, 180 }, Drag = 3, Light = 0.4 }
		)
	elseif name == "Confetti" then
		return spec(
			TEX.Glow,
			if color then ColorSequence.new(color) else RAINBOW,
			{
				Size = { 0.35, 0.3 },
				Life = { 1.5, 2.5 },
				Speed = { 6, 12 },
				Spread = 50,
				Accel = Vector3.new(0, -7, 0),
				Rot = { 0, 360 },
				Spin = { -300, 300 },
				Trans = { 0, 0.6 },
			}
		)
	elseif name == "Feathers" then
		return spec(
			TEX.Glow,
			cs(Color3.new(1, 1, 1)),
			{
				Size = { 0.45, 0.35 },
				Life = { 2.5, 3.5 },
				Speed = { 0.5, 1.5 },
				Spread = 30,
				Dir = Enum.NormalId.Bottom,
				Accel = Vector3.new(0, -0.6, 0),
				Rot = { 0, 360 },
				Spin = { -60, 60 },
				Light = 0.5,
				Trans = { 0.1, 1 },
			}
		)
	elseif name == "Seeds" then
		return spec(
			TEX.Sparkle,
			cs(Color3.fromRGB(255, 255, 245)),
			{ Size = { 0.3, 0.2 }, Life = { 2, 4 }, Speed = { 1, 3 }, Accel = Vector3.new(1.2, 0.5, 0), Spin = { -90, 90 }, Drag = 1 }
		)
	elseif name == "Sand" then
		return spec(
			TEX.Smoke,
			cs(Color3.fromRGB(230, 200, 140)),
			{ Size = { 0.5, 1.4 }, Life = { 0.8, 1.4 }, Speed = { 3, 6 }, Spread = 20, Dir = Enum.NormalId.Right, Trans = { 0.5, 1 } }
		)
	elseif name == "Wisps" then
		return spec(
			TEX.Smoke,
			cs(Color3.fromRGB(60, 40, 80)),
			{ Size = { 0.6, 0.2 }, Life = { 0.4, 0.8 }, Speed = { 0.5, 1.5 }, Trans = { 0.3, 1 } }
		)
	elseif name == "Spores" then
		return spec(
			TEX.Glow,
			cs(Color3.fromRGB(255, 240, 200)),
			{ Size = { 0.25, 0.4 }, Life = { 1.5, 2.5 }, Speed = { 0.5, 1.5 }, Accel = Vector3.new(0, 0.4, 0), Light = 0.4, Trans = { 0.2, 1 } }
		)
	end
	return spec(TEX.Sparkle, cs(Color3.new(1, 1, 1)), {})
end

local function applySpec(e: ParticleEmitter, s: Spec)
	e.Texture = s.Tex
	e.Color = s.Color
	e.Size = NumberSequence.new(s.Size[1], s.Size[2])
	e.Transparency = NumberSequence.new(s.Trans[1], s.Trans[2])
	e.Lifetime = NumberRange.new(s.Life[1], s.Life[2])
	e.Speed = NumberRange.new(s.Speed[1], s.Speed[2])
	e.SpreadAngle = Vector2.new(s.Spread, s.Spread)
	e.EmissionDirection = s.Dir
	e.Acceleration = s.Accel
	e.Drag = s.Drag
	e.LightEmission = s.Light
	e.Rotation = NumberRange.new(s.Rot[1], s.Rot[2])
	e.RotSpeed = NumberRange.new(s.Spin[1], s.Spin[2])
	e.Rate = s.Rate
end

-- ============================================================================
-- Session state
-- ============================================================================
type Session = {
	Ctx: Ctx,
	Folder: Folder,
	Screen: Frame,
	Grade: ColorCorrectionEffect,
	Bloom: BloomEffect,
	BaseFov: number,
	Updaters: { Updater },
	MotionKeys: { [string]: boolean }, -- keys set last frame (cleared when no op drives them any more)
	MotionOps: { (acc: { [string]: MotionAcc }, t: number, dt: number) -> () },
	Grows: { [string]: { From: number, To: number, T0: number, Time: number } },
	T0: number,
	WalkStarted: boolean,
	Edges: { GuiObject },
	FovOffset: number, -- added by the camera director (heat haze)
	Piece: any?, -- CatchSetPieces set piece for this zone
	Env: CatchSetPieces.Env?,
	Intro: CatchSetPieces.Intro?,
}

local session: Session? = nil

local function now(s: Session): number
	return os.clock() - s.T0
end

local function body(model: Model): BasePart?
	local parts = SlimeFactory.FindParts(model, "^Body$")
	if parts[1] then
		return parts[1]
	end
	return model.PrimaryPart
end

-- Parts an op targets: Pattern, Key (exact name) or the body
local function targets(s: Session, op: Op, cap: number?): { BasePart }
	local model = s.Ctx.Model
	local found: { BasePart }
	if op.Pattern then
		found = SlimeFactory.FindParts(model, op.Pattern)
	elseif op.Key then
		found = SlimeFactory.FindParts(model, "^" .. op.Key .. "$")
	else
		found = {}
	end
	if #found == 0 then
		local b = body(model)
		if b and not op.Pattern and not op.Key then
			found = { b }
		end
	end
	if cap and #found > cap then
		local trimmed = {}
		for i = 1, cap do
			trimmed[i] = found[i]
		end
		found = trimmed
	end
	return found
end

local function slimeCentre(s: Session): Vector3
	local root = s.Ctx.Model.PrimaryPart
	return if root then root.Position else s.Ctx.StageCenter
end

local function anchorPart(s: Session, cf: CFrame, size: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = "FxAnchor"
	p.Size = size or Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = cf
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = s.Folder
	return p
end

local function emitterOn(parent: Instance, sp: Spec): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	applySpec(e, sp)
	e.Parent = parent
	return e
end

local function opSpec(op: Op): Spec
	local sp = presetSpec(op.Preset or "Sparkle", if op.Color then rgb(op.Color, Color3.new(1, 1, 1)) else nil, op.Tex)
	if op.Speed then
		sp.Speed = { op.Speed * 0.6, op.Speed }
	end
	return sp
end

local function axisAngles(axis: string?, a: number): CFrame
	if axis == "X" then
		return CFrame.Angles(a, 0, 0)
	elseif axis == "Z" then
		return CFrame.Angles(0, 0, a)
	end
	return CFrame.Angles(0, a, 0)
end

local function contribute(acc: { [string]: MotionAcc }, key: string, rot: CFrame?, pos: Vector3?, scale: number?)
	local m = acc[key]
	if not m then
		m = { Rot = CFrame.identity, Pos = Vector3.zero, Scale = 1 }
		acc[key] = m
	end
	if rot then
		m.Rot = m.Rot * rot
	end
	if pos then
		m.Pos += pos
	end
	if scale then
		m.Scale *= scale
	end
end

-- ============================================================================
-- Screen helpers (edges, flash, sweep)
-- ============================================================================
local function makeEdges(s: Session, color: Color3, alpha: number, tex: string?, pulseHz: number?): { GuiObject }
	local made: { GuiObject } = {}
	local defs = {
		{ Pos = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.22), Rot = 90 },
		{ Pos = UDim2.fromScale(0, 0.78), Size = UDim2.fromScale(1, 0.22), Rot = 270 },
		{ Pos = UDim2.fromScale(0, 0), Size = UDim2.fromScale(0.18, 1), Rot = 0 },
		{ Pos = UDim2.fromScale(0.82, 0), Size = UDim2.fromScale(0.18, 1), Rot = 180 },
	}
	for _, d in defs do
		local g: GuiObject
		if tex then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Image = tex
			img.ScaleType = Enum.ScaleType.Tile
			img.TileSize = UDim2.fromOffset(64, 64)
			img.ImageColor3 = color
			img.ImageTransparency = 1
			g = img
		else
			local f = Instance.new("Frame")
			f.BackgroundColor3 = color
			f.BackgroundTransparency = 1
			f.BorderSizePixel = 0
			g = f
		end
		g.Position = d.Pos
		g.Size = d.Size
		g.ZIndex = 0
		g.Active = false
		local grad = Instance.new("UIGradient")
		grad.Rotation = d.Rot
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, alpha),
			NumberSequenceKeypoint.new(1, 1),
		})
		grad.Parent = g
		g.Parent = s.Screen
		local prop = if tex then "ImageTransparency" else "BackgroundTransparency"
		TweenService:Create(g, TweenInfo.new(0.5), { [prop] = 0 }):Play()
		if pulseHz then
			task.delay(0.5, function()
				if g.Parent then
					TweenService:Create(
						g,
						TweenInfo.new(0.5 / pulseHz, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ [prop] = 0.5 }
					):Play()
				end
			end)
		end
		table.insert(made, g)
	end
	return made
end

local function screenFlash(s: Session, color: Color3, alpha: number)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - alpha
	f.BorderSizePixel = 0
	f.ZIndex = 40
	f.Active = false
	f.Parent = s.Screen
	TweenService:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.4, function()
		f:Destroy()
	end)
end

local function screenSweep(s: Session, color: Color3)
	for i, y in { 0, 0.93 } do
		local bar = Instance.new("ImageLabel")
		bar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		bar.BackgroundTransparency = 0.2
		bar.BorderSizePixel = 0
		bar.Image = TEX.Stripes
		bar.ScaleType = Enum.ScaleType.Tile
		bar.TileSize = UDim2.fromOffset(48, 48)
		bar.ImageColor3 = color
		bar.Size = UDim2.fromScale(1, 0.07)
		bar.Position = UDim2.fromScale(if i == 1 then -1 else 1, y)
		bar.ZIndex = 1
		bar.Parent = s.Screen
		TweenService:Create(bar, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0, y),
		}):Play()
	end
end

-- ============================================================================
-- World helpers (rays billboard, ring pulse, beams)
-- ============================================================================
local function behindSlime(s: Session, pos: Vector3, dist: number): Vector3
	local away = pos - s.Ctx.Camera.CFrame.Position
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 0, 1)
	return pos + away * dist
end

local function billboardImage(s: Session, pos: Vector3, studs: number, tex: string, color: Color3, transparency: number): (BillboardGui, ImageLabel)
	local anchor = anchorPart(s, CFrame.new(pos))
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(studs, studs)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Adornee = anchor
	bb.Parent = anchor
	local img = Instance.new("ImageLabel")
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = tex
	img.ImageColor3 = color
	img.ImageTransparency = 1
	img.Parent = bb
	TweenService:Create(img, TweenInfo.new(0.3), { ImageTransparency = transparency }):Play()
	return bb, img
end

local function beamBetween(s: Session, a0: Attachment, a1: Attachment, color: ColorSequence, w0: number, w1: number, trans: number): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Color = color
	b.Width0 = w0
	b.Width1 = w1
	b.Texture = TEX.Glow
	b.TextureMode = Enum.TextureMode.Stretch
	b.LightEmission = 1
	b.LightInfluence = 0
	b.FaceCamera = true
	b.Segments = 20
	b.Transparency = NumberSequence.new(trans)
	b.Parent = s.Folder
	return b
end

local function attachmentOn(parent: Instance, offset: Vector3?): Attachment
	local a = Instance.new("Attachment")
	a.Position = offset or Vector3.zero
	a.Parent = parent
	return a
end

-- ============================================================================
-- Op runner
-- ============================================================================
local function runOp(s: Session, op: Op, phase: string, at: Vector3?)
	local kind = op.Op
	local model = s.Ctx.Model

	if kind == "Spin" then
		local angle = 0
		local rpm = op.Rpm or 30
		local key = op.Key
		local bob = op.Bob or 0
		local bobHz = op.BobHz or 1
		table.insert(s.MotionOps, function(acc, t, dt)
			angle += dt * rpm / 60 * math.pi * 2
			local pos = if bob ~= 0 then Vector3.new(0, bob * math.sin(t * math.pi * 2 * bobHz), 0) else nil
			contribute(acc, key, axisAngles(op.Axis, angle), pos, nil)
		end)
	elseif kind == "Wobble" then
		local amp = math.rad(op.Deg or 10)
		local hz = op.Hz or 1
		local ph = op.Phase or 0
		table.insert(s.MotionOps, function(acc, t, _dt)
			contribute(acc, op.Key, axisAngles(op.Axis, amp * math.sin(t * math.pi * 2 * hz + ph)), nil, nil)
		end)
	elseif kind == "Bob" then
		local amp = op.Amp or 0.05
		local hz = op.Hz or 1
		local ph = op.Phase or 0
		table.insert(s.MotionOps, function(acc, t, _dt)
			contribute(acc, op.Key, nil, Vector3.new(0, amp * math.sin(t * math.pi * 2 * hz + ph), 0), nil)
		end)
	elseif kind == "Pulse" then
		local lo, hi, hz = op.Min or 0.9, op.Max or 1.1, op.Hz or 1
		table.insert(s.MotionOps, function(acc, t, _dt)
			local k = lo + (hi - lo) * (0.5 + 0.5 * math.sin(t * math.pi * 2 * hz))
			contribute(acc, op.Key, nil, nil, k)
		end)
	elseif kind == "Grow" then
		s.Grows[op.Key] = { From = op.From or 1, To = op.To or 1, T0 = now(s), Time = op.Time or 0.3 }
	elseif kind == "Glow" then
		for _, p in targets(s, op, 24) do
			p.Material = Enum.Material.Neon
		end
	elseif kind == "GlowWave" then
		local parts = targets(s, op, 24)
		table.sort(parts, function(a, b)
			return a.Name < b.Name
		end)
		local hz = op.Hz or 2
		local last = -1
		table.insert(s.Updaters, function(t, _dt)
			if #parts == 0 then
				return
			end
			local idx = math.floor(t * hz) % #parts + 1
			if idx ~= last then
				last = idx
				for i, p in parts do
					if p.Parent then
						p.Material = if i == idx
							then Enum.Material.Neon
							else ((Enum.Material :: any)[(p:GetAttribute("OrigMaterial") :: string?) or "SmoothPlastic"] or Enum.Material.SmoothPlastic)
					end
				end
			end
		end)
	elseif kind == "Light" then
		local p = targets(s, op, 1)[1] or body(model)
		if not p then
			return
		end
		local light: Light
		if op.Spot then
			local sl = Instance.new("SpotLight")
			sl.Face = Enum.NormalId.Front
			sl.Angle = 55
			light = sl
		else
			light = Instance.new("PointLight")
		end
		light.Color = rgb(op.Color, Color3.new(1, 1, 1))
		local anyLight: any = light
		anyLight.Range = op.Range or 10
		local bright = op.Brightness or 2
		light.Brightness = 0
		light.Parent = p
		TweenService:Create(light, TweenInfo.new(0.25), { Brightness = bright }):Play()
		if op.Pulse then
			local hz = op.Pulse
			table.insert(s.Updaters, function(t, _dt)
				if light.Parent then
					light.Brightness = bright * (0.6 + 0.4 * math.sin(t * math.pi * 2 * hz))
				end
			end)
		end
	elseif kind == "Hide" then
		for _, p in targets(s, op, 32) do
			p.Transparency = 1
		end
	elseif kind == "Emit" then
		for _, p in targets(s, op, 6) do
			local sp = opSpec(op)
			sp.Rate = op.Rate or sp.Rate
			local a = attachmentOn(p)
			a.Name = "CatchFxEmit"
			emitterOn(a, sp)
		end
	elseif kind == "Burst" then
		local sp = opSpec(op)
		sp.Rate = 0
		local count = op.Count or 15
		local parents: { Instance } = {}
		if phase == "Land" and not op.Key and not op.Pattern and at then
			table.insert(parents, anchorPart(s, CFrame.new(at + Vector3.new(0, 0.2, 0))))
		else
			for _, p in targets(s, op, 4) do
				table.insert(parents, p)
			end
		end
		for _, parent in parents do
			local a = attachmentOn(parent)
			local e = emitterOn(a, sp)
			e:Emit(math.max(1, math.floor(count / #parents)))
			task.delay(4, function()
				a:Destroy()
			end)
		end
	elseif kind == "Orbit" then
		local sp = opSpec(op)
		sp.Rate = op.Rate or 20
		sp.Speed = { 0, 0.5 }
		local anchor = anchorPart(s, CFrame.new(slimeCentre(s)))
		emitterOn(anchor, sp)
		local radius = op.Radius or 2.5
		local hz = op.Hz or 1
		local rise = op.Rise == true
		local t0 = now(s)
		table.insert(s.Updaters, function(t, _dt)
			local lt = t - t0
			local c = slimeCentre(s)
			local a = lt * math.pi * 2 * hz
			local y = if rise then -0.8 + (lt * 1.2) % 3 else 0.3 * math.sin(lt * 3)
			anchor.CFrame = CFrame.new(c + Vector3.new(math.cos(a) * radius, y, math.sin(a) * radius))
		end)
	elseif kind == "Rain" then
		local sp = opSpec(op)
		sp.Rate = 0
		sp.Dir = Enum.NormalId.Bottom
		sp.Speed = { 2, 4 }
		sp.Spread = 10
		sp.Life = { 2, 3 }
		sp.Accel = Vector3.new(0, -3, 0)
		local box = anchorPart(s, CFrame.new(slimeCentre(s) + Vector3.new(0, 8, 0)), Vector3.new(14, 0.2, 6))
		local e = emitterOn(box, sp)
		pcall(function()
			(e :: any).Shape = Enum.ParticleEmitterShape.Box
		end)
		e:Emit(op.Count or 20)
	elseif kind == "Cannon" then
		local cam = s.Ctx.Camera
		local c = slimeCentre(s)
		local right = cam.CFrame.RightVector
		for _, side in { -1, 1 } do
			local from = c + right * (7 * side) + Vector3.new(0, -1.5, 0)
			local aim = c + Vector3.new(0, 3, 0)
			local p = anchorPart(s, CFrame.lookAt(from, aim) * CFrame.Angles(-math.pi / 2, 0, 0))
			local sp = opSpec(op)
			sp.Rate = 0
			sp.Spread = 20
			sp.Speed = { 10, 16 }
			local e = emitterOn(p, sp)
			e:Emit(op.Count or 40)
		end
	elseif kind == "Ambient" then
		local size = op.Size or { 30, 1, 16 }
		local box = anchorPart(
			s,
			CFrame.new(s.Ctx.StageCenter + Vector3.new(0, (op.Height or 6) - 1.22, 0)),
			Vector3.new(size[1], size[2], size[3])
		)
		local sp = opSpec(op)
		sp.Rate = op.Rate or 6
		local e = emitterOn(box, sp)
		pcall(function()
			(e :: any).Shape = Enum.ParticleEmitterShape.Box;
			(e :: any).ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		end)
	elseif kind == "Beam" then
		local beamKind = op.Kind
		local root = model.PrimaryPart
		if not root then
			return
		end
		if beamKind == "Holy" then
			-- a shaft of light from straight above onto the slime
			local top = anchorPart(s, CFrame.new(root.Position + Vector3.new(0, 16, 0)))
			local color = rgb(op.Color, Color3.fromRGB(255, 245, 210))
			local b = beamBetween(s, attachmentOn(top), attachmentOn(root), ColorSequence.new(color), 3, 5, 0.55)
			b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 0.4) })
			table.insert(s.Updaters, function(_t, _dt)
				top.CFrame = CFrame.new(root.Position + Vector3.new(0, 16, 0))
			end)
		elseif beamKind == "Aurora" then
			-- three wavy ribbons across the sky behind the slime
			local cam = s.Ctx.Camera
			local back = behindSlime(s, root.Position, 7)
			local right = cam.CFrame.RightVector
			local cols = {
				ColorSequence.new(Color3.fromRGB(110, 255, 170), Color3.fromRGB(160, 120, 255)),
				ColorSequence.new(Color3.fromRGB(160, 120, 255), Color3.fromRGB(110, 255, 210)),
				ColorSequence.new(Color3.fromRGB(110, 230, 255), Color3.fromRGB(200, 120, 255)),
			}
			for i = 1, 3 do
				local y = 5 + i * 1.3
				local pa = anchorPart(s, CFrame.new(back - right * 16 + Vector3.new(0, y, 0)))
				local pb = anchorPart(s, CFrame.new(back + right * 16 + Vector3.new(0, y + 1, 0)))
				local b = beamBetween(s, attachmentOn(pa), attachmentOn(pb), cols[i], 2.5, 2.5, 0.45)
				b.Texture = TEX.Smoke
				local ph = i * 1.7
				table.insert(s.Updaters, function(t, _dt)
					b.CurveSize0 = 5 * math.sin(t * 0.9 + ph)
					b.CurveSize1 = -5 * math.cos(t * 0.7 + ph)
				end)
			end
		elseif beamKind == "Rainbow" then
			-- refraction beams between the parts (e.g. the floating gems)
			local parts = targets(s, op, 6)
			if #parts >= 2 then
				for i = 1, #parts do
					local a = parts[i]
					local b = parts[i % #parts + 1]
					beamBetween(s, attachmentOn(a), attachmentOn(b), RAINBOW, 0.12, 0.12, 0.1)
				end
			end
		elseif beamKind == "Arcs" then
			-- flickering electric arcs from the part to random points around the slime
			local src = targets(s, op, 1)[1] or body(model)
			if not src then
				return
			end
			local color = ColorSequence.new(rgb(op.Color, Color3.fromRGB(150, 230, 255)))
			local beams: { { Beam: Beam, Tip: Part } } = {}
			for _ = 1, 3 do
				local tip = anchorPart(s, CFrame.new(root.Position))
				local bm = beamBetween(s, attachmentOn(src), attachmentOn(tip), color, 0.08, 0.04, 0)
				table.insert(beams, { Beam = bm, Tip = tip })
			end
			local nextT = 0
			table.insert(s.Updaters, function(t, _dt)
				if t < nextT then
					return
				end
				nextT = t + 0.08
				for _, b in beams do
					local dir = Vector3.new(math.random() * 2 - 1, math.random() * 1.5, math.random() * 2 - 1)
					b.Tip.CFrame = CFrame.new(root.Position + dir.Unit * (2 + math.random() * 1.5))
					b.Beam.CurveSize0 = (math.random() * 2 - 1) * 2
					b.Beam.CurveSize1 = (math.random() * 2 - 1) * 2
					b.Beam.Enabled = math.random() > 0.25
				end
			end)
		end
	elseif kind == "Rays" then
		local root = model.PrimaryPart
		if not root then
			return
		end
		local baseSize = (model:GetAttribute("BaseSize") :: number?) or 2.4
		local tex = if op.Tex == "glow" then TEX.Glow else TEX.Sunburst
		local bb, img = billboardImage(
			s,
			behindSlime(s, root.Position, baseSize * 1.7),
			baseSize * 4.5 * (op.Scale or 1),
			tex,
			rgb(op.Color, Color3.new(1, 1, 1)),
			if op.Tex == "glow" then 0.25 else 0.5
		)
		local spin = op.Spin or 0
		if spin ~= 0 then
			TweenService:Create(img, TweenInfo.new(math.abs(spin), Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), {
				Rotation = if spin > 0 then 360 else -360,
			}):Play()
		end
		local adornee = bb.Adornee :: BasePart
		table.insert(s.Updaters, function(_t, _dt)
			if root.Parent then
				adornee.CFrame = CFrame.new(behindSlime(s, root.Position, baseSize * 1.7))
			end
		end)
	elseif kind == "RingPulse" then
		local color = rgb(op.Color, Color3.new(1, 1, 1))
		for i = 1, op.Count or 1 do
			task.delay((i - 1) * 0.25, function()
				if not session or session ~= s then
					return
				end
				local bb, img = billboardImage(s, slimeCentre(s), 1, TEX.Ring, color, 0.1)
				img.ImageTransparency = 0.1
				TweenService:Create(bb, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.fromScale(16, 16),
				}):Play()
				TweenService:Create(img, TweenInfo.new(0.7), { ImageTransparency = 1 }):Play()
			end)
		end
	elseif kind == "Flash" then
		screenFlash(s, rgb(op.Color, Color3.new(1, 1, 1)), op.Alpha or 0.5)
	elseif kind == "Sweep" then
		screenSweep(s, rgb(op.Color, Color3.fromRGB(255, 220, 40)))
	elseif kind == "Edge" then
		for _, g in makeEdges(s, rgb(op.Color, Color3.new(1, 1, 1)), op.Alpha or 0.2, nil, nil) do
			table.insert(s.Edges, g)
		end
	elseif kind == "Tint" then
		local colors = op.Colors or {}
		local step = (op.Time or 0.6) / math.max(1, #colors)
		for i, c in colors do
			task.delay((i - 1) * step, function()
				if session == s and s.Grade.Parent then
					TweenService:Create(s.Grade, TweenInfo.new(step), { TintColor = rgb(c, Color3.new(1, 1, 1)) }):Play()
				end
			end)
		end
	elseif kind == "Shake" then
		s.Ctx.Shake(op.Time or 0.25)
	elseif kind == "Haze" then
		-- the camera director adds this to its FOV (CatchFx.GetFovOffset)
		table.insert(s.Updaters, function(t, _dt)
			s.FovOffset = 0.35 * math.sin(t * math.pi * 2 * 0.6)
		end)
	end
end

local function runOps(s: Session, ops: { Op }?, phase: string, at: Vector3?)
	if not ops then
		return
	end
	for _, op in ops do
		if op.Delay and op.Delay > 0 then
			task.delay(op.Delay, function()
				if session == s then
					runOp(s, op, phase, at)
				end
			end)
		else
			local ok, err = pcall(runOp, s, op, phase, at)
			if not ok then
				warn("[CatchFx] op", op.Op, "failed:", err)
			end
		end
	end
end

-- Zone, personality and signature layers that exist for this catch (in that order)
local function layers(s: Session): { CatchFxData.Layer }
	local list: { CatchFxData.Layer } = {}
	local zone = CatchFxData.Zones[s.Ctx.ZoneIndex]
	if zone then
		table.insert(list, zone :: any)
	end
	local personality = CatchFxData.Personality[SlimeFactory.GetFaceType(s.Ctx.Model)]
	if personality then
		table.insert(list, personality)
	end
	local sig = CatchFxData.Signatures[s.Ctx.SlimeId]
	if sig then
		table.insert(list, sig)
	end
	return list
end

-- ============================================================================
-- Public API
-- ============================================================================

-- Face type of the slime ("Happy" | "Sleepy" | "Angry"): ThrowController tunes blink speed / float bounce with it
function CatchFx.GetPersonality(model: Model): string
	return SlimeFactory.GetFaceType(model)
end

function CatchFx.Start(ctx: Ctx)
	CatchFx.Stop()
	local folder = Instance.new("Folder")
	folder.Name = "CatchFx"
	folder.Parent = workspace

	local screen = Instance.new("Frame")
	screen.Name = "CatchFxScreen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundTransparency = 1
	screen.ZIndex = 0
	screen.Active = false
	screen.Parent = ctx.RevealRoot

	local zone = CatchFxData.Zones[ctx.ZoneIndex] or CatchFxData.Zones[1]

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "CatchFxGrade"
	grade.Parent = ctx.Camera
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "CatchFxBloom"
	bloom.Intensity = 0
	bloom.Size = 24
	bloom.Threshold = 1.2
	bloom.Parent = ctx.Camera

	local s: Session = {
		Ctx = ctx,
		Folder = folder,
		Screen = screen,
		Grade = grade,
		Bloom = bloom,
		BaseFov = ctx.Camera.FieldOfView,
		Updaters = {},
		MotionKeys = {},
		MotionOps = {},
		Grows = {},
		T0 = os.clock(),
		WalkStarted = false,
		Edges = {},
		FovOffset = 0,
		Piece = nil,
		Env = nil,
		Intro = nil,
	}
	session = s

	local g = zone.Grade
	TweenService:Create(grade, TweenInfo.new(0.5), {
		TintColor = rgb(g.Tint, Color3.new(1, 1, 1)),
		Saturation = g.Saturation,
		Contrast = g.Contrast,
		Brightness = g.Brightness,
	}):Play()
	TweenService:Create(bloom, TweenInfo.new(0.5), { Intensity = g.Bloom }):Play()

	local edgeTex = if zone.Edge.Tex == "stripes" then TEX.Stripes else nil
	s.Edges = makeEdges(s, rgb(zone.Edge.Color, Color3.new(1, 1, 1)), zone.Edge.Alpha, edgeTex, zone.Edge.PulseHz)

	-- Zone ambient starts right away (the slime's own Walk ops wait for BeginWalk)
	runOps(s, zone.Walk, "Walk", nil)

	-- Zone set piece (volcano, blizzard, geysers...): background spectacle for the whole cutscene
	local piece = zone.SetPiece and CatchSetPieces.Pieces[zone.SetPiece]
	if piece then
		local flatView = Vector3.new(ctx.ViewDir.X, 0, ctx.ViewDir.Z)
		local away = if flatView.Magnitude > 0.01 then -flatView.Unit else Vector3.new(0, 0, -1)
		local walk = Vector3.new(ctx.BaitPos.X - ctx.EmergePos.X, 0, ctx.BaitPos.Z - ctx.EmergePos.Z)
		local right = if walk.Magnitude > 0.01 then walk.Unit else Vector3.new(1, 0, 0)
		local env: CatchSetPieces.Env = {
			Folder = folder,
			Camera = ctx.Camera,
			StageCenter = ctx.StageCenter,
			FloorY = ctx.FloorY,
			EmergePos = ctx.EmergePos,
			BaitPos = ctx.BaitPos,
			Away = away,
			Right = right,
			SlimeSize = (ctx.Model:GetAttribute("BaseSize") :: number?) or 2.4,
			Slime = ctx.Model,
			ZoneColor = rgb(zone.Edge.Color, Color3.new(1, 1, 1)),
			Strength = if ctx.Full then 1 else 0.5,
			Full = ctx.Full,
			AddUpdater = function(fn)
				table.insert(s.Updaters, fn)
			end,
			Emit = function(parent, preset, color, count, overrides)
				local sp = presetSpec(preset, color, nil)
				if overrides then
					for k, v in overrides do
						(sp :: any)[k] = v
					end
				end
				if count > 0 then
					sp.Rate = 0
				end
				local e = emitterOn(parent, sp)
				if count > 0 then
					e:Emit(count)
				end
				return e
			end,
			Shake = function(seconds)
				ctx.Shake(seconds)
			end,
			Flash = function(color, alpha)
				screenFlash(s, color, alpha)
			end,
			Now = function()
				return now(s)
			end,
		}
		s.Piece = piece
		s.Env = env
		local ok, err = pcall(piece.Background, env)
		if not ok then
			warn("[CatchFx] set piece background failed:", err)
		end
	end
end

-- Where the establishing shot should look (the set piece, e.g. the volcano); the stage if none
function CatchFx.GetFocus(): Vector3?
	local s = session
	if not s then
		return nil
	end
	if s.Piece and s.Env then
		local ok, pos = pcall(s.Piece.Focus, s.Env)
		if ok then
			return pos
		end
	end
	return s.Ctx.StageCenter
end

-- FOV offset the camera director adds (heat haze)
function CatchFx.GetFovOffset(): number
	local s = session
	return if s then s.FovOffset else 0
end

-- Full show: build the intro prop at the emerge spot (snow mound, lava pool, gift box...)
function CatchFx.IntroBuild()
	local s = session
	if not s or not s.Piece or not s.Env or s.Intro then
		return
	end
	local ok, handle = pcall(s.Piece.Intro, s.Env)
	if ok then
		s.Intro = handle
	else
		warn("[CatchFx] set piece intro failed:", handle)
	end
end

-- The intro prop rumbles (0..1); called every frame during the struggle emergence
function CatchFx.IntroShake(k: number)
	local s = session
	if s and s.Intro then
		pcall(s.Intro.Shake, k)
	end
end

-- The slime bursts out of the intro prop
function CatchFx.IntroBurst()
	local s = session
	if s and s.Intro then
		pcall(s.Intro.Burst)
	end
end

-- Personality + signature Walk ops. Call once the slime is visible (immediately for already-known slimes).
function CatchFx.BeginWalk()
	local s = session
	if not s or s.WalkStarted then
		return
	end
	s.WalkStarted = true
	local face = SlimeFactory.GetFaceType(s.Ctx.Model)
	local personality = CatchFxData.Personality[face]
	runOps(s, personality and personality.Walk, "Walk", nil)
	local sig = CatchFxData.Signatures[s.Ctx.SlimeId]
	runOps(s, sig and sig.Walk, "Walk", nil)
end

function CatchFx.Landed(groundPos: Vector3, stepIndex: number)
	local s = session
	if not s then
		return
	end
	if s.Piece and s.Env then
		local ok, err = pcall(s.Piece.Path, s.Env, groundPos, stepIndex)
		if not ok then
			warn("[CatchFx] set piece path failed:", err)
		end
	end
	for _, layer in layers(s) do
		if layer then
			runOps(s, layer.Land, "Land", groundPos)
		end
	end
end

function CatchFx.Showcase()
	local s = session
	if not s then
		return
	end
	CatchFx.BeginWalk() -- make sure walk details (spins, glows) are on for the showcase too
	TweenService:Create(s.Bloom, TweenInfo.new(0.2), { Intensity = s.Bloom.Intensity + 0.4 }):Play()
	if s.Ctx.Full and s.Piece and s.Env then
		local root = s.Ctx.Model.PrimaryPart
		local ok, err = pcall(s.Piece.Climax, s.Env, if root then root.Position else s.Ctx.StageCenter)
		if not ok then
			warn("[CatchFx] set piece climax failed:", err)
		end
	end
	for _, layer in layers(s) do
		if layer then
			runOps(s, layer.Show, "Show", nil)
		end
	end
end

function CatchFx.Update(dt: number)
	local s = session
	if not s then
		return
	end
	local t = now(s)
	for _, fn in s.Updaters do
		local ok, err = pcall(fn, t, dt)
		if not ok then
			warn("[CatchFx] updater failed:", err)
		end
	end

	-- Part motions: combine every op per key, then hand them to SlimeFactory
	local model = s.Ctx.Model
	local acc: { [string]: MotionAcc } = {}
	for _, fn in s.MotionOps do
		fn(acc, t, dt)
	end
	for key, g in s.Grows do
		local u = if g.Time <= 0 then 1 else math.clamp((t - g.T0) / g.Time, 0, 1)
		local e = 1 - (1 - u) * (1 - u)
		contribute(acc, key, nil, nil, g.From + (g.To - g.From) * e)
	end
	for key in s.MotionKeys do
		if not acc[key] then
			SlimeFactory.SetPartMotion(model, key, nil, nil)
			s.MotionKeys[key] = nil
		end
	end
	for key, m in acc do
		SlimeFactory.SetPartMotion(model, key, CFrame.new(m.Pos) * m.Rot, m.Scale)
		s.MotionKeys[key] = true
	end
end

function CatchFx.Stop()
	local s = session
	if not s then
		return
	end
	session = nil
	pcall(function()
		s.Ctx.Camera.FieldOfView = s.BaseFov
	end)
	for key in s.MotionKeys do
		SlimeFactory.SetPartMotion(s.Ctx.Model, key, nil, nil)
	end
	-- lights / emitters attached to the slime's own parts are removed with the slime model; the rest here
	s.Grade:Destroy()
	s.Bloom:Destroy()
	s.Screen:Destroy()
	s.Folder:Destroy()
end

return CatchFx
