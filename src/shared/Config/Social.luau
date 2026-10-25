-- Social.luau
--
-- Social trading rules (GDD §2) shared by client and server: the server
-- enforces them, the client explains them.

local Social = {}

-- A cap keeps the Following list (saved in the player's profile) small
Social.MAX_FOLLOWING = 200

-- How many of a player's latest trades their public profile shows, when
-- they share trades
Social.RECENT_TRADES = 10

-- The feed's views: everyone, or only the players you follow
Social.FEED_VIEWS = { "All", "Following" }

-- How many feed items a request returns
Social.FEED_PAGE_SIZE = 50

-- How a milestone reads in the feed, after the player's name
Social.FEED_MILESTONES = {
	FirstTrade = "Made their first trade",
	FirstProfitableSale = "Closed their first profitable trade",
	Diversified = "Diversified into 3 positions",
	TutorialComplete = "Finished getting started",
}

function Social.isFeedView(view): boolean
	return table.find(Social.FEED_VIEWS, view) ~= nil
end

-- Theses: a player's structured, public view on one ticker. Opinions, not
-- trades, so they're labeled "Simulated, not financial advice" wherever
-- they show.
Social.THESIS_DIRECTIONS = { "Bullish", "Bearish" }

Social.THESIS_HORIZONS = {
	{ id = "1W", label = "1 week", seconds = 7 * 86400 },
	{ id = "1M", label = "1 month", seconds = 30 * 86400 },
	{ id = "3M", label = "3 months", seconds = 91 * 86400 },
	{ id = "6M", label = "6 months", seconds = 182 * 86400 },
	{ id = "1Y", label = "1 year", seconds = 365 * 86400 },
}

Social.THESIS_TEXT_MAX = 280 -- characters
Social.THESES_PER_DAY = 5 -- per player, UTC day
Social.THESES_KEPT = 20 -- in the author's profile
Social.THESES_PER_TICKER = 30 -- in a ticker's list
Social.PROFILE_THESES = 5 -- on the public profile

function Social.getHorizon(horizonId)
	for _, horizon in ipairs(Social.THESIS_HORIZONS) do
		if horizon.id == horizonId then
			return horizon
		end
	end

	return nil
end

return Social
