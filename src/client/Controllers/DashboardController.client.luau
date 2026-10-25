-- DashboardController.client.luau
--
-- Fills the Dashboard's Studio-built widgets (GDD §3): Account Info, the
-- watchlist, orders, performance, a market overview and top traders. The
-- widget frames come from Studio; their contents are built here from Theme
-- tokens. TerminalController still owns the greeting and NYSE countdown.
-- Everything refreshes when the Dashboard opens, after a trade, and once a
-- minute while it's showing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)
local LineChart = require(ReplicatedStorage.UI.LineChart)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local Economy = require(ReplicatedStorage.Config.Economy)
local Progression = require(ReplicatedStorage.Config.Progression)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetPortfolioEvent = EventsFolder:WaitForChild("GetPortfolioEvent")
local GetPositionsEvent = EventsFolder:WaitForChild("GetPositionsEvent")
local GetOrdersEvent = EventsFolder:WaitForChild("GetOrdersEvent")
local GetWatchlistEvent = EventsFolder:WaitForChild("GetWatchlistEvent")
local GetMarketOverviewEvent = EventsFolder:WaitForChild("GetMarketOverviewEvent")
local GetMarketMoversEvent = EventsFolder:WaitForChild("GetMarketMoversEvent")
local GetLeaderboardEvent = EventsFolder:WaitForChild("GetLeaderboardEvent")
local OrderUpdateEvent = EventsFolder:WaitForChild("OrderUpdateEvent")

-- References
local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local DashboardScreen = TerminalGui:WaitForChild("MainBackground"):WaitForChild("ScreenContainer"):WaitForChild("DashboardScreen")
local DashboardGrid = DashboardScreen:WaitForChild("DashboardGrid")
local LeftSidebar = DashboardGrid:WaitForChild("LeftSidebar")
local AccountInfoWidget = LeftSidebar:WaitForChild("AccountInfoWidget")
local WatchlistWidget = LeftSidebar:WaitForChild("WatchlistWidget")
local MainWorkspace = DashboardGrid:WaitForChild("MainWorkspace")
local OrderStatusWidget = MainWorkspace:WaitForChild("TopRow"):WaitForChild("OrderStatusWidget")
local BottomRow = MainWorkspace:WaitForChild("BottomRow")
local HeatmapWidget = BottomRow:WaitForChild("HeatmapWidget")
local PLWidget = BottomRow:WaitForChild("PLWidget")
local EventFeedWidget = DashboardGrid:WaitForChild("RightSidebar"):WaitForChild("EventFeedWidget")

local AccountValues = {
	optionPower = AccountInfoWidget:WaitForChild("OptionPowerRow"):WaitForChild("ValueText"),
	netLiquidity = AccountInfoWidget:WaitForChild("NetLiquidityRow"):WaitForChild("ValueText"),
	cash = AccountInfoWidget:WaitForChild("CashSweepRow"):WaitForChild("ValueText"),
	availableFunds = AccountInfoWidget:WaitForChild("AvailableFundsRow"):WaitForChild("ValueText"),
}

-- Layout Constants
local PADDING = 12
local TITLE_HEIGHT = 22
local LINE_HEIGHT = 18
local ROW_HEIGHT = 30
local TRADER_ROW_HEIGHT = 36
local TRADER_AVATAR_SIZE = 24
local LINK_HEIGHT = 24
local PERFORMANCE_CHART_HEIGHT = 110
local MAX_OPEN_ORDER_LINES = 4
local MAX_FILL_LINES = 5
local MAX_TRADERS = 10
local HEAT_FULL_MOVE = 3 -- a move this many percent gets the strongest tint
local PERFORMANCE_RANGE = "7d"

local REFRESH_INTERVAL = 60

local UP_HEX = Theme.Colors.Up:ToHex()
local DOWN_HEX = Theme.Colors.Down:ToHex()

