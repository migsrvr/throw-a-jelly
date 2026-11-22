--!strict
--[[
	LeaderboardService.luau
	Styled hub leaderboards (docs/docs/UI-MOCKUP-SPEC.md 3h). Replaces each board's old text SurfaceGui with a
	coloured header (icon, title, subtitle), 10 rows (medal, avatar headshot, name, value) and a footer.
	Boards read the players currently in the server; they refresh every UPDATE_INTERVAL seconds.
	NOTE: the panel is 16x22 studs, so the canvas is 310x426 and the rows are 32 high (the spec's 42 px rows do not fit).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiKit = require(Shared:WaitForChild("UiKit"))

local LeaderboardService = {}

local UPDATE_INTERVAL = 60
local ROW_COUNT = 10

export type Row = { UserId: number, Name: string, Value: string }

type BoardStyle = { Title: string, Subtitle: string, Icon: string, Tone: UiKit.Tri }

local STYLES: { [string]: BoardStyle } = {
	MOSTMONEY = { Title = "Richest", Subtitle = "Most cash", Icon = "cash", Tone = UiKit.Gradients.Green },
	BESTS = { Title = "Best Income", Subtitle = "Highest $ per second", Icon = "clock", Tone = UiKit.Gradients.Blue },
	THROWPOWER = { Title = "Strongest", Subtitle = "Most throw power", Icon = "power", Tone = UiKit.Gradients.Orange },
	RARESTSLIME = { Title = "Rarest Slime", Subtitle = "Best catch so far", Icon = "crown", Tone = UiKit.Gradients.SlimesNav },
}

local MEDALS: { UiKit.Tri } = {
	{ Light = Color3.fromRGB(255, 244, 150), Mid = Color3.fromRGB(255, 205, 50), Dark = Color3.fromRGB(214, 140, 10) },
	{ Light = Color3.fromRGB(240, 244, 250), Mid = Color3.fromRGB(190, 198, 212), Dark = Color3.fromRGB(130, 138, 156) },
	{ Light = Color3.fromRGB(240, 190, 130), Mid = Color3.fromRGB(205, 130, 60), Dark = Color3.fromRGB(150, 85, 30) },
}
local ROW_DARK: UiKit.Tri = {
	Light = Color3.fromRGB(44, 46, 55),
	Mid = Color3.fromRGB(36, 37, 45),
	Dark = Color3.fromRGB(27, 28, 34),
}

local lastUpdate = 0
local lastCount = -1

local function makeLabel(parent: Instance, size: number, text: string, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.Text = text
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = parent
	UiKit.AddTextStroke(l)
	return l
end

local function getBoard(boardModel: Instance): SurfaceGui?
	local panel = boardModel:FindFirstChild("Panel")
	if not panel then
		return nil
	end
	local gui = panel:FindFirstChild("Board")
	if gui and gui:GetAttribute("Styled") == true then
		return gui :: SurfaceGui
	end
	local style = STYLES[boardModel.Name]
	if not style then
		return nil
	end
	if gui then
		gui:Destroy()
	end

	local sg = Instance.new("SurfaceGui")
	sg.Name = "Board"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = Vector2.new(310, 426)
	sg.LightInfluence = 0
	sg.ResetOnSpawn = false
	sg:SetAttribute("Styled", true)
	sg.Parent = panel

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	root.Parent = sg
	UiKit.AddCorner(root, 22)
	UiKit.ApplyTri(root, { Light = Color3.fromRGB(34, 35, 43), Mid = Color3.fromRGB(26, 27, 34), Dark = Color3.fromRGB(18, 19, 24) })
	UiKit.AddFrameOutline(root, 5)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 72)
	header.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	header.Parent = root
	UiKit.AddCorner(header, 22)
	UiKit.ApplyTri(header, style.Tone)
	UiKit.AddStripes(header, 22)
	UiKit.AddGloss(header, 22)
	local plate = UiKit.CreateIconPlate(header, style.Icon, 48)
	plate.Position = UDim2.fromOffset(12, 12)
	local title = makeLabel(header, 28, style.Title, Enum.TextXAlignment.Left)
	title.Position = UDim2.fromOffset(70, 6)
	title.Size = UDim2.new(1, -80, 0, 36)
	local sub = makeLabel(header, 15, style.Subtitle, Enum.TextXAlignment.Left)
	sub.Position = UDim2.fromOffset(70, 42)
	sub.Size = UDim2.new(1, -80, 0, 22)

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Position = UDim2.fromOffset(10, 80)
	rows.Size = UDim2.new(1, -20, 0, ROW_COUNT * 32)
	rows.BackgroundTransparency = 1
	rows.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rows

	for rank = 1, ROW_COUNT do
		local row = Instance.new("Frame")
		row.Name = "Row" .. rank
		row.LayoutOrder = rank
		row.Size = UDim2.new(1, 0, 0, 30)
		row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		row.BackgroundTransparency = if rank <= 3 then 0.55 else 0.75
		row.Parent = rows
		UiKit.AddCorner(row, 10)
		UiKit.ApplyTri(row, if rank <= 3 then MEDALS[rank] else ROW_DARK)

		local medal = Instance.new("Frame")
		medal.Name = "Medal"
		medal.Position = UDim2.fromOffset(4, 2)
		medal.Size = UDim2.fromOffset(26, 26)
		medal.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		medal.Parent = row
		UiKit.AddCorner(medal, 13)
		UiKit.ApplyTri(medal, if rank <= 3 then MEDALS[rank] else UiKit.Gradients.IconPlate)
		UiKit.AddStroke(medal, UiKit.Colors.Ink, 2, Enum.ApplyStrokeMode.Border)
		local num = makeLabel(medal, 15, tostring(rank))
		num.Size = UDim2.fromScale(1, 1)

		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.Position = UDim2.fromOffset(36, 2)
		avatar.Size = UDim2.fromOffset(26, 26)
		avatar.BackgroundColor3 = Color3.fromRGB(35, 37, 44)
		avatar.Visible = false
		avatar.Parent = row
		UiKit.AddCorner(avatar, 13)

		local name = makeLabel(row, 16, "---", Enum.TextXAlignment.Left)
		name.Name = "Name"
		name.Position = UDim2.fromOffset(68, 0)
		name.Size = UDim2.new(0.5, -68, 1, 0)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local value = makeLabel(row, 16, "", Enum.TextXAlignment.Right)
		value.Name = "Value"
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -8, 0, 0)
		value.Size = UDim2.new(0.5, -8, 1, 0)
		UiKit.ApplyTri(value, style.Tone)
	end

	local footer = makeLabel(root, 14, `Updates every {UPDATE_INTERVAL} seconds`)
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.new(0.5, 0, 1, -6)
	footer.Size = UDim2.new(1, 0, 0, 22)
	footer.TextTransparency = 0.25
	return sg
end

-- Fill one board. `boardsFolder` is Hub.Leaderboards, `boardName` a model name such as "MOSTMONEY".
function LeaderboardService.Render(boardsFolder: Instance, boardName: string, entries: { Row })
	local model = boardsFolder:FindFirstChild(boardName)
	if not model then
		return
	end
	local sg = getBoard(model)
	if not sg then
		return
	end
	local rows = sg:FindFirstChild("Rows", true)
	if not rows then
		return
	end
	for rank = 1, ROW_COUNT do
		local row = rows:FindFirstChild("Row" .. rank)
		if row then
			local entry = entries[rank]
			local nameLabel = row:FindFirstChild("Name") :: TextLabel
			local valueLabel = row:FindFirstChild("Value") :: TextLabel
			local avatar = row:FindFirstChild("Avatar") :: ImageLabel
			if entry then
				nameLabel.Text = entry.Name
				valueLabel.Text = entry.Value
				avatar.Image = `rbxthumb://type=AvatarHeadShot&id={entry.UserId}&w=48&h=48`
				avatar.Visible = true
			else
				nameLabel.Text = "---"
				valueLabel.Text = ""
				avatar.Visible = false
			end
		end
	end
end

-- True when the boards are due a refresh: first call, every UPDATE_INTERVAL, or when the player count changes.
function LeaderboardService.ShouldUpdate(playerCount: number): boolean
	local now = os.clock()
	if lastUpdate == 0 or now - lastUpdate >= UPDATE_INTERVAL or playerCount ~= lastCount then
		lastUpdate = now
		lastCount = playerCount
		return true
	end
	return false
end

return LeaderboardService
