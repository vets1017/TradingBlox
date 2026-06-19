local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local RequestChartEvent = EventsFolder:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = EventsFolder:WaitForChild("GetMarketDataEvent")

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

RequestChartEvent.OnServerInvoke = function(player, ticker, timeframe, mode)
	local targetTicker = string.upper(ticker)
	local timeframeValue = timeframe

	local url = CANDLES_ENDPOINT .. targetTicker .. "?tf=" .. timeframeValue

	if mode then
		url = url .. "&mode=" .. mode .. "&cb=" .. os.time()
	end

	local success, response = pcall(function()
		return HttpService:GetAsync(url)
	end)

	if success then
		return HttpService:JSONDecode(response)
	else
		local jsonSuccess, decodedError = pcall(function()
			return HttpService:JSONDecode(response)
		end)

		if jsonSuccess and decodedError and decodedError.error then
			warn("Server Error: ", decodedError.error)
		else
			warn("Roblox Network HTTP Fetch Error: ", tostring(response))
		end
		return nil
	end
end

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
