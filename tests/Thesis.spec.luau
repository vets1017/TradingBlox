local TestKit = require("./TestKit")
local ThesisModule = require("../src/server/Modules/ThesisModule")
local Social = require("../src/shared/Config/Social")

local test, equal = TestKit.test, TestKit.equal

local NOW = TestKit.utc(2026, 10, 25, 15)
local DAY = 86400

local function draft(overrides)
	local base = { direction = "Bullish", horizon = "1M" }

	for key, value in pairs(overrides or {}) do
		base[key] = value
	end

	return base
end

local function reason(ok, message)
	return if ok then "ok" else message
end

test("text is trimmed and whitespace collapsed", function()
	equal(ThesisModule.normalizeText("  Strong   iPhone\n\ncycle  "), "Strong iPhone cycle")
	equal(ThesisModule.normalizeText(" \n\t "), nil)
end)

test("a plain draft passes", function()
	equal(reason(ThesisModule.validate(draft(), 100, Social)), "ok")
	equal(reason(ThesisModule.validate(draft({ direction = "Bearish", horizon = "1Y" }), 100, Social)), "ok")
end)

test("direction and horizon must be known", function()
	equal(reason(ThesisModule.validate(draft({ direction = "Sideways" }), 100, Social)), "Pick bullish or bearish.")
	equal(reason(ThesisModule.validate(draft({ horizon = "5Y" }), 100, Social)), "Pick a time horizon.")
	equal(reason(ThesisModule.validate("nope", 100, Social)), "Invalid thesis.")
end)

test("a target has to agree with the direction", function()
	equal(reason(ThesisModule.validate(draft({ targetPrice = 120 }), 100, Social)), "ok")
	equal(
		reason(ThesisModule.validate(draft({ targetPrice = 90 }), 100, Social)),
		"A bullish target has to be above the current price."
	)
	equal(
		reason(ThesisModule.validate(draft({ direction = "Bearish", targetPrice = 100 }), 100, Social)),
		"A bearish target has to be below the current price."
	)
end)

test("a target must be a sane positive number", function()
	for _, bad in ipairs({ 0, -5, 0 / 0, math.huge, "120" }) do
		equal(
			reason(ThesisModule.validate(draft({ targetPrice = bad }), 100, Social)),
			"Enter a target price above $0.",
			tostring(bad)
		)
	end
end)

test("text has a length limit counted in characters", function()
	local limit = Social.THESIS_TEXT_MAX

	equal(reason(ThesisModule.validate(draft({ text = string.rep("é", limit) }), 100, Social)), "ok")
	equal(
		reason(ThesisModule.validate(draft({ text = string.rep("a", limit + 1) }), 100, Social)),
		"Keep it to 280 characters."
	)
	equal(reason(ThesisModule.validate(draft({ text = "\255" }), 100, Social)), "Invalid text.", "bad UTF-8")
end)

test("the daily limit resets on a new UTC day", function()
	local social = { ThesisDay = "", ThesesToday = 0 }

	for _ = 1, 2 do
		equal(ThesisModule.checkDailyLimit(social, NOW, 2), true)
		ThesisModule.countPublish(social, NOW)
	end

	equal(reason(ThesisModule.checkDailyLimit(social, NOW, 2)), "You can publish 2 theses a day.")
	equal(ThesisModule.checkDailyLimit(social, NOW + DAY, 2), true, "next day")

	ThesisModule.countPublish(social, NOW + DAY)
	equal(social.ThesesToday, 1)
end)

test("one open thesis per ticker", function()
	local theses = {
		{ id = "1-1", ticker = "AAPL", endsAt = NOW - 1 },
		{ id = "1-2", ticker = "MSFT", endsAt = NOW + DAY },
	}

	equal(ThesisModule.findOpen(theses, "AAPL", NOW), nil, "the AAPL one ended")
	equal(ThesisModule.findOpen(theses, "MSFT", NOW).id, "1-2")
end)

test("lists keep the newest up to a cap, and remove by id", function()
	local list = {}

	for index = 1, 4 do
		ThesisModule.addToList(list, { id = "t" .. index }, 3)
	end

	equal(#list, 3)
	equal(list[1].id, "t2")
	equal(ThesisModule.removeFromList(list, "t3"), true)
	equal(ThesisModule.removeFromList(list, "t3"), false)
	equal(#list, 2)
end)

test("viewers get copies, newest first, with text only if they can see it", function()
	local list = { { id = "a", text = "old" }, { id = "b" }, { id = "c", text = "new" } }
	local shown = ThesisModule.forViewer(list, 2, true)

	equal(#shown, 2)
	equal(shown[1].id, "c")
	equal(shown[1].text, "new")

	local hidden = ThesisModule.forViewer(list, 3, false)

	equal(hidden[1].text, nil)
	equal(hidden[1].textHidden, true)
	equal(hidden[2].textHidden, nil, "had no text to hide")
	equal(list[3].text, "new", "the stored list is untouched")
end)

test("open theses are counted per side", function()
	local list = {
		{ direction = "Bullish", endsAt = NOW + 1 },
		{ direction = "Bullish", endsAt = NOW + 1 },
		{ direction = "Bearish", endsAt = NOW + 1 },
		{ direction = "Bearish", endsAt = NOW - 1 },
	}

	equal(ThesisModule.countOpen(list, NOW), { Bullish = 2, Bearish = 1 })
end)

test("reports count each old-enough reporter once and cross the threshold once", function()
	local thesis = { id = "9-1" }
	local record, crossed = ThesisModule.addReport(nil, thesis, 1, true, NOW, 2)

	equal(record.counted, 1)
	equal(crossed, false)
	equal(record.thesis, thesis)

	record, crossed = ThesisModule.addReport(record, thesis, 1, true, NOW, 2)
	equal(record.counted, 1, "the same reporter again")
	equal(crossed, false)

	record, crossed = ThesisModule.addReport(record, thesis, 2, false, NOW, 2)
	equal(record.counted, 1, "a new account is recorded but not counted")
	equal(record.reporters["2"].counted, false)
	equal(crossed, false)

	record, crossed = ThesisModule.addReport(record, thesis, 3, true, NOW, 2)
	equal(record.counted, 2)
	equal(crossed, true)
	equal(record.takenDown, true)

	record, crossed = ThesisModule.addReport(record, thesis, 4, true, NOW, 2)
	equal(crossed, false, "already taken down")
end)