-- State
local isRefreshing = false
local isRefreshQueued = false
local performanceHistory = nil
local lastOrders = {} -- from the last refresh, so Available Funds stays right between refreshes
local marketView = "Overview" -- or a movers list: "gainers", "losers", "active"
local lastOverview = nil
local lastMovers = nil

local makeFrame = UIKit.makeFrame
local makeLabel = UIKit.makeLabel

-- Formatting
local function formatSignedMoney(amount)
	return (amount >= 0 and "+" or "-") .. NumberModule.format(math.abs(amount))
end

local function getChangeColor(amount)
	if amount > 0 then
		return Theme.Colors.Up
	elseif amount < 0 then
		return Theme.Colors.Down
	end

	return Theme.Colors.Text
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

local function sideText(side)
	return string.format('<font color="#%s">%s</font>', side == "Buy" and UP_HEX or DOWN_HEX, side)
end

-- Builders
-- A title in an empty Studio widget and the content frame under it
local function buildWidget(widget, title)
	local titleLabel = makeLabel("Title", widget, Theme.Fonts.UISemibold, Theme.TextSize.Title, Theme.Colors.Text)
	titleLabel.Position = UDim2.fromOffset(PADDING, PADDING)
	titleLabel.Size = UDim2.new(1, -PADDING * 2, 0, TITLE_HEIGHT)
	titleLabel.Text = title

	local content = makeFrame("Content", widget)
	content.Position = UDim2.fromOffset(PADDING, PADDING + TITLE_HEIGHT + 8)
	content.Size = UDim2.new(1, -PADDING * 2, 1, -(PADDING * 2 + TITLE_HEIGHT + 8))

	return content
end

local function makeList(name, parent)
	local list = makeFrame(name, parent)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = list

	return list
end

local function clearList(list)
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A small text button that jumps to another tab
local function makeLink(name, parent, text, tabName)
	local link = Instance.new("TextButton")
	link.Name = name
	link.AnchorPoint = Vector2.new(0, 1)
	link.Position = UDim2.fromScale(0, 1)
	link.Size = UDim2.new(1, 0, 0, LINK_HEIGHT)
	link.BackgroundTransparency = 1
	link.BorderSizePixel = 0
	link.FontFace = Theme.Fonts.UISemibold
	link.TextSize = Theme.TextSize.Caption
	link.TextColor3 = Theme.Colors.Accent
	link.TextXAlignment = Enum.TextXAlignment.Left
	link.Text = text
	link.Parent = parent

	link.MouseButton1Click:Connect(function()
		Navigation.openTab(tabName)
	end)

	return link
end

local function addLine(list, index, richText, color)
	local line = makeLabel("Line_" .. index, list, Theme.Fonts.Mono, Theme.TextSize.Caption, color or Theme.Colors.Text)
	line.LayoutOrder = index
	line.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)
	line.RichText = true
	line.Text = richText

	return line
end

