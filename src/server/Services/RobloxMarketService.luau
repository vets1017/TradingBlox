-- RobloxMarketService.luau
--
-- The Roblox market (GDD §6). Every five minutes one game server - whichever
-- claims the tick first - fetches the listed experiences' public stats
-- through the backend, steps every simulated price (RobloxPriceModule) and
-- saves the result. Every server reads that one saved state, so prices agree
-- everywhere; they move only while some game server is running
-- (TECHNICAL-PLAN "Phase 3 decisions").
--
-- DataStore RobloxMarket_v1:
--   "state"            { lastTickAt, experiences = { [ticker] = state } }
--   "history:<ticker>" price points { { time, price } }, oldest first
--
-- MarketDataModule routes Roblox tickers' quotes and candles here.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RobloxMarket = require(ReplicatedStorage.Config.RobloxMarket)
local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local RobloxPriceModule = require(ServerScriptService.Modules.RobloxPriceModule)

local Store = DataStoreService:GetDataStore("RobloxMarket_v1")

local TICK_SECONDS = 300
local CHECK_INTERVAL = 60 -- how often each server looks for a due tick
local STATE_CACHE_SECONDS = 60
local HISTORY_CACHE_SECONDS = 300
local LIVE_CANDLES = 5 -- what a "live" candle request returns, like the backend's

-- Chart timeframes: candle size and how far back, like the backend's
-- Yahoo candles. History has five-minute points at most, so 1M charts get
-- five-minute candles.
local TIMEFRAMES = {
	["1M"] = { interval = 300, lookback = 7 * 86400 },
	["5M"] = { interval = 300, lookback = 7 * 86400 },
	["30M"] = { interval = 1800, lookback = 7 * 86400 },
	["H"] = { interval = 3600, lookback = 60 * 86400 },
	["D"] = { interval = 86400, lookback = 730 * 86400 },
}

local market = nil -- the saved state as last read or written
local marketReadAt = -math.huge
local isReading = false
local isTicking = false
local historyCache = {} -- [ticker] = { fetchedAt = os.clock(), points }

local RobloxMarketService = {}

local function readMarket()
	isReading = true

	local success, saved = pcall(Store.GetAsync, Store, "state")

	isReading = false

	if not success then
		warn("[RobloxMarketService] Couldn't read the market: " .. tostring(saved))

		return
	end

	market = saved
	marketReadAt = os.clock()
end

-- The saved state, re-read at most once a minute; nil before the first tick
local function getMarket()
	if os.clock() - marketReadAt >= STATE_CACHE_SECONDS and not isReading then
		readMarket()
	end

	return market
end

local function getUniverseIds()
	local ids = {}

	for _, experience in ipairs(RobloxMarket.EXPERIENCES) do
		table.insert(ids, experience.universeId)
	end

	return ids
end

local function appendHistory(ticker: string, time: number, price: number)
	local success, points = pcall(Store.UpdateAsync, Store, "history:" .. ticker, function(stored)
		return RobloxPriceModule.addPoint(stored or {}, time, price)
	end)

	if success then
		historyCache[ticker] = { fetchedAt = os.clock(), points = points }
	else
		warn("[RobloxMarketService] Couldn't save the history of " .. ticker .. ": " .. tostring(points))
	end
end

-- Steps the market if a tick is due and no other server has claimed it
local function runTick()
	local current = getMarket()

	if current and os.time() - current.lastTickAt < TICK_SECONDS then
		return
	end

	local statsById, err = MarketDataModule.getRobloxExperiences(getUniverseIds())

	if not statsById then
		warn("[RobloxMarketService] Couldn't fetch experience stats: " .. tostring(err))

		return
	end

	local claimed = false
	local success, saved = pcall(Store.UpdateAsync, Store, "state", function(stored)
		local now = os.time()

		-- Another server ticked while this one fetched; nil leaves its state
		if stored and now - stored.lastTickAt < TICK_SECONDS then
			claimed = false

			return nil
		end

		claimed = true

		return RobloxPriceModule.tickMarket(stored, RobloxMarket.EXPERIENCES, statsById, now)
	end)

	if not success then
		warn("[RobloxMarketService] Couldn't save a tick: " .. tostring(saved))

		return
	end

	if not claimed or not saved then
		-- Pick up the other server's tick
		marketReadAt = -math.huge

		return
	end

	market = saved
	marketReadAt = os.clock()

	for ticker, experience in pairs(saved.experiences) do
		if not experience.delisted then
			appendHistory(ticker, saved.lastTickAt, experience.price)
		end
	end
