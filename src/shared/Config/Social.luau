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

-- Reactions on feed items: one per player per item. Counts live on the
-- item, so they expire with it.
Social.REACTIONS = {
	{ id = "Fire", emoji = "🔥", label = "Fire" },
	{ id = "Watching", emoji = "👀", label = "Watching" },
	{ id = "Skeptical", emoji = "🤔", label = "Skeptical" },
}

Social.MAX_REACTIONS_KEPT = 300 -- the player's own reactions remembered in their profile

function Social.getReaction(reactionId)
	for _, reaction in ipairs(Social.REACTIONS) do
		if reaction.id == reactionId then
			return reaction
		end
	end

	return nil
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

-- Safety: mutes are the game's own and saved; blocks are the player's
-- Roblox blocks. Either one hides that player's feed items and theses, and
-- the trades and theses on their profile.
Social.MAX_MUTED = 500
Social.MAX_HIDDEN_THESES = 200 -- theses a player reported, hidden from them

-- A thesis comes down everywhere once this many players have reported it,
-- counting only Roblox accounts at least MIN_REPORTER_ACCOUNT_AGE_DAYS old
-- so a few fresh alts can't take down whatever they like
Social.REPORTS_TO_TAKE_DOWN = 3
Social.MIN_REPORTER_ACCOUNT_AGE_DAYS = 30

-- Notifications: the inbox keeps the latest INBOX_SIZE
Social.INBOX_SIZE = 50

local ITEM_WORDS = {
	Trade = "trade",
	Thesis = "thesis",
	Milestone = "milestone",
}

-- A notification's title and body, composed from its fields (none of them
-- typed by players): Follow { fromName }, Reaction { fromName, reaction,
-- itemKind, ticker? }, ThesisRemoved { ticker }
function Social.describeNotification(notification)
	local kind = notification.kind

	if kind == "Follow" then
		return "New follower", notification.fromName .. " followed you."
	elseif kind == "Reaction" then
		local reaction = Social.getReaction(notification.reaction)
		local item = ITEM_WORDS[notification.itemKind] or "post"

		if notification.ticker and notification.itemKind ~= "Milestone" then
			item ..= " on " .. notification.ticker
		end

		return "New reaction",
			string.format(
				"%s reacted %sto your %s.",
				notification.fromName,
				reaction and (reaction.emoji .. " ") or "",
				item
			)
	elseif kind == "ThesisRemoved" then
		return "Thesis taken down",
			string.format("Your thesis on %s was taken down after reports.", notification.ticker)
	end

	return "Notification", ""
end

function Social.getHorizon(horizonId)
	for _, horizon in ipairs(Social.THESIS_HORIZONS) do
		if horizon.id == horizonId then
			return horizon
		end
	end

	return nil
end

return Social
