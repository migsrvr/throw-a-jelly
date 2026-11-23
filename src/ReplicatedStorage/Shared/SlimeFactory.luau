--!strict
--[[
	SlimeFactory.luau
	Procedural 3D Jelly Slime Model generator (with Mutation visuals & Silhouette mode)
	plus 3D Jelly Bait / Carrot Treat model for holding and throwing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

local SlimeFactory = {}

-- ============================================================================
-- AUTHORED SLIME MODELS
-- Templates live in ReplicatedStorage.SlimeModels.<Zone>.<Name>.Slime (imported meshes).
-- CreateSlimeModel clones the template for a SlimeId and rigs it so every existing caller
-- (PositionSlime squash, silhouette reveal, viewports, plots) keeps working. A SlimeId with no
-- entry here (or a missing template) falls back to the old procedural jelly ball.
-- To add a slime: put its model under SlimeModels and add its SlimeId -> { ZoneFolder, ModelName } here.
-- The authored front of every model is -Z (CFrame.lookAt faces the target).
-- ============================================================================
local MODEL_PATHS: { [string]: { string } } = {
	-- Zone 1: Meadow
	meadow_sprout = { "Meadow", "Sprout" },
	meadow_clover = { "Meadow", "Clover" },
	meadow_dandelion = { "Meadow", "Dandelion" },
	meadow_honey = { "Meadow", "Honey" },
	meadow_mushroom = { "Meadow", "Mushroom" },
	meadow_bloom = { "Meadow", "Sakura Bloom" },
	-- Zone 2: Crystal Cave
	crystal_pebble = { "CrystalCave", "Pebble" },
	crystal_quartz = { "CrystalCave", "Quartz" },
	crystal_glowcap = { "CrystalCave", "Glowcap" },
	crystal_amethyst = { "CrystalCave", "Amethyst" },
	crystal_bat = { "CrystalCave", "Bat" },
	crystal_prism = { "CrystalCave", "Prism Geode" },
	-- Zone 3: Lava Fields
	lava_ember = { "LavaFields", "Ember" },
	lava_salamander = { "LavaFields", "Salamander" },
	lava_volcano = { "LavaFields", "Volcano" },
	lava_obsidian = { "LavaFields", "Obsidian Core" },
	lava_phoenix = { "LavaFields", "Phoenix" },
	lava_solar = { "LavaFields", "Solar Flare" },
	-- Zone 4: Frost Peaks
	frost_snowball = { "FrostPeaks", "Snowball" },
	frost_glacier = { "FrostPeaks", "Glacier" },
	frost_penguin = { "FrostPeaks", "Penguin" },
	frost_aurora = { "FrostPeaks", "Aurora Borealis" },
	frost_yeti = { "FrostPeaks", "Yeti" },
	frost_cryo = { "FrostPeaks", "Cryo Monarch" },
	-- Zone 5: Candy Land
	candy_gumdrop = { "CandyLand", "Gumdrop" },
	candy_cupcake = { "CandyLand", "Cupcake" },
	candy_bubblegum = { "CandyLand", "Bubblegum" },
	candy_cotton = { "CandyLand", "Cotton Cloud" },
	candy_lollipop = { "CandyLand", "Lollipop" },
	candy_royal = { "CandyLand", "Royal Sugar King" },
	-- Zone 6: Desert Dunes
	desert_sand = { "Desert", "Sand" },
	desert_cactus = { "Desert", "Cactus" },
	desert_mummy = { "Desert", "Mummy" },
	desert_scarab = { "Desert", "Scarab" },
	desert_djinn = { "Desert", "Djinn" },
	desert_pharaoh = { "Desert", "Pharaoh" },
	-- Zone 7: Acid Swamp
	acid_sludge = { "Acid", "Sludge" },
	acid_bubbling = { "Acid", "Bubbling" },
	acid_hazmat = { "Acid", "Hazmat" },
	acid_mutant = { "Acid", "Mutant" },
	acid_scientist = { "Acid", "Mad Scientist" },
	acid_nuclear = { "Acid", "Nuclear Core" },
}

-- Which role a part plays in an authored model (drives the optional pose layer)
export type PartGroup = "Body" | "Outline" | "Core" | "Base" | "Face" | "Highlight" | "Accessory"

type PartInfo = {
	Part: BasePart,
	Group: PartGroup,
	Keys: { string }, -- the part's name plus every ancestor name up to the model (e.g. Halo_Green, Acc_AuroraHalo)
	Pos: Vector3, -- offset from the body centre at template scale (already lifted to the ball's ground line)
	Pivot: Vector3, -- accessories: where the part's Acc_ group attaches to the body (same space as Pos); others: Pos
	Side: number, -- wings: -1 left of the body, 1 right (mirrors flaps); everything else 1 (moves as one piece)
	Rot: CFrame, -- orientation relative to the body
	Size: Vector3,
	MScale: number, -- last SetPartMotion scale applied to this part's size
	SqX: Vector3, -- squared components of the part's local axes in model space (for squash scaling)
	SqY: Vector3,
	SqZ: Vector3,
}

-- Extra transform for one part / node / Acc_ group (SetPartMotion): rotation + offset + uniform scale
-- around the centre of everything under that name.
type PartMotion = { Cf: CFrame, Scale: number }

type SlimeState = {
	Root: BasePart,
	Parts: { PartInfo },
	BodyRef: number, -- template body width; BaseSize / BodyRef = uniform scale
	FaceCenter: Vector3, -- centre of the Face_ parts (same space as PartInfo.Pos)
	FaceType: string, -- "Happy" | "Sleepy" | "Angry" (from the Face_<Type> group), "Happy" if unknown
	HasAccessories: boolean,
	KeyCentres: { [string]: Vector3 }, -- centre of the parts under each key (same space as PartInfo.Pos)
	Motion: { [string]: PartMotion },
	HasMotion: boolean,
	LastR: number,
	LastKx: number,
	LastKy: number,
	LastFaceY: number,
	Stripped: { { SA: SurfaceAppearance, Part: BasePart } }, -- SurfaceAppearances removed while silhouetted
}

-- Optional extra layer for PositionSlime (cutscene animation). Every field is optional; nil = neutral.
--   AccessoryLift: extra lift of accessories, as a fraction of BaseSize (spring bounce)
--   AccessoryTilt: radians (pitch, yaw, roll) around each accessory's attach point; roll is mirrored
--                  left/right so wings flap together
--   FaceScaleY:    vertical scale of the face around its centre (blink ~0.1, surprised ~1.25)
--   FaceOffset:    face offset in studs at template scale (glancing eyes)
export type Pose = {
	AccessoryLift: number?,
	AccessoryTilt: Vector3?,
	FaceScaleY: number?,
	FaceOffset: Vector3?,
}

-- Authored layout: Base/<Body|Core|Outline|Highlight...>, Face_<Type>/..., Acc_<Name>/...
local function classifyPart(part: BasePart, model: Model): PartGroup
	local name = part.Name
	if string.find(name, "Highlight") then
		return "Highlight"
	end
	local inBase = false
	local node: Instance? = part.Parent
	while node and node ~= model do
		if string.sub(node.Name, 1, 5) == "Face_" then
			return "Face"
		end
		if string.sub(node.Name, 1, 4) == "Acc_" then
			return "Accessory"
		end
		if node.Name == "Base" then
			inBase = true
		end
		node = node.Parent
	end
	if name == "Body" or name == "Outline" or name == "Core" then
		return name :: PartGroup
	end
	return if inBase then "Base" else "Accessory"
end

-- The part's own name followed by each ancestor's name up to (not including) the model
local function partKeys(part: BasePart, model: Model): { string }
	local keys = { part.Name }
	local node: Instance? = part.Parent
	while node and node ~= model do
		table.insert(keys, node.Name)
		node = node.Parent
	end
	return keys
end

local function isWingPart(keys: { string }): boolean
	for _, k in keys do
		if string.find(k, "Wing") then
			return true
		end
	end
	return false
end

local slimeState: { [Model]: SlimeState } = setmetatable({}, { __mode = "k" }) :: any

local templatesRoot: Instance? = nil
local templatesWaited = false

local function getTemplate(slimeId: string): Model?
	local path = MODEL_PATHS[slimeId]
	if not path then
		return nil
	end
	if not templatesRoot then
		templatesRoot = ReplicatedStorage:FindFirstChild("SlimeModels")
		if not templatesRoot and not templatesWaited then
			templatesWaited = true
			templatesRoot = ReplicatedStorage:WaitForChild("SlimeModels", 5)
		end
	end
	local zone = templatesRoot and templatesRoot:FindFirstChild(path[1])
	local holder = zone and zone:FindFirstChild(path[2])
	local slime = holder and holder:FindFirstChild("Slime")
	if slime and slime:IsA("Model") then
		return slime
	end
	return nil
end

local function buildCustomSlime(
	template: Model,
	def: GameConfig.SlimeDef,
	showBillboard: boolean?,
	mutId: string,
	mutDef: GameConfig.MutationDef,
	customIncome: number?
): Model?
	local model = template:Clone()
	local body = model:FindFirstChild("Body", true)
	if not body or not body:IsA("BasePart") then
		model:Destroy()
		return nil
	end

	local baseRadius = 2.4 * (def.Scale or 1.0)
	local bodyRef = body.Size.X
	local origin = body.CFrame
	local originInv = origin:Inverse()

	-- Rest the jelly on the same ground line the old ball used (bottom = -0.44 * BaseSize)
	local bottomRel = -body.Size.Y * 0.5
	local baseModel = model:FindFirstChild("Base")
	if baseModel and baseModel:IsA("Model") then
		local bcf, bsize = baseModel:GetBoundingBox()
		bottomRel = (bcf.Position.Y - bsize.Y * 0.5) - origin.Position.Y
	end
	local lift = -0.44 * bodyRef - bottomRel

	model.Name = `Slime_{def.Id}`

	local mutCol = SlimeFactory.ToColor3(mutDef.Color)
	local parts: { PartInfo } = {}
	local bodyCentre = Vector3.new(0, lift, 0)
	local half = body.Size * 0.5
	local faceSum = Vector3.zero
	local faceCount = 0
	local hasAccessories = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true

			-- The authored meshes carry baked colour textures (TextureID / SurfaceAppearance) which ignore
			-- BasePart.Color. A mutation therefore swaps the body and core to a flat tinted colour and tints the
			-- outline's SurfaceAppearance (plus the glow highlight below).
			if mutId ~= "NORMAL" and d:IsA("MeshPart") then
				if d.Name == "Body" then
					d.TextureID = ""
					d.Color = d.Color:Lerp(mutCol, 0.85)
					-- more solid than the normal jelly so the tint reads clearly (also in viewports)
					d.Transparency = math.min(d.Transparency, 0.1)
					if mutId == "GOLDEN" then
						d.Reflectance = 0.12
					end
				elseif d.Name == "Outline" then
					for _, child in d:GetChildren() do
						if child:IsA("SurfaceAppearance") then
							child.Color = Color3.new(1, 1, 1):Lerp(mutCol, 0.95)
						end
					end
					d.Color = d.Color:Lerp(mutCol, 0.6)
				elseif d.Name == "Core" then
					d.TextureID = ""
					d.Color = mutCol
					d.Material = Enum.Material.Neon
				end
			end

			-- Remembered so SetSilhouetteMode(false) restores the (mutated) look
			d:SetAttribute("OrigColor", d.Color)
			d:SetAttribute("OrigTransparency", d.Transparency)
			d:SetAttribute("OrigReflectance", d.Reflectance)
			d:SetAttribute("OrigMaterial", d.Material.Name)
			if d:IsA("MeshPart") then
				d:SetAttribute("OrigTexture", d.TextureID)
			end

			local rel = originInv * d.CFrame
			local rot = rel.Rotation
			local rx, ry, rz = rot.RightVector, rot.UpVector, rot.LookVector
			local pos = rel.Position + Vector3.new(0, lift, 0)
			local group = classifyPart(d, model)
			if group == "Accessory" then
				hasAccessories = true
			elseif group == "Face" then
				faceSum += pos
				faceCount += 1
			end
			table.insert(parts, {
				Part = d,
				Group = group,
				Keys = partKeys(d, model),
				Pos = pos,
				Pivot = pos, -- accessories get their group attach point below
				Side = 1,
				Rot = rot,
				Size = d.Size,
				MScale = 1,
				SqX = Vector3.new(rx.X * rx.X, rx.Y * rx.Y, rx.Z * rx.Z),
				SqY = Vector3.new(ry.X * ry.X, ry.Y * ry.Y, ry.Z * ry.Z),
				SqZ = Vector3.new(rz.X * rz.X, rz.Y * rz.Y, rz.Z * rz.Z),
			})
		end
	end

	-- Centre of the parts under every key (part, node or Acc_ group name)
	local keySum: { [string]: Vector3 } = {}
	local keyCount: { [string]: number } = {}
	for _, info in parts do
		for _, k in info.Keys do
			keySum[k] = (keySum[k] or Vector3.zero) + info.Pos
			keyCount[k] = (keyCount[k] or 0) + 1
		end
	end
	local keyCentres: { [string]: Vector3 } = {}
	for k, sum in keySum do
		keyCentres[k] = sum / keyCount[k]
	end

	-- Attach point = where the line from the body centre to a point crosses the body's ellipsoid
	local function attachPoint(p: Vector3): Vector3
		local off = p - bodyCentre
		local k = math.sqrt(
			(off.X / math.max(half.X, 0.01)) ^ 2 + (off.Y / math.max(half.Y, 0.01)) ^ 2 + (off.Z / math.max(half.Z, 0.01)) ^ 2
		)
		return if k > 1 then bodyCentre + off / k else p
	end
	-- A hat / crown / halo moves as one piece around its group's attach point; wings flap on their own
	for _, info in parts do
		if info.Group == "Accessory" then
			if isWingPart(info.Keys) then
				info.Pivot = attachPoint(info.Pos)
				info.Side = if info.Pos.X < 0 then -1 else 1
			else
				local accKey: string? = nil
				for _, k in info.Keys do
					if string.sub(k, 1, 4) == "Acc_" then
						accKey = k
					end
				end
				info.Pivot = attachPoint(if accKey then keyCentres[accKey] else info.Pos)
			end
		end
	end

	local faceType = "Happy"
	for _, child in model:GetChildren() do
		if string.sub(child.Name, 1, 5) == "Face_" then
			faceType = string.sub(child.Name, 6)
		end
	end

	-- Invisible anchored root at the body centre: PrimaryPart for callers that read its position
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.5, 0.5, 0.5)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = origin
	root.Parent = model
	model.PrimaryPart = root

	model:SetAttribute("SlimeId", def.Id)
	model:SetAttribute("Mutation", mutId)
	model:SetAttribute("BaseSize", baseRadius)
	model:SetAttribute("CustomModel", true)

	local coreColor = if mutId ~= "NORMAL" then mutCol else SlimeFactory.ToColor3(def.CoreColor)
	if mutId ~= "NORMAL" then
		local highlight = Instance.new("Highlight")
		highlight.Name = "MutationGlow"
		highlight.FillColor = coreColor
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.FillTransparency = 0.65
		highlight.OutlineTransparency = 0.15
		highlight.Parent = model
	end

	if showBillboard ~= false then
		local bb = Instance.new("BillboardGui")
		bb.Name = "SlimeLabel"
		bb.Size = UDim2.fromOffset(165, 58)
		bb.StudsOffset = Vector3.new(0, baseRadius * 0.78 + 1.0, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 95
		bb.Adornee = root
		bb.Parent = root

		local mutPrefix = if mutId ~= "NORMAL" then `[{mutId}] ` else ""
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0.52, 0)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextColor3 = if mutId ~= "NORMAL" then coreColor else SlimeFactory.GetRarityColor(def.Rarity)
		title.Text = `{mutPrefix}{def.Name}`
		title.Parent = bb

		local stroke1 = Instance.new("UIStroke")
		stroke1.Thickness = 1.8
		stroke1.Color = Color3.fromRGB(15, 18, 25)
		stroke1.Parent = title

		local incomeVal = customIncome or math.max(1, math.floor(def.IncomePerSec * mutDef.IncomeMultiplier + 0.5))
		local sub = Instance.new("TextLabel")
		sub.Name = "Income"
		sub.Position = UDim2.fromScale(0, 0.50)
		sub.Size = UDim2.new(1, 0, 0.50, 0)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.FredokaOne
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(115, 255, 130)
		sub.Text = `${GameConfig.FormatNumber(incomeVal)}/s`
		sub.Parent = bb

		local stroke2 = stroke1:Clone()
		stroke2.Parent = sub
	end

	slimeState[model] = {
		Root = root,
		Parts = parts,
		BodyRef = bodyRef,
		FaceCenter = if faceCount > 0 then faceSum / faceCount else bodyCentre,
		FaceType = faceType,
		HasAccessories = hasAccessories,
		KeyCentres = keyCentres,
		Motion = {},
		HasMotion = false,
		LastR = -1,
		LastKx = -1,
		LastKy = -1,
		LastFaceY = 1,
		Stripped = {},
	}
	model.Destroying:Connect(function()
		slimeState[model] = nil
	end)

	SlimeFactory.PositionSlime(model, CFrame.new(0, 5, 0), 0)
	return model
end

local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(200, 235, 200),
	Uncommon = Color3.fromRGB(120, 240, 145),
	Rare = Color3.fromRGB(100, 195, 255),
	Epic = Color3.fromRGB(205, 130, 255),
	Legendary = Color3.fromRGB(255, 205, 70),
	Mythic = Color3.fromRGB(255, 110, 195),
}

function SlimeFactory.ToColor3(rgb: GameConfig.RGB): Color3
	return Color3.fromRGB(rgb[1] or 255, rgb[2] or 255, rgb[3] or 255)
end

function SlimeFactory.GetRarityColor(rarity: string): Color3
	return RARITY_COLORS[rarity] or Color3.fromRGB(255, 255, 255)
end

function SlimeFactory.GetMutationColor(mutationId: string?): Color3
	local mut = if mutationId then GameConfig.MutationsById[mutationId] else nil
	if mut then
		return SlimeFactory.ToColor3(mut.Color)
	end
	return Color3.fromRGB(255, 255, 255)
end

local function createProceduralSlime(slimeId: string, showBillboard: boolean?, mutationId: string?, customIncome: number?): Model
	local def = GameConfig.SlimesById[slimeId] or GameConfig.Slimes[1]
	local mutId = mutationId or "NORMAL"
	local mutDef = GameConfig.MutationsById[mutId] or GameConfig.Mutations[1]
	local scale = def.Scale or 1.0
	local baseRadius = 2.4 * scale

	local model = Instance.new("Model")
	model.Name = `Slime_{def.Id}`
	model:SetAttribute("SlimeId", def.Id)
	model:SetAttribute("Mutation", mutId)
	model:SetAttribute("BaseSize", baseRadius)

	local outerColor = SlimeFactory.ToColor3(def.Color)
	local coreColor = SlimeFactory.ToColor3(def.CoreColor)

	if mutId ~= "NORMAL" then
		local mutCol = SlimeFactory.ToColor3(mutDef.Color)
		outerColor = outerColor:Lerp(mutCol, 0.45)
		coreColor = mutCol
	end

	local outer = Instance.new("Part")
	outer.Name = "OuterJelly"
	outer.Shape = Enum.PartType.Ball
	outer.Size = Vector3.new(baseRadius, baseRadius * 0.88, baseRadius)
	outer.Color = outerColor
	outer.Material = if mutId == "CRYSTAL" then Enum.Material.Glass else Enum.Material.SmoothPlastic
	outer.Transparency = if mutId == "GOLDEN" then 0.08 else 0.22
	outer.Reflectance = if mutId == "GOLDEN" then 0.45 else 0.15
	outer.Anchored = true
	outer.CanCollide = false
	outer.CastShadow = true
	outer.TopSurface = Enum.SurfaceType.Smooth
	outer.BottomSurface = Enum.SurfaceType.Smooth
	outer:SetAttribute("OrigColor", outerColor)
	outer.Parent = model

	if mutId ~= "NORMAL" then
		local highlight = Instance.new("Highlight")
		highlight.Name = "MutationGlow"
		highlight.FillColor = coreColor
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.FillTransparency = 0.65
		highlight.OutlineTransparency = 0.15
		highlight.Parent = model
	end

	local core = Instance.new("Part")
	core.Name = "InnerCore"
	core.Shape = Enum.PartType.Ball
	core.Size = outer.Size * 0.54
	core.Color = coreColor
	core.Material = Enum.Material.Neon
	core.Transparency = 0.08
	core.Anchored = true
	core.CanCollide = false
	core.CastShadow = false
	core:SetAttribute("OrigColor", coreColor)
	core.Parent = model

	local eyeSize = Vector3.new(0.26 * scale, 0.34 * scale, 0.18 * scale)
	local leftEye = Instance.new("Part")
	leftEye.Name = "LeftEye"
	leftEye.Shape = Enum.PartType.Ball
	leftEye.Size = eyeSize
	leftEye.Color = Color3.fromRGB(25, 25, 35)
	leftEye.Material = Enum.Material.SmoothPlastic
	leftEye.Anchored = true
	leftEye.CanCollide = false
	leftEye.Parent = model

	local rightEye = leftEye:Clone()
	rightEye.Name = "RightEye"
	rightEye.Parent = model

	if showBillboard ~= false then
		local bb = Instance.new("BillboardGui")
		bb.Name = "SlimeLabel"
		bb.Size = UDim2.fromOffset(165, 58)
		bb.StudsOffset = Vector3.new(0, baseRadius * 0.78 + 1.0, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 95
		bb.Adornee = outer
		bb.Parent = outer

		local mutPrefix = if mutId ~= "NORMAL" then `[{mutId}] ` else ""
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0.52, 0)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextColor3 = if mutId ~= "NORMAL" then coreColor else SlimeFactory.GetRarityColor(def.Rarity)
		title.Text = `{mutPrefix}{def.Name}`
		title.Parent = bb

		local stroke1 = Instance.new("UIStroke")
		stroke1.Thickness = 1.8
		stroke1.Color = Color3.fromRGB(15, 18, 25)
		stroke1.Parent = title

		local incomeVal = customIncome or math.max(1, math.floor(def.IncomePerSec * mutDef.IncomeMultiplier + 0.5))
		local sub = Instance.new("TextLabel")
		sub.Name = "Income"
		sub.Position = UDim2.fromScale(0, 0.50)
		sub.Size = UDim2.new(1, 0, 0.50, 0)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.FredokaOne
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(115, 255, 130)
		sub.Text = `${GameConfig.FormatNumber(incomeVal)}/s`
		sub.Parent = bb

		local stroke2 = stroke1:Clone()
		stroke2.Parent = sub
	end

	model.PrimaryPart = outer
	SlimeFactory.PositionSlime(model, CFrame.new(0, 5, 0), 0)
	return model
end

function SlimeFactory.CreateSlimeModel(slimeId: string, showBillboard: boolean?, mutationId: string?, customIncome: number?): Model
	local def = GameConfig.SlimesById[slimeId] or GameConfig.Slimes[1]
	local mutId = mutationId or "NORMAL"
	local mutDef = GameConfig.MutationsById[mutId] or GameConfig.Mutations[1]

	local template = getTemplate(def.Id)
	if template then
		local custom = buildCustomSlime(template, def, showBillboard, mutId, mutDef, customIncome)
		if custom then
			return custom
		end
	end
	return createProceduralSlime(slimeId, showBillboard, mutationId, customIncome)
end

function SlimeFactory.SetSilhouetteMode(model: Model, isSilhouette: boolean)
	local state = slimeState[model]
	if state then
		-- Authored model: solid dark shape, face + shine details hidden
		local hidden: { [Instance]: boolean } = {}
		for _, child in model:GetChildren() do
			if string.sub(child.Name, 1, 5) == "Face_" then
				for _, d in child:GetDescendants() do
					hidden[d] = true
				end
			end
		end
		for _, info in state.Parts do
			local part = info.Part
			if isSilhouette then
				-- Baked textures ignore Color, so strip them for a true black silhouette
				if part:IsA("MeshPart") then
					part.TextureID = ""
				end
				for _, child in part:GetChildren() do
					if child:IsA("SurfaceAppearance") then
						table.insert(state.Stripped, { SA = child, Part = part })
						child.Parent = nil
					end
				end
				part.Color = Color3.fromRGB(18, 25, 20)
				part.Material = Enum.Material.SmoothPlastic
				part.Reflectance = 0
				part.Transparency = if hidden[part] or string.find(part.Name, "Highlight") then 1 else 0
			else
				if part:IsA("MeshPart") then
					part.TextureID = (part:GetAttribute("OrigTexture") :: string?) or ""
				end
				local c = part:GetAttribute("OrigColor") :: Color3?
				if c then
					part.Color = c
				end
				local matName = part:GetAttribute("OrigMaterial") :: string?
				if matName then
					part.Material = (Enum.Material :: any)[matName]
				end
				part.Reflectance = (part:GetAttribute("OrigReflectance") :: number?) or 0
				part.Transparency = (part:GetAttribute("OrigTransparency") :: number?) or 0
			end
		end
		if not isSilhouette then
			for _, entry in state.Stripped do
				entry.SA.Parent = entry.Part
			end
			table.clear(state.Stripped)
		end
		local glow = model:FindFirstChild("MutationGlow")
		if glow and glow:IsA("Highlight") then
			glow.Enabled = not isSilhouette
		end
		return
	end

	local outer = model:FindFirstChild("OuterJelly") :: BasePart?
	local core = model:FindFirstChild("InnerCore") :: BasePart?
	local leftEye = model:FindFirstChild("LeftEye") :: BasePart?
	local rightEye = model:FindFirstChild("RightEye") :: BasePart?

	if isSilhouette then
		if outer then
			outer.Color = Color3.fromRGB(18, 25, 20)
			outer.Transparency = 0.05
		end
		if core then
			core.Color = Color3.fromRGB(110, 255, 150)
		end
		if leftEye then
			leftEye.Transparency = 1
		end
		if rightEye then
			rightEye.Transparency = 1
		end
	else
		if outer then
			local orig = outer:GetAttribute("OrigColor") :: Color3?
			if orig then
				outer.Color = orig
			end
			outer.Transparency = 0.22
		end
		if core then
			local orig = core:GetAttribute("OrigColor") :: Color3?
			if orig then
				core.Color = orig
			end
		end
		if leftEye then
			leftEye.Transparency = 0
		end
		if rightEye then
			rightEye.Transparency = 0
		end
	end
end

function SlimeFactory.CreateJellyBaitModel(): Model
	local model = Instance.new("Model")
	model.Name = "JellyBait"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(0.85, 0.85, 2.3)
	body.Color = Color3.fromRGB(255, 125, 40)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CastShadow = true
	body.Parent = model

	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.55, 0.55, 0.7)
	tip.Color = Color3.fromRGB(245, 105, 30)
	tip.Material = Enum.Material.SmoothPlastic
	tip.Anchored = true
	tip.CanCollide = false
	tip.Parent = model

	local leaf1 = Instance.new("Part")
	leaf1.Name = "Leaf1"
	leaf1.Size = Vector3.new(0.32, 0.9, 0.32)
	leaf1.Color = Color3.fromRGB(85, 215, 95)
	leaf1.Material = Enum.Material.SmoothPlastic
	leaf1.Anchored = true
	leaf1.CanCollide = false
	leaf1.Parent = model

	local leaf2 = leaf1:Clone()
	leaf2.Name = "Leaf2"
	leaf2.Parent = model

	model.PrimaryPart = body
	SlimeFactory.PositionBait(model, CFrame.new(0, 5, 0))
	return model
