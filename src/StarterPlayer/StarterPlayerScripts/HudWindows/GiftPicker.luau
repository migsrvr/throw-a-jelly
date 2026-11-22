--!strict
--[[
	GiftPicker.luau
	Gift picker (docs/docs/UI-MOCKUP-SPEC.md 4g): 600x540, blue header with a gift icon, an item chip row, "Who do you
	want to gift?", and one 88 high row per OTHER player in the server (headshot, DisplayName, @Name, GIFT button).
	The server validates the target and starts the developer product purchase (MonetizationService RequestGift).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiKit = require(Shared:WaitForChild("UiKit"))

local GiftPicker = {}

export type GiftItem = { Kind: string, ItemId: string, Count: number, Name: string }

export type GiftPickerContext = {
	ModalScrim: Frame,
	Items: { GiftItem },
	OnGift: (targetUserId: number, item: GiftItem) -> (),
}

export type GiftPickerHandle = {
	Frame: Frame,
	Open: () -> (),
}

local function makeLabel(parent: Instance, size: number, text: string, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.Text = text
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Parent = parent
	UiKit.AddTextStroke(l)
	return l
end

function GiftPicker.Build(parent: Instance, ctx: GiftPickerContext): GiftPickerHandle
	local win = UiKit.CreateWindow({
		Name = "GiftPickerModal",
		Parent = parent,
		Title = "Gift",
		Size = UDim2.fromOffset(600, 540),
		Position = UDim2.fromScale(0.5, 0.52),
		Header = UiKit.Gradients.Blue,
	})
	local frame = win.Frame
	frame.ZIndex = 30
	win.Close.Activated:Connect(function()
		UiKit.ToggleModalAnimated(frame, ctx.ModalScrim, false)
	end)
	local giftIcon = UiKit.CreateIconPlate(win.Header, "rewards", 48)
	giftIcon.AnchorPoint = Vector2.new(1, 0.5)
	giftIcon.Position = UDim2.new(1, -70, 0.5, 0)
	giftIcon.ZIndex = 4

	local body = win.Body
	local selected: GiftItem? = ctx.Items[1]

	-- Item chips
	local chipRow = Instance.new("Frame")
	chipRow.Position = UDim2.fromOffset(20, 12)
	chipRow.Size = UDim2.new(1, -40, 0, 40)
	chipRow.BackgroundTransparency = 1
	chipRow.Parent = body
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 8)
	chipLayout.Parent = chipRow
	local chipButtons: { [GiftItem]: TextButton } = {}
	local function paintChips()
		for item, btn in chipButtons do
			UiKit.SetButtonTone(btn, if item == selected then UiKit.Gradients.Green else UiKit.Gradients.Grey, 0)
		end
	end
	for _, item in ctx.Items do
		local btn = UiKit.CreateGradientButton({
			Parent = chipRow,
			Size = UDim2.fromOffset(150, 38),
			Kind = "grey",
			CornerRadius = 12,
			Text = item.Name,
			TextSize = 15,
			OnClick = function()
				selected = item
				paintChips()
			end,
		})
		chipButtons[item] = btn
	end
	paintChips()

	local prompt = makeLabel(body, 24, "Who do you want to gift?")
	prompt.Position = UDim2.fromOffset(20, 62)
	prompt.Size = UDim2.new(1, -40, 0, 32)

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(20, 100)
	list.Size = UDim2.new(1, -40, 1, -116)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 3)
	pad.PaddingTop = UDim.new(0, 3)
	pad.Parent = list

	local empty = makeLabel(body, 22, "No other players here yet", Enum.TextXAlignment.Center)
	empty.Position = UDim2.fromOffset(20, 180)
	empty.Size = UDim2.new(1, -40, 0, 60)
	empty.TextColor3 = Color3.fromRGB(215, 225, 240)
	empty.Visible = false

	local function rebuild()
		for _, c in list:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local count = 0
		for _, other in Players:GetPlayers() do
			if other ~= Players.LocalPlayer then
				count += 1
				local row = Instance.new("Frame")
				row.LayoutOrder = count
				row.Size = UDim2.new(1, 0, 0, 88)
				row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				row.Parent = list
				UiKit.AddCorner(row, 18)
				UiKit.ApplyTri(row, { Light = Color3.fromRGB(44, 46, 55), Mid = Color3.fromRGB(36, 37, 45), Dark = Color3.fromRGB(27, 28, 34) })
				UiKit.AddFrameOutline(row, 4)
				local avatar = Instance.new("ImageLabel")
				avatar.Position = UDim2.fromOffset(12, 12)
				avatar.Size = UDim2.fromOffset(60, 60)
				avatar.BackgroundColor3 = Color3.fromRGB(35, 37, 44)
				avatar.Image = `rbxthumb://type=AvatarHeadShot&id={other.UserId}&w=150&h=150`
				avatar.Parent = row
				UiKit.AddCorner(avatar, 30)
				UiKit.AddStroke(avatar, UiKit.Colors.Ink, 3, Enum.ApplyStrokeMode.Border)
				local display = makeLabel(row, 24, other.DisplayName)
				display.Position = UDim2.fromOffset(86, 12)
				display.Size = UDim2.new(1, -250, 0, 32)
				display.TextTruncate = Enum.TextTruncate.AtEnd
				local handle = makeLabel(row, 16, `@{other.Name}`)
				handle.Position = UDim2.fromOffset(86, 46)
				handle.Size = UDim2.new(1, -250, 0, 22)
				handle.TextColor3 = Color3.fromRGB(190, 200, 218)
				handle.TextTruncate = Enum.TextTruncate.AtEnd
				local userId = other.UserId
				UiKit.CreateGradientButton({
					Name = "GiftBtn",
					Parent = row,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -14, 0.5, 0),
					Size = UDim2.fromOffset(130, 56),
					Kind = "blue",
					CornerRadius = 16,
					Text = "GIFT",
					TextSize = 26,
					OnClick = function()
						local item = selected
						if item then
							ctx.OnGift(userId, item)
						end
					end,
				})
			end
		end
		empty.Visible = count == 0
	end

	return {
		Frame = frame,
		Open = function()
			rebuild()
			UiKit.ToggleModalAnimated(frame, ctx.ModalScrim, true)
		end,
	}
end

return GiftPicker
