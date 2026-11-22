--!strict
--[[
	UnlockPopups.luau
	Unlock pop-ups (docs/docs/UI-MOCKUP-SPEC.md 4f): 640 wide at the top, no dimming, a striped header in the kind colour
	with a small close, a 110 tile, kicker / name 42 / detail, an optional button, and an 8 px orange timer bar that
	auto-dismisses after 5 s. Up to 2 are stacked, newest on top. The server sends the content (UnlockPopup remote).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiKit = require(Shared:WaitForChild("UiKit"))

local UnlockPopups = {}

export type UnlockPayload = {
	Kind: string,
	Kicker: string,
	Name: string,
	Detail: string,
	Icon: string?,
	ShowShop: boolean?,
}

export type UnlockPopupsContext = {
	OnOpenUpgrades: () -> (),
}

export type UnlockPopupsHandle = {
	Push: (payload: UnlockPayload) -> (),
}

local MAX_STACK = 2
local DISMISS_SECONDS = 5

local KIND_TONES: { [string]: UiKit.Tri } = {
	bait = UiKit.Gradients.Orange,
	zone = UiKit.Gradients.RewardsNav,
}
-- Tile colour contrasts the header (blue under orange, purple under teal)
local TILE_TONES: { [string]: UiKit.Tri } = {
	bait = UiKit.Gradients.Blue,
	zone = UiKit.Gradients.SlimesNav,
}

local function makeLabel(parent: Instance, size: number, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.Text = text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	UiKit.AddTextStroke(l)
	return l
end

function UnlockPopups.Build(parent: Instance, ctx: UnlockPopupsContext): UnlockPopupsHandle
	local holder = Instance.new("Frame")
	holder.Name = "UnlockPopups"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 72)
	holder.Size = UDim2.fromOffset(640, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.ZIndex = 30
	holder.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder

	local counter = 0
	local active: { Frame } = {}

	local function dismiss(card: Frame)
		local idx = table.find(active, card)
		if idx then
			table.remove(active, idx)
		end
		if card.Parent then
			card:Destroy()
		end
	end

	local function push(payload: UnlockPayload)
		counter += 1
		-- Newest on top: smaller LayoutOrder sorts first
		local card = Instance.new("Frame")
		card.Name = "Popup_" .. counter
		card.LayoutOrder = -counter
		card.Size = UDim2.new(1, 0, 0, 190)
		card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		card.Parent = holder
		UiKit.AddCorner(card, 20)
		UiKit.ApplyTri(card, { Light = Color3.fromRGB(44, 46, 55), Mid = Color3.fromRGB(36, 37, 45), Dark = Color3.fromRGB(27, 28, 34) })
		UiKit.AddFrameOutline(card, 4)
		card.ClipsDescendants = true

		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, 0, 0, 38)
		header.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		header.Parent = card
		UiKit.ApplyTri(header, KIND_TONES[payload.Kind] or UiKit.Gradients.Orange)
		UiKit.AddStripes(header)
		local kicker = makeLabel(header, 20, payload.Kicker)
		kicker.Position = UDim2.fromOffset(18, 0)
		kicker.Size = UDim2.new(1, -70, 1, 0)

		UiKit.CreateGradientButton({
			Name = "CloseBtn",
			Parent = header,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(30, 30),
			Kind = "red",
			CornerRadius = 9,
			Text = "X",
			TextSize = 16,
			OnClick = function()
				dismiss(card)
			end,
		})

		local tile = Instance.new("Frame")
		tile.Position = UDim2.fromOffset(18, 54)
		tile.Size = UDim2.fromOffset(110, 110)
		tile.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		tile.Parent = card
		UiKit.AddCorner(tile, 22)
		UiKit.ApplyTri(tile, TILE_TONES[payload.Kind] or UiKit.Gradients.Blue)
		UiKit.AddFrameOutline(tile, 4)
		if payload.Icon then
			local icon = UiKit.CreateIcon(tile, payload.Icon, 78)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
		end

		local name = makeLabel(card, 42, payload.Name)
		name.Position = UDim2.fromOffset(144, 50)
		name.Size = UDim2.new(1, -170, 0, 52)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local detail = makeLabel(card, 22, payload.Detail)
		detail.Position = UDim2.fromOffset(144, 104)
		detail.Size = UDim2.new(1, -170, 0, 30)
		detail.TextColor3 = Color3.fromRGB(215, 225, 240)

		if payload.ShowShop then
			local btn = UiKit.CreateGradientButton({
				Name = "ShopBtn",
				Parent = card,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -18, 1, -22),
				Size = UDim2.fromOffset(150, 40),
				Kind = "green",
				CornerRadius = 12,
				Text = "UPGRADES",
				TextSize = 18,
				OnClick = function()
					ctx.OnOpenUpgrades()
					dismiss(card)
				end,
			})
			btn.ZIndex = 5
		end

		-- 8 px orange timer bar, empties over DISMISS_SECONDS
		local track = Instance.new("Frame")
		track.AnchorPoint = Vector2.new(0, 1)
		track.Position = UDim2.new(0, 0, 1, 0)
		track.Size = UDim2.new(1, 0, 0, 8)
		track.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
		track.BorderSizePixel = 0
		track.Parent = card
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		fill.BorderSizePixel = 0
		fill.Parent = track
		UiKit.ApplyTri(fill, UiKit.Gradients.Orange)
		TweenService:Create(fill, TweenInfo.new(DISMISS_SECONDS, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()

		-- Slide-in
		local scale = Instance.new("UIScale")
		scale.Scale = 0.85
		scale.Parent = card
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

		table.insert(active, 1, card)
		while #active > MAX_STACK do
			dismiss(active[#active])
		end
		task.delay(DISMISS_SECONDS, function()
			dismiss(card)
		end)
	end

	return { Push = push }
end

return UnlockPopups
