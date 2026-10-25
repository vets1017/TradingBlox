-- DiscoveryService.luau
--
-- Asset discovery from in-game signals (GDD §2): how many players watch a
-- ticker and how often it's traded, and the most traded and most watched
-- tickers. Counts live in OrderedDataStores so any server can rank them:
-- Watchers_v1 (current watchers per ticker) and TickerTrades_<UTC day>
-- (that day's fills by every player; only totals are ever shown). Each
-- server adds up its fills and writes them once a minute rather than on
-- every fill. Popularity is shown beside market data, never as advice.

local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local OrderEvents = require(ServerScriptService.Services.OrderEvents)
local DiscoveryModule = require(ServerScriptService.Modules.DiscoveryModule)

local WatcherStore = DataStoreService:GetOrderedDataStore("Watchers_v1")

local FLUSH_INTERVAL = 60
local STATS_CACHE_SECONDS = 60
-- Ranked reads have a small budget (5 + 2 per player a minute, shared with
-- the leaderboards), so the trending lists are read at most every two minutes
local TRENDING_CACHE_SECONDS = 120
local TRENDING_SIZE = 10
local TRENDING_PAGE = 25 -- read from each day's ranking before merging the two

local pendingTrades = {} -- [ticker] = fills on this server not written yet
local statsCache = {} -- [ticker] = { fetchedAt = os.clock(), stats }
local trendingCache = nil -- { fetchedAt = os.clock(), trending }
-- Weak keys, so a player who has left drops out on their own
local isSyncing = setmetatable({}, { __mode = "k" }) -- [player] = true while watcher counts save
local needsResync = setmetatable({}, { __mode = "k" })

local DiscoveryService = {}

local function getTradeStore(dayKey: string)
	return DataStoreService:GetOrderedDataStore("TickerTrades_" .. dayKey)
end

-- Never below zero, even if a count was lost along the way
local function adjustWatchers(ticker: string, delta: number): boolean
	local success, err = pcall(WatcherStore.UpdateAsync, WatcherStore, ticker, function(count)
		return math.max((count or 0) + delta, 0)
	end)

	if not success then
		warn("[DiscoveryService] Couldn't update the watchers of " .. ticker .. ": " .. tostring(err))

		return false
	end

	statsCache[ticker] = nil

	return true
end

local function syncOnce(player)
	local data = PlayerDataService.get(player)

	if not data then
		return
	end

	local toAdd, toRemove = DiscoveryModule.reconcileWatches(data.Watchlist, data.Social.CountedWatches)

	for _, ticker in ipairs(toAdd) do
		if adjustWatchers(ticker, 1) then
			data = PlayerDataService.get(player)

			if not data then
				return
			end

			data.Social.CountedWatches[ticker] = true
		end
	end

	for _, ticker in ipairs(toRemove) do
		if adjustWatchers(ticker, -1) then
			data = PlayerDataService.get(player)

			if not data then
				return
			end

			data.Social.CountedWatches[ticker] = nil
		end
	end
end

-- Brings the watcher counts in line with the player's watchlist, counting
-- new watches and uncounting dropped ones. The profile records which are
-- counted, so a watch is never counted twice and old watchlists are counted
-- at login. Yields; changes made meanwhile are picked up by another pass.
function DiscoveryService.syncWatches(player)
	if isSyncing[player] then
		needsResync[player] = true

		return
	end

	isSyncing[player] = true

	repeat
		needsResync[player] = nil

		local ok, err = pcall(syncOnce, player)

		if not ok then
			warn("[DiscoveryService] Watch sync failed for " .. player.Name .. ": " .. tostring(err))
		end
	until not needsResync[player]

	isSyncing[player] = nil
end

local function flushTrades()
	if next(pendingTrades) == nil then
		return
	end

	local batch = pendingTrades
	local store = getTradeStore(DiscoveryModule.dayKey(os.time()))

	pendingTrades = {}

	for ticker, count in pairs(batch) do
		local success, err = pcall(store.IncrementAsync, store, ticker, count)

		if not success then
			warn("[DiscoveryService] Couldn't save trade counts for " .. ticker .. ": " .. tostring(err))
			-- Tried again next flush
			pendingTrades[ticker] = (pendingTrades[ticker] or 0) + count
		end
	end
end

-- { watchers, trades } for one ticker: current watchers, and fills over
-- today and yesterday (UTC). Cached a minute; a field is nil when it can't
-- be read.
function DiscoveryService.getTickerStats(ticker: string)
	local cached = statsCache[ticker]

	if cached and os.clock() - cached.fetchedAt < STATS_CACHE_SECONDS then
		return cached.stats
	end

	local stats = {}
	local watchersOk, watchers = pcall(WatcherStore.GetAsync, WatcherStore, ticker)

	stats.watchers = if watchersOk then watchers or 0 else nil

	local trades = pendingTrades[ticker] or 0

	for _, dayKey in ipairs(DiscoveryModule.windowKeys(os.time())) do
		local store = getTradeStore(dayKey)
		local dayOk, count = pcall(store.GetAsync, store, ticker)

		if not dayOk then
			trades = nil

			break
		end

		trades += count or 0
	end

	stats.trades = trades
	statsCache[ticker] = { fetchedAt = os.clock(), stats = stats }

	return stats
end

local function readRanking(store, size: number)
	local success, pages = pcall(store.GetSortedAsync, store, false, size)

	if not success then
		warn("[DiscoveryService] Couldn't read a ranking: " .. tostring(pages))

		return nil
	end

	local counts = {}

	for _, entry in ipairs(pages:GetCurrentPage()) do
		counts[entry.key] = entry.value
	end

	return counts
end

-- { traded = { { ticker, trades } }, watched = { { ticker, watchers } } }:
-- the most traded tickers over today and yesterday (UTC) and the most
-- watched, up to TRENDING_SIZE each. Cached two minutes; the last good
-- copy, or nil, when the rankings can't be read.
function DiscoveryService.getTrending()
	if trendingCache and os.clock() - trendingCache.fetchedAt < TRENDING_CACHE_SECONDS then
		return trendingCache.trending
	end

	local countMaps = { table.clone(pendingTrades) }

	for _, dayKey in ipairs(DiscoveryModule.windowKeys(os.time())) do
		local counts = readRanking(getTradeStore(dayKey), TRENDING_PAGE)

		if not counts then
			return trendingCache and trendingCache.trending
		end

		table.insert(countMaps, counts)
	end

	local watcherCounts = readRanking(WatcherStore, TRENDING_SIZE)

	if not watcherCounts then
		return trendingCache and trendingCache.trending
	end

	local watched = {}

	for _, entry in ipairs(DiscoveryModule.rank({ watcherCounts }, TRENDING_SIZE)) do
		table.insert(watched, { ticker = entry.ticker, watchers = entry.trades })
	end

	local trending = { traded = DiscoveryModule.rank(countMaps, TRENDING_SIZE), watched = watched }

	trendingCache = { fetchedAt = os.clock(), trending = trending }

	return trending
end

-- Must run before PlayerDataService.start so no PlayerLoaded is missed
function DiscoveryService.start()
	OrderEvents.Filled:Connect(function(_player, _realizedPL, _now, fill)
		-- An option counts toward its underlying
		if fill and fill.ticker then
			pendingTrades[fill.ticker] = (pendingTrades[fill.ticker] or 0) + 1
		end
	end)

	PlayerDataService.PlayerLoaded:Connect(function(player)
		task.spawn(DiscoveryService.syncWatches, player)
	end)

	game:BindToClose(flushTrades)

	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			flushTrades()

			for ticker, cached in pairs(statsCache) do
				if os.clock() - cached.fetchedAt > STATS_CACHE_SECONDS then
					statsCache[ticker] = nil
				end
			end
		end
	end)
end

return DiscoveryService
