-- API_Manager.server.luau
--
-- Middleman API

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local ProgressionService = require(ServerScriptService.Services.ProgressionService)
local RobloxMarketService = require(ServerScriptService.Services.RobloxMarketService)
local RemoteGuard = require(ServerScriptService.Modules.RemoteGuard)
local Progression = require(ReplicatedStorage.Config.Progression)
local Instruments = require(ReplicatedStorage.Config.Instruments)

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
local GetRobloxMarketEvent = EventsFolder:WaitForChild("GetRobloxMarketEvent")

-- Config
local VALID_TIMEFRAMES = { ["1M"] = true, ["5M"] = true, ["30M"] = true, ["H"] = true, ["D"] = true }

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
RemoteGuard.handle(RequestChartEvent, RemoteGuard.LIMITS.Poll, function(player, ticker, timeframe, mode)
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
end)

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

-- A Roblox-market experience for the Trade screen: RobloxMarketService's
-- research ({ name, price, prevClose, observed, averagePlaying, target, ... })
-- plus { ticker, assetClass = "roblox", companyName }, or nil if it isn't on
-- the market (yet). The creator's name comes from Roblox, so it's filtered.
local function getRobloxMarketData(player, ticker)
	local research = RobloxMarketService.getResearch(ticker)

	if not research then
		return nil
	end

	research.ticker = ticker
	research.assetClass = "roblox"
	research.companyName = research.name
	research.observed.creator = filterExternalText(research.observed.creator, player)

	return research
end

-- GetMarketDataEvent
-- Returns a quote ({ ticker, price, prevClose }) for the given ticker, merged
-- with quote-details fields (bid/ask, volume, market cap, etc.) when available.
-- A Roblox-market ticker gets its research instead (getRobloxMarketData).
RemoteGuard.handle(GetMarketDataEvent, RemoteGuard.LIMITS.Read, function(player, ticker)
	if not ticker then
		return nil
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	if Instruments.isRoblox(ticker) then
		return getRobloxMarketData(player, string.upper(ticker))
	end

	local quote = MarketDataModule.getQuote(ticker)

	if not quote then
		warn(string.format("[API_Manager] Quote fetch failed for %s", string.upper(ticker)))

		return nil
	end

	local details, detailsErr = MarketDataModule.getQuoteDetails(ticker)

	if not details then
		warn(
			string.format(
				"[API_Manager] Quote details fetch failed for %s: %s",
				string.upper(ticker),
				tostring(detailsErr)
			)
		)
	end

	if details then
		for key, value in pairs(details) do
			quote[key] = value
		end
	end

	return quote
end)

-- GetOptionsDataEvent
RemoteGuard.handle(GetOptionsDataEvent, RemoteGuard.LIMITS.Research, function(player, ticker)
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
end)

-- GetAnalystReportEvent
RemoteGuard.handle(GetAnalystReportEvent, RemoteGuard.LIMITS.Research, function(player, ticker)
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
end)

-- GetFundamentalsEvent
RemoteGuard.handle(GetFundamentalsEvent, RemoteGuard.LIMITS.Research, function(player, ticker)
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
end)

-- GetOptionStatsEvent
RemoteGuard.handle(GetOptionStatsEvent, RemoteGuard.LIMITS.Research, function(player, ticker)
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
end)

-- GetNewsFeedEvent
-- Up to 10 recent headlines for a ticker: { { title, publisher, publishedAt } }.
-- Links are dropped: players can't open outside links from a game.
RemoteGuard.handle(GetNewsFeedEvent, RemoteGuard.LIMITS.Research, function(player, ticker)
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
end)

-- GetMarketMoversEvent
-- Today's top gainers, losers and most active stocks, 10 each:
-- { gainers, losers, active } of { symbol, name, price, changePercent }.
-- Cached a few minutes by MarketDataModule, so players share one fetch.
RemoteGuard.handle(GetMarketMoversEvent, RemoteGuard.LIMITS.Research, function(player)
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
end)

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
	local tickers = {}

	for _, benchmark in ipairs(MARKET_OVERVIEW) do
		table.insert(tickers, benchmark.ticker)
	end

	MarketDataModule.getQuotes(tickers) -- all six in one request

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

RemoteGuard.handle(GetMarketOverviewEvent, RemoteGuard.LIMITS.Research, function()
	while isFetchingMarketOverview do
		task.wait()
	end

	if not marketOverview or os.clock() - marketOverview.fetchedAt >= MARKET_OVERVIEW_CACHE_SECONDS then
		isFetchingMarketOverview = true
		marketOverview = fetchMarketOverview()
		isFetchingMarketOverview = false
	end

	return { quotes = marketOverview.quotes, updatedAt = marketOverview.updatedAt }
end)

-- GetRobloxMarketEvent
-- Every listed experience for browsing: { { ticker, name, price, prevClose,
-- playing } }, most players first. Names are the game's own, not Roblox's.
RemoteGuard.handle(GetRobloxMarketEvent, RemoteGuard.LIMITS.Research, function()
	return RobloxMarketService.getListing()
end)
