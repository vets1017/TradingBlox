-- WatchlistSystem.server.luau
--
-- Per-player watchlist: add/remove tickers, report them back priced against
-- live market data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetWatchlistEvent = EventsFolder:WaitForChild("GetWatchlistEvent")
local ToggleWatchlistEvent = EventsFolder:WaitForChild("ToggleWatchlistEvent")

local WATCHLIST_CAP = 20

-- GetWatchlistEvent
-- Returns the player's watchlist tickers priced against live market data.
GetWatchlistEvent.OnServerInvoke = function(player)
	local playerData = _G.PlayerData[player.UserId]

	if not playerData or not playerData.Watchlist then
		return {}
	end

	local rows = {}

	MarketDataModule.getQuotes(playerData.Watchlist) -- one batch request for the whole list

	for _, ticker in ipairs(playerData.Watchlist) do
		local quote = MarketDataModule.getQuote(ticker)
		local price = quote and quote.price
		local change = (price and quote.prevClose) and (price - quote.prevClose) or nil
		local changePct = (change and quote.prevClose and quote.prevClose ~= 0) and (change / quote.prevClose * 100)
			or nil

		table.insert(rows, {
			ticker = ticker,
			price = price,
			change = change,
			changePct = changePct,
		})
	end

	return rows
end

-- ToggleWatchlistEvent
-- Adds the ticker if it isn't already on the watchlist, removes it if it is.
ToggleWatchlistEvent.OnServerInvoke = function(player, ticker)
	if type(ticker) ~= "string" then
		return { success = false, message = "Invalid ticker." }
	end

	local targetTicker = string.upper(ticker)

	if not MarketDataModule.isValidTicker(targetTicker) then
		return { success = false, message = "Invalid ticker." }
	end

	local playerData = _G.PlayerData[player.UserId]

	if not playerData then
		return { success = false, message = "Player data not loaded." }
	end

	playerData.Watchlist = playerData.Watchlist or {}

	local existingIndex = table.find(playerData.Watchlist, targetTicker)

	if existingIndex then
		table.remove(playerData.Watchlist, existingIndex)

		return { success = true, added = false, ticker = targetTicker, watchlist = playerData.Watchlist }
	end

	if #playerData.Watchlist >= WATCHLIST_CAP then
		return { success = false, message = "Watchlist is full (max " .. WATCHLIST_CAP .. ")." }
	end

	table.insert(playerData.Watchlist, targetTicker)

	return { success = true, added = true, ticker = targetTicker, watchlist = playerData.Watchlist }
end
