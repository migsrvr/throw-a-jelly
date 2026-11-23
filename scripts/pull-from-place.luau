--!strict
--[[
	Pulls scripts and an AI-readable DataModel hierarchy snapshot from a saved
	Roblox Studio place file (.rbxl or .rbxlx) into a safe Rojo workspace.

	WARNING: this DELETES and rebuilds src/ and rewrites default.project.json from the place file.
	It does NOT extract meshes or models (e.g. ReplicatedStorage.SlimeModels). An old place file can
	bring back stale scripts, so it refuses to run unless you pass --force.
	For slime models, use scripts/check-slime-models instead (read-only).

	Usage:
		lune run scripts/pull-from-place [path/to/place.rbxl] --force
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local SERVICES = {
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"Workspace",
	"Lighting",
	"SoundService",
	"TextChatService",
}

local GEOMETRY_CLASSES: { [string]: boolean } = {
	Part = true,
	MeshPart = true,
	UnionOperation = true,
	WedgePart = true,
	CornerWedgePart = true,
	TrussPart = true,
	Seat = true,
	VehicleSeat = true,
	SpawnLocation = true,
	Attachment = true,
	Weld = true,
	WeldConstraint = true,
	Motor6D = true,
	Decal = true,
	Texture = true,
	SurfaceAppearance = true,
	SpecialMesh = true,
}

local function findPlaceFile(): string?
	local explicitArg = nil
	for _, arg in process.args do
		if string.sub(arg, 1, 2) ~= "--" then
			explicitArg = arg
			break
		end
	end
	if explicitArg and explicitArg ~= "" then
		if fs.isFile(explicitArg) then
			return explicitArg
		end
		print(`ERROR: Specified place file not found: {explicitArg}`)
		return nil
	end

	if fs.isFile("place.rbxl") then
		return "place.rbxl"
	end
	if fs.isFile("place.rbxlx") then
		return "place.rbxlx"
	end

	local matches = {}
	for _, entry in fs.readDir(".") do
		if fs.isFile(entry) and (string.match(entry, "%.rbxl$") or string.match(entry, "%.rbxlx$")) then
			table.insert(matches, entry)
		end
	end

	if #matches == 1 then
		return matches[1]
	elseif #matches > 1 then
		table.sort(matches)
		print("Multiple place files found in workspace root; using: " .. matches[1])
		return matches[1]
	end

	return nil
end

local function isScript(inst: any): boolean
	local className = inst.ClassName
	return className == "Script" or className == "LocalScript" or className == "ModuleScript"
end

local function scriptExtension(className: string): string
	if className == "Script" then
		return ".server.luau"
	elseif className == "LocalScript" then
		return ".client.luau"
	else
		return ".luau"
	end
end

local function hasDescendantScript(inst: any): boolean
	if isScript(inst) then
		return true
	end
	for _, child in inst:GetChildren() do
		if hasDescendantScript(child) then
			return true
		end
	end
	return false
end

local function sanitizeName(name: string): string
	local cleaned = string.gsub(name, '[<>:"/\\|%?%*]', "_")
	cleaned = string.gsub(cleaned, "[%.%s]+$", "")
	if cleaned == "" or cleaned == "." or cleaned == ".." then
		cleaned = "Unnamed"
	end
	return cleaned
end

local function uniqueName(used: { [string]: number }, baseName: string): string
	local lower = string.lower(baseName)
	local count = used[lower]
	if not count then
		used[lower] = 1
		return baseName
	end
	count += 1
	used[lower] = count
	return `{baseName}_{count}`
end

local function ensureDir(path: string)
	if not fs.isDir(path) then
		fs.writeDir(path)
	end
end

local function writeMetaJson(dirPath: string, className: string?)
	local meta: { [string]: any } = {
		ignoreUnknownInstances = true,
	}
	if className and className ~= "Folder" then
		meta.className = className
	end
	fs.writeFile(`{dirPath}/init.meta.json`, serde.encode("json", meta, true))
end

local counts = {
	Server = 0,
	Client = 0,
	Module = 0,
}

local function extractChildren(parentInst: any, outDir: string)
	local children = parentInst:GetChildren()
	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)

	local usedNames: { [string]: number } = {}

	for _, child in children do
		if not hasDescendantScript(child) then
			continue
		end

		local safeName = uniqueName(usedNames, sanitizeName(child.Name))

		if isScript(child) then
			local ext = scriptExtension(child.ClassName)
			if child.ClassName == "Script" then
				counts.Server += 1
			elseif child.ClassName == "LocalScript" then
				counts.Client += 1
			else
				counts.Module += 1
			end

			local hasNestedScripts = false
			for _, grandChild in child:GetChildren() do
				if hasDescendantScript(grandChild) then
					hasNestedScripts = true
					break
				end
			end

			local source = child.Source or ""
			if hasNestedScripts then
				local childDir = `{outDir}/{safeName}`
				ensureDir(childDir)
				fs.writeFile(`{childDir}/init{ext}`, source)
				writeMetaJson(childDir, nil)
				extractChildren(child, childDir)
			else
				fs.writeFile(`{outDir}/{safeName}{ext}`, source)
			end
		else
			local childDir = `{outDir}/{safeName}`
			ensureDir(childDir)
			writeMetaJson(childDir, child.ClassName)
			extractChildren(child, childDir)
		end
	end
end

local function formatAttributes(inst: any): string
	local ok, attrs = pcall(function()
		return inst:GetAttributes()
	end)
	if not ok or type(attrs) ~= "table" then
		return ""
	end
	local keys = {}
	for k in attrs do
		table.insert(keys, k)
	end
	if #keys == 0 then
		return ""
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		table.insert(parts, `{k}={tostring(attrs[k])}`)
	end
	return ` [Attrs: {table.concat(parts, ", ")}]`
end

local function formatTags(inst: any): string
	local ok, tags = pcall(function()
		return inst:GetTags()
	end)
	if not ok or type(tags) ~= "table" or #tags == 0 then
		return ""
	end
	table.sort(tags)
	return ` [Tags: {table.concat(tags, ", ")}]`
end

local function formatExtraInfo(inst: any): string
	local extra = ""
	if isScript(inst) then
		local ok, disabled = pcall(function()
			return inst.Disabled
		end)
		if ok and disabled == true then
			extra ..= " (Disabled)"
		end
	elseif string.match(inst.ClassName, "Value$") then
		local ok, val = pcall(function()
			return inst.Value
		end)
		if ok and val ~= nil then
			extra ..= ` = {tostring(val)}`
		end
	end
	extra ..= formatAttributes(inst)
	extra ..= formatTags(inst)
	return extra
end

local function buildHierarchyLines(inst: any, indent: string, lines: { string }, inWorkspace: boolean)
	local children = inst:GetChildren()
	table.sort(children, function(a, b)
		if a.Name == b.Name then
			return a.ClassName < b.ClassName
		end
		return a.Name < b.Name
	end)

	local omittedGeometry = 0
	local shownGeometry = 0
	local maxGeometryPerContainer = 20

	for _, child in children do
		local isPureGeo = inWorkspace
			and GEOMETRY_CLASSES[child.ClassName] == true
			and not hasDescendantScript(child)
			and #child:GetChildren() == 0

		if isPureGeo then
			shownGeometry += 1
			if shownGeometry > maxGeometryPerContainer then
				omittedGeometry += 1
				continue
			end
		end

		table.insert(lines, `{indent}- {child.Name} [{child.ClassName}]{formatExtraInfo(child)}`)
		buildHierarchyLines(child, indent .. "  ", lines, inWorkspace)
	end

	if omittedGeometry > 0 then
		table.insert(lines, `{indent}- ... (+{omittedGeometry} additional geometry parts omitted)`)
	end
end

local function main()
	local force = table.find(process.args, "--force") ~= nil
	if not force then
		print("Refusing to run: this rewrites src/ and default.project.json from the place file.")
		print("Your repo's scripts would be replaced by whatever the place file contains.")
		print("Run again with --force only if you really mean it (see the header of this script).")
		process.exit(1)
	end

	local placePath = findPlaceFile()
	if not placePath then
		print("No .rbxl or .rbxlx place file found in workspace root.")
		print("")
		print("Next steps:")
		print("  1. In Roblox Studio, disconnect Rojo (if connected).")
		print("  2. Click File -> Save to File As...")
		print("  3. Save the file as: place.rbxl inside this project folder.")
		print("  4. Re-run: lune run scripts/pull-from-place")
		process.exit(1)
	end

	print(`Reading place file: {placePath} ...`)
	local raw = fs.readFile(placePath)
	local game = roblox.deserializePlace(raw)

	-- Reset src/ cleanly before extraction
	if fs.isDir("src") then
		fs.removeDir("src")
	end
	ensureDir("src")

	local projectTree: { [string]: any } = {
		["$className"] = "DataModel",
		["$ignoreUnknownInstances"] = true,
	}

	local hierarchyLines = {
		`# Roblox Studio Place Hierarchy`,
		`Source: {placePath}`,
		"",
	}

	local mappedServices = {}

	for _, serviceName in SERVICES do
		local ok, service = pcall(function()
			return game:GetService(serviceName)
		end)
		if not ok or not service then
			continue
		end

		if #service:GetChildren() > 0 then
			table.insert(hierarchyLines, `## {serviceName}`)
			buildHierarchyLines(service, "", hierarchyLines, serviceName == "Workspace")
			table.insert(hierarchyLines, "")
		end

		if not hasDescendantScript(service) then
			continue
		end

		if serviceName == "StarterPlayer" then
			local spTree: { [string]: any } = {
				["$ignoreUnknownInstances"] = true,
			}
			local addedAny = false
			for _, subName in { "StarterPlayerScripts", "StarterCharacterScripts" } do
				local sub = service:FindFirstChild(subName)
				if sub and hasDescendantScript(sub) then
					local outDir = `src/StarterPlayer/{subName}`
					ensureDir("src/StarterPlayer")
					ensureDir(outDir)
					extractChildren(sub, outDir)
					spTree[subName] = {
						["$path"] = outDir,
						["$ignoreUnknownInstances"] = true,
					}
					addedAny = true
				end
			end
			if addedAny then
				projectTree[serviceName] = spTree
				table.insert(mappedServices, serviceName)
			end
		else
			local outDir = `src/{serviceName}`
			ensureDir(outDir)
			extractChildren(service, outDir)
			projectTree[serviceName] = {
				["$path"] = outDir,
				["$ignoreUnknownInstances"] = true,
			}
			table.insert(mappedServices, serviceName)
		end
	end

	-- Write safe default.project.json
	local projectJson = {
		name = "RobloxProject",
		tree = projectTree,
	}
	fs.writeFile("default.project.json", serde.encode("json", projectJson, true))

	-- Write AI-readable hierarchy snapshot
	ensureDir("docs")
	fs.writeFile("docs/place-hierarchy.txt", table.concat(hierarchyLines, "\n"))

	local totalScripts = counts.Server + counts.Client + counts.Module
	print("")
	print("Extraction complete!")
	print(`  Scripts extracted: {totalScripts} (Server: {counts.Server}, Client: {counts.Client}, Module: {counts.Module})`)
	print(`  Mapped services:   {#mappedServices > 0 and table.concat(mappedServices, ", ") or "(none)"}`)
	print("  Updated:           default.project.json (with $ignoreUnknownInstances: true)")
	print("  Generated:         docs/place-hierarchy.txt")
	print("")
	print("Tip: Run `rojo sourcemap default.project.json --output sourcemap.json` to enable Luau LSP type checking.")
end

main()
