-- TradeController.client.luau
--
-- Handles Trade Screen. The ticker row picks the market first
-- (MarketPickerModule): real-world tickers are typed, Roblox games are
-- searched by name; a game also gets a banner under the header
-- (GameBannerModule).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local Instruments = require(ReplicatedStorage.Config.Instruments)
local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)
local OrderTicketModule = require(ReplicatedStorage.Modules.Trade.OrderTicketModule)
local ThesisPanelModule = require(ReplicatedStorage.Modules.Trade.ThesisPanelModule)
local MarketPickerModule = require(ReplicatedStorage.Modules.Trade.MarketPickerModule)
local GameBannerModule = require(ReplicatedStorage.Modules.Trade.GameBannerModule)
local StarterPicksModule = require(ReplicatedStorage.Modules.Trade.StarterPicksModule)
local UIKit = require(ReplicatedStorage.UI.UIKit)

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
local PlayerOptionOrderEvent = EventsFolder:WaitForChild("PlayerOptionOrderEvent")
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
local PriceLabel = HeaderRow:WaitForChild("PriceLabel")
local ChangeLabel = HeaderRow:WaitForChild("ChangeLabel")
local BidSizeLabel = HeaderRow:WaitForChild("BidSizeLabel")
local AskSizeLabel = HeaderRow:WaitForChild("AskSizeLabel")
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

-- Theme Colors (names kept from the pre-theme constants so call sites stay put)
local GREEN = Theme.Colors.Up
local RED = Theme.Colors.Down
local GRAY = Theme.Colors.TextMuted

local TEXT_PRIMARY = Theme.Colors.Text
local TEXT_SECONDARY = Theme.Colors.TextMuted
local BG_ROW_EVEN = Theme.Colors.Panel
local BG_ROW_ODD = Theme.Colors.Background
local BG_ITM = Theme.Colors.AccentTint -- In-The-Money
local BG_OTM = Theme.Colors.Background -- Out-The-Money

local COLOR_TAB_ACTIVE = Theme.Colors.Accent
local COLOR_TAB_INACTIVE = Theme.Colors.TextMuted

local TWEEN_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MED = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Layout. The screen scrolls as one column of sections with even gaps, each
-- sized to what it holds (the Studio canvas was three screens tall, and the
-- sections fixed heights that clipped or left gaps).
local SCREEN_PADDING = 12
local SECTION_GAP = 10
local SECTION_PADDING = 12
local SECTION_TITLE_HEIGHT = 22
local INPUT_ROW_HEIGHT = 32
local HEADER_HEIGHT = 72
local HEADER_GAP = 20
local ACTION_BUTTON_WIDTH = 104
local ACTION_BUTTON_HEIGHT = 34
local ACTION_BUTTON_GAP = 8
local PRICE_BLOCK_WIDTH = 170
local SIZE_BLOCK_WIDTH = 110
local PRICE_CHART_HEIGHT = 240
local TAB_HEADER_HEIGHT = 30
local OPTION_CHAIN_HEIGHT = 300
local NEWS_MAX_HEIGHT = 300 -- about five headlines; more scroll inside

