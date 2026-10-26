-- PortfolioController.client.luau
--
-- Builds and runs the Portfolio screen: profile header, net worth with a
-- 24h/7d/30d history chart, cash balance and every open position. Built in
-- code rather than Studio so it lives in git (StarterGui isn't synced), and
-- styled straight from Theme tokens. TerminalController still owns tab
-- switching; this only reacts to the screen being shown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local OrderRules = require(ReplicatedStorage.Modules.Multi.OrderRules)
local LineChart = require(ReplicatedStorage.UI.LineChart)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)
local Progression = require(ReplicatedStorage.Config.Progression)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetPortfolioEvent = EventsFolder:WaitForChild("GetPortfolioEvent")
local GetPositionsEvent = EventsFolder:WaitForChild("GetPositionsEvent")
local GetOrdersEvent = EventsFolder:WaitForChild("GetOrdersEvent")
local CancelOrderEvent = EventsFolder:WaitForChild("CancelOrderEvent")
local OrderUpdateEvent = EventsFolder:WaitForChild("OrderUpdateEvent")

-- References
local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local MainBackground = TerminalGui:WaitForChild("MainBackground")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")
local PortfolioScreen = ScreenContainer:WaitForChild("PortfolioScreen")

-- Layout Constants
local PADDING = 16
local GAP = 12
local HEADER_HEIGHT = 64
local AVATAR_SIZE = 56
local SIDE_PANEL_SCALE = 0.32
local SIDE_PANEL_MIN_WIDTH = 300
local SIDE_PANEL_MAX_WIDTH = 400
local STACK_BELOW_WIDTH = 760 -- narrower than this, the side panel moves under the chart
local STACKED_CHART_SHARE = 0.55
local VALUE_HEIGHT = 40
local CHANGE_HEIGHT = 20
local RANGE_PILL_WIDTH = 44
local RANGE_PILL_HEIGHT = 26
local RANGE_PILL_GAP = 4
local STATS_STRIP_HEIGHT = 56
local CASH_ROW_HEIGHT = 24
local SECTION_HEADER_HEIGHT = 24
local ROW_HEIGHT = 56
local ROW_INSET = 8 -- the hover highlight reaches this far past the row's content
local ROW_ICON_SIZE = 40
local ROW_VALUE_WIDTH = 120
local ORDER_ROW_HEIGHT = 36
local MAX_ORDER_ROWS = 5 -- more than this collapses into "+N more"
local ALLOCATION_BAR_HEIGHT = 10
local MAX_ALLOCATION_LEGEND = 4 -- more groups than this fold into "+N more"

-- Allocation segment colors, largest group first (a chart data series, so
-- literals are allowed); cash is always TextDisabled gray
local ALLOCATION_COLORS = {
	Theme.Colors.Accent,
	Color3.fromRGB(0, 170, 255),
	Color3.fromRGB(255, 170, 0),
	Color3.fromRGB(255, 90, 205),
	Color3.fromRGB(120, 220, 200),
	Color3.fromRGB(255, 214, 102),
	Color3.fromRGB(180, 140, 255),
	Color3.fromRGB(130, 150, 180),
}

-- Chart Constants
local END_DOT_SIZE = 8
local HOVER_DOT_SIZE = 10
local PULSE_INFO = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1)

local REFRESH_INTERVAL = 60
local RANGES = { "24h", "7d", "30d" }
local CIRCLE = UIKit.CIRCLE
local MUTED_HEX = "#" .. Theme.Colors.TextMuted:ToHex()

-- State
local selectedRange = "24h"
local profileSummary = nil -- trades and join date from the last refresh
local histories = {} -- [range] = { { time, value }, ... } from the last refresh
local chartPoints = {} -- the drawn points: { x, y (0-1 of the chart), time, value }
local currentNetWorth = Player:GetAttribute("NetWorth")
local lineColor = Theme.Colors.Up
local pulseTween = nil
local isScrubbing = false
local isRefreshing = false
local isRefreshQueued = false

-- UI Builders
local makeFrame = UIKit.makeFrame
local makeLabel = UIKit.makeLabel
local addCorner = UIKit.addCorner
local addStroke = UIKit.addStroke
local makePanel = UIKit.makePanel
local makeDot = UIKit.makeDot

-- Profile Header
local ProfileHeader = makeFrame("ProfileHeader", PortfolioScreen)
ProfileHeader.Position = UDim2.fromOffset(PADDING, PADDING)
ProfileHeader.Size = UDim2.new(1, -PADDING * 2, 0, HEADER_HEIGHT)

local Avatar = Instance.new("ImageLabel")
Avatar.Name = "Avatar"
Avatar.AnchorPoint = Vector2.new(0, 0.5)
Avatar.Position = UDim2.fromScale(0, 0.5)
Avatar.Size = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE)
Avatar.BackgroundColor3 = Theme.Colors.Raised
Avatar.BorderSizePixel = 0
Avatar.Parent = ProfileHeader
addCorner(Avatar, CIRCLE)

-- Stands in until the headshot loads, or if it never does
local AvatarInitial = makeLabel("Initial", Avatar, Theme.Fonts.UIBold, Theme.TextSize.Display, Theme.Colors.TextMuted)
AvatarInitial.Size = UDim2.fromScale(1, 1)
AvatarInitial.TextXAlignment = Enum.TextXAlignment.Center
AvatarInitial.Text = string.upper(string.sub(Player.DisplayName, 1, 1))

local PROFILE_TEXT_X = AVATAR_SIZE + 14

local DisplayNameLabel =
	makeLabel("DisplayName", ProfileHeader, Theme.Fonts.UIBold, Theme.TextSize.Display, Theme.Colors.Text)
DisplayNameLabel.Position = UDim2.fromOffset(PROFILE_TEXT_X, 2)
DisplayNameLabel.Size = UDim2.new(1, -PROFILE_TEXT_X, 0, 28)
DisplayNameLabel.Text = Player.DisplayName

