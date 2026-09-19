-- API_Manager.server.luau
--
-- Middleman API

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local RequestChartEvent = EventsFolder:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = EventsFolder:WaitForChild("GetMarketDataEvent")

-- Config
local PLAYER_COOLDOWN = 1
local VALID_TIMEFRAMES = { ["1M"] = true, ["5M"] = true, ["30M"] = true, ["H"] = true, ["D"] = true }

-- State
local PlayerLastRequest = {} -- [UserId] = os.time() of last request

--

-- RequestChartEvent
RequestChartEvent.OnServerInvoke = function(player, ticker, timeframe, mode)
	local userId = player.UserId
	local now = os.time()
	local lastRequest = PlayerLastRequest[userId] or 0

	if (now - lastRequest) < PLAYER_COOLDOWN then
		return nil
	end

	PlayerLastRequest[userId] = now

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	if not VALID_TIMEFRAMES[timeframe] then
		warn(string.format("[API_Manager] Invalid timeframe from %s: %s", player.Name, tostring(timeframe)))

		return nil
	end

	local targetTicker = string.upper(ticker)
	local data, err = MarketDataModule.getCandles(targetTicker, timeframe, mode)

	if not data then
		warn(string.format("[API_Manager] Chart fetch failed for %s (%s): %s", targetTicker, timeframe, tostring(err)))

		return nil
	end

	return data
end

-- GetMarketDataEvent
-- Returns a minimal quote ({ ticker, price, prevClose }) for the given ticker.
GetMarketDataEvent.OnServerInvoke = function(player, ticker)
	if not ticker then
		return nil
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local quote = MarketDataModule.getQuote(ticker)

	if not quote then
		warn(string.format("[API_Manager] Quote fetch failed for %s", string.upper(ticker)))
	end

	return quote
end

-- Clean up
Players.PlayerRemoving:Connect(function(player)
	PlayerLastRequest[player.UserId] = nil
end)
