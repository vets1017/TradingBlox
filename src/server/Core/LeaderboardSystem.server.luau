-- LeaderboardSystem.server.luau
--
-- Leaderboards tab remotes: a board's top page and any player's public
-- profile. Both read DataStores, so each is limited to one request a second
-- per player on top of the services' own caches.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LeaderboardService = require(ServerScriptService.Services.LeaderboardService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local PublicProfileService = require(ServerScriptService.Services.PublicProfileService)
local Leaderboards = require(ReplicatedStorage.Config.Leaderboards)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetLeaderboardEvent = EventsFolder:WaitForChild("GetLeaderboardEvent")
local GetPublicProfileEvent = EventsFolder:WaitForChild("GetPublicProfileEvent")

local REQUEST_COOLDOWN = 1

local lastRequestAt = {} -- [player] = { [remoteName] = os.clock() }

local function isThrottled(player, remoteName)
	local perRemote = lastRequestAt[player]

	if not perRemote then
		perRemote = {}
		lastRequestAt[player] = perRemote
	end

	local now = os.clock()

	if now - (perRemote[remoteName] or -math.huge) < REQUEST_COOLDOWN then
		return true
	end

	perRemote[remoteName] = now

	return false
end

-- GetLeaderboardEvent
-- Returns { boardId, periodLabel, entries = { rank, userId, displayName,
-- username, score }, you = { score } }, where `you.score` is the caller's
-- live score (nil until they qualify) since the cached page can lag.
-- Limited per board, so flicking between boards isn't refused; checking the
-- id first keeps a client from minting endless throttle keys.
GetLeaderboardEvent.OnServerInvoke = function(player, boardId)
	if type(boardId) ~= "string" or not Leaderboards.getBoard(boardId) then
		return nil
	end

	if isThrottled(player, "GetLeaderboardEvent:" .. boardId) then
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
end

-- GetPublicProfileEvent
GetPublicProfileEvent.OnServerInvoke = function(player, userId)
	if type(userId) ~= "number" or userId ~= math.floor(userId) or userId <= 0 then
		return nil
	end

	if isThrottled(player, "GetPublicProfileEvent") then
		return nil
	end

	return PublicProfileService.get(userId)
end

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
end)
