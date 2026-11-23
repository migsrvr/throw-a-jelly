--!strict
--[[
	tests/CatchFx.spec.luau
	Catch-cutscene effect design data (CatchFxData): every zone has a preset, every personality exists, every
	signature belongs to a real slime, and every op / preset name is one CatchFx knows how to play.
	(Part names are checked against the real models by `lune run scripts/check-slime-models assets.rbxl`.)
]]

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local CatchFxData = require("../src/ReplicatedStorage/Shared/CatchFxData")

return function(t: any)
	local describe = t.describe
	local it = t.it
	local expect = t.expect

	local function checkOps(where: string, ops: { any }?)
		if not ops then
			return
		end
		for i, op in ops do
			if not CatchFxData.KnownOps[op.Op] then
				error(`{where} op #{i}: unknown Op "{tostring(op.Op)}"`)
			end
			if op.Preset ~= nil and not CatchFxData.KnownPresets[op.Preset] then
				error(`{where} op #{i}: unknown Preset "{tostring(op.Preset)}"`)
			end
			if CatchFxData.MotionOps[op.Op] and type(op.Key) ~= "string" then
				error(`{where} op #{i}: {op.Op} needs a Key`)
			end
		end
	end

	describe("CatchFx - Design data", function()
		it("has a zone preset for every zone", function()
			for i = 1, #GameConfig.Zones do
				local z = CatchFxData.Zones[i]
				expect(z ~= nil).toBeTruthy()
				expect(z.Grade ~= nil).toBeTruthy()
				expect(z.Edge ~= nil).toBeTruthy()
			end
		end)

		it("gives every zone a known emergence style, set piece and valid shot overrides", function()
			for i = 1, #GameConfig.Zones do
				local z = CatchFxData.Zones[i]
				if not CatchFxData.EmergeStyles[z.Emerge] then
					error(`zone {i}: unknown Emerge "{tostring(z.Emerge)}"`)
				end
				if not CatchFxData.SetPieces[z.SetPiece] then
					error(`zone {i}: unknown SetPiece "{tostring(z.SetPiece)}"`)
				end
				for kind in z.Shots or {} do
					if not CatchFxData.ShotKinds[kind] then
						error(`zone {i}: unknown shot override "{kind}"`)
					end
				end
			end
		end)

		it("has a default for every shot kind and walk beats inside the walk", function()
			for kind in CatchFxData.ShotKinds do
				expect(CatchFxData.Shots[kind] ~= nil).toBeTruthy()
			end
			local beats = CatchFxData.ShotBeats
			expect(beats.Track).toBeLessThanOrEqual(beats.Front)
			expect(beats.Front).toBeLessThanOrEqual(beats.Close)
			expect(beats.Close).toBeLessThanOrEqual(8)
			expect(CatchFxData.FullShowMinTier).toBeGreaterThanOrEqual(1)
		end)

		it("covers the Happy, Sleepy and Angry faces", function()
			expect(CatchFxData.Personality.Happy ~= nil).toBeTruthy()
			expect(CatchFxData.Personality.Sleepy ~= nil).toBeTruthy()
			expect(CatchFxData.Personality.Angry ~= nil).toBeTruthy()
		end)

		it("gives every slime a signature, and only real slimes", function()
			for _, s in GameConfig.Slimes do
				if not CatchFxData.Signatures[s.Id] then
					error(`no signature for {s.Id}`)
				end
			end
			for id in CatchFxData.Signatures do
				if not GameConfig.SlimesById[id] then
					error(`signature for unknown slime "{id}"`)
				end
			end
		end)

		it("only uses ops and presets CatchFx can play", function()
			for i, z in CatchFxData.Zones do
				checkOps(`zone {i} Walk`, z.Walk)
				checkOps(`zone {i} Land`, z.Land)
				checkOps(`zone {i} Show`, z.Show)
			end
			for face, layer in CatchFxData.Personality do
				checkOps(`{face} Walk`, layer.Walk)
				checkOps(`{face} Land`, layer.Land)
				checkOps(`{face} Show`, layer.Show)
			end
			for id, layer in CatchFxData.Signatures do
				checkOps(`{id} Walk`, layer.Walk)
				checkOps(`{id} Land`, layer.Land)
				checkOps(`{id} Show`, layer.Show)
			end
		end)
	end)
end
