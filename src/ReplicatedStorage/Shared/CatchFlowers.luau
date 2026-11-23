--!strict
--[[
	CatchFlowers.luau
	3D flowers for the Meadow catch set piece (CatchSetPieces.luau), in the map's classic studded style: every piece
	is a plain block (the set piece's newPart turns all parts into studded Plastic / Neon blocks): a square stem,
	plate leaves, plate petals like Lego flower plates, and a block centre.

	Kinds: Daisy, Cosmos, Sunflower, Tulip, Rose, Lupin (a spike of bells).

	A flower is built once (Build) and then posed every frame (Pose) by its owner:
	  grow  0..1   uniform scale from the stem base (grows out of the ground)
	  open  0..1   petals swing from a closed bud to the open bloom (Lupin bells swell)
	  bend  CFrame rotation at the stem base (wind sway, rustling, bending outward)
	Pose appends to (parts, cframes) lists so the owner can move every flower with one workspace:BulkMoveTo.
]]

local CatchFlowers = {}

export type Kind = "Daisy" | "Cosmos" | "Sunflower" | "Tulip" | "Rose" | "Lupin"

type PetalPose = { Head: CFrame, A: number, Open: number, Closed: number, Off: number, Len: number }
type Piece = {
	Part: BasePart,
	Size: Vector3, -- full-grown size
	Cf: CFrame?, -- fixed local CFrame (stem, leaves, centre, bells)
	Petal: PetalPose?,
	OpenScale: boolean?, -- size swells with `open` (Lupin bells)
}
export type Flower = {
	Kind: Kind,
	Pos: Vector3,
	Rot: CFrame,
	Pieces: { Piece },
	LastG: number,
	LastO: number,
}

export type Make = (props: { [string]: any }) -> Part?

local GREEN = Color3.fromRGB(86, 170, 74)
local LEAF = Color3.fromRGB(70, 155, 62)
local WHITE = Color3.new(1, 1, 1)
local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- cylinders run along X; this stands them up

-- Default stem height (studs at scale 1)
CatchFlowers.Heights = { Daisy = 1.1, Cosmos = 1.25, Sunflower = 1.9, Tulip = 1.0, Rose = 1.0, Lupin = 1.5 } :: { [Kind]: number }

local PALETTES: { [Kind]: { Color3 } } = {
	Daisy = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 228, 238), Color3.fromRGB(255, 250, 215) },
	Cosmos = { Color3.fromRGB(255, 130, 190), Color3.fromRGB(230, 80, 170), Color3.fromRGB(255, 240, 248), Color3.fromRGB(200, 160, 255) },
	Sunflower = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(255, 175, 30) },
	Tulip = {
		Color3.fromRGB(240, 60, 70),
		Color3.fromRGB(255, 120, 170),
		Color3.fromRGB(255, 215, 70),
		Color3.fromRGB(255, 150, 60),
		Color3.fromRGB(170, 90, 220),
	},
	Rose = { Color3.fromRGB(220, 40, 60), Color3.fromRGB(255, 140, 180), Color3.fromRGB(255, 120, 100), Color3.fromRGB(255, 245, 240) },
	Lupin = { Color3.fromRGB(150, 100, 255), Color3.fromRGB(100, 140, 255), Color3.fromRGB(255, 120, 200) },
}

local WEIGHTS: { { Kind: Kind, W: number, Tall: boolean } } = {
	{ Kind = "Daisy", W = 3, Tall = false },
	{ Kind = "Cosmos", W = 3, Tall = false },
	{ Kind = "Tulip", W = 3, Tall = false },
	{ Kind = "Rose", W = 2, Tall = false },
	{ Kind = "Lupin", W = 2, Tall = true },
	{ Kind = "Sunflower", W = 1, Tall = true },
}

-- Weighted random kind + one of its colours. allowTall = false leaves out Lupins and Sunflowers.
function CatchFlowers.Random(allowTall: boolean?): (Kind, Color3)
	local total = 0
	for _, w in WEIGHTS do
		if allowTall ~= false or not w.Tall then
			total += w.W
		end
	end
	local r = math.random() * total
	for _, w in WEIGHTS do
		if allowTall ~= false or not w.Tall then
			r -= w.W
			if r <= 0 then
				return w.Kind, CatchFlowers.Color(w.Kind)
			end
		end
	end
	return "Daisy", CatchFlowers.Color("Daisy")
