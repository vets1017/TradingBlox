-- Services
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Modules
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local ChartRenderer = require(ReplicatedStorage.Modules.Multi.ChartRenderer)
local DrawingModule = require(ReplicatedStorage.Modules.Multi.DrawingModule)
local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)
local Progression = require(ReplicatedStorage.Config.Progression)

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local RequestChartEvent = EventsFolder:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = EventsFolder:WaitForChild("GetMarketDataEvent")
local PlayerOrderEvent = EventsFolder:WaitForChild("PlayerOrderEvent")
local GetPositionsEvent = EventsFolder:WaitForChild("GetPositionsEvent")
local GetWatchlistEvent = EventsFolder:WaitForChild("GetWatchlistEvent")
local ToggleWatchlistEvent = EventsFolder:WaitForChild("ToggleWatchlistEvent")

-- UI Instances
local PlayerGui = Player:WaitForChild("PlayerGui")
local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local MainBackground = TerminalGui:WaitForChild("MainBackground")
local TopBar = MainBackground:WaitForChild("TopBar")
local AccentLine = TopBar:WaitForChild("AccentLine")
local AccentGradient = AccentLine:WaitForChild("AccentGradient")
local TabContainer = TopBar:WaitForChild("TabContainer")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")
local DashboardScreen = ScreenContainer:WaitForChild("DashboardScreen")
local GreetingBar = DashboardScreen:WaitForChild("GreetingBar")
local GreetingText = GreetingBar:WaitForChild("GreetingText")
local DateText = GreetingBar:WaitForChild("DateText")
local DashboardGrid = DashboardScreen:WaitForChild("DashboardGrid")
local RightSidebar = DashboardGrid:WaitForChild("RightSidebar")
local MainWorkspace = DashboardGrid:WaitForChild("MainWorkspace")
local BottomRow = MainWorkspace:WaitForChild("BottomRow")
local TopRow = MainWorkspace:WaitForChild("TopRow")
local CountdownWidget = TopRow:WaitForChild("CountdownWidget")
local TimeContainer = CountdownWidget:WaitForChild("TimeContainer")
local TitleText = CountdownWidget:WaitForChild("TitleText")
local HoursNumber = TimeContainer.HoursBlock.Number
local MinutesNumber = TimeContainer.MinutesBlock.Number
local SecondsNumber = TimeContainer.SecondsBlock.Number
local ChartsScreen = ScreenContainer:WaitForChild("ChartsScreen")
local ActiveTraderPanel = ChartsScreen:WaitForChild("ActiveTraderPanel")
local ActiveTraderTopBar = ActiveTraderPanel:WaitForChild("ActiveTraderTopBar")
local ActiveTraderContentArea = ActiveTraderPanel:WaitForChild("ContentArea")
local ActiveTraderTickerLabel = ActiveTraderContentArea:WaitForChild("TickerLabel")
local ActiveTraderAskPriceLabel = ActiveTraderContentArea:WaitForChild("BuyHeaderRow"):WaitForChild("AskPriceLabel")
local ActiveTraderPositionLabel = ActiveTraderContentArea:WaitForChild("SellHeaderRow"):WaitForChild("PositionLabel")
local ActiveTraderBuyPresetsGrid = ActiveTraderContentArea:WaitForChild("BuyPresetsGrid")
local ActiveTraderSellPresetsGrid = ActiveTraderContentArea:WaitForChild("SellPresetsGrid")
local ActiveTraderStatusLabel = ActiveTraderContentArea:WaitForChild("StatusLabel")

local ActiveTraderBuyPresets = {
	{ button = ActiveTraderBuyPresetsGrid:WaitForChild("BuyPreset_100"), amount = 100 },
	{ button = ActiveTraderBuyPresetsGrid:WaitForChild("BuyPreset_250"), amount = 250 },
	{ button = ActiveTraderBuyPresetsGrid:WaitForChild("BuyPreset_500"), amount = 500 },
	{ button = ActiveTraderBuyPresetsGrid:WaitForChild("BuyPreset_1000"), amount = 1000 },
}

local ActiveTraderSellPresets = {
	{ button = ActiveTraderSellPresetsGrid:WaitForChild("SellPreset_25"), fraction = 0.25 },
	{ button = ActiveTraderSellPresetsGrid:WaitForChild("SellPreset_50"), fraction = 0.5 },
	{ button = ActiveTraderSellPresetsGrid:WaitForChild("SellPreset_75"), fraction = 0.75 },
	{ button = ActiveTraderSellPresetsGrid:WaitForChild("SellPreset_100"), fraction = 1 },
}
local Sidebar = ChartsScreen:WaitForChild("Sidebar")
local ToggleActiveTraderButton = Sidebar:WaitForChild("ToggleActiveTraderButton")
local ToggleSymbolInfoButton = Sidebar:WaitForChild("ToggleSymbolInfoButton")
local SymbolInfoPanel = ChartsScreen:WaitForChild("SymbolInfoPanel")
local SymbolInfoTopBar = SymbolInfoPanel:WaitForChild("SymbolInfoTopBar")
local SymbolInfoTickerLabel = SymbolInfoTopBar:WaitForChild("TickerNameLabel")
local SymbolInfoContentArea = SymbolInfoPanel:WaitForChild("ContentArea")

local SymbolInfoFields = {
	MarketCap = SymbolInfoContentArea:WaitForChild("MarketCapRow"):WaitForChild("Value"),
	PE = SymbolInfoContentArea:WaitForChild("PERow"):WaitForChild("Value"),
	EPS = SymbolInfoContentArea:WaitForChild("EPSRow"):WaitForChild("Value"),
	DayRange = SymbolInfoContentArea:WaitForChild("DayRangeRow"):WaitForChild("Value"),
	FiftyTwoWeekRange = SymbolInfoContentArea:WaitForChild("FiftyTwoWeekRangeRow"):WaitForChild("Value"),
	Volume = SymbolInfoContentArea:WaitForChild("VolumeRow"):WaitForChild("Value"),
	AvgVolume = SymbolInfoContentArea:WaitForChild("AvgVolumeRow"):WaitForChild("Value"),
	Beta = SymbolInfoContentArea:WaitForChild("BetaRow"):WaitForChild("Value"),
	DividendYield = SymbolInfoContentArea:WaitForChild("DividendYieldRow"):WaitForChild("Value"),
}

