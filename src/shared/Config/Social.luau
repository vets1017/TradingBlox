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

return Social
