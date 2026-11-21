# Luau Architecture & Dual-Runtime Testing Reference

## 1. Dual-Runtime Module Pattern (`Roblox` + `Lune`)

To allow pure shared modules (`ThrowPhysics.luau`, `ProgressionLogic.luau`) to run inside both Roblox Studio and Lune terminal unit tests (`lune run tests/run-tests`):

```luau
--!strict
local GameConfig = if typeof(script) == "Instance"
	then require(script.Parent:WaitForChild("GameConfig"))
	else require("./GameConfig")
```

## 2. Server-Authoritative RemoteEvent Guard

```luau
local cooldowns: { [Player]: number } = {}

remote.OnServerEvent:Connect(function(player: Player, payload: any)
	local now = os.clock()
	if cooldowns[player] and (now - cooldowns[player]) < 0.35 then
		return
	end
	cooldowns[player] = now

	if type(payload) ~= "table" then
		return
	end
	local ratio = if type(payload.ChargeRatio) == "number"
		then math.clamp(payload.ChargeRatio, 0, 1)
		else 0.5
	-- Execute authoritative state reducer
end)
```

## 3. Procedural Full-Body `Motor6D` Animation Lifecycle

When driving R15/R6 `Motor6D.Transform` properties in `RunService.RenderStepped`:
- Always store the active `RBXScriptConnection` and disconnect it before starting a new animation or when the animation duration finishes.
- Reset modified `Motor6D.Transform` properties back to `CFrame.identity` on completion so default Roblox locomotion animations resume cleanly.
