local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local NumberModule = require(ReplicatedStorage.Modules.NumberModule)

local Player = Players.LocalPlayer

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local RequestChartEvent = EventsFolder:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = EventsFolder:WaitForChild("GetMarketDataEvent")

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
local LeftSidebar = DashboardGrid:WaitForChild("LeftSidebar")
local AccountInfoWidget = LeftSidebar:WaitForChild("AccountInfoWidget")
local OptionPowerValue = AccountInfoWidget:WaitForChild("OptionPowerRow").ValueText
local NetLiquidityValue = AccountInfoWidget:WaitForChild("NetLiquidityRow").ValueText
local CashSweepValue = AccountInfoWidget:WaitForChild("CashSweepRow").ValueText
local AvailableFundsValue = AccountInfoWidget:WaitForChild("AvailableFundsRow").ValueText
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
local Sidebar = ChartsScreen:WaitForChild("Sidebar")
local ToggleActiveTraderButton = Sidebar:WaitForChild("ToggleActiveTraderButton")
local MainChart = ChartsScreen:WaitForChild("MainChart")
local BottomAxis = MainChart:WaitForChild("BottomAxis")
local ChartCanvas = MainChart:WaitForChild("ChartCanvas")
local RightAxis = MainChart:WaitForChild("RightAxis")
local LeftToolbar = MainChart:WaitForChild("LeftToolbar")
local TopToolbar = MainChart:WaitForChild("TopToolbar")
local CrosshairX = ChartCanvas:WaitForChild("CrosshairX")
local CrosshairY = ChartCanvas:WaitForChild("CrosshairY")
local HoverPriceTag = RightAxis:WaitForChild("HoverPriceTag")
local HoverTimeTag = BottomAxis:WaitForChild("HoverTimeTag")
local TickerInput = TopToolbar:WaitForChild("TickerInput")
local ChartTickerLabel = TopToolbar:WaitForChild("ChartTickerLabel")

local SWEEP_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_EASING = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local HIDDEN_POSITION = UDim2.new(1, 300, 0.5, 0)
local VISIBLE_POSITION = UDim2.new(1, -50, 0.5, 0)

local GREEN = Color3.fromRGB(14, 203, 129)
local RED = Color3.fromRGB(242, 54, 69)
local GRAY = Color3.fromRGB(132, 142, 156)

-- UI Dragging variables
local dragging = false
local dragInput = nil
local dragStart = nil
local startPosition = nil

local isActiveTradeVisible = false
local isCrosshairActive = true

local currentMaxPrice = 200.00
local currentMinPrice = 150.00
local currentDisplayedTicker = ""

local currentTimeframe = "D"

local isFetchingData = false

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
}

local Holidays = {
	["01-01"] = true, -- New Year's Day
	["01-15"] = true, -- Martin Luther King Jr. Day
	["02-19"] = true, -- Presidents' Day
	["03-29"] = true, -- Good Friday
	["05-27"] = true, -- Memorial Day
	["06-19"] = true, -- Juneteenth
	["07-04"] = true, -- Independence Day
	["09-02"] = true, -- Labor Day
	["11-28"] = true, -- Thanksgiving
	["12-25"] = true, -- Christmas
}

local TimeframeFormats = {
	["D"] = "%b %d, %Y",
	["H"] = "%b %d, %H:%M",
	["30M"] = "%b %d, %H:%M",
	["5M"] = "%H:%M",
	["M"] = "%H:%M",
}

local function refreshTerminal()
	local marketData = GetMarketDataEvent:InvokeServer()

	if not marketData then
		return
	end
	-- continue after stock-list is done
end

local function switchTab(tabName)
	for _, data in pairs(Tabs) do
		data.Frame.Visible = false
		data.Button.TextColor3 = Color3.fromRGB(120, 123, 134)
	end

	if Tabs[tabName] then
		Tabs[tabName].Frame.Visible = true
		Tabs[tabName].Button.TextColor3 = Color3.fromRGB(209, 212, 220)

		AccentGradient.Offset = Vector2.new(-1, 0)

		local sweepTween = TweenService:Create(AccentGradient, SWEEP_INFO, { Offset = Vector2.new(1, 0) })
		sweepTween:Play()
	end
