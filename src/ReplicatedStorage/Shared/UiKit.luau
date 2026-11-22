--!strict
--[[
	UiKit.luau
	Reusable Roblox UI component library following the `roblox-ui-luau` skill:
	- AttachResponsiveScale (adaptive UIScale for PC, Mobile, Tablet, 4K)
	- AttachButtonJuice (TweenService hover/press/release spring micro-interactions)
	- CreateBevelButton (3D bottom bevel lip + glossy vertical UIGradient + bold outlined text)
	- CreateSlimeViewport (live 3D ViewportFrame preview of any slime or dark ??? silhouette)
	- ToggleModalAnimated (spring UIScale pop-in + dimmed backdrop scrim)
	- Design system for the new UI: Colors, Gradients, AddGradient, AddTextStroke, AddStripes,
	  CreateIconPlate, CreateGradientButton, CreateWindow, CreateTabs, CreateProgressBar (UI-MOCKUP-SPEC.md)
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local SlimeFactory = require(script.Parent:WaitForChild("SlimeFactory"))
local UiAssets = require(script.Parent:WaitForChild("UiAssets"))
local UiLayout = require(script.Parent:WaitForChild("UiLayout"))

local UiKit = {}

function UiKit.AddCorner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function UiKit.AddStroke(
	parent: Instance,
	color: Color3,
	thickness: number,
	mode: Enum.ApplyStrokeMode?
): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	if mode then
		s.ApplyStrokeMode = mode
	end
	s.Parent = parent
	return s
end

function UiKit.AddGlossGradient(parent: Instance, baseColor: Color3): UIGradient
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	local top = baseColor:Lerp(Color3.fromRGB(255, 255, 255), 0.18)
	local bot = baseColor:Lerp(Color3.fromRGB(0, 0, 0), 0.12)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(0.5, baseColor),
		ColorSequenceKeypoint.new(1, bot),
	})
	g.Parent = parent
	return g
end

function UiKit.AttachResponsiveScale(screenGui: ScreenGui): UIScale
	local uiScale = screenGui:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = screenGui
	end

	local function updateScale()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		if vp.X <= 0 or vp.Y <= 0 then
			return
		end
		-- PC fits 1366x768 (0.68-1.18). Touch-only phones use vp.Y / 574 (0.6-0.8), spec section 0.
		uiScale.Scale = UiLayout.RootScale(vp.X, vp.Y, UiKit.IsPhone())
	end

	updateScale()
	local camConn: RBXScriptConnection? = nil
	local function bindCamera(cam: Camera?)
		if camConn then
			camConn:Disconnect()
			camConn = nil
		end
		if cam then
			updateScale()
			camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
	end
	bindCamera(workspace.CurrentCamera)
	local worldCamConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(workspace.CurrentCamera)
	end)
	screenGui.Destroying:Connect(function()
		if camConn then
			camConn:Disconnect()
			camConn = nil
		end
		worldCamConn:Disconnect()
	end)

	return uiScale
end

function UiKit.AttachButtonJuice(button: GuiButton, faceFrame: Frame?)
	local scale = button:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = button
	end
	local baseFacePos = if faceFrame then faceFrame.Position else UDim2.new()

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1.06,
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1.0,
		}):Play()
		if faceFrame then
			faceFrame.Position = baseFacePos
		end
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 0.93,
		}):Play()
		if faceFrame then
			faceFrame.Position = baseFacePos + UDim2.fromOffset(0, 3)
		end
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1.04,
		}):Play()
		if faceFrame then
			faceFrame.Position = baseFacePos
		end
	end)
end

export type BevelButtonOpts = {
	Name: string?,
	Parent: Instance,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Size: UDim2,
	Color: Color3,
	CornerRadius: number?,
	Text: string?,
	TextSize: number?,
	OnClick: (() -> ())?,
}

