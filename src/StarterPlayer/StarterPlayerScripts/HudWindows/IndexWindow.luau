--!strict
--[[
	IndexWindow.luau
	Slime Index modal (docs/docs/UI-MOCKUP-SPEC.md 3d, 5b): zone rows with zone card, 6 slime cards
	(2 rows of 3; silhouette + "???" until discovered), zone progress bar, footer "Unlocked X/total", and a right column with
	the selected slime's detail card and the zone trail card (LOCKED / EQUIP / EQUIPPED).
	Cards are built once; Refresh only re-tints what changed so viewports do not flicker on state syncs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))
local UiKit = require(Shared:WaitForChild("UiKit"))
local UiAssets = require(Shared:WaitForChild("UiAssets"))
local UiLayout = require(Shared:WaitForChild("UiLayout"))

local IndexWindow = {}

export type IndexWindowContext = {
	ModalScrim: Frame,
	OnEquipTrail: (zoneIndex: number) -> (),
}

export type IndexWindowHandle = {
	Frame: Frame,
	Refresh: (state: any) -> (),
}

local ZONE_ICON_KEYS = { "zone_meadow", "zone_crystal", "zone_lava", "zone_frost", "zone_candy" }
local CARD_W, CARD_H = 148, 190
local COLS = 3 -- slime cards per line; a zone's 6 slimes wrap onto two lines
local ROW_H = CARD_H * 2 + 6 + 10 + 30 + 4 -- two card lines + progress bar

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

local function darkCard(frame: GuiObject, radius: number)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	UiKit.AddCorner(frame, radius)
	UiKit.ApplyTri(frame, {
		Light = Color3.fromRGB(44, 46, 55),
		Mid = Color3.fromRGB(36, 37, 45),
		Dark = Color3.fromRGB(27, 28, 34),
	})
	UiKit.AddFrameOutline(frame, 4)
end

type SlimeCard = {
	Def: GameConfig.SlimeDef,
	Button: TextButton,
	Holder: Frame,
	Name: TextLabel,
	Stroke: UIStroke,
	Discovered: boolean?,
}

type ZoneRow = {
	Zone: GameConfig.ZoneDef,
	Stroke: UIStroke,
	Pct: TextLabel,
	Bar: UiKit.ProgressBarParts,
}

