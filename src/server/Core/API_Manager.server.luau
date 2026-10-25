-- API_Manager.server.luau
--
-- Middleman API

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local ProgressionService = require(ServerScriptService.Services.ProgressionService)
local Progression = require(ReplicatedStorage.Config.Progression)

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local RequestChartEvent = EventsFolder:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = EventsFolder:WaitForChild("GetMarketDataEvent")
local GetMarketOverviewEvent = EventsFolder:WaitForChild("GetMarketOverviewEvent")
local GetMarketMoversEvent = EventsFolder:WaitForChild("GetMarketMoversEvent")
local GetNewsFeedEvent = EventsFolder:WaitForChild("GetNewsFeedEvent")
local GetAnalystReportEvent = EventsFolder:WaitForChild("GetAnalystReportEvent")
local GetFundamentalsEvent = EventsFolder:WaitForChild("GetFundamentalsEvent")
local GetOptionStatsEvent = EventsFolder:WaitForChild("GetOptionStatsEvent")
local GetOptionsDataEvent = EventsFolder:WaitForChild("GetOptionsDataEvent")

-- Config
local PLAYER_COOLDOWN = 1
local VALID_TIMEFRAMES = { ["1M"] = true, ["5M"] = true, ["30M"] = true, ["H"] = true, ["D"] = true }

-- State
local PlayerLastRequest = {} -- [UserId] = { [remoteName] = os.time() }

-- Per-remote: switching tabs hits a different remote each time, so one tab's
-- fetch must not throttle the next tab's first fetch.
local function isThrottled(player, remoteName)
	local now = os.time()
	local perRemote = PlayerLastRequest[player.UserId]

	if not perRemote then
		perRemote = {}
		PlayerLastRequest[player.UserId] = perRemote
	end

	if (now - (perRemote[remoteName] or 0)) < PLAYER_COOLDOWN then
		return true
	end

	perRemote[remoteName] = now

	return false
end

-- The "no data" shape the research tabs already render, carrying the
-- unlock message; nil when the player has the feature
local function getLockedResponse(player, feature)
	if ProgressionService.hasFeature(player, feature) then
		return nil
	end

	return { available = false, locked = true, message = Progression.getLockedMessage(feature) }
end

--

-- RequestChartEvent
RequestChartEvent.OnServerInvoke = function(player, ticker, timeframe, mode)
	if isThrottled(player, "RequestChartEvent") then
		return nil
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	if not VALID_TIMEFRAMES[timeframe] then
		warn(string.format("[API_Manager] Invalid timeframe from %s: %s", player.Name, tostring(timeframe)))

		return nil
	end

	local targetTicker = string.upper(ticker)
	local data, err = MarketDataModule.getCandles(targetTicker, timeframe, mode)

	if not data then
		warn(string.format("[API_Manager] Chart fetch failed for %s (%s): %s", targetTicker, timeframe, tostring(err)))

		return nil
	end

	return data
end

-- GetMarketDataEvent
-- Returns a quote ({ ticker, price, prevClose }) for the given ticker, merged
-- with quote-details fields (bid/ask, volume, market cap, etc.) when available.
GetMarketDataEvent.OnServerInvoke = function(player, ticker)
	if not ticker then
		return nil
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local quote = MarketDataModule.getQuote(ticker)

	if not quote then
		warn(string.format("[API_Manager] Quote fetch failed for %s", string.upper(ticker)))

		return nil
	end

	local details, detailsErr = MarketDataModule.getQuoteDetails(ticker)

	if not details then
		warn(string.format("[API_Manager] Quote details fetch failed for %s: %s", string.upper(ticker), tostring(detailsErr)))
	end

	if details then
		for key, value in pairs(details) do
			quote[key] = value
		end
	end

	return quote
end

-- GetOptionsDataEvent
GetOptionsDataEvent.OnServerInvoke = function(player, ticker)
	if isThrottled(player, "GetOptionsDataEvent") then
		return nil
	end

	local locked = getLockedResponse(player, "Options")

	if locked then
		return locked
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local chain, err = MarketDataModule.getOptionChain(ticker)

	if not chain then
		warn(string.format("[API_Manager] Option chain fetch failed for %s: %s", string.upper(ticker), tostring(err)))
	end

	return chain
end

-- GetAnalystReportEvent
GetAnalystReportEvent.OnServerInvoke = function(player, ticker)
	if isThrottled(player, "GetAnalystReportEvent") then
		return nil
	end

	local locked = getLockedResponse(player, "Fundamentals")

	if locked then
		return locked
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local report, err = MarketDataModule.getAnalystReport(ticker)

	if not report then
		warn(string.format("[API_Manager] Analyst report fetch failed for %s: %s", string.upper(ticker), tostring(err)))
	end

	return report
end

-- GetFundamentalsEvent
GetFundamentalsEvent.OnServerInvoke = function(player, ticker)
	if isThrottled(player, "GetFundamentalsEvent") then
		return nil
	end

	local locked = getLockedResponse(player, "Fundamentals")

	if locked then
		return locked
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local fundamentals, err = MarketDataModule.getFundamentals(ticker)

	if not fundamentals then
		warn(string.format("[API_Manager] Fundamentals fetch failed for %s: %s", string.upper(ticker), tostring(err)))
	end

	return fundamentals
end

