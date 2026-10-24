local ServerScriptService = game:GetService("ServerScriptService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local PortfolioHistoryModule = require(ServerScriptService.Modules.PortfolioHistoryModule)

local CalculatorModule = {}

-- Per-share premium of an option quote: the bid/ask midpoint, or the last
-- trade when there's no two-sided market. Nil when there's no quote.
function CalculatorModule.getOptionPremium(quote)
	return quote and quote.bid and quote.ask and (quote.bid + quote.ask) / 2 or quote and quote.lastPrice
end

function CalculatorModule.calculateNetWorth(player)
	local playerData = _G.PlayerData[player.UserId]

	if not playerData then
		return 0
	end

	local totalShareValue = 0
	local totalOptionValue = 0

	-- False when a holding couldn't be priced because the backend failed.
	-- That total is undercounted, so it stays out of the chart history,
	-- where it would read as a crash.
	local isComplete = true

	if playerData.Portfolio and playerData.Portfolio.Shares then
		for ticker, shares in pairs(playerData.Portfolio.Shares) do
			local price = MarketDataModule.getCurrentPrice(ticker)

			if price then
				totalShareValue = (totalShareValue or 0) + (shares * price)
			else
				isComplete = false
			end
		end
	end

	if playerData.Portfolio and playerData.Portfolio.Options then
		for contractSymbol, position in pairs(playerData.Portfolio.Options) do
			local quote = MarketDataModule.getOptionQuote(position.ticker, contractSymbol)
			local premium = CalculatorModule.getOptionPremium(quote)

			if premium then
				totalOptionValue = (totalOptionValue or 0) + (position.contracts * premium * 100)
			elseif not MarketDataModule.getOptionChain(position.ticker) then
				-- Only a chain that failed to load counts. A contract the chain
				-- no longer lists (expired, or outside its strike window) is
				-- valued at 0 every time, so it doesn't distort the history.
				isComplete = false
			end
		end
	end

	local finalNetWorth = playerData.Balance + totalShareValue + totalOptionValue

	if isComplete then
		playerData.NetWorthHistory =
			PortfolioHistoryModule.record(playerData.NetWorthHistory or {}, finalNetWorth, os.time())
	end

	if _G.UpdatePlayerStat then
		_G.UpdatePlayerStat(player, "NetWorth", finalNetWorth)
	else
		warn("UpdatePlayerStat function not found. Net worth will not be updated for " .. player.Name)
	end

	return finalNetWorth
end

return CalculatorModule