function UiKit.CreateBevelButton(opts: BevelButtonOpts): (TextButton, Frame, TextLabel?)
	local radius = opts.CornerRadius or 12
	local lipColor = opts.Color:Lerp(Color3.fromRGB(10, 12, 18), 0.38)

	local btn = Instance.new("TextButton")
	btn.Name = opts.Name or "BevelButton"
	if opts.AnchorPoint then
		btn.AnchorPoint = opts.AnchorPoint
	end
	if opts.Position then
		btn.Position = opts.Position
	end
	btn.Size = opts.Size
	btn.BackgroundColor3 = lipColor
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Parent = opts.Parent
	UiKit.AddCorner(btn, radius)
	UiKit.AddStroke(btn, Color3.fromRGB(15, 18, 25), 2.5, Enum.ApplyStrokeMode.Border)

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Position = UDim2.fromOffset(0, -3)
	face.Size = UDim2.new(1, 0, 1, -2)
	face.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	face.Parent = btn
	UiKit.AddCorner(face, radius)
	UiKit.AddGlossGradient(face, opts.Color)
	UiKit.AddStroke(face, Color3.fromRGB(15, 18, 25), 1.8, Enum.ApplyStrokeMode.Border)

	-- Top inner shine line
	local shine = Instance.new("Frame")
	shine.Name = "TopShine"
	shine.Position = UDim2.new(0, 6, 0, 3)
	shine.Size = UDim2.new(1, -12, 0, 3)
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.65
	shine.BorderSizePixel = 0
	shine.Parent = face
	UiKit.AddCorner(shine, 3)

	local label: TextLabel? = nil
	if opts.Text and opts.Text ~= "" then
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextSize = opts.TextSize or 18
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.Text = opts.Text
		lbl.Parent = face
		UiKit.AddStroke(lbl, Color3.fromRGB(15, 18, 25), 2.2)
		label = lbl
	end

	UiKit.AttachButtonJuice(btn, face)
	if opts.OnClick then
		btn.Activated:Connect(opts.OnClick)
	end

	return btn, face, label
end

function UiKit.CreateSlimeViewport(
	parent: Instance,
	slimeId: string,
	mutationId: string?,
	isSilhouette: boolean?
): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "SlimeViewport"
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(205, 215, 235)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-1, -1.3, -1)
	vp.Parent = parent

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = vp

	local def = GameConfig.SlimesById[slimeId] or GameConfig.Slimes[1]
	local model = SlimeFactory.CreateSlimeModel(def.Id, false, mutationId)
	-- Face the camera, which sits at -Z. Authored slime models face -Z (3/4 turn toward the camera's
	-- right); the old procedural ball had its eyes on +Z, so it needs the 160 degree turn.
	local isCustom = model:GetAttribute("CustomModel") == true
	local yaw = if isCustom then math.rad(-24) else math.rad(160)
	SlimeFactory.PositionSlime(model, CFrame.new(0, 0, 0) * CFrame.Angles(0, yaw, 0), 0)

	if isSilhouette and isCustom then
		SlimeFactory.SetSilhouetteMode(model, true)
	elseif isSilhouette then
		local outer = model:FindFirstChild("OuterJelly") :: BasePart?
		local core = model:FindFirstChild("InnerCore") :: BasePart?
		local lEye = model:FindFirstChild("LeftEye") :: BasePart?
		local rEye = model:FindFirstChild("RightEye") :: BasePart?
		if outer then
			outer.Color = Color3.fromRGB(18, 20, 26)
			outer.Transparency = 0
		end
		if core then
			core.Transparency = 1
		end
		if lEye then
			lEye.Transparency = 1
		end
		if rEye then
			rEye.Transparency = 1
		end
	end

	model.Parent = worldModel

	local cam = Instance.new("Camera")
	local baseRadius = (model:GetAttribute("BaseSize") :: number?) or 2.4
	local dist = baseRadius * 1.55
	local lookAtPoint = Vector3.new(0, -0.05, 0)
	if isCustom then
		-- Authored models have accessories (crowns, wings...) so frame the whole bounding box
		local bboxCf, bboxSize = model:GetBoundingBox()
		lookAtPoint = bboxCf.Position
		dist = math.max(bboxSize.X, bboxSize.Y, bboxSize.Z) * 1.2
	end
	cam.CFrame = CFrame.lookAt(lookAtPoint + Vector3.new(dist * 0.45, dist * 0.35, -dist), lookAtPoint)
	cam.FieldOfView = 42
	cam.Parent = vp
	vp.CurrentCamera = cam

	return vp
