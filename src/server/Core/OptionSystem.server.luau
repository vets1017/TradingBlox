-- OptionSystem.server.luau
--
-- Option contract order execution (Buy/Sell). Long calls/puts only - no
-- short selling or writing, matching how share trading is long-only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local PlayerOptionOrderEvent = EventsFolder:WaitForChild("PlayerOptionOrderEvent")

local VALID_ACTIONS = { Buy = true, Sell = true }
local VALID_OPTION_TYPES = { C = true, P = true }

local function isPositiveInteger(value)
	return type(value) == "number" and value > 0 and value == math.floor(value)
end

-- PlayerOptionOrderEvent
PlayerOptionOrderEvent.OnServerInvoke = function(player, action, contractSymbol, ticker, expiration, strike, optionType, contracts)
	if type(action) ~= "string" or not VALID_ACTIONS[action] then
		return { success = false, message = "Invalid order type." }
	end

	if not MarketDataModule.isValidTicker(ticker) then
		return { success = false, message = "Invalid ticker." }
	end

	if type(contractSymbol) ~= "string" or contractSymbol == "" then
		return { success = false, message = "Invalid contract." }
	end

	if type(optionType) ~= "string" or not VALID_OPTION_TYPES[optionType] then
		return { success = false, message = "Invalid option type." }
	end

	if not isPositiveInteger(contracts) then
		return { success = false, message = "Invalid contract quantity." }
	end

	-- Options don't trade 24/7 like crypto does - always gate on NYSE hours,
	-- with no exemption.
	if not MarketHoursModule.getMarketStatus(os.time()) then
		return { success = false, message = "Market is closed." }
	end

	local targetTicker = string.upper(ticker)
	local playerData = _G.PlayerData[player.UserId]

	if not playerData then
		return { success = false, message = "Player data not loaded." }
	end

	local quote, quoteErr = MarketDataModule.getOptionQuote(targetTicker, contractSymbol)

	if not quote then
		return { success = false, message = "Price unavailable: " .. tostring(quoteErr) }
	end

	playerData.Portfolio.Options = playerData.Portfolio.Options or {}

	if action == "Buy" then
		local price = quote.ask

		if not price or price <= 0 then
			return { success = false, message = "No ask price available for this contract." }
		end

		local totalCost = price * 100 * contracts

		if playerData.Balance < totalCost then
			return { success = false, message = "Insufficient funds." }
		end

		local existing = playerData.Portfolio.Options[contractSymbol]
		local currentContracts = existing and existing.contracts or 0
		local newContracts = currentContracts + contracts
		local currentAvgCost = existing and existing.avgCost or price

		playerData.Portfolio.Options[contractSymbol] = {
			contracts = newContracts,
			ticker = targetTicker,
			expiration = expiration,
			strike = strike,
			type = optionType,
			avgCost = ((currentAvgCost * currentContracts) + (price * contracts)) / newContracts,
		}

		_G.UpdatePlayerStat(player, "Balance", playerData.Balance - totalCost)
	else -- Sell
		local price = quote.bid

		if not price or price <= 0 then
			return { success = false, message = "No bid price available for this contract." }
		end

		local existing = playerData.Portfolio.Options[contractSymbol]
		local ownedContracts = existing and existing.contracts or 0

		if ownedContracts < contracts then
			return { success = false, message = "Not enough contracts to sell." }
		end

		local totalProceeds = price * 100 * contracts
		local remainingContracts = ownedContracts - contracts

		if remainingContracts > 0 then
			existing.contracts = remainingContracts
		else
			playerData.Portfolio.Options[contractSymbol] = nil
		end

		_G.UpdatePlayerStat(player, "Balance", playerData.Balance + totalProceeds)
	end

	CalculatorModule.calculateNetWorth(player)

	return {
		success = true,
		message = string.format(
			"%s %d x %s %s $%.2f exp %s",
			action,
			contracts,
			targetTicker,
			optionType == "C" and "Call" or "Put",
			strike or 0,
			tostring(expiration)
		),
	}
end
