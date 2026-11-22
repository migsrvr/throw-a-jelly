--!strict
--[[
	SlimeSignProximity.client.luau
	Slime info signs (name / income) follow their roaming slime, but are only visible while the local
	player is standing right next to it. The server marks those billboards with ProximityOnly = true.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SHOW_WITHIN = 12 -- studs from the player's character
local HIDE_BEYOND = 15 -- a little larger so the sign doesn't flicker at the edge

local player = Players.LocalPlayer

RunService.Heartbeat:Connect(function()
	local character = player.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local playerPos = if hrp and hrp:IsA("BasePart") then hrp.Position else nil

	for _, inst in CollectionService:GetTagged("WorldSign") do
		if inst:IsA("BillboardGui") and inst:GetAttribute("ProximityOnly") == true then
			local adornee = inst.Adornee
			if not playerPos or not adornee or not adornee:IsA("BasePart") then
				inst.Enabled = false
			else
				local dist = (adornee.Position - playerPos).Magnitude
				if inst.Enabled then
					inst.Enabled = dist <= HIDE_BEYOND
				else
					inst.Enabled = dist <= SHOW_WITHIN
				end
			end
		end
	end
end)
