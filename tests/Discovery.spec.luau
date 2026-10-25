local TestKit = require("./TestKit")
local DiscoveryModule = require("../src/server/Modules/DiscoveryModule")

local test, equal = TestKit.test, TestKit.equal

test("trades go into the UTC day, and the window is today and yesterday", function()
	local lateEvening = TestKit.utc(2026, 10, 25, 23, 59)

	equal(DiscoveryModule.dayKey(lateEvening), "2026-10-25")
	equal(DiscoveryModule.dayKey(lateEvening + 60), "2026-10-26")
	equal(DiscoveryModule.windowKeys(TestKit.utc(2026, 11, 1, 3)), { "2026-11-01", "2026-10-31" })
end)

test("counts are summed across days and ranked, ties by ticker", function()
	local ranked = DiscoveryModule.rank({ { AAPL = 3, TSLA = 5 }, { AAPL = 4, MSFT = 2, NVDA = 2 } }, 3)

	equal(ranked, {
		{ ticker = "AAPL", trades = 7 },
		{ ticker = "TSLA", trades = 5 },
		{ ticker = "MSFT", trades = 2 },
	})
end)

test("zero counts aren't trending", function()
	equal(DiscoveryModule.rank({ { AAPL = 0 } }, 5), {})
end)

test("watches are counted once and uncounted when dropped", function()
	local toAdd, toRemove = DiscoveryModule.reconcileWatches({ "AAPL", "TSLA" }, { TSLA = true, MSFT = true })

	equal(toAdd, { "AAPL" })
	equal(toRemove, { "MSFT" })

	toAdd, toRemove = DiscoveryModule.reconcileWatches({}, {})
	equal(toAdd, {})
	equal(toRemove, {})
end)
