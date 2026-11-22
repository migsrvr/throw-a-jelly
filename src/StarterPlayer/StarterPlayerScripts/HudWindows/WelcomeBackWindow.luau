--!strict
--[[
	WelcomeBackWindow.luau
	Welcome Back pop-up (docs/docs/UI-MOCKUP-SPEC.md 4e): 660x460, no close button, centred title, the offline
	earnings as a big gradient number, "Away for Xm", CLAIM (green) and "2X + Robux 25" (orange, developer product).
	The server decides the amount (PlayerStateService offline offer); this window only shows it and reports the click.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local UiAssets = require(Shared:WaitForChild("UiAssets"))
local UiKit = require(Shared:WaitForChild("UiKit"))
local UiLayout = require(Shared:WaitForChild("UiLayout"))

local WelcomeBackWindow = {}

export type WelcomeBackContext = {
	ModalScrim: Frame,
	OnClaim: () -> (),
	OnClaimDouble: () -> (),
}

export type WelcomeBackHandle = {
	Frame: Frame,
	Show: (cash: number, awaySeconds: number) -> (),
	Hide: () -> (),
}

local function makeLabel(parent: Instance, size: number, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.Text = text
	l.Parent = parent
	UiKit.AddTextStroke(l)
	return l
end

function WelcomeBackWindow.Build(parent: Instance, ctx: WelcomeBackContext): WelcomeBackHandle
	local win = UiKit.CreateWindow({
		Name = "WelcomeBackModal",
		Parent = parent,
		Title = "Welcome Back!",
		Size = UDim2.fromOffset(660, 460),
		Position = UDim2.fromScale(0.5, 0.52),
		Header = UiKit.Gradients.Orange,
	})
	local frame = win.Frame
	frame.ZIndex = 40
	win.Close.Visible = false
	win.Title.Size = UDim2.fromScale(1, 1)
	win.Title.Position = UDim2.fromOffset(0, 0)
	win.Title.TextXAlignment = Enum.TextXAlignment.Center
	win.Title.TextSize = 44

	local body = win.Body
	local away = makeLabel(body, 26, "Away for 0m")
	away.Position = UDim2.fromOffset(0, 24)
	away.Size = UDim2.new(1, 0, 0, 36)
	away.TextColor3 = Color3.fromRGB(215, 225, 240)

	local kicker = makeLabel(body, 22, "While you were gone, your slimes earned")
	kicker.Position = UDim2.fromOffset(0, 64)
	kicker.Size = UDim2.new(1, 0, 0, 30)

	local icon = UiKit.CreateIcon(body, "cash", 70)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 100)
	icon.Visible = false

	local amount = makeLabel(body, 84, "$0")
	amount.Position = UDim2.fromOffset(0, 100)
	amount.Size = UDim2.new(1, 0, 0, 100)
	UiKit.ApplyTri(amount, UiKit.Gradients.Cash)

	local claim = UiKit.CreateGradientButton({
		Name = "ClaimBtn",
		Parent = body,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 40, 1, -34),
		Size = UDim2.new(0.5, -50, 0, 84),
		Kind = "green",
		CornerRadius = 22,
		Text = "CLAIM",
		TextSize = 38,
		OnClick = function()
			ctx.OnClaim()
		end,
	})
	claim.ZIndex = 41

	local double, doubleFace = UiKit.CreateGradientButton({
		Name = "DoubleBtn",
		Parent = body,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -40, 1, -34),
		Size = UDim2.new(0.5, -50, 0, 84),
		Kind = "orange",
		CornerRadius = 22,
		OnClick = function()
			ctx.OnClaimDouble()
		end,
	})
	double.ZIndex = 41
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.ZIndex = 3
	row.Parent = doubleFace
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row
	local x2 = makeLabel(row, 34, "2X +")
	x2.AutomaticSize = Enum.AutomaticSize.X
	x2.Size = UDim2.fromOffset(0, 50)
	x2.ZIndex = 3
	x2.LayoutOrder = 1
	local glyph = Instance.new("ImageLabel")
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromOffset(30, 30)
	glyph.Image = UiAssets.Robux
	glyph.LayoutOrder = 2
	glyph.ZIndex = 3
	glyph.Parent = row
	local robux = makeLabel(row, 34, tostring(GameConfig.Offline.DoubleRobux))
	robux.AutomaticSize = Enum.AutomaticSize.X
	robux.Size = UDim2.fromOffset(0, 50)
	robux.ZIndex = 3
	robux.LayoutOrder = 3
	-- Developer product not set up yet: grey + "Coming soon"
	if GameConfig.Offline.DoubleProductId <= 0 then
		UiKit.SetButtonTone(double, UiKit.Gradients.Grey, 0.2)
		x2.Text = "2X (Soon)"
		glyph.Visible = false
		robux.Visible = false
	end

	local function hide()
		UiKit.ToggleModalAnimated(frame, ctx.ModalScrim, false)
	end

	return {
		Frame = frame,
		Show = function(cash: number, awaySeconds: number)
			amount.Text = `${GameConfig.FormatNumber(cash)}`
			away.Text = `Away for {UiLayout.FormatAway(awaySeconds)}`
			UiKit.ToggleModalAnimated(frame, ctx.ModalScrim, true)
		end,
		Hide = hide,
	}
end

return WelcomeBackWindow