local ToggleWatchlistButton = Sidebar:WaitForChild("ToggleWatchlistButton")
local WatchlistPanel = ChartsScreen:WaitForChild("WatchlistPanel")
local WatchlistTopBar = WatchlistPanel:WaitForChild("WatchlistTopBar")
local AddTickerRow = WatchlistPanel:WaitForChild("AddTickerRow")
local AddTickerInput = AddTickerRow:WaitForChild("AddTickerInput")
local AddTickerButton = AddTickerRow:WaitForChild("AddTickerButton")
local WatchlistListContainer = WatchlistPanel:WaitForChild("ListContainer")
local WatchlistEmptyLabel = WatchlistListContainer:WaitForChild("EmptyLabel")
local WatchlistRowTemplate = WatchlistListContainer:WaitForChild("RowTemplate")

local MainChart = ChartsScreen:WaitForChild("MainChart")
local BottomAxis = MainChart:WaitForChild("BottomAxis")
local ChartCanvas = MainChart:WaitForChild("ChartCanvas")
local RightAxis = MainChart:WaitForChild("RightAxis")
local LeftToolbar = MainChart:WaitForChild("LeftToolbar")
local TopToolbar = MainChart:WaitForChild("TopToolbar")
local CrosshairX = ChartCanvas:WaitForChild("CrosshairX")
local CrosshairY = ChartCanvas:WaitForChild("CrosshairY")
local HoverPriceTag = RightAxis:WaitForChild("HoverPriceTag")
local HoverTimeTag = ChartCanvas:WaitForChild("HoverTimeTag")
local TickerInputBox = TopToolbar:WaitForChild("TickerInputBox")
local TickerInput = TickerInputBox:WaitForChild("TickerInput")
local ChartLegend = ChartCanvas:WaitForChild("ChartLegend")
local ChartTickerLabel = ChartLegend:WaitForChild("ChartTickerLabel")
local TimeframeDropdown = TopToolbar:WaitForChild("TimeframeDropdown")
local TimeDropdownList = TimeframeDropdown:WaitForChild("TimeDropdownList")
local MainTimeframeButton = TimeframeDropdown:WaitForChild("MainTimeframeButton")
local IndicatorsContainer = ChartCanvas:WaitForChild("IndicatorsContainer")
local IndicatorsDropdown = TopToolbar:WaitForChild("IndicatorsDropdown")
local IndicatorsDropdownList = IndicatorsDropdown:WaitForChild("IndicatorsDropdownList")
local MainIndicatorsButton = IndicatorsDropdown:WaitForChild("MainIndicatorsButton")
local ScrollTrack = ChartCanvas:WaitForChild("ScrollTrack")
local ScrollThumb = ScrollTrack:WaitForChild("ScrollThumb")
local CandlesContainer = ChartCanvas:WaitForChild("CandlesContainer")
local GridContainer = ChartCanvas:WaitForChild("GridContainer")
local DrawingsContainer = ChartCanvas:WaitForChild("DrawingsContainer")
local CursorToolButton = LeftToolbar:WaitForChild("CursorToolButton")
local TrendLineToolButton = LeftToolbar:WaitForChild("TrendLineToolButton")
local HorizontalLineToolButton = LeftToolbar:WaitForChild("HorizontalLineToolButton")
local ClearDrawingsButton = LeftToolbar:WaitForChild("ClearDrawingsButton")

-- Tween Constants
local SWEEP_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_EASING = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Position Constants
local HIDDEN_POSITION = UDim2.new(1, 300, 0.5, 0)
local VISIBLE_POSITION = UDim2.new(1, -50, 0.5, 0)

-- Theme Colors (names kept from the pre-theme constants so call sites stay put)
local GREEN = Theme.Colors.Up
local RED = Theme.Colors.Down
local GRAY = Theme.Colors.TextMuted

local COLOR_ACTIVE_BACKGROUND = Theme.Colors.Accent
local COLOR_ACTIVE_TEXT = Theme.Colors.Background -- white on the violet fill is under 3:1
local COLOR_INACTIVE_BACKGROUND = Theme.Colors.Raised
local COLOR_INACTIVE_TEXT = Theme.Colors.TextMuted

-- UI Dragging variables
local dragging = false
local dragInput = nil
local dragStart = nil
local startPosition = nil
local draggedPanel = nil

-- Variables
local currentMaxPrice
local currentMinPrice
local visibleCandles = 60 -- How much candles should be rendered
local rightOffset = 0 -- UI Offset for graph
local lastMouseDragX
local currentDisplayedTicker = ""
local currentTimeframe = "H" -- Default Timeframe
local activeTraderAsk = nil
local activeTraderPositionQty = 0
local scrollDragStartX = 0
local startRightOffset = 0 -- UI Offset for Scroll

-- Booleans
local isFetchingData = false
local isHoveringChart = false
local isActiveTradeVisible = false
local isSymbolInfoVisible = false
local isWatchlistVisible = false
local isCrosshairActive = true
local isDropdownOpen = false
local isIndicatorsDropdownOpen = false
local isDraggingChart = false
local isDraggingScroll = false

local currentChartData = {} -- Data of current chart
local masterChartData = {}
local viewportUpdateScheduled = false

-- Drawing tools (session-only, per ticker; not persisted to DataStore)
local currentDrawingTool = "cursor" -- "cursor" | "trendline" | "horizontal"
local pendingTrendLineStart = nil -- { timestamp, price } while placing a trend line's 2nd point
local drawingsByTicker = {} -- [ticker] = { horizontalLines = {}, trendLines = {} }

local TIMEFRAME_SECONDS = {
	M = 60,
	["5M"] = 300,
	["30M"] = 1800,
	H = 3600,
	D = 86400,
}

local function getTimeframeStep(timeframe)
	return TIMEFRAME_SECONDS[timeframe] or 60
end

local Tabs = {
	Dashboard = {
		Button = TabContainer:WaitForChild("DashboardButton"),
		Frame = ScreenContainer:WaitForChild("DashboardScreen"),
	},
	Portfolio = {
		Button = TabContainer:WaitForChild("PortfolioButton"),
		Frame = ScreenContainer:WaitForChild("PortfolioScreen"),
	},
	Trade = {
		Button = TabContainer:WaitForChild("TradeButton"),
		Frame = ScreenContainer:WaitForChild("TradeScreen"),
	},
	Charts = {
		Button = TabContainer:WaitForChild("ChartsButton"),
		Frame = ScreenContainer:WaitForChild("ChartsScreen"),
	},
	-- Built in code by ShellController and filled by LeaderboardController
	Leaderboards = {
		Button = TabContainer:WaitForChild("LeaderboardsButton"),
		Frame = ScreenContainer:WaitForChild("LeaderboardsScreen"),
	},
}

