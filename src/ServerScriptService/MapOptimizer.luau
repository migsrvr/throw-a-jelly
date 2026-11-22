--!strict
--[[
	MapOptimizer.luau
	Eliminates Z-fighting / studs flickering across Hub and Zones 1..5
	and optimizes collision, touch, raycast-query, and shadow flags across
	the 13,193 parts in Workspace.Map.
]]

local MapOptimizer = {}

local function setTopHeight(part: BasePart, desiredTopY: number, desiredThickness: number?)
	local size = part.Size
	local thickness = desiredThickness or size.Y
	part.Size = Vector3.new(size.X, thickness, size.Z)
	local pos = part.Position
	part.Position = Vector3.new(pos.X, desiredTopY - thickness * 0.5, pos.Z)
end

local function makeSmoothOverlay(part: BasePart)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
end

local function optimizeDecorativeContainer(container: Instance, disableCollisions: boolean)
	local parts: { BasePart } = {}
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanTouch = false
			d.CanQuery = false
			if disableCollisions then
				d.CanCollide = false
			end
			if d.Size.Magnitude < 14 then
				d.CastShadow = false
			end
			table.insert(parts, d)
		end
	end

	-- De-conflict coplanar overlapping sibling parts (e.g., Tree leaves, Flower petals, Cliff drips)
	for i = 1, #parts do
		local a = parts[i]
		local pa = a.Position
		local sa = a.Size
		local topA = pa.Y + sa.Y * 0.5
		for j = i + 1, #parts do
			local b = parts[j]
			if a.Parent == b.Parent then
				local pb = b.Position
				local sb = b.Size
				local topB = pb.Y + sb.Y * 0.5
				local overlapX = (math.min(pa.X + sa.X * 0.5, pb.X + sb.X * 0.5) - math.max(pa.X - sa.X * 0.5, pb.X - sb.X * 0.5)) > 0.05
				local overlapZ = (math.min(pa.Z + sa.Z * 0.5, pb.Z + sb.Z * 0.5) - math.max(pa.Z - sa.Z * 0.5, pb.Z - sb.Z * 0.5)) > 0.05
				if overlapX and overlapZ and math.abs(topA - topB) < 0.03 then
					b.Position = Vector3.new(pb.X, pb.Y + 0.035, pb.Z)
				end
			end
		end
	end
end

local function deconflictZoneLane(zoneFolder: Instance)
	local floorY = (zoneFolder:GetAttribute("FloorY") :: number?) or 0
	local lane = zoneFolder:FindFirstChild("Lane")
	if not lane then
		return
	end

	for _, child in lane:GetChildren() do
		if child:IsA("BasePart") then
			child.CanTouch = false
			child.CanQuery = false

			if child.Name == "DirtFill" then
				-- Inset DirtFill horizontally and lower its top so it never Z-fights with Tile or Walls
				child.Size = Vector3.new(math.max(1, child.Size.X - 0.24), child.Size.Y, math.max(1, child.Size.Z - 0.24))
				setTopHeight(child, floorY - 2.06, child.Size.Y)
				child.CanCollide = false
				child.CastShadow = false
			elseif child.Name == "EdgeLine" then
				makeSmoothOverlay(child)
				setTopHeight(child, floorY + 0.18, 0.16)
			elseif child.Name == "DistanceLine" then
				makeSmoothOverlay(child)
				setTopHeight(child, floorY + 0.21, 0.16)
			elseif child.Name == "CenterDash" then
				makeSmoothOverlay(child)
				setTopHeight(child, floorY + 0.24, 0.16)
			elseif child.Name == "DistanceText" then
				makeSmoothOverlay(child)
				setTopHeight(child, floorY + 0.27, 0.16)
			end
		end
	end
end