end

function CatchFlowers.Color(kind: Kind): Color3
	local p = PALETTES[kind]
	return p[math.random(1, #p)]
end

-- A plain block (petal, leaf, bell, leafy blob). Classic studded style: no meshes, so the studs show.
function CatchFlowers.Blob(make: Make, props: { [string]: any }): Part?
	return make(props)
end
CatchFlowers.Ellipsoid = CatchFlowers.Blob

-- Slight natural colour variation
local function vary(c: Color3): Color3
	local k = math.random()
	return if k < 0.5 then c:Lerp(WHITE, k * 0.25) else c:Lerp(Color3.new(0, 0, 0), (k - 0.5) * 0.15)
end

function CatchFlowers.Build(
	make: Make,
	kind: Kind,
	opts: { Pos: Vector3, Facing: Vector3, Scale: number?, Height: number?, Color: Color3? }
): Flower
	local s = opts.Scale or 1
	local h = opts.Height or (CatchFlowers.Heights[kind] * s)
	local color = opts.Color or CatchFlowers.Color(kind)
	local facing = Vector3.new(opts.Facing.X, 0, opts.Facing.Z)
	facing = if facing.Magnitude > 0.01 then facing.Unit else Vector3.new(0, 0, -1)
	local f: Flower = {
		Kind = kind,
		Pos = opts.Pos,
		Rot = CFrame.lookAt(Vector3.zero, facing).Rotation, -- local -Z faces the camera
		Pieces = {},
		LastG = -1,
		LastO = -1,
	}

	local function add(part: Part?, size: Vector3, cf: CFrame?, petal: PetalPose?, openScale: boolean?)
		if part then
			table.insert(f.Pieces, { Part = part, Size = size, Cf = cf, Petal = petal, OpenScale = openScale })
		end
	end
	local function fixed(props: { [string]: any }, size: Vector3, cf: CFrame, ellipsoid: boolean?, openScale: boolean?)
		props.Size = Vector3.new(0.01, 0.01, 0.01)
		local part = if ellipsoid then CatchFlowers.Ellipsoid(make, props) else make(props)
		add(part, size, cf, nil, openScale)
	end
	local function petals(head: CFrame, n: number, w: number, t: number, len: number, off: number, open: number, closed: number, c: Color3, phase: number?)
		for i = 1, n do
			local part = CatchFlowers.Ellipsoid(make, { Color = vary(c), Size = Vector3.new(0.01, 0.01, 0.01) })
			add(part, Vector3.new(w, t, len) * s, nil, {
				Head = head,
				A = (i + (phase or 0)) / n * math.pi * 2,
				Open = open,
				Closed = closed,
				Off = off * s,
				Len = len * s,
			})
		end
	end

	-- stem + two leaves
	local stemLen = if kind == "Lupin" then h * 0.95 else h
	local stemD = (if kind == "Sunflower" then 0.11 elseif kind == "Lupin" then 0.08 else 0.07) * s
	fixed({ Shape = Enum.PartType.Cylinder, Color = GREEN }, Vector3.new(stemLen, stemD, stemD), CFrame.new(0, stemLen / 2, 0) * VERTICAL)
	local leafL = (if kind == "Sunflower" then 0.5 else 0.36) * s
	local leafW = (if kind == "Sunflower" then 0.24 else 0.15) * s
	for i, frac in { 0.3, 0.52 } do
		local a = (if i == 1 then 0.9 else 0.9 + math.pi) + (math.random() - 0.5) * 0.6
		fixed(
			{ Color = vary(LEAF) },
			Vector3.new(leafW, 0.07 * s, leafL),
			CFrame.new(0, h * frac, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(0.55, 0, 0) * CFrame.new(0, 0, -leafL / 2),
			true
		)
	end

	if kind == "Lupin" then
		-- a spike of bells up the top half of the stem, shading toward white at the tip
		for i = 1, 10 do
			local u = (i - 1) / 9
			local y = h * (0.5 + 0.5 * u)
			local r = 0.11 * s * (1 - u * 0.75)
			local a = i * 2.4
			local d = 0.14 * s * (1 - u * 0.4)
			fixed(
				{ Color = vary(color:Lerp(WHITE, u * 0.55)) },
				Vector3.new(d, d * 0.85, d),
				CFrame.new(math.cos(a) * r, y, math.sin(a) * r),
				true,
				true
			)
		end
		f.LastG = -1
		CatchFlowers.Pose(f, 0, 0, CFrame.identity, nil, nil)
		return f
	end

	local face = if kind == "Tulip" then 0.15 elseif kind == "Sunflower" then 0.5 else 0.42
	local head = CFrame.new(0, h, 0) * CFrame.Angles(-face, 0, 0) -- tilted toward the camera

	if kind == "Daisy" then
		petals(head, 9, 0.18, 0.06, 0.38, 0.1, 0.12, 1.35, color)
		fixed({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(255, 205, 50) }, Vector3.new(0.08, 0.26, 0.26) * s, head * CFrame.new(0, 0.02 * s, 0) * VERTICAL)
	elseif kind == "Cosmos" then
		petals(head, 8, 0.24, 0.06, 0.36, 0.06, 0.18, 1.3, color)
		fixed({ Shape = Enum.PartType.Ball, Color = Color3.fromRGB(255, 215, 70) }, Vector3.new(0.14, 0.14, 0.14) * s, head * CFrame.new(0, 0.03 * s, 0))
	elseif kind == "Sunflower" then
		petals(head, 12, 0.21, 0.06, 0.42, 0.26, 0.1, 1.2, color)
		fixed(
			{ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(110, 70, 35), Material = Enum.Material.Fabric },
			Vector3.new(0.14, 0.58, 0.58) * s,
			head * CFrame.new(0, 0.03 * s, 0) * VERTICAL
		)
	elseif kind == "Tulip" then
		petals(head, 3, 0.3, 0.07, 0.5, 0.03, 1.1, 1.45, color)
		petals(head, 3, 0.3, 0.07, 0.5, 0.0, 1.0, 1.42, color:Lerp(WHITE, 0.08), 0.5)
	elseif kind == "Rose" then
		fixed({ Shape = Enum.PartType.Ball, Color = color:Lerp(Color3.new(0, 0, 0), 0.15) }, Vector3.new(0.17, 0.17, 0.17) * s, head * CFrame.new(0, 0.05 * s, 0))
		petals(head, 5, 0.2, 0.06, 0.2, 0.03, 1.05, 1.4, color)
		petals(head, 6, 0.26, 0.06, 0.28, 0.07, 0.4, 1.25, color:Lerp(WHITE, 0.1), 0.5)
	end

	CatchFlowers.Pose(f, 0, 0, CFrame.identity, nil, nil)
	return f
end

-- Pose the flower. With parts/cframes lists the CFrames are appended (for one BulkMoveTo); without, set directly.
function CatchFlowers.Pose(f: Flower, grow: number, open: number, bend: CFrame, parts: { BasePart }?, cframes: { CFrame }?)
	local root = CFrame.new(f.Pos) * bend * f.Rot
	local sizeDirty = grow ~= f.LastG
	local openDirty = open ~= f.LastO
	local g = math.max(grow, 0.01)
	for _, pc in f.Pieces do
		local lc: CFrame
		local petal = pc.Petal
		if petal then
			local tilt = petal.Closed + (petal.Open - petal.Closed) * open
			lc = petal.Head * CFrame.Angles(0, petal.A, 0) * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, 0, -(petal.Off + petal.Len * 0.5))
		else
			lc = pc.Cf or CFrame.identity
		end
		lc = lc - lc.Position + lc.Position * grow
		local cf = root * lc
		if parts and cframes then
			table.insert(parts, pc.Part)
			table.insert(cframes, cf)
		else
			pc.Part.CFrame = cf
		end
		if sizeDirty or (pc.OpenScale and openDirty) then
			local k = g * (if pc.OpenScale then 0.35 + 0.65 * open else 1)
			local sz = pc.Size * k
			pc.Part.Size = Vector3.new(math.max(sz.X, 0.01), math.max(sz.Y, 0.01), math.max(sz.Z, 0.01))
		end
	end
	f.LastG = grow
	f.LastO = open
end

function CatchFlowers.Destroy(f: Flower)
	for _, pc in f.Pieces do
		pc.Part:Destroy()
	end
	table.clear(f.Pieces)
end

function CatchFlowers.PartCount(f: Flower): number
	return #f.Pieces
end

return CatchFlowers
