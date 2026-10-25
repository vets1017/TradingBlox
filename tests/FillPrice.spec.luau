local TestKit = require("./TestKit")
local FillPriceModule = require("../src/server/Modules/FillPriceModule")

local test, equal = TestKit.test, TestKit.equal
local getFillPrice = FillPriceModule.getFillPrice

local NOW = 1_800_000_000

-- `without` lists fields to leave out, as the backend does when Yahoo has none
local function quote(overrides, without)
	local result = { price = 100, bid = 99.95, ask = 100.05, marketState = "REGULAR", time = NOW }

	for key, value in pairs(overrides or {}) do
		result[key] = value
	end

	for _, key in ipairs(without or {}) do
		result[key] = nil
	end

	return result
end

test("regular session: buys pay the ask, sells get the bid", function()
	equal(getFillPrice(quote(), "Buy", false, NOW), 100.05)
	equal(getFillPrice(quote(), "Sell", false, NOW), 99.95)
end)

test("no usable price refuses the fill", function()
	equal({ getFillPrice(nil, "Buy", false, NOW) }, { nil, "Price unavailable." })
	equal({ getFillPrice(quote({ price = 0 }), "Buy", false, NOW) }, { nil, "Price unavailable." })
	equal({ getFillPrice({ marketState = "REGULAR" }, "Buy", false, NOW) }, { nil, "Price unavailable." })
end)

test("crypto always fills at the last price", function()
	equal(getFillPrice(quote(), "Buy", true, NOW), 100)
	equal(getFillPrice(quote(), "Sell", true, NOW), 100)
end)

test("outside the regular session both sides fill at the last price", function()
	equal(getFillPrice(quote({ marketState = "POST" }), "Buy", false, NOW), 100)
	equal(getFillPrice(quote({ marketState = "PRE" }), "Sell", false, NOW), 100)
end)

test("a missing, inverted or wide book falls back to the last price", function()
	equal(getFillPrice(quote(nil, { "bid", "ask" }), "Buy", false, NOW), 100, "missing")
	equal(getFillPrice(quote({ bid = 0 }), "Sell", false, NOW), 100, "zero bid")
	equal(getFillPrice(quote({ bid = 100.1, ask = 100 }), "Buy", false, NOW), 100, "inverted")
	equal(getFillPrice(quote({ bid = 95, ask = 105 }), "Buy", false, NOW), 100, "10% spread")
end)

test("a 2% spread is still sane", function()
	equal(getFillPrice(quote({ bid = 99, ask = 101 }), "Buy", false, NOW), 101)
end)

test("a regular-session quote over 15 minutes old is refused", function()
	local stale = { nil, "The price feed is behind; try again in a moment." }

	equal({ getFillPrice(quote({ time = NOW - 15 * 60 - 1 }), "Buy", false, NOW) }, stale)
	equal(getFillPrice(quote({ time = NOW - 15 * 60 }), "Buy", false, NOW), 100.05, "exactly 15 minutes")
end)

test("staleness only applies to regular-session stock quotes", function()
	local old = NOW - 3600

	equal(getFillPrice(quote({ time = old }), "Buy", true, NOW), 100, "crypto")
	equal(getFillPrice(quote({ time = old, marketState = "CLOSED" }), "Buy", false, NOW), 100, "closed")
	equal(getFillPrice(quote(nil, { "time" }), "Buy", false, NOW), 100.05, "no timestamp")
end)

return nil
