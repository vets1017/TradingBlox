-- API_Manager.server.luau
--
-- Middleman API

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local RequestChartEvent = EventsFolder:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = EventsFolder:WaitForChild("GetMarketDataEvent")
local GetOptionDataEvent = EventsFolder:WaitForChild("GetOptionDataEvent")
local GetPositionsEvent = EventsFolder:WaitForChild("GetPositionsEvent")
local GetNewsFeedEvent = EventsFolder:WaitForChild("GetNewsFeedEvent")
local PlayerOrderEvent = EventsFolder:WaitForChild("PlayerOrderEvent")

-- Config
local SERVER_URL = "https://tradingblox-terminal-backend.onrender.com" -- temp
local QUOTES_ENDPOINT = SERVER_URL .. "/api/quotes"
local CANDLES_ENDPOINT = SERVER_URL .. "/api/candles/"

local CHART_CACHE_DURATION = 300
local CACHE_SWEEP_INTERVAL = 600
local QUOTES_POLL_INTERVAL = 60

local PLAYER_COOLDOWN = 1
local VALID_TIMEFRAMES = { ["1M"] = true, ["5M"] = true, ["30M"] = true, ["H"] = true, ["D"] = true }
local MAX_TICKER_LENGTH = 10

-- State
local LiveMarketData = {}
local ChartCache = {} -- [cachekey] = { data = ..., lastUpdated = os.time() }
local PlayerLastRequest = {} -- [UserId] = os.time() of last request

--

local function isValidTicker(ticker)
	if type(ticker) ~= "string" then
		return false
	end

	if ticker == "" or #ticker > MAX_TICKER_LENGTH then
		return false
	end

	return string.match(ticker, "^[%a%d%.%-]+$") ~= nil
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

-- Polling
local function updateMarketData()
	local data, error = fetchJSON(QUOTES_ENDPOINT)

	if data then
		LiveMarketData = data

		print("[API_Manager] Quotes updated (" .. os.time() .. "}")
	else
		warn("[API_Manager] Failed to fetch quotes: " .. tostring(error))
	end
end

-- RequestChartEvent
RequestChartEvent.OnServerInvoke = function(player, ticker, timeframe, mode)
	local userId = player.UserId
	local now = os.time()
	local lastRequest = PlayerLastRequest[userId] or 0

	if (now - lastRequest) < PLAYER_COOLDOWN then
		return nil
	end

	PlayerLastRequest[userId] = now

	if not isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(timeframe)))

		return nil
	end

	local targetTicker = string.upper(ticker)

	if not VALID_TIMEFRAMES[timeframe] then
		warn(string.format("[API_Manager] Invalid timeframe from %s: %s", player.Name, tostring(timeframe)))

		return nil
	end

	local isLiveRequest = (mode == "live")
	local cacheKey = buildCacheKey(targetTicker, timeframe, mode)

	if not isLiveRequest then
		local cached = ChartCache[cacheKey]

		if cached and (now - cached.lastUpdated) < CHART_CACHE_DURATION then
			return cached.data
		end
	end

	local url = CANDLES_ENDPOINT .. HttpService:UrlEncode(targetTicker) .. "?tf=" .. timeframe

	if mode then
		url = url .. "&mode=" .. HttpService:UrlEncode(mode) .. "&cb=" .. now
	end

	local data, error = fetchJSON(url)

	if not data then
		warn(
			string.format("[API_Manager] Chart fetch failed for %s (%s): %s", targetTicker, timeframe, tostring(error))
		)

		return nil
	end

	if data.error then
		warn(string.format("[API_Manager] Server-side erorr for %s: %s", targetTicker, tostring(data.error)))

		return nil
	end

	if not isLiveRequest then
		ChartCache[cacheKey] = { data = data, lastUpdated = now }
	end

	return data
end

-- GetMarketDataEvent
-- No ticker -> full quotes dataset
-- With ticker -> specific quote
GetMarketDataEvent.OnServerInvoke = function(player, ticker)
	if not ticker then
		return LiveMarketData
	end

	local targetTicker = string.upper(ticker)

	local direct = LiveMarketData[targetTicker]

	if direct then
		return direct
	end

	if type(LiveMarketData) == "table" then
		for _, quote in pairs(LiveMarketData) do
			if type(quote) == "table" then
				local quoteTicker = quote.ticker or quote.symbol

				if quoteTicker and string.upper(quoteTicker) == targetTicker then
					return quote
				end
			end
		end
	end

	return nil
end

-- Tasks
task.spawn(function()
	while true do
		updateMarketData()
		task.wait(QUOTES_POLL_INTERVAL)
	end
end)

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
			print("[API_Manager] Cleared " .. deletedCount .. " stale chart cache entries.")
		end
	end
end)

-- Clean up
game:GetService("Players").PlayerRemoving:Connect(function(player)
	PlayerLastRequest[player.UserId] = nil
end)
