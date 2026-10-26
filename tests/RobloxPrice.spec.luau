local TestKit = require("./TestKit")
local RobloxPriceModule = require("../src/server/Modules/RobloxPriceModule")
local RobloxMarket = require("../src/shared/Config/RobloxMarket")
local Instruments = require("../src/shared/Config/Instruments")

local test, equal, near = TestKit.test, TestKit.equal, TestKit.near

local DAY = 86400
local NOW = TestKit.utc(2026, 10, 25, 12)

local function stats(playing, overrides)
	local base = { playing = playing, upVotes = 900, downVotes = 100, updated = NOW - 30 * DAY }

	for key, value in pairs(overrides or {}) do
		base[key] = value
	end

	return base
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
	local up = RobloxPriceModule.step(100, 200, fiveMinutes)

	near(up, 100 + 100 * 0.10 * fiveMinutes / DAY, 1e-9, "capped")
	near(RobloxPriceModule.step(100, 100.01, fiveMinutes), 100 + 0.01 * (1 - math.exp(-300 / 43200)), 1e-9, "uncapped")

	local afterGap = RobloxPriceModule.step(100, 200, 2 * DAY)

	near(afterGap, 120, 1e-9, "two days with no ticks allow 20%")
end)

test("listing starts the price at its target", function()
	local state = RobloxPriceModule.tick(nil, stats(10000), NOW)

	equal(state.price, 140) -- 100 x 1.4 like x 1 momentum x 1 freshness
	equal(state.prevClose, 140)
	equal(state.listedAt, NOW)
	equal(state.activity, 10000)
	equal(state.day, "2026-10-25")
end)

test("activity is a smoothed average, so one quiet tick barely moves it", function()
	local state = RobloxPriceModule.tick(nil, stats(10000), NOW)

	state = RobloxPriceModule.tick(state, stats(0), NOW + 300)

	near(state.activity, 10000 * math.exp(-300 / DAY), 1e-6)
	equal(state.price >= 140 * (1 - 0.10 * 300 / DAY) - 0.01, true, "the price can't fall faster than the cap")
end)

test("a new day makes the last price the day's previous close", function()
	local state = RobloxPriceModule.tick(nil, stats(10000), NOW)

	state = RobloxPriceModule.tick(state, stats(40000), NOW + 300)

	local lastPriceOfDay = state.price

	equal(state.prevClose, 140, "same day")

	state = RobloxPriceModule.tick(state, stats(40000), NOW + 13 * 3600)

	equal(state.prevClose, lastPriceOfDay)
	equal(state.day, "2026-10-26")
end)

test("a week of growth adds momentum", function()
	local state = RobloxPriceModule.tick(nil, stats(10000), NOW)

	for day = 1, 7 do
		state = RobloxPriceModule.tick(state, stats(40000), NOW + day * DAY)
	end

	equal(state.activityByDay[RobloxPriceModule.dayKey(NOW)] ~= nil, true, "a week back is still kept")
	equal(state.target > RobloxPriceModule.targetPrice(state.activity, 1.4, 1, 1), true)
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

test("history keeps a week in full, then hourly, then daily", function()
	local points = {}
	local start = NOW - 100 * DAY

	for time = start, NOW, 1800 do
		points = RobloxPriceModule.addPoint(points, time, 1)
	end

	local lastWeek, older = 0, 0

	for _, point in ipairs(points) do
		if NOW - point[1] <= 7 * DAY then
			lastWeek += 1
		else
			older += 1
		end
	end

	equal(lastWeek, 7 * 48 + 1, "every half-hour point of the last week")
	equal(older < (100 - 7) * 24 + 10, true, "at most one an hour before that")
end)

test("candles open at the previous close and span their bucket", function()
	local points = { { 1000, 10 }, { 1300, 12 }, { 1500, 9 }, { 1900, 11 } }
	local candles = RobloxPriceModule.buildCandles(points, 600, 1200)

	equal(#candles, 2)
	equal(candles[1], { Timestamp = 1200, Open = 10, High = 12, Low = 9, Close = 9, Volume = 0 })
	equal(candles[2], { Timestamp = 1800, Open = 9, High = 11, Low = 9, Close = 11, Volume = 0 })
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
	equal(market.experiences["RBX-AAAA"].delisted, nil)

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
