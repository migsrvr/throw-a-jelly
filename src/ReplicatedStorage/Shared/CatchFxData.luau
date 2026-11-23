--!strict
--[[
	CatchFxData.luau
	DESIGN DATA for the catch-cutscene effects (played by CatchFx.luau). Pure data, no Roblox calls, so it is
	unit-tested (tests/CatchFx.spec.luau) and its part names are checked against the real models
	(lune run scripts/check-slime-models assets.rbxl).

	Three layers, all optional per entry:
	  Zones[zoneIndex]        screen mood for the zone the bait landed in (whole cutscene)
	  Personality[faceType]   small extras from the model's Face_<Type> group (Happy / Sleepy / Angry)
	  Signatures[slimeId]     per-slime effects built on the model's own Acc_* parts (docs/docs/SLIME-PARTS.md)

	Each layer has op lists for three moments:
	  Walk  starts when the slime is visible on its walk (immediately for known slimes, ~halfway for new ones)
	  Land  fires on every walking step landing
	  Show  fires when the slime floats up into the catch showcase

	OPS (field "Op"):
	  Motion (drive SlimeFactory.SetPartMotion on Key, combined per key every frame):
	    Spin   { Key, Axis = "X"|"Y"|"Z", Rpm, Bob? (template studs), BobHz? }
	    Wobble { Key, Axis, Deg, Hz, Phase? }
	    Bob    { Key, Amp (template studs), Hz, Phase? }
	    Pulse  { Key, Min, Max, Hz }            (uniform scale)
	    Grow   { Key, From, To, Time }          (scale tween; the latest Grow on a key wins)
	  Parts (target = Pattern (Lua pattern on part/node names) or Key (exact name); default = the body):
	    Glow     { Pattern|Key }                (Neon)
	    GlowWave { Pattern, Hz }                (one part at a time, in order)
	    Light    { Pattern|Key, Color, Range, Brightness, Pulse? (Hz), Spot? }
	    Hide     { Pattern|Key, Delay? }
	  Particles (Preset = Sparkle | Smoke | Fire | Embers | Sparks | Bubbles | Snow | Leaves | Petals | Stars |
	             Confetti | Feathers | Seeds | Sand | Dust | Glints | Wisps | Spores | Icon (+ Tex = icon name)):
	    Emit   { Preset, Color?, Rate?, Pattern|Key? }            continuous from the part(s)
	    Burst  { Preset, Color?, Count, Pattern|Key?, Speed? }     one shot (Land: from the ground if no target)
	    Orbit  { Preset, Color?, Radius, Hz, Rate?, Rise? }        emitter circling the slime (swirls, bee, twister)
	    Rain   { Preset, Color?, Count }                           falls from above the slime
	    Cannon { Preset, Color?, Count }                           from both screen sides toward the slime
	    Ambient{ Preset, Color?, Rate, Size = {x, y, z}, Height }  box of particles over the stage
	  Screen / world:
	    Beam      { Kind = "Holy" | "Aurora" | "Rainbow" | "Arcs", Color?, Pattern? }
	    Rays      { Tex = "sunburst" | "glow", Color, Scale, Spin (seconds per turn, 0 = still, <0 reverse) }
	    RingPulse { Color, Count? }
	    Flash     { Color, Alpha }
	    Sweep     { Color }                      (hazard stripes sliding across the top / bottom edges)
	    Edge      { Color, Alpha }               (extra screen-edge vignette, e.g. frost creeping in)
	    Tint      { Colors = { RGB... }, Time }  (sweep the screen grade through colours)
	    Shake     { Time }
	    Haze      { }                            (heat shimmer: tiny FOV wobble)
	  Any op may have Delay (seconds).

	Colours are { r, g, b } (0-255).
]]

export type RGB = { number }
export type Op = { [string]: any }
export type Layer = { Walk: { Op }?, Land: { Op }?, Show: { Op }? }
export type ZonePreset = {
	Emerge: string?,
	SetPiece: string?,
	Shots: { [string]: { [string]: number } }?,
	Grade: { Tint: RGB, Saturation: number, Contrast: number, Brightness: number, Bloom: number },
	Edge: { Color: RGB, Alpha: number, Tex: string?, PulseHz: number? },
	Walk: { Op }?,
	Land: { Op }?,
	Show: { Op }?,
}

local CatchFxData = {}

CatchFxData.MotionOps = { Spin = true, Wobble = true, Bob = true, Pulse = true, Grow = true }
CatchFxData.KnownOps = {
	Spin = true,
	Wobble = true,
	Bob = true,
	Pulse = true,
	Grow = true,
	Glow = true,
	GlowWave = true,
	Light = true,
	Hide = true,
	Emit = true,
	Burst = true,
	Orbit = true,
	Rain = true,
	Cannon = true,
	Ambient = true,
	Beam = true,
	Rays = true,
	RingPulse = true,
	Flash = true,
	Sweep = true,
	Edge = true,
	Tint = true,
	Shake = true,
	Haze = true,
}
CatchFxData.KnownPresets = {
	Sparkle = true,
	Smoke = true,
	Fire = true,
	Embers = true,
	Sparks = true,
	Bubbles = true,
	Snow = true,
	Leaves = true,
	Petals = true,
	Stars = true,
	Confetti = true,
	Feathers = true,
	Seeds = true,
	Sand = true,
	Dust = true,
	Glints = true,
	Wisps = true,
	Spores = true,
	Icon = true,
}