end

local function updateGreeting()
	local timeData = os.date("*t")
	local hour = timeData.hour

	local greeting = "Welcome back,"
	if hour >= 5 and hour < 12 then
		greeting = "Good morning,"
	elseif hour >= 12 and hour < 17 then
		greeting = "Good afternoon,"
	elseif hour >= 17 and hour < 22 then
		greeting = "Good evening,"
	end

	local formattedDate = os.date("%A, %d %B %Y")

	GreetingText.Text = string.format("%s %s.", greeting, Player.DisplayName) -- Player.Name might be changed to a custom username instead
	DateText.Text = formattedDate
end

local function isMarketClosed(currentTime)
	local date = os.date("!*t", currentTime)

	if date.wday == 1 or date.wday == 7 then
		return true
	end

	local dateString = string.format("%02d-%02d", date.month, date.day)

	if Holidays[dateString] then
		return true
	end

	return false
end

local function updateCountdown()
	local time = os.time()
	local currentUTC = os.date("!*t", time)

	local marketOpen = os.time({
		year = currentUTC.year,
		month = currentUTC.month,
		day = currentUTC.day,
		hour = 13,
		minute = 30,
		second = 0,
	})

	local marketClose = os.time({
		year = currentUTC.year,
		month = currentUTC.month,
		day = currentUTC.day,
		hour = 20,
		minute = 0,
		second = 0,
	})

	local targetTime

	if not isMarketClosed(time) and time >= marketOpen and time < marketClose then
		targetTime = marketClose
		TitleText.Text = "NYSE Closes In"
		TitleText.TextColor3 = Color3.fromRGB(8, 153, 129)
	else
		TitleText.Text = "NYSE Opens In"
		TitleText.TextColor3 = Color3.fromRGB(120, 123, 134)
		targetTime = marketOpen

		if time >= marketOpen or isMarketClosed(time) then
			targetTime = targetTime + 86400
		end

		while isMarketClosed(targetTime) do
			targetTime = targetTime + 86400
		end
	end

	local differenceTime = targetTime - time

	local hours = math.floor(differenceTime / 3600)
	local minutes = math.floor((differenceTime % 3600) / 60)
	local seconds = differenceTime % 60

	HoursNumber.Text = string.format("%02d", hours)
	MinutesNumber.Text = string.format("%02d", minutes)
	SecondsNumber.Text = string.format("%02d", seconds)
end

for tabName, data in pairs(Tabs) do
	data.Button.MouseButton1Click:Connect(function()
		switchTab(tabName)
	end)
end

task.spawn(function()
	while true do
		updateCountdown()
		task.wait(1)
	end
end)

local function updateAccountInfo()
	local currentBalance = Player:GetAttribute("Balance") or 0
	local currentNetWorth = Player:GetAttribute("NetWorth") or 0
	local optionPower = currentBalance or 0 -- wip

	OptionPowerValue.Text = NumberModule.format(optionPower)
	NetLiquidityValue.Text = NumberModule.format(currentNetWorth)
	CashSweepValue.Text = NumberModule.format(currentBalance)
	AvailableFundsValue.Text = NumberModule.format(currentBalance)
end

local function toggleActiveTrader()
	isActiveTradeVisible = not isActiveTradeVisible

	local targetPosition = isActiveTradeVisible and VISIBLE_POSITION or HIDDEN_POSITION

	local slideTween = TweenService:Create(ActiveTraderPanel, SLIDE_EASING, { Position = targetPosition })
	slideTween:Play()

	if isActiveTradeVisible then
		ToggleActiveTraderButton.Text = "Hide Active Trader"
	else
		ToggleActiveTraderButton.Text = "Show Active Trader"
	end
end

