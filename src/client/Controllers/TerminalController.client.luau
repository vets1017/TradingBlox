-- Services
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Modules
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local Instruments = require(ReplicatedStorage.Config.Instruments)
local ChartRenderer = require(ReplicatedStorage.Modules.Multi.ChartRenderer)
local IndicatorModule = require(ReplicatedStorage.Modules.Multi.IndicatorModule)
local DrawingModule = require(ReplicatedStorage.Modules.Multi.DrawingModule)
local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)
local Progression = require(ReplicatedStorage.Config.Progression)
local RobloxMarket = require(ReplicatedStorage.Config.RobloxMarket)
local MarketPickerModule = require(ReplicatedStorage.Modules.Trade.MarketPickerModule)
local UIKit = require(ReplicatedStorage.UI.UIKit)

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
local AccentGradient = TopBar:WaitForChild("AccentLine"):WaitForChild("AccentGradient")
local TabContainer = TopBar:WaitForChild("TabContainer")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")
local DashboardScreen = ScreenContainer:WaitForChild("DashboardScreen")
local GreetingBar = DashboardScreen:WaitForChild("GreetingBar")
local GreetingText = GreetingBar:WaitForChild("GreetingText")
local DateText = GreetingBar:WaitForChild("DateText")
-- Paths straight to what's used: this script is near Luau's 200-local limit
local CountdownWidget = DashboardScreen:WaitForChild("DashboardGrid")
	:WaitForChild("MainWorkspace")
	:WaitForChild("TopRow")
	:WaitForChild("CountdownWidget")
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
local OpenInTradeButton = Sidebar:WaitForChild("PlaceholderButton") -- a placeholder in Studio
local SymbolInfoPanel = ChartsScreen:WaitForChild("SymbolInfoPanel")
local SymbolInfoTopBar = SymbolInfoPanel:WaitForChild("SymbolInfoTopBar")
local SymbolInfoTickerLabel = SymbolInfoTopBar:WaitForChild("TickerNameLabel")

-- Symbol Info's rows top to bottom, with their Studio labels (a stock's
-- fields). A Roblox game shows its own fields in them, under its own labels.
local SymbolInfoRows = {}

for _, rowName in ipairs({
	"MarketCapRow",
	"PERow",
	"EPSRow",
	"DayRangeRow",
	"FiftyTwoWeekRangeRow",
	"VolumeRow",
	"AvgVolumeRow",
	"BetaRow",
	"DividendYieldRow",
}) do
	local row = SymbolInfoPanel:WaitForChild("ContentArea"):WaitForChild(rowName)
	local label = row:WaitForChild("Label")

	table.insert(SymbolInfoRows, { label = label, value = row:WaitForChild("Value"), stockLabel = label.Text })
end

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
local currentStartIndex = 1 -- where currentChartData starts in masterChartData
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
	-- Built in code by ShellController and filled by SocialController and
	-- LeaderboardController
	Social = {
		Button = TabContainer:WaitForChild("SocialButton"),
		Frame = ScreenContainer:WaitForChild("SocialScreen"),
	},
	Leaderboards = {
		Button = TabContainer:WaitForChild("LeaderboardsButton"),
		Frame = ScreenContainer:WaitForChild("LeaderboardsScreen"),
	},
}

-- `option` is how the dropdown lists a timeframe, `short` how the button
-- and the legend show the chosen one
local TimeDropdownOptions = {
	[TimeDropdownList:WaitForChild("1MinuteButton")] = { query = "1M", option = "1 min", short = "1m" },
	[TimeDropdownList:WaitForChild("5MinuteButton")] = { query = "5M", option = "5 min", short = "5m" },
	[TimeDropdownList:WaitForChild("30MinuteButton")] = { query = "30M", option = "30 min", short = "30m" },
	[TimeDropdownList:WaitForChild("1HourButton")] = { query = "H", option = "1 hour", short = "1H" },
	[TimeDropdownList:WaitForChild("1DayButton")] = { query = "D", option = "1 day", short = "1D" },
}

local function getTimeframeShort(query)
	for _, data in pairs(TimeDropdownOptions) do
		if data.query == query then
			return data.short
		end
	end

	return query
end

for button, data in pairs(TimeDropdownOptions) do
	button.Text = data.option
end

local DEFAULT_CHART_TICKER = "SPY" -- what the Charts tab opens on

local function movingAverage(average, period)
	return function(_, closes)
		return { lines = { { values = average(closes, period) } } }
	end
end

local function utcDay(timestamp)
	return timestamp // 86400
end

