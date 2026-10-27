-- Challenges.luau
--
-- Daily challenges and the streak they keep. Each UTC day every player gets
-- PER_DAY challenges from POOL, picked for them from the ones they can do
-- that day; finishing one earns XP, and finishing at least one a day keeps
-- their streak going, which earns a growing bonus. Shared so the client can
-- word and explain them; ChallengeService enforces them.

local Challenges = {}

Challenges.PER_DAY = 3
Challenges.XP = 30 -- per challenge
Challenges.STREAK_XP_PER_DAY = 10 -- the streak bonus: this times the streak's length...
Challenges.STREAK_XP_MAX_DAYS = 7 -- ...counting at most this many days

-- `event` is what advances a challenge: "fill" (a filled order), "thesis"
-- (publishing one) or "reaction" (reacting to a feed post). For fills,
-- `side`, `assetClass` (Config/Instruments), `profit` and `option` narrow it
-- down. `distinct` counts different tickers (or posts) instead of events.
-- `feature` is an unlock it needs (Config/Progression); `stockMarket` means
-- it needs NYSE to open that day.
Challenges.POOL = {
	{ id = "Trade3", text = "Make 3 trades", event = "fill", goal = 3 },
	{ id = "Tickers3", text = "Trade 3 different tickers", event = "fill", distinct = true, goal = 3 },
	{
		id = "BuyStock",
		text = "Buy a stock or ETF",
		event = "fill",
		side = "Buy",
		assetClass = "security",
		stockMarket = true,
		goal = 1,
	},
	{ id = "BuyCrypto", text = "Buy some crypto", event = "fill", side = "Buy", assetClass = "crypto", goal = 1 },
	{
		id = "BuyRoblox",
		text = "Buy shares of a Roblox game",
		event = "fill",
		side = "Buy",
		assetClass = "roblox",
		goal = 1,
	},
	{ id = "SellProfit", text = "Sell something for a profit", event = "fill", side = "Sell", profit = true, goal = 1 },
	{ id = "Thesis", text = "Publish a thesis on any ticker", event = "thesis", goal = 1 },
	{ id = "React2", text = "React to 2 posts in the feed", event = "reaction", distinct = true, goal = 2 },
	{ id = "Option", text = "Trade an option contract", event = "fill", option = true, feature = "Options", goal = 1 },
}

local byId = {}

for _, challenge in ipairs(Challenges.POOL) do
	byId[challenge.id] = challenge
end

function Challenges.get(id: string)
	return byId[id]
end

-- The streak bonus for reaching `days` in a row
function Challenges.getStreakXP(days: number): number
	return Challenges.STREAK_XP_PER_DAY * math.min(days, Challenges.STREAK_XP_MAX_DAYS)
end

return Challenges
