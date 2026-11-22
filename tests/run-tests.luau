--!strict
--[[
	tests/run-tests.luau
	Lightweight Lune unit-test runner for ThrowPhysics and ProgressionLogic.
	Run with:
		lune run tests/run-tests
]]

local process = require("@lune/process")

local totalSuites = 0
local totalTests = 0
local passedTests = 0
local failedTests = 0
local failures: { string } = {}
local currentSuite = ""

local function describe(suiteName: string, fn: () -> ())
	totalSuites += 1
	currentSuite = suiteName
	print(`\n=== {suiteName} ===`)
	fn()
end

local function it(testName: string, fn: () -> ())
	totalTests += 1
	local ok, err = pcall(fn)
	if ok then
		passedTests += 1
		print(`  [PASS] {testName}`)
	else
		failedTests += 1
		local msg = `{currentSuite} > {testName}: {tostring(err)}`
		table.insert(failures, msg)
		print(`  [FAIL] {testName}\n         {tostring(err)}`)
	end
end

local function expect(actual: any)
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				error(`Expected {tostring(expected)}, got {tostring(actual)}`, 2)
			end
		end,
		toBeTruthy = function()
			if not actual then
				error(`Expected truthy value, got {tostring(actual)}`, 2)
			end
		end,
		toBeFalsy = function()
			if actual then
				error(`Expected falsy value, got {tostring(actual)}`, 2)
			end
		end,
		toBeGreaterThan = function(bound: number)
			if type(actual) ~= "number" or not (actual > bound) then
				error(`Expected {tostring(actual)} > {tostring(bound)}`, 2)
			end
		end,
		toBeGreaterThanOrEqual = function(bound: number)
			if type(actual) ~= "number" or not (actual >= bound) then
				error(`Expected {tostring(actual)} >= {tostring(bound)}`, 2)
			end
		end,
		toBeLessThanOrEqual = function(bound: number)
			if type(actual) ~= "number" or not (actual <= bound) then
				error(`Expected {tostring(actual)} <= {tostring(bound)}`, 2)
			end
		end,
		toBeNear = function(expected: number, tolerance: number?)
			local tol = tolerance or 1e-3
			if type(actual) ~= "number" or math.abs(actual - expected) > tol then
				error(`Expected {tostring(actual)} to be within {tol} of {expected}`, 2)
			end
		end,
	}
end

local harness = {
	describe = describe,
	it = it,
	expect = expect,
}

require("./ThrowPhysics.spec")(harness)
require("./ProgressionLogic.spec")(harness)
require("./PullUpMotion.spec")(harness)
require("./Gems.spec")(harness)
require("./Quests.spec")(harness)
require("./ProfileSerializer.spec")(harness)
require("./UiLayout.spec")(harness)
require("./Offline.spec")(harness)

print("\n----------------------------------------")
print(`Suites: {totalSuites} | Tests: {totalTests} | Passed: {passedTests} | Failed: {failedTests}`)
print("----------------------------------------")

if failedTests > 0 then
	for _, f in failures do
		print(`  * {f}`)
	end
	process.exit(1)
end
