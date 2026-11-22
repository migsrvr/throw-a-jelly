--!strict
--[[
	PlotService.luau
	Integrates with existing Studio instances on Plot1..5 and Hub:
	- PullUpBar (Bar.ProximityPrompt toggles the looping pull-up training, Bar.Billboard)
	- SlimeSlots (Slot1..Slot12 visual mutated slimes, idle bobbing, and slot Prompts
	  so players can place their hotbar slime directly onto any slot!)
	- UpgradeStand & UpgradeSign (+4 SLOTS for $5K -> MaxSlimes 8 to 12)
	- OwnerSign.IncomeBillboard & CollectPad.CollectBillboard + Touched collection
	- JellyShop.ShopTrigger.ProximityPrompt
	- Hub.Leaderboards (RARESTSLIME, BESTS, THROWPOWER, MOSTMONEY)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local QuestLogic = require(Shared:WaitForChild("QuestLogic"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))

local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))
local WorldUi = require(script.Parent:WaitForChild("WorldUi"))
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))

local PlotService = {}

local plotSlotModels: { [Instance]: { [number]: Model } } = {}
local collectCooldowns: { [Player]: number } = {}

local function getBasesFolder(): Folder?
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	return (hub and hub:FindFirstChild("PlayerBases")) :: Folder?
end

function PlotService.GetPlayerPlot(player: Player): Model?
	local bases = getBasesFolder()
	if not bases then
		return nil
	end
	local uidStr = tostring(player.UserId)
	local plotIdAttr = player:GetAttribute("PlotId")
	for _, plot in bases:GetChildren() do
		if plot:IsA("Model") then
			if plot:GetAttribute("Owner") == uidStr then
				return plot
			end
			if plotIdAttr ~= nil and plot:GetAttribute("PlotId") == plotIdAttr then
				return plot
			end
		end
	end
	return nil
end

local function getPlotOwner(plot: Model): Player?
	local ownerAttr = plot:GetAttribute("Owner")
	if type(ownerAttr) == "string" and ownerAttr ~= "" then
		local uid = tonumber(ownerAttr)
		if uid then
			return Players:GetPlayerByUserId(uid)
		end
	end
	return nil
end

local function updateCollectBillboard(plot: Model, pendingCash: number)
	WorldUi.SetCollect(plot, pendingCash)
end

local function updateOwnerIncomeBillboard(plot: Model, incomePerSec: number)
	WorldUi.SetPlotSign(plot, incomePerSec)
end

local function updatePullUpBillboard(plot: Model, tierIndex: number)
	WorldUi.SetPullUp(plot, tierIndex)
end

local function updateUpgradeSign(plot: Model, maxSlimes: number)
	WorldUi.SetUpgradeStand(plot, maxSlimes)
end

