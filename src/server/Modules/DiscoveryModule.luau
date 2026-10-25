-- DiscoveryModule.luau
--
-- The rules behind asset discovery (GDD §2: what players watch and trade),
-- kept free of Roblox services so the Lune tests can run them.
-- DiscoveryService keeps the counts.

local DiscoveryModule = {}

local DAY = 86400

-- "2026-10-25": the UTC day whose trade counts a fill goes into
function DiscoveryModule.dayKey(now: number): string
	return os.date("!%Y-%m-%d", now)
end

-- Today's and yesterday's keys, the window trending covers
function DiscoveryModule.windowKeys(now: number): { string }
	return { DiscoveryModule.dayKey(now), DiscoveryModule.dayKey(now - DAY) }
end

-- Sums { [ticker] = count } maps into a list sorted by count, most first
-- (ties by ticker), up to `limit`
function DiscoveryModule.rank(countMaps, limit: number)
	local totals = {}

	for _, counts in ipairs(countMaps) do
		for ticker, count in pairs(counts) do
			totals[ticker] = (totals[ticker] or 0) + count
		end
	end

	local ranked = {}

	for ticker, count in pairs(totals) do
		if count > 0 then
			table.insert(ranked, { ticker = ticker, trades = count })
		end
	end

	table.sort(ranked, function(a, b)
		if a.trades ~= b.trades then
			return a.trades > b.trades
		end

		return a.ticker < b.ticker
	end)

	while #ranked > limit do
		table.remove(ranked)
	end

	return ranked
end

-- Which watches still need counting (on the watchlist, not yet counted) and
-- which need uncounting (counted, no longer watched). `counted` is a set.
function DiscoveryModule.reconcileWatches(watchlist, counted)
	local toAdd, toRemove = {}, {}
	local watched = {}

	for _, ticker in ipairs(watchlist) do
		watched[ticker] = true

		if not counted[ticker] then
			table.insert(toAdd, ticker)
		end
	end

	for ticker in pairs(counted) do
		if not watched[ticker] then
			table.insert(toRemove, ticker)
		end
	end

	table.sort(toAdd)
	table.sort(toRemove)

	return toAdd, toRemove
end

return DiscoveryModule
