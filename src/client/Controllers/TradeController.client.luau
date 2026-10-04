-- TradeController.client.luau
--
-- Handles Trade Screen

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remote
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetMarketDataEvent = EventsFolder:WaitForChild("GetMarketDataEvent")
local RequestChartEvent = EventsFolder:WaitForChild("RequestChartEvent")
local GetOptionsDataEvent = EventsFolder:WaitForChild("GetOptionsDataEvent")
local GetPositionsEvent = EventsFolder:WaitForChild("GetPositionsEvent")
local GetNewsFeedEvent = EventsFolder:WaitForChild("GetNewsFeedEvent")
local PlayerOrderEvent = EventsFolder:WaitForChild("PlayerOrderEvent")
local GetAnalystReportEvent = EventsFolder:WaitForChild("GetAnalystReportEvent")
local GetFundamentalsEvent = EventsFolder:WaitForChild("GetFundamentalsEvent")
local GetOptionStatsEvent = EventsFolder:WaitForChild("GetOptionStatsEvent")

-- References
local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local MainBackground = TerminalGui:WaitForChild("MainBackground")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")
local TradeScreen = ScreenContainer:WaitForChild("TradeScreen")
local HeaderRow = TradeScreen:WaitForChild("HeaderRow")
local BuyButton = HeaderRow:WaitForChild("BuyButton")
local SellButton = HeaderRow:WaitForChild("SellButton")
local CompanyLabel = HeaderRow:WaitForChild("CompanyLabel")
local TickerLabel = HeaderRow:WaitForChild("TickerLabel")
local InputRow = TradeScreen:WaitForChild("InputRow")
local TickerInput = InputRow:WaitForChild("TickerInput")
local MiniChart = TradeScreen:WaitForChild("MiniChart")
local NewsFeed = TradeScreen:WaitForChild("NewsFeed")
local OptionChain = TradeScreen:WaitForChild("OptionChain")
local ChainData = OptionChain:WaitForChild("ChainData")
local ColumnHeaders = ChainData:WaitForChild("ColumnHeaders")
local ChainToggle = OptionChain:WaitForChild("Toggle")
local PositionsTable = TradeScreen:WaitForChild("PositionsTable")
local TableHeader = PositionsTable:WaitForChild("TableHeader")
local QuoteDetails = TradeScreen:WaitForChild("QuoteDetails")
local TabContentContainer = QuoteDetails:WaitForChild("TabContentContainer")
local TabHeaderContainer = QuoteDetails:WaitForChild("TabHeaderContainer")
local ContentQuoteDetails = TabContentContainer:WaitForChild("Content_QuoteDetails")
local ContentAnalystReports = TabContentContainer:WaitForChild("Content_AnalystReports")
local ContentFundamentals = TabContentContainer:WaitForChild("Content_Fundamentals")
local ContentOptionStats = TabContentContainer:WaitForChild("Content_OptionStats")

-- Contants
local GREEN = Color3.fromRGB(8, 153, 129)
local RED = Color3.fromRGB(242, 54, 69)
local GRAY = Color3.fromRGB(132, 142, 156)

local TEXT_PRIMARY = Color3.fromRGB(209, 212, 220)
local TEXT_SECONDARY = Color3.fromRGB(132, 142, 156)
local BG_ROW_EVEN = Color3.fromRGB(22, 26, 35)
local BG_ROW_ODD = Color3.fromRGB(18, 22, 30)
local BG_ITM = Color3.fromRGB(28, 40, 58) -- In-The-Money
local BG_OTM = Color3.fromRGB(18, 22, 30) -- Out-The-Money

local COLOR_TAB_ACTIVE = Color3.fromRGB(209, 212, 220)
local COLOR_TAB_INACTIVE = Color3.fromRGB(120, 123, 134)

local TWEEN_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MED = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local QUOTE_FIELDS = {
	{ label = "Volume", key = "volume", format = "count" },
	{ label = "Avg Volume", key = "avgVolume", format = "count" },
	{ label = "Beta", key = "beta", format = "decimal2" },
	{ label = "Market Cap", key = "marketCap", format = "compact" },
	{ label = "Yield", key = "dividendYield", format = "percent" },
	{ label = "Div Amount", key = "dividendRate", format = "price" },
	{ label = "Ex Date", key = "exDividendDate", format = "date" },
	{ label = "PE (Trailing)", key = "trailingPE", format = "decimal2" },
	{ label = "PE (Forward)", key = "forwardPE", format = "decimal2" },
	{ label = "EPS", key = "eps", format = "decimal2" },
	{ label = "Earnings", key = "earningsDate", format = "date" },
	{ label = "Day High", key = "dayHigh", format = "price" },
	{ label = "Day Low", key = "dayLow", format = "price" },
	{ label = "52-Wk High", key = "fiftyTwoWeekHigh", format = "price" },
	{ label = "52-Wk Low", key = "fiftyTwoWeekLow", format = "price" },
}

