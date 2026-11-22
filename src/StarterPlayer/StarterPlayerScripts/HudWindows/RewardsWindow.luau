--!strict
--[[
	RewardsWindow.luau
	Rewards & Quests modal (docs/docs/UI-MOCKUP-SPEC.md 3c, 4d). Built only from UiKit.
	- Daily tab: "Daily Login · Day N" + reset countdown, 7 day tiles (claimed / today / future / Day 7 epic),
	  3 daily quest cards with progress bars and CLAIM.
	- Quest Line tab: 12-segment track, hero card for the current step (glows when claimable),
	  "COMING UP" preview cards with lock plates, and an "All quests done!" card after step 12.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local QuestLogic = require(Shared:WaitForChild("QuestLogic"))
local UiAssets = require(Shared:WaitForChild("UiAssets"))
local UiKit = require(Shared:WaitForChild("UiKit"))
local UiLayout = require(Shared:WaitForChild("UiLayout"))

local RewardsWindow = {}

export type RewardsWindowContext = {
	ModalScrim: Frame,
	OnClaimDaily: () -> (),
	OnClaimQuest: (kind: "Line" | "Daily", index: number?) -> (),
}

export type RewardsWindowHandle = {
	Frame: Frame,
	Refresh: (state: any) -> boolean,
}

local CARD_TONE: UiKit.Tri = {
	Light = Color3.fromRGB(44, 46, 55),
	Mid = Color3.fromRGB(36, 37, 45),
	Dark = Color3.fromRGB(27, 28, 34),
}
local DARK_TONE: UiKit.Tri = {
	Light = Color3.fromRGB(58, 61, 76),
	Mid = Color3.fromRGB(48, 50, 65),
	Dark = Color3.fromRGB(38, 40, 54),
}

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

local function makeCard(parent: Instance, radius: number, tone: UiKit.Tri?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	f.Parent = parent
	UiKit.AddCorner(f, radius)
	UiKit.ApplyTri(f, tone or CARD_TONE)
	UiKit.AddFrameOutline(f, 4)
	return f
end

-- Reward chips ("+15" + gem icon, "+$250" + cash icon), right aligned. Rebuilt only when the reward changes.
local function makeRewardChips(parent: Instance, textSize: number): (Frame, (reward: GameConfig.QuestReward) -> ())
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	local lastKey = ""
	local function set(reward: GameConfig.QuestReward)
		local key = `{reward.Gems or 0}|{reward.Cash or 0}`
		if key == lastKey then
			return
		end
		lastKey = key
		for _, c in holder:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local order = 0
		local function chip(text: string, icon: string, tone: UiKit.Tri)
			order += 1
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.AutomaticSize = Enum.AutomaticSize.X
			row.Size = UDim2.fromOffset(0, textSize + 8)
			row.LayoutOrder = order
			row.Parent = holder
			local rl = Instance.new("UIListLayout")
			rl.FillDirection = Enum.FillDirection.Horizontal
			rl.VerticalAlignment = Enum.VerticalAlignment.Center
			rl.Padding = UDim.new(0, 4)
			rl.Parent = row
			local t = makeLabel(row, textSize, text)
			t.AutomaticSize = Enum.AutomaticSize.X
			t.Size = UDim2.fromOffset(0, textSize + 8)
			t.LayoutOrder = 1
			UiKit.ApplyTri(t, tone)
			local ic = UiKit.CreateIcon(row, icon, textSize + 6)
			ic.LayoutOrder = 2
		end
		if reward.Gems and reward.Gems > 0 then
			chip(`+{GameConfig.FormatNumber(reward.Gems)}`, "gem", UiKit.Gradients.Gems)
		end
		if reward.Cash and reward.Cash > 0 then
			chip(`+${GameConfig.FormatNumber(reward.Cash)}`, "cash", UiKit.Gradients.Cash)
		end
	end
	return holder, set
end

function RewardsWindow.Build(parent: Instance, ctx: RewardsWindowContext): RewardsWindowHandle
	local win = UiKit.CreateWindow({
		Name = "RewardsModal",
		Parent = parent,
		Title = "Rewards & Quests",
		Size = UDim2.fromOffset(960, 540),
		Position = UDim2.fromScale(0.5, 0.52),
		Header = {
			Light = Color3.fromRGB(143, 214, 255),
			Mid = Color3.fromRGB(62, 162, 255),
			Dark = Color3.fromRGB(26, 111, 224),
		},
	})
	local modal = win.Frame
	win.Close.Activated:Connect(function()
		UiKit.ToggleModalAnimated(modal, ctx.ModalScrim, false)
	end)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(20, 14)
	content.Size = UDim2.new(1, -40, 1, -28)
	content.BackgroundTransparency = 1
	content.Parent = win.Body

	local dailyPage = Instance.new("Frame")
	dailyPage.Name = "DailyPage"
	dailyPage.Position = UDim2.fromOffset(0, 62)
	dailyPage.Size = UDim2.new(1, 0, 1, -62)
	dailyPage.BackgroundTransparency = 1
	dailyPage.Parent = content
	local linePage = Instance.new("Frame")
	linePage.Name = "QuestLinePage"
	linePage.Position = UDim2.fromOffset(0, 62)
	linePage.Size = UDim2.new(1, 0, 1, -62)
	linePage.BackgroundTransparency = 1
	linePage.Visible = false
	linePage.Parent = content

	local tabs = UiKit.CreateTabs(content, {
		{ Id = "Daily", Text = "Daily Rewards", Icon = "calendar", Gradient = UiKit.Gradients.Blue },
		{ Id = "Line", Text = "Quest Line", Icon = "trophy", Gradient = UiKit.Gradients.SlimesNav },
	}, function(id: string)
		dailyPage.Visible = id == "Daily"
		linePage.Visible = id == "Line"
	end)
	tabs.Frame.Position = UDim2.fromOffset(0, 0)

	-- ============================================================================
	-- DAILY TAB
	-- ============================================================================
	local sectionLabel = makeLabel(dailyPage, 24, "Daily Login · Day 1", Enum.TextXAlignment.Left)
	sectionLabel.Position = UDim2.fromOffset(4, 0)
	sectionLabel.Size = UDim2.fromOffset(400, 30)
	local clockIcon = UiKit.CreateIcon(dailyPage, "clock", 26)
	clockIcon.AnchorPoint = Vector2.new(1, 0)
	clockIcon.Position = UDim2.new(1, -176, 0, 2)
	local countdownLabel = makeLabel(dailyPage, 18, "Resets in 24h 00m", Enum.TextXAlignment.Right)
	countdownLabel.AnchorPoint = Vector2.new(1, 0)
	countdownLabel.Position = UDim2.new(1, -4, 0, 2)
	countdownLabel.Size = UDim2.fromOffset(170, 26)
	countdownLabel.TextColor3 = Color3.fromRGB(215, 225, 240)

	local strip = Instance.new("Frame")
	strip.Position = UDim2.fromOffset(0, 36)
	strip.Size = UDim2.new(1, 0, 0, 124)
	strip.BackgroundTransparency = 1
	strip.Parent = dailyPage
	local stripLayout = Instance.new("UIListLayout")
	stripLayout.FillDirection = Enum.FillDirection.Horizontal
	stripLayout.Padding = UDim.new(0, 8)
	stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stripLayout.Parent = strip

	type DayTile = {
		Frame: Frame,
		Stroke: UIStroke,
		Check: ImageLabel,
		Glow: ImageLabel,
		Gem: ImageLabel,
		Claim: TextButton,
		Tone: UiKit.Tri,
	}
	local dayTiles: { DayTile } = {}
	local dayCount = #GameConfig.Gems.DailyRewards
	for i, gems in GameConfig.Gems.DailyRewards do
		local isEpic = i == dayCount
		local tile = Instance.new("Frame")
		tile.Name = `DayTile_{i}`
		tile.LayoutOrder = i
		tile.Size = UDim2.new(1 / dayCount, -7, 0, 124)
		tile.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		tile.Parent = strip
		UiKit.AddCorner(tile, 16)
		local tone = if isEpic then UiKit.Gradients.SlimesNav else DARK_TONE
		UiKit.ApplyTri(tile, tone)
		local stroke = UiKit.AddFrameOutline(tile, 4)

		local glow = Instance.new("ImageLabel")
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.new(1, 50, 1, 50)
		glow.BackgroundTransparency = 1
		glow.Image = UiAssets.Textures.glow
		glow.ImageColor3 = Color3.fromRGB(255, 225, 74)
		glow.ImageTransparency = 1
		glow.ZIndex = 0
		glow.Parent = tile

		local dayLbl = makeLabel(tile, 17, `DAY {i}`)
		dayLbl.Position = UDim2.fromOffset(0, 6)
		dayLbl.Size = UDim2.new(1, 0, 0, 22)
		UiKit.ApplyTri(dayLbl, UiKit.Gradients.Luck)

		local gem = UiKit.CreateIcon(tile, "gem", if isEpic then 60 else 44)
		gem.AnchorPoint = Vector2.new(0.5, 0)
		gem.Position = UDim2.new(0.5, 0, 0, if isEpic then 26 else 32)
		local amount = makeLabel(tile, 20, `+{gems}`)
		amount.Position = UDim2.fromOffset(0, 80)
		amount.Size = UDim2.new(1, 0, 0, 24)
		UiKit.ApplyTri(amount, UiKit.Gradients.Gems)

		local check = UiKit.CreateIcon(tile, "check", 30)
		check.AnchorPoint = Vector2.new(1, 0)
		check.Position = UDim2.new(1, -4, 0, 2)
		check.Visible = false
		check.ZIndex = 5

		local claim = UiKit.CreateGradientButton({
			Name = "ClaimDailyBtn",
			Parent = tile,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -14, 0, 30),
			Kind = "green",
			CornerRadius = 10,
			Text = "CLAIM!",
			TextSize = 16,
			OnClick = ctx.OnClaimDaily,
		})
		claim.Visible = false
		claim.ZIndex = 6

		dayTiles[i] = { Frame = tile, Stroke = stroke, Check = check, Glow = glow, Gem = gem, Claim = claim, Tone = tone }
	end

	-- 3 daily quest cards
	local questHolder = Instance.new("Frame")
	questHolder.Position = UDim2.fromOffset(0, 172)
	questHolder.Size = UDim2.new(1, 0, 1, -172)
	questHolder.BackgroundTransparency = 1
	questHolder.Parent = dailyPage
	local questLayout = Instance.new("UIListLayout")
	questLayout.Padding = UDim.new(0, 8)
	questLayout.SortOrder = Enum.SortOrder.LayoutOrder
	questLayout.Parent = questHolder

	type QuestCard = {
		Row: Frame,
		Title: TextLabel,
		SetReward: (GameConfig.QuestReward) -> (),
		Bar: UiKit.ProgressBarParts,
		Button: TextButton,
		ButtonLabel: TextLabel,
	}
	local questCards: { QuestCard } = {}
	for i = 1, GameConfig.Quests.DailyCount do
		local row = makeCard(questHolder, 16)
		row.Name = `DailyQuestCard_{i}`
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 62)

		local title = makeLabel(row, 20, "Daily Quest", Enum.TextXAlignment.Left)
		title.Position = UDim2.fromOffset(16, 4)
		title.Size = UDim2.fromOffset(460, 26)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		local bar = UiKit.CreateProgressBar(row, UDim2.fromOffset(500, 22), UiKit.Gradients.Green)
		bar.Frame.Position = UDim2.fromOffset(16, 32)
		bar.Label.TextSize = 15

		local rewardHolder, setReward = makeRewardChips(row, 22)
		rewardHolder.AnchorPoint = Vector2.new(1, 0.5)
		rewardHolder.Position = UDim2.new(1, -190, 0.5, 0)
		rewardHolder.Size = UDim2.fromOffset(180, 34)

		local idx = i
		local btn = UiKit.CreateGradientButton({
			Name = "ClaimBtn",
			Parent = row,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(150, 46),
			Kind = "green",
			CornerRadius = 14,
			Text = "CLAIM!",
			TextSize = 22,
			OnClick = function()
				ctx.OnClaimQuest("Daily", idx)
			end,
		})
		questCards[i] = {
			Row = row,
			Title = title,
			SetReward = setReward,
			Bar = bar,
			Button = btn,
			ButtonLabel = btn:FindFirstChild("Label", true) :: TextLabel,
		}
	end

	-- ============================================================================
	-- QUEST LINE TAB
	-- ============================================================================
	local totalSteps = #GameConfig.Quests.Line
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 24)
	track.BackgroundTransparency = 1
	track.Parent = linePage
	local trackLayout = Instance.new("UIListLayout")
	trackLayout.FillDirection = Enum.FillDirection.Horizontal
	trackLayout.Padding = UDim.new(0, 6)
	trackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trackLayout.Parent = track
	local segments: { Frame } = {}
	local segGlows: { ImageLabel } = {}
	for i = 1, totalSteps do
		local seg = Instance.new("Frame")
		seg.Name = "Seg_" .. i
		seg.LayoutOrder = i
		seg.Size = UDim2.new(1 / totalSteps, -6, 1, 0)
		seg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		seg.Parent = track
		UiKit.AddCorner(seg, 12)
		UiKit.ApplyTri(seg, DARK_TONE)
		UiKit.AddFrameOutline(seg, 3)
		local glow = Instance.new("ImageLabel")
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.new(1, 24, 1, 24)
		glow.BackgroundTransparency = 1
		glow.Image = UiAssets.Textures.glow
		glow.ImageColor3 = Color3.fromRGB(255, 178, 28)
		glow.ImageTransparency = 1
		glow.ZIndex = 0
		glow.Parent = seg
		segments[i] = seg
		segGlows[i] = glow
	end

	-- Hero card (178 high): gold diagonal gradient
	local hero = Instance.new("Frame")
	hero.Name = "CurrentStepCard"
	hero.Position = UDim2.fromOffset(0, 38)
	hero.Size = UDim2.new(1, 0, 0, 178)
	hero.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	hero.Parent = linePage
	UiKit.AddCorner(hero, 20)
	local heroGradient = UiKit.ApplyTri(hero, { Light = Color3.fromRGB(255, 244, 150), Mid = Color3.fromRGB(255, 196, 40), Dark = Color3.fromRGB(226, 128, 10) })
	heroGradient.Rotation = 35
	local heroStroke = UiKit.AddFrameOutline(hero, 4)
	UiKit.AddStripes(hero, 20)
	local heroGlow = Instance.new("ImageLabel")
	heroGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	heroGlow.Position = UDim2.fromScale(0.5, 0.5)
	heroGlow.Size = UDim2.new(1, 90, 1, 90)
	heroGlow.BackgroundTransparency = 1
	heroGlow.Image = UiAssets.Textures.glow
	heroGlow.ImageColor3 = Color3.fromRGB(255, 255, 255)
	heroGlow.ImageTransparency = 1
	heroGlow.ZIndex = 0
	heroGlow.Parent = hero

	local heroIconPlate = UiKit.CreateIconPlate(hero, "target", 96)
	heroIconPlate.Position = UDim2.fromOffset(18, 20)
	local stepBadge = makeLabel(hero, 20, "STEP 1 / 12", Enum.TextXAlignment.Left)
	stepBadge.Position = UDim2.fromOffset(130, 12)
	stepBadge.Size = UDim2.fromOffset(260, 26)
	local heroTitle = makeLabel(hero, 32, "Quest", Enum.TextXAlignment.Left)
	heroTitle.Position = UDim2.fromOffset(130, 38)
	heroTitle.Size = UDim2.new(1, -150, 0, 42)
	heroTitle.TextTruncate = Enum.TextTruncate.AtEnd
	local heroBar = UiKit.CreateProgressBar(hero, UDim2.new(1, -350, 0, 30), UiKit.Gradients.Green)
	heroBar.Frame.Position = UDim2.fromOffset(130, 90)
	heroBar.Label.TextSize = 18
	local rewardKicker = makeLabel(hero, 16, "REWARD", Enum.TextXAlignment.Left)
	rewardKicker.Position = UDim2.fromOffset(130, 128)
	rewardKicker.Size = UDim2.fromOffset(80, 30)
	local heroRewardHolder, setHeroReward = makeRewardChips(hero, 26)
	heroRewardHolder.Position = UDim2.fromOffset(212, 126)
	heroRewardHolder.Size = UDim2.fromOffset(240, 34)
	local heroRewardLayout = heroRewardHolder:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	heroRewardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local heroClaim = UiKit.CreateGradientButton({
		Name = "ClaimLineQuestBtn",
		Parent = hero,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -16),
		Size = UDim2.fromOffset(150, 70),
		Kind = "green",
		CornerRadius = 18,
		Text = "CLAIM!",
		TextSize = 28,
		OnClick = function()
			ctx.OnClaimQuest("Line", nil)
		end,
	})
	local heroClaimLabel = heroClaim:FindFirstChild("Label", true) :: TextLabel

	local comingUp = makeLabel(linePage, 20, "COMING UP", Enum.TextXAlignment.Left)
	comingUp.Position = UDim2.fromOffset(4, 224)
	comingUp.Size = UDim2.fromOffset(200, 24)
	comingUp.TextColor3 = Color3.fromRGB(215, 225, 240)

	type PreviewCard = { Row: Frame, Title: TextLabel, SetReward: (GameConfig.QuestReward) -> () }
	local previews: { PreviewCard } = {}
	for i = 1, 2 do
		local row = makeCard(linePage, 16)
		row.Name = `NextStepPreview_{i}`
		row.Position = UDim2.fromOffset(0, 250 + (i - 1) * 64)
		row.Size = UDim2.new(1, 0, 0, 56)
		row.BackgroundTransparency = 0.3
		local lock = UiKit.CreateIconPlate(row, "lock", 40)
		lock.Position = UDim2.fromOffset(10, 8)
		local title = makeLabel(row, 20, "", Enum.TextXAlignment.Left)
		title.Position = UDim2.fromOffset(62, 0)
		title.Size = UDim2.new(1, -300, 1, 0)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.TextTransparency = 0.3
		local holder, setReward = makeRewardChips(row, 20)
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position = UDim2.new(1, -16, 0.5, 0)
		holder.Size = UDim2.fromOffset(220, 30)
		previews[i] = { Row = row, Title = title, SetReward = setReward }
	end

	local doneCard = makeCard(linePage, 20, UiKit.Gradients.Green)
	doneCard.Name = "AllDoneCard"
	doneCard.Position = UDim2.fromOffset(0, 38)
	doneCard.Size = UDim2.new(1, 0, 0, 178)
	doneCard.Visible = false
	local doneLabel = makeLabel(doneCard, 44, "All quests done!")
	doneLabel.Size = UDim2.fromScale(1, 1)

	-- ============================================================================
	-- REFRESH
	-- ============================================================================
	local function refresh(state: any): boolean
		local canClaimDaily = state.DailyCanClaim == true
		local nextStreakDay = math.clamp(tonumber(state.DailyNextDay) or 1, 1, dayCount)
		local curStreak = math.clamp(tonumber(state.DailyStreak) or 0, 0, dayCount)
		local activeDay = if canClaimDaily then nextStreakDay else math.max(1, curStreak)

		sectionLabel.Text = `Daily Login · Day {activeDay}`
		countdownLabel.Text = UiLayout.FormatCountdown(tonumber(state.SecondsUntilNextDay) or 0)

		for i, t in dayTiles do
			local isClaimed = (canClaimDaily and i < activeDay) or (not canClaimDaily and i <= curStreak)
			local isToday = canClaimDaily and i == activeDay
			t.Check.Visible = isClaimed
			t.Claim.Visible = isToday
			t.Glow.ImageTransparency = if isToday then 0.45 else 1
			t.Gem.ImageTransparency = if isClaimed then 0.45 else 0
			if isToday then
				UiKit.SetTone(t.Frame, UiKit.Gradients.Luck)
				t.Frame.BackgroundTransparency = 0
				t.Stroke.Color = UiKit.Colors.White
			elseif isClaimed then
				UiKit.SetTone(t.Frame, t.Tone)
				t.Frame.BackgroundTransparency = 0.45
				t.Stroke.Color = UiKit.Colors.Ink
			else
				UiKit.SetTone(t.Frame, t.Tone)
				t.Frame.BackgroundTransparency = if i == dayCount then 0 else 0.2
				t.Stroke.Color = UiKit.Colors.Ink
			end
		end

		-- Daily quests
		local dailyList = if type(state.DailyQuests) == "table" then state.DailyQuests else {}
		for i, card in questCards do
			local slot = dailyList[i]
			local def = if slot and type(slot.Id) == "string" then GameConfig.QuestsById[slot.Id] else nil
			if slot and def then
				card.Row.Visible = true
				local prog = math.clamp(tonumber(slot.Progress) or 0, 0, def.Target)
				local ratio = if def.Target > 0 then prog / def.Target else 0
				card.Title.Text = def.Title
				card.SetReward(def.Reward)
				card.Bar.SetFraction(ratio)
				card.Bar.Label.Text = `{GameConfig.FormatNumber(prog)} / {GameConfig.FormatNumber(def.Target)}`
				if slot.Claimed == true then
					UiKit.SetButtonTone(card.Button, UiKit.Gradients.Grey, 0.3)
					card.ButtonLabel.Text = "CLAIMED"
				elseif prog >= def.Target then
					UiKit.SetButtonTone(card.Button, UiKit.Gradients.Green, 0)
					card.ButtonLabel.Text = "CLAIM!"
				else
					UiKit.SetButtonTone(card.Button, UiKit.Gradients.Grey, 0.4)
					card.ButtonLabel.Text = "CLAIM!"
				end
			else
				card.Row.Visible = false
			end
		end

		-- Quest line
		local step = tonumber(state.QuestLineStep) or 1
		local curDef = GameConfig.Quests.Line[step]
		for i, seg in segments do
			local st = UiLayout.TrackState(i, step)
			UiKit.SetTone(seg, if st == "done" then UiKit.Gradients.Green elseif st == "current" then UiKit.Gradients.Orange else DARK_TONE)
			segGlows[i].ImageTransparency = if st == "current" then 0.4 else 1
		end
		hero.Visible = curDef ~= nil
		doneCard.Visible = curDef == nil
		for i, p in previews do
			local nextDef = GameConfig.Quests.Line[step + i]
			p.Row.Visible = nextDef ~= nil and curDef ~= nil
			if nextDef then
				p.Title.Text = `Step {step + i}: {nextDef.Title}`
				p.SetReward(nextDef.Reward)
			end
		end
		comingUp.Visible = curDef ~= nil and GameConfig.Quests.Line[step + 1] ~= nil
		if curDef then
			local prog = math.clamp(tonumber(state.QuestLineProgress) or 0, 0, curDef.Target)
			local ratio = if curDef.Target > 0 then prog / curDef.Target else 0
			local claimable = prog >= curDef.Target
			stepBadge.Text = `STEP {step} / {totalSteps}`
			heroTitle.Text = curDef.Title
			setHeroReward(curDef.Reward)
			heroBar.SetFraction(ratio)
			heroBar.Label.Text = `{GameConfig.FormatNumber(prog)} / {GameConfig.FormatNumber(curDef.Target)}`
			UiKit.SetButtonTone(heroClaim, if claimable then UiKit.Gradients.Green else UiKit.Gradients.Grey, if claimable then 0 else 0.4)
			heroClaimLabel.Text = "CLAIM!"
			heroStroke.Color = if claimable then UiKit.Colors.White else UiKit.Colors.Ink
			heroGlow.ImageTransparency = if claimable then 0.5 else 1
		end

		return canClaimDaily or QuestLogic.HasAnyClaimableQuest(state)
	end

	tabs.Select("Daily")

	return { Frame = modal, Refresh = refresh }
end

return RewardsWindow