-- ============================================================================
-- EXAGGERATED SHOW: who gets it, how the slime comes out, which set piece, camera shots
-- ============================================================================

-- New discoveries and slimes of this rarity tier or higher get the full show (intro prop, struggle
-- emergence, camera cuts, set-piece climax). Others get the lite show. Tiers: Common 1 .. Mythic 6.
CatchFxData.FullShowMinTier = 3

CatchFxData.EmergeStyles = { Burrow = true, Mound = true, Pool = true, Geode = true, Box = true, Bush = true }
CatchFxData.SetPieces = {
	Meadow = true,
	Crystal = true,
	Volcano = true,
	Blizzard = true,
	Candy = true,
	Desert = true,
	Acid = true,
}

-- Camera shots (ThrowController ShotDirector). Distances in studs, Fov in degrees, Dutch = camera roll.
--   Establish  high + wide over the stage and the zone set piece, slow push-in (full intro)
--   Ground     ground-level close-up on the emerge spot (full emergence)
--   Track      side tracking framing that keeps the slime above the name title (walk)
--   Front      low behind the bait, looking back at the slime creeping toward the camera
--   Close      the last step: starts at Back and pulls out by Pull x Back over PullTime (dramatic zoom-out)
--   AboveTitle the final showcase framing (slime centred above the name title)
CatchFxData.ShotKinds = { Establish = true, Ground = true, Track = true, Front = true, Close = true, AboveTitle = true }
CatchFxData.Shots = {
	Establish = { Fov = 60, Back = 22, Up = 10, Push = 0.15 },
	Ground = { Fov = 55, Back = 5, Up = 0.7, Side = 1.5, Dutch = 8 },
	Track = { Sway = 0.06 },
	Front = { Fov = 62, Back = 3.6, Up = 1.3, Side = 0.9, Dutch = -4 },
	Close = { Fov = 60, Back = 6, Up = 1.8, Pull = 0.45, PullTime = 0.7 },
	AboveTitle = {},
}
-- Which walk step each shot starts on (full show); the lite show tracks the whole walk
CatchFxData.ShotBeats = { Track = 1, Front = 5, Close = 8 }