local POSITION_COLUMNS = {
	{ key = "mark", format = "price", label = "Mark", width = 70 },
	{ key = "markChange", format = "change", label = "Chng $", width = 70 },
	{ key = "plDay", format = "change", label = "P/L Day", width = 80 },
	{ key = "plOpen", format = "change", label = "P/L Open", width = 80 },
	{ key = "netLiq", format = "price", label = "Net Liq", width = 70 },
	{ key = "tradePrice", format = "price", label = "Trade Price", width = 85 },
	{ key = "cost", format = "price", label = "Cost", width = 70 },
	{ key = "delta", format = "decimal2", label = "Delta", width = 55 },
	{ key = "theta", format = "decimal2", label = "Theta", width = 55 },
	{ key = "plOpenPct", format = "percent", label = "P/L Open %", width = 75 },
}

local ANALYST_FIELDS = {
	{ label = "Mean Target", key = "targetMean", format = "price" },
	{ label = "High Target", key = "targetHigh", format = "price" },
	{ label = "Low Target", key = "targetLow", format = "price" },
	{ label = "Median Target", key = "targetMedian", format = "price" },
	{ label = "Rating", key = "recommendationKey", format = "auto" },
	{ label = "Rating Score (1-5)", key = "recommendationMean", format = "decimal2" },
	{ label = "# Analysts", key = "numberOfAnalysts", format = "count" },
	{ label = "Strong Buy", key = "strongBuyCount", format = "count" },
	{ label = "Buy", key = "buyCount", format = "count" },
	{ label = "Hold", key = "holdCount", format = "count" },
	{ label = "Sell", key = "sellCount", format = "count" },
	{ label = "Strong Sell", key = "strongSellCount", format = "count" },
}

local FUNDAMENTALS_FIELDS = {
	{ label = "Revenue", key = "totalRevenue", format = "compact" },
	{ label = "Gross Margin", key = "grossMargins", format = "percent" },
	{ label = "Operating Margin", key = "operatingMargins", format = "percent" },
	{ label = "Profit Margin", key = "profitMargins", format = "percent" },
	{ label = "ROE", key = "returnOnEquity", format = "percent" },
	{ label = "ROA", key = "returnOnAssets", format = "percent" },
	{ label = "Cash", key = "totalCash", format = "compact" },
	{ label = "Debt", key = "totalDebt", format = "compact" },
	{ label = "Debt/Equity", key = "debtToEquity", format = "decimal2" },
	{ label = "Free Cash Flow", key = "freeCashflow", format = "compact" },
	{ label = "P/B", key = "priceToBook", format = "decimal2" },
	{ label = "PEG Ratio", key = "pegRatio", format = "decimal2" },
	{ label = "EV/EBITDA", key = "enterpriseToEbitda", format = "decimal2" },
	{ label = "Revenue Growth", key = "revenueGrowth", format = "percent" },
	{ label = "Earnings Growth", key = "earningsGrowth", format = "percent" },
}

local OPTION_STATS_ROWS = {
	{ label = "Bid", key = "bid", format = "price" },
	{ label = "Ask", key = "ask", format = "price" },
	{ label = "Last", key = "lastPrice", format = "price" },
	{ label = "IV", key = "impliedVolatility", format = "percent" },
	{ label = "Volume", key = "volume", format = "count" },
	{ label = "Open Interest", key = "openInterest", format = "count" },
}

-- State
local currentTicker = ""
local currentPrice = 0
local currentPrevClose = 0
local currentQuoteData = nil
local currentOptionData = nil
local currentAnalystData = nil
local currentFundamentalsData = nil
local currentOptionStatsData = nil
local isFetchingData = false
local activeTabName = ""
local chainExpanded = true
local orderQuantity = 1

-- Map
local TabButtons = {
	QuoteDetails = TabHeaderContainer:WaitForChild("Tab_QuoteDetails"),
	AnalystReports = TabHeaderContainer:WaitForChild("Tab_AnalystReports"),
	Fundamentals = TabHeaderContainer:WaitForChild("Tab_Fundamentals"),
	OptionStats = TabHeaderContainer:WaitForChild("Tab_OptionStats"),
}

local TabContents = {
	QuoteDetails = ContentQuoteDetails,
	AnalystReports = ContentAnalystReports,
	Fundamentals = ContentFundamentals,
	OptionStats = ContentOptionStats,
}

--

local function formatValue(value, formatType)
	if value == nil or value == "" then
		return "—"
	end

	if formatType == "price" then
		return string.format("%.2f", value)
	elseif formatType == "decimal2" then
		return string.format("%.2f", value)
	elseif formatType == "percent" then
		return string.format("%.2f%%", value)
	elseif formatType == "change" then
		local sign = value >= 0 and "+" or ""

		return string.format("%s%.2f", sign, value)
	elseif formatType == "number" then
		return NumberModule.format(value)
	elseif formatType == "count" then
		return NumberModule.formatShares(value)
	elseif formatType == "compact" then
		return NumberModule.formatCompact(value)
	elseif formatType == "date" then
		local text = tostring(value)

		-- Backend passes Yahoo Date objects through as ISO-8601; only the day matters here.
		return string.match(text, "^%d%d%d%d%-%d%d%-%d%d") or text
	elseif formatType == "auto" then
		return tostring(value)
	end

	return tostring(value)
end

local function getChangeColor(value)
	if value == nil then
		return GRAY
	end
	if value > 0 then
		return GREEN
	end
	if value < 0 then
		return RED
	end
	return GRAY
end

