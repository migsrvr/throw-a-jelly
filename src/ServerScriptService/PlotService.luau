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

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Slimes in a base wander around the yard (slot grid + margin)
local ROAM_SPEED = 3.2 -- studs/second while travelling
local ROAM_MARGIN_X = 5
local ROAM_MARGIN_Z = 4

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))

local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))
local WorldUi = require(script.Parent:WaitForChild("WorldUi"))
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))

local PlotService = {}

local plotSlotModels: { [Instance]: { [number]: Model } } = {}
-- slot pad each roaming slime belongs to (its Pick Up prompt anchor follows the slime)
local slimeSlotPart: { [Model]: BasePart } = setmetatable({}, { __mode = "k" }) :: any
local plotLayoutSig: { [Instance]: string } = {}
local collectCooldowns: { [Player]: number } = {}

-- Computes half the world-space vertical height of a BasePart, accounting for rotated Cylinders
-- (e.g. Slot1..12 and TrainSpot are Cylinders rotated 90 deg on Z, so their world Y thickness is Size.X).
local function getWorldHalfHeight(part: BasePart): number
	local up = part.CFrame:VectorToObjectSpace(Vector3.yAxis)
	return 0.5 * (math.abs(up.X) * part.Size.X + math.abs(up.Y) * part.Size.Y + math.abs(up.Z) * part.Size.Z)
end

local function buildPlotLayoutSignature(plot: Model, profile: ProgressionLogic.PlayerProfile?): string
	local ownerAttr = tostring(plot:GetAttribute("Owner") or "")
	if not profile then
		return `empty|{ownerAttr}`
	end
	local hasUnplaced = if #profile.UnplacedSlimes > 0 then "1" else "0"
	local parts = {
		ownerAttr,
		tostring(ProgressionLogic.GetEffectiveMaxSlimes(profile)),
		tostring(profile.PullUpTier),
		hasUnplaced,
	}
	for slot = 1, GameConfig.Slots.ExpandedMaxSlimes do
		local inst = profile.PlacedSlimesBySlot[slot]
		if inst then
			table.insert(parts, `{slot}:{inst.Uid}:{inst.SlimeId}:{inst.Mutation}:{inst.IncomePerSec}`)
		else
			table.insert(parts, `{slot}:_`)
		end
	end
	return table.concat(parts, "|")
