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

		it("enforces an exact 9-segment baseline: monotonic ChargeRatio/Luck, valid labels, and ONLY Band 9 is PERFECT", function()
			local prevCharge = 0
			local prevLuck = 0
			for i, seg in GameConfig.MeterSegments do
				expect(seg.Index).toBe(i)
				expect(type(seg.QualityLabel) == "string" and #seg.QualityLabel > 0).toBe(true)
				expect(seg.ChargeRatio).toBeGreaterThan(prevCharge)
				expect(seg.LuckMultiplier).toBeGreaterThan(prevLuck)
				expect(seg.IsPerfect == true).toBe(i == #GameConfig.MeterSegments)
				prevCharge = seg.ChargeRatio
				prevLuck = seg.LuckMultiplier
			end
			-- Red (ratio 0.0..0.1) must never be PERFECT
			expect(GameConfig.EvaluateMeterRatio(0.0).IsPerfect == true).toBe(false)
			expect(GameConfig.EvaluateMeterRatio(0.05).QualityLabel).toBe("WEAK")
			expect(GameConfig.EvaluateMeterRatio(1.0).QualityLabel).toBe("PERFECT!")
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

		it("conserves initial horizontal speed magnitude across yaw angles (vx^2 + vz^2 == horizSpeed^2)", function()
			local res0 = ThrowPhysics.Simulate({
				ThrowPower = 40,
				ChargeRatio = 0.8,
				PitchDeg = 36,
				YawDeg = 0,
			})
			local resYaw = ThrowPhysics.Simulate({
				ThrowPower = 40,
				ChargeRatio = 0.8,
				PitchDeg = 36,
				YawDeg = 18,
			})
			local v0 = res0.Samples[1].Velocity
			local vY = resYaw.Samples[1].Velocity
			local hMag0 = math.sqrt(v0.X * v0.X + v0.Z * v0.Z)
			local hMagY = math.sqrt(vY.X * vY.X + vY.Z * vY.Z)
			expect(hMag0).toBeNear(res0.LaunchSpeed * math.cos(math.rad(36)), 1e-4)
			expect(hMagY).toBeNear(hMag0, 1e-4)
		end)

		it("lands cleanly near each zone end right below the gate without wall bounces, and enters cleanly on unlock", function()
			for _, pair in {
				{ Below = 49, Unlock = 50, BelowZone = 1, UnlockZone = 2 },
				{ Below = 249, Unlock = 250, BelowZone = 2, UnlockZone = 3 },
				{ Below = 999, Unlock = 1000, BelowZone = 3, UnlockZone = 4 },
				{ Below = 4999, Unlock = 5000, BelowZone = 4, UnlockZone = 5 },
			} do
				local rBelow = ThrowPhysics.Simulate({ ThrowPower = pair.Below, ChargeRatio = 1.0, SlimeWeight = 1.0 })
				expect(rBelow.HitGate).toBe(false)
				expect(rBelow.LandedZoneIndex).toBe(pair.BelowZone)

				local rUnlock = ThrowPhysics.Simulate({ ThrowPower = pair.Unlock, ChargeRatio = 1.0, SlimeWeight = 1.0 })
				expect(rUnlock.HitGate).toBe(false)
				expect(rUnlock.LandedZoneIndex).toBe(pair.UnlockZone)
			end
		end)

		it("increases landing distance monotonically across all power checkpoints from 5 to 25,000", function()
			local prev = 0
			for _, p in { 5, 10, 25, 49, 50, 100, 160, 249, 250, 500, 850, 999, 1000, 2200, 4999, 5000, 10000, 25000 } do
				local dist = ThrowPhysics.Simulate({ ThrowPower = p, ChargeRatio = 1.0, SlimeWeight = 1.0 }).Distance
				expect(dist >= prev).toBe(true)
				prev = dist
			end
		end)

		it("Auto-Throw 5-throw shuffle bag guarantees exactly 3 PERFECT and 2 GOOD per 5-throw cycle", function()
			local bag: { number } = {}
			local seenOrders: { [string]: boolean } = {}
			-- Deterministic LCG so the shuffle varies across cycles reproducibly
			local seed = 42
			local function nextRng(): number
				seed = (seed * 1103515245 + 12345) % 2147483648
				return seed / 2147483648
			end

			for _ = 1, 10 do
				local perfects = 0
				local goods = 0
				local pattern = {}
				for _ = 1, 5 do
					local peekRatio, peekPerf = ThrowPhysics.PeekAutoThrowRatio(bag, nextRng)
					local ratio, isPerfect = ThrowPhysics.NextAutoThrowRatio(bag, nextRng)
					expect(ratio).toBe(peekRatio)
					expect(isPerfect).toBe(peekPerf)
					if isPerfect then
						perfects += 1
						expect(ratio).toBe(GameConfig.AutoThrow.PerfectMeterRatio)
						table.insert(pattern, "P")
					else
						goods += 1
						expect(ratio).toBe(GameConfig.AutoThrow.GoodMeterRatio)
						table.insert(pattern, "G")
					end
				end
				expect(perfects).toBe(3)
				expect(goods).toBe(2)
				seenOrders[table.concat(pattern)] = true
			end

			local uniqueOrders = 0
			for _ in seenOrders do
				uniqueOrders += 1
			end
			expect(uniqueOrders).toBeGreaterThan(1)
		end)

		it("never teleports a low bait upward onto a higher terrain at stepped cliff edges (Z=240, 480, 720, 960)", function()
			for _, case in {
				{ OriginZ = 230, FloorY = 0, StepZ = 240, LowerZone = 1, Power = 5000 },
				{ OriginZ = 470, FloorY = 6, StepZ = 480, LowerZone = 2, Power = 5000 },
				{ OriginZ = 710, FloorY = 12, StepZ = 720, LowerZone = 3, Power = 5000 },
				{ OriginZ = 950, FloorY = 18, StepZ = 960, LowerZone = 4, Power = 5000 },
			} do
				local res = ThrowPhysics.Simulate({
					Origin = ThrowPhysics.Vec3(0, case.FloorY + 1.5, case.OriginZ),
					ThrowPower = case.Power,
					ChargeRatio = 0.25,
					PitchDeg = 18,
					SlimeWeight = 2.0,
				})
				expect(res.FinalPosition.Z < case.StepZ).toBe(true)
				expect(res.LandedZoneIndex).toBe(case.LowerZone)
			end

			-- Sweep Hub throws across powers & all 9 meter segments: crossing any zone step must occur ABOVE its floor
			local dt = GameConfig.Physics.FixedDt
			for _, p in { 5, 25, 49, 50, 120, 249, 250, 600, 999, 1000, 2500, 4999, 5000, 10000, 25000 } do
				for _, seg in GameConfig.MeterSegments do
					local sim = ThrowPhysics.Simulate({
						ThrowPower = p,
						ChargeRatio = seg.ChargeRatio,
						SlimeWeight = 1.0,
					})
					for i = 2, #sim.Samples do
						local prev = sim.Samples[i - 1]
						local cur = sim.Samples[i]
						local prevFloor = ThrowPhysics.GetFloorYAtZ(math.max(0, prev.Position.Z))
						local curFloor = ThrowPhysics.GetFloorYAtZ(math.max(0, cur.Position.Z))
						if curFloor > prevFloor then
							-- Bait crossed forward onto a higher zone: it must have cleared the cliff in mid-air
							expect(prev.Position.Y >= curFloor + 0.5).toBe(true)
							expect(cur.Position.Y >= curFloor + 0.5).toBe(true)
						end
						-- Never jump upward faster than physics velocity allows in one tick
						local maxAllowedRise = math.max(0, prev.Velocity.Y) * dt + 2.0
						expect(cur.Position.Y - prev.Position.Y <= maxAllowedRise).toBe(true)
					end
				end
			end
		end)
	end)
end
