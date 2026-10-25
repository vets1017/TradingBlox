-- MarketDataModule.luau
--
-- Shared market-data access: ticker validation, candle fetching/caching, and
-- price/quote derivation on top of the backend's routes (candles,
-- quote-details, analyst, fundamentals, options, option chain, news, movers,
-- profile). Used by API_Manager
-- (chart/quote remotes) and TradeSystem (trade pricing + positions) so
-- neither duplicates the HTTP fetch/cache logic.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local MarketDataModule = {}

-- Config
-- In Studio only, a "BackendUrl" attribute on ServerScriptService points the
-- game at another backend (e.g. http://localhost:3000 while developing one);
-- live servers always use the deployed backend.
local DEPLOYED_SERVER_URL = "https://tradingblox-terminal-backend.onrender.com"
local SERVER_URL = RunService:IsStudio() and ServerScriptService:GetAttribute("BackendUrl") or DEPLOYED_SERVER_URL
local CANDLES_ENDPOINT = SERVER_URL .. "/api/candles/"
local QUOTE_DETAILS_ENDPOINT = SERVER_URL .. "/api/quote-details/"
local ANALYST_ENDPOINT = SERVER_URL .. "/api/analyst/"
local FUNDAMENTALS_ENDPOINT = SERVER_URL .. "/api/fundamentals/"
local OPTIONS_ENDPOINT = SERVER_URL .. "/api/options/"
local OPTIONS_CHAIN_ENDPOINT = SERVER_URL .. "/api/option-chain/"
local NEWS_ENDPOINT = SERVER_URL .. "/api/news/"
local MOVERS_ENDPOINT = SERVER_URL .. "/api/movers"
local PROFILE_ENDPOINT = SERVER_URL .. "/api/profile/"
local QUOTES_ENDPOINT = SERVER_URL .. "/api/quotes?symbols="
local SPLITS_ENDPOINT = SERVER_URL .. "/api/splits/"

local CHART_CACHE_DURATION = 300
local QUOTE_DETAILS_CACHE_DURATION = 60
local ANALYST_CACHE_DURATION = 21600 -- 6 hours
local FUNDAMENTALS_CACHE_DURATION = 21600 -- 6 hours
local OPTION_STATS_CACHE_DURATION = 300
local OPTION_CHAIN_CACHE_DURATION = 300
local NEWS_CACHE_DURATION = 600
local MOVERS_CACHE_DURATION = 120
local PROFILE_CACHE_DURATION = 86400 -- a company's sector doesn't change
local QUOTE_CACHE_DURATION = 10 -- how old a "live" price may be
local SPLITS_CACHE_DURATION = 43200
local MAX_QUOTES_PER_REQUEST = 50 -- the backend's batch limit

-- Fills use the bid or ask only in regular trading with a sane spread;
-- otherwise (crypto, after hours, a gapped book) they use the last price
local MAX_FILL_SPREAD = 0.02 -- as a fraction of the price
-- A regular-session stock quote this old means the feed has stalled
local STALE_QUOTE_SECONDS = 15 * 60
local CACHE_SWEEP_INTERVAL = 600
local MAX_TICKER_LENGTH = 10
local VALID_TIMEFRAMES = { ["1M"] = true, ["5M"] = true, ["30M"] = true, ["H"] = true, ["D"] = true }

-- State
local ChartCache = {} -- [cacheKey] = { data = ..., lastUpdated = os.time() }
local QuoteDetailsCache = {}
local AnalystCache = {}
local FundamentalsCache = {}
local OptionStatsCache = {}
local OptionChainCache = {}
local NewsCache = {}
local MoversCache = {}
local ProfileCache = {}
local QuoteCache = {} -- [ticker] = { data = quote, lastUpdated }, filled in batches
local SplitsCache = {}

--

function MarketDataModule.isValidTicker(ticker)
	if type(ticker) ~= "string" then
		return false
	end

	if ticker == "" or #ticker > MAX_TICKER_LENGTH then
		return false
	end

	return string.match(ticker, "^[%a%d%.%-]+$") ~= nil
end

-- Crypto tickers use Yahoo Finance's "-USD" suffix convention (e.g. BTC-USD,
-- ETH-USD) and trade 24/7, so callers use this to exempt them from NYSE
-- market-hours gating.
function MarketDataModule.isCryptoTicker(ticker)
	if type(ticker) ~= "string" then
		return false
	end

	return string.match(string.upper(ticker), "^%a+%-USD$") ~= nil