end

function UiKit.ToggleModalAnimated(modal: Frame, scrim: Frame?, visible: boolean)
	local scale = modal:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = modal
	end

	if visible then
		modal.Visible = true
		scale.Scale = 0.82
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1.0,
		}):Play()
		if scrim then
			scrim.Visible = true
			TweenService:Create(scrim, TweenInfo.new(0.18), {
				BackgroundTransparency = 0.42,
			}):Play()
		end
	else
		modal.Visible = false
		if scrim then
			scrim.BackgroundTransparency = 1
			scrim.Visible = false
		end
	end
end

-- ============================================================================
-- DESIGN SYSTEM (docs/docs/UI-MOCKUP-SPEC.md sections 0-1c). Every screen uses only these helpers.
-- ============================================================================

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Section 1 tokens
UiKit.Colors = {
	Ink = rgb(5, 5, 7),
	Panel = rgb(23, 24, 28),
	PanelInner = rgb(59, 61, 70),
	White = rgb(255, 255, 255),
	Power = rgb(62, 184, 255),
	Cash = rgb(184, 242, 51),
	Gems = rgb(143, 228, 255),
	Luck = rgb(255, 225, 74),
	Gold = rgb(255, 215, 65),
	Green = rgb(76, 219, 22),
	Red = rgb(232, 40, 42),
}

export type Tri = { Light: Color3, Mid: Color3, Dark: Color3 }

local function tri(l: Color3, m: Color3, d: Color3): Tri
	return { Light = l, Mid = m, Dark = d }
end

-- Section 1c gradient table (light 0 / mid 0.55 / dark 1, rotation 90 = top to bottom)
UiKit.Gradients = {
	IndexNav = tri(rgb(255, 240, 122), rgb(255, 178, 28), rgb(240, 122, 0)),
	ShopNav = tri(rgb(182, 255, 122), rgb(76, 219, 22), rgb(36, 153, 12)),
	UpgradesNav = tri(rgb(158, 216, 255), rgb(62, 162, 255), rgb(26, 92, 200)),
	RewardsNav = tri(rgb(168, 255, 242), rgb(46, 224, 207), rgb(15, 154, 168)),
	SlimesNav = tri(rgb(210, 182, 255), rgb(155, 92, 255), rgb(90, 43, 208)),
	Green = tri(rgb(140, 255, 74), rgb(76, 219, 22), rgb(47, 168, 15)),
	Red = tri(rgb(255, 122, 122), rgb(232, 40, 42), rgb(179, 18, 44)),
	Orange = tri(rgb(255, 240, 122), rgb(255, 178, 28), rgb(240, 122, 0)),
	Blue = tri(rgb(158, 216, 255), rgb(62, 162, 255), rgb(26, 92, 200)),
	Grey = tri(rgb(190, 194, 204), rgb(120, 124, 134), rgb(70, 73, 82)),
	Power = tri(rgb(200, 240, 255), rgb(62, 184, 255), rgb(30, 111, 224)),
	Cash = tri(rgb(244, 255, 176), rgb(184, 242, 51), rgb(92, 194, 26)),
	Gems = tri(rgb(240, 252, 255), rgb(143, 228, 255), rgb(58, 168, 232)),
	Luck = tri(rgb(255, 251, 208), rgb(255, 225, 74), rgb(255, 159, 10)),
	IconPlate = tri(rgb(52, 54, 63), rgb(35, 37, 44), rgb(18, 19, 24)),
}

