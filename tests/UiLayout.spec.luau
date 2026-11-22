--!strict
--[[
	tests/UiLayout.spec.luau
	Unit tests for the pure UI layout rules (stroke thickness, phone scale, toast kinds, counter timing).
]]

local UiLayout = require("../src/ReplicatedStorage/Shared/UiLayout")

return function(t: any)
	local describe = t.describe
	local it = t.it
	local expect = t.expect

	describe("UiLayout - text stroke", function()
		it("follows round(TextSize * 0.085) in half pixels (spec 1c)", function()
			expect(UiLayout.StrokeThickness(24)).toBe(2)
			expect(UiLayout.StrokeThickness(42)).toBe(3.5)
			expect(UiLayout.StrokeThickness(88)).toBe(5)
		end)
		it("never goes below 1 px", function()
			expect(UiLayout.StrokeThickness(8)).toBe(1)
		end)
	end)

	describe("UiLayout - root scale", function()
		it("phone: 844x390 gives about 0.68", function()
			expect(UiLayout.RootScale(844, 390, true)).toBeNear(0.68, 0.01)
		end)
		it("phone: clamps between 0.6 and 0.8", function()
			expect(UiLayout.RootScale(500, 200, true)).toBe(0.6)
			expect(UiLayout.RootScale(2000, 1200, true)).toBe(0.8)
		end)
		it("PC: 1366x768 is exactly 1", function()
			expect(UiLayout.RootScale(1366, 768, false)).toBe(1)
		end)
		it("PC: clamps between 0.68 and 1.18", function()
			expect(UiLayout.RootScale(400, 300, false)).toBe(0.68)
			expect(UiLayout.RootScale(5000, 3000, false)).toBe(1.18)
		end)
		it("is a phone only when touch is on and there is no keyboard", function()
			expect(UiLayout.IsPhone(true, false)).toBe(true)
			expect(UiLayout.IsPhone(true, true)).toBe(false)
			expect(UiLayout.IsPhone(false, true)).toBe(false)
		end)
	end)

	describe("UiLayout - toast kinds", function()
		it("maps the six ToastNotify kinds", function()
			expect(UiLayout.ToastKey("cash")).toBe("cash")
			expect(UiLayout.ToastKey("power")).toBe("power")
			expect(UiLayout.ToastKey("gems")).toBe("gems")
			expect(UiLayout.ToastKey("warn")).toBe("red")
			expect(UiLayout.ToastKey("success")).toBe("gold")
			expect(UiLayout.ToastKey("info")).toBe("gold")
		end)
		it("falls back to gold for unknown or missing kinds", function()
			expect(UiLayout.ToastKey(nil)).toBe("gold")
			expect(UiLayout.ToastKey("mystery")).toBe("gold")
		end)
	end)

	describe("UiLayout - counter", function()
		it("tweens for 0.4 s and snaps for tiny changes", function()
			expect(UiLayout.CounterDuration(0, 500)).toBe(0.4)
			expect(UiLayout.CounterDuration(10, 10)).toBe(0)
			expect(UiLayout.CounterDuration(10, 10.4)).toBe(0)
		end)
		it("the hotbar always has 5 slots", function()
			expect(UiLayout.HotbarSlots).toBe(5)
		end)
	end)

	describe("UiLayout - shop button state", function()
		it("owned, maxed and claimed rows are locked", function()
			expect(UiLayout.ShopButtonState("Owned", true)).toBe("locked")
			expect(UiLayout.ShopButtonState("Maxed", false)).toBe("locked")
			expect(UiLayout.ShopButtonState("Claimed", true)).toBe("locked")
		end)
		it("an option the player cannot pay for is unaffordable", function()
			expect(UiLayout.ShopButtonState("Unaffordable", false)).toBe("unaffordable")
			expect(UiLayout.ShopButtonState("Available", false)).toBe("unaffordable")
		end)
		it("otherwise it is available", function()
			expect(UiLayout.ShopButtonState("Available", true)).toBe("available")
		end)
	end)

	describe("UiLayout - index chance and backpack sort", function()
		it("chance is the weight share rounded to a percent", function()
			expect(UiLayout.ChancePercent(65, 100)).toBe(65)
			expect(UiLayout.ChancePercent(1, 3)).toBe(33)
			expect(UiLayout.ChancePercent(5, 0)).toBe(0)
		end)
		local items = {
			{ Income = 5, Rank = 1, Index = 1 },
			{ Income = 50, Rank = 2, Index = 2 },
			{ Income = 20, Rank = 3, Index = 3 },
		}
		it("sorts by income, rarity and newest", function()
			local byIncome = UiLayout.SortedIndexes(items, "Income")
			expect(byIncome[1]).toBe(2)
			expect(byIncome[3]).toBe(1)
			local byRarity = UiLayout.SortedIndexes(items, "Rarity")
			expect(byRarity[1]).toBe(3)
			local newest = UiLayout.SortedIndexes(items, "Newest")
			expect(newest[1]).toBe(3)
			expect(newest[3]).toBe(1)
		end)
	end)

	describe("UiLayout - session rate", function()
		it("averages per second and ignores the first second", function()
			expect(UiLayout.PerSecond(100, 10)).toBe(10)
			expect(UiLayout.PerSecond(100, 0.5)).toBe(0)
		end)
	end)
end
