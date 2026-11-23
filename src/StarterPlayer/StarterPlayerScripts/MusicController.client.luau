--!strict
--[[
	MusicController.client.luau
	Background music on this device. Plays GameConfig.Music.Tracks (Roblox audio asset ids) in a shuffled loop
	through one local Sound in SoundService. With no tracks configured it does nothing.

	On / off follows the LocalPlayer attribute "MusicOn": the saved setting sets it (PlayerStateSync.MusicOn), and
	the Settings window sets it right away when tapped. Off pauses the track, on resumes it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

-- Saved setting from the server
Remotes.GetEvent("PlayerStateSync").OnClientEvent:Connect(function(state: any)
	if type(state) == "table" and type(state.MusicOn) == "boolean" and player:GetAttribute("MusicOn") ~= state.MusicOn then
		player:SetAttribute("MusicOn", state.MusicOn)
	end
end)

local tracks = GameConfig.Music.Tracks
if #tracks == 0 then
	return -- no music added yet
end

local sound = Instance.new("Sound")
sound.Name = "BackgroundMusic"
sound.Volume = GameConfig.Music.Volume
sound.Looped = false
sound.Parent = SoundService

local order: { number } = {}
local index = 0

local function shuffle()
	order = table.clone(tracks)
	for i = #order, 2, -1 do
		local j = math.random(1, i)
		order[i], order[j] = order[j], order[i]
	end
	index = 0
end

local function musicOn(): boolean
	return player:GetAttribute("MusicOn") ~= false -- on until the saved setting says otherwise
end

local function playNext()
	index += 1
	if index > #order then
		shuffle()
		index = 1
	end
	sound.SoundId = "rbxassetid://" .. tostring(order[index])
	sound.TimePosition = 0
	if musicOn() then
		sound:Play()
	end
end

sound.Ended:Connect(playNext)

player:GetAttributeChangedSignal("MusicOn"):Connect(function()
	if musicOn() then
		if sound.IsPaused then
			sound:Resume()
		elseif not sound.IsPlaying then
			sound:Play()
		end
	else
		sound:Pause()
	end
end)

shuffle()
playNext()
