-- LeaderboardController.client.luau
--
-- Builds and runs the Leaderboards screen (GDD §9): the top players on each
-- board beside the public profile of whoever is selected - the player
-- themselves to start with. The profile has a Follow button for other
-- players, the trade-sharing toggle on the player's own, recent trades when
-- they're shared, and recent theses (GDD §2). Built in code inside the empty screen
-- ShellController adds; TerminalController switches to it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)
local LineChart = require(ReplicatedStorage.UI.LineChart)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local Leaderboards = require(ReplicatedStorage.Config.Leaderboards)
local Progression = require(ReplicatedStorage.Config.Progression)
local Social = require(ReplicatedStorage.Config.Social)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetLeaderboardEvent = EventsFolder:WaitForChild("GetLeaderboardEvent")
local GetPublicProfileEvent = EventsFolder:WaitForChild("GetPublicProfileEvent")
local FollowPlayerEvent = EventsFolder:WaitForChild("FollowPlayerEvent")
local SetShareTradesEvent = EventsFolder:WaitForChild("SetShareTradesEvent")

-- References
local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local MainBackground = TerminalGui:WaitForChild("MainBackground")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")
local LeaderboardsScreen = ScreenContainer:WaitForChild("LeaderboardsScreen")

-- Layout Constants
local PADDING = 16
local GAP = 12
local PROFILE_PANEL_SCALE = 0.36
local PROFILE_PANEL_MIN_WIDTH = 320
local PROFILE_PANEL_MAX_WIDTH = 440
local STACK_BELOW_WIDTH = 760 -- narrower than this, the profile moves under the board
local STACKED_BOARD_SHARE = 0.5
local TITLE_HEIGHT = 24
local PILL_HEIGHT = 26
local PILL_TEXT_PADDING = 12
local COLUMN_HEADER_HEIGHT = 18
local FOOTER_HEIGHT = 34
local ROW_HEIGHT = 44
local ROW_INSET = 8 -- the hover highlight reaches this far past the row's content
local RANK_WIDTH = 36
local ROW_AVATAR_SIZE = 28
local SCORE_WIDTH = 140
local PROFILE_AVATAR_SIZE = 56
local PROFILE_CHART_HEIGHT = 140
local STAT_CELL_HEIGHT = 40
local ACTION_HEIGHT = 28
local ACTION_BUTTON_WIDTH = 124
local TRADE_ROW_HEIGHT = 20
local TRADE_ROW_PADDING = 6 -- inside the hover highlight
local TRADE_AGE_WIDTH = 72

local REFRESH_INTERVAL = 60
local RETRY_DELAY = 1.1 -- the server allows one request a second per board and per profile
local BOARD_CACHE_SECONDS = 30
local HISTORY_DAYS = 30

local PROFILE_STATS =
	{ "winRate", "averages", "maxDrawdown", "realizedPL", "trades", "joined", "followers", "following" }
local PROFILE_STAT_CAPTIONS = {
	winRate = "Win rate",
	averages = "Avg gain / loss",
	maxDrawdown = "Max drawdown (30d)",
	realizedPL = "Realized P/L",
	trades = "Trades",
	joined = "Joined",
	followers = "Followers",
	following = "Following",
}

-- State
local selectedBoardId = Leaderboards.BOARDS[1].id
local selectedUserId = Player.UserId
local boardCache = {} -- [boardId] = { fetchedAt = os.clock(), page = {...} }
local boardRequestId = 0
local profileRequestId = 0
local currentProfile = nil
local isActionPending = false
local isActionHovered = false

local makeFrame = UIKit.makeFrame
local makeLabel = UIKit.makeLabel

-- Formatting
local UP_HEX = Theme.Colors.Up:ToHex()
local DOWN_HEX = Theme.Colors.Down:ToHex()

local function formatSignedMoney(amount)
	return (amount >= 0 and "+" or "-") .. NumberModule.format(math.abs(amount))
end

local function formatSignedPercent(fraction)
	return string.format("%s%.2f%%", fraction >= 0 and "+" or "-", math.abs(fraction) * 100)
end

local function getChangeColor(amount)
	if amount > 0 then
		return Theme.Colors.Up
	elseif amount < 0 then
		return Theme.Colors.Down
	end

	return Theme.Colors.Text
end

local function sideText(side)
	return string.format('<font color="#%s">%s</font>', side == "Buy" and UP_HEX or DOWN_HEX, side)
end

-- "Bullish AAPL · target $210.00 · 1 month", and "· ended" once it has
local function describeThesis(thesis)
	local horizon = Social.getHorizon(thesis.horizon)

	return string.format(
		'<font color="#%s"><b>%s</b></font> %s%s · %s%s',
		thesis.direction == "Bullish" and UP_HEX or DOWN_HEX,
		thesis.direction,
		thesis.ticker,
		thesis.targetPrice and (" · target " .. NumberModule.format(thesis.targetPrice)) or "",
		horizon and horizon.label or thesis.horizon,
		thesis.endsAt <= os.time() and " · ended" or ""
	)
end

