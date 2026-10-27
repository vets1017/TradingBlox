-- Data_Manager.server.luau
--
-- Starts the player services. Server scripts reach player data through
-- PlayerDataService; there is no `_G` state.

local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local ProgressionService = require(ServerScriptService.Services.ProgressionService)
local ChallengeService = require(ServerScriptService.Services.ChallengeService)
local LeaderboardService = require(ServerScriptService.Services.LeaderboardService)
local PublicProfileService = require(ServerScriptService.Services.PublicProfileService)
local SocialService = require(ServerScriptService.Services.SocialService)
local FeedService = require(ServerScriptService.Services.FeedService)
local ThesisService = require(ServerScriptService.Services.ThesisService)
local NotificationService = require(ServerScriptService.Services.NotificationService)
local DiscoveryService = require(ServerScriptService.Services.DiscoveryService)
local RobloxMarketService = require(ServerScriptService.Services.RobloxMarketService)
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
ChallengeService.start()
LeaderboardService.start()
PublicProfileService.start()
SocialService.start()
FeedService.start()
ThesisService.start()
NotificationService.start()
DiscoveryService.start()
RobloxMarketService.start()
OrderService.start()
SettlementService.start()
PlayerDataService.start()
