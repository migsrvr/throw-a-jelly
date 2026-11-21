--!strict
--[[
	ThrowService.luau
	Validates throw requests from the 9-segment vertical meter, computes authoritative
	ThrowPhysics trajectory, rolls caught Slime + Mutation + "1 in X" odds via
	ProgressionLogic (placing caught slimes into the player's Hotbar), and broadcasts
	ThrowBroadcast for the flight camera & cinematic reveal cutscene.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local QuestLogic = require(Shared:WaitForChild("QuestLogic"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ThrowPhysics = require(Shared:WaitForChild("ThrowPhysics"))

local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))

local ThrowService = {}

local lastThrowTime: { [Player]: number } = {}

function ThrowService.Init()
	local requestThrow = Remotes.GetEvent("RequestThrow")
	local throwBroadcast = Remotes.GetEvent("ThrowBroadcast")

	requestThrow.OnServerEvent:Connect(function(player: Player, payload: any)
		local now = os.clock()
		if lastThrowTime[player] and now - lastThrowTime[player] < 0.75 then
			return
		end
		lastThrowTime[player] = now

		local profile = PlayerStateService.GetProfile(player)
		if not profile then
			return
		end

		local meterRatio = 0.75
		local pitchDeg = GameConfig.Physics.DefaultPitchDeg
		local yawDeg = 0
		local isAuto = type(payload) == "table" and payload.Auto == true

		-- Auto-Throw is a Gem unlock; auto throws always use the fixed AutoThrow meter ratio
		if isAuto and not profile.OwnedBoosts.auto_throw then
			return
		end

		if type(payload) == "table" then
			if isAuto then
				meterRatio = GameConfig.AutoThrow.MeterRatio
			elseif type(payload.ChargeRatio) == "number" then
				meterRatio = math.clamp(payload.ChargeRatio, 0, 1)
			end
			if type(payload.PitchDeg) == "number" then
				pitchDeg = math.clamp(payload.PitchDeg, GameConfig.Physics.MinPitchDeg, GameConfig.Physics.MaxPitchDeg)
			end
			if type(payload.YawDeg) == "number" then
				yawDeg = math.clamp(payload.YawDeg, -GameConfig.Physics.MaxYawDeg, GameConfig.Physics.MaxYawDeg)
			end
		end

		local meterSeg = GameConfig.EvaluateMeterRatio(meterRatio)

		local launchX = 0
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			launchX = math.clamp(root.Position.X, -GameConfig.Hub.ClearHalfWidth + 2, GameConfig.Hub.ClearHalfWidth - 2)
		end

		local origin = Vector3.new(launchX, GameConfig.Hub.FloorY + 1.8, GameConfig.Hub.ThrowLineZ)
		local effectivePower = ProgressionLogic.GetEffectiveThrowPower(profile) + meterSeg.BonusPower
		local equippedDef = GameConfig.SlimesById[profile.EquippedSlimeId] or GameConfig.Slimes[1]

		local simResult = ThrowPhysics.Simulate({
			Origin = origin,
			ThrowPower = effectivePower,
			ChargeRatio = math.clamp(0.35 + 0.65 * meterRatio, 0.25, 1.0),
			PitchDeg = pitchDeg,
			YawDeg = yawDeg,
			SlimeWeight = equippedDef.Weight,
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

		throwBroadcast:FireAllClients({
			PlayerUserId = player.UserId,
			PlayerName = player.DisplayName,
			Origin = origin,
			ThrowPower = effectivePower,
			ChargeRatio = math.clamp(0.35 + 0.65 * meterRatio, 0.25, 1.0),
			MeterRatio = meterRatio,
			BonusPower = meterSeg.BonusPower,
			LuckMultiplier = totalLuck,
			MeterLuck = meterSeg.LuckMultiplier,
			BaitLuck = baitDef.LuckMultiplier,
			BoostLuck = boostLuck,
			IsAuto = isAuto,
			BaitTier = profile.BaitTier,
			BaitName = baitDef.Name,
			IsPerfect = meterSeg.IsPerfect == true,
			PitchDeg = pitchDeg,
			YawDeg = yawDeg,
			SlimeId = equippedDef.Id,
			SlimeWeight = equippedDef.Weight,
			Distance = simResult.Distance,
			LandedZoneName = zoneDef.Name,
			LandedZoneEmoji = zoneDef.Emoji,
			LandedZoneIndex = simResult.LandedZoneIndex,
			HitGate = simResult.HitGate,
			BlockedByZoneName = if blockedZone then blockedZone.Name else nil,
			BlockedRequiredPower = if blockedZone then blockedZone.RequiredThrowPower else nil,
			CashEarned = reward.CashEarned,
			CaughtSlimeId = reward.CaughtSlimeId,
			CaughtSlimeName = reward.CaughtSlimeDef.Name,
			CaughtShortWord = reward.CaughtSlimeDef.ShortWord,
			CaughtSlimeRarity = reward.CaughtSlimeDef.Rarity,
			CaughtMutation = reward.Mutation,
			CaughtIncomePerSec = reward.CaughtInstance.IncomePerSec,
			OddsOneInX = reward.OddsOneInX,
			IsSuperLucky = reward.IsSuperLucky,
			IsNewDiscovery = reward.IsNewDiscovery,
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
