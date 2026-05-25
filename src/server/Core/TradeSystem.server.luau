local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local TradeEvent = EventsFolder:WaitForChild("TradeEvent")

TradeEvent.OnServerEvent:Connect(function(player, action, ticker, shares)
	if type(action) ~= "string" or type(ticker) ~= "string" or type(shares) ~= "number" then
		return
	end

	shares = math.floor(shares)

	if shares <= 0 then
		return
	end

	ticker = string.upper(ticker)

	local PlayerData = _G.PlayerData[player.UserId]
	local LiveMarketData = _G.LiveMarketData

	if not PlayerData or not LiveMarketData or not LiveMarketData[ticker] then
		warn("Invalid trade attempt by " .. player.Name)
		return
	end

	local currentPrice = LiveMarketData[ticker].Price
	local totalValue = currentPrice * shares

	if action == "Buy" then
		if PlayerData.Balance >= totalValue then
			local newBalance = PlayerData.Balance - totalValue

			_G.UpdatePlayerStat(player, "Balance", newBalance)
			_G.UpdatePortfolio(player, ticker, shares)
			CalculatorModule.calculateNetWorth(player)

			print(player.Name .. " bought " .. shares .. " shares of " .. ticker)
		else
			warn(player.Name .. " has insufficient funds to buy " .. shares .. " shares of " .. ticker)
		end
	elseif action == "Sell" then
		local ownedShares = PlayerData.Portfolio.Shares[ticker] or 0

		if PlayerData.Portfolio and PlayerData.Portfolio.Shares[ticker] then
			ownedShares = PlayerData.Portfolio.Shares[ticker]
		else
			ownedShares = 0
		end

		if ownedShares >= shares then
			local totalProceeds = currentPrice * shares
			local newBalance = PlayerData.Balance + totalProceeds

			_G.UpdatePlayerStat(player, "Balance", newBalance)
			_G.UpdatePortfolio(player, ticker, -shares)
			CalculatorModule.calculateNetWorth(player)

			print(player.Name .. " sold " .. shares .. " shares of " .. ticker)
		else
			warn(player.Name .. " does not have enough shares to sell " .. shares .. " of " .. ticker)
		end
	end
end)
