--!strict
--[[
	UiKit.luau
	Reusable Roblox UI component library following the `roblox-ui-luau` skill:
	- AttachResponsiveScale (adaptive UIScale for PC, Mobile, Tablet, 4K)
	- AttachButtonJuice (TweenService hover/press/release spring micro-interactions)
	- CreateBevelButton (3D bottom bevel lip + glossy vertical UIGradient + bold outlined text)
	- CreateSlimeViewport (live 3D ViewportFrame preview of any slime or dark ??? silhouette)
	- ToggleModalAnimated (spring UIScale pop-in + dimmed backdrop scrim)
]]

local TweenService = game:GetService("TweenService")

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local SlimeFactory = require(script.Parent:WaitForChild("SlimeFactory"))

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
		local raw = math.min(vp.X / 1366, vp.Y / 768)
		uiScale.Scale = math.clamp(raw, 0.68, 1.18)
	end

	updateScale()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local newCam = workspace.CurrentCamera
		if newCam then
			updateScale()
			newCam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
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
	-- Face the camera (+Z forward face looks toward camera at -Z)
	SlimeFactory.PositionSlime(model, CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(160), 0), 0)

	if isSilhouette then
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
	cam.CFrame = CFrame.lookAt(Vector3.new(dist * 0.45, dist * 0.35, -dist), Vector3.new(0, -0.05, 0))
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

return UiKit
