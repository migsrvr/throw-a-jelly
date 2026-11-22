--!strict
--[[
	SlimeFactory.luau
	Procedural 3D Jelly Slime Model generator (with Mutation visuals & Silhouette mode)
	plus 3D Jelly Bait / Carrot Treat model for holding and throwing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

type PartInfo = {
	Part: BasePart,
	Pos: Vector3, -- offset from the body centre at template scale (already lifted to the ball's ground line)
	Rot: CFrame, -- orientation relative to the body
	Size: Vector3,
	SqX: Vector3, -- squared components of the part's local axes in model space (for squash scaling)
	SqY: Vector3,
	SqZ: Vector3,
}

type SlimeState = {
	Root: BasePart,
	Parts: { PartInfo },
	BodyRef: number, -- template body width; BaseSize / BodyRef = uniform scale
	LastR: number,
	LastKx: number,
	LastKy: number,
	Stripped: { { SA: SurfaceAppearance, Part: BasePart } }, -- SurfaceAppearances removed while silhouetted
}

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
			table.insert(parts, {
				Part = d,
				Pos = rel.Position + Vector3.new(0, lift, 0),
				Rot = rot,
				Size = d.Size,
				SqX = Vector3.new(rx.X * rx.X, rx.Y * rx.Y, rx.Z * rx.Z),
				SqY = Vector3.new(ry.X * ry.X, ry.Y * ry.Y, ry.Z * ry.Z),
				SqZ = Vector3.new(rz.X * rz.X, rz.Y * rz.Y, rz.Z * rz.Z),
			})
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
		LastR = -1,
		LastKx = -1,
		LastKy = -1,
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

function SlimeFactory.PositionSlime(model: Model, centerCFrame: CFrame, squashAmount: number)
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
		local sizeDirty = state.LastR ~= baseRadius or state.LastKx ~= kx or state.LastKy ~= ky
		state.LastR, state.LastKx, state.LastKy = baseRadius, kx, ky

		local kx2, ky2 = kx * kx, ky * ky
		local ux, uy = s0 * kx, s0 * ky
		for _, info in state.Parts do
			local p = info.Pos
			local part = info.Part
			part.CFrame = centerCFrame * CFrame.new(p.X * ux, p.Y * uy, p.Z * ux) * info.Rot
			if sizeDirty then
				local sx = math.sqrt((info.SqX.X + info.SqX.Z) * kx2 + info.SqX.Y * ky2)
				local sy = math.sqrt((info.SqY.X + info.SqY.Z) * kx2 + info.SqY.Y * ky2)
				local sz = math.sqrt((info.SqZ.X + info.SqZ.Z) * kx2 + info.SqZ.Y * ky2)
				part.Size = Vector3.new(info.Size.X * sx, info.Size.Y * sy, info.Size.Z * sz) * s0
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
	if leftEye then
		leftEye.CFrame = centerCFrame * CFrame.new(-eyeSpread, eyeHeight, forwardOffset)
	end
	if rightEye then
		rightEye.CFrame = centerCFrame * CFrame.new(eyeSpread, eyeHeight, forwardOffset)
	end
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
