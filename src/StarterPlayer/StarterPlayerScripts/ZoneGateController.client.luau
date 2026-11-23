--!strict
--[[
	ZoneGateController.client.luau
	Updates each zone's Gate Barrier forcefield and lock Sign locally for this player
	whenever EffectiveThrowPower updates via PlayerStateSync.
	- Unlocked (EffectiveThrowPower >= zone.RequiredThrowPower): hides Barrier & Sign and disables Barrier collision.
	- Locked: keeps Barrier & Sign visible and collidable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

type PartOrig = {
	Transparency: number,
	CanCollide: boolean,
	CanTouch: boolean,
	CanQuery: boolean,
}

local origProps: { [BasePart]: PartOrig } = {}
local latestPower = 0

local function rememberPart(part: BasePart): PartOrig
	local saved = origProps[part]
	if not saved then
		saved = {
			Transparency = part.Transparency,
			CanCollide = part.CanCollide,
			CanTouch = part.CanTouch,
			CanQuery = part.CanQuery,
		}
		origProps[part] = saved
	end
	return saved
end

local function setPartHidden(part: BasePart, hidden: boolean)
	local orig = rememberPart(part)
	if hidden then
		part.Transparency = 1
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
	else
		part.Transparency = orig.Transparency
		part.CanCollide = orig.CanCollide
		part.CanTouch = orig.CanTouch
		part.CanQuery = orig.CanQuery
	end
	for _, d in part:GetDescendants() do
		if d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			d.Enabled = not hidden
		end
	end
end

local function applyZoneGate(zonesFolder: Instance, zone: GameConfig.ZoneDef, power: number)
	if zone.RequiredThrowPower <= 0 then
		return
	end
	local zoneFolder = zonesFolder:FindFirstChild(zone.Id)
	local gate = zoneFolder and zoneFolder:FindFirstChild("Gate")
	if not gate then
		return
	end
	local unlocked = power >= zone.RequiredThrowPower

	-- Hide/restore the entire Gate model (Barrier, Sign, and all yellow/black hazard border Parts)
	for _, d in gate:GetDescendants() do
		if d:IsA("BasePart") then
			setPartHidden(d, unlocked)
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			d.Enabled = not unlocked
		end
	end
end

local function refreshAllGates(power: number)
	local map = workspace:FindFirstChild("Map")
	local zonesFolder = map and map:FindFirstChild("Zones")
	if not zonesFolder then
		return
	end
	for _, zone in GameConfig.Zones do
		applyZoneGate(zonesFolder, zone, power)
	end
end

Remotes.GetEvent("PlayerStateSync").OnClientEvent:Connect(function(state: any)
	if type(state) == "table" and type(state.EffectiveThrowPower) == "number" then
		latestPower = state.EffectiveThrowPower
		refreshAllGates(latestPower)
	end
end)

-- Also refresh if Map.Zones streams in after the initial PlayerStateSync
task.spawn(function()
	local map = workspace:WaitForChild("Map", 15)
	local zones = map and map:WaitForChild("Zones", 15)
	if zones then
		refreshAllGates(latestPower)
		-- with streaming, gate parts arrive bit by bit: refresh (debounced) whenever anything streams in
		local pending = false
		zones.DescendantAdded:Connect(function()
			if pending then
				return
			end
			pending = true
			task.delay(0.2, function()
				pending = false
				refreshAllGates(latestPower)
			end)
		end)
	end
end)
