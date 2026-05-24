local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = ReplicatedStorage:WaitForChild("Events")
local RequestChartEvent = Events:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = Events:WaitForChild("GetMarketDataEvent")

local ServerURL = "https://spicy-dryers-smile.loca.lt/api/stock/AMZN" -- temp

_G.LiveData = {}

local function updateMarketData()
	local success, response = pcall(function()
		return HttpService:GetAsync(ServerURL)
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
	local url = ServerURL .. string.upper(ticker)

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
	return _G.LiveData
end

task.spawn(function()
	while true do
		updateMarketData()
		task.wait(60)
	end
end)
