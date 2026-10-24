local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENTS = {
	"RequestChartEvent",
	"GetMarketDataEvent",
	"GetOptionsDataEvent",
	"GetPositionsEvent",
	"GetPortfolioEvent",
	"GetNewsFeedEvent",
	"PlayerOrderEvent",
	"PlayerOptionOrderEvent",
	"GetAnalystReportEvent",
	"GetFundamentalsEvent",
	"GetOptionStatsEvent",
	"GetWatchlistEvent",
	"ToggleWatchlistEvent",
}

local Event = {}

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end

	return folder
end

local function getOrCreateRemote(parent, name, className)
	local remote = parent:FindFirstChild(name)

	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = parent
	end

	return remote
end

local EventsFolder = getOrCreateFolder(ReplicatedStorage, "EventsFolder")

for _, eventName in ipairs(EVENTS) do
	Event[eventName] = getOrCreateRemote(EventsFolder, eventName, "RemoteFunction")
end

local RequestChartEvent = Event.RequestChartEvent
local GetMarketDataEvent = Event.GetMarketDataEvent
local GetOptionsDataEvent = Event.GetOptionsDataEvent
local GetPositionsEvent = Event.GetPositionsEvent
local GetNewsFeedEvent = Event.GetNewsFeedEvent
local PlayerOrderEvent = Event.PlayerOrderEvent
