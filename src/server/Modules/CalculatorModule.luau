local ServerScriptService = game:GetService("ServerScriptService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)

local CalculatorModule = {}

function CalculatorModule.calculateNetWorth(player)
	local playerData = _G.PlayerData[player.UserId]

	if not playerData then
		return 0
	end

	local totalShareValue = 0
	local totalOptionValue = 0

	if playerData.Portfolio and playerData.Portfolio.Shares then
		for ticker, shares in pairs(playerData.Portfolio.Shares) do
			local price = MarketDataModule.getCurrentPrice(ticker)

			if price then
				totalShareValue = (totalShareValue or 0) + (shares * price)
			end
		end
	end

	if playerData.Portfolio and playerData.Portfolio.Options then
		for contractSymbol, position in pairs(playerData.Portfolio.Options) do
			local quote = MarketDataModule.getOptionQuote(position.ticker, contractSymbol)
			local premium = quote and quote.bid and quote.ask and (quote.bid + quote.ask) / 2
				or quote and quote.lastPrice

			if premium then
				totalOptionValue = (totalOptionValue or 0) + (position.contracts * premium * 100)
			end
		end
	end

	local finalNetWorth = playerData.Balance + totalShareValue + totalOptionValue

	if _G.UpdatePlayerStat then
		_G.UpdatePlayerStat(player, "NetWorth", finalNetWorth)
	else
		warn("UpdatePlayerStat function not found. Net worth will not be updated for " .. player.Name)
	end

	return finalNetWorth
end

return CalculatorModule
