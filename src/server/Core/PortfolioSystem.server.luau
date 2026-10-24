-- PortfolioSystem.server.luau
--
-- Portfolio tab: account summary, net-worth history and option positions
-- (share positions come from TradeSystem's GetPositionsEvent), plus a
-- periodic net-worth sample that keeps the history chart moving while a
-- player holds positions without trading.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)
local PortfolioHistoryModule = require(ServerScriptService.Modules.PortfolioHistoryModule)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetPortfolioEvent = EventsFolder:WaitForChild("GetPortfolioEvent")

local SAMPLE_INTERVAL = 300 -- the history's finest bucket

-- Option contracts priced off the cached chain, so this adds no HTTP calls
-- after calculateNetWorth has just loaded the same chains.
local function buildOptionPositions(playerData)
	local positions = {}

	for contractSymbol, position in pairs(playerData.Portfolio.Options or {}) do
		local quote = MarketDataModule.getOptionQuote(position.ticker, contractSymbol)
		local premium = CalculatorModule.getOptionPremium(quote)
		local cost = position.avgCost * position.contracts * 100
		local value = premium and (premium * position.contracts * 100) or nil
		local plOpen = value and (value - cost) or nil

		table.insert(positions, {
			contractSymbol = contractSymbol,
			ticker = position.ticker,
			type = position.type,
			strike = position.strike,
			expiration = position.expiration,
			contracts = position.contracts,
			value = value,
			plOpenPct = (plOpen and cost ~= 0) and (plOpen / cost * 100) or nil,
		})
	end

	return positions
end

-- GetPortfolioEvent
-- Reprices the account (which also records a history point) and returns
-- everything the Portfolio tab shows except share positions. Every range's
-- chart comes back at once so switching ranges needs no round trip.
GetPortfolioEvent.OnServerInvoke = function(player)
	local playerData = _G.PlayerData[player.UserId]

	-- Portfolio is set once the DataStore load finishes
	if not playerData or not playerData.Portfolio then
		return nil
	end

	local netWorth = CalculatorModule.calculateNetWorth(player)
	local now = os.time()
	local histories = {}

	for range, rangeSeconds in pairs(PortfolioHistoryModule.RANGES) do
		histories[range] = PortfolioHistoryModule.getRange(playerData.NetWorthHistory or {}, rangeSeconds, now)
	end

	return {
		netWorth = netWorth,
		balance = playerData.Balance,
		histories = histories,
		trades = playerData.Stats and playerData.Stats.Trades or 0,
		joinedAt = playerData.Stats and playerData.Stats.JoinedAt,
		options = buildOptionPositions(playerData),
	}
end

task.spawn(function()
	while true do
		task.wait(SAMPLE_INTERVAL)

		for _, player in ipairs(Players:GetPlayers()) do
			local playerData = _G.PlayerData[player.UserId]

			if playerData and playerData.Portfolio then
				task.spawn(CalculatorModule.calculateNetWorth, player)
			end
		end
	end
end)