end

function SlimeFactory.PositionBait(model: Model, centerCFrame: CFrame)
	local body = model:FindFirstChild("Body") :: BasePart?
	local tip = model:FindFirstChild("Tip") :: BasePart?
	local leaf1 = model:FindFirstChild("Leaf1") :: BasePart?
	local leaf2 = model:FindFirstChild("Leaf2") :: BasePart?

	if body then
		body.CFrame = centerCFrame
	end
	if tip then
		tip.CFrame = centerCFrame * CFrame.new(0, 0, -1.35)
	end
	if leaf1 then
		leaf1.CFrame = centerCFrame * CFrame.new(0.18, 0.15, 1.35) * CFrame.Angles(math.rad(35), 0, math.rad(-25))
	end
	if leaf2 then
		leaf2.CFrame = centerCFrame * CFrame.new(-0.18, 0.15, 1.35) * CFrame.Angles(math.rad(35), 0, math.rad(25))
	end
end

local function scaledSize(info: PartInfo, kx2: number, ky2: number, s0: number): Vector3
	local sx = math.sqrt((info.SqX.X + info.SqX.Z) * kx2 + info.SqX.Y * ky2)
	local sy = math.sqrt((info.SqY.X + info.SqY.Z) * kx2 + info.SqY.Y * ky2)
	local sz = math.sqrt((info.SqZ.X + info.SqZ.Z) * kx2 + info.SqZ.Y * ky2)
	return Vector3.new(info.Size.X * sx, info.Size.Y * sy, info.Size.Z * sz) * s0
