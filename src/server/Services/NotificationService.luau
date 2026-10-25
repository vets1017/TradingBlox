-- NotificationService.luau
--
-- Each player's inbox (GDD §2): new followers, reactions to their posts,
-- and a thesis taken down after reports. A notification is left in the
-- recipient's profile as a ProfileStore message, so it reaches them on any
-- server or when they next join; a MessagingService broadcast also shows it
-- as a toast within seconds wherever they're playing. The recipient's mutes
-- and Roblox blocks drop notifications from those players. The client
-- words each one from its fields (Social.describeNotification) - none are
-- typed by players.

local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Social = require(ReplicatedStorage.Config.Social)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local MuteService = require(ServerScriptService.Services.MuteService)
local InboxModule = require(ServerScriptService.Modules.InboxModule)

local NotificationEvent = ReplicatedStorage:WaitForChild("EventsFolder"):WaitForChild("NotificationEvent")

local TOPIC = "Notifications_v1"

-- Weak keys, so a player who has left drops out on their own
local sentOnce = setmetatable({}, { __mode = "k" }) -- [sender] = { [key] = true }

local NotificationService = {}

-- A notification of `kind` with its fields, stamped with an id and time
function NotificationService.new(kind: string, fields)
	local notification = table.clone(fields or {})

	notification.kind = kind
	notification.id = HttpService:GenerateGUID(false)
	notification.at = os.time()

	return notification
end

-- Dropped when the recipient muted or blocked the sender
local function isWanted(player, notification): boolean
	return not (notification.fromUserId and MuteService.getFilter(player).hidesUser(notification.fromUserId))
end

-- Tells the client the unread count, with a toast for a live notification.
-- A live one can arrive before its ProfileStore message, so it's counted
-- even when it isn't in the inbox yet.
local function push(player, notification, toast: boolean)
	local data = PlayerDataService.get(player)

	if not data then
		return
	end

	local unread = InboxModule.countUnread(data.Social.Inbox, data.Social.InboxSeenAt)

	if toast and not InboxModule.has(data.Social.Inbox, notification.id) then
		unread += 1
	end

	NotificationEvent:FireClient(player, { notification = notification, toast = toast, unread = unread })
end

-- Puts a notification in the inbox of a player on this server
function NotificationService.deliver(player, data, notification, toast: boolean)
	if isWanted(player, notification) and InboxModule.add(data.Social.Inbox, notification, Social.INBOX_SIZE) then
		push(player, notification, toast)
	end
end

-- Sends a notification to any player, wherever they are. Yields, so callers
-- spawn it.
function NotificationService.notify(userId: number, notification)
	-- Live first, so an online player sees the toast before the inbox catches up
	local success, err =
		pcall(MessagingService.PublishAsync, MessagingService, TOPIC, { userId = userId, notification = notification })

	if not success then
		warn("[NotificationService] Couldn't broadcast a notification: " .. tostring(err))
	end

	PlayerDataService.sendMessage(userId, { kind = "Notification", notification = notification })
end

-- notify, but at most once a session for each `key` from `sender`, so
-- following, unfollowing and following again doesn't notify every time
function NotificationService.notifyOnce(sender, key: string, userId: number, notification)
	local sent = sentOnce[sender]

	if not sent then
		sent = {}
		sentOnce[sender] = sent
	end

	if sent[key] then
		return
	end

	sent[key] = true
	NotificationService.notify(userId, notification)
end

-- { items (newest first), unread }, or nil before the profile loads
function NotificationService.getInbox(player)
	local data = PlayerDataService.get(player)

	if not data then
		return nil
	end

	local social = data.Social

	return {
		items = InboxModule.newestFirst(social.Inbox, Social.INBOX_SIZE),
		unread = InboxModule.countUnread(social.Inbox, social.InboxSeenAt),
	}
end

function NotificationService.markSeen(player)
	local data = PlayerDataService.get(player)

	if data then
		data.Social.InboxSeenAt = os.time()
	end
end

-- Must run before PlayerDataService.start, so no message is missed
function NotificationService.start()
	PlayerDataService.onMessage("Notification", function(player, data, message)
		if type(message.notification) == "table" then
			NotificationService.deliver(player, data, message.notification, false)
		end
	end)

	-- Spawned: subscribing yields
	task.spawn(function()
		local success, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(packet)
			local message = packet.Data
			local player = type(message) == "table" and Players:GetPlayerByUserId(message.userId)

			if player and type(message.notification) == "table" and isWanted(player, message.notification) then
				push(player, message.notification, true)
			end
		end)

		if not success then
			warn("[NotificationService] Couldn't subscribe to live notifications: " .. tostring(err))
		end
	end)
end

return NotificationService
