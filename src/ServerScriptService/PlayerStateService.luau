--!strict
--[[
	PlayerStateService.luau
	Manages per-player profiles, Roblox leaderstats, and state replication
	for Hotbar/Slot placement, Slime Index, Shop Eggs, Boosts, and Free Gift.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))

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
		PullUpRepInterval = ProgressionLogic.GetPullUpRepInterval(profile),
		StrengthLevel = profile.StrengthLevel,
		TrainingXP = profile.TrainingXP,
		TrainingXPRequired = GameConfig.GetXPRequiredForLevel(profile.StrengthLevel),
		BaitTier = profile.BaitTier,
		Gems = profile.Gems,
		IndexMilestonesClaimed = profile.IndexMilestonesClaimed,
		HighestZoneReached = profile.HighestZoneReached,
		DailyStreak = profile.DailyStreak,
		ProgressSaved = DataService.CanSave(player), -- false: this session won't be saved (load failed / Studio)
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

local PURCHASE_COOLDOWN = 0.15
local lastPurchaseAt: { [Player]: number } = {}

-- Shared purchase path: rate limit -> ProgressionLogic.Purchase -> toast -> sync.
function PlayerStateService.Purchase(player: Player, itemId: string, quantity: ProgressionLogic.ShopQuantity?): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local now = os.clock()
	if lastPurchaseAt[player] and now - lastPurchaseAt[player] < PURCHASE_COOLDOWN then
		return false
	end
	lastPurchaseAt[player] = now

	local ok, msg = ProgressionLogic.Purchase(profile, itemId, quantity)
	PlayerStateService.Toast(player, msg, if ok then "success" else "warn")
	if ok then
		PlayerStateService.Sync(player)
	end
	return ok
end

-- Daily login Gems (once per UTC day). Called on join and every minute, so players online across
-- midnight still get the next day's reward.
local function tryDailyReward(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local claimed, gems, streak = ProgressionLogic.ClaimDailyReward(profile, ProgressionLogic.GetDayNumber(os.time()))
	if claimed then
		PlayerStateService.Toast(player, `Daily reward: +{gems} Gems! (Day {streak} streak)`, "gems")
		PlayerStateService.Sync(player)
	end
end

function PlayerStateService.Init()
	local function onPlayerAdded(player: Player)
		ensureLeaderstats(player)
		local profile, loaded = DataService.Load(player) -- yields (DataStore); other services wait for GetProfile
		if not player.Parent then
			DataService.SaveAndRelease(player, nil) -- left while loading: nothing new to save
			return
		end
		profiles[player] = profile
		PlayerStateService.Sync(player)
		if not loaded then
			local msg = if RunService:IsStudio()
				then "Saving is off: File > Experience Settings > Security > enable Studio API access."
				else "Progress can't be saved this session."
			PlayerStateService.Toast(player, msg, "warn")
		end
		tryDailyReward(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		local profile = profiles[player]
		profiles[player] = nil
		lastPurchaseAt[player] = nil
		DataService.SaveAndRelease(player, profile)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	DataService.Start(PlayerStateService.GetAllProfiles)

	task.spawn(function()
		while true do
			task.wait(60)
			for player in profiles do
				tryDailyReward(player)
			end
		end
	end)

	-- Single entry point for every shop purchase (UI buttons, JellyShop prompt, UpgradeStand prompt)
	Remotes.GetEvent("RequestPurchase").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" or type(payload.ItemId) ~= "string" then
			return
		end
		local quantity: ProgressionLogic.ShopQuantity = 1
		if payload.Quantity == "max" then
			quantity = "max"
		elseif type(payload.Quantity) == "number" then
			quantity = payload.Quantity
		elseif payload.Quantity ~= nil then
			return
		end
		PlayerStateService.Purchase(player, payload.ItemId, quantity)
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