local TimeDropdownOptions = {
	[TimeDropdownList:WaitForChild("1MinuteButton")] = { query = "1M" },
	[TimeDropdownList:WaitForChild("5MinuteButton")] = { query = "5M" },
	[TimeDropdownList:WaitForChild("30MinuteButton")] = { query = "30M" },
	[TimeDropdownList:WaitForChild("1HourButton")] = { query = "H" },
	[TimeDropdownList:WaitForChild("1DayButton")] = { query = "D" },
}

-- Moving-average overlay indicators. `active` is toggled by the dropdown;
-- renderChart reads it to decide what to hand ChartRenderer each render.
local IndicatorOptions = {
	[IndicatorsDropdownList:WaitForChild("SMA20Button")] = {
		key = "SMA20",
		type = "sma",
		period = 20,
		color = Color3.fromRGB(255, 170, 0),
		active = false,
	},
	[IndicatorsDropdownList:WaitForChild("SMA50Button")] = {
		key = "SMA50",
		type = "sma",
		period = 50,
		color = Color3.fromRGB(0, 170, 255),
		active = false,
	},
	[IndicatorsDropdownList:WaitForChild("EMA20Button")] = {
		key = "EMA20",
		type = "ema",
		period = 20,
		color = Color3.fromRGB(255, 90, 205),
		active = false,
	},
	[IndicatorsDropdownList:WaitForChild("EMA50Button")] = {
		key = "EMA50",
		type = "ema",
		period = 50,
		color = Color3.fromRGB(220, 222, 230), -- near-white: the old purple was nearly the UI accent
		active = false,
	},
}

-- Unfinished
local function refreshTerminal()
	local marketData = GetMarketDataEvent:InvokeServer()

	if not marketData then
		return
	end
	-- continue after stock-list is done
end

local function getActiveIndicators()
	local activeIndicators = {}

	for _, indicator in pairs(IndicatorOptions) do
		if indicator.active then
			table.insert(activeIndicators, indicator)
		end
	end

	return activeIndicators
end

local function renderChart(ticker, chartData)
	local liveCandle = #masterChartData > 0 and masterChartData[#masterChartData] or nil

	local minPrice, maxPrice = ChartRenderer.render({
		ChartTickerLabel = ChartTickerLabel,
		CandlesContainer = CandlesContainer,
		GridContainer = GridContainer,
		IndicatorsContainer = IndicatorsContainer,
		RightAxis = RightAxis,
		BottomAxis = BottomAxis,
		MainChart = MainChart,
	}, ticker, chartData, currentTimeframe, liveCandle, getActiveIndicators())

	if minPrice and maxPrice then
		currentMinPrice = minPrice
		currentMaxPrice = maxPrice

		DrawingModule.render({
			DrawingsContainer = DrawingsContainer,
			MainChart = MainChart,
		}, chartData, minPrice, maxPrice, drawingsByTicker[ticker])
	end
end

local DRAWING_TOOL_BUTTONS = {
	cursor = CursorToolButton,
	trendline = TrendLineToolButton,
	horizontal = HorizontalLineToolButton,
}

local function setDrawingTool(tool)
	currentDrawingTool = tool
	pendingTrendLineStart = nil

	for toolName, button in pairs(DRAWING_TOOL_BUTTONS) do
		local isActive = toolName == tool

		button.BackgroundColor3 = isActive and COLOR_ACTIVE_BACKGROUND or COLOR_INACTIVE_BACKGROUND
		button.TextColor3 = isActive and COLOR_ACTIVE_TEXT or COLOR_INACTIVE_TEXT
	end
end

local function getTickerDrawings(ticker)
	drawingsByTicker[ticker] = drawingsByTicker[ticker] or { horizontalLines = {}, trendLines = {} }

	return drawingsByTicker[ticker]
end

