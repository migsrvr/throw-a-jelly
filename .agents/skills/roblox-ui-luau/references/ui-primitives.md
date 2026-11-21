# Roblox UI Primitives Reference (`UiKit.luau`)

## 1. Responsive Viewport `UIScale`

```luau
function UiKit.AttachResponsiveScale(screenGui: ScreenGui): UIScale
	local uiScale = screenGui:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = screenGui
	end

	local function update()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		if vp.X <= 0 or vp.Y <= 0 then
			return
		end
		uiScale.Scale = math.clamp(math.min(vp.X / 1366, vp.Y / 768), 0.68, 1.18)
	end

	update()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return uiScale
end
```

## 2. Tactile 3D-Bevel Button with Spring Micro-Interactions

```luau
function UiKit.AttachButtonJuice(button: GuiButton, faceFrame: Frame?)
	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", button)
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
```

## 3. Live 3D `ViewportFrame` Slime/Item Card

```luau
function UiKit.CreateSlimeViewport(parent: Instance, slimeId: string, mutationId: string?, isSilhouette: boolean?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(210, 220, 235)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-1, -1.2, -1)
	vp.Parent = parent

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = vp

	local model = SlimeFactory.CreateSlimeModel(slimeId, false, mutationId)
	SlimeFactory.PositionSlime(model, CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(155), 0), 0)
	if isSilhouette then
		SlimeFactory.SetSilhouetteMode(model, true)
	end
	model.Parent = worldModel

	local cam = Instance.new("Camera")
	local baseRadius = (model:GetAttribute("BaseSize") :: number?) or 2.4
	local dist = baseRadius * 1.65
	cam.CFrame = CFrame.lookAt(Vector3.new(dist * 0.55, dist * 0.42, -dist), Vector3.new(0, -0.1, 0))
	cam.FieldOfView = 45
	cam.Parent = vp
	vp.CurrentCamera = cam

	return vp
end
```
