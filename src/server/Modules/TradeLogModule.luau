-- TradeLogModule.luau
--
-- Records every fill a player makes into their data: the recent fills
-- themselves (playerData.TradeLog, oldest first) and running realized-P/L
-- stats in playerData.Stats that cover every trade ever made, so win rate
-- and average gain/loss survive the log being trimmed.
--
-- A sell's realized P/L is measured against the position's average cost at
-- the moment of the sale - the same basis the positions tables show. Each
-- sell counts as one closed trade: a win above $0, a loss below, and a
-- break-even sell neither.

local TradeLogModule = {}

local MAX_LOG_ENTRIES = 500
local OPTION_MULTIPLIER = 100 -- shares per contract

local function roundCents(amount)
	return math.round(amount * 100) / 100
end

-- fill = {
--   ticker: string,      the share ticker, or an option's underlying
--   contract: string?,   the option's contract symbol; nil for shares
--   side: "Buy" | "Sell",
--   quantity: number,    shares or contracts
--   price: number,       per share, or per-share premium for options
--   costBasis: number?,  average cost per unit before the fill; required for sells
--   settlement: string?, set when no order caused it (e.g. "Expired" for an
--                        option settled at expiry): logged and counted in the
--                        realized P/L stats, but not as one of the player's trades
-- }
-- Returns the fill's realized P/L (nil for buys).
function TradeLogModule.record(playerData, fill, now)
	local stats = playerData.Stats
	local multiplier = fill.contract and OPTION_MULTIPLIER or 1
	local realizedPL = nil

	if fill.side == "Sell" then
		realizedPL = roundCents((fill.price - fill.costBasis) * fill.quantity * multiplier)
		stats.RealizedPL = roundCents(stats.RealizedPL + realizedPL)

		if realizedPL > 0 then
			stats.Wins += 1
			stats.GrossGain = roundCents(stats.GrossGain + realizedPL)
		elseif realizedPL < 0 then
			stats.Losses += 1
			stats.GrossLoss = roundCents(stats.GrossLoss - realizedPL)
		end
	end

	if not fill.settlement then
		stats.Trades += 1
	end

	local log = playerData.TradeLog

	table.insert(log, {
		time = now,
		ticker = fill.ticker,
		contract = fill.contract,
		side = fill.side,
		quantity = fill.quantity,
		price = fill.price,
		realizedPL = realizedPL,
		settlement = fill.settlement,
	})

	while #log > MAX_LOG_ENTRIES do
		table.remove(log, 1)
	end

	return realizedPL
end

-- Win rate and average gain/loss from the running stats; each is nil until
-- there's a closed trade to base it on
function TradeLogModule.getSummary(stats)
	local closedTrades = stats.Wins + stats.Losses

	return {
		realizedPL = stats.RealizedPL,
		winRate = closedTrades > 0 and stats.Wins / closedTrades or nil,
		averageGain = stats.Wins > 0 and roundCents(stats.GrossGain / stats.Wins) or nil,
		averageLoss = stats.Losses > 0 and roundCents(stats.GrossLoss / stats.Losses) or nil,
		closedTrades = closedTrades,
	}
end

return TradeLogModule