-- Top to bottom: what it is (or, before anything's loaded, what to pick),
-- how it's moving, trade it, what you hold, the research, then the community
local SECTION_ORDER = {
	InputRow = 1,
	HeaderRow = 2,
	StarterPicks = 3,
	GameBanner = 4,
	PriceChart = 5,
	OrderTicket = 6,
	PositionsTable = 7,
	QuoteDetails = 8,
	OptionChain = 9,
	NewsFeed = 10,
	Theses = 11,
}

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

-- A Roblox-market experience's Quote Details: every label says where its
-- number comes from, since the GDD (§6) asks that observed stats, estimates
-- and the simulated price never be confused
local ROBLOX_FIELDS = {
	{ label = "Players now · observed", key = "playing", format = "count" },
	{ label = "7-day avg players · estimated", key = "averagePlaying", format = "count" },
	{ label = "Players vs usual · estimated", key = "vsUsual", format = "auto" },
	{ label = "Visits · observed", key = "visits", format = "count" },
	{ label = "Favorites · observed", key = "favorites", format = "count" },
	{ label = "Like ratio · observed", key = "likeRatio", format = "percent" },
	{ label = "Updated · observed", key = "updated", format = "date" },
	{ label = "Created · observed", key = "created", format = "date" },
	{ label = "Genre · observed", key = "genre", format = "auto" },
	{ label = "Creator · observed", key = "creator", format = "auto" },
	{ label = "Target price · simulated", key = "target", format = "price" },
	{ label = "Listed since", key = "listedAt", format = "date" },
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
local currentQuoteData = nil
local currentOptionData = nil
local currentAnalystData = nil
local currentFundamentalsData = nil
local currentOptionStatsData = nil
local isFetchingData = false
local activeTabName = ""
local chainExpanded = true
local orderQuantity = 1
local currentPositionQuantity = 0 -- shares held of currentTicker, for the order ticket's sell presets
local orderTicket = nil -- created once the functions it calls exist
local thesisPanel = nil -- created with the order ticket
local marketPicker = nil -- likewise
local gameBanner = nil
local starterPicks = nil

local selectedContract = nil

-- Script-generated indicator shown in the (mostly empty) space next to the
-- ticker input while an option contract is selected for trading instead of
-- shares. Clicking it clears the selection and returns to share-trading
-- mode. Created once here rather than per-row, since only one contract can
-- be selected at a time.
local ContractIndicator = Instance.new("TextButton")

ContractIndicator.Name = "ContractIndicator"
-- Right of the market picker's dropdown and search box
ContractIndicator.Size = UDim2.new(1, -(MarketPickerModule.ROW_WIDTH + 16), 1, 0)
ContractIndicator.Position = UDim2.fromOffset(MarketPickerModule.ROW_WIDTH + 16, 0)
ContractIndicator.BackgroundTransparency = 1
ContractIndicator.Text = ""
ContractIndicator.TextColor3 = TEXT_PRIMARY
ContractIndicator.FontFace = Theme.Fonts.UISemibold
ContractIndicator.TextSize = Theme.TextSize.Body
ContractIndicator.TextXAlignment = Enum.TextXAlignment.Left
ContractIndicator.Visible = false
ContractIndicator.Parent = InputRow

local function updateContractIndicator()
	if not selectedContract then
		ContractIndicator.Visible = false

		return
	end

	local expLabel = string.match(tostring(selectedContract.expiration), "^%d%d%d%d%-%d%d%-%d%d")
		or tostring(selectedContract.expiration)
	local typeLabel = selectedContract.type == "C" and "Call" or "Put"

	ContractIndicator.Text = string.format(
		"Now trading: %s $%.2f %s exp %s — Back to Shares",
		selectedContract.ticker,
		selectedContract.strike,
		typeLabel,
		expLabel
	)
	ContractIndicator.Visible = true
end

local function clearContractSelection()
	selectedContract = nil
	updateContractIndicator()
end

-- contractType: "C" | "P". strikeEntry: a single entry from optionData.strikes
-- (the `s` passed into createStrikeRow), so it carries both call and put.
local function selectContract(contractType, strikeEntry, strike)
	local contract = contractType == "C" and strikeEntry.call or strikeEntry.put

	if not contract or not contract.contractSymbol then
		return
	end

	selectedContract = {
		contractSymbol = contract.contractSymbol,
		ticker = currentTicker,
		expiration = currentOptionData and currentOptionData.expiration,
		strike = strike,
		type = contractType,
	}

	updateContractIndicator()
end

ContractIndicator.MouseButton1Click:Connect(clearContractSelection)

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

local function addPadding(parent, vertical, horizontal)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, vertical)
	padding.PaddingBottom = UDim.new(0, vertical)
	padding.PaddingLeft = UDim.new(0, horizontal or vertical)
	padding.PaddingRight = UDim.new(0, horizontal or vertical)
	padding.Parent = parent

	return padding
end

-- A section's title, in the Community section's style
local function makeSectionTitle(name, parent, text)
	local title = UIKit.makeLabel(name, parent, Theme.Fonts.UIBold, Theme.TextSize.Title, Theme.Colors.Text)
	title.Size = UDim2.new(1, 0, 0, SECTION_TITLE_HEIGHT)
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.Text = text

	return title
end

-- The header, laid out here: ticker and company on the left; the price,
-- then Sell and Buy on the right, with the bid and ask sizes before the
-- price when the quote has them. On a narrow screen (a phone) the buttons
-- drop to a row of their own under the rest. The Studio layout overlapped,
-- and its sizes read "XXX" for quotes without them (chart-only quotes never
-- have them).
local HEADER_COMPACT_HEIGHT = HEADER_HEIGHT + ACTION_BUTTON_GAP + ACTION_BUTTON_HEIGHT
local HEADER_SIDE_PADDING = 16
local HEADER_MIN_TICKER_WIDTH = 140 -- narrower than this and the header stacks
local HEADER_PRICE_RIGHT = ACTION_BUTTON_WIDTH * 2 + ACTION_BUTTON_GAP + HEADER_GAP
local HEADER_SIZES_RIGHT = HEADER_PRICE_RIGHT + PRICE_BLOCK_WIDTH + HEADER_GAP

local headerHasSizes = false

-- `hasSizes` is whether the quote has bid and ask sizes; nil keeps the last answer
local function layoutHeader(hasSizes)
	if hasSizes ~= nil then
		headerHasSizes = hasSizes
	end

	local innerWidth = HeaderRow.AbsoluteSize.X - HEADER_SIDE_PADDING * 2
	local priceEdge = HEADER_PRICE_RIGHT + PRICE_BLOCK_WIDTH + HEADER_GAP
	local isCompact = innerWidth - priceEdge < HEADER_MIN_TICKER_WIDTH
	local showSizes = headerHasSizes and not isCompact
	local leftWidth = if isCompact
		then PRICE_BLOCK_WIDTH + HEADER_GAP
		elseif showSizes then HEADER_SIZES_RIGHT + SIZE_BLOCK_WIDTH + HEADER_GAP
		else priceEdge

	HeaderRow.Size = UDim2.new(1, 0, 0, isCompact and HEADER_COMPACT_HEIGHT or HEADER_HEIGHT)
	TickerLabel.Size = UDim2.new(1, -leftWidth, 0, 30)
	CompanyLabel.Size = UDim2.new(1, -leftWidth, 0, 16)
	BidSizeLabel.Visible = showSizes
	AskSizeLabel.Visible = showSizes

	if isCompact then
		-- Price at the top right, Sell and Buy splitting the row below
		local buttonSize = UDim2.new(0.5, -ACTION_BUTTON_GAP / 2, 0, ACTION_BUTTON_HEIGHT)

		PriceLabel.Position = UDim2.new(1, 0, 0, 15)
		ChangeLabel.Position = UDim2.new(1, 0, 0, 38)
		SellButton.Position = UDim2.new(0.5, -ACTION_BUTTON_GAP / 2, 1, -ACTION_BUTTON_HEIGHT / 2)
		SellButton.Size = buttonSize
		BuyButton.Position = UDim2.new(1, 0, 1, -ACTION_BUTTON_HEIGHT / 2)
		BuyButton.Size = buttonSize
	else
		local buttonSize = UDim2.fromOffset(ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT)

		PriceLabel.Position = UDim2.new(1, -HEADER_PRICE_RIGHT, 0.5, -8)
		ChangeLabel.Position = UDim2.new(1, -HEADER_PRICE_RIGHT, 0.5, 14)
		SellButton.Position = UDim2.new(1, -(ACTION_BUTTON_WIDTH + ACTION_BUTTON_GAP), 0.5, 0)
		SellButton.Size = buttonSize
		BuyButton.Position = UDim2.fromScale(1, 0.5)
		BuyButton.Size = buttonSize
	end
end

addPadding(HeaderRow, SECTION_PADDING, HEADER_SIDE_PADDING)

TickerLabel.Position = UDim2.fromOffset(0, 0)
TickerLabel.TextTruncate = Enum.TextTruncate.AtEnd
CompanyLabel.Position = UDim2.fromOffset(0, 31)
CompanyLabel.TextTruncate = Enum.TextTruncate.AtEnd
PriceLabel.Size = UDim2.fromOffset(PRICE_BLOCK_WIDTH, 28)
ChangeLabel.Size = UDim2.fromOffset(PRICE_BLOCK_WIDTH, 16)
BidSizeLabel.Position = UDim2.new(1, -HEADER_SIZES_RIGHT, 0.5, -9)
BidSizeLabel.Size = UDim2.fromOffset(SIZE_BLOCK_WIDTH, 16)
AskSizeLabel.Position = UDim2.new(1, -HEADER_SIZES_RIGHT, 0.5, 9)
AskSizeLabel.Size = UDim2.fromOffset(SIZE_BLOCK_WIDTH, 16)

-- Nothing loaded yet: no Studio placeholders ("XXXX", "Label"). The ticker
-- stays empty: TutorialController counts any text there as a lookup.
TickerLabel.Text = ""
CompanyLabel.Text = "Pick a stock, crypto or Roblox game above"
PriceLabel.Text = ""
ChangeLabel.Text = ""
layoutHeader(false)

HeaderRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	layoutHeader(nil)
end)

