-- MarketDataModule.luau
--
-- Shared market-data access: ticker validation, candle fetching/caching, and
-- price/quote derivation on top of the candles endpoint (the only endpoint
-- the backend actually exposes). Used by API_Manager (chart/quote remotes)
-- and TradeSystem (trade pricing + positions) so neither duplicates the HTTP
-- fetch/cache logic.

local HttpService = game:GetService("HttpService")

local MarketDataModule = {}

-- Config
local SERVER_URL = "https://tradingblox-terminal-backend.onrender.com" -- temp
local CANDLES_ENDPOINT = SERVER_URL .. "/api/candles/"

local CHART_CACHE_DURATION = 300
local CACHE_SWEEP_INTERVAL = 600
local MAX_TICKER_LENGTH = 10
local VALID_TIMEFRAMES = { ["1M"] = true, ["5M"] = true, ["30M"] = true, ["H"] = true, ["D"] = true }

-- State
local ChartCache = {} -- [cacheKey] = { data = ..., lastUpdated = os.time() }

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

	if not isLiveRequest then
		ChartCache[cacheKey] = { data = data, lastUpdated = now }
	end

	return data, nil
end

-- Current price for a ticker. Fetched with mode="live", which makes the
-- backend overwrite the last candle's Close with a real Yahoo Finance quote
-- (regularMarketPrice) rather than a stale historical close.
function MarketDataModule.getCurrentPrice(ticker)
	local candles = MarketDataModule.getCandles(ticker, "5M", "live")

	if not candles or #candles == 0 then
		return nil
	end

	return candles[#candles].Close
end

-- Minimal quote shape: { ticker, price, prevClose }. No bid/ask/volume/etc. -
-- the backend has no route for those.
function MarketDataModule.getQuote(ticker)
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

-- Cache sweep
task.spawn(function()
	while true do
		task.wait(CACHE_SWEEP_INTERVAL)

		local now = os.time()
		local deletedCount = 0

		for key, entry in pairs(ChartCache) do
			if (now - entry.lastUpdated) > CHART_CACHE_DURATION then
				ChartCache[key] = nil
				deletedCount += 1
			end
		end

		if deletedCount > 0 then
			print("[MarketDataModule] Cleared " .. deletedCount .. " stale chart cache entries.")
		end
	end
end)

return MarketDataModule
