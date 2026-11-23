--!strict
--[[
	SettingsWindow.luau
	Settings pop-up: a "Graphics" row with Auto / Low / High and a "Music" row with On / Off (the picked one is green).
	Both are saved on the server (RequestSetGraphics / RequestSetMusic -> profile GraphicsMode / MusicOn) and applied
	right away: graphics through DeviceProfile, music through the LocalPlayer "MusicOn" attribute (MusicController).
	A line under the graphics row shows the detail level the game is actually running at (Auto can drop to Low).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeviceProfile = require(Shared:WaitForChild("DeviceProfile"))
local UiKit = require(Shared:WaitForChild("UiKit"))

local SettingsWindow = {}

export type SettingsContext = {
	ModalScrim: Frame,
	OnPickGraphics: (mode: string) -> (),
	OnPickMusic: (on: boolean) -> (),
}

export type SettingsHandle = {
	Frame: Frame,
}

local MODES = { "Auto", "Low", "High" }
local TIER_NAMES = { Low = "LOW", Mid = "MEDIUM", High = "HIGH" }

local function makeLabel(parent: Instance, size: number, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.Text = text
	l.ZIndex = 12
	l.Parent = parent
	UiKit.AddTextStroke(l)
	return l
end

function SettingsWindow.Build(parent: Instance, ctx: SettingsContext): SettingsHandle
	local win = UiKit.CreateWindow({
		Name = "SettingsModal",
		Parent = parent,
		Title = "Settings",
		Size = UDim2.fromOffset(560, 450),
		Header = UiKit.Gradients.Blue,
	})
	local modal = win.Frame
	win.Close.Activated:Connect(function()
		UiKit.ToggleModalAnimated(modal, ctx.ModalScrim, false)
	end)

	local body = win.Body
	local title = makeLabel(body, 32, "Graphics")
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 14)
	title.Size = UDim2.new(1, -40, 0, 38)

	local row = Instance.new("Frame")
	row.Name = "GraphicsRow"
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 62)
	row.Size = UDim2.fromOffset(3 * 150 + 2 * 14, 72)
	row.BackgroundTransparency = 1
	row.ZIndex = 11
	row.Parent = body
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 14)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row

	local buttons: { [string]: TextButton } = {}
	local function refresh()
		local mode = DeviceProfile.Mode()
		for m, btn in buttons do
			UiKit.SetButtonTone(btn, if m == mode then UiKit.Gradients.Green else UiKit.Gradients.Grey)
		end
	end

	for i, m in MODES do
		local btn = UiKit.CreateGradientButton({
			Name = m .. "Btn",
			Parent = row,
			Size = UDim2.fromOffset(150, 64),
			Kind = "grey",
			Text = m,
			TextSize = 30,
			LayoutOrder = i,
			OnClick = function()
				DeviceProfile.SetMode(m) -- apply right away, the server saves it
				ctx.OnPickGraphics(m)
				refresh()
			end,
		})
		buttons[m] = btn
	end

	local hint = makeLabel(body, 22, "Low = smoother on older phones and tablets")
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 152)
	hint.Size = UDim2.new(1, -40, 0, 28)
	hint.TextWrapped = true

	local status = makeLabel(body, 22, "")
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0, 186)
	status.Size = UDim2.new(1, -40, 0, 28)
	status.TextColor3 = Color3.fromRGB(255, 230, 120)
	local function refreshStatus()
		status.Text = `Running at {TIER_NAMES[DeviceProfile.Tier()] or "HIGH"} detail`
	end

	-- Music: On / Off (the LocalPlayer "MusicOn" attribute drives MusicController; the server saves it)
	local musicTitle = makeLabel(body, 32, "Music")
	musicTitle.AnchorPoint = Vector2.new(0.5, 0)
	musicTitle.Position = UDim2.new(0.5, 0, 0, 228)
	musicTitle.Size = UDim2.new(1, -40, 0, 38)

	local musicRow = Instance.new("Frame")
	musicRow.Name = "MusicRow"
	musicRow.AnchorPoint = Vector2.new(0.5, 0)
	musicRow.Position = UDim2.new(0.5, 0, 0, 276)
	musicRow.Size = UDim2.fromOffset(2 * 150 + 14, 72)
	musicRow.BackgroundTransparency = 1
	musicRow.ZIndex = 11
	musicRow.Parent = body
	local musicList = list:Clone()
	musicList.Parent = musicRow

	local player = Players.LocalPlayer
	local musicButtons: { [boolean]: TextButton } = {}
	local function refreshMusic()
		local on = player:GetAttribute("MusicOn") ~= false
		for value, btn in musicButtons do
			UiKit.SetButtonTone(btn, if value == on then UiKit.Gradients.Green else UiKit.Gradients.Grey)
		end
	end
	for i, value in { true, false } do
		musicButtons[value] = UiKit.CreateGradientButton({
			Name = if value then "MusicOnBtn" else "MusicOffBtn",
			Parent = musicRow,
			Size = UDim2.fromOffset(150, 64),
			Kind = "grey",
			Text = if value then "On" else "Off",
			TextSize = 30,
			LayoutOrder = i,
			OnClick = function()
				player:SetAttribute("MusicOn", value) -- apply right away, the server saves it
				ctx.OnPickMusic(value)
			end,
		})
	end
	player:GetAttributeChangedSignal("MusicOn"):Connect(refreshMusic)

	DeviceProfile.Changed:Connect(function()
		refresh()
		refreshStatus()
	end)
	modal:GetPropertyChangedSignal("Visible"):Connect(function()
		if modal.Visible then
			refresh()
			refreshStatus()
			refreshMusic()
		end
	end)
	refresh()
	refreshStatus()
	refreshMusic()

	return { Frame = modal }
end

return SettingsWindow
