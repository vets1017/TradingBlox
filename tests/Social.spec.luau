local TestKit = require("./TestKit")
local SocialModule = require("../src/server/Modules/SocialModule")

local test, equal = TestKit.test, TestKit.equal

local NOW = 1_800_000_000
local ME = 100
local OTHER = 200

-- playerData.Social as PlayerDataService's template starts it
local function newSocial()
	return { Following = {}, ShareTrades = true }
end

test("following and unfollowing a player", function()
	local social = newSocial()

	equal(SocialModule.isFollowing(social, OTHER), false)

	SocialModule.setFollowing(social, OTHER, true, NOW)

	equal(SocialModule.isFollowing(social, OTHER), true)
	equal(SocialModule.countFollowing(social), 1)
	equal(social.Following["200"], NOW, "keyed by the id as a string")

	SocialModule.setFollowing(social, OTHER, false, NOW)

	equal(SocialModule.isFollowing(social, OTHER), false)
	equal(SocialModule.countFollowing(social), 0)
end)

test("a player can follow someone else under the cap", function()
	equal(SocialModule.checkFollow(newSocial(), ME, OTHER, 200), true)
end)

test("a player can't follow themselves", function()
	local ok, message = SocialModule.checkFollow(newSocial(), ME, ME, 200)

	equal(ok, false)
	equal(message, "You can't follow yourself.")
end)

test("the cap stops new follows", function()
	local social = newSocial()

	SocialModule.setFollowing(social, 1, true, NOW)
	SocialModule.setFollowing(social, 2, true, NOW)

	local ok, message = SocialModule.checkFollow(social, ME, OTHER, 2)

	equal(ok, false)
	equal(message, "You can follow up to 2 players.")
end)

local function makeLog(count)
	local log = {}

	for index = 1, count do
		table.insert(log, { time = NOW + index, ticker = "T" .. index, side = "Buy", quantity = index, price = 10 })
	end

	return log
end

test("recent trades are the newest fills, newest first", function()
	local trades = SocialModule.getRecentTrades(makeLog(12), 10)

	equal(#trades, 10)
	equal(trades[1].ticker, "T12")
	equal(trades[10].ticker, "T3")
end)

test("recent trades from a short log", function()
	equal(#SocialModule.getRecentTrades(makeLog(3), 10), 3)
	equal(SocialModule.getRecentTrades({}, 10), {})
end)

test("recent trades keep every field and are copies", function()
	local log = {
		{ time = NOW, ticker = "AAPL", contract = "AAPL261120C00300000", side = "Sell", quantity = 2, price = 1.5 },
	}

	log[1].realizedPL = -100
	log[1].settlement = "Expired"

	local trades = SocialModule.getRecentTrades(log, 10)

	equal(trades[1], log[1])

	trades[1].ticker = "MSFT"

	equal(log[1].ticker, "AAPL", "the log is untouched")
end)

test("muting and unmuting a player", function()
	local social = { Following = {}, Muted = {} }

	SocialModule.setMuted(social, OTHER, true, NOW)
	equal(SocialModule.isMuted(social, OTHER), true)
	equal(social.Muted["200"], NOW)

	SocialModule.setMuted(social, OTHER, false, NOW)
	equal(SocialModule.isMuted(social, OTHER), false)
end)

test("a player can't mute themselves or past the cap", function()
	local social = { Following = {}, Muted = {} }

	equal(select(2, SocialModule.checkMute(social, ME, ME, 2)), "You can't mute yourself.")

	SocialModule.setMuted(social, 1, true, NOW)
	SocialModule.setMuted(social, 2, true, NOW)

	equal(select(2, SocialModule.checkMute(social, ME, OTHER, 2)), "You can mute up to 2 players.")
	equal(SocialModule.checkMute(social, ME, OTHER, 3), true)
end)

test("a capped map drops its oldest entry", function()
	local map = {}

	SocialModule.addCapped(map, "a", NOW, 2)
	SocialModule.addCapped(map, "b", NOW + 1, 2)
	SocialModule.addCapped(map, "c", NOW + 2, 2)

	equal(map, { b = NOW + 1, c = NOW + 2 })
end)