-- Gradient from one base colour: lightened 50% / base / darkened 25% (zone banners), or custom amounts.
function UiKit.TriFromColor(base: Color3, lighten: number?, darken: number?): Tri
	return tri(
		base:Lerp(rgb(255, 255, 255), lighten or 0.5),
		base,
		base:Lerp(rgb(0, 0, 0), darken or 0.25)
	)
end

-- Bottom lip colour for a gradient (the 7 px strip under a button face)
local function lipColor(t: Tri): Color3
	return t.Dark:Lerp(rgb(0, 0, 0), 0.35)
end

function UiKit.IsPhone(): boolean
	return UiLayout.IsPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
end

-- 3-stop vertical UIGradient (spec 1c). For gradient text keep TextColor3 white and add AddTextStroke.
function UiKit.AddGradient(target: Instance, light: Color3, mid: Color3, dark: Color3): UIGradient
	local g = Instance.new("UIGradient")
	g.Name = "ToneGradient"
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, light),
		ColorSequenceKeypoint.new(0.55, mid),
		ColorSequenceKeypoint.new(1, dark),
	})
	g.Parent = target
	return g
end

function UiKit.ApplyTri(target: Instance, t: Tri): UIGradient
	return UiKit.AddGradient(target, t.Light, t.Mid, t.Dark)
end

-- Re-tint an existing tone gradient (or add one). Used for state changes (button grey/green, banners).
function UiKit.SetTone(target: Instance, t: Tri)
	local g = target:FindFirstChild("ToneGradient")
	if g and g:IsA("UIGradient") then
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, t.Light),
			ColorSequenceKeypoint.new(0.55, t.Mid),
			ColorSequenceKeypoint.new(1, t.Dark),
		})
	else
		UiKit.ApplyTri(target, t)
	end
end

-- Text outline A: black Contextual stroke, thickness from the text size (or an explicit override)
function UiKit.AddTextStroke(label: GuiObject, thickness: number?): UIStroke
	local size = if label:IsA("TextLabel") or label:IsA("TextButton") then label.TextSize else 24
	local s = Instance.new("UIStroke")
	s.Name = "TextStroke"
	s.Color = UiKit.Colors.Ink
	s.Thickness = thickness or UiLayout.StrokeThickness(size)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = label
	return s
end

-- Frame outline A: black Border stroke, 4 px
function UiKit.AddFrameOutline(frame: GuiObject, thickness: number?): UIStroke
	return UiKit.AddStroke(frame, UiKit.Colors.Ink, thickness or 4, Enum.ApplyStrokeMode.Border)
end

-- Inner light bevel: inset child frame with a 3 px white stroke at 0.65 transparency
function UiKit.AddBevel(frame: GuiObject, radius: number): Frame
	local inset = Instance.new("Frame")
	inset.Name = "InnerBevel"
	inset.Position = UDim2.fromOffset(3, 3)
	inset.Size = UDim2.new(1, -6, 1, -6)
	inset.BackgroundTransparency = 1
	inset.Active = false
	inset.Parent = frame
	UiKit.AddCorner(inset, math.max(radius - 3, 2))
	local s = UiKit.AddStroke(inset, UiKit.Colors.White, 3, Enum.ApplyStrokeMode.Border)
	s.Transparency = 0.65
	return inset
end

-- Gloss: white frame over the top 42%, transparency 0.55 -> 1
function UiKit.AddGloss(frame: GuiObject, radius: number): Frame
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Position = UDim2.fromOffset(4, 4)
	gloss.Size = UDim2.new(1, -8, 0.42, -4)
	gloss.BackgroundColor3 = UiKit.Colors.White
	gloss.BorderSizePixel = 0
	gloss.Active = false
	gloss.Parent = frame
	UiKit.AddCorner(gloss, math.max(radius - 4, 2))
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = gloss
	return gloss
end