local function renderChart(ticker, chartData)
	ChartTickerLabel.Text = ticker

	for _, child in pairs(ChartCanvas:GetChildren()) do
		if string.match(child.Name, "Candle_") then
			child:Destroy()
		end
	end
	for _, child in pairs(RightAxis:GetChildren()) do
		if string.match(child.name, "AxisLabel_") then
			child:Destroy()
		end
	end
	for _, child in pairs(BottomAxis:GetChildren()) do
		if string.match(child.name, "AxisLabel_") then
			child:Destroy()
		end
	end

	if not chartData or #chartData == 0 then
		print("Failed Chart Check")
		return
	end

	local minimumPrice = math.huge
	local maximumPrice = -math.huge

	for _, candle in ipairs(chartData) do
		if candle.Low < minimumPrice then
			minimumPrice = candle.Low
		end
		if candle.High > maximumPrice then
			maximumPrice = candle.High
		end
	end

	local priceRange = maximumPrice - minimumPrice

	if priceRange == 0 then
		priceRange = 1
	end

	maximumPrice = maximumPrice + (priceRange * 0.05)
	minimumPrice = minimumPrice - (priceRange * 0.05)
	priceRange = maximumPrice - minimumPrice
	currentMaxPrice = maximumPrice
	currentMinPrice = minimumPrice

	local numberCandles = #chartData
	local candleWidthScale = 1 / numberCandles
	local paddingScale = candleWidthScale * 0.2

	for index, candle in ipairs(chartData) do
		local isBullish = candle.Close >= candle.Open
		local candleColor = isBullish and GREEN or RED

		local xPositionScale = (index - 1) * candleWidthScale

		local wickTopScale = (maximumPrice - candle.High) / priceRange
		local wickHeightScale = (candle.High - candle.Low) / priceRange

		local bodyTopPrice = isBullish and candle.Close or candle.Open
		local bodyBottomPrice = isBullish and candle.Open or candle.Close

		local bodyTopScale = (maximumPrice - bodyTopPrice) / priceRange
		local bodyHeightScale = (bodyTopPrice - bodyBottomPrice) / priceRange

		if bodyHeightScale <= 0.002 then
			bodyHeightScale = 0.002
		end -- doji

		local wickFrame = Instance.new("Frame")
		wickFrame.Name = "Candle_Wick_" .. index
		wickFrame.BackgroundColor3 = candleColor
		wickFrame.BorderSizePixel = 0
		wickFrame.AnchorPoint = Vector2.new(0.5, 0)
		wickFrame.Size = UDim2.new(0, 1, wickHeightScale, 0)
		wickFrame.Position = UDim2.new(xPositionScale + (candleWidthScale / 2), 0, wickTopScale, 0)
		wickFrame.Parent = ChartCanvas

		local bodyFrame = Instance.new("Frame")
		bodyFrame.Name = "Candle_Body_" .. index
		bodyFrame.BackgroundColor3 = candleColor
		bodyFrame.BorderSizePixel = 0
		bodyFrame.Size = UDim2.new(candleWidthScale - paddingScale, 0, bodyHeightScale, 0)
		bodyFrame.Position = UDim2.new(xPositionScale + (paddingScale / 2), 0, bodyTopScale, 0)
		bodyFrame.Parent = ChartCanvas
	end

	local numberPriceLabels = 5

	for index = 0, numberPriceLabels do
		local percentage = index / numberPriceLabels
		local priceValue = minimumPrice + (priceRange * percentage)

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "AxisLabel_Price_" .. index
		priceLabel.Text = string.format("%.2f", priceValue)
		priceLabel.Size = UDim2.new(1, -10, 0, 20)
		priceLabel.Position = UDim2.new(0, 5, 1 - percentage, -10)
		priceLabel.BackgroundTransparency = 1
		priceLabel.TextColor3 = Color3.fromRGB(132, 142, 156)
		priceLabel.Parent = RightAxis
		priceLabel.Font = Enum.Font.SourceSans
		priceLabel.TextSize = 11
		priceLabel.TextXAlignment = Enum.TextXAlignment.Right
	end

	local numberTimeLabels = 4

	for index = 0, numberTimeLabels do
		local dataIndex = math.floor((index / numberTimeLabels) * (numberCandles - 1)) + 1

		if chartData[dataIndex] then
			local timeLabel = Instance.new("TextLabel")
			timeLabel.Name = "AxisLabel_Time_" .. index
			timeLabel.Size = UDim2.new(0, 60, 1, 0)
			timeLabel.Position = UDim2.new((index / numberTimeLabels), -30, 0, 0)
			timeLabel.BackgroundTransparency = 1

			local formatString = TimeframeFormats[currentTimeframe] or "%b %d"
			local timestamp = chartData[dataIndex].Timestamp or os.time()
			local dateString = os.date(formatString, timestamp)

			timeLabel.Text = dateString
			timeLabel.TextColor3 = Color3.fromRGB(132, 142, 156)
			timeLabel.Parent = BottomAxis
			timeLabel.Font = Enum.Font.SourceSans
			timeLabel.TextSize = 11
		end
	end
