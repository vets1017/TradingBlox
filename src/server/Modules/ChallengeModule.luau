-- ChallengeModule.luau
--
-- Pure rules for daily challenges and streaks: which challenges a player
-- gets on a day, what advances them, and how the streak grows or breaks. The
-- challenge definitions (Config/Challenges) are passed in, and there are no
-- Roblox services, so it's unit tested.
--
-- A player's `daily` (playerData.Daily):
--   Day         the UTC day number the challenges are for
--   Challenges  { { id, progress, done, seen = { [key] = true } } }, `seen`
--               only for `distinct` challenges
--   StreakDays  the streak's length when it was last extended
--   StreakDay   the UTC day it was last extended
--   BestStreak  the longest streak

local ChallengeModule = {}

local DAY = 86400
local RANDOM_MODULUS = 2147483647 -- Park-Miller; every product stays exact in a double
local RANDOM_MULTIPLIER = 16807

function ChallengeModule.dayOf(now: number): number
	return now // DAY
end

function ChallengeModule.resetsAt(day: number): number
	return (day + 1) * DAY
end

-- The day's challenges for one player: `count` of the eligible ones in
-- `pool`, in an order seeded by the day and the player, so they're the same
-- all day on every server
function ChallengeModule.pick(pool, count: number, day: number, userId: number, isEligible: (any) -> boolean)
	local eligible = {}

	for _, challenge in ipairs(pool) do
		if isEligible(challenge) then
			table.insert(eligible, challenge.id)
		end
	end

	local seed = (day * 7919 + userId) % (RANDOM_MODULUS - 1) + 1

	-- Fisher-Yates, front to back, only as far as needed
	for index = 1, math.min(count, #eligible) do
		seed = seed * RANDOM_MULTIPLIER % RANDOM_MODULUS

		local swap = index + seed % (#eligible - index + 1)

		eligible[index], eligible[swap] = eligible[swap], eligible[index]
	end

	local picked = {}

	for index = 1, math.min(count, #eligible) do
		table.insert(picked, { id = eligible[index], progress = 0, done = false, seen = {} })
	end

	return picked
end

-- event = { kind: "fill" | "thesis" | "reaction", key: string? (ticker or
-- post id, for `distinct`), side?, assetClass?, profit: boolean?, option: boolean? }
function ChallengeModule.matches(challenge, event): boolean
	if challenge.event ~= event.kind then
		return false
	elseif challenge.side and challenge.side ~= event.side then
		return false
	elseif challenge.assetClass and challenge.assetClass ~= event.assetClass then
		return false
	elseif challenge.profit and not event.profit then
		return false
	elseif challenge.option and not event.option then
		return false
	end

	return true
end

-- Moves one of the day's challenges (`entry`, defined by `challenge`) along
-- for `event`. Returns whether its progress changed, and whether that
-- finished it.
function ChallengeModule.advance(entry, challenge, event): (boolean, boolean)
	if entry.done or not ChallengeModule.matches(challenge, event) then
		return false, false
	end

	if challenge.distinct then
		if not event.key or entry.seen[event.key] then
			return false, false
		end

		entry.seen[event.key] = true
	end

	entry.progress += 1

	if entry.progress >= challenge.goal then
		entry.done = true

		return true, true
	end

	return true, false
end

-- The first finished challenge of a day extends the streak: by a day if one
-- was finished yesterday, else it starts again at 1. Returns the new length,
-- or nil if the streak was already extended today.
function ChallengeModule.extendStreak(daily, day: number): number?
	if daily.StreakDay == day then
		return nil
	end

	daily.StreakDays = daily.StreakDay == day - 1 and daily.StreakDays + 1 or 1
	daily.StreakDay = day
	daily.BestStreak = math.max(daily.BestStreak, daily.StreakDays)

	return daily.StreakDays
end

-- The streak as it stands on `day`: still alive until a whole day passes
-- with nothing finished
function ChallengeModule.currentStreak(daily, day: number): number
	return daily.StreakDay >= day - 1 and daily.StreakDays or 0
end

return ChallengeModule
