-- OrderEvents.luau
--
-- Fires after every filled order (shares and options), so services that
-- react to trading - progression, leaderboards, profiles, the feed -
-- subscribe here instead of each order script calling every one of them.

local OrderEvents = {}

local filled = Instance.new("BindableEvent")

-- (player, realizedPL: number?, now: number, fill) - realizedPL is nil for
-- buys; fill is what the order recorded in the trade log (see
-- TradeLogModule.record), and listeners get a copy
OrderEvents.Filled = filled.Event

function OrderEvents.fireFilled(player, realizedPL: number?, now: number, fill)
	filled:Fire(player, realizedPL, now, fill)
end

return OrderEvents