-- Attaches Hover Highlight
local function attachHover(button, baseColor, hoverColor)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_FAST, { BackgroundColor3 = hoverColor }):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, TWEEN_FAST, { BackgroundColor3 = baseColor }):Play()
	end)
end

-- Header
local function updateHeader(data, livePrice)
	local price = livePrice or (data and data.price) or 0
	local prevClose = (data and data.prevClose) or price
	local change = price - prevClose
	local changePct = prevClose ~= 0 and ((change / prevClose) * 100) or 0
	local color = change >= 0 and GREEN or RED

	TickerLabel.Text = (data and data.ticker) or currentTicker or "—"
	CompanyLabel.Text = (data and data.companyName) or "—"

	local priceLabel = HeaderRow:FindFirstChild("PriceLabel")
	local changeLabel = HeaderRow:FindFirstChild("ChangeLabel")

	if priceLabel then
		priceLabel.Text = string.format("%.2f", price)
		priceLabel.TextColor3 = color
	end

	if changeLabel then
		changeLabel.Text = string.format("%s%.2f (%.2f%%)", change >= 0 and "+" or "", change, changePct)
		changeLabel.TextColor3 = color
	end

	local bid = data and data.bid
	local ask = data and data.ask
	local bidSize = data and data.bidSize
	local askSize = data and data.askSize

	if ask then
		BuyButton.Text = string.format("Buy  %.2f", ask)
	end

	if bid then
		SellButton.Text = string.format("Sell  %.2f", bid)
	end

	local bidSizeLabel = HeaderRow:FindFirstChild("BidSizeLabel")
	local askSizeLabel = HeaderRow:FindFirstChild("AskSizeLabel")

	if bidSizeLabel and bidSize then
		bidSizeLabel.Text = "Bid size: " .. bidSize
	end

	if askSizeLabel and askSize then
		askSizeLabel.Text = "Ask size: " .. askSize
	end
end

-- UIGridLayout has no `Enabled` property (confirmed live - Studio throws
-- "Enabled is not a valid member of UIGridLayout"), so "toggling" it off/on
-- means unparenting/reparenting the same instance instead. Cache the lookup
-- once per container: FindFirstChildOfClass can't find it while detached, so
-- a fresh lookup after renderUnavailable has run would silently return nil.
local GridLayoutCache = {}

local function getGridLayout(container)
	local cached = GridLayoutCache[container]

	if cached == nil then
		cached = container:FindFirstChildOfClass("UIGridLayout") or false
		GridLayoutCache[container] = cached
	end

	return cached or nil
end

-- Renders a flat label/value grid into `container`, clearing any previous
-- rows tagged with `prefix` first. Shared by Quote Details, Analyst
-- Reports, and Fundamentals - all three are flat field-list tabs.
local function renderFieldGrid(container, fields, data, prefix)
	for _, child in pairs(container:GetChildren()) do
		if child:IsA("Frame") and string.match(child.Name, "^" .. prefix) then
			child:Destroy()
		end
	end

	local gridLayout = getGridLayout(container)

	if gridLayout then
		gridLayout.Parent = container
	end

	if not data then
		return
	end

	for i, field in ipairs(fields) do
		local row = Instance.new("Frame")

		row.Name = prefix .. field.key
		row.Size = UDim2.new(0.5, -4, 0, 22)
		row.BackgroundTransparency = 1
		row.LayoutOrder = i
		row.Parent = container

		local lbl = Instance.new("TextLabel")

		lbl.Name = "Label"
		lbl.Text = field.label
		lbl.Size = UDim2.new(0.55, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = TEXT_SECONDARY
		lbl.Font = Enum.Font.SourceSans
		lbl.TextSize = 13
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = row

		local val = Instance.new("TextLabel")

		val.Name = "Value"
		val.Text = formatValue(data[field.key], field.format)
		val.Size = UDim2.new(0.45, 0, 1, 0)
		val.Position = UDim2.fromScale(0.55, 0)
		val.BackgroundTransparency = 1
		val.TextColor3 = TEXT_PRIMARY
		val.Font = Enum.Font.SourceSansSemibold
		val.TextSize = 13
		val.TextXAlignment = Enum.TextXAlignment.Right
		val.Parent = row
	end
end

-- Shows a single centered message instead of a field grid - used when a
-- tab's data comes back { available = false } (e.g. Analyst/Fundamentals
-- for a crypto ticker with no Yahoo coverage).
local function renderUnavailable(container, prefix, message)
	for _, child in pairs(container:GetChildren()) do
		if child:IsA("Frame") and string.match(child.Name, "^" .. prefix) then
			child:Destroy()
		end
	end

	local gridLayout = getGridLayout(container)

	if gridLayout then
		gridLayout.Parent = nil
	end

	local row = Instance.new("Frame")

	row.Name = prefix .. "Unavailable"
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.Parent = container

	local lbl = Instance.new("TextLabel")

	lbl.Name = "Label"
	lbl.Text = message
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = TEXT_SECONDARY
	lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.Parent = row
end

