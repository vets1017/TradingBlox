-- Services
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Modules
local NumberModule = require(ReplicatedStorage.Modules.NumberModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.MarketHoursModule)
local ChartRenderer = require(ReplicatedStorage.Modules.ChartRenderer)

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local RequestChartEvent = EventsFolder:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = EventsFolder:WaitForChild("GetMarketDataEvent")

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
local HoverTimeTag = ChartCanvas:WaitForChild("HoverTimeTag")
local TickerInputBox = TopToolbar:WaitForChild("TickerInputBox")
local TickerInput = TickerInputBox:WaitForChild("TickerInput")
local ChartLegend = ChartCanvas:WaitForChild("ChartLegend")
local ChartTickerLabel = ChartLegend:WaitForChild("ChartTickerLabel")
local TimeframeDropdown = TopToolbar:WaitForChild("TimeframeDropdown")
local TimeDropdownList = TimeframeDropdown:WaitForChild("TimeDropdownList")
local MainTimeframeButton = TimeframeDropdown:WaitForChild("MainTimeframeButton")
local ScrollTrack = ChartCanvas:WaitForChild("ScrollTrack")
local ScrollThumb = ScrollTrack:WaitForChild("ScrollThumb")
local CandlesContainer = ChartCanvas:WaitForChild("CandlesContainer")
local GridContainer = ChartCanvas:WaitForChild("GridContainer")

-- Tween Constants
local SWEEP_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_EASING = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Position Constants
local HIDDEN_POSITION = UDim2.new(1, 300, 0.5, 0)
local VISIBLE_POSITION = UDim2.new(1, -50, 0.5, 0)

-- RGB Constants
local GREEN = Color3.fromRGB(8, 153, 129)
local RED = Color3.fromRGB(242, 54, 69)
local GRAY = Color3.fromRGB(132, 142, 156)

local COLOR_ACTIVE_BACKGROUND = Color3.fromRGB(38, 166, 154)
local COLOR_ACTIVE_TEXT = Color3.fromRGB(255, 255, 255)
local COLOR_INACTIVE_BACKGROUND = Color3.fromRGB(30, 34, 45)
local COLOR_INACTIVE_TEXT = Color3.fromRGB(132, 142, 156)

-- UI Dragging variables
local dragging = false
local dragInput = nil
local dragStart = nil
local startPosition = nil

-- Variables
local currentMaxPrice
local currentMinPrice
local visibleCandles = 60 -- How much candles should be rendered
local rightOffset = 0 -- UI Offset for graph
local lastMouseDragX
local currentDisplayedTicker = ""
local currentTimeframe = "H" -- Default Timeframe
local scrollDragStartX = 0
local startRightOffset = 0 -- UI Offset for Scroll

-- Booleans
local isFetchingData = false
local isHoveringChart = false
local isActiveTradeVisible = false
local isCrosshairActive = true
local isDropdownOpen = false
local isDraggingChart = false
local isDraggingScroll = false

local currentChartData = {} -- Data of current chart
local masterChartData = {}
local viewportUpdateScheduled = false

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
}

local TimeDropdownOptions = {
	[TimeDropdownList:WaitForChild("1MinuteButton")] = { query = "1M" },
	[TimeDropdownList:WaitForChild("5MinuteButton")] = { query = "5M" },
	[TimeDropdownList:WaitForChild("30MinuteButton")] = { query = "30M" },
	[TimeDropdownList:WaitForChild("1HourButton")] = { query = "H" },
	[TimeDropdownList:WaitForChild("1DayButton")] = { query = "D" },
}

-- Unfinished
local function refreshTerminal()
	local marketData = GetMarketDataEvent:InvokeServer()

	if not marketData then
		return
	end
	-- continue after stock-list is done
end

