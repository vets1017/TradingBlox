local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local RequestChartEvent = EventsFolder:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = EventsFolder:WaitForChild("GetMarketDataEvent")

print("ignore error below")
local SERVER_URL = "https://tradingblox-terminal-backend.onrender.com" -- temp
local QUOTES_ENDPOINT = SERVER_URL .. "/api/quotes"
local CANDLES_ENDPOINT = SERVER_URL .. "/api/candles/"

local CACHE_DURATION = 300

local ChartCache = {}

_G.LiveMarketData = {}

local function updateMarketData()
	local success, response = pcall(function()
		return HttpService:GetAsync(QUOTES_ENDPOINT)
	end)

	if success then
		local decodedData = HttpService:JSONDecode(response)
		_G.LiveMarketData = decodedData
		print("Market Data Updated Successfully!")
		print(_G.LiveMarketData)
	else
		warn("Failed to fetch data: " .. tostring(response))
	end
end

RequestChartEvent.OnServerInvoke = function(player, ticker, timeframe)
	local targetTicker = string.upper(ticker)
	local timeframeValue = timeframe

	local url = CANDLES_ENDPOINT .. targetTicker .. "?timeframe=" .. timeframeValue

	local success, response = pcall(function()
		return HttpService:GetAsync(url)
	end)

	if success then
		return HttpService:JSONDecode(response)
	else
		warn(response)
		return nil
	end
end

-- RequestChartEvent.OnServerInvoke = function(player, ticker)
-- 	ticker = string.upper(ticker)

-- 	local currentTime = os.time()

-- 	if ChartCache[ticker] then
-- 		local timeSinceLastFetch = currentTime - ChartCache[ticker].LastUpdated

-- 		if timeSinceLastFetch < CACHE_DURATION then
-- 			print("Serving chart data for " .. ticker .. " from cache.")

-- 			return ChartCache[ticker].Data
-- 		else
-- 			print("Cache expired")
-- 		end
-- 	end

-- 	local url = CANDLES_ENDPOINT .. ticker

-- 	local success, response = pcall(function()
-- 		return HttpService:GetAsync(url)
-- 	end)

-- 	if success then
-- 		local decodedData = HttpService:JSONDecode(response)

-- 		ChartCache[ticker] = {
-- 			Data = decodedData,
-- 			LastUpdated = currentTime,
-- 		}

-- 		return decodedData
-- 	else
-- 		warn("Failed to fetch chart data for " .. ticker .. ": " .. tostring(response))
-- 		if ChartCache[ticker] then
-- 			print("Serving stale chart data for " .. ticker .. " from cache due to fetch failure.")
-- 			return ChartCache[ticker].Data
-- 		end
-- 		return nil
-- 	end
-- end

GetMarketDataEvent.OnServerInvoke = function(player)
	return _G.LiveMarketData
end

task.spawn(function()
	while true do
		updateMarketData()
		task.wait(60)
	end
end)

task.spawn(function()
	while true do
		task.wait(600)
		local currentTime = os.time()
		local deletedCount = 0

		for ticker, cacheEntry in pairs(ChartCache) do
			if (currentTime - cacheEntry.LastUpdated) > CACHE_DURATION then
				ChartCache[ticker] = nil
				deletedCount = deletedCount + 1
			end
		end

		if deletedCount > 0 then
			print("Cleared " .. deletedCount .. " stale entries from chart cache.")
		end
	end
end)
