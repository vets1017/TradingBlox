local MarketHoursModule = {}

local holidayCache = {}

-- Returns the day-of-month for the nth occurrence of a weekday in a month.
-- weekday follows os.date wday conention: 1 = Sunday ... 7 = Saturday
local function nthWeekdayOfMonth(year, month, weekday, n)
	local firstOfMonth = os.time({ year = year, month = month, day = 1, hour = 12 })
	local firstWday = os.date("!*t", firstOfMonth).wday

	local offset = (weekday - firstWday) % 7
	local day = 1 + offset + (n - 1) * 7

	return day
end

-- Returns the day-of-month for the last occurrence of a weekday in a month.
local function lastWeekdayOfMonth(year, month, weekday)
	local daysInMonth = os.date("!*t", os.time({ year = year, month = month + 1, day = 0, hour = 12 })).day
	local lastDay = os.time({ year = year, month = month, day = daysInMonth, hour = 12 })
	local lastWday = os.date("!*t", lastDay).wday

	local offset = (lastWday - weekday) % 7

	return daysInMonth - offset
end

-- Gregorian algorithm for Easter Sunday
local function getGoodFridayTime(year)
	local a = year % 19
	local b = math.floor(year / 100)
	local c = year % 100
	local d = math.floor(b / 4)
	local e = b % 4
	local f = math.floor((b + 8) / 25)
	local g = math.floor((b - f + 1) / 3)
	local h = (19 * a + b - d - g + 15) % 30
	local i = math.floor(c / 4)
	local k = c % 4
	local l = (32 + 2 * e + 2 * i - h - k) % 7
	local m = math.floor((a + 11 * h + 22 * l) / 451)
	local month = math.floor((h + 1 - 7 * m + 114) / 31)
	local day = ((h + 1 - 7 * m + 114) % 31) + 1

	return os.time({ year = year, month = month, day = day - 2, hour = 12 })
end

local function getHolidaysForYear(year)
	if holidayCache[year] then
		return holidayCache[year]
	end

	local goodFridayDate = os.date("!*t", getGoodFridayTime(year))

	local holidays = {
		["01-01"] = true, -- New Year's Day
		["06-19"] = true, -- Juneteenth
		["07-04"] = true, -- Independence Day
		["12-25"] = true, --Christmas

		[string.format("01-%02d", nthWeekdayOfMonth(year, 1, 2, 3))] = true, -- MLK Day
		[string.format("02-%02d", nthWeekdayOfMonth(year, 2, 2, 3))] = true, -- Presidents' Day
		[string.format("05-%02d", lastWeekdayOfMonth(year, 5, 2))] = true, -- Memorial Day
		[string.format("09-%02d", nthWeekdayOfMonth(year, 9, 2, 1))] = true, -- Labor Day
		[string.format("11-%02d", nthWeekdayOfMonth(year, 11, 5, 4))] = true, -- Thanksgiving
		[string.format("%02d-%02d", goodFridayDate.month, goodFridayDate.day)] = true, -- Good Friday
	}

	holidayCache[year] = holidays
	return holidays
end

-- Public: true if given unix time falls on a weekend of NYSE holiday
function MarketHoursModule.isMarketClosed(currentTime)
	local date = os.date("!*t", currentTime)

	if date.wday == 1 or date.wday == 7 then
		return true
	end

	local yearHolidays = getHolidaysForYear(date.year)
	local dateString = string.format("%02d-%02d", date.month, date.day)

	if yearHolidays[dateString] then
		return true
	end

	return false
end

-- Public: given unix time returns:
--      isOpen (bool), targetTime (unix time of next close if open, else next open)
function MarketHoursModule.getMarketStatus(currentTime)
	local currentUTC = os.date("!*t", currentTime)

	local marketOpen = os.time({
		year = currentUTC.year,
		month = currentUTC.month,
		day = currentUTC.day,
		hour = 13,
		minute = 30,
		second = 0,
	})

	local marketClose = os.time({
		year = currentUTC.year,
		month = currentUTC.month,
		day = currentUTC.day,
		hour = 20,
		minute = 0,
		second = 0,
	})

	if
		not MarketHoursModule.isMarketClosed(currentTime)
		and currentTime >= marketOpen
		and currentTime < marketClose
	then
		return true, marketClose
	end

	local targetTime = marketOpen

	if currentTime >= marketOpen or MarketHoursModule.isMarketClosed(currentTime) then
		targetTime = targetTime + 86400
	end

	while MarketHoursModule.isMarketClosed(targetTime) do
		targetTime = targetTime + 86400
	end

	return false, targetTime
end

-- Public: compact countdown for the status bar - "2d 17h", "3h 12m" or
-- "12m 30s" depending on how far away the target is. Never negative.
function MarketHoursModule.formatCountdown(seconds)
	seconds = math.max(0, math.floor(seconds))

	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if days >= 1 then
		return string.format("%dd %dh", days, hours)
	elseif hours >= 1 then
		return string.format("%dh %dm", hours, minutes)
	end

	return string.format("%dm %ds", minutes, seconds % 60)
end

return MarketHoursModule
