local IndicatorModule = require(script.Parent.IndicatorModule)
local Theme = require(script.Parent.Theme)

local ChartRenderer = {}

local GREEN = Theme.Colors.Up
local RED = Theme.Colors.Down

-- The live-price badge sits in the 60px-wide right axis; six-figure prices
-- (e.g. BTC) only fit without decimals
local BADGE_DECIMALS_CUTOFF = 10000

local INDICATOR_FUNCTIONS = {
	sma = IndicatorModule.sma,
	ema = IndicatorModule.ema,
}

ChartRenderer.TimeframeFormats = {
	["D"] = "%b %d, %Y",
	["H"] = "%b %d, %H:%M",
	["30M"] = "%b %d, %H:%M",
	["5M"] = "%H:%M",
	["M"] = "%H:%M",
}

-- Renders full candlestick chart
--
-- elements: {
--     ChartTickerLabel : TextLabel
--     CandlesContainer : Frame
--     GridContainer : Frame
--     IndicatorsContainer : Frame
--     RightAxis : Frame
--     BottomAxis : Frame
--     MainChart : Frame
-- }
--
-- ticker : string
-- chartData : array  { Open, High, Low, Close, Timestamp}
-- timeframe : string matching TimeframeFormats keys
-- liveCandle : optional latest candle (full series); used for price badge when viewport is scrolled
-- indicators : optional array of { key, type ("sma"|"ema"), period, color }, drawn as overlay lines
--
-- Returns minPrice, maxPrice,

