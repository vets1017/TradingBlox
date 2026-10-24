-- Navigation.luau
--
-- Client-side hand-off between screen controllers, which are separate
-- LocalScripts and can't reach each other's locals. A controller asks for a
-- ticker; TerminalController switches to the Trade tab and TradeController
-- loads it. Every LocalScript that requires this gets the same table, so the
-- one BindableEvent below links them.

local Navigation = {}

local tickerRequested = Instance.new("BindableEvent")

-- Fires with the ticker to show on the Trade screen
Navigation.TickerRequested = tickerRequested.Event

function Navigation.openTicker(ticker: string)
	tickerRequested:Fire(ticker)
end

return Navigation
