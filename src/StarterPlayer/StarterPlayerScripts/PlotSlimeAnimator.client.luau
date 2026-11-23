--!strict
--[[
	PlotSlimeAnimator.client.luau
	Animates the slimes roaming the player bases ON THIS DEVICE. The server (PlotService) only decides each walk
	segment and publishes it as attributes on the slime model:
	  RoamFromX/Z, RoamToX/Z   start / end of the segment (ground-rest centre)
	  RoamT0, RoamDur          server time it started (workspace:GetServerTimeNow()) and its length (s)
	  RoamYaw                  heading for the segment (front = -Z)
	  SlotBaseY, SlotPhase     rest height and bob phase
	Here we work out where it is now, add the hop while walking, the idle bob and a smooth turn, and move the
	welded (MakeRigid) slime by its root. Only slimes near the camera are animated (DeviceProfile radius); the
	rest stay where they are, so a phone does nothing for bases it can't see.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DeviceProfile = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DeviceProfile"))

local TAG = "PlotSlime"
local LOW_RATE = 1 / 30 -- Low tier: animate at 30 Hz

type Track = { Yaw: number?, Active: boolean }
local tracked: { [Model]: Track } = {}

local function add(inst: Instance)
	if inst:IsA("Model") then
		tracked[inst] = { Yaw = nil, Active = false }
	end
end

for _, inst in CollectionService:GetTagged(TAG) do
	add(inst)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
	tracked[inst :: Model] = nil
end)

local acc = 0
RunService.RenderStepped:Connect(function(dt: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	acc += dt
	local low = DeviceProfile.Tier() == "Low"
	if low and acc < LOW_RATE then
		return
	end
	local step = acc
	acc = 0

	local radius = DeviceProfile.Settings().SlimeAnimRadius
	local camPos = cam.CFrame.Position
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()

	for model, tr in tracked do
		local root = model.PrimaryPart
		if not root or not model.Parent then
			continue
		end
		local fromX = model:GetAttribute("RoamFromX") :: number?
		local fromZ = model:GetAttribute("RoamFromZ") :: number?
		local toX = model:GetAttribute("RoamToX") :: number?
		local toZ = model:GetAttribute("RoamToZ") :: number?
		if not (fromX and fromZ and toX and toZ) then
			continue
		end
		local baseY = (model:GetAttribute("SlotBaseY") :: number?) or root.Position.Y
		local t0 = (model:GetAttribute("RoamT0") :: number?) or now
		local dur = (model:GetAttribute("RoamDur") :: number?) or 0
		local u = if dur > 0 then math.clamp((now - t0) / dur, 0, 1) else 1
		local x = fromX + (toX - fromX) * u
		local z = fromZ + (toZ - fromZ) * u

		local dx, dz = x - camPos.X, z - camPos.Z
		if dx * dx + dz * dz > radius * radius then
			tr.Active = false -- out of range: leave it where the server put it
			continue
		end
		tr.Active = true

		-- turn smoothly toward this segment's heading
		local goalYaw = (model:GetAttribute("RoamYaw") :: number?) or math.pi
		local yaw = tr.Yaw or goalYaw
		local diff = (goalYaw - yaw + math.pi) % (2 * math.pi) - math.pi
		yaw += diff * math.min(1, step * 8)
		tr.Yaw = yaw

		-- hop while travelling, gentle idle bob otherwise (same as the old server motion)
		local moving = u < 1
		local phase = (model:GetAttribute("SlotPhase") :: number?) or 0
		local wave = math.sin(clock * (if moving then 9 else 3.4) + phase)
		local lift = if moving then math.abs(wave) * 0.6 else math.max(0, wave) * 0.12
		root.CFrame = CFrame.new(x, baseY + lift, z) * CFrame.Angles(0, yaw, 0)
	end
end)
