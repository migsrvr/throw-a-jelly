--!strict
--[[
	UiLayout.luau
	Pure number/string rules from docs/docs/UI-MOCKUP-SPEC.md section 0 and 1c. No Roblox types, so
	Lune can unit-test it (tests/UiLayout.spec.luau). UiKit and HudController call these.
]]

local UiLayout = {}

export type ToastKey = "cash" | "power" | "gems" | "gold" | "red"

-- Phone design space: 844x390 viewport at scale 0.68 is about 1241x574 (spec section 0).
local PHONE_DESIGN_HEIGHT = 574
local PC_DESIGN_WIDTH = 1366
local PC_DESIGN_HEIGHT = 768

-- Text outline A: Thickness = round(TextSize * 0.085) in half pixels, capped at 5 so the huge numbers
-- stay clean (24 -> 2, 42 -> 3.5, 88 -> 5, as listed in the spec).
function UiLayout.StrokeThickness(textSize: number): number
	local raw = textSize * 0.085
	return math.clamp(math.floor(raw * 2 + 0.5) / 2, 1, 5)
end

function UiLayout.IsPhone(touchEnabled: boolean, keyboardEnabled: boolean): boolean
	return touchEnabled and not keyboardEnabled
end

-- Root UIScale. Phone: viewport.Y / 574 clamped 0.6-0.8. PC: fit 1366x768 clamped 0.68-1.18.
function UiLayout.RootScale(viewportX: number, viewportY: number, isPhone: boolean): number
	if isPhone then
		return math.clamp(viewportY / PHONE_DESIGN_HEIGHT, 0.6, 0.8)
	end
	local raw = math.min(viewportX / PC_DESIGN_WIDTH, viewportY / PC_DESIGN_HEIGHT)
	return math.clamp(raw, 0.68, 1.18)
end

-- Toast kinds from ToastNotify. `success` and `info` share Gold (spec section 2).
function UiLayout.ToastKey(kind: string?): ToastKey
	if kind == "cash" then
		return "cash"
	elseif kind == "power" then
		return "power"
	elseif kind == "gems" then
		return "gems"
	elseif kind == "warn" then
		return "red"
	end
	return "gold"
end

-- Cash counter tween: 0.4 s (UI-MOTION.md allows up to 0.8 s). A change under 1 snaps with no tween.
function UiLayout.CounterDuration(oldValue: number, newValue: number): number
	if math.abs(newValue - oldValue) < 1 then
		return 0
	end
	return 0.4
end

-- Shop button state (spec section 8): Owned / Maxed / Claimed rows are "locked" (grey, "Permanent"),
-- an option the player cannot pay for is "unaffordable" (0.4 transparency, "Need N more"), else "available".
export type ButtonState = "available" | "unaffordable" | "locked"

function UiLayout.ShopButtonState(entryState: string, canAfford: boolean): ButtonState
	if entryState == "Owned" or entryState == "Maxed" or entryState == "Claimed" then
		return "locked"
	end
	if not canAfford then
		return "unaffordable"
	end
	return "available"
end

-- Number of slots the hotbar always shows, so the bar does not jump.
UiLayout.HotbarSlots = 5

return UiLayout
