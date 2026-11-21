--!strict
--[[
	RewardsWindow.luau
	Two-tab Rewards & Quests modal:
	- Tab 1 (Daily): 7-Day Daily Reward Calendar strip on top (ticked claimed days, glowing today with CLAIM,
	  dimmed future days, "Resets in HH:MM" countdown) + 3 Daily Quest cards with progress bars below.
	- Tab 2 (Quest Line): Current step card large with progress bar + CLAIM, plus the next 2 steps dimmed below.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local QuestLogic = require(Shared:WaitForChild("QuestLogic"))
local UiKit = require(Shared:WaitForChild("UiKit"))

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

local function formatRewardText(reward: GameConfig.QuestReward): string
	local parts = {}
	if reward.Gems and reward.Gems > 0 then
		table.insert(parts, `💎 +{GameConfig.FormatNumber(reward.Gems)}`)
	end
	if reward.Cash and reward.Cash > 0 then
		table.insert(parts, `💵 +${GameConfig.FormatNumber(reward.Cash)}`)
	end
	return table.concat(parts, "  ")
end

local function formatCountdown(seconds: number): string
	local clean = math.max(0, math.floor(seconds))
	local hrs = math.floor(clean / 3600)
	local mins = math.floor((clean % 3600) / 60)
	return string.format("Resets in %02dh %02dm", hrs, mins)
end

function RewardsWindow.Build(parent: Instance, ctx: RewardsWindowContext): RewardsWindowHandle
	local addCorner = UiKit.AddCorner
	local addStroke = UiKit.AddStroke

	local modal = Instance.new("Frame")
	modal.Name = "RewardsModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(660, 450)
	modal.BackgroundColor3 = Color3.fromRGB(34, 38, 46)
	modal.Visible = false
	modal.ZIndex = 10
	modal.Parent = parent
	addCorner(modal, 14)
	addStroke(modal, Color3.fromRGB(15, 18, 24), 3.2, Enum.ApplyStrokeMode.Border)

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 54)
	header.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	header.Parent = modal
	addCorner(header, 14)
	UiKit.AddGlossGradient(header, Color3.fromRGB(245, 155, 45))
	addStroke(header, Color3.fromRGB(32, 18, 10), 2.2, Enum.ApplyStrokeMode.Border)

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(18, 6)
	title.Size = UDim2.fromOffset(320, 40)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 28
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "🎁 Rewards & Quests"
	title.Parent = header
	addStroke(title, Color3.fromRGB(28, 16, 8), 2.5)

	UiKit.CreateBevelButton({
		Name = "CloseBtn",
		Parent = header,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 1),
		Size = UDim2.fromOffset(40, 40),
		Color = Color3.fromRGB(235, 55, 65),
		CornerRadius = 9,
		Text = "X",
		TextSize = 22,
		OnClick = function()
			UiKit.ToggleModalAnimated(modal, ctx.ModalScrim, false)
		end,
	})

	-- Tab Bar
	local dailyPage = Instance.new("Frame")
	local linePage = Instance.new("Frame")

	local _, dailyTabFace = UiKit.CreateBevelButton({
		Name = "DailyTabBtn",
		Parent = modal,
		Position = UDim2.fromOffset(16, 62),
		Size = UDim2.fromOffset(195, 38),
		Color = Color3.fromRGB(70, 195, 255),
		CornerRadius = 10,
		Text = "📅 Daily Rewards",
		TextSize = 19,
		OnClick = function()
			dailyPage.Visible = true
			linePage.Visible = false
		end,
	})

	local _, lineTabFace = UiKit.CreateBevelButton({
		Name = "QuestLineTabBtn",
		Parent = modal,
		Position = UDim2.fromOffset(222, 62),
		Size = UDim2.fromOffset(195, 38),
		Color = Color3.fromRGB(165, 95, 245),
		CornerRadius = 10,
		Text = "🏆 Quest Line",
		TextSize = 19,
		OnClick = function()
			dailyPage.Visible = false
			linePage.Visible = true
		end,
	})
	local _ = dailyTabFace
	local _ = lineTabFace

	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.AnchorPoint = Vector2.new(1, 0)
	countdownLabel.Position = UDim2.new(1, -18, 0, 68)
	countdownLabel.Size = UDim2.fromOffset(200, 26)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Font = Enum.Font.FredokaOne
	countdownLabel.TextSize = 18
	countdownLabel.TextXAlignment = Enum.TextXAlignment.Right
	countdownLabel.TextColor3 = Color3.fromRGB(200, 215, 235)
	countdownLabel.Text = "Resets in 24h 00m"
	countdownLabel.Parent = modal
	addStroke(countdownLabel, Color3.fromRGB(15, 18, 25), 1.8)

	-- ============================================================================
	-- TAB 1: DAILY PAGE (7-Tile Calendar on top + 3 Daily Quests below)
	-- ============================================================================
	dailyPage.Name = "DailyPage"
	dailyPage.Position = UDim2.fromOffset(14, 108)
	dailyPage.Size = UDim2.new(1, -28, 1, -120)
	dailyPage.BackgroundTransparency = 1
	dailyPage.Visible = true
	dailyPage.Parent = modal

	local calendarCard = Instance.new("Frame")
	calendarCard.Name = "CalendarCard"
	calendarCard.Size = UDim2.new(1, 0, 0, 126)
	calendarCard.BackgroundColor3 = Color3.fromRGB(26, 30, 38)
	calendarCard.Parent = dailyPage
	addCorner(calendarCard, 12)
	addStroke(calendarCard, Color3.fromRGB(16, 18, 24), 2.2, Enum.ApplyStrokeMode.Border)

	local stripFrame = Instance.new("Frame")
	stripFrame.Position = UDim2.fromOffset(10, 10)
	stripFrame.Size = UDim2.new(1, -155, 0, 106)
	stripFrame.BackgroundTransparency = 1
	stripFrame.Parent = calendarCard

	local stripLayout = Instance.new("UIListLayout")
	stripLayout.FillDirection = Enum.FillDirection.Horizontal
	stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	stripLayout.Padding = UDim.new(0, 6)
	stripLayout.Parent = stripFrame

	type DayTileUI = {
		Frame: Frame,
		Stroke: UIStroke,
		StatusLabel: TextLabel,
	}
	local dayTiles: { DayTileUI } = {}
	for i, gems in GameConfig.Gems.DailyRewards do
		local tile = Instance.new("Frame")
		tile.Name = `DayTile_{i}`
		tile.Size = UDim2.fromOffset(62, 102)
		tile.BackgroundColor3 = Color3.fromRGB(42, 48, 62)
		tile.Parent = stripFrame
		addCorner(tile, 10)
		local stroke = addStroke(tile, Color3.fromRGB(18, 20, 28), 2.2, Enum.ApplyStrokeMode.Border)

		local dayHdr = Instance.new("TextLabel")
		dayHdr.Position = UDim2.fromOffset(2, 6)
		dayHdr.Size = UDim2.new(1, -4, 0, 20)
		dayHdr.BackgroundTransparency = 1
		dayHdr.Font = Enum.Font.FredokaOne
		dayHdr.TextSize = 15
		dayHdr.TextColor3 = Color3.fromRGB(255, 235, 110)
		dayHdr.Text = `DAY {i}`
		dayHdr.Parent = tile
		addStroke(dayHdr, Color3.fromRGB(15, 18, 25), 1.6)

		local gemIcon = Instance.new("TextLabel")
		gemIcon.Position = UDim2.fromOffset(2, 28)
		gemIcon.Size = UDim2.new(1, -4, 0, 42)
		gemIcon.BackgroundTransparency = 1
		gemIcon.Font = Enum.Font.FredokaOne
		gemIcon.TextSize = 19
		gemIcon.TextColor3 = Color3.fromRGB(125, 215, 255)
		gemIcon.Text = `💎\n+{gems}`
		gemIcon.Parent = tile
		addStroke(gemIcon, Color3.fromRGB(15, 18, 25), 1.8)

		local statusLbl = Instance.new("TextLabel")
		statusLbl.Position = UDim2.fromOffset(2, 76)
		statusLbl.Size = UDim2.new(1, -4, 0, 20)
		statusLbl.BackgroundTransparency = 1
		statusLbl.Font = Enum.Font.FredokaOne
		statusLbl.TextSize = 13
		statusLbl.TextColor3 = Color3.fromRGB(180, 190, 210)
		statusLbl.Text = "LOCKED"
		statusLbl.Parent = tile
		addStroke(statusLbl, Color3.fromRGB(15, 18, 25), 1.5)

		dayTiles[i] = {
			Frame = tile,
			Stroke = stroke,
			StatusLabel = statusLbl,
		}
	end

	local _, claimDailyFace, claimDailyLbl = UiKit.CreateBevelButton({
		Name = "ClaimDailyBtn",
		Parent = calendarCard,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 2),
		Size = UDim2.fromOffset(132, 82),
		Color = Color3.fromRGB(85, 235, 85),
		CornerRadius = 11,
		Text = "CLAIM\nTODAY!",
		TextSize = 21,
		OnClick = function()
			ctx.OnClaimDaily()
		end,
	})

	-- Daily Quests Container (3 cards below calendar)
	local dailyQuestsContainer = Instance.new("Frame")
	dailyQuestsContainer.Name = "DailyQuestsContainer"
	dailyQuestsContainer.Position = UDim2.fromOffset(0, 136)
	dailyQuestsContainer.Size = UDim2.new(1, 0, 1, -136)
	dailyQuestsContainer.BackgroundTransparency = 1
	dailyQuestsContainer.Parent = dailyPage

	local dailyQuestsLayout = Instance.new("UIListLayout")
	dailyQuestsLayout.Padding = UDim.new(0, 8)
	dailyQuestsLayout.Parent = dailyQuestsContainer

	type DailyCardUI = {
		Row: Frame,
		TitleLabel: TextLabel,
		RewardLabel: TextLabel,
		BarFill: Frame,
		BarText: TextLabel,
		ButtonFace: Frame,
		ButtonLabel: TextLabel,
	}
	local dailyCards: { DailyCardUI } = {}
	for i = 1, GameConfig.Quests.DailyCount do
		local row = Instance.new("Frame")
		row.Name = `DailyQuestCard_{i}`
		row.Size = UDim2.new(1, 0, 0, 58)
		row.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
		row.Parent = dailyQuestsContainer
		addCorner(row, 10)
		addStroke(row, Color3.fromRGB(16, 18, 24), 2, Enum.ApplyStrokeMode.Border)

		local qTitle = Instance.new("TextLabel")
		qTitle.Position = UDim2.fromOffset(12, 4)
		qTitle.Size = UDim2.fromOffset(320, 24)
		qTitle.BackgroundTransparency = 1
		qTitle.Font = Enum.Font.FredokaOne
		qTitle.TextSize = 18
		qTitle.TextXAlignment = Enum.TextXAlignment.Left
		qTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
		qTitle.Text = "Daily Quest"
		qTitle.Parent = row
		addStroke(qTitle, Color3.fromRGB(15, 18, 25), 1.8)

		local qReward = Instance.new("TextLabel")
		qReward.Position = UDim2.fromOffset(336, 4)
		qReward.Size = UDim2.fromOffset(145, 24)
		qReward.BackgroundTransparency = 1
		qReward.Font = Enum.Font.FredokaOne
		qReward.TextSize = 17
		qReward.TextXAlignment = Enum.TextXAlignment.Right
		qReward.TextColor3 = Color3.fromRGB(120, 215, 255)
		qReward.Text = "💎 +15"
		qReward.Parent = row
		addStroke(qReward, Color3.fromRGB(15, 18, 25), 1.8)

		local barBg = Instance.new("Frame")
		barBg.Position = UDim2.fromOffset(12, 32)
		barBg.Size = UDim2.fromOffset(468, 18)
		barBg.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
		barBg.Parent = row
		addCorner(barBg, 8)

		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.fromScale(0, 1)
		barFill.BackgroundColor3 = Color3.fromRGB(85, 235, 95)
		barFill.Parent = barBg
		addCorner(barFill, 8)

		local barTxt = Instance.new("TextLabel")
		barTxt.Size = UDim2.fromScale(1, 1)
		barTxt.BackgroundTransparency = 1
		barTxt.Font = Enum.Font.FredokaOne
		barTxt.TextSize = 14
		barTxt.TextColor3 = Color3.fromRGB(255, 255, 255)
		barTxt.Text = "0 / 1"
		barTxt.ZIndex = 3
		barTxt.Parent = barBg
		addStroke(barTxt, Color3.fromRGB(12, 14, 18), 1.5)

		local idxCopy = i
		local _, btnFace, btnLbl = UiKit.CreateBevelButton({
			Name = "ClaimBtn",
			Parent = row,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 1),
			Size = UDim2.fromOffset(126, 40),
			Color = Color3.fromRGB(85, 235, 85),
			CornerRadius = 9,
			Text = "CLAIM!",
			TextSize = 18,
			OnClick = function()
				ctx.OnClaimQuest("Daily", idxCopy)
			end,
		})

		dailyCards[i] = {
			Row = row,
			TitleLabel = qTitle,
			RewardLabel = qReward,
			BarFill = barFill,
			BarText = barTxt,
			ButtonFace = btnFace,
			ButtonLabel = btnLbl,
		}
	end

	-- ============================================================================
	-- TAB 2: QUEST LINE PAGE (Current Step Hero Card + Next 2 Preview Cards)
	-- ============================================================================
	linePage.Name = "QuestLinePage"
	linePage.Position = UDim2.fromOffset(14, 108)
	linePage.Size = UDim2.new(1, -28, 1, -120)
	linePage.BackgroundTransparency = 1
	linePage.Visible = false
	linePage.Parent = modal

	local heroCard = Instance.new("Frame")
	heroCard.Name = "CurrentStepCard"
	heroCard.Size = UDim2.new(1, 0, 0, 162)
	heroCard.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	heroCard.Parent = linePage
	addCorner(heroCard, 12)
	UiKit.AddGlossGradient(heroCard, Color3.fromRGB(68, 52, 115))
	addStroke(heroCard, Color3.fromRGB(20, 16, 34), 2.5, Enum.ApplyStrokeMode.Border)

	local stepBadge = Instance.new("TextLabel")
	stepBadge.Position = UDim2.fromOffset(16, 10)
	stepBadge.Size = UDim2.fromOffset(220, 26)
	stepBadge.BackgroundTransparency = 1
	stepBadge.Font = Enum.Font.FredokaOne
	stepBadge.TextSize = 20
	stepBadge.TextXAlignment = Enum.TextXAlignment.Left
	stepBadge.TextColor3 = Color3.fromRGB(255, 225, 85)
	stepBadge.Text = "STEP 1 / 12"
	stepBadge.Parent = heroCard
	addStroke(stepBadge, Color3.fromRGB(15, 18, 25), 2)

	local heroRewardLabel = Instance.new("TextLabel")
	heroRewardLabel.AnchorPoint = Vector2.new(1, 0)
	heroRewardLabel.Position = UDim2.new(1, -16, 0, 10)
	heroRewardLabel.Size = UDim2.fromOffset(260, 26)
	heroRewardLabel.BackgroundTransparency = 1
	heroRewardLabel.Font = Enum.Font.FredokaOne
	heroRewardLabel.TextSize = 22
	heroRewardLabel.TextXAlignment = Enum.TextXAlignment.Right
	heroRewardLabel.TextColor3 = Color3.fromRGB(120, 225, 255)
	heroRewardLabel.Text = "💎 +15"
	heroRewardLabel.Parent = heroCard
	addStroke(heroRewardLabel, Color3.fromRGB(15, 18, 25), 2)

	local heroTitle = Instance.new("TextLabel")
	heroTitle.Position = UDim2.fromOffset(16, 40)
	heroTitle.Size = UDim2.new(1, -32, 0, 36)
	heroTitle.BackgroundTransparency = 1
	heroTitle.Font = Enum.Font.FredokaOne
	heroTitle.TextSize = 26
	heroTitle.TextXAlignment = Enum.TextXAlignment.Left
	heroTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	heroTitle.Text = "Throw bait 1 time"
	heroTitle.Parent = heroCard
	addStroke(heroTitle, Color3.fromRGB(15, 18, 25), 2.2)

	local heroBarBg = Instance.new("Frame")
	heroBarBg.Position = UDim2.fromOffset(16, 86)
	heroBarBg.Size = UDim2.fromOffset(420, 28)
	heroBarBg.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	heroBarBg.Parent = heroCard
	addCorner(heroBarBg, 10)
	addStroke(heroBarBg, Color3.fromRGB(10, 12, 18), 1.8, Enum.ApplyStrokeMode.Border)

	local heroBarFill = Instance.new("Frame")
	heroBarFill.Size = UDim2.fromScale(0, 1)
	heroBarFill.BackgroundColor3 = Color3.fromRGB(95, 245, 95)
	heroBarFill.Parent = heroBarBg
	addCorner(heroBarFill, 10)

	local heroBarTxt = Instance.new("TextLabel")
	heroBarTxt.Size = UDim2.fromScale(1, 1)
	heroBarTxt.BackgroundTransparency = 1
	heroBarTxt.Font = Enum.Font.FredokaOne
	heroBarTxt.TextSize = 18
	heroBarTxt.TextColor3 = Color3.fromRGB(255, 255, 255)
	heroBarTxt.Text = "0 / 1"
	heroBarTxt.ZIndex = 3
	heroBarTxt.Parent = heroBarBg
	addStroke(heroBarTxt, Color3.fromRGB(12, 14, 18), 1.8)

	local _, heroClaimFace, heroClaimLbl = UiKit.CreateBevelButton({
		Name = "ClaimLineQuestBtn",
		Parent = heroCard,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -14),
		Size = UDim2.fromOffset(172, 54),
		Color = Color3.fromRGB(85, 235, 85),
		CornerRadius = 11,
		Text = "CLAIM!",
		TextSize = 22,
		OnClick = function()
			ctx.OnClaimQuest("Line", nil)
		end,
	})

	-- Next 2 Preview Cards
	type PreviewCardUI = {
		Row: Frame,
		TitleLabel: TextLabel,
		RewardLabel: TextLabel,
	}
	local previewCards: { PreviewCardUI } = {}
	for i = 1, 2 do
		local pRow = Instance.new("Frame")
		pRow.Name = `NextStepPreview_{i}`
		pRow.Position = UDim2.fromOffset(0, 174 + (i - 1) * 76)
		pRow.Size = UDim2.new(1, 0, 0, 68)
		pRow.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
		pRow.BackgroundTransparency = 0.2
		pRow.Parent = linePage
		addCorner(pRow, 10)
		addStroke(pRow, Color3.fromRGB(16, 18, 24), 1.8, Enum.ApplyStrokeMode.Border)

		local pTitle = Instance.new("TextLabel")
		pTitle.Position = UDim2.fromOffset(14, 8)
		pTitle.Size = UDim2.new(1, -190, 0, 52)
		pTitle.BackgroundTransparency = 1
		pTitle.Font = Enum.Font.FredokaOne
		pTitle.TextSize = 18
		pTitle.TextWrapped = true
		pTitle.TextXAlignment = Enum.TextXAlignment.Left
		pTitle.TextColor3 = Color3.fromRGB(155, 165, 185)
		pTitle.Text = "🔒 Step 2"
		pTitle.Parent = pRow
		addStroke(pTitle, Color3.fromRGB(12, 14, 18), 1.6)

		local pReward = Instance.new("TextLabel")
		pReward.AnchorPoint = Vector2.new(1, 0.5)
		pReward.Position = UDim2.new(1, -16, 0.5, 0)
		pReward.Size = UDim2.fromOffset(160, 32)
		pReward.BackgroundTransparency = 1
		pReward.Font = Enum.Font.FredokaOne
		pReward.TextSize = 18
		pReward.TextXAlignment = Enum.TextXAlignment.Right
		pReward.TextColor3 = Color3.fromRGB(130, 175, 210)
		pReward.Text = ""
		pReward.Parent = pRow
		addStroke(pReward, Color3.fromRGB(12, 14, 18), 1.6)

		previewCards[i] = {
			Row = pRow,
			TitleLabel = pTitle,
			RewardLabel = pReward,
		}
	end

	local function refresh(state: any): boolean
		local canClaimDaily = state.DailyCanClaim == true
		local nextStreakDay = math.clamp(tonumber(state.DailyNextDay) or 1, 1, #GameConfig.Gems.DailyRewards)
		local curStreak = math.clamp(tonumber(state.DailyStreak) or 0, 0, #GameConfig.Gems.DailyRewards)
		local activeDay = if canClaimDaily then nextStreakDay else math.max(1, curStreak)

		countdownLabel.Text = formatCountdown(tonumber(state.SecondsUntilNextDay) or 0)

		for i, tileUi in dayTiles do
			local isClaimed = (canClaimDaily and i < activeDay) or (not canClaimDaily and i <= curStreak)
			local isToday = (canClaimDaily and i == activeDay)
			if isClaimed then
				tileUi.Frame.BackgroundColor3 = Color3.fromRGB(38, 82, 52)
				tileUi.Stroke.Color = Color3.fromRGB(95, 235, 115)
				tileUi.StatusLabel.Text = "✓ DONE"
				tileUi.StatusLabel.TextColor3 = Color3.fromRGB(115, 255, 130)
			elseif isToday then
				tileUi.Frame.BackgroundColor3 = Color3.fromRGB(78, 65, 28)
				tileUi.Stroke.Color = Color3.fromRGB(255, 215, 55)
				tileUi.StatusLabel.Text = "TODAY!"
				tileUi.StatusLabel.TextColor3 = Color3.fromRGB(255, 235, 95)
			else
				tileUi.Frame.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
				tileUi.Stroke.Color = Color3.fromRGB(18, 20, 28)
				tileUi.StatusLabel.Text = "LOCKED"
				tileUi.StatusLabel.TextColor3 = Color3.fromRGB(130, 140, 160)
			end
		end

		if canClaimDaily then
			claimDailyFace.BackgroundColor3 = Color3.fromRGB(85, 235, 85)
			claimDailyLbl.Text = `CLAIM!\n(Day {activeDay})`
			claimDailyLbl.TextTransparency = 0
		else
			claimDailyFace.BackgroundColor3 = Color3.fromRGB(65, 72, 86)
			claimDailyLbl.Text = "CLAIMED\nTODAY ✓"
			claimDailyLbl.TextTransparency = 0.2
		end

		-- Daily Quests
		local dailyList = if type(state.DailyQuests) == "table" then state.DailyQuests else {}
		for i, card in dailyCards do
			local slot = dailyList[i]
			local def = if slot and type(slot.Id) == "string" then GameConfig.QuestsById[slot.Id] else nil
			if slot and def then
				card.Row.Visible = true
				local prog = math.clamp(tonumber(slot.Progress) or 0, 0, def.Target)
				local ratio = if def.Target > 0 then prog / def.Target else 0
				card.TitleLabel.Text = def.Title
				card.RewardLabel.Text = formatRewardText(def.Reward)
				card.BarFill.Size = UDim2.fromScale(ratio, 1)
				card.BarText.Text = `{GameConfig.FormatNumber(prog)} / {GameConfig.FormatNumber(def.Target)}`

				if slot.Claimed == true then
					card.ButtonFace.BackgroundColor3 = Color3.fromRGB(62, 68, 82)
					card.ButtonLabel.Text = "CLAIMED ✓"
					card.ButtonLabel.TextTransparency = 0.25
				elseif prog >= def.Target then
					card.ButtonFace.BackgroundColor3 = Color3.fromRGB(85, 235, 85)
					card.ButtonLabel.Text = "CLAIM!"
					card.ButtonLabel.TextTransparency = 0
				else
					card.ButtonFace.BackgroundColor3 = Color3.fromRGB(58, 92, 138)
					card.ButtonLabel.Text = `{math.floor(ratio * 100)}%`
					card.ButtonLabel.TextTransparency = 0.25
				end
			else
				card.Row.Visible = false
			end
		end

		-- Quest Line
		local step = tonumber(state.QuestLineStep) or 1
		local totalSteps = #GameConfig.Quests.Line
		local curDef = GameConfig.Quests.Line[step]
		if curDef then
			local prog = math.clamp(tonumber(state.QuestLineProgress) or 0, 0, curDef.Target)
			local ratio = if curDef.Target > 0 then prog / curDef.Target else 0
			stepBadge.Text = `QUEST LINE — STEP {step} / {totalSteps}`
			heroTitle.Text = curDef.Title
			heroRewardLabel.Text = formatRewardText(curDef.Reward)
			heroBarFill.Size = UDim2.fromScale(ratio, 1)
			heroBarTxt.Text = `{GameConfig.FormatNumber(prog)} / {GameConfig.FormatNumber(curDef.Target)}`
			if prog >= curDef.Target then
				heroClaimFace.BackgroundColor3 = Color3.fromRGB(85, 235, 85)
				heroClaimLbl.Text = "CLAIM!"
				heroClaimLbl.TextTransparency = 0
			else
				heroClaimFace.BackgroundColor3 = Color3.fromRGB(65, 72, 92)
				heroClaimLbl.Text = "IN PROGRESS"
				heroClaimLbl.TextTransparency = 0.25
			end
		else
			stepBadge.Text = `QUEST LINE — COMPLETE ({totalSteps} / {totalSteps})`
			heroTitle.Text = "🎉 All Quest Line steps completed!"
			heroRewardLabel.Text = "✓ MAX"
			heroBarFill.Size = UDim2.fromScale(1, 1)
			heroBarTxt.Text = "COMPLETED"
			heroClaimFace.BackgroundColor3 = Color3.fromRGB(62, 68, 82)
			heroClaimLbl.Text = "DONE ✓"
			heroClaimLbl.TextTransparency = 0.25
		end

		for i, pCard in previewCards do
			local nextIdx = step + i
			local nextDef = GameConfig.Quests.Line[nextIdx]
			if nextDef then
				pCard.Row.Visible = true
				pCard.TitleLabel.Text = `🔒 Step {nextIdx}: {nextDef.Title}\n(Complete Step {step} to unlock)`
				pCard.RewardLabel.Text = formatRewardText(nextDef.Reward)
			else
				pCard.Row.Visible = false
			end
		end

		return canClaimDaily or QuestLogic.HasAnyClaimableQuest(state)
	end

	return {
		Frame = modal,
		Refresh = refresh,
	}
end

return RewardsWindow