-- Builds a single TextLabel from a props table. Moved up here (ahead of its
-- original spot near the Option Chain row-builders) so the two-column Option
-- Stats renderer below - and switchTab's lazy-fetch wiring further down - can
-- call it; Luau locals aren't visible above their declaration.
local function makeLabel(parent, props)
	local lbl = Instance.new("TextLabel")

	lbl.Name = props.name or "Label"
	lbl.Text = props.text or ""
	lbl.Size = props.sz or UDim2.new(1, 0, 1, 0)
	lbl.Position = props.pos or UDim2.fromOffset(0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = props.font or Enum.Font.SourceSans
	lbl.TextSize = props.size or 13
	lbl.TextColor3 = props.color or TEXT_PRIMARY
	lbl.TextXAlignment = props.align or Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.ZIndex = props.zindex or 1
	lbl.Parent = parent

	return lbl
end

local function renderAnalystReport(data)
	if not data then
		renderUnavailable(ContentAnalystReports, "AR_", "Data unavailable — try again")
		return
	end

	if data.available == false then
		renderUnavailable(ContentAnalystReports, "AR_", "Not available for this asset")
		return
	end

	renderFieldGrid(ContentAnalystReports, ANALYST_FIELDS, data, "AR_")
end

local function fetchAnalystReport()
	local ticker = currentTicker
	local data = GetAnalystReportEvent:InvokeServer(ticker)

	if ticker ~= currentTicker then
		return
	end

	currentAnalystData = data
	renderAnalystReport(data)
end

local function renderFundamentals(data)
	if not data then
		renderUnavailable(ContentFundamentals, "FN_", "Data unavailable — try again")
		return
	end

	if data.available == false then
		renderUnavailable(ContentFundamentals, "FN_", "Not available for this asset")
		return
	end

	renderFieldGrid(ContentFundamentals, FUNDAMENTALS_FIELDS, data, "FN_")
end

local function fetchFundamentals()
	local ticker = currentTicker
	local data = GetFundamentalsEvent:InvokeServer(ticker)

	if ticker ~= currentTicker then
		return
	end

	currentFundamentalsData = data
	renderFundamentals(data)
end

-- Option Stats isn't a flat field list like the three tabs above it - the
-- payload is inherently two-sided (call vs put) - so it gets its own
-- clear/render pair instead of going through renderFieldGrid.
local function clearOptionStats()
	for _, child in pairs(ContentOptionStats:GetChildren()) do
		if child:IsA("Frame") and string.match(child.Name, "^OS_") then
			child:Destroy()
		end
	end
end

local function renderOptionStats(data)
	clearOptionStats()

	if not data then
		renderUnavailable(ContentOptionStats, "OS_", "Data unavailable — try again")
		return
	end

	if data.available == false then
		renderUnavailable(ContentOptionStats, "OS_", "Not available for this asset")
		return
	end

	local header = Instance.new("Frame")

	header.Name = "OS_Header"
	header.Size = UDim2.new(1, 0, 0, 22)
	header.BackgroundTransparency = 1
	header.LayoutOrder = 0
	header.Parent = ContentOptionStats

	makeLabel(header, {
		name = "HeaderLabel",
		text = string.format("Nearest Expiry: %s   ·   Strike: %.2f", formatValue(data.expiration, "date"), data.strike or 0),
		sz = UDim2.new(1, 0, 1, 0),
		color = TEXT_SECONDARY,
		font = Enum.Font.SourceSansSemibold,
		align = Enum.TextXAlignment.Left,
	})

	local columnsRow = Instance.new("Frame")

	columnsRow.Name = "OS_Columns"
	columnsRow.Size = UDim2.new(1, 0, 0, 20)
	columnsRow.BackgroundTransparency = 1
	columnsRow.LayoutOrder = 1
	columnsRow.Parent = ContentOptionStats

	makeLabel(columnsRow, {
		name = "CallHeader",
		text = "CALL",
		sz = UDim2.new(0.35, 0, 1, 0),
		pos = UDim2.fromScale(0.4, 0),
		color = TEXT_SECONDARY,
		font = Enum.Font.SourceSansSemibold,
		align = Enum.TextXAlignment.Center,
	})

	makeLabel(columnsRow, {
		name = "PutHeader",
		text = "PUT",
		sz = UDim2.new(0.35, 0, 1, 0),
		pos = UDim2.fromScale(0.75, 0),
		color = TEXT_SECONDARY,
		font = Enum.Font.SourceSansSemibold,
		align = Enum.TextXAlignment.Center,
	})

	for i, field in ipairs(OPTION_STATS_ROWS) do
		local row = Instance.new("Frame")

		row.Name = "OS_" .. field.key
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundTransparency = 1
		row.LayoutOrder = i + 1
		row.Parent = ContentOptionStats

		makeLabel(row, {
			name = "Label",
			text = field.label,
			sz = UDim2.new(0.4, 0, 1, 0),
			color = TEXT_SECONDARY,
			align = Enum.TextXAlignment.Left,
		})

		makeLabel(row, {
			name = "CallValue",
			text = formatValue(data.call and data.call[field.key], field.format),
			sz = UDim2.new(0.3, 0, 1, 0),
			pos = UDim2.fromScale(0.4, 0),
			color = TEXT_PRIMARY,
			align = Enum.TextXAlignment.Center,
		})

		makeLabel(row, {
			name = "PutValue",
			text = formatValue(data.put and data.put[field.key], field.format),
			sz = UDim2.new(0.3, 0, 1, 0),
			pos = UDim2.fromScale(0.75, 0),
			color = TEXT_PRIMARY,
			align = Enum.TextXAlignment.Center,
		})
	end
end

local function fetchOptionStats()
	local ticker = currentTicker
	local data = GetOptionStatsEvent:InvokeServer(ticker)

	if ticker ~= currentTicker then
		return
	end

	currentOptionStatsData = data
	renderOptionStats(data)
end

local function renderQuoteDetails(data)
	renderFieldGrid(ContentQuoteDetails, QUOTE_FIELDS, data, "QF_")
end

-- Refresh Quotes
local function updateQuoteField(key, value, format)
	local row = ContentQuoteDetails:FindFirstChild("QF_" .. key)

	if not row then
		return
	end

	local valLabel = row:FindFirstChild("Value")

	if valLabel then
		valLabel.Text = formatValue(value, format)
	end
end

-- Tabs
local function switchTab(tabName)
	if tabName == "AnalystReports" and currentTicker ~= "" and not currentAnalystData then
		fetchAnalystReport()
	end

	if tabName == "Fundamentals" and currentTicker ~= "" and not currentFundamentalsData then
		fetchFundamentals()
	end

	if tabName == "OptionStats" and currentTicker ~= "" and not currentOptionStatsData then
		fetchOptionStats()
	end

	if activeTabName == tabName then
		return
	end

	activeTabName = tabName

	for name, button in pairs(TabButtons) do
		local isActive = (name == tabName)

		TweenService:Create(button, TWEEN_FAST, { TextColor3 = isActive and COLOR_TAB_ACTIVE or COLOR_TAB_INACTIVE })
			:Play()

		local ActiveIndicator = button:FindFirstChild("ActiveIndicator")

		if ActiveIndicator then
			ActiveIndicator.Visible = isActive
		end
	end

	for name, frame in pairs(TabContents) do
		frame.Visible = (name == tabName)
	end
end

-- Row
local TICKER_COL_WIDTH = 90
local ROW_HEIGHT_CHAIN = 28
local ROW_HEIGHT_POS = 24
local ROW_HEIGHT_NEWS = 44

-- separator line
local function makeSeparator(parent)
	local sep = Instance.new("Frame")

	sep.Name = "Separator"
	sep.Size = UDim2.new(1, 0, 0, 1)
	sep.Position = UDim2.fromScale(0, 0)
	sep.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
	sep.BorderSizePixel = 0
	sep.ZIndex = 2
	sep.Parent = parent

	return sep
end

-- s = { strike, call = { contractSymbol, bid, ask, lastPrice, impliedVolatility, volume, openInterest } | nil, put = {...} | nil }
local function createStrikeRow(parent, index, s, spotPrice)
	local callITM = spotPrice > s.strike
	local putITM = spotPrice < s.strike
	local isATM = math.abs(s.strike - spotPrice) < 0.5

	local row = Instance.new("Frame")

	row.Name = "Strike_" .. index
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT_CHAIN)
	row.BackgroundColor3 = (callITM or putITM) and BG_ITM or BG_OTM
	row.BorderSizePixel = 0
	row.LayoutOrder = index
	row.Parent = parent

	makeSeparator(row)

	local callBid = s.call and s.call.bid
	local callAsk = s.call and s.call.ask
	local putBid = s.put and s.put.bid
	local putAsk = s.put and s.put.ask

	makeLabel(row, {
		name = "CallBidAsk",
		text = string.format("%.2f / %.2f", callBid or 0, callAsk or 0),
		sz = UDim2.new(0.38, -8, 1, 0),
		pos = UDim2.fromOffset(8, 0),
		color = callITM and TEXT_PRIMARY or TEXT_SECONDARY,
		align = Enum.TextXAlignment.Left,
	})

	makeLabel(row, {
		name = "StrikeLabel",
		text = string.format("%.2f", s.strike),
		sz = UDim2.new(0.24, 0, 1, 0),
		pos = UDim2.fromScale(0.38, 0),
		color = isATM and TEXT_PRIMARY or TEXT_SECONDARY,
		font = isATM and Enum.Font.SourceSansBold or Enum.Font.SourceSans,
		align = Enum.TextXAlignment.Center,
	})

	makeLabel(row, {
		name = "PutBidAsk",
		text = string.format("%.2f / %.2f", putBid or 0, putAsk or 0),
		sz = UDim2.new(0.38, -8, 1, 0),
		pos = UDim2.new(0.62, 0, 0, 0),
		color = putITM and TEXT_PRIMARY or TEXT_SECONDARY,
		align = Enum.TextXAlignment.Right,
	})

	return row
