-- Progression.luau
--
-- Levels, what each one unlocks, and how XP is earned (GDD §8). Shared so
-- the client can show locks and what unlocks them; ProgressionService on the
-- server is what enforces them. Levels unlock tools, never capital.

local Progression = {}

Progression.LEVELS = {
	{ name = "Beginner", xp = 0 },
	{ name = "Investor", xp = 300 },
	{ name = "Advanced Trader", xp = 1000 },
	{ name = "Professional", xp = 3000 },
}

-- Feature -> the level that unlocks it. Stocks, ETFs, crypto, market
-- orders, positions and plain charts are always available. Crypto stays at
-- level 1 because it's the only market open on weekends.
Progression.FEATURES = {
	Fundamentals = 2, -- Fundamentals and Analyst Reports tabs
	ChartIndicators = 2, -- moving averages, RSI, MACD, Bollinger Bands
	Analytics = 2, -- portfolio analytics beyond positions and value
	LimitOrders = 2,
	StopOrders = 2, -- stop and stop-limit
	Options = 3, -- option chain, Option Stats tab, contract orders
	AdvancedIndicators = 3, -- ATR, VWAP, volume profile
}

-- How each feature reads in the level-up toast
Progression.FEATURE_NAMES = {
	Fundamentals = "fundamentals and analyst reports",
	ChartIndicators = "chart indicators",
	AdvancedIndicators = "advanced chart indicators",
	Analytics = "portfolio analytics",
	LimitOrders = "limit orders",
	StopOrders = "stop orders",
	Options = "options trading",
}

Progression.XP = {
	FIRST_TRADE_OF_DAY = 50,
	PER_FILL = 10,
	MAX_FILL_XP_PER_DAY = 100, -- so churning orders can't farm XP
}

-- One-time XP, each awarded once per player
Progression.MILESTONES = {
	FirstTrade = 50,
	FirstProfitableSale = 50,
	Diversified = 100, -- holding DIVERSIFIED_HOLDINGS positions at once
	TutorialComplete = 100, -- every TUTORIAL step done
}

Progression.DIVERSIFIED_HOLDINGS = 3

-- The getting-started checklist. A `milestone` step is done once that
-- milestone is claimed; the others are things only the client sees (opening
-- a screen) and are reported by it.
Progression.TUTORIAL = {
	{ id = "ViewedTicker", text = "Look up a stock on the Trade tab" },
	{ id = "FirstTrade", text = "Buy your first shares", milestone = true },
	{ id = "ViewedPortfolio", text = "Check your Portfolio tab" },
	{ id = "Diversified", text = "Hold 3 different positions", milestone = true },
	{ id = "FirstProfitableSale", text = "Sell something for a profit", milestone = true },
}

function Progression.getTutorialStep(stepId: string)
	for _, step in ipairs(Progression.TUTORIAL) do
		if step.id == stepId then
			return step
		end
	end

	return nil
end

function Progression.getLevel(xp: number): number
	local level = 1

	for index, info in ipairs(Progression.LEVELS) do
		if xp >= info.xp then
			level = index
		end
	end

	return level
end

function Progression.isUnlocked(level: number, feature: string): boolean
	local requiredLevel = Progression.FEATURES[feature]

	assert(requiredLevel, "[Progression] Unknown feature " .. tostring(feature))

	return level >= requiredLevel
end

-- "Unlocks at Level 3 · Advanced Trader"
function Progression.getLockedMessage(feature: string): string
	local requiredLevel = Progression.FEATURES[feature]

	return string.format("Unlocks at Level %d · %s", requiredLevel, Progression.LEVELS[requiredLevel].name)
end

-- Display names of the features that unlock at exactly `level`, sorted
function Progression.getUnlocksAt(level: number): { string }
	local names = {}

	for feature, requiredLevel in pairs(Progression.FEATURES) do
		if requiredLevel == level then
			table.insert(names, Progression.FEATURE_NAMES[feature])
		end
	end

	table.sort(names)

	return names
end

return Progression
