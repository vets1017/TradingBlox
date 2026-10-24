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
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetPortfolioEvent = EventsFolder:WaitForChild("GetPortfolioEvent")
local GetPositionsEvent = EventsFolder:WaitForChild("GetPositionsEvent")

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
local CASH_ROW_HEIGHT = 24
local SECTION_HEADER_HEIGHT = 24
local ROW_HEIGHT = 56
local ROW_INSET = 8 -- the hover highlight reaches this far past the row's content
local ROW_ICON_SIZE = 40
local ROW_VALUE_WIDTH = 120

-- Chart Constants
local LINE_THICKNESS = 2
local CHART_VERTICAL_INSET = 0.1 -- headroom above the high and below the low
local LINE_FADE = 0.6 -- how far the line's oldest end fades toward the panel
local FILL_TOP_TRANSPARENCY = 0.85
local END_DOT_SIZE = 8
local HOVER_DOT_SIZE = 10
local PULSE_INFO = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1)

local REFRESH_INTERVAL = 60
local RANGES = { "24h", "7d", "30d" }
local CIRCLE = UDim.new(0.5, 0)
local MUTED_HEX = "#" .. Theme.Colors.TextMuted:ToHex()

-- State
local selectedRange = "24h"
local histories = {} -- [range] = { { time, value }, ... } from the last refresh
local chartPoints = {} -- the drawn points: { x, y (0-1 of the chart), time, value }
local currentNetWorth = Player:GetAttribute("NetWorth")
local lineColor = Theme.Colors.Up
local pulseTween = nil
local isScrubbing = false
local isRefreshing = false
local isRefreshQueued = false

-- UI Builders
local function makeFrame(name, parent)
	local frame = Instance.new("Frame")

	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent

	return frame
end

local function makeLabel(name, parent, font, textSize, color)
	local label = Instance.new("TextLabel")

	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = font
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent

	return label
end

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")

	corner.CornerRadius = radius or Theme.Radius
	corner.Parent = instance
end

local function addStroke(instance, color)
	local stroke = Instance.new("UIStroke")

	stroke.Color = color or Theme.Colors.Border
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance

	return stroke
end

local function makePanel(name, parent)
	local panel = makeFrame(name, parent)

	panel.BackgroundTransparency = 0
	panel.BackgroundColor3 = Theme.Colors.Panel
	addCorner(panel)
	addStroke(panel)

	return panel
end

local function makeDot(name, parent, size, color)
	local dot = makeFrame(name, parent)

	dot.BackgroundTransparency = 0
	dot.BackgroundColor3 = color
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(size, size)
	addCorner(dot, CIRCLE)

	return dot
end

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

local DisplayNameLabel = makeLabel("DisplayName", ProfileHeader, Theme.Fonts.UIBold, Theme.TextSize.Display, Theme.Colors.Text)
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

local POSITIONS_HEADER_Y = DIVIDER_Y + 1 + GAP

local PositionsHeader = makeFrame("PositionsHeader", SidePanel)
PositionsHeader.Position = UDim2.fromOffset(PADDING, POSITIONS_HEADER_Y)
PositionsHeader.Size = UDim2.new(1, -PADDING * 2, 0, SECTION_HEADER_HEIGHT)

local PositionsHeaderLayout = Instance.new("UIListLayout")
PositionsHeaderLayout.FillDirection = Enum.FillDirection.Horizontal
PositionsHeaderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
PositionsHeaderLayout.SortOrder = Enum.SortOrder.LayoutOrder
PositionsHeaderLayout.Padding = UDim.new(0, 8)
PositionsHeaderLayout.Parent = PositionsHeader

local PositionsTitle = makeLabel("Title", PositionsHeader, Theme.Fonts.UISemibold, Theme.TextSize.Title, Theme.Colors.Text)
PositionsTitle.LayoutOrder = 1
PositionsTitle.AutomaticSize = Enum.AutomaticSize.X
PositionsTitle.Size = UDim2.fromScale(0, 1)
PositionsTitle.TextTruncate = Enum.TextTruncate.None
PositionsTitle.Text = "Open positions"

local PositionsDot = makeDot("Dot", PositionsHeader, 6, Theme.Colors.Accent)
PositionsDot.LayoutOrder = 2

local PositionsCount = makeLabel("Count", PositionsHeader, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.TextMuted)
PositionsCount.LayoutOrder = 3
PositionsCount.AutomaticSize = Enum.AutomaticSize.X
PositionsCount.Size = UDim2.fromScale(0, 1)
PositionsCount.TextTruncate = Enum.TextTruncate.None

local LIST_TOP = POSITIONS_HEADER_Y + SECTION_HEADER_HEIGHT + 8

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

local function updateProfileStats(summary)
	local parts = { pluralize(summary.trades or 0, "trade", "trades") }

	if summary.joinedAt then
		table.insert(parts, "Joined " .. os.date("%b %Y", summary.joinedAt))
	end

	StatsLabel.Text = table.concat(parts, "  ·  ")
end

