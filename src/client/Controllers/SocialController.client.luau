-- SocialController.client.luau
--
-- Builds and runs the Social tab (GDD §2): the feed of executed trades,
-- theses and milestones from every player, or only from the players you
-- follow, and Trending - the tickers players trade and watch most. A row opens its player's profile; the ticker of a trade or thesis
-- opens on the Trade tab, where theses show in full. Reaction chips on each
-- row (one reaction per player per item; read-only on your own posts).
--
-- Also sends the server the player's Roblox block list, which only the
-- client can read, so blocked players' posts are hidden everywhere.
-- Built in code inside the empty screen ShellController adds;
-- TerminalController switches to it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local FeedText = require(ReplicatedStorage.UI.FeedText)
local Social = require(ReplicatedStorage.Config.Social)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetFeedEvent = EventsFolder:WaitForChild("GetFeedEvent")
local GetTrendingEvent = EventsFolder:WaitForChild("GetTrendingEvent")
local ReactToFeedItemEvent = EventsFolder:WaitForChild("ReactToFeedItemEvent")
local SetRobloxBlocksEvent = EventsFolder:WaitForChild("SetRobloxBlocksEvent")

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
local CHIP_WIDTH = 44
local CHIP_HEIGHT = 20
local CHIP_GAP = 4
local CHIPS_WIDTH = #Social.REACTIONS * (CHIP_WIDTH + CHIP_GAP)

local POLL_INTERVAL = 5
local CORE_RETRIES = 20 -- a second apart, while Roblox's core scripts register
local RETRY_DELAY = 1.1 -- past the server's per-request cooldown when throttled

-- The feed's views, then Trending, which lists tickers instead of posts
local VIEWS = table.clone(Social.FEED_VIEWS)
table.insert(VIEWS, "Trending")

local TRENDING_ROW_HEIGHT = 30
local TRENDING_NOTE = "From every player's trades and watchlists. Popularity isn't research: "
	.. "check the fundamentals and news before you trade."

local KIND_LABELS = {
	Trade = "Executed trade",
	Thesis = "Thesis",
	Milestone = "Milestone",
}

-- State
local selectedView = VIEWS[1]
local requestId = 0
local renderedSignature = nil -- the view and item ids on screen; an unchanged poll keeps scroll and hover
local ageLabels = {} -- [label] = item, so ages tick without rebuilding rows
local rowsById = {} -- [item id] = { item, chips = { [reactionId] = { button, stroke } } }
local isReacting = false

local makeFrame = UIKit.makeFrame
local makeLabel = UIKit.makeLabel

-- Formatting
local MUTED_HEX = Theme.Colors.TextMuted:ToHex()

local escape = FeedText.escape
local formatAge = FeedText.formatAge
local describeItem = FeedText.describe

local function describeKind(item)
	return string.format("%s · %s", KIND_LABELS[item.kind] or item.kind, formatAge(os.time() - item.time))
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
FeedSubtitle.Text = "Trades, theses and milestones from TradingBlox players. Simulated trading, not financial advice."

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

for index, view in ipairs(VIEWS) do
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
	table.clear(rowsById)
end

-- "🔥 3", or just "🔥" with no one on it yet; your own reaction is outlined
local function updateChips(row)
	local item = row.item
	local counts = item.reactions or {}

	for _, reaction in ipairs(Social.REACTIONS) do
		local chip = row.chips[reaction.id]
		local count = counts[reaction.id]
		local isYours = item.yourReaction == reaction.id

		chip.button.Text = count and string.format("%s %d", reaction.emoji, count) or reaction.emoji
		chip.button.TextColor3 = isYours and Theme.Colors.Text or Theme.Colors.TextMuted
		chip.stroke.Color = isYours and Theme.Colors.Accent or Theme.Colors.Border
	end
end

