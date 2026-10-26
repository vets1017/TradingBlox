-- SettlementService.luau
--
-- Applies what changes a position without the player trading: options
-- reaching expiry, and stock splits. A player's data only loads while they're
-- online, so this runs as they load in (catching up on anything that happened
-- while they were away) and then every few minutes.
--
-- Expiry: an option settles in cash at its intrinsic value against the
-- underlying's close on the expiration date - a call pays close minus strike,
-- a put strike minus close, and one out of the money pays nothing. It's
-- logged as a sale at that price, so realized P/L counts it.
--
-- Splits: shares multiply by the ratio and average cost divides by it, as a
-- broker does. A fraction of a share left over (a reverse split) is paid out
-- in cash at the current price, and open limit orders on the ticker are
-- adjusted the same way. Options on a split stock aren't adjusted yet.
--
-- Delisting: shares of an experience that left the Roblox market pay out at
-- its last simulated price, logged as a sale ("Delisted") so realized P/L
-- counts it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local OrderService = require(ServerScriptService.Services.OrderService)
local RobloxMarketService = require(ServerScriptService.Services.RobloxMarketService)
local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local TradeLogModule = require(ServerScriptService.Modules.TradeLogModule)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local Instruments = require(ReplicatedStorage.Config.Instruments)
local RobloxMarket = require(ReplicatedStorage.Config.RobloxMarket)

local CHECK_INTERVAL = 600
-- An expiration day's close is final by 21:00 UTC: the 16:00 New York close
-- is 20:00 UTC in summer and 21:00 UTC in winter
local EXPIRY_SETTLE_HOUR_UTC = 21
local OPTION_MULTIPLIER = 100
local EPSILON = 1e-9 -- so 3 x 0.333... still rounds down to 0.999... shares, not 1

local SettlementService = {}

local function describeOption(position)
	local strike = position.strike % 1 == 0 and string.format("$%d", position.strike)
		or string.format("$%.2f", position.strike)

	return string.format("%s %s %s", position.ticker, strike, position.type == "C" and "Call" or "Put")
end

-- The expiration date as numbers, from "2026-11-20T00:00:00.000Z"
local function getExpirationDate(position)
	local year, month, day = string.match(tostring(position.expiration), "^(%d%d%d%d)%-(%d%d)%-(%d%d)")

	if not year then
		return nil
	end

	return tonumber(year), tonumber(month), tonumber(day)
end

-- The underlying's close on a date, or the last session before it when the
-- date had none; nil if the candles can't be fetched
local function getCloseOn(ticker, year, month, day)
	local candles = MarketDataModule.getCandles(ticker, "D")

	if not candles then
		return nil
	end

	local dateKey = string.format("%04d-%02d-%02d", year, month, day)
	local endOfDay = os.time({ year = year, month = month, day = day, hour = 23, min = 59, sec = 59 })
	local lastClose = nil

	for _, candle in ipairs(candles) do
		if os.date("!%Y-%m-%d", candle.Timestamp) == dateKey then
			return candle.Close
		elseif candle.Timestamp <= endOfDay then
			lastClose = candle.Close
		end
	end

	return lastClose
end

local function settleExpiredOptions(player, data, now)
	for contractSymbol, position in pairs(table.clone(data.Portfolio.Options)) do
		local year, month, day = getExpirationDate(position)
		local settlesAt = year and os.time({ year = year, month = month, day = day, hour = EXPIRY_SETTLE_HOUR_UTC })

		if settlesAt and now >= settlesAt then
			local close = getCloseOn(position.ticker, year, month, day)

			-- No close yet means no settlement yet; the next pass tries again.
			-- The data is re-read because the candle fetch yields.
			if
				close
				and PlayerDataService.get(player) == data
				and data.Portfolio.Options[contractSymbol] == position
			then
				local intrinsic = position.type == "C" and math.max(close - position.strike, 0)
					or math.max(position.strike - close, 0)
				local proceeds = intrinsic * OPTION_MULTIPLIER * position.contracts

				data.Portfolio.Options[contractSymbol] = nil

				if proceeds > 0 then
					PlayerDataService.setStat(player, "Balance", data.Balance + proceeds)
				end

				TradeLogModule.record(data, {
					ticker = position.ticker,
					contract = contractSymbol,
					side = "Sell",
					quantity = position.contracts,
					price = intrinsic,
					costBasis = position.avgCost,
					settlement = "Expired",
				}, now)

				OrderService.notify(
					player,
					"expired",
					proceeds > 0
							and string.format(
								"%s expired in the money: paid %s",
								describeOption(position),
								NumberModule.format(proceeds)
							)
						or describeOption(position) .. " expired worthless"
				)
			end
		end
	end
end

