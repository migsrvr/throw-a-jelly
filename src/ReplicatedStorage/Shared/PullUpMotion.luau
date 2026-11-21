--!strict
--[[
	PullUpMotion.luau
	Pure math for the exaggerated pull-up rep. No Roblox services, so it is unit-tested in Lune
	(tests/PullUpMotion.spec.luau). CharacterAnimator turns the returned pose into joint CFrames.

	One rep = phase u in [0, 1):
	  0.00 - 0.12  anticipation: body sinks below the dead hang (stretch)
	  0.12 - 0.50  explosive pull, overshooting above the bar. PEAK (chin over bar) is exactly u = 0.5,
	               which is when the server pays the rep, so shake / effects land on it.
	  0.50 - 0.58  hold at the top (settles from the overshoot)
	  0.58 - 0.95  accelerating drop back to the hang
	  0.95 - 1.00  small bounce at the bottom
]]

export type AnimConfig = {
	Rise: number,
	StretchDip: number,
	Overshoot: number,
	HoldFraction: number,
	ShoulderHang: number,
	ShoulderTopR15: number,
	ShoulderTopR6: number,
	ElbowTop: number,
	LeanBack: number,
	NeckTilt: number,
	Roll: number,
	KneeTuck: number,
	LegSwing: number,
}

-- All angles in degrees, distances in studs. Positive = lean back / chin up / leg forward / knee tuck.
export type Pose = {
	Lift: number, -- normalized curve value (about -StretchDip .. 1 + Overshoot), already scaled
	Rise: number,
	Lean: number,
	Roll: number,
	Neck: number,
	ShoulderR15: number,
	ShoulderR6: number,
	Elbow: number,
	HipL: number,
	HipR: number,
	KneeL: number,
	KneeR: number,
}

local PullUpMotion = {}

local ANTICIPATION_END = 0.12
local PEAK = 0.5
local BOUNCE_START = 0.95
local BOUNCE_DEPTH = 0.4 -- fraction of StretchDip used by the small bottom bounce

local MIN_INTENSITY = 0.4
local INTENSITY_REF_SECONDS = 1.0

local function smooth(t: number): number
	return 0.5 - 0.5 * math.cos(math.pi * t)
end

-- Normalized lift for phase u (wrapped into [0, 1)). 0 = dead hang, 1 = chin over bar.
function PullUpMotion.Curve(u: number, cfg: AnimConfig): number
	u = u % 1
	local dip = cfg.StretchDip
	local over = cfg.Overshoot
	local holdEnd = PEAK + cfg.HoldFraction

	if u < ANTICIPATION_END then
		return -dip * smooth(u / ANTICIPATION_END)
	elseif u < PEAK then
		local t = (u - ANTICIPATION_END) / (PEAK - ANTICIPATION_END)
		local e = 1 - (1 - t) ^ 3 -- explosive start, zero velocity at the peak
		return -dip + (1 + over + dip) * e
	elseif u < holdEnd then
		local t = (u - PEAK) / (holdEnd - PEAK)
		return 1 + over * (1 - smooth(t))
	elseif u < BOUNCE_START then
		local t = (u - holdEnd) / (BOUNCE_START - holdEnd)
		return 1 - t * t -- gravity: accelerating drop
	else
		local t = (u - BOUNCE_START) / (1 - BOUNCE_START)
		return -dip * BOUNCE_DEPTH * math.sin(math.pi * t)
	end
end

-- Faster reps (strong player / good bar) get a smaller motion so 0.35s reps stay readable.
function PullUpMotion.Intensity(intervalSeconds: number): number
	return math.clamp(intervalSeconds / INTENSITY_REF_SECONDS, MIN_INTENSITY, 1)
end

--[[
	Full pose for phase u.
	  scale      : intensity (x soft-stop blend). 0 = plain dead hang, 1 = full exaggeration.
	  repIndex   : which rep this is (alternates the body roll left/right).
	  timeSeconds: free-running clock for the gentle idle dangle.
]]
function PullUpMotion.Pose(u: number, scale: number, repIndex: number, timeSeconds: number, cfg: AnimConfig): Pose
	u = u % 1
	local lift = PullUpMotion.Curve(u, cfg) * scale
	local up = math.clamp(lift, 0, 1) -- only the upward part drives arm folds / tucks

	-- Pendulum leg swing while dropping and bouncing, fading out as the next rep starts
	local holdEnd = PEAK + cfg.HoldFraction
	local swing = 0
	if u >= holdEnd then
		local d = (u - holdEnd) / (1 - holdEnd)
		swing = cfg.LegSwing * math.sin(d * math.pi * 1.5) * (1 - 0.5 * d)
	elseif u < ANTICIPATION_END then
		-- residual swing from the previous rep's drop, damping out
		local d = u / ANTICIPATION_END
		swing = cfg.LegSwing * math.sin(math.pi * 1.5) * 0.5 * (1 - d)
	end
	swing *= scale
	local dangle = 3 * math.sin(timeSeconds * 2.2)
	local scissor = swing * 0.35

	local rollSign = if repIndex % 2 == 0 then 1 else -1
	local tuck = cfg.KneeTuck * (up ^ 1.5)

	return {
		Lift = lift,
		Rise = cfg.Rise * lift,
		Lean = cfg.LeanBack * up,
		Roll = cfg.Roll * up * rollSign,
		Neck = cfg.NeckTilt * up,
		ShoulderR15 = cfg.ShoulderHang - (cfg.ShoulderHang - cfg.ShoulderTopR15) * up,
		ShoulderR6 = cfg.ShoulderHang - (cfg.ShoulderHang - cfg.ShoulderTopR6) * up,
		Elbow = cfg.ElbowTop * up,
		HipL = 8 + 0.45 * tuck + swing + scissor + dangle,
		HipR = 8 + 0.45 * tuck + swing - scissor - dangle,
		KneeL = 20 + tuck,
		KneeR = 20 + tuck,
	}
end

-- Shortest signed distance from phase a to phase b on the [0, 1) circle, in [-0.5, 0.5).
function PullUpMotion.PhaseDelta(a: number, b: number): number
	return ((b - a + 0.5) % 1) - 0.5
end

PullUpMotion.PEAK = PEAK

return PullUpMotion
