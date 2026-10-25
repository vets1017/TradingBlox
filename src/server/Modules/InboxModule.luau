-- InboxModule.luau
--
-- The rules for a player's inbox (`playerData.Social.Inbox`, oldest first),
-- kept free of Roblox services so the Lune tests can run them.
-- NotificationService fills it.
--
-- A notification: { id, kind, at, fromUserId?, fromName?, ... } - see
-- Config/Social's describeNotification for each kind's fields.

local InboxModule = {}

function InboxModule.has(inbox, id: string): boolean
	for _, notification in ipairs(inbox) do
		if notification.id == id then
			return true
		end
	end

	return false
end

-- Appends a notification, dropping the oldest past `cap`. Returns false if
-- it was already there (a message can be delivered twice).
function InboxModule.add(inbox, notification, cap: number): boolean
	if InboxModule.has(inbox, notification.id) then
		return false
	end

	table.insert(inbox, notification)

	while #inbox > cap do
		table.remove(inbox, 1)
	end

	return true
end

-- Notifications newer than when the player last opened the inbox
function InboxModule.countUnread(inbox, seenAt: number): number
	local count = 0

	for _, notification in ipairs(inbox) do
		if notification.at > seenAt then
			count += 1
		end
	end

	return count
end

function InboxModule.newestFirst(inbox, limit: number)
	local items = {}

	for index = #inbox, math.max(#inbox - limit + 1, 1), -1 do
		table.insert(items, inbox[index])
	end

	return items
end

return InboxModule