-- Diagonal stripe texture (headers, banners). ImageTransparency 0.86, 64 px tile.
function UiKit.AddStripes(frame: GuiObject, radius: number?): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = "Stripes"
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = UiAssets.Textures.stripes
	img.ScaleType = Enum.ScaleType.Tile
	img.TileSize = UDim2.fromOffset(64, 64)
	img.ImageTransparency = 0.86
	img.Active = false
	img.Parent = frame
	if radius then
		UiKit.AddCorner(img, radius)
	end
	return img
end

-- Icon (ImageLabel, Fit). `iconKey` is a key of UiAssets.Icons, or an image string.
function UiKit.CreateIcon(parent: Instance, iconKey: string, size: number): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = "Icon_" .. iconKey
	img.Size = UDim2.fromOffset(size, size)
	img.BackgroundTransparency = 1
	img.Image = (UiAssets.Icons :: any)[iconKey] or iconKey
	img.ScaleType = Enum.ScaleType.Fit
	img.Active = false
	img.Parent = parent
	return img
end

-- Dark icon plate (spec 1b): use when an icon would sit on a similar colour. iconScale default 0.7.
function UiKit.CreateIconPlate(parent: Instance, iconKey: string, size: number, iconScale: number?): Frame
	local plate = Instance.new("Frame")
	plate.Name = "IconPlate"
	plate.Size = UDim2.fromOffset(size, size)
	plate.BackgroundColor3 = UiKit.Colors.White
	plate.Parent = parent
	UiKit.AddCorner(plate, math.floor(size * 0.28))
	UiKit.ApplyTri(plate, UiKit.Gradients.IconPlate)
	UiKit.AddStroke(plate, UiKit.Colors.Ink, 3, Enum.ApplyStrokeMode.Border)
	local icon = UiKit.CreateIcon(plate, iconKey, math.floor(size * (iconScale or 0.7)))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	return plate
end

export type ButtonKind = "green" | "orange" | "blue" | "red" | "grey" | "indexnav" | "shopnav" | "upgradesnav" | "rewardsnav" | "slimesnav"

export type GradientButtonOpts = {
	Name: string?,
	Parent: Instance,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Size: UDim2?,
	AutomaticSize: Enum.AutomaticSize?,
	Kind: ButtonKind?,
	Gradient: Tri?,
	CornerRadius: number?,
	Text: string?,
	TextSize: number?,
	PaddingX: number?,
	LayoutOrder: number?,
	OnClick: (() -> ())?,
}

local KIND_GRADIENTS: { [string]: string } = {
	green = "Green",
	orange = "Orange",
	blue = "Blue",
	red = "Red",
	grey = "Grey",
	indexnav = "IndexNav",
	shopnav = "ShopNav",
	upgradesnav = "UpgradesNav",
	rewardsnav = "RewardsNav",
	slimesnav = "SlimesNav",
}