-- Chart
-- Draws the selected range as one continuous line (rotated 2px segments -
-- Roblox has no polyline), colored by whether the range is up or down and
-- fading toward its oldest end, over a soft fill and a pulsing end dot.
-- Time runs left to right proportionally, so gaps while the player was
-- offline read as straight stretches.
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

	-- A single point (a brand-new account) draws as a flat line
	if #points == 1 then
		points = { points[1], points[1] }
	end

	local low, high = math.huge, -math.huge

	for _, point in ipairs(points) do
		low = math.min(low, point[2])
		high = math.max(high, point[2])
	end

	local firstTime = points[1][1]
	local timeSpan = points[#points][1] - firstTime

	for index, point in ipairs(points) do
		local x = timeSpan > 0 and (point[1] - firstTime) / timeSpan or (index - 1) / (#points - 1)
		local y = high > low and CHART_VERTICAL_INSET + (1 - CHART_VERTICAL_INSET * 2) * (high - point[2]) / (high - low)
			or 0.5

		table.insert(chartPoints, { x = x, y = y, time = point[1], value = point[2] })
	end

	local width = math.max(Chart.AbsoluteSize.X, 1)
	local height = math.max(Chart.AbsoluteSize.Y, 1)

	lineColor = points[#points][2] >= points[1][2] and Theme.Colors.Up or Theme.Colors.Down
	HoverDot.BackgroundColor3 = lineColor

	local fadedColor = lineColor:Lerp(Theme.Colors.Panel, LINE_FADE)

	for i = 1, #chartPoints - 1 do
		local from = chartPoints[i]
		local to = chartPoints[i + 1]
		local dx = (to.x - from.x) * width
		local dy = (to.y - from.y) * height

		local segment = makeFrame("Segment_" .. i, Plot)
		segment.BackgroundTransparency = 0
		segment.BackgroundColor3 = Color3.new(1, 1, 1) -- tinted by the gradient
		segment.AnchorPoint = Vector2.new(0.5, 0.5)
		segment.Position = UDim2.fromScale((from.x + to.x) / 2, (from.y + to.y) / 2)
		-- +1px overlaps neighbours so sharp turns don't show a notch
		segment.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 1, LINE_THICKNESS)
		segment.Rotation = math.deg(math.atan2(dy, dx))
		segment.ZIndex = 3

		local segmentGradient = Instance.new("UIGradient")
		segmentGradient.Color = ColorSequence.new(fadedColor:Lerp(lineColor, from.x), fadedColor:Lerp(lineColor, to.x))
		segmentGradient.Parent = segment

		-- Fill: a column under the segment's lower end, fading out downward.
		-- Whole pixels, so neighbouring columns neither gap nor overlap.
		local left = math.floor(from.x * width)
		local right = math.floor(to.x * width)
		local top = math.floor(math.max(from.y, to.y) * height)

		if right > left and top < height then
			local fill = makeFrame("Fill_" .. i, Plot)
			fill.BackgroundTransparency = 0
			fill.BackgroundColor3 = lineColor
			fill.Position = UDim2.fromOffset(left, top)
			fill.Size = UDim2.fromOffset(right - left, height - top)
			fill.ZIndex = 2

			local fillGradient = Instance.new("UIGradient")
			fillGradient.Rotation = 90
			fillGradient.Transparency = NumberSequence.new(FILL_TOP_TRANSPARENCY, 1)
			fillGradient.Parent = fill
		end
	end

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
-- display shape, biggest holding first
local function buildRows(sharePositions, optionPositions)
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
local function invoke(remote)
	local success, result = pcall(remote.InvokeServer, remote)

	if not success then
		warn("[PortfolioController] " .. remote.Name .. " failed: " .. tostring(result))

		return nil
	end

	return result
end

-- Calls made while one is in flight collapse into a single follow-up
local function refresh()
	if isRefreshing then
		isRefreshQueued = true

		return
	end

	isRefreshing = true

	-- Both reprice holdings over HTTP on the server, so run them side by side
	local summary, sharePositions
	local pending = 2

	task.spawn(function()
		summary = invoke(GetPortfolioEvent)
		pending -= 1
	end)

	task.spawn(function()
		sharePositions = invoke(GetPositionsEvent)
		pending -= 1
	end)

	while pending > 0 do
		task.wait()
	end

	if summary then
		histories = summary.histories or {}
		currentNetWorth = summary.netWorth
		ChartMessage.Text = "No history yet"
		updateProfileStats(summary)
		renderChart()

		-- Shares and options only render together: a list missing one kind
		-- would read as those positions having been closed
		if sharePositions then
			renderPositions(buildRows(sharePositions, summary.options or {}))
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
	local bodyTop = PADDING + HEADER_HEIGHT + GAP

	ChartPanel.Position = UDim2.fromOffset(PADDING, bodyTop)

	if screenSize.X < STACK_BELOW_WIDTH then
		local bodyHeight = screenSize.Y - bodyTop - PADDING
		local chartHeight = math.floor((bodyHeight - GAP) * STACKED_CHART_SHARE)

		ChartPanel.Size = UDim2.new(1, -PADDING * 2, 0, chartHeight)
		SidePanel.Position = UDim2.new(1, -PADDING, 0, bodyTop + chartHeight + GAP)
		SidePanel.Size = UDim2.new(1, -PADDING * 2, 0, bodyHeight - chartHeight - GAP)

		return
	end

	local sideWidth = math.clamp(math.floor(screenSize.X * SIDE_PANEL_SCALE), SIDE_PANEL_MIN_WIDTH, SIDE_PANEL_MAX_WIDTH)

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
Player:GetAttributeChangedSignal("Balance"):Connect(function()
	updateCash()

	if PortfolioScreen.Visible then
		refresh()
	end
end)

-- Every reprice (trades, the server's 5-minute sample) lands here; the
-- chart itself catches up on the next refresh
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
showCurrentValue()
