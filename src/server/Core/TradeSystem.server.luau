local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = ReplicatedStorage:WaitForChild("Events")
local TradeEvent = Events:WaitForChild("TradeEvent")

TradeEvent.OnServerEvent:Connect(function(player, action, ticker, shares)
	if type(action) ~= "string" or type(ticker) ~= "string" or type(shares) ~= "number" then
		return
	end
	shares = math.floor(shares)
	if shares <= 0 then
		return
	end
	ticker = string.upper(ticker)

	local playerData = _G.ActivePlayers[player.UserId]
	local marketData = _G.LiveData

	if not playerData or not marketData or not marketData[ticker] then
		warn("Invalid trade attempt by " .. player.Name)
		return
	end

	local currentPrice = marketData[ticker].Price
	local totalValue = currentPrice * shares

	if action == "Buy" then
		if playerData.Balance >= totalValue then
			playerData.Balance -= totalValue
			playerData.Portfolio.Shares[ticker] = (playerData.Portfolio.Shares[ticker] or 0) + shares

			print(player.Name .. " bought " .. shares .. " shares of " .. ticker)
		else
			warn(player.Name .. " has insufficient funds to buy " .. shares .. " shares of ")
		end
	elseif action == "Sell" then
		local ownedShares = playerData.Portfolio.Shares[ticker] or 0

		if ownedShares >= shares then
			playerData.Portfolio.Shares[ticker] = ownedShares - shares
			playerData.Balance += totalValue

			if playerData.Portfolio.Shares[ticker] == 0 then
				playerData.Portfolio.Shares[ticker] = nil
			end

			print(player.Name .. " sold " .. shares .. " shares of " .. ticker)
		else
			warn(player.Name .. " does not have enough shares to sell " .. shares .. " of " .. ticker)
		end
	end
end)
