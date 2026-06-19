local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventsFolder = ReplicatedStorage:FindFirstChild("EventsFolder")

if not EventsFolder then
	EventsFolder = Instance.new("Folder")
	EventsFolder.Name = "EventsFolder"
	EventsFolder.Parent = ReplicatedStorage
end

local RequestChartEvent = EventsFolder:FindFirstChild("RequestChartEvent")
if not RequestChartEvent then
	RequestChartEvent = Instance.new("RemoteFunction")
	RequestChartEvent.Name = "RequestChartEvent"
	RequestChartEvent.Parent = EventsFolder
end

local GetMarketDataEvent = EventsFolder:FindFirstChild("GetMarketDataEvent")
if not GetMarketDataEvent then
	GetMarketDataEvent = Instance.new("RemoteFunction")
	GetMarketDataEvent.Name = "GetMarketDataEvent"
	GetMarketDataEvent.Parent = EventsFolder
end
