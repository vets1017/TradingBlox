-- FeedService.luau
--
-- The social feed (GDD §2): executed trades, milestones and theses from
-- every player, newest first. Items live in one MemoryStore sorted map that every
-- server shares, capped by count and expiring after two days, because
-- MemoryStore memory is small (64 KB + 1.2 KB per concurrent user, for the
-- whole experience). Each server caches the latest items for a few seconds,
-- so reads grow with servers, not players. The feed is never the source of
-- truth: trades come from the trade log and milestones from progression.
--
-- Reactions are counts on the item itself, so they cost no extra reads and
-- expire with it. Who reacted with what is kept in each reactor's profile,
-- which is also what stops a player counting twice.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Social = require(ReplicatedStorage.Config.Social)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local ProgressionService = require(ServerScriptService.Services.ProgressionService)
local OrderEvents = require(ServerScriptService.Services.OrderEvents)
local MuteService = require(ServerScriptService.Services.MuteService)
local FeedModule = require(ServerScriptService.Modules.FeedModule)
local SocialModule = require(ServerScriptService.Modules.SocialModule)

local FeedMap = MemoryStoreService:GetSortedMap("Feed_v1")

local MAX_ITEMS = 120 -- about 30 KB; leaves room in the memory quota for other hot data
local ITEM_LIFETIME = 2 * 86400
local CACHE_SECONDS = 5
local TRIM_INTERVAL = 60
local MIN_SECONDS_BETWEEN_TRADES = 30 -- per player
local MIN_UPDATE_LIFETIME = 60 -- an item about to expire still takes a reaction

-- Tells this server's keys apart from every other server's
local SERVER_TAG = string.sub(HttpService:GenerateGUID(false), 1, 8)

local sequence = 0
local cachedItems = {} -- newest first, each with its `id`
local fetchedAt = -math.huge
local isFetching = false
-- Weak keys, so a player who has left drops out on their own
local lastTradePostedAt = setmetatable({}, { __mode = "k" }) -- [player] = os.time()
local isReacting = setmetatable({}, { __mode = "k" }) -- [player] = true while a reaction saves

local FeedService = {}

local function getAuthor(player)
	return { userId = player.UserId, displayName = player.DisplayName, username = player.Name }
end

local function refresh()
	isFetching = true

	local success, entries = pcall(FeedMap.GetRangeAsync, FeedMap, Enum.SortDirection.Descending, MAX_ITEMS)

	isFetching = false

	if not success then
		warn("[FeedService] Couldn't read the feed: " .. tostring(entries))

		return
	end

	local items = {}

	for _, entry in ipairs(entries) do
		local item = entry.value

		item.id = entry.key
		table.insert(items, item)
	end

	cachedItems = items
	fetchedAt = os.clock()
end

-- Shows on this server straight away, and on others at their next refresh
local function post(item)
	sequence += 1

	local key = FeedModule.makeKey(DateTime.now().UnixTimestampMillis, SERVER_TAG, sequence)
	local success, err = pcall(FeedMap.SetAsync, FeedMap, key, item, ITEM_LIFETIME)

	if not success then
		warn("[FeedService] Couldn't post to the feed: " .. tostring(err))

		return
	end

	local cached = table.clone(item)

	cached.id = key
	table.insert(cachedItems, 1, cached)

	if #cachedItems > MAX_ITEMS then
		table.remove(cachedItems)
	end
end

-- Keeps the map at MAX_ITEMS by dropping the oldest. Every server runs this;
-- removing a key another server already removed is harmless.
local function trim()
	local success, size = pcall(FeedMap.GetSizeAsync, FeedMap)

	if not success or size <= MAX_ITEMS then
		return
	end

	local readSuccess, oldest =
		pcall(FeedMap.GetRangeAsync, FeedMap, Enum.SortDirection.Ascending, math.min(size - MAX_ITEMS, 200))

	if not readSuccess then
		return
	end

	for _, entry in ipairs(oldest) do
		pcall(FeedMap.RemoveAsync, FeedMap, entry.key)
	end
end

local function onFill(player, realizedPL: number?, now: number, fill)
	local data = PlayerDataService.get(player)

	if not data or not data.Social.ShareTrades or not fill then
		return
	end

	if not FeedModule.canPostTrade(lastTradePostedAt[player], now, MIN_SECONDS_BETWEEN_TRADES) then
		return
	end

	lastTradePostedAt[player] = now
	post(FeedModule.makeTradeItem(getAuthor(player), fill, realizedPL, now))
end

local function onAchieved(player, kind: string, value)
	local author = getAuthor(player)
	local now = os.time()

	if kind == "Level" then
		post(FeedModule.makeMilestoneItem(author, nil, value, now))
	elseif Social.FEED_MILESTONES[value] then
		post(FeedModule.makeMilestoneItem(author, value, nil, now))
	end
end