end

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

	local slotsFolder = plot:FindFirstChild("SlimeSlots")
	if not slotsFolder then
		return
	end

	local maxSlimes = if profile
		then ProgressionLogic.GetEffectiveMaxSlimes(profile)
		else GameConfig.Slots.InitialMaxSlimes
	local income = if profile then ProgressionLogic.GetIncomePerSecond(profile) else 0
	local pending = if profile then profile.PendingIncome else 0
	local pullTier = if profile then profile.PullUpTier else 1
	local sig = buildPlotLayoutSignature(plot, profile)

	if plotLayoutSig[plot] ~= sig then
		plotLayoutSig[plot] = sig
		plot:SetAttribute("MaxSlimes", maxSlimes)

		for idx, mdl in currentModels do
			mdl:Destroy()
			currentModels[idx] = nil
		end

		-- Roam area: the slot grid plus a margin, so slimes wander around the yard but stay inside the fence
		local rMinX, rMaxX, rMinZ, rMaxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, sp in slotsFolder:GetChildren() do
			if sp:IsA("BasePart") then
				rMinX, rMaxX = math.min(rMinX, sp.Position.X), math.max(rMaxX, sp.Position.X)
				rMinZ, rMaxZ = math.min(rMinZ, sp.Position.Z), math.max(rMaxZ, sp.Position.Z)
			end
		end

		for _, slotPart in slotsFolder:GetChildren() do
			if slotPart:IsA("BasePart") then
				local slotIdx = (slotPart:GetAttribute("SlotIndex") :: number?)
					or tonumber(string.match(slotPart.Name, "%d+"))
					or 0
				local unlocked = slotIdx <= maxSlimes
				local inst = if profile and unlocked then profile.PlacedSlimesBySlot[slotIdx] else nil

				-- Keep slot pads invisible as configured in place.rbxl (WorldUi renders floating slot signs)
				slotPart.Transparency = 1

				WorldUi.SetSlot(slotPart, slotIdx, unlocked, inst)

				local prompt = slotPart:FindFirstChildWhichIsA("ProximityPrompt", true)
				local promptAnchor = slotPart:FindFirstChild("PromptAnchor") :: Attachment?
				if promptAnchor and not inst then
					promptAnchor.Position = Vector3.zero -- no slime here: the prompt sits back on the pad
				end
				if prompt then
					prompt.Enabled = unlocked
					if inst then
						prompt.ActionText = "Pick Up Slime"
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
					local halfHeight = getWorldHalfHeight(slotPart)
					-- Plots are entered from the +Z side (spawn pad), so turn the slime's face (-Z) toward +Z
					local baseCf = CFrame.new(slotPart.Position + Vector3.new(0, halfHeight + radius, 0))
						* CFrame.Angles(0, math.pi, 0)
					slimeModel:SetAttribute("SlotBaseY", baseCf.Position.Y)
					slimeModel:SetAttribute("SlotPhase", slotIdx * 0.75)
					slimeModel:SetAttribute("RoamMinX", rMinX - ROAM_MARGIN_X)
					slimeModel:SetAttribute("RoamMaxX", rMaxX + ROAM_MARGIN_X)
					slimeModel:SetAttribute("RoamMinZ", rMinZ - ROAM_MARGIN_Z)
					slimeModel:SetAttribute("RoamMaxZ", rMaxZ + ROAM_MARGIN_Z)
					SlimeFactory.PositionSlime(slimeModel, baseCf, 0)
					slimeModel.Parent = plot
					SlimeFactory.MakeRigid(slimeModel) -- weld to the root: one replicated part per slime while bobbing
					slimeSlotPart[slimeModel] = slotPart
					-- Sit the slime's lowest point exactly on the yard floor (no floating)
					local floorPart = plot:FindFirstChild("Floor")
					if floorPart and floorPart:IsA("BasePart") then
						local floorTop = floorPart.Position.Y + floorPart.Size.Y * 0.5
						local bbCf, bbSize = slimeModel:GetBoundingBox()
						local gap = (bbCf.Position.Y - bbSize.Y * 0.5) - floorTop
						if math.abs(gap) < 3 then
							slimeModel:SetAttribute("SlotBaseY", baseCf.Position.Y - gap)
						end
					end
					-- The slot sign follows the roaming slime; the client only shows it when a player is right next to it
					local sign = slotPart:FindFirstChild("SlotSign")
					if sign and sign:IsA("BillboardGui") and slimeModel.PrimaryPart then
						sign.Adornee = slimeModel.PrimaryPart
						sign.StudsOffset = Vector3.new(0, slimeModel:GetExtentsSize().Y * 0.5 + 3, 0)
						sign.Enabled = false
						sign:SetAttribute("ProximityOnly", true)
					end
					currentModels[slotIdx] = slimeModel
				end
			end
		end

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

		updateUpgradeSign(plot, maxSlimes)
		local upgradeStand = plot:FindFirstChild("UpgradeStand")
		local standPart = (upgradeStand and (upgradeStand:FindFirstChild("Backing") or upgradeStand:FindFirstChildWhichIsA("BasePart")))
			or (plot:FindFirstChild("UpgradeSign") :: BasePart?)
		local standPrompt = standPart and standPart:FindFirstChildOfClass("ProximityPrompt")
		if standPrompt then
			local nextCost = GameConfig.GetNextSlotGemCost(maxSlimes)
			if maxSlimes >= GameConfig.Slots.ExpandedMaxSlimes or not nextCost then
				standPrompt.Enabled = false
				standPrompt.ActionText = "MAX SLOTS (12/12)"
				standPrompt.ObjectText = "All Slots Unlocked"
			else
				standPrompt.Enabled = true
				standPrompt.ActionText = `Unlock Slot #{maxSlimes + 1} ({GameConfig.FormatNumber(nextCost)} Gems)`
				standPrompt.ObjectText = "Plot Slots (or +4 Slots Pass)"
			end
		end
	end

	updateOwnerIncomeBillboard(plot, income)
	updateCollectBillboard(plot, pending)
	updatePullUpBillboard(plot, pullTier)
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
		local minY = trainSpot.Position.Y + getWorldHalfHeight(trainSpot) + STAND_HEIGHT
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
				local prompt = slotPart:FindFirstChildWhichIsA("ProximityPrompt", true)
				if not prompt then
					prompt = Instance.new("ProximityPrompt")
					prompt.ActionText = "Place Slime"
					prompt.ObjectText = `Slot #{slotIdx}`
					prompt.HoldDuration = 0
					prompt.MaxActivationDistance = 11
					prompt.RequiresLineOfSight = false
					prompt.Parent = slotPart
				end
				-- The prompt lives on an attachment so it can follow the roaming slime (the pad itself never moves)
				local anchor = slotPart:FindFirstChild("PromptAnchor") :: Attachment?
				if not anchor then
					anchor = Instance.new("Attachment")
					anchor.Name = "PromptAnchor"
					anchor.Parent = slotPart
				end
				prompt.Parent = anchor
				prompt.MaxActivationDistance = 8 -- only when you're right next to the slime
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
					if profile.PlacedSlimesBySlot[slotIdx] then
						local ok, msg = ProgressionLogic.PickupSlimeFromSlot(profile, slotIdx)
						PlayerStateService.Toast(triggerPlayer, msg, if ok then "info" else "warn")
						if ok then
							PlayerStateService.Sync(triggerPlayer)
						end
					elseif #profile.UnplacedSlimes > 0 then
						local topSlime = profile.UnplacedSlimes[1]
						local ok, msg = ProgressionLogic.PlaceSlimeAtSlot(profile, topSlime.Uid, slotIdx)
						PlayerStateService.Toast(triggerPlayer, msg, if ok then "success" else "warn")
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

	-- 3. UpgradeStand prompt (Unlock locked Slots 9..12 one-by-one with Gems)
	local upgradeStand = plot:FindFirstChild("UpgradeStand")
	local standPart = (upgradeStand and (upgradeStand:FindFirstChild("Backing") or upgradeStand:FindFirstChildWhichIsA("BasePart")))
		or (plot:FindFirstChild("UpgradeSign") :: BasePart?)
	if standPart and standPart:IsA("BasePart") then
		local prompt = standPart:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = standPart
		end
		local firstCost = GameConfig.GetNextSlotGemCost(GameConfig.Slots.InitialMaxSlimes) or 1500
		prompt.ActionText = `Unlock Slot #9 ({GameConfig.FormatNumber(firstCost)} Gems)`
		prompt.ObjectText = "Plot Slots (or +4 Slots Pass)"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.Triggered:Connect(function(triggerPlayer: Player)
			if getPlotOwner(plot) ~= triggerPlayer then
				PlayerStateService.Toast(triggerPlayer, "That's another player's plot!", "warn")
				return
			end
			PlayerStateService.Purchase(triggerPlayer, "gem_slot_unlock", 1)
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

-- Sister Slime Sell Shop directly beside Hub.JellyShop (X = 72.5, Z = -11.5),
-- matching JellyShop's exact deck, counter, roof, slanted striped awning, and gold-framed roof sign.
local function wireSellShop()
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	if not hub then
		return
	end

	local sellShop = hub:FindFirstChild("SellShop") :: Model?
	if not sellShop then
		local model = Instance.new("Model")
		model.Name = "SellShop"
		model.Parent = hub
		sellShop = model

		local cx = 72.5
		local mintWall = Color3.fromRGB(110, 225, 140)
		local emeraldAwning = Color3.fromRGB(55, 195, 95)
		local creamWhite = Color3.fromRGB(255, 250, 252)
		local goldTrim = Color3.fromRGB(255, 210, 60)
		local woodDeck = Color3.fromRGB(170, 115, 70)

		local function makePart(name: string, size: Vector3, cf: CFrame, color: Color3): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Material = Enum.Material.Plastic
			p.Anchored = true
			p.CanCollide = true
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Parent = model
			return p
		end

		-- Deck, walls, counter, and roof aligned flush with Hub.JellyShop
		makePart("Deck", Vector3.new(16.0, 0.8, 17.0), CFrame.new(cx, 30.4, -11.5), woodDeck)
		makePart("BackWall", Vector3.new(15.0, 13.2, 2.0), CFrame.new(cx, 37.4, -4.0), mintWall)
		makePart("LeftWall", Vector3.new(1.4, 13.2, 13.0), CFrame.new(cx - 6.8, 37.4, -10.5), mintWall)
		makePart("RightWall", Vector3.new(1.4, 13.2, 13.0), CFrame.new(cx + 6.8, 37.4, -10.5), mintWall)
		makePart("Counter", Vector3.new(12.2, 4.0, 3.0), CFrame.new(cx, 32.8, -13.5), creamWhite)
		makePart("CounterTrim", Vector3.new(12.6, 0.35, 3.4), CFrame.new(cx, 34.95, -13.5), goldTrim)
		makePart("Roof", Vector3.new(17.0, 1.5, 17.0), CFrame.new(cx, 44.8, -10.5), mintWall)

		-- Slanted emerald & white striped awning + front scallops matching JellyShop.Awning / Scallop
		for i = 0, 3 do
			local sx = cx - 6.0 + i * 4.0
			local col = if i % 2 == 0 then emeraldAwning else creamWhite
			makePart(
				"Awning",
				Vector3.new(4.0, 0.5, 5.4),
				CFrame.new(sx, 43.6, -21.2) * CFrame.Angles(math.rad(-22), 0, 0),
				col
			)
			local scallop = makePart(
				"Scallop",
				Vector3.new(0.3, 2.4, 2.4),
				CFrame.new(sx, 42.2, -23.8) * CFrame.Angles(0, math.rad(90), 0),
				col
			)
			scallop.Shape = Enum.PartType.Cylinder
			scallop.CanCollide = false
		end

		-- Gold-framed roof sign matching JellyShop.Sign & SignFrame at Y = 49.6, Z = -17.5
		makePart("SignFrame", Vector3.new(15.6, 7.6, 0.6), CFrame.new(cx, 49.6, -16.7), goldTrim)
		local sign = makePart("Sign", Vector3.new(14.0, 6.0, 1.0), CFrame.new(cx, 49.6, -17.5), Color3.fromRGB(40, 170, 75))
		local signGui = Instance.new("SurfaceGui")
		signGui.Name = "SignGui"
		signGui.Face = Enum.NormalId.Front
		signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		signGui.PixelsPerStud = 36
		signGui.LightInfluence = 0
		signGui.Parent = sign
		local signText = Instance.new("TextLabel")
		signText.Size = UDim2.fromScale(1, 1)
		signText.BackgroundTransparency = 1
		signText.Font = Enum.Font.FredokaOne
		signText.TextScaled = true
		signText.TextColor3 = Color3.fromRGB(255, 255, 255)
		signText.Text = "SLIME SELL"
		signText.Parent = signGui
		local signStroke = Instance.new("UIStroke")
		signStroke.Color = Color3.fromRGB(15, 22, 18)
		signStroke.Thickness = 5
		signStroke.Parent = signText

		-- Golden slime mascot on the counter facing -Z
		local mascot = SlimeFactory.CreateSlimeModel("meadow_honey", false, "GOLDEN")
		SlimeFactory.PositionSlime(mascot, CFrame.lookAt(Vector3.new(cx, 36.2, -13.5), Vector3.new(cx, 36.2, -25)), 0)
		mascot.Parent = model
		SlimeFactory.MakeRigid(mascot)

		-- Invisible interaction trigger aligned next to JellyShop.ShopTrigger
		local trigger = makePart("SellTrigger", Vector3.new(14.0, 8.0, 8.0), CFrame.new(cx, 34.0, -24.5), creamWhite)
		trigger.Transparency = 1
		trigger.CanCollide = false
		trigger.CastShadow = false
	end

	local trigger = sellShop and sellShop:FindFirstChild("SellTrigger")
	if trigger and trigger:IsA("BasePart") then
		local prompt = trigger:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = trigger
		end
		prompt.ActionText = "Sell Slimes"
		prompt.ObjectText = "Slime Sell Shop"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Triggered:Connect(function(player: Player)
			Remotes.GetEvent("OpenSellShop"):FireClient(player)
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
	elseif target == "JellyShop" then
		-- Land cleanly in front of JellyShop & SellShop facing the shop counters
		local pos = Vector3.new(90, GameConfig.Hub.FloorY + 3.5, -29)
		local lookAt = Vector3.new(90, GameConfig.Hub.FloorY + 3.5, -13.5)
		char:PivotTo(CFrame.lookAt(pos, lookAt))
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
	wireSellShop()

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

	-- Passive income loop: accumulates earnings in PendingIncome on the plot's CollectPad
	-- so stepping onto (or standing on) CollectPad claims all accumulated cash into the wallet.
	task.spawn(function()
		while true do
			task.wait(1.0)
			for player, profile in PlayerStateService.GetAllProfiles() do
				local rate = ProgressionLogic.GetIncomePerSecond(profile)
				if rate > 0 then
					ProgressionLogic.TickPassiveIncome(profile, 1.0)
				end
				local plot = PlotService.GetPlayerPlot(player)
				if plot then
					-- Also collect if the owner is currently standing on CollectPad when income ticks
					local collectPad = plot:FindFirstChild("CollectPad")
					local char = player.Character
					local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
					if collectPad and collectPad:IsA("BasePart") and root and profile.PendingIncome >= 1 then
						local delta = root.Position - collectPad.Position
						local flatDist = Vector3.new(delta.X, 0, delta.Z).Magnitude
						if flatDist <= 5.5 and math.abs(delta.Y) <= 6.5 then
							collectPlotCash(player, plot)
						end
					end
					updateCollectBillboard(plot, profile.PendingIncome)
				end
				if rate > 0 then
					PlayerStateService.Sync(player)
				end
			end
			updateHubLeaderboards()
		end
	end)

	-- ROAMING (mobile-friendly): the server only DECIDES where each plot slime walks, at ROAM_TICK. Each walk
	-- segment is published as attributes (RoamFromX/Z, RoamToX/Z, RoamT0 = server time, RoamDur, RoamYaw) and every
	-- client animates the slimes near its camera (PlotSlimeAnimator.client.luau): hop, idle bob and turning are
	-- local, so nothing about the motion replicates 60 times a second. The server writes the root once per
	-- segment (at its end) and moves the Pick Up prompt anchor along the path at ROAM_TICK.
	local ROAM_TICK = 0.2
	local autoTrainAccum = 0
	local roamAccum = 0
	local roamRng = Random.new()
	type Roam = { X: number, Z: number, TX: number, TZ: number, Yaw: number, Wait: number, Moving: boolean, T0: number, Dur: number }
	local roamState: { [Model]: Roam } = setmetatable({}, { __mode = "k" }) :: any

	local function publishRoam(model: Model, st: Roam)
		model:SetAttribute("RoamFromX", st.X)
		model:SetAttribute("RoamFromZ", st.Z)
		model:SetAttribute("RoamToX", st.TX)
		model:SetAttribute("RoamToZ", st.TZ)
		model:SetAttribute("RoamYaw", st.Yaw)
		model:SetAttribute("RoamDur", st.Dur)
		model:SetAttribute("RoamT0", st.T0)
	end

	local function stepRoaming(tickDt: number)
		local now = workspace:GetServerTimeNow()
		for _, slotsMap in plotSlotModels do
			for _, slimeModel in slotsMap do
				local primary = slimeModel.PrimaryPart
				if primary and slimeModel.Parent then
					local baseY = (slimeModel:GetAttribute("SlotBaseY") :: number?) or primary.Position.Y
					local st = roamState[slimeModel]
					if not st then
						st = {
							X = primary.Position.X,
							Z = primary.Position.Z,
							TX = primary.Position.X,
							TZ = primary.Position.Z,
							Yaw = math.pi,
							Wait = roamRng:NextNumber(0.2, 3.5),
							Moving = false,
							T0 = now,
							Dur = 0,
						}
						roamState[slimeModel] = st
						publishRoam(slimeModel, st) -- resting where it was placed
						CollectionService:AddTag(slimeModel, "PlotSlime")
					end
					local padPart = slimeSlotPart[slimeModel]
					local promptAnchor = if padPart then padPart:FindFirstChild("PromptAnchor") :: Attachment? else nil
					if st.Moving then
						local u = if st.Dur > 0 then (now - st.T0) / st.Dur else 1
						if u >= 1 then
							st.X, st.Z = st.TX, st.TZ
							st.Moving = false
							st.Wait = roamRng:NextNumber(1.5, 5.0)
							-- one root write per segment: rest at the destination, facing the way it walked
							SlimeFactory.PositionSlime(slimeModel, CFrame.new(st.X, baseY, st.Z) * CFrame.Angles(0, st.Yaw, 0), 0)
							if promptAnchor then
								promptAnchor.WorldPosition = Vector3.new(st.X, baseY + 1, st.Z)
							end
						elseif promptAnchor then
							promptAnchor.WorldPosition = Vector3.new(st.X + (st.TX - st.X) * u, baseY + 1, st.Z + (st.TZ - st.Z) * u)
						end
					else
						st.Wait -= tickDt
						if st.Wait <= 0 then
							local minX = (slimeModel:GetAttribute("RoamMinX") :: number?) or st.X
							local maxX = (slimeModel:GetAttribute("RoamMaxX") :: number?) or st.X
							local minZ = (slimeModel:GetAttribute("RoamMinZ") :: number?) or st.Z
							local maxZ = (slimeModel:GetAttribute("RoamMaxZ") :: number?) or st.Z
							st.TX = roamRng:NextNumber(minX, maxX)
							st.TZ = roamRng:NextNumber(minZ, maxZ)
							local dx, dz = st.TX - st.X, st.TZ - st.Z
							local dist = math.sqrt(dx * dx + dz * dz)
							if dist > 0.05 then
								st.Yaw = math.atan2(-dx, -dz) -- the slime's front is -Z
								st.Dur = dist / ROAM_SPEED
								st.T0 = now
								st.Moving = true
								publishRoam(slimeModel, st)
							else
								st.Wait = roamRng:NextNumber(1.5, 5.0)
							end
						end
					end
				end
			end
		end
	end

	RunService.Heartbeat:Connect(function(dt: number)
		stepTraining()
		autoTrainAccum += dt
		if autoTrainAccum >= 0.2 then
			autoTrainAccum = 0
			checkAutoStartTraining()
		end
		roamAccum += dt
		if roamAccum >= ROAM_TICK then
			local tickDt = roamAccum
			roamAccum = 0
			stepRoaming(tickDt)
		end
	end)
end

return PlotService