function PlotService.RefreshPlotVisuals(plot: Model, profile: ProgressionLogic.PlayerProfile?)
	if not plotSlotModels[plot] then
		plotSlotModels[plot] = {}
	end
	local currentModels = plotSlotModels[plot]

	for idx, mdl in currentModels do
		mdl:Destroy()
		currentModels[idx] = nil
	end

	local slotsFolder = plot:FindFirstChild("SlimeSlots")
	if not slotsFolder then
		return
	end

	local maxSlimes = if profile then profile.MaxSlimes else GameConfig.Slots.InitialMaxSlimes
	plot:SetAttribute("MaxSlimes", maxSlimes)

	for _, slotPart in slotsFolder:GetChildren() do
		if slotPart:IsA("BasePart") then
			local slotIdx = (slotPart:GetAttribute("SlotIndex") :: number?)
				or tonumber(string.match(slotPart.Name, "%d+"))
				or 0
			local unlocked = slotIdx <= maxSlimes
			local inst = if profile and unlocked then profile.PlacedSlimesBySlot[slotIdx] else nil

			slotPart.Color = if not unlocked
				then Color3.fromRGB(85, 85, 95)
				elseif inst then Color3.fromRGB(95, 215, 120)
				else Color3.fromRGB(240, 255, 150)
			slotPart.Transparency = if unlocked then 0.12 else 0.58

			WorldUi.SetSlot(slotPart, slotIdx, unlocked, inst)

			local prompt = slotPart:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = unlocked
				if inst then
					prompt.ActionText = if profile and #profile.UnplacedSlimes > 0
						then "Swap / Pick Up Slime"
						else "Pick Up Slime"
					prompt.ObjectText = `{inst.Name} (${GameConfig.FormatNumber(inst.IncomePerSec)}/s)`
				else
					prompt.ActionText = "Place Slime"
					prompt.ObjectText = `Slot #{slotIdx}`
				end
			end

			if inst then
				local slimeModel = SlimeFactory.CreateSlimeModel(inst.SlimeId, false, inst.Mutation, inst.IncomePerSec)
				local def = GameConfig.SlimesById[inst.SlimeId] or GameConfig.Slimes[1]
				local radius = (2.4 * def.Scale) * 0.44
				local baseCf = CFrame.new(slotPart.Position + Vector3.new(0, slotPart.Size.Y * 0.5 + radius, 0))
				slimeModel:SetAttribute("SlotBaseY", baseCf.Position.Y)
				slimeModel:SetAttribute("SlotPhase", slotIdx * 0.75)
				SlimeFactory.PositionSlime(slimeModel, baseCf, 0)
				slimeModel.Parent = plot
				currentModels[slotIdx] = slimeModel
			end
		end
	end

	local income = if profile then ProgressionLogic.GetIncomePerSecond(profile) else 0
	local pending = if profile then profile.PendingIncome else 0
	local pullTier = if profile then profile.PullUpTier else 1

	local pullUp = plot:FindFirstChild("PullUpBar")
	local bar = pullUp and pullUp:FindFirstChild("Bar")
	local barPrompt = bar and bar:FindFirstChildOfClass("ProximityPrompt")
	if barPrompt then
		local curTier = GameConfig.PullUpTiers[pullTier] or GameConfig.PullUpTiers[1]
		local nextTier = GameConfig.PullUpTiers[pullTier + 1]
		if nextTier then
			barPrompt.Enabled = true
			barPrompt.ActionText = "Upgrade Bar"
			barPrompt.ObjectText = `{nextTier.Name} (${GameConfig.FormatNumber(nextTier.Cost)})`
		else
			barPrompt.Enabled = false
			barPrompt.ActionText = "MAX TIER"
			barPrompt.ObjectText = curTier.Name
		end
	end

	updateOwnerIncomeBillboard(plot, income)
	updateCollectBillboard(plot, pending)
	updatePullUpBillboard(plot, pullTier)
	updateUpgradeSign(plot, maxSlimes)
end

-- ============================================================================
-- PULL-UP TRAINING LOOP (server-authoritative cadence; the client only animates)
-- E on the bar toggles training. Reps are paid every GetPullUpRepInterval(profile) seconds,
-- re-read each rep so strength gains / bar upgrades speed the loop up live.
-- ============================================================================
type TrainingSession = {
	Bar: BasePart,
	Character: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	HangCFrame: CFrame,
	-- Constraints that pin the HRP under the bar. NOT anchoring: an anchored assembly becomes
	-- server-owned and the client's local joint (C0) posing never shows, freezing the character.
	Hold: { Instance },
	StartedAt: number,
	NextRepAt: number,
	Reps: number,
	-- Bonus Rep offers are scheduled by the SERVER (not the client), so an exploiter can only claim
	-- offers the server actually made, inside their window, at most once each.
	NextBonusAt: number,
	BonusId: number, -- id of the currently offered Bonus Rep (0 = none)
	BonusExpiresAt: number,
	LastBonusAt: number,
}

local HOLD_BREAK_DISTANCE = 4 -- studs the HRP may drift from the hang spot before training auto-stops

local function createHold(root: BasePart, hangCf: CFrame): { Instance }
	local att = Instance.new("Attachment")
	att.Name = "TrainHoldAttachment"
	att.Parent = root

	local alignPos = Instance.new("AlignPosition")
	alignPos.Name = "TrainHoldPosition"
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.Attachment0 = att
	alignPos.RigidityEnabled = true
	alignPos.Position = hangCf.Position
	alignPos.Parent = root

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Name = "TrainHoldOrientation"
	alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.Attachment0 = att
	alignOri.RigidityEnabled = true
	alignOri.CFrame = hangCf.Rotation
	alignOri.Parent = root

	return { alignPos, alignOri, att }
end

local training: { [Player]: TrainingSession } = {}
local barArmed: { [Player]: boolean } = {}
local bonusIdCounter = 0
local bonusRng = Random.new()