local UsernameLabel = makeLabel("Username", ProfileHeader, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
UsernameLabel.Position = UDim2.fromOffset(PROFILE_TEXT_X, 30)
UsernameLabel.Size = UDim2.new(1, -PROFILE_TEXT_X, 0, 16)
UsernameLabel.Text = "@" .. Player.Name

local StatsLabel = makeLabel("Stats", ProfileHeader, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
StatsLabel.Position = UDim2.fromOffset(PROFILE_TEXT_X, 46)
StatsLabel.Size = UDim2.new(1, -PROFILE_TEXT_X, 0, 16)

-- Stats Strip
-- The first three are basic tracking; the `analytics` ones need level 2
local STAT_TILES = {
	{ key = "dayPL", caption = "Day P/L" },
	{ key = "unrealizedPL", caption = "Unrealized P/L" },
	{ key = "realizedPL", caption = "Realized P/L" },
	{ key = "winRate", caption = "Win rate", analytics = true },
	{ key = "averages", caption = "Avg gain / loss", analytics = true },
	{ key = "maxDrawdown", caption = "Max drawdown (30d)", analytics = true },
}

local StatsStrip = makeFrame("StatsStrip", PortfolioScreen)
StatsStrip.Position = UDim2.fromOffset(PADDING, PADDING + HEADER_HEIGHT + GAP)
StatsStrip.Size = UDim2.new(1, -PADDING * 2, 0, STATS_STRIP_HEIGHT)

local StatsStripLayout = Instance.new("UIListLayout")
StatsStripLayout.FillDirection = Enum.FillDirection.Horizontal
StatsStripLayout.HorizontalFlex = Enum.UIFlexAlignment.Fill -- equal shares of the width
StatsStripLayout.SortOrder = Enum.SortOrder.LayoutOrder
StatsStripLayout.Padding = UDim.new(0, GAP)
StatsStripLayout.Parent = StatsStrip

local statValueLabels = {} -- [tile key] = value TextLabel

for index, tile in ipairs(STAT_TILES) do
	local tileFrame = makePanel("Stat_" .. tile.key, StatsStrip)
	tileFrame.LayoutOrder = index
	tileFrame.Size = UDim2.fromScale(0, 1)

	local caption = makeLabel("Caption", tileFrame, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	caption.Position = UDim2.fromOffset(12, 8)
	caption.Size = UDim2.new(1, -24, 0, 16)
	caption.Text = tile.caption

	-- RichText for the gain/loss pair; scaled so long amounts fit narrow tiles
	local value = makeLabel("Value", tileFrame, Theme.Fonts.Mono, Theme.TextSize.Title, Theme.Colors.Text)
	value.Position = UDim2.fromOffset(12, 26)
	value.Size = UDim2.new(1, -24, 0, 22)
	value.RichText = true
	value.TextScaled = true
	value.Text = "—"

	local valueSizeConstraint = Instance.new("UITextSizeConstraint")
	valueSizeConstraint.MaxTextSize = Theme.TextSize.Title
	valueSizeConstraint.MinTextSize = Theme.TextSize.Caption
	valueSizeConstraint.Parent = value

	statValueLabels[tile.key] = value
end

-- Chart Panel
local ChartPanel = makePanel("ChartPanel", PortfolioScreen)

local RANGE_PILLS_WIDTH = #RANGES * RANGE_PILL_WIDTH + (#RANGES - 1) * RANGE_PILL_GAP

-- Cents are dimmed with a <font> tag, so this one is RichText
local ValueLabel = makeLabel("ValueLabel", ChartPanel, Theme.Fonts.MonoBold, Theme.TextSize.Hero, Theme.Colors.Text)
ValueLabel.RichText = true
ValueLabel.Position = UDim2.fromOffset(PADDING, PADDING)
ValueLabel.Size = UDim2.new(1, -(PADDING * 2 + RANGE_PILLS_WIDTH + GAP), 0, VALUE_HEIGHT)
ValueLabel.TextScaled = true -- shrinks a long balance on a narrow panel instead of cutting it off
ValueLabel.Text = "—"

local ValueSizeConstraint = Instance.new("UITextSizeConstraint")
ValueSizeConstraint.MaxTextSize = Theme.TextSize.Hero
ValueSizeConstraint.MinTextSize = Theme.TextSize.Title
ValueSizeConstraint.Parent = ValueLabel

-- Muted by default: the range/time suffix; the amount is colored inline
local ChangeLabel = makeLabel("ChangeLabel", ChartPanel, Theme.Fonts.Mono, Theme.TextSize.Title, Theme.Colors.TextMuted)
ChangeLabel.RichText = true
ChangeLabel.Position = UDim2.fromOffset(PADDING, PADDING + VALUE_HEIGHT + 2)
ChangeLabel.Size = UDim2.new(1, -PADDING * 2, 0, CHANGE_HEIGHT)

local RangePills = makeFrame("RangePills", ChartPanel)
RangePills.AnchorPoint = Vector2.new(1, 0)
RangePills.Position = UDim2.new(1, -PADDING, 0, PADDING)
RangePills.Size = UDim2.fromOffset(RANGE_PILLS_WIDTH, RANGE_PILL_HEIGHT)

local RangePillsLayout = Instance.new("UIListLayout")
RangePillsLayout.FillDirection = Enum.FillDirection.Horizontal
RangePillsLayout.SortOrder = Enum.SortOrder.LayoutOrder
RangePillsLayout.Padding = UDim.new(0, RANGE_PILL_GAP)
RangePillsLayout.Parent = RangePills

local rangePills = {} -- [range] = { button, stroke }

for index, range in ipairs(RANGES) do
	local button = Instance.new("TextButton")

	button.Name = "Range_" .. range
	button.LayoutOrder = index
	button.Size = UDim2.fromOffset(RANGE_PILL_WIDTH, RANGE_PILL_HEIGHT)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Theme.Colors.Raised
	button.FontFace = Theme.Fonts.UISemibold
	button.TextSize = Theme.TextSize.Caption
	button.Text = range
	button.Parent = RangePills
	addCorner(button)

	rangePills[range] = { button = button, stroke = addStroke(button) }
end

local CHART_TOP = PADDING + VALUE_HEIGHT + 2 + CHANGE_HEIGHT + PADDING

local Chart = makeFrame("Chart", ChartPanel)
Chart.Position = UDim2.fromOffset(PADDING, CHART_TOP)
Chart.Size = UDim2.new(1, -PADDING * 2, 1, -(CHART_TOP + PADDING))

-- Cleared and redrawn on every render; the hover overlay sits outside it
local Plot = makeFrame("Plot", Chart)
Plot.Size = UDim2.fromScale(1, 1)

local ChartMessage = makeLabel("Message", Chart, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
ChartMessage.Size = UDim2.fromScale(1, 1)
ChartMessage.TextXAlignment = Enum.TextXAlignment.Center
ChartMessage.Text = "Loading…"

local HoverGuide = makeFrame("HoverGuide", Chart)
HoverGuide.BackgroundTransparency = 0.5
HoverGuide.BackgroundColor3 = Theme.Colors.TextMuted
HoverGuide.AnchorPoint = Vector2.new(0.5, 0)
HoverGuide.Size = UDim2.new(0, 1, 1, 0)
HoverGuide.ZIndex = 3
HoverGuide.Visible = false

local HoverDot = makeDot("HoverDot", Chart, HOVER_DOT_SIZE, lineColor)
HoverDot.ZIndex = 5
HoverDot.Visible = false

-- A panel-colored ring so the dot reads on top of the line
local HoverDotRing = addStroke(HoverDot, Theme.Colors.Panel)
HoverDotRing.Thickness = 2

-- Side Panel
local SidePanel = makePanel("SidePanel", PortfolioScreen)
SidePanel.AnchorPoint = Vector2.new(1, 0)

local CashCaption = makeLabel("CashCaption", SidePanel, Theme.Fonts.UI, Theme.TextSize.Title, Theme.Colors.Text)
CashCaption.Position = UDim2.fromOffset(PADDING, PADDING)
CashCaption.Size = UDim2.new(0.5, -PADDING, 0, CASH_ROW_HEIGHT)
CashCaption.Text = "Cash balance"

local CashValue = makeLabel("CashValue", SidePanel, Theme.Fonts.Mono, Theme.TextSize.Title, Theme.Colors.Text)
CashValue.AnchorPoint = Vector2.new(1, 0)
CashValue.Position = UDim2.new(1, -PADDING, 0, PADDING)
CashValue.Size = UDim2.new(0.5, -PADDING, 0, CASH_ROW_HEIGHT)
CashValue.TextXAlignment = Enum.TextXAlignment.Right

local DIVIDER_Y = PADDING + CASH_ROW_HEIGHT + GAP

local Divider = makeFrame("Divider", SidePanel)
Divider.BackgroundTransparency = 0
Divider.BackgroundColor3 = Theme.Colors.Border
Divider.Position = UDim2.fromOffset(PADDING, DIVIDER_Y)
Divider.Size = UDim2.new(1, -PADDING * 2, 0, 1)

local SECTIONS_TOP = DIVIDER_Y + 1 + GAP

-- Allocation (level 2), then open orders, then positions. The first two
-- only show when they have something to show, and layoutSidePanel stacks
-- whatever is showing.
local AllocationSection = makeFrame("AllocationSection", SidePanel)
AllocationSection.Size = UDim2.new(1, -PADDING * 2, 0, 0)
AllocationSection.AutomaticSize = Enum.AutomaticSize.Y
AllocationSection.Visible = false

local AllocationLayout = Instance.new("UIListLayout")
AllocationLayout.SortOrder = Enum.SortOrder.LayoutOrder
AllocationLayout.Padding = UDim.new(0, 6)
AllocationLayout.Parent = AllocationSection

local AllocationHeader =
	makeLabel("Header", AllocationSection, Theme.Fonts.UISemibold, Theme.TextSize.Title, Theme.Colors.Text)
AllocationHeader.LayoutOrder = 0
AllocationHeader.Size = UDim2.new(1, 0, 0, SECTION_HEADER_HEIGHT)
AllocationHeader.Text = "Allocation"

local AllocationBar = makeFrame("Bar", AllocationSection)
AllocationBar.LayoutOrder = 1
AllocationBar.Size = UDim2.new(1, 0, 0, ALLOCATION_BAR_HEIGHT)
AllocationBar.ClipsDescendants = true
addCorner(AllocationBar)

local AllocationBarLayout = Instance.new("UIListLayout")
AllocationBarLayout.FillDirection = Enum.FillDirection.Horizontal
AllocationBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
AllocationBarLayout.Parent = AllocationBar

local AllocationLegend = makeFrame("Legend", AllocationSection)
AllocationLegend.LayoutOrder = 2
AllocationLegend.Size = UDim2.fromScale(1, 0)
AllocationLegend.AutomaticSize = Enum.AutomaticSize.Y

local AllocationLegendLayout = Instance.new("UIListLayout")
AllocationLegendLayout.SortOrder = Enum.SortOrder.LayoutOrder
AllocationLegendLayout.Padding = UDim.new(0, 2)
AllocationLegendLayout.Parent = AllocationLegend

local OrdersSection = makeFrame("OrdersSection", SidePanel)
OrdersSection.Position = UDim2.fromOffset(PADDING, SECTIONS_TOP)
OrdersSection.Size = UDim2.new(1, -PADDING * 2, 0, 0)
OrdersSection.AutomaticSize = Enum.AutomaticSize.Y
OrdersSection.Visible = false

local OrdersLayout = Instance.new("UIListLayout")
OrdersLayout.SortOrder = Enum.SortOrder.LayoutOrder
OrdersLayout.Padding = UDim.new(0, 4)
OrdersLayout.Parent = OrdersSection

local OrdersHeader = makeLabel("Header", OrdersSection, Theme.Fonts.UISemibold, Theme.TextSize.Title, Theme.Colors.Text)
OrdersHeader.LayoutOrder = 0
OrdersHeader.Size = UDim2.new(1, 0, 0, SECTION_HEADER_HEIGHT)

local PositionsHeader = makeFrame("PositionsHeader", SidePanel)
PositionsHeader.Position = UDim2.fromOffset(PADDING, SECTIONS_TOP)
PositionsHeader.Size = UDim2.new(1, -PADDING * 2, 0, SECTION_HEADER_HEIGHT)

local PositionsHeaderLayout = Instance.new("UIListLayout")
PositionsHeaderLayout.FillDirection = Enum.FillDirection.Horizontal
PositionsHeaderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
PositionsHeaderLayout.SortOrder = Enum.SortOrder.LayoutOrder
PositionsHeaderLayout.Padding = UDim.new(0, 8)
PositionsHeaderLayout.Parent = PositionsHeader

local PositionsTitle =
	makeLabel("Title", PositionsHeader, Theme.Fonts.UISemibold, Theme.TextSize.Title, Theme.Colors.Text)
PositionsTitle.LayoutOrder = 1
PositionsTitle.AutomaticSize = Enum.AutomaticSize.X
PositionsTitle.Size = UDim2.fromScale(0, 1)
PositionsTitle.TextTruncate = Enum.TextTruncate.None
PositionsTitle.Text = "Open positions"

local PositionsDot = makeDot("Dot", PositionsHeader, 6, Theme.Colors.Accent)
PositionsDot.LayoutOrder = 2

local PositionsCount =
	makeLabel("Count", PositionsHeader, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.TextMuted)
PositionsCount.LayoutOrder = 3
PositionsCount.AutomaticSize = Enum.AutomaticSize.X
PositionsCount.Size = UDim2.fromScale(0, 1)
PositionsCount.TextTruncate = Enum.TextTruncate.None

local LIST_TOP = SECTIONS_TOP + SECTION_HEADER_HEIGHT + 8

-- Starts ROW_INSET left of the content so a row's highlight can extend past
-- it, and runs to the panel's right edge so the scrollbar sits in the
-- padding beside the rows instead of over them
local PositionsList = Instance.new("ScrollingFrame")
PositionsList.Name = "PositionsList"
PositionsList.Position = UDim2.fromOffset(PADDING - ROW_INSET, LIST_TOP)
PositionsList.Size = UDim2.new(1, -(PADDING - ROW_INSET), 1, -(LIST_TOP + PADDING / 2))
PositionsList.BackgroundTransparency = 1
PositionsList.BorderSizePixel = 0
PositionsList.ScrollBarThickness = 4
PositionsList.ScrollBarImageColor3 = Theme.Colors.TextDisabled
PositionsList.ScrollingDirection = Enum.ScrollingDirection.Y
PositionsList.CanvasSize = UDim2.new()
PositionsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
PositionsList.Parent = SidePanel

local PositionsListLayout = Instance.new("UIListLayout")
PositionsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
PositionsListLayout.Padding = UDim.new(0, 4)
PositionsListLayout.Parent = PositionsList

local PositionsMessage = makeLabel("Message", SidePanel, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
PositionsMessage.Position = UDim2.fromOffset(PADDING, LIST_TOP)
PositionsMessage.Size = UDim2.new(1, -PADDING * 2, 0, 40)
PositionsMessage.TextWrapped = true
PositionsMessage.TextYAlignment = Enum.TextYAlignment.Top
PositionsMessage.Text = "Loading…"

-- Formatting
local function formatSignedMoney(amount)
	return (amount >= 0 and "+" or "-") .. NumberModule.format(math.abs(amount))
end

-- "$93,737.34" with the cents dimmed
local function formatHeroValue(value)
	local text = NumberModule.format(value)
	local whole, cents = string.match(text, "^(.-)(%.%d+)$")

	if not whole then
		return text
	end

	return string.format('%s<font color="%s">%s</font>', whole, MUTED_HEX, cents)
end

local function formatPercent(percent)
	return string.format("%s %.2f%%", percent >= 0 and "▲" or "▼", math.abs(percent))
end

-- Strips os.date's zero padding: "Oct 04, 03:05 PM" -> "Oct 4, 3:05 PM"
local function formatPointTime(time)
	local text = selectedRange == "24h" and os.date("%I:%M %p", time) or os.date("%b %d, %I:%M %p", time)

	return (string.gsub(string.gsub(text, "^0", ""), " 0", " "))
end

local function formatStrike(strike)
	return strike % 1 == 0 and string.format("$%d", strike) or string.format("$%.2f", strike)
end

local function pluralize(count, singular, plural)
	return NumberModule.formatShares(count) .. " " .. (count == 1 and singular or plural)
end

-- Header
-- Shows `value` and its change since the selected range's first point.
-- `suffix` names what the change spans: the range, or the hovered time.
local function setHeader(value, suffix)
	if not value then
		ValueLabel.Text = "—"
		ChangeLabel.Text = ""

		return
	end

	ValueLabel.Text = formatHeroValue(value)

	local points = histories[selectedRange]
	local baseline = points and points[1] and points[1][2]

	if not baseline then
		ChangeLabel.Text = suffix

		return
	end

	local change = math.round((value - baseline) * 100) / 100
	local percent = baseline ~= 0 and (change / baseline * 100) or 0
	local color = change >= 0 and Theme.Colors.Up or Theme.Colors.Down

	ChangeLabel.Text = string.format(
		'<font color="#%s">%s (%s%.2f%%)</font>  %s',
		color:ToHex(),
		formatSignedMoney(change),
		change >= 0 and "+" or "-",
		math.abs(percent),
		suffix
	)
end

local function showCurrentValue()
	setHeader(currentNetWorth, selectedRange)
end

local function updateRangePills()
	for range, pill in pairs(rangePills) do
		local isActive = range == selectedRange

		pill.button.BackgroundTransparency = isActive and 0 or 1
		pill.button.TextColor3 = isActive and Theme.Colors.Text or Theme.Colors.TextMuted
		pill.stroke.Enabled = isActive
	end
end

local function updateCash()
	local balance = Player:GetAttribute("Balance")

	CashValue.Text = balance and NumberModule.format(balance) or "—"
end

-- "Level 1 · Beginner · 120 / 300 XP" (no target once at the top level)
local function formatLevel()
	local level = Player:GetAttribute("Level")
	local xp = Player:GetAttribute("XP")

	if not level or not xp then
		return nil
	end

	local nextLevel = Progression.LEVELS[level + 1]
	local progress = nextLevel
			and string.format("%s / %s XP", NumberModule.formatShares(xp), NumberModule.formatShares(nextLevel.xp))
		or NumberModule.formatShares(xp) .. " XP"

	return string.format("Level %d · %s · %s", level, Progression.LEVELS[level].name, progress)
end

-- Level comes from attributes and the rest from the last GetPortfolioEvent,
-- so either one changing redraws the whole line
local function updateProfileStats()
	local parts = {}
	local levelText = formatLevel()

	if levelText then
		table.insert(parts, levelText)
	end

	if profileSummary then
		table.insert(parts, pluralize(profileSummary.trades or 0, "trade", "trades"))

		if profileSummary.joinedAt then
			table.insert(parts, "Joined " .. os.date("%b %Y", profileSummary.joinedAt))
		end
	end

	StatsLabel.Text = table.concat(parts, "  ·  ")
end

-- Stats
local UP_HEX = Theme.Colors.Up:ToHex()
local DOWN_HEX = Theme.Colors.Down:ToHex()

local function getChangeColor(amount)
	if amount > 0 then
		return Theme.Colors.Up
	elseif amount < 0 then
		return Theme.Colors.Down
	end

	return Theme.Colors.Text
end

local function setStat(key, text, color)
	local label = statValueLabels[key]

	label.Text = text
	label.TextColor3 = color or Theme.Colors.Text
end

local function setMoneyStat(key, amount)
	if amount then
		setStat(key, formatSignedMoney(amount), getChangeColor(amount))
	else
		setStat(key, "—", Theme.Colors.TextMuted)
	end
end

-- Day and unrealized P/L add up the position rows (day P/L is shares only:
-- option quotes carry no previous close); the rest is the server's summary
local function renderStats(summary, sharePositions)
	local dayPL, unrealizedPL = 0, 0

	for _, position in ipairs(sharePositions) do
		dayPL += position.plDay or 0
		unrealizedPL += position.plOpen or 0
	end

	for _, position in ipairs(summary.options or {}) do
		unrealizedPL += position.plOpen or 0
	end

	setMoneyStat("dayPL", dayPL)
	setMoneyStat("unrealizedPL", unrealizedPL)
	setMoneyStat("realizedPL", summary.realizedPL)

	local analytics = summary.analytics

	if not analytics then
		local lockedText = "Unlocks at Lv " .. Progression.FEATURES.Analytics

		for _, tile in ipairs(STAT_TILES) do
			if tile.analytics then
				setStat(tile.key, lockedText, Theme.Colors.TextDisabled)
			end
		end

		return
	end

	if analytics.winRate then
		setStat(
			"winRate",
			string.format("%.0f%% · %s", analytics.winRate * 100, pluralize(analytics.closedTrades, "trade", "trades"))
		)
	else
		setStat("winRate", "—", Theme.Colors.TextMuted)
	end

	if analytics.averageGain or analytics.averageLoss then
		local gain = analytics.averageGain
				and string.format('<font color="#%s">+%s</font>', UP_HEX, NumberModule.format(analytics.averageGain))
			or "—"
		local loss = analytics.averageLoss
				and string.format('<font color="#%s">-%s</font>', DOWN_HEX, NumberModule.format(analytics.averageLoss))
			or "—"

		setStat("averages", gain .. " / " .. loss)
	else
		setStat("averages", "—", Theme.Colors.TextMuted)
	end

	local drawdownPercent = analytics.maxDrawdown and analytics.maxDrawdown * 100

	-- Below half a hundredth it would print as a red "-0.00%"
	if drawdownPercent and drawdownPercent >= 0.005 then
		setStat("maxDrawdown", string.format("-%.2f%%", drawdownPercent), Theme.Colors.Down)
	elseif drawdownPercent then
		setStat("maxDrawdown", "0.00%")
	else
		setStat("maxDrawdown", "—", Theme.Colors.TextMuted)
	end
end

-- Chart
-- The selected range as a LineChart, plus a pulsing dot on the newest point
local function renderChart()
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end

	Plot:ClearAllChildren()
	table.clear(chartPoints)
	HoverGuide.Visible = false
	HoverDot.Visible = false
	isScrubbing = false

	local points = histories[selectedRange]

	if not points or #points == 0 then
		ChartMessage.Visible = true
		showCurrentValue()

		return
	end

	ChartMessage.Visible = false

	chartPoints = LineChart.layout(points)
	lineColor = LineChart.getColor(points)
	HoverDot.BackgroundColor3 = lineColor
	LineChart.draw(Plot, chartPoints, lineColor, Theme.Colors.Panel, 2)

	local last = chartPoints[#chartPoints]

	local halo = makeDot("EndHalo", Plot, END_DOT_SIZE, lineColor)
	halo.BackgroundTransparency = 0.5
	halo.Position = UDim2.fromScale(last.x, last.y)
	halo.ZIndex = 3

	local endDot = makeDot("EndDot", Plot, END_DOT_SIZE, lineColor)
	endDot.Position = UDim2.fromScale(last.x, last.y)
	endDot.ZIndex = 4

	pulseTween = TweenService:Create(halo, PULSE_INFO, {
		Size = UDim2.fromOffset(END_DOT_SIZE * 3, END_DOT_SIZE * 3),
		BackgroundTransparency = 1,
	})
	pulseTween:Play()

	showCurrentValue()
end

local function getNearestPoint(relativeX)
	local nearest = nil
	local nearestDistance = math.huge

	for _, point in ipairs(chartPoints) do
		local distance = math.abs(point.x - relativeX)

		if distance < nearestDistance then
			nearest = point
			nearestDistance = distance
		end
	end

	return nearest
end

-- Hovering scrubs the header to the point under the cursor
local function onChartMouseMoved(mouseX)
	local point = getNearestPoint((mouseX - Chart.AbsolutePosition.X) / math.max(Chart.AbsoluteSize.X, 1))

	if not point then
		return
	end

	isScrubbing = true
	HoverGuide.Position = UDim2.fromScale(point.x, 0)
	HoverGuide.Visible = true
	HoverDot.Position = UDim2.fromScale(point.x, point.y)
	HoverDot.Visible = true
	setHeader(point.value, formatPointTime(point.time))
end

local function onChartMouseLeave()
	isScrubbing = false
	HoverGuide.Visible = false
	HoverDot.Visible = false
	showCurrentValue()
end

-- Positions
-- "BTC-USD" -> "BTC"
local function getIconText(ticker)
	return string.sub(string.match(ticker, "^%w+") or ticker, 1, 4)
end

-- Share rows (GetPositionsEvent) and option rows (GetPortfolioEvent) in one
-- display shape, biggest holding first, each with its share of net worth
local function buildRows(sharePositions, optionPositions, netWorth)
	local rows = {}

	for _, position in ipairs(sharePositions) do
		local avgCost = position.tradePrice and NumberModule.format(position.tradePrice) or "—"

		table.insert(rows, {
			ticker = position.ticker,
			title = position.ticker,
			subtitle = pluralize(position.quantity, "share", "shares") .. " · avg " .. avgCost,
			value = position.netLiq,
			plOpenPct = position.plOpenPct,
		})
	end

	for _, position in ipairs(optionPositions) do
		local expiration = string.match(tostring(position.expiration), "^%d%d%d%d%-%d%d%-%d%d")
			or tostring(position.expiration)

		table.insert(rows, {
			ticker = position.ticker,
			isOption = true,
			title = string.format(
				"%s %s %s",
				position.ticker,
				formatStrike(position.strike),
				position.type == "C" and "Call" or "Put"
			),
			subtitle = pluralize(position.contracts, "contract", "contracts") .. " · exp " .. expiration,
			value = position.value,
			plOpenPct = position.plOpenPct,
		})
	end

	for _, row in ipairs(rows) do
		if row.value and netWorth and netWorth > 0 then
			row.subtitle ..= string.format(" · %.1f%%", row.value / netWorth * 100)
		end
	end

	-- Unpriced holdings sink to the bottom
	table.sort(rows, function(a, b)
		return (a.value or -math.huge) > (b.value or -math.huge)
	end)

	return rows
end

-- Clicking a row opens its ticker on the Trade tab (the underlying for an
-- option, whose chain lives there)
local function createPositionRow(index, row)
	local rowButton = Instance.new("TextButton")
	rowButton.Name = "Position_" .. index
	rowButton.LayoutOrder = index
	rowButton.Size = UDim2.new(1, -(PADDING - ROW_INSET), 0, ROW_HEIGHT)
	rowButton.AutoButtonColor = false
	rowButton.BorderSizePixel = 0
	rowButton.BackgroundColor3 = Theme.Colors.Raised
	rowButton.BackgroundTransparency = 1
	rowButton.Text = ""
	rowButton.Parent = PositionsList
	addCorner(rowButton)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, ROW_INSET)
	padding.PaddingRight = UDim.new(0, ROW_INSET)
	padding.Parent = rowButton

	rowButton.MouseEnter:Connect(function()
		rowButton.BackgroundTransparency = 0
	end)

	rowButton.MouseLeave:Connect(function()
		rowButton.BackgroundTransparency = 1
	end)

	rowButton.MouseButton1Click:Connect(function()
		Navigation.openTicker(row.ticker)
	end)

	-- Options get the accent tint so they stand apart from shares at a glance
	local icon = makeFrame("Icon", rowButton)
	icon.BackgroundTransparency = 0
	icon.BackgroundColor3 = row.isOption and Theme.Colors.AccentTint or Theme.Colors.Raised
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0, 0.5)
	icon.Size = UDim2.fromOffset(ROW_ICON_SIZE, ROW_ICON_SIZE)
	addCorner(icon, CIRCLE)

	local iconText = makeLabel(
		"Text",
		icon,
		Theme.Fonts.UIBold,
		Theme.TextSize.Caption,
		row.isOption and Theme.Colors.Accent or Theme.Colors.Text
	)
	iconText.Size = UDim2.fromScale(1, 1)
	iconText.TextXAlignment = Enum.TextXAlignment.Center
	iconText.TextTruncate = Enum.TextTruncate.None
	iconText.Text = getIconText(row.ticker)

	local textX = ROW_ICON_SIZE + 12
	local textWidth = -(textX + ROW_VALUE_WIDTH + 8)

	local title = makeLabel("Title", rowButton, Theme.Fonts.UISemibold, Theme.TextSize.Title, Theme.Colors.Text)
	title.Position = UDim2.fromOffset(textX, 9)
	title.Size = UDim2.new(1, textWidth, 0, 20)
	title.Text = row.title

	local subtitle = makeLabel("Subtitle", rowButton, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	subtitle.Position = UDim2.fromOffset(textX, 31)
	subtitle.Size = UDim2.new(1, textWidth, 0, 16)
	subtitle.Text = row.subtitle

	local value = makeLabel("Value", rowButton, Theme.Fonts.Mono, Theme.TextSize.Title, Theme.Colors.Text)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, 0, 0, 9)
	value.Size = UDim2.fromOffset(ROW_VALUE_WIDTH, 20)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Text = row.value and NumberModule.format(row.value) or "—"

	local change = makeLabel("Change", rowButton, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	change.AnchorPoint = Vector2.new(1, 0)
	change.Position = UDim2.new(1, 0, 0, 31)
	change.Size = UDim2.fromOffset(ROW_VALUE_WIDTH, 16)
	change.TextXAlignment = Enum.TextXAlignment.Right
	change.Text = row.plOpenPct and formatPercent(row.plOpenPct) or "—"

	if row.plOpenPct then
		change.TextColor3 = row.plOpenPct >= 0 and Theme.Colors.Up or Theme.Colors.Down
	end
end

local function renderPositions(rows)
	for _, child in ipairs(PositionsList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	PositionsCount.Text = tostring(#rows)
	PositionsMessage.Text = "No open positions yet. Buy something on the Trade tab and it shows up here."
	PositionsMessage.Visible = #rows == 0

	for index, row in ipairs(rows) do
		createPositionRow(index, row)
	end
end

-- Refresh
local function invoke(remote, ...)
	local success, result = pcall(remote.InvokeServer, remote, ...)

	if not success then
		warn("[PortfolioController] " .. remote.Name .. " failed: " .. tostring(result))

		return nil
	end

	return result
end

-- Open Orders
local refresh -- defined below; cancelling an order refreshes the tab

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

-- Stacks allocation and open orders (when showing) above the positions
local function layoutSidePanel()
	local top = SECTIONS_TOP

	for _, section in ipairs({ AllocationSection, OrdersSection }) do
		section.Position = UDim2.fromOffset(PADDING, top)

		if section.Visible then
			top += section.AbsoluteSize.Y + GAP
		end
	end

	local listTop = top + SECTION_HEADER_HEIGHT + 8

	PositionsHeader.Position = UDim2.fromOffset(PADDING, top)
	PositionsList.Position = UDim2.fromOffset(PADDING - ROW_INSET, listTop)
	PositionsList.Size = UDim2.new(1, -(PADDING - ROW_INSET), 1, -(listTop + PADDING / 2))
	PositionsMessage.Position = UDim2.fromOffset(PADDING, listTop)
end

local function createOrderRow(index, order)
	local row = makeFrame("Order_" .. index, OrdersSection)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, 0, 0, ORDER_ROW_HEIGHT)

	local sideColor = order.side == "Buy" and Theme.Colors.Up or Theme.Colors.Down

	local title = makeLabel("Title", row, Theme.Fonts.UISemibold, Theme.TextSize.Body, Theme.Colors.Text)
	title.RichText = true
	title.Size = UDim2.new(1, -80, 0, 18)
	title.Text = string.format(
		'<font color="#%s">%s</font> %s %s',
		sideColor:ToHex(),
		order.side,
		NumberModule.formatShares(order.quantity),
		order.ticker
	)

	local detail = makeLabel("Detail", row, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	detail.Position = UDim2.fromOffset(0, 18)
	detail.Size = UDim2.new(1, -80, 0, 16)
	detail.Text = string.format(
		"%s · %s",
		OrderRules.describeLevels(order, NumberModule.format),
		formatAge(os.time() - order.createdAt)
	)

	local cancel = Instance.new("TextButton")
	cancel.Name = "Cancel"
	cancel.AnchorPoint = Vector2.new(1, 0.5)
	cancel.Position = UDim2.fromScale(1, 0.5)
	cancel.Size = UDim2.fromOffset(68, 24)
	cancel.AutoButtonColor = false
	cancel.BorderSizePixel = 0
	cancel.BackgroundColor3 = Theme.Colors.Raised
	cancel.FontFace = Theme.Fonts.UISemibold
	cancel.TextSize = Theme.TextSize.Caption
	cancel.TextColor3 = Theme.Colors.TextMuted
	cancel.Text = "Cancel"
	cancel.Parent = row
	addCorner(cancel)
	addStroke(cancel)

	cancel.MouseButton1Click:Connect(function()
		cancel.Text = "…"
		invoke(CancelOrderEvent, order.id)
		refresh()
	end)
end

-- Level 2 analytics: how net worth splits across stock sectors, other kinds
-- of security (ETFs, crypto...) and cash. `rows` are the position rows,
-- whose values are already priced.
local function renderAllocation(summary, rows)
	local groupsByTicker = summary.analytics and summary.analytics.allocationGroups

	for _, container in ipairs({ AllocationBar, AllocationLegend }) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	AllocationSection.Visible = groupsByTicker ~= nil

	if not groupsByTicker then
		layoutSidePanel()

		return
	end

	local totals = {}

	for _, row in ipairs(rows) do
		if row.value and row.value > 0 then
			local group = groupsByTicker[row.ticker] or "Other"

			totals[group] = (totals[group] or 0) + row.value
		end
	end

	local cash = Player:GetAttribute("Balance") or summary.balance or 0
	local groups = {}
	local total = 0

	for name, value in pairs(totals) do
		table.insert(groups, { name = name, value = value })
	end

	if cash > 0 then
		table.insert(groups, { name = "Cash", value = cash, isCash = true })
	end

	table.sort(groups, function(a, b)
		return a.value > b.value
	end)

	local colorIndex = 0

	for _, group in ipairs(groups) do
		total += group.value

		if group.isCash then
			group.color = Theme.Colors.TextDisabled
		else
			colorIndex += 1
			group.color = ALLOCATION_COLORS[(colorIndex - 1) % #ALLOCATION_COLORS + 1]
		end
	end

	for index, group in ipairs(groups) do
		local segment = makeFrame("Segment_" .. index, AllocationBar)
		segment.LayoutOrder = index
		segment.BackgroundTransparency = 0
		segment.BackgroundColor3 = group.color
		segment.Size = UDim2.fromScale(group.value / total, 1)
	end

	for index = 1, math.min(#groups, MAX_ALLOCATION_LEGEND) do
		local group = groups[index]

		local line = makeFrame("Line_" .. index, AllocationLegend)
		line.LayoutOrder = index
		line.Size = UDim2.new(1, 0, 0, 16)

		local dot = makeDot("Dot", line, 8, group.color)
		dot.Position = UDim2.new(0, 4, 0.5, 0)

		local name = makeLabel("Name", line, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.Text)
		name.Position = UDim2.fromOffset(14, 0)
		name.Size = UDim2.new(1, -74, 1, 0)
		name.Text = group.name

		local share = makeLabel("Share", line, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.TextMuted)
		share.AnchorPoint = Vector2.new(1, 0)
		share.Position = UDim2.fromScale(1, 0)
		share.Size = UDim2.new(0, 60, 1, 0)
		share.TextXAlignment = Enum.TextXAlignment.Right
		share.Text = string.format("%.1f%%", group.value / total * 100)
	end

	if #groups > MAX_ALLOCATION_LEGEND then
		local more = makeLabel("More", AllocationLegend, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
		more.LayoutOrder = MAX_ALLOCATION_LEGEND + 1
		more.Size = UDim2.new(1, 0, 0, 16)
		more.Text = string.format("+%d more", #groups - MAX_ALLOCATION_LEGEND)
	end

	layoutSidePanel()
end

local function renderOrders(orders)
	for _, child in ipairs(OrdersSection:GetChildren()) do
		if child:IsA("GuiObject") and child ~= OrdersHeader then
			child:Destroy()
		end
	end

	OrdersHeader.Text = "Open orders · " .. #orders
	OrdersSection.Visible = #orders > 0

	for index = 1, math.min(#orders, MAX_ORDER_ROWS) do
		createOrderRow(index, orders[index])
	end

	if #orders > MAX_ORDER_ROWS then
		local more = makeLabel("More", OrdersSection, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
		more.LayoutOrder = MAX_ORDER_ROWS + 1
		more.Size = UDim2.new(1, 0, 0, 16)
		more.Text = string.format("+%d more", #orders - MAX_ORDER_ROWS)
	end

	layoutSidePanel()
end

-- Calls made while one is in flight collapse into a single follow-up.
-- Assigns the `refresh` declared above, so the order rows can call it.
function refresh()
	if isRefreshing then
		isRefreshQueued = true

		return
	end

	isRefreshing = true

	-- The first two reprice holdings over HTTP on the server, so all three
	-- run side by side
	local summary, sharePositions, orders
	local pending = 3

	task.spawn(function()
		summary = invoke(GetPortfolioEvent)
		pending -= 1
	end)

	task.spawn(function()
		sharePositions = invoke(GetPositionsEvent)
		pending -= 1
	end)

	task.spawn(function()
		orders = invoke(GetOrdersEvent)
		pending -= 1
	end)

	while pending > 0 do
		task.wait()
	end

	if orders then
		renderOrders(orders)
	end

	if summary then
		histories = summary.histories or {}
		currentNetWorth = summary.netWorth
		ChartMessage.Text = "No history yet"
		profileSummary = summary
		updateProfileStats()
		renderChart()

		-- Shares and options only render together: a list missing one kind
		-- would read as those positions having been closed
		if sharePositions then
			local rows = buildRows(sharePositions, summary.options or {}, summary.netWorth)

			renderPositions(rows)
			renderAllocation(summary, rows)
			renderStats(summary, sharePositions)
		end
	elseif next(histories) == nil then
		ChartMessage.Text = "Couldn't load your portfolio"
	end

	isRefreshing = false

	if isRefreshQueued then
		isRefreshQueued = false
		refresh()
	end
end

-- Layout
-- Side by side, the side panel takes about a third of the width and the
-- chart the rest; on a narrow screen the side panel stacks under the chart
local function layoutScreen()
	local screenSize = PortfolioScreen.AbsoluteSize
	local bodyTop = PADDING + HEADER_HEIGHT + GAP + STATS_STRIP_HEIGHT + GAP

	ChartPanel.Position = UDim2.fromOffset(PADDING, bodyTop)

	if screenSize.X < STACK_BELOW_WIDTH then
		local bodyHeight = screenSize.Y - bodyTop - PADDING
		local chartHeight = math.floor((bodyHeight - GAP) * STACKED_CHART_SHARE)

		ChartPanel.Size = UDim2.new(1, -PADDING * 2, 0, chartHeight)
		SidePanel.Position = UDim2.new(1, -PADDING, 0, bodyTop + chartHeight + GAP)
		SidePanel.Size = UDim2.new(1, -PADDING * 2, 0, bodyHeight - chartHeight - GAP)

		return
	end

	local sideWidth =
		math.clamp(math.floor(screenSize.X * SIDE_PANEL_SCALE), SIDE_PANEL_MIN_WIDTH, SIDE_PANEL_MAX_WIDTH)

	ChartPanel.Size = UDim2.new(1, -(PADDING * 2 + GAP + sideWidth), 1, -(bodyTop + PADDING))
	SidePanel.Position = UDim2.new(1, -PADDING, 0, bodyTop)
	SidePanel.Size = UDim2.new(0, sideWidth, 1, -(bodyTop + PADDING))
end

-- Connections
for range, pill in pairs(rangePills) do
	pill.button.MouseButton1Click:Connect(function()
		selectedRange = range
		updateRangePills()
		renderChart()
	end)
end

Chart.MouseMoved:Connect(onChartMouseMoved)
Chart.MouseLeave:Connect(onChartMouseLeave)
-- Segment lengths are in pixels, so a resize needs a redraw
Chart:GetPropertyChangedSignal("AbsoluteSize"):Connect(renderChart)
PortfolioScreen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutScreen)

PortfolioScreen:GetPropertyChangedSignal("Visible"):Connect(function()
	if PortfolioScreen.Visible then
		refresh()
	end
end)

-- Balance only moves on a trade, so positions changed too
OrdersSection:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutSidePanel)
AllocationSection:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutSidePanel)

-- A limit order filled, was cancelled or expired on the server
OrderUpdateEvent.OnClientEvent:Connect(function()
	if PortfolioScreen.Visible then
		refresh()
	end
end)

Player:GetAttributeChangedSignal("Balance"):Connect(function()
	updateCash()

	if PortfolioScreen.Visible then
		refresh()
	end
end)

-- Every reprice (trades, the server's 5-minute sample) lands here; the
-- chart itself catches up on the next refresh
Player:GetAttributeChangedSignal("XP"):Connect(updateProfileStats)

-- A new level can unlock analytics, which only arrive with a refresh
Player:GetAttributeChangedSignal("Level"):Connect(function()
	updateProfileStats()

	if PortfolioScreen.Visible then
		refresh()
	end
end)

Player:GetAttributeChangedSignal("NetWorth"):Connect(function()
	currentNetWorth = Player:GetAttribute("NetWorth")

	if not isScrubbing then
		showCurrentValue()
	end
end)

task.spawn(function()
	local success, image = pcall(
		Players.GetUserThumbnailAsync,
		Players,
		Player.UserId,
		Enum.ThumbnailType.HeadShot,
		Enum.ThumbnailSize.Size150x150
	)

	if success and image then
		Avatar.Image = image
		AvatarInitial.Visible = false
	end
end)

task.spawn(function()
	while true do
		task.wait(REFRESH_INTERVAL)

		if PortfolioScreen.Visible then
			refresh()
		end
	end
end)

layoutScreen()
updateRangePills()
updateCash()
updateProfileStats()
showCurrentValue()
