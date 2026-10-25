-- SocialService.luau
--
-- Social trading (GDD §2): who a player follows, how many players follow
-- them, and whether their trades are public. A player's Following list and
-- sharing setting live in their own profile; follower counts live in the
-- Followers DataStore, because players on other servers change them.
-- Following someone shows their activity; it never copies their trades.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Social = require(ReplicatedStorage.Config.Social)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local PublicProfileService = require(ServerScriptService.Services.PublicProfileService)
local FeedService = require(ServerScriptService.Services.FeedService)
local SocialModule = require(ServerScriptService.Modules.SocialModule)

local FollowerStore = DataStoreService:GetDataStore("Followers_v1")

local FOLLOWER_CACHE_SECONDS = 60
local SWEEP_INTERVAL = 300

local followerCache = {} -- [userId] = { fetchedAt = os.clock(), count = number }
-- Weak keys, so a player who has left drops out on their own
local isUpdating = setmetatable({}, { __mode = "k" }) -- [player] = true while a follow change saves

local SocialService = {}

local function failure(message: string)
	return { success = false, message = message }
end

-- How many players follow `userId`, or nil if the count can't be read.
-- Cached a minute per server, like public profiles.
function SocialService.getFollowerCount(userId: number): number?
	local cached = followerCache[userId]

	if cached and os.clock() - cached.fetchedAt < FOLLOWER_CACHE_SECONDS then
		return cached.count
	end

	local success, count = pcall(FollowerStore.GetAsync, FollowerStore, tostring(userId))

	if not success then
		warn("[SocialService] Couldn't read the followers of " .. userId .. ": " .. tostring(count))

		return cached and cached.count
	end

	followerCache[userId] = { fetchedAt = os.clock(), count = count or 0 }

	return count or 0
end

function SocialService.isFollowing(player, userId: number): boolean
	local data = PlayerDataService.get(player)

	return data ~= nil and SocialModule.isFollowing(data.Social, userId)
end

local function describeFollow(data, targetUserId: number, followers: number?)
	return {
		success = true,
		isFollowing = SocialModule.isFollowing(data.Social, targetUserId),
		followers = followers,
		following = SocialModule.countFollowing(data.Social),
	}
end

-- Runs with the player's update lock held; yields
local function changeFollow(player, targetUserId: number, shouldFollow: boolean)
	-- Only players with a public profile can be followed, so ids that aren't
	-- players never collect a count
	if shouldFollow and not PublicProfileService.get(targetUserId) then
		return failure("That player has no public profile yet.")
	end

	-- The count changes first: if it can't be saved, nothing has changed
	local delta = if shouldFollow then 1 else -1
	local success, followers = pcall(FollowerStore.UpdateAsync, FollowerStore, tostring(targetUserId), function(count)
		return math.max((count or 0) + delta, 0)
	end)

	if not success then
		warn("[SocialService] Couldn't update the followers of " .. targetUserId .. ": " .. tostring(followers))

		return failure("Couldn't save that. Try again in a moment.")
	end

	followerCache[targetUserId] = { fetchedAt = os.clock(), count = followers }

	-- Gone only if the player left while the count saved
	local data = PlayerDataService.get(player)

	if not data then
		return failure("Your data is still loading.")
	end

	SocialModule.setFollowing(data.Social, targetUserId, shouldFollow, os.time())

	return describeFollow(data, targetUserId, followers)
end

-- Follows or unfollows a player. Returns { success, message? } plus, on
-- success, { isFollowing, followers (nil if unknown), following }.
function SocialService.setFollowing(player, targetUserId: number, shouldFollow: boolean)
	local data = PlayerDataService.get(player)

	if not data then
		return failure("Your data is still loading.")
	end

	if SocialModule.isFollowing(data.Social, targetUserId) == shouldFollow then
		return describeFollow(data, targetUserId, SocialService.getFollowerCount(targetUserId))
	end

	if shouldFollow then
		local canFollow, message =
			SocialModule.checkFollow(data.Social, player.UserId, targetUserId, Social.MAX_FOLLOWING)

		if not canFollow then
			return failure(message)
		end
	end

	-- Two overlapping requests would both pass the check above and count twice
	if isUpdating[player] then
		return failure("Still saving your last change.")
	end

	isUpdating[player] = true

	local ok, result = pcall(changeFollow, player, targetUserId, shouldFollow)

	isUpdating[player] = nil

	if not ok then
		warn("[SocialService] Follow change failed for " .. player.Name .. ": " .. tostring(result))

		return failure("Couldn't save that. Try again in a moment.")
	end

	return result
end

-- Shows or hides the player's recent trades on their public profile and in
-- the feed. Returns { success, message?, shareTrades }.
function SocialService.setShareTrades(player, shareTrades: boolean)
	local data = PlayerDataService.get(player)

	if not data then
		return failure("Your data is still loading.")
	end

	data.Social.ShareTrades = shareTrades

	-- Published straight away rather than within the minute, so turning
	-- sharing off reaches other servers as soon as their profile caches expire
	PublicProfileService.publishNow(player)

	-- Trades already in the feed go too; turning sharing back on doesn't
	-- restore them
	if not shareTrades then
		task.spawn(FeedService.removeTrades, player.UserId)
	end

	return { success = true, shareTrades = shareTrades }
end

function SocialService.start()
	task.spawn(function()
		while true do
			task.wait(SWEEP_INTERVAL)

			for userId, cached in pairs(followerCache) do
				if os.clock() - cached.fetchedAt > FOLLOWER_CACHE_SECONDS then
					followerCache[userId] = nil
				end
			end
		end
	end)
end

return SocialService
