-- InboxController.client.luau
--
-- The inbox (GDD §2): the unread badge on ShellController's bell, and the
-- list of notifications the bell opens under it - new followers, reactions
-- and theses taken down. Opening the list marks everything read. A row
-- opens the player it's about, or the ticker. Toasts for live
-- notifications are ShellController's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local Social = require(ReplicatedStorage.Config.Social)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetInboxEvent = EventsFolder:WaitForChild("GetInboxEvent")
local MarkInboxSeenEvent = EventsFolder:WaitForChild("MarkInboxSeenEvent")
local NotificationEvent = EventsFolder:WaitForChild("NotificationEvent")

-- References
local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local MainBackground = TerminalGui:WaitForChild("MainBackground")
local InboxButton = MainBackground:WaitForChild("TopBar"):WaitForChild("InboxButton")
local InboxBadge = InboxButton:WaitForChild("Badge")

-- Layout Constants
local PANEL_WIDTH = 340
local PANEL_MAX_HEIGHT = 420
local PADDING = 12
local TITLE_HEIGHT = 20
local ROW_HEIGHT = 48
local AVATAR_SIZE = 28
local Z_INDEX = 20 -- TerminalGui renders by global ZIndex, so the list sits above every screen

local STARTUP_RETRIES = 10
local RETRY_DELAY = 1.1

-- State
local isOpen = false
local isLoading = false

local makeLabel = UIKit.makeLabel

-- "3 min ago", "2 h ago", "just now"
local function formatAge(seconds)
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. " min ago"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. " h ago"
	end

	return math.floor(seconds / 86400) .. " d ago"
end

local function raise(root)
	root.ZIndex = Z_INDEX

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = Z_INDEX
		end
	end
end

local function setUnread(count)
	InboxBadge.Visible = count > 0
	InboxBadge.Text = count > 9 and "9+" or tostring(count)
end

-- Panel
local InboxPanel = UIKit.makePanel("InboxPanel", MainBackground)
InboxPanel.AnchorPoint = Vector2.new(1, 0)
InboxPanel.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
InboxPanel.AutomaticSize = Enum.AutomaticSize.Y
InboxPanel.Visible = false

local PanelPadding = Instance.new("UIPadding")
PanelPadding.PaddingTop = UDim.new(0, PADDING)
PanelPadding.PaddingBottom = UDim.new(0, PADDING)
PanelPadding.PaddingLeft = UDim.new(0, PADDING)
PanelPadding.PaddingRight = UDim.new(0, PADDING)
PanelPadding.Parent = InboxPanel

local PanelLayout = Instance.new("UIListLayout")
PanelLayout.SortOrder = Enum.SortOrder.LayoutOrder
PanelLayout.Padding = UDim.new(0, 8)
PanelLayout.Parent = InboxPanel

local PanelTitle = makeLabel("Title", InboxPanel, Theme.Fonts.UIBold, Theme.TextSize.Title, Theme.Colors.Text)
PanelTitle.LayoutOrder = 1
PanelTitle.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
PanelTitle.Text = "Notifications"

local List = Instance.new("ScrollingFrame")
List.Name = "List"
List.LayoutOrder = 2
List.Size = UDim2.fromScale(1, 0) -- render sets the height
List.BackgroundTransparency = 1
List.BorderSizePixel = 0
List.ScrollBarThickness = 4
List.ScrollBarImageColor3 = Theme.Colors.TextDisabled
List.ScrollingDirection = Enum.ScrollingDirection.Y
List.CanvasSize = UDim2.new()
List.AutomaticCanvasSize = Enum.AutomaticSize.Y
List.Parent = InboxPanel

local ListLayout = Instance.new("UIListLayout")
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Padding = UDim.new(0, 2)
ListLayout.Parent = List

