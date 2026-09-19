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
local GetAnalystReportEvent = EventsFolder:WaitForChild("GetAnalystReportEvent")
local GetFundamentalsEvent = EventsFolder:WaitForChild("GetFundamentalsEvent")
local GetOptionStatsEvent = EventsFolder:WaitForChild("GetOptionStatsEvent")

-- Config
local PLAYER_COOLDOWN = 1
local VALID_TIMEFRAMES = { ["1M"] = true, ["5M"] = true, ["30M"] = true, ["H"] = true, ["D"] = true }

-- State
local PlayerLastRequest = {} -- [UserId] = { [remoteName] = os.time() }

-- Per-remote: switching tabs hits a different remote each time, so one tab's
-- fetch must not throttle the next tab's first fetch.
local function isThrottled(player, remoteName)
	local now = os.time()
	local perRemote = PlayerLastRequest[player.UserId]

	if not perRemote then
		perRemote = {}
		PlayerLastRequest[player.UserId] = perRemote
	end

	if (now - (perRemote[remoteName] or 0)) < PLAYER_COOLDOWN then
		return true
	end

	perRemote[remoteName] = now

	return false
end

--

-- RequestChartEvent
RequestChartEvent.OnServerInvoke = function(player, ticker, timeframe, mode)
	if isThrottled(player, "RequestChartEvent") then
		return nil
	end

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
-- Returns a quote ({ ticker, price, prevClose }) for the given ticker, merged
-- with quote-details fields (bid/ask, volume, market cap, etc.) when available.
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

		return nil
	end

	local details, detailsErr = MarketDataModule.getQuoteDetails(ticker)

	if not details then
		warn(string.format("[API_Manager] Quote details fetch failed for %s: %s", string.upper(ticker), tostring(detailsErr)))
	end

	if details then
		for key, value in pairs(details) do
			quote[key] = value
		end
	end

	return quote
end

-- GetAnalystReportEvent
GetAnalystReportEvent.OnServerInvoke = function(player, ticker)
	if isThrottled(player, "GetAnalystReportEvent") then
		return nil
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local report, err = MarketDataModule.getAnalystReport(ticker)

	if not report then
		warn(string.format("[API_Manager] Analyst report fetch failed for %s: %s", string.upper(ticker), tostring(err)))
	end

	return report
end

-- GetFundamentalsEvent
GetFundamentalsEvent.OnServerInvoke = function(player, ticker)
	if isThrottled(player, "GetFundamentalsEvent") then
		return nil
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local fundamentals, err = MarketDataModule.getFundamentals(ticker)

	if not fundamentals then
		warn(string.format("[API_Manager] Fundamentals fetch failed for %s: %s", string.upper(ticker), tostring(err)))
	end

	return fundamentals
end

-- GetOptionStatsEvent
GetOptionStatsEvent.OnServerInvoke = function(player, ticker)
	if isThrottled(player, "GetOptionStatsEvent") then
		return nil
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local stats, err = MarketDataModule.getOptionStats(ticker)

	if not stats then
		warn(string.format("[API_Manager] Option stats fetch failed for %s: %s", string.upper(ticker), tostring(err)))
	end

	return stats
end

-- Clean up
Players.PlayerRemoving:Connect(function(player)
	PlayerLastRequest[player.UserId] = nil
end)