-- "Buy 5 AAPL @ $182.10", with the realized P/L after a sale
local function describeTrade(trade)
	local realized = ""

	if trade.realizedPL then
		realized = string.format(
			' <font color="#%s">%s</font>',
			trade.realizedPL >= 0 and UP_HEX or DOWN_HEX,
			formatSignedMoney(trade.realizedPL)
		)
	end

	return string.format(
		"%s %s %s%s @ %s%s",
		trade.settlement or sideText(trade.side),
		NumberModule.formatShares(trade.quantity),
		trade.ticker,
		trade.contract and " opt" or "",
		NumberModule.format(trade.price),
		realized
	)
end

local function formatScore(board, score)
	if board.metric == "netWorth" then
		return NumberModule.format(score)
	end

	return formatSignedPercent(score)
end

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

-- Board Panel
local BoardPanel = UIKit.makePanel("BoardPanel", LeaderboardsScreen)

local BoardTitle = makeLabel("Title", BoardPanel, Theme.Fonts.UIBold, Theme.TextSize.Title, Theme.Colors.Text)
BoardTitle.Position = UDim2.fromOffset(PADDING, PADDING)
BoardTitle.Size = UDim2.new(0.5, -PADDING, 0, TITLE_HEIGHT)
BoardTitle.Text = "Leaderboards"

local PeriodLabel = makeLabel("Period", BoardPanel, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
PeriodLabel.AnchorPoint = Vector2.new(1, 0)
PeriodLabel.Position = UDim2.new(1, -PADDING, 0, PADDING)
PeriodLabel.Size = UDim2.new(0.5, -PADDING, 0, TITLE_HEIGHT)
PeriodLabel.TextXAlignment = Enum.TextXAlignment.Right

local PILLS_Y = PADDING + TITLE_HEIGHT + 8

local BoardPills = makeFrame("BoardPills", BoardPanel)
BoardPills.Position = UDim2.fromOffset(PADDING, PILLS_Y)
BoardPills.Size = UDim2.new(1, -PADDING * 2, 0, PILL_HEIGHT)

local BoardPillsLayout = Instance.new("UIListLayout")
BoardPillsLayout.FillDirection = Enum.FillDirection.Horizontal
BoardPillsLayout.SortOrder = Enum.SortOrder.LayoutOrder
BoardPillsLayout.Padding = UDim.new(0, 4)
BoardPillsLayout.Parent = BoardPills

local boardPills = {} -- [boardId] = { button, stroke }

for index, board in ipairs(Leaderboards.BOARDS) do
	local button = Instance.new("TextButton")
	button.Name = "Board_" .. board.id
	button.LayoutOrder = index
	button.AutomaticSize = Enum.AutomaticSize.X
	button.Size = UDim2.fromScale(0, 1)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Theme.Colors.Raised
	button.FontFace = Theme.Fonts.UISemibold
	button.TextSize = Theme.TextSize.Caption
	button.Text = board.name
	button.Parent = BoardPills
	UIKit.addCorner(button)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, PILL_TEXT_PADDING)
	padding.PaddingRight = UDim.new(0, PILL_TEXT_PADDING)
	padding.Parent = button

	boardPills[board.id] = { button = button, stroke = UIKit.addStroke(button) }
end

local COLUMNS_Y = PILLS_Y + PILL_HEIGHT + GAP

local ColumnHeader = makeFrame("ColumnHeader", BoardPanel)
ColumnHeader.Position = UDim2.fromOffset(PADDING, COLUMNS_Y)
ColumnHeader.Size = UDim2.new(1, -PADDING * 2, 0, COLUMN_HEADER_HEIGHT)