end

-- pose is optional (see the Pose type): the catch cutscene uses it for accessory bounce, wing flaps
-- and face blinks. Rigid models ignore it.
function SlimeFactory.PositionSlime(model: Model, centerCFrame: CFrame, squashAmount: number, pose: Pose?)
	local state = slimeState[model]
	if state then
		state.Root.CFrame = centerCFrame
		if model:GetAttribute("Rigid") then
			-- Welded to the root (see MakeRigid): moving the root moves everything, squash is skipped
			return
		end

		local baseRadius = (model:GetAttribute("BaseSize") :: number?) or 2.4
		local s = math.clamp(squashAmount, -0.45, 0.65)
		local ky = math.max(0.38 / 0.88, 1 - s * 0.52)
		local kx = math.max(0.55, 1 + s * 0.34)
		local s0 = baseRadius / state.BodyRef
		local faceY = math.clamp(if pose and pose.FaceScaleY then pose.FaceScaleY else 1, 0.05, 2)
		local bodyDirty = state.LastR ~= baseRadius or state.LastKx ~= kx or state.LastKy ~= ky
		local faceDirty = bodyDirty or state.LastFaceY ~= faceY
		state.LastR, state.LastKx, state.LastKy, state.LastFaceY = baseRadius, kx, ky, faceY

		local kx2, ky2 = kx * kx, ky * ky
		local kyf = ky * faceY
		local kyf2 = kyf * kyf
		local ux, uy = s0 * kx, s0 * ky

		local accLift = if pose and pose.AccessoryLift then pose.AccessoryLift * baseRadius else 0
		local accTilt = if pose and pose.AccessoryTilt then pose.AccessoryTilt else nil
		local faceOff = if pose and pose.FaceOffset then pose.FaceOffset * s0 else nil
		local fc = state.FaceCenter

		local motions = state.Motion
		local hasMotion = state.HasMotion
		for _, info in state.Parts do
			local p = info.Pos
			local part = info.Part
			local group = info.Group
			local isAccPose = group == "Accessory" and (accTilt ~= nil or accLift ~= 0)
			local localCf: CFrame
			if isAccPose then
				local pv = Vector3.new(info.Pivot.X * ux, info.Pivot.Y * uy + accLift, info.Pivot.Z * ux)
				local local0 = Vector3.new(p.X * ux, p.Y * uy + accLift, p.Z * ux)
				local rot = if accTilt
					then CFrame.Angles(accTilt.X, accTilt.Y * info.Side, accTilt.Z * info.Side)
					else CFrame.identity
				localCf = CFrame.new(pv) * rot * CFrame.new(local0 - pv) * info.Rot
			elseif group == "Face" and (faceY ~= 1 or faceOff) then
				local y = fc.Y * uy + (p.Y - fc.Y) * uy * faceY
				local localPos = Vector3.new(p.X * ux, y, p.Z * ux)
				if faceOff then
					localPos += faceOff
				end
				localCf = CFrame.new(localPos) * info.Rot
			else
				localCf = CFrame.new(p.X * ux, p.Y * uy, p.Z * ux) * info.Rot
			end

			-- Per-part / per-group motion (spinning halos, orbiting gems, swinging pickaxe, inflating bubble...)
			local mScale = 1
			if hasMotion then
				for _, key in info.Keys do
					local m = motions[key]
					if m then
						local kc = state.KeyCentres[key]
						local c = Vector3.new(kc.X * ux, kc.Y * uy + (if isAccPose then accLift else 0), kc.Z * ux)
						local rotM = m.Cf.Rotation
						local newPos = c + rotM * ((localCf.Position - c) * m.Scale) + m.Cf.Position * s0
						localCf = CFrame.new(newPos) * rotM * localCf.Rotation
						mScale = m.Scale
						break
					end
				end
			end
			part.CFrame = centerCFrame * localCf

			local sizeDirty = (if group == "Face" then faceDirty else bodyDirty) or mScale ~= info.MScale
			if sizeDirty then
				info.MScale = mScale
				part.Size = scaledSize(info, kx2, if group == "Face" then kyf2 else ky2, s0) * mScale
			end
		end
		return
	end

	local baseRadius = (model:GetAttribute("BaseSize") :: number?) or 2.4
	local s = math.clamp(squashAmount, -0.45, 0.65)
	local yScale = math.max(0.38, (1 - s * 0.52) * 0.88)
	local xzScale = math.max(0.55, 1 + s * 0.34)

	local outerSize = Vector3.new(baseRadius * xzScale, baseRadius * yScale, baseRadius * xzScale)
	local outer = model:FindFirstChild("OuterJelly") :: BasePart?
	local core = model:FindFirstChild("InnerCore") :: BasePart?
	local leftEye = model:FindFirstChild("LeftEye") :: BasePart?
	local rightEye = model:FindFirstChild("RightEye") :: BasePart?

	if outer then
		outer.Size = outerSize
		outer.CFrame = centerCFrame
	end
	if core then
		core.Size = outerSize * 0.54
		core.CFrame = centerCFrame
	end
	local forwardOffset = outerSize.Z * 0.43
	local eyeSpread = outerSize.X * 0.22
	local eyeHeight = outerSize.Y * 0.12
	local faceY = math.clamp(if pose and pose.FaceScaleY then pose.FaceScaleY else 1, 0.05, 2)
	local function scaleEye(eye: BasePart?)
		if not eye then
			return
		end
		local base = eye:GetAttribute("EyeSize") :: Vector3?
		if not base then
			base = eye.Size
			eye:SetAttribute("EyeSize", base)
		end
		local b = base :: Vector3
		eye.Size = Vector3.new(b.X, b.Y * faceY, b.Z)
	end
	scaleEye(leftEye)
	scaleEye(rightEye)
	if leftEye then
		leftEye.CFrame = centerCFrame * CFrame.new(-eyeSpread, eyeHeight, forwardOffset)
	end
	if rightEye then
		rightEye.CFrame = centerCFrame * CFrame.new(eyeSpread, eyeHeight, forwardOffset)
	end
