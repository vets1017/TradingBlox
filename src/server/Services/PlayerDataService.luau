-- PlayerDataService.luau
--
-- Owns every player's saved data: one session-locked ProfileStore profile
-- per player, autosaved every minute and saved again when they leave or the
-- server shuts down. Only the server holding a profile's session can write
-- it, so two servers can't overwrite each other, and a load that fails kicks
-- the player instead of handing them default data that would later be saved
-- over their real record.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.Vendor.ProfileStore)

-- v1 saves are left in place; v2 starts every player fresh at the GDD's
-- $50,000 (TECHNICAL-PLAN decision 2)
local STORE_NAME = "PlayerData_v2"
local STARTING_BALANCE = 50000
local AUTO_SAVE_PERIOD = 60 -- ProfileStore's default is 300; a crash now loses at most a minute

local TEMPLATE = {
	Balance = STARTING_BALANCE,
	Portfolio = {
		Shares = {}, -- [ticker] = share count
		AvgCost = {}, -- [ticker] = average cost per share
		Options = {}, -- [contractSymbol] = { contracts, ticker, expiration, strike, type, avgCost }
	},
	Watchlist = {},
	Stats = {
		Trades = 0, -- filled share and option orders
		JoinedAt = 0, -- set from the profile's first session on load
		-- Realized P/L over every sell ever made; see TradeLogModule
		RealizedPL = 0,
		Wins = 0,
		Losses = 0,
		GrossGain = 0,
		GrossLoss = 0, -- positive dollars
	},
	TradeLog = {}, -- the most recent fills; see TradeLogModule
	NetWorthHistory = {}, -- see PortfolioHistoryModule
}

ProfileStore.SetConstant("AUTO_SAVE_PERIOD", AUTO_SAVE_PERIOD)

local PlayerStore = ProfileStore.New(STORE_NAME, TEMPLATE)

local profiles = {} -- [player] = profile, only while this server holds the session
local startedPlayers = {} -- [player] = true once a load has begun
local playerLoaded = Instance.new("BindableEvent")

local PlayerDataService = {}

PlayerDataService.STARTING_BALANCE = STARTING_BALANCE

-- Fires (player, data) once a player's profile has loaded
PlayerDataService.PlayerLoaded = playerLoaded.Event

-- The player's live data table, or nil before it loads and after the session
-- ends. Changes to it are saved; don't hold on to it across yields without
-- checking again, since the session can end in between.
function PlayerDataService.get(player)
	local profile = profiles[player]

	return profile and profile.Data
end

-- Sets a top-level stat and mirrors it to the player's attribute of the same
-- name, which is how the client reads Balance and NetWorth
function PlayerDataService.setStat(player, statName, value)
	local data = PlayerDataService.get(player)

	if data then
		data[statName] = value
	end

	player:SetAttribute(statName, value)
end

-- Adds (or with negative `shares`, removes) shares of a ticker. A buy at
-- `price` rolls into the weighted-average cost; selling doesn't change it.
function PlayerDataService.updateShares(player, ticker, shares, price)
	local data = PlayerDataService.get(player)

	if not data then
		return
	end

	local portfolio = data.Portfolio
	local currentShares = portfolio.Shares[ticker] or 0
	local newShares = currentShares + shares

	if newShares <= 0 then
		portfolio.Shares[ticker] = nil
		portfolio.AvgCost[ticker] = nil

		return
	end

	if shares > 0 and price then
		local currentAvgCost = portfolio.AvgCost[ticker] or price

		portfolio.AvgCost[ticker] = ((currentAvgCost * currentShares) + (price * shares)) / newShares
	end

	portfolio.Shares[ticker] = newShares
end

local function onPlayerAdded(player)
	-- A second StartSessionAsync for the same key makes the first return nil,
	-- which would read as a failed load and kick the player
	if startedPlayers[player] then
		return
	end

	startedPlayers[player] = true

	local profile = PlayerStore:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if not profile then
		-- nil after a cancel (the player left) or after retrying for two minutes
		if player.Parent == Players then
			player:Kick("Your data couldn't be loaded. Please rejoin.")
		end

		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	if profile.Data.Stats.JoinedAt == 0 then
		profile.Data.Stats.JoinedAt = profile.FirstSessionTime
	end

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil

		-- Still here means another server took the session over
		if player.Parent == Players then
			player:Kick("Your data was loaded on another server. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()

		return
	end

	profiles[player] = profile
	player:SetAttribute("Balance", profile.Data.Balance)
	playerLoaded:Fire(player, profile.Data)
end

local function onPlayerRemoving(player)
	local profile = profiles[player]

	startedPlayers[player] = nil

	if profile then
		profile:EndSession()
	end
end

function PlayerDataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Players who joined before this ran (Studio play starts the player early)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerDataService
