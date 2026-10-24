-- MarketHoursModule.luau
--
-- NYSE regular session (9:30-16:00 New York time) for a unix time:
-- weekends, the exchange's holidays with their weekend observance, the
-- 13:00 early closes, and daylight saving time. Everything is computed from
-- UTC timestamps (Luau's os.time reads a date table as UTC), so the answer
-- doesn't depend on the server's or the player's own time zone.

local MarketHoursModule = {}

local DAY = 86400
local OPEN_MINUTES = 9 * 60 + 30
local CLOSE_MINUTES = 16 * 60
local EARLY_CLOSE_MINUTES = 13 * 60
local EDT_OFFSET = 4 * 3600 -- hours New York is behind UTC in summer
local EST_OFFSET = 5 * 3600
local MAX_DAYS_TO_NEXT_OPEN = 14

local calendarCache = {} -- [year] = { holidays = { ["MM-DD"] = true }, earlyCloses = { ["MM-DD"] = true } }

-- os.time only reads `min`/`sec`; `minute`/`second` keys are silently ignored
local function utcTime(year, month, day, hour, min)
	return os.time({ year = year, month = month, day = day, hour = hour or 0, min = min or 0, sec = 0 })
end

local function getWeekday(year, month, day)
	return os.date("!*t", utcTime(year, month, day, 12)).wday -- 1 = Sunday ... 7 = Saturday
end

local function dateKey(month, day)
	return string.format("%02d-%02d", month, day)
end

-- Day of the month of the nth `weekday` (1 = Sunday ... 7 = Saturday)
local function nthWeekdayOfMonth(year, month, weekday, n)
	local offset = (weekday - getWeekday(year, month, 1)) % 7

	return 1 + offset + (n - 1) * 7
end

local function lastWeekdayOfMonth(year, month, weekday)
	local daysInMonth = os.date("!*t", utcTime(year, month + 1, 0, 12)).day
	local offset = (getWeekday(year, month, daysInMonth) - weekday) % 7

	return daysInMonth - offset
end

-- Easter Sunday (Anonymous Gregorian algorithm)
local function getEaster(year)
	local a = year % 19
	local b = year // 100
	local c = year % 100
	local d = b // 4
	local e = b % 4
	local f = (b + 8) // 25
	local g = (b - f + 1) // 3
	local h = (19 * a + b - d - g + 15) % 30
	local i = c // 4
	local k = c % 4
	local l = (32 + 2 * e + 2 * i - h - k) % 7
	local m = (a + 11 * h + 22 * l) // 451
	local monthAndDay = h + l - 7 * m + 114

	return monthAndDay // 31, (monthAndDay % 31) + 1
end

-- A fixed-date holiday on a Saturday is observed the Friday before and one
-- on a Sunday the Monday after. New Year's Day on a Saturday isn't moved
-- into the previous year (NYSE rule), so that year has no observed day.
local function addObservedHoliday(holidays, year, month, day)
	local weekday = getWeekday(year, month, day)
	local time = utcTime(year, month, day, 12)

	if weekday == 7 then
		if month == 1 and day == 1 then
			return
		end

		time -= DAY
	elseif weekday == 1 then
		time += DAY
	end

	local observed = os.date("!*t", time)
	holidays[dateKey(observed.month, observed.day)] = true
end

local function getCalendar(year)
	if calendarCache[year] then
		return calendarCache[year]
	end

	local holidays = {}
	local earlyCloses = {}

	addObservedHoliday(holidays, year, 1, 1) -- New Year's Day
	addObservedHoliday(holidays, year, 6, 19) -- Juneteenth
	addObservedHoliday(holidays, year, 7, 4) -- Independence Day
	addObservedHoliday(holidays, year, 12, 25) -- Christmas

	holidays[dateKey(1, nthWeekdayOfMonth(year, 1, 2, 3))] = true -- MLK Day
	holidays[dateKey(2, nthWeekdayOfMonth(year, 2, 2, 3))] = true -- Presidents' Day
	holidays[dateKey(5, lastWeekdayOfMonth(year, 5, 2))] = true -- Memorial Day
	holidays[dateKey(9, nthWeekdayOfMonth(year, 9, 2, 1))] = true -- Labor Day

	local thanksgiving = nthWeekdayOfMonth(year, 11, 5, 4)
	holidays[dateKey(11, thanksgiving)] = true

	local easterMonth, easterDay = getEaster(year)
	local goodFriday = os.date("!*t", utcTime(year, easterMonth, easterDay, 12) - 2 * DAY)
	holidays[dateKey(goodFriday.month, goodFriday.day)] = true

	-- 13:00 closes: the day after Thanksgiving, and July 3 / December 24
	-- when they fall Monday-Thursday (on a Friday they're the observed holiday)
	earlyCloses[dateKey(11, thanksgiving + 1)] = true

	for _, date in ipairs({ { 7, 3 }, { 12, 24 } }) do
		local weekday = getWeekday(year, date[1], date[2])

		if weekday >= 2 and weekday <= 5 then
			earlyCloses[dateKey(date[1], date[2])] = true
		end
	end

	calendarCache[year] = { holidays = holidays, earlyCloses = earlyCloses }

	return calendarCache[year]
end

-- US daylight saving: second Sunday of March through the day before the
-- first Sunday of November. Changes happen at 2:00 on a Sunday, when the
-- market is closed, so the calendar date decides it.
local function isDaylightSaving(year, month, day)
	if month < 3 or month > 11 then
		return false
	elseif month > 3 and month < 11 then
		return true
	elseif month == 3 then
		return day >= nthWeekdayOfMonth(year, 3, 1, 2)
	end

	return day < nthWeekdayOfMonth(year, 11, 1, 1)
end

-- The New York calendar date at a unix time
local function getNewYorkDate(currentTime)
	local date = os.date("!*t", currentTime - EST_OFFSET)

	if isDaylightSaving(date.year, date.month, date.day) then
		date = os.date("!*t", currentTime - EDT_OFFSET)
	end

	return date
end

-- Open and close of the session on a New York date as unix times, or nil
-- when there's no session that day
local function getSession(year, month, day)
	local weekday = getWeekday(year, month, day)

	if weekday == 1 or weekday == 7 then
		return nil
	end

	local calendar = getCalendar(year)
	local key = dateKey(month, day)

	if calendar.holidays[key] then
		return nil
	end

	local offset = isDaylightSaving(year, month, day) and EDT_OFFSET or EST_OFFSET
	local midnight = utcTime(year, month, day) + offset
	local closeMinutes = calendar.earlyCloses[key] and EARLY_CLOSE_MINUTES or CLOSE_MINUTES

	return midnight + OPEN_MINUTES * 60, midnight + closeMinutes * 60
end

-- Public: true if the New York date at a unix time is a weekend or NYSE holiday
function MarketHoursModule.isMarketClosed(currentTime)
	local date = getNewYorkDate(currentTime)

	return getSession(date.year, date.month, date.day) == nil
end

-- Public: given unix time returns:
--      isOpen (bool), targetTime (unix time of next close if open, else next open)
function MarketHoursModule.getMarketStatus(currentTime)
	local today = getNewYorkDate(currentTime)
	local openTime, closeTime = getSession(today.year, today.month, today.day)

	if openTime and currentTime >= openTime and currentTime < closeTime then
		return true, closeTime
	end

	if openTime and currentTime < openTime then
		return false, openTime
	end

	local noon = utcTime(today.year, today.month, today.day, 12)

	for daysAhead = 1, MAX_DAYS_TO_NEXT_OPEN do
		local date = os.date("!*t", noon + daysAhead * DAY)
		local nextOpen = getSession(date.year, date.month, date.day)

		if nextOpen then
			return false, nextOpen
		end
	end

	error("[MarketHoursModule] No session within " .. MAX_DAYS_TO_NEXT_OPEN .. " days of " .. currentTime)
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
