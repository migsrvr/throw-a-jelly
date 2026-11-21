--!strict
--[[
	PlayerStateService.luau
	Manages per-player profiles, Roblox leaderstats, and state replication
	for Hotbar/Slot placement, Slime Index, Shop Eggs, Boosts, and Free Gift.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerStateService = {}

local profiles: { [Player]: ProgressionLogic.PlayerProfile } = {}
local listeners: { (Player, ProgressionLogic.PlayerProfile) -> () } = {}

local function ensureLeaderstats(player: Player)
	local ls = player:FindFirstChild("leaderstats") :: Folder?
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end

	local function ensureInt(name: string): IntValue
		local v = ls:FindFirstChild(name) :: IntValue?
		if not v then
			v = Instance.new("IntValue")
			v.Name = name
			v.Parent = ls
		end
		return v
	end

	ensureInt("Cash")
	ensureInt("ThrowPower")
	ensureInt("BestThrow")
end

function PlayerStateService.GetProfile(player: Player): ProgressionLogic.PlayerProfile?
	return profiles[player]
end

function PlayerStateService.GetAllProfiles(): { [Player]: ProgressionLogic.PlayerProfile }
	return profiles
end

function PlayerStateService.OnProfileChanged(fn: (Player, ProgressionLogic.PlayerProfile) -> ())
	table.insert(listeners, fn)
end

function PlayerStateService.Sync(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	local effPower = ProgressionLogic.GetEffectiveThrowPower(profile)
	local incomePerSec = ProgressionLogic.GetIncomePerSecond(profile)

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cashVal = ls:FindFirstChild("Cash") :: IntValue?
		local powerVal = ls:FindFirstChild("ThrowPower") :: IntValue?
		local bestVal = ls:FindFirstChild("BestThrow") :: IntValue?
		if cashVal then
			cashVal.Value = math.floor(profile.Cash)
		end
		if powerVal then
			powerVal.Value = effPower
		end
		if bestVal then
			bestVal.Value = math.floor(profile.BestDistance)
		end
	end

	-- Serialize PlacedSlimesBySlot with string keys so RemoteEvent table replication never drops sparse integer keys
	local placedBySlotStr: { [string]: ProgressionLogic.SlimeInstance } = {}
	for slot, inst in profile.PlacedSlimesBySlot do
		placedBySlotStr[tostring(slot)] = inst
	end

	local syncEvent = Remotes.GetEvent("PlayerStateSync")
	syncEvent:FireClient(player, {
		Cash = profile.Cash,
		BaseThrowPower = profile.BaseThrowPower,
		PowerUpgradeLevel = profile.PowerUpgradeLevel,
		EffectiveThrowPower = effPower,
		NextPowerCost = GameConfig.GetPowerUpgradeCost(profile.PowerUpgradeLevel),
		PullUpTier = profile.PullUpTier,
		MaxSlimes = profile.MaxSlimes,
		BestDistance = profile.BestDistance,
		EquippedSlimeId = profile.EquippedSlimeId,
		OwnedSlimes = profile.OwnedSlimes,
		PlacedSlimes = profile.PlacedSlimes,
		UnplacedSlimes = profile.UnplacedSlimes,
		PlacedSlimesBySlot = placedBySlotStr,
		DiscoveredSlimes = profile.DiscoveredSlimes,
		EquippedTrailZone = profile.EquippedTrailZone,
		ClaimedFreeGift = profile.ClaimedFreeGift,
		OwnedBoosts = profile.OwnedBoosts,
		TotalThrows = profile.TotalThrows,
		TotalPullUps = profile.TotalPullUps,
		PendingIncome = math.floor(profile.PendingIncome),
		IncomePerSec = incomePerSec,
	})

	for _, fn in listeners do
		task.spawn(fn, player, profile)
	end
end

function PlayerStateService.Toast(player: Player, message: string, kind: string?)
	Remotes.GetEvent("ToastNotify"):FireClient(player, {
		Message = message,
		Kind = kind or "info",
	})
end

function PlayerStateService.Init()
	local function onPlayerAdded(player: Player)
		profiles[player] = ProgressionLogic.CreateInitialProfile()
		ensureLeaderstats(player)
		task.defer(function()
			if player.Parent then
				PlayerStateService.Sync(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		profiles[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Remotes.GetEvent("RequestUpgrade").OnServerEvent:Connect(function(player: Player, payload: any)
		local profile = profiles[player]
		if not profile or type(payload) ~= "table" then
			return
		end
		local upgradeType = payload.UpgradeType
		local ok, msg = false, "Invalid upgrade"
		if upgradeType == "ThrowPower" then
			ok, msg = ProgressionLogic.PurchasePowerUpgrade(profile)
		elseif upgradeType == "PullUpTier" then
			ok, msg = ProgressionLogic.PurchasePullUpTier(profile)
		elseif upgradeType == "SlotExpansion" then
			ok, msg = ProgressionLogic.PurchaseSlotExpansion(profile)
		end
		PlayerStateService.Toast(player, msg, if ok then "success" else "warn")
		if ok then
			PlayerStateService.Sync(player)
		end
	end)

	Remotes.GetEvent("RequestEquipSlime").OnServerEvent:Connect(function(player: Player, payload: any)
		local profile = profiles[player]
		if not profile or type(payload) ~= "table" or type(payload.SlimeId) ~= "string" then
			return
		end
		local ok, msg = ProgressionLogic.EquipSlime(profile, payload.SlimeId)
		PlayerStateService.Toast(player, msg, if ok then "success" else "warn")
		if ok then
			PlayerStateService.Sync(player)
		end
	end)

	Remotes.GetEvent("RequestPlaceBestSlimes").OnServerEvent:Connect(function(player: Player)
		local profile = profiles[player]
		if not profile then
			return
		end
		ProgressionLogic.PlaceBestSlimes(profile)
		PlayerStateService.Toast(player, "Placed your highest-earning slimes on your plot!", "success")
		PlayerStateService.Sync(player)
	end)

	Remotes.GetEvent("RequestPlaceOnSlot").OnServerEvent:Connect(function(player: Player, payload: any)
		local profile = profiles[player]
		if not profile or type(payload) ~= "table" then
			return
		end
		local uid = payload.SlimeUid
		local slotIdx = tonumber(payload.SlotIndex)
		if type(uid) == "string" and slotIdx then
			local ok, msg = ProgressionLogic.PlaceSlimeAtSlot(profile, uid, slotIdx)
			PlayerStateService.Toast(player, msg, if ok then "success" else "warn")
			if ok then
				PlayerStateService.Sync(player)
			end
		end
	end)

	Remotes.GetEvent("RequestPickupFromSlot").OnServerEvent:Connect(function(player: Player, payload: any)
		local profile = profiles[player]
		if not profile or type(payload) ~= "table" then
			return
		end
		local slotIdx = tonumber(payload.SlotIndex)
		if slotIdx then
			local ok, msg = ProgressionLogic.PickupSlimeFromSlot(profile, slotIdx)
			PlayerStateService.Toast(player, msg, if ok then "info" else "warn")
			if ok then
				PlayerStateService.Sync(player)
			end
		end
	end)

	Remotes.GetEvent("RequestClaimFreeGift").OnServerEvent:Connect(function(player: Player)
		local profile = profiles[player]
		if not profile then
			return
		end
		local ok, msg = ProgressionLogic.ClaimFreeGiftSlime(profile)
		PlayerStateService.Toast(player, msg, if ok then "success" else "warn")
		if ok then
			PlayerStateService.Sync(player)
		end
	end)

	Remotes.GetEvent("RequestBuyBoost").OnServerEvent:Connect(function(player: Player, payload: any)
		local profile = profiles[player]
		if not profile or type(payload) ~= "table" or type(payload.BoostId) ~= "string" then
			return
		end
		local ok, msg = ProgressionLogic.PurchaseShopBoost(profile, payload.BoostId)
		PlayerStateService.Toast(player, msg, if ok then "success" else "warn")
		if ok then
			PlayerStateService.Sync(player)
		end
	end)

	Remotes.GetEvent("RequestHatchEgg").OnServerEvent:Connect(function(player: Player, payload: any)
		local profile = profiles[player]
		if not profile or type(payload) ~= "table" or type(payload.EggId) ~= "string" then
			return
		end
		local count = if payload.Count == 3 then 3 else 1
		local ok, msg = ProgressionLogic.HatchShopEgg(profile, payload.EggId, count, nil)
		PlayerStateService.Toast(player, msg, if ok then "success" else "warn")
		if ok then
			PlayerStateService.Sync(player)
		end
	end)

	Remotes.GetEvent("RequestEquipTrail").OnServerEvent:Connect(function(player: Player, payload: any)
		local profile = profiles[player]
		if not profile or type(payload) ~= "table" then
			return
		end
		local zIdx = tonumber(payload.ZoneIndex)
		if zIdx then
			local ok, msg = ProgressionLogic.EquipZoneTrail(profile, zIdx)
			PlayerStateService.Toast(player, msg, if ok then "success" else "warn")
			if ok then
				PlayerStateService.Sync(player)
			end
		end
	end)
end

return PlayerStateService
