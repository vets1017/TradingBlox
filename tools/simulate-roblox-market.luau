-- simulate-roblox-market.luau
--
-- Runs the real RobloxPriceModule over made-up player counts, a tick a
-- minute like the game, and prints how each price behaves - to check a
-- change to the price model before it reaches the live market.
-- From the repository root: `lune run tools/simulate-roblox-market.luau`
-- (add a tick length in seconds, e.g. `-- 300`, for a faster, coarser run).
--
-- Each scenario prints the price every six hours as a sparkline, then:
--   open     the price when trading opens, after the warm-up
--   range    the lowest and highest price once open
--   day move the largest change between two daily closes
--   swing    the average gap between a day's high and low, noise included
--   minute   the average 1-minute candle's range, wicks included
--   hour     the typical and the largest change over an hour - how fast-paced
--            it feels
--   fair     the day swing of the fair price alone (trend and surge, without
--            the noise) - for a steady game, the part that would follow a
--            schedule, which a player could farm by buying every dip and
--            selling every peak (the noise is random, so it can't be)

local process = require("@lune/process")

local RobloxPriceModule = require("../src/server/Modules/RobloxPriceModule")

local DAY = 86400
local HOUR = 3600
local START = 1793577600 -- Monday 2 November 2026, 00:00 UTC
local DAYS = 28
local TICK_SECONDS = tonumber(process.args[1]) or 60
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

local SUNDAY = START - DAY -- a Sunday, 00:00 UTC

-- A typical Roblox day: busiest in the US evening (about 00:00 UTC), quietest
-- twelve hours later, and busier over the weekend - smoothly, as real player
-- counts are
local function dailyCycle(t: number): number
	local hour = (t % DAY) / HOUR
	local week = math.cos((t - SUNDAY) / (7 * DAY) * 2 * math.pi)

	return (1 + 0.35 * math.cos(hour / 24 * 2 * math.pi)) * (1 + 0.075 * week)
end

-- Players online at `t` for each scenario, around `base`
local SCENARIOS = {
	{
		name = "Steady: the same game every week",
		base = 150000,
		playing = function(base, t)
			return base * dailyCycle(t)
		end,
	},
	{
		name = "Growing: players double over two weeks, from day 7",
		base = 20000,
		playing = function(base, t)
			local days = math.clamp((t - START) / DAY - 7, 0, 14)

			return base * 2 ^ (days / 14) * dailyCycle(t)
		end,
	},
	{
		name = "Viral: ten times the players for two days, on days 10-11",
		base = 5000,
		playing = function(base, t)
			local day = (t - START) // DAY
			local spike = (day == 10 or day == 11) and 10 or 1

			return base * spike * dailyCycle(t)
		end,
	},
	{
		name = "Event: an update brings 60% more players for six hours, day 12 from 18:00",
		base = 40000,
		playing = function(base, t)
			local hours = (t - START) / HOUR - (12 * 24 + 18)
			local event = (hours >= 0 and hours < 6) and 1.6 or 1

			return base * event * dailyCycle(t)
		end,
	},
	{
		name = "Fading: players halve over three weeks, from day 7",
		base = 60000,
		playing = function(base, t)
			local days = math.clamp((t - START) / DAY - 7, 0, 21)

			return base * 0.5 ^ (days / 21) * dailyCycle(t)
		end,
	},
	{
		name = "Listed at the daily peak vs the daily low (same game)",
		base = 150000,
		offset = 12 * HOUR,
		playing = function(base, t)
			return base * dailyCycle(t)
		end,
	},
}

local function sparkline(values)
	local low, high = math.huge, -math.huge

	for _, value in ipairs(values) do
		low = math.min(low, value)
		high = math.max(high, value)
	end

	local characters = {}

	for _, value in ipairs(values) do
		local level = high > low and math.floor((value - low) / (high - low) * (#SPARK - 1)) + 1 or 1

		table.insert(characters, SPARK[level])
	end

	return table.concat(characters)
end

local function stats(playing: number, t: number)
	return { playing = math.round(playing), upVotes = 900, downVotes = 100, updated = t - 30 * DAY }
end

local function run(scenario)
	-- Small noise, the same every run
	math.randomseed(1)

	local start = START + (scenario.offset or 0)
	local state = nil
	local openPrice = nil
	local samples = {}
	local low, high = math.huge, -math.huge
	local closes = {}
	local dayLow, dayHigh = math.huge, -math.huge
	local fairLow, fairHigh = math.huge, -math.huge
	local swings, fairSwings = {}, {}
	local minuteRanges, minuteCount = 0, 0
	local prices = {} -- every tick's price, for hourly changes
	local ticksPerHour = HOUR // TICK_SECONDS
	local hourTotal, hourCount, largestHour = 0, 0, 0

	for t = start, start + DAYS * DAY, TICK_SECONDS do
		local playing = scenario.playing(scenario.base, t) * (1 + (math.random() - 0.5) * 0.06)

		state = RobloxPriceModule.tick(state, stats(playing, t), t, math.random)
		table.insert(prices, state.price)

		local isOpen = RobloxPriceModule.isOpen(state, t)
		local hourAgo = prices[#prices - ticksPerHour]

		if isOpen and hourAgo then
			local move = math.abs(state.price / hourAgo - 1)

			hourTotal += move
			hourCount += 1
			largestHour = math.max(largestHour, move)
		end

		if isOpen then
			openPrice = openPrice or state.price
			low = math.min(low, state.price)
			high = math.max(high, state.price)
			dayLow = math.min(dayLow, state.low)
			dayHigh = math.max(dayHigh, state.high)
			fairLow = math.min(fairLow, state.fair)
			fairHigh = math.max(fairHigh, state.fair)
			minuteRanges += (state.high - state.low) / state.price
			minuteCount += 1
		end

		if (t - start) % (6 * HOUR) < TICK_SECONDS then
			table.insert(samples, state.price)
		end

		-- The end of a UTC day: note its close and its high-low swing
		if (t + TICK_SECONDS) // DAY ~= t // DAY and isOpen then
			table.insert(closes, state.price)
			table.insert(swings, (dayHigh - dayLow) / dayLow)
			table.insert(fairSwings, (fairHigh - fairLow) / fairLow)
			dayLow, dayHigh = math.huge, -math.huge
			fairLow, fairHigh = math.huge, -math.huge
		end
	end

	local largestMove = 0

	for index = 2, #closes do
		local move = (closes[index] - closes[index - 1]) / closes[index - 1]

		if math.abs(move) > math.abs(largestMove) then
			largestMove = move
		end
	end

	local swingTotal, fairSwingTotal = 0, 0

	-- The first day open is partial
	for index = 2, #swings do
		swingTotal += swings[index]
		fairSwingTotal += fairSwings[index]
	end

	local days = math.max(#swings - 1, 1)

	print(scenario.name)
	print("  " .. sparkline(samples))
	print(
		string.format(
			"  open $%.2f · range $%.2f-$%.2f · final $%.2f · day move %+.1f%%",
			openPrice or 0,
			low,
			high,
			state.price,
			largestMove * 100
		)
	)
	print(
		string.format(
			"  swing %.2f%% · minute %.3f%% · hour %.2f%% (largest %.1f%%) · fair swing %.2f%%",
			swingTotal / days * 100,
			minuteRanges / math.max(minuteCount, 1) * 100,
			hourTotal / math.max(hourCount, 1) * 100,
			largestHour * 100,
			fairSwingTotal / days * 100
		)
	)
	print()
end

print(
	string.format(
		"%d days, a tick every %d s, warm-up %d h\n",
		DAYS,
		TICK_SECONDS,
		RobloxPriceModule.WARMUP_SECONDS / HOUR
	)
)

for _, scenario in ipairs(SCENARIOS) do
	run(scenario)
end