local function applySplit(player, data, ticker, split)
	local portfolio = data.Portfolio
	local shares = portfolio.Shares[ticker]
	local ratio = split.numerator / split.denominator
	local exactShares = shares * ratio
	local newShares = math.floor(exactShares + EPSILON)
	local fraction = exactShares - newShares
	local cashInLieu = 0

	-- Price the fraction first: the lookup yields, so the position is checked
	-- again before anything changes
	if fraction > EPSILON then
		local price = MarketDataModule.getCurrentPrice(ticker)
			or (portfolio.AvgCost[ticker] and portfolio.AvgCost[ticker] / ratio)
			or 0

		cashInLieu = fraction * price

		if PlayerDataService.get(player) ~= data or portfolio.Shares[ticker] ~= shares then
			return false
		end
	end

	if newShares > 0 then
		portfolio.Shares[ticker] = newShares
		portfolio.AvgCost[ticker] = portfolio.AvgCost[ticker] and portfolio.AvgCost[ticker] / ratio
	else
		portfolio.Shares[ticker] = nil
		portfolio.AvgCost[ticker] = nil
		portfolio.SplitCheckedAt[ticker] = nil
	end

	if cashInLieu > 0 then
		PlayerDataService.setStat(player, "Balance", data.Balance + cashInLieu)
	end

	for orderId, order in pairs(data.Orders) do
		if order.ticker == ticker then
			local quantity = math.floor(order.quantity * ratio + EPSILON)

			if quantity < 1 then
				data.Orders[orderId] = nil
			else
				order.quantity = quantity
				order.limitPrice = math.round(order.limitPrice / ratio * 100) / 100
			end
		end
	end

	OrderService.notify(
		player,
		"split",
		string.format(
			"%s split %d-for-%d: your %s shares are now %s%s",
			ticker,
			split.numerator,
			split.denominator,
			NumberModule.formatShares(shares),
			NumberModule.formatShares(newShares),
			cashInLieu > 0 and (", plus " .. NumberModule.format(cashInLieu) .. " for the fraction") or ""
		)
	)

	return true
end

local function applySplits(player, data, now)
	local portfolio = data.Portfolio

	for ticker in pairs(table.clone(portfolio.Shares)) do
		local checkedAt = portfolio.SplitCheckedAt[ticker]

		if not checkedAt then
			-- Held from before splits were tracked: nothing applies retroactively
			portfolio.SplitCheckedAt[ticker] = now
		elseif not MarketDataModule.isCryptoTicker(ticker) then
			local splits = MarketDataModule.getSplits(ticker)

			-- nil splits (backend unreachable) leave checkedAt alone, so the next
			-- pass looks again
			if splits and PlayerDataService.get(player) == data then
				table.sort(splits, function(a, b)
					return a.date < b.date
				end)

				local isComplete = true

				for _, split in ipairs(splits) do
					local isValid = split.numerator > 0 and split.denominator > 0

					if isValid and split.date > checkedAt and split.date <= now and portfolio.Shares[ticker] then
						isComplete = applySplit(player, data, ticker, split) and isComplete
					end
				end

				if isComplete and portfolio.Shares[ticker] then
					portfolio.SplitCheckedAt[ticker] = now
				end
			end
		end
	end
end

local function settleDelisted(player, data, now)
	for ticker in pairs(table.clone(data.Portfolio.Shares)) do
		if Instruments.isRoblox(ticker) then
			local experience = RobloxMarketService.getExperienceState(ticker)
			local shares = data.Portfolio.Shares[ticker]

			-- Re-read after the market read, which can yield
			if experience and experience.delisted and shares and PlayerDataService.get(player) == data then
				local price = experience.price
				local proceeds = shares * price
				local listed = RobloxMarket.getExperience(ticker)

				TradeLogModule.record(data, {
					ticker = ticker,
					side = "Sell",
					quantity = shares,
					price = price,
					costBasis = data.Portfolio.AvgCost[ticker] or price,
					settlement = "Delisted",
				}, now)

				PlayerDataService.setStat(player, "Balance", data.Balance + proceeds)
				PlayerDataService.updateShares(player, ticker, -shares)
				OrderService.notify(
					player,
					"delisted",
					string.format(
						"%s left the Roblox market: %s shares paid %s",
						listed and listed.name or ticker,
						NumberModule.formatShares(shares),
						NumberModule.format(proceeds)
					)
				)
			end
		end
	end
end

function SettlementService.settlePlayer(player)
	local data = PlayerDataService.get(player)

	if not data then
		return
	end

	local now = os.time()

	settleExpiredOptions(player, data, now)
	applySplits(player, data, now)
	settleDelisted(player, data, now)
end

-- Must run before PlayerDataService.start so no PlayerLoaded is missed
function SettlementService.start()
	PlayerDataService.PlayerLoaded:Connect(function(player)
		task.spawn(SettlementService.settlePlayer, player)
	end)

	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)

			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(SettlementService.settlePlayer, player)
			end
		end
	end)
end

return SettlementService
