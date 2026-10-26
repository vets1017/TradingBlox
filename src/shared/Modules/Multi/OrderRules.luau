-- OrderRules.luau
--
-- When a waiting share order fills, and how it reads. Pure (no Roblox
-- services, no requires) so the Lune tests can run it; OrderService applies
-- it live and at login, and the order lists and ticket word orders with it.
--
-- An order in playerData.Orders:
--   { id, ticker, side ("Buy" | "Sell"), quantity, createdAt,
--     type? ("limit" when unset, "stop" or "stopLimit"),
--     limitPrice? (limit and stop-limit), stopPrice? (stop and stop-limit),
--     triggeredAt? (a stop-limit whose stop was reached) }
--
--   limit       a buy fills at or below the limit, a sell at or above
--   stop        a buy fills at the market once the price rises to the stop,
--               a sell once it falls to it (a stop-loss)
--   stopLimit   reaching the stop turns it into a limit order at the limit
--
-- Live checks see one price - the ask for a buy, the bid for a sell - and
-- fill at it. Catch-up sees candles: a candle that crosses a level fills at
-- the level, or at the candle's open if it opened past it (a gap) - the
-- better price for a limit, the worse for a stop, as on a real exchange.

local OrderRules = {}

OrderRules.TYPE_NAMES = { limit = "Limit", stop = "Stop", stopLimit = "Stop-limit" }

function OrderRules.typeOf(order): string
	return order.type or "limit"
end

-- Whether the order is waiting on its limit: a limit order, or a stop-limit
-- whose stop has been reached
local function isAtLimit(order): boolean
	local orderType = OrderRules.typeOf(order)

	return orderType == "limit" or (orderType == "stopLimit" and order.triggeredAt ~= nil)
end

function OrderRules.crossesLimit(order, low: number, high: number): boolean
	if order.side == "Buy" then
		return low <= order.limitPrice
	end

	return high >= order.limitPrice
end

function OrderRules.reachesStop(order, low: number, high: number): boolean
	if order.side == "Buy" then
		return high >= order.stopPrice
	end

	return low <= order.stopPrice
end

-- What a live `price` does to the order: { fill = price } to fill now,
-- { trigger = true } when a stop-limit's stop is reached but its limit
-- isn't, or nil
function OrderRules.checkLive(order, price: number)
	if isAtLimit(order) then
		return if OrderRules.crossesLimit(order, price, price) then { fill = price } else nil
	end

	if not OrderRules.reachesStop(order, price, price) then
		return nil
	end

	if OrderRules.typeOf(order) == "stop" or OrderRules.crossesLimit(order, price, price) then
		return { fill = price }
	end

	return { trigger = true }
end

-- Where a candle that crossed `level` fills: at the level, or at its open
-- when it opened past it (a gap) - the path inside a candle is unknown
local function fillWithin(candle, level: number, openedPast: boolean): number
	return if openedPast then candle.Open else level
end

-- Replays the candles since the order was placed (or triggered) - oldest
-- first, { Timestamp, Open, High, Low, Close } - and returns
-- { fill = price, at = timestamp }, { triggeredAt = timestamp } for a
-- stop-limit that triggered but hasn't filled, or nil
function OrderRules.catchUp(order, candles)
	local since = order.triggeredAt or order.createdAt
	local orderType = OrderRules.typeOf(order)
	local triggeredAt = order.triggeredAt
	local isBuy = order.side == "Buy"

	for _, candle in ipairs(candles) do
		if candle.Timestamp >= since and (not triggeredAt or candle.Timestamp > triggeredAt) then
			if orderType == "limit" or triggeredAt then
				if OrderRules.crossesLimit(order, candle.Low, candle.High) then
					-- A buy that opened below the limit (or a sell above it) gets the open
					local openedPast = if isBuy then candle.Open < order.limitPrice else candle.Open > order.limitPrice

					return { fill = fillWithin(candle, order.limitPrice, openedPast), at = candle.Timestamp }
				end
			elseif OrderRules.reachesStop(order, candle.Low, candle.High) then
				-- A buy stop that opened above the stop (or a sell below it) gets the open
				local openedPast = if isBuy then candle.Open > order.stopPrice else candle.Open < order.stopPrice
				local triggerPrice = fillWithin(candle, order.stopPrice, openedPast)

				if orderType == "stop" or OrderRules.crossesLimit(order, triggerPrice, triggerPrice) then
					return { fill = triggerPrice, at = candle.Timestamp }
				end

				-- Gapped past the limit: it waits as a limit order from the next candle
				triggeredAt = candle.Timestamp
			end
		end
	end

	if triggeredAt and not order.triggeredAt then
		return { triggeredAt = triggeredAt }
	end

	return nil
end

-- The price a buy is reserved at, for cash already promised to open orders
function OrderRules.reservedPrice(order): number
	return order.limitPrice or order.stopPrice
end

-- "@ $150.00 limit", "@ $150.00 stop", "@ $150.00 stop, $151.00 limit";
-- `money` formats a dollar amount (NumberModule.format)
function OrderRules.describeTerms(order, money: (number) -> string): string
	local orderType = OrderRules.typeOf(order)

	if orderType == "stop" then
		return string.format("@ %s stop", money(order.stopPrice))
	elseif orderType == "stopLimit" then
		local terms = string.format("@ %s stop, %s limit", money(order.stopPrice), money(order.limitPrice))

		return if order.triggeredAt then terms .. " (stop reached)" else terms
	end

	return string.format("@ %s limit", money(order.limitPrice))
end

-- For a column rather than a sentence: "limit $150.00", "stop $140.00",
-- "stop $150.00, limit $151.00"
function OrderRules.describeLevels(order, money: (number) -> string): string
	local orderType = OrderRules.typeOf(order)

	if orderType == "stop" then
		return "stop " .. money(order.stopPrice)
	elseif orderType == "stopLimit" then
		local levels = string.format("stop %s, limit %s", money(order.stopPrice), money(order.limitPrice))

		return if order.triggeredAt then levels .. " (stop reached)" else levels
	end

	return "limit " .. money(order.limitPrice)
end

-- "Buy 10 AAPL @ $150.00 limit"
function OrderRules.describe(order, money: (number) -> string): string
	return string.format(
		"%s %d %s %s",
		order.side,
		order.quantity,
		order.ticker,
		OrderRules.describeTerms(order, money)
	)
end

return OrderRules
