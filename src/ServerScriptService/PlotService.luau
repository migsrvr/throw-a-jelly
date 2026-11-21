--!strict
--[[
	PlotService.luau
	Integrates with existing Studio instances on Plot1..5 and Hub:
	- PullUpBar (Bar.ProximityPrompt, Bar.Billboard)
	- SlimeSlots (Slot1..Slot12 visual procedural slimes & idle bobbing)
	- UpgradeStand & UpgradeSign (+4 SLOTS for $5K -> MaxSlimes 8 to 12)
	- OwnerSign.IncomeBillboard & CollectPad.CollectBillboard + Touched collection
	- JellyShop.ShopTrigger.ProximityPrompt
	- Hub.Leaderboards (RARESTSLIME, BESTS, THROWPOWER, MOSTMONEY)
	- RequestTeleport & RequestTrainRep & RequestCollect
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))

local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))

local PlotService = {}

local plotSlotModels: { [Instance]: { [number]: Model } } = {}
local repCooldowns: { [Player]: number } = {}
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
	local collectPad = plot:FindFirstChild("CollectPad")
	local bb = collectPad and collectPad:FindFirstChild("CollectBillboard")
	if not bb then
		return
	end
	local labels = {}
	for _, child in bb:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	for _, lbl in labels do
		if lbl.Text == "COLLECT" or string.find(lbl.Text, "COLLECT") then
			lbl.Text = "COLLECT"
		else
			lbl.Text = `${GameConfig.FormatNumber(math.floor(pendingCash))}`
		end
	end
end

local function updateOwnerIncomeBillboard(plot: Model, incomePerSec: number)
	local ownerSign = plot:FindFirstChild("OwnerSign")
	local incomeBb = ownerSign and ownerSign:FindFirstChild("IncomeBillboard")
	local line1 = incomeBb and incomeBb:FindFirstChild("Line1") :: TextLabel?
	if line1 then
		line1.Text = `${GameConfig.FormatNumber(incomePerSec)}/s`
	end
end

local function updatePullUpBillboard(plot: Model, tierIndex: number)
	local pullUp = plot:FindFirstChild("PullUpBar")
	local bar = pullUp and pullUp:FindFirstChild("Bar")
	local bb = bar and bar:FindFirstChild("Billboard")
	local tierDef = GameConfig.PullUpTiers[tierIndex] or GameConfig.PullUpTiers[1]
	if bb then
		local l1 = bb:FindFirstChild("Line1") :: TextLabel?
		local l2 = bb:FindFirstChild("Line2") :: TextLabel?
		local l3 = bb:FindFirstChild("Line3") :: TextLabel?
		if l1 then
			l1.Text = tierDef.Name
		end
		if l2 then
			local nextTier = GameConfig.PullUpTiers[tierIndex + 1]
			l2.Text = if nextTier then `Tier {tierDef.Tier}` else "MAX TIER"
		end
		if l3 then
			l3.Text = `+{tierDef.XPPerRep} Power / rep`
		end
	end
end

local function updateUpgradeSign(plot: Model, maxSlimes: number)
	local upgradeSign = plot:FindFirstChild("UpgradeSign")
	local signGui = upgradeSign and upgradeSign:FindFirstChild("SignGui")
	local txt = signGui and signGui:FindFirstChild("Text") :: TextLabel?
	if txt then
		if maxSlimes >= GameConfig.Slots.ExpandedMaxSlimes then
			txt.Text = "MAX SLOTS\n<font color='#7CFF7C'>12 / 12</font>"
		else
			txt.Text = `+4 SLOTS\n<font color='#7CFF7C'>$${GameConfig.FormatNumber(GameConfig.Slots.ExpansionCost)}</font>`
		end
	end
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
			slotPart.Color = if unlocked then Color3.fromRGB(115, 220, 135) else Color3.fromRGB(95, 95, 105)
			slotPart.Transparency = if unlocked then 0.15 else 0.55

			if profile and unlocked and slotIdx >= 1 and slotIdx <= #profile.PlacedSlimes then
				local slimeId = profile.PlacedSlimes[slotIdx]
				local slimeModel = SlimeFactory.CreateSlimeModel(slimeId, true)
				local def = GameConfig.SlimesById[slimeId] or GameConfig.Slimes[1]
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

	updateOwnerIncomeBillboard(plot, income)
	updateCollectBillboard(plot, pending)
	updatePullUpBillboard(plot, pullTier)
	updateUpgradeSign(plot, maxSlimes)
end

local function performPullUpRep(player: Player)
	local now = os.clock()
	if repCooldowns[player] and now - repCooldowns[player] < 0.45 then
		return
	end
	repCooldowns[player] = now

	local profile = PlayerStateService.GetProfile(player)
	if not profile then
		return
	end

	local gained = ProgressionLogic.ApplyPullUpRep(profile)

	-- Subtle hop feedback on character
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Jump = true
	end

	PlayerStateService.Toast(player, `+{gained} Throw Power! (Total: {ProgressionLogic.GetEffectiveThrowPower(profile)})`, "power")
	PlayerStateService.Sync(player)
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
		PlayerStateService.Toast(player, `Collected +$${GameConfig.FormatNumber(collected)} Cash!`, "cash")
		PlayerStateService.Sync(player)
		local targetPlot = plot or PlotService.GetPlayerPlot(player)
		if targetPlot then
			updateCollectBillboard(targetPlot, profile.PendingIncome)
		end
	end
