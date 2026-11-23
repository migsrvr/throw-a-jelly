--!strict
--[[
	tests/SlimeMotion.spec.luau
	Catch-cutscene movement styles: every SlimeDef.Motion must be a style SlimeMotion implements.
]]

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")

return function(t: any)
	local describe = t.describe
	local it = t.it
	local expect = t.expect

	describe("SlimeMotion - Styles", function()
		it("every slime's Motion is nil or a known style", function()
			for _, s in GameConfig.Slimes do
				local m = s.Motion
				if m ~= nil then
					if not GameConfig.SlimeMotionStyles[m] then
						error(`{s.Id} has unknown Motion "{tostring(m)}"`)
					end
				end
			end
		end)

		it("uses every non-default style at least once", function()
			local seen: { [string]: boolean } = {}
			for _, s in GameConfig.Slimes do
				if s.Motion then
					seen[s.Motion] = true
				end
			end
			expect(seen.Fly).toBeTruthy()
			expect(seen.Slide).toBeTruthy()
			expect(seen.Waddle).toBeTruthy()
		end)
	end)
end
