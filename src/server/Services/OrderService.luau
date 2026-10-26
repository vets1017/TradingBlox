-- OrderService.luau
--
-- Share order execution. Market orders and waiting orders' fills both go
-- through fillShares, which moves cash and shares, logs the fill, fires
-- OrderEvents.Filled and reprices net worth.
--
-- Limit, stop and stop-limit orders (level 2) wait in playerData.Orders;
-- OrderRules says when each fills. A player's data is only loaded while
-- they're online, so orders are checked live while they play and caught up
-- at their next login against the candles since each order was placed.
-- Orders that can't fill (no cash or shares left) are cancelled, and
-- anything older than MAX_ORDER_AGE expires.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local ProgressionService = require(ServerScriptService.Services.ProgressionService)
local RobloxMarketService = require(ServerScriptService.Services.RobloxMarketService)
local OrderEvents = require(ServerScriptService.Services.OrderEvents)
local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local FillPriceModule = require(ServerScriptService.Modules.FillPriceModule)
local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)
local TradeLogModule = require(ServerScriptService.Modules.TradeLogModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local OrderRules = require(ReplicatedStorage.Modules.Multi.OrderRules)
local Progression = require(ReplicatedStorage.Config.Progression)
local Instruments = require(ReplicatedStorage.Config.Instruments)

local OrderUpdateEvent = ReplicatedStorage:WaitForChild("EventsFolder"):WaitForChild("OrderUpdateEvent")

local CHECK_INTERVAL = 15
local MAX_OPEN_ORDERS = 20
local MAX_ORDER_AGE = 30 * 86400
-- The backend keeps 5-minute candles for 7 days and hourly ones for 60, so
-- a catch-up uses the finest candles that still reach back to the order
local FINE_CANDLE_REACH = 6 * 86400

local OrderService = {}

local function isPositiveInteger(value)
	return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function isTradeable(ticker, now)
	return Instruments.tradesAroundTheClock(ticker) or MarketHoursModule.getMarketStatus(now)
end

local function describeOrder(order)
	return OrderRules.describe(order, NumberModule.format)
end

-- `price == price` rules out NaN
local function isPrice(price)
	return type(price) == "number" and price > 0 and price == price and price ~= math.huge
end

local function roundCents(price)
	return math.round(price * 100) / 100
end

-- Tells the player's client about something that happened to their orders
-- or positions while they weren't waiting on it. `kind` is "filled",
-- "cancelled", "expired" or "split".
function OrderService.notify(player, kind, message)
	if player.Parent == Players then
		OrderUpdateEvent:FireClient(player, { kind = kind, message = message })
	end
end

local notify = OrderService.notify

-- Executes a share fill at `price`. Checks cash and holdings only: callers
-- have validated the request and that the market is open.
function OrderService.fillShares(player, action, ticker, shares, price)
	local data = PlayerDataService.get(player)

	if not data then
		return { success = false, message = "Player data not loaded." }
	end

	-- Read before the fill: selling a whole position clears its average cost.
	-- Every held ticker has one; the fallback only stops a malformed save from
	-- failing a sale halfway through.
	local costBasis = data.Portfolio.AvgCost[ticker] or price

	if action == "Buy" then
		local totalCost = price * shares

		if data.Balance < totalCost then
			return { success = false, message = "Insufficient funds." }
		end

		PlayerDataService.setStat(player, "Balance", data.Balance - totalCost)
		PlayerDataService.updateShares(player, ticker, shares, price)
	else
		if (data.Portfolio.Shares[ticker] or 0) < shares then
			return { success = false, message = "Not enough shares to sell." }
		end

		PlayerDataService.setStat(player, "Balance", data.Balance + price * shares)
		PlayerDataService.updateShares(player, ticker, -shares, price)
	end

	local now = os.time()
	local fill = {
		ticker = ticker,
		side = action,
		quantity = shares,
		price = price,
		costBasis = costBasis,
	}
	local realizedPL = TradeLogModule.record(data, fill, now)

	OrderEvents.fireFilled(player, realizedPL, now, fill)
	CalculatorModule.calculateNetWorth(player)

	return {
		success = true,
		message = string.format("%s %d x %s @ %.2f", action, shares, ticker, price),
		price = price,
	}
end

local function isValidRequest(action, ticker, shares)
	if action ~= "Buy" and action ~= "Sell" then
		return false, "Invalid order type."
	elseif not MarketDataModule.isValidTicker(ticker) then
		return false, "Invalid ticker."
	elseif not isPositiveInteger(shares) then
		return false, "Invalid share quantity."
	end

	return true
end

-- What every waiting order checks before it's stored; the caller has
-- checked the request and its prices. `terms` holds the order's type and
-- prices ({ type?, limitPrice?, stopPrice? }).
local function storeOrder(player, action, targetTicker, shares, terms)
	-- A Roblox game warming up has candles but no trading, so no order may catch up against them
	if Instruments.isRoblox(targetTicker) then
		local reason = RobloxMarketService.getClosedReason(targetTicker)

		if reason then
			return { success = false, message = reason }
		end
	end

	local data = PlayerDataService.get(player)

	if not data then
		return { success = false, message = "Player data not loaded." }
	end

	local openCount = 0

	for _ in pairs(data.Orders) do
		openCount += 1
	end

	if openCount >= MAX_OPEN_ORDERS then
		return { success = false, message = "You can have up to " .. MAX_OPEN_ORDERS .. " open orders." }
	end

	-- Checked again at fill time; this just stops orders that can't fill now
	if action == "Buy" and data.Balance < OrderRules.reservedPrice(terms) * shares then
		return { success = false, message = "Insufficient funds for this order." }
	elseif action == "Sell" and (data.Portfolio.Shares[targetTicker] or 0) < shares then
		return { success = false, message = "Not enough shares to sell." }
	end

	data.OrderSequence += 1

	local order = {
		id = "O" .. data.OrderSequence,
		ticker = targetTicker,
		side = action,
		quantity = shares,
		type = terms.type,
		limitPrice = terms.limitPrice,
		stopPrice = terms.stopPrice,
		createdAt = os.time(),
	}

	data.Orders[order.id] = order

	return { success = true, message = "Placed: " .. describeOrder(order), order = order }
end

function OrderService.placeLimit(player, action, ticker, shares, limitPrice)
	local isValid, reason = isValidRequest(action, ticker, shares)

	if not isValid then
		return { success = false, message = reason }
	elseif not isPrice(limitPrice) then
		return { success = false, message = "Invalid limit price." }
	elseif not ProgressionService.hasFeature(player, "LimitOrders") then
		return { success = false, message = "Limit orders: " .. Progression.getLockedMessage("LimitOrders") }
	end

	return storeOrder(player, action, string.upper(ticker), shares, { limitPrice = roundCents(limitPrice) })
end

-- A stop (`limitPrice` nil: fills at the market once the stop is reached)
-- or a stop-limit. The stop has to be on the far side of the price - above
-- it to buy, below it to sell - or it would go off straight away.
function OrderService.placeStop(player, action, ticker, shares, stopPrice, limitPrice)
	local isValid, reason = isValidRequest(action, ticker, shares)

	if not isValid then
		return { success = false, message = reason }
	elseif not isPrice(stopPrice) then
		return { success = false, message = "Invalid stop price." }
	elseif limitPrice ~= nil and not isPrice(limitPrice) then
		return { success = false, message = "Invalid limit price." }
	elseif not ProgressionService.hasFeature(player, "StopOrders") then
		return { success = false, message = "Stop orders: " .. Progression.getLockedMessage("StopOrders") }
	end

	local targetTicker = string.upper(ticker)
	local price, priceReason = OrderService.getFillPrice(targetTicker, action)

	if not price then
		return { success = false, message = priceReason }
	end

	local stop = roundCents(stopPrice)

	if action == "Buy" and stop <= price then
		return {
			success = false,
			message = string.format(
				"A buy stop goes above the price (%s): it buys once the price rises to it.",
				NumberModule.format(price)
			),
		}
	elseif action == "Sell" and stop >= price then
		return {
			success = false,
			message = string.format(
				"A sell stop goes below the price (%s): it sells once the price falls to it.",
				NumberModule.format(price)
			),
		}
	end

	return storeOrder(player, action, targetTicker, shares, {
		type = limitPrice and "stopLimit" or "stop",
		stopPrice = stop,
		limitPrice = limitPrice and roundCents(limitPrice),
	})
end

function OrderService.cancel(player, orderId)
	local data = PlayerDataService.get(player)

	if not data or type(orderId) ~= "string" or not data.Orders[orderId] then
		return { success = false, message = "Order not found." }
	end

	local order = data.Orders[orderId]

	data.Orders[orderId] = nil

	return { success = true, message = "Cancelled: " .. describeOrder(order) }
end

-- Open orders, oldest first
function OrderService.getOrders(player)
	local data = PlayerDataService.get(player)
	local orders = {}

	if not data then
		return orders
	end

	for _, order in pairs(data.Orders) do
		table.insert(orders, order)
	end

	-- Ids count up, so they break ties between orders placed in the same second
	table.sort(orders, function(a, b)
		if a.createdAt ~= b.createdAt then
			return a.createdAt < b.createdAt
		end

		return tonumber(string.sub(a.id, 2)) < tonumber(string.sub(b.id, 2))
	end)

	return orders
end

-- The live price an order on `ticker` fills at - the ask for a buy and the
-- bid for a sell in regular trading - or nil and why not. Falls back to the
-- candle-based price when the quote route can't be reached. A Roblox-market
-- game that's warming up or delisted doesn't trade.
function OrderService.getFillPrice(ticker, side)
	if Instruments.isRoblox(ticker) then
		local reason = RobloxMarketService.getClosedReason(string.upper(ticker))

		if reason then
			return nil, reason
		end
	end

	local isCrypto = MarketDataModule.isCryptoTicker(ticker)
	local quote = MarketDataModule.getLiveQuote(ticker)

	if quote then
		return FillPriceModule.getFillPrice(quote, side, isCrypto, os.time())
	end

	local price = MarketDataModule.getCurrentPrice(ticker)

	if not price then
		return nil, "Price unavailable for " .. ticker .. "."
	end

	return price
end

-- Fills or cancels one order, if it's still open. `price` is what it fills at.
local function settle(player, order, price)
	local data = PlayerDataService.get(player)

	-- The player may have cancelled it while the price was being fetched
	if not data or data.Orders[order.id] ~= order then
		return
	end

	data.Orders[order.id] = nil

	local result = OrderService.fillShares(player, order.side, order.ticker, order.quantity, price)

	if result.success then
		notify(
			player,
			"filled",
			string.format(
				"%s %s filled: %d %s @ %s",
				OrderRules.TYPE_NAMES[OrderRules.typeOf(order)],
				string.lower(order.side),
				order.quantity,
				order.ticker,
				NumberModule.format(price)
			)
		)
	else
		notify(player, "cancelled", "Cancelled " .. describeOrder(order) .. ": " .. result.message)
	end
end

-- A stop-limit's stop was reached at `at` without its limit: from then on
-- it waits on the limit, if it's still open
local function trigger(player, order, at)
	local data = PlayerDataService.get(player)

	if not data or data.Orders[order.id] ~= order then
		return
	end

	order.triggeredAt = at
	notify(
		player,
		"triggered",
		string.format(
			"Stop reached: %s %d %s now waits on its %s limit",
			order.side,
			order.quantity,
			order.ticker,
			NumberModule.format(order.limitPrice)
		)
	)
end

local function expireOld(player, data, now)
	for id, order in pairs(data.Orders) do
		if now - order.createdAt > MAX_ORDER_AGE then
			data.Orders[id] = nil
			notify(player, "cancelled", "Expired after 30 days: " .. describeOrder(order))
		end
	end
end

-- Login catch-up: replays each order against the candles since it was
-- placed (OrderRules.catchUp), filling it - or triggering a stop-limit -
-- as the price went while the player was away
local function catchUp(player, data)
	local now = os.time()

	expireOld(player, data, now)

	for _, order in pairs(table.clone(data.Orders)) do
		local since = order.triggeredAt or order.createdAt
		local timeframe = now - since <= FINE_CANDLE_REACH and "5M" or "H"
		local outcome = OrderRules.catchUp(order, MarketDataModule.getCandles(order.ticker, timeframe) or {})

		if outcome and outcome.fill then
			settle(player, order, outcome.fill)
		elseif outcome and outcome.triggeredAt then
			trigger(player, order, outcome.triggeredAt)
		end
	end
end

-- One pass over every online player's orders, fetching each ticker's price
-- once per pass
local function checkOpenOrders()
	local now = os.time()
	local pending = {} -- { player, order }
	local tickers = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local data = PlayerDataService.get(player)

		if data then
			expireOld(player, data, now)

			for _, order in pairs(data.Orders) do
				if isTradeable(order.ticker, now) then
					table.insert(pending, { player = player, order = order })
					tickers[order.ticker] = true
				end
			end
		end
	end

	local tickerList = {}

	for ticker in pairs(tickers) do
		table.insert(tickerList, ticker)
	end

	MarketDataModule.getQuotes(tickerList) -- one batch request per pass

	-- A buy goes by the ask and a sell by the bid
	for _, entry in ipairs(pending) do
		local price = OrderService.getFillPrice(entry.order.ticker, entry.order.side)
		local outcome = price and OrderRules.checkLive(entry.order, price)

		if outcome and outcome.fill then
			task.spawn(settle, entry.player, entry.order, outcome.fill)
		elseif outcome and outcome.trigger then
			trigger(entry.player, entry.order, now)
		end
	end
end

function OrderService.start()
	PlayerDataService.PlayerLoaded:Connect(function(player)
		local data = PlayerDataService.get(player)

		if data and next(data.Orders) then
			catchUp(player, data)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			checkOpenOrders()
		end
	end)
end

return OrderService
