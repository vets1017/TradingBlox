local TestKit = require("./TestKit")
local PortfolioHistoryModule = require("../src/server/Modules/PortfolioHistoryModule")

local test, equal, near = TestKit.test, TestKit.equal, TestKit.near

local HOUR = 3600
local DAY = 86400
local T0 = 1_800_000_000 -- a multiple of 3600, so bucket edges are easy to see

test("record appends a point rounded to cents", function()
	equal(PortfolioHistoryModule.record({}, 100.456, T0), { { T0, 100.46 } })
end)

test("record leaves the passed history untouched", function()
	local history = { { T0, 1 } }

	PortfolioHistoryModule.record(history, 2, T0 + HOUR)
	equal(history, { { T0, 1 } })
end)

test("within the last day, the latest point in each 5-minute bucket wins", function()
	local history = PortfolioHistoryModule.record({}, 1, T0)

	history = PortfolioHistoryModule.record(history, 2, T0 + 100) -- same bucket
	equal(history, { { T0 + 100, 2 } })

	history = PortfolioHistoryModule.record(history, 3, T0 + 300) -- next bucket
	equal(history, { { T0 + 100, 2 }, { T0 + 300, 3 } })
end)

test("points older than a day thin out to one per hour", function()
	local history = { { T0, 1 }, { T0 + 600, 2 }, { T0 + HOUR, 3 } }

	equal(PortfolioHistoryModule.record(history, 4, T0 + 2 * DAY), {
		{ T0 + 600, 2 },
		{ T0 + HOUR, 3 },
		{ T0 + 2 * DAY, 4 },
	})
end)

test("points past 30 days are dropped", function()
	local history = { { T0, 1 }, { T0 + DAY, 2 } }

	equal(PortfolioHistoryModule.record(history, 3, T0 + 30 * DAY + 1), {
		{ T0 + DAY, 2 },
		{ T0 + 30 * DAY + 1, 3 },
	})
end)

test("a clock behind the last point never writes before it", function()
	equal(PortfolioHistoryModule.record({ { T0, 1 } }, 2, T0 - 5), { { T0, 2 } })
end)

test("getRange leads with the value the range started from", function()
	local history = { { T0, 10 }, { T0 + 2 * DAY, 20 }, { T0 + 3 * DAY, 30 } }

	equal(PortfolioHistoryModule.getRange(history, DAY, T0 + 3 * DAY + HOUR), {
		{ T0 + 2 * DAY + HOUR, 20 },
		{ T0 + 3 * DAY, 30 },
	})
end)

test("getRange downsamples long histories but keeps both ends", function()
	local history = {}

	for i = 0, 999 do
		table.insert(history, { T0 + i * 300, i })
	end

	local now = T0 + 999 * 300
	local points = PortfolioHistoryModule.getRange(history, 7 * DAY, now)

	-- The first point plus the last of each of 150 slices; the newest point
	-- sits on the far edge, in a slice of its own
	equal(#points <= 152, true, "point count " .. #points)
	equal(points[1], { T0, 0 })
	equal(points[#points], { now, 999 })

	for i = 2, #points do
		equal(points[i][1] > points[i - 1][1], true, "times increase")
	end
end)

test("getMaxDrawdown is the largest fall from a high", function()
	equal(PortfolioHistoryModule.getMaxDrawdown({ { 1, 100 } }), nil)
	equal(PortfolioHistoryModule.getMaxDrawdown({ { 1, 100 }, { 2, 110 } }), 0)
	near(
		PortfolioHistoryModule.getMaxDrawdown({ { 1, 100 }, { 2, 150 }, { 3, 90 }, { 4, 120 }, { 5, 80 } }),
		0.4667,
		1e-4
	)
end)

return nil
