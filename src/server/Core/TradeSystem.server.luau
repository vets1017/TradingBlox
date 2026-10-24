-- TradeSystem.server.luau
--
-- Share order remotes (market orders, and level 2 limit orders placed,
-- cancelled and listed) and positions reporting. Execution itself lives in
-- OrderService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local OrderService = require(ServerScriptService.Services.OrderService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local PlayerOrderEvent = EventsFolder:WaitForChild("PlayerOrderEvent")
local PlaceLimitOrderEvent = EventsFolder:WaitForChild("PlaceLimitOrderEvent")
local CancelOrderEvent = EventsFolder:WaitForChild("CancelOrderEvent")
local GetOrdersEvent = EventsFolder:WaitForChild("GetOrdersEvent")
local GetPositionsEvent = EventsFolder:WaitForChild("GetPositionsEvent")

local VALID_ACTIONS = { Buy = true, Sell = true }

local function isPositiveInteger(value)
	return type(value) == "number" and value > 0 and value == math.floor(value)
end

-- PlayerOrderEvent
-- Market order: fills now at the live price
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

	if not PlayerDataService.get(player) then
		return { success = false, message = "Player data not loaded." }
	end

	local price = MarketDataModule.getCurrentPrice(targetTicker)

	if not price then
		return { success = false, message = "Price unavailable for " .. targetTicker .. "." }
	end

	return OrderService.fillShares(player, action, targetTicker, shares, price)
end

-- PlaceLimitOrderEvent
-- Can be placed while the market is closed; it fills once the market opens
-- and the price crosses the limit
PlaceLimitOrderEvent.OnServerInvoke = function(player, action, ticker, shares, limitPrice)
	return OrderService.placeLimit(player, action, ticker, shares, limitPrice)
end

-- CancelOrderEvent
CancelOrderEvent.OnServerInvoke = function(player, orderId)
	return OrderService.cancel(player, orderId)
end

-- GetOrdersEvent
-- Open limit orders, oldest first
GetOrdersEvent.OnServerInvoke = function(player)
	return OrderService.getOrders(player)
end

-- GetPositionsEvent
-- Builds the player's current holdings, priced against live market data.
-- With a ticker, filters to just that ticker's position (the Trade screen's
-- use case - one active symbol at a time); without one, returns every open
-- position (the Portfolio tab's share rows).
GetPositionsEvent.OnServerInvoke = function(player, ticker)
	local playerData = PlayerDataService.get(player)

	if not playerData then
		return {}
	end

	local targetTicker = type(ticker) == "string" and string.upper(ticker) or nil
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