-- GetOptionStatsEvent
GetOptionStatsEvent.OnServerInvoke = function(player, ticker)
	if isThrottled(player, "GetOptionStatsEvent") then
		return nil
	end

	local locked = getLockedResponse(player, "Options")

	if locked then
		return locked
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local stats, err = MarketDataModule.getOptionStats(ticker)

	if not stats then
		warn(string.format("[API_Manager] Option stats fetch failed for %s: %s", string.upper(ticker), tostring(err)))
	end

	return stats
end

-- Text from outside Roblox (headlines, company names) has to pass Roblox's
-- filter before a player sees it. It reads the same for everyone, so each
-- string is filtered once per server and the result reused.
local FILTER_CACHE_LIMIT = 2000

local filteredText = {} -- [original] = filtered
local filteredTextCount = 0

-- The filtered string, or nil if it can't be filtered: unfiltered external
-- text is never shown
local function filterExternalText(text, player)
	if type(text) ~= "string" or text == "" then
		return nil
	end

	if filteredText[text] then
		return filteredText[text]
	end

	local success, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId):GetNonChatStringForBroadcastAsync()
	end)

	if not success then
		warn("[API_Manager] Couldn't filter external text: " .. tostring(result))

		return nil
	end

	if filteredTextCount >= FILTER_CACHE_LIMIT then
		table.clear(filteredText)
		filteredTextCount = 0
	end

	filteredText[text] = result
	filteredTextCount += 1

	return result
end

-- GetNewsFeedEvent
-- Up to 10 recent headlines for a ticker: { { title, publisher, publishedAt } }.
-- Links are dropped: players can't open outside links from a game.
GetNewsFeedEvent.OnServerInvoke = function(player, ticker)
	if isThrottled(player, "GetNewsFeedEvent") then
		return nil
	end

	if not MarketDataModule.isValidTicker(ticker) then
		return nil
	end

	local news, err = MarketDataModule.getNews(ticker)

	if not news then
		warn(string.format("[API_Manager] News fetch failed for %s: %s", string.upper(ticker), tostring(err)))

		return nil
	end

	local items = {}

	for _, item in ipairs(news.items or {}) do
		local title = filterExternalText(item.title, player)

		if title then
			table.insert(items, {
				title = title,
				publisher = filterExternalText(item.publisher, player),
				publishedAt = item.publishedAt,
			})
		end
	end

	return items
end

-- GetMarketMoversEvent
-- Today's top gainers, losers and most active stocks, 10 each:
-- { gainers, losers, active } of { symbol, name, price, changePercent }.
-- Cached a few minutes by MarketDataModule, so players share one fetch.
GetMarketMoversEvent.OnServerInvoke = function(player)
	if isThrottled(player, "GetMarketMoversEvent") then
		return nil
	end

	local movers, err = MarketDataModule.getMovers()

	if not movers then
		warn("[API_Manager] Movers fetch failed: " .. tostring(err))

		return nil
	end

	local result = {}

	for _, list in ipairs({ "gainers", "losers", "active" }) do
		result[list] = {}

		for _, quote in ipairs(movers[list] or {}) do
			-- Tickers are checked like any other; company names are outside text
			if MarketDataModule.isValidTicker(quote.symbol) then
				table.insert(result[list], {
					symbol = quote.symbol,
					name = filterExternalText(quote.name, player) or quote.symbol,
					price = quote.price,
					changePercent = quote.changePercent,
				})
			end
		end
	end

	return result
end

-- GetMarketOverviewEvent
-- The Dashboard's market overview: a fixed set of benchmarks, fetched once a
-- minute per server however many players are looking. Returns
-- { quotes = { ticker, name, price, change, changePct }, updatedAt }.
local MARKET_OVERVIEW = {
	{ ticker = "SPY", name = "S&P 500" },
	{ ticker = "QQQ", name = "Nasdaq 100" },
	{ ticker = "DIA", name = "Dow 30" },
	{ ticker = "IWM", name = "Russell 2000" },
	{ ticker = "BTC-USD", name = "Bitcoin" },
	{ ticker = "ETH-USD", name = "Ethereum" },
}
local MARKET_OVERVIEW_CACHE_SECONDS = 60

local marketOverview = nil -- { quotes, updatedAt, fetchedAt = os.clock() }
local isFetchingMarketOverview = false

local function fetchMarketOverview()
	local quotes = {}

	for _, benchmark in ipairs(MARKET_OVERVIEW) do
		local quote = MarketDataModule.getQuote(benchmark.ticker)
		local change = quote and quote.price - quote.prevClose

		table.insert(quotes, {
			ticker = benchmark.ticker,
			name = benchmark.name,
			price = quote and quote.price,
			change = change,
			changePct = (change and quote.prevClose ~= 0) and (change / quote.prevClose * 100) or nil,
		})
	end

	return { quotes = quotes, updatedAt = os.time(), fetchedAt = os.clock() }
end

GetMarketOverviewEvent.OnServerInvoke = function()
	while isFetchingMarketOverview do
		task.wait()
	end

	if not marketOverview or os.clock() - marketOverview.fetchedAt >= MARKET_OVERVIEW_CACHE_SECONDS then
		isFetchingMarketOverview = true
		marketOverview = fetchMarketOverview()
		isFetchingMarketOverview = false
	end

	return { quotes = marketOverview.quotes, updatedAt = marketOverview.updatedAt }
end

-- Clean up
Players.PlayerRemoving:Connect(function(player)
	PlayerLastRequest[player.UserId] = nil
end)