-- Gradient button: dark lip behind, gradient face on top, inner light bevel, gloss, 4 px outline, juice.
-- Returns (button, face, label). Put icons/children in `face`.
function UiKit.CreateGradientButton(opts: GradientButtonOpts): (TextButton, Frame, TextLabel?)
	local kind: string = opts.Kind or "green"
	local gradient: Tri = opts.Gradient or (UiKit.Gradients :: any)[KIND_GRADIENTS[kind] or "Green"]
	local radius = opts.CornerRadius or 16
	local lip = 7

	local btn = Instance.new("TextButton")
	btn.Name = opts.Name or "GradientButton"
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.BackgroundColor3 = lipColor(gradient)
	btn.Size = opts.Size or UDim2.fromOffset(160, 56)
	if opts.AutomaticSize then
		btn.AutomaticSize = opts.AutomaticSize
	end
	if opts.AnchorPoint then
		btn.AnchorPoint = opts.AnchorPoint
	end
	if opts.Position then
		btn.Position = opts.Position
	end
	if opts.LayoutOrder then
		btn.LayoutOrder = opts.LayoutOrder
	end
	btn.Parent = opts.Parent
	UiKit.AddCorner(btn, radius)
	UiKit.AddFrameOutline(btn)

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Size = UDim2.new(1, 0, 1, -lip)
	face.BackgroundColor3 = UiKit.Colors.White
	face.Active = false
	face.Parent = btn
	UiKit.AddCorner(face, radius)
	UiKit.ApplyTri(face, gradient)
	UiKit.AddBevel(face, radius)
	UiKit.AddGloss(face, radius)

	local label: TextLabel? = nil
	if opts.Text and opts.Text ~= "" then
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextSize = opts.TextSize or 24
		lbl.TextColor3 = UiKit.Colors.White
		lbl.Text = opts.Text
		lbl.ZIndex = 3
		lbl.Parent = face
		UiKit.AddTextStroke(lbl)
		if opts.AutomaticSize == Enum.AutomaticSize.X or opts.AutomaticSize == Enum.AutomaticSize.XY then
			-- Button width follows the text: label drives the size, padding on both sides
			lbl.AutomaticSize = Enum.AutomaticSize.X
			lbl.Size = UDim2.new(0, 0, 1, 0)
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, opts.PaddingX or 26)
			pad.PaddingRight = UDim.new(0, opts.PaddingX or 26)
			pad.Parent = lbl
			face.AutomaticSize = Enum.AutomaticSize.X
			face.Size = UDim2.new(0, 0, 1, -lip)
		end
		label = lbl
	end

	UiKit.AttachButtonJuice(btn, nil)
	if opts.OnClick then
		btn.Activated:Connect(opts.OnClick)
	end
	return btn, face, label
end

-- Re-tint a CreateGradientButton (face gradient + lip) and set how see-through it is.
function UiKit.SetButtonTone(btn: TextButton, t: Tri, transparency: number?)
	local alpha = transparency or 0
	btn.BackgroundColor3 = lipColor(t)
	btn.BackgroundTransparency = alpha
	local face = btn:FindFirstChild("Face")
	if face and face:IsA("Frame") then
		UiKit.SetTone(face, t)
		face.BackgroundTransparency = alpha
	end
end

export type WindowOpts = {
	Name: string?,
	Parent: Instance,
	Title: string,
	Size: UDim2,
	Header: Tri,
	Position: UDim2?,
	OnClose: (() -> ())?,
}

export type WindowParts = {
	Frame: Frame,
	Header: Frame,
	Title: TextLabel,
	Body: Frame,
	Close: TextButton,
}

-- Window: Panel body, 4 px outline, striped gradient header with gloss, title and red close button.
function UiKit.CreateWindow(opts: WindowOpts): WindowParts
	local frame = Instance.new("Frame")
	frame.Name = opts.Name or "Window"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = opts.Position or UDim2.fromScale(0.5, 0.5)
	frame.Size = opts.Size
	frame.BackgroundColor3 = UiKit.Colors.Panel
	frame.Visible = false
	frame.ZIndex = 10
	frame.Parent = opts.Parent
	UiKit.AddCorner(frame, 20)
	UiKit.AddFrameOutline(frame)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 64)
	header.BackgroundColor3 = UiKit.Colors.White
	header.Parent = frame
	UiKit.AddCorner(header, 20)
	UiKit.ApplyTri(header, opts.Header)
	UiKit.AddStripes(header, 20)
	UiKit.AddGloss(header, 20)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(22, 0)
	title.Size = UDim2.new(1, -90, 1, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 34
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = UiKit.Colors.White
	title.Text = opts.Title
	title.ZIndex = 3
	title.Parent = header
	UiKit.AddTextStroke(title)

	local close = UiKit.CreateGradientButton({
		Name = "CloseBtn",
		Parent = header,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		Kind = "red",
		CornerRadius = 12,
		Text = "X",
		TextSize = 24,
		OnClick = opts.OnClose,
	})
	close.ZIndex = 4

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, 64)
	body.Size = UDim2.new(1, 0, 1, -64)
	body.BackgroundTransparency = 1
	body.Parent = frame

	return { Frame = frame, Header = header, Title = title, Body = body, Close = close }
