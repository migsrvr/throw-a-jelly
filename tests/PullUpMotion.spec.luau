--!strict
--[[
	tests/PullUpMotion.spec.luau
	Unit tests for the exaggerated pull-up rep curve, intensity scaling and phase-lock helper.
]]

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local PullUpMotion = require("../src/ReplicatedStorage/Shared/PullUpMotion")

return function(t: any)
	local describe = t.describe
	local it = t.it
	local expect = t.expect

	local cfg = GameConfig.PullUp.Anim

	describe("PullUpMotion - Rep Curve", function()
		it("starts and ends at the dead hang and peaks (chin over bar) at phase 0.5", function()
			expect(PullUpMotion.Curve(0, cfg)).toBeNear(0)
			expect(PullUpMotion.Curve(0.999999, cfg)).toBeNear(0, 1e-3)
			expect(PullUpMotion.Curve(PullUpMotion.PEAK, cfg)).toBeNear(1 + cfg.Overshoot)
			-- the peak is the global maximum
			local maxV, maxU = -math.huge, 0
			for i = 0, 1000 do
				local u = i / 1000
				local v = PullUpMotion.Curve(u, cfg)
				if v > maxV then
					maxV, maxU = v, u
				end
			end
			expect(maxU).toBeNear(PullUpMotion.PEAK, 0.002)
		end)

		it("stretches below the hang and overshoots above the bar, within bounds", function()
			local minV, maxV = math.huge, -math.huge
			for i = 0, 1000 do
				local v = PullUpMotion.Curve(i / 1000, cfg)
				minV = math.min(minV, v)
				maxV = math.max(maxV, v)
			end
			expect(minV < 0).toBe(true)
			expect(minV).toBeGreaterThanOrEqual(-cfg.StretchDip - 1e-6)
			expect(maxV > 1).toBe(true)
			expect(maxV).toBeLessThanOrEqual(1 + cfg.Overshoot + 1e-6)
		end)

		it("is continuous (no visible pops) across every segment and the wrap", function()
			local steps = 4000
			local prev = PullUpMotion.Curve(0, cfg)
			for i = 1, steps do
				local v = PullUpMotion.Curve(i / steps, cfg) -- i == steps wraps back to u = 0
				expect(math.abs(v - prev)).toBeLessThanOrEqual(0.01)
				prev = v
			end
		end)

		it("holds near the top right after the peak", function()
			local holdMid = PullUpMotion.PEAK + cfg.HoldFraction * 0.5
			expect(PullUpMotion.Curve(holdMid, cfg)).toBeGreaterThanOrEqual(1)
		end)
	end)

	describe("PullUpMotion - Intensity & Pose", function()
		it("shrinks the motion for faster reps, clamped to [0.4, 1]", function()
			local prev = math.huge
			for _, interval in { 1.6, 1.0, 0.8, 0.6, 0.35 } do
				local v = PullUpMotion.Intensity(interval)
				expect(v <= prev).toBe(true)
				expect(v).toBeGreaterThanOrEqual(0.4)
				expect(v).toBeLessThanOrEqual(1)
				prev = v
			end
			expect(PullUpMotion.Intensity(GameConfig.PullUp.MinRepSeconds)).toBeNear(0.4)
			expect(PullUpMotion.Intensity(GameConfig.PullUp.BaseRepSeconds)).toBeNear(1)
		end)

		it("rises the full Rise at the peak with arms folded, and is a plain hang at scale 0", function()
			local peak = PullUpMotion.Pose(PullUpMotion.PEAK, 1, 0, 0, cfg)
			expect(peak.Rise).toBeNear(cfg.Rise * (1 + cfg.Overshoot))
			expect(peak.Elbow).toBeNear(cfg.ElbowTop)
			expect(peak.ShoulderR15).toBeNear(cfg.ShoulderTopR15)
			expect(peak.ShoulderR6).toBeNear(cfg.ShoulderTopR6)
			expect(peak.Neck).toBeNear(cfg.NeckTilt)

			local rest = PullUpMotion.Pose(PullUpMotion.PEAK, 0, 0, 0, cfg)
			expect(rest.Rise).toBeNear(0)
			expect(rest.Elbow).toBeNear(0)
			expect(rest.ShoulderR6).toBeNear(cfg.ShoulderHang)
		end)

		it("alternates the body roll left/right each rep", function()
			local a = PullUpMotion.Pose(PullUpMotion.PEAK, 1, 0, 0, cfg)
			local b = PullUpMotion.Pose(PullUpMotion.PEAK, 1, 1, 0, cfg)
			expect(a.Roll).toBeNear(cfg.Roll)
			expect(b.Roll).toBeNear(-cfg.Roll)
		end)
	end)

	describe("PullUpMotion - Phase Lock", function()
		it("returns the shortest signed distance around the cycle", function()
			expect(PullUpMotion.PhaseDelta(0.4, 0.5)).toBeNear(0.1)
			expect(PullUpMotion.PhaseDelta(0.6, 0.5)).toBeNear(-0.1)
			expect(PullUpMotion.PhaseDelta(0.95, 0.05)).toBeNear(0.1)
			expect(PullUpMotion.PhaseDelta(0.05, 0.95)).toBeNear(-0.1)
		end)
	end)
end