-- Chart indicators, in the dropdown's order. `build(candles, closes)` makes
-- the series from the whole loaded history (aligned with it), so a line
-- starts at the left edge rather than `period` candles in; a `visibleOnly`
-- one (the volume profile) is built from the candles in view instead. An
-- indicator draws on the price chart, or in its own pane under it (`pane`).
-- `feature` is its unlock (Config/Progression). The moving averages have
-- Studio-built buttons (`buttonName`); the rest get copies of those.
-- Series colors are chart data, so they're literals. `active` is toggled by
-- the dropdown.
local INDICATORS = {
	{
		key = "SMA20",
		label = "SMA 20",
		buttonName = "SMA20Button",
		feature = "ChartIndicators",
		color = Color3.fromRGB(255, 170, 0),
		build = movingAverage(IndicatorModule.sma, 20),
	},
	{
		key = "SMA50",
		label = "SMA 50",
		buttonName = "SMA50Button",
		feature = "ChartIndicators",
		color = Color3.fromRGB(0, 170, 255),
		build = movingAverage(IndicatorModule.sma, 50),
	},
	{
		key = "EMA20",
		label = "EMA 20",
		buttonName = "EMA20Button",
		feature = "ChartIndicators",
		color = Color3.fromRGB(255, 90, 205),
		build = movingAverage(IndicatorModule.ema, 20),
	},
	{
		key = "EMA50",
		label = "EMA 50",
		buttonName = "EMA50Button",
		feature = "ChartIndicators",
		color = Color3.fromRGB(220, 222, 230), -- near-white: the old purple was nearly the UI accent
		build = movingAverage(IndicatorModule.ema, 50),
	},
	{
		key = "BB20",
		label = "Bollinger 20",
		feature = "ChartIndicators",
		color = Color3.fromRGB(110, 190, 255),
		build = function(_, closes)
			local bands = IndicatorModule.bollinger(closes, 20, 2)

			return {
				lines = {
					{ values = bands.upper },
					{ values = bands.middle, transparency = 0.5 },
					{ values = bands.lower },
				},
			}
		end,
	},
	{
		key = "RSI14",
		label = "RSI 14",
		feature = "ChartIndicators",
		pane = true,
		color = Color3.fromRGB(190, 140, 255),
		build = function(_, closes)
			return { range = { 0, 100 }, guides = { 30, 70 }, lines = { { values = IndicatorModule.rsi(closes, 14) } } }
		end,
	},
	{
		key = "MACD",
		label = "MACD 12 26 9",
		feature = "ChartIndicators",
		pane = true,
		color = Color3.fromRGB(0, 170, 255),
		build = function(_, closes)
			local result = IndicatorModule.macd(closes, 12, 26, 9)

			return {
				lines = { { values = result.macd }, { values = result.signal, color = Color3.fromRGB(255, 140, 0) } },
				bars = { values = result.histogram },
			}
		end,
	},
	{
		key = "ATR14",
		label = "ATR 14",
		feature = "AdvancedIndicators",
		pane = true,
		color = Color3.fromRGB(220, 222, 230),
		build = function(candles)
			return { lines = { { values = IndicatorModule.atr(candles, 14) } } }
		end,
	},
	{
		key = "VWAP",
		label = "VWAP",
		feature = "AdvancedIndicators",
		color = Color3.fromRGB(255, 215, 90),
		build = function(candles)
			-- Restarts each UTC day, with no line joining one day to the next;
			-- daily candles run as one session
			local sessionOf = currentTimeframe ~= "D" and utcDay or nil
			local breaks = {}

			for index = 2, if sessionOf then #candles else 0 do
				if utcDay(candles[index].Timestamp) ~= utcDay(candles[index - 1].Timestamp) then
					breaks[index] = true
				end
			end

			return { lines = { { values = IndicatorModule.vwap(candles, sessionOf), breaks = breaks } } }
		end,
	},
	{
		key = "VolumeProfile",
		label = "Volume profile",
		feature = "AdvancedIndicators",
		visibleOnly = true,
		color = Color3.fromRGB(154, 107, 255),
		build = function(candles)
			return { profile = IndicatorModule.volumeProfile(candles, 24) }
		end,
	},
}

local INDICATOR_OPTION_HEIGHT = 30
local INDICATOR_LIST_WIDTH = 180 -- room for "Volume profile · Lv 3"