end

local function createPositionsHeader(parent)
	local existing = parent:FindFirstChild("PosHeader")

	if existing then
		existing:Destroy()
	end

	local header = Instance.new("Frame")

	header.Name = "PosHeader"
	header.Size = UDim2.new(1, 0, 0, ROW_HEIGHT_POS)
	header.BackgroundColor3 = Color3.fromRGB(25, 29, 40)
	header.BorderSizePixel = 0
	header.LayoutOrder = 0
	header.Parent = parent

	makeLabel(header, {
		name = "TradeHeader",
		text = "TRADE",
		sz = UDim2.new(0, TICKER_COL_WIDTH, 1, 0),
		pos = UDim2.fromOffset(8, 0),
		color = TEXT_SECONDARY,
		font = Enum.Font.SourceSansSemibold,
		size = 11,
		align = Enum.TextXAlignment.Left,
	})

	local xOffset = TICKER_COL_WIDTH + 8

	for _, col in ipairs(POSITION_COLUMNS) do
		makeLabel(header, {
			name = col.key .. "_hdr",
			text = string.upper(col.label),
			sz = UDim2.new(0, col.width, 1, 0),
			pos = UDim2.fromOffset(xOffset, 0),
			color = TEXT_SECONDARY,
			font = Enum.Font.SourceSansSemibold,
			size = 11,
			align = Enum.TextXAlignment.Right,
		})

		xOffset = xOffset + col.width
	end

	return header
