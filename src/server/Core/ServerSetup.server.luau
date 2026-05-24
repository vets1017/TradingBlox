local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventsFolder = ReplicatedStorage:FindFirstChild("EventsFolder")

if not EventsFolder then
	EventsFolder = Instance.new("Folder")
	EventsFolder.Name = "EventsFolder"
	EventsFolder.Parent = ReplicatedStorage
end

local TradeEvent = Instance.new("RemoteEvent")
local OptionEvent = Instance.new("RemoteEvent")
local RequestChartEvent = Instance.new("RemoteFunction")
local GetMarketDataEvent = Instance.new("RemoteFunction")

TradeEvent.Name = "TradeEvent"
TradeEvent.Parent = EventsFolder

OptionEvent.Name = "OptionEvent"
OptionEvent.Parent = EventsFolder

RequestChartEvent.Name = "RequestChartEvent"
RequestChartEvent.Parent = EventsFolder

GetMarketDataEvent.Name = "GetMarketDataEvent"
GetMarketDataEvent.Parent = EventsFolder
