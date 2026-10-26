-- RobloxPriceModule.luau
--
-- The simulated price of a Roblox-market experience (GDD §6), and the
-- candles its price history makes. Kept free of Roblox services so the Lune
-- tests (and tools/simulate-roblox-market.luau) can run it;
-- RobloxMarketService applies it every minute.
--
-- The price chases a target made from observed stats:
--   target = BASE_PRICE x sqrt(activity / 100) x like x momentum x freshness
-- where activity is players online averaged over the last seven days, hour
-- by hour - a whole number of days and weeks, so the day-night cycle and
-- weekends cancel out and a price can't be farmed on a schedule. Like comes
-- from the like ratio, momentum from a week's growth in activity, and
-- freshness from how recently the experience was updated. The square root
-- keeps a 300k-player experience pricier than a 3k one without being 100
-- times pricier. The price closes in on the target over about half a day,
-- never moving more than DAILY_MOVE_CAP of itself per 24 hours that pass -
-- so after a gap with no ticks it may catch up further, in proportion.
--
-- That smooth path is the trend. Live activity moves the price faster: the
-- players online right now against the usual for this hour of the week (the
-- same time a week before) make a surge, which the price follows within
-- minutes - up to SURGE_LIMIT either way - and which fades as the activity
-- does. Comparing like with like, a steady game's daily and weekly cycles
-- make no surge, so it can't be farmed on a schedule. fair = trend x surge.
--
-- The traded price wanders around the fair price:
-- price = fair x e^noise, where the noise is jolted at random and drifts back
-- to zero over about a day (keeping a spread of NOISE_SPREAD), so charts
-- move like a market's, candles get wicks, and a minute's move is close to
-- a coin flip - nothing to scalp. Each tick walks the noise in sub-steps and
-- keeps the range it covered, which is the candle's high and low.
--
-- A newly listed experience warms up for WARMUP_SECONDS before it trades:
-- until its average covers a full day, the time of day it was listed would
-- skew the price. While warming up the trend simply follows the target.
--
-- One experience's saved state:
--   { price, high, low, trend, surge, usual?, fair, noise, prevClose, day, activity,
--     hours = { { hour, mean } }, current = { hour, sum, count },
--     activityByDay = { [day] = activity }, target, listedAt, opensAt,
--     lastSeenAt, missingSince?, stats }
-- where price is the last tick's close and high/low its range.
--
-- A price point, in `recent` and the history, is { time, close, high?, low? }.

local RobloxPriceModule = {}

RobloxPriceModule.BASE_PRICE = 10 -- dollars at 100 players online, before the other factors
RobloxPriceModule.DAILY_MOVE_CAP = 0.10
RobloxPriceModule.DELIST_AFTER = 86400 -- missing from Roblox's answers this long delists it
RobloxPriceModule.WARMUP_SECONDS = 86400
RobloxPriceModule.FLUSH_SECONDS = 300 -- how often recent price points are written to the history
RobloxPriceModule.RECENT_SECONDS = 900 -- longer than a flush plus a reader's history cache
RobloxPriceModule.NOISE_SPREAD = 0.025 -- typical distance of the price from its fair price
RobloxPriceModule.NOISE_TAU = 86400 -- how long the noise takes to fade back, roughly
RobloxPriceModule.SURGE_RESPONSE = 0.35 -- price change per change in activity, on log scales
RobloxPriceModule.SURGE_LIMIT = math.log(1.25) -- at most 25% up, or the same down
RobloxPriceModule.SURGE_TAU = 600 -- how fast the price follows a surge

local DAY = 86400
local HOUR = 3600
local WINDOW_HOURS = 7 * 24
-- Hours kept: the window plus two, so the same time a week before always has
-- an hour either side to interpolate between
local KEPT_HOURS = WINDOW_HOURS + 2
local PRICE_TAU = 12 * HOUR
local MOMENTUM_DAYS = 7
local MOMENTUM_MIN, MOMENTUM_MAX = 0.5, 2
local MOMENTUM_EXPONENT = 0.25
local DEFAULT_LIKE_RATIO = 0.8 -- before an experience has any votes
local ACTIVITY_DAYS_KEPT = MOMENTUM_DAYS + 1
local NOISE_LIMIT = 3 * RobloxPriceModule.NOISE_SPREAD
-- Steps the noise takes within a tick: with fewer, a minute's path often
-- peaks at its open or close and the candle has no wick
local SUBSTEP_SECONDS = 1
local MAX_SUBSTEPS = 60

