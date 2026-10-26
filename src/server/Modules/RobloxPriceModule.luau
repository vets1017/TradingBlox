-- RobloxPriceModule.luau
--
-- The simulated price of a Roblox-market experience (GDD §6), and the
-- candles its price history makes. Kept free of Roblox services so the Lune
-- tests can run it; RobloxMarketService applies it every five minutes.
--
-- The price chases a target made from observed stats:
--   target = BASE_PRICE x sqrt(activity / 100) x like x momentum x freshness
-- where activity is players online averaged over about a day (so the
-- day-night cycle barely moves it), like comes from the like ratio, momentum
-- from a week's growth in activity, and freshness from how recently the
-- experience was updated. The square root keeps a 300k-player experience
-- pricier than a 3k one without being 100 times pricier. The price closes in
-- on the target over about half a day, never moving more than
-- DAILY_MOVE_CAP of itself per 24 hours that pass - so after a gap with no
-- ticks it may catch up further, in proportion.
--
-- One experience's saved state:
--   { price, prevClose, day, activity, activityByDay = { [day] = activity },
--     target, listedAt, lastSeenAt, missingSince?, stats = latest observed }

local RobloxPriceModule = {}

RobloxPriceModule.BASE_PRICE = 10 -- dollars at 100 players online, before the other factors
RobloxPriceModule.DAILY_MOVE_CAP = 0.10
RobloxPriceModule.DELIST_AFTER = 86400 -- missing from Roblox's answers this long delists it

local DAY = 86400
local ACTIVITY_TAU = DAY -- the players-online average spans about a day
local PRICE_TAU = 12 * 3600
local MOMENTUM_DAYS = 7
local MOMENTUM_MIN, MOMENTUM_MAX = 0.5, 2
local MOMENTUM_EXPONENT = 0.25
local DEFAULT_LIKE_RATIO = 0.8 -- before an experience has any votes
local ACTIVITY_DAYS_KEPT = MOMENTUM_DAYS + 1

-- Price history: every point for a week, then one an hour for 90 days, then
-- one a day for two years
local FULL_DETAIL_SECONDS = 7 * DAY
local HOURLY_SECONDS = 90 * DAY
local KEPT_SECONDS = 730 * DAY

local function roundCents(amount: number): number
	return math.round(amount * 100) / 100
end

function RobloxPriceModule.dayKey(now: number): string
	return os.date("!%Y-%m-%d", now)
end

-- 0.5 for an experience everyone dislikes, 1.5 for one everyone likes
function RobloxPriceModule.likeFactor(upVotes: number?, downVotes: number?): number
	local total = (upVotes or 0) + (downVotes or 0)
	local ratio = if total > 0 then (upVotes or 0) / total else DEFAULT_LIKE_RATIO

	return 0.5 + ratio
end

-- A little above 1 for a recent update, a little below for a long-abandoned
-- experience
function RobloxPriceModule.freshnessFactor(updatedAt: number?, now: number): number
	if not updatedAt then
		return 1
	end

	local days = (now - updatedAt) / DAY

	if days <= 14 then
		return 1.05
	elseif days <= 90 then
		return 1
	elseif days <= 365 then
		return 0.95
	end

	return 0.9
end

-- Growth in activity over a week, capped and damped: doubling gives about
-- 1.19, halving about 0.84; 1 until there's a week to compare with
function RobloxPriceModule.momentumFactor(activityNow: number, activityThen: number?): number
	if not activityThen or activityThen <= 0 then
		return 1
	end

	local ratio = math.clamp(activityNow / activityThen, MOMENTUM_MIN, MOMENTUM_MAX)

	return ratio ^ MOMENTUM_EXPONENT
end

function RobloxPriceModule.targetPrice(activity: number, like: number, momentum: number, freshness: number): number
	return RobloxPriceModule.BASE_PRICE * math.sqrt(math.max(activity, 1) / 100) * like * momentum * freshness
end

-- Moves `price` toward `target` over `elapsed` seconds
function RobloxPriceModule.step(price: number, target: number, elapsed: number): number
	local wanted = (target - price) * (1 - math.exp(-elapsed / PRICE_TAU))
	local cap = price * RobloxPriceModule.DAILY_MOVE_CAP * elapsed / DAY

	return price + math.clamp(wanted, -cap, cap)
end

