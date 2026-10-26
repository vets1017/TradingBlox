local TestKit = require("./TestKit")
local OrderRules = require("../src/shared/Modules/Multi/OrderRules")

local test, equal = TestKit.test, TestKit.equal

local PLACED = 1000

local function order(fields)
	local base = { id = "O1", ticker = "AAPL", side = "Buy", quantity = 10, createdAt = PLACED }

	for key, value in pairs(fields) do
		base[key] = value
	end

	return base
end

-- Candles a minute apart from just after the order was placed
local function candles(list)
	local result = {}

	for index, ohlc in ipairs(list) do
		result[index] =
			{ Timestamp = PLACED + index * 60, Open = ohlc[1], High = ohlc[2], Low = ohlc[3], Close = ohlc[4] }
	end

	return result
end

local function money(amount)
	return string.format("$%.2f", amount)
end

test("a limit order fills live at or past its limit", function()
	local buy = order({ limitPrice = 100 })
	local sell = order({ side = "Sell", limitPrice = 100 })

	equal(OrderRules.checkLive(buy, 101), nil)
	equal(OrderRules.checkLive(buy, 100), { fill = 100 })
	equal(OrderRules.checkLive(buy, 99.5), { fill = 99.5 })
	equal(OrderRules.checkLive(sell, 99), nil)
	equal(OrderRules.checkLive(sell, 100.5), { fill = 100.5 })
	equal(OrderRules.typeOf(buy), "limit", "orders saved before stops have no type")
end)

test("a stop fills live once the price reaches it: up for a buy, down for a sell", function()
	local buy = order({ type = "stop", stopPrice = 110 })
	local sell = order({ side = "Sell", type = "stop", stopPrice = 90 })

	equal(OrderRules.checkLive(buy, 109), nil)
	equal(OrderRules.checkLive(buy, 111), { fill = 111 })
	equal(OrderRules.checkLive(sell, 91), nil)
	equal(OrderRules.checkLive(sell, 89), { fill = 89 }, "a stop-loss sells at the market")
end)

test("a stop-limit triggers at its stop, then waits on its limit", function()
	local buy = order({ type = "stopLimit", stopPrice = 110, limitPrice = 112 })

	equal(OrderRules.checkLive(buy, 109), nil, "below the stop")
	equal(OrderRules.checkLive(buy, 111), { fill = 111 }, "stop reached, and within the limit")
	equal(OrderRules.checkLive(buy, 115), { trigger = true }, "stop reached, but past the limit")

	buy.triggeredAt = PLACED + 60

	equal(OrderRules.checkLive(buy, 115), nil, "now a limit at 112")
	equal(OrderRules.checkLive(buy, 108), { fill = 108 }, "a triggered order no longer needs the stop")
end)

test("catching up, a limit fills at the limit, or at a gap's better open", function()
	local buy = order({ limitPrice = 100 })

	equal(
		OrderRules.catchUp(buy, candles({ { 105, 106, 101, 102 }, { 103, 104, 99, 100 } })),
		{ fill = 100, at = PLACED + 120 }
	)
	equal(
		OrderRules.catchUp(buy, candles({ { 105, 106, 101, 102 }, { 97, 98, 96, 97 } })),
		{ fill = 97, at = PLACED + 120 }
	)
	equal(OrderRules.catchUp(buy, candles({ { 105, 106, 101, 102 } })), nil)
end)

test("catching up, a stop fills at the stop, or at a gap's worse open", function()
	local sell = order({ side = "Sell", type = "stop", stopPrice = 90 })

	equal(
		OrderRules.catchUp(sell, candles({ { 95, 96, 92, 93 }, { 92, 93, 88, 89 } })),
		{ fill = 90, at = PLACED + 120 }
	)
	-- Opened at 85, already under the 90 stop: the stop-loss sells at 85
	equal(
		OrderRules.catchUp(sell, candles({ { 95, 96, 92, 93 }, { 85, 86, 84, 85 } })),
		{ fill = 85, at = PLACED + 120 }
	)
end)

test("catching up, a stop-limit that gaps past its limit waits for it", function()
	local buy = order({ type = "stopLimit", stopPrice = 110, limitPrice = 112 })

	-- Reached the stop at 110, within the limit: fills at 110
	equal(OrderRules.catchUp(buy, candles({ { 108, 111, 107, 110 } })), { fill = 110, at = PLACED + 60 })

	-- Opened at 115, past the stop and the limit: triggered, not filled
	local gapped = candles({ { 115, 116, 113, 115 }, { 115, 117, 114, 116 } })

	equal(OrderRules.catchUp(buy, gapped), { triggeredAt = PLACED + 60 })

	-- Then it comes back to the limit
	local back = candles({ { 115, 116, 113, 115 }, { 114, 114, 111, 111.5 } })

	equal(OrderRules.catchUp(buy, back), { fill = 112, at = PLACED + 120 })
end)

test("a triggered stop-limit catches up as a limit from when it triggered", function()
	local sell =
		order({ side = "Sell", type = "stopLimit", stopPrice = 90, limitPrice = 89, triggeredAt = PLACED + 60 })

	-- The first candle is the one it triggered in, so it doesn't count
	equal(OrderRules.catchUp(sell, candles({ { 92, 95, 85, 86 }, { 86, 88, 85, 87 } })), nil)
	equal(
		OrderRules.catchUp(sell, candles({ { 92, 95, 85, 86 }, { 86, 90, 85, 89 } })),
		{ fill = 89, at = PLACED + 120 }
	)
end)

test("candles from before the order was placed don't count", function()
	local early = { { Timestamp = PLACED - 60, Open = 99, High = 99, Low = 95, Close = 96 } }

	equal(OrderRules.catchUp(order({ limitPrice = 100 }), early), nil)
end)

test("orders read the same everywhere", function()
	equal(OrderRules.describe(order({ limitPrice = 150 }), money), "Buy 10 AAPL @ $150.00 limit")
	equal(
		OrderRules.describe(order({ side = "Sell", type = "stop", stopPrice = 140 }), money),
		"Sell 10 AAPL @ $140.00 stop"
	)
	equal(
		OrderRules.describeTerms(order({ type = "stopLimit", stopPrice = 150, limitPrice = 151 }), money),
		"@ $150.00 stop, $151.00 limit"
	)
	equal(
		OrderRules.describeTerms(
			order({ type = "stopLimit", stopPrice = 150, limitPrice = 151, triggeredAt = 1 }),
			money
		),
		"@ $150.00 stop, $151.00 limit (stop reached)"
	)
	equal(OrderRules.describeLevels(order({ limitPrice = 150 }), money), "limit $150.00")
	equal(
		OrderRules.describeLevels(order({ type = "stopLimit", stopPrice = 150, limitPrice = 151 }), money),
		"stop $150.00, limit $151.00"
	)
	equal(OrderRules.reservedPrice(order({ type = "stop", stopPrice = 140 })), 140)
	equal(OrderRules.reservedPrice(order({ type = "stopLimit", stopPrice = 150, limitPrice = 151 })), 151)
end)
