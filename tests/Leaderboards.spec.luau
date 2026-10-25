local TestKit = require("./TestKit")
local Leaderboards = require("../src/shared/Config/Leaderboards")

local test, equal, utc = TestKit.test, TestKit.equal, TestKit.utc

local netWorthBoard = Leaderboards.getBoard("NetWorth")
local weeklyBoard = Leaderboards.getBoard("WeeklyReturn")

test("getBoard finds boards by id", function()
	equal(netWorthBoard.period, "AllTime")
	equal(weeklyBoard.metric, "return")
	equal(Leaderboards.getBoard("Nope"), nil)
end)

test("every board's period has a minimum trade count", function()
	for _, board in ipairs(Leaderboards.BOARDS) do
		equal(type(Leaderboards.MIN_TRADES[board.period]), "number", board.id)
	end
end)

test("weeks run Monday 00:00 to Sunday 23:59 UTC", function()
	local monday = Leaderboards.getPeriodKey("Week", utc(2026, 10, 19))

	equal(monday, "W2963")
	equal(Leaderboards.getPeriodKey("Week", utc(2026, 10, 25, 23, 59, 59)), monday)
	equal(Leaderboards.getPeriodKey("Week", utc(2026, 10, 26)), "W2964")
end)

test("month and all-time keys", function()
	equal(Leaderboards.getPeriodKey("Month", utc(2026, 10, 31, 23, 59, 59)), "2026-10")
	equal(Leaderboards.getPeriodKey("Month", utc(2026, 11, 1)), "2026-11")
	equal(Leaderboards.getPeriodKey("AllTime", utc(2026, 10, 25)), "all")
end)

test("period labels", function()
	equal(Leaderboards.getPeriodLabel("Week", utc(2026, 10, 25, 12)), "Week of Oct 19")
	equal(Leaderboards.getPeriodLabel("Month", utc(2026, 10, 25)), "October 2026")
	equal(Leaderboards.getPeriodLabel("AllTime", utc(2026, 10, 25)), "All time")
end)

test("scores are stored as cents or basis points and round-trip", function()
	equal(Leaderboards.encodeScore(netWorthBoard, 50000.126), 5000013)
	equal(Leaderboards.decodeScore(netWorthBoard, 5000013), 50000.13)
	equal(Leaderboards.encodeScore(weeklyBoard, 0.1234), 1234)
	equal(Leaderboards.encodeScore(weeklyBoard, -0.05), -500)
	equal(Leaderboards.decodeScore(weeklyBoard, 1234), 0.1234)
end)

return nil
