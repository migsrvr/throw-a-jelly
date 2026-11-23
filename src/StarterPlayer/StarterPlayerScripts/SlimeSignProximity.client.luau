--!strict
--[[
	SlimeSignProximity.client.luau
	Slime info signs (name / income) follow their roaming slime, but are only visible while the local
	player is standing right next to it. The server marks those billboards with ProximityOnly = true.
	MOBILE: the tagged signs are kept in a set (CollectionService signals, no GetTagged every frame) and
	checked at CHECK_HZ instead of every Heartbeat.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SHOW_WITHIN = 12 -- studs from the player's character
local HIDE_BEYOND = 15 -- a little larger so the sign doesn't flicker at the edge
local CHECK_HZ = 8

local player = Players.LocalPlayer
local signs: { [BillboardGui]: true } = {}

local function track(inst: Instance)
	if inst:IsA("BillboardGui") then
		signs[inst] = true
	end
end

for _, inst in CollectionService:GetTagged("WorldSign") do
	track(inst)
end
CollectionService:GetInstanceAddedSignal("WorldSign"):Connect(track)
CollectionService:GetInstanceRemovedSignal("WorldSign"):Connect(function(inst)
	signs[inst :: BillboardGui] = nil
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt: number)
	acc += dt
	if acc < 1 / CHECK_HZ then
		return
	end
	acc = 0

	local character = player.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local playerPos = if hrp and hrp:IsA("BasePart") then hrp.Position else nil

	for inst in signs do
		if not inst.Parent then
			signs[inst] = nil
		elseif inst:GetAttribute("ProximityOnly") == true then
			local adornee = inst.Adornee
			local want: boolean
			if not playerPos or not adornee or not adornee:IsA("BasePart") then
				want = false
			else
				local dist = (adornee.Position - playerPos).Magnitude
				want = if inst.Enabled then dist <= HIDE_BEYOND else dist <= SHOW_WITHIN
			end
			if inst.Enabled ~= want then
				inst.Enabled = want
			end
		end
	end
end)
