-- SocialSystem.server.luau
--
-- Social remotes: following players, the trade-sharing setting and the
-- feed. The follower counts themselves come with GetPublicProfileEvent
-- (LeaderboardSystem).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Social = require(ReplicatedStorage.Config.Social)
local SocialService = require(ServerScriptService.Services.SocialService)
local FeedService = require(ServerScriptService.Services.FeedService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local SocialModule = require(ServerScriptService.Modules.SocialModule)
local RemoteGuard = require(ServerScriptService.Modules.RemoteGuard)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local FollowPlayerEvent = EventsFolder:WaitForChild("FollowPlayerEvent")
local SetShareTradesEvent = EventsFolder:WaitForChild("SetShareTradesEvent")
local GetFeedEvent = EventsFolder:WaitForChild("GetFeedEvent")

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