end

local function renderDailyOverview(ticker, data)
	ChartTickerLabel.Text = ticker .. " - Daily Overview"

	for _, child in pairs(ChartCanvas:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	if not data then
		return
	end

	local range = data.High - data.Low

	if range == 0 then
		range = 0.01
	end

	local currentPercentage = (data.Price - data.Low) / range
	currentPercentage = math.clamp(currentPercentage, 0, 1)

	local isBullish = data.Price >= data.Open
	local color = isBullish and GREEN or RED

	local rangeTrack = Instance.new("Frame")
	rangeTrack.Name = "RangeTrack"
	rangeTrack.Size = UDim2.new(0.8, 0, 0, 6)
	rangeTrack.Position = UDim2.new(0.1, 0, 0.5, -3)
	rangeTrack.BackgroundColor3 = Color3.fromRGB(43, 54, 69)
	rangeTrack.BorderSizePixel = 0
	rangeTrack.Parent = ChartCanvas

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = rangeTrack

	local priceMarker = Instance.new("Frame")
	priceMarker.Name = "PriceMarker"
	priceMarker.Size = UDim2.new(0, 4, 0, 24)
	priceMarker.Position = UDim2.new(currentPercentage, 0, 0.5, 0)
	priceMarker.BackgroundColor3 = color
	priceMarker.BorderSizePixel = 0
	priceMarker.Parent = rangeTrack

	local markerCorner = Instance.new("UICorner")
	markerCorner.CornerRadius = UDim.new(1, 0)
	markerCorner.Parent = priceMarker

	local function createLabel(text, value, xPosition, yPosition, alignment)
		local label = Instance.new("TextLabel")
		label.Text = text .. "\n$" .. string.format("%.2f", value)
		label.Size = UDim2.new(0, 100, 0, 20)
		label.Position = yPosition
		label.BackgroundTransparency = 1
		label.TextColor3 = GRAY
		label.Font = Enum.Font.SourceSans
		label.TextSize = 14
		label.TextXAlignment = alignment
		label.Parent = rangeTrack
		return label
	end

	createLabel("Today's Low", data.Low, 0, UDim2.new(0, 0, 1, 15), Enum.TextXAlignment.Left)

	createLabel("Today's High", data.High, 1, UDim2.new(1, 0, 1, 15), Enum.TextXAlignment.Right)

	createLabel("Open", data.Open, 0, UDim2.new(0, 0, 0, -45), Enum.TextXAlignment.Left)

	createLabel("Prev Close", data.PreviousClose, 1, UDim2.new(1, 0, 0, -45), Enum.TextXAlignment.Right)

	local currentLabel = Instance.new("TextLabel")
	currentLabel.Size = UDim2.new(0, 100, 0, 20)
	currentLabel.AnchorPoint = Vector2.new(0.5, 1)
	currentLabel.Position = UDim2.new(currentPercentage, 0, 0, -15)
	currentLabel.BackgroundTransparency = 1
	currentLabel.Text = "$" .. string.format("%.2f", data.Price)
	currentLabel.TextColor3 = color
	currentLabel.Font = Enum.Font.SourceSans
	currentLabel.TextSize = 18
	currentLabel.Parent = rangeTrack
end

ActiveTraderTopBar.InputBegan:Connect(function(input)
	if not isActiveTradeVisible then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPosition = ActiveTraderPanel.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

ActiveTraderTopBar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input == dragInput then
		local delta = input.Position - dragStart

		ActiveTraderPanel.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end
end)

ChartCanvas.InputChanged:Connect(function(input)
	if not isCrosshairActive then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local mousePosition = input.Position
		local canvasPosition = ChartCanvas.AbsolutePosition
		local canvasSize = ChartCanvas.AbsoluteSize

		local relativeX = mousePosition.X - canvasPosition.X
		local relativeY = mousePosition.Y - canvasPosition.Y

		if relativeX >= 0 and relativeX <= canvasSize.X and relativeY >= 0 and relativeY <= canvasSize.Y then
			CrosshairX.Visible = true
			CrosshairY.Visible = true
			HoverPriceTag.Visible = true
			HoverTimeTag.Visible = true

			CrosshairX.Position = UDim2.new(0, relativeX, 0, 0)
			CrosshairY.Position = UDim2.new(0, 0, 0, relativeY)

			local priceRange = currentMaxPrice - currentMinPrice
			local yPercentage = relativeY / canvasSize.Y
			local hoveredPrice = currentMaxPrice - (yPercentage * priceRange)

			HoverPriceTag.Position = UDim2.new(0, 0, 0, relativeY - (HoverPriceTag.AbsoluteSize.Y / 2))
			HoverPriceTag.Text = string.format("%.2f", hoveredPrice)

			HoverTimeTag.Position = UDim2.new(0, relativeX - (HoverTimeTag.AbsoluteSize.X / 2), 1, 0)
			HoverTimeTag.Text = "12:34" -- placeholder
		else
			CrosshairX.Visible = false
			CrosshairY.Visible = false
			HoverPriceTag.Visible = false
			HoverTimeTag.Visible = false
		end
	end
end)

ChartCanvas.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		CrosshairX.Visible = false
		CrosshairY.Visible = false
		HoverPriceTag.Visible = false
		HoverTimeTag.Visible = false
	end
end)

TickerInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		if isFetchingData then
			return
		end

		local targetTicker = string.gsub(string.upper(TickerInput.Text), "%s+", "")

		if targetTicker == "" then
			TickerInput.Text = currentDisplayedTicker
			return
		end

		isFetchingData = true

		if targetTicker == "GOOG" then
			TickerInput.Text = " . . . "
			ChartTickerLabel.Text = "Loading"

			local historicalData = RequestChartEvent:InvokeServer("GOOG", "D")

			if historicalData then
				currentDisplayedTicker = "GOOG"
				TickerInput.Text = "GOOG"

				renderChart("GOOG", historicalData)
			end
		end

		TickerInput.Text = " . . . "
		ChartTickerLabel.Text = "Loading"

		local newChartData = GetMarketDataEvent:InvokeServer(targetTicker) -- TEMPORARY

		if newChartData then
			currentDisplayedTicker = targetTicker
			TickerInput.Text = targetTicker
			renderDailyOverview(targetTicker, newChartData[targetTicker])

			currentDisplayedTicker = targetTicker
			TickerInput.Text = targetTicker
		else
			TickerInput.Text = " . . . "
			ChartTickerLabel.Text = "Error"
			-- send error
			task.delay(2, function()
				TickerInput.Text = currentDisplayedTicker
			end)
		end

		isFetchingData = false
	end
end)

Player:GetAttributeChangedSignal("Balance"):Connect(updateAccountInfo)
Player:GetAttributeChangedSignal("NetWorth"):Connect(updateAccountInfo)

ToggleActiveTraderButton.MouseButton1Click:Connect(toggleActiveTrader)

switchTab("Dashboard")
updateGreeting()
updateAccountInfo()
