--!strict
--[[
	WorldSignScaler.client.luau
	Billboard signs are laid out in pixels (crisp text), so they would stay one size on screen at any distance.
	This scales each sign's UIScale by camera distance: full size when close, smaller as you walk away.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local NEAR = 22 -- studs: full size at or inside this distance
local MIN_SCALE = 0.3

local trackedSigns: { [BillboardGui]: UIScale } = {}

local function trackSign(inst: Instance)
	if inst:IsA("BillboardGui") then
		local root = inst:FindFirstChild("Root")
		local scale = if root then root:FindFirstChild("DistanceScale") :: UIScale? else nil
		if scale then
			trackedSigns[inst] = scale
		end
	end
end

local function untrackSign(inst: Instance)
	if inst:IsA("BillboardGui") then
		trackedSigns[inst] = nil
	end
end

for _, inst in CollectionService:GetTagged("WorldSign") do
	trackSign(inst)
end
CollectionService:GetInstanceAddedSignal("WorldSign"):Connect(trackSign)
CollectionService:GetInstanceRemovedSignal("WorldSign"):Connect(untrackSign)

local function adorneePosition(bb: BillboardGui): Vector3?
	local a = bb.Adornee
	if a and a:IsA("BasePart") then
		return a.Position + bb.StudsOffset
	end
	local p = bb.Parent
	if p and p:IsA("BasePart") then
		return p.Position + bb.StudsOffset
	end
	return nil
end

-- MOBILE: 15 updates a second is plenty for a size change, and signs farther than FAR are skipped (they are
-- at MIN_SCALE long before that); a scale is only written when it actually changes.
local UPDATE_HZ = 15
local FAR = 300
local acc = 0
RunService.RenderStepped:Connect(function(dt: number)
	acc += dt
	if acc < 1 / UPDATE_HZ then
		return
	end
	acc = 0
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	for bb, scale in trackedSigns do
		if not bb.Parent then
			trackedSigns[bb] = nil
			continue
		end
		if not bb.Enabled then
			continue
		end
		local pos = adorneePosition(bb)
		if pos then
			local dist = (pos - camPos).Magnitude
			local s = if dist > FAR then MIN_SCALE else math.clamp(NEAR / math.max(dist, 1), MIN_SCALE, 1)
			if math.abs(scale.Scale - s) > 0.005 then
				scale.Scale = s
			end
		end
	end
end)
