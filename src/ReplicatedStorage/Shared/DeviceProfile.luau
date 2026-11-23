--!strict
--[[
	DeviceProfile.luau (client)
	Picks a detail tier (Low / Mid / High) so the game stays smooth on low-end phones. Everything that costs
	frame time reads Settings() from here: cutscene parts and particles, bloom, map light culling, plot slime
	animation radius, flower sway.

	Mode (the player's Settings window choice, saved in the profile as GraphicsMode):
	  "Auto"  tier from the Roblox graphics level (or phone = Mid, otherwise High), then a live FPS monitor
	          steps down one tier when the game runs below 35 fps for 5 s (15 s cooldown, never back up)
	  "Low"   always Low      "High"   always High
	On the server (or in tests) it simply reports High.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UiLayout = require(script.Parent:WaitForChild("UiLayout"))

export type Tier = "Low" | "Mid" | "High"
export type Mode = "Auto" | "Low" | "High"
export type TierSettings = {
	Particles: number, -- multiplier on particle rates and burst counts
	CutsceneParts: number, -- part budget for a catch cutscene set piece
	PostFx: boolean, -- bloom (map and cutscene)
	SlimeAnimRadius: number, -- plot slimes closer than this to the camera are animated
	LightRadius: number, -- map PointLights farther than this from the camera are switched off
	Sway: boolean, -- cutscene flowers keep swaying after they have grown
	AmbientCap: number, -- max zone Ambient particle boxes in a cutscene
	Detail: number, -- 0 = Low, 1 = Mid, 2 = High (set pieces scale extras with it)
	Shadows: boolean, -- world shadows (Lighting.GlobalShadows as designed)
	FlatLighting: boolean, -- no environment reflections, no atmosphere haze / glare
	HideTinyDecor: boolean, -- hide very small map decorations (pebbles, tiny flowers, embers)
	FogDensity: number?, -- Atmosphere.Density override (closer fog = shorter view distance); nil = as designed
}

local SETTINGS: { [Tier]: TierSettings } = {
	Low = {
		Particles = 0.4,
		CutsceneParts = 220,
		PostFx = false,
		SlimeAnimRadius = 60,
		LightRadius = 90,
		Sway = false,
		AmbientCap = 2,
		Detail = 0,
		Shadows = false,
		FlatLighting = true,
		HideTinyDecor = true,
		FogDensity = 0.38,
	},
	Mid = {
		Particles = 0.7,
		CutsceneParts = 360,
		PostFx = true,
		SlimeAnimRadius = 100,
		LightRadius = 160,
		Sway = true,
		AmbientCap = 99,
		Detail = 1,
		Shadows = true,
		FlatLighting = false,
		HideTinyDecor = false,
		FogDensity = nil,
	},
	High = {
		Particles = 1,
		CutsceneParts = 500,
		PostFx = true,
		SlimeAnimRadius = 150,
		LightRadius = math.huge,
		Sway = true,
		AmbientCap = 99,
		Detail = 2,
		Shadows = true,
		FlatLighting = false,
		HideTinyDecor = false,
		FogDensity = nil,
	},
}
local ORDER: { Tier } = { "Low", "Mid", "High" }

local FPS_WINDOW = 5 -- seconds averaged
local FPS_FLOOR = 35 -- below this (Auto mode) the tier steps down
local DOWNGRADE_COOLDOWN = 15
local WARMUP = 12 -- ignore the loading hitches right after joining

local DeviceProfile = {}

local changed = Instance.new("BindableEvent")
DeviceProfile.Changed = changed.Event -- fires (tier) whenever the effective tier changes

local mode: Mode = "Auto"
local penalty = 0 -- tiers dropped by the FPS monitor (Auto only)
local current: Tier = "High"
local started = false

local function tierIndex(t: Tier): number
	return table.find(ORDER, t) or 3
end

-- Tier from the device alone (Roblox graphics level, else phone vs. not)
local function baseTier(): Tier
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and level and level ~= Enum.SavedQualitySetting.Automatic then
		local n = level.Value
		return if n <= 3 then "Low" elseif n <= 6 then "Mid" else "High"
	end
	return if UiLayout.IsPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled) then "Mid" else "High"
end

local function recompute()
	local t: Tier
	if mode == "Low" or mode == "High" then
		t = mode
	else
		t = ORDER[math.max(1, tierIndex(baseTier()) - penalty)]
	end
	if t ~= current then
		current = t
		changed:Fire(t)
	end
end

local function start()
	if started then
		return
	end
	started = true
	if not RunService:IsClient() then
		return
	end
	current = baseTier()
	pcall(function()
		UserSettings():GetService("UserGameSettings"):GetPropertyChangedSignal("SavedQualityLevel"):Connect(recompute)
	end)

	-- live FPS monitor
	local frames, elapsed, sinceJoin, lastDrop = 0, 0, 0, -math.huge
	RunService.Heartbeat:Connect(function(dt)
		sinceJoin += dt
		if sinceJoin < WARMUP then
			return
		end
		frames += 1
		elapsed += dt
		if elapsed >= FPS_WINDOW then
			local fps = frames / elapsed
			frames, elapsed = 0, 0
			if mode == "Auto" and fps < FPS_FLOOR and current ~= "Low" and os.clock() - lastDrop > DOWNGRADE_COOLDOWN then
				lastDrop = os.clock()
				penalty += 1
				recompute()
			end
		end
	end)
end

function DeviceProfile.Tier(): Tier
	start()
	return current
end

function DeviceProfile.Settings(): TierSettings
	start()
	return SETTINGS[current]
end

function DeviceProfile.Mode(): Mode
	return mode
end

-- Called with the saved setting (PlayerStateSync) and when the player picks one in Settings
function DeviceProfile.SetMode(m: string)
	start()
	if m ~= "Auto" and m ~= "Low" and m ~= "High" then
		m = "Auto"
	end
	if m ~= mode then
		mode = m :: Mode
		penalty = 0
		recompute()
	end
end

return DeviceProfile