end

-- True when an authored slime has parts beyond body/face (leaves, wings, hats) that the pose layer can move
function SlimeFactory.HasAccessories(model: Model): boolean
	local state = slimeState[model]
	return state ~= nil and state.HasAccessories
end

-- Extra transform for everything under `key` (a part, node or Acc_ group name, e.g. "Halo_Green",
-- "Acc_FloatingGems"): rotate by cf's rotation and scale by `scale` around that key's centre, then offset by
-- cf's position (studs at template scale). Applied by every PositionSlime call; pass cf = nil and scale = nil
-- to clear. A part uses the first key that has a motion, starting from its own name.
function SlimeFactory.SetPartMotion(model: Model, key: string, cf: CFrame?, scale: number?)
	local state = slimeState[model]
	if not state or not state.KeyCentres[key] then
		return
	end
	if cf == nil and scale == nil then
		state.Motion[key] = nil
	else
		state.Motion[key] = { Cf = cf or CFrame.identity, Scale = scale or 1 }
	end
	state.HasMotion = next(state.Motion) ~= nil
end

-- True when the authored model has a part / node / group with exactly this name
function SlimeFactory.HasPartKey(model: Model, key: string): boolean
	local state = slimeState[model]
	return state ~= nil and state.KeyCentres[key] ~= nil