-- The next state of one experience after a tick at `now`, given its newly
-- observed `stats` ({ playing, upVotes, downVotes, updated, ... }); a nil
-- `state` lists it, with the price starting at its target
function RobloxPriceModule.tick(state, stats, now: number)
	local today = RobloxPriceModule.dayKey(now)
	local playing = math.max(stats.playing or 0, 0)
	local activity, price, prevClose, listedAt, activityByDay

	if state then
		local elapsed = math.max(now - state.lastSeenAt, 0)
		local alpha = 1 - math.exp(-elapsed / ACTIVITY_TAU)

		activity = state.activity + (playing - state.activity) * alpha
		activityByDay = table.clone(state.activityByDay or {})
		listedAt = state.listedAt
		-- The last price of the previous day is this day's close to compare with
		prevClose = if state.day ~= today then state.price else state.prevClose
	else
		activity = playing
		activityByDay = {}
		listedAt = now
	end

	activityByDay[today] = activity

	-- Only the last ACTIVITY_DAYS_KEPT days are needed
	local oldest = RobloxPriceModule.dayKey(now - (ACTIVITY_DAYS_KEPT - 1) * DAY)

	for day in pairs(activityByDay) do
		if day < oldest then
			activityByDay[day] = nil
		end
	end

	local weekAgo = activityByDay[RobloxPriceModule.dayKey(now - MOMENTUM_DAYS * DAY)]
	local target = RobloxPriceModule.targetPrice(
		activity,
		RobloxPriceModule.likeFactor(stats.upVotes, stats.downVotes),
		RobloxPriceModule.momentumFactor(activity, weekAgo),
		RobloxPriceModule.freshnessFactor(stats.updated, now)
	)

	if state then
		price = RobloxPriceModule.step(state.price, target, math.max(now - state.lastSeenAt, 0))
	else
		price = target
		prevClose = roundCents(target)
	end

	return {
		price = roundCents(price),
		prevClose = prevClose,
		day = today,
		activity = activity,
		activityByDay = activityByDay,
		target = roundCents(target),
		listedAt = listedAt,
		lastSeenAt = now,
		stats = stats,
	}
end

-- A tick that didn't get the experience's stats: everything holds, and the
-- time it went missing is noted for shouldDelist
function RobloxPriceModule.hold(state, now: number)
	local held = table.clone(state)

	held.missingSince = state.missingSince or now

	return held
end

function RobloxPriceModule.shouldDelist(state, now: number): boolean
	return state.missingSince ~= nil and now - state.missingSince >= RobloxPriceModule.DELIST_AFTER
end

-- The whole market's next saved state after a tick at `now`:
-- { lastTickAt, experiences = { [ticker] = state } }. `listing` is
-- Config/RobloxMarket.EXPERIENCES and `statsById` the backend's answer, keyed
-- by universe id strings. An experience Roblox didn't answer for holds, and
-- delists after DELIST_AFTER; one dropped from the listing delists at once.
-- Either way it keeps its last price, which holdings settle at.
function RobloxPriceModule.tickMarket(market, listing, statsById, now: number)
	local previous = market and market.experiences or {}
	local experiences = {}

	for _, listed in ipairs(listing) do
		local prior = previous[listed.ticker]
		local stats = statsById[tostring(listed.universeId)]

		if prior and prior.delisted then
			experiences[listed.ticker] = prior
		elseif stats then
			experiences[listed.ticker] = RobloxPriceModule.tick(prior, stats, now)
		elseif prior then
			local held = RobloxPriceModule.hold(prior, now)

			if RobloxPriceModule.shouldDelist(held, now) then
				held.delisted = true
				held.delistedAt = now
			end

			experiences[listed.ticker] = held
		end
	end

	for ticker, prior in pairs(previous) do
		if not experiences[ticker] then
			local delisted = table.clone(prior)

			delisted.delisted = true
			delisted.delistedAt = prior.delistedAt or now
			experiences[ticker] = delisted
		end
	end

	return { lastTickAt = now, experiences = experiences }
end

-- Appends a price point ({ time, price }, oldest first) and thins older
-- ones: full detail for a week, then the last point of each hour, then of
-- each day, and nothing past two years
function RobloxPriceModule.addPoint(points, now: number, price: number)
	table.insert(points, { now, price })

	local kept = {}
	local lastBucket = nil

	for _, point in ipairs(points) do
		local age = now - point[1]

		if age <= FULL_DETAIL_SECONDS then
			table.insert(kept, point)
			lastBucket = nil
		elseif age <= KEPT_SECONDS then
			local size = if age <= HOURLY_SECONDS then 3600 else DAY
			local bucket = size .. ":" .. (point[1] // size)

			-- Points arrive in time order, so a later one in the same bucket replaces it
			if bucket == lastBucket then
				kept[#kept] = point
			else
				table.insert(kept, point)
			end

			lastBucket = bucket
		end
	end

	return kept
end

-- Candles of `interval` seconds from price points (oldest first), for the
-- points at or after `since`, in the chart's shape. Each candle opens at the
-- previous one's close, so the line has no gaps between them.
function RobloxPriceModule.buildCandles(points, interval: number, since: number)
	local candles = {}
	local previousClose = nil

	for _, point in ipairs(points) do
		local time, price = point[1], point[2]
		local bucketStart = (time // interval) * interval
		local candle = candles[#candles]

		if time >= since then
			if candle and candle.Timestamp == bucketStart then
				candle.Close = price
				candle.High = math.max(candle.High, price)
				candle.Low = math.min(candle.Low, price)
			else
				local open = previousClose or price

				candle = {
					Timestamp = bucketStart,
					Open = open,
					High = math.max(open, price),
					Low = math.min(open, price),
					Close = price,
					Volume = 0,
				}
				table.insert(candles, candle)
			end
		end

		previousClose = price
	end

	return candles
end

return RobloxPriceModule
