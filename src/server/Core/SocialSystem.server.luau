-- SocialSystem.server.luau
--
-- Social remotes: following players and the trade-sharing setting. The
-- follower counts themselves come with GetPublicProfileEvent
-- (LeaderboardSystem).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SocialService = require(ServerScriptService.Services.SocialService)
local RemoteGuard = require(ServerScriptService.Modules.RemoteGuard)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local FollowPlayerEvent = EventsFolder:WaitForChild("FollowPlayerEvent")
local SetShareTradesEvent = EventsFolder:WaitForChild("SetShareTradesEvent")

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