end

-- pos = { ticker, quantity, mark, markChange, plDay, plOpen, netLiq, tradePrice, cost, delta, theta, plOpenPct }
local function createPositionRow(parent, index, pos)
	local row = Instance.new("Frame")

	row.Name = "Pos_" .. index
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT_POS)
	row.BackgroundColor3 = index % 2 == 0 and BG_ROW_EVEN or BG_ROW_ODD
	row.BorderSizePixel = 0
	row.LayoutOrder = index + 1
	row.Parent = parent

	makeLabel(row, {
		name = "TickerLabel",
		text = string.format("+%d %s", pos.quantity or 0, pos.ticker or ""),
		sz = UDim2.new(0, TICKER_COL_WIDTH, 1, 0),
		pos = UDim2.fromOffset(8, 0),
		color = GREEN,
		font = Enum.Font.SourceSansSemibold,
		align = Enum.TextXAlignment.Left,
	})

	local xOffset = TICKER_COL_WIDTH + 8

	for _, col in ipairs(POSITION_COLUMNS) do
		local v = pos[col.key]
		local isColored = col.format == "change" or col.format == "percent"

		makeLabel(row, {
			name = col.key,
			text = formatValue(v, col.format),
			sz = UDim2.new(0, col.width, 1, 0),
			pos = UDim2.fromOffset(xOffset, 0),
			color = isColored and getChangeColor(v) or TEXT_PRIMARY,
			align = Enum.TextXAlignment.Right,
		})

		xOffset = xOffset + col.width
	end

	return row
end

-- item = { headline, timestamp, source? }
local function createNewsItem(parent, index, item)
	local row = Instance.new("Frame")

	row.Name = "News_" .. index
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT_NEWS)
	row.BackgroundColor3 = BG_ROW_ODD
	row.BorderSizePixel = 0
	row.LayoutOrder = index
	row.Parent = parent

	makeSeparator(row)

	local headline = Instance.new("TextLabel")

	headline.Name = "Headline"
	headline.Text = item.headline or ""
	headline.Size = UDim2.new(1, -90, 1, -2)
	headline.Position = UDim2.fromOffset(8, 1)
	headline.BackgroundTransparency = 1
	headline.TextColor3 = TEXT_PRIMARY
	headline.Font = Enum.Font.SourceSans
	headline.TextSize = 13
	headline.TextXAlignment = Enum.TextXAlignment.Left
	headline.TextYAlignment = Enum.TextYAlignment.Center
	headline.TextWrapped = true
	headline.Parent = row

	makeLabel(row, {
		name = "Timestamp",
		text = item.timestamp or "",
		sz = UDim2.new(0, 78, 0, 16),
		pos = UDim2.new(1, -82, 0, 4),
		color = TEXT_SECONDARY,
		size = 11,
		align = Enum.TextXAlignment.Right,
	})

	if item.source then
		makeLabel(row, {
			name = "Source",
			text = item.source,
			sz = UDim2.new(0, 78, 0, 13),
			pos = UDim2.new(1, -82, 1, -16),
			color = TEXT_SECONDARY,
			size = 10,
			align = Enum.TextXAlignment.Right,
		})
	end

	row.MouseEnter:Connect(function()
		row.BackgroundColor3 = Color3.fromRGB(28, 36, 50)
	end)
	row.MouseLeave:Connect(function()
		row.BackgroundColor3 = BG_ROW_ODD
	end)

	return row
end

-- OptionChain
local function clearOptionChain()
	for _, child in pairs(ChainData:GetChildren()) do
		local isGeneratedRow = child:IsA("Frame") and string.match(child.Name, "^Strike_")

		if isGeneratedRow then
			child:Destroy()
		end
	end
end

-- Real shape, from GetOptionsDataEvent / the backend's /api/option-chain/:ticker:
-- {
--   available = true,
--   spotPrice = 150.25,
--   expiration = "2026-01-17",
--   expirationDates = { "2026-01-17", ... },
--   strikes = {
--     { strike = 145, call = { contractSymbol, bid, ask, lastPrice, impliedVolatility, volume, openInterest }, put = {...} },
--     ...
--   }
-- }
local function renderOptionChain(optionData)
	clearOptionChain()

	if not optionData or optionData.available == false or not optionData.strikes then
		return
	end

	local spotPrice = optionData.spotPrice or currentPrice

	for i, s in ipairs(optionData.strikes) do
		createStrikeRow(ChainData, i, s, spotPrice)
	end
end

