--!strict
--[[
	PromptStyle.client.luau
	Custom ProximityPrompt look (docs/docs/UI-MOCKUP-SPEC.md 3g): dark pill, keycap with the key inside a gold hold ring,
	ObjectText (14) above ActionText (22). Switches every prompt to Style = Custom on this client and draws our own gui.
	Hold progress: the ring fills in from transparent to solid gold and a thin gold bar fills along the bottom of the pill
	(a true conic ring needs masking tricks, so this is the simpler read of the same idea).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiAssets = require(Shared:WaitForChild("UiAssets"))
local UiKit = require(Shared:WaitForChild("UiKit"))

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local activePromptCleanups: { [ProximityPrompt]: () -> () } = {}

local function makeCustom(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Style = Enum.ProximityPromptStyle.Custom
	end
end

for _, d in workspace:GetDescendants() do
	makeCustom(d)
end
workspace.DescendantAdded:Connect(makeCustom)

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return "A"
	end
	local key = prompt.KeyboardKeyCode
	return if key == Enum.KeyCode.Unknown then "E" else key.Name
end

ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		return
	end
	if activePromptCleanups[prompt] then
		activePromptCleanups[prompt]()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "StyledPrompt"
	gui.Size = UDim2.fromOffset(260, 66)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.Adornee = prompt.Parent :: Instance?
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local pill = Instance.new("Frame")
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	pill.Parent = gui
	UiKit.AddCorner(pill, 33)
	UiKit.ApplyTri(pill, UiKit.Gradients.IconPlate)
	UiKit.AddFrameOutline(pill, 4)

	-- Keycap inside a gold hold ring
	local ring = Instance.new("ImageLabel")
	ring.AnchorPoint = Vector2.new(0, 0.5)
	ring.Position = UDim2.new(0, 6, 0.5, 0)
	ring.Size = UDim2.fromOffset(54, 54)
	ring.BackgroundTransparency = 1
	ring.Image = UiAssets.Textures.ring
	ring.ImageColor3 = UiKit.Colors.Gold
	ring.ImageTransparency = 0.85
	ring.Parent = pill
	local keycap = Instance.new("Frame")
	keycap.AnchorPoint = Vector2.new(0.5, 0.5)
	keycap.Position = UDim2.fromScale(0.5, 0.5)
	keycap.Size = UDim2.fromOffset(36, 36)
	keycap.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	keycap.Parent = ring
	UiKit.AddCorner(keycap, 10)
	UiKit.ApplyTri(keycap, { Light = Color3.fromRGB(255, 255, 255), Mid = Color3.fromRGB(235, 238, 244), Dark = Color3.fromRGB(205, 210, 222) })
	UiKit.AddStroke(keycap, UiKit.Colors.Ink, 2.5, Enum.ApplyStrokeMode.Border)
	local key = Instance.new("TextLabel")
	key.Size = UDim2.fromScale(1, 1)
	key.BackgroundTransparency = 1
	key.Font = Enum.Font.FredokaOne
	key.TextSize = if #keyText(prompt, inputType) > 2 then 14 else 22
	key.TextColor3 = Color3.fromRGB(20, 22, 30)
	key.Text = keyText(prompt, inputType)
	key.Parent = keycap

	local object = Instance.new("TextLabel")
	object.BackgroundTransparency = 1
	object.Position = UDim2.fromOffset(68, 6)
	object.Size = UDim2.new(1, -78, 0, 18)
	object.Font = Enum.Font.FredokaOne
	object.TextSize = 14
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextColor3 = Color3.fromRGB(205, 212, 226)
	object.Text = prompt.ObjectText
	object.TextTruncate = Enum.TextTruncate.AtEnd
	object.Parent = pill
	local action = Instance.new("TextLabel")
	action.BackgroundTransparency = 1
	action.Position = UDim2.fromOffset(68, 22)
	action.Size = UDim2.new(1, -78, 0, 32)
	action.Font = Enum.Font.FredokaOne
	action.TextSize = 22
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.TextColor3 = Color3.fromRGB(255, 255, 255)
	action.Text = prompt.ActionText
	action.TextTruncate = Enum.TextTruncate.AtEnd
	action.Parent = pill
	UiKit.AddTextStroke(action)

	local barTrack = Instance.new("Frame")
	barTrack.AnchorPoint = Vector2.new(0.5, 1)
	barTrack.Position = UDim2.new(0.5, 0, 1, -6)
	barTrack.Size = UDim2.new(1, -44, 0, 5)
	barTrack.BackgroundTransparency = 1
	barTrack.Parent = pill
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = UiKit.Colors.Gold
	barFill.BorderSizePixel = 0
	barFill.Parent = barTrack
	UiKit.AddCorner(barFill, 3)

	-- Pop in
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = pill
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local holdBegan = prompt.PromptButtonHoldBegan:Connect(function()
		local d = math.max(prompt.HoldDuration, 0.05)
		TweenService:Create(barFill, TweenInfo.new(d, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
		TweenService:Create(ring, TweenInfo.new(d, Enum.EasingStyle.Linear), { ImageTransparency = 0 }):Play()
	end)
	local holdEnded = prompt.PromptButtonHoldEnded:Connect(function()
		TweenService:Create(barFill, TweenInfo.new(0.1), { Size = UDim2.fromScale(0, 1) }):Play()
		TweenService:Create(ring, TweenInfo.new(0.1), { ImageTransparency = 0.85 }):Play()
	end)

	-- Tap / click on the pill triggers it (touch + mouse)
	local clickArea = Instance.new("TextButton")
	clickArea.Size = UDim2.fromScale(1, 1)
	clickArea.BackgroundTransparency = 1
	clickArea.Text = ""
	clickArea.ZIndex = 10
	clickArea.Parent = pill
	clickArea.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end)
	clickArea.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end)

	local changed = prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		action.Text = prompt.ActionText
	end)
	local changedObj = prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
		object.Text = prompt.ObjectText
	end)

	local cleanedUp = false
	local hiddenConn: RBXScriptConnection? = nil
	local ancestryConn: RBXScriptConnection? = nil

	local function cleanup()
		if cleanedUp then
			return
		end
		cleanedUp = true
		activePromptCleanups[prompt] = nil
		holdBegan:Disconnect()
		holdEnded:Disconnect()
		changed:Disconnect()
		changedObj:Disconnect()
		if hiddenConn then
			hiddenConn:Disconnect()
		end
		if ancestryConn then
			ancestryConn:Disconnect()
		end
		gui:Destroy()
	end

	activePromptCleanups[prompt] = cleanup
	hiddenConn = ProximityPromptService.PromptHidden:Connect(function(hiddenPrompt: ProximityPrompt)
		if hiddenPrompt == prompt then
			cleanup()
		end
	end)
	ancestryConn = prompt.AncestryChanged:Connect(function()
		if not prompt:IsDescendantOf(game) then
			cleanup()
		end
	end)
end)