-- ============================================================================
-- A. ZONES (index = GameConfig.Zones index)
--   Emerge   how the slime comes out in the full show (Burrow / Mound / Pool / Geode / Box / Bush)
--   SetPiece the zone spectacle built by CatchSetPieces.luau
--   Shots    optional per-zone overrides of CatchFxData.Shots
-- ============================================================================
CatchFxData.Zones = {
	-- 1 Meadow: drifting leaves + petals + pollen, warm and saturated
	{
		Emerge = "Bush", SetPiece = "Meadow", Shots = { Ground = { Back = 6.5, Up = 1.4, Fov = 58, Dutch = 4 } },
		Grade = { Tint = { 255, 248, 232 }, Saturation = 0.15, Contrast = 0.05, Brightness = 0.02, Bloom = 0.4 },
		Edge = { Color = { 124, 255, 138 }, Alpha = 0.55 },
		Walk = {
			{ Op = "Ambient", Preset = "Leaves", Rate = 4, Size = { 36, 1, 20 }, Height = 10 },
			{ Op = "Ambient", Preset = "Petals", Color = { 255, 170, 210 }, Rate = 3, Size = { 36, 1, 20 }, Height = 10 },
			{ Op = "Ambient", Preset = "Glints", Color = { 255, 240, 150 }, Rate = 6, Size = { 30, 6, 16 }, Height = 3 },
		},
		Show = {
			{ Op = "Orbit", Preset = "Leaves", Radius = 2.6, Hz = 0.8, Rise = true, Rate = 14 },
			{ Op = "Orbit", Preset = "Petals", Color = { 255, 170, 210 }, Radius = 3.0, Hz = -0.7, Rate = 12 },
			{ Op = "Beam", Kind = "Holy", Color = { 255, 245, 205 } },
		},
	},
	-- 2 Crystal Cave: twinkling glints and motes, cool and dark-edged, prism sweep on the catch
	{
		Emerge = "Geode", SetPiece = "Crystal", Shots = { Track = { Sway = 0.08 } },
		Grade = { Tint = { 225, 235, 255 }, Saturation = 0.05, Contrast = 0.1, Brightness = -0.03, Bloom = 0.7 },
		Edge = { Color = { 60, 40, 140 }, Alpha = 0.35 },
		Walk = {
			{ Op = "Ambient", Preset = "Glints", Color = { 120, 230, 255 }, Rate = 8, Size = { 34, 10, 18 }, Height = 4 },
			{ Op = "Ambient", Preset = "Glints", Color = { 200, 140, 255 }, Rate = 5, Size = { 34, 10, 18 }, Height = 4 },
			{ Op = "Ambient", Preset = "Dust", Color = { 170, 180, 220 }, Rate = 3, Size = { 34, 8, 18 }, Height = 3 },
		},
		Show = {
			{ Op = "Burst", Preset = "Stars", Color = { 140, 230, 255 }, Count = 30 },
			{ Op = "Tint", Colors = { { 190, 255, 255 }, { 255, 190, 255 }, { 255, 250, 190 }, { 225, 235, 255 } }, Time = 0.8 },
		},
	},
	-- 3 Lava Fields: rising embers + ash, hot grade with heat haze, eruption on the catch
	{
		Emerge = "Pool", SetPiece = "Volcano", Shots = { Establish = { Back = 26, Up = 8, Fov = 66, Push = 0.2 } },
		Grade = { Tint = { 255, 228, 200 }, Saturation = 0.1, Contrast = 0.15, Brightness = 0, Bloom = 0.5 },
		Edge = { Color = { 255, 90, 30 }, Alpha = 0.45 },
		Walk = {
			{ Op = "Ambient", Preset = "Embers", Rate = 14, Size = { 34, 1, 18 }, Height = 0.5 },
			{ Op = "Ambient", Preset = "Dust", Color = { 90, 80, 80 }, Rate = 3, Size = { 34, 1, 18 }, Height = 9 },
			{ Op = "Haze" },
		},
		Show = {
			{ Op = "Burst", Preset = "Fire", Color = { 255, 140, 40 }, Count = 40, Speed = 9 },
			{ Op = "Burst", Preset = "Embers", Count = 30 },
			{ Op = "Shake", Time = 0.25 },
		},
	},
	-- 4 Frost Peaks: falling snow, cold desaturated grade, frosted corners, breath puffs, ice burst
	{
		Emerge = "Mound", SetPiece = "Blizzard", Shots = { Ground = { Up = 0.35, Dutch = 10 } },
		Grade = { Tint = { 225, 240, 255 }, Saturation = -0.15, Contrast = 0.03, Brightness = 0.03, Bloom = 0.3 },
		Edge = { Color = { 225, 245, 255 }, Alpha = 0.25 },
		Walk = {
			{ Op = "Ambient", Preset = "Snow", Rate = 18, Size = { 36, 1, 20 }, Height = 10 },
		},
		Land = {
			{ Op = "Burst", Preset = "Smoke", Color = { 240, 248, 255 }, Count = 3 },
		},
		Show = {
			{ Op = "Burst", Preset = "Stars", Color = { 190, 235, 255 }, Count = 30 },
			{ Op = "Orbit", Preset = "Snow", Radius = 2.8, Hz = 1.2, Rate = 30 },
		},
	},
	-- 5 Candy Land: bubbles + sprinkles, pastel grade with candy-stripe edges, confetti cannons
	{
		Emerge = "Box", SetPiece = "Candy",
		Grade = { Tint = { 255, 235, 245 }, Saturation = 0.2, Contrast = 0.02, Brightness = 0.02, Bloom = 0.6 },
		Edge = { Color = { 255, 140, 200 }, Alpha = 0.5, Tex = "stripes" },
		Walk = {
			{ Op = "Ambient", Preset = "Bubbles", Color = { 255, 180, 230 }, Rate = 5, Size = { 34, 1, 18 }, Height = 0.5 },
			{ Op = "Ambient", Preset = "Confetti", Rate = 5, Size = { 36, 1, 20 }, Height = 10 },
		},
		Show = {
			{ Op = "Cannon", Preset = "Confetti", Count = 45 },
			{ Op = "Burst", Preset = "Sparkle", Color = { 255, 220, 250 }, Count = 25 },
		},
	},
	-- 6 Desert Dunes: sideways sand streaks, warm sepia, sand twister + golden sun rays
	{
		Emerge = "Mound", SetPiece = "Desert",
		Grade = { Tint = { 255, 236, 205 }, Saturation = -0.05, Contrast = 0.08, Brightness = 0.02, Bloom = 0.35 },
		Edge = { Color = { 230, 180, 100 }, Alpha = 0.45 },
		Walk = {
			{ Op = "Ambient", Preset = "Sand", Rate = 8, Size = { 4, 3, 18 }, Height = 1.2 },
			{ Op = "Haze" },
		},
		Show = {
			{ Op = "Orbit", Preset = "Sand", Radius = 2.2, Hz = 1.6, Rise = true, Rate = 30 },
			{ Op = "Rays", Tex = "sunburst", Color = { 255, 205, 90 }, Scale = 1.3, Spin = 10 },
		},
	},
	-- 7 Acid Swamp: rising bubbles + low toxic fog, sickly grade with pulsing edges, bubble pop + radiation ring
	{
		Emerge = "Pool", SetPiece = "Acid",
		Grade = { Tint = { 220, 255, 215 }, Saturation = -0.1, Contrast = 0.05, Brightness = 0, Bloom = 0.4 },
		Edge = { Color = { 110, 255, 90 }, Alpha = 0.45, PulseHz = 0.6 },
		Walk = {
			{ Op = "Ambient", Preset = "Bubbles", Color = { 130, 255, 110 }, Rate = 10, Size = { 34, 1, 18 }, Height = 0.3 },
			{ Op = "Ambient", Preset = "Smoke", Color = { 120, 200, 90 }, Rate = 3, Size = { 34, 1, 18 }, Height = 0.6 },
		},
		Show = {
			{ Op = "Burst", Preset = "Bubbles", Color = { 130, 255, 110 }, Count = 35 },
			{ Op = "RingPulse", Color = { 130, 255, 110 }, Count = 2 },
		},
	},
}

