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
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))

local MonetizationService = {}

local checkedPassesForPlayer: { [Player]: boolean } = {}

-- Gifting: the buyer asks to gift an item to another player in the same server (RequestGift). The server validates and
-- remembers the intent; when the developer product receipt arrives, the item goes to the target instead of the buyer.
type GiftIntent = { Target: number, ProductId: number, Expires: number }
local giftIntents: { [number]: GiftIntent } = {}
local GIFT_INTENT_SECONDS = 180

local function pushProcessedReceipt(profile: ProgressionLogic.PlayerProfile, purchaseId: string)
	profile.ProcessedReceipts = profile.ProcessedReceipts or {}
	if not table.find(profile.ProcessedReceipts, purchaseId) then
		table.insert(profile.ProcessedReceipts, purchaseId)
		while #profile.ProcessedReceipts > GameConfig.Robux.MaxProcessedReceipts do
			table.remove(profile.ProcessedReceipts, 1)
		end
	end
end

local function checkPlayerGamePasses(player: Player, profile: ProgressionLogic.PlayerProfile, syncIfChanged: boolean?)
	local changed = false
	local allOk = true
	for _, pass in GameConfig.Robux.Passes do
		if pass.PassId > 0 and not profile.OwnedPasses[pass.Id] then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.PassId)
			if not ok then
				allOk = false
			elseif owns == true then
				profile.OwnedPasses[pass.Id] = true
				changed = true
			end
		end
	end
	if allOk then
		checkedPassesForPlayer[player] = true
	end
	if syncIfChanged and changed and player.Parent then
		PlayerStateService.Sync(player)
	end
end

