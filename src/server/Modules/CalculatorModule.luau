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
	elseif playerData.Portfolio and playerData.Portfolio.Options then
		for contractID, contractsOwned in pairs(playerData.Portfolio.Options) do
			local currentPremium = nil -- WIP optionPremium(contractID)
			local contractValue = currentPremium * 100

			totalOptionValue = (totalOptionValue or 0) + (contractsOwned * contractValue)
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
