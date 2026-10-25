-- SocialModule.luau
--
-- The rules for following players and for what a public profile shares,
-- kept free of Roblox services so the Lune tests can run them.
-- SocialService applies them to player data (`playerData.Social`).

local SocialModule = {}

-- Following is keyed by user id strings: DataStores can't save a table
-- whose keys are sparse numbers
local function toKey(userId: number): string
	return tostring(userId)
end

function SocialModule.isFollowing(social, userId: number): boolean
	return social.Following[toKey(userId)] ~= nil
end

function SocialModule.countFollowing(social): number
	local count = 0

	for _ in pairs(social.Following) do
		count += 1
	end

	return count
end

-- Whether `ownUserId` may start following `targetUserId`; when not, also
-- returns the reason to show the player
function SocialModule.checkFollow(social, ownUserId: number, targetUserId: number, maxFollowing: number)
	if targetUserId == ownUserId then
		return false, "You can't follow yourself."
	end

	if SocialModule.countFollowing(social) >= maxFollowing then
		return false, string.format("You can follow up to %d players.", maxFollowing)
	end

	return true, nil
end

function SocialModule.setFollowing(social, userId: number, isFollowing: boolean, now: number)
	social.Following[toKey(userId)] = if isFollowing then now else nil
end

function SocialModule.isMuted(social, userId: number): boolean
	return social.Muted[toKey(userId)] ~= nil
end

-- Whether `ownUserId` may mute `targetUserId`, and why not
function SocialModule.checkMute(social, ownUserId: number, targetUserId: number, maxMuted: number)
	if targetUserId == ownUserId then
		return false, "You can't mute yourself."
	end

	local count = 0

	for _ in pairs(social.Muted) do
		count += 1
	end

	if count >= maxMuted then
		return false, string.format("You can mute up to %d players.", maxMuted)
	end

	return true, nil
end

function SocialModule.setMuted(social, userId: number, isMuted: boolean, now: number)
	social.Muted[toKey(userId)] = if isMuted then now else nil
end

-- Adds `key` to a map of key -> time, dropping the oldest entry past `cap`
function SocialModule.addCapped(map, key: string, now: number, cap: number)
	map[key] = now

	local count, oldestKey, oldestTime = 0, nil, math.huge

	for existingKey, time in pairs(map) do
		count += 1

		if time < oldestTime then
			oldestKey, oldestTime = existingKey, time
		end
	end

	if count > cap and oldestKey then
		map[oldestKey] = nil
	end
end

-- The player's own reaction on a feed item, or nil
function SocialModule.getReaction(social, itemId: string): string?
	local entry = social.Reactions[itemId]

	return entry and entry.reaction
end

-- Records (or with nil, clears) the player's reaction on a feed item,
-- forgetting the oldest past `cap`; feed items expire anyway
function SocialModule.setReaction(social, itemId: string, reaction: string?, now: number, cap: number)
	local reactions = social.Reactions

	if not reaction then
		reactions[itemId] = nil

		return
	end

	reactions[itemId] = { reaction = reaction, at = now }

	local count, oldestId, oldestAt = 0, nil, math.huge

	for id, entry in pairs(reactions) do
		count += 1

		if entry.at < oldestAt then
			oldestId, oldestAt = id, entry.at
		end
	end

	if count > cap and oldestId then
		reactions[oldestId] = nil
	end
end

-- A player's latest `limit` fills from their trade log (oldest first), newest
-- first, as copies: the public snapshot is saved apart from the profile
function SocialModule.getRecentTrades(tradeLog, limit: number)
	local trades = {}

	for index = #tradeLog, math.max(#tradeLog - limit + 1, 1), -1 do
		local fill = tradeLog[index]

		table.insert(trades, {
			time = fill.time,
			ticker = fill.ticker,
			contract = fill.contract,
			side = fill.side,
			quantity = fill.quantity,
			price = fill.price,
			realizedPL = fill.realizedPL,
			settlement = fill.settlement,
		})
	end

	return trades
end

return SocialModule
