local task = require("@lune/task")

local TestKit = require("./TestKit")
local RemoteGuard = require("../src/server/Modules/RemoteGuard")

local test, equal = TestKit.test, TestKit.equal

-- Stands in for a RemoteFunction: RemoteGuard only reads Name and sets
-- OnServerInvoke
local function fakeRemote(name)
	return { Name = name }
end

local function echo(_player, value)
	return value
end

test("allows a burst, then returns the limited result", function()
	local remote = fakeRemote("Burst")
	local player = {}

	RemoteGuard.handle(remote, { perMinute = 1, burst = 3 }, echo, "limited")

	equal(remote.OnServerInvoke(player, 1), 1)
	equal(remote.OnServerInvoke(player, 2), 2)
	equal(remote.OnServerInvoke(player, 3), 3)
	equal(remote.OnServerInvoke(player, 4), "limited")
end)

test("the limited result defaults to nil", function()
	local remote = fakeRemote("DefaultLimited")
	local player = {}

	RemoteGuard.handle(remote, { perMinute = 1, burst = 1 }, echo)

	equal(remote.OnServerInvoke(player, "first"), "first")
	equal(remote.OnServerInvoke(player, "second"), nil)
end)

test("each player and each remote has its own bucket", function()
	local orders, reads = fakeRemote("Orders"), fakeRemote("Reads")
	local alice, bob = {}, {}
	local limit = { perMinute = 1, burst = 1 }

	RemoteGuard.handle(orders, limit, echo, "limited")
	RemoteGuard.handle(reads, limit, echo, "limited")

	equal(orders.OnServerInvoke(alice, "a"), "a")
	equal(orders.OnServerInvoke(alice, "a"), "limited")
	equal(orders.OnServerInvoke(bob, "b"), "b")
	equal(reads.OnServerInvoke(alice, "r"), "r")
end)

test("tokens refill at perMinute", function()
	local remote = fakeRemote("Refill")
	local player = {}

	RemoteGuard.handle(remote, { perMinute = 600, burst = 1 }, echo, "limited") -- a token every 0.1 s

	equal(remote.OnServerInvoke(player, 1), 1)
	equal(remote.OnServerInvoke(player, 2), "limited")
	task.wait(0.25)
	equal(remote.OnServerInvoke(player, 3), 3)
end)

test("the shared tiers are all defined", function()
	for _, tier in ipairs({ "Poll", "Read", "Order", "Research", "Rare" }) do
		local limit = RemoteGuard.LIMITS[tier]

		equal(limit.perMinute > 0 and limit.burst >= 1, true, tier)
	end

	equal(RemoteGuard.TOO_MANY_REQUESTS.success, false)
end)

return nil
