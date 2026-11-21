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
	"RequestPurchase", -- C->S { ItemId: string, Quantity: number | "max" }: every shop purchase
	"TrainingState", -- S->C { Active: boolean, Interval: number? }: pull-up loop started/stopped
	"TrainingRep", -- S->C { Gained: number, Power: number, Interval: number }: one rep paid
	"RequestStopTraining", -- C->S: player jumped/moved off the bar
	"TrainingBonus", -- S->C { Id: number, Window: number }: a Bonus Rep pop-up is available
	"RequestBonusRep", -- C->S { Id: number }: player clicked the Bonus Rep pop-up
	"RequestEquipSlime",
	"RequestPlaceBestSlimes",
	"RequestPlaceOnSlot",
	"RequestPickupFromSlot",
	"RequestEquipTrail",
	"RequestClaimDaily", -- C->S: manual daily reward claim on the 7-day calendar
	"RequestClaimQuest", -- C->S { Kind = "Line" | "Daily", Index: number? }: claim completed quest
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
