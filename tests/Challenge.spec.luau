local TestKit = require("./TestKit")
local ChallengeModule = require("../src/server/Modules/ChallengeModule")
local Challenges = require("../src/shared/Config/Challenges")

local test, equal = TestKit.test, TestKit.equal

local TODAY = ChallengeModule.dayOf(TestKit.utc(2026, 10, 26, 15))

local function everything()
	return true
end

local function newDaily()
	return { Day = 0, Challenges = {}, StreakDays = 0, StreakDay = 0, BestStreak = 0 }
end

local function entryFor(id)
	return { id = id, progress = 0, done = false, seen = {} }
end

test("dayOf counts UTC days, and the day resets at the next midnight", function()
	equal(ChallengeModule.dayOf(TestKit.utc(2026, 10, 26, 0)), ChallengeModule.dayOf(TestKit.utc(2026, 10, 26, 23)))
	equal(ChallengeModule.dayOf(TestKit.utc(2026, 10, 27, 0)), TODAY + 1)
	equal(ChallengeModule.resetsAt(TODAY), TestKit.utc(2026, 10, 27, 0))
end)

test("pick gives the same distinct challenges for the same day and player", function()
	local first = ChallengeModule.pick(Challenges.POOL, 3, TODAY, 42, everything)
	local again = ChallengeModule.pick(Challenges.POOL, 3, TODAY, 42, everything)
	local ids = {}

	equal(#first, 3)

	for index, entry in ipairs(first) do
		equal(entry.id, again[index].id, "same order")
		equal(ids[entry.id], nil, "no repeats")
		equal(entry.progress, 0)
		equal(entry.done, false)
		ids[entry.id] = true
	end
end)

test("pick varies across days and players", function()
	local seen = {}
	local distinctSets = 0

	for offset = 0, 9 do
		for _, userId in ipairs({ 1, 2, 3 }) do
			local key = {}

			for _, entry in ipairs(ChallengeModule.pick(Challenges.POOL, 3, TODAY + offset, userId, everything)) do
				table.insert(key, entry.id)
			end

			local joined = table.concat(key, ",")

			if not seen[joined] then
				seen[joined] = true
				distinctSets += 1
			end
		end
	end

	equal(distinctSets > 10, true, "30 picks give more than 10 different sets")
end)

test("pick only offers eligible challenges, and fewer when few are eligible", function()
	local onlyFills = ChallengeModule.pick(Challenges.POOL, 3, TODAY, 7, function(challenge)
		return challenge.event == "fill"
	end)

	for _, entry in ipairs(onlyFills) do
		equal(Challenges.get(entry.id).event, "fill", entry.id)
	end

	local onlyOne = ChallengeModule.pick(Challenges.POOL, 3, TODAY, 7, function(challenge)
		return challenge.id == "Thesis"
	end)

	equal(#onlyOne, 1)
	equal(onlyOne[1].id, "Thesis")
end)

test("matches checks the event and each narrowing field", function()
	local buyRoblox = Challenges.get("BuyRoblox")

	equal(ChallengeModule.matches(buyRoblox, { kind = "fill", side = "Buy", assetClass = "roblox" }), true)
	equal(ChallengeModule.matches(buyRoblox, { kind = "fill", side = "Sell", assetClass = "roblox" }), false)
	equal(ChallengeModule.matches(buyRoblox, { kind = "fill", side = "Buy", assetClass = "crypto" }), false)
	equal(ChallengeModule.matches(buyRoblox, { kind = "thesis" }), false)

	local sellProfit = Challenges.get("SellProfit")

	equal(ChallengeModule.matches(sellProfit, { kind = "fill", side = "Sell", profit = true }), true)
	equal(ChallengeModule.matches(sellProfit, { kind = "fill", side = "Sell", profit = false }), false)
	equal(ChallengeModule.matches(Challenges.get("Option"), { kind = "fill", side = "Buy" }), false)
	equal(ChallengeModule.matches(Challenges.get("Option"), { kind = "fill", side = "Buy", option = true }), true)
end)

test("advance counts matching events and finishes at the goal", function()
	local entry = entryFor("Trade3")
	local challenge = Challenges.get("Trade3")
	local fill = { kind = "fill", side = "Buy", key = "AAPL" }

	equal(select(1, ChallengeModule.advance(entry, challenge, { kind = "thesis" })), false, "wrong event")
	equal(select(2, ChallengeModule.advance(entry, challenge, fill)), false)
	equal(select(2, ChallengeModule.advance(entry, challenge, fill)), false)

	local changed, finished = ChallengeModule.advance(entry, challenge, fill)

	equal(changed, true)
	equal(finished, true)
	equal(entry.done, true)
	equal(select(1, ChallengeModule.advance(entry, challenge, fill)), false, "done stays done")
	equal(entry.progress, 3)
end)

test("advance counts each ticker or post once for distinct challenges", function()
	local entry = entryFor("Tickers3")
	local challenge = Challenges.get("Tickers3")

	ChallengeModule.advance(entry, challenge, { kind = "fill", key = "AAPL" })
	equal(select(1, ChallengeModule.advance(entry, challenge, { kind = "fill", key = "AAPL" })), false, "repeat")
	equal(select(1, ChallengeModule.advance(entry, challenge, { kind = "fill" })), false, "no key")
	ChallengeModule.advance(entry, challenge, { kind = "fill", key = "BTC-USD" })
	equal(entry.progress, 2)
	equal(select(2, ChallengeModule.advance(entry, challenge, { kind = "fill", key = "RBX-ADPT" })), true)
end)

test("extendStreak starts, grows a day at a time, and restarts after a gap", function()
	local daily = newDaily()

	equal(ChallengeModule.extendStreak(daily, TODAY), 1)
	equal(ChallengeModule.extendStreak(daily, TODAY), nil, "once a day")
	equal(ChallengeModule.extendStreak(daily, TODAY + 1), 2)
	equal(ChallengeModule.extendStreak(daily, TODAY + 2), 3)
	equal(ChallengeModule.extendStreak(daily, TODAY + 4), 1, "a missed day")
	equal(daily.BestStreak, 3)
end)

test("currentStreak holds through the next day and breaks after it", function()
	local daily = newDaily()

	equal(ChallengeModule.currentStreak(daily, TODAY), 0)
	ChallengeModule.extendStreak(daily, TODAY)
	ChallengeModule.extendStreak(daily, TODAY + 1)
	equal(ChallengeModule.currentStreak(daily, TODAY + 1), 2)
	equal(ChallengeModule.currentStreak(daily, TODAY + 2), 2, "not done yet today")
	equal(ChallengeModule.currentStreak(daily, TODAY + 3), 0)
end)

test("every challenge is complete and can be looked up", function()
	for _, challenge in ipairs(Challenges.POOL) do
		equal(type(challenge.text), "string", challenge.id)
		equal(challenge.goal >= 1, true, challenge.id)
		equal(Challenges.get(challenge.id), challenge, challenge.id)
		equal(challenge.event == "fill" or challenge.event == "thesis" or challenge.event == "reaction", true)
	end
end)

test("the streak bonus grows with the streak up to its cap", function()
	equal(Challenges.getStreakXP(1), Challenges.STREAK_XP_PER_DAY)
	equal(Challenges.getStreakXP(3), Challenges.STREAK_XP_PER_DAY * 3)
	equal(Challenges.getStreakXP(100), Challenges.STREAK_XP_PER_DAY * Challenges.STREAK_XP_MAX_DAYS)
end)
