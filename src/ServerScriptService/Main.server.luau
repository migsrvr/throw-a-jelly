--!strict
--[[
	Main.server.luau
	Bootstraps all Throw-a-Slime Tycoon server services and runs MapOptimizer
	to eliminate Z-fighting/studs flickering and optimize the 13,193 map parts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local MapOptimizer = require(script.Parent:WaitForChild("MapOptimizer"))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local ThrowService = require(script.Parent:WaitForChild("ThrowService"))

MapOptimizer.Init()
Remotes.Init()
PlayerStateService.Init()
PlotService.Init()
ThrowService.Init()
