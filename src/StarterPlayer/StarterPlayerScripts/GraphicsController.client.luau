--!strict
--[[
	GraphicsController.client.luau
	Applies the device detail tier (DeviceProfile) to the world on this device:
	  - the saved Graphics setting (PlayerStateSync.GraphicsMode) sets DeviceProfile's mode
	  - Low tier: the map Bloom is switched off locally, and the world gets a lighter look: no shadows, flat
	    lighting, closer fog and the tiniest decorations hidden (applyWorldDetail; Mid / High restore the design)
	  - map PointLights farther than the tier's LightRadius from the camera are switched off (checked once a
	    second; lights stream in and out with the map, so they are tracked as they appear)
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeviceProfile = require(Shared:WaitForChild("DeviceProfile"))
local Remotes = require(Shared:WaitForChild("Remotes"))

-- Saved setting from the server
Remotes.GetEvent("PlayerStateSync").OnClientEvent:Connect(function(state: any)
	if type(state) == "table" and type(state.GraphicsMode) == "string" then
		DeviceProfile.SetMode(state.GraphicsMode)
	end
end)

-- Bloom
local function applyPostFx()
	local on = DeviceProfile.Settings().PostFx
	for _, e in Lighting:GetChildren() do
		if e:IsA("BloomEffect") then
			if e:GetAttribute("DesignEnabled") == nil then
				e:SetAttribute("DesignEnabled", e.Enabled)
			end
			e.Enabled = on and (e:GetAttribute("DesignEnabled") :: boolean)
		end
	end
end

-- World look on Low: no shadows, flat lighting (no reflections / haze / glare), closer fog, tiny decorations hidden.
-- Every original value is remembered, so Mid / High put the designed look back exactly.
local TINY_DECOR = 3.5 -- parts smaller than this (Size.Magnitude) in decoration folders are hidden on Low
local DECOR_FOLDERS = { Details = true, Decor = true, HubDecor = true }

local designedLighting: { [string]: any } = {}
local function setLighting(inst: Instance, prop: string, value: any?)
	local key = inst:GetFullName() .. "." .. prop
	if designedLighting[key] == nil then
		designedLighting[key] = (inst :: any)[prop]
	end
	local want = if value == nil then designedLighting[key] else value
	if (inst :: any)[prop] ~= want then
		(inst :: any)[prop] = want
	end
end

local tinyParts: { [BasePart]: number } = {} -- part -> its designed Transparency
local decorHidden = false

local function inDecorFolder(inst: Instance): boolean
	local p = inst.Parent
	while p and p ~= workspace do
		if DECOR_FOLDERS[p.Name] then
			return true
		end
		p = p.Parent
	end
	return false
end

local function trackTiny(inst: Instance)
	if inst:IsA("BasePart") and tinyParts[inst] == nil and inst.Size.Magnitude < TINY_DECOR and inDecorFolder(inst) then
		tinyParts[inst] = inst.Transparency
		if decorHidden then
			inst.Transparency = 1
		end
	end
end

local function applyWorldDetail()
	local st = DeviceProfile.Settings()
	setLighting(Lighting, "GlobalShadows", if st.Shadows then nil else false)
	setLighting(Lighting, "EnvironmentDiffuseScale", if st.FlatLighting then 0 else nil)
	setLighting(Lighting, "EnvironmentSpecularScale", if st.FlatLighting then 0 else nil)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		setLighting(atmosphere, "Haze", if st.FlatLighting then 0 else nil)
		setLighting(atmosphere, "Glare", if st.FlatLighting then 0 else nil)
		setLighting(atmosphere, "Density", st.FogDensity)
	end
	if decorHidden ~= st.HideTinyDecor then
		decorHidden = st.HideTinyDecor
		for part, designed in tinyParts do
			if part.Parent then
				part.Transparency = if decorHidden then 1 else designed
			else
				tinyParts[part] = nil
			end
		end
	end
end

-- Map light culling
local lights: { [Light]: boolean } = {} -- light -> its designed Enabled value

local function trackLight(inst: Instance)
	if inst:IsA("Light") and lights[inst] == nil then
		lights[inst] = inst.Enabled
	end
end

local function lightPosition(light: Light): Vector3?
	local p = light.Parent
	if p and p:IsA("BasePart") then
		return p.Position
	elseif p and p:IsA("Attachment") then
		return p.WorldPosition
	end
	return nil
end

local function cullLights()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local radius = DeviceProfile.Settings().LightRadius
	local camPos = cam.CFrame.Position
	for light, designed in lights do
		if not light.Parent then
			lights[light] = nil
			continue
		end
		local want = designed
		if want and radius < math.huge then
			local pos = lightPosition(light)
			want = pos ~= nil and (pos - camPos).Magnitude <= radius
		end
		if light.Enabled ~= want then
			light.Enabled = want
		end
	end
end

task.spawn(function()
	local map = workspace:WaitForChild("Map", 30)
	if map then
		for _, d in map:GetDescendants() do
			trackLight(d)
			trackTiny(d)
		end
		map.DescendantAdded:Connect(function(d)
			trackLight(d)
			trackTiny(d)
		end)
		applyWorldDetail()
	end
end)

DeviceProfile.Changed:Connect(function()
	applyPostFx()
	applyWorldDetail()
	cullLights()
end)
applyPostFx()
applyWorldDetail()

task.spawn(function()
	while true do
		task.wait(1)
		cullLights()
	end
end)