-- ============================================================================
-- B. FACE PERSONALITY (from the model's Face_<Type> group)
-- ============================================================================
CatchFxData.Personality = {
	-- heavier landings, a "huff" at the catch
	Angry = {
		Land = { { Op = "Burst", Preset = "Dust", Count = 6 } },
		Show = { { Op = "Burst", Preset = "Smoke", Color = { 150, 150, 150 }, Count = 8 } },
	},
	-- drifting dreamy sparkles (and slower blinks, set in ThrowController)
	Sleepy = {
		Walk = { { Op = "Emit", Preset = "Sparkle", Color = { 170, 200, 255 }, Rate = 1.5 } },
	},
	-- star sparkles at the catch (and a bouncier float-up, set in ThrowController)
	Happy = {
		Show = { { Op = "Burst", Preset = "Stars", Color = { 255, 235, 120 }, Count = 18 } },
	},
}

-- ============================================================================
-- C. PER-SLIME SIGNATURES (part names from docs/docs/SLIME-PARTS.md)
-- ============================================================================
local GOLD = { 255, 205, 70 }
local ICE = { 190, 235, 255 }
local TOXIC = { 130, 255, 110 }

CatchFxData.Signatures = {
	-- ===== Meadow =====
	meadow_sprout = {
		Walk = { { Op = "Wobble", Key = "Acc_Sprout", Axis = "Z", Deg = 8, Hz = 1.5 } },
		Land = { { Op = "Burst", Preset = "Leaves", Key = "Leaf_L", Count = 2 } },
		Show = { { Op = "Spin", Key = "Acc_Sprout", Axis = "Y", Rpm = 240 } }, -- propeller!
	},
	meadow_clover = {
		Walk = { { Op = "Emit", Preset = "Glints", Color = { 120, 255, 140 }, Key = "Acc_Clover", Rate = 4 } },
		Show = {
			{ Op = "Spin", Key = "Node30", Axis = "Y", Rpm = 120 },
			{ Op = "Orbit", Preset = "Icon", Tex = "clover", Radius = 2.4, Hz = 0.9, Rate = 8 },
		},
	},
	meadow_dandelion = {
		Walk = { { Op = "Emit", Preset = "Seeds", Key = "DandelionPuff", Rate = 2 } },
		Show = {
			{ Op = "Burst", Preset = "Seeds", Key = "DandelionPuff", Count = 45, Speed = 6 },
			{ Op = "Hide", Key = "DandelionPuff", Delay = 0.05 },
		},
	},
	meadow_honey = {
		Walk = {
			{ Op = "Wobble", Key = "Acc_BeeAntennae", Axis = "Z", Deg = 6, Hz = 3 },
			{ Op = "Emit", Preset = "Glints", Color = GOLD, Key = "Acc_BeeAntennae", Rate = 3 },
		},
		Show = {
			{ Op = "Glow", Pattern = "^AntennaTip_" },
			{ Op = "Light", Key = "Acc_BeeAntennae", Color = GOLD, Range = 10, Brightness = 3 },
			{ Op = "Orbit", Preset = "Sparkle", Color = GOLD, Radius = 1.8, Hz = 1.5, Rate = 25 }, -- a buzzing bee
		},
	},
	meadow_mushroom = {
		Land = { { Op = "Burst", Preset = "Spores", Key = "MushroomCap", Count = 6 } },
		Show = {
			{ Op = "GlowWave", Pattern = "^MushroomSpot_", Hz = 6 },
			{ Op = "Burst", Preset = "Spores", Key = "MushroomCap", Count = 30 },
		},
	},
	meadow_bloom = {
		Walk = { { Op = "Emit", Preset = "Petals", Color = { 255, 170, 210 }, Key = "Acc_Flower", Rate = 4 } },
		Show = {
			{ Op = "Spin", Key = "Node25", Axis = "Y", Rpm = 90 },
			{ Op = "Burst", Preset = "Petals", Color = { 255, 170, 210 }, Count = 60, Speed = 7 },
		},
	},

	-- ===== Crystal Cave =====
	crystal_pebble = {
		Land = { { Op = "Burst", Preset = "Dust", Color = { 150, 150, 160 }, Count = 5 } },
		Show = {
			{ Op = "Wobble", Key = "Acc_Pickaxe", Axis = "X", Deg = 40, Hz = 1.6 },
			{ Op = "Burst", Preset = "Sparks", Key = "PickaxeHead", Count = 15 },
		},
	},
	crystal_quartz = {
		-- the miner helmet lamp is a real light that lights the cave in front of it
		Walk = { { Op = "Light", Key = "LampLens", Color = { 255, 240, 200 }, Range = 18, Brightness = 3, Spot = true } },
		Show = {
			{ Op = "Light", Key = "LampLens", Color = { 255, 255, 255 }, Range = 22, Brightness = 6, Spot = true },
			{ Op = "Emit", Preset = "Glints", Color = { 255, 255, 255 }, Key = "LampLens", Rate = 10 },
		},
	},
	crystal_glowcap = {
		Walk = {
			{ Op = "GlowWave", Pattern = "^GlowCap_", Hz = 1.5 },
			{ Op = "Light", Key = "Acc_Glowcaps", Color = { 120, 230, 255 }, Range = 10, Brightness = 1.5, Pulse = 1.5 },
		},
		Show = {
			{ Op = "Glow", Pattern = "^GlowCap_" },
			{ Op = "Light", Key = "Acc_Glowcaps", Color = { 120, 230, 255 }, Range = 22, Brightness = 5 },
		},
	},
	crystal_amethyst = {
		Walk = { { Op = "Emit", Preset = "Glints", Color = { 200, 140, 255 }, Key = "Acc_CrystalCluster", Rate = 4 } },
		Show = {
			{ Op = "Glow", Pattern = "^Crystal_" },
			{ Op = "Burst", Preset = "Stars", Color = { 200, 140, 255 }, Count = 30 },
		},
	},
	crystal_bat = {
		Walk = { { Op = "Emit", Preset = "Wisps", Color = { 60, 40, 80 }, Key = "Acc_BatWings", Rate = 6 } },
		Show = { -- bats swooping around it
			{ Op = "Orbit", Preset = "Wisps", Color = { 50, 30, 70 }, Radius = 3.2, Hz = 1.6, Rate = 30 },
			{ Op = "Orbit", Preset = "Wisps", Color = { 50, 30, 70 }, Radius = 2.6, Hz = -1.9, Rate = 30 },
		},
	},
	crystal_prism = {
		Walk = { { Op = "Spin", Key = "Acc_FloatingGems", Axis = "Y", Rpm = 30 } }, -- gems orbit its head
		Show = {
			{ Op = "Spin", Key = "Acc_FloatingGems", Axis = "Y", Rpm = 160 },
			{ Op = "Beam", Kind = "Rainbow", Pattern = "^Gem_" },
			{ Op = "Burst", Preset = "Stars", Count = 25 }, -- no Color = rainbow
		},
	},

	-- ===== Lava Fields =====
	lava_ember = {
		Walk = {
			{ Op = "Pulse", Key = "Acc_Flame", Min = 0.9, Max = 1.12, Hz = 7 },
			{ Op = "Emit", Preset = "Fire", Color = { 255, 140, 40 }, Key = "Flame_Main", Rate = 12 },
			{ Op = "Light", Key = "Acc_Flame", Color = { 255, 140, 40 }, Range = 10, Brightness = 2, Pulse = 6 },
		},
		Show = {
			{ Op = "Grow", Key = "Acc_Flame", From = 1, To = 1.6, Time = 0.3 },
			{ Op = "Burst", Preset = "Sparks", Key = "Flame_Main", Count = 40 },
		},
	},
	lava_salamander = {
		Land = { { Op = "Burst", Preset = "Fire", Color = { 255, 120, 40 }, Count = 5 } }, -- fire footprints
		Show = {
			{ Op = "GlowWave", Pattern = "^Spike_", Hz = 8 },
			{ Op = "Orbit", Preset = "Fire", Color = { 255, 120, 40 }, Radius = 2.4, Hz = 1.2, Rate = 30 },
		},
	},
	lava_volcano = {
		Walk = { { Op = "Emit", Preset = "Smoke", Color = { 80, 70, 70 }, Key = "VolcanoLava", Rate = 5 } },
		Show = { -- mini eruption from the hat
			{ Op = "Burst", Preset = "Fire", Color = { 255, 110, 30 }, Key = "VolcanoLava", Count = 35, Speed = 10 },
			{ Op = "Burst", Preset = "Embers", Key = "VolcanoLava", Count = 30 },
			{ Op = "Shake", Time = 0.2 },
		},
	},
	lava_obsidian = {
		Walk = { { Op = "Light", Key = "Core", Color = { 255, 80, 30 }, Range = 8, Brightness = 1.5, Pulse = 1.2 } },
		Show = {
			{ Op = "Glow", Pattern = "^HornTip_" },
			{ Op = "Light", Key = "Core", Color = { 255, 80, 30 }, Range = 18, Brightness = 6 },
			{ Op = "Burst", Preset = "Sparks", Count = 20 },
		},
	},
	lava_phoenix = {
		Walk = { { Op = "Emit", Preset = "Fire", Color = { 255, 150, 50 }, Pattern = "^Wing", Rate = 5 } },
		Show = {
			{ Op = "Grow", Key = "Acc_PhoenixCrest", From = 1, To = 1.25, Time = 0.3 },
			{ Op = "Burst", Preset = "Fire", Color = { 255, 150, 50 }, Count = 50, Speed = 8 },
			{ Op = "Orbit", Preset = "Fire", Color = { 255, 190, 80 }, Radius = 2.8, Hz = 1.4, Rate = 30 },
		},
	},
	lava_solar = {
		Walk = { { Op = "Light", Key = "Body", Color = { 255, 220, 90 }, Range = 10, Brightness = 1.5 } },
		Show = {
			{ Op = "GlowWave", Pattern = "^Lens_", Hz = 4 }, -- "cool" lens glint
			{ Op = "Burst", Preset = "Glints", Color = { 255, 255, 255 }, Key = "Lens_L", Count = 6 },
			{ Op = "Rays", Tex = "sunburst", Color = { 255, 220, 90 }, Scale = 1.5, Spin = 4 },
		},
	},

	-- ===== Frost Peaks =====
	frost_snowball = {
		Land = { { Op = "Burst", Preset = "Snow", Count = 8 } },
		Show = {
			{ Op = "Wobble", Key = "Arm_L", Axis = "Z", Deg = 25, Hz = 3 },
			{ Op = "Wobble", Key = "Arm_R", Axis = "Z", Deg = -25, Hz = 3 },
			{ Op = "Burst", Preset = "Snow", Count = 50, Speed = 6 },
		},
	},
	frost_glacier = {
		Walk = { { Op = "Emit", Preset = "Glints", Color = ICE, Rate = 6 } }, -- frost trail while sliding
		Show = {
			{ Op = "Bob", Key = "Pompom", Amp = 0.08, Hz = 3 },
			{ Op = "Burst", Preset = "Stars", Color = ICE, Count = 30, Speed = 9 },
		},
	},
	frost_penguin = {
		Walk = { { Op = "Emit", Preset = "Glints", Color = ICE, Rate = 6 } }, -- ice slide trail
		Show = {
			{ Op = "Burst", Preset = "Snow", Count = 30 },
			{ Op = "Burst", Preset = "Smoke", Color = { 230, 245, 255 }, Count = 10 },
		},
	},
	frost_aurora = {
		-- angel halos: glow, counter-rotate and bob above its head; holy beam + feathers + aurora sky on the catch
		Walk = {
			{ Op = "Spin", Key = "Halo_Green", Axis = "Y", Rpm = 25, Bob = 0.03, BobHz = 0.8 },
			{ Op = "Spin", Key = "Halo_Purple", Axis = "Y", Rpm = -40, Bob = 0.03, BobHz = 0.9 },
			{ Op = "Glow", Pattern = "^Halo_" },
			{ Op = "Light", Key = "Acc_AuroraHalo", Color = { 170, 255, 210 }, Range = 8, Brightness = 1.5, Pulse = 0.8 },
		},
		Show = {
			{ Op = "Spin", Key = "Halo_Green", Axis = "Y", Rpm = 90 },
			{ Op = "Spin", Key = "Halo_Purple", Axis = "Y", Rpm = -140 },
			{ Op = "Beam", Kind = "Holy", Color = { 255, 250, 225 } },
			{ Op = "Rain", Preset = "Feathers", Count = 30 },
			{ Op = "Beam", Kind = "Aurora" },
		},
	},
	frost_yeti = {
		Walk = { { Op = "Emit", Preset = "Smoke", Color = { 240, 248, 255 }, Rate = 2 } }, -- frost breath
		Land = { { Op = "Burst", Preset = "Snow", Count = 8 } },
		Show = { -- ground-pound
			{ Op = "RingPulse", Color = ICE, Count = 2 },
			{ Op = "Burst", Preset = "Snow", Count = 40, Speed = 7 },
			{ Op = "Shake", Time = 0.35 },
		},
	},
	frost_cryo = {
		Walk = { { Op = "GlowWave", Pattern = "^Spike_", Hz = 3 } },
		Show = {
			{ Op = "Glow", Pattern = "^Spike_" },
			{ Op = "Light", Key = "Acc_IceCrown", Color = ICE, Range = 16, Brightness = 5 },
			{ Op = "RingPulse", Color = ICE, Count = 2 },
			{ Op = "Edge", Color = { 235, 250, 255 }, Alpha = 0.1 }, -- frost creeps in from the edges
		},
	},

	-- ===== Candy Land =====
	candy_gumdrop = {
		Walk = { { Op = "Emit", Preset = "Glints", Key = "Acc_Sprinkles", Rate = 5 } },
		Show = { { Op = "Burst", Preset = "Confetti", Count = 50, Speed = 10 } },
	},
	candy_cupcake = {
		Walk = { { Op = "Bob", Key = "Cherry", Amp = 0.03, Hz = 2 }, { Op = "Bob", Key = "CherryStem", Amp = 0.03, Hz = 2 } },
		Show = {
			{ Op = "Bob", Key = "Cherry", Amp = 0.22, Hz = 1.2 },
			{ Op = "Bob", Key = "CherryStem", Amp = 0.22, Hz = 1.2 },
			{ Op = "Burst", Preset = "Confetti", Count = 40 },
		},
	},
	candy_bubblegum = {
		Walk = { { Op = "Pulse", Key = "Acc_GumBubble", Min = 0.7, Max = 1.2, Hz = 0.8 } }, -- blowing a bubble
		Show = { -- giant bubble pops into confetti
			{ Op = "Grow", Key = "Acc_GumBubble", From = 1, To = 2.4, Time = 0.45 },
			{ Op = "Hide", Key = "Acc_GumBubble", Delay = 0.45 },
			{ Op = "Burst", Preset = "Confetti", Color = { 255, 140, 200 }, Count = 50, Speed = 10, Delay = 0.45 },
		},
	},
	candy_cotton = {
		Walk = { { Op = "Emit", Preset = "Smoke", Color = { 255, 230, 245 }, Key = "Acc_CloudPuff", Rate = 4 } },
		Show = {
			{ Op = "Orbit", Preset = "Smoke", Color = { 255, 225, 245 }, Radius = 2.6, Hz = 1, Rate = 24 },
			{ Op = "Burst", Preset = "Icon", Tex = "rainbow", Count = 12 },
		},
	},
	candy_lollipop = {
		Walk = {
			{ Op = "Spin", Key = "LollipopSwirl_O", Axis = "Z", Rpm = 60 },
			{ Op = "Spin", Key = "LollipopSwirl_I", Axis = "Z", Rpm = 60 },
		},
		Show = {
			{ Op = "Spin", Key = "LollipopSwirl_O", Axis = "Z", Rpm = 240 },
			{ Op = "Spin", Key = "LollipopSwirl_I", Axis = "Z", Rpm = 240 },
			{ Op = "Rays", Tex = "sunburst", Color = { 255, 120, 190 }, Scale = 1.4, Spin = 3 },
			{ Op = "Rays", Tex = "sunburst", Color = { 255, 255, 255 }, Scale = 1.0, Spin = -4 },
		},
	},
	candy_royal = {
		Walk = { { Op = "GlowWave", Pattern = "^Gem_", Hz = 2 } },
		Show = { -- royal fanfare
			{ Op = "Rain", Preset = "Icon", Tex = "crown", Count = 20 },
			{ Op = "Burst", Preset = "Confetti", Color = GOLD, Count = 50 },
			{ Op = "Light", Key = "Acc_RoyalCrown", Color = GOLD, Range = 14, Brightness = 4 },
		},
	},

	-- ===== Desert Dunes =====
	desert_sand = {
		Walk = { { Op = "Emit", Preset = "Sand", Key = "HatBrim", Rate = 3 } },
		Show = {
			{ Op = "Wobble", Key = "Acc_SunHat", Axis = "X", Deg = 15, Hz = 1.5 }, -- hat tip
			{ Op = "Burst", Preset = "Sand", Count = 25 },
		},
	},
	desert_cactus = {
		Walk = {
			{ Op = "Wobble", Key = "ArmUp_L", Axis = "Z", Deg = 8, Hz = 1.2 },
			{ Op = "Wobble", Key = "ArmUp_R", Axis = "Z", Deg = -8, Hz = 1.2 },
			{ Op = "Grow", Key = "Node38", From = 0.4, To = 0.4, Time = 0 }, -- flower closed while walking
		},
		Show = { -- the flower blooms open
			{ Op = "Grow", Key = "Node38", From = 0.4, To = 1.35, Time = 0.5 },
			{ Op = "Burst", Preset = "Petals", Color = { 255, 120, 170 }, Count = 20 },
		},
	},
	desert_mummy = {
		Walk = { { Op = "Emit", Preset = "Dust", Rate = 3 } },
		Show = { { Op = "Orbit", Preset = "Smoke", Color = { 235, 225, 200 }, Radius = 2.2, Hz = 1.5, Rise = true, Rate = 30 } }, -- unwrap swirl
	},
	desert_scarab = {
		Walk = { { Op = "Emit", Preset = "Glints", Color = GOLD, Key = "Acc_ScarabEmblem", Rate = 4 } },
		Show = {
			{ Op = "Wobble", Key = "ScarabWing_L", Axis = "Z", Deg = 35, Hz = 4 },
			{ Op = "Wobble", Key = "ScarabWing_R", Axis = "Z", Deg = -35, Hz = 4 },
			{ Op = "Burst", Preset = "Glints", Color = GOLD, Count = 20 },
		},
	},
	desert_djinn = {
		Walk = { { Op = "Emit", Preset = "Smoke", Color = { 170, 110, 230 }, Rate = 6 } }, -- smoke tail
		Show = {
			{ Op = "Glow", Pattern = "^TurbanGem" },
			{ Op = "Orbit", Preset = "Smoke", Color = { 170, 110, 230 }, Radius = 2.5, Hz = 1.3, Rise = true, Rate = 30 },
			{ Op = "Burst", Preset = "Sparkle", Color = { 255, 120, 255 }, Count = 30 },
		},
	},
	desert_pharaoh = {
		Walk = { { Op = "GlowWave", Pattern = "^BrowGem", Hz = 1 } },
		Show = { -- a golden sun disc rises behind it
			{ Op = "Rays", Tex = "glow", Color = GOLD, Scale = 1.8, Spin = 0 },
			{ Op = "Rays", Tex = "sunburst", Color = GOLD, Scale = 2.0, Spin = 8 },
			{ Op = "Light", Key = "BrowGem", Color = GOLD, Range = 12, Brightness = 5 },
		},
	},

	-- ===== Acid Swamp =====
	acid_sludge = {
		Walk = { { Op = "Pulse", Key = "Acc_GooDrips", Min = 0.95, Max = 1.08, Hz = 1.5 } },
		Land = { { Op = "Burst", Preset = "Bubbles", Color = TOXIC, Count = 5 } }, -- puddle splats
		Show = {
			{ Op = "Burst", Preset = "Bubbles", Color = TOXIC, Count = 30, Speed = 7 },
			{ Op = "Burst", Preset = "Smoke", Color = { 120, 200, 90 }, Count = 12 },
		},
	},
	acid_bubbling = {
		Walk = {
			{ Op = "Bob", Key = "Bubble_0", Amp = 0.05, Hz = 1.2, Phase = 0 },
			{ Op = "Bob", Key = "Bubble_1", Amp = 0.05, Hz = 1.2, Phase = 1.2 },
			{ Op = "Bob", Key = "Bubble_2", Amp = 0.05, Hz = 1.2, Phase = 2.4 },
			{ Op = "Bob", Key = "Bubble_3", Amp = 0.05, Hz = 1.2, Phase = 3.6 },
			{ Op = "Bob", Key = "Bubble_4", Amp = 0.05, Hz = 1.2, Phase = 4.8 },
			{ Op = "Emit", Preset = "Bubbles", Color = TOXIC, Rate = 4 },
		},
		Show = { { Op = "Burst", Preset = "Bubbles", Color = TOXIC, Count = 45, Speed = 8 } },
	},
	acid_hazmat = {
		Walk = { { Op = "Emit", Preset = "Smoke", Color = { 140, 230, 110 }, Pattern = "^Filter_", Rate = 3 } },
		Show = {
			{ Op = "Sweep", Color = { 255, 220, 40 } }, -- hazard stripes
			{ Op = "Burst", Preset = "Smoke", Color = { 140, 230, 110 }, Count = 15 },
		},
	},
	acid_mutant = {
		Walk = {
			{ Op = "Wobble", Key = "Acc_EyeStalk", Axis = "Y", Deg = 35, Hz = 0.5 }, -- looking around
			{ Op = "Wobble", Key = "Acc_EyeStalk", Axis = "X", Deg = 10, Hz = 0.8 },
		},
		Show = {
			{ Op = "Glow", Pattern = "^StalkEye" },
			{ Op = "Flash", Color = TOXIC, Alpha = 0.5 },
			{ Op = "Flash", Color = TOXIC, Alpha = 0.6, Delay = 0.3 },
		},
	},
	acid_scientist = {
		Walk = { { Op = "Emit", Preset = "Bubbles", Color = TOXIC, Key = "TestTubeLiquid", Rate = 4 } },
		Show = {
			{ Op = "Glow", Pattern = "^GoggleLens" },
			{ Op = "Beam", Kind = "Arcs", Pattern = "^TestTube$", Color = { 150, 230, 255 } },
			{ Op = "Burst", Preset = "Sparkle", Color = { 150, 230, 255 }, Count = 20 },
		},
	},
	acid_nuclear = {
		Walk = {
			{ Op = "Spin", Key = "Orbit_0", Axis = "Y", Rpm = 60 },
			{ Op = "Spin", Key = "Orbit_1", Axis = "Y", Rpm = -80 },
			{ Op = "Spin", Key = "Orbit_2", Axis = "Y", Rpm = 100 },
			{ Op = "Light", Key = "Core", Color = TOXIC, Range = 10, Brightness = 2, Pulse = 2 },
		},
		Show = {
			{ Op = "Spin", Key = "Orbit_0", Axis = "Y", Rpm = 240 },
			{ Op = "Spin", Key = "Orbit_1", Axis = "Y", Rpm = -300 },
			{ Op = "Spin", Key = "Orbit_2", Axis = "Y", Rpm = 360 },
			{ Op = "RingPulse", Color = TOXIC, Count = 3 },
			{ Op = "Flash", Color = TOXIC, Alpha = 0.4 },
		},
	},
} :: { [string]: Layer }

return CatchFxData
