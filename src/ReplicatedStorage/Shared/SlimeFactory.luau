--!strict
--[[
	SlimeFactory.luau
	Procedural 3D Jelly Slime Model generator (with Mutation visuals & Silhouette mode)
	plus 3D Jelly Bait / Carrot Treat model for holding and throwing.
]]

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

local SlimeFactory = {}

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

function SlimeFactory.CreateSlimeModel(slimeId: string, showBillboard: boolean?, mutationId: string?, customIncome: number?): Model
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

function SlimeFactory.SetSilhouetteMode(model: Model, isSilhouette: boolean)
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

return SlimeFactory