function MonetizationService.CheckPasses(player: Player, profile: ProgressionLogic.PlayerProfile)
	if not checkedPassesForPlayer[player] then
		checkPlayerGamePasses(player, profile, false)
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

	-- Welcome Back "2X" developer product
	if GameConfig.Offline.DoubleProductId > 0 and receiptInfo.ProductId == GameConfig.Offline.DoubleProductId then
		local claimed, claimedAmount, awaySeconds = PlayerStateService.ClaimOffline(player, 2)
		if claimed then
			pushProcessedReceipt(profile, purchaseId)
			if DataService.CanSave(player) and not DataService.Save(player, profile) then
				profile.Cash = math.max(0, profile.Cash - claimedAmount)
				local idx = table.find(profile.ProcessedReceipts, purchaseId)
				if idx then
					table.remove(profile.ProcessedReceipts, idx)
				end
				PlayerStateService.RestoreOfflineOffer(player, math.floor(claimedAmount / 2), awaySeconds)
				PlayerStateService.Sync(player)
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local pack = GameConfig.RobuxGemPacksByProductId[receiptInfo.ProductId]
	local eggOrder = GameConfig.RobuxEggsByProductId[receiptInfo.ProductId]
	if not pack and not eggOrder then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Gift: grant to the target player's profile when a valid intent exists, otherwise to the buyer
	local intent = giftIntents[receiptInfo.PlayerId]
	local recipient: Player? = nil
	local hasActiveGiftIntent = intent ~= nil and intent.ProductId == receiptInfo.ProductId and os.time() <= intent.Expires
	if hasActiveGiftIntent and intent then
		recipient = Players:GetPlayerByUserId(intent.Target)
		if not recipient or not PlayerStateService.GetProfile(recipient) then
			PlayerStateService.Toast(player, "Gift recipient left the server before receipt completed; retrying...", "warn")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	local recipientProfile = if recipient then PlayerStateService.GetProfile(recipient) else nil
	local grantPlayer: Player = if recipient and recipientProfile then recipient else player
	local grantProfile: ProgressionLogic.PlayerProfile = if recipient and recipientProfile then recipientProfile else profile
	local isGift = grantPlayer ~= player

	-- Snapshot profile state in case DataService.Save fails and we need Roblox to retry
	local prevGems = grantProfile.Gems
	local prevUnplacedCount = #grantProfile.UnplacedSlimes
	local prevNextUid = grantProfile.NextUid
	local prevMilestones = grantProfile.IndexMilestonesClaimed
	local prevDiscovered = table.clone(grantProfile.DiscoveredSlimes)

	local ok = false
	local msg = ""
	if pack then
		local granted, _, packMsg = ProgressionLogic.GrantRobuxGemPack(grantProfile, pack.Id, purchaseId)
		ok = granted
		msg = packMsg
	elseif eggOrder then
		local granted, eggMsg = ProgressionLogic.GrantRobuxEgg(grantProfile, eggOrder.EggId, eggOrder.Count, purchaseId)
		ok = granted
		msg = eggMsg
	end

	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- A gift is also recorded on the buyer's receipts so a retried callback is recognised
	if isGift then
		pushProcessedReceipt(profile, purchaseId)
	end

	-- Save immediately before returning PurchaseGranted when saving is active for this session.
	-- Save the recipient first so the gift is persisted before the buyer's deduplication receipt is committed.
	local savedAll = true
	if isGift and DataService.CanSave(grantPlayer) then
		savedAll = DataService.Save(grantPlayer, grantProfile)
	end
	if savedAll and DataService.CanSave(player) then
		savedAll = DataService.Save(player, profile)
	end
	if not savedAll then
		-- Roll back in-memory grant so Roblox retries ProcessReceipt cleanly
		grantProfile.Gems = prevGems
		grantProfile.NextUid = prevNextUid
		grantProfile.IndexMilestonesClaimed = prevMilestones
		grantProfile.DiscoveredSlimes = prevDiscovered
		while #grantProfile.UnplacedSlimes > prevUnplacedCount do
			table.remove(grantProfile.UnplacedSlimes)
		end
		ProgressionLogic.SyncLegacyArrays(grantProfile)
		for _, p in { profile, grantProfile } do
			local idx = table.find(p.ProcessedReceipts, purchaseId)
			if idx then
				table.remove(p.ProcessedReceipts, idx)
			end
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	giftIntents[receiptInfo.PlayerId] = nil
	if isGift then
		PlayerStateService.Toast(player, `Gift sent to {grantPlayer.DisplayName}!`, "success")
		PlayerStateService.Toast(grantPlayer, `{player.DisplayName} gifted you: {msg}`, "gems")
		PlayerStateService.Sync(grantPlayer)
	else
		PlayerStateService.Toast(player, msg, "gems")
	end
	PlayerStateService.Sync(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Validates a gift request and remembers it until the receipt arrives. Returns the product id to prompt, or nil.
local function startGift(player: Player, payload: any): number?
	if type(payload) ~= "table" or type(payload.TargetUserId) ~= "number" then
		return nil
	end
	local target = Players:GetPlayerByUserId(payload.TargetUserId)
	if not target or target == player or not PlayerStateService.GetProfile(target) then
		PlayerStateService.Toast(player, "That player is not in this server.", "warn")
		return nil
	end
	local productId = 0
	if payload.Kind == "pack" and type(payload.ItemId) == "string" then
		local pack = GameConfig.RobuxGemPacksById[payload.ItemId]
		productId = if pack then pack.ProductId else 0
	elseif payload.Kind == "egg" and type(payload.ItemId) == "string" then
		local egg = GameConfig.ShopEggsById[payload.ItemId]
		if egg then
			productId = if payload.Count == 3 then egg.Buy3ProductId else egg.Buy1ProductId
		end
	end
	if productId <= 0 then
		PlayerStateService.Toast(player, "That item can't be gifted yet.", "warn")
		return nil
	end
	giftIntents[player.UserId] = { Target = target.UserId, ProductId = productId, Expires = os.time() + GIFT_INTENT_SECONDS }
	return productId
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt
	PlayerStateService.SetPassChecker(MonetizationService.CheckPasses)

	Remotes.GetEvent("RequestGift").OnServerEvent:Connect(function(player: Player, payload: any)
		local productId = startGift(player, payload)
		if productId then
			Remotes.GetEvent("GiftReady"):FireClient(player, { ProductId = productId })
		end
	end)

	PlayerStateService.OnProfileChanged(function(player: Player, profile: ProgressionLogic.PlayerProfile)
		if not checkedPassesForPlayer[player] then
			checkPlayerGamePasses(player, profile, true)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		checkedPassesForPlayer[player] = nil
		giftIntents[player.UserId] = nil
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
