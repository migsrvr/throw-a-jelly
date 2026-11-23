--!strict
--[[
	Checks that the authored slime models in a saved place file match the code. READ-ONLY: writes nothing.

	Usage:
		lune run scripts/check-slime-models scratch/place-copy.rbxl

	How to make the place copy in Studio: File > Save to File As > save it inside scratch/ (outside src/).

	Reports:
	  - slimes in GameConfig.Slimes with no MODEL_PATHS entry (they would use the jelly-ball fallback)
	  - MODEL_PATHS entries whose model is missing from ReplicatedStorage.SlimeModels
	  - models that are present but not used by any slime (extra or misnamed)
	  - models that are not a Model with a Slime child and a Body BasePart (SlimeFactory needs both)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local CatchFxData = require("../src/ReplicatedStorage/Shared/CatchFxData")

local FACTORY_PATH = "src/ReplicatedStorage/Shared/SlimeFactory.luau"

-- Parse MODEL_PATHS from SlimeFactory.luau text, e.g.  meadow_sprout = { "Meadow", "Sprout" },
local function parseModelPaths(): { [string]: { zone: string, name: string } }
	local paths = {}
	local source = fs.readFile(FACTORY_PATH)
	local inTable = false
	for line in string.gmatch(source, "[^\n]+") do
		if string.find(line, "^local MODEL_PATHS") then
			inTable = true
		elseif inTable and string.find(line, "^}") then
			break
		elseif inTable then
			local id, zone, name = string.match(line, '^%s*([%w_]+)%s*=%s*{%s*"([^"]+)"%s*,%s*"([^"]+)"%s*}')
			if id and zone and name then
				paths[id] = { zone = zone, name = name }
			end
		end
	end
	return paths
end

local function main()
	local placePath = process.args[1]
	if not placePath or placePath == "" then
		print("Usage: lune run scripts/check-slime-models scratch/place-copy.rbxl")
		process.exit(1)
	end
	if not fs.isFile(placePath) then
		print(`ERROR: place file not found: {placePath}`)
		process.exit(1)
	end

	local paths = parseModelPaths()
	local pathCount = 0
	for _ in paths do
		pathCount += 1
	end
	local root: any = nil
	if string.match(placePath, "%.rbxmx?$") then
		-- Exported model file (Save/Export Selection of ReplicatedStorage.SlimeModels): the SlimeModels folder is the top level
		local top = roblox.deserializeModel(fs.readFile(placePath))
		for _, inst in top do
			if inst.Name == "SlimeModels" then
				root = inst
				break
			end
		end
		if not root then
			print("ERROR: the .rbxm does not contain a top-level folder named SlimeModels. Export that folder itself.")
			process.exit(1)
		end
	else
		local game = roblox.deserializePlace(fs.readFile(placePath))
		root = game:GetService("ReplicatedStorage"):FindFirstChild("SlimeModels")
	end

	local problems: { string } = {}
	local okCount = 0
	local used: { [string]: boolean } = {}

	if not root then
		table.insert(problems, "ReplicatedStorage.SlimeModels folder is missing from this place file")
	end

	-- 1. Every configured slime needs a MODEL_PATHS entry
	for _, slime in GameConfig.Slimes do
		if not paths[slime.Id] then
			table.insert(problems, `no MODEL_PATHS entry for slime "{slime.Id}" ({slime.Name})`)
		end
	end

	-- 2. Every MODEL_PATHS entry must exist and be valid
	for id, p in paths do
		if not GameConfig.SlimesById[id] then
			table.insert(problems, `MODEL_PATHS has "{id}" but GameConfig.Slimes does not`)
		end
		local zone = root and root:FindFirstChild(p.zone)
		local holder = zone and zone:FindFirstChild(p.name)
		local slime = holder and holder:FindFirstChild("Slime")
		if not holder then
			table.insert(problems, `missing model {p.zone}/{p.name} (for {id})`)
		elseif not slime then
			table.insert(problems, `{p.zone}/{p.name} has no "Slime" child (for {id})`)
		elseif slime.ClassName ~= "Model" then
			table.insert(problems, `{p.zone}/{p.name}/Slime is a {slime.ClassName}, expected Model (for {id})`)
		else
			local body = slime:FindFirstChild("Body", true)
			if not body or not body:IsA("BasePart") then
				table.insert(problems, `{p.zone}/{p.name}/Slime has no Body BasePart (for {id})`)
			else
				okCount += 1
				used[`{p.zone}/{p.name}`] = true
			end
		end
	end

	-- 2b. CatchFx signatures: every Key / Pattern must name something in that slime's model
	for id, layer in CatchFxData.Signatures do
		local p = paths[id]
		local zone = root and p and root:FindFirstChild(p.zone)
		local holder = zone and zone:FindFirstChild(p.name)
		local slime = holder and holder:FindFirstChild("Slime")
		if slime then
			local names: { string } = {}
			for _, d in slime:GetDescendants() do
				table.insert(names, d.Name)
			end
			for _, phase in { "Walk", "Land", "Show" } do
				for _, op in (layer :: any)[phase] or {} do
					local found = false
					if op.Key then
						for _, n in names do
							if n == op.Key then
								found = true
								break
							end
						end
					elseif op.Pattern then
						for _, n in names do
							if string.find(n, op.Pattern) then
								found = true
								break
							end
						end
					else
						found = true
					end
					if not found then
						table.insert(
							problems,
							`CatchFx {id} {phase} {op.Op}: "{op.Key or op.Pattern}" matches nothing in {p.zone}/{p.name}`
						)
					end
				end
			end
		end
	end

	-- 3. Models that no slime uses (extra or misnamed)
	if root then
		for _, zone in root:GetChildren() do
			for _, holder in zone:GetChildren() do
				local key = `{zone.Name}/{holder.Name}`
				if not used[key] then
					table.insert(problems, `unused model {key} (not in MODEL_PATHS, or its slime is broken above)`)
				end
			end
		end
	end

	print(`Slime configs: {#GameConfig.Slimes} | MODEL_PATHS entries: {pathCount} | valid models: {okCount}`)
	if #problems == 0 then
		print("OK: every slime has a valid model, and no models are unused.")
		return
	end
	print(`{#problems} problem(s):`)
	for _, msg in problems do
		print("  - " .. msg)
	end
	process.exit(1)
end

main()