-- Watchlist (Studio title row; the list goes under it in the widget's layout)
local WatchlistList = Instance.new("ScrollingFrame")
WatchlistList.Name = "List"
WatchlistList.LayoutOrder = 1
WatchlistList.Size = UDim2.new(1, 0, 0.9, 15) -- the 90% the title row leaves, plus its -16 offset
WatchlistList.BackgroundTransparency = 1
WatchlistList.BorderSizePixel = 0
WatchlistList.ScrollBarThickness = 4
WatchlistList.ScrollBarImageColor3 = Theme.Colors.TextDisabled
WatchlistList.ScrollingDirection = Enum.ScrollingDirection.Y
WatchlistList.CanvasSize = UDim2.new()
WatchlistList.AutomaticCanvasSize = Enum.AutomaticSize.Y
WatchlistList.Parent = WatchlistWidget

local WatchlistListLayout = Instance.new("UIListLayout")
WatchlistListLayout.SortOrder = Enum.SortOrder.LayoutOrder
WatchlistListLayout.Parent = WatchlistList

-- Orders
local OrdersContent = buildWidget(OrderStatusWidget, "Orders")

local OpenOrdersColumn = makeFrame("OpenOrders", OrdersContent)
OpenOrdersColumn.Size = UDim2.new(0.5, -PADDING / 2, 1, -LINK_HEIGHT)

local OpenOrdersCaption = makeLabel("Caption", OpenOrdersColumn, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
OpenOrdersCaption.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)

local OpenOrdersList = makeList("List", OpenOrdersColumn)
OpenOrdersList.Position = UDim2.fromOffset(0, LINE_HEIGHT + 4)
OpenOrdersList.Size = UDim2.new(1, 0, 1, -(LINE_HEIGHT + 4))

local FillsColumn = makeFrame("RecentFills", OrdersContent)
FillsColumn.AnchorPoint = Vector2.new(1, 0)
FillsColumn.Position = UDim2.fromScale(1, 0)
FillsColumn.Size = UDim2.new(0.5, -PADDING / 2, 1, -LINK_HEIGHT)

local FillsCaption = makeLabel("Caption", FillsColumn, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
FillsCaption.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)
FillsCaption.Text = "Recent fills"

local FillsList = makeList("List", FillsColumn)
FillsList.Position = UDim2.fromOffset(0, LINE_HEIGHT + 4)
FillsList.Size = UDim2.new(1, 0, 1, -(LINE_HEIGHT + 4))

makeLink("PortfolioLink", OrdersContent, "Manage orders on the Portfolio tab →", "Portfolio")

-- Performance
local PerformanceContent = buildWidget(PLWidget, "Performance")

local PerformanceValue =
	makeLabel("NetWorth", PerformanceContent, Theme.Fonts.MonoBold, Theme.TextSize.Display, Theme.Colors.Text)
PerformanceValue.Size = UDim2.new(1, 0, 0, 28)
PerformanceValue.TextScaled = true

local PerformanceValueSize = Instance.new("UITextSizeConstraint")
PerformanceValueSize.MaxTextSize = Theme.TextSize.Display
PerformanceValueSize.Parent = PerformanceValue

local PerformanceReturn = makeLabel("Return", PerformanceContent, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.TextMuted)
PerformanceReturn.Position = UDim2.fromOffset(0, 30)
PerformanceReturn.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)
PerformanceReturn.RichText = true

local PerformanceChart = makeFrame("Chart", PerformanceContent)
PerformanceChart.Position = UDim2.fromOffset(0, 54)
PerformanceChart.Size = UDim2.new(1, 0, 0, PERFORMANCE_CHART_HEIGHT)

local PerformanceStats = makeList("Stats", PerformanceContent)
PerformanceStats.Position = UDim2.fromOffset(0, 54 + PERFORMANCE_CHART_HEIGHT + 8)
PerformanceStats.Size = UDim2.new(1, 0, 1, -(54 + PERFORMANCE_CHART_HEIGHT + 8))

local performanceStatValues = {}

