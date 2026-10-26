-- RobloxMarketService.luau
--
-- The Roblox market (GDD §6). Every minute one game server - whichever
-- claims the tick first - fetches the listed experiences' public stats
-- through the backend, steps every simulated price (RobloxPriceModule) and
-- saves the result. Every server reads the same saved prices, so they agree
-- everywhere; they move only while some game server is running
-- (TECHNICAL-PLAN "Phase 3 decisions").
--
-- DataStore RobloxMarket_v1:
--   "tick"             when the last tick was claimed; moving it claims the next
--   "state"            the whole market (RobloxPriceModule.tickMarket), read
--                      and written only by the server ticking it
--   "prices"           its publicView: small, and what every server reads
--   "history:<ticker>" price points { { time, close, high?, low? } }, oldest
--                      first, written in five-minute batches
--
-- MarketDataModule routes Roblox tickers' quotes and candles here.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RobloxMarket = require(ReplicatedStorage.Config.RobloxMarket)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local RobloxPriceModule = require(ServerScriptService.Modules.RobloxPriceModule)

local Store = DataStoreService:GetDataStore("RobloxMarket_v1")

local TICK_SECONDS = 60
local CHECK_INTERVAL = 5 -- how often each server looks for a due tick
local PRICES_CACHE_SECONDS = 20
-- A chart's history may be this stale; the prices' recent points (15
-- minutes) cover it plus the five minutes between history writes
local HISTORY_CACHE_SECONDS = 300
local LIVE_CANDLES = 5 -- what a "live" candle request returns, like the backend's
local BUDGET_RESERVE = 10 -- UpdateAsync requests history writes leave for player data

-- Chart timeframes: candle size and how far back. History keeps every
-- minute for a day, five-minute points for a week, hourly ones for 90 days.
local TIMEFRAMES = {
	["1M"] = { interval = 60, lookback = 86400 },
	["5M"] = { interval = 300, lookback = 7 * 86400 },
	["30M"] = { interval = 1800, lookback = 7 * 86400 },
	["H"] = { interval = 3600, lookback = 60 * 86400 },
	["D"] = { interval = 86400, lookback = 730 * 86400 },
}

local market = nil -- the "prices" view as last read or written
local marketReadAt = -math.huge
local isReading = false
local isTicking = false
local nextClaimAt = 0 -- os.time() before which another server has the tick
local historyCache = {} -- [ticker] = { fetchedAt = os.clock(), points }
local noiseRandom = Random.new() -- moves the prices' noise; saved prices make every server agree

local RobloxMarketService = {}

local function nextRandom(): number
	return noiseRandom:NextNumber()
end

local function noteTick(lastTickAt: number)
	nextClaimAt = math.max(nextClaimAt, lastTickAt + TICK_SECONDS)
end

local function readPrices()
	isReading = true

	local success, saved = pcall(Store.GetAsync, Store, "prices")

	isReading = false

	if not success then
		warn("[RobloxMarketService] Couldn't read the prices: " .. tostring(saved))

		return
	end

	market = saved
	marketReadAt = os.clock()

	if saved then
		noteTick(saved.lastTickAt)
	end
end

-- The prices, re-read every PRICES_CACHE_SECONDS; nil before the first tick
local function getMarket()
	if os.clock() - marketReadAt >= PRICES_CACHE_SECONDS and not isReading then
		readPrices()
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

local function waitForBudget()
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < BUDGET_RESERVE do
		task.wait(1)
	end
end

-- Adds a flush's points to each ticker's history. Runs on its own thread:
-- fifty writes can take a while when the request budget is low.
local function writeHistory(flush)
	for ticker, points in pairs(flush) do
		waitForBudget()

		local success, saved = pcall(Store.UpdateAsync, Store, "history:" .. ticker, function(stored)
			return RobloxPriceModule.addPoints(stored or {}, points, os.time())
		end)

		if success then
			historyCache[ticker] = { fetchedAt = os.clock(), points = saved }
		else
			warn("[RobloxMarketService] Couldn't save the history of " .. ticker .. ": " .. tostring(saved))
		end
	end
end

-- Moves "tick" to now if the last tick is a minute old; true if this
-- server got it
local function claimTick(): boolean
	local claimed = false
	local success, result = pcall(Store.UpdateAsync, Store, "tick", function(lastTickAt)
		local now = os.time()

		if lastTickAt and now - lastTickAt < TICK_SECONDS then
			claimed = false
			noteTick(lastTickAt)

			-- nil leaves it as it is
			return nil
		end

		claimed = true

		return now
	end)

	if not success then
		warn("[RobloxMarketService] Couldn't claim a tick: " .. tostring(result))

		return false
	end

	if claimed then
		noteTick(result)
	end

	return claimed
end