-- Header
local function updateHeader(data, livePrice)
	local price = livePrice or (data and data.price) or 0
	local prevClose = (data and data.prevClose) or price
	local change = price - prevClose
	local changePct = prevClose ~= 0 and ((change / prevClose) * 100) or 0
	local color = change >= 0 and GREEN or RED

	TickerLabel.Text = (data and data.ticker) or currentTicker or "—"
	CompanyLabel.Text = (data and data.companyName) or "—"

	-- A Roblox-market price is the game's simulation, and says so beside it
	if data and data.assetClass == "roblox" then
		if data.delisted then
			CompanyLabel.Text ..= " · Delisted"
		elseif data.opensAt then
			CompanyLabel.Text ..= " · Opens in " .. MarketHoursModule.formatCountdown(data.opensAt - os.time())
		else
			CompanyLabel.Text ..= " · Simulated price"
		end
	end

	PriceLabel.Text = string.format("%.2f", price)
	PriceLabel.TextColor3 = color
	ChangeLabel.Text = string.format("%s%.2f (%.2f%%)", change >= 0 and "+" or "", change, changePct)
	ChangeLabel.TextColor3 = color

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

	local hasSizes = bidSize ~= nil and askSize ~= nil

	if hasSizes then
		BidSizeLabel.Text = "Bid size " .. NumberModule.formatShares(bidSize)
		AskSizeLabel.Text = "Ask size " .. NumberModule.formatShares(askSize)
	end

	layoutHeader(hasSizes)
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

-- The research tabs grow to the open tab's rows; at the Studio's fixed
-- 120 px the fourth row of Quote Details and Fundamentals was cut off
local RESEARCH_CONTENT_PADDING = 8
local UNAVAILABLE_ROW_HEIGHT = 22