for index, stat in ipairs({ { "dayPL", "Day P/L" }, { "unrealizedPL", "Unrealized P/L" }, { "realizedPL", "Realized P/L" } }) do
	local row = makeFrame("Stat_" .. stat[1], PerformanceStats)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, 0, 0, 22)

	local caption = makeLabel("Caption", row, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	caption.Size = UDim2.fromScale(0.5, 1)
	caption.Text = stat[2]

	local value = makeLabel("Value", row, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.Text)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.Size = UDim2.fromScale(0.5, 1)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Text = "—"

	performanceStatValues[stat[1]] = value
end

-- Market overview
local MarketContent = buildWidget(HeatmapWidget, "Market overview")

local MarketGrid = makeFrame("Grid", MarketContent)
MarketGrid.Size = UDim2.new(1, 0, 1, -LINE_HEIGHT)

local MarketGridLayout = Instance.new("UIGridLayout")
MarketGridLayout.CellSize = UDim2.new(1 / 3, -6, 0.5, -4)
MarketGridLayout.CellPadding = UDim2.fromOffset(8, 8)
MarketGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
MarketGridLayout.Parent = MarketGrid

-- Today's movers, in place of the tiles when a movers pill is picked
local MoversList = makeList("Movers", MarketContent)
MoversList.Size = UDim2.new(1, 0, 1, -LINE_HEIGHT)
MoversList.Visible = false

local MARKET_VIEWS = {
	{ id = "Overview", label = "Overview" },
	{ id = "gainers", label = "Gainers" },
	{ id = "losers", label = "Losers" },
	{ id = "active", label = "Active" },
}

-- Pills on the right of the widget's title row
local MarketViewPills = makeFrame("Views", HeatmapWidget)
MarketViewPills.AnchorPoint = Vector2.new(1, 0)
MarketViewPills.Position = UDim2.new(1, -PADDING, 0, PADDING)
MarketViewPills.Size = UDim2.new(0.7, 0, 0, TITLE_HEIGHT)

local MarketViewPillsLayout = Instance.new("UIListLayout")
MarketViewPillsLayout.FillDirection = Enum.FillDirection.Horizontal
MarketViewPillsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
MarketViewPillsLayout.SortOrder = Enum.SortOrder.LayoutOrder
MarketViewPillsLayout.Padding = UDim.new(0, 4)
MarketViewPillsLayout.Parent = MarketViewPills

local marketViewPills = {} -- [view id] = { button, stroke }

for index, view in ipairs(MARKET_VIEWS) do
	local pill = Instance.new("TextButton")
	pill.Name = view.id
	pill.LayoutOrder = index
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromScale(0, 1)
	pill.AutoButtonColor = false
	pill.BorderSizePixel = 0
	pill.BackgroundColor3 = Theme.Colors.Raised
	pill.FontFace = Theme.Fonts.UISemibold
	pill.TextSize = Theme.TextSize.Caption
	pill.Text = view.label
	pill.Parent = MarketViewPills
	UIKit.addCorner(pill)

	local pillPadding = Instance.new("UIPadding")
	pillPadding.PaddingLeft = UDim.new(0, 8)
	pillPadding.PaddingRight = UDim.new(0, 8)
	pillPadding.Parent = pill

	marketViewPills[view.id] = { button = pill, stroke = UIKit.addStroke(pill) }
end

local MarketUpdated = makeLabel("Updated", MarketContent, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
MarketUpdated.AnchorPoint = Vector2.new(0, 1)
MarketUpdated.Position = UDim2.fromScale(0, 1)
MarketUpdated.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)

-- Top traders
local TradersContent = buildWidget(EventFeedWidget, "Top traders")

local TradersList = makeList("List", TradersContent)
TradersList.Size = UDim2.new(1, 0, 1, -LINK_HEIGHT)

makeLink("LeaderboardsLink", TradersContent, "Full leaderboards →", "Leaderboards")

-- Rendering
-- Called with fresh data on a refresh, and with nothing when an attribute
-- changes in between, which reuses the last orders
local function renderAccountInfo(summary, orders)
	lastOrders = orders or lastOrders

	local cash = Player:GetAttribute("Balance") or (summary and summary.balance)
	local netWorth = Player:GetAttribute("NetWorth") or (summary and summary.netWorth)

	AccountValues.netLiquidity.Text = netWorth and NumberModule.format(netWorth) or "—"
	AccountValues.cash.Text = cash and NumberModule.format(cash) or "—"

	if Progression.isUnlocked(Player:GetAttribute("Level") or 1, "Options") then
		AccountValues.optionPower.Text = cash and NumberModule.format(cash) or "—"
		AccountValues.optionPower.TextColor3 = Theme.Colors.Text
	else
		AccountValues.optionPower.Text = "Lv " .. Progression.FEATURES.Options
		AccountValues.optionPower.TextColor3 = Theme.Colors.TextDisabled
	end

	-- Cash already promised to open buy limits isn't available for new orders
	local committed = 0

	for _, order in ipairs(lastOrders) do
		if order.side == "Buy" then
			committed += order.quantity * order.limitPrice
		end
	end

	AccountValues.availableFunds.Text = cash and NumberModule.format(math.max(cash - committed, 0)) or "—"
end

local function renderWatchlist(rows)
	clearList(WatchlistList)

	if #rows == 0 then
		local empty = makeLabel("Empty", WatchlistList, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.TextWrapped = true
		empty.Text = "Add tickers from the watchlist on the Charts screen."

		local inset = Instance.new("UIPadding")
		inset.PaddingLeft = UDim.new(0, 8)
		inset.PaddingRight = UDim.new(0, 8)
		inset.Parent = empty

		return
	end

	for index, entry in ipairs(rows) do
		local row = Instance.new("TextButton")
		row.Name = "Row_" .. entry.ticker
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.AutoButtonColor = false
		row.BorderSizePixel = 0
		row.BackgroundColor3 = Theme.Colors.Raised
		row.BackgroundTransparency = 1
		row.Text = ""
		row.Parent = WatchlistList

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.Parent = row

		local ticker = makeLabel("Ticker", row, Theme.Fonts.UISemibold, Theme.TextSize.Body, Theme.Colors.Text)
		ticker.Size = UDim2.fromScale(0.4, 1)
		ticker.Text = entry.ticker

		local price = makeLabel("Price", row, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.Text)
		price.Position = UDim2.fromScale(0.4, 0)
		price.Size = UDim2.fromScale(0.35, 1)
		price.TextXAlignment = Enum.TextXAlignment.Right
		price.Text = entry.price and NumberModule.format(entry.price) or "—"

		local change = makeLabel("Change", row, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.TextMuted)
		change.AnchorPoint = Vector2.new(1, 0)
		change.Position = UDim2.fromScale(1, 0)
		change.Size = UDim2.fromScale(0.25, 1)
		change.TextXAlignment = Enum.TextXAlignment.Right

		if entry.changePct then
			change.Text = string.format("%+.2f%%", entry.changePct)
			change.TextColor3 = getChangeColor(entry.changePct)
		else
			change.Text = "—"
		end

		row.MouseEnter:Connect(function()
			row.BackgroundTransparency = 0
		end)

		row.MouseLeave:Connect(function()
			row.BackgroundTransparency = 1
		end)

		row.MouseButton1Click:Connect(function()
			Navigation.openTicker(entry.ticker)
		end)
	end
end

local function renderOrders(orders, fills)
	clearList(OpenOrdersList)
	clearList(FillsList)

	OpenOrdersCaption.Text = "Open limit orders · " .. #orders

	if #orders == 0 then
		addLine(OpenOrdersList, 1, "None open", Theme.Colors.TextMuted)
	end

	for index = 1, math.min(#orders, MAX_OPEN_ORDER_LINES) do
		local order = orders[index]

		addLine(
			OpenOrdersList,
			index,
			string.format("%s %d %s @ %s", sideText(order.side), order.quantity, order.ticker, NumberModule.format(order.limitPrice))
		)
	end

	if #orders > MAX_OPEN_ORDER_LINES then
		addLine(OpenOrdersList, MAX_OPEN_ORDER_LINES + 1, string.format("+%d more", #orders - MAX_OPEN_ORDER_LINES), Theme.Colors.TextMuted)
	end

	if #fills == 0 then
		addLine(FillsList, 1, "No trades yet", Theme.Colors.TextMuted)
	end

	for index = 1, math.min(#fills, MAX_FILL_LINES) do
		local fill = fills[index]
		local realized = fill.realizedPL
				and string.format(' <font color="#%s">%s</font>', fill.realizedPL >= 0 and UP_HEX or DOWN_HEX, formatSignedMoney(fill.realizedPL))
			or ""

		addLine(
			FillsList,
			index,
			string.format(
				"%s %d %s%s @ %s%s · %s",
				fill.settlement and string.lower(fill.settlement) or sideText(fill.side),
				fill.quantity,
				fill.ticker,
				fill.contract and " opt" or "",
				NumberModule.format(fill.price),
				realized,
				formatAge(os.time() - fill.time)
			)
		)
	end
end

local function renderPerformanceChart()
	PerformanceChart:ClearAllChildren()

	if performanceHistory and #performanceHistory > 0 then
		LineChart.draw(
			PerformanceChart,
			LineChart.layout(performanceHistory),
			LineChart.getColor(performanceHistory),
			Theme.Colors.Panel,
			2
		)
	end
end

local function setMoneyStat(key, amount)
	local label = performanceStatValues[key]

	label.Text = amount and formatSignedMoney(amount) or "—"
	label.TextColor3 = amount and getChangeColor(amount) or Theme.Colors.TextMuted
end

local function renderPerformance(summary, sharePositions)
	local netWorth = summary.netWorth
	local totalReturn = (netWorth - Economy.STARTING_BALANCE) / Economy.STARTING_BALANCE
	local dayPL, unrealizedPL = 0, 0

	for _, position in ipairs(sharePositions) do
		dayPL += position.plDay or 0
		unrealizedPL += position.plOpen or 0
	end

	for _, position in ipairs(summary.options or {}) do
		unrealizedPL += position.plOpen or 0
	end

	PerformanceValue.Text = NumberModule.format(netWorth)
	PerformanceReturn.Text = string.format(
		'<font color="#%s">%+.2f%%</font> since starting · %s',
		totalReturn >= 0 and UP_HEX or DOWN_HEX,
		totalReturn * 100,
		PERFORMANCE_RANGE
	)

	setMoneyStat("dayPL", dayPL)
	setMoneyStat("unrealizedPL", unrealizedPL)
	setMoneyStat("realizedPL", summary.realizedPL)

	performanceHistory = summary.histories and summary.histories[PERFORMANCE_RANGE]
	renderPerformanceChart()
end

local function renderMarketOverview(overview)
	clearList(MarketGrid)

	for index, quote in ipairs(overview.quotes) do
		local tile = Instance.new("TextButton")
		tile.Name = "Tile_" .. quote.ticker
		tile.LayoutOrder = index
		tile.AutoButtonColor = false
		tile.BorderSizePixel = 0
		tile.Text = ""
		tile.Parent = MarketGrid
		UIKit.addCorner(tile)
		UIKit.addStroke(tile)

		-- Heatmap tint: the bigger the move, the stronger the color
		local pct = quote.changePct or 0
		local strength = math.min(math.abs(pct) / HEAT_FULL_MOVE, 1)

		tile.BackgroundColor3 = Theme.Colors.Raised:Lerp(pct >= 0 and Theme.Colors.Up or Theme.Colors.Down, 0.15 + 0.35 * strength)

		local name = makeLabel("Name", tile, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
		name.Position = UDim2.fromOffset(10, 8)
		name.Size = UDim2.new(1, -20, 0, 16)
		name.Text = quote.name

		local ticker = makeLabel("Ticker", tile, Theme.Fonts.UIBold, Theme.TextSize.Title, Theme.Colors.Text)
		ticker.Position = UDim2.fromOffset(10, 24)
		ticker.Size = UDim2.new(1, -20, 0, 20)
		ticker.Text = quote.ticker

		local price = makeLabel("Price", tile, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.Text)
		price.AnchorPoint = Vector2.new(0, 1)
		price.Position = UDim2.new(0, 10, 1, -26)
		price.Size = UDim2.new(1, -20, 0, 18)
		price.Text = quote.price and NumberModule.format(quote.price) or "—"

		local change = makeLabel("Change", tile, Theme.Fonts.MonoBold, Theme.TextSize.Body, Theme.Colors.Text)
		change.AnchorPoint = Vector2.new(0, 1)
		change.Position = UDim2.new(0, 10, 1, -8)
		change.Size = UDim2.new(1, -20, 0, 18)
		change.Text = quote.changePct and string.format("%+.2f%%", quote.changePct) or "—"

		tile.MouseButton1Click:Connect(function()
			Navigation.openTicker(quote.ticker)
		end)
	end

	MarketUpdated.Text = "Updated " .. os.date("%I:%M %p", overview.updatedAt):gsub("^0", "")
end

local function renderMovers(quotes)
	clearList(MoversList)

	if #quotes == 0 then
		addLine(MoversList, 1, "No movers right now", Theme.Colors.TextMuted)

		return
	end

	for index, quote in ipairs(quotes) do
		local row = Instance.new("TextButton")
		row.Name = "Mover_" .. quote.symbol
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, 24)
		row.AutoButtonColor = false
		row.BorderSizePixel = 0
		row.BackgroundColor3 = Theme.Colors.Raised
		row.BackgroundTransparency = 1
		row.Text = ""
		row.Parent = MoversList

		local symbol = makeLabel("Symbol", row, Theme.Fonts.UISemibold, Theme.TextSize.Body, Theme.Colors.Text)
		symbol.Size = UDim2.new(0, 70, 1, 0)
		symbol.Text = quote.symbol

		local name = makeLabel("Name", row, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
		name.Position = UDim2.fromOffset(74, 0)
		name.Size = UDim2.new(1, -(74 + 170), 1, 0)
		name.Text = quote.name

		local price = makeLabel("Price", row, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.Text)
		price.AnchorPoint = Vector2.new(1, 0)
		price.Position = UDim2.new(1, -74, 0, 0)
		price.Size = UDim2.new(0, 90, 1, 0)
		price.TextXAlignment = Enum.TextXAlignment.Right
		price.Text = NumberModule.format(quote.price)

		local change = makeLabel("Change", row, Theme.Fonts.MonoBold, Theme.TextSize.Body, Theme.Colors.Text)
		change.AnchorPoint = Vector2.new(1, 0)
		change.Position = UDim2.fromScale(1, 0)
		change.Size = UDim2.new(0, 70, 1, 0)
		change.TextXAlignment = Enum.TextXAlignment.Right
		change.Text = quote.changePercent and string.format("%+.2f%%", quote.changePercent) or "—"
		change.TextColor3 = quote.changePercent and getChangeColor(quote.changePercent) or Theme.Colors.TextMuted

		row.MouseEnter:Connect(function()
			row.BackgroundTransparency = 0
		end)

		row.MouseLeave:Connect(function()
			row.BackgroundTransparency = 1
		end)

		row.MouseButton1Click:Connect(function()
			Navigation.openTicker(quote.symbol)
		end)
	end
end

-- Draws whichever view is picked from the data already fetched
local function renderMarket()
	local isOverview = marketView == "Overview"

	for viewId, pill in pairs(marketViewPills) do
		local isActive = viewId == marketView

		pill.button.BackgroundTransparency = isActive and 0 or 1
		pill.button.TextColor3 = isActive and Theme.Colors.Text or Theme.Colors.TextMuted
		pill.stroke.Enabled = isActive
	end

	MarketGrid.Visible = isOverview
	MoversList.Visible = not isOverview

	if isOverview and lastOverview then
		renderMarketOverview(lastOverview)
	elseif not isOverview then
		if lastMovers then
			renderMovers(lastMovers[marketView] or {})
		else
			clearList(MoversList)
			addLine(MoversList, 1, "Movers unavailable right now", Theme.Colors.TextMuted)
		end
	end
end

local function renderTopTraders(page)
	clearList(TradersList)

	if #page.entries == 0 then
		addLine(TradersList, 1, "No one is ranked yet", Theme.Colors.TextMuted)

		return
	end

	for index = 1, math.min(#page.entries, MAX_TRADERS) do
		local entry = page.entries[index]
		local isYou = entry.userId == Player.UserId

		local row = makeFrame("Trader_" .. entry.rank, TradersList)
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, TRADER_ROW_HEIGHT)

		local rank = makeLabel("Rank", row, Theme.Fonts.MonoBold, Theme.TextSize.Caption, Theme.Colors.TextMuted)
		rank.Size = UDim2.new(0, 22, 1, 0)
		rank.Text = tostring(entry.rank)

		local avatar = UIKit.makeAvatar("Avatar", row, entry.userId, TRADER_AVATAR_SIZE)
		avatar.AnchorPoint = Vector2.new(0, 0.5)
		avatar.Position = UDim2.new(0, 22, 0.5, 0)

		local name = makeLabel(
			"DisplayName",
			row,
			Theme.Fonts.UISemibold,
			Theme.TextSize.Body,
			isYou and Theme.Colors.Accent or Theme.Colors.Text
		)
		name.Position = UDim2.fromOffset(22 + TRADER_AVATAR_SIZE + 8, 0)
		name.Size = UDim2.new(1, -(22 + TRADER_AVATAR_SIZE + 8 + 100), 1, 0)
		name.Text = entry.displayName

		local value = makeLabel("Value", row, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.Text)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.fromScale(1, 0)
		value.Size = UDim2.new(0, 100, 1, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.Text = NumberModule.formatCompact(entry.score)
	end
end

-- Refresh
local function invoke(remote, ...)
	local success, result = pcall(remote.InvokeServer, remote, ...)

	if not success then
		warn("[DashboardController] " .. remote.Name .. " failed: " .. tostring(result))

		return nil
	end

	return result
end

-- Every widget's data in parallel; calls made mid-refresh collapse into one
-- follow-up
local function refresh()
	if isRefreshing then
		isRefreshQueued = true

		return
	end

	isRefreshing = true

	local results = {}
	local calls = {
		summary = { GetPortfolioEvent },
		sharePositions = { GetPositionsEvent },
		orders = { GetOrdersEvent },
		watchlist = { GetWatchlistEvent },
		overview = { GetMarketOverviewEvent },
		movers = { GetMarketMoversEvent },
		traders = { GetLeaderboardEvent, "NetWorth" },
	}
	local pending = 0

	for key, call in pairs(calls) do
		pending += 1

		task.spawn(function()
			results[key] = invoke(table.unpack(call))
			pending -= 1
		end)
	end

	while pending > 0 do
		task.wait()
	end

	renderAccountInfo(results.summary, results.orders)

	if results.watchlist then
		renderWatchlist(results.watchlist)
	end

	if results.orders and results.summary then
		renderOrders(results.orders, results.summary.recentFills or {})
	end

	if results.summary and results.sharePositions then
		renderPerformance(results.summary, results.sharePositions)
	end

	if results.overview then
		lastOverview = results.overview
	end

	if results.movers then
		lastMovers = results.movers
	end

	renderMarket()

	if results.traders then
		renderTopTraders(results.traders)
	end

	isRefreshing = false

	if isRefreshQueued then
		isRefreshQueued = false
		refresh()
	end
end

-- Connections
for viewId, pill in pairs(marketViewPills) do
	pill.button.MouseButton1Click:Connect(function()
		marketView = viewId
		renderMarket()
	end)
end

DashboardScreen:GetPropertyChangedSignal("Visible"):Connect(function()
	if DashboardScreen.Visible then
		refresh()
	end
end)

-- Balance moves on every trade; limit fills can land while the Dashboard is up
for _, signal in ipairs({ Player:GetAttributeChangedSignal("Balance"), OrderUpdateEvent.OnClientEvent }) do
	signal:Connect(function()
		if DashboardScreen.Visible then
			refresh()
		end
	end)
end

Player:GetAttributeChangedSignal("NetWorth"):Connect(function()
	renderAccountInfo(nil, nil)
end)

Player:GetAttributeChangedSignal("Level"):Connect(function()
	renderAccountInfo(nil, nil)
end)

-- Segment lengths are in pixels, so a resize needs a redraw
PerformanceChart:GetPropertyChangedSignal("AbsoluteSize"):Connect(renderPerformanceChart)

task.spawn(function()
	while true do
		task.wait(REFRESH_INTERVAL)

		if DashboardScreen.Visible then
			refresh()
		end
	end
end)

-- The Dashboard is the tab the game opens on
if DashboardScreen.Visible then
	task.spawn(refresh)
end
