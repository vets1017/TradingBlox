-- PublicProfileService.luau
--
-- Each player's public "financial résumé" (GDD §2): net worth, return since
-- starting, win rate, average gain and loss, drawdown, level, trades, join
-- date and a 30-day net-worth line. The server holding the player's session
-- writes a snapshot to the PublicProfile DataStore - a minute after a trade
-- at most, every 5 minutes, and as they leave - and submits the same numbers
-- to the leaderboards, so any server can show any player.
--
-- The latest trades are included only while the player shares them (see
-- SocialService); holdings stay private.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Economy = require(ReplicatedStorage.Config.Economy)
local Progression = require(ReplicatedStorage.Config.Progression)
local Social = require(ReplicatedStorage.Config.Social)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local LeaderboardService = require(ServerScriptService.Services.LeaderboardService)
local OrderEvents = require(ServerScriptService.Services.OrderEvents)
local TradeLogModule = require(ServerScriptService.Modules.TradeLogModule)
local PortfolioHistoryModule = require(ServerScriptService.Modules.PortfolioHistoryModule)
local SocialModule = require(ServerScriptService.Modules.SocialModule)

local SnapshotStore = DataStoreService:GetDataStore("PublicProfile_v1")

local PUBLISH_INTERVAL = 300
local MIN_SECONDS_BETWEEN_PUBLISHES = 60
local FILL_SETTLE_SECONDS = 5 -- lets the post-trade net worth reprice land first
local READ_CACHE_SECONDS = 60
local HISTORY_RANGE = 30 * 86400

-- Weak keys, so a player who has left drops out on their own
local lastPublishedAt = setmetatable({}, { __mode = "k" }) -- [player] = os.clock()
local isPublishScheduled = setmetatable({}, { __mode = "k" })

local readCache = {} -- [userId] = { fetchedAt = os.clock(), snapshot = {...} or false }

local PublicProfileService = {}

local function buildSnapshot(player, data, netWorth: number, now: number)
	local summary = TradeLogModule.getSummary(data.Stats)

	return {
		userId = player.UserId,
		displayName = player.DisplayName,
		username = player.Name,
		level = Progression.getLevel(data.Progression.XP),
		netWorth = netWorth,
		totalReturn = (netWorth - Economy.STARTING_BALANCE) / Economy.STARTING_BALANCE,
		trades = data.Stats.Trades,
		closedTrades = summary.closedTrades,
		winRate = summary.winRate,
		averageGain = summary.averageGain,
		averageLoss = summary.averageLoss,
		realizedPL = summary.realizedPL,
		maxDrawdown = PortfolioHistoryModule.getMaxDrawdown(data.NetWorthHistory),
		joinedAt = data.Stats.JoinedAt,
		history = PortfolioHistoryModule.getRange(data.NetWorthHistory, HISTORY_RANGE, now),
		following = SocialModule.countFollowing(data.Social),
		sharesTrades = data.Social.ShareTrades,
		-- Left out while private, so those trades never reach the DataStore
		recentTrades = if data.Social.ShareTrades
			then SocialModule.getRecentTrades(data.TradeLog, Social.RECENT_TRADES)
			else nil,
		updatedAt = now,
	}
end

-- Builds the snapshot and scores before the first yield, so callers on the
-- way out (onPlayerLeaving) can spawn this and still capture final data
local function publish(player, data)
	local netWorth = player:GetAttribute("NetWorth")

	data = data or PlayerDataService.get(player)

	if not data or not netWorth then
		return
	end

	local now = os.time()
	local snapshot = buildSnapshot(player, data, netWorth, now)
	local scores = LeaderboardService.getScores(player, data, netWorth, now)

	lastPublishedAt[player] = os.clock()
	readCache[player.UserId] = { fetchedAt = os.clock(), snapshot = snapshot }

	local success, err = pcall(SnapshotStore.SetAsync, SnapshotStore, tostring(player.UserId), snapshot)

	if not success then
		warn("[PublicProfileService] Couldn't save the profile of " .. player.Name .. ": " .. tostring(err))
	end

	LeaderboardService.submit(player, scores, now)
end

-- At most one publish a minute per player, however fast they trade
local function requestPublish(player)
	if isPublishScheduled[player] then
		return
	end

	local sinceLast = os.clock() - (lastPublishedAt[player] or -math.huge)
	local delay = math.max(FILL_SETTLE_SECONDS, MIN_SECONDS_BETWEEN_PUBLISHES - sinceLast)

	isPublishScheduled[player] = true

	task.delay(delay, function()
		isPublishScheduled[player] = nil

		if player.Parent == Players then
			publish(player)
		end
	end)
end

-- Publishes the player's profile now, skipping the once-a-minute limit; for
-- changes other servers should see quickly, like turning trade sharing off
function PublicProfileService.publishNow(player)
	task.spawn(publish, player)
end

-- A player's public profile, or nil if they've never had one published.
-- Players on this server are built live; anyone else is read from the
-- DataStore, cached for a minute.
function PublicProfileService.get(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	local data = player and PlayerDataService.get(player)
	local netWorth = player and player:GetAttribute("NetWorth")

	if data and netWorth then
		return buildSnapshot(player, data, netWorth, os.time())
	end

	local cached = readCache[userId]

	if cached and os.clock() - cached.fetchedAt < READ_CACHE_SECONDS then
		return cached.snapshot or nil
	end

	local success, snapshot = pcall(SnapshotStore.GetAsync, SnapshotStore, tostring(userId))

	if not success then
		warn("[PublicProfileService] Couldn't read the profile of " .. userId .. ": " .. tostring(snapshot))

		return cached and cached.snapshot or nil
	end

	-- false caches "no profile", so a missing one isn't re-read every request
	readCache[userId] = { fetchedAt = os.clock(), snapshot = snapshot or false }

	return snapshot
end

function PublicProfileService.start()
	OrderEvents.Filled:Connect(requestPublish)

	PlayerDataService.onPlayerLeaving(function(player, data)
		task.spawn(publish, player, data)
	end)

	task.spawn(function()
		while true do
			task.wait(PUBLISH_INTERVAL)

			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(publish, player)
			end

			for userId, cached in pairs(readCache) do
				if os.clock() - cached.fetchedAt > READ_CACHE_SECONDS then
					readCache[userId] = nil
				end
			end
		end
	end)
end

return PublicProfileService
