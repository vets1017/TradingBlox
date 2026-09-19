local NumberModule = {}

local function addCommas(numberString)
	local formatted = numberString
	local k

	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")

		if k == 0 then
			break
		end
	end

	return formatted
end

function NumberModule.format(amount)
	local sign = amount < 0 and "-" or ""

	return sign .. "$" .. addCommas(string.format("%.2f", math.abs(amount)))
end

-- Comma-grouped integer, no currency prefix - for share/contract counts
-- (Volume, Open Interest, # of Analysts), not dollar amounts.
function NumberModule.formatShares(amount)
	return addCommas(string.format("%d", math.floor(amount)))
end

-- Abbreviated currency for large dollar figures (market cap, revenue, cash,
-- debt) - e.g. $3.00T, $245.67B, $12.30M, $850.00K. Falls back to plain
-- comma-grouped dollars under $1,000.
function NumberModule.formatCompact(amount)
	local sign = amount < 0 and "-" or ""
	local magnitude = math.abs(amount)

	if magnitude >= 1e12 then
		return sign .. string.format("$%.2fT", magnitude / 1e12)
	elseif magnitude >= 1e9 then
		return sign .. string.format("$%.2fB", magnitude / 1e9)
	elseif magnitude >= 1e6 then
		return sign .. string.format("$%.2fM", magnitude / 1e6)
	elseif magnitude >= 1e3 then
		return sign .. string.format("$%.2fK", magnitude / 1e3)
	end

	return sign .. "$" .. addCommas(string.format("%.2f", magnitude))
end

return NumberModule
