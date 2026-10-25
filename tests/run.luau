-- run.luau
--
-- Runs every tests/*.spec.luau and exits non-zero if any test failed.
-- From the repository root: `lune run tests/run.luau`
--
-- Specs require game modules by relative path, so only modules that don't
-- touch Roblox services (game:GetService, Instance, ...) can be tested here.

local fs = require("@lune/fs")
local process = require("@lune/process")

local TestKit = require("./TestKit")

local TESTS_DIR = "tests"

if not fs.isDir(TESTS_DIR) then
	error("Run this from the repository root: lune run tests/run.luau")
end

local specs = {}

for _, fileName in ipairs(fs.readDir(TESTS_DIR)) do
	local specName = string.match(fileName, "^(.+%.spec)%.luau$")

	if specName then
		table.insert(specs, specName)
	end
end

table.sort(specs)

for _, specName in ipairs(specs) do
	local before = TestKit.results.passed + #TestKit.results.failures

	TestKit.setSpec(specName)

	local ok, err = pcall(require, "./" .. specName)

	if not ok then
		table.insert(TestKit.results.failures, { spec = specName, name = "(loading the spec)", err = tostring(err) })
	end

	print(string.format("%-28s %d tests", specName, TestKit.results.passed + #TestKit.results.failures - before))
end

local failures = TestKit.results.failures

for _, failure in ipairs(failures) do
	print(string.format("\nFAIL %s > %s\n  %s", failure.spec, failure.name, failure.err))
end

print(string.format("\n%d passed, %d failed", TestKit.results.passed, #failures))

process.exit(#failures > 0 and 1 or 0)
