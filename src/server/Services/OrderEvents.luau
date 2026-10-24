-- OrderEvents.luau
--
-- Fires after every filled order (shares and options), so services that
-- react to trading - progression, leaderboards, profiles, later the feed -
-- subscribe here instead of each order script calling every one of them.

local OrderEvents = {}

local filled = Instance.new("BindableEvent")

-- (player, realizedPL: number?, now: number) - realizedPL is nil for buys
OrderEvents.Filled = filled.Event

function OrderEvents.fireFilled(player, realizedPL: number?, now: number)
	filled:Fire(player, realizedPL, now)
end

return OrderEvents