local RankHeader = makeLabel("Rank", ColumnHeader, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
RankHeader.Size = UDim2.new(0, RANK_WIDTH, 1, 0)
RankHeader.Text = "#"

local PlayerHeader = makeLabel("Player", ColumnHeader, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
PlayerHeader.Position = UDim2.fromOffset(RANK_WIDTH, 0)
PlayerHeader.Size = UDim2.new(1, -(RANK_WIDTH + SCORE_WIDTH), 1, 0)
PlayerHeader.Text = "Player"

local ScoreHeader = makeLabel("Score", ColumnHeader, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
ScoreHeader.AnchorPoint = Vector2.new(1, 0)
ScoreHeader.Position = UDim2.fromScale(1, 0)
ScoreHeader.Size = UDim2.new(0, SCORE_WIDTH, 1, 0)
ScoreHeader.TextXAlignment = Enum.TextXAlignment.Right

local LIST_TOP = COLUMNS_Y + COLUMN_HEADER_HEIGHT + 4

-- Starts ROW_INSET left of the content so a row's highlight can extend past
-- it, and runs to the panel's right edge so the scrollbar sits in the padding
local BoardList = Instance.new("ScrollingFrame")
BoardList.Name = "BoardList"
BoardList.Position = UDim2.fromOffset(PADDING - ROW_INSET, LIST_TOP)
BoardList.Size = UDim2.new(1, -(PADDING - ROW_INSET), 1, -(LIST_TOP + FOOTER_HEIGHT + PADDING))
BoardList.BackgroundTransparency = 1
BoardList.BorderSizePixel = 0
BoardList.ScrollBarThickness = 4
BoardList.ScrollBarImageColor3 = Theme.Colors.TextDisabled
BoardList.ScrollingDirection = Enum.ScrollingDirection.Y
BoardList.CanvasSize = UDim2.new()
BoardList.AutomaticCanvasSize = Enum.AutomaticSize.Y
BoardList.Parent = BoardPanel

local BoardListLayout = Instance.new("UIListLayout")
BoardListLayout.SortOrder = Enum.SortOrder.LayoutOrder
BoardListLayout.Padding = UDim.new(0, 2)
BoardListLayout.Parent = BoardList

local BoardMessage = makeLabel("Message", BoardPanel, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
BoardMessage.Position = UDim2.fromOffset(PADDING, LIST_TOP + GAP)
BoardMessage.Size = UDim2.new(1, -PADDING * 2, 0, 40)
BoardMessage.TextWrapped = true
BoardMessage.TextXAlignment = Enum.TextXAlignment.Center
BoardMessage.Text = "Loading…"

-- Where the player stands on this board, or what they need to qualify
local BoardFooter = makeLabel("Footer", BoardPanel, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
BoardFooter.AnchorPoint = Vector2.new(0, 1)
BoardFooter.Position = UDim2.new(0, PADDING, 1, -PADDING)
BoardFooter.Size = UDim2.new(1, -PADDING * 2, 0, FOOTER_HEIGHT)
BoardFooter.TextWrapped = true
BoardFooter.TextYAlignment = Enum.TextYAlignment.Bottom

-- Profile Panel
local ProfilePanel = UIKit.makePanel("ProfilePanel", LeaderboardsScreen)

-- Scrolls when a short (stacked) panel can't fit the whole profile
local ProfileContent = Instance.new("ScrollingFrame")
ProfileContent.Name = "Content"
ProfileContent.Size = UDim2.fromScale(1, 1)
ProfileContent.BackgroundTransparency = 1
ProfileContent.BorderSizePixel = 0
ProfileContent.ScrollBarThickness = 4
ProfileContent.ScrollBarImageColor3 = Theme.Colors.TextDisabled
ProfileContent.ScrollingDirection = Enum.ScrollingDirection.Y
ProfileContent.CanvasSize = UDim2.new()
ProfileContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
ProfileContent.Parent = ProfilePanel

local ProfileAvatar = UIKit.makeAvatar("Avatar", ProfileContent, Player.UserId, PROFILE_AVATAR_SIZE)
ProfileAvatar.Position = UDim2.fromOffset(PADDING, PADDING)

local PROFILE_TEXT_X = PADDING + PROFILE_AVATAR_SIZE + 12

local ProfileName =
	makeLabel("DisplayName", ProfileContent, Theme.Fonts.UIBold, Theme.TextSize.Display, Theme.Colors.Text)
ProfileName.Position = UDim2.fromOffset(PROFILE_TEXT_X, PADDING + 2)
ProfileName.Size = UDim2.new(1, -(PROFILE_TEXT_X + PADDING), 0, 28)

local ProfileSubtitle =
	makeLabel("Subtitle", ProfileContent, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
ProfileSubtitle.Position = UDim2.fromOffset(PROFILE_TEXT_X, PADDING + 32)
ProfileSubtitle.Size = UDim2.new(1, -(PROFILE_TEXT_X + PADDING), 0, 18)

local ACTION_Y = PADDING + PROFILE_AVATAR_SIZE + GAP

-- Follow on other players' profiles, the trade-sharing toggle on your own
local ProfileAction = Instance.new("TextButton")
ProfileAction.Name = "Action"
ProfileAction.Position = UDim2.fromOffset(PADDING, ACTION_Y)
ProfileAction.Size = UDim2.fromOffset(ACTION_BUTTON_WIDTH, ACTION_HEIGHT)
ProfileAction.AutoButtonColor = false
ProfileAction.BorderSizePixel = 0
ProfileAction.TextSize = Theme.TextSize.Body
ProfileAction.Parent = ProfileContent
UIKit.addCorner(ProfileAction)

local ProfileActionStroke = UIKit.addStroke(ProfileAction)

local ACTION_NOTE_X = PADDING + ACTION_BUTTON_WIDTH + 10

-- What the toggle means, or why the last click failed
local ProfileActionNote =
	makeLabel("ActionNote", ProfileContent, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
ProfileActionNote.Position = UDim2.fromOffset(ACTION_NOTE_X, ACTION_Y)
ProfileActionNote.Size = UDim2.new(1, -(ACTION_NOTE_X + PADDING), 0, ACTION_HEIGHT)
ProfileActionNote.TextWrapped = true

local VALUE_Y = ACTION_Y + ACTION_HEIGHT + GAP

local ProfileValue =
	makeLabel("NetWorth", ProfileContent, Theme.Fonts.MonoBold, Theme.TextSize.Display, Theme.Colors.Text)
ProfileValue.Position = UDim2.fromOffset(PADDING, VALUE_Y)
ProfileValue.Size = UDim2.new(1, -PADDING * 2, 0, 30)

local ProfileReturn = makeLabel("Return", ProfileContent, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.TextMuted)
ProfileReturn.Position = UDim2.fromOffset(PADDING, VALUE_Y + 30)
ProfileReturn.Size = UDim2.new(1, -PADDING * 2, 0, 18)
ProfileReturn.RichText = true

local CHART_Y = VALUE_Y + 30 + 18 + GAP

local ProfileChart = makeFrame("Chart", ProfileContent)
ProfileChart.Position = UDim2.fromOffset(PADDING, CHART_Y)
ProfileChart.Size = UDim2.new(1, -PADDING * 2, 0, PROFILE_CHART_HEIGHT)

local STATS_Y = CHART_Y + PROFILE_CHART_HEIGHT + GAP

local ProfileStatsGrid = makeFrame("Stats", ProfileContent)
ProfileStatsGrid.Position = UDim2.fromOffset(PADDING, STATS_Y)
ProfileStatsGrid.Size = UDim2.new(1, -PADDING * 2, 0, math.ceil(#PROFILE_STATS / 2) * STAT_CELL_HEIGHT)

local ProfileStatsLayout = Instance.new("UIGridLayout")
ProfileStatsLayout.CellSize = UDim2.new(0.5, -GAP / 2, 0, STAT_CELL_HEIGHT)
ProfileStatsLayout.CellPadding = UDim2.fromOffset(GAP, 0)
ProfileStatsLayout.SortOrder = Enum.SortOrder.LayoutOrder
ProfileStatsLayout.Parent = ProfileStatsGrid

local profileStatLabels = {} -- [stat] = value TextLabel

for index, stat in ipairs(PROFILE_STATS) do
	local cell = makeFrame("Stat_" .. stat, ProfileStatsGrid)
	cell.LayoutOrder = index

	local caption = makeLabel("Caption", cell, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	caption.Size = UDim2.new(1, 0, 0, 16)
	caption.Text = PROFILE_STAT_CAPTIONS[stat]

	local value = makeLabel("Value", cell, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.Text)
	value.Position = UDim2.fromOffset(0, 17)
	value.Size = UDim2.new(1, 0, 0, 18)
	value.RichText = true

	profileStatLabels[stat] = value
end

-- Recent trades, then when the profile was updated. A list layout, since
-- the number of trades varies.
local ProfileLower = makeFrame("Lower", ProfileContent)
ProfileLower.Position = UDim2.fromOffset(PADDING, STATS_Y + math.ceil(#PROFILE_STATS / 2) * STAT_CELL_HEIGHT + GAP)
ProfileLower.Size = UDim2.new(1, -PADDING * 2, 0, 0)
ProfileLower.AutomaticSize = Enum.AutomaticSize.Y

local ProfileLowerLayout = Instance.new("UIListLayout")
ProfileLowerLayout.SortOrder = Enum.SortOrder.LayoutOrder
ProfileLowerLayout.Padding = UDim.new(0, 6)
ProfileLowerLayout.Parent = ProfileLower

local TradesTitle =
	makeLabel("TradesTitle", ProfileLower, Theme.Fonts.UISemibold, Theme.TextSize.Body, Theme.Colors.Text)
TradesTitle.LayoutOrder = 1
TradesTitle.Size = UDim2.new(1, 0, 0, 18)
TradesTitle.Text = "Recent trades"

local TradesList = makeFrame("TradesList", ProfileLower)
TradesList.LayoutOrder = 2
TradesList.Size = UDim2.fromScale(1, 0)
TradesList.AutomaticSize = Enum.AutomaticSize.Y

local TradesListLayout = Instance.new("UIListLayout")
TradesListLayout.SortOrder = Enum.SortOrder.LayoutOrder
TradesListLayout.Parent = TradesList

local ThesesTitle =
	makeLabel("ThesesTitle", ProfileLower, Theme.Fonts.UISemibold, Theme.TextSize.Body, Theme.Colors.Text)
ThesesTitle.LayoutOrder = 3
ThesesTitle.Size = UDim2.new(1, 0, 0, 18)
ThesesTitle.Text = "Theses"

local ThesesList = makeFrame("ThesesList", ProfileLower)
ThesesList.LayoutOrder = 4
ThesesList.Size = UDim2.fromScale(1, 0)
ThesesList.AutomaticSize = Enum.AutomaticSize.Y

local ThesesListLayout = Instance.new("UIListLayout")
ThesesListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ThesesListLayout.Parent = ThesesList

local ProfileUpdated =
	makeLabel("Updated", ProfileLower, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
ProfileUpdated.LayoutOrder = 5
ProfileUpdated.Size = UDim2.new(1, 0, 0, 16)

local ProfileMessage = makeLabel("Message", ProfilePanel, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
ProfileMessage.Size = UDim2.fromScale(1, 1)
ProfileMessage.TextXAlignment = Enum.TextXAlignment.Center
ProfileMessage.TextWrapped = true
ProfileMessage.Text = "Loading…"

-- Profile
local function setProfileStat(stat, text, color)
	local label = profileStatLabels[stat]

	label.Text = text
	label.TextColor3 = color or Theme.Colors.Text
end

-- Follow (Accent fill) or Following (outlined; "Unfollow" on hover) for
-- other players, and the sharing toggle on your own profile
local function renderAction()
	local profile = currentProfile

	if profile.userId == Player.UserId then
		local isSharing = profile.sharesTrades ~= false

		ProfileAction.Text = isSharing and "Share trades: On" or "Share trades: Off"
		ProfileAction.FontFace = Theme.Fonts.UISemibold
		ProfileAction.BackgroundColor3 = Theme.Colors.Raised
		ProfileAction.TextColor3 = isSharing and Theme.Colors.Text or Theme.Colors.TextMuted
		ProfileActionStroke.Enabled = true
		ProfileActionStroke.Color = isSharing and Theme.Colors.Accent or Theme.Colors.Border
		ProfileActionNote.Text = isSharing and "Your trades show on your profile and in the feed."
			or "Other players see your stats, not your trades."

		return
	end

	if profile.isFollowing then
		ProfileAction.Text = isActionHovered and "Unfollow" or "Following"
		ProfileAction.FontFace = Theme.Fonts.UISemibold
		ProfileAction.BackgroundColor3 = Theme.Colors.Raised
		ProfileAction.TextColor3 = isActionHovered and Theme.Colors.Down or Theme.Colors.Text
		ProfileActionStroke.Enabled = true
		ProfileActionStroke.Color = Theme.Colors.Border
	else
		ProfileAction.Text = "Follow"
		ProfileAction.FontFace = Theme.Fonts.UIBold
		ProfileAction.BackgroundColor3 = Theme.Colors.Accent
		ProfileAction.TextColor3 = Theme.Colors.Background -- dark on Accent reads better than white
		ProfileActionStroke.Enabled = false
	end

	ProfileActionNote.Text = ""
end

local function addListMessage(list, text)
	local message = makeLabel("Message", list, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	message.Size = UDim2.new(1, 0, 0, TRADE_ROW_HEIGHT)
	message.Text = text
end

local function clearList(list)
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A trade row opens its ticker on the Trade tab
local function createTradeRow(index, trade)
	local row = Instance.new("TextButton")
	row.Name = "Trade_" .. index
	row.LayoutOrder = index
	row.Size = UDim2.new(1, 0, 0, TRADE_ROW_HEIGHT)
	row.AutoButtonColor = false
	row.BorderSizePixel = 0
	row.BackgroundColor3 = Theme.Colors.Raised
	row.BackgroundTransparency = 1
	row.Text = ""
	row.Parent = TradesList
	UIKit.addCorner(row)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, TRADE_ROW_PADDING)
	padding.PaddingRight = UDim.new(0, TRADE_ROW_PADDING)
	padding.Parent = row

	local detail = makeLabel("Detail", row, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.Text)
	detail.Size = UDim2.new(1, -TRADE_AGE_WIDTH, 1, 0)
	detail.RichText = true
	detail.Text = describeTrade(trade)

	local age = makeLabel("Age", row, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	age.AnchorPoint = Vector2.new(1, 0)
	age.Position = UDim2.fromScale(1, 0)
	age.Size = UDim2.new(0, TRADE_AGE_WIDTH, 1, 0)
	age.TextXAlignment = Enum.TextXAlignment.Right
	age.Text = formatAge(os.time() - trade.time)

	row.MouseEnter:Connect(function()
		row.BackgroundTransparency = 0
	end)

	row.MouseLeave:Connect(function()
		row.BackgroundTransparency = 1
	end)

	row.MouseButton1Click:Connect(function()
		Navigation.openTicker(trade.ticker)
	end)
end

local function renderRecentTrades(profile, isYou)
	clearList(TradesList)

	-- nil (not false) on snapshots saved before trades could be shared
	if profile.sharesTrades == false then
		addListMessage(
			TradesList,
			isYou and "Hidden from other players." or ("@" .. profile.username .. " keeps trades private.")
		)
	elseif not profile.recentTrades or #profile.recentTrades == 0 then
		addListMessage(TradesList, "No trades to show yet.")
	else
		for index, trade in ipairs(profile.recentTrades) do
			createTradeRow(index, trade)
		end
	end
end

-- A thesis row opens its ticker on the Trade tab, where the thesis shows
-- in full. The server leaves text out for viewers who can't chat.
local function createThesisRow(index, thesis)
	local row = Instance.new("TextButton")
	row.Name = "Thesis_" .. index
	row.LayoutOrder = index
	row.Size = UDim2.fromScale(1, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.AutoButtonColor = false
	row.BorderSizePixel = 0
	row.BackgroundColor3 = Theme.Colors.Raised
	row.BackgroundTransparency = 1
	row.Text = ""
	row.Parent = ThesesList
	UIKit.addCorner(row)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, TRADE_ROW_PADDING)
	padding.PaddingRight = UDim.new(0, TRADE_ROW_PADDING)
	padding.PaddingBottom = UDim.new(0, 2)
	padding.Parent = row

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local line = makeFrame("Line", row)
	line.LayoutOrder = 1
	line.Size = UDim2.new(1, 0, 0, TRADE_ROW_HEIGHT)

	local call = makeLabel("Call", line, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.Text)
	call.Size = UDim2.new(1, -TRADE_AGE_WIDTH, 1, 0)
	call.RichText = true
	call.Text = describeThesis(thesis)

	local age = makeLabel("Age", line, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	age.AnchorPoint = Vector2.new(1, 0)
	age.Position = UDim2.fromScale(1, 0)
	age.Size = UDim2.new(0, TRADE_AGE_WIDTH, 1, 0)
	age.TextXAlignment = Enum.TextXAlignment.Right
	age.Text = formatAge(os.time() - thesis.createdAt)

	if thesis.text then
		-- Filtered by the server; plain text, never rich text
		local body = makeLabel("Text", row, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
		body.LayoutOrder = 2
		body.Size = UDim2.fromScale(1, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.TextWrapped = true
		body.TextTruncate = Enum.TextTruncate.None
		body.Text = thesis.text
	end

	row.MouseEnter:Connect(function()
		row.BackgroundTransparency = 0
	end)

	row.MouseLeave:Connect(function()
		row.BackgroundTransparency = 1
	end)

	row.MouseButton1Click:Connect(function()
		Navigation.openTicker(thesis.ticker)
	end)
end

local function renderTheses(profile, isYou)
	clearList(ThesesList)

	if not profile.theses or #profile.theses == 0 then
		addListMessage(ThesesList, isYou and "Publish one from a ticker on the Trade tab." or "No theses yet.")

		return
	end

	for index, thesis in ipairs(profile.theses) do
		createThesisRow(index, thesis)
	end
end

local function renderProfileChart()
	ProfileChart:ClearAllChildren()

	local history = currentProfile and currentProfile.history

	if history and #history > 0 then
		LineChart.draw(ProfileChart, LineChart.layout(history), LineChart.getColor(history), Theme.Colors.Panel, 2)
	end
end

local function renderProfile(profile)
	currentProfile = profile
	ProfileContent.Visible = profile ~= nil
	ProfileMessage.Visible = profile == nil

	if not profile then
		ProfileMessage.Text = "No public profile yet. It appears after a player's first trade."

		return
	end

	local level = Progression.LEVELS[profile.level]
	local isYou = profile.userId == Player.UserId

	UIKit.setAvatarUser(ProfileAvatar, profile.userId)
	ProfileName.Text = profile.displayName .. (isYou and " (you)" or "")
	ProfileSubtitle.Text =
		string.format("@%s  ·  Level %d · %s", profile.username, profile.level, level and level.name or "")
	ProfileValue.Text = NumberModule.format(profile.netWorth)
	ProfileReturn.Text = string.format(
		'<font color="#%s">%s</font> since starting  ·  %d-day net worth',
		profile.totalReturn >= 0 and UP_HEX or DOWN_HEX,
		formatSignedPercent(profile.totalReturn),
		HISTORY_DAYS
	)

	if profile.winRate then
		setProfileStat("winRate", string.format("%.0f%% of %d", profile.winRate * 100, profile.closedTrades))
	else
		setProfileStat("winRate", "—", Theme.Colors.TextMuted)
	end

	if profile.averageGain or profile.averageLoss then
		local gain = profile.averageGain
				and string.format('<font color="#%s">+%s</font>', UP_HEX, NumberModule.format(profile.averageGain))
			or "—"
		local loss = profile.averageLoss
				and string.format('<font color="#%s">-%s</font>', DOWN_HEX, NumberModule.format(profile.averageLoss))
			or "—"

		setProfileStat("averages", gain .. " / " .. loss)
	else
		setProfileStat("averages", "—", Theme.Colors.TextMuted)
	end

	-- Below half a hundredth it would print as a red "-0.00%"
	local drawdownPercent = profile.maxDrawdown and profile.maxDrawdown * 100

	if drawdownPercent and drawdownPercent >= 0.005 then
		setProfileStat("maxDrawdown", string.format("-%.2f%%", drawdownPercent), Theme.Colors.Down)
	else
		setProfileStat("maxDrawdown", drawdownPercent and "0.00%" or "—")
	end

	setProfileStat("realizedPL", formatSignedMoney(profile.realizedPL), getChangeColor(profile.realizedPL))
	setProfileStat("trades", NumberModule.formatShares(profile.trades))
	setProfileStat("joined", profile.joinedAt and os.date("%b %Y", profile.joinedAt) or "—")

	for _, stat in ipairs({ "followers", "following" }) do
		if profile[stat] then
			setProfileStat(stat, NumberModule.formatShares(profile[stat]))
		else
			setProfileStat(stat, "—", Theme.Colors.TextMuted)
		end
	end

	ProfileUpdated.Text = "Updated " .. formatAge(os.time() - profile.updatedAt)
	renderAction()
	renderRecentTrades(profile, isYou)
	renderTheses(profile, isYou)
	renderProfileChart()
end

local function invoke(remote, ...)
	local success, result = pcall(remote.InvokeServer, remote, ...)

	if not success then
		warn("[LeaderboardController] " .. remote.Name .. " failed: " .. tostring(result))

		return nil
	end

	return result
end

-- The server answers nil both when throttled and when there's nothing, so
-- one retry after its cooldown tells them apart. A newer request makes an
-- older one drop its answer.
local function loadProfile(userId)
	selectedUserId = userId
	profileRequestId += 1

	local requestId = profileRequestId

	if not currentProfile or currentProfile.userId ~= userId then
		ProfileContent.Visible = false
		ProfileMessage.Visible = true
		ProfileMessage.Text = "Loading…"
	end

	local profile = invoke(GetPublicProfileEvent, userId)

	if profile == nil then
		task.wait(RETRY_DELAY)

		if requestId ~= profileRequestId then
			return
		end

		profile = invoke(GetPublicProfileEvent, userId)
	end

	if requestId == profileRequestId then
		renderProfile(profile)
	end
end

-- Follows or unfollows the player shown, or flips your own sharing setting
local function onActionClicked()
	local profile = currentProfile

	if isActionPending or not profile then
		return
	end

	local userId = profile.userId
	local isYou = userId == Player.UserId
	local result

	isActionPending = true
	ProfileActionNote.Text = ""

	if isYou then
		result = invoke(SetShareTradesEvent, profile.sharesTrades == false)
	else
		result = invoke(FollowPlayerEvent, userId, not profile.isFollowing)
	end

	isActionPending = false

	-- A refresh may have replaced the profile table meanwhile, or the player
	-- opened someone else
	if not currentProfile or currentProfile.userId ~= userId then
		return
	end

	if not result or not result.success then
		ProfileActionNote.Text = result and result.message or "Couldn't reach the server. Try again."

		return
	end

	if isYou then
		-- Reloaded so the trades list matches the new setting
		currentProfile.sharesTrades = result.shareTrades
		renderAction()
		loadProfile(userId)

		return
	end

	currentProfile.isFollowing = result.isFollowing
	currentProfile.followers = result.followers
	renderProfile(currentProfile)
end

-- Board
local function describeStanding(board, page)
	for _, entry in ipairs(page.entries) do
		if entry.userId == Player.UserId then
			return string.format("You're #%d on this board.", entry.rank)
		end
	end

	local yourScore = page.you and page.you.score

	if yourScore then
		return string.format("You: %s · ranks refresh every few minutes.", formatScore(board, yourScore))
	elseif board.period == "AllTime" then
		return "Make your first trade to join this board."
	end

	return string.format(
		"To qualify: %d trades this %s and an account at least %d days old.",
		Leaderboards.MIN_TRADES[board.period],
		string.lower(board.period),
		Leaderboards.MIN_ACCOUNT_AGE_DAYS
	)
end

local function createBoardRow(board, entry)
	local isYou = entry.userId == Player.UserId
	local isSelected = entry.userId == selectedUserId

	local row = Instance.new("TextButton")
	row.Name = "Row_" .. entry.rank
	row.LayoutOrder = entry.rank
	row.Size = UDim2.new(1, -(PADDING - ROW_INSET), 0, ROW_HEIGHT)
	row.AutoButtonColor = false
	row.BorderSizePixel = 0
	row.BackgroundColor3 = Theme.Colors.Raised
	row.BackgroundTransparency = isSelected and 0 or 1
	row.Text = ""
	row:SetAttribute("UserId", entry.userId)
	row.Parent = BoardList
	UIKit.addCorner(row)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, ROW_INSET)
	padding.PaddingRight = UDim.new(0, ROW_INSET)
	padding.Parent = row

	local rank = makeLabel("Rank", row, Theme.Fonts.MonoBold, Theme.TextSize.Body, Theme.Colors.TextMuted)
	rank.Size = UDim2.new(0, RANK_WIDTH, 1, 0)
	rank.Text = tostring(entry.rank)

	if entry.rank <= 3 then
		rank.TextColor3 = Theme.Colors.Accent
	end

	local avatar = UIKit.makeAvatar("Avatar", row, entry.userId, ROW_AVATAR_SIZE)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, RANK_WIDTH, 0.5, 0)

	local textX = RANK_WIDTH + ROW_AVATAR_SIZE + 10
	local textWidth = -(textX + SCORE_WIDTH + 8)

	local name = makeLabel(
		"DisplayName",
		row,
		Theme.Fonts.UISemibold,
		Theme.TextSize.Body,
		isYou and Theme.Colors.Accent or Theme.Colors.Text
	)
	name.Position = UDim2.fromOffset(textX, 5)
	name.Size = UDim2.new(1, textWidth, 0, 18)
	name.Text = entry.displayName .. (isYou and " (you)" or "")

	local username = makeLabel("Username", row, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	username.Position = UDim2.fromOffset(textX, 23)
	username.Size = UDim2.new(1, textWidth, 0, 16)
	username.Text = entry.username and ("@" .. entry.username) or ""

	local score = makeLabel("Score", row, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.Text)
	score.AnchorPoint = Vector2.new(1, 0)
	score.Position = UDim2.fromScale(1, 0)
	score.Size = UDim2.new(0, SCORE_WIDTH, 1, 0)
	score.TextXAlignment = Enum.TextXAlignment.Right
	score.Text = formatScore(board, entry.score)

	if board.metric == "return" then
		score.TextColor3 = getChangeColor(entry.score)
	end

	row.MouseEnter:Connect(function()
		row.BackgroundTransparency = 0
	end)

	row.MouseLeave:Connect(function()
		row.BackgroundTransparency = entry.userId == selectedUserId and 0 or 1
	end)

	row.MouseButton1Click:Connect(function()
		for _, other in ipairs(BoardList:GetChildren()) do
			if other:IsA("GuiButton") then
				other.BackgroundTransparency = 1
			end
		end

		row.BackgroundTransparency = 0
		loadProfile(entry.userId)
	end)
end

local function renderBoard(page)
	local board = Leaderboards.getBoard(page.boardId)

	for _, child in ipairs(BoardList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	PeriodLabel.Text = page.periodLabel
	ScoreHeader.Text = board.metric == "netWorth" and "Net worth" or "Return"
	BoardMessage.Visible = #page.entries == 0
	BoardMessage.Text = "No one has qualified for this board yet."
	BoardFooter.Text = describeStanding(board, page)

	for _, entry in ipairs(page.entries) do
		createBoardRow(board, entry)
	end
end

local function updateBoardPills()
	for boardId, pill in pairs(boardPills) do
		local isActive = boardId == selectedBoardId

		pill.button.BackgroundTransparency = isActive and 0 or 1
		pill.button.TextColor3 = isActive and Theme.Colors.Text or Theme.Colors.TextMuted
		pill.stroke.Enabled = isActive
	end
end

-- Recent pages come from a short client cache, which also keeps quick pill
-- switching under the server's one-request-a-second limit
local function loadBoard(boardId, force)
	selectedBoardId = boardId
	boardRequestId += 1

	local requestId = boardRequestId
	local cached = boardCache[boardId]

	updateBoardPills()

	if cached then
		renderBoard(cached.page)

		if not force and os.clock() - cached.fetchedAt < BOARD_CACHE_SECONDS then
			return
		end
	else
		for _, child in ipairs(BoardList:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		BoardMessage.Visible = true
		BoardMessage.Text = "Loading…"
		BoardFooter.Text = ""
	end

	local page = invoke(GetLeaderboardEvent, boardId)

	if page == nil then
		task.wait(RETRY_DELAY)

		if requestId ~= boardRequestId then
			return
		end

		page = invoke(GetLeaderboardEvent, boardId)
	end

	if requestId ~= boardRequestId then
		return
	end

	if page then
		boardCache[boardId] = { fetchedAt = os.clock(), page = page }
		renderBoard(page)
	elseif not cached then
		BoardMessage.Text = "Couldn't load this board. Try again in a moment."
	end
end

local function refresh(force)
	task.spawn(loadBoard, selectedBoardId, force)
	task.spawn(loadProfile, selectedUserId)
end

-- Layout
-- Side by side, the profile takes about a third of the width; on a narrow
-- screen it stacks under the board
local function layoutScreen()
	local screenSize = LeaderboardsScreen.AbsoluteSize
	local bodyHeight = screenSize.Y - PADDING * 2

	BoardPanel.Position = UDim2.fromOffset(PADDING, PADDING)
	ProfilePanel.AnchorPoint = Vector2.new(1, 0)

	if screenSize.X < STACK_BELOW_WIDTH then
		local boardHeight = math.floor((bodyHeight - GAP) * STACKED_BOARD_SHARE)

		BoardPanel.Size = UDim2.new(1, -PADDING * 2, 0, boardHeight)
		ProfilePanel.Position = UDim2.new(1, -PADDING, 0, PADDING + boardHeight + GAP)
		ProfilePanel.Size = UDim2.new(1, -PADDING * 2, 0, bodyHeight - boardHeight - GAP)

		return
	end

	local profileWidth =
		math.clamp(math.floor(screenSize.X * PROFILE_PANEL_SCALE), PROFILE_PANEL_MIN_WIDTH, PROFILE_PANEL_MAX_WIDTH)

	BoardPanel.Size = UDim2.new(1, -(PADDING * 2 + GAP + profileWidth), 1, -PADDING * 2)
	ProfilePanel.Position = UDim2.new(1, -PADDING, 0, PADDING)
	ProfilePanel.Size = UDim2.new(0, profileWidth, 1, -PADDING * 2)
end

-- Connections
-- Another screen asked for a player's profile (e.g. a feed row);
-- TerminalController switches to this tab
Navigation.ProfileRequested:Connect(function(userId)
	for _, row in ipairs(BoardList:GetChildren()) do
		if row:IsA("GuiButton") then
			row.BackgroundTransparency = row:GetAttribute("UserId") == userId and 0 or 1
		end
	end

	loadProfile(userId)
end)

ProfileAction.MouseButton1Click:Connect(onActionClicked)

ProfileAction.MouseEnter:Connect(function()
	isActionHovered = true

	if currentProfile then
		renderAction()
	end
end)

ProfileAction.MouseLeave:Connect(function()
	isActionHovered = false

	if currentProfile then
		renderAction()
	end
end)

for boardId, pill in pairs(boardPills) do
	pill.button.MouseButton1Click:Connect(function()
		loadBoard(boardId)
	end)
end

LeaderboardsScreen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutScreen)
-- Segment lengths are in pixels, so a resize needs a redraw
ProfileChart:GetPropertyChangedSignal("AbsoluteSize"):Connect(renderProfileChart)

LeaderboardsScreen:GetPropertyChangedSignal("Visible"):Connect(function()
	if LeaderboardsScreen.Visible then
		refresh(false)
	end
end)

task.spawn(function()
	while true do
		task.wait(REFRESH_INTERVAL)

		if LeaderboardsScreen.Visible then
			refresh(true)
		end
	end
end)

layoutScreen()
updateBoardPills()
ProfileContent.Visible = false
