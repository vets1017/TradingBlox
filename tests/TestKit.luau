-- TestKit.luau
--
-- The few assertions the specs need. Each `test` runs straight away and
-- records a pass or failure; run.luau prints the failures and sets the exit
-- code. Assertions raise at level 2 so a failure points at the spec's line.

local TestKit = {}

TestKit.results = { passed = 0, failures = {} }

local currentSpec = "?"

local function show(value)
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) ~= "table" then
		return tostring(value)
	end

	local keys = {}

	for key in pairs(value) do
		table.insert(keys, key)
	end

	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local parts = {}

	for _, key in ipairs(keys) do
		table.insert(parts, string.format("[%s] = %s", show(key), show(value[key])))
	end

	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function deepEqual(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end

	for key, value in pairs(a) do
		if not deepEqual(value, b[key]) then
			return false
		end
	end

	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end

	return true
end

local function fail(label, message)
	error((label and label .. ": " or "") .. message, 3)
end

function TestKit.setSpec(name: string)
	currentSpec = name
end

function TestKit.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)

	if ok then
		TestKit.results.passed += 1
	else
		table.insert(TestKit.results.failures, { spec = currentSpec, name = name, err = tostring(err) })
	end
end

function TestKit.equal(actual, expected, label: string?)
	if not deepEqual(actual, expected) then
		fail(label, string.format("expected %s, got %s", show(expected), show(actual)))
	end
end

function TestKit.near(actual: number, expected: number, tolerance: number, label: string?)
	if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
		fail(label, string.format("expected %s ± %s, got %s", show(expected), show(tolerance), show(actual)))
	end
end

function TestKit.errors(fn: () -> (), label: string?)
	if pcall(fn) then
		fail(label, "expected an error, but none was raised")
	end
end

-- A unix time from a UTC calendar date. Luau's os.time reads a date table
-- as UTC, in Roblox and in Lune alike (MarketHours.spec checks this).
function TestKit.utc(year: number, month: number, day: number, hour: number?, min: number?, sec: number?): number
	return os.time({ year = year, month = month, day = day, hour = hour or 0, min = min or 0, sec = sec or 0 })
end

return TestKit