end

-- Every part whose own name or any ancestor name (up to the model) matches the Lua pattern
function SlimeFactory.FindParts(model: Model, pattern: string): { BasePart }
	local state = slimeState[model]
	local found: { BasePart } = {}
	if not state then
		return found
	end
	for _, info in state.Parts do
		for _, k in info.Keys do
			if string.find(k, pattern) then
				table.insert(found, info.Part)
				break
			end
		end
	end
	return found
end

-- Face personality from the authored Face_<Type> group: "Happy" | "Sleepy" | "Angry" (procedural = "Happy")
function SlimeFactory.GetFaceType(model: Model): string
	local state = slimeState[model]
	return if state then state.FaceType else "Happy"
end

-- ============================================================================
-- WORLD SILHOUETTE + SMOOTH REVEAL (catch cutscene)
-- A dark Highlight covers the slime instead of stripping its textures, so the reveal can fade straight
-- into the real look. World-only: Highlights do not render inside ViewportFrames, so UI viewports keep
-- using SetSilhouetteMode.
-- ============================================================================
local SHADE_COLOR = Color3.fromRGB(18, 25, 20)

local function setFaceTransparency(state: SlimeState, hidden: boolean)
	for _, info in state.Parts do
		if info.Group == "Face" or info.Group == "Highlight" then
			info.Part.Transparency = if hidden then 1 else ((info.Part:GetAttribute("OrigTransparency") :: number?) or 0)
		end
	end