local function fitQuoteDetails()
	local content = TabContents[activeTabName]

	if not content then
		return
	end

	-- A tab showing its "unavailable" message has its grid detached
	local layout = content:FindFirstChildWhichIsA("UIGridStyleLayout")
	local height = layout and layout.AbsoluteContentSize.Y or UNAVAILABLE_ROW_HEIGHT

	QuoteDetails.Size = UDim2.new(1, 0, 0, TAB_HEADER_HEIGHT + height + RESEARCH_CONTENT_PADDING * 2)
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
		lbl.Size = UDim2.fromScale(0.55, 1)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = TEXT_SECONDARY
		lbl.FontFace = Theme.Fonts.UI
		lbl.TextSize = Theme.TextSize.Body
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = row

		local val = Instance.new("TextLabel")

		val.Name = "Value"
		val.Text = formatValue(data[field.key], field.format)
		val.Size = UDim2.fromScale(0.45, 1)
		val.Position = UDim2.fromScale(0.55, 0)
		val.BackgroundTransparency = 1
		val.TextColor3 = TEXT_PRIMARY
		val.FontFace = Theme.Fonts.Mono
		val.TextSize = Theme.TextSize.Body
		val.TextXAlignment = Enum.TextXAlignment.Right
		val.Parent = row
	end

	fitQuoteDetails()
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
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = TEXT_SECONDARY
	lbl.FontFace = Theme.Fonts.UI
	lbl.TextSize = Theme.TextSize.Body
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.Parent = row

	fitQuoteDetails()
end

-- Builds a single TextLabel from a props table. Moved up here (ahead of its
-- original spot near the Option Chain row-builders) so the two-column Option
-- Stats renderer below - and switchTab's lazy-fetch wiring further down - can
-- call it; Luau locals aren't visible above their declaration.
local function makeLabel(parent, props)
	local lbl = Instance.new("TextLabel")

	lbl.Name = props.name or "Label"
	lbl.Text = props.text or ""
	lbl.Size = props.sz or UDim2.fromScale(1, 1)
	lbl.Position = props.pos or UDim2.fromOffset(0, 0)
	lbl.BackgroundTransparency = 1
	lbl.FontFace = props.font or Theme.Fonts.UI
	lbl.TextSize = props.size or Theme.TextSize.Body
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
		renderUnavailable(ContentAnalystReports, "AR_", data.message or "Not available for this asset")
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
		renderUnavailable(ContentFundamentals, "FN_", data.message or "Not available for this asset")
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
		renderUnavailable(ContentOptionStats, "OS_", data.message or "Not available for this asset")
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
		text = string.format(
			"Nearest Expiry: %s   ·   Strike: %.2f",
			formatValue(data.expiration, "date"),
			data.strike or 0
		),
		sz = UDim2.fromScale(1, 1),
		color = TEXT_SECONDARY,
		font = Theme.Fonts.UISemibold,
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
		sz = UDim2.fromScale(0.35, 1),
		pos = UDim2.fromScale(0.4, 0),
		color = TEXT_SECONDARY,
		font = Theme.Fonts.UISemibold,
		align = Enum.TextXAlignment.Center,
	})

	makeLabel(columnsRow, {
		name = "PutHeader",
		text = "PUT",
		sz = UDim2.fromScale(0.35, 1),
		pos = UDim2.fromScale(0.75, 0),
		color = TEXT_SECONDARY,
		font = Theme.Fonts.UISemibold,
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
			sz = UDim2.fromScale(0.4, 1),
			color = TEXT_SECONDARY,
			align = Enum.TextXAlignment.Left,
		})

		makeLabel(row, {
			name = "CallValue",
			text = formatValue(data.call and data.call[field.key], field.format),
			sz = UDim2.fromScale(0.3, 1),
			pos = UDim2.fromScale(0.4, 0),
			color = TEXT_PRIMARY,
			font = Theme.Fonts.Mono,
			align = Enum.TextXAlignment.Center,
		})

		makeLabel(row, {
			name = "PutValue",
			text = formatValue(data.put and data.put[field.key], field.format),
			sz = UDim2.fromScale(0.3, 1),
			pos = UDim2.fromScale(0.75, 0),
			color = TEXT_PRIMARY,
			font = Theme.Fonts.Mono,
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

-- Roblox sends times as unix seconds; the grid shows the day
local function toDay(seconds)
	return seconds and os.date("!%Y-%m-%d", seconds)
end

local function renderQuoteDetails(data)
	if data and data.assetClass == "roblox" then
		local observed = data.observed or {}
		local votes = (observed.upVotes or 0) + (observed.downVotes or 0)

		renderFieldGrid(ContentQuoteDetails, ROBLOX_FIELDS, {
			playing = observed.playing,
			averagePlaying = data.averagePlaying,
			-- Against the same hour a week before; what moves the price fastest
			vsUsual = data.vsUsual and string.format("%+.0f%%", data.vsUsual * 100),
			visits = observed.visits,
			favorites = observed.favorites,
			likeRatio = votes > 0 and observed.upVotes / votes * 100 or nil,
			updated = toDay(observed.updated),
			created = toDay(observed.created),
			genre = observed.genre,
			creator = observed.creator,
			target = data.target,
			listedAt = toDay(data.listedAt),
		}, "QF_")

		return
	end

	renderFieldGrid(ContentQuoteDetails, QUOTE_FIELDS, data, "QF_")
end

-- Refresh Quotes: kept for a live "Last" field (see the chart refresh below)
-- selene: allow(unused_variable)
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

	fitQuoteDetails()
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
	sep.BackgroundColor3 = Theme.Colors.Border
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
		font = Theme.Fonts.Mono,
		align = Enum.TextXAlignment.Left,
	})

	makeLabel(row, {
		name = "StrikeLabel",
		text = string.format("%.2f", s.strike),
		sz = UDim2.fromScale(0.24, 1),
		pos = UDim2.fromScale(0.38, 0),
		color = isATM and TEXT_PRIMARY or TEXT_SECONDARY,
		font = isATM and Theme.Fonts.MonoBold or Theme.Fonts.Mono,
		align = Enum.TextXAlignment.Center,
	})

	makeLabel(row, {
		name = "PutBidAsk",
		text = string.format("%.2f / %.2f", putBid or 0, putAsk or 0),
		sz = UDim2.new(0.38, -8, 1, 0),
		pos = UDim2.fromScale(0.62, 0),
		color = putITM and TEXT_PRIMARY or TEXT_SECONDARY,
		font = Theme.Fonts.Mono,
		align = Enum.TextXAlignment.Right,
	})

	if s.call and s.call.contractSymbol then
		local callHit = Instance.new("TextButton")

		callHit.Name = "CallHitArea"
		callHit.Size = UDim2.new(0.38, -8, 1, 0)
		callHit.Position = UDim2.fromOffset(8, 0)
		callHit.BackgroundTransparency = 1
		callHit.Text = ""
		callHit.ZIndex = 2
		callHit.Parent = row

		callHit.MouseButton1Click:Connect(function()
			selectContract("C", s, s.strike)
		end)
	end

	if s.put and s.put.contractSymbol then
		local putHit = Instance.new("TextButton")

		putHit.Name = "PutHitArea"
		putHit.Size = UDim2.new(0.38, -8, 1, 0)
		putHit.Position = UDim2.fromScale(0.62, 0)
		putHit.BackgroundTransparency = 1
		putHit.Text = ""
		putHit.ZIndex = 2
		putHit.Parent = row

		putHit.MouseButton1Click:Connect(function()
			selectContract("P", s, s.strike)
		end)
	end

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
	header.BackgroundColor3 = Theme.Colors.Raised
	header.BorderSizePixel = 0
	header.LayoutOrder = 0
	header.Parent = parent

	makeLabel(header, {
		name = "TradeHeader",
		text = "TRADE",
		sz = UDim2.new(0, TICKER_COL_WIDTH, 1, 0),
		pos = UDim2.fromOffset(8, 0),
		color = TEXT_SECONDARY,
		font = Theme.Fonts.UISemibold,
		size = Theme.TextSize.Caption,
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
			font = Theme.Fonts.UISemibold,
			size = Theme.TextSize.Caption,
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
		font = Theme.Fonts.UISemibold,
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
			font = Theme.Fonts.Mono,
			align = Enum.TextXAlignment.Right,
		})

		xOffset = xOffset + col.width
	end

	return row