-- Collapse / expand
local function setChainExpanded(expanded)
	chainExpanded = expanded
	print("ran")
	local targetSize = expanded and UDim2.new(1, 0, 0.45, 0) or UDim2.new(1, 0, 0, 30) -- collapsed to just the toggle bar

	TweenService:Create(OptionChain, TWEEN_MED, { Size = targetSize }):Play()
	ChainData.Visible = expanded
	ChainToggle.Text = expanded and "Option Chain ▼" or "Option Chain ▶"
end

-- Positions
local function clearPositions()
	for _, child in pairs(PositionsTable:GetChildren()) do
		if child:IsA("Frame") and string.match(child.Name, "^Pos_") then
			child:Destroy()
		end
	end
end

-- {
--   {
--     ticker = "COIN", quantity = 3,
--     mark = 166.30, markChange = -2.57,
--     plDay = -7.71,  plOpen = -112.28,
--     netLiq = 498.90, tradePrice = 203.73, cost = 611.18,
--     delta = 3.00,   theta = 0.00,  plOpenPct = -18.37
--   },
--   ...
-- }
local function renderPositions(positions)
	clearPositions()

	local emptyLabel = PositionsTable:FindFirstChild("EmptyLabel")

	if not positions or #positions == 0 then
		if emptyLabel then
			emptyLabel.Visible = true
		end

		return
	end

	if emptyLabel then
		emptyLabel.Visible = false
	end

	createPositionsHeader(PositionsTable)

	for i, pos in ipairs(positions) do
		createPositionRow(PositionsTable, i, pos)
	end
end

-- Fetches the player's holdings in the current ticker and re-renders the
-- Positions table (Trade screen shows one active symbol at a time).
local function refreshPositions()
	if currentTicker == "" then
		return
	end

	local positions = GetPositionsEvent:InvokeServer(currentTicker)

	if positions then
		renderPositions(positions)
	end
end

-- NewsFeed
local function clearNewsFeed()
	for _, child in pairs(NewsFeed:GetChildren()) do
		if child:IsA("Frame") and string.match(child.Name, "^News_") then
			child:Destroy()
		end
	end
end

-- { { headline = "COIN surges on ETF news", timestamp = "2h ago", source = "Reuters" }, ... }
local function renderNewsFeed(newsItems)
	clearNewsFeed()

	if not newsItems or #newsItems == 0 then
		return
	end

	for i, item in ipairs(newsItems) do
		createNewsItem(NewsFeed, i, item)
	end
end

-- Mini Chart
local MINI_CHART_GRADIENT_START = Color3.fromRGB(224, 170, 255) -- pale violet (older)
local MINI_CHART_GRADIENT_END = Color3.fromRGB(124, 58, 237) -- vivid purple (most recent)

local function lerpColor(fromColor, toColor, t)
	return Color3.new(
		fromColor.R + (toColor.R - fromColor.R) * t,
		fromColor.G + (toColor.G - fromColor.G) * t,
		fromColor.B + (toColor.B - fromColor.B) * t
	)
end

-- Draws the line as rotated 2px-thick segments between consecutive points
-- (Roblox has no native polyline) so it reads as one continuous line rather
-- than a series of disconnected height jumps, with a purple gradient running
-- along it from oldest (pale) to most recent (vivid).
local function renderMiniChart(chartData)
	MiniChart:ClearAllChildren()

	if not chartData or #chartData < 2 then
		return
	end

	local high = -math.huge
	local low = math.huge

	for _, c in ipairs(chartData) do
		if c.Close > high then
			high = c.Close
		end

		if c.Close < low then
			low = c.Close
		end
	end

	local range = high - low

	if range == 0 then
		range = 1
	end

	local count = #chartData
	local absoluteSize = MiniChart.AbsoluteSize
	local width = math.max(absoluteSize.X, 1)
	local height = math.max(absoluteSize.Y, 1)

	for i = 1, count - 1 do
		local x1 = (i - 1) / (count - 1)
		local x2 = i / (count - 1)
		local y1 = 1 - (chartData[i].Close - low) / range
		local y2 = 1 - (chartData[i + 1].Close - low) / range

		local dx = (x2 - x1) * width
		local dy = (y2 - y1) * height
		local length = math.sqrt(dx * dx + dy * dy)
		local angle = math.deg(math.atan2(dy, dx))

		local seg = Instance.new("Frame")

		seg.Name = "Seg_" .. i
		seg.BackgroundColor3 = Color3.new(1, 1, 1)
		seg.BorderSizePixel = 0
		seg.ZIndex = 2
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		seg.Size = UDim2.new(0, length, 0, 2)
		seg.Rotation = angle
		seg.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
		seg.Parent = MiniChart

		local gradient = Instance.new("UIGradient")

		gradient.Color = ColorSequence.new(
			lerpColor(MINI_CHART_GRADIENT_START, MINI_CHART_GRADIENT_END, x1),
			lerpColor(MINI_CHART_GRADIENT_START, MINI_CHART_GRADIENT_END, x2)
		)
		gradient.Parent = seg
	end
end

-- Loading
local function setLoadingState(isLoading)
	if isLoading then
		TickerLabel.Text = "Loading..."
		CompanyLabel.Text = ""
		BuyButton.Text = "Buy"
		SellButton.Text = "Sell"
	end

	BuyButton.Active = not isLoading
	SellButton.Active = not isLoading
	TickerInput.TextEditable = not isLoading
end