local function nextBonusDelay(): number
	local cfg = GameConfig.Training
	return bonusRng:NextNumber(cfg.BonusRepIntervalMin, cfg.BonusRepIntervalMax)
end

-- Everything the client needs to update the XP bar / level-up popup after a (bonus) rep
local function repPayload(profile: ProgressionLogic.PlayerProfile, result: ProgressionLogic.PullUpRepResult, interval: number, isBonus: boolean)
	return {
		XPGained = result.XPGained,
		LevelsGained = result.LevelsGained,
		PowerGained = result.PowerGained,
		StrengthLevel = result.NewLevel,
		CurrentXP = result.CurrentXP,
		RequiredXP = result.RequiredXP,
		Power = ProgressionLogic.GetEffectiveThrowPower(profile),
		Interval = interval,
		IsBonus = isBonus,
	}
end

local HANG_DROP = 3.0 -- HumanoidRootPart sits this far below the bar with arms straight up
local STAND_HEIGHT = 3.0 -- approx. HumanoidRootPart height above the floor when standing

-- Where the character hangs: under the bar's centre, facing across the bar.
local function getHangCFrame(bar: BasePart, trainSpot: BasePart?): CFrame
	local cf = bar.CFrame
	local size = bar.Size
	-- The bar's long axis is its largest horizontal dimension (Cylinder parts run along X)
	local longAxis = if bar:IsA("Part") and bar.Shape == Enum.PartType.Cylinder
		then cf.RightVector
		elseif size.X >= size.Z then cf.RightVector
		else cf.LookVector
	local facing = Vector3.new(longAxis.X, 0, longAxis.Z):Cross(Vector3.yAxis)
	if facing.Magnitude < 1e-3 then
		facing = Vector3.new(0, 0, 1)
	end
	facing = facing.Unit

	local hangPos = bar.Position - Vector3.new(0, HANG_DROP, 0)
	if trainSpot then
		-- Face away from the TrainSpot side, and never sink the body below a standing pose
		local toBar = Vector3.new(bar.Position.X - trainSpot.Position.X, 0, bar.Position.Z - trainSpot.Position.Z)
		if toBar.Magnitude > 0.1 and toBar:Dot(facing) < 0 then
			facing = -facing
		end
		local minY = trainSpot.Position.Y + trainSpot.Size.Y * 0.5 + STAND_HEIGHT
		hangPos = Vector3.new(hangPos.X, math.max(hangPos.Y, minY), hangPos.Z)
	end
	return CFrame.lookAt(hangPos, hangPos + facing)
end

local function stopTraining(player: Player, reason: string?)
	local session = training[player]
	if not session then
		return
	end
	training[player] = nil
	barArmed[player] = false

	for _, inst in session.Hold do
		inst:Destroy()
	end
	if session.Humanoid.Parent then
		session.Humanoid.PlatformStand = false
		if session.Humanoid.Health > 0 then
			session.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
	Remotes.GetEvent("TrainingState"):FireClient(player, { Active = false, Reason = reason })
	if session.Reps > 0 then
		PlayerStateService.Toast(player, `Training done: {session.Reps} reps!`, "power")
	end
	PlayerStateService.Sync(player)
end