local Message = makeLabel("Message", InboxPanel, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
Message.LayoutOrder = 3
Message.Size = UDim2.new(1, 0, 0, 20)
Message.TextWrapped = true

local function close()
	isOpen = false
	InboxPanel.Visible = false
end

-- Follows and reactions open the player; a thesis taken down, its ticker
local function openNotification(notification)
	close()

	if notification.fromUserId then
		Navigation.openProfile(notification.fromUserId)
	elseif notification.ticker then
		Navigation.openTicker(notification.ticker)
	end
end

local function createRow(index, notification, seenAt)
	local title, body = Social.describeNotification(notification)
	local isUnread = notification.at > seenAt

	local row = Instance.new("TextButton")
	row.Name = "Notification_" .. index
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -6, 0, ROW_HEIGHT)
	row.AutoButtonColor = false
	row.BorderSizePixel = 0
	row.BackgroundColor3 = Theme.Colors.Raised
	row.BackgroundTransparency = isUnread and 0 or 1
	row.Text = ""
	row.Parent = List
	UIKit.addCorner(row)

	local textX = 8

	if notification.fromUserId then
		local avatar = UIKit.makeAvatar("Avatar", row, notification.fromUserId, AVATAR_SIZE)
		avatar.AnchorPoint = Vector2.new(0, 0.5)
		avatar.Position = UDim2.new(0, 6, 0.5, 0)
		textX = 6 + AVATAR_SIZE + 8
	end

	local titleLabel = makeLabel("Title", row, Theme.Fonts.UISemibold, Theme.TextSize.Body, Theme.Colors.Text)
	titleLabel.Position = UDim2.fromOffset(textX, 6)
	titleLabel.Size = UDim2.new(1, -(textX + 80), 0, 18)
	titleLabel.Text = title

	local age = makeLabel("Age", row, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	age.AnchorPoint = Vector2.new(1, 0)
	age.Position = UDim2.new(1, -8, 0, 6)
	age.Size = UDim2.fromOffset(72, 18)
	age.TextXAlignment = Enum.TextXAlignment.Right
	age.Text = formatAge(os.time() - notification.at)

	local bodyLabel = makeLabel("Body", row, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	bodyLabel.Position = UDim2.fromOffset(textX, 25)
	bodyLabel.Size = UDim2.new(1, -(textX + 8), 0, 16)
	bodyLabel.Text = body

	row.MouseButton1Click:Connect(function()
		openNotification(notification)
	end)
end

local function render(inbox, seenAt)
	for _, child in ipairs(List:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local items = inbox and inbox.items or {}

	Message.Visible = #items == 0
	Message.Text = inbox and "Nothing yet. New followers and reactions to your posts show up here."
		or "Couldn't load your notifications. Try again in a moment."

	for index, notification in ipairs(items) do
		createRow(index, notification, seenAt)
	end

	List.Size = UDim2.new(1, 0, 0, math.min(#items * (ROW_HEIGHT + 2), PANEL_MAX_HEIGHT))
	raise(InboxPanel)
end

local function invoke(remote)
	local success, result = pcall(remote.InvokeServer, remote)

	if not success then
		warn("[InboxController] " .. remote.Name .. " failed: " .. tostring(result))

		return nil
	end

	return result
end

-- Fetches and shows the inbox, then marks it read: rows that were unread
-- stay highlighted for this look
local function load()
	if isLoading then
		return
	end

	isLoading = true

	local inbox = invoke(GetInboxEvent)

	if inbox == nil then
		task.wait(RETRY_DELAY)
		inbox = invoke(GetInboxEvent)
	end

	isLoading = false

	if not isOpen then
		return
	end

	local seenAt = math.huge

	-- Highlights what was unread: the items newer than the unread cut
	if inbox and inbox.unread > 0 and inbox.items[inbox.unread] then
		seenAt = inbox.items[inbox.unread].at - 1
	end

	render(inbox, seenAt)

	if inbox and inbox.unread > 0 then
		invoke(MarkInboxSeenEvent)
	end

	setUnread(0)
end

local function open()
	local buttonPosition = InboxButton.AbsolutePosition
	local buttonSize = InboxButton.AbsoluteSize
	local origin = MainBackground.AbsolutePosition

	isOpen = true
	InboxPanel.Position =
		UDim2.fromOffset(buttonPosition.X + buttonSize.X - origin.X, buttonPosition.Y + buttonSize.Y + 6 - origin.Y)
	InboxPanel.Visible = true
	raise(InboxPanel)
	load()
end

-- Connections
InboxButton.MouseButton1Click:Connect(function()
	if isOpen then
		close()
	else
		open()
	end
end)

-- A new notification, or the count after one landed in the inbox
NotificationEvent.OnClientEvent:Connect(function(update)
	if isOpen then
		task.spawn(load)
	elseif update.unread then
		setUnread(update.unread)
	end
end)

-- The count waiting from while the player was away; the profile may still
-- be loading, so it's asked again a few times
task.spawn(function()
	for _ = 1, STARTUP_RETRIES do
		local inbox = invoke(GetInboxEvent)

		if inbox then
			if not isOpen then
				setUnread(inbox.unread)
			end

			return
		end

		task.wait(RETRY_DELAY)
	end
end)
