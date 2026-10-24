-- Data_Manager.server.luau
--
-- Starts the player services and keeps the `_G` names the other server
-- scripts still use pointing at PlayerDataService, until those scripts move
-- onto services (docs/TECHNICAL-PLAN.md, Phase 0).

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local ProgressionService = require(ServerScriptService.Services.ProgressionService)
local LeaderboardService = require(ServerScriptService.Services.LeaderboardService)
local PublicProfileService = require(ServerScriptService.Services.PublicProfileService)
local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)

-- Reads resolve straight to the live profile data, so there's nothing to keep
-- in sync: nil before a player's data loads and after their session ends
_G.PlayerData = setmetatable({}, {
	__index = function(_, userId)
		local player = Players:GetPlayerByUserId(userId)

		return player and PlayerDataService.get(player)
	end,
})

_G.UpdatePlayerStat = PlayerDataService.setStat
_G.UpdatePortfolio = PlayerDataService.updateShares

-- Seed NetWorth so the status bar has a value before the first trade;
-- spawned because pricing held shares fetches prices over HTTP
PlayerDataService.PlayerLoaded:Connect(function(player)
	task.spawn(CalculatorModule.calculateNetWorth, player)
end)

-- Listeners first, so none of them misses a player who loads straight away
ProgressionService.start()
LeaderboardService.start()
PublicProfileService.start()
PlayerDataService.start()