local function startTraining(player: Player, plot: Model, bar: BasePart)
	local profile = PlayerStateService.GetProfile(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not profile or not char or not hum or hum.Health <= 0 or not root then
		return
	end
	if getPlotOwner(plot) ~= player then
		PlayerStateService.Toast(player, "Train on your own pull-up bar!", "warn")
		return
	end
	if (root.Position - bar.Position).Magnitude > GameConfig.PullUp.MaxTrainDistance then
		return
	end

	local pullUp = bar.Parent
	local trainSpot = pullUp and pullUp:FindFirstChild("TrainSpot") :: BasePart?
	local hangCf = getHangCFrame(bar, if trainSpot and trainSpot:IsA("BasePart") then trainSpot else nil)
	char:PivotTo(hangCf)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	-- PlatformStand stops the Humanoid state machine/Animate (falling, walking) while hanging
	hum.PlatformStand = true

	local interval = ProgressionLogic.GetPullUpRepInterval(profile)
	training[player] = {
		Bar = bar,
		Character = char,
		Root = root,
		Humanoid = hum,
		HangCFrame = hangCf,
		Hold = createHold(root, hangCf),
		StartedAt = os.clock(),
		-- First rep at half an interval: the client animation starts at the dead hang (phase 0) and
		-- peaks (chin over bar) at phase 0.5, so every paid rep lands on the peak.
		NextRepAt = os.clock() + interval * 0.5,
		Reps = 0,
		NextBonusAt = os.clock() + nextBonusDelay(),
		BonusId = 0,
		BonusExpiresAt = 0,
		LastBonusAt = 0,
	}
	Remotes.GetEvent("TrainingState"):FireClient(player, {
		Active = true,
		Interval = interval,
		StrengthLevel = profile.StrengthLevel,
		CurrentXP = profile.TrainingXP,
		RequiredXP = GameConfig.GetXPRequiredForLevel(profile.StrengthLevel),
	})
end

-- Step-on auto-start check (called every 0.2s). Starts training when the plot owner is armed and walks
-- within AutoStartRadius of TrainSpot (or Bar). Re-arms only after walking out past RearmRadius.
local function checkAutoStartTraining()
	for player in PlayerStateService.GetAllProfiles() do
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local plot = PlotService.GetPlayerPlot(player)
		local pullUp = plot and plot:FindFirstChild("PullUpBar")
		local bar = pullUp and pullUp:FindFirstChild("Bar") :: BasePart?
		local trainSpot = pullUp and pullUp:FindFirstChild("TrainSpot") :: BasePart?
		if not root or not hum or hum.Health <= 0 or not plot or not bar then
			continue
		end
		local anchorPos = if trainSpot and trainSpot:IsA("BasePart") then trainSpot.Position else bar.Position
		local delta = root.Position - anchorPos
		local flatDist = Vector3.new(delta.X, 0, delta.Z).Magnitude
		if training[player] == nil then
			if barArmed[player] == false then
				if flatDist >= GameConfig.PullUp.RearmRadius then
					barArmed[player] = true
				end
			else
				if flatDist <= GameConfig.PullUp.AutoStartRadius then
					startTraining(player, plot, bar)
				end
			end
		end
	end
end

local function stepTraining()
	local now = os.clock()
	for player, session in training do
		local hum = session.Humanoid
		if
			player.Character ~= session.Character
			or not session.Root.Parent
			or not hum.Parent
			or hum.Health <= 0
			-- something moved them off the bar (also stops a client walking away while still earning).
			-- Grace period: the client owns the character, so the snap takes a moment to replicate back.
			or (
				now - session.StartedAt > 1.0
				and (session.Root.Position - session.HangCFrame.Position).Magnitude > HOLD_BREAK_DISTANCE
			)
		then
			stopTraining(player, "interrupted")
			continue
		end

		if now >= session.NextRepAt then
			local profile = PlayerStateService.GetProfile(player)
			if not profile then
				stopTraining(player, "interrupted")
				continue
			end
			local result = ProgressionLogic.ApplyPullUpRep(profile)
			session.Reps += 1
			local interval = ProgressionLogic.GetPullUpRepInterval(profile)
			-- Schedule from the previous deadline (steady cadence), but never "catch up" after a lag spike
			session.NextRepAt = math.max(session.NextRepAt + interval, now + interval * 0.5)

			Remotes.GetEvent("TrainingRep"):FireClient(player, repPayload(profile, result, interval, false))
			-- Sync right away on a level up (Throw Power changed); otherwise every few reps
			if result.LevelsGained > 0 or session.Reps % GameConfig.PullUp.SyncEveryReps == 0 then
				PlayerStateService.Sync(player)
			end
		end

		-- Offer a Bonus Rep pop-up every BonusRepIntervalMin..Max seconds
		if session.BonusId ~= 0 and now > session.BonusExpiresAt then
			session.BonusId = 0 -- missed it
		end
		if session.BonusId == 0 and now >= session.NextBonusAt then
			bonusIdCounter += 1
			session.BonusId = bonusIdCounter
			session.BonusExpiresAt = now + GameConfig.Training.BonusRepWindow
			session.NextBonusAt = now + nextBonusDelay()
			Remotes.GetEvent("TrainingBonus"):FireClient(player, {
				Id = session.BonusId,
				Window = GameConfig.Training.BonusRepWindow,
				Multiplier = GameConfig.Training.BonusRepMultiplier,
			})
		end
	end
end

local function claimBonusRep(player: Player, bonusId: any)
	local session = training[player]
	if not session or type(bonusId) ~= "number" then
		return
	end
	local now = os.clock()
	-- Must be the offer currently open, still inside its window (small latency allowance),
	-- and respect the per-player cooldown.
	if
		session.BonusId == 0
		or bonusId ~= session.BonusId
		or now > session.BonusExpiresAt + 0.3
		or now - session.LastBonusAt < GameConfig.Training.BonusRepServerCooldown
	then
		return
	end
	local profile = PlayerStateService.GetProfile(player)
	if not profile then
		return
	end
	session.BonusId = 0
	session.LastBonusAt = now

	local result = ProgressionLogic.ApplyPullUpRep(profile, GameConfig.Training.BonusRepMultiplier)
	local interval = ProgressionLogic.GetPullUpRepInterval(profile)
	Remotes.GetEvent("TrainingRep"):FireClient(player, repPayload(profile, result, interval, true))
	PlayerStateService.Sync(player)
end

function PlotService.IsTraining(player: Player): boolean
	return training[player] ~= nil
end

function PlotService.StopTraining(player: Player)
	stopTraining(player, "external")
end

local function collectPlotCash(player: Player, plot: Model?)
	local now = os.clock()
	if collectCooldowns[player] and now - collectCooldowns[player] < 0.35 then
		return
	end
	collectCooldowns[player] = now

	local profile = PlayerStateService.GetProfile(player)
	if not profile then
		return
	end
	local collected = ProgressionLogic.CollectPendingIncome(profile)
	if collected > 0 then
		PlayerStateService.Toast(player, `+${GameConfig.FormatNumber(collected)} Cash!`, "cash")
		PlayerStateService.Sync(player)
		local targetPlot = plot or PlotService.GetPlayerPlot(player)
		if targetPlot then
			updateCollectBillboard(targetPlot, profile.PendingIncome)
		end
	end
end

local function wirePlotInteractions(plot: Model)
	-- 1. PullUpBar prompt (Upgrade Bar; training itself auto-starts when stepping under the bar)
	local pullUp = plot:FindFirstChild("PullUpBar")
	local bar = pullUp and pullUp:FindFirstChild("Bar")
	if bar and bar:IsA("BasePart") then
		local prompt = bar:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = bar
		end
		local nextTier = GameConfig.PullUpTiers[2]
		prompt.ActionText = "Upgrade Bar"
		prompt.ObjectText = if nextTier
			then `{nextTier.Name} (${GameConfig.FormatNumber(nextTier.Cost)})`
			else "Pull-Up Bar"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Triggered:Connect(function(triggerPlayer: Player)
			if getPlotOwner(plot) ~= triggerPlayer then
				PlayerStateService.Toast(triggerPlayer, "That's another player's pull-up bar!", "warn")
				return
			end
			PlayerStateService.Purchase(triggerPlayer, "pullup_tier", 1)
		end)
	end

	-- 2. SlimeSlots placement prompts (Slot1..Slot12)
	local slotsFolder = plot:FindFirstChild("SlimeSlots")
	if slotsFolder then
		for _, slotPart in slotsFolder:GetChildren() do
			if slotPart:IsA("BasePart") then
				local slotIdx = (slotPart:GetAttribute("SlotIndex") :: number?)
					or tonumber(string.match(slotPart.Name, "%d+"))
					or 1
				local prompt = slotPart:FindFirstChildOfClass("ProximityPrompt")
				if not prompt then
					prompt = Instance.new("ProximityPrompt")
					prompt.ActionText = "Place Slime"
					prompt.ObjectText = `Slot #{slotIdx}`
					prompt.HoldDuration = 0
					prompt.MaxActivationDistance = 11
					prompt.RequiresLineOfSight = false
					prompt.Parent = slotPart
				end
				prompt.Triggered:Connect(function(triggerPlayer: Player)
					local owner = getPlotOwner(plot)
					if owner ~= triggerPlayer then
						PlayerStateService.Toast(triggerPlayer, "That's another player's plot!", "warn")
						return
					end
					local profile = PlayerStateService.GetProfile(triggerPlayer)
					if not profile then
						return
					end
					if #profile.UnplacedSlimes > 0 then
						local topSlime = profile.UnplacedSlimes[1]
						local ok, msg = ProgressionLogic.PlaceSlimeAtSlot(profile, topSlime.Uid, slotIdx)
						PlayerStateService.Toast(triggerPlayer, msg, if ok then "success" else "warn")
						if ok then
							PlayerStateService.Sync(triggerPlayer)
						end
					elseif profile.PlacedSlimesBySlot[slotIdx] then
						local ok, msg = ProgressionLogic.PickupSlimeFromSlot(profile, slotIdx)
						PlayerStateService.Toast(triggerPlayer, msg, if ok then "info" else "warn")
						if ok then
							PlayerStateService.Sync(triggerPlayer)
						end
					else
						PlayerStateService.Toast(triggerPlayer, "Throw bait at the Throw Line to catch a slime first!", "warn")
					end
				end)
			end
		end
	end

	-- 3. UpgradeStand prompt (+4 SLOTS for $5K)
	local upgradeStand = plot:FindFirstChild("UpgradeStand")
	local standPart = (upgradeStand and (upgradeStand:FindFirstChild("Backing") or upgradeStand:FindFirstChildWhichIsA("BasePart")))
		or (plot:FindFirstChild("UpgradeSign") :: BasePart?)
	if standPart and standPart:IsA("BasePart") then
		local prompt = standPart:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = standPart
		end
		prompt.ActionText = `+4 Slime Slots (${GameConfig.FormatNumber(GameConfig.Slots.ExpansionCost)})`
		prompt.ObjectText = "Plot Capacity (8 -> 12)"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.Triggered:Connect(function(triggerPlayer: Player)
			PlayerStateService.Purchase(triggerPlayer, "slot_expansion", 1)
		end)
	end

	-- 4. CollectPad touch
	local collectPad = plot:FindFirstChild("CollectPad")
	if collectPad and collectPad:IsA("BasePart") then
		collectPad.Touched:Connect(function(hit: BasePart)
			local char = hit.Parent
			local player = char and Players:GetPlayerFromCharacter(char)
			if not player then
				return
			end
			local owner = getPlotOwner(plot)
			if owner == player then
				collectPlotCash(player, plot)
			end
		end)
	end

	plot:GetAttributeChangedSignal("Owner"):Connect(function()
		local owner = getPlotOwner(plot)
		local profile = if owner then PlayerStateService.GetProfile(owner) else nil
		PlotService.RefreshPlotVisuals(plot, profile)
	end)

	PlotService.RefreshPlotVisuals(plot, nil)
end

local function wireJellyShop()
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	local shop = hub and hub:FindFirstChild("JellyShop")
	local trigger = shop and shop:FindFirstChild("ShopTrigger")
	if trigger and trigger:IsA("BasePart") then
		local prompt = trigger:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = trigger
		end
		prompt.ActionText = "Upgrade Throw Power"
		prompt.ObjectText = "Jelly Shop"
		prompt.HoldDuration = 0
		prompt.Triggered:Connect(function(player: Player)
			PlayerStateService.Purchase(player, "power_upgrade", 1)
		end)
	end
end

local function updateHubLeaderboards()
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	local boards = hub and hub:FindFirstChild("Leaderboards")
	if not boards then
		return
	end

	local allProfiles = PlayerStateService.GetAllProfiles()
	local entries = {}
	for player, profile in allProfiles do
		local rarest = ProgressionLogic.GetRarestSlimeDef(profile)
		table.insert(entries, {
			UserId = player.UserId,
			Name = player.DisplayName,
			Cash = profile.Cash,
			Income = ProgressionLogic.GetIncomePerSecond(profile),
			Power = ProgressionLogic.GetEffectiveThrowPower(profile),
			RarityRank = rarest.RarityRank,
			RarityText = rarest.Rarity,
		})
	end
	if not LeaderboardService.ShouldUpdate(#entries) then
		return
	end

	local function fillBoard(boardModelName: string, sortFn: (any, any) -> boolean, formatVal: (any) -> string)
		local list = table.clone(entries)
		table.sort(list, sortFn)
		local rows: { LeaderboardService.Row } = {}
		for rank = 1, math.min(10, #list) do
			local item = list[rank]
			rows[rank] = { UserId = item.UserId, Name = item.Name, Value = formatVal(item) }
		end
		LeaderboardService.Render(boards, boardModelName, rows)
	end

	fillBoard("MOSTMONEY", function(a, b)
		return a.Cash > b.Cash
	end, function(e)
		return `${GameConfig.FormatNumber(e.Cash)}`
	end)

	fillBoard("BESTS", function(a, b)
		return a.Income > b.Income
	end, function(e)
		return `${GameConfig.FormatNumber(e.Income)}/s`
	end)

	fillBoard("THROWPOWER", function(a, b)
		return a.Power > b.Power
	end, function(e)
		return GameConfig.FormatNumber(e.Power)
	end)

	fillBoard("RARESTSLIME", function(a, b)
		return a.RarityRank > b.RarityRank
	end, function(e)
		return e.RarityText
	end)
end

local function teleportPlayer(player: Player, target: string)
	local char = player.Character
	if not char then
		return
	end
	stopTraining(player, "teleport") -- un-anchor before moving
	if target == "ThrowLine" then
		local plotId = (player:GetAttribute("PlotId") :: number?) or 3
		local xOffset = (plotId - 3) * 8
		local pos = Vector3.new(xOffset, GameConfig.Hub.FloorY + 3.5, GameConfig.Hub.ThrowLineZ - 2.5)
		char:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(0, 0, 20)))
	elseif target == "Plot" then
		local plot = PlotService.GetPlayerPlot(player)
		local pad = plot and plot:FindFirstChild("SpawnPad")
		local spawnLoc = pad and pad:FindFirstChild("PlotSpawn") :: BasePart?
		if spawnLoc then
			char:PivotTo(spawnLoc.CFrame + Vector3.new(0, 4, 0))
		end
	end
end

function PlotService.Init()
	local bases = getBasesFolder()
	if bases then
		for _, plot in bases:GetChildren() do
			if plot:IsA("Model") then
				wirePlotInteractions(plot)
			end
		end
	end

	wireJellyShop()

	PlayerStateService.OnProfileChanged(function(player: Player, profile: ProgressionLogic.PlayerProfile)
		local plot = PlotService.GetPlayerPlot(player)
		if plot then
			PlotService.RefreshPlotVisuals(plot, profile)
		end
	end)

	Remotes.GetEvent("RequestStopTraining").OnServerEvent:Connect(function(player: Player)
		stopTraining(player, "client")
	end)

	Remotes.GetEvent("RequestBonusRep").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) == "table" then
			claimBonusRep(player, payload.Id)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		training[player] = nil
		barArmed[player] = nil
		collectCooldowns[player] = nil
	end)

	Remotes.GetEvent("RequestCollect").OnServerEvent:Connect(function(player: Player)
		collectPlotCash(player, nil)
	end)

	Remotes.GetEvent("RequestTeleport").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) == "table" and type(payload.Target) == "string" then
			teleportPlayer(player, payload.Target)
		end
	end)

	-- Passive income loop: auto-credits cash directly into player wallet (like Clip 2 "$0 -> $10 -> $19")
	-- while also keeping CollectPad available for bonus collection!
	task.spawn(function()
		while true do
			task.wait(1.0)
			for player, profile in PlayerStateService.GetAllProfiles() do
				local rate = ProgressionLogic.GetIncomePerSecond(profile)
				if rate > 0 then
					profile.Cash += rate
					QuestLogic.RecordEvent(profile, "EarnCash", rate)
					PlayerStateService.Sync(player)
				end
				local plot = PlotService.GetPlayerPlot(player)
				if plot then
					updateCollectBillboard(plot, rate)
				end
			end
			updateHubLeaderboards()
		end
	end)

	local accum = 0
	local autoTrainAccum = 0
	RunService.Heartbeat:Connect(function(dt: number)
		stepTraining()
		autoTrainAccum += dt
		if autoTrainAccum >= 0.2 then
			autoTrainAccum = 0
			checkAutoStartTraining()
		end
		accum += dt
		for _, slotsMap in plotSlotModels do
			for _, slimeModel in slotsMap do
				local primary = slimeModel.PrimaryPart
				if primary then
					local baseY = (slimeModel:GetAttribute("SlotBaseY") :: number?) or primary.Position.Y
					local phase = (slimeModel:GetAttribute("SlotPhase") :: number?) or 0
					local wave = math.sin(accum * 3.4 + phase)
					local pos = Vector3.new(primary.Position.X, baseY + math.max(0, wave) * 0.45, primary.Position.Z)
					SlimeFactory.PositionSlime(slimeModel, CFrame.new(pos), -wave * 0.14)
				end
			end
		end
	end)
end

return PlotService
