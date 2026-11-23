--!strict
--[[
	ThrowService.luau
	Validates throw requests from the 9-segment vertical meter, computes authoritative
	ThrowPhysics trajectory, rolls caught Slime + Mutation + "1 in X" odds via
	ProgressionLogic (placing caught slimes into the player's Hotbar), and broadcasts
	ThrowBroadcast for the flight camera & cinematic reveal cutscene.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local QuestLogic = require(Shared:WaitForChild("QuestLogic"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ThrowPhysics = require(Shared:WaitForChild("ThrowPhysics"))

local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))

local ThrowService = {}

local lastThrowTime: { [Player]: number } = {}
local autoThrowBags: { [Player]: { number } } = {}

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) < math.huge
end

-- Non-destructive peek at the player's next Auto-Throw meter target so the client's visible
-- vertical meter can smoothly glide onto the exact Green / Light-Green band before firing.
function ThrowService.PeekNextAutoMeterRatio(player: Player): number
	local bag = autoThrowBags[player]
	if not bag then
		bag = {}
		autoThrowBags[player] = bag
	end
	local ratio = ThrowPhysics.PeekAutoThrowRatio(bag)
	return ratio
end

function ThrowService.Init()
	local requestThrow = Remotes.GetEvent("RequestThrow")
	local throwBroadcast = Remotes.GetEvent("ThrowBroadcast")

	PlayerStateService.SetAutoMeterPeeker(ThrowService.PeekNextAutoMeterRatio)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastThrowTime[player] = nil
		autoThrowBags[player] = nil
	end)

	requestThrow.OnServerEvent:Connect(function(player: Player, payload: any)
		local now = os.clock()
		if lastThrowTime[player] and now - lastThrowTime[player] < 0.75 then
			return
		end

		local profile = PlayerStateService.GetProfile(player)
		if not profile then
			return
		end

		local meterRatio = 0.75
		local pitchDeg = GameConfig.Physics.DefaultPitchDeg
		local yawDeg = 0
		local isAuto = type(payload) == "table" and payload.Auto == true

		-- Auto-Throw is unlocked via Gems OR the Auto-Throw Robux Pass; draws from a shuffled 5-throw bag
		if isAuto and not ProgressionLogic.OwnsAutoThrow(profile) then
			return
		end

		if type(payload) == "table" then
			if not isAuto and isFiniteNumber(payload.ChargeRatio) then
				meterRatio = math.clamp(payload.ChargeRatio, 0, 1)
			end
			if isFiniteNumber(payload.PitchDeg) then
				pitchDeg = math.clamp(payload.PitchDeg, GameConfig.Physics.MinPitchDeg, GameConfig.Physics.MaxPitchDeg)
			end
			if isFiniteNumber(payload.YawDeg) then
				yawDeg = math.clamp(payload.YawDeg, -GameConfig.Physics.MaxYawDeg, GameConfig.Physics.MaxYawDeg)
			end
		end

		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		-- Only throws from the throw line count (same box as the client meter, with a little slack)
		local pos = root.Position
		local hub = GameConfig.Hub
		local onLine = pos.X >= hub.ThrowLineMinX - 4
			and pos.X <= hub.ThrowLineMaxX + 4
			and pos.Z >= hub.ThrowLineZ - 13
			and pos.Z <= hub.ThrowLineZ + 7
		if not onLine then
			return
		end

		lastThrowTime[player] = now
		if isAuto then
			local bag = autoThrowBags[player]
			if not bag then
				bag = {}
				autoThrowBags[player] = bag
			end
			meterRatio = ThrowPhysics.NextAutoThrowRatio(bag)
		end

		local meterSeg = GameConfig.EvaluateMeterRatio(meterRatio)
		local launchX = math.clamp(pos.X, -GameConfig.Hub.ClearHalfWidth + 2, GameConfig.Hub.ClearHalfWidth - 2)

		local origin = Vector3.new(launchX, GameConfig.Hub.FloorY + 1.8, GameConfig.Hub.ThrowLineZ)
		-- Use the player's true EffectiveThrowPower so terrain landing & gate unlock match the HUD 1:1
		local effectivePower = ProgressionLogic.GetEffectiveThrowPower(profile)
		local equippedDef = GameConfig.SlimesById[profile.EquippedSlimeId] or GameConfig.Slimes[1]
		local chargeRatio = meterSeg.ChargeRatio

		local simResult = ThrowPhysics.Simulate({
			Origin = origin,
			ThrowPower = effectivePower,
			ChargeRatio = chargeRatio,
			PitchDeg = pitchDeg,
			YawDeg = yawDeg,
			SlimeWeight = 1.0,
		})

		-- Luck = distance down the lane x meter band x Jelly Bait quality (authoritative; the client ticker
		-- only replays this with GameConfig.ComputeFlightLuck during the flight)
		-- Gem luck boosts (Lucky Charm) multiply on top, folded into the bait factor so the ticker matches.
		local baitDef = ProgressionLogic.GetBaitDef(profile)
		local boostLuck = ProgressionLogic.GetBoostLuckMultiplier(profile)
		local totalLuck =
			GameConfig.ComputeFlightLuck(simResult.Distance, meterSeg.LuckMultiplier, baitDef.LuckMultiplier * boostLuck)

		-- Put newly caught slime into Hotbar (UnplacedSlimes) so the player can equip & place it (Clip 1/2 flow!)
		local reward = ProgressionLogic.EvaluateThrowReward(
			profile,
			simResult.Distance,
			simResult.LandedZoneIndex,
			nil,
			totalLuck,
			nil,
			true
		)

		if meterSeg.IsPerfect == true then
			QuestLogic.RecordEvent(profile, "PerfectThrow", 1)
		end

		PlayerStateService.Sync(player)

		local zoneDef = GameConfig.Zones[simResult.LandedZoneIndex] or GameConfig.Zones[1]
		local blockedZone = if simResult.BlockedByZoneIndex then GameConfig.Zones[simResult.BlockedByZoneIndex] else nil

		-- STUDIO ONLY: ReplicatedStorage:SetAttribute("DebugForceSlimeId", "crystal_bat") (optionally also
		-- "DebugForceMutation") changes which slime the catch cutscene SHOWS. Visual only: the real reward
		-- above is unchanged. Live servers ignore it.
		-- "DebugForceNew" (bool) picks the new-discovery silhouette (true) or the already-known full-colour
		-- look (false); without it a forced slime counts as new if this profile never discovered it.
		local shownSlimeDef = reward.CaughtSlimeDef
		local shownMutation = reward.Mutation
		local shownIsNew = reward.IsNewDiscovery
		if RunService:IsStudio() then
			local forcedId = ReplicatedStorage:GetAttribute("DebugForceSlimeId")
			if type(forcedId) == "string" and GameConfig.SlimesById[forcedId] then
				shownSlimeDef = GameConfig.SlimesById[forcedId]
				if forcedId ~= reward.CaughtSlimeId then
					shownIsNew = profile.DiscoveredSlimes[forcedId] ~= true
				end
			end
			local forcedNew = ReplicatedStorage:GetAttribute("DebugForceNew")
			if type(forcedNew) == "boolean" then
				shownIsNew = forcedNew
			end
			local forcedMut = ReplicatedStorage:GetAttribute("DebugForceMutation")
			if type(forcedMut) == "string" and GameConfig.MutationsById[forcedMut] then
				shownMutation = forcedMut
			end
		end

		throwBroadcast:FireAllClients({
			PlayerUserId = player.UserId,
			PlayerName = player.DisplayName,
			Origin = origin,
			ThrowPower = effectivePower,
			ChargeRatio = chargeRatio,
			MeterRatio = meterRatio,
			BonusPower = meterSeg.BonusPower,
			LuckMultiplier = totalLuck,
			MeterLuck = meterSeg.LuckMultiplier,
			BaitLuck = baitDef.LuckMultiplier,
			BoostLuck = boostLuck,
			IsAuto = isAuto,
			NextAutoMeterRatio = if ProgressionLogic.OwnsAutoThrow(profile)
				then ThrowService.PeekNextAutoMeterRatio(player)
				else nil,
			BaitTier = profile.BaitTier,
			BaitName = baitDef.Name,
			IsPerfect = meterSeg.IsPerfect == true,
			QualityLabel = meterSeg.QualityLabel,
			QualityColor = meterSeg.Color,
			PitchDeg = pitchDeg,
			YawDeg = yawDeg,
			SlimeId = equippedDef.Id,
			SlimeWeight = 1.0,
			Distance = simResult.Distance,
			LandedZoneName = zoneDef.Name,
			LandedZoneEmoji = zoneDef.Emoji,
			LandedZoneIndex = simResult.LandedZoneIndex,
			HitGate = simResult.HitGate,
			BlockedByZoneName = if blockedZone then blockedZone.Name else nil,
			BlockedRequiredPower = if blockedZone then blockedZone.RequiredThrowPower else nil,
			CashEarned = reward.CashEarned,
			CaughtSlimeId = shownSlimeDef.Id,
			CaughtSlimeName = shownSlimeDef.Name,
			CaughtShortWord = shownSlimeDef.ShortWord,
			CaughtSlimeRarity = shownSlimeDef.Rarity,
			CaughtMutation = shownMutation,
			CaughtIncomePerSec = reward.CaughtInstance.IncomePerSec,
			OddsOneInX = reward.OddsOneInX,
			IsSuperLucky = reward.IsSuperLucky,
			IsNewDiscovery = shownIsNew,
			AutoPlaced = reward.AutoPlaced,
			IsNewBest = reward.IsNewBestDistance,
			GemsEarned = reward.Gems.Total,
			GemsFromCatch = reward.Gems.FromCatch,
			GemsFromZone = reward.Gems.FromZone,
			GemsFromIndex = reward.Gems.FromIndex,
		})
	end)
end

return ThrowService