end

local function buildCacheKey(ticker, timeframe, mode)
	return ticker .. "|" .. timeframe .. "|" .. tostring(mode or "")
end

local function fetchJSON(url)
	local success, response = pcall(function()
		return HttpService:GetAsync(url)
	end)

	if not success then
		return nil, tostring(response)
	end

	local decodeSuccess, decoded = pcall(function()
		return HttpService:JSONDecode(response)
	end)

	if not decodeSuccess then
		return nil, "Failed to decode JSON response"
	end

	return decoded, nil
end

-- Thin pre/post-market liquidity occasionally makes the backend emit a
-- garbage candle. Left in, it blows out a renderer's price-scale range
-- (computed as the global min/max across all candles) and shows up as a
-- full-height spike in both ChartRenderer and the mini chart - confirmed
-- live against AAPL 5M data: a single candle (Close 327.58) landed ~2.4%
-- below its neighbors (~335.55) and reverted on the very next candle. That's
-- too small a deviation for a flat percent-vs-previous-close threshold to
-- catch without also rejecting real intraday moves, so this instead flags a
-- candle whose Close jumps away from BOTH neighbors while those neighbors
-- closely match each other - the signature of one bad tick, since a real
-- price move persists into the following candle instead of snapping back.
local function isInternallyValid(candle)
	local open, high, low, close = candle.Open, candle.High, candle.Low, candle.Close

	if type(open) ~= "number" or type(high) ~= "number" or type(low) ~= "number" or type(close) ~= "number" then
		return false
	end

	if open <= 0 or high <= 0 or low <= 0 or close <= 0 then
		return false
	end

	if high < low or high < open or high < close or low > open or low > close then
		return false
	end

	return true
end

-- Isolated-spike check is only meaningful intraday. A daily candle can
-- legitimately jump away from the prior day and give it back the next (a
-- real news-driven round trip), so it's exempted rather than misflagged.
local SPIKE_DEVIATION_THRESHOLD = 0.015 -- vs. each immediate neighbor
local NEIGHBOR_AGREEMENT_THRESHOLD = 0.005 -- how close neighbors must be to trust them as the real level

local function isIsolatedSpike(prevClose, close, nextClose)
	local prevDeviation = math.abs(close - prevClose) / prevClose
	local nextDeviation = math.abs(close - nextClose) / nextClose
	local neighborAgreement = math.abs(prevClose - nextClose) / prevClose

	return prevDeviation > SPIKE_DEVIATION_THRESHOLD
		and nextDeviation > SPIKE_DEVIATION_THRESHOLD
		and neighborAgreement < NEIGHBOR_AGREEMENT_THRESHOLD
end

local function sanitizeCandles(candles, timeframe)
	local valid = {}

	for _, candle in ipairs(candles) do
		if isInternallyValid(candle) then
			table.insert(valid, candle)
		end
	end

	if timeframe == "D" then
		return valid
	end

	local cleaned = {}

	for index, candle in ipairs(valid) do
		local prevCandle = valid[index - 1]
		local nextCandle = valid[index + 1]
		local isSpike = prevCandle and nextCandle and isIsolatedSpike(prevCandle.Close, candle.Close, nextCandle.Close)

		if not isSpike then
			table.insert(cleaned, candle)
		end
	end

	return cleaned
end

-- Generic cache-or-fetch: returns cached data if still within `ttl` seconds,
-- otherwise calls fetchFn() and stores a fresh copy on success.
local function cachedFetch(cache, key, ttl, fetchFn)
	local cached = cache[key]
	local now = os.time()

	if cached and (now - cached.lastUpdated) < ttl then
		return cached.data, nil
	end

	local data, err = fetchFn()

	if data then
		cache[key] = { data = data, lastUpdated = now }
	end

	return data, err
end

