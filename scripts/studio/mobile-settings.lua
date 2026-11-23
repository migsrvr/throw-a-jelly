-- ONE-TIME Studio command-bar snippet: mobile / low-end streaming settings.
-- These Workspace and Model properties can't be changed by game scripts at runtime, so paste this whole file
-- into Studio's Command Bar (View > Command Bar), press Enter, then save and publish the place.
-- Safe to run again (it just sets the same values).
--
--   StreamingTargetRadius 1024 -> 512   phones load the nearby zones instead of the whole 1,440-stud map
--   StreamingMinRadius      64 -> 128   always keep the area around the player loaded
--   LevelOfDetail = StreamingMesh       zone models with 20+ parts show a low-detail mesh when streamed out,
--                                       so distant zones aren't empty during the throw flight
-- The throw also pre-loads its landing zone (ThrowController: RequestStreamAroundAsync).

workspace.StreamingEnabled = true
workspace.StreamingTargetRadius = 512
workspace.StreamingMinRadius = 128

local models = 0
local map = workspace:FindFirstChild("Map")
local zones = map and map:FindFirstChild("Zones")
if zones then
	for _, m in zones:GetDescendants() do
		if m:IsA("Model") then
			local parts = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				end
			end
			if parts >= 20 then
				m.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
				models += 1
			end
		end
	end
end
print(`[mobile-settings] StreamingTargetRadius 512, StreamingMinRadius 128, StreamingMesh on {models} zone models`)