local function showError(message)
	TickerLabel.Text = "Error"
	CompanyLabel.Text = message or "Ticker not found"
end

-- Main Load
local function loadTicker(rawTicker)
	local ticker = string.upper((string.gsub(rawTicker, "%s+", "")))

	if ticker == "" then
		return
	end

	if ticker == currentTicker and not isFetchingData then
		return
	end

	if isFetchingData then
		return
	end

	isFetchingData = true
	currentTicker = ticker
	currentAnalystData = nil
	currentFundamentalsData = nil
	currentOptionStatsData = nil

	renderFieldGrid(ContentAnalystReports, ANALYST_FIELDS, nil, "AR_")
	renderFieldGrid(ContentFundamentals, FUNDAMENTALS_FIELDS, nil, "FN_")
	clearOptionStats()

	setLoadingState(true)
	clearOptionChain()
	clearPositions()
	clearNewsFeed()

	-- Core
	local marketData = GetMarketDataEvent:InvokeServer(ticker)

	if not marketData then
		showError("Ticker not found")
		TickerInput.Text = currentTicker ~= ticker and currentTicker or "..."
		isFetchingData = false

		return
	end

	if not marketData.ticker and not marketData.price then
		warn(
			string.format(
				"[TradeController] GetMarketDataEvent returned an unexpected shape for %s - check server-side field names.",
				ticker
			)
		)
	end

	currentQuoteData = marketData
	currentPrice = marketData.price or 0
	currentPrevClose = marketData.prevClose or currentPrice

	TickerInput.Text = ticker
	updateHeader(marketData)
	renderQuoteDetails(marketData)
	switchTab("QuoteDetails")

	-- MiniChart
	local miniData = RequestChartEvent:InvokeServer(ticker, "5M")
	if miniData then
		renderMiniChart(miniData)
	end

	-- ── Options data ──────────────────────────────────────────────────────────
	local optionData = GetOptionsDataEvent:InvokeServer(ticker)

	if optionData then
		currentOptionData = optionData
		renderOptionChain(optionData)
	end

	-- ── Player positions ──────────────────────────────────────────────────────
	refreshPositions()

	-- ── News feed ──────────────────────────────────────────────────────────────
	-- Uncomment when GetNewsFeedEvent is live on the server.
	-- local news = GetNewsFeedEvent:InvokeServer(ticker)
	-- if news then
	--     renderNewsFeed(news)
	-- end

	isFetchingData = false
end

-- Polling
task.spawn(function()
	while true do
		task.wait(5)

		if currentTicker ~= "" and not isFetchingData then
			local liveData = RequestChartEvent:InvokeServer(currentTicker, "H", "live")

			if liveData and #liveData > 0 then
				local latest = liveData[#liveData]

				currentPrice = latest.Close or currentPrice
				updateHeader(currentQuoteData, currentPrice)

				-- Keep the live price field in Quote Details in sync.
				-- "price" key is not in QUOTE_FIELDS (it's in the header),
				-- but if you add a "Last" field you could call:
				-- updateQuoteField("price", currentPrice, "price")
			end
		end
	end
end)

-- Buy/Sell
local function isMarketOpen()
	return MarketHoursModule.getMarketStatus(os.time())
end

local function placeOrder(action)
	if currentTicker == "" or isFetchingData then
		return
	end

	if not isMarketOpen() then
		print("[TradeController] Market is closed — cannot place order.") -- Add Toast

		return
	end

	local result = PlayerOrderEvent:InvokeServer(action, currentTicker, orderQuantity)

	if not result or not result.success then
		print(string.format("[TradeController] %s failed: %s", action, (result and result.message) or "Unknown error"))

		return
	end

	print("[TradeController] " .. result.message)

	refreshPositions()
end

BuyButton.MouseButton1Click:Connect(function()
	placeOrder("Buy")
end)

SellButton.MouseButton1Click:Connect(function()
	placeOrder("Sell")
end)

attachHover(BuyButton, Color3.fromRGB(38, 166, 154), Color3.fromRGB(25, 140, 128))
attachHover(SellButton, Color3.fromRGB(200, 50, 50), Color3.fromRGB(170, 35, 35))

-- Ticker Input
TickerInput.FocusLost:Connect(function(enterPressed)
	if not enterPressed then
		return
	end

	local raw = string.upper((string.gsub(TickerInput.Text, "%s+", "")))

	if raw == "" then
		TickerInput.Text = currentTicker ~= "" and currentTicker or "..."

		return
	end

	loadTicker(raw)
end)

-- Option Chain Toggle
ChainToggle.MouseButton1Click:Connect(function()
	setChainExpanded(not chainExpanded)
end)

-- Tab Button
for tabName, button in pairs(TabButtons) do
	button.MouseButton1Click:Connect(function()
		switchTab(tabName)
	end)
end

-- Player Attribute Watchers
local function onBalanceChanged()
	if currentTicker == "" then
		return
	end

	refreshPositions()
end

Player:GetAttributeChangedSignal("Balance"):Connect(onBalanceChanged)
Player:GetAttributeChangedSignal("NetWorth"):Connect(onBalanceChanged)

switchTab("QuoteDetails")

setChainExpanded(false)
TableHeader.Visible = false

print("[DEBUG] Script fully intitalized")

-- Preloading Ticker:
-- loadTicker("AAPL")