-- Clicking your current reaction takes it off; another one switches to it
local function react(row, reactionId)
	if isReacting then
		return
	end

	local item = row.item

	isReacting = true

	local success, result = pcall(
		ReactToFeedItemEvent.InvokeServer,
		ReactToFeedItemEvent,
		item.id,
		if item.yourReaction == reactionId then nil else reactionId
	)

	isReacting = false

	if not success or not result or not result.success then
		warn("[SocialController] Reaction failed: " .. tostring(result and result.message or result))

		return
	end

	item.reactions = result.reactions
	item.yourReaction = result.yourReaction
	updateChips(row)
end

local function createChips(row, parent, item)
	local isYours = item.userId == Player.UserId

	local group = makeFrame("Reactions", parent)
	group.AnchorPoint = Vector2.new(1, 0)
	group.Size = UDim2.fromOffset(CHIPS_WIDTH, CHIP_HEIGHT)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, CHIP_GAP)
	layout.Parent = group

	for index, reaction in ipairs(Social.REACTIONS) do
		local chip = Instance.new("TextButton")
		chip.Name = reaction.id
		chip.LayoutOrder = index
		chip.Size = UDim2.fromOffset(CHIP_WIDTH, CHIP_HEIGHT)
		chip.AutoButtonColor = false
		chip.BorderSizePixel = 0
		chip.BackgroundColor3 = Theme.Colors.Panel
		chip.FontFace = Theme.Fonts.UI
		chip.TextSize = Theme.TextSize.Caption
		chip.Parent = group
		UIKit.addCorner(chip)

		row.chips[reaction.id] = { button = chip, stroke = UIKit.addStroke(chip) }

		-- Your own posts show their counts but take no reactions
		if not isYours then
			chip.MouseButton1Click:Connect(function()
				react(row, reaction.id)
			end)
		end
	end

	return group
end

-- A whole row opens the player's profile; the ticker pill of a trade or
-- thesis opens the ticker instead (the pill sits on top, so it takes the click)
local function createRow(index, item)
	local isTrade = item.kind == "Trade"
	local hasTicker = item.ticker ~= nil
	local rightWidth = hasTicker and TICKER_PILL_WIDTH + 8 or 0

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
	detail.Size = UDim2.new(1, -(TEXT_X + rightWidth + CHIPS_WIDTH + 8), 0, 18)
	detail.RichText = true
	detail.Text = describeItem(item)

	local rowState = { item = item, chips = {} }
	local chips = createChips(rowState, row, item)

	chips.Position = UDim2.new(1, -rightWidth, 0, 28)
	rowsById[item.id] = rowState
	updateChips(rowState)

	if hasTicker then
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
		return "No activity yet. Trades, theses and milestones from every player show up here."
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

	-- Same items: counts change in place, so scroll and hover stay put
	if signature == renderedSignature then
		for _, item in ipairs(items) do
			local row = rowsById[item.id]

			if row then
				row.item.reactions = item.reactions
				row.item.yourReaction = item.yourReaction
				updateChips(row)
			end
		end

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
	local remote = if view == "Trending" then GetTrendingEvent else GetFeedEvent
	local success, result = pcall(remote.InvokeServer, remote, view)

	if not success then
		warn("[SocialController] " .. remote.Name .. " failed: " .. tostring(result))

		return nil
	end

	return result
end

-- Trending
local function addTrendingLabel(order, text, font, color)
	local label = makeLabel("Label_" .. order, FeedList, font, Theme.TextSize.Caption, color)
	label.LayoutOrder = order
	label.Size = UDim2.new(1, -(PADDING - ROW_INSET), 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.None
	label.Text = text

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, ROW_INSET)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = label
end

-- A ranked ticker; clicking it opens the ticker on the Trade tab
local function addTrendingRow(order, rank, ticker, countText)
	local row = Instance.new("TextButton")
	row.Name = "Trending_" .. order
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -(PADDING - ROW_INSET), 0, TRENDING_ROW_HEIGHT)
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

	local rankLabel = makeLabel("Rank", row, Theme.Fonts.MonoBold, Theme.TextSize.Body, Theme.Colors.TextMuted)
	rankLabel.Size = UDim2.new(0, 28, 1, 0)
	rankLabel.Text = tostring(rank)

	local tickerLabel = makeLabel("Ticker", row, Theme.Fonts.UISemibold, Theme.TextSize.Body, Theme.Colors.Text)
	tickerLabel.Position = UDim2.fromOffset(28, 0)
	tickerLabel.Size = UDim2.new(1, -(28 + 140), 1, 0)
	tickerLabel.Text = ticker

	local count = makeLabel("Count", row, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.TextMuted)
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.fromScale(1, 0)
	count.Size = UDim2.new(0, 140, 1, 0)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Text = countText

	row.MouseEnter:Connect(function()
		row.BackgroundTransparency = 0
	end)

	row.MouseLeave:Connect(function()
		row.BackgroundTransparency = 1
	end)

	row.MouseButton1Click:Connect(function()
		Navigation.openTicker(ticker)
	end)
