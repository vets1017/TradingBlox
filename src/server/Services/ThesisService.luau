-- ThesisService.luau
--
-- Theses (GDD §2): a player's structured view on one ticker - bullish or
-- bearish, a time horizon, and an optional target price and text. The
-- author's profile keeps their latest theses (`playerData.Social.Theses`);
-- DataStore TickerTheses_v1 keeps each ticker's latest, written with
-- UpdateAsync because authors on every server add to it. Each thesis also
-- goes into the feed.
--
-- Text: Roblox filters text only while its sender is connected to the
-- server, so it's filtered for broadcast when it's published and only the
-- filtered result is saved. Only players whose accounts allow chat can write
-- text or see other players' text.
--
-- Reports go to DataStore Reports_v1 (one key per thesis) for review, with
-- the thesis as it was reported. Enough of them take the thesis down.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local Social = require(ReplicatedStorage.Config.Social)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local PublicProfileService = require(ServerScriptService.Services.PublicProfileService)
local FeedService = require(ServerScriptService.Services.FeedService)
local MuteService = require(ServerScriptService.Services.MuteService)
local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local ThesisModule = require(ServerScriptService.Modules.ThesisModule)

local TickerStore = DataStoreService:GetDataStore("TickerTheses_v1")
local ReportStore = DataStoreService:GetDataStore("Reports_v1")

local TICKER_CACHE_SECONDS = 60
local SWEEP_INTERVAL = 300

local tickerCache = {} -- [ticker] = { fetchedAt = os.clock(), theses = {...} (oldest first) }
-- Weak keys, so a player who has left drops out on their own
local canChatCache = setmetatable({}, { __mode = "k" }) -- [player] = boolean
local isPublishing = setmetatable({}, { __mode = "k" }) -- [player] = true while a publish or delete saves

local ThesisService = {}

local function failure(message: string)
	return { success = false, message = message }
end

-- Whether the player's account allows chat, asked once a session. A failed
-- check counts as no (and is asked again next time), so text is never taken
-- or shown by mistake.
function ThesisService.canUseText(player): boolean
	local cached = canChatCache[player]

	if cached ~= nil then
		return cached
	end

	local success, canChat = pcall(TextChatService.CanUserChatAsync, TextChatService, player.UserId)

	if not success then
		warn("[ThesisService] Couldn't check chat for " .. player.Name .. ": " .. tostring(canChat))

		return false
	end

	canChatCache[player] = canChat

	return canChat
end

local function filterForBroadcast(player, text: string): string?
	local success, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
			:GetNonChatStringForBroadcastAsync()
	end)

	if not success then
		warn("[ThesisService] Couldn't filter a thesis from " .. player.Name .. ": " .. tostring(result))

		return nil
	end

	return result
end

-- A ticker's theses (oldest first), cached a minute per server; the last
-- good copy, or nil, when the store can't be read
local function readTicker(ticker: string)
	local cached = tickerCache[ticker]

	if cached and os.clock() - cached.fetchedAt < TICKER_CACHE_SECONDS then
		return cached.theses
	end

	local success, theses = pcall(TickerStore.GetAsync, TickerStore, ticker)

	if not success then
		warn("[ThesisService] Couldn't read the theses on " .. ticker .. ": " .. tostring(theses))

		return cached and cached.theses
	end

	tickerCache[ticker] = { fetchedAt = os.clock(), theses = theses or {} }

	return theses or {}
end

