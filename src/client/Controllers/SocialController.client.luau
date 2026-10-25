-- SocialController.client.luau
--
-- Builds and runs the Social tab (GDD §2): the feed of executed trades and
-- milestones from every player, or only from the players you follow. A row
-- opens its player's profile; a trade's ticker opens on the Trade tab.
-- Built in code inside the empty screen ShellController adds;
-- TerminalController switches to it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local Social = require(ReplicatedStorage.Config.Social)
local Progression = require(ReplicatedStorage.Config.Progression)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetFeedEvent = EventsFolder:WaitForChild("GetFeedEvent")

-- References
local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local MainBackground = TerminalGui:WaitForChild("MainBackground")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")
local SocialScreen = ScreenContainer:WaitForChild("SocialScreen")

-- Layout Constants
local PADDING = 16
local GAP = 12
local MAX_FEED_WIDTH = 760
local TITLE_HEIGHT = 24
local SUBTITLE_HEIGHT = 16
local PILL_HEIGHT = 26
local PILL_TEXT_PADDING = 12
local ROW_HEIGHT = 56
local ROW_INSET = 8 -- the hover highlight reaches this far past the row's content
local AVATAR_SIZE = 32
local TEXT_X = AVATAR_SIZE + 10
local KIND_WIDTH = 130
local TICKER_PILL_WIDTH = 76
local TICKER_PILL_HEIGHT = 24

local POLL_INTERVAL = 5
local RETRY_DELAY = 1.1 -- past the server's per-request cooldown when throttled

local KIND_LABELS = {
	Trade = "Executed trade",
	Milestone = "Milestone",
}

-- State
local selectedView = Social.FEED_VIEWS[1]
local requestId = 0
local renderedSignature = nil -- the view and item ids on screen; an unchanged poll keeps scroll and hover
local ageLabels = {} -- [label] = item, so ages tick without rebuilding rows

local makeFrame = UIKit.makeFrame
local makeLabel = UIKit.makeLabel

-- Formatting
local UP_HEX = Theme.Colors.Up:ToHex()
local DOWN_HEX = Theme.Colors.Down:ToHex()
local MUTED_HEX = Theme.Colors.TextMuted:ToHex()