-- Fetches a backend route through a cache, treating an `error` field in the
-- response as a failure
local function cachedRoute(cache, key, ttl, url)
	return cachedFetch(cache, key, ttl, function()
		local data, err = fetchJSON(url)

		if data and data.error then
			return nil, tostring(data.error)
		end

		return data, err
	end)
end

-- Fetches candles for ticker/timeframe/mode, using the shared cache for
-- non-live requests (mode == "live" always hits the backend, matching how
-- the client already treats live requests as cache-busting).
-- Returns candles array, error
function MarketDataModule.getCandles(ticker, timeframe, mode)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	if not VALID_TIMEFRAMES[timeframe] then
		return nil, "Invalid timeframe"
	end

	local targetTicker = string.upper(ticker)
	local isLiveRequest = (mode == "live")
	local cacheKey = buildCacheKey(targetTicker, timeframe, mode)
	local now = os.time()

	if not isLiveRequest then
		local cached = ChartCache[cacheKey]

		if cached and (now - cached.lastUpdated) < CHART_CACHE_DURATION then
			return cached.data, nil
		end
	end

	local url = CANDLES_ENDPOINT .. HttpService:UrlEncode(targetTicker) .. "?tf=" .. timeframe

	if mode then
		url = url .. "&mode=" .. HttpService:UrlEncode(mode) .. "&cb=" .. now
	end

	local data, err = fetchJSON(url)

	if not data then
		return nil, err
	end

	if data.error then
		return nil, tostring(data.error)
	end

	data = sanitizeCandles(data, timeframe)

	if not isLiveRequest then
		ChartCache[cacheKey] = { data = data, lastUpdated = now }
	end

	return data, nil
end

