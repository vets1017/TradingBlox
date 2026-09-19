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

return IndicatorModule