-- Steps the market if a tick is due and this server claims it
local function runTick()
	getMarket()

	if os.time() < nextClaimAt or not claimTick() then
		return
	end

	local statsById, err = MarketDataModule.getRobloxExperiences(getUniverseIds())

	if not statsById then
		warn("[RobloxMarketService] Couldn't fetch experience stats: " .. tostring(err))

		return
	end

	local flush = nil
	local success, saved = pcall(Store.UpdateAsync, Store, "state", function(stored)
		local nextMarket, due =
			RobloxPriceModule.tickMarket(stored, RobloxMarket.EXPERIENCES, statsById, os.time(), nextRandom)

		-- The last call's is the one saved
		flush = due

		return nextMarket
	end)

	if not success then
		warn("[RobloxMarketService] Couldn't save a tick: " .. tostring(saved))

		return
	end

	local view = RobloxPriceModule.publicView(saved)
	local published, publishErr = pcall(Store.SetAsync, Store, "prices", view)

	if not published then
		warn("[RobloxMarketService] Couldn't publish the prices: " .. tostring(publishErr))
	end

	market = view
	marketReadAt = os.clock()

	if flush then
		task.spawn(writeHistory, flush)
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

-- One experience's published state ({ price, prevClose, target, activity,
-- listedAt, opensAt, delisted, stats, recent }), or nil if it isn't (or
-- isn't yet) on the market
function RobloxMarketService.getExperienceState(ticker: string)
	local current = getMarket()

	return current and current.experiences[ticker]
end

-- When a listed experience that's still warming up opens for trading, or nil
local function getOpensAt(experience): number?
	if experience.delisted or RobloxPriceModule.isOpen(experience, os.time()) then
		return nil
	end

	return experience.opensAt
end

-- Why `ticker` can't be traded right now, or nil if it can
function RobloxMarketService.getClosedReason(ticker: string): string?
	local experience = RobloxMarketService.getExperienceState(ticker)
	local listed = RobloxMarket.getExperience(ticker)
	local name = listed and listed.name or ticker

	if not experience then
		return name .. " isn't on the market yet."
	elseif experience.delisted then
		return name .. " was delisted."
	end

	local opensAt = getOpensAt(experience)

	if opensAt then
		return string.format(
			"%s opens for trading in %s.",
			name,
			MarketHoursModule.formatCountdown(opensAt - os.time())
		)
	end

	return nil
end

-- A quote in MarketDataModule's shape, or nil while it can't be traded
-- (warming up, delisted or unknown). No bid or ask, so fills use the price;
-- `time` is the last tick, so FillPriceModule refuses a price that's
-- stopped updating.
function RobloxMarketService.getQuote(ticker: string)
	local experience = RobloxMarketService.getExperienceState(ticker)

	if not experience or RobloxMarketService.getClosedReason(ticker) then
		return nil
	end

	return {
		price = experience.price,
		prevClose = experience.prevClose,
		time = market.lastTickAt,
		marketState = "REGULAR",
	}
end

-- Candles in the chart's shape from the price history and the latest
-- minutes' points; a "live" request gets the last few, like the backend's
function RobloxMarketService.getCandles(ticker: string, timeframe: string, mode: string?)
	local frame = TIMEFRAMES[timeframe]

	if not frame then
		return nil, "Invalid timeframe"
	end

	local experience = RobloxMarketService.getExperienceState(ticker)

	if not experience then
		return nil, "Not on the Roblox market"
	end

	local points = getHistory(ticker)

	if not points then
		return nil, "Price history unavailable"
	end

	points = RobloxPriceModule.withRecent(points, experience.recent)

	local candles = RobloxPriceModule.buildCandles(points, frame.interval, os.time() - frame.lookback)

	if mode == "live" then
		return table.move(candles, math.max(#candles - LIVE_CANDLES + 1, 1), #candles, 1, {}), nil
	end

	return candles, nil
end

-- What the research view shows, or nil if the ticker isn't on the market:
-- { name, price, prevClose, delisted, opensAt?, lastTickAt, listedAt,
-- target, averagePlaying, vsUsual?, observed = { playing, visits, favorites,
-- upVotes, downVotes, created, updated, genre, creator } }. `opensAt` is set
-- while it warms up; `vsUsual` is players now against the usual for this
-- hour of the week (0.35 is 35% more), once there's a usual. `observed` is
-- Roblox's own numbers (the creator's name still needs filtering); the
-- price, target, average and usual are ours.
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
		opensAt = getOpensAt(experience),
		lastTickAt = market.lastTickAt,
		listedAt = experience.listedAt,
		target = experience.target,
		averagePlaying = experience.activity,
		vsUsual = if experience.usual and experience.usual > 0 then stats.playing / experience.usual - 1 else nil,
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
-- { { ticker, name, price, prevClose, playing, opensAt? } }, most players
-- first; `opensAt` is set while it warms up
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
				opensAt = getOpensAt(experience),
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