function ChartRenderer.render(elements, ticker, chartData, timeframe, liveCandle, indicators)
	local ChartTickerLabel = elements.ChartTickerLabel
	local CandlesContainer = elements.CandlesContainer
	local GridContainer = elements.GridContainer
	local IndicatorsContainer = elements.IndicatorsContainer
	local RightAxis = elements.RightAxis
	local BottomAxis = elements.BottomAxis
	local MainChart = elements.MainChart

	ChartTickerLabel.Text = ticker

	CandlesContainer:ClearAllChildren()
	GridContainer:ClearAllChildren()

	if IndicatorsContainer then
		IndicatorsContainer:ClearAllChildren()
	end

	for _, child in pairs(RightAxis:GetChildren()) do
		if string.match(child.Name, "AxisLabel_") then
			child:Destroy()
		end
	end
	for _, child in pairs(BottomAxis:GetChildren()) do
		if string.match(child.Name, "AxisLabel_") then
			child:Destroy()
		end
	end

	if not chartData or #chartData == 0 then
		return
	end

	-- Price range calculations
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

	-- Candles Calculations
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
		end

		local wickFrame = Instance.new("Frame")
		wickFrame.Name = "Candle_Wick_" .. index
		wickFrame.AnchorPoint = Vector2.new(0.5, 0)
		wickFrame.BackgroundColor3 = candleColor
		wickFrame.Size = UDim2.new(0, 1, wickHeightScale, 0)
		wickFrame.Position = UDim2.fromScale(xPositionScale + (candleWidthScale / 2), wickTopScale)
		wickFrame.Parent = CandlesContainer

		local bodyFrame = Instance.new("Frame")
		bodyFrame.Name = "Candle_Body_" .. index
		bodyFrame.AnchorPoint = Vector2.new(0.5, 0)
		bodyFrame.BackgroundColor3 = candleColor
		bodyFrame.Size = UDim2.fromScale(candleWidthScale - paddingScale, bodyHeightScale)
		bodyFrame.Position = UDim2.fromScale(xPositionScale + (candleWidthScale / 2), bodyTopScale)
		bodyFrame.Parent = CandlesContainer
	end

	-- Indicator Overlays (moving averages drawn on the same price scale as the candles)
	if IndicatorsContainer and indicators and #indicators > 0 then
		local closes = {}

		for index, candle in ipairs(chartData) do
			closes[index] = candle.Close
		end

		for _, indicator in ipairs(indicators) do
			local computeFn = INDICATOR_FUNCTIONS[indicator.type]
			local values = computeFn and computeFn(closes, indicator.period)

			if values then
				for index = 2, numberCandles do
					local previousValue = values[index - 1]
					local currentValue = values[index]

					if previousValue and currentValue then
						local x1 = ((index - 2) * candleWidthScale) + (candleWidthScale / 2)
						local x2 = ((index - 1) * candleWidthScale) + (candleWidthScale / 2)
						local y1 = (maximumPrice - previousValue) / priceRange
						local y2 = (maximumPrice - currentValue) / priceRange

						local dx = (x2 - x1) * MainChart.AbsoluteSize.X
						local dy = (y2 - y1) * MainChart.AbsoluteSize.Y
						local length = math.sqrt(dx * dx + dy * dy)
						local angle = math.deg(math.atan2(dy, dx))

						local segment = Instance.new("Frame")
						segment.Name = indicator.key .. "_" .. index
						segment.AnchorPoint = Vector2.new(0.5, 0.5)
						segment.BackgroundColor3 = indicator.color
						segment.BorderSizePixel = 0
						segment.ZIndex = 2
						segment.Size = UDim2.fromOffset(length, 2)
						segment.Rotation = angle
						segment.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
						segment.Parent = IndicatorsContainer
					end
				end
			end
		end
	end

	-- Grid and Axis Labels

	local numberPriceLabels = 10
	local numberTimeLabels = 4

	local containerHeight = MainChart.AbsoluteSize.Y

	if containerHeight and containerHeight > 0 then
		numberPriceLabels = math.clamp(math.floor(containerHeight / 55), 3, 10)
	end

	if numberCandles > 150 then
		numberTimeLabels = 8
	elseif numberCandles > 80 then
		numberTimeLabels = 6
	else
		numberTimeLabels = 4
	end

	if numberTimeLabels >= numberCandles then
		numberTimeLabels = math.max(1, numberCandles - 1)
	end

	for index = 0, numberPriceLabels do
		local percentage = index / numberPriceLabels
		local priceValue = minimumPrice + (priceRange * percentage)
		local yScale = 1 - percentage

		if index > 0 and index < numberPriceLabels then
			local priceLabel = Instance.new("TextLabel")
			priceLabel.Name = "AxisLabel_Price_" .. index
			priceLabel.Text = string.format("%.2f", priceValue)
			priceLabel.Size = UDim2.fromOffset(80, 20)
			priceLabel.Position = UDim2.new(1, -85, yScale, -10)
			priceLabel.BackgroundTransparency = 1
			priceLabel.TextColor3 = Theme.Colors.TextMuted
			priceLabel.FontFace = Theme.Fonts.Mono
			priceLabel.TextSize = Theme.TextSize.Caption
			priceLabel.TextXAlignment = Enum.TextXAlignment.Right
			priceLabel.Parent = RightAxis

			local horizontalGrid = Instance.new("Frame")
			horizontalGrid.Name = "HorizontalGrid_" .. index
			horizontalGrid.Size = UDim2.new(1, 0, 0, 1)
			horizontalGrid.Position = UDim2.fromScale(0, yScale)
			horizontalGrid.BackgroundColor3 = Theme.Colors.Border
			horizontalGrid.BackgroundTransparency = 0
			horizontalGrid.ZIndex = 1
			horizontalGrid.Parent = GridContainer
		end
	end

	-- Time Labels & Vertical Grid Lines

	for index = 0, numberTimeLabels do
		local dataIndex = math.floor((index / numberTimeLabels) * (numberCandles - 1)) + 1

		if chartData[dataIndex] then
			local candleXPositionScale = (dataIndex - 1) * candleWidthScale
			local candleCenterScale = candleXPositionScale + (candleWidthScale / 2)

			local timeLabel = Instance.new("TextLabel")
			timeLabel.Name = "AxisLabel_Time" .. index
			timeLabel.BackgroundTransparency = 1
			timeLabel.Size = UDim2.new(0, 60, 1, 0)
			timeLabel.TextColor3 = Theme.Colors.TextMuted
			timeLabel.FontFace = Theme.Fonts.Mono
			timeLabel.TextSize = Theme.TextSize.Caption

			if index == 0 then
				timeLabel.AnchorPoint = Vector2.new(0, 0)
				timeLabel.Position = UDim2.fromOffset(5, 0)
				timeLabel.TextXAlignment = Enum.TextXAlignment.Left
			elseif index == numberTimeLabels then
				timeLabel.AnchorPoint = Vector2.new(1, 0)
				timeLabel.Position = UDim2.new(1, -5, 0, 0)
				timeLabel.TextXAlignment = Enum.TextXAlignment.Right
			else
				timeLabel.AnchorPoint = Vector2.new(0.5, 0)
				timeLabel.Position = UDim2.fromScale(candleCenterScale, 0)
				timeLabel.TextXAlignment = Enum.TextXAlignment.Center
			end

			local timestamp = chartData[dataIndex].Timestamp or os.time()

			if timeframe == "D" then
				timeLabel.Text = os.date("%b %d", timestamp)
			else
				local timeData = os.date("*t", timestamp)
				timeLabel.Text = string.format("%02d:%02d", timeData.hour, timeData.min)
			end

			timeLabel.Parent = BottomAxis

			if index > 0 and index < numberTimeLabels then
				local verticalGrid = Instance.new("Frame")
				verticalGrid.Name = "VerticalGrid_" .. index
				verticalGrid.Size = UDim2.new(0, 1, 1, 0)
				verticalGrid.Position = UDim2.fromScale(candleCenterScale, 0)
				verticalGrid.BackgroundColor3 = Theme.Colors.Border
				verticalGrid.BackgroundTransparency = 0
				verticalGrid.ZIndex = 1
				verticalGrid.Parent = GridContainer
			end
		end
	end

	-- Price Badge (always reflects live candle, not viewport tail)
	local viewportLastCandle = chartData[numberCandles]
	local badgeCandle = liveCandle or viewportLastCandle

	if badgeCandle then
		local currentPrice = badgeCandle.Close
		local isBullish = badgeCandle.Close >= badgeCandle.Open
		local color = isBullish and GREEN or RED
		local yScale = (maximumPrice - currentPrice) / priceRange
		yScale = math.clamp(yScale, 0, 1)

		local PriceLine = Instance.new("ImageLabel")
		PriceLine.Name = "LivePriceLine"
		PriceLine.Size = UDim2.new(1, 0, 0, 2)
		PriceLine.Position = UDim2.fromScale(0, yScale)
		PriceLine.BackgroundTransparency = 1
		PriceLine.ZIndex = 3
		PriceLine.Image = "rbxassetid://83871845664366"
		PriceLine.ImageColor3 = color
		PriceLine.ScaleType = Enum.ScaleType.Tile
		PriceLine.TileSize = UDim2.new(0, 8, 1, 0)
		PriceLine.Parent = GridContainer

		local PriceBadge = Instance.new("Frame")
		PriceBadge.Name = "AxisLabel_LiveBadge"
		PriceBadge.Size = UDim2.fromOffset(55, 24)
		PriceBadge.AnchorPoint = Vector2.new(0, 0.5)
		PriceBadge.Position = UDim2.new(0, 5, yScale, 0)
		PriceBadge.BackgroundColor3 = color
		PriceBadge.ZIndex = 4
		PriceBadge.Parent = RightAxis

		local BadgeText = Instance.new("TextLabel")
		BadgeText.Name = "PriceText"
		BadgeText.Text = string.format(currentPrice >= BADGE_DECIMALS_CUTOFF and "%.0f" or "%.2f", currentPrice)
		BadgeText.Size = UDim2.new(1, -6, 0, 12)
		BadgeText.Position = UDim2.fromOffset(3, 1)
		BadgeText.BackgroundTransparency = 1
		BadgeText.TextColor3 = Theme.Colors.Background -- dark text stays readable on the Up/Down fill
		BadgeText.FontFace = Theme.Fonts.UIBold
		BadgeText.TextSize = Theme.TextSize.Caption -- the text box is only 12px tall
		BadgeText.TextXAlignment = Enum.TextXAlignment.Center
		BadgeText.ZIndex = 5
		BadgeText.Parent = PriceBadge

		local TimerText = Instance.new("TextLabel")
		TimerText.Name = "CountdownText"
		TimerText.Text = "00:00"
		TimerText.Size = UDim2.new(1, -6, 0, 12)
		TimerText.Position = UDim2.fromOffset(3, 11)
		TimerText.BackgroundTransparency = 1
		TimerText.TextColor3 = Theme.Colors.Background
		TimerText.FontFace = Theme.Fonts.UI
		TimerText.TextSize = Theme.TextSize.Caption
		TimerText.TextXAlignment = Enum.TextXAlignment.Center
		TimerText.ZIndex = 5
		TimerText.Parent = PriceBadge
	end

	return minimumPrice, maximumPrice
end

return ChartRenderer
