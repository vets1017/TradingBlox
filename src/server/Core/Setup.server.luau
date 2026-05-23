local ReplicatedStorage = game:GetService("ReplicatedStorage")

local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local tradeEvent = Instance.new("RemoteEvent")
local optionEvent = Instance.new("RemoteEvent")
local requestChartEvent = Instance.new("RemoteFunction")
local getMarketDataEvent = Instance.new("RemoteFunction")

tradeEvent.Name = "TradeEvent"
tradeEvent.Parent = eventsFolder
optionEvent.Name = "OptionEvent"
optionEvent.Parent = eventsFolder
requestChartEvent.Name = "RequestChartEvent"
requestChartEvent.Parent = eventsFolder
getMarketDataEvent.Name = "GetMarketDataEvent"
getMarketDataEvent.Parent = eventsFolder