end

local function wirePlotInteractions(plot: Model)
	-- 1. PullUpBar prompt
	local pullUp = plot:FindFirstChild("PullUpBar")
	local bar = pullUp and pullUp:FindFirstChild("Bar")
	if bar and bar:IsA("BasePart") then
		local prompt = bar:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = bar
		end
		prompt.ActionText = "Do Pull-Up (+Power)"
		prompt.ObjectText = "Training Bar"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.Triggered:Connect(function(triggerPlayer: Player)
			performPullUpRep(triggerPlayer)
		end)
	end

	-- 2. UpgradeStand prompt (+4 SLOTS for $5K)
	local upgradeStand = plot:FindFirstChild("UpgradeStand")
	local standPart = (upgradeStand and (upgradeStand:FindFirstChild("Backing") or upgradeStand:FindFirstChildWhichIsA("BasePart")))
		or (plot:FindFirstChild("UpgradeSign") :: BasePart?)
	if standPart and standPart:IsA("BasePart") then
		local prompt = standPart:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = standPart
		end
		prompt.ActionText = `+4 Slime Slots ($${GameConfig.FormatNumber(GameConfig.Slots.ExpansionCost)})`
		prompt.ObjectText = "Plot Capacity"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.Triggered:Connect(function(triggerPlayer: Player)
			local profile = PlayerStateService.GetProfile(triggerPlayer)
			if not profile then
				return
			end
			local ok, msg = ProgressionLogic.PurchaseSlotExpansion(profile)
			PlayerStateService.Toast(triggerPlayer, msg, if ok then "success" else "warn")
			if ok then
				ProgressionLogic.PlaceBestSlimes(profile)
				PlayerStateService.Sync(triggerPlayer)
			end
		end)
	end

	-- 3. CollectPad touch
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

	-- React to Owner attribute changes from PlotAssignment.server.luau
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
			local profile = PlayerStateService.GetProfile(player)
			if not profile then
				return
			end
			local ok, msg = ProgressionLogic.PurchasePowerUpgrade(profile)
			PlayerStateService.Toast(player, msg, if ok then "success" else "warn")
			if ok then
				PlayerStateService.Sync(player)
			end
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
			Name = player.DisplayName,
			Cash = profile.Cash,
			Income = ProgressionLogic.GetIncomePerSecond(profile),
			Power = ProgressionLogic.GetEffectiveThrowPower(profile),
			RarityRank = rarest.RarityRank,
			RarityText = `{rarest.Name} ({rarest.Rarity})`,
		})
	end

	local function fillBoard(boardModelName: string, sortFn: (any, any) -> boolean, formatVal: (any) -> string)
		local mdl = boards:FindFirstChild(boardModelName)
		local panel = mdl and mdl:FindFirstChild("Panel")
		local gui = panel and panel:FindFirstChild("Board")
		if not gui then
			return
		end
		local list = table.clone(entries)
		table.sort(list, sortFn)
		for rank = 1, 10 do
			local row = gui:FindFirstChild(`Row{rank}`) :: TextLabel?
			if row then
				local item = list[rank]
				if item then
					row.Text = string.format("  %d.  %-14s %s", rank, string.sub(item.Name, 1, 14), formatVal(item))
				else
					row.Text = string.format("  %d.   ---", rank)
				end
			end
		end
	end

	fillBoard("MOSTMONEY", function(a, b)
		return a.Cash > b.Cash
	end, function(e)
		return `$${GameConfig.FormatNumber(e.Cash)}`
	end)

	fillBoard("BESTS", function(a, b)
		return a.Income > b.Income
	end, function(e)
		return `$${GameConfig.FormatNumber(e.Income)}/s`
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

	Remotes.GetEvent("RequestTrainRep").OnServerEvent:Connect(function(player: Player)
		performPullUpRep(player)
	end)

	Remotes.GetEvent("RequestCollect").OnServerEvent:Connect(function(player: Player)
		collectPlotCash(player, nil)
	end)

	Remotes.GetEvent("RequestTeleport").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) == "table" and type(payload.Target) == "string" then
			teleportPlayer(player, payload.Target)
		end
	end)

	-- Passive income loop (every 1s)
	task.spawn(function()
		while true do
			task.wait(1.0)
			for player, profile in PlayerStateService.GetAllProfiles() do
				ProgressionLogic.TickPassiveIncome(profile, 1.0)
				local plot = PlotService.GetPlayerPlot(player)
				if plot then
					updateCollectBillboard(plot, profile.PendingIncome)
				end
			end
			updateHubLeaderboards()
		end
	end)

	-- Gentle idle bobbing animation for placed plot slimes
	local accum = 0
	RunService.Heartbeat:Connect(function(dt: number)
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