-- Runs with the player's lock held; yields
local function publishThesis(player, ticker: string, draft)
	-- Only the fields a thesis has, so a client can't slip in others
	local clean = {
		direction = draft.direction,
		horizon = draft.horizon,
		targetPrice = draft.targetPrice,
		text = if type(draft.text) == "string" then ThesisModule.normalizeText(draft.text) else draft.text,
	}

	if clean.text ~= nil and not ThesisService.canUseText(player) then
		return failure("Your account's chat settings don't allow text. Publish without it.")
	end

	local price = MarketDataModule.getCurrentPrice(ticker)

	if not price then
		return failure("Couldn't price " .. ticker .. " right now. Try again in a moment.")
	end

	local isValid, message = ThesisModule.validate(clean, price, Social)

	if not isValid then
		return failure(message)
	end

	if clean.text then
		clean.text = filterForBroadcast(player, clean.text)

		if not clean.text then
			return failure("Couldn't check your text. Try again in a moment.")
		end
	end

	local data = PlayerDataService.get(player)

	if not data then
		return failure("Your data is still loading.")
	end

	local now = os.time()

	data.Social.ThesisSequence += 1

	local thesis = {
		id = string.format("%d-%d", player.UserId, data.Social.ThesisSequence),
		userId = player.UserId,
		displayName = player.DisplayName,
		username = player.Name,
		ticker = ticker,
		direction = clean.direction,
		horizon = clean.horizon,
		targetPrice = clean.targetPrice,
		priceAtPost = price,
		text = clean.text,
		createdAt = now,
		endsAt = now + Social.getHorizon(clean.horizon).seconds,
	}

	-- The ticker's list first: if it can't be saved, nothing was published
	local success, theses = pcall(TickerStore.UpdateAsync, TickerStore, ticker, function(list)
		return ThesisModule.addToList(list or {}, thesis, Social.THESES_PER_TICKER)
	end)

	if not success then
		warn("[ThesisService] Couldn't save a thesis on " .. ticker .. ": " .. tostring(theses))

		return failure("Couldn't publish that. Try again in a moment.")
	end

	tickerCache[ticker] = { fetchedAt = os.clock(), theses = theses }

	-- Gone only if the player left while the list saved
	data = PlayerDataService.get(player)

	if data then
		ThesisModule.addToList(data.Social.Theses, thesis, Social.THESES_KEPT)
		ThesisModule.countPublish(data.Social, now)
		PublicProfileService.publishNow(player)
	end

	task.spawn(FeedService.postThesis, player, thesis)

	return { success = true, thesis = thesis }
end

-- Takes a thesis off its ticker's list; returns whether that saved
local function removeFromTicker(thesis): boolean
	local ticker = thesis.ticker
	local success, theses = pcall(TickerStore.UpdateAsync, TickerStore, ticker, function(list)
		-- nil leaves the key as it is
		if not list or not ThesisModule.removeFromList(list, thesis.id) then
			return nil
		end

		return list
	end)

	if not success then
		warn("[ThesisService] Couldn't remove a thesis on " .. ticker .. ": " .. tostring(theses))

		return false
	end

	-- nil when there was nothing to remove from the ticker's list
	tickerCache[ticker] = if theses then { fetchedAt = os.clock(), theses = theses } else nil

	return true
end

local function deleteThesis(player, thesis)
	if not removeFromTicker(thesis) then
		return failure("Couldn't delete that. Try again in a moment.")
	end

	local data = PlayerDataService.get(player)

	if data then
		ThesisModule.removeFromList(data.Social.Theses, thesis.id)
		PublicProfileService.publishNow(player)
	end

	task.spawn(FeedService.removeThesis, thesis.id)

	return { success = true }
end

-- Runs `action(player, ...)` under the player's lock: two overlapping
-- requests would both pass the checks made before it
local function withLock(player, action, ...)
	if isPublishing[player] then
		return failure("Still saving your last change.")
	end

	isPublishing[player] = true

	local ok, result = pcall(action, player, ...)

	isPublishing[player] = nil

	if not ok then
		warn("[ThesisService] A thesis change failed for " .. player.Name .. ": " .. tostring(result))

		return failure("Couldn't save that. Try again in a moment.")
	end

	return result
end

-- Publishes a thesis on `ticker` from a client draft: { direction, horizon,
-- targetPrice?, text? }. Returns { success, message?, thesis? }.
function ThesisService.publish(player, ticker: string, draft)
	local data = PlayerDataService.get(player)

	if not data then
		return failure("Your data is still loading.")
	elseif type(draft) ~= "table" then
		return failure("Invalid thesis.")
	end

	ticker = string.upper(ticker)

	local now = os.time()

	if ThesisModule.findOpen(data.Social.Theses, ticker, now) then
		return failure("You already have an open thesis on " .. ticker .. ". Delete it to publish another.")
	end

	local isWithinLimit, limitMessage = ThesisModule.checkDailyLimit(data.Social, now, Social.THESES_PER_DAY)

	if not isWithinLimit then
		return failure(limitMessage)
	end

	return withLock(player, publishThesis, ticker, draft)
end

-- Deletes one of the player's own theses. Returns { success, message? }.
-- Deleting doesn't give back a thesis from the daily limit.
function ThesisService.delete(player, thesisId: string)
	local data = PlayerDataService.get(player)

	if not data then
		return failure("Your data is still loading.")
	end

	for _, thesis in ipairs(data.Social.Theses) do
		if thesis.id == thesisId then
			return withLock(player, deleteThesis, thesis)
		end
	end

	return failure("That thesis isn't yours, or it's already gone.")