end

local function plural(count, singular, pluralForm)
	return NumberModule.formatShares(count) .. " " .. (count == 1 and singular or pluralForm)
end

local function renderTrending(trending)
	local parts = { "Trending" }

	for _, entry in ipairs(trending.traded) do
		table.insert(parts, entry.ticker .. "=" .. entry.trades)
	end

	table.insert(parts, "|")

	for _, entry in ipairs(trending.watched) do
		table.insert(parts, entry.ticker .. "=" .. entry.watchers)
	end

	local signature = table.concat(parts, ",")

	if signature == renderedSignature then
		return
	end

	renderedSignature = signature
	clearRows()
	FeedMessage.Visible = false

	local order = 0
	local function nextOrder()
		order += 1

		return order
	end

	addTrendingLabel(nextOrder(), "Most traded · today and yesterday (UTC)", Theme.Fonts.UISemibold, Theme.Colors.Text)

	if #trending.traded == 0 then
		addTrendingLabel(nextOrder(), "No player trades yet today.", Theme.Fonts.UI, Theme.Colors.TextMuted)
	end

	for rank, entry in ipairs(trending.traded) do
		addTrendingRow(nextOrder(), rank, entry.ticker, plural(entry.trades, "trade", "trades"))
	end

	addTrendingLabel(nextOrder(), "Most watched", Theme.Fonts.UISemibold, Theme.Colors.Text)

	if #trending.watched == 0 then
		addTrendingLabel(nextOrder(), "No tickers on watchlists yet.", Theme.Fonts.UI, Theme.Colors.TextMuted)
	end

	for rank, entry in ipairs(trending.watched) do
		addTrendingRow(nextOrder(), rank, entry.ticker, plural(entry.watchers, "watcher", "watchers"))
	end

	addTrendingLabel(nextOrder(), TRENDING_NOTE, Theme.Fonts.UI, Theme.Colors.TextMuted)
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

	if result and view == "Trending" then
		renderTrending(result)
	elseif result then
		renderFeed(result)
	elseif not renderedSignature then
		FeedMessage.Visible = true
		FeedMessage.Text = view == "Trending" and "Couldn't load trending tickers. Trying again in a moment."
			or "Couldn't load the feed. Trying again in a moment."
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

-- Roblox blocks: read with GetCore, which fails until Roblox's core scripts
-- have registered it, so each lookup is retried
local function getCore(name)
	for _ = 1, CORE_RETRIES do
		local success, value = pcall(StarterGui.GetCore, StarterGui, name)

		if success and value ~= nil then
			return value
		end

		task.wait(1)
	end

	warn("[SocialController] GetCore " .. name .. " never became available")

	return nil
end

local function sendRobloxBlocks()
	local userIds = getCore("GetBlockedUserIds")

	if type(userIds) == "table" then
		pcall(SetRobloxBlocksEvent.InvokeServer, SetRobloxBlocksEvent, userIds)
	end
end

task.spawn(function()
	sendRobloxBlocks()

	for _, eventName in ipairs({ "PlayerBlockedEvent", "PlayerUnblockedEvent" }) do
		local event = getCore(eventName)

		if event then
			event.Event:Connect(function()
				sendRobloxBlocks()

				-- Redrawn without (or with) the player just blocked (or unblocked)
				if SocialScreen.Visible then
					renderedSignature = nil
					loadFeed()
				end
			end)
		end
	end
end)

layoutScreen()
updateViewPills()
