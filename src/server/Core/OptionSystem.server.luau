-- OptionSystem.server.luau
--
-- Option contract order execution (Buy/Sell). Long calls/puts only - no
-- short selling or writing, matching how share trading is long-only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)
local TradeLogModule = require(ServerScriptService.Modules.TradeLogModule)
local ProgressionService = require(ServerScriptService.Services.ProgressionService)
local OrderEvents = require(ServerScriptService.Services.OrderEvents)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local RemoteGuard = require(ServerScriptService.Modules.RemoteGuard)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local Progression = require(ReplicatedStorage.Config.Progression)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local PlayerOptionOrderEvent = EventsFolder:WaitForChild("PlayerOptionOrderEvent")

local VALID_ACTIONS = { Buy = true, Sell = true }
local VALID_OPTION_TYPES = { C = true, P = true }

local function isPositiveInteger(value)
	return type(value) == "number" and value > 0 and value == math.floor(value)
end

-- PlayerOptionOrderEvent
RemoteGuard.handle(PlayerOptionOrderEvent, RemoteGuard.LIMITS.Order, function(player, action, contractSymbol, ticker, expiration, strike, optionType, contracts)
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

	if type(strike) ~= "number" then
		return { success = false, message = "Invalid strike." }
	end

	if type(expiration) ~= "string" or expiration == "" then
		return { success = false, message = "Invalid expiration." }
	end

	if not isPositiveInteger(contracts) then
		return { success = false, message = "Invalid contract quantity." }
	end

	if not ProgressionService.hasFeature(player, "Options") then
		return { success = false, message = "Options: " .. Progression.getLockedMessage("Options") }
	end

	-- Options don't trade 24/7 like crypto does - always gate on NYSE hours,
	-- with no exemption.
	if not MarketHoursModule.getMarketStatus(os.time()) then
		return { success = false, message = "Market is closed." }
	end

	local targetTicker = string.upper(ticker)
	local playerData = PlayerDataService.get(player)

	if not playerData then
		return { success = false, message = "Player data not loaded." }
	end

	local quote, quoteErr = MarketDataModule.getOptionQuote(targetTicker, contractSymbol)

	if not quote then
		return { success = false, message = "Price unavailable: " .. tostring(quoteErr) }
	end

	playerData.Portfolio.Options = playerData.Portfolio.Options or {}

	local fillPrice, costBasis -- per-share premium; average cost is read before a sale changes the position

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

		PlayerDataService.setStat(player, "Balance", playerData.Balance - totalCost)
		fillPrice = price
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

		fillPrice = price
		costBasis = existing.avgCost

		if remainingContracts > 0 then
			existing.contracts = remainingContracts
		else
			playerData.Portfolio.Options[contractSymbol] = nil
		end

		PlayerDataService.setStat(player, "Balance", playerData.Balance + totalProceeds)
	end

	local now = os.time()
	local realizedPL = TradeLogModule.record(playerData, {
		ticker = targetTicker,
		contract = contractSymbol,
		side = action,
		quantity = contracts,
		price = fillPrice,
		costBasis = costBasis,
	}, now)

	OrderEvents.fireFilled(player, realizedPL, now)
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
end, RemoteGuard.TOO_MANY_REQUESTS)
