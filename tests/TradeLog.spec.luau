local TestKit = require("./TestKit")
local TradeLogModule = require("../src/server/Modules/TradeLogModule")

local test, equal = TestKit.test, TestKit.equal

local NOW = 1_800_000_000

-- The Stats fields TradeLogModule touches, as PlayerDataService's template
-- starts them
local function newPlayerData()
	return {
		Stats = { Trades = 0, RealizedPL = 0, Wins = 0, Losses = 0, GrossGain = 0, GrossLoss = 0 },
		TradeLog = {},
	}
end

test("a buy is logged and counted, with no realized P/L", function()
	local data = newPlayerData()
	local realized = TradeLogModule.record(data, { ticker = "AAPL", side = "Buy", quantity = 5, price = 10 }, NOW)

	equal(realized, nil)
	equal(data.Stats.Trades, 1)
	equal(data.TradeLog[1].ticker, "AAPL")
	equal(data.TradeLog[1].time, NOW)
end)

test("a share sale realizes against the average cost", function()
	local data = newPlayerData()
	local fill = { ticker = "AAPL", side = "Sell", quantity = 5, price = 12.5, costBasis = 10 }

	equal(TradeLogModule.record(data, fill, NOW), 12.5)
	equal(data.Stats.RealizedPL, 12.5)
	equal(data.Stats.Wins, 1)
	equal(data.Stats.GrossGain, 12.5)
end)

test("an option sale multiplies by 100 shares a contract", function()
	local data = newPlayerData()
	local fill =
		{ ticker = "AAPL", contract = "AAPL261120C00300000", side = "Sell", quantity = 2, price = 1.5, costBasis = 2 }

	equal(TradeLogModule.record(data, fill, NOW), -100)
	equal(data.Stats.Losses, 1)
	equal(data.Stats.GrossLoss, 100)
	equal(data.Stats.RealizedPL, -100)
end)

test("a break-even sale is neither a win nor a loss", function()
	local data = newPlayerData()

	TradeLogModule.record(data, { ticker = "X", side = "Sell", quantity = 1, price = 10, costBasis = 10 }, NOW)
	equal({ data.Stats.Wins, data.Stats.Losses, data.Stats.Trades }, { 0, 0, 1 })
end)

test("a settlement counts toward realized P/L but not trades", function()
	local data = newPlayerData()
	local fill = {
		ticker = "AAPL",
		contract = "AAPL261023C00300000",
		side = "Sell",
		quantity = 1,
		price = 47.73,
		costBasis = 40,
		settlement = "Expired",
	}

	equal(TradeLogModule.record(data, fill, NOW), 773)
	equal(data.Stats.Trades, 0)
	equal(data.Stats.Wins, 1)
	equal(data.TradeLog[1].settlement, "Expired")
end)

test("the log keeps the latest 500 fills", function()
	local data = newPlayerData()

	for i = 1, 505 do
		TradeLogModule.record(data, { ticker = "X", side = "Buy", quantity = 1, price = 1 }, i)
	end

	equal(#data.TradeLog, 500)
	equal(data.TradeLog[1].time, 6)
	equal(data.Stats.Trades, 505)
end)

test("getSummary has no rates before a closed trade", function()
	equal(TradeLogModule.getSummary(newPlayerData().Stats), { realizedPL = 0, closedTrades = 0 })
end)

test("getSummary averages wins and losses separately", function()
	local data = newPlayerData()

	for _, fill in ipairs({
		{ price = 12, costBasis = 10 }, -- +2
		{ price = 14, costBasis = 10 }, -- +4
		{ price = 7, costBasis = 10 }, -- -3
	}) do
		TradeLogModule.record(
			data,
			{ ticker = "X", side = "Sell", quantity = 1, price = fill.price, costBasis = fill.costBasis },
			NOW
		)
	end

	equal(TradeLogModule.getSummary(data.Stats), {
		realizedPL = 3,
		winRate = 2 / 3,
		averageGain = 3,
		averageLoss = 3,
		closedTrades = 3,
	})
end)

return nil
