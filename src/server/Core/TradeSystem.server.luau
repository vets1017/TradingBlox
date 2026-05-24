local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
			PlayerData.Balance -= totalValue
			PlayerData.Portfolio.Shares[ticker] = (PlayerData.Portfolio.Shares[ticker] or 0) + shares

			print(player.Name .. " bought " .. shares .. " shares of " .. ticker)
		else
			warn(player.Name .. " has insufficient funds to buy " .. shares .. " shares of " .. ticker)
		end
	elseif action == "Sell" then
		local ownedShares = PlayerData.Portfolio.Shares[ticker] or 0

		if ownedShares >= shares then
			PlayerData.Portfolio.Shares[ticker] = ownedShares - shares
			PlayerData.Balance += totalValue

			if PlayerData.Portfolio.Shares[ticker] == 0 then
				PlayerData.Portfolio.Shares[ticker] = nil
			end

			print(player.Name .. " sold " .. shares .. " shares of " .. ticker)
		else
			warn(player.Name .. " does not have enough shares to sell " .. shares .. " of " .. ticker)
		end
	end
end)
