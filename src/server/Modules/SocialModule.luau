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
