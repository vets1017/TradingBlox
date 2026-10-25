local TestKit = require("./TestKit")
local InboxModule = require("../src/server/Modules/InboxModule")
local Social = require("../src/shared/Config/Social")

local test, equal = TestKit.test, TestKit.equal

local NOW = 1_800_000_000

local function note(id, at)
	return { id = id, kind = "Follow", at = at or NOW, fromUserId = 1, fromName = "Ann" }
end

test("adding skips a notification already there and keeps the newest", function()
	local inbox = {}

	equal(InboxModule.add(inbox, note("a"), 2), true)
	equal(InboxModule.add(inbox, note("a"), 2), false, "delivered twice")
	InboxModule.add(inbox, note("b"), 2)
	InboxModule.add(inbox, note("c"), 2)

	equal(#inbox, 2)
	equal(inbox[1].id, "b")
	equal(InboxModule.has(inbox, "a"), false)
end)

test("unread counts what arrived after the inbox was last opened", function()
	local inbox = { note("a", NOW - 10), note("b", NOW), note("c", NOW + 10) }

	equal(InboxModule.countUnread(inbox, NOW), 1)
	equal(InboxModule.countUnread(inbox, 0), 3)
end)

test("newest first, up to a limit", function()
	local inbox = { note("a"), note("b"), note("c") }
	local items = InboxModule.newestFirst(inbox, 2)

	equal(#items, 2)
	equal(items[1].id, "c")
	equal(items[2].id, "b")
end)

test("every notification kind reads as a title and body", function()
	equal(
		{ Social.describeNotification({ kind = "Follow", fromName = "Ann" }) },
		{ "New follower", "Ann followed you." }
	)
	equal({
		Social.describeNotification({
			kind = "Reaction",
			fromName = "Ann",
			reaction = "Fire",
			itemKind = "Thesis",
			ticker = "AAPL",
		}),
	}, { "New reaction", "Ann reacted 🔥 to your thesis on AAPL." })
	equal(
		select(
			2,
			Social.describeNotification({
				kind = "Reaction",
				fromName = "Ann",
				reaction = "Eyes?",
				itemKind = "Milestone",
			})
		),
		"Ann reacted to your milestone.",
		"an unknown reaction"
	)
	equal({ Social.describeNotification({ kind = "ThesisRemoved", ticker = "TSLA" }) }, {
		"Thesis taken down",
		"Your thesis on TSLA was taken down after reports.",
	})
end)
