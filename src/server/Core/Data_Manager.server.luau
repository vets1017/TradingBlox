-- Data_Manager.server.luau
--
-- Starts the player services. Server scripts reach player data through
-- PlayerDataService; there is no `_G` state.

local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local ProgressionService = require(ServerScriptService.Services.ProgressionService)
local LeaderboardService = require(ServerScriptService.Services.LeaderboardService)
local PublicProfileService = require(ServerScriptService.Services.PublicProfileService)
local SocialService = require(ServerScriptService.Services.SocialService)
local FeedService = require(ServerScriptService.Services.FeedService)
local ThesisService = require(ServerScriptService.Services.ThesisService)
local OrderService = require(ServerScriptService.Services.OrderService)
local SettlementService = require(ServerScriptService.Services.SettlementService)
local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)

-- Seed NetWorth so the status bar has a value before the first trade;
-- spawned because pricing held shares fetches prices over HTTP
PlayerDataService.PlayerLoaded:Connect(function(player)
	task.spawn(CalculatorModule.calculateNetWorth, player)
end)

-- Listeners first, so none of them misses a player who loads straight away
ProgressionService.start()
LeaderboardService.start()
PublicProfileService.start()
SocialService.start()
FeedService.start()
ThesisService.start()
OrderService.start()
SettlementService.start()
PlayerDataService.start()