-- Converts a mouse position over ChartCanvas into a (timestamp, price) point
-- on the currently-rendered candle window, for placing drawings. Uses the
-- same snap-to-candle-index and price-scale math as the crosshair hover.
local function getChartPointFromPosition(mousePosition)
	if #currentChartData == 0 or not currentMinPrice or not currentMaxPrice then
		return nil
	end

	local canvasPosition = ChartCanvas.AbsolutePosition
	local canvasSize = ChartCanvas.AbsoluteSize

	local relativeX = mousePosition.X - canvasPosition.X
	local relativeY = mousePosition.Y - canvasPosition.Y

	if relativeX < 0 or relativeX > canvasSize.X or relativeY < 0 or relativeY > canvasSize.Y then
		return nil
	end

	local percentX = math.clamp(relativeX / canvasSize.X, 0, 1)
	local index = math.clamp(math.ceil(percentX * #currentChartData), 1, #currentChartData)

	local priceRange = currentMaxPrice - currentMinPrice
	local yPercentage = relativeY / canvasSize.Y
	local price = currentMaxPrice - (yPercentage * priceRange)

	local candle = currentChartData[index]

	return { timestamp = candle.Timestamp, price = price }
end

-- Handles a click on ChartCanvas while a drawing tool is active. Returns
-- true if it consumed the click (so the caller skips starting a pan-drag).
local function handleDrawingClick(mousePosition)
	if currentDrawingTool == "cursor" or currentDisplayedTicker == "" then
		return false
	end

	local point = getChartPointFromPosition(mousePosition)

	if not point then
		return false
	end

	local drawings = getTickerDrawings(currentDisplayedTicker)

	if currentDrawingTool == "horizontal" then
		table.insert(drawings.horizontalLines, { price = point.price })
		renderChart(currentDisplayedTicker, currentChartData)

		return true
	end

	if currentDrawingTool == "trendline" then
		if not pendingTrendLineStart then
			pendingTrendLineStart = point
		else
			table.insert(drawings.trendLines, {
				t1 = pendingTrendLineStart.timestamp,
				p1 = pendingTrendLineStart.price,
				t2 = point.timestamp,
				p2 = point.price,
			})
			pendingTrendLineStart = nil
			renderChart(currentDisplayedTicker, currentChartData)
		end

		return true
	end

	return false
end

-- Switching tab function
local function switchTab(tabName)
	for _, data in pairs(Tabs) do
		data.Frame.Visible = false
		data.Button.TextColor3 = COLOR_INACTIVE_TEXT
	end

	if Tabs[tabName] then
		Tabs[tabName].Frame.Visible = true
		Tabs[tabName].Button.TextColor3 = COLOR_ACTIVE_BACKGROUND -- the accent, as text

		AccentGradient.Offset = Vector2.new(-1, 0)

		local sweepTween = TweenService:Create(AccentGradient, SWEEP_INFO, { Offset = Vector2.new(1, 0) })
		sweepTween:Play() -- Gradient effect in TopBar when switching tab
	end
end

-- Changes Greeting Text on Dashboard based on time
local function updateGreeting()
	local timeData = os.date("*t")
	local hour = timeData.hour

	local greeting
	if hour >= 5 and hour < 12 then
		greeting = "Good morning,"
	elseif hour >= 12 and hour < 17 then
		greeting = "Good afternoon,"
	elseif hour >= 17 and hour < 22 then
		greeting = "Good evening,"
	else
		greeting = "Good night,"
	end

	local formattedDate = os.date("%A, %d %B %Y")

	GreetingText.Text = string.format("%s %s.", greeting, Player.DisplayName) -- Player.Name might be changed to a custom username instead
	DateText.Text = formattedDate
end

-- Updates NYSE Countdown
local function updateCountdown()
	local time = os.time()

	local isOpen, targetTime = MarketHoursModule.getMarketStatus(time)

	if isOpen then
		TitleText.Text = "NYSE Closes In"
		TitleText.TextColor3 = GREEN
	else
		TitleText.Text = "NYSE Opens In"
		TitleText.TextColor3 = GRAY
	end

	local differenceTime = targetTime - time

	local hours = math.floor(differenceTime / 3600)
	local minutes = math.floor((differenceTime % 3600) / 60)
	local seconds = differenceTime % 60

	HoursNumber.Text = string.format("%02d", hours)
	MinutesNumber.Text = string.format("%02d", minutes)
	SecondsNumber.Text = string.format("%02d", seconds)
end

local updateSymbolData
local updateActiveTraderPosition
local toggleActiveTrader
local toggleSymbolInfo
local toggleWatchlist
local refreshWatchlist
local loadTicker

local ACTIVE_TRADER_DISABLED_COLOR = Theme.Colors.TextDisabled

-- Toggle for ActiveTrader window. Mutually exclusive with Symbol Info and
-- Watchlist - all three flyouts share the same anchored screen slot.
toggleActiveTrader = function()
	isActiveTradeVisible = not isActiveTradeVisible

	if isActiveTradeVisible and isSymbolInfoVisible then
		toggleSymbolInfo()
	end

	if isActiveTradeVisible and isWatchlistVisible then
		toggleWatchlist()
	end

	local targetPosition = isActiveTradeVisible and VISIBLE_POSITION or HIDDEN_POSITION

	local slideTween = TweenService:Create(ActiveTraderPanel, SLIDE_EASING, { Position = targetPosition })
	slideTween:Play() -- Tween slide for ActiveTrader window

	if isActiveTradeVisible then
		ToggleActiveTraderButton.Text = "Hide Active Trader"
	else
		ToggleActiveTraderButton.Text = "Show Active Trader"
	end

	if isActiveTradeVisible then
		updateSymbolData()
		updateActiveTraderPosition()
	end
end

-- Toggle for the Symbol Info flyout. Mutually exclusive with Active Trader
-- and Watchlist - all three flyouts share the same anchored screen slot.
toggleSymbolInfo = function()
	isSymbolInfoVisible = not isSymbolInfoVisible

	if isSymbolInfoVisible and isActiveTradeVisible then
		toggleActiveTrader()
	end

	if isSymbolInfoVisible and isWatchlistVisible then
		toggleWatchlist()
	end

	local targetPosition = isSymbolInfoVisible and VISIBLE_POSITION or HIDDEN_POSITION

	local slideTween = TweenService:Create(SymbolInfoPanel, SLIDE_EASING, { Position = targetPosition })
	slideTween:Play()

	if isSymbolInfoVisible then
		ToggleSymbolInfoButton.Text = "Hide Symbol Info"
	else
		ToggleSymbolInfoButton.Text = "Symbol Info"
	end

	if isSymbolInfoVisible then
		updateSymbolData()
	end
end

-- Toggle for the Watchlist flyout. Mutually exclusive with Active Trader
-- and Symbol Info - all three flyouts share the same anchored screen slot.
toggleWatchlist = function()
	isWatchlistVisible = not isWatchlistVisible

	if isWatchlistVisible and isActiveTradeVisible then
		toggleActiveTrader()
	end

	if isWatchlistVisible and isSymbolInfoVisible then
		toggleSymbolInfo()
	end

	local targetPosition = isWatchlistVisible and VISIBLE_POSITION or HIDDEN_POSITION

	local slideTween = TweenService:Create(WatchlistPanel, SLIDE_EASING, { Position = targetPosition })
	slideTween:Play()

	if isWatchlistVisible then
		ToggleWatchlistButton.Text = "Hide Watchlist"
	else
		ToggleWatchlistButton.Text = "Watchlist"
	end

	if isWatchlistVisible then
		refreshWatchlist()
	end
end

local watchlistRowInstances = {}

-- Rebuilds the Watchlist row list from a fresh GetWatchlistEvent result:
-- clones/prices/wires rows for each ticker, clears stale ones, and toggles
-- the empty-state label.
refreshWatchlist = function()
	local rows = GetWatchlistEvent:InvokeServer()

	for _, row in ipairs(watchlistRowInstances) do
		row:Destroy()
	end
	table.clear(watchlistRowInstances)

	WatchlistEmptyLabel.Visible = #rows == 0

	for _, entry in ipairs(rows) do
		local row = WatchlistRowTemplate:Clone()
		row.Name = "Row_" .. entry.ticker
		row.Visible = true
		row.LayoutOrder = 1
		row.Parent = WatchlistListContainer

		local rowButton = row:WaitForChild("RowButton")
		local tickerLabel = rowButton:WaitForChild("TickerLabel")
		local priceLabel = rowButton:WaitForChild("PriceLabel")
		local changeLabel = rowButton:WaitForChild("ChangeLabel")
		local removeButton = row:WaitForChild("RemoveButton")

		tickerLabel.Text = entry.ticker
		priceLabel.Text = entry.price and string.format("%.2f", entry.price) or "—"

		if entry.change and entry.changePct then
			local sign = entry.change >= 0 and "+" or ""
			changeLabel.Text = string.format("%s%.2f (%s%.2f%%)", sign, entry.change, sign, entry.changePct)
			changeLabel.TextColor3 = entry.change >= 0 and GREEN or RED
		else
			changeLabel.Text = "—"
			changeLabel.TextColor3 = GRAY
		end

		rowButton.MouseButton1Click:Connect(function()
			loadTicker(entry.ticker)
		end)

		removeButton.MouseButton1Click:Connect(function()
			ToggleWatchlistEvent:InvokeServer(entry.ticker)
			refreshWatchlist()
		end)

		table.insert(watchlistRowInstances, row)
	end
end

-- Enables/dims the Sell preset pills based on whether there's a position to
-- sell out of - a 25%/50%/75%/100% preset means nothing against 0 shares.
local function updateSellPresetsEnabled()
	local hasPosition = activeTraderPositionQty > 0

	for _, preset in ipairs(ActiveTraderSellPresets) do
		local button = preset.button
		local stroke = button:FindFirstChild("Stroke")

		button.Active = hasPosition
		button.AutoButtonColor = hasPosition
		button.TextColor3 = hasPosition and RED or ACTIVE_TRADER_DISABLED_COLOR

		if stroke then
			stroke.Color = hasPosition and RED or ACTIVE_TRADER_DISABLED_COLOR
		end
	end
end

-- Refreshes live data for the ticker currently loaded on the chart: the
-- Active Trader ask price (Active Trader always trades that ticker - there
-- is no separate ticker input on the panel itself) and the Symbol Info
-- fields. One shared InvokeServer call feeds both panels.
updateSymbolData = function()
	if currentDisplayedTicker == "" then
		return
	end

	local quote = GetMarketDataEvent:InvokeServer(currentDisplayedTicker)

	if not quote then
		return
	end

	if quote.ask then
		activeTraderAsk = quote.ask
		ActiveTraderAskPriceLabel.Text = string.format("Ask %.2f", quote.ask)
	end

	SymbolInfoTickerLabel.Text = currentDisplayedTicker

	SymbolInfoFields.MarketCap.Text = quote.marketCap and NumberModule.formatCompact(quote.marketCap) or "—"
	SymbolInfoFields.PE.Text = quote.trailingPE and string.format("%.2f", quote.trailingPE) or "—"
	SymbolInfoFields.EPS.Text = quote.eps and string.format("%.2f", quote.eps) or "—"

	SymbolInfoFields.DayRange.Text = (quote.dayLow and quote.dayHigh)
			and string.format("%.2f - %.2f", quote.dayLow, quote.dayHigh)
		or "—"

	SymbolInfoFields.FiftyTwoWeekRange.Text = (quote.fiftyTwoWeekLow and quote.fiftyTwoWeekHigh)
			and string.format("%.2f - %.2f", quote.fiftyTwoWeekLow, quote.fiftyTwoWeekHigh)
		or "—"

	SymbolInfoFields.Volume.Text = quote.volume and NumberModule.formatShares(quote.volume) or "—"
	SymbolInfoFields.AvgVolume.Text = quote.avgVolume and NumberModule.formatShares(quote.avgVolume) or "—"
	SymbolInfoFields.Beta.Text = quote.beta and string.format("%.2f", quote.beta) or "—"
	SymbolInfoFields.DividendYield.Text = quote.dividendYield and string.format("%.2f%%", quote.dividendYield) or "—"
end

-- Refreshes the held share count for the current ticker, which Sell
-- presets are a percentage of.
updateActiveTraderPosition = function()
	if currentDisplayedTicker == "" then
		activeTraderPositionQty = 0
		ActiveTraderPositionLabel.Text = ""
		updateSellPresetsEnabled()

		return
	end

	local positions = GetPositionsEvent:InvokeServer(currentDisplayedTicker)
	local quantity = (positions and positions[1] and positions[1].quantity) or 0

	activeTraderPositionQty = quantity
	ActiveTraderPositionLabel.Text = quantity > 0 and (quantity .. " shares") or "No position"
	updateSellPresetsEnabled()
end

local function placeActiveTraderBuy(dollarAmount)
	if currentDisplayedTicker == "" then
		ActiveTraderStatusLabel.TextColor3 = GRAY
		ActiveTraderStatusLabel.Text = "Load a ticker on the chart first."

		return
	end

	if not MarketHoursModule.getMarketStatus(os.time()) then
		ActiveTraderStatusLabel.TextColor3 = GRAY
		ActiveTraderStatusLabel.Text = "Market is closed."

		return
	end

	if not activeTraderAsk then
		ActiveTraderStatusLabel.TextColor3 = GRAY
		ActiveTraderStatusLabel.Text = "Price unavailable, try again."

		return
	end

	local shares = math.floor(dollarAmount / activeTraderAsk)

	if shares < 1 then
		ActiveTraderStatusLabel.TextColor3 = GRAY
		ActiveTraderStatusLabel.Text = "Preset amount is below one share."

		return
	end

	local result = PlayerOrderEvent:InvokeServer("Buy", currentDisplayedTicker, shares)

	if not result or not result.success then
		ActiveTraderStatusLabel.TextColor3 = RED
		ActiveTraderStatusLabel.Text = (result and result.message) or "Order failed."

		return
	end

	ActiveTraderStatusLabel.TextColor3 = GREEN
	ActiveTraderStatusLabel.Text = result.message

	updateSymbolData()
	updateActiveTraderPosition()
end

local function placeActiveTraderSell(fraction)
	if activeTraderPositionQty <= 0 then
		ActiveTraderStatusLabel.TextColor3 = GRAY
		ActiveTraderStatusLabel.Text = "No position to sell."

		return
	end

	if not MarketHoursModule.getMarketStatus(os.time()) then
		ActiveTraderStatusLabel.TextColor3 = GRAY
		ActiveTraderStatusLabel.Text = "Market is closed."

		return
	end

	local shares = math.max(1, math.floor(activeTraderPositionQty * fraction))
	shares = math.min(shares, activeTraderPositionQty)

	local result = PlayerOrderEvent:InvokeServer("Sell", currentDisplayedTicker, shares)

	if not result or not result.success then
		ActiveTraderStatusLabel.TextColor3 = RED
		ActiveTraderStatusLabel.Text = (result and result.message) or "Order failed."

		return
	end

	ActiveTraderStatusLabel.TextColor3 = GREEN
	ActiveTraderStatusLabel.Text = result.message

	updateSymbolData()
	updateActiveTraderPosition()
end

-- ScrollBar Logic
local function updateScrollBarUI()
	if #masterChartData == 0 then
		ScrollTrack.Visible = false
		return
	end

	ScrollTrack.Visible = true

	local maxOffset = #masterChartData - visibleCandles
	local viewRatio = math.clamp(visibleCandles / #masterChartData, 0.05, 1)

	ScrollThumb.Size = UDim2.fromScale(viewRatio, 1)

	if maxOffset > 0 then
		local availableWidthScale = 1 - viewRatio
		local scrollAlpha = 1 - (rightOffset / maxOffset)

		ScrollThumb.Position = UDim2.fromScale(scrollAlpha * availableWidthScale, 0)
	else
		ScrollThumb.Position = UDim2.fromScale(1 - viewRatio, 0)
	end
end

-- Zoom and Scroll logic
local function updateViewport()
	if #masterChartData == 0 then
		return
	end

	visibleCandles = math.clamp(visibleCandles, 10, #masterChartData)
	rightOffset = math.clamp(rightOffset, 0, #masterChartData - visibleCandles)

	local startIndex = #masterChartData - rightOffset - visibleCandles + 1
	local endIndex = #masterChartData - rightOffset

	currentChartData = {}

	for i = startIndex, endIndex do
		table.insert(currentChartData, masterChartData[i])
	end

	renderChart(currentDisplayedTicker, currentChartData)
	updateScrollBarUI()
end

local function scheduleViewportUpdate()
	if viewportUpdateScheduled then
		return
	end
	viewportUpdateScheduled = true
	task.defer(function()
		viewportUpdateScheduled = false
		updateViewport()
	end)
end

-- Loads a ticker onto the chart. Shared by the ticker input (Enter) and
-- Watchlist row clicks, so both paths go through the same fetch/render/error
-- handling instead of duplicating it.
loadTicker = function(ticker)
	if isFetchingData then
		return
	end

	local targetTicker = string.gsub(string.upper(ticker or ""), "%s+", "")

	if targetTicker == "" then
		TickerInput.Text = currentDisplayedTicker
		return
	end

	-- A pending trend-line first point belongs to whatever ticker's candle
	-- series was showing when it was placed - discard it on ticker switch.
	pendingTrendLineStart = nil

	isFetchingData = true

	TickerInput.Text = " . . . "
	ChartTickerLabel.Text = "Loading"

	local chartData = RequestChartEvent:InvokeServer(targetTicker, currentTimeframe)

	if chartData and #chartData > 0 then
		masterChartData = chartData
		currentDisplayedTicker = targetTicker
		rightOffset = 0
		TickerInput.Text = targetTicker
		ActiveTraderTickerLabel.Text = targetTicker
		ActiveTraderStatusLabel.Text = ""
		updateViewport()
		updateSymbolData()
		updateActiveTraderPosition()
	else
		TickerInput.Text = " . . . "
		ChartTickerLabel.Text = "Error"
		task.delay(2, function()
			TickerInput.Text = currentDisplayedTicker
		end)
	end

	isFetchingData = false
end

local function updateTimeframeUI(activeTime)
	for button, data in pairs(TimeDropdownOptions) do
		if data.query == activeTime then
			button.BackgroundColor3 = COLOR_ACTIVE_BACKGROUND
			button.TextColor3 = COLOR_ACTIVE_TEXT
		else
			button.BackgroundColor3 = COLOR_INACTIVE_BACKGROUND
			button.TextColor3 = COLOR_INACTIVE_TEXT
		end
	end
end

for button, data in pairs(TimeDropdownOptions) do
	button.MouseButton1Click:Connect(function()
		isDropdownOpen = false
		TimeDropdownList.Visible = false

		if isFetchingData then
			return
		end

		isFetchingData = true
		print(data.query)
		currentTimeframe = data.query
		updateTimeframeUI(data.query)
		pendingTrendLineStart = nil

		if currentDisplayedTicker ~= "" then
			ChartTickerLabel.Text = "Loading"

			updateScrollBarUI()

			local chartData = RequestChartEvent:InvokeServer(currentDisplayedTicker, data.query)

			if chartData then
				masterChartData = chartData
				rightOffset = 0

				updateViewport()
				MainTimeframeButton.Text = data.query
			end
		end

		isFetchingData = false
	end)
end

for tabName, data in pairs(Tabs) do
	data.Button.MouseButton1Click:Connect(function()
		switchTab(tabName)
	end)
end

-- Another screen opened a ticker (e.g. a Portfolio row); TradeController loads it
Navigation.TickerRequested:Connect(function()
	switchTab("Trade")
end)

Navigation.TabRequested:Connect(function(tabName)
	if Tabs[tabName] then
		switchTab(tabName)
	end
end)

MainTimeframeButton.MouseButton1Click:Connect(function()
	isDropdownOpen = not isDropdownOpen
	TimeDropdownList.Visible = isDropdownOpen

	isIndicatorsDropdownOpen = false
	IndicatorsDropdownList.Visible = false
end)

MainIndicatorsButton.MouseButton1Click:Connect(function()
	isIndicatorsDropdownOpen = not isIndicatorsDropdownOpen
	IndicatorsDropdownList.Visible = isIndicatorsDropdownOpen

	isDropdownOpen = false
	TimeDropdownList.Visible = false
end)

local INDICATORS_BUTTON_TEXT = MainIndicatorsButton.Text

local function areIndicatorsUnlocked()
	return Progression.isUnlocked(Player:GetAttribute("Level") or 1, "ChartIndicators")
end

-- Below the unlock level the dropdown still opens, but its options are
-- dimmed and do nothing, and the button names the level that unlocks them
local function updateIndicatorLock()
	local isUnlocked = areIndicatorsUnlocked()

	MainIndicatorsButton.Text = isUnlocked and INDICATORS_BUTTON_TEXT
		or string.format("%s · Lv %d", INDICATORS_BUTTON_TEXT, Progression.FEATURES.ChartIndicators)

	for button, indicator in pairs(IndicatorOptions) do
		if not indicator.active then
			button.TextColor3 = isUnlocked and COLOR_INACTIVE_TEXT or Theme.Colors.TextDisabled
		end
	end
end

for button, indicator in pairs(IndicatorOptions) do
	button.MouseButton1Click:Connect(function()
		if not areIndicatorsUnlocked() then
			return
		end

		indicator.active = not indicator.active
		button.BackgroundTransparency = indicator.active and 0 or 1
		button.BackgroundColor3 = indicator.active and indicator.color or COLOR_INACTIVE_BACKGROUND
		-- Dark text: every series color is bright (EMA50 is near-white)
		button.TextColor3 = indicator.active and Theme.Colors.Background or COLOR_INACTIVE_TEXT

		renderChart(currentDisplayedTicker, currentChartData)
	end)
end

-- Closes the timeframe/indicators dropdowns on any click/tap outside them -
-- previously they only closed via their own toggle button or picking an
-- option, so they stayed open (and silently ate the next click) if you
-- clicked anywhere else, including the chart itself.
local function isWithinBounds(frame, inputPosition)
	local framePosition = frame.AbsolutePosition
	local frameSize = frame.AbsoluteSize

	return inputPosition.X >= framePosition.X
		and inputPosition.X <= framePosition.X + frameSize.X
		and inputPosition.Y >= framePosition.Y
		and inputPosition.Y <= framePosition.Y + frameSize.Y
end

UserInputService.InputBegan:Connect(function(input)
	if not isDropdownOpen and not isIndicatorsDropdownOpen then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	-- The open list visually extends below its toggle button, outside the
	-- toggle frame's own AbsoluteSize - check both rects, or a click on a
	-- list item (below the toggle) reads as "outside" and hides the list
	-- on mouse-down, before the item's own click can fire.
	if
		isDropdownOpen
		and not isWithinBounds(TimeframeDropdown, input.Position)
		and not isWithinBounds(TimeDropdownList, input.Position)
	then
		isDropdownOpen = false
		TimeDropdownList.Visible = false
	end

	if
		isIndicatorsDropdownOpen
		and not isWithinBounds(IndicatorsDropdown, input.Position)
		and not isWithinBounds(IndicatorsDropdownList, input.Position)
	then
		isIndicatorsDropdownOpen = false
		IndicatorsDropdownList.Visible = false
	end
end)

ActiveTraderTopBar.InputBegan:Connect(function(input)
	if not isActiveTradeVisible then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPosition = ActiveTraderPanel.Position
		draggedPanel = ActiveTraderPanel
	end
end)

ActiveTraderTopBar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

SymbolInfoTopBar.InputBegan:Connect(function(input)
	if not isSymbolInfoVisible then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPosition = SymbolInfoPanel.Position
		draggedPanel = SymbolInfoPanel
	end
end)

SymbolInfoTopBar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

WatchlistTopBar.InputBegan:Connect(function(input)
	if not isWatchlistVisible then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPosition = WatchlistPanel.Position
		draggedPanel = WatchlistPanel
	end
end)

WatchlistTopBar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input == dragInput and draggedPanel then
		local delta = input.Position - dragStart

		draggedPanel.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end
end)

ChartCanvas.InputBegan:Connect(function(input)
	if isDraggingScroll then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if handleDrawingClick(input.Position) then
			return
		end

		isDraggingChart = true
		lastMouseDragX = input.Position.X

		CrosshairX.Visible = false
		CrosshairY.Visible = false
		HoverPriceTag.Visible = false
		HoverTimeTag.Visible = false
	end
end)

ChartCanvas.InputChanged:Connect(function(input)
	if #masterChartData == 0 then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local zoomSpeed = math.max(2, math.floor(visibleCandles * 0.1))

		if input.Position.Z > 0 then
			visibleCandles = visibleCandles - zoomSpeed
		else
			visibleCandles = visibleCandles + zoomSpeed
		end
		scheduleViewportUpdate()
		return
	end

	if
		isDraggingChart
		and not isDraggingScroll
		and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch)
	then
		local deltaX = input.Position.X - lastMouseDragX
		local pixelsPerCandle = ChartCanvas.AbsoluteSize.X / visibleCandles

		if math.abs(deltaX) >= pixelsPerCandle then
			local shiftAmount = math.floor(deltaX / pixelsPerCandle)

			rightOffset = rightOffset + shiftAmount

			lastMouseDragX = input.Position.X

			scheduleViewportUpdate()
		end
		return
	end

	if not isCrosshairActive then
		return
	end

	if not isDraggingChart then
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if #currentChartData == 0 then
				return
			end

			local mousePosition = input.Position
			local canvasPosition = ChartCanvas.AbsolutePosition
			local canvasSize = ChartCanvas.AbsoluteSize
			local canvasWidth = ChartCanvas.AbsoluteSize.X

			local relativeX = mousePosition.X - canvasPosition.X
			local relativeY = mousePosition.Y - canvasPosition.Y

			if relativeX >= 0 and relativeX <= canvasSize.X and relativeY >= 0 and relativeY <= canvasSize.Y then
				if not currentMinPrice or not currentMaxPrice then
					return
				end

				local percentX = math.clamp(relativeX / canvasWidth, 0, 1)
				local index = math.ceil(percentX * #currentChartData)

				index = math.clamp(index, 1, #currentChartData)

				local numberCandles = #currentChartData
				local candleWidthScale = 1 / numberCandles
				local snapXScale = ((index - 1) * candleWidthScale) + (candleWidthScale / 2)

				CrosshairX.Visible = true
				CrosshairY.Visible = true
				HoverPriceTag.Visible = true
				HoverTimeTag.Visible = true

				CrosshairX.Position = UDim2.fromScale(snapXScale, 0)
				CrosshairY.Position = UDim2.fromOffset(0, relativeY)

				local priceRange = currentMaxPrice - currentMinPrice
				local yPercentage = relativeY / canvasSize.Y
				local hoveredPrice = currentMaxPrice - (yPercentage * priceRange)

				HoverPriceTag.Position = UDim2.fromOffset(0, relativeY - (HoverPriceTag.AbsoluteSize.Y / 2))
				HoverPriceTag.Text = string.format("%.2f", hoveredPrice)

				local hoverCandle = currentChartData[index]
				local timestamp = hoverCandle.Timestamp or os.time()

				local formatString = ChartRenderer.TimeframeFormats[currentTimeframe] or "%b %d, %H:%M"

				HoverTimeTag.Text = os.date(formatString, timestamp)

				HoverTimeTag.Position = UDim2.new(snapXScale, 0, 1, -25)
			else
				CrosshairX.Visible = false
				CrosshairY.Visible = false
				HoverPriceTag.Visible = false
				HoverTimeTag.Visible = false
			end
		end
	end
end)

ChartCanvas.InputEnded:Connect(function()
	CrosshairX.Visible = false
	CrosshairY.Visible = false
	HoverPriceTag.Visible = false
	HoverTimeTag.Visible = false
	isDraggingChart = false
end)

TickerInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		loadTicker(TickerInput.Text)
		return
	end

	-- Clicked/tabbed away without pressing Enter - discard whatever was
	-- typed instead of leaving stale text sitting in the box forever.
	TickerInput.Text = currentDisplayedTicker
end)

ScrollThumb.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isDraggingScroll = true
		scrollDragStartX = input.Position.X
		startRightOffset = rightOffset
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isDraggingScroll = false
		dragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if
		isDraggingScroll
		and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch)
	then
		local deltaX = input.Position.X - scrollDragStartX

		local trackWidth = ScrollTrack.AbsoluteSize.X
		local thumbWidth = ScrollThumb.AbsoluteSize.X
		local maxOffset = #masterChartData - visibleCandles

		if trackWidth > thumbWidth then
			local candlesPerPixel = maxOffset / (trackWidth - thumbWidth)

			local offsetChange = math.floor(deltaX * candlesPerPixel)

			rightOffset = math.clamp(startRightOffset - offsetChange, 0, maxOffset)
			scheduleViewportUpdate()
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(5)

		if #masterChartData > 0 and not isFetchingData and rightOffset == 0 and currentDisplayedTicker ~= "" then
			local liveData = RequestChartEvent:InvokeServer(currentDisplayedTicker, currentTimeframe, "live")

			if liveData and #liveData > 0 then
				local incomingLiveCandle = liveData[#liveData]
				local currentLastCandle = masterChartData[#masterChartData]

				if incomingLiveCandle.Timestamp == currentLastCandle.Timestamp then
					currentLastCandle.Close = incomingLiveCandle.Close

					if incomingLiveCandle.Close > currentLastCandle.High then
						currentLastCandle.High = incomingLiveCandle.Close
					end

					if incomingLiveCandle.Close < currentLastCandle.Low then
						currentLastCandle.Low = incomingLiveCandle.Close
					end

					masterChartData[#masterChartData] = currentLastCandle
				elseif incomingLiveCandle.Timestamp > currentLastCandle.Timestamp then
					table.insert(masterChartData, incomingLiveCandle)
				end

				scheduleViewportUpdate()
			end

			if isActiveTradeVisible then
				updateSymbolData()
				updateActiveTraderPosition()
			elseif isSymbolInfoVisible then
				updateSymbolData()
			end
		end

		if isWatchlistVisible then
			refreshWatchlist()
		end
	end
end)

task.spawn(function()
	while true do
		updateCountdown()
		task.wait(1)
	end
end)

task.spawn(function()
	while true do
		task.wait(1)

		local PriceBadge = RightAxis:FindFirstChild("AxisLabel_LiveBadge")

		if PriceBadge then
			local CountdownText = PriceBadge:FindFirstChild("CountdownText")

			if CountdownText and #masterChartData > 0 then
				local currentUnixTime = os.time()
				local lastCandle = masterChartData[#masterChartData]

				local timeframeStep = getTimeframeStep(currentTimeframe)

				local candleStartTime = lastCandle.Timestamp
				local candleEndTime = candleStartTime + timeframeStep
				local secondsRemaining = candleEndTime - currentUnixTime

				if secondsRemaining <= 0 then
					CountdownText.Text = "00:00"
				else
					local minutes = math.floor(secondsRemaining / 60)
					local seconds = secondsRemaining % 60

					CountdownText.Text = string.format("%02d:%02d", minutes, seconds)
				end
			end
		end
	end
end)

ToggleActiveTraderButton.MouseButton1Click:Connect(toggleActiveTrader)
ToggleSymbolInfoButton.MouseButton1Click:Connect(toggleSymbolInfo)
ToggleWatchlistButton.MouseButton1Click:Connect(toggleWatchlist)

CursorToolButton.MouseButton1Click:Connect(function()
	setDrawingTool("cursor")
end)

TrendLineToolButton.MouseButton1Click:Connect(function()
	setDrawingTool("trendline")
end)

HorizontalLineToolButton.MouseButton1Click:Connect(function()
	setDrawingTool("horizontal")
end)

ClearDrawingsButton.MouseButton1Click:Connect(function()
	if currentDisplayedTicker == "" then
		return
	end

	drawingsByTicker[currentDisplayedTicker] = { horizontalLines = {}, trendLines = {} }
	pendingTrendLineStart = nil
	renderChart(currentDisplayedTicker, currentChartData)
end)

local function addTickerToWatchlist()
	local targetTicker = string.gsub(string.upper(AddTickerInput.Text), "%s+", "")
	AddTickerInput.Text = ""

	if targetTicker == "" then
		return
	end

	ToggleWatchlistEvent:InvokeServer(targetTicker)
	refreshWatchlist()
end

AddTickerButton.MouseButton1Click:Connect(addTickerToWatchlist)

AddTickerInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		addTickerToWatchlist()
	end
end)

for _, preset in ipairs(ActiveTraderBuyPresets) do
	preset.button.MouseButton1Click:Connect(function()
		placeActiveTraderBuy(preset.amount)
	end)
end

for _, preset in ipairs(ActiveTraderSellPresets) do
	preset.button.MouseButton1Click:Connect(function()
		placeActiveTraderSell(preset.fraction)
	end)
end

-- Preset pills: the stroke outlines the pill (Border mode - the default,
-- Contextual, outlines a text object's glyphs). Buy pills never dim, so their
-- green is set once here; Sell pills are recolored by updateSellPresetsEnabled.
local function stylePresetPill(button, color)
	local stroke = button:FindFirstChild("Stroke")

	button.TextColor3 = color

	if stroke then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = color
	end
end

for _, preset in ipairs(ActiveTraderBuyPresets) do
	stylePresetPill(preset.button, GREEN)
end

for _, preset in ipairs(ActiveTraderSellPresets) do
	stylePresetPill(preset.button, RED)
end

for button in pairs(IndicatorOptions) do
	button.BackgroundColor3 = COLOR_INACTIVE_BACKGROUND
	button.TextColor3 = COLOR_INACTIVE_TEXT
end

Player:GetAttributeChangedSignal("Level"):Connect(updateIndicatorLock)

switchTab("Dashboard")
updateIndicatorLock()
setDrawingTool(currentDrawingTool) -- the Studio defaults no longer show which tool is active
updateTimeframeUI(currentTimeframe)
updateGreeting()
updateActiveTraderPosition() -- grays out Sell presets until a position exists
ChartTickerLabel.Text = "—" -- otherwise this shows Studio's literal default "Label" until a ticker loads
