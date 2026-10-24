local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENTS = {
	"RequestChartEvent",
	"GetMarketDataEvent",
	"GetOptionsDataEvent",
	"GetPositionsEvent",
	"GetPortfolioEvent",
	"GetLeaderboardEvent",
	"GetPublicProfileEvent",
	"GetNewsFeedEvent",
	"PlayerOrderEvent",
	"PlaceLimitOrderEvent",
	"CancelOrderEvent",
	"GetOrdersEvent",
	"PlayerOptionOrderEvent",
	"GetAnalystReportEvent",
	"GetFundamentalsEvent",
	"GetOptionStatsEvent",
	"GetWatchlistEvent",
	"ToggleWatchlistEvent",
}

-- Server-to-client pushes (RemoteEvents rather than RemoteFunctions)
local PUSH_EVENTS = {
	"OrderUpdateEvent", -- a limit order filled or was cancelled while the player wasn't waiting on it
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

for _, eventName in ipairs(PUSH_EVENTS) do
	Event[eventName] = getOrCreateRemote(EventsFolder, eventName, "RemoteEvent")
end

local RequestChartEvent = Event.RequestChartEvent
local GetMarketDataEvent = Event.GetMarketDataEvent
local GetOptionsDataEvent = Event.GetOptionsDataEvent
local GetPositionsEvent = Event.GetPositionsEvent
local GetNewsFeedEvent = Event.GetNewsFeedEvent
local PlayerOrderEvent = Event.PlayerOrderEvent
