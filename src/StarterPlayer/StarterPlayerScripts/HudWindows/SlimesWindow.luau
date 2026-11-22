--!strict
--[[
	SlimesWindow.luau
	Backpack modal (docs/docs/UI-MOCKUP-SPEC.md 3e, 5b): "IN YOUR BACKPACK N", sort chips, 84 px rows,
	PLACE buttons, PLOT FULL state, AUTO-PLACE BEST, empty state. Built only from UiKit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))
local UiKit = require(Shared:WaitForChild("UiKit"))
local UiLayout = require(Shared:WaitForChild("UiLayout"))

local SlimesWindow = {}

export type SlimesWindowContext = {
	ModalScrim: Frame,
	GetFreeSlot: () -> number?,
	OnPlace: (uid: string, slot: number) -> (),
	OnAutoPlace: () -> (),
	OnSell: (uid: string) -> (),
	OnSellAll: () -> (),
}

export type SlimesWindowHandle = {
	Frame: Frame,
	Refresh: (state: any) -> (),
}

local SORTS = { "Income", "Rarity", "Newest" }

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

function SlimesWindow.Build(parent: Instance, ctx: SlimesWindowContext): SlimesWindowHandle
	local win = UiKit.CreateWindow({
		Name = "SlimesModal",
		Parent = parent,
		Title = "My Slimes",
		Size = UDim2.fromOffset(680, 540),
		Position = UDim2.fromScale(0.5, 0.52),
		Header = {
			Light = Color3.fromRGB(255, 122, 234),
			Mid = Color3.fromRGB(236, 31, 216),
			Dark = Color3.fromRGB(168, 18, 184),
		},
	})
	local modal = win.Frame
	win.Close.Activated:Connect(function()
		UiKit.ToggleModalAnimated(modal, ctx.ModalScrim, false)
	end)

	-- Plot pill: <placed>/<MaxSlimes>
	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -70, 0.5, 0)
	pill.Size = UDim2.fromOffset(150, 40)
	pill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	pill.ZIndex = 4
	pill.Parent = win.Header
	UiKit.AddCorner(pill, 20)
	UiKit.ApplyTri(pill, UiKit.Gradients.IconPlate)
	UiKit.AddFrameOutline(pill, 3)
	local plotIcon = UiKit.CreateIcon(pill, "basket", 30)
	plotIcon.AnchorPoint = Vector2.new(0, 0.5)
	plotIcon.Position = UDim2.new(0, 8, 0.5, 0)
	plotIcon.ZIndex = 5
	local plotLabel = makeLabel(pill, 22, "0/8")
	plotLabel.Position = UDim2.fromOffset(46, 0)
	plotLabel.Size = UDim2.new(1, -54, 1, 0)
	plotLabel.ZIndex = 5

	local body = win.Body
	local countLabel = makeLabel(body, 24, "IN YOUR BACKPACK 0")
	countLabel.Position = UDim2.fromOffset(20, 10)
	countLabel.Size = UDim2.fromOffset(280, 34)

	-- Sort chips
	local sortMode = "Income"
	local chips: { [string]: TextButton } = {}
	local rebuild: () -> () = function() end
	local function paintChips()
		for mode, chip in chips do
			UiKit.SetButtonTone(chip, if mode == sortMode then UiKit.Gradients.Green else UiKit.Gradients.Grey, 0)
		end
	end
	for i, mode in SORTS do
		local chip = UiKit.CreateGradientButton({
			Name = "Sort_" .. mode,
			Parent = body,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -20 - (#SORTS - i) * 86, 0, 10),
			Size = UDim2.fromOffset(80, 34),
			Kind = "grey",
			CornerRadius = 12,
			Text = mode,
			TextSize = 15,
			OnClick = function()
				sortMode = mode
				paintChips()
				rebuild()
			end,
		})
		chips[mode] = chip
	end
	paintChips()

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(20, 54)
	list.Size = UDim2.new(1, -40, 1, -54 - 84)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingLeft = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = list

	local emptyLabel = makeLabel(body, 28, "Throw jelly to catch slimes!")
	emptyLabel.Position = UDim2.fromOffset(20, 120)
	emptyLabel.Size = UDim2.new(1, -40, 0, 80)
	emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
	emptyLabel.Visible = false

	-- Bottom footer: AUTO-PLACE BEST (left) + SELL ALL (right)
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.new(0.5, 0, 1, -16)
	footer.Size = UDim2.new(1, -40, 0, 64)
	footer.BackgroundTransparency = 1
	footer.Parent = body

	local autoBtn, autoFace = UiKit.CreateGradientButton({
		Name = "AutoPlaceBestBtn",
		Parent = footer,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0.54, -6, 1, 0),
		Kind = "orange",
		CornerRadius = 18,
		Text = "AUTO-PLACE BEST",
		TextSize = 24,
		OnClick = ctx.OnAutoPlace,
	})
	UiKit.AddStripes(autoFace, 18)

	local hasUnplaced = false
	local sellAllBtn, sellAllFace, sellAllLabel = UiKit.CreateGradientButton({
		Name = "SellAllBtn",
		Parent = footer,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.46, -6, 1, 0),
		Kind = "red",
		CornerRadius = 18,
		Text = "SELL ALL",
		TextSize = 22,
		OnClick = function()
			if hasUnplaced then
				ctx.OnSellAll()
			end
		end,
	})
	UiKit.AddStripes(sellAllFace, 18)

	local lastSignature = ""
	local lastState: any = nil

	rebuild = function()
		local state = lastState
		if not state then
			return
		end
		local unplaced: { any } = state.UnplacedSlimes or {}
		local placedCount = 0
		for _ in state.PlacedSlimes or {} do
			placedCount += 1
		end
		local maxSlimes = state.MaxSlimes or 8
		local plotFull = ctx.GetFreeSlot() == nil

		local totalSellValue = 0
		for _, inst in unplaced do
			totalSellValue += ProgressionLogic.GetSlimeSellPrice(inst)
		end
		hasUnplaced = #unplaced > 0
		if sellAllLabel then
			sellAllLabel.Text = if hasUnplaced then `SELL ALL (${GameConfig.FormatNumber(totalSellValue)})` else "SELL ALL"
		end
		UiKit.SetButtonTone(sellAllBtn, if hasUnplaced then UiKit.Gradients.Red else UiKit.Gradients.Grey, if hasUnplaced then 0 else 0.35)

		plotLabel.Text = `{placedCount}/{maxSlimes}`
		countLabel.Text = `IN YOUR BACKPACK {#unplaced}`
		emptyLabel.Visible = #unplaced == 0
		list.Visible = #unplaced > 0

		local parts = { sortMode, tostring(plotFull) }
		for _, inst in unplaced do
			table.insert(parts, inst.Uid)
		end
		local signature = table.concat(parts, "|")
		if signature == lastSignature then
			return
		end
		lastSignature = signature

		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local items: { UiLayout.SortItem } = {}
		for i, inst in unplaced do
			local def = GameConfig.SlimesById[inst.SlimeId] or GameConfig.Slimes[1]
			table.insert(items, { Income = inst.IncomePerSec, Rank = def.RarityRank, Index = i })
		end

		for order, idx in UiLayout.SortedIndexes(items, sortMode) do
			local inst = unplaced[idx]
			local def = GameConfig.SlimesById[inst.SlimeId] or GameConfig.Slimes[1]
			local rarityColor = SlimeFactory.GetRarityColor(def.Rarity)
			local sellPrice = ProgressionLogic.GetSlimeSellPrice(inst)

			local row = Instance.new("Frame")
			row.Name = "SlimeRow_" .. inst.Uid
			row.LayoutOrder = order
			row.Size = UDim2.new(1, 0, 0, 84)
			row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			row.Parent = list
			UiKit.AddCorner(row, 18)
			UiKit.ApplyTri(row, {
				Light = Color3.fromRGB(44, 46, 55),
				Mid = Color3.fromRGB(36, 37, 45),
				Dark = Color3.fromRGB(27, 28, 34),
			})
			UiKit.AddFrameOutline(row, 4)

			local tile = Instance.new("Frame")
			tile.Position = UDim2.fromOffset(10, 10)
			tile.Size = UDim2.fromOffset(64, 64)
			tile.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			tile.Parent = row
			UiKit.AddCorner(tile, 14)
			UiKit.ApplyTri(tile, UiKit.TriFromColor(rarityColor, 0.4, 0.3))
			UiKit.AddStroke(tile, UiKit.Colors.Ink, 3, Enum.ApplyStrokeMode.Border)
			local vpHolder = Instance.new("Frame")
			vpHolder.Size = UDim2.fromScale(1, 1)
			vpHolder.BackgroundTransparency = 1
			vpHolder.Parent = tile
			UiKit.CreateSlimeViewport(vpHolder, inst.SlimeId, inst.Mutation, false)

			local word = makeLabel(row, 14, if inst.Mutation ~= "NORMAL" then inst.Mutation else def.Rarity)
			word.Position = UDim2.fromOffset(88, 8)
			word.Size = UDim2.fromOffset(250, 18)
			if inst.Mutation ~= "NORMAL" then
				UiKit.ApplyTri(word, UiKit.TriFromColor(SlimeFactory.GetMutationColor(inst.Mutation), 0.5, 0.2))
			else
				UiKit.ApplyTri(word, UiKit.TriFromColor(rarityColor, 0.5, 0.2))
			end
			local name = makeLabel(row, 24, inst.Name)
			name.Position = UDim2.fromOffset(88, 24)
			name.Size = UDim2.fromOffset(265, 30)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local income = makeLabel(row, 19, `${GameConfig.FormatNumber(inst.IncomePerSec)}/s`)
			income.Position = UDim2.fromOffset(88, 54)
			income.Size = UDim2.fromOffset(220, 24)
			UiKit.ApplyTri(income, UiKit.Gradients.Cash)

			local uid = inst.Uid
			local _, sellFace = UiKit.CreateGradientButton({
				Name = "SellBtn",
				Parent = row,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -138, 0.5, 0),
				Size = UDim2.fromOffset(116, 56),
				Kind = "red",
				CornerRadius = 14,
				OnClick = function()
					ctx.OnSell(uid)
				end,
			})
			local sellTop = makeLabel(sellFace, 14, "SELL")
			sellTop.Position = UDim2.fromOffset(0, 4)
			sellTop.Size = UDim2.new(1, 0, 0, 18)
			sellTop.TextXAlignment = Enum.TextXAlignment.Center
			sellTop.ZIndex = 3
			local sellVal = makeLabel(sellFace, 20, `${GameConfig.FormatNumber(sellPrice)}`)
			sellVal.Position = UDim2.fromOffset(0, 20)
			sellVal.Size = UDim2.new(1, 0, 0, 26)
			sellVal.TextXAlignment = Enum.TextXAlignment.Center
			sellVal.ZIndex = 3
			UiKit.ApplyTri(sellVal, UiKit.Gradients.Cash)

			UiKit.CreateGradientButton({
				Name = "PlaceBtn",
				Parent = row,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(116, 56),
				Kind = if plotFull then "grey" else "blue",
				CornerRadius = 14,
				Text = if plotFull then "PLOT FULL" else "PLACE",
				TextSize = if plotFull then 16 else 22,
				OnClick = function()
					local slot = ctx.GetFreeSlot()
					if slot then
						ctx.OnPlace(uid, slot)
					end
				end,
			})
		end
	end

	return {
		Frame = modal,
		Refresh = function(state: any)
			lastState = state
			rebuild()
		end,
	}
end

return SlimesWindow
