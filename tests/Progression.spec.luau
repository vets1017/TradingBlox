local TestKit = require("./TestKit")
local Progression = require("../src/shared/Config/Progression")

local test, equal, errors = TestKit.test, TestKit.equal, TestKit.errors

test("getLevel steps up exactly at each threshold", function()
	for _, case in ipairs({ { 0, 1 }, { 299, 1 }, { 300, 2 }, { 999, 2 }, { 1000, 3 }, { 3000, 4 }, { 1e9, 4 } }) do
		equal(Progression.getLevel(case[1]), case[2], case[1] .. " XP")
	end
end)

test("level thresholds rise", function()
	equal(Progression.LEVELS[1].xp, 0)

	for i = 2, #Progression.LEVELS do
		equal(Progression.LEVELS[i].xp > Progression.LEVELS[i - 1].xp, true, "level " .. i)
	end
end)

test("isUnlocked compares against the feature's level, and rejects unknown features", function()
	equal(Progression.isUnlocked(1, "LimitOrders"), false)
	equal(Progression.isUnlocked(2, "LimitOrders"), true)
	equal(Progression.isUnlocked(2, "Options"), false)
	errors(function()
		Progression.isUnlocked(4, "Teleport")
	end)
end)

test("every feature unlocks at a real level and has a display name", function()
	for feature, level in pairs(Progression.FEATURES) do
		equal(Progression.LEVELS[level] ~= nil, true, feature .. " level")
		equal(type(Progression.FEATURE_NAMES[feature]), "string", feature .. " name")
	end
end)

test("getLockedMessage names the level", function()
	equal(Progression.getLockedMessage("Options"), "Unlocks at Level 3 · Advanced Trader")
end)

test("getUnlocksAt lists that level's features, sorted", function()
	equal(Progression.getUnlocksAt(1), {})
	equal(Progression.getUnlocksAt(2), {
		"chart indicators",
		"fundamentals and analyst reports",
		"limit orders",
		"portfolio analytics",
	})
end)

test("milestone tutorial steps have a milestone to claim", function()
	for _, step in ipairs(Progression.TUTORIAL) do
		if step.milestone then
			equal(type(Progression.MILESTONES[step.id]), "number", step.id)
		end
	end

	equal(Progression.getTutorialStep("FirstTrade").milestone, true)
	equal(Progression.getTutorialStep("Nope"), nil)
end)

return nil