-- Price history detail by age: every point for a day, then one per bucket
local HISTORY_ZONES = {
	{ maxAge = DAY, bucket = nil },
	{ maxAge = 7 * DAY, bucket = 300 },
	{ maxAge = 90 * DAY, bucket = HOUR },
	{ maxAge = 730 * DAY, bucket = DAY },
}

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
-- 1.19, halving about 0.84; 1 until there's a full week's average from a
-- week ago to compare with
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

-- Adds a players-online sample to the hourly buckets: `current` gathers
-- this hour's samples, and each finished hour keeps just its mean. Hours
-- older than KEPT_HOURS drop off. Returns new tables.
function RobloxPriceModule.addSample(hours, current, playing: number, now: number)
	local hour = now // HOUR
	local newHours = table.clone(hours or {})
	local newCurrent = current and table.clone(current)

	if newCurrent and newCurrent.hour ~= hour then
		if newCurrent.count > 0 then
			table.insert(newHours, { newCurrent.hour, math.round(newCurrent.sum / newCurrent.count) })
		end

		newCurrent = nil
	end

	newCurrent = newCurrent or { hour = hour, sum = 0, count = 0 }
	newCurrent.sum += playing
	newCurrent.count += 1

	while newHours[1] and newHours[1][1] <= hour - KEPT_HOURS do
		table.remove(newHours, 1)
	end

	return newHours, newCurrent
end

-- Players online over the window (this hour and the WINDOW_HOURS - 1 before
-- it): the mean of the hourly means, so an hour with more samples counts no
-- more than one with fewer
function RobloxPriceModule.activityFrom(hours, current): number
	local total, count = 0, 0
	local oldest = if current then current.hour - WINDOW_HOURS + 1 else -math.huge

	for _, entry in ipairs(hours) do
		if entry[1] >= oldest then
			total += entry[2]
			count += 1
		end
	end

	if current and current.count > 0 then
		total += current.sum / current.count
		count += 1
	end

	return if count > 0 then total / count else 0
end

local function hourlyMean(hours, hour: number): number?
	for _, entry in ipairs(hours) do
		if entry[1] == hour then
			return entry[2]
		end
	end

	return nil
end

-- Players online at `time` by the hourly means, interpolated between the
-- middles of the hours either side, so a climb within an hour isn't read as
-- a surprise; nil without either hour
local function playingAt(hours, time: number): number?
	local position = (time - HOUR / 2) / HOUR
	local before = position // 1
	local weight = position - before
	local first = hourlyMean(hours, before)
	local second = hourlyMean(hours, before + 1)

	if first and second then
		return first + (second - first) * weight
	end

	return first or second
end

local function isWeekend(time: number): boolean
	local weekday = os.date("!%w", time)

	return weekday == "0" or weekday == "6"
end

-- The players usually online at `now`: the same time a week before. Until a
-- week is kept, the same time the day before, unless one of the two days is
-- a weekend and the other isn't, when there's nothing like to compare with.
function RobloxPriceModule.usualPlaying(hours, now: number): number?
	local weekBefore = playingAt(hours, now - 7 * DAY)

	if weekBefore then
		return weekBefore
	end

	if isWeekend(now) ~= isWeekend(now - DAY) then
		return nil
	end

	return playingAt(hours, now - DAY)
end

-- Where the surge heads (on a log scale) for `playing` players online
-- against `usual`: 0 without a usual to compare with
function RobloxPriceModule.surgeTarget(playing: number, usual: number?): number
	if not usual or usual <= 0 then
		return 0
	end

	local change = math.log(math.max(playing, 1) / usual)

	return math.clamp(
		RobloxPriceModule.SURGE_RESPONSE * change,
		-RobloxPriceModule.SURGE_LIMIT,
		RobloxPriceModule.SURGE_LIMIT
	)
