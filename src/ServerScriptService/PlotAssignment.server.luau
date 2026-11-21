-- Gives each joining player a free base and makes them spawn on it.
local Players = game:GetService("Players")
local Bases = workspace:WaitForChild("Map"):WaitForChild("Hub"):WaitForChild("PlayerBases")

local function setSign(plot, text)
	local sign = plot:FindFirstChild("OwnerSign")
	local label = sign and sign:FindFirstChild("SignGui") and sign.SignGui:FindFirstChild("Text")
	if label then label.Text = text end
end

local function getPlots()
	local plots = Bases:GetChildren()
	table.sort(plots, function(a, b) return (a:GetAttribute("PlotId") or 0) < (b:GetAttribute("PlotId") or 0) end)
	return plots
end

local function spawnOf(plot)
	local pad = plot:FindFirstChild("SpawnPad")
	return pad and pad:FindFirstChild("PlotSpawn")
end

local function assign(player)
	for _, plot in ipairs(getPlots()) do
		local owner = plot:GetAttribute("Owner")
		if owner == nil or owner == "" then
			plot:SetAttribute("Owner", tostring(player.UserId))
			player:SetAttribute("PlotId", plot:GetAttribute("PlotId"))
			setSign(plot, player.DisplayName .. "'s Base")
			local spawn = spawnOf(plot)
			if spawn then
				player.RespawnLocation = spawn
				-- if the character already loaded somewhere else, move it home
				local char = player.Character
				if char and char.PrimaryPart then
					char:PivotTo(spawn.CFrame + Vector3.new(0, 4, 0))
				end
			end
			return plot
		end
	end
	warn("No free base for " .. player.Name)
end

local function release(player)
	for _, plot in ipairs(getPlots()) do
		if plot:GetAttribute("Owner") == tostring(player.UserId) then
			plot:SetAttribute("Owner", "")
			setSign(plot, "Empty Plot")
		end
	end
end

Players.PlayerAdded:Connect(assign)
Players.PlayerRemoving:Connect(release)
for _, p in ipairs(Players:GetPlayers()) do assign(p) end
