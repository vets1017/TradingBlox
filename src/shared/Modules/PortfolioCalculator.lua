local PortfolioCalculator = {}

function PortfolioCalculator.calculatePortfolioValue(playerData, marketData)
	if not marketData then
		return playerData.Balance
	end

	local totalNetWorth = playerData.Balance

	for ticker, amount in pairs(playerData.Portfolio.Shares) do
		if marketData[ticker] then
			totalNetWorth += (amount * marketData[ticker].Price)
		end
	end

	for _, contract in ipairs(playerData.Portfolio.Options) do
		if marketData[contract.Ticker] then
			local livePrice = marketData[contract.Ticker].Price
			local intrinsicValue = 0

			if contract.Type == "Call" and livePrice > contract.StrikePrice then
				intrinsicValue = (livePrice - contract.StrikePrice) * contract.Quantity
			elseif contract.Type == "Put" and livePrice < contract.StrikePrice then
				intrinsicValue = (contract.StrikePrice - livePrice) * contract.Quantity
			end
		end
	end
	return totalNetWorth
end

function PortfolioCalculator.format(amount)
	local formatted = tostring(amount)
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return "$" .. formatted
end

return PortfolioCalculator