end

-- A standard normal number from two uniform ones in [0, 1) (Box-Muller)
local function normal(random: () -> number): number
	local u = math.max(random(), 1e-12)

	return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * random())
end

-- The noise `elapsed` seconds on: it fades toward zero and gets a random
-- jolt sized so its spread stays NOISE_SPREAD (an Ornstein-Uhlenbeck step)
function RobloxPriceModule.stepNoise(noise: number, elapsed: number, random: () -> number): number
	local decay = math.exp(-elapsed / RobloxPriceModule.NOISE_TAU)
	local jolt = RobloxPriceModule.NOISE_SPREAD * math.sqrt(1 - decay * decay) * normal(random)

	return math.clamp(noise * decay + jolt, -NOISE_LIMIT, NOISE_LIMIT)
end

function RobloxPriceModule.isOpen(state, now: number): boolean
	return state.opensAt == nil or now >= state.opensAt
end

-- The next state of one experience after a tick at `now`, given its newly
-- observed `stats` ({ playing, upVotes, downVotes, updated, ... }). A nil
-- `state` - or one saved before the hourly average existed - lists it, and
-- it warms up before trading. `random` (uniform in [0, 1)) drives the noise;
-- without it the price is the fair price's smooth path, which tests use.
function RobloxPriceModule.tick(state, stats, now: number, random: (() -> number)?)
	local today = RobloxPriceModule.dayKey(now)
	local isListing = not state or not state.hours
	local prior = if isListing then nil else state
	local playing = math.max(stats.playing or 0, 0)
	local hours, current = RobloxPriceModule.addSample(prior and prior.hours, prior and prior.current, playing, now)
	local activity = RobloxPriceModule.activityFrom(hours, current)
	local activityByDay = table.clone(prior and prior.activityByDay or {})

	-- Only a full week's average is kept for momentum: comparing it with a
	-- shorter one would read the weekend coming into the window as growth
	if #hours >= WINDOW_HOURS - 1 then
		activityByDay[today] = activity
	end

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
	local opensAt = if prior then prior.opensAt else now + RobloxPriceModule.WARMUP_SECONDS
	local elapsed = if prior then math.max(now - prior.lastSeenAt, 0) else 0
	-- States saved before the surge have only a fair price, and before the
	-- noise only a price; either was the trend
	local priorTrend = prior and (prior.trend or prior.fair or prior.price)
	local priorFair = prior and priorTrend * math.exp(prior.surge or 0)
	local trend

	if not prior or now < opensAt then
		-- Warming up: no trades yet, so the price can follow the target freely
		trend = target
	else
		trend = RobloxPriceModule.step(priorTrend, target, elapsed)
	end

	-- The surge closes in on where live activity puts it over SURGE_TAU
	local usual = RobloxPriceModule.usualPlaying(hours, now)
	local surge = prior and prior.surge or 0
	local follow = 1 - math.exp(-elapsed / RobloxPriceModule.SURGE_TAU)

	surge += (RobloxPriceModule.surgeTarget(playing, usual) - surge) * follow

	local fair = trend * math.exp(surge)

	-- The path since the last tick: the fair price moves evenly, the noise in
	-- sub-steps, and the range they cover is this tick's high and low
	local noise = prior and prior.noise or 0
	local high, low = -math.huge, math.huge

	if prior then
		high, low = prior.price, prior.price
	end

	if random and prior and elapsed > 0 then
		local steps = math.clamp(math.round(elapsed / SUBSTEP_SECONDS), 1, MAX_SUBSTEPS)

		for index = 1, steps do
			noise = RobloxPriceModule.stepNoise(noise, elapsed / steps, random)

			local passing = priorFair * (fair / priorFair) ^ (index / steps) * math.exp(noise)

			high = math.max(high, passing)
			low = math.min(low, passing)
		end
	end

	local price = fair * math.exp(noise)

	high = math.max(high, price)
	low = math.min(low, price)

	local prevClose

	if not prior or now < opensAt then
		prevClose = price
	else
		-- The last price of the previous day is this day's close to compare with
		prevClose = if prior.day ~= today then prior.price else prior.prevClose
	end

	-- Prices are kept exact: a minute's move can be well under a cent, and
	-- rounding every tick would stall a cheap price or speed up a dear one.
	-- What players see (publicView, the history) is rounded to cents.
	return {
		price = price,
		high = high,
		low = low,
		trend = trend,
		surge = surge,
		usual = usual and math.round(usual),
		fair = fair,
		noise = noise,
		prevClose = prevClose,
		day = today,
		activity = activity,
		hours = hours,
		current = current,
		activityByDay = activityByDay,
		target = roundCents(target),
		listedAt = prior and prior.listedAt or now,
		opensAt = opensAt,
		lastSeenAt = now,
		stats = stats,
	}
