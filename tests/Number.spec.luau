local TestKit = require("./TestKit")
local NumberModule = require("../src/shared/Modules/Multi/NumberModule")

local test, equal = TestKit.test, TestKit.equal

test("format: dollars with commas and cents", function()
	equal(NumberModule.format(0), "$0.00")
	equal(NumberModule.format(1234.5), "$1,234.50")
	equal(NumberModule.format(-1234567.891), "-$1,234,567.89")
	equal(NumberModule.format(999.999), "$1,000.00", "rounding up past a comma")
end)

test("formatShares: whole numbers with commas, no currency", function()
	equal(NumberModule.formatShares(1234567), "1,234,567")
	equal(NumberModule.formatShares(999.9), "999")
end)

test("formatCompact: abbreviates thousands and up", function()
	equal(NumberModule.formatCompact(3e12), "$3.00T")
	equal(NumberModule.formatCompact(245.67e9), "$245.67B")
	equal(NumberModule.formatCompact(-12.3e6), "-$12.30M")
	equal(NumberModule.formatCompact(850000), "$850.00K")
	equal(NumberModule.formatCompact(999.5), "$999.50")
end)

return nil
