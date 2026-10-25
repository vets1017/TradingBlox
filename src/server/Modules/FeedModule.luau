-- FeedModule.luau
--
-- The shape of feed items and the rules for picking them, kept free of
-- Roblox services so the Lune tests can run them. FeedService stores the
-- items and serves them.
--
-- Every item names its author and its kind, so the feed can tell executed
-- trades (copied from the trade log, so they're real) from milestones and
-- opinions:
--   { kind = "Trade", userId, displayName, username, time,
--     ticker, contract?, side, quantity, price, realizedPL? }
--   { kind = "Milestone", userId, displayName, username, time,
--     milestone? (a Progression milestone), level? (a level reached) }
--   { kind = "Thesis", userId, displayName, username, time, thesisId,
--     ticker, direction, horizon, targetPrice? } - no text: the feed points
--     to the ticker, where the thesis shows in full
-- Stored items carry no id; FeedService adds `id` (the item's key) when it
-- reads them. Any item can carry `reactions` = { [reactionId] = count }.

local FeedModule = {}

-- Sorted map keys put the feed in time order: zero-padded milliseconds sort
-- as text, and the server tag and sequence keep keys from different
-- servers apart
function FeedModule.makeKey(timeMillis: number, serverTag: string, sequence: number): string
	return string.format("%014d-%s-%d", timeMillis, serverTag, sequence)
end

-- author = { userId, displayName, username }; fill is what the order logged
function FeedModule.makeTradeItem(author, fill, realizedPL: number?, now: number)
	return {
		kind = "Trade",
		userId = author.userId,
		displayName = author.displayName,
		username = author.username,
		time = now,
		ticker = fill.ticker,
		contract = fill.contract,
		side = fill.side,
		quantity = fill.quantity,
		price = fill.price,
		realizedPL = realizedPL,
	}
end

-- A milestone claimed (`milestone`) or a level reached (`level`)
function FeedModule.makeMilestoneItem(author, milestone: string?, level: number?, now: number)
	return {
		kind = "Milestone",
		userId = author.userId,
		displayName = author.displayName,
		username = author.username,
		time = now,
		milestone = milestone,
		level = level,
	}
end

function FeedModule.makeThesisItem(author, thesis)
	return {
		kind = "Thesis",
		userId = author.userId,
		displayName = author.displayName,
		username = author.username,
		time = thesis.createdAt,
		thesisId = thesis.id,
		ticker = thesis.ticker,
		direction = thesis.direction,
		horizon = thesis.horizon,
		targetPrice = thesis.targetPrice,
	}
end

-- A player's trades reach the feed at most once every `minGap` seconds, so
-- a burst of one-click fills doesn't bury everyone else. The skipped fills
-- still show on their profile.
function FeedModule.canPostTrade(lastPostedAt: number?, now: number, minGap: number): boolean
	return lastPostedAt == nil or now - lastPostedAt >= minGap
end

-- The first `limit` items (newest first, as stored) that `keep` accepts;
-- every item when there's no `keep`
function FeedModule.select(items, limit: number, keep: ((any) -> boolean)?)
	local selected = {}

	for _, item in ipairs(items) do
		if #selected >= limit then
			break
		end

		if not keep or keep(item) then
			table.insert(selected, item)
		end
	end

	return selected
end

-- Moves one player's reaction on `item` from `previous` to `reaction`
-- (either may be nil), keeping counts at zero or more and dropping zeros
function FeedModule.applyReaction(item, previous: string?, reaction: string?)
	local reactions = item.reactions or {}

	if previous and reactions[previous] then
		reactions[previous] -= 1

		if reactions[previous] <= 0 then
			reactions[previous] = nil
		end
	end

	if reaction then
		reactions[reaction] = (reactions[reaction] or 0) + 1
	end

	item.reactions = if next(reactions) then reactions else nil

	return item
end

-- Whether an item is one of `userId`'s trades, which leave the feed when
-- they stop sharing trades
function FeedModule.isTradeBy(item, userId: number): boolean
	return item.kind == "Trade" and item.userId == userId
end

-- Whether an item announces the thesis `thesisId`, which leaves the feed
-- when it's deleted
function FeedModule.isThesis(item, thesisId: string): boolean
	return item.kind == "Thesis" and item.thesisId == thesisId
end

return FeedModule