end

-- A tick that didn't get the experience's stats: everything holds, and the
-- time it went missing is noted for shouldDelist
function RobloxPriceModule.hold(state, now: number)
	local held = table.clone(state)

	-- Nothing moved, so no range this tick
	held.high = nil
	held.low = nil
	held.missingSince = state.missingSince or now

	return held
end

function RobloxPriceModule.shouldDelist(state, now: number): boolean
	return state.missingSince ~= nil and now - state.missingSince >= RobloxPriceModule.DELIST_AFTER
end

-- The whole market's next saved state after a tick at `now`, and the price
-- points due for the history (nil when none are due):
--   { lastTickAt, flushedAt, recent = { [ticker] = { { time, price } } },
--     experiences = { [ticker] = state } }
-- `listing` is Config/RobloxMarket.EXPERIENCES and `statsById` the backend's
-- answer, keyed by universe id strings. An experience Roblox didn't answer
-- for holds, and delists after DELIST_AFTER; one dropped from the listing
-- delists at once. Either way it keeps its last price, which holdings settle
-- at. Each listed experience gets a price point every tick - while warming
-- up too, so its chart shows the price forming. `recent` keeps the
-- last RECENT_SECONDS of them, for charts to show before the history has
-- them; every FLUSH_SECONDS the points since the last flush are due, so the
-- history is written in batches rather than every minute.
function RobloxPriceModule.tickMarket(market, listing, statsById, now: number, random: (() -> number)?)
	local previous = market and market.experiences or {}
	local experiences = {}

	for _, listed in ipairs(listing) do
		local prior = previous[listed.ticker]
		local stats = statsById[tostring(listed.universeId)]

		if prior and prior.delisted then
			experiences[listed.ticker] = prior
		elseif stats then
			experiences[listed.ticker] = RobloxPriceModule.tick(prior, stats, now, random)
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

	local previousRecent = market and market.recent or {}
	local recent = {}

	for ticker, experience in pairs(experiences) do
		local points = {}

		for _, point in ipairs(previousRecent[ticker] or {}) do
			if point[1] > now - RobloxPriceModule.RECENT_SECONDS then
				table.insert(points, point)
			end
		end

		if not experience.delisted then
			local close = roundCents(experience.price)
			local high = roundCents(experience.high or experience.price)
			local low = roundCents(experience.low or experience.price)

			-- A flat tick needs no range
			table.insert(points, if high ~= close or low ~= close then { now, close, high, low } else { now, close })
		end

		if #points > 0 then
			recent[ticker] = points
		end
	end

	local flushedAt = market and market.flushedAt
	local flush = nil

	if not flushedAt or now - flushedAt >= RobloxPriceModule.FLUSH_SECONDS then
		for ticker, points in pairs(recent) do
			local due = {}

			for _, point in ipairs(points) do
				if not flushedAt or point[1] > flushedAt then
					table.insert(due, point)
				end
			end

			if #due > 0 then
				flush = flush or {}
				flush[ticker] = due
			end
		end

		flushedAt = now
	end

	return { lastTickAt = now, flushedAt = flushedAt, recent = recent, experiences = experiences }, flush