end

export type TabDef = { Id: string, Text: string, Icon: string?, Gradient: Tri? }

export type TabsParts = {
	Frame: Frame,
	Select: (id: string) -> (),
	Selected: () -> string,
	Buttons: { [string]: TextButton },
}

-- Tab row: equal-width gradient buttons, the selected one lifted with a gold outline.
function UiKit.CreateTabs(parent: Instance, list: { TabDef }, onSelect: ((id: string, previous: string?) -> ())?): TabsParts
	local row = Instance.new("Frame")
	row.Name = "Tabs"
	row.Size = UDim2.new(1, 0, 0, 52)
	row.BackgroundTransparency = 1
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local buttons: { [string]: TextButton } = {}
	local strokes: { [string]: UIStroke } = {}
	local current = ""
	local function selectTab(id: string)
		if id == current then
			return
		end
		local previous = if current ~= "" then current else nil
		current = id
		for tabId, b in buttons do
			local on = tabId == id
			strokes[tabId].Color = if on then UiKit.Colors.Gold else UiKit.Colors.Ink
			TweenService:Create(b, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				BackgroundTransparency = if on then 0 else 0.35,
			}):Play()
			local face = b:FindFirstChild("Face") :: Frame?
			if face then
				face.BackgroundTransparency = if on then 0 else 0.35
			end
		end
		if onSelect then
			onSelect(id, previous)
		end
	end

	for i, def in list do
		local btn, face = UiKit.CreateGradientButton({
			Name = "Tab_" .. def.Id,
			Parent = row,
			Size = UDim2.new(1 / #list, -10 * (#list - 1) / #list, 1, 0),
			Gradient = def.Gradient or UiKit.Gradients.Blue,
			CornerRadius = 14,
			Text = def.Text,
			TextSize = 22,
			LayoutOrder = i,
			OnClick = function()
				selectTab(def.Id)
			end,
		})
		buttons[def.Id] = btn
		strokes[def.Id] = btn:FindFirstChildOfClass("UIStroke") :: UIStroke
		if def.Icon then
			local icon = UiKit.CreateIcon(face, def.Icon, 30)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 10, 0.5, 0)
		end
	end

	return {
		Frame = row,
		Select = selectTab,
		Selected = function()
			return current
		end,
		Buttons = buttons,
	}
end

export type ProgressBarParts = {
	Frame: Frame,
	Fill: Frame,
	Label: TextLabel,
	SetFraction: (fraction: number, animate: boolean?) -> (),
}

-- Progress bar: dark pill track with a gradient fill (default green) and a centred outlined label.
function UiKit.CreateProgressBar(parent: Instance, size: UDim2, fillTone: Tri?): ProgressBarParts
	local track = Instance.new("Frame")
	track.Name = "ProgressBar"
	track.Size = size
	track.BackgroundColor3 = rgb(16, 18, 24)
	track.Parent = parent
	UiKit.AddCorner(track, 999)
	UiKit.AddStroke(track, UiKit.Colors.Ink, 3, Enum.ApplyStrokeMode.Border)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = UiKit.Colors.White
	fill.BorderSizePixel = 0
	fill.Parent = track
	UiKit.AddCorner(fill, 999)
	UiKit.ApplyTri(fill, fillTone or UiKit.Gradients.Green)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 16
	label.TextColor3 = UiKit.Colors.White
	label.Text = ""
	label.ZIndex = 3
	label.Parent = track
	UiKit.AddTextStroke(label)

	return {
		Frame = track,
		Fill = fill,
		Label = label,
		SetFraction = function(fraction: number, animate: boolean?)
			local target = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			if animate then
				TweenService:Create(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = target,
				}):Play()
			else
				fill.Size = target
			end
		end,
	}
end

return UiKit
