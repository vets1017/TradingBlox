local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENTS = {
	"RequestChartEvent",
	"GetMarketDataEvent",
	"GetMarketOverviewEvent",
	"GetMarketMoversEvent",
	"GetOptionsDataEvent",
	"GetPositionsEvent",
	"GetPortfolioEvent",
	"GetLeaderboardEvent",
	"GetPublicProfileEvent",
	"GetNewsFeedEvent",
	"PlayerOrderEvent",
	"PlaceLimitOrderEvent",
	"PlaceStopOrderEvent",
	"CancelOrderEvent",
	"GetOrdersEvent",
	"PlayerOptionOrderEvent",
	"GetAnalystReportEvent",
	"GetFundamentalsEvent",
	"GetOptionStatsEvent",
	"GetWatchlistEvent",
	"ToggleWatchlistEvent",
	"CompleteTutorialStepEvent",
	"FollowPlayerEvent",
	"SetShareTradesEvent",
	"GetFeedEvent",
	"PublishThesisEvent",
	"DeleteThesisEvent",
	"GetTickerThesesEvent",
	"MutePlayerEvent",
	"SetRobloxBlocksEvent",
	"ReportThesisEvent",
	"ReactToFeedItemEvent",
	"GetInboxEvent",
	"MarkInboxSeenEvent",
	"GetTrendingEvent",
	"GetRobloxMarketEvent",
	"GetDailyEvent",
}

-- Server-to-client pushes (RemoteEvents rather than RemoteFunctions)
local PUSH_EVENTS = {
	"OrderUpdateEvent", -- a limit order filled or was cancelled while the player wasn't waiting on it
	"NotificationEvent", -- a new notification or unread count; see NotificationService
	"RewardEvent", -- a fill, challenge, streak or milestone to celebrate, or new daily challenges; see ChallengeService
}

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
	getOrCreateRemote(EventsFolder, eventName, "RemoteFunction")
end

for _, eventName in ipairs(PUSH_EVENTS) do
	getOrCreateRemote(EventsFolder, eventName, "RemoteEvent")
end
