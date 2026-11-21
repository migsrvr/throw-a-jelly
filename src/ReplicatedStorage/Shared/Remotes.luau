--!strict
--[[
	Remotes.luau
	Creates (on Server) and retrieves (on Client) the typed RemoteEvents folder.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local EVENT_NAMES = {
	"RequestThrow",
	"ThrowBroadcast",
	"PlayerStateSync",
	"RequestUpgrade",
	"RequestTrainRep",
	"RequestEquipSlime",
	"RequestPlaceBestSlimes",
	"RequestPlaceOnSlot",
	"RequestPickupFromSlot",
	"RequestClaimFreeGift",
	"RequestHatchEgg",
	"RequestBuyBoost",
	"RequestEquipTrail",
	"RequestCollect",
	"RequestTeleport",
	"ToastNotify",
}

local folderCache: Folder? = nil

function Remotes.Init(): Folder
	if folderCache then
		return folderCache
	end

	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		for _, name in EVENT_NAMES do
			if not folder:FindFirstChild(name) then
				local ev = Instance.new("RemoteEvent")
				ev.Name = name
				ev.Parent = folder
			end
		end
		folderCache = folder
		return folder
	else
		local folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
		for _, name in EVENT_NAMES do
			folder:WaitForChild(name)
		end
		folderCache = folder
		return folder
	end
end

function Remotes.GetEvent(name: string): RemoteEvent
	local folder = Remotes.Init()
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