-- The newest items for `view` ("All", or "Following" for the players
-- `player` follows), up to Social.FEED_PAGE_SIZE, leaving out players they
-- muted or blocked and theses they reported
function FeedService.getFeed(player, view: string)
	if os.clock() - fetchedAt >= CACHE_SECONDS and not isFetching then
		refresh()
	end

	local data = PlayerDataService.get(player)

	if view == "Following" and not data then
		return {}
	end

	local filter = MuteService.getFilter(player)
	local selected = FeedModule.select(cachedItems, Social.FEED_PAGE_SIZE, function(item)
		if filter.hidesUser(item.userId) or (item.thesisId and filter.hidesThesis(item.thesisId)) then
			return false
		end

		return view ~= "Following" or SocialModule.isFollowing(data.Social, item.userId)
	end)

	-- Copies, since the cache is shared and `yourReaction` is the viewer's own
	local items = {}

	for index, item in ipairs(selected) do
		local copy = table.clone(item)

		copy.yourReaction = data and SocialModule.getReaction(data.Social, item.id)
		items[index] = copy
	end

	return items
end

local function findCached(itemId: string)
	for _, item in ipairs(cachedItems) do
		if item.id == itemId then
			return item
		end
	end

	return nil
end

-- Runs with the player's lock held; yields
local function saveReaction(player, cached, previous: string?, reaction: string?)
	-- The item keeps its original expiry rather than starting two days over
	local remaining = math.max(ITEM_LIFETIME - (os.time() - cached.time), MIN_UPDATE_LIFETIME)
	local success, updated = pcall(FeedMap.UpdateAsync, FeedMap, cached.id, function(value)
		-- nil cancels: the item expired or was trimmed
		if value == nil then
			return nil
		end

		return FeedModule.applyReaction(value, previous, reaction)
	end, remaining)

	if not success then
		warn("[FeedService] Couldn't save a reaction: " .. tostring(updated))

		return { success = false, message = "Couldn't save that. Try again in a moment." }
	elseif not updated then
		return { success = false, message = "That post is gone." }
	end

	local data = PlayerDataService.get(player)

	if data then
		SocialModule.setReaction(data.Social, cached.id, reaction, os.time(), Social.MAX_REACTIONS_KEPT)
	end

	-- This server shows the new counts straight away; others at their next refresh
	cached.reactions = updated.reactions

	return { success = true, reactions = updated.reactions, yourReaction = reaction }
end

-- Sets the player's reaction on a feed item; nil takes theirs off. Returns
-- { success, message?, reactions, yourReaction }.
function FeedService.react(player, itemId: string, reaction: string?)
	local data = PlayerDataService.get(player)

	if not data then
		return { success = false, message = "Your data is still loading." }
	end

	local cached = findCached(itemId)

	if not cached then
		return { success = false, message = "That post is gone." }
	elseif cached.userId == player.UserId then
		return { success = false, message = "You can't react to your own post." }
	end

	local previous = SocialModule.getReaction(data.Social, itemId)

	if previous == reaction then
		return { success = true, reactions = cached.reactions, yourReaction = reaction }
	end

	-- Two overlapping clicks would both start from the same previous reaction
	if isReacting[player] then
		return { success = false, message = "Still saving your last reaction." }
	end

	isReacting[player] = true

	local ok, result = pcall(saveReaction, player, cached, previous, reaction)

	isReacting[player] = nil

	if not ok then
		warn("[FeedService] A reaction failed for " .. player.Name .. ": " .. tostring(result))

		return { success = false, message = "Couldn't save that. Try again in a moment." }
	end

	return result
end

-- Takes the items `matches` accepts out of the feed. Other servers drop
-- them at their next refresh.
local function removeWhere(matches: (any) -> boolean)
	local kept = {}

	for _, item in ipairs(cachedItems) do
		if not matches(item) then
			table.insert(kept, item)
		end
	end

	cachedItems = kept

	-- The whole map fits in one read, since it's capped at MAX_ITEMS
	local success, entries = pcall(FeedMap.GetRangeAsync, FeedMap, Enum.SortDirection.Descending, 200)

	if not success then
		warn("[FeedService] Couldn't read the feed to remove items: " .. tostring(entries))

		return
	end

	for _, entry in ipairs(entries) do
		if matches(entry.value) then
			pcall(FeedMap.RemoveAsync, FeedMap, entry.key)
		end
	end
end

-- For when a player stops sharing their trades
function FeedService.removeTrades(userId: number)
	removeWhere(function(item)
		return FeedModule.isTradeBy(item, userId)
	end)
end

function FeedService.postThesis(player, thesis)
	post(FeedModule.makeThesisItem(getAuthor(player), thesis))
end

-- For when a thesis is deleted
function FeedService.removeThesis(thesisId: string)
	removeWhere(function(item)
		return FeedModule.isThesis(item, thesisId)
	end)
end

function FeedService.start()
	OrderEvents.Filled:Connect(onFill)
	ProgressionService.Achieved:Connect(onAchieved)

	task.spawn(function()
		while true do
			task.wait(TRIM_INTERVAL)
			trim()
		end
	end)
end

return FeedService