end

-- Theses from `list` (oldest first) that `player` hasn't muted, blocked or
-- reported, as they may see them: newest first, text only if they can chat
function ThesisService.forViewer(player, list, limit: number)
	local filter = MuteService.getFilter(player)
	local visible = {}

	for _, thesis in ipairs(list) do
		if not filter.hidesUser(thesis.userId) and not filter.hidesThesis(thesis.id) then
			table.insert(visible, thesis)
		end
	end

	return ThesisModule.forViewer(visible, limit, ThesisService.canUseText(player))
end

-- A ticker's theses as `player` sees them, or nil if they can't be read:
-- { ticker, theses (newest first), counts = { Bullish, Bearish } (open
-- ones shown), canUseText, openThesisId (the player's own open one, if any) }
function ThesisService.getForTicker(player, ticker: string)
	ticker = string.upper(ticker)

	local theses = readTicker(ticker)

	if not theses then
		return nil
	end

	local now = os.time()
	local data = PlayerDataService.get(player)
	local openThesis = data and ThesisModule.findOpen(data.Social.Theses, ticker, now)
	local visible = ThesisService.forViewer(player, theses, Social.THESES_PER_TICKER)

	return {
		ticker = ticker,
		theses = visible,
		counts = ThesisModule.countOpen(visible, now),
		canUseText = ThesisService.canUseText(player),
		openThesisId = openThesis and openThesis.id,
	}
end

-- The thesis `thesisId` from its ticker's list, or else from its author's
-- public profile (a ticker keeps only its latest few)
local function findThesis(thesisId: string, ticker: string)
	for _, thesis in ipairs(readTicker(ticker) or {}) do
		if thesis.id == thesisId then
			return thesis
		end
	end

	local authorId = tonumber(string.match(thesisId, "^(%d+)%-%d+$"))
	local profile = authorId and PublicProfileService.get(authorId)

	for _, thesis in ipairs(profile and profile.theses or {}) do
		if thesis.id == thesisId then
			return thesis
		end
	end

	return nil
end

-- Off its ticker's list and the feed now, and out of its author's own list
-- once their profile gets the message (straight away if they're online)
local function takeDown(thesis)
	removeFromTicker(thesis)
	FeedService.removeThesis(thesis.id)
	PlayerDataService.sendMessage(thesis.userId, { kind = "ThesisRemoved", thesisId = thesis.id })
end

-- Reports someone else's thesis on `ticker`. Once recorded it's hidden from
-- the reporter; REPORTS_TO_TAKE_DOWN reports from established accounts take
-- it down for everyone. Returns { success, message? }.
function ThesisService.report(player, thesisId: string, ticker: string)
	if not PlayerDataService.get(player) then
		return failure("Your data is still loading.")
	end

	local thesis = findThesis(thesisId, string.upper(ticker))

	if not thesis then
		return failure("That thesis is already gone.")
	elseif thesis.userId == player.UserId then
		return failure("You can't report your own thesis.")
	end

	local counts = player.AccountAge >= Social.MIN_REPORTER_ACCOUNT_AGE_DAYS
	local now = os.time()
	local reachedThreshold = false

	local success, err = pcall(ReportStore.UpdateAsync, ReportStore, thesisId, function(record)
		local updated

		-- Reset on every run: UpdateAsync can run this more than once
		updated, reachedThreshold =
			ThesisModule.addReport(record, thesis, player.UserId, counts, now, Social.REPORTS_TO_TAKE_DOWN)

		return updated
	end)

	if not success then
		warn("[ThesisService] Couldn't record a report on " .. thesisId .. ": " .. tostring(err))

		return failure("Couldn't send the report. Try again in a moment.")
	end

	MuteService.hideThesis(player, thesisId)

	if reachedThreshold then
		task.spawn(takeDown, thesis)
	end

	return { success = true }
end

function ThesisService.start()
	-- A thesis taken down after reports leaves its author's own list too
	PlayerDataService.onMessage("ThesisRemoved", function(player, data, message)
		if type(message.thesisId) == "string" and ThesisModule.removeFromList(data.Social.Theses, message.thesisId) then
			PublicProfileService.publishNow(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(SWEEP_INTERVAL)

			for ticker, cached in pairs(tickerCache) do
				if os.clock() - cached.fetchedAt > TICKER_CACHE_SECONDS then
					tickerCache[ticker] = nil
				end
			end
		end
	end)
end

return ThesisService
