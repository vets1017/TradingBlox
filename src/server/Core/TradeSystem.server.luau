-- TradeSystem.server.luau
--
-- Order execution (Buy/Sell) and positions reporting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)
local TradeLogModule = require(ServerScriptService.Modules.TradeLogModule)
local OrderEvents = require(ServerScriptService.Services.OrderEvents)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local PlayerOrderEvent = EventsFolder:WaitForChild("PlayerOrderEvent")
local GetPositionsEvent = EventsFolder:WaitForChild("GetPositionsEvent")

local VALID_ACTIONS = { Buy = true, Sell = true }

local function isPositiveInteger(value)
	return type(value) == "number" and value > 0 and value == math.floor(value)
end

-- PlayerOrderEvent
PlayerOrderEvent.OnServerInvoke = function(player, action, ticker, shares)
	if type(action) ~= "string" or not VALID_ACTIONS[action] then
		return { success = false, message = "Invalid order type." }
	end

	if not MarketDataModule.isValidTicker(ticker) then
		return { success = false, message = "Invalid ticker." }
	end

	if not isPositiveInteger(shares) then
		return { success = false, message = "Invalid share quantity." }
	end

	local targetTicker = string.upper(ticker)

	if not MarketDataModule.isCryptoTicker(targetTicker) and not MarketHoursModule.getMarketStatus(os.time()) then
		return { success = false, message = "Market is closed." }
	end

	local playerData = _G.PlayerData[player.UserId]

	if not playerData then
		return { success = false, message = "Player data not loaded." }
	end

	local price = MarketDataModule.getCurrentPrice(targetTicker)

	if not price then
		return { success = false, message = "Price unavailable for " .. targetTicker .. "." }
	end

	-- Read before the fill: selling a whole position clears its average cost.
	-- Every held ticker has one; the fallback only stops a malformed save from
	-- failing a sale halfway through.
	local costBasis = playerData.Portfolio.AvgCost[targetTicker] or price

	if action == "Buy" then
		local totalCost = price * shares

		if playerData.Balance < totalCost then
			return { success = false, message = "Insufficient funds." }
		end

		_G.UpdatePlayerStat(player, "Balance", playerData.Balance - totalCost)
		_G.UpdatePortfolio(player, targetTicker, shares, price)
	else -- Sell
		local portfolioShares = playerData.Portfolio and playerData.Portfolio.Shares
		local ownedShares = (portfolioShares and portfolioShares[targetTicker]) or 0

		if ownedShares < shares then
			return { success = false, message = "Not enough shares to sell." }
		end

		local totalProceeds = price * shares

		_G.UpdatePlayerStat(player, "Balance", playerData.Balance + totalProceeds)
		_G.UpdatePortfolio(player, targetTicker, -shares, price)
	end

	local now = os.time()
	local realizedPL = TradeLogModule.record(playerData, {
		ticker = targetTicker,
		side = action,
		quantity = shares,
		price = price,
		costBasis = costBasis,
	}, now)

	OrderEvents.fireFilled(player, realizedPL, now)
	CalculatorModule.calculateNetWorth(player)

	return {
		success = true,
		message = string.format("%s %d x %s @ %.2f", action, shares, targetTicker, price),
		price = price,
	}
end

-- GetPositionsEvent
-- Builds the player's current holdings, priced against live market data.
-- With a ticker, filters to just that ticker's position (the Trade screen's
-- use case - one active symbol at a time); without one, returns every open
-- position (the Portfolio tab's share rows).
GetPositionsEvent.OnServerInvoke = function(player, ticker)
	local playerData = _G.PlayerData[player.UserId]

	if not playerData or not playerData.Portfolio or not playerData.Portfolio.Shares then
		return {}
	end

	local targetTicker = ticker and string.upper(ticker) or nil
	local positions = {}

	for posTicker, quantity in pairs(playerData.Portfolio.Shares) do
		if not targetTicker or posTicker == targetTicker then
			local quote = MarketDataModule.getQuote(posTicker)
			local avgCost = playerData.Portfolio.AvgCost and playerData.Portfolio.AvgCost[posTicker]

			local mark = quote and quote.price
			local markChange = (mark and quote.prevClose) and (mark - quote.prevClose) or nil
			local cost = avgCost and (avgCost * quantity) or nil
			local netLiq = mark and (mark * quantity) or nil
			local plOpen = (netLiq and cost) and (netLiq - cost) or nil
			local plOpenPct = (plOpen and cost and cost ~= 0) and (plOpen / cost * 100) or nil
			local plDay = markChange and (markChange * quantity) or nil

			table.insert(positions, {
				ticker = posTicker,
				quantity = quantity,
				mark = mark,
				markChange = markChange,
				plDay = plDay,
				plOpen = plOpen,
				netLiq = netLiq,
				tradePrice = avgCost,
				cost = cost,
				delta = nil,
				theta = nil,
				plOpenPct = plOpenPct,
			})
		end
	end

	return positions
end
