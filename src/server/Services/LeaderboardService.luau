-- LeaderboardService.luau
--
-- Scores players on the boards in ReplicatedStorage.Config.Leaderboards and
-- serves the top pages. Each board and period is its own OrderedDataStore
-- (e.g. "LB_WeeklyReturn_W2964"), so a new week or month starts a fresh
-- board and old ones stay readable.
--
-- A period's return is measured from the player's net worth when they
-- first showed up in that period, kept in playerData.Leaderboard.
--
-- Reads are cached per server: GetSortedAsync allows only 5 + 2 x players
-- calls a minute per server, so one fetch serves every player for a minute.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local UserService = game:GetService("UserService")

local Leaderboards = require(ReplicatedStorage.Config.Leaderboards)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local OrderEvents = require(ServerScriptService.Services.OrderEvents)

local PAGE_CACHE_SECONDS = 60
local RETURN_PERIODS = { "Week", "Month" }

local pageCache = {} -- [storeName] = { fetchedAt = os.clock(), page = {...} }
local fetchesInFlight = {} -- [storeName] = true while a GetSortedAsync is running
-- [player] = { [storeName] = last stored score }, to skip unchanged writes.
-- Weak keys: a leaving player's final submit can land after PlayerRemoving.
local submitted = setmetatable({}, { __mode = "k" })

local LeaderboardService = {}

local function getStoreName(board, now)
	return "LB_" .. board.id .. "_" .. Leaderboards.getPeriodKey(board.period, now)
end

-- Starts a new week or month for the player when one has begun, measured
-- from `netWorth`
local function rollPeriods(periodData, netWorth, now)
	for _, period in ipairs(RETURN_PERIODS) do
		local key = Leaderboards.getPeriodKey(period, now)

		if periodData[period] ~= key then
			periodData[period] = key
			periodData[period .. "Start"] = netWorth
			periodData[period .. "Trades"] = 0
		end
	end
end

local function onFill(player, _, now)
	local data = PlayerDataService.get(player)

	if not data then
		return
	end

	-- A fill swaps cash for a position at market, so the net worth from just
	-- before it is the right baseline if this fill opens a new period
	rollPeriods(data.Leaderboard, player:GetAttribute("NetWorth") or data.Balance, now)

	for _, period in ipairs(RETURN_PERIODS) do
		data.Leaderboard[period .. "Trades"] += 1
	end
end

-- The boards a player qualifies for right now: { [boardId] = score }, with
-- returns as fractions (0.12 = +12%)
function LeaderboardService.getScores(player, data, netWorth: number, now: number)
	local periodData = data.Leaderboard
	local scores = {}

	rollPeriods(periodData, netWorth, now)

	for _, board in ipairs(Leaderboards.BOARDS) do
		local minTrades = Leaderboards.MIN_TRADES[board.period]

		if board.metric == "netWorth" then
			if data.Stats.Trades >= minTrades then
				scores[board.id] = netWorth
			end
		else
			local start = periodData[board.period .. "Start"]
			local isOldEnough = player.AccountAge >= Leaderboards.MIN_ACCOUNT_AGE_DAYS

			if isOldEnough and periodData[board.period .. "Trades"] >= minTrades and start > 0 then
				scores[board.id] = (netWorth - start) / start
			end
		end
	end

	return scores
end

-- Writes the player's qualifying scores, skipping any that haven't changed
function LeaderboardService.submit(player, scores, now: number)
	local lastScores = submitted[player]

	if not lastScores then
		lastScores = {}
		submitted[player] = lastScores
	end

	for boardId, score in pairs(scores) do
		local board = Leaderboards.getBoard(boardId)
		local storeName = getStoreName(board, now)
		local stored = Leaderboards.encodeScore(board, score)

		if lastScores[storeName] ~= stored then
			local store = DataStoreService:GetOrderedDataStore(storeName)
			local success, err = pcall(store.SetAsync, store, tostring(player.UserId), stored)

			if success then
				lastScores[storeName] = stored
			else
				warn("[LeaderboardService] Couldn't save " .. storeName .. " for " .. player.Name .. ": " .. tostring(err))
			end
		end
	end
end

-- { [userId] = { displayName, username } } in one request; names fall back
-- to "Player <id>" if the lookup fails
local function getNames(userIds)
	local names = {}
	local success, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, userIds)

	if success then
		for _, info in ipairs(infos) do
			names[info.Id] = { displayName = info.DisplayName, username = info.Username }
		end
	else
		warn("[LeaderboardService] Name lookup failed: " .. tostring(infos))
	end

	return names
end

local function fetchPage(board, storeName, now)
	local store = DataStoreService:GetOrderedDataStore(storeName)
	local success, pages = pcall(store.GetSortedAsync, store, false, Leaderboards.PAGE_SIZE)

	if not success then
		warn("[LeaderboardService] Couldn't read " .. storeName .. ": " .. tostring(pages))

		return nil
	end

	local items = pages:GetCurrentPage()
	local userIds = {}

	for _, item in ipairs(items) do
		table.insert(userIds, tonumber(item.key))
	end

	local names = #userIds > 0 and getNames(userIds) or {}
	local entries = {}

	for rank, item in ipairs(items) do
		local userId = tonumber(item.key)
		local name = names[userId]

		table.insert(entries, {
			rank = rank,
			userId = userId,
			displayName = name and name.displayName or ("Player " .. item.key),
			username = name and name.username,
			score = Leaderboards.decodeScore(board, item.value),
		})
	end

	return {
		boardId = board.id,
		periodLabel = Leaderboards.getPeriodLabel(board.period, now),
		entries = entries,
	}
end

-- The board's top page, at most a minute old. Players asking at the same
-- moment share one read.
function LeaderboardService.getPage(boardId: string)
	local board = Leaderboards.getBoard(boardId)

	if not board then
		return nil
	end

	local now = os.time()
	local storeName = getStoreName(board, now)

	while fetchesInFlight[storeName] do
		task.wait()
	end

	local cached = pageCache[storeName]

	if cached and os.clock() - cached.fetchedAt < PAGE_CACHE_SECONDS then
		return cached.page
	end

	fetchesInFlight[storeName] = true

	local page = fetchPage(board, storeName, now)

	fetchesInFlight[storeName] = nil

	if not page then
		return cached and cached.page -- stale beats nothing
	end

	pageCache[storeName] = { fetchedAt = os.clock(), page = page }

	return page
end

function LeaderboardService.start()
	OrderEvents.Filled:Connect(onFill)
end

return LeaderboardService
