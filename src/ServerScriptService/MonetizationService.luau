--!strict
--[[
	MonetizationService.luau
	Server-authoritative Robux monetization handler:
	- MarketplaceService.ProcessReceipt for Developer Products (Gem packs).
	  Uses ProgressionLogic.GrantRobuxGemPack (with ProcessedReceipts deduplication) and saves immediately
	  via DataService.Save before returning Enum.ProductPurchaseDecision.PurchaseGranted.
	- Game Pass ownership checks on profile load (UserOwnsGamePassAsync) and live purchase listener
	  (PromptGamePassPurchaseFinished), stored in runtime-only profile.OwnedPasses.
	- Any item whose ProductId/PassId is 0 in GameConfig.Robux is skipped until real Roblox asset IDs are configured.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))

local MonetizationService = {}

local checkedPassesForPlayer: { [Player]: boolean } = {}

local function checkPlayerGamePasses(player: Player, profile: ProgressionLogic.PlayerProfile)
	local changed = false
	for _, pass in GameConfig.Robux.Passes do
		if pass.PassId > 0 and not profile.OwnedPasses[pass.Id] then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.PassId)
			if ok and owns == true then
				profile.OwnedPasses[pass.Id] = true
				changed = true
			end
		end
	end
	if changed and player.Parent then
		PlayerStateService.Sync(player)
	end
end

local function processReceipt(receiptInfo: {
	PlayerId: number,
	ProductId: number,
	PurchaseId: string,
}): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = PlayerStateService.GetProfile(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	-- Already granted and saved in an earlier callback for this receipt
	if table.find(profile.ProcessedReceipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local pack = GameConfig.RobuxGemPacksByProductId[receiptInfo.ProductId]
	local eggOrder = GameConfig.RobuxEggsByProductId[receiptInfo.ProductId]
	if not pack and not eggOrder then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Snapshot profile state in case DataService.Save fails and we need Roblox to retry
	local prevGems = profile.Gems
	local prevUnplacedCount = #profile.UnplacedSlimes
	local prevNextUid = profile.NextUid
	local prevMilestones = profile.IndexMilestonesClaimed
	local prevDiscovered = table.clone(profile.DiscoveredSlimes)

	local ok = false
	local msg = ""
	if pack then
		local granted, _, packMsg = ProgressionLogic.GrantRobuxGemPack(profile, pack.Id, purchaseId)
		ok = granted
		msg = packMsg
	elseif eggOrder then
		local granted, eggMsg = ProgressionLogic.GrantRobuxEgg(profile, eggOrder.EggId, eggOrder.Count, purchaseId)
		ok = granted
		msg = eggMsg
	end

	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Save immediately before returning PurchaseGranted when saving is active for this session
	if DataService.CanSave(player) then
		local saved = DataService.Save(player, profile)
		if not saved then
			-- Roll back in-memory grant so Roblox retries ProcessReceipt cleanly
			profile.Gems = prevGems
			profile.NextUid = prevNextUid
			profile.IndexMilestonesClaimed = prevMilestones
			profile.DiscoveredSlimes = prevDiscovered
			while #profile.UnplacedSlimes > prevUnplacedCount do
				table.remove(profile.UnplacedSlimes)
			end
			ProgressionLogic.SyncLegacyArrays(profile)
			local idx = table.find(profile.ProcessedReceipts, purchaseId)
			if idx then
				table.remove(profile.ProcessedReceipts, idx)
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end

	PlayerStateService.Toast(player, msg, "gems")
	PlayerStateService.Sync(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt

	PlayerStateService.OnProfileChanged(function(player: Player, profile: ProgressionLogic.PlayerProfile)
		if not checkedPassesForPlayer[player] then
			checkedPassesForPlayer[player] = true
			checkPlayerGamePasses(player, profile)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		checkedPassesForPlayer[player] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if not wasPurchased or not player then
				return
			end
			local pass = GameConfig.RobuxPassesByPassId[gamePassId]
			local profile = PlayerStateService.GetProfile(player)
			if not pass or not profile then
				return
			end
			profile.OwnedPasses[pass.Id] = true
			PlayerStateService.Toast(player, `Unlocked {pass.Name} Pass!`, "gems")
			PlayerStateService.Sync(player)
		end
	)
end

return MonetizationService
