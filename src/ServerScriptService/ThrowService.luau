--!strict
--[[
	ThrowService.luau
	Validates throw requests, executes authoritative ThrowPhysics simulation,
	awards zone Cash & Slime drops via ProgressionLogic, and broadcasts
	ThrowBroadcast for smooth 60fps client visualization.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
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

		local chargeRatio = 0.75
		local pitchDeg = GameConfig.Physics.DefaultPitchDeg
		local yawDeg = 0

		if type(payload) == "table" then
			if type(payload.ChargeRatio) == "number" then
				chargeRatio = math.clamp(payload.ChargeRatio, 0.15, 1.0)
			end
			if type(payload.PitchDeg) == "number" then
				pitchDeg = math.clamp(payload.PitchDeg, GameConfig.Physics.MinPitchDeg, GameConfig.Physics.MaxPitchDeg)
			end
			if type(payload.YawDeg) == "number" then
				yawDeg = math.clamp(payload.YawDeg, -GameConfig.Physics.MaxYawDeg, GameConfig.Physics.MaxYawDeg)
			end
		end

		local launchX = 0
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			launchX = math.clamp(root.Position.X, -GameConfig.Hub.ClearHalfWidth + 2, GameConfig.Hub.ClearHalfWidth - 2)
		end

		local origin = Vector3.new(launchX, GameConfig.Hub.FloorY + 1.8, GameConfig.Hub.ThrowLineZ)
		local effectivePower = ProgressionLogic.GetEffectiveThrowPower(profile)
		local equippedDef = GameConfig.SlimesById[profile.EquippedSlimeId] or GameConfig.Slimes[1]

		local simResult = ThrowPhysics.Simulate({
			Origin = origin,
			ThrowPower = effectivePower,
			ChargeRatio = chargeRatio,
			PitchDeg = pitchDeg,
			YawDeg = yawDeg,
			SlimeWeight = equippedDef.Weight,
		})

		local reward = ProgressionLogic.EvaluateThrowReward(
			profile,
			simResult.Distance,
			simResult.LandedZoneIndex,
			nil
		)

		PlayerStateService.Sync(player)

		local zoneDef = GameConfig.Zones[simResult.LandedZoneIndex] or GameConfig.Zones[1]
		local blockedZone = if simResult.BlockedByZoneIndex then GameConfig.Zones[simResult.BlockedByZoneIndex] else nil

		throwBroadcast:FireAllClients({
			PlayerUserId = player.UserId,
			PlayerName = player.DisplayName,
			Origin = origin,
			ThrowPower = effectivePower,
			ChargeRatio = chargeRatio,
			PitchDeg = pitchDeg,
			YawDeg = yawDeg,
			SlimeId = equippedDef.Id,
			SlimeWeight = equippedDef.Weight,
			Distance = simResult.Distance,
			LandedZoneName = zoneDef.Name,
			LandedZoneIndex = simResult.LandedZoneIndex,
			HitGate = simResult.HitGate,
			BlockedByZoneName = if blockedZone then blockedZone.Name else nil,
			BlockedRequiredPower = if blockedZone then blockedZone.RequiredThrowPower else nil,
			CashEarned = reward.CashEarned,
			CaughtSlimeId = reward.CaughtSlimeId,
			CaughtSlimeName = reward.CaughtSlimeDef.Name,
			CaughtSlimeRarity = reward.CaughtSlimeDef.Rarity,
			AutoPlaced = reward.AutoPlaced,
			IsNewBest = reward.IsNewBestDistance,
		})
	end)
end

return ThrowService
