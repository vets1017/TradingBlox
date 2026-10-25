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
local RemoteGuard = require(ServerScriptService.Modules.RemoteGuard)
local Leaderboards = require(ReplicatedStorage.Config.Leaderboards)

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
RemoteGuard.handle(GetPublicProfileEvent, RemoteGuard.LIMITS.Research, function(_player, userId)
	if type(userId) ~= "number" or userId ~= math.floor(userId) or userId <= 0 then
		return nil
	end

	return PublicProfileService.get(userId)
end)
