local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local RequestChartEvent = EventsFolder:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = EventsFolder:WaitForChild("GetMarketDataEvent")

local SERVER_URL = nil -- temp

_G.LiveMarketData = {}

local function updateMarketData()
	local success, response = pcall(function()
		return HttpService:GetAsync(SERVER_URL)
	end)

	if success then
		local decodedData = HttpService:JSONDecode(response)
		_G.LiveMarketData = decodedData
		print("Market Data Updated Successfully!")
	else
		warn("Failed to fetch data: " .. tostring(response))
	end
end

RequestChartEvent.OnServerInvoke = function(player, ticker)
	local url = SERVER_URL .. string.upper(ticker)

	local success, response = pcall(function()
		return HttpService:GetAsync(url)
	end)

	if success then
		local decodedData = HttpService:JSONDecode(response)
		return decodedData
	else
		warn("Failed to fetch chart data for " .. ticker .. ": " .. tostring(response))
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
