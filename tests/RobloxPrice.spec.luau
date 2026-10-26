local TestKit = require("./TestKit")
local RobloxPriceModule = require("../src/server/Modules/RobloxPriceModule")
local RobloxMarket = require("../src/shared/Config/RobloxMarket")
local Instruments = require("../src/shared/Config/Instruments")

local test, equal, near = TestKit.test, TestKit.equal, TestKit.near

local DAY = 86400
local HOUR = 3600
local NOW = TestKit.utc(2026, 10, 25, 12)
local WARMUP = RobloxPriceModule.WARMUP_SECONDS

local function stats(playing, overrides)
	local base = { playing = playing, upVotes = 900, downVotes = 100, updated = NOW - 30 * DAY }

	for key, value in pairs(overrides or {}) do
		base[key] = value
	end

	return base
end

-- Ticks every `step` seconds from `from` to `to`, with players online from `playingAt(t)`
local function run(state, from, to, step, playingAt)
	for t = from, to, step do
		state = RobloxPriceModule.tick(state, stats(playingAt(t)), t)
	end

	return state
end

-- A repeatable uniform source in (0, 1) for the noise (Park-Miller)
local function seeded(seed)
	local value = seed

	return function()
		value = value * 16807 % 2147483647

		return value / 2147483647
	end
end

-- Ticks every `step` seconds (a minute by default) with the noise on,
-- `playing` players throughout; returns every state from `from` to `to`
local function runNoisy(from, to, playing, seed, step)
	local random = seeded(seed)
	local states = {}
	local state = nil

	for t = from, to, step or 60 do
		state = RobloxPriceModule.tick(state, stats(playing), t, random)
		table.insert(states, state)
	end

	return states
end

test("the like factor runs from 0.5 to 1.5, and assumes 80% with no votes", function()
	near(RobloxPriceModule.likeFactor(900, 100), 1.4, 1e-9)
	equal(RobloxPriceModule.likeFactor(0, 0), 1.3)
	equal(RobloxPriceModule.likeFactor(nil, nil), 1.3)
	equal(RobloxPriceModule.likeFactor(0, 50), 0.5)
end)

test("freshness rewards recent updates and marks down abandoned experiences", function()
	equal(RobloxPriceModule.freshnessFactor(NOW - 3 * DAY, NOW), 1.05)
	equal(RobloxPriceModule.freshnessFactor(NOW - 60 * DAY, NOW), 1)
	equal(RobloxPriceModule.freshnessFactor(NOW - 200 * DAY, NOW), 0.95)
	equal(RobloxPriceModule.freshnessFactor(NOW - 800 * DAY, NOW), 0.9)
	equal(RobloxPriceModule.freshnessFactor(nil, NOW), 1)
end)

test("momentum is damped, capped, and 1 without a week of history", function()
	near(RobloxPriceModule.momentumFactor(200, 100), 2 ^ 0.25, 1e-9)
	near(RobloxPriceModule.momentumFactor(1000, 100), 2 ^ 0.25, 1e-9, "capped at doubling")
	near(RobloxPriceModule.momentumFactor(10, 100), 0.5 ^ 0.25, 1e-9, "capped at halving")
	equal(RobloxPriceModule.momentumFactor(100, nil), 1)
end)

test("the target grows with the square root of activity", function()
	equal(RobloxPriceModule.targetPrice(100, 1, 1, 1), 10)
	equal(RobloxPriceModule.targetPrice(10000, 1, 1, 1), 100)
	equal(RobloxPriceModule.targetPrice(0, 1, 1, 1), 1, "an empty experience doesn't go to zero")
end)

test("a step closes in on the target but moves at most 10% per day passed", function()
	local fiveMinutes = 300

	near(RobloxPriceModule.step(100, 200, fiveMinutes), 100 + 100 * 0.10 * fiveMinutes / DAY, 1e-9, "capped")
	near(RobloxPriceModule.step(100, 100.01, fiveMinutes), 100 + 0.01 * (1 - math.exp(-300 / 43200)), 1e-9, "uncapped")
	near(RobloxPriceModule.step(100, 200, 2 * DAY), 120, 1e-9, "two days with no ticks allow 20%")
end)

