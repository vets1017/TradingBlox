local TestKit = require("./TestKit")
local IndicatorModule = require("../src/shared/Modules/Multi/IndicatorModule")

local test, equal, near = TestKit.test, TestKit.equal, TestKit.near

local function count(values)
	local total = 0

	for _ in pairs(values) do
		total += 1
	end

	return total
end

-- 1, 2, ..., n
local function rising(n)
	local closes = {}

	for i = 1, n do
		closes[i] = i
	end

	return closes
end

local function candle(timestamp, high, low, close, volume)
	return { Timestamp = timestamp, Open = close, High = high, Low = low, Close = close, Volume = volume }
end

test("moving averages start once their period is filled", function()
	equal(IndicatorModule.sma({ 1, 2, 3, 4 }, 2), { [2] = 1.5, [3] = 2.5, [4] = 3.5 })
	equal(IndicatorModule.ema({ 1, 2, 3 }, 2)[2], 1.5, "seeded with the SMA")
	near(IndicatorModule.ema({ 1, 2, 3 }, 2)[3], 1.5 + (3 - 1.5) * 2 / 3, 1e-9)
	equal(IndicatorModule.ema({ 1 }, 2), {})
end)

test("RSI uses Wilder's smoothing", function()
	-- Changes +1, -0.5, +1.5. First: gain 0.5, loss 0.25, RS 2. Then gain 1, loss 0.125, RS 8.
	local rsi = IndicatorModule.rsi({ 10, 11, 10.5, 12 }, 2)

	equal(rsi[2], nil, "needs period + 1 closes")
	near(rsi[3], 100 - 100 / 3, 1e-9)
	near(rsi[4], 100 - 100 / 9, 1e-9)
end)

test("RSI is 100 when only rising and 50 when flat", function()
	equal(IndicatorModule.rsi(rising(20), 14)[20], 100)
	equal(IndicatorModule.rsi(table.create(20, 5), 14)[20], 50)
	equal(IndicatorModule.rsi({ 1, 2 }, 14), {})
end)

test("MACD on a steady climb is the gap between the EMAs' lags", function()
	-- An EMA of a straight line lags it by (period - 1) / 2 steps, so the
	-- fast and slow EMAs sit (26 - 12) / 2 = 7 apart for a slope of 1
	local result = IndicatorModule.macd(rising(80), 12, 26, 9)

	equal(result.macd[25], nil, "needs the slow period")
	near(result.macd[26], 7, 1e-9)
	near(result.macd[80], 7, 1e-9)
	equal(result.signal[33], nil, "the signal needs nine values of the line")
	near(result.signal[34], 7, 1e-9)
	near(result.histogram[80], 0, 1e-9)
end)

test("MACD is zero on a flat series", function()
	local result = IndicatorModule.macd(table.create(60, 42), 12, 26, 9)

	near(result.macd[60], 0, 1e-9)
	near(result.histogram[60], 0, 1e-9)
end)

test("Bollinger Bands sit the deviations either side of the mean", function()
	local bands = IndicatorModule.bollinger({ 1, 3, 3 }, 2, 2)

	-- {1, 3}: mean 2, standard deviation 1
	equal(bands.middle[2], 2)
	equal(bands.upper[2], 4)
	equal(bands.lower[2], 0)
	-- {3, 3}: no spread
	equal(bands.upper[3], 3)
	equal(bands.lower[3], 3)
	equal(bands.middle[1], nil)
end)

test("ATR counts gaps through the previous close", function()
	local steady = {}

	for i = 1, 20 do
		steady[i] = candle(i, 11, 9, 10, 0)
	end

	equal(IndicatorModule.atr(steady, 14)[20], 2, "high minus low, every candle")

	-- A gap up: the range is 1, but it opened 5 above the previous close
	local gapped = { candle(1, 11, 9, 10, 0), candle(2, 15, 14, 14.5, 0), candle(3, 15, 14, 14.5, 0) }
	local atr = IndicatorModule.atr(gapped, 1)

	equal(atr[2], 5)
	equal(atr[3], 1)
	equal(count(IndicatorModule.atr(steady, 30)), 0)
end)

test("VWAP weighs the typical price by volume and restarts each session", function()
	local DAY = 86400
	local candles = {
		candle(0, 12, 8, 10, 1), -- typical 10
		candle(60, 22, 18, 20, 3), -- typical 20
		candle(DAY, 32, 28, 30, 2), -- next day: starts again
	}
	local vwap = IndicatorModule.vwap(candles, function(timestamp)
		return timestamp // DAY
	end)

	equal(vwap[1], 10)
	equal(vwap[2], (10 + 60) / 4)
	equal(vwap[3], 30)
	equal(IndicatorModule.vwap(candles)[3], (10 + 60 + 60) / 6, "one long session")
end)

test("VWAP stays unset without volume, as for Roblox games", function()
	equal(IndicatorModule.vwap({ candle(0, 12, 8, 10, 0), candle(60, 12, 8, 10, 0) }), {})
end)

test("the volume profile shares each candle's volume across the bands it spans", function()
	local profile = IndicatorModule.volumeProfile({
		candle(0, 10, 0, 5, 100), -- spans all four bands
		candle(60, 2, 1, 1.5, 40), -- the lowest band only
	}, 4)

	equal(profile.low, 0)
	equal(profile.high, 10)
	equal(profile.volumes, { 65, 25, 25, 25 })
	equal(IndicatorModule.volumeProfile({ candle(0, 10, 0, 5, 0) }, 4), nil, "no volume")
end)
