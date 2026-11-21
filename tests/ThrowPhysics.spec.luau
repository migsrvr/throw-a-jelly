--!strict
--[[
	tests/ThrowPhysics.spec.luau
	Unit tests for deterministic throwing physics, zone floor elevation,
	locked gate collisions, lateral wall bounces, rolling stop, and
	the 9-segment vertical throw meter evaluator.
]]

local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local ThrowPhysics = require("../src/ReplicatedStorage/Shared/ThrowPhysics")

return function(t: any)
	local describe = t.describe
	local it = t.it
	local expect = t.expect

	describe("GameConfig - 9-Segment Vertical Throw Meter", function()
		it("maps meter ratio [0, 1] across segments 1..9 with monotonic BonusPower and LuckMultiplier", function()
			local segBottom = GameConfig.EvaluateMeterRatio(0.0)
			local segMid = GameConfig.EvaluateMeterRatio(0.5)
			local segTop = GameConfig.EvaluateMeterRatio(1.0)

			expect(segBottom.Index).toBe(1)
			expect(segMid.Index).toBe(5)
			expect(segTop.Index).toBe(9)

			expect(segMid.BonusPower).toBeGreaterThan(segBottom.BonusPower)
			expect(segTop.BonusPower).toBeGreaterThan(segMid.BonusPower)

			expect(segMid.LuckMultiplier).toBeGreaterThan(segBottom.LuckMultiplier)
			expect(segTop.LuckMultiplier).toBeGreaterThan(segMid.LuckMultiplier)
		end)
	end)

	describe("ThrowPhysics - Zone & Gate Helpers", function()
		it("resolves correct zone and floor elevation across all 5 zones", function()
			expect(ThrowPhysics.GetZoneAtZ(10).Index).toBe(1)
			expect(ThrowPhysics.GetFloorYAtZ(10)).toBe(0)

			expect(ThrowPhysics.GetZoneAtZ(250).Index).toBe(2)
			expect(ThrowPhysics.GetFloorYAtZ(250)).toBe(6)

			expect(ThrowPhysics.GetZoneAtZ(500).Index).toBe(3)
			expect(ThrowPhysics.GetFloorYAtZ(500)).toBe(12)

			expect(ThrowPhysics.GetZoneAtZ(800).Index).toBe(4)
			expect(ThrowPhysics.GetFloorYAtZ(800)).toBe(18)

			expect(ThrowPhysics.GetZoneAtZ(1050).Index).toBe(5)
			expect(ThrowPhysics.GetFloorYAtZ(1050)).toBe(24)
		end)

		it("identifies the first locked gate based on RequiredThrowPower thresholds", function()
			local gateZ1, blocked1 = ThrowPhysics.GetFirstLockedGate(10)
			expect(gateZ1).toBe(240)
			expect(blocked1).toBe(2)

			local gateZ2, blocked2 = ThrowPhysics.GetFirstLockedGate(50)
			expect(gateZ2).toBe(480)
			expect(blocked2).toBe(3)

			local gateZ3, blocked3 = ThrowPhysics.GetFirstLockedGate(250)
			expect(gateZ3).toBe(720)
			expect(blocked3).toBe(4)

			local gateZ4, blocked4 = ThrowPhysics.GetFirstLockedGate(1000)
			expect(gateZ4).toBe(960)
			expect(blocked4).toBe(5)

			local gateZ5, blocked5 = ThrowPhysics.GetFirstLockedGate(5000)
			expect(gateZ5).toBe(GameConfig.Hub.LaneMaxZ)
			expect(blocked5).toBe(nil)
		end)
	end)

	describe("ThrowPhysics - Trajectory & Collision Simulation", function()
		it("launches from Hub cliff (Y=31.7, Z=-3.6) and settles cleanly on Zone 1 floor", function()
			local res = ThrowPhysics.Simulate({
				ThrowPower = 5,
				ChargeRatio = 0.5,
				PitchDeg = 35,
			})
			expect(#res.Samples).toBeGreaterThan(20)
			expect(res.Distance).toBeGreaterThan(20)
			expect(res.Distance).toBeLessThanOrEqual(240)
			expect(res.LandedZoneIndex).toBe(1)
			expect(res.FinalPosition.Y).toBeNear(1.0, 0.01)
			expect(res.HitGate).toBe(false)
		end)

		it("scales distance monotonically with chargeRatio", function()
			local low = ThrowPhysics.Simulate({ ThrowPower = 20, ChargeRatio = 0.25 })
			local mid = ThrowPhysics.Simulate({ ThrowPower = 20, ChargeRatio = 0.60 })
			local full = ThrowPhysics.Simulate({ ThrowPower = 20, ChargeRatio = 1.00 })

			expect(mid.Distance).toBeGreaterThan(low.Distance)
			expect(full.Distance).toBeGreaterThan(mid.Distance)
		end)

		it("scales distance monotonically across unlocked ThrowPower tiers", function()
			local d1 = ThrowPhysics.Simulate({ ThrowPower = 10, ChargeRatio = 1.0 }).Distance
			local d2 = ThrowPhysics.Simulate({ ThrowPower = 120, ChargeRatio = 1.0 }).Distance
			local d3 = ThrowPhysics.Simulate({ ThrowPower = 600, ChargeRatio = 1.0 }).Distance
			local d4 = ThrowPhysics.Simulate({ ThrowPower = 2500, ChargeRatio = 1.0 }).Distance
			local d5 = ThrowPhysics.Simulate({ ThrowPower = 7500, ChargeRatio = 1.0 }).Distance

			expect(d2).toBeGreaterThan(d1)
			expect(d3).toBeGreaterThan(d2)
			expect(d4).toBeGreaterThan(d3)
			expect(d5).toBeGreaterThan(d4)
		end)

		it("blocks and rebounds off Zone 2 gate when ThrowPower < 50 even if velocity is huge", function()
			local res = ThrowPhysics.Simulate({
				ThrowPower = 49,
				ChargeRatio = 1.0,
				PitchDeg = 40,
				SlimeWeight = 0.5,
			})
			expect(res.HitGate).toBe(true)
			expect(res.BlockedByZoneIndex).toBe(2)
			expect(res.FinalPosition.Z).toBeLessThanOrEqual(240)
			expect(res.LandedZoneIndex).toBe(1)
		end)

		it("clears Zone 2 gate once ThrowPower >= 50", function()
			local res = ThrowPhysics.Simulate({
				ThrowPower = 55,
				ChargeRatio = 1.0,
				PitchDeg = 40,
				SlimeWeight = 0.75,
			})
			expect(res.FinalPosition.Z).toBeGreaterThan(240)
			expect(res.LandedZoneIndex).toBeGreaterThanOrEqual(2)
		end)

		it("contains angled throws within ClearHalfWidth lateral walls", function()
			local maxHalf = GameConfig.Hub.ClearHalfWidth - 1.0
			local res = ThrowPhysics.Simulate({
				Origin = ThrowPhysics.Vec3(15, 31.7, -3.6),
				ThrowPower = 500,
				ChargeRatio = 1.0,
				YawDeg = 18,
			})
			for _, sample in res.Samples do
				expect(math.abs(sample.Position.X)).toBeLessThanOrEqual(maxHalf + 1e-4)
			end
		end)

		it("records bounces and terminates within MaxSimSeconds", function()
			local res = ThrowPhysics.Simulate({
				ThrowPower = 80,
				ChargeRatio = 0.9,
			})
			expect(#res.BounceTimes).toBeGreaterThanOrEqual(1)
			expect(res.TotalDuration).toBeLessThanOrEqual(GameConfig.Physics.MaxSimSeconds)
		end)
	end)
end