local function deconflictHub(hub: Instance)
	local hubFloorY = 30.0

	-- 1. Hub.Ground: inset DirtFill and optimize Tiles
	local ground = hub:FindFirstChild("Ground")
	if ground then
		for _, child in ground:GetChildren() do
			if child:IsA("BasePart") then
				child.CanTouch = false
				child.CanQuery = false
				if child.Name == "DirtFill" then
					child.Size = Vector3.new(math.max(1, child.Size.X - 0.24), child.Size.Y, math.max(1, child.Size.Z - 0.24))
					setTopHeight(child, hubFloorY - 2.06, child.Size.Y)
					child.CanCollide = false
					child.CastShadow = false
				end
			end
		end
	end

	-- 2. Hub.Paths: separate Walkway and ToThrowLine so their intersection never Z-fights
	local paths = hub:FindFirstChild("Paths")
	if paths then
		for _, child in paths:GetChildren() do
			if child:IsA("BasePart") then
				child.CanTouch = false
				child.CanQuery = false
				if child.Name == "Walkway" then
					setTopHeight(child, hubFloorY + 0.30, 0.28)
				elseif child.Name == "ToThrowLine" then
					child.TopSurface = Enum.SurfaceType.Smooth
					setTopHeight(child, hubFloorY + 0.35, 0.32)
				elseif child.Name == "Edge" then
					child.TopSurface = Enum.SurfaceType.Smooth
					setTopHeight(child, hubFloorY + 0.45, 0.42)
				end
			end
		end
	end

	-- 3. Hub.ThrowLine: keep Check tiles crisp above Hub.Ground
	local throwLine = hub:FindFirstChild("ThrowLine")
	if throwLine then
		for _, d in throwLine:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanTouch = false
				d.CanQuery = false
				if d.Name == "Check" then
					setTopHeight(d, hubFloorY + 0.42, 0.38)
				end
			end
		end
	end

	-- 4. Hub.JellyShop: lift thin deck stripe parts above Deck (topY = 30.820)
	local shop = hub:FindFirstChild("JellyShop")
	if shop then
		local deckIdx = 0
		for _, d in shop:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name ~= "ShopTrigger" then
					d.CanTouch = false
					d.CanQuery = false
				end
				if d.Name == "Part" and d.Size.Y < 0.15 and math.abs(d.Position.Y - 30.8) < 0.2 then
					deckIdx += 1
					d.TopSurface = Enum.SurfaceType.Smooth
					setTopHeight(d, 30.85 + (deckIdx % 2) * 0.005, 0.06)
					d.CanCollide = false
				end
			end
		end
	end

	-- 5. Hub.PlayerBases (Plot1..Plot5): separate Border, Floor, Pads, and Slots
	local bases = hub:FindFirstChild("PlayerBases")
	if bases then
		for _, plot in bases:GetChildren() do
			local border = plot:FindFirstChild("Border") :: BasePart?
			local floor = plot:FindFirstChild("Floor") :: BasePart?
			if border and border:IsA("BasePart") then
				border.TopSurface = Enum.SurfaceType.Smooth
				border.BottomSurface = Enum.SurfaceType.Smooth
				setTopHeight(border, hubFloorY + 0.34, 0.32)
				border.CanTouch = false
				border.CanQuery = false
			end
			if floor and floor:IsA("BasePart") then
				-- Floor sits cleanly ON TOP of Border (30.35 .. 30.62) with crisp Studs
				setTopHeight(floor, hubFloorY + 0.62, 0.27)
				floor.CanTouch = false
				floor.CanQuery = false
			end

			local details = plot:FindFirstChild("Details")
			if details then
				optimizeDecorativeContainer(details, true)
			end

			-- Remove white neon ground circles at plot entrance (ClaimPad) and pull-up bar (TrainSpot)
			local claimPad = plot:FindFirstChild("ClaimPad")
			if claimPad and claimPad:IsA("BasePart") then
				claimPad.Transparency = 1
				claimPad.CanCollide = false
				claimPad.CanTouch = false
				claimPad.CanQuery = false
				claimPad.CastShadow = false
			end
			local pullUp = plot:FindFirstChild("PullUpBar")
			local trainSpot = pullUp and pullUp:FindFirstChild("TrainSpot")
			if trainSpot and trainSpot:IsA("BasePart") then
				trainSpot.Transparency = 1
				trainSpot.CanCollide = false
				trainSpot.CanTouch = false
				trainSpot.CanQuery = false
				trainSpot.CastShadow = false
			end
		end
	end

	-- 6. Hub.EdgeGuard: widen front cliff safety wall to span the full Hub width (X = [-142, +142])
	local edgeGuard = hub:FindFirstChild("EdgeGuard", true)
	if edgeGuard and edgeGuard:IsA("BasePart") then
		edgeGuard.Size = Vector3.new(math.max(284, edgeGuard.Size.X), edgeGuard.Size.Y, edgeGuard.Size.Z)
	end
end

function MapOptimizer.OptimizeMap(mapRoot: Instance?)
	local map = mapRoot or workspace:FindFirstChild("Map")
	if not map then
		return
	end

	local hub = map:FindFirstChild("Hub")
	if hub then
		deconflictHub(hub)
		for _, folderName in { "HubDecor", "Perimeter", "FrontCliff", "Lamps", "Leaderboards", "Gantry" } do
			local sub = hub:FindFirstChild(folderName)
			if sub then
				optimizeDecorativeContainer(sub, folderName == "HubDecor")
			end
		end
	end

	local zones = map:FindFirstChild("Zones")
	if zones then
		for _, zone in zones:GetChildren() do
			deconflictZoneLane(zone)
			for _, folderName in { "Decor", "Details", "MagmaVeins", "Walls" } do
				local sub = zone:FindFirstChild(folderName)
				if sub then
					optimizeDecorativeContainer(sub, folderName ~= "Walls")
				end
			end
		end
	end
end

function MapOptimizer.Init()
	MapOptimizer.OptimizeMap(workspace:FindFirstChild("Map"))
end

return MapOptimizer