-- Live quotes for many tickers: { [ticker] = { price, bid, ask, prevClose,
-- time, marketState } }. Tickers quoted in the last QUOTE_CACHE_DURATION
-- seconds come from this server's quote table; the rest are fetched together,
-- 50 to a request. Callers about to price several tickers should call this
-- first so the per-ticker lookups after it hit the table.
function MarketDataModule.getQuotes(tickers)
	local now = os.time()
	local missing = {}
	local seen = {}

	for _, ticker in ipairs(tickers) do
		local targetTicker = string.upper(ticker)
		local cached = QuoteCache[targetTicker]

		if MarketDataModule.isValidTicker(targetTicker) and not seen[targetTicker] then
			seen[targetTicker] = true

			if not cached or now - cached.lastUpdated >= QUOTE_CACHE_DURATION then
				table.insert(missing, targetTicker)
			end
		end
	end

	for first = 1, #missing, MAX_QUOTES_PER_REQUEST do
		local batch = table.move(missing, first, math.min(first + MAX_QUOTES_PER_REQUEST - 1, #missing), 1, {})
		local data, err = fetchJSON(QUOTES_ENDPOINT .. HttpService:UrlEncode(table.concat(batch, ",")))

		if data and not data.error then
			for symbol, quote in pairs(data) do
				QuoteCache[symbol] = { data = quote, lastUpdated = now }
			end
		else
			warn("[MarketDataModule] Quote batch failed: " .. tostring(err or data.error))
		end
	end

	local quotes = {}

	for targetTicker in pairs(seen) do
		quotes[targetTicker] = QuoteCache[targetTicker] and QuoteCache[targetTicker].data
	end

	return quotes
end

function MarketDataModule.getLiveQuote(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil
	end

	return MarketDataModule.getQuotes({ ticker })[string.upper(ticker)]
end

-- Current price for a ticker, from the quote table. If the batch route is
-- unavailable it falls back to candles fetched with mode="live", where the
-- backend overwrites the last Close with the live quote.
function MarketDataModule.getCurrentPrice(ticker)
	local quote = MarketDataModule.getLiveQuote(ticker)

	if quote and quote.price then
		return quote.price
	end

	local candles = MarketDataModule.getCandles(ticker, "5M", "live")

	if not candles or #candles == 0 then
		return nil
	end

	return candles[#candles].Close
end

-- The price an order fills at, or nil and a reason not to fill. Pure, so it
-- can be tested with made-up quotes. A buy pays the ask and a sell gets the
-- bid during regular trading when the spread is sane; otherwise (crypto,
-- after hours, a gapped book) both use the last price. A regular-session
-- stock quote older than STALE_QUOTE_SECONDS is refused rather than traded
-- against.
function MarketDataModule.getFillPrice(quote, side, isCrypto, now)
	if not quote or not quote.price or quote.price <= 0 then
		return nil, "Price unavailable."
	end

	local isRegular = quote.marketState == "REGULAR"

	if isRegular and not isCrypto and quote.time and now - quote.time > STALE_QUOTE_SECONDS then
		return nil, "The price feed is behind; try again in a moment."
	end

	local bid, ask = quote.bid, quote.ask
	local hasSaneSpread = bid and ask and bid > 0 and ask >= bid and (ask - bid) / quote.price <= MAX_FILL_SPREAD

	if isRegular and not isCrypto and hasSaneSpread then
		return side == "Buy" and ask or bid
	end

	return quote.price
end

-- Splits over the last two years: { { date, numerator, denominator } }, dates
-- as unix seconds; nil if the backend can't be reached
function MarketDataModule.getSplits(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil
	end

	local targetTicker = string.upper(ticker)
	local data = cachedRoute(
		SplitsCache,
		targetTicker,
		SPLITS_CACHE_DURATION,
		SPLITS_ENDPOINT .. HttpService:UrlEncode(targetTicker)
	)

	return data and data.splits
end

-- Minimal quote shape: { ticker, price, prevClose }. The quote table has
-- the previous close; daily candles stand in when it doesn't.
function MarketDataModule.getQuote(ticker)
	local liveQuote = MarketDataModule.getLiveQuote(ticker)

	if liveQuote and liveQuote.price and liveQuote.prevClose then
		return {
			ticker = string.upper(ticker),
			price = liveQuote.price,
			prevClose = liveQuote.prevClose,
		}
	end

	local price = MarketDataModule.getCurrentPrice(ticker)

	if not price then
		return nil
	end

	local prevClose = price
	local dailyCandles = MarketDataModule.getCandles(ticker, "D")

	if dailyCandles and #dailyCandles >= 2 then
		prevClose = dailyCandles[#dailyCandles - 1].Close
	end

	return {
		ticker = string.upper(ticker),
		price = price,
		prevClose = prevClose,
	}
end

-- Quote Details tab: bid/ask/sizes, volume, market cap, beta, PE, dividends,
-- EPS, ex-div/earnings dates, day & 52-week range.
function MarketDataModule.getQuoteDetails(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedFetch(QuoteDetailsCache, targetTicker, QUOTE_DETAILS_CACHE_DURATION, function()
		local data, err = fetchJSON(QUOTE_DETAILS_ENDPOINT .. HttpService:UrlEncode(targetTicker))

		if data and data.error then
			return nil, tostring(data.error)
		end

		return data, err
	end)
end

-- Analyst Reports tab: price targets, recommendation mean/key, rating counts.
-- Returns { available = false } for tickers with no analyst coverage.
function MarketDataModule.getAnalystReport(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedFetch(AnalystCache, targetTicker, ANALYST_CACHE_DURATION, function()
		local data, err = fetchJSON(ANALYST_ENDPOINT .. HttpService:UrlEncode(targetTicker))

		if data and data.error then
			return nil, tostring(data.error)
		end

		return data, err
	end)
end

-- Fundamentals tab: revenue, margins, ROE/ROA, cash, debt, valuation ratios,
-- growth. Returns { available = false } for tickers with no financials.
function MarketDataModule.getFundamentals(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedFetch(FundamentalsCache, targetTicker, FUNDAMENTALS_CACHE_DURATION, function()
		local data, err = fetchJSON(FUNDAMENTALS_ENDPOINT .. HttpService:UrlEncode(targetTicker))

		if data and data.error then
			return nil, tostring(data.error)
		end

		return data, err
	end)
end

-- Option Stats tab: nearest-expiration ATM call/put. No greeks - Yahoo
-- doesn't provide them. Returns { available = false } if no listed options.
function MarketDataModule.getOptionStats(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedFetch(OptionStatsCache, targetTicker, OPTION_STATS_CACHE_DURATION, function()
		local data, err = fetchJSON(OPTIONS_ENDPOINT .. HttpService:UrlEncode(targetTicker))

		if data and data.error then
			return nil, tostring(data.error)
		end

		return data, err
	end)
end

-- Option Chain panel (Trade tab): nearest-expiration, multi-strike chain
-- (~±20% of spot, set server-side). Returns { available = false } if no
-- listed options.
function MarketDataModule.getOptionChain(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedFetch(OptionChainCache, targetTicker, OPTION_CHAIN_CACHE_DURATION, function()
		local data, err = fetchJSON(OPTIONS_CHAIN_ENDPOINT .. HttpService:UrlEncode(targetTicker))

		if data and data.error then
			return nil, tostring(data.error)
		end

		return data, err
	end)
end

-- Looks up a single contract's live fields by OCC contractSymbol, reusing
-- the cached chain so order pricing and net-worth mark-to-market share one
-- lookup path instead of two independently-written ones.
function MarketDataModule.getOptionQuote(ticker, contractSymbol)
	local chain, err = MarketDataModule.getOptionChain(ticker)

	if not chain or chain.available == false or not chain.strikes then
		return nil, err or "Option chain unavailable"
	end

	for _, entry in ipairs(chain.strikes) do
		if entry.call and entry.call.contractSymbol == contractSymbol then
			return entry.call, nil
		end

		if entry.put and entry.put.contractSymbol == contractSymbol then
			return entry.put, nil
		end
	end

	return nil, "Contract not found"
end

-- Recent headlines mentioning a ticker:
-- { available, items = { { title, publisher, link, publishedAt, relatedTickers } } }
function MarketDataModule.getNews(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedRoute(
		NewsCache,
		targetTicker,
		NEWS_CACHE_DURATION,
		NEWS_ENDPOINT .. HttpService:UrlEncode(targetTicker)
	)
end

-- Today's movers: { gainers, losers, active }, each up to 10
-- { symbol, name, price, change, changePercent, volume }
function MarketDataModule.getMovers()
	return cachedRoute(MoversCache, "movers", MOVERS_CACHE_DURATION, MOVERS_ENDPOINT)
end

-- { quoteType, sector, industry }; sector and industry are only set for stocks
function MarketDataModule.getProfile(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedRoute(
		ProfileCache,
		targetTicker,
		PROFILE_CACHE_DURATION,
		PROFILE_ENDPOINT .. HttpService:UrlEncode(targetTicker)
	)
end

-- Cache sweep
local ALL_CACHES = {
	{ cache = ChartCache, ttl = CHART_CACHE_DURATION },
	{ cache = QuoteDetailsCache, ttl = QUOTE_DETAILS_CACHE_DURATION },
	{ cache = AnalystCache, ttl = ANALYST_CACHE_DURATION },
	{ cache = FundamentalsCache, ttl = FUNDAMENTALS_CACHE_DURATION },
	{ cache = OptionStatsCache, ttl = OPTION_STATS_CACHE_DURATION },
	{ cache = OptionChainCache, ttl = OPTION_CHAIN_CACHE_DURATION },
	{ cache = NewsCache, ttl = NEWS_CACHE_DURATION },
	{ cache = MoversCache, ttl = MOVERS_CACHE_DURATION },
	{ cache = ProfileCache, ttl = PROFILE_CACHE_DURATION },
	{ cache = QuoteCache, ttl = QUOTE_CACHE_DURATION },
	{ cache = SplitsCache, ttl = SPLITS_CACHE_DURATION },
}

task.spawn(function()
	while true do
		task.wait(CACHE_SWEEP_INTERVAL)

		local now = os.time()
		local deletedCount = 0

		for _, entry in ipairs(ALL_CACHES) do
			for key, cacheEntry in pairs(entry.cache) do
				if (now - cacheEntry.lastUpdated) > entry.ttl then
					entry.cache[key] = nil
					deletedCount += 1
				end
			end
		end

		if deletedCount > 0 then
			print("[MarketDataModule] Cleared " .. deletedCount .. " stale cache entries.")
		end
	end
end)

return MarketDataModule
