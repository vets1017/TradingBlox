-- SocialSystem.server.luau
--
-- Social remotes: following players, the trade-sharing setting, the feed,
-- theses, and muting, blocking and reporting. The follower counts themselves come with GetPublicProfileEvent
-- (LeaderboardSystem).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Social = require(ReplicatedStorage.Config.Social)
local SocialService = require(ServerScriptService.Services.SocialService)
local FeedService = require(ServerScriptService.Services.FeedService)
local ThesisService = require(ServerScriptService.Services.ThesisService)
local MuteService = require(ServerScriptService.Services.MuteService)
local NotificationService = require(ServerScriptService.Services.NotificationService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local SocialModule = require(ServerScriptService.Modules.SocialModule)
local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local RemoteGuard = require(ServerScriptService.Modules.RemoteGuard)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local FollowPlayerEvent = EventsFolder:WaitForChild("FollowPlayerEvent")
local SetShareTradesEvent = EventsFolder:WaitForChild("SetShareTradesEvent")
local GetFeedEvent = EventsFolder:WaitForChild("GetFeedEvent")
local PublishThesisEvent = EventsFolder:WaitForChild("PublishThesisEvent")
local DeleteThesisEvent = EventsFolder:WaitForChild("DeleteThesisEvent")
local GetTickerThesesEvent = EventsFolder:WaitForChild("GetTickerThesesEvent")
local MutePlayerEvent = EventsFolder:WaitForChild("MutePlayerEvent")
local SetRobloxBlocksEvent = EventsFolder:WaitForChild("SetRobloxBlocksEvent")
local ReportThesisEvent = EventsFolder:WaitForChild("ReportThesisEvent")
local ReactToFeedItemEvent = EventsFolder:WaitForChild("ReactToFeedItemEvent")
local GetInboxEvent = EventsFolder:WaitForChild("GetInboxEvent")
local MarkInboxSeenEvent = EventsFolder:WaitForChild("MarkInboxSeenEvent")

local MAX_THESIS_ID_LENGTH = 40
local MAX_FEED_ITEM_ID_LENGTH = 64

local INVALID_REQUEST = { success = false, message = "Invalid request." }

-- A positive whole number a user id can be (math.huge passes the floor check)
local function isUserId(value): boolean
	return type(value) == "number" and value == math.floor(value) and value > 0 and value < 2 ^ 53
end

-- FollowPlayerEvent(userId, shouldFollow)
-- Returns { success, message?, isFollowing, followers, following }
RemoteGuard.handle(FollowPlayerEvent, RemoteGuard.LIMITS.Rare, function(player, userId, shouldFollow)
	if not isUserId(userId) or type(shouldFollow) ~= "boolean" then
		return INVALID_REQUEST
	end

	return SocialService.setFollowing(player, userId, shouldFollow)
end, RemoteGuard.TOO_MANY_REQUESTS)

-- SetShareTradesEvent(shareTrades)
-- Returns { success, message?, shareTrades }
RemoteGuard.handle(SetShareTradesEvent, RemoteGuard.LIMITS.Rare, function(player, shareTrades)
	if type(shareTrades) ~= "boolean" then
		return INVALID_REQUEST
	end

	return SocialService.setShareTrades(player, shareTrades)
end, RemoteGuard.TOO_MANY_REQUESTS)

-- GetFeedEvent(view)
-- Returns { items, following }: the newest feed items for "All" or
-- "Following" (see FeedModule for their shape), and how many players the
-- caller follows, so the client can tell "follows no one" from "quiet".
-- The Social tab polls this every few seconds while it's open.
RemoteGuard.handle(GetFeedEvent, RemoteGuard.LIMITS.Read, function(player, view)
	if not Social.isFeedView(view) then
		return nil
	end

	local data = PlayerDataService.get(player)

	return {
		items = FeedService.getFeed(player, view),
		following = data and SocialModule.countFollowing(data.Social) or 0,
	}
end)

-- PublishThesisEvent(ticker, draft)
-- draft = { direction, horizon, targetPrice?, text? }; see ThesisModule.
-- Returns { success, message?, thesis? }
RemoteGuard.handle(PublishThesisEvent, RemoteGuard.LIMITS.Rare, function(player, ticker, draft)
	if not MarketDataModule.isValidTicker(ticker) or type(draft) ~= "table" then
		return INVALID_REQUEST
	end

	return ThesisService.publish(player, ticker, draft)
end, RemoteGuard.TOO_MANY_REQUESTS)

-- DeleteThesisEvent(thesisId)
-- Returns { success, message? }
RemoteGuard.handle(DeleteThesisEvent, RemoteGuard.LIMITS.Rare, function(player, thesisId)
	if type(thesisId) ~= "string" or #thesisId > MAX_THESIS_ID_LENGTH then
		return INVALID_REQUEST
	end

	return ThesisService.delete(player, thesisId)
end, RemoteGuard.TOO_MANY_REQUESTS)

-- GetTickerThesesEvent(ticker)
-- Returns ThesisService.getForTicker's table, or nil
RemoteGuard.handle(GetTickerThesesEvent, RemoteGuard.LIMITS.Research, function(player, ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil
	end

	return ThesisService.getForTicker(player, ticker)
end)

-- MutePlayerEvent(userId, shouldMute)
-- Returns { success, message?, isMuted }
RemoteGuard.handle(MutePlayerEvent, RemoteGuard.LIMITS.Rare, function(player, userId, shouldMute)
	if not isUserId(userId) or type(shouldMute) ~= "boolean" then
		return INVALID_REQUEST
	end

	return MuteService.setMuted(player, userId, shouldMute)
end, RemoteGuard.TOO_MANY_REQUESTS)

-- SetRobloxBlocksEvent(userIds)
-- The client's Roblox block list, sent at startup and whenever it changes
RemoteGuard.handle(SetRobloxBlocksEvent, RemoteGuard.LIMITS.Rare, function(player, userIds)
	if type(userIds) ~= "table" then
		return false
	end

	MuteService.setRobloxBlocks(player, userIds)

	return true
end, false)

-- ReportThesisEvent(thesisId, ticker)
-- Returns { success, message? }
RemoteGuard.handle(ReportThesisEvent, RemoteGuard.LIMITS.Rare, function(player, thesisId, ticker)
	if type(thesisId) ~= "string" or #thesisId > MAX_THESIS_ID_LENGTH or not MarketDataModule.isValidTicker(ticker) then
		return INVALID_REQUEST
	end

	return ThesisService.report(player, thesisId, ticker)
end, RemoteGuard.TOO_MANY_REQUESTS)

-- ReactToFeedItemEvent(itemId, reactionId | nil)
-- nil takes the player's reaction off. Returns { success, message?,
-- reactions, yourReaction }
RemoteGuard.handle(ReactToFeedItemEvent, RemoteGuard.LIMITS.Research, function(player, itemId, reactionId)
	if type(itemId) ~= "string" or #itemId > MAX_FEED_ITEM_ID_LENGTH then
		return INVALID_REQUEST
	elseif reactionId ~= nil and not Social.getReaction(reactionId) then
		return INVALID_REQUEST
	end

	return FeedService.react(player, itemId, reactionId)
end, RemoteGuard.TOO_MANY_REQUESTS)

-- GetInboxEvent()
-- Returns { items (newest first), unread }, or nil before the profile loads
RemoteGuard.handle(GetInboxEvent, RemoteGuard.LIMITS.Read, function(player)
	return NotificationService.getInbox(player)
end)

-- MarkInboxSeenEvent()
-- The player opened the inbox: everything in it now counts as read
RemoteGuard.handle(MarkInboxSeenEvent, RemoteGuard.LIMITS.Research, function(player)
	NotificationService.markSeen(player)

	return true
end, false)
