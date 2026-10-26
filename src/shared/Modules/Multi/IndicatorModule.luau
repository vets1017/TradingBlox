-- IndicatorModule.luau
--
-- Chart indicators (GDD §4 "Technical Analysis"). Pure: no Roblox services,
-- so the Lune tests can run it. Each function returns arrays aligned with
-- its input - index i is the indicator at candle i - and leaves an index
-- unset (nil) until there's enough data for it.

local IndicatorModule = {}

-- Simple Moving Average. Returns an array the same length as `closes`;
-- indices before `period` is satisfied are left unset (nil).
function IndicatorModule.sma(closes, period)
	local result = {}
	local sum = 0

	for i, close in ipairs(closes) do
		sum += close

		if i > period then
			sum -= closes[i - period]
		end

		if i >= period then
			result[i] = sum / period
		end
	end

	return result
end

-- Exponential Moving Average. Seeded with the SMA of the first `period`
-- closes, then the standard EMA recurrence for the rest. Same sparse
-- shape as sma().
function IndicatorModule.ema(closes, period)
	local result = {}

	if #closes < period then
		return result
	end

	local sum = 0

	for i = 1, period do
		sum += closes[i]
	end

	local multiplier = 2 / (period + 1)
	local previousEma = sum / period
	result[period] = previousEma

	for i = period + 1, #closes do
		previousEma = (closes[i] - previousEma) * multiplier + previousEma
		result[i] = previousEma
	end

	return result
end

local function rsiFrom(averageGain: number, averageLoss: number): number
	if averageLoss == 0 then
		return if averageGain == 0 then 50 else 100
	end

	return 100 - 100 / (1 + averageGain / averageLoss)
end

-- Relative Strength Index, 0 to 100, with Wilder's smoothing: the first
-- value averages the first `period` changes, then each new change is
-- blended in at 1/period. Set from index period + 1.
function IndicatorModule.rsi(closes, period)
	local result = {}

	if #closes <= period then
		return result
	end

	local gain, loss = 0, 0

	for i = 2, period + 1 do
		local change = closes[i] - closes[i - 1]

		gain += math.max(change, 0)
		loss += math.max(-change, 0)
	end

	gain /= period
	loss /= period
	result[period + 1] = rsiFrom(gain, loss)

	for i = period + 2, #closes do
		local change = closes[i] - closes[i - 1]

		gain = (gain * (period - 1) + math.max(change, 0)) / period
		loss = (loss * (period - 1) + math.max(-change, 0)) / period
		result[i] = rsiFrom(gain, loss)
	end

	return result
end

-- MACD: the fast EMA minus the slow one, its `signalPeriod` EMA, and the
-- gap between the two (the histogram).
-- Returns { macd = {}, signal = {}, histogram = {} }.
function IndicatorModule.macd(closes, fast, slow, signalPeriod)
	local fastEma = IndicatorModule.ema(closes, fast)
	local slowEma = IndicatorModule.ema(closes, slow)
	local line, signal, histogram = {}, {}, {}
	local first = nil

	for i = math.max(fast, slow), #closes do
		if fastEma[i] and slowEma[i] then
			line[i] = fastEma[i] - slowEma[i]
			first = first or i
		end
	end

	if first then
		-- The signal is an EMA of the line's own stretch, which starts at `first`
		local stretch = {}

		for i = first, #closes do
			table.insert(stretch, line[i])
		end

		for offset, value in pairs(IndicatorModule.ema(stretch, signalPeriod)) do
			local i = first + offset - 1

			signal[i] = value
			histogram[i] = line[i] - value
		end
	end

	return { macd = line, signal = signal, histogram = histogram }
end

-- Bollinger Bands: the `period` SMA, and `deviations` standard deviations
-- (of the same closes, population) either side.
-- Returns { middle = {}, upper = {}, lower = {} }.
function IndicatorModule.bollinger(closes, period, deviations)
	local middle, upper, lower = {}, {}, {}

	for i = period, #closes do
		local sum, sumOfSquares = 0, 0

		for j = i - period + 1, i do
			sum += closes[j]
			sumOfSquares += closes[j] * closes[j]
		end

		local mean = sum / period
		local spread = deviations * math.sqrt(math.max(sumOfSquares / period - mean * mean, 0))

		middle[i] = mean
		upper[i] = mean + spread
		lower[i] = mean - spread
	end

	return { middle = middle, upper = upper, lower = lower }
end

-- Average True Range, with Wilder's smoothing. A candle's true range is the
-- widest of high to low and either against the previous close, so gaps
-- count. Takes candles ({ High, Low, Close }); set from index period + 1.
function IndicatorModule.atr(candles, period)
	local result = {}

	if #candles <= period then
		return result
	end

	local function trueRange(i)
		local candle, previousClose = candles[i], candles[i - 1].Close

		return math.max(
			candle.High - candle.Low,
			math.abs(candle.High - previousClose),
			math.abs(candle.Low - previousClose)
		)
	end

	local sum = 0

	for i = 2, period + 1 do
		sum += trueRange(i)
	end

	local value = sum / period

	result[period + 1] = value

	for i = period + 2, #candles do
		value = (value * (period - 1) + trueRange(i)) / period
		result[i] = value
	end

	return result
end

-- Volume-weighted average price of the typical price ((high + low + close)
-- / 3), restarting each session: `sessionOf(timestamp)` names the session a
-- candle belongs to, or nil for one long session. Unset until volume has
-- traded in the session - so always unset without volume (Roblox games).
function IndicatorModule.vwap(candles, sessionOf)
	local result = {}
	local session, priceVolume, volume = nil, 0, 0

	for i, candle in ipairs(candles) do
		local candleSession = sessionOf and sessionOf(candle.Timestamp)

		if i == 1 or candleSession ~= session then
			session, priceVolume, volume = candleSession, 0, 0
		end

		local traded = candle.Volume or 0

		priceVolume += (candle.High + candle.Low + candle.Close) / 3 * traded
		volume += traded

		if volume > 0 then
			result[i] = priceVolume / volume
		end
	end

	return result
end

-- Volume by price: `bins` equal bands from the lowest low to the highest
-- high, each candle's volume shared evenly across the bands its range
-- covers. Returns { low, high, volumes = { [band] = volume } }, or nil with
-- no volume or no range.
function IndicatorModule.volumeProfile(candles, bins)
	local low, high, total = math.huge, -math.huge, 0

	for _, candle in ipairs(candles) do
		low = math.min(low, candle.Low)
		high = math.max(high, candle.High)
		total += candle.Volume or 0
	end

	if total <= 0 or high <= low then
		return nil
	end

	local width = (high - low) / bins
	local volumes = table.create(bins, 0)

	for _, candle in ipairs(candles) do
		local traded = candle.Volume or 0

		if traded > 0 then
			local first = math.clamp(math.floor((candle.Low - low) / width) + 1, 1, bins)
			local last = math.clamp(math.floor((candle.High - low) / width) + 1, 1, bins)
			local share = traded / (last - first + 1)

			for band = first, last do
				volumes[band] += share
			end
		end
	end

	return { low = low, high = high, volumes = volumes }
end

return IndicatorModule
