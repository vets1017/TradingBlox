local TestKit = require("./TestKit")
local FeedModule = require("../src/server/Modules/FeedModule")

local test, equal = TestKit.test, TestKit.equal

local NOW = 1_800_000_000
local AUTHOR = { userId = 100, displayName = "Ann", username = "ann_trades" }

test("keys sort as text in time order", function()
	local earlier = FeedModule.makeKey(999_999_999_999, "zzzzzzzz", 9)
	local later = FeedModule.makeKey(1_000_000_000_000, "aaaaaaaa", 1)

	equal(earlier < later, true)
	equal(later, "01000000000000-aaaaaaaa-1")
end)

test("a trade item copies the fill and names its author", function()
	local fill = { ticker = "AAPL", side = "Sell", quantity = 5, price = 190.5, costBasis = 180 }
	local item = FeedModule.makeTradeItem(AUTHOR, fill, 52.5, NOW)

	equal(item, {
		kind = "Trade",
		userId = 100,
		displayName = "Ann",
		username = "ann_trades",
		time = NOW,
		ticker = "AAPL",
		side = "Sell",
		quantity = 5,
		price = 190.5,
		realizedPL = 52.5,
	})
end)

test("an option trade keeps its contract", function()
	local fill = { ticker = "AAPL", contract = "AAPL261120C00300000", side = "Buy", quantity = 1, price = 2 }

	equal(FeedModule.makeTradeItem(AUTHOR, fill, nil, NOW).contract, "AAPL261120C00300000")
end)

test("milestone and level items", function()
	local milestone = FeedModule.makeMilestoneItem(AUTHOR, "FirstTrade", nil, NOW)
	local level = FeedModule.makeMilestoneItem(AUTHOR, nil, 2, NOW)

	equal(milestone.kind, "Milestone")
	equal(milestone.milestone, "FirstTrade")
	equal(level.level, 2)
	equal(level.milestone, nil)
end)

test("trades post at most once per gap", function()
	equal(FeedModule.canPostTrade(nil, NOW, 30), true, "first trade")
	equal(FeedModule.canPostTrade(NOW - 29, NOW, 30), false, "too soon")
	equal(FeedModule.canPostTrade(NOW - 30, NOW, 30), true, "gap passed")
end)

local function makeItems()
	return {
		{ kind = "Trade", userId = 1 },
		{ kind = "Milestone", userId = 2 },
		{ kind = "Trade", userId = 2 },
		{ kind = "Trade", userId = 3 },
	}
end

test("select keeps order and stops at the limit", function()
	local items = makeItems()

	equal(FeedModule.select(items, 2), { items[1], items[2] })
	equal(#FeedModule.select(items, 10), 4)
end)

test("select filters before counting toward the limit", function()
	local items = makeItems()
	local selected = FeedModule.select(items, 2, function(item)
		return item.userId ~= 1
	end)

	equal(selected, { items[2], items[3] })
end)

test("isTradeBy matches only that player's trades", function()
	local items = makeItems()

	equal(FeedModule.isTradeBy(items[3], 2), true)
	equal(FeedModule.isTradeBy(items[2], 2), false, "milestones stay")
	equal(FeedModule.isTradeBy(items[1], 2), false, "someone else's trade")
end)
