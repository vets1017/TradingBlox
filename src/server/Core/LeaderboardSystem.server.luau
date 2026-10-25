-- LeaderboardSystem.server.luau
--
-- Leaderboards tab remotes: a board's top page and any player's public
-- profile. Both read DataStores, so RemoteGuard limits them on top of the
-- services' own caches.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LeaderboardService = require(ServerScriptService.Services.LeaderboardService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local PublicProfileService = require(ServerScriptService.Services.PublicProfileService)
local SocialService = require(ServerScriptService.Services.SocialService)
local ThesisService = require(ServerScriptService.Services.ThesisService)
local ThesisModule = require(ServerScriptService.Modules.ThesisModule)
local RemoteGuard = require(ServerScriptService.Modules.RemoteGuard)
local Leaderboards = require(ReplicatedStorage.Config.Leaderboards)
local Social = require(ReplicatedStorage.Config.Social)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetLeaderboardEvent = EventsFolder:WaitForChild("GetLeaderboardEvent")
local GetPublicProfileEvent = EventsFolder:WaitForChild("GetPublicProfileEvent")

-- GetLeaderboardEvent
-- Returns { boardId, periodLabel, entries = { rank, userId, displayName,
-- username, score }, you = { score } }, where `you.score` is the caller's
-- live score (nil until they qualify) since the cached page can lag.
RemoteGuard.handle(GetLeaderboardEvent, RemoteGuard.LIMITS.Research, function(player, boardId)
	if type(boardId) ~= "string" or not Leaderboards.getBoard(boardId) then
		return nil
	end

	local page = LeaderboardService.getPage(boardId)

	if not page then
		return nil
	end

	local data = PlayerDataService.get(player)
	local netWorth = player:GetAttribute("NetWorth")
	local yourScore = nil

	if data and netWorth then
		yourScore = LeaderboardService.getScores(player, data, netWorth, os.time())[boardId]
	end

	-- The page is shared by every caller, so the caller's part goes on a copy
	return {
		boardId = page.boardId,
		periodLabel = page.periodLabel,
		entries = page.entries,
		you = { score = yourScore },
	}
end)

-- GetPublicProfileEvent
-- Returns the player's public snapshot (see PublicProfileService) plus
-- `followers` (nil if unknown) and `isFollowing` (whether the caller follows
-- them), or nil if they have no public profile. `theses` comes newest first,
-- without text for callers whose accounts can't chat.
RemoteGuard.handle(GetPublicProfileEvent, RemoteGuard.LIMITS.Research, function(player, userId)
	if type(userId) ~= "number" or userId ~= math.floor(userId) or userId <= 0 then
		return nil
	end

	local snapshot = PublicProfileService.get(userId)

	if not snapshot then
		return nil
	end

	-- Cached snapshots are shared by every caller, so the caller's part goes on a copy
	local profile = table.clone(snapshot)

	profile.followers = SocialService.getFollowerCount(userId)
	profile.isFollowing = SocialService.isFollowing(player, userId)
	profile.theses =
		ThesisModule.forViewer(snapshot.theses or {}, Social.PROFILE_THESES, ThesisService.canUseText(player))

	return profile
end)
