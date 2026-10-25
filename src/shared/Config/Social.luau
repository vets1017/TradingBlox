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

return Social