end

local function getHistory(ticker: string)
	local cached = historyCache[ticker]

	if cached and os.clock() - cached.fetchedAt < HISTORY_CACHE_SECONDS then
		return cached.points
	end

	local success, points = pcall(Store.GetAsync, Store, "history:" .. ticker)

	if not success then
		warn("[RobloxMarketService] Couldn't read the history of " .. ticker .. ": " .. tostring(points))

		return cached and cached.points
	end

	historyCache[ticker] = { fetchedAt = os.clock(), points = points or {} }

	return points or {}
end

-- One experience's saved state, or nil if it isn't (or isn't yet) on the market
function RobloxMarketService.getExperienceState(ticker: string)
	local current = getMarket()

	return current and current.experiences[ticker]
end

-- A quote in MarketDataModule's shape, or nil for a delisted or unknown
-- ticker. No bid or ask, so fills use the price; `time` is the last tick,
-- so FillPriceModule refuses a price that's stopped updating.
function RobloxMarketService.getQuote(ticker: string)
	local experience = RobloxMarketService.getExperienceState(ticker)

	if not experience or experience.delisted then
		return nil
	end

	return {
		price = experience.price,
		prevClose = experience.prevClose,
		time = market.lastTickAt,
		marketState = "REGULAR",
	}
end

-- Candles in the chart's shape from the price history; a "live" request gets
-- the last few, like the backend's
function RobloxMarketService.getCandles(ticker: string, timeframe: string, mode: string?)
	local frame = TIMEFRAMES[timeframe]

	if not frame then
		return nil, "Invalid timeframe"
	end

	if not RobloxMarketService.getExperienceState(ticker) then
		return nil, "Not on the Roblox market"
	end

	local points = getHistory(ticker)

	if not points then
		return nil, "Price history unavailable"
	end

	local candles = RobloxPriceModule.buildCandles(points, frame.interval, os.time() - frame.lookback)

	if mode == "live" then
		return table.move(candles, math.max(#candles - LIVE_CANDLES + 1, 1), #candles, 1, {}), nil
	end

	return candles, nil
end

-- What the research view shows, or nil if the ticker isn't on the market:
-- { name, price, prevClose, delisted, lastTickAt, listedAt, target,
-- averagePlaying, observed = { playing, visits, favorites, upVotes,
-- downVotes, created, updated, genre, creator } }. `observed` is Roblox's
-- own numbers (the creator's name still needs filtering); the price, target
-- and average are ours.
function RobloxMarketService.getResearch(ticker: string)
	local experience = RobloxMarketService.getExperienceState(ticker)

	if not experience then
		return nil
	end

	local listed = RobloxMarket.getExperience(ticker)
	local stats = experience.stats

	return {
		name = listed and listed.name or ticker,
		price = experience.price,
		prevClose = experience.prevClose,
		delisted = experience.delisted == true,
		lastTickAt = market.lastTickAt,
		listedAt = experience.listedAt,
		target = experience.target,
		averagePlaying = math.round(experience.activity),
		observed = {
			playing = stats.playing,
			visits = stats.visits,
			favorites = stats.favorites,
			upVotes = stats.upVotes,
			downVotes = stats.downVotes,
			created = stats.created,
			updated = stats.updated,
			genre = stats.genre,
			creator = stats.creator,
		},
	}
end

-- Every listed experience's price for browsing:
-- { { ticker, name, price, prevClose, playing } }, most players first
function RobloxMarketService.getListing()
	local current = getMarket()
	local rows = {}

	for _, listed in ipairs(RobloxMarket.EXPERIENCES) do
		local experience = current and current.experiences[listed.ticker]

		if experience and not experience.delisted then
			table.insert(rows, {
				ticker = listed.ticker,
				name = listed.name,
				price = experience.price,
				prevClose = experience.prevClose,
				playing = experience.stats.playing,
			})
		end
	end

	table.sort(rows, function(a, b)
		return a.playing > b.playing
	end)

	return rows
end

function RobloxMarketService.start()
	MarketDataModule.setRobloxProvider(RobloxMarketService)

	task.spawn(function()
		while true do
			if not isTicking then
				isTicking = true

				local ok, err = pcall(runTick)

				isTicking = false

				if not ok then
					warn("[RobloxMarketService] Tick failed: " .. tostring(err))
				end
			end

			task.wait(CHECK_INTERVAL)
		end
	end)
end

return RobloxMarketService