do
	local template = IndicatorsDropdownList:WaitForChild("SMA20Button")

	for index, indicator in ipairs(INDICATORS) do
		local button

		if indicator.buttonName then
			button = IndicatorsDropdownList:WaitForChild(indicator.buttonName)
		else
			button = template:Clone()
			button.Name = indicator.key .. "Button"
			button.Parent = IndicatorsDropdownList
		end

		button.Text = indicator.label
		button.LayoutOrder = index
		indicator.button = button
		indicator.active = false
	end

	-- The Studio list fits only the moving averages
	IndicatorsDropdownList.Size = UDim2.fromOffset(INDICATOR_LIST_WIDTH, INDICATOR_OPTION_HEIGHT * #INDICATORS)
end

-- Oscillator panes under the price chart, built in code. While any are on,
-- the chart and its price axis give up their height.
local PANE_HEIGHT = 96
local PANE_GAP = 12 -- keeps the chart's scroll bar clear of the first pane
local CANVAS_SIZE = ChartCanvas.Size
local AXIS_SIZE = RightAxis.Size
local CANVAS_BOTTOM = ChartCanvas.Position.Y.Offset + CANVAS_SIZE.Y.Offset -- from the bottom of MainChart

local IndicatorPanes = Instance.new("Frame")
IndicatorPanes.Name = "IndicatorPanes"
IndicatorPanes.BackgroundTransparency = 1
IndicatorPanes.Parent = MainChart

local paneContents = {} -- each pane's frame for ChartRenderer.renderPane

local function layoutPanes(count)
	local taken = count > 0 and count * PANE_HEIGHT + PANE_GAP or 0

	ChartCanvas.Size = UDim2.new(CANVAS_SIZE.X.Scale, CANVAS_SIZE.X.Offset, 1, CANVAS_SIZE.Y.Offset - taken)
	RightAxis.Size = UDim2.new(AXIS_SIZE.X.Scale, AXIS_SIZE.X.Offset, 1, AXIS_SIZE.Y.Offset - taken)
	IndicatorPanes.Position = UDim2.new(0, ChartCanvas.Position.X.Offset, 1, CANVAS_BOTTOM - count * PANE_HEIGHT)
	IndicatorPanes.Size = UDim2.new(CANVAS_SIZE.X.Scale, CANVAS_SIZE.X.Offset, 0, count * PANE_HEIGHT)

	for index = #paneContents + 1, count do
		local pane = Instance.new("Frame")
		pane.Name = "Pane_" .. index
		pane.BackgroundTransparency = 1
		pane.Position = UDim2.fromOffset(0, (index - 1) * PANE_HEIGHT)
		pane.Size = UDim2.new(1, 0, 0, PANE_HEIGHT)
		pane.Parent = IndicatorPanes

		local divider = Instance.new("Frame")
		divider.Name = "Divider"
		divider.BackgroundColor3 = Theme.Colors.Border
		divider.BorderSizePixel = 0
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.Parent = pane

		local content = Instance.new("Frame")
		content.Name = "Content"
		content.BackgroundTransparency = 1
		content.Position = UDim2.fromOffset(0, 4)
		content.Size = UDim2.new(1, 0, 1, -8)
		content.Parent = pane

		paneContents[index] = content
	end

	for index = #paneContents, count + 1, -1 do
		paneContents[index].Parent:Destroy()
		paneContents[index] = nil
	end
end

-- The whole loaded history's series, per indicator; rebuilt when the
-- history changes (a new ticker or timeframe, or a live candle)
local seriesCache = { source = nil, length = 0, lastClose = nil, closes = {}, byKey = {} }

local function getFullSeries(indicator)
	local last = masterChartData[#masterChartData]
	local lastClose = last and last.Close

	if
		seriesCache.source ~= masterChartData
		or seriesCache.length ~= #masterChartData
		or seriesCache.lastClose ~= lastClose
	then
		local closes = {}

		for index, candle in ipairs(masterChartData) do
			closes[index] = candle.Close
		end

		seriesCache =
			{ source = masterChartData, length = #masterChartData, lastClose = lastClose, closes = closes, byKey = {} }
	end

	local series = seriesCache.byKey[indicator.key]

	if not series then
		series = indicator.build(masterChartData, seriesCache.closes)
		seriesCache.byKey[indicator.key] = series
	end

	return series
end

-- `series` cut to the `count` candles in view, which start at history index `first`
local function sliceSeries(series, first, count)
	local function cut(values)
		local slice = {}

		for index = 1, count do
			slice[index] = values[first + index - 1]
		end

		return slice
	end

	local sliced = table.clone(series)

	if series.lines then
		sliced.lines = {}

		for index, line in ipairs(series.lines) do
			local copy = table.clone(line)

			copy.values = cut(line.values)
			copy.breaks = line.breaks and cut(line.breaks)
			sliced.lines[index] = copy
		end
	end

	if series.bars then
		sliced.bars = { values = cut(series.bars.values) }
	end

	return sliced
end

-- Unfinished: wired up once the stock list lands
-- selene: allow(unused_variable)
local function refreshTerminal()
	local marketData = GetMarketDataEvent:InvokeServer()

	if not marketData then
		return
	end
	-- continue after stock-list is done
end

-- The legend: the chart's title, then a candle's open, high, low, close,
-- change on the previous close and volume - the hovered candle's, or the
-- latest's
local UP_HEX = Theme.Colors.Up:ToHex()
local DOWN_HEX = Theme.Colors.Down:ToHex()
local MUTED_HEX = Theme.Colors.TextMuted:ToHex()
local TEXT_HEX = Theme.Colors.Text:ToHex()

local hoveredIndex = nil -- the candle under the crosshair, in currentChartData

do
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = ChartLegend

	ChartTickerLabel.LayoutOrder = 1
	ChartTickerLabel.Size = UDim2.fromScale(0, 1)
	ChartTickerLabel.AutomaticSize = Enum.AutomaticSize.X
end

local ChartValuesLabel =
	UIKit.makeLabel("ChartValuesLabel", ChartLegend, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.TextMuted)
ChartValuesLabel.LayoutOrder = 2
ChartValuesLabel.Size = UDim2.fromScale(0, 1)
ChartValuesLabel.AutomaticSize = Enum.AutomaticSize.X
ChartValuesLabel.RichText = true
ChartValuesLabel.Text = ""

local EmptyChartHint =
	UIKit.makeLabel("EmptyChartHint", ChartCanvas, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
EmptyChartHint.AnchorPoint = Vector2.new(0.5, 0.5)
EmptyChartHint.Position = UDim2.fromScale(0.5, 0.5)
EmptyChartHint.Size = UDim2.new(1, -40, 0, 40)
EmptyChartHint.TextWrapped = true
EmptyChartHint.TextXAlignment = Enum.TextXAlignment.Center
EmptyChartHint.Text = "Search a stock, crypto or Roblox game above to chart it"

-- What's charted: the ticker, or a Roblox game by its name
local function getChartName()
	local listed = RobloxMarket.getExperience(currentDisplayedTicker)

	return listed and listed.name or currentDisplayedTicker
end

-- "AAPL · 1H"
local function getChartTitle()
	if currentDisplayedTicker == "" then
		return "—"
	end

	return string.format("%s · %s", getChartName(), getTimeframeShort(currentTimeframe))
end

local function legendField(name, value)
	return string.format('<font color="#%s">%s</font> <font color="#%s">%.2f</font>', MUTED_HEX, name, TEXT_HEX, value)
end

local function showCandleValues(index)
	local candle = currentChartData[index]

	if not candle then
		ChartValuesLabel.Text = ""

		return
	end

	local parts = {
		legendField("O", candle.Open),
		legendField("H", candle.High),
		legendField("L", candle.Low),
		legendField("C", candle.Close),
	}
	local previous = masterChartData[currentStartIndex + index - 2]

	if previous and previous.Close ~= 0 then
		local change = candle.Close - previous.Close

		table.insert(
			parts,
			string.format(
				'<font color="#%s">%+.2f (%+.2f%%)</font>',
				change >= 0 and UP_HEX or DOWN_HEX,
				change,
				change / previous.Close * 100
			)
		)
	end

	if (candle.Volume or 0) > 0 then
		table.insert(
			parts,
			string.format(
				'<font color="#%s">Vol</font> <font color="#%s">%s</font>',
				MUTED_HEX,
				TEXT_HEX,
				NumberModule.formatCount(candle.Volume)
			)
		)
	end

	ChartValuesLabel.Text = table.concat(parts, "  ")
end

local function refreshLegend()
	ChartTickerLabel.Text = getChartTitle()
	showCandleValues(hoveredIndex or #currentChartData)
end

-- A short message in the legend's place, then the legend again
local function flashLegend(message)
	ChartTickerLabel.Text = message
	ChartValuesLabel.Text = ""
	task.delay(2.5, refreshLegend)
end

-- The active indicators for the candles in view: overlays for the price
-- chart, and panes for under it
local function getActiveIndicators(chartData)
	local overlays, panes = {}, {}

	for _, indicator in ipairs(INDICATORS) do
		if indicator.active then
			local series = if indicator.visibleOnly
				then indicator.build(chartData)
				else sliceSeries(getFullSeries(indicator), currentStartIndex, #chartData)

			series.key = indicator.key
			series.label = indicator.label
			series.color = indicator.color
			table.insert(if indicator.pane then panes else overlays, series)
		end
	end

	return overlays, panes
end

-- While a trend line waits for its second point, its first point shows as a
-- dot with a line to the cursor (the first click used to leave no trace).
-- Above the drawings, below the flyouts. Scoped: this script is near Luau's
-- 200-local limit.
local updateTrendPreview
local cancelTrendLine

do
	local DrawingPreview = UIKit.makeFrame("DrawingPreview", ChartCanvas)
	DrawingPreview.Size = UDim2.fromScale(1, 1)
	DrawingPreview.ZIndex = DrawingsContainer.ZIndex + 1
	DrawingPreview.Visible = false

	local PreviewLine = UIKit.makeFrame("Line", DrawingPreview)
	PreviewLine.AnchorPoint = Vector2.new(0.5, 0.5)
	PreviewLine.BackgroundTransparency = 0.35
	PreviewLine.BackgroundColor3 = DrawingModule.DEFAULT_COLOR
	PreviewLine.ZIndex = DrawingPreview.ZIndex

	local PreviewAnchor = UIKit.makeDot("Anchor", DrawingPreview, 7, DrawingModule.DEFAULT_COLOR)
	PreviewAnchor.ZIndex = DrawingPreview.ZIndex + 1

	local previewMousePosition = nil -- the cursor's last screen position over the chart

	-- A { timestamp, price } point's pixel position in ChartCanvas, or nil while
	-- its candle is out of view
	local function getPointPixels(point)
		if not currentMinPrice or not currentMaxPrice then
			return nil
		end

		local priceRange = currentMaxPrice - currentMinPrice
		local canvasSize = ChartCanvas.AbsoluteSize

		for index, candle in ipairs(currentChartData) do
			if candle.Timestamp == point.timestamp then
				return Vector2.new(
					(index - 0.5) / #currentChartData * canvasSize.X,
					(currentMaxPrice - point.price) / (priceRange ~= 0 and priceRange or 1) * canvasSize.Y
				)
			end
		end

		return nil
	end

	function updateTrendPreview(mousePosition)
		previewMousePosition = mousePosition or previewMousePosition

		local start = pendingTrendLineStart and getPointPixels(pendingTrendLineStart)

		if not start then
			DrawingPreview.Visible = false

			return
		end

		local finish = start

		if previewMousePosition then
			finish = Vector2.new(previewMousePosition.X, previewMousePosition.Y) - ChartCanvas.AbsolutePosition
		end

		local delta = finish - start

		PreviewAnchor.Position = UDim2.fromOffset(start.X, start.Y)
		PreviewLine.Position = UDim2.fromOffset((start.X + finish.X) / 2, (start.Y + finish.Y) / 2)
		PreviewLine.Size = UDim2.fromOffset(math.max(delta.Magnitude, 1), 2)
		PreviewLine.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		DrawingPreview.Visible = true
	end

	function cancelTrendLine()
		pendingTrendLineStart = nil
		DrawingPreview.Visible = false
	end
end

local function renderChart(ticker, chartData)
	local liveCandle = #masterChartData > 0 and masterChartData[#masterChartData] or nil
	local overlays, panes = getActiveIndicators(chartData)

	-- Panes first: the chart's size depends on how many there are
	layoutPanes(#panes)

	local minPrice, maxPrice = ChartRenderer.render({
		ChartTickerLabel = ChartTickerLabel,
		CandlesContainer = CandlesContainer,
		GridContainer = GridContainer,
		IndicatorsContainer = IndicatorsContainer,
		RightAxis = RightAxis,
		BottomAxis = BottomAxis,
	}, getChartTitle(), chartData, currentTimeframe, liveCandle, overlays)

	for index, pane in ipairs(panes) do
		ChartRenderer.renderPane(paneContents[index], pane, #chartData)
	end

	EmptyChartHint.Visible = #chartData == 0
	showCandleValues(hoveredIndex or #chartData)

	if minPrice and maxPrice then
		currentMinPrice = minPrice
		currentMaxPrice = maxPrice

		DrawingModule.render({
			DrawingsContainer = DrawingsContainer,
		}, chartData, minPrice, maxPrice, drawingsByTicker[ticker])
	end

	-- The chart moved or rescaled under a pending trend line
	if pendingTrendLineStart then
		updateTrendPreview(nil)
	end
end

local DRAWING_TOOL_BUTTONS = {
	cursor = CursorToolButton,
	trendline = TrendLineToolButton,
	horizontal = HorizontalLineToolButton,
}

-- The drawing tools show small drawn icons in their text color (the Studio
-- buttons had a letter each) and their name beside them on hover. Their
-- list sorted by name, which put Clear first.
LeftToolbar:FindFirstChildWhichIsA("UIListLayout").SortOrder = Enum.SortOrder.LayoutOrder

local toolIcons = {} -- [button] = { icon parts }

local function addIconPart(button, size, position, rotation)
	local part = Instance.new("Frame")
	part.Name = "Icon"
	part.AnchorPoint = Vector2.new(0.5, 0.5)
	part.BorderSizePixel = 0
	part.Position = UDim2.new(0.5, position.X, 0.5, position.Y)
	part.Size = UDim2.fromOffset(size.X, size.Y)
	part.Rotation = rotation or 0
	part.ZIndex = button.ZIndex + 1
	part.Parent = button

	toolIcons[button] = toolIcons[button] or {}
	table.insert(toolIcons[button], part)
end

local function colorIcon(button, color)
	for _, part in ipairs(toolIcons[button] or {}) do
		part.BackgroundColor3 = color
	end
end

-- Cursor: a crosshair
addIconPart(CursorToolButton, Vector2.new(16, 2), Vector2.zero)
addIconPart(CursorToolButton, Vector2.new(2, 16), Vector2.zero)
-- Trend line: a slanted line between two points
addIconPart(TrendLineToolButton, Vector2.new(20, 2), Vector2.zero, -35)
addIconPart(TrendLineToolButton, Vector2.new(5, 5), Vector2.new(-8, 6))
addIconPart(TrendLineToolButton, Vector2.new(5, 5), Vector2.new(8, -6))
-- Horizontal line: a level with a point on it
addIconPart(HorizontalLineToolButton, Vector2.new(20, 2), Vector2.zero)
addIconPart(HorizontalLineToolButton, Vector2.new(5, 5), Vector2.new(-6, 0))
-- Clear: a cross
addIconPart(ClearDrawingsButton, Vector2.new(16, 2), Vector2.zero, 45)
addIconPart(ClearDrawingsButton, Vector2.new(16, 2), Vector2.zero, -45)

-- One tooltip, moved into whichever tool is hovered and shown beside it
local ToolTip = UIKit.makeLabel("ToolTip", MainChart, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.Text)
ToolTip.AnchorPoint = Vector2.new(0, 0.5)
ToolTip.Position = UDim2.new(1, 6, 0.5, 0)
ToolTip.AutomaticSize = Enum.AutomaticSize.X
ToolTip.Size = UDim2.fromOffset(0, 22)
ToolTip.BackgroundTransparency = 0
ToolTip.BackgroundColor3 = Theme.Colors.Raised
ToolTip.ZIndex = 20
ToolTip.Visible = false
UIKit.addCorner(ToolTip)
UIKit.addStroke(ToolTip)

do
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = ToolTip
end

for button, name in pairs({
	[CursorToolButton] = "Cursor",
	[TrendLineToolButton] = "Trend line · click two points, right-click cancels",
	[HorizontalLineToolButton] = "Horizontal line · click a price",
	[ClearDrawingsButton] = "Clear drawings",
}) do
	button.Text = ""

	button.MouseEnter:Connect(function()
		ToolTip.Text = name
		ToolTip.Parent = button
		ToolTip.Visible = true
	end)

	button.MouseLeave:Connect(function()
		ToolTip.Visible = false
	end)
end

colorIcon(ClearDrawingsButton, COLOR_INACTIVE_TEXT)

local function setDrawingTool(tool)
	currentDrawingTool = tool
	cancelTrendLine()

	for toolName, button in pairs(DRAWING_TOOL_BUTTONS) do
		local isActive = toolName == tool
		local color = isActive and COLOR_ACTIVE_TEXT or COLOR_INACTIVE_TEXT

		button.BackgroundColor3 = isActive and COLOR_ACTIVE_BACKGROUND or COLOR_INACTIVE_BACKGROUND
		button.TextColor3 = color
		colorIcon(button, color)
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
			updateTrendPreview(mousePosition)
		else
			table.insert(drawings.trendLines, {
				t1 = pendingTrendLineStart.timestamp,
				p1 = pendingTrendLineStart.price,
				t2 = point.timestamp,
				p2 = point.price,
			})
			cancelTrendLine()
			renderChart(currentDisplayedTicker, currentChartData)
		end

		return true
	end

	return false
end

local loadTicker -- defined further down; switchTab loads the Charts tab's first chart

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

	-- The Charts tab opens on a chart rather than an empty canvas
	if tabName == "Charts" and currentDisplayedTicker == "" and not isFetchingData then
		task.spawn(loadTicker, DEFAULT_CHART_TICKER)
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
local marketPicker = nil -- built once the ticker input is wired, further down

-- The ticker box shows what's loaded on the chart - a Roblox game by its name
local function showLoadedTicker()
	if marketPicker and currentDisplayedTicker ~= "" then
		marketPicker:showLoaded(currentDisplayedTicker)
	else
		TickerInput.Text = currentDisplayedTicker
	end
end

local ACTIVE_TRADER_DISABLED_COLOR = Theme.Colors.TextDisabled

-- Sidebar. Its buttons are 25 px wide, so each label runs down its button
-- (the Studio text ran off the edge) and an accent edge marks the open
-- flyout. Open in Trade dims while nothing is charted. Scoped, like the
-- flyout fixes after it: this script is near Luau's 200-local limit.
local updateSidebar

do
	local SIDEBAR_LABEL_HEIGHT = 18
	local FLYOUT_BAR_HEIGHT = 26 -- every flyout's title bar; Active Trader's was 15
	local CLOSE_BUTTON_SIZE = 22

	local sidebarParts = {} -- [button] = { label, edge }

	for button, text in pairs({
		[ToggleActiveTraderButton] = "Active Trader",
		[ToggleSymbolInfoButton] = "Symbol Info",
		[ToggleWatchlistButton] = "Watchlist",
		[OpenInTradeButton] = "Open in Trade",
	}) do
		button.Text = ""

		local label =
			UIKit.makeLabel("Label", button, Theme.Fonts.UISemibold, Theme.TextSize.Caption, COLOR_INACTIVE_TEXT)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		-- Turned a quarter, so its width runs along the button's height
		label.Size = UDim2.fromOffset(button.Size.Y.Offset, SIDEBAR_LABEL_HEIGHT)
		label.Rotation = 90
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextTruncate = Enum.TextTruncate.None
		label.ZIndex = button.ZIndex + 1
		label.Text = text

		local edge = UIKit.makeFrame("ActiveEdge", button)
		edge.AnchorPoint = Vector2.new(0, 0.5)
		edge.Position = UDim2.fromScale(0, 0.5)
		edge.Size = UDim2.new(0, 2, 1, -16)
		edge.BackgroundTransparency = 0
		edge.BackgroundColor3 = Theme.Colors.Accent
		edge.ZIndex = button.ZIndex + 1
		edge.Visible = false

		sidebarParts[button] = { label = label, edge = edge }
	end

	function updateSidebar()
		local isOpen = {
			[ToggleActiveTraderButton] = isActiveTradeVisible,
			[ToggleSymbolInfoButton] = isSymbolInfoVisible,
			[ToggleWatchlistButton] = isWatchlistVisible,
		}
		local hasChart = currentDisplayedTicker ~= ""

		for button, parts in pairs(sidebarParts) do
			local open = isOpen[button] == true
			local enabled = button ~= OpenInTradeButton or hasChart

			parts.edge.Visible = open
			parts.label.TextColor3 = open and COLOR_ACTIVE_BACKGROUND
				or enabled and Theme.Colors.Text
				or Theme.Colors.TextDisabled
		end

		OpenInTradeButton.AutoButtonColor = hasChart
	end

	-- Flyouts. TerminalGui sorts ZIndex globally, so a flyout's contents have to
	-- sit above the panel's own background: Symbol Info's rows and Active
	-- Trader's title bar (ZIndex 1 in Studio) were drawn under it, leaving
	-- Symbol Info blank.
	local function liftAbove(panel)
		local function lift(parent, depth)
			for _, child in ipairs(parent:GetChildren()) do
				if child:IsA("GuiObject") then
					child.ZIndex = math.max(child.ZIndex, panel.ZIndex + depth)
					lift(child, depth + 1)
				end
			end
		end

		lift(panel, 1)
	end

	ActiveTraderTopBar.Size = UDim2.new(1, 0, 0, FLYOUT_BAR_HEIGHT)
	ActiveTraderContentArea.Position = UDim2.fromOffset(0, FLYOUT_BAR_HEIGHT)
	ActiveTraderContentArea.Size = UDim2.new(1, 0, 1, -FLYOUT_BAR_HEIGHT)

	-- Each title leaves room for a close button at the bar's right end
	for _, title in ipairs({
		ActiveTraderTopBar:WaitForChild("TextLabel"),
		SymbolInfoTickerLabel,
		WatchlistTopBar:WaitForChild("TitleLabel"),
	}) do
		title.Position = UDim2.fromOffset(10, 0)
		title.Size = UDim2.new(1, -(10 + CLOSE_BUTTON_SIZE + 6), 1, 0)
		title.TextTruncate = Enum.TextTruncate.AtEnd
	end

	for _, panel in ipairs({ ActiveTraderPanel, SymbolInfoPanel, WatchlistPanel }) do
		liftAbove(panel)
	end

	local function addCloseButton(topBar, isOpen, close)
		local button = Instance.new("TextButton")
		button.Name = "CloseButton"
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -2, 0.5, 0)
		button.Size = UDim2.fromOffset(CLOSE_BUTTON_SIZE, CLOSE_BUTTON_SIZE)
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.FontFace = Theme.Fonts.UISemibold
		button.TextSize = Theme.TextSize.Title
		button.TextColor3 = Theme.Colors.TextMuted
		button.Text = "×"
		button.ZIndex = topBar.ZIndex + 2
		button.Parent = topBar

		button.MouseEnter:Connect(function()
			button.TextColor3 = Theme.Colors.Text
		end)

		button.MouseLeave:Connect(function()
			button.TextColor3 = Theme.Colors.TextMuted
		end)

		button.MouseButton1Click:Connect(function()
			if isOpen() then
				close()
			end
		end)
	end

	addCloseButton(ActiveTraderTopBar, function()
		return isActiveTradeVisible
	end, function()
		toggleActiveTrader()
	end)

	addCloseButton(SymbolInfoTopBar, function()
		return isSymbolInfoVisible
	end, function()
		toggleSymbolInfo()
	end)

	addCloseButton(WatchlistTopBar, function()
		return isWatchlistVisible
	end, function()
		toggleWatchlist()
	end)
end

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

	updateSidebar()

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

	updateSidebar()

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

	updateSidebar()

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

local DAILY_CANDLES_SECONDS = 600
local dailyCandles = {} -- [ticker] = { fetchedAt, candles }, for Symbol Info's year

-- The latest UTC day's range and volume in the loaded candles
local function getDayFromCandles()
	local last = masterChartData[#masterChartData]

	if not last then
		return nil
	elseif currentTimeframe == "D" then
		return { low = last.Low, high = last.High, volume = last.Volume or 0 }
	end

	local day = last.Timestamp // 86400
	local low, high, volume = math.huge, -math.huge, 0

	for index = #masterChartData, 1, -1 do
		local candle = masterChartData[index]

		if candle.Timestamp // 86400 ~= day then
			break
		end

		low = math.min(low, candle.Low)
		high = math.max(high, candle.High)
		volume += candle.Volume or 0
	end

	return { low = low, high = high, volume = volume }
end

-- The last year's range and the average daily volume over about three
-- months, from daily candles (fetched once per ticker every few minutes)
local function getYearFromCandles(ticker)
	local candles = currentTimeframe == "D" and masterChartData or nil
	local cached = dailyCandles[ticker]

	if not candles and cached and os.clock() - cached.fetchedAt < DAILY_CANDLES_SECONDS then
		candles = cached.candles
	elseif not candles then
		candles = RequestChartEvent:InvokeServer(ticker, "D") or {}
		dailyCandles[ticker] = { fetchedAt = os.clock(), candles = candles }
	end

	local last = candles[#candles]

	if not last then
		return nil
	end

	local low, high = math.huge, -math.huge
	local volumeTotal, volumeDays = 0, 0

	for index = #candles, 1, -1 do
		local candle = candles[index]

		if candle.Timestamp < last.Timestamp - 365 * 86400 then
			break
		end

		low = math.min(low, candle.Low)
		high = math.max(high, candle.High)

		if volumeDays < 63 and (candle.Volume or 0) > 0 then
			volumeTotal += candle.Volume
			volumeDays += 1
		end
	end

	return { low = low, high = high, averageVolume = volumeDays > 0 and volumeTotal / volumeDays or nil }
end

local function formatRange(low, high)
	return (low and high) and string.format("%.2f - %.2f", low, high) or "—"
end

-- Symbol Info for a stock, ETF or crypto, under the Studio labels. When the
-- quote has no details (the data provider refuses them at times), the day,
-- the year and volume come from candles instead.
local function getSecurityInfo(quote)
	local day = (not quote.dayLow or not quote.volume) and getDayFromCandles() or nil
	local year = (not quote.fiftyTwoWeekLow or not quote.avgVolume) and getYearFromCandles(currentDisplayedTicker)
		or nil
	local volume = quote.volume or (day and day.volume > 0 and day.volume)
	local averageVolume = quote.avgVolume or (year and year.averageVolume)

	return {
		quote.marketCap and NumberModule.formatCompact(quote.marketCap) or "—",
		quote.trailingPE and string.format("%.2f", quote.trailingPE) or "—",
		quote.eps and string.format("%.2f", quote.eps) or "—",
		quote.dayLow and formatRange(quote.dayLow, quote.dayHigh) or formatRange(day and day.low, day and day.high),
		quote.fiftyTwoWeekLow and formatRange(quote.fiftyTwoWeekLow, quote.fiftyTwoWeekHigh)
			or formatRange(year and year.low, year and year.high),
		volume and NumberModule.formatCount(volume) or "—",
		averageVolume and NumberModule.formatCount(averageVolume) or "—",
		quote.beta and string.format("%.2f", quote.beta) or "—",
		quote.dividendYield and string.format("%.2f%%", quote.dividendYield) or "—",
	}
end

-- Symbol Info for a Roblox game: its own fields, each labeled observed,
-- estimated or simulated (GDD §6)
local function getRobloxInfo(data)
	local observed = data.observed or {}
	local votes = (observed.upVotes or 0) + (observed.downVotes or 0)

	local function count(value)
		return value and NumberModule.formatCount(value) or "—"
	end

	return {
		{ "Players now · observed", count(observed.playing) },
		{ "7-day avg players · estimated", count(data.averagePlaying) },
		{ "Players vs usual · estimated", data.vsUsual and string.format("%+.0f%%", data.vsUsual * 100) or "—" },
		{ "Like ratio · observed", votes > 0 and string.format("%.1f%%", observed.upVotes / votes * 100) or "—" },
		{ "Visits · observed", count(observed.visits) },
		{ "Favorites · observed", count(observed.favorites) },
		{ "Target price · simulated", data.target and string.format("%.2f", data.target) or "—" },
		{ "Updated · observed", observed.updated and os.date("!%Y-%m-%d", observed.updated) or "—" },
		{ "Genre · observed", observed.genre or "—" },
	}
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

	-- Presets turn dollars into shares at the ask, or at the price where
	-- there's no ask (a Roblox game, or a quote without bid/ask); the server
	-- prices the fill either way
	if quote.ask then
		activeTraderAsk = quote.ask
		ActiveTraderAskPriceLabel.Text = string.format("Ask %.2f", quote.ask)
	elseif quote.price then
		activeTraderAsk = quote.price
		ActiveTraderAskPriceLabel.Text = string.format("Price %.2f", quote.price)
	end

	if quote.assetClass == "roblox" then
		SymbolInfoTickerLabel.Text = quote.name or currentDisplayedTicker

		for index, field in ipairs(getRobloxInfo(quote)) do
			SymbolInfoRows[index].label.Text = field[1]
			SymbolInfoRows[index].value.Text = field[2]
		end
	else
		SymbolInfoTickerLabel.Text = currentDisplayedTicker

		for index, value in ipairs(getSecurityInfo(quote)) do
			SymbolInfoRows[index].label.Text = SymbolInfoRows[index].stockLabel
			SymbolInfoRows[index].value.Text = value
		end
	end
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

	-- Crypto and the Roblox market trade around the clock
	if
		not Instruments.tradesAroundTheClock(currentDisplayedTicker)
		and not MarketHoursModule.getMarketStatus(os.time())
	then
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

	-- Crypto and the Roblox market trade around the clock
	if
		not Instruments.tradesAroundTheClock(currentDisplayedTicker)
		and not MarketHoursModule.getMarketStatus(os.time())
	then
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

	-- At least 10 candles, unless the series is shorter (a new Roblox listing)
	visibleCandles = math.clamp(visibleCandles, math.min(10, #masterChartData), #masterChartData)
	rightOffset = math.clamp(rightOffset, 0, #masterChartData - visibleCandles)

	local startIndex = #masterChartData - rightOffset - visibleCandles + 1
	local endIndex = #masterChartData - rightOffset

	currentStartIndex = startIndex
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
		showLoadedTicker()
		return
	end

	-- A pending trend-line first point belongs to whatever ticker's candle
	-- series was showing when it was placed - discard it on ticker switch.
	cancelTrendLine()

	isFetchingData = true

	TickerInput.Text = " . . . "
	ChartTickerLabel.Text = "Loading"

	local chartData = RequestChartEvent:InvokeServer(targetTicker, currentTimeframe)

	if chartData and #chartData > 0 then
		masterChartData = chartData
		currentDisplayedTicker = targetTicker
		rightOffset = 0
		activeTraderAsk = nil -- the last ticker's; updateSymbolData fetches this one's
		showLoadedTicker()
		ActiveTraderTickerLabel.Text = targetTicker
		ActiveTraderStatusLabel.Text = ""
		updateViewport()
		updateSymbolData()
		updateActiveTraderPosition()
		updateSidebar()
	else
		TickerInput.Text = " . . . "
		flashLegend("Couldn't load " .. targetTicker)
		task.delay(2, showLoadedTicker)
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

local function setTimeframe(query)
	currentTimeframe = query
	updateTimeframeUI(query)
	MainTimeframeButton.Text = getTimeframeShort(query) .. " ▾"
end

for button, data in pairs(TimeDropdownOptions) do
	button.MouseButton1Click:Connect(function()
		isDropdownOpen = false
		TimeDropdownList.Visible = false

		if isFetchingData or data.query == currentTimeframe then
			return
		end

		local previousTimeframe = currentTimeframe

		setTimeframe(data.query)
		cancelTrendLine()

		if currentDisplayedTicker == "" then
			return
		end

		isFetchingData = true
		ChartTickerLabel.Text = "Loading"
		ChartValuesLabel.Text = ""
		updateScrollBarUI()

		local chartData = RequestChartEvent:InvokeServer(currentDisplayedTicker, data.query)

		if chartData and #chartData > 0 then
			masterChartData = chartData
			rightOffset = 0
			updateViewport()
		else
			-- Stay on the chart that's showing
			setTimeframe(previousTimeframe)
			flashLegend(string.format("No %s chart for %s", data.option, getChartName()))
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

-- Profiles live on the Leaderboards tab; LeaderboardController loads it
Navigation.ProfileRequested:Connect(function()
	switchTab("Leaderboards")
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

local function isUnlocked(feature)
	return Progression.isUnlocked(Player:GetAttribute("Level") or 1, feature)
end

-- Below an indicator's unlock level its option is dimmed, does nothing and
-- names the level; below the first, the dropdown's button names it too
local function updateIndicatorLock()
	MainIndicatorsButton.Text = isUnlocked("ChartIndicators") and INDICATORS_BUTTON_TEXT
		or string.format("%s · Lv %d", INDICATORS_BUTTON_TEXT, Progression.FEATURES.ChartIndicators)

	for _, indicator in ipairs(INDICATORS) do
		local unlocked = isUnlocked(indicator.feature)

		indicator.button.Text = unlocked and indicator.label
			or string.format("%s · Lv %d", indicator.label, Progression.FEATURES[indicator.feature])

		if not indicator.active then
			indicator.button.TextColor3 = unlocked and COLOR_INACTIVE_TEXT or Theme.Colors.TextDisabled
		end
	end
end

for _, indicator in ipairs(INDICATORS) do
	local button = indicator.button

	button.MouseButton1Click:Connect(function()
		if not isUnlocked(indicator.feature) then
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

-- Hides the crosshair and its price and time tags, and the legend goes back
-- to the latest candle
local function hideCrosshair()
	CrosshairX.Visible = false
	CrosshairY.Visible = false
	HoverPriceTag.Visible = false
	HoverTimeTag.Visible = false

	if hoveredIndex then
		hoveredIndex = nil
		showCandleValues(#currentChartData)
	end
end

hideCrosshair() -- the Studio tags start shown, reading "Label"

ChartCanvas.InputBegan:Connect(function(input)
	if isDraggingScroll then
		return
	end

	-- Right-click drops a half-placed trend line, then puts the tool down
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if pendingTrendLineStart then
			cancelTrendLine()
		elseif currentDrawingTool ~= "cursor" then
			setDrawingTool("cursor")
		end

		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if handleDrawingClick(input.Position) then
			return
		end

		isDraggingChart = true
		lastMouseDragX = input.Position.X

		hideCrosshair()
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

	if pendingTrendLineStart and input.UserInputType == Enum.UserInputType.MouseMovement then
		updateTrendPreview(input.Position)
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

				if hoveredIndex ~= index then
					hoveredIndex = index
					showCandleValues(index)
				end
			else
				hideCrosshair()
			end
		end
	end
end)

ChartCanvas.InputEnded:Connect(function()
	hideCrosshair()
	isDraggingChart = false
end)

-- Ticker input (real-world market; the picker handles Roblox searches)
TickerInput.FocusLost:Connect(function(enterPressed)
	if marketPicker:getMarket() == "Roblox" then
		return
	end

	if enterPressed then
		loadTicker(TickerInput.Text)
		return
	end

	-- Clicked/tabbed away without pressing Enter - discard whatever was
	-- typed instead of leaving stale text sitting in the box forever.
	showLoadedTicker()
end)

-- The market picker takes the ticker box's place in the toolbar: a market
-- dropdown, then the box, which searches games in the Roblox market
local PickerRow = Instance.new("Frame")
PickerRow.Name = "MarketPickerRow"
PickerRow.BackgroundTransparency = 1
PickerRow.LayoutOrder = TickerInputBox.LayoutOrder
PickerRow.Size = UDim2.new(0, MarketPickerModule.ROW_WIDTH, 1, 0)
PickerRow.Parent = TopToolbar
TickerInputBox.Parent = PickerRow

marketPicker = MarketPickerModule.new({
	inputRow = PickerRow,
	input = TickerInput,
	inputFrame = TickerInputBox,
	overlayParent = MainBackground,
	screen = ChartsScreen,
	onSelect = function(ticker)
		task.spawn(loadTicker, ticker)
	end,
})

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
		local maxOffset = math.max(#masterChartData - visibleCandles, 0)

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

-- The Sidebar's fourth button opens what's charted on the Trade tab, for the
-- order ticket and research
OpenInTradeButton.MouseButton1Click:Connect(function()
	if currentDisplayedTicker ~= "" then
		Navigation.openTicker(currentDisplayedTicker)
	end
end)

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
	cancelTrendLine()
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

for _, indicator in ipairs(INDICATORS) do
	indicator.button.BackgroundColor3 = COLOR_INACTIVE_BACKGROUND
	indicator.button.TextColor3 = COLOR_INACTIVE_TEXT
end

Player:GetAttributeChangedSignal("Level"):Connect(updateIndicatorLock)

switchTab("Dashboard")
updateIndicatorLock()
setDrawingTool(currentDrawingTool) -- the Studio defaults no longer show which tool is active
updateSidebar() -- Open in Trade starts dimmed: nothing is charted yet
setTimeframe(currentTimeframe) -- the Studio button reads the bare query, "H"
updateGreeting()
updateActiveTraderPosition() -- grays out Sell presets until a position exists
ChartTickerLabel.Text = "—" -- otherwise this shows Studio's literal default "Label" until a ticker loads
