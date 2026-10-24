-- Navigation.luau
--
-- Client-side hand-off between screen controllers, which are separate
-- LocalScripts and can't reach each other's locals. A controller asks for a
-- ticker or a tab; TerminalController switches tabs, and TradeController
-- loads a requested ticker. Every LocalScript that requires this gets the
-- same table, so the BindableEvents below link them.

local Navigation = {}

local tickerRequested = Instance.new("BindableEvent")
local tabRequested = Instance.new("BindableEvent")

-- Fires with the ticker to show on the Trade screen
Navigation.TickerRequested = tickerRequested.Event

-- Fires with the tab to switch to: "Dashboard", "Portfolio", "Leaderboards"...
Navigation.TabRequested = tabRequested.Event

function Navigation.openTicker(ticker: string)
	tickerRequested:Fire(ticker)
end

function Navigation.openTab(tabName: string)
	tabRequested:Fire(tabName)
end

return Navigation