end

function SlimeFactory.BeginWorldSilhouette(model: Model)
	local state = slimeState[model]
	if not state then
		SlimeFactory.SetSilhouetteMode(model, true) -- procedural ball: the old swap is fine
		return
	end
	local shade = model:FindFirstChild("RevealShade") :: Highlight?
	if not shade then
		local h = Instance.new("Highlight")
		h.Name = "RevealShade"
		h.DepthMode = Enum.HighlightDepthMode.Occluded -- stays hidden while it is still under the floor
		h.Parent = model
		shade = h
	end
	local s = shade :: Highlight
	s.FillColor = SHADE_COLOR
	s.FillTransparency = 0
	s.OutlineTransparency = 1
	s.Enabled = true
	setFaceTransparency(state, true)
	local glow = model:FindFirstChild("MutationGlow")
	if glow and glow:IsA("Highlight") then
		glow.Enabled = false
	end
end

-- Partial silhouette for a world slime started with BeginWorldSilhouette: 1 = fully black, 0 = fully visible.
-- The face fades in along with it. No-op without a RevealShade (procedural ball stays black until the reveal).
function SlimeFactory.SetSilhouetteAmount(model: Model, amount: number)
	local state = slimeState[model]
	local shade = model:FindFirstChild("RevealShade") :: Highlight?
	if not state or not shade then
		return
	end
	local a = math.clamp(amount, 0, 1)
	shade.FillTransparency = 1 - a
	for _, info in state.Parts do
		if info.Group == "Face" or info.Group == "Highlight" then
			local orig = (info.Part:GetAttribute("OrigTransparency") :: number?) or 0
			info.Part.Transparency = orig + (1 - orig) * a
		end
	end