test("hours keep their mean, and drop off after a week", function()
	local hours, current = RobloxPriceModule.addSample(nil, nil, 100, NOW)

	hours, current = RobloxPriceModule.addSample(hours, current, 300, NOW + 60)
	equal(#hours, 0, "still the first hour")
	equal(RobloxPriceModule.activityFrom(hours, current), 200)

	hours, current = RobloxPriceModule.addSample(hours, current, 50, NOW + HOUR)
	equal(hours, { { NOW // HOUR, 200 } }, "the finished hour keeps its mean")
	equal(RobloxPriceModule.activityFrom(hours, current), 125, "a mean of hourly means")

	hours, current = RobloxPriceModule.addSample(hours, current, 50, NOW + 7 * DAY + HOUR)
	equal(#hours, 0, "older than a week is gone")
end)

test("a steady day-night cycle and weekends leave the weekly average flat", function()
	local function playingAt(t)
		local hour = (t % DAY) / HOUR
		local weekday = tonumber(os.date("!%w", t))

		return 10000 * (1 + 0.35 * math.cos(hour / 24 * 2 * math.pi)) * ((weekday == 0 or weekday == 6) and 1.15 or 1)
	end

	local state = run(nil, NOW, NOW + 7 * DAY, 300, playingAt)
	local low, high = math.huge, -math.huge

	for t = NOW + 7 * DAY + 300, NOW + 9 * DAY, 300 do
		state = RobloxPriceModule.tick(state, stats(playingAt(t)), t)
		low = math.min(low, state.activity)
		high = math.max(high, state.activity)
	end

	equal((high - low) / low < 0.01, true, string.format("activity moved %.2f%%", (high - low) / low * 100))
end)

test("a new listing warms up for a day: the price follows the target, then trades", function()
	local state = RobloxPriceModule.tick(nil, stats(10000), NOW)

	equal(state.price, 140) -- 100 x 1.4 like x 1 momentum x 1 freshness
	equal(state.opensAt, NOW + WARMUP)
	equal(RobloxPriceModule.isOpen(state, NOW + WARMUP - 1), false)
	equal(RobloxPriceModule.isOpen(state, NOW + WARMUP), true)

	state = RobloxPriceModule.tick(state, stats(40000), NOW + 60)
	near(state.price, state.target, 0.005, "warming up: no cap")

	state = run(state, NOW + 120, NOW + WARMUP, HOUR, function()
		return 40000
	end)
	state = RobloxPriceModule.tick(state, stats(40000), NOW + WARMUP)

	local before = state.price

	state = RobloxPriceModule.tick(state, stats(400000), NOW + WARMUP + 60)
	equal(state.price <= before * (1 + 0.10 * 60 / DAY) + 0.01, true, "open: capped")
end)

test("a cheap price still moves a minute at a time", function()
	-- One player online: $1.40, so the most it may move in a minute is a
	-- hundredth of a cent
	local state = run(nil, NOW, NOW + WARMUP, 60, function()
		return 1
	end)
	local opening = state.price

	state = run(state, NOW + WARMUP + 60, NOW + WARMUP + DAY, 60, function()
		return 4
	end)

	equal(state.price > opening * 1.05, true, string.format("$%.4f -> $%.4f", opening, state.price))
	equal(state.price <= opening * math.exp(0.10) + 1e-9, true, "within the daily cap")
end)

test("momentum waits for a full week's average from a week before", function()
	local state = run(nil, NOW, NOW + 10 * DAY, HOUR, function()
		return 10000
	end)

	for day in pairs(state.activityByDay) do
		equal(day >= RobloxPriceModule.dayKey(NOW + 7 * DAY - HOUR), true, "kept a partial week: " .. day)
	end
end)

test("a state saved before the weekly average is listed again", function()
	local old =
		{ price = 555, prevClose = 555, day = "2026-10-25", activity = 150000, listedAt = NOW - DAY, lastSeenAt = NOW }
	local state = RobloxPriceModule.tick(old, stats(10000), NOW + 60)

	equal(state.opensAt, NOW + 60 + WARMUP)
	equal(state.listedAt, NOW + 60)
end)

test("once open, a new day makes the last price the day's previous close", function()
	local state = run(nil, NOW, NOW + WARMUP, HOUR, function()
		return 10000
	end)

	state = RobloxPriceModule.tick(state, stats(40000), NOW + WARMUP + 300)

	local lastPriceOfDay = state.price

	state = RobloxPriceModule.tick(state, stats(40000), NOW + WARMUP + 13 * HOUR)
	equal(state.prevClose, lastPriceOfDay)
end)

test("a missing experience holds its price and delists after a day", function()
	local state = RobloxPriceModule.tick(nil, stats(10000), NOW)
	local held = RobloxPriceModule.hold(state, NOW + 300)

	equal(held.price, state.price)
	equal(held.missingSince, NOW + 300)
	equal(RobloxPriceModule.hold(held, NOW + 600).missingSince, NOW + 300, "keeps the first time it went missing")
	equal(RobloxPriceModule.shouldDelist(held, NOW + 300 + DAY - 1), false)
	equal(RobloxPriceModule.shouldDelist(held, NOW + 300 + DAY), true)
	equal(RobloxPriceModule.tick(held, stats(10000), NOW + 900).missingSince, nil, "found again")
end)

test("history keeps a day in full, then five-minute, then hourly points", function()
	local points = {}
	local batch = {}

	for time = NOW - 30 * DAY, NOW, 60 do
		table.insert(batch, { time, 1 })

		if #batch == 5 then
			points = RobloxPriceModule.addPoints(points, batch, time)
			batch = {}
		end
	end

	local lastDay, lastWeek, older = 0, 0, 0

	for _, point in ipairs(points) do
		local age = NOW - point[1]

		if age <= DAY then
			lastDay += 1
		elseif age <= 7 * DAY then
			lastWeek += 1
		else
			older += 1
		end
	end

	equal(lastDay >= 1430 and lastDay <= 1441, true, "about every minute of the last day: " .. lastDay)
	equal(lastWeek <= 6 * 288 + 2, true, "at most one per five minutes before that: " .. lastWeek)
	equal(older <= 23 * 24 + 2, true, "at most one an hour before that: " .. older)
end)

test("candles open at the previous close and span their bucket", function()
	local points = { { 1000, 10 }, { 1300, 12 }, { 1500, 9 }, { 1900, 11 } }
	local candles = RobloxPriceModule.buildCandles(points, 600, 1200)

	equal(#candles, 2)
	equal(candles[1], { Timestamp = 1200, Open = 10, High = 12, Low = 9, Close = 9, Volume = 0 })
	equal(candles[2], { Timestamp = 1800, Open = 9, High = 11, Low = 9, Close = 11, Volume = 0 })
end)

test("a market tick lists, holds and delists experiences", function()
	local listing = {
		{ ticker = "RBX-AAAA", universeId = 1 },
		{ ticker = "RBX-BBBB", universeId = 2 },
	}
	local market = RobloxPriceModule.tickMarket(nil, listing, { ["1"] = stats(10000) }, NOW)

	equal(market.lastTickAt, NOW)
	equal(market.experiences["RBX-AAAA"].price, 140)
	equal(market.experiences["RBX-BBBB"], nil, "never seen, not listed yet")

	market = RobloxPriceModule.tickMarket(market, listing, {}, NOW + 300)

	equal(market.experiences["RBX-AAAA"].missingSince, NOW + 300, "Roblox didn't answer: held")

	market = RobloxPriceModule.tickMarket(market, listing, {}, NOW + 300 + DAY)

	equal(market.experiences["RBX-AAAA"].delisted, true, "missing a day: delisted")
	equal(market.experiences["RBX-AAAA"].price, 140, "at its last price")

	market = RobloxPriceModule.tickMarket(market, listing, { ["1"] = stats(10000) }, NOW + 600 + DAY)

	equal(market.experiences["RBX-AAAA"].delisted, true, "delisting is final")
end)

test("an experience dropped from the listing delists at once", function()
	local listing = { { ticker = "RBX-AAAA", universeId = 1 } }
	local market = RobloxPriceModule.tickMarket(nil, listing, { ["1"] = stats(10000) }, NOW)

	market = RobloxPriceModule.tickMarket(market, {}, { ["1"] = stats(10000) }, NOW + 300)

	equal(market.experiences["RBX-AAAA"].delisted, true)
	equal(market.experiences["RBX-AAAA"].delistedAt, NOW + 300)
end)

test("each tick adds a price point; 15 minutes are kept, and sent to the history every five", function()
	local listing = { { ticker = "RBX-AAAA", universeId = 1 } }
	local statsById = { ["1"] = stats(10000) }
	local market, flush = nil, nil
	local sent, flushes = {}, 0

	for t = NOW, NOW + 1800, 60 do
		market, flush = RobloxPriceModule.tickMarket(market, listing, statsById, t)

		if flush then
			flushes += 1

			for _, point in ipairs(flush["RBX-AAAA"]) do
				table.insert(sent, point[1])
			end
		end
	end

	local expected = {}

	for t = NOW, NOW + 1800, 60 do
		table.insert(expected, t)
	end

	equal(sent, expected, "every point once, in order - warming up too")
	equal(flushes, 7, "the first tick, then one flush per five minutes")
	equal(#market.recent["RBX-AAAA"], 15)
	equal(market.recent["RBX-AAAA"][15][1], NOW + 1800)

	market = RobloxPriceModule.tickMarket(market, {}, statsById, NOW + 1860)
	equal(#market.recent["RBX-AAAA"], 14, "a delisted experience gets no new points")
end)

test("the public view leaves out the averaging internals", function()
	local listing = { { ticker = "RBX-AAAA", universeId = 1 } }
	local statsById = { ["1"] = stats(10000) }
	local market = RobloxPriceModule.tickMarket(nil, listing, statsById, NOW)
	local view = RobloxPriceModule.publicView(market)
	local experience = view.experiences["RBX-AAAA"]

	equal(view.lastTickAt, NOW)
	equal(experience.price, 140)
	equal(experience.opensAt, NOW + WARMUP)
	equal(experience.hours, nil)
	equal(experience.current, nil)
	equal(experience.activityByDay, nil)
	equal(experience.recent, { { NOW, 140 } })
end)

test("recent points replace the saved history's from the same stretch", function()
	local saved = { { 100, 1 }, { 160, 2 }, { 220, 3 } }

	equal(RobloxPriceModule.withRecent(saved, { { 160, 5 }, { 220, 6 }, { 280, 7 } }), {
		{ 100, 1 },
		{ 160, 5 },
		{ 220, 6 },
		{ 280, 7 },
	})
	equal(RobloxPriceModule.withRecent(saved, nil), saved)
	equal(RobloxPriceModule.withRecent({}, { { 280, 7 } }), { { 280, 7 } })
end)

test("a batch written to the history twice isn't doubled, and a late one lands in order", function()
	local points = RobloxPriceModule.addPoints({}, { { NOW - 120, 1 }, { NOW - 60, 2 } }, NOW)

	points = RobloxPriceModule.addPoints(points, { { NOW - 120, 1 }, { NOW - 60, 2 }, { NOW, 3 } }, NOW)
	equal(points, { { NOW - 120, 1 }, { NOW - 60, 2 }, { NOW, 3 } })

	points = RobloxPriceModule.addPoints(points, { { NOW - 180, 0 } }, NOW)
	equal(points[1], { NOW - 180, 0 })
	equal(#points, 4)
end)

test("noise gives each tick a range around its open and close, so candles get wicks", function()
	local states = runNoisy(NOW, NOW + DAY, 10000, 7)
	local wicks, rangeTotal = 0, 0

	for index = 2, #states do
		local previous, state = states[index - 1], states[index]
		local bodyHigh = math.max(previous.price, state.price)
		local bodyLow = math.min(previous.price, state.price)

		equal(state.high >= bodyHigh - 1e-9 and state.low <= bodyLow + 1e-9, true, "range covers the body")

		if state.high > bodyHigh + 1e-9 or state.low < bodyLow - 1e-9 then
			wicks += 1
		end

		rangeTotal += (state.high - state.low) / state.price
	end

	local averageRange = rangeTotal / (#states - 1)

	equal(wicks > (#states - 1) / 2, true, "most minutes have a wick: " .. wicks)
	equal(
		averageRange > 0.0003 and averageRange < 0.005,
		true,
		string.format("a minute's range is visible but small: %.3f%%", averageRange * 100)
	)
end)

test("noise keeps its spread around the fair price, within bounds, and fades back", function()
	local states = runNoisy(NOW, NOW + 30 * DAY, 10000, 11, 600)
	local total, count, largest = 0, 0, 0

	for _, state in ipairs(states) do
		local deviation = math.log(state.price / state.fair)

		total += deviation * deviation
		count += 1
		largest = math.max(largest, math.abs(deviation))
	end

	local spread = math.sqrt(total / count)

	equal(
		spread > RobloxPriceModule.NOISE_SPREAD * 0.5 and spread < RobloxPriceModule.NOISE_SPREAD * 1.5,
		true,
		string.format("spread %.2f%%", spread * 100)
	)
	equal(largest <= 3 * RobloxPriceModule.NOISE_SPREAD + 1e-9, true, "capped at three spreads")

	-- cos(2π x 0.25) is 0, so this source gives no jolt: only the fade
	local noJolt = function()
		return 0.25
	end

	near(
		RobloxPriceModule.stepNoise(0.02, RobloxPriceModule.NOISE_TAU, noJolt),
		0.02 * math.exp(-1),
		1e-9,
		"fades by e in NOISE_TAU"
	)
end)

test("a minute's move doesn't foretell the next, so the noise can't be scalped", function()
	local states = runNoisy(NOW + WARMUP, NOW + WARMUP + 5 * DAY, 10000, 3)
	local moves = {}

	for index = 2, #states do
		table.insert(moves, math.log(states[index].price / states[index - 1].price))
	end

	local mean = 0

	for _, move in ipairs(moves) do
		mean += move / #moves
	end

	local covariance, variance = 0, 0

	for index = 2, #moves do
		covariance += (moves[index] - mean) * (moves[index - 1] - mean)
	end

	for _, move in ipairs(moves) do
		variance += (move - mean) ^ 2
	end

	local correlation = covariance / variance

	equal(math.abs(correlation) < 0.05, true, string.format("correlation %.3f", correlation))
end)

test("thinning keeps a bucket's whole range, and candles use it", function()
	local old = NOW - 2 * DAY -- five-minute buckets at this age
	local bucket = (old // 300) * 300
	local points = RobloxPriceModule.addPoints({}, {
		{ bucket + 10, 10, 11, 9 },
		{ bucket + 70, 10.5, 10.6, 8.5 },
		{ bucket + 130, 10.2 },
	}, NOW)

	equal(points, { { bucket + 130, 10.2, 11, 8.5 } })

	local candles = RobloxPriceModule.buildCandles({ { 1000, 10 }, { 1060, 10.2, 10.6, 9.5 } }, 300, 0)

	equal(candles, { { Timestamp = 900, Open = 10, High = 10.6, Low = 9.5, Close = 10.2, Volume = 0 } })
end)

test("every listed experience has a unique RBX- ticker the game accepts", function()
	local seenTickers, seenIds = {}, {}

	for _, experience in ipairs(RobloxMarket.EXPERIENCES) do
		equal(Instruments.isRoblox(experience.ticker), true, experience.ticker)
		equal(
			#experience.ticker <= 10 and string.match(experience.ticker, "^[%a%d%.%-]+$") ~= nil,
			true,
			experience.ticker
		)
		equal(seenTickers[experience.ticker], nil, "duplicate ticker " .. experience.ticker)
		equal(seenIds[experience.universeId], nil, "duplicate universe " .. experience.universeId)
		seenTickers[experience.ticker] = true
		seenIds[experience.universeId] = true
	end

	equal(#RobloxMarket.EXPERIENCES, 50)
	equal(RobloxMarket.getExperience("RBX-ADPT").name, "Adopt Me!")
end)

test("asset classes", function()
	equal(Instruments.getAssetClass("RBX-ADPT"), "roblox")
	equal(Instruments.getAssetClass("btc-usd"), "crypto")
	equal(Instruments.getAssetClass("AAPL"), "security")
	equal(Instruments.tradesAroundTheClock("RBX-ADPT"), true)
	equal(Instruments.tradesAroundTheClock("ETH-USD"), true)
	equal(Instruments.tradesAroundTheClock("SPY"), false)
end)