local RICH_TEXT_ESCAPES = { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" }

local function escape(text: string): string
	return (string.gsub(text, "[<>&]", RICH_TEXT_ESCAPES))
end

local function formatSignedMoney(amount)
	return (amount >= 0 and "+" or "-") .. NumberModule.format(math.abs(amount))
end

-- "now", "12m", "3h", "2d"
local function formatAge(seconds)
	if seconds < 60 then
		return "now"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. "h"
	end

	return math.floor(seconds / 86400) .. "d"
end

local function describeKind(item)
	return string.format("%s · %s", KIND_LABELS[item.kind] or item.kind, formatAge(os.time() - item.time))
end

-- "Bought 5 AAPL @ $182.10", with the realized P/L after a sale;
-- "Reached Level 2 · Investor" for a milestone
local function describeItem(item)
	if item.kind == "Trade" then
		local isBuy = item.side == "Buy"
		local realized = ""

		if item.realizedPL then
			realized = string.format(
				' <font color="#%s">%s</font>',
				item.realizedPL >= 0 and UP_HEX or DOWN_HEX,
				formatSignedMoney(item.realizedPL)
			)
		end

		return string.format(
			'<font color="#%s">%s</font> %s %s%s @ %s%s',
			isBuy and UP_HEX or DOWN_HEX,
			isBuy and "Bought" or "Sold",
			NumberModule.formatShares(item.quantity),
			item.ticker,
			item.contract and " opt" or "",
			NumberModule.format(item.price),
			realized
		)
	end

	local levelInfo = item.level and Progression.LEVELS[item.level]

	if levelInfo then
		return string.format("Reached Level %d · %s", item.level, levelInfo.name)
	end

	return Social.FEED_MILESTONES[item.milestone] or "Reached a milestone"
end

-- Feed Panel
local FeedPanel = UIKit.makePanel("FeedPanel", SocialScreen)

local FeedTitle = makeLabel("Title", FeedPanel, Theme.Fonts.UIBold, Theme.TextSize.Title, Theme.Colors.Text)
FeedTitle.Position = UDim2.fromOffset(PADDING, PADDING)
FeedTitle.Size = UDim2.new(0.5, -PADDING, 0, TITLE_HEIGHT)
FeedTitle.Text = "Feed"

local FeedSubtitle = makeLabel("Subtitle", FeedPanel, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
FeedSubtitle.Position = UDim2.fromOffset(PADDING, PADDING + TITLE_HEIGHT)
FeedSubtitle.Size = UDim2.new(1, -PADDING * 2, 0, SUBTITLE_HEIGHT)
FeedSubtitle.Text = "Trades and milestones from TradingBlox players. Simulated trading, not financial advice."

local ViewPills = makeFrame("ViewPills", FeedPanel)
ViewPills.AnchorPoint = Vector2.new(1, 0)
ViewPills.Position = UDim2.new(1, -PADDING, 0, PADDING)
ViewPills.Size = UDim2.new(0.5, -PADDING, 0, PILL_HEIGHT)

local ViewPillsLayout = Instance.new("UIListLayout")
ViewPillsLayout.FillDirection = Enum.FillDirection.Horizontal
ViewPillsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
ViewPillsLayout.SortOrder = Enum.SortOrder.LayoutOrder
ViewPillsLayout.Padding = UDim.new(0, 4)
ViewPillsLayout.Parent = ViewPills

local viewPills = {} -- [view] = { button, stroke }

for index, view in ipairs(Social.FEED_VIEWS) do
	local button = Instance.new("TextButton")
	button.Name = "View_" .. view
	button.LayoutOrder = index
	button.AutomaticSize = Enum.AutomaticSize.X
	button.Size = UDim2.fromScale(0, 1)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Theme.Colors.Raised
	button.FontFace = Theme.Fonts.UISemibold
	button.TextSize = Theme.TextSize.Caption
	button.Text = view
	button.Parent = ViewPills
	UIKit.addCorner(button)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, PILL_TEXT_PADDING)
	padding.PaddingRight = UDim.new(0, PILL_TEXT_PADDING)
	padding.Parent = button

	viewPills[view] = { button = button, stroke = UIKit.addStroke(button) }
end

local LIST_TOP = PADDING + TITLE_HEIGHT + SUBTITLE_HEIGHT + GAP

-- Starts ROW_INSET left of the content so a row's highlight can extend past
-- it, and runs to the panel's right edge so the scrollbar sits in the padding
local FeedList = Instance.new("ScrollingFrame")
FeedList.Name = "FeedList"
FeedList.Position = UDim2.fromOffset(PADDING - ROW_INSET, LIST_TOP)
FeedList.Size = UDim2.new(1, -(PADDING - ROW_INSET), 1, -(LIST_TOP + PADDING))
FeedList.BackgroundTransparency = 1
FeedList.BorderSizePixel = 0
FeedList.ScrollBarThickness = 4
FeedList.ScrollBarImageColor3 = Theme.Colors.TextDisabled
FeedList.ScrollingDirection = Enum.ScrollingDirection.Y
FeedList.CanvasSize = UDim2.new()
FeedList.AutomaticCanvasSize = Enum.AutomaticSize.Y
FeedList.Parent = FeedPanel

local FeedListLayout = Instance.new("UIListLayout")
FeedListLayout.SortOrder = Enum.SortOrder.LayoutOrder
FeedListLayout.Padding = UDim.new(0, 2)
FeedListLayout.Parent = FeedList

local FeedMessage = makeLabel("Message", FeedPanel, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
FeedMessage.Position = UDim2.fromOffset(PADDING, LIST_TOP + GAP)
FeedMessage.Size = UDim2.new(1, -PADDING * 2, 0, 40)
FeedMessage.TextWrapped = true
FeedMessage.TextXAlignment = Enum.TextXAlignment.Center
FeedMessage.Text = "Loading…"

-- Rows
local function clearRows()
	for _, child in ipairs(FeedList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	table.clear(ageLabels)
end

-- A whole row opens the player's profile; a trade's ticker pill opens the
-- ticker instead (the pill sits on top, so it takes the click)
local function createRow(index, item)
	local isTrade = item.kind == "Trade" and item.ticker ~= nil
	local rightWidth = isTrade and TICKER_PILL_WIDTH + 8 or 0

	local row = Instance.new("TextButton")
	row.Name = "Item_" .. index
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -(PADDING - ROW_INSET), 0, ROW_HEIGHT)
	row.AutoButtonColor = false
	row.BorderSizePixel = 0
	row.BackgroundColor3 = Theme.Colors.Raised
	row.BackgroundTransparency = 1
	row.Text = ""
	row.Parent = FeedList
	UIKit.addCorner(row)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, ROW_INSET)
	padding.PaddingRight = UDim.new(0, ROW_INSET)
	padding.Parent = row

	local avatar = UIKit.makeAvatar("Avatar", row, item.userId, AVATAR_SIZE)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.fromScale(0, 0.5)

	local isYou = item.userId == Player.UserId

	local name = makeLabel("Name", row, Theme.Fonts.UISemibold, Theme.TextSize.Body, Theme.Colors.Text)
	name.Position = UDim2.fromOffset(TEXT_X, 9)
	name.Size = UDim2.new(1, -(TEXT_X + KIND_WIDTH + rightWidth), 0, 18)
	name.RichText = true
	name.Text = string.format(
		'%s%s <font color="#%s">@%s</font>',
		escape(item.displayName),
		isYou and " (you)" or "",
		MUTED_HEX,
		escape(item.username)
	)

	local kind = makeLabel("Kind", row, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	kind.AnchorPoint = Vector2.new(1, 0)
	kind.Position = UDim2.new(1, -rightWidth, 0, 9)
	kind.Size = UDim2.fromOffset(KIND_WIDTH, 18)
	kind.TextXAlignment = Enum.TextXAlignment.Right
	kind.Text = describeKind(item)
	ageLabels[kind] = item

	local detail = makeLabel(
		"Detail",
		row,
		isTrade and Theme.Fonts.Mono or Theme.Fonts.UI,
		isTrade and Theme.TextSize.Caption or Theme.TextSize.Body,
		Theme.Colors.Text
	)
	detail.Position = UDim2.fromOffset(TEXT_X, 29)
	detail.Size = UDim2.new(1, -(TEXT_X + rightWidth), 0, 18)
	detail.RichText = true
	detail.Text = describeItem(item)

	if isTrade then
		local tickerPill = Instance.new("TextButton")
		tickerPill.Name = "Ticker"
		tickerPill.AnchorPoint = Vector2.new(1, 0.5)
		tickerPill.Position = UDim2.fromScale(1, 0.5)
		tickerPill.Size = UDim2.fromOffset(TICKER_PILL_WIDTH, TICKER_PILL_HEIGHT)
		tickerPill.AutoButtonColor = false
		tickerPill.BorderSizePixel = 0
		tickerPill.BackgroundColor3 = Theme.Colors.Panel
		tickerPill.FontFace = Theme.Fonts.MonoBold
		tickerPill.TextSize = Theme.TextSize.Caption
		tickerPill.TextColor3 = Theme.Colors.Text
		tickerPill.TextTruncate = Enum.TextTruncate.AtEnd
		tickerPill.Text = item.ticker
		tickerPill.Parent = row
		UIKit.addCorner(tickerPill)

		local pillStroke = UIKit.addStroke(tickerPill)

		tickerPill.MouseEnter:Connect(function()
			pillStroke.Color = Theme.Colors.Accent
		end)

		tickerPill.MouseLeave:Connect(function()
			pillStroke.Color = Theme.Colors.Border
		end)

		tickerPill.MouseButton1Click:Connect(function()
			Navigation.openTicker(item.ticker)
		end)
	end

	row.MouseEnter:Connect(function()
		row.BackgroundTransparency = 0
	end)

	row.MouseLeave:Connect(function()
		row.BackgroundTransparency = 1
	end)

	row.MouseButton1Click:Connect(function()
		Navigation.openProfile(item.userId)
	end)
end

local function describeEmptyFeed(result)
	if selectedView ~= "Following" then
		return "No activity yet. Trades and milestones from every player show up here."
	elseif result.following == 0 then
		return "You're not following anyone yet. Open a player's profile from this feed or the Leaderboards tab and press Follow."
	end

	return "No recent activity from the players you follow."
end

local function renderFeed(result)
	local items = result.items
	local ids = { selectedView }

	for _, item in ipairs(items) do
		table.insert(ids, item.id)
	end

	local signature = table.concat(ids, ",")

	for label, item in pairs(ageLabels) do
		label.Text = describeKind(item)
	end

	if signature == renderedSignature then
		return
	end

	renderedSignature = signature

	local scrollY = FeedList.CanvasPosition.Y

	clearRows()
	FeedMessage.Visible = #items == 0
	FeedMessage.Text = describeEmptyFeed(result)

	for index, item in ipairs(items) do
		createRow(index, item)
	end

	-- New items arrived while the reader was scrolled down: the canvas regrows
	-- on the next frame, then the scroll position can go back
	if scrollY > 0 then
		task.defer(function()
			task.wait()
			FeedList.CanvasPosition = Vector2.new(0, scrollY)
		end)
	end
end

-- Loading
local function invoke(view)
	local success, result = pcall(GetFeedEvent.InvokeServer, GetFeedEvent, view)

	if not success then
		warn("[SocialController] GetFeedEvent failed: " .. tostring(result))

		return nil
	end

	return result
end

-- The server answers nil when throttled, so one retry after its cooldown.
-- A newer request makes an older one drop its answer.
local function loadFeed()
	requestId += 1

	local thisRequest = requestId
	local view = selectedView
	local result = invoke(view)

	if result == nil then
		task.wait(RETRY_DELAY)

		if thisRequest ~= requestId then
			return
		end

		result = invoke(view)
	end

	if thisRequest ~= requestId then
		return
	end

	if result then
		renderFeed(result)
	elseif not renderedSignature then
		FeedMessage.Visible = true
		FeedMessage.Text = "Couldn't load the feed. Trying again in a moment."
	end
end

local function updateViewPills()
	for view, pill in pairs(viewPills) do
		local isActive = view == selectedView

		pill.button.BackgroundTransparency = isActive and 0 or 1
		pill.button.TextColor3 = isActive and Theme.Colors.Text or Theme.Colors.TextMuted
		pill.stroke.Enabled = isActive
	end
end

-- Layout
-- A centered column, so rows stay readable on a wide screen
local function layoutScreen()
	local screenSize = SocialScreen.AbsoluteSize
	local width = math.min(screenSize.X - PADDING * 2, MAX_FEED_WIDTH)

	FeedPanel.AnchorPoint = Vector2.new(0.5, 0)
	FeedPanel.Position = UDim2.new(0.5, 0, 0, PADDING)
	FeedPanel.Size = UDim2.new(0, width, 1, -PADDING * 2)
end

-- Connections
for view, pill in pairs(viewPills) do
	pill.button.MouseButton1Click:Connect(function()
		if view == selectedView then
			return
		end

		selectedView = view
		renderedSignature = nil
		clearRows()
		FeedList.CanvasPosition = Vector2.zero
		FeedMessage.Visible = true
		FeedMessage.Text = "Loading…"
		updateViewPills()
		loadFeed()
	end)
end

SocialScreen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutScreen)

SocialScreen:GetPropertyChangedSignal("Visible"):Connect(function()
	if SocialScreen.Visible then
		loadFeed()
	end
end)

task.spawn(function()
	while true do
		task.wait(POLL_INTERVAL)

		if SocialScreen.Visible then
			task.spawn(loadFeed)
		end
	end
end)

layoutScreen()
updateViewPills()
