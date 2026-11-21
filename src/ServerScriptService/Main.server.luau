--!strict
--[[
	Main.server.luau
	Bootstraps all Throw-a-Slime Tycoon server services.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local ThrowService = require(script.Parent:WaitForChild("ThrowService"))

Remotes.Init()
PlayerStateService.Init()
PlotService.Init()
ThrowService.Init()