end

-- Flash white, then fade the shade away into the real textures over `duration` seconds
function SlimeFactory.RevealFromSilhouette(model: Model, duration: number)
	local state = slimeState[model]
	local shade = model:FindFirstChild("RevealShade") :: Highlight?
	if not state or not shade then
		SlimeFactory.SetSilhouetteMode(model, false)
		return
	end
	shade.FillColor = Color3.new(1, 1, 1)
	shade.FillTransparency = 0.05
	TweenService:Create(shade, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FillTransparency = 1,
	}):Play()
	for _, info in state.Parts do
		if info.Group == "Face" or info.Group == "Highlight" then
			TweenService:Create(info.Part, TweenInfo.new(duration * 0.8), {
				Transparency = (info.Part:GetAttribute("OrigTransparency") :: number?) or 0,
			}):Play()
		end
	end
	task.delay(duration, function()
		if shade.Parent then
			shade:Destroy()
		end
		local glow = model:FindFirstChild("MutationGlow")
		if glow and glow:IsA("Highlight") then
			glow.Enabled = true
		end
	end)
end

-- Weld every part of an authored slime to its root and unanchor them, so moving the root (PositionSlime)
-- moves the whole slime with a single replicated part instead of dozens. Call AFTER parenting the model
-- into the workspace. Squash is skipped while rigid. Used for server-side plot / shop slimes.
function SlimeFactory.MakeRigid(model: Model)
	local state = slimeState[model]
	if not state or model:GetAttribute("Rigid") then
		return
	end
	SlimeFactory.PositionSlime(model, state.Root.CFrame, 0) -- settle at final scale first
	for _, info in state.Parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = state.Root
		weld.Part1 = info.Part
		weld.Parent = info.Part
		info.Part.Anchored = false
	end
	model:SetAttribute("Rigid", true)
end

return SlimeFactory