local function renderChart(ticker, chartData)
	local liveCandle = #masterChartData > 0 and masterChartData[#masterChartData] or nil

	local minPrice, maxPrice = ChartRenderer.render({
		ChartTickerLabel = ChartTickerLabel,
		CandlesContainer = CandlesContainer,
		GridContainer = GridContainer,
		RightAxis = RightAxis,
		BottomAxis = BottomAxis,
		MainChart = MainChart,
	}, ticker, chartData, currentTimeframe, liveCandle)

	if minPrice and maxPrice then
		currentMinPrice = minPrice
		currentMaxPrice = maxPrice
	end
end

-- Switching tab function
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
		TitleText.TextColor3 = Color3.fromRGB(8, 153, 129)
	else
		TitleText.Text = "NYSE Opens In"
		TitleText.TextColor3 = Color3.fromRGB(120, 123, 134)
	end

	local differenceTime = targetTime - time

	local hours = math.floor(differenceTime / 3600)
	local minutes = math.floor((differenceTime % 3600) / 60)
	local seconds = differenceTime % 60

	HoursNumber.Text = string.format("%02d", hours)
	MinutesNumber.Text = string.format("%02d", minutes)
	SecondsNumber.Text = string.format("%02d", seconds)
end

-- Updates Account Info on Dashboard
local function updateAccountInfo()
	local currentBalance = Player:GetAttribute("Balance") or 0
	local currentNetWorth = Player:GetAttribute("NetWorth") or 0
	local optionPower = currentBalance or 0 -- wip

	OptionPowerValue.Text = NumberModule.format(optionPower)
	NetLiquidityValue.Text = NumberModule.format(currentNetWorth)
	CashSweepValue.Text = NumberModule.format(currentBalance)
	AvailableFundsValue.Text = NumberModule.format(currentBalance)
end

-- Toggle for ActiveTrader window
local function toggleActiveTrader()
	isActiveTradeVisible = not isActiveTradeVisible

	local targetPosition = isActiveTradeVisible and VISIBLE_POSITION or HIDDEN_POSITION

	local slideTween = TweenService:Create(ActiveTraderPanel, SLIDE_EASING, { Position = targetPosition })
	slideTween:Play() -- Tween slide for ActiveTrader window

	if isActiveTradeVisible then
		ToggleActiveTraderButton.Text = "Hide Active Trader"
	else
		ToggleActiveTraderButton.Text = "Show Active Trader"
	end
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

MainTimeframeButton.MouseButton1Click:Connect(function()
	isDropdownOpen = not isDropdownOpen
	TimeDropdownList.Visible = isDropdownOpen
end)

ActiveTraderTopBar.InputBegan:Connect(function(input)
	if not isActiveTradeVisible then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPosition = ActiveTraderPanel.Position
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

ChartCanvas.InputBegan:Connect(function(input)
	if isDraggingScroll then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
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
		if isFetchingData then
			return
		end

		local targetTicker = string.gsub(string.upper(TickerInput.Text), "%s+", "")

		if targetTicker == "" then
			TickerInput.Text = currentDisplayedTicker
			return
		end

		isFetchingData = true

		TickerInput.Text = " . . . "
		ChartTickerLabel.Text = "Loading"

		local chartData = RequestChartEvent:InvokeServer(targetTicker, currentTimeframe)

		if chartData and #chartData > 0 then
			masterChartData = chartData
			currentDisplayedTicker = targetTicker
			rightOffset = 0
			TickerInput.Text = targetTicker
			updateViewport()
		else
			TickerInput.Text = " . . . "
			ChartTickerLabel.Text = "Error"
			-- send error
			task.delay(2, function()
				TickerInput.Text = currentDisplayedTicker
			end)
		end

		isFetchingData = false
		return
	end
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

Player:GetAttributeChangedSignal("Balance"):Connect(updateAccountInfo)
Player:GetAttributeChangedSignal("NetWorth"):Connect(updateAccountInfo)

ToggleActiveTraderButton.MouseButton1Click:Connect(toggleActiveTrader)

switchTab("Dashboard")
updateGreeting()
updateAccountInfo()