function IndexWindow.Build(parent: Instance, ctx: IndexWindowContext): IndexWindowHandle
	local win = UiKit.CreateWindow({
		Name = "SlimeIndexModal",
		Parent = parent,
		Title = "Slime Index",
		Size = UDim2.fromOffset(960, 540),
		Position = UDim2.fromScale(0.5, 0.52),
		Header = {
			Light = Color3.fromRGB(242, 122, 255),
			Mid = Color3.fromRGB(194, 60, 240),
			Dark = Color3.fromRGB(122, 31, 200),
		},
	})
	local modal = win.Frame
	win.Close.Activated:Connect(function()
		UiKit.ToggleModalAnimated(modal, ctx.ModalScrim, false)
	end)
	local body = win.Body

	-- Left: zone rows
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Zones"
	scroll.Position = UDim2.fromOffset(16, 12)
	scroll.Size = UDim2.new(0, 640, 1, -12 - 12 - 56)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = body
	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.Padding = UDim.new(0, 12)
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Parent = scroll
	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop = UDim.new(0, 3)
	scrollPad.PaddingLeft = UDim.new(0, 3)
	scrollPad.PaddingRight = UDim.new(0, 10)
	scrollPad.PaddingBottom = UDim.new(0, 4)
	scrollPad.Parent = scroll

	-- Footer: book icon + "Unlocked X/15" with a green fill
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.Position = UDim2.new(0, 16, 1, -62)
	footer.Size = UDim2.fromOffset(640, 50)
	footer.Parent = body
	darkCard(footer, 16)
	local bookIcon = UiKit.CreateIcon(footer, "index", 34)
	bookIcon.AnchorPoint = Vector2.new(0, 0.5)
	bookIcon.Position = UDim2.new(0, 12, 0.5, 0)
	local footerBar = UiKit.CreateProgressBar(footer, UDim2.new(1, -64, 0, 28), UiKit.Gradients.Green)
	footerBar.Frame.AnchorPoint = Vector2.new(1, 0.5)
	footerBar.Frame.Position = UDim2.new(1, -12, 0.5, 0)

	-- Right column (270): detail card + trail card
	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	detail.Position = UDim2.new(1, -286, 0, 12)
	detail.Size = UDim2.fromOffset(270, 292)
	detail.Parent = body
	darkCard(detail, 18)

	local previewTile = Instance.new("Frame")
	previewTile.AnchorPoint = Vector2.new(0.5, 0)
	previewTile.Position = UDim2.new(0.5, 0, 0, 10)
	previewTile.Size = UDim2.fromOffset(96, 80)
	previewTile.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	previewTile.Parent = detail
	UiKit.AddCorner(previewTile, 14)
	UiKit.ApplyTri(previewTile, UiKit.Gradients.IconPlate)
	UiKit.AddStroke(previewTile, UiKit.Colors.Ink, 3, Enum.ApplyStrokeMode.Border)
	local previewHolder = Instance.new("Frame")
	previewHolder.Size = UDim2.fromScale(1, 1)
	previewHolder.BackgroundTransparency = 1
	previewHolder.Parent = previewTile

	local detailName = makeLabel(detail, 26, "")
	detailName.Position = UDim2.fromOffset(8, 94)
	detailName.Size = UDim2.new(1, -16, 0, 30)
	local detailMeta = makeLabel(detail, 16, "")
	detailMeta.Position = UDim2.fromOffset(8, 124)
	detailMeta.Size = UDim2.new(1, -16, 0, 20)
	local detailIncome = makeLabel(detail, 20, "")
	detailIncome.Position = UDim2.fromOffset(8, 146)
	detailIncome.Size = UDim2.new(1, -16, 0, 26)
	UiKit.ApplyTri(detailIncome, UiKit.Gradients.Cash)

	local chipGrid = Instance.new("Frame")
	chipGrid.Position = UDim2.fromOffset(10, 180)
	chipGrid.Size = UDim2.new(1, -20, 0, 100)
	chipGrid.BackgroundTransparency = 1
	chipGrid.Parent = detail
	local chipLayout = Instance.new("UIGridLayout")
	chipLayout.CellSize = UDim2.fromOffset(76, 28)
	chipLayout.CellPadding = UDim2.fromOffset(6, 6)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chipGrid

	local trail = Instance.new("Frame")
	trail.Name = "Trail"
	trail.Position = UDim2.new(1, -286, 0, 316)
	trail.Size = UDim2.fromOffset(270, 134)
	trail.Parent = body
	darkCard(trail, 18)
	local trailIconPlate = UiKit.CreateIconPlate(trail, "zone_meadow", 56)
	trailIconPlate.Position = UDim2.fromOffset(12, 10)
	local trailIcon = trailIconPlate:FindFirstChildOfClass("ImageLabel") :: ImageLabel
	local trailName = makeLabel(trail, 21, "", Enum.TextXAlignment.Left)
	trailName.Position = UDim2.fromOffset(78, 10)
	trailName.Size = UDim2.new(1, -88, 0, 28)
	local trailBonus = makeLabel(trail, 17, "", Enum.TextXAlignment.Left)
	trailBonus.Position = UDim2.fromOffset(78, 38)
	trailBonus.Size = UDim2.new(1, -88, 0, 24)
	UiKit.ApplyTri(trailBonus, UiKit.Gradients.Cash)
	local trailBtn = UiKit.CreateGradientButton({
		Name = "TrailEquipBtn",
		Parent = trail,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, 50),
		Kind = "grey",
		CornerRadius = 14,
		Text = "LOCKED",
		TextSize = 24,
	})
	local trailBtnLabel = trailBtn:FindFirstChild("Label", true) :: TextLabel

	-- Build zone rows and slime cards once
	local cards: { [string]: SlimeCard } = {}
	local zoneRows: { ZoneRow } = {}
	local selectedSlime: GameConfig.SlimeDef? = GameConfig.Slimes[1]
	local lastState: any = {}
	local refreshDetail: () -> () = function() end
	local lastDetailSignature = ""

	for _, zone in GameConfig.Zones do
		local pool = GameConfig.SlimesByZone[zone.Index] or {}
		local zoneTone = UiKit.TriFromColor(SlimeFactory.ToColor3(zone.ThemeColor), 0.35, 0.3)

		local row = Instance.new("Frame")
		row.Name = "Zone_" .. zone.Index
		row.LayoutOrder = zone.Index
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.BackgroundTransparency = 1
		row.Parent = scroll

		local zCard = Instance.new("Frame")
		zCard.Size = UDim2.fromOffset(132, ROW_H)
		zCard.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		zCard.Parent = row
		UiKit.AddCorner(zCard, 18)
		UiKit.ApplyTri(zCard, zoneTone)
		local zStroke = UiKit.AddFrameOutline(zCard, 4)
		UiKit.AddBevel(zCard, 18)
		UiKit.AddGloss(zCard, 18)
		local zIcon: GuiObject
		if ZONE_ICON_KEYS[zone.Index] then
			zIcon = UiKit.CreateIcon(zCard, ZONE_ICON_KEYS[zone.Index], 78)
		else
			-- zones without an icon asset yet (Desert Dunes, Acid Swamp) show their emoji
			local emoji = Instance.new("TextLabel")
			emoji.Size = UDim2.fromOffset(78, 78)
			emoji.BackgroundTransparency = 1
			emoji.Text = zone.Emoji
			emoji.TextSize = 60
			emoji.Parent = zCard
			zIcon = emoji
		end
		zIcon.AnchorPoint = Vector2.new(0.5, 0)
		zIcon.Position = UDim2.new(0.5, 0, 0, ROW_H * 0.5 - 60)
		zIcon.ZIndex = 3
		local zName = makeLabel(zCard, 22, zone.Name)
		zName.Position = UDim2.fromOffset(4, 14)
		zName.Size = UDim2.new(1, -8, 0, 28)
		zName.ZIndex = 3
		local zPct = makeLabel(zCard, 26, "0%")
		zPct.Position = UDim2.fromOffset(4, ROW_H * 0.5 + 40)
		zPct.Size = UDim2.new(1, -8, 0, 34)
		zPct.ZIndex = 3

		for idx, sDef in pool do
			local btn = Instance.new("TextButton")
			btn.Name = "Slime_" .. sDef.Id
			btn.AutoButtonColor = false
			btn.Text = ""
			btn.Position = UDim2.fromOffset(140 + ((idx - 1) % COLS) * (CARD_W + 6), ((idx - 1) // COLS) * (CARD_H + 6))
			btn.Size = UDim2.fromOffset(CARD_W, CARD_H)
			btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			btn.Parent = row
			UiKit.AddCorner(btn, 16)
			UiKit.ApplyTri(btn, UiKit.TriFromColor(SlimeFactory.GetRarityColor(sDef.Rarity), 0.4, 0.3))
			local stroke = UiKit.AddFrameOutline(btn, 4)
			UiKit.AddBevel(btn, 16)
			UiKit.AddGloss(btn, 16)

			local holder = Instance.new("Frame")
			holder.AnchorPoint = Vector2.new(0.5, 0)
			holder.Position = UDim2.new(0.5, 0, 0, 34)
			holder.Size = UDim2.fromOffset(110, 100)
			holder.BackgroundTransparency = 1
			holder.Parent = btn

			local nameLbl = makeLabel(btn, 22, "???")
			nameLbl.Position = UDim2.fromOffset(4, 6)
			nameLbl.Size = UDim2.new(1, -8, 0, 28)
			nameLbl.ZIndex = 3
			local rarityLbl = makeLabel(btn, 16, sDef.Rarity)
			rarityLbl.Position = UDim2.fromOffset(4, 150)
			rarityLbl.Size = UDim2.new(1, -8, 0, 24)
			rarityLbl.ZIndex = 3

			local card: SlimeCard = { Def = sDef, Button = btn, Holder = holder, Name = nameLbl, Stroke = stroke, Discovered = nil }
			cards[sDef.Id] = card
			btn.Activated:Connect(function()
				selectedSlime = sDef
				refreshDetail()
			end)
		end

		local bar = UiKit.CreateProgressBar(row, UDim2.fromOffset(CARD_W * COLS + 6 * (COLS - 1), 30), UiKit.Gradients.Green)
		bar.Frame.Position = UDim2.fromOffset(140, CARD_H * 2 + 16)

		table.insert(zoneRows, { Zone = zone, Stroke = zStroke, Pct = zPct, Bar = bar })
	end

	local function zoneStats(zone: GameConfig.ZoneDef, discovered: any): (number, number)
		local pool = GameConfig.SlimesByZone[zone.Index] or {}
		local n = 0
		for _, s in pool do
			if discovered[s.Id] then
				n += 1
			end
		end
		return n, #pool
	end

	refreshDetail = function()
		local def = selectedSlime
		if not def then
			return
		end
		local discovered = lastState.DiscoveredSlimes or {}
		local known = discovered[def.Id] == true
		for id, card in cards do
			card.Stroke.Color = if id == def.Id then UiKit.Colors.Gold else UiKit.Colors.Ink
		end

		local foundKey = {}
		for _, list in { lastState.UnplacedSlimes or {}, lastState.PlacedSlimes or {} } do
			for _, inst in list do
				if type(inst) == "table" and inst.SlimeId == def.Id and inst.Mutation then
					table.insert(foundKey, inst.Mutation)
				end
			end
		end
		table.sort(foundKey)
		local zoneForKey = GameConfig.Zones[def.ZoneIndex]
		local zn0, zt0 = zoneStats(zoneForKey, discovered)
		local signature = `{def.Id}|{known}|{table.concat(foundKey, ",")}|{zn0}/{zt0}|{lastState.EquippedTrailZone}`
		if signature == lastDetailSignature then
			return
		end
		lastDetailSignature = signature

		previewHolder:ClearAllChildren()
		UiKit.CreateSlimeViewport(previewHolder, def.Id, "NORMAL", not known)
		detailName.Text = if known then def.Name else "???"
		local totalWeight = 0
		for _, s in GameConfig.SlimesByZone[def.ZoneIndex] or {} do
			totalWeight += s.DropWeight
		end
		local zone = GameConfig.Zones[def.ZoneIndex]
		detailMeta.Text = `{def.Rarity} · {UiLayout.ChancePercent(def.DropWeight, totalWeight)}% in {zone.Name}`
		detailIncome.Text = if known then `${GameConfig.FormatNumber(def.IncomePerSec)}/s  +{def.ThrowBonus} Power` else "Not found yet"

		-- Mutation chips: found = mutation colour (you hold one of this slime with it), otherwise "?"
		local foundMutations: { [string]: boolean } = {}
		for _, list in { lastState.UnplacedSlimes or {}, lastState.PlacedSlimes or {} } do
			for _, inst in list do
				if type(inst) == "table" and inst.SlimeId == def.Id and inst.Mutation then
					foundMutations[inst.Mutation] = true
				end
			end
		end
		for _, c in chipGrid:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for i, mut in GameConfig.Mutations do
			local chip = Instance.new("Frame")
			chip.LayoutOrder = i
			chip.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			chip.Parent = chipGrid
			UiKit.AddCorner(chip, 10)
			local isFound = foundMutations[mut.Id] == true or (mut.Id == "NORMAL" and known)
			local color = Color3.fromRGB(mut.Color[1], mut.Color[2], mut.Color[3])
			UiKit.ApplyTri(chip, if isFound then UiKit.TriFromColor(color, 0.3, 0.45) else UiKit.Gradients.IconPlate)
			UiKit.AddStroke(chip, UiKit.Colors.Ink, 2.5, Enum.ApplyStrokeMode.Border)
			local lbl = makeLabel(chip, 13, if isFound then (if mut.Id == "NORMAL" then "NORMAL" else mut.Name) else "?")
			lbl.Size = UDim2.fromScale(1, 1)
		end

		-- Trail card for this slime's zone
		local zi = def.ZoneIndex
		local z = GameConfig.Zones[zi]
		local zn, zt = zoneStats(z, discovered)
		local complete = zt > 0 and zn >= zt
		local equipped = lastState.EquippedTrailZone == zi
		trailIcon.Image = (UiAssets.Icons :: any)[ZONE_ICON_KEYS[zi] or ""] or ""
		trailName.Text = z.TrailName
		trailBonus.Text = z.TrailBonusText
		if equipped then
			UiKit.SetButtonTone(trailBtn, UiKit.Gradients.Blue, 0)
			trailBtnLabel.Text = "EQUIPPED"
		elseif complete then
			UiKit.SetButtonTone(trailBtn, UiKit.Gradients.Green, 0)
			trailBtnLabel.Text = "EQUIP"
		else
			UiKit.SetButtonTone(trailBtn, UiKit.Gradients.Grey, 0)
			trailBtnLabel.Text = `LOCKED ({zn}/{zt})`
		end
		trailBtn:SetAttribute("ZoneIndex", zi)
		trailBtn:SetAttribute("CanEquip", complete and not equipped)
	end

	trailBtn.Activated:Connect(function()
		if trailBtn:GetAttribute("CanEquip") == true then
			ctx.OnEquipTrail(trailBtn:GetAttribute("ZoneIndex") :: number)
		end
	end)

	local function refresh(state: any)
		lastState = state
		local discovered = state.DiscoveredSlimes or {}
		local total = 0
		for _ in discovered do
			total += 1
		end
		footerBar.SetFraction(total / math.max(1, #GameConfig.Slimes))
		footerBar.Label.Text = `Unlocked: {total}/{#GameConfig.Slimes}`

		for id, card in cards do
			local known = discovered[id] == true
			if card.Discovered ~= known then
				card.Discovered = known
				card.Holder:ClearAllChildren()
				UiKit.CreateSlimeViewport(card.Holder, id, "NORMAL", not known)
				card.Name.Text = if known then card.Def.ShortWord else "???"
			end
		end
		for _, zr in zoneRows do
			local n, t = zoneStats(zr.Zone, discovered)
			zr.Pct.Text = `{if t > 0 then math.floor(n / t * 100 + 0.5) else 0}%`
			zr.Bar.SetFraction(if t > 0 then n / t else 0)
			zr.Bar.Label.Text = `{n}/{t}`
			-- complete zone: gold frame
			zr.Stroke.Color = if t > 0 and n >= t then UiKit.Colors.Gold else UiKit.Colors.Ink
		end
		refreshDetail()
	end

	return { Frame = modal, Refresh = refresh }
end

return IndexWindow
