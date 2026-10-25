local TestKit = require("./TestKit")
local MarketHoursModule = require("../src/shared/Modules/Multi/MarketHoursModule")

local test, equal, utc = TestKit.test, TestKit.equal, TestKit.utc

local function expectOpen(time, closesAt)
	local isOpen, target = MarketHoursModule.getMarketStatus(time)

	equal(isOpen, true, "open at " .. os.date("!%Y-%m-%d %H:%M", time))
	equal(target, closesAt, "close time")
end

local function expectClosed(time, opensAt)
	local isOpen, target = MarketHoursModule.getMarketStatus(time)

	equal(isOpen, false, "closed at " .. os.date("!%Y-%m-%d %H:%M", time))
	equal(target, opensAt, "next open")
end

test("date tables are read as UTC, as in Roblox", function()
	equal(utc(2026, 10, 26, 14, 0), 1793023200)
end)

test("open mid-session in daylight time, closing at 16:00 EDT", function()
	expectOpen(utc(2026, 10, 26, 14, 0), utc(2026, 10, 26, 20, 0))
end)

test("closed before the open, opening at 9:30 EDT", function()
	expectClosed(utc(2026, 10, 26, 13, 0), utc(2026, 10, 26, 13, 30))
end)

test("the closing second is closed; the next open is the next morning", function()
	expectClosed(utc(2026, 10, 26, 20, 0), utc(2026, 10, 27, 13, 30))
end)

test("a weekend points at Monday's open", function()
	expectClosed(utc(2026, 10, 24, 15, 0), utc(2026, 10, 26, 13, 30))
	equal(MarketHoursModule.isMarketClosed(utc(2026, 10, 24, 15, 0)), true)
	equal(MarketHoursModule.isMarketClosed(utc(2026, 10, 26, 15, 0)), false)
end)

test("standard time puts the session an hour later in UTC", function()
	expectClosed(utc(2026, 12, 1, 14, 0), utc(2026, 12, 1, 14, 30))
	expectOpen(utc(2026, 12, 1, 14, 30), utc(2026, 12, 1, 21, 0))
end)

test("daylight saving starts the second Sunday of March", function()
	expectClosed(utc(2026, 3, 6, 14, 0), utc(2026, 3, 6, 14, 30)) -- Friday, still EST
	expectOpen(utc(2026, 3, 9, 13, 30), utc(2026, 3, 9, 20, 0)) -- Monday, EDT
end)

test("daylight saving ends the first Sunday of November", function()
	-- Friday 2026-10-30 closes at 16:00 EDT; Monday 2026-11-02 opens at 9:30 EST
	expectClosed(utc(2026, 10, 30, 20, 0), utc(2026, 11, 2, 14, 30))
end)

test("NYSE holidays are closed", function()
	local holidays = {
		{ 2026, 1, 1 }, -- New Year's Day
		{ 2026, 1, 19 }, -- Martin Luther King Jr. Day
		{ 2026, 2, 16 }, -- Presidents' Day
		{ 2026, 4, 3 }, -- Good Friday
		{ 2026, 5, 25 }, -- Memorial Day
		{ 2026, 6, 19 }, -- Juneteenth
		{ 2026, 7, 3 }, -- Independence Day, observed (July 4 is a Saturday)
		{ 2026, 9, 7 }, -- Labor Day
		{ 2026, 11, 26 }, -- Thanksgiving
		{ 2026, 12, 25 }, -- Christmas
	}

	for _, date in ipairs(holidays) do
		local label = string.format("%d-%02d-%02d", date[1], date[2], date[3])

		equal(MarketHoursModule.isMarketClosed(utc(date[1], date[2], date[3], 15, 0)), true, label)
	end
end)

test("Good Friday follows Easter", function()
	equal(MarketHoursModule.isMarketClosed(utc(2025, 4, 18, 15, 0)), true, "2025")
	equal(MarketHoursModule.isMarketClosed(utc(2027, 3, 26, 15, 0)), true, "2027")
	equal(MarketHoursModule.isMarketClosed(utc(2026, 4, 2, 15, 0)), false, "the Thursday before")
end)

test("a Saturday holiday moves to Friday, except New Year's Day", function()
	equal(MarketHoursModule.isMarketClosed(utc(2027, 12, 24, 15, 0)), true, "Christmas 2027")
	equal(MarketHoursModule.isMarketClosed(utc(2021, 12, 31, 15, 0)), false, "New Year's Eve 2021")
end)

test("early closes at 13:00", function()
	expectOpen(utc(2026, 11, 27, 15, 0), utc(2026, 11, 27, 18, 0)) -- day after Thanksgiving
	expectOpen(utc(2026, 12, 24, 15, 0), utc(2026, 12, 24, 18, 0)) -- Christmas Eve, a Thursday
	expectClosed(utc(2026, 12, 24, 18, 0), utc(2026, 12, 28, 14, 30)) -- next open skips Christmas and the weekend
end)

test("formatCountdown picks units by distance and never goes negative", function()
	equal(MarketHoursModule.formatCountdown(0), "0m 0s")
	equal(MarketHoursModule.formatCountdown(-5), "0m 0s")
	equal(MarketHoursModule.formatCountdown(90.9), "1m 30s")
	equal(MarketHoursModule.formatCountdown(3 * 3600 + 12 * 60 + 5), "3h 12m")
	equal(MarketHoursModule.formatCountdown(2 * 86400 + 17 * 3600 + 59), "2d 17h")
end)

return nil