end

-- What every server reads: the market without the averaging internals,
-- small enough to read often. Each experience keeps { price, prevClose,
-- target, activity, usual, listedAt, opensAt, delisted, delistedAt, stats,
-- recent }.
function RobloxPriceModule.publicView(market)
	local experiences = {}

	for ticker, experience in pairs(market.experiences) do
		experiences[ticker] = {
			price = roundCents(experience.price),
			prevClose = roundCents(experience.prevClose),
			target = experience.target,
			activity = math.round(experience.activity or 0),
			usual = experience.usual,
			listedAt = experience.listedAt,
			opensAt = experience.opensAt,
			delisted = experience.delisted,
			delistedAt = experience.delistedAt,
			stats = experience.stats,
			recent = market.recent and market.recent[ticker],
		}
	end

	return { lastTickAt = market.lastTickAt, experiences = experiences }
end

-- A saved history with the market's recent points in place of its own from
-- the same stretch - the saved copy may be minutes behind
function RobloxPriceModule.withRecent(points, recent)
	if not recent or #recent == 0 then
		return points
	end

	local merged = {}

	for _, point in ipairs(points) do
		if point[1] < recent[1][1] then
			table.insert(merged, point)
		end
	end

	table.move(recent, 1, #recent, #merged + 1, merged)

	return merged
end

-- A point's range; points saved without one only have their close
local function rangeOf(point)
	return point[3] or point[2], point[4] or point[2]
end

-- Appends price points ({ time, close, high?, low? }, in time order) to a
-- history kept oldest first, and thins it by age: every point for a day,
-- then one per five minutes to a week, per hour to 90 days, per day to two
-- years, and nothing older. A thinned point keeps its bucket's last time
-- and close and the whole bucket's range. Points merge by time, so a batch
-- written twice isn't doubled and one written late still lands in order.
function RobloxPriceModule.addPoints(points, newPoints, now: number)
	local all = table.clone(points)
	local isAfter = true -- the usual case: every new point is later than the history

	for _, point in ipairs(newPoints) do
		local last = all[#all]

		if last and point[1] <= last[1] then
			isAfter = false

			break
		end

		table.insert(all, point)
	end

	if not isAfter then
		all = table.clone(points)

		local times = {}

		for _, point in ipairs(points) do
			times[point[1]] = true
		end

		for _, point in ipairs(newPoints) do
			if not times[point[1]] then
				table.insert(all, point)
				times[point[1]] = true
			end
		end

		table.sort(all, function(a, b)
			return a[1] < b[1]
		end)
	end

	local kept = {}
	local lastZone, lastBucket = nil, nil

	for _, point in ipairs(all) do
		local age = now - point[1]
		local zone = nil

		for _, candidate in ipairs(HISTORY_ZONES) do
			if age <= candidate.maxAge then
				zone = candidate

				break
			end
		end

		if zone and not zone.bucket then
			table.insert(kept, point)
			lastZone = nil
		elseif zone then
			local bucket = point[1] // zone.bucket

			-- In time order, a later point in the same bucket takes its place,
			-- widened to the range of both
			if zone == lastZone and bucket == lastBucket then
				local previous = kept[#kept]
				local high, low = rangeOf(point)
				local previousHigh, previousLow = rangeOf(previous)

				kept[#kept] = { point[1], point[2], math.max(high, previousHigh), math.min(low, previousLow) }
			else
				table.insert(kept, point)
			end

			lastZone, lastBucket = zone, bucket
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
		local high, low = rangeOf(point)
		local bucketStart = (time // interval) * interval
		local candle = candles[#candles]

		if time >= since then
			if candle and candle.Timestamp == bucketStart then
				candle.Close = price
				candle.High = math.max(candle.High, high, price)
				candle.Low = math.min(candle.Low, low, price)
			else
				local open = previousClose or price

				candle = {
					Timestamp = bucketStart,
					Open = open,
					High = math.max(open, high, price),
					Low = math.min(open, low, price),
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
