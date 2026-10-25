-- RemoteGuard.luau
--
-- Per-player rate limits for every RemoteFunction. Most remotes cost the
-- server an HTTP call or a DataStore read, and those are budgeted per server
-- (500 HTTP requests a minute; DataStore reads by player count), so one
-- client flooding a remote could starve everyone else on the server.
--
-- Each remote gets a token bucket per player: up to `burst` requests at
-- once, refilling at `perMinute`. A request with no token left gets the
-- remote's limited result instead of running - nil for reads (clients treat
-- it as "no data this time"), or a failed result for orders.

local RemoteGuard = {}

-- Pick the tier that matches how often the real UI calls the remote
RemoteGuard.LIMITS = {
	Poll = { perMinute = 120, burst = 20 }, -- live charts refresh every few seconds
	Read = { perMinute = 60, burst = 10 }, -- positions, orders, quotes on demand
	Order = { perMinute = 60, burst = 10 }, -- one-click presets can fire quickly
	Research = { perMinute = 30, burst = 6 }, -- tabs, panels, boards and profiles
	Rare = { perMinute = 10, burst = 5 }, -- things a player does a handful of times
}

-- What a remote that reports success or failure (orders, watchlist edits)
-- answers when the player is over its limit
RemoteGuard.TOO_MANY_REQUESTS = { success = false, message = "Too many requests. Slow down a moment." }

-- [player] = { [remoteName] = { tokens, updatedAt } }; weak keys, so a
-- player who leaves drops out without cleanup
local buckets = setmetatable({}, { __mode = "k" })

local function takeToken(player, remoteName, limit)
	local playerBuckets = buckets[player]

	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end

	local now = os.clock()
	local bucket = playerBuckets[remoteName]

	if not bucket then
		bucket = { tokens = limit.burst, updatedAt = now }
		playerBuckets[remoteName] = bucket
	end

	bucket.tokens = math.min(limit.burst, bucket.tokens + (now - bucket.updatedAt) * limit.perMinute / 60)
	bucket.updatedAt = now

	if bucket.tokens < 1 then
		return false
	end

	bucket.tokens -= 1

	return true
end

-- Sets remote.OnServerInvoke to run handler(player, ...) while the player is
-- within `limit`, and to return `limitedResult` (nil by default) once over it
function RemoteGuard.handle(remote, limit, handler, limitedResult)
	local remoteName = remote.Name

	remote.OnServerInvoke = function(player, ...)
		if not takeToken(player, remoteName, limit) then
			return limitedResult
		end

		return handler(player, ...)
	end
end

return RemoteGuard
