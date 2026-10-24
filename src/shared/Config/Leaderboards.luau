-- Leaderboards.luau
--
-- The leaderboards (GDD §9), the period each one covers, and who qualifies.
-- Shared so the client can explain eligibility; LeaderboardService scores
-- players. OrderedDataStores hold integers only, so scores are stored in
-- cents (net worth) or basis points (returns).

local Leaderboards = {}

Leaderboards.BOARDS = {
	{ id = "NetWorth", name = "Net worth", period = "AllTime", metric = "netWorth" },
	{ id = "WeeklyReturn", name = "Weekly return", period = "Week", metric = "return" },
	{ id = "MonthlyReturn", name = "Monthly return", period = "Month", metric = "return" },
}

-- Trades needed in the board's period before a player appears on it. The
-- GDD asks boards to account for sample size, so one lucky trade can't top a
-- return board.
Leaderboards.MIN_TRADES = {
	AllTime = 1,
	Week = 3,
	Month = 3,
}

-- Return boards only: keeps throwaway alt accounts out
Leaderboards.MIN_ACCOUNT_AGE_DAYS = 7

Leaderboards.PAGE_SIZE = 50

local WEEK = 7 * 86400
local FIRST_MONDAY = 4 * 86400 -- 1970-01-05 00:00 UTC; weeks run Monday to Sunday, UTC

function Leaderboards.getBoard(boardId: string)
	for _, board in ipairs(Leaderboards.BOARDS) do
		if board.id == boardId then
			return board
		end
	end

	return nil
end

-- A string that changes when a new period starts: "all", "W2964", "2026-10"
function Leaderboards.getPeriodKey(period: string, now: number): string
	if period == "Week" then
		return "W" .. (now - FIRST_MONDAY) // WEEK
	elseif period == "Month" then
		return os.date("!%Y-%m", now)
	end

	return "all"
end

-- "Week of Oct 19", "October 2026", "All time"
function Leaderboards.getPeriodLabel(period: string, now: number): string
	if period == "Week" then
		local weekStart = FIRST_MONDAY + ((now - FIRST_MONDAY) // WEEK) * WEEK
		local date = os.date("!*t", weekStart)

		return string.format("Week of %s %d", os.date("!%b", weekStart), date.day)
	elseif period == "Month" then
		return os.date("!%B %Y", now)
	end

	return "All time"
end

function Leaderboards.encodeScore(board, score: number): number
	local scale = board.metric == "netWorth" and 100 or 10000

	return math.floor(score * scale + 0.5)
end

function Leaderboards.decodeScore(board, stored: number): number
	local scale = board.metric == "netWorth" and 100 or 10000

	return stored / scale
end

return Leaderboards