end

-- item = { headline, timestamp, source? }
-- "just now", "12m ago", "3h ago", "2d ago"
local function formatNewsAge(seconds)
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m ago"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. "h ago"
	end

	return math.floor(seconds / 86400) .. "d ago"
end

-- item = { title, publisher, publishedAt } from GetNewsFeedEvent (headlines
-- arrive already through Roblox's text filter)
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
	headline.Text = item.title or ""
	headline.Size = UDim2.new(1, -90, 1, -2)
	headline.Position = UDim2.fromOffset(8, 1)
	headline.BackgroundTransparency = 1
	headline.TextColor3 = TEXT_PRIMARY
	headline.FontFace = Theme.Fonts.UI
	headline.TextSize = Theme.TextSize.Body
	headline.TextTruncate = Enum.TextTruncate.AtEnd -- long headlines end in "…" instead of clipping mid-line
	headline.TextXAlignment = Enum.TextXAlignment.Left
	headline.TextYAlignment = Enum.TextYAlignment.Center
	headline.TextWrapped = true
	headline.Parent = row

	makeLabel(row, {
		name = "Timestamp",
		text = item.publishedAt and formatNewsAge(os.time() - item.publishedAt) or "",
		sz = UDim2.fromOffset(78, 16),
		pos = UDim2.new(1, -82, 0, 4),
		color = TEXT_SECONDARY,
		size = Theme.TextSize.Caption,
		align = Enum.TextXAlignment.Right,
	})

	if item.publisher then
		makeLabel(row, {
			name = "Source",
			text = item.publisher,
			sz = UDim2.fromOffset(78, 13),
			pos = UDim2.new(1, -82, 1, -16),
			color = TEXT_SECONDARY,
			size = Theme.TextSize.Caption,
			align = Enum.TextXAlignment.Right,
		})
	end

	row.MouseEnter:Connect(function()
		row.BackgroundColor3 = Theme.Colors.Raised
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

	-- Below the unlock level the server sends the unlock message instead of
	-- a chain, and for an asset with no options (a Roblox experience) why not;
	-- a Strike_ frame so clearOptionChain removes it like a row
	local isLocked = optionData ~= nil
		and (optionData.locked == true or (optionData.available == false and optionData.message ~= nil))

	ColumnHeaders.Visible = not isLocked
	if isLocked then
		local row = Instance.new("Frame")

		row.Name = "Strike_Locked"
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT_CHAIN)
		row.BackgroundTransparency = 1
		row.Parent = ChainData

		makeLabel(row, {
			name = "Message",
			text = optionData.message,
			color = TEXT_SECONDARY,
			align = Enum.TextXAlignment.Center,
		})

		return
	end

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

	-- Collapsed to just the toggle bar. In pixels: a scale here would be of
	-- the screen's canvas, which grows with its content.
	local targetSize = UDim2.new(1, 0, 0, expanded and OPTION_CHAIN_HEIGHT or ChainToggle.Size.Y.Offset)

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
		local header = PositionsTable:FindFirstChild("PosHeader")

		if header then
			header:Destroy()
		end

		if emptyLabel then
			emptyLabel.Text = string.format("You don't own any %s yet. Buy with a preset above.", currentTicker)
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
		currentPositionQuantity = positions[1] and positions[1].quantity or 0
		renderPositions(positions)

		if orderTicket then
			orderTicket:update()
		end
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

	local emptyLabel = NewsFeed:FindFirstChild("EmptyLabel")
	local isEmpty = not newsItems or #newsItems == 0

	if emptyLabel then
		emptyLabel.Text = newsItems and "No recent headlines." or "Headlines unavailable right now."
		emptyLabel.Visible = isEmpty
	end

	if isEmpty then
		return
	end

	for i, item in ipairs(newsItems) do
		createNewsItem(NewsFeed, i, item)
	end
end

-- Mini Chart
local MINI_CHART_GRADIENT_START = Theme.Colors.AccentSoft -- pale violet (older)
local MINI_CHART_GRADIENT_END = Theme.Colors.Accent -- the UI accent (most recent)
local MINI_CHART_PIXELS_PER_POINT = 3

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
local lastMiniChartData = nil -- redrawn on resize: segment lengths are in pixels
local PriceChartCaption = nil -- built with the section, further down

local function renderMiniChart(chartData)
	MiniChart:ClearAllChildren()
	lastMiniChartData = chartData

	if not chartData or #chartData < 2 then
		PriceChartCaption.Text = chartData and "Not enough recent prices to chart" or "Chart unavailable"

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

	-- "5-min · Oct 21 – Oct 26 · H 191.20 · L 186.05"
	local firstDay = os.date("%b %d", chartData[1].Timestamp)
	local lastDay = os.date("%b %d", chartData[#chartData].Timestamp)

	PriceChartCaption.Text = string.format(
		"5-min · %s · H %.2f · L %.2f",
		firstDay == lastDay and firstDay or (firstDay .. " – " .. lastDay),
		high,
		low
	)

	local absoluteSize = MiniChart.AbsoluteSize
	local width = math.max(absoluteSize.X, 1)
	local height = math.max(absoluteSize.Y, 1)

	-- A week of 5-minute candles is ~1,000 points: more segments than the
	-- width can show, each a Frame, redrawn on every resize. Every few
	-- pixels' worth is enough; the latest point always stays.
	local step = math.max(1, math.ceil(#chartData / (width / MINI_CHART_PIXELS_PER_POINT)))

	if step > 1 then
		local sampled = {}

		for index = 1, #chartData, step do
			table.insert(sampled, chartData[index])
		end

		if sampled[#sampled] ~= chartData[#chartData] then
			table.insert(sampled, chartData[#chartData])
		end

		chartData = sampled
	end

	local count = #chartData

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
		seg.Size = UDim2.fromOffset(length, 2)
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

-- Until a player's first trade, the order ticket coaches them through it
local function updateCoaching()
	if not orderTicket then
		return -- the attribute can change while the screen is still being built
	end

	local progress = Player:GetAttribute("TutorialProgress")
	local hasTraded = progress ~= nil and string.find("," .. progress .. ",", ",FirstTrade,", 1, true) ~= nil

	orderTicket:setCoaching(progress ~= nil and currentTicker ~= "" and not hasTraded)
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
	currentPositionQuantity = 0

	renderFieldGrid(ContentAnalystReports, ANALYST_FIELDS, nil, "AR_")
	renderFieldGrid(ContentFundamentals, FUNDAMENTALS_FIELDS, nil, "FN_")
	clearOptionStats()

	setLoadingState(true)
	clearOptionChain()
	clearContractSelection()
	clearPositions()
	clearNewsFeed()
	renderMiniChart(nil)
	PriceChartCaption.Text = "Loading…"

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

	TickerInput.Text = ticker
	marketPicker:showLoaded(ticker)
	starterPicks:hide()

	if marketData.assetClass == "roblox" then
		gameBanner:show(marketData)
	else
		gameBanner:hide()
	end

	updateHeader(marketData)
	renderQuoteDetails(marketData)
	switchTab("QuoteDetails")

	-- Spawned so a slow theses read never holds up the rest of the screen
	task.spawn(thesisPanel.load, thesisPanel, ticker)

	-- MiniChart
	renderMiniChart(RequestChartEvent:InvokeServer(ticker, "5M"))

	-- ── Options data ──────────────────────────────────────────────────────────
	local optionData = GetOptionsDataEvent:InvokeServer(ticker)

	if optionData then
		currentOptionData = optionData
		renderOptionChain(optionData)
	end

	-- ── Player positions ──────────────────────────────────────────────────────
	refreshPositions()

	-- ── News feed ──────────────────────────────────────────────────────────────
	renderNewsFeed(GetNewsFeedEvent:InvokeServer(ticker))

	isFetchingData = false
	orderTicket:update() -- the new ticker and price
	updateCoaching()
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
-- Crypto and the Roblox market trade around the clock
local function isMarketOpen()
	return Instruments.tradesAroundTheClock(currentTicker) or MarketHoursModule.getMarketStatus(os.time())
end

-- The header's Buy and Sell trade one share, or one contract of the option
-- picked in the chain, at market. What happened shows in the order ticket's
-- status line, right under the header (it only reached the output log).
local function placeOrder(action)
	if currentTicker == "" or isFetchingData then
		return
	end

	if not isMarketOpen() then
		orderTicket:setStatus("The market is closed, so market orders can't fill right now.", RED)

		return
	end

	local result

	if selectedContract then
		result = PlayerOptionOrderEvent:InvokeServer(
			action,
			selectedContract.contractSymbol,
			selectedContract.ticker,
			selectedContract.expiration,
			selectedContract.strike,
			selectedContract.type,
			orderQuantity
		)
	else
		result = PlayerOrderEvent:InvokeServer(action, currentTicker, orderQuantity)
	end

	if not result or not result.success then
		orderTicket:setStatus((result and result.message) or "Order failed. Try again.", RED)

		return
	end

	orderTicket:setStatus(result.message, GREEN)
	refreshPositions()
end

BuyButton.MouseButton1Click:Connect(function()
	placeOrder("Buy")
end)

SellButton.MouseButton1Click:Connect(function()
	placeOrder("Sell")
end)

BuyButton.BackgroundColor3 = Theme.Colors.Up
SellButton.BackgroundColor3 = Theme.Colors.Down
attachHover(BuyButton, Theme.Colors.Up, Theme.Colors.UpHover)
attachHover(SellButton, Theme.Colors.Down, Theme.Colors.DownHover)

-- Ticker Input (real-world market; the picker handles Roblox searches)
TickerInput.FocusLost:Connect(function(enterPressed)
	if not enterPressed or marketPicker:getMarket() == "Roblox" then
		return
	end

	local raw = string.upper((string.gsub(TickerInput.Text, "%s+", "")))

	if raw == "" then
		TickerInput.Text = currentTicker ~= "" and currentTicker or "..."

		return
	end

	loadTicker(raw)
end)

-- Another screen opened a ticker (e.g. a Portfolio row); TerminalController
-- switches to this tab
Navigation.TickerRequested:Connect(loadTicker)

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
Player:GetAttributeChangedSignal("TutorialProgress"):Connect(function()
	updateCoaching()
end)
Player:GetAttributeChangedSignal("NetWorth"):Connect(onBalanceChanged)

-- Screen and sections
TradeScreen.CanvasSize = UDim2.new()
TradeScreen.AutomaticCanvasSize = Enum.AutomaticSize.Y
TradeScreen.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
TradeScreen:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, SECTION_GAP)
addPadding(TradeScreen, SCREEN_PADDING)

for name, layoutOrder in pairs(SECTION_ORDER) do
	local section = TradeScreen:FindFirstChild(name)

	if section then
		section.LayoutOrder = layoutOrder
	end
end

-- The screen's padding replaces the row's own
InputRow.Size = UDim2.new(1, 0, 0, INPUT_ROW_HEIGHT)
InputRow.BackgroundTransparency = 1
InputRow:FindFirstChildOfClass("UIPadding"):Destroy()

-- Price: the 5-minute line in a titled panel, captioned with its period and range
local PriceChart = UIKit.makePanel("PriceChart", TradeScreen)
PriceChart.LayoutOrder = SECTION_ORDER.PriceChart
PriceChart.Size = UDim2.new(1, 0, 0, PRICE_CHART_HEIGHT)
addPadding(PriceChart, SECTION_PADDING)
makeSectionTitle("Title", PriceChart, "Price")

PriceChartCaption =
	UIKit.makeLabel("Caption", PriceChart, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.TextMuted)
PriceChartCaption.AnchorPoint = Vector2.new(1, 0)
PriceChartCaption.Position = UDim2.fromScale(1, 0)
PriceChartCaption.Size = UDim2.new(1, -80, 0, SECTION_TITLE_HEIGHT)
PriceChartCaption.TextXAlignment = Enum.TextXAlignment.Right
PriceChartCaption.TextYAlignment = Enum.TextYAlignment.Top

MiniChart.Parent = PriceChart
MiniChart.Position = UDim2.fromOffset(0, SECTION_TITLE_HEIGHT + 8)
MiniChart.Size = UDim2.new(1, 0, 1, -(SECTION_TITLE_HEIGHT + 8))
MiniChart.BackgroundTransparency = 1

MiniChart:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if lastMiniChartData then
		renderMiniChart(lastMiniChartData)
	end
end)

-- Your position: a title, the table or a line saying there's none, and a
-- height that fits (the Studio frame was 160 px with a canvas twice that)
local PositionsLayout = PositionsTable:FindFirstChildOfClass("UIListLayout")
local POSITIONS_TABLE_WIDTH = 8 + TICKER_COL_WIDTH + 8

for _, column in ipairs(POSITION_COLUMNS) do
	POSITIONS_TABLE_WIDTH += column.width
end

PositionsTable.CanvasSize = UDim2.new()
PositionsTable.AutomaticCanvasSize = Enum.AutomaticSize.X -- the columns scroll sideways on a narrow screen
addPadding(PositionsTable, SECTION_PADDING)

local PositionsTitle = makeSectionTitle("PosTitle", PositionsTable, "Your position")
PositionsTitle.LayoutOrder = -2
PositionsTitle.Size = UDim2.new(1, 0, 0, SECTION_TITLE_HEIGHT + 6)

local PositionsEmpty =
	UIKit.makeLabel("EmptyLabel", PositionsTable, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
PositionsEmpty.LayoutOrder = -1
PositionsEmpty.Size = UDim2.new(1, 0, 0, ROW_HEIGHT_POS)
PositionsEmpty.Text = "Load a ticker to see your position."

local function fitPositions()
	PositionsTable.Size = UDim2.new(1, 0, 0, PositionsLayout.AbsoluteContentSize.Y + SECTION_PADDING * 2)
end

PositionsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitPositions)

-- Wide enough for every column, so the canvas can scroll to them
PositionsTable.ChildAdded:Connect(function(child)
	if child:IsA("Frame") and (child.Name == "PosHeader" or string.match(child.Name, "^Pos_")) then
		local constraint = Instance.new("UISizeConstraint")
		constraint.MinSize = Vector2.new(POSITIONS_TABLE_WIDTH, 0)
		constraint.Parent = child
	end
end)

-- Research tabs: padded content, tabs inset from the edge
addPadding(TabContentContainer, RESEARCH_CONTENT_PADDING, SECTION_PADDING)
addPadding(TabHeaderContainer, 0, SECTION_PADDING)

for _, content in pairs(TabContents) do
	local layout = content:FindFirstChildWhichIsA("UIGridStyleLayout")

	if layout then
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitQuoteDetails)
	end
end

-- Option chain: the toggle bar's text inset by padding rather than spaces
addPadding(ChainToggle, 0, SECTION_PADDING)
ChainData.CanvasSize = UDim2.new()
ChainData.AutomaticCanvasSize = Enum.AutomaticSize.Y

-- News: a title, the headlines or a line saying there are none, and a
-- height that fits up to about five before scrolling
local NewsLayout = NewsFeed:FindFirstChildOfClass("UIListLayout")

NewsFeed.CanvasSize = UDim2.new()
NewsFeed.AutomaticCanvasSize = Enum.AutomaticSize.Y
addPadding(NewsFeed, SECTION_PADDING)

local NewsTitle = makeSectionTitle("NewsTitle", NewsFeed, "News")
NewsTitle.LayoutOrder = -2

local NewsEmpty = UIKit.makeLabel("EmptyLabel", NewsFeed, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
NewsEmpty.LayoutOrder = -1
NewsEmpty.Size = UDim2.new(1, 0, 0, 22)
NewsEmpty.Text = "Load a ticker to see its headlines."

local function fitNews()
	NewsFeed.Size =
		UDim2.new(1, 0, 0, math.min(NewsLayout.AbsoluteContentSize.Y, NEWS_MAX_HEIGHT) + SECTION_PADDING * 2)
end

NewsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitNews)

gameBanner = GameBannerModule.new({ parent = TradeScreen, layoutOrder = SECTION_ORDER.GameBanner })

starterPicks = StarterPicksModule.new({
	parent = TradeScreen,
	layoutOrder = SECTION_ORDER.StarterPicks,
	onSelect = function(ticker)
		task.spawn(loadTicker, ticker)
	end,
})

marketPicker = MarketPickerModule.new({
	inputRow = InputRow,
	input = TickerInput,
	overlayParent = MainBackground,
	screen = TradeScreen,
	onSelect = function(ticker)
		task.spawn(loadTicker, ticker)
	end,
})

orderTicket = OrderTicketModule.new({
	parent = TradeScreen,
	layoutOrder = SECTION_ORDER.OrderTicket,
	getTicker = function()
		return currentTicker
	end,
	getPrice = function()
		return currentPrice
	end,
	getPosition = function()
		return currentPositionQuantity
	end,
	onOrderPlaced = refreshPositions,
})

-- Theses go after the news, at the end of the research sections
thesisPanel = ThesisPanelModule.new({
	parent = TradeScreen,
	layoutOrder = SECTION_ORDER.Theses,
	getPrice = function()
		return currentPrice
	end,
})

switchTab("QuoteDetails")

setChainExpanded(false)
TableHeader.Visible = false
fitPositions()
fitNews()
