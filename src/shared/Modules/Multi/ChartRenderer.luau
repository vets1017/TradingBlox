local Theme = require(script.Parent.Theme)

local ChartRenderer = {}

local GREEN = Theme.Colors.Up
local RED = Theme.Colors.Down

-- The live-price badge sits in the 60px-wide right axis; six-figure prices
-- (e.g. BTC) only fit without decimals
local BADGE_DECIMALS_CUTOFF = 10000

local PROFILE_WIDTH = 0.25 -- of the chart's width, for the busiest price band
local PROFILE_TRANSPARENCY = 0.75
local BAR_TRANSPARENCY = 0.35
local PANE_PADDING = 0.1 -- of a pane's value range, above and below

-- One line through `line.values` (aligned with the candles; nil gaps are
-- left out, and so are joins into an index in `line.breaks`) as rotated
-- segments in `container`. `toY(value)` gives the value's height on the
-- container's scale, 0 at the top.
local function drawLine(container, name, line, count, color, toY)
	local size = container.AbsoluteSize
	local width = 1 / count
	local values, breaks = line.values, line.breaks

	for index = 2, count do
		local previous, current = values[index - 1], values[index]

		if previous and current and not (breaks and breaks[index]) then
			local x1, x2 = (index - 1.5) * width, (index - 0.5) * width
			local y1, y2 = toY(previous), toY(current)
			local dx, dy = (x2 - x1) * size.X, (y2 - y1) * size.Y

			local segment = Instance.new("Frame")
			segment.Name = name .. "_" .. index
			segment.AnchorPoint = Vector2.new(0.5, 0.5)
			segment.BackgroundColor3 = color
			segment.BackgroundTransparency = line.transparency or 0
			segment.BorderSizePixel = 0
			segment.ZIndex = 2
			segment.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), 2)
			segment.Rotation = math.deg(math.atan2(dy, dx))
			segment.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
			segment.Parent = container
		end
	end
end

-- The last value set in `values`, looking back from `count`
local function lastValue(values, count)
	for index = count, 1, -1 do
		if values[index] then
			return values[index]
		end
	end

	return nil
end

ChartRenderer.TimeframeFormats = {
	["D"] = "%b %d, %Y",
	["H"] = "%b %d, %H:%M",
	["30M"] = "%b %d, %H:%M",
	["5M"] = "%H:%M",
	["1M"] = "%H:%M",
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
-- }
--
-- ticker : string
-- chartData : array  { Open, High, Low, Close, Timestamp}
-- timeframe : string matching TimeframeFormats keys
-- liveCandle : optional latest candle (full series); used for price badge when viewport is scrolled
-- overlays : optional array of indicators drawn on the price scale, each
--     { key, color, lines = { { values, color?, transparency?, breaks? } }?,
--       profile = { low, high, volumes }? } with values aligned to chartData.
--     Lines widen the price scale so they stay in view; a profile draws as
--     bars from the right edge, one per price band.
--
-- Returns minPrice, maxPrice,

function ChartRenderer.render(elements, ticker, chartData, timeframe, liveCandle, overlays)
	local ChartTickerLabel = elements.ChartTickerLabel
	local CandlesContainer = elements.CandlesContainer
	local GridContainer = elements.GridContainer
	local IndicatorsContainer = elements.IndicatorsContainer
	local RightAxis = elements.RightAxis
	local BottomAxis = elements.BottomAxis

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

	for _, overlay in ipairs(overlays or {}) do
		for _, line in ipairs(overlay.lines or {}) do
			for index = 1, #chartData do
				local value = line.values[index]

				if value then
					minimumPrice = math.min(minimumPrice, value)
					maximumPrice = math.max(maximumPrice, value)
				end
			end
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

	-- Indicator overlays, on the same price scale as the candles
	if IndicatorsContainer and overlays then
		local function toY(price)
			return (maximumPrice - price) / priceRange
		end

		for _, overlay in ipairs(overlays) do
			for lineIndex, line in ipairs(overlay.lines or {}) do
				drawLine(
					IndicatorsContainer,
					overlay.key .. "_" .. lineIndex,
					line,
					numberCandles,
					line.color or overlay.color,
					toY
				)
			end

			local profile = overlay.profile

			if profile then
				local busiest = math.max(table.unpack(profile.volumes))
				local bandHeight = (profile.high - profile.low) / #profile.volumes

				for band, volume in ipairs(profile.volumes) do
					if volume > 0 then
						local bar = Instance.new("Frame")
						bar.Name = overlay.key .. "_" .. band
						bar.AnchorPoint = Vector2.new(1, 0)
						bar.BackgroundColor3 = overlay.color
						bar.BackgroundTransparency = PROFILE_TRANSPARENCY
						bar.BorderSizePixel = 0
						bar.Position = UDim2.fromScale(1, toY(profile.low + band * bandHeight))
						bar.Size = UDim2.new(PROFILE_WIDTH * volume / busiest, 0, bandHeight / priceRange, -1)
						bar.Parent = IndicatorsContainer
					end
				end
			end
		end
	end

	-- Grid and Axis Labels

	local numberPriceLabels = 10
	local numberTimeLabels = 4

	-- The candles' own height: indicator panes may take some of the chart's
	local containerHeight = CandlesContainer.AbsoluteSize.Y

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

-- Draws an oscillator in `container` (a pane under the chart, emptied
-- first) for `count` visible candles:
--   pane = { key, label, color, lines = { { values, color? } },
--            bars = { values }?, range = { min, max }?, guides = { number }? }
-- Values are aligned to the candles. Without a range the pane fits its
-- values (and zero, when it has bars). Bars rise or fall from zero in the
-- up or down color. The label shows each line's latest value.
function ChartRenderer.renderPane(container, pane, count)
	container:ClearAllChildren()

	if count == 0 then
		return
	end

	local low, high

	if pane.range then
		low, high = pane.range[1], pane.range[2]
	else
		low, high = math.huge, -math.huge

		local function include(values)
			for index = 1, count do
				if values[index] then
					low = math.min(low, values[index])
					high = math.max(high, values[index])
				end
			end
		end

		for _, line in ipairs(pane.lines or {}) do
			include(line.values)
		end

		if pane.bars then
			include(pane.bars.values)
			low, high = math.min(low, 0), math.max(high, 0)
		end

		if low > high then
			return
		end

		local padding = math.max(high - low, math.abs(high) * 0.01, 1e-9) * PANE_PADDING

		low -= padding
		high += padding
	end

	local function toY(value)
		return (high - value) / (high - low)
	end

	local function addAxisLabel(name, value)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(1, 5, math.clamp(toY(value), 0.08, 0.92), 0)
		label.Size = UDim2.fromOffset(50, 14)
		label.FontFace = Theme.Fonts.Mono
		label.TextSize = Theme.TextSize.Caption
		label.TextColor3 = Theme.Colors.TextMuted
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = string.format("%.2f", value)
		label.Parent = container
	end

	for index, guide in ipairs(pane.guides or {}) do
		local line = Instance.new("Frame")
		line.Name = "Guide_" .. index
		line.BackgroundColor3 = Theme.Colors.Border
		line.BorderSizePixel = 0
		line.Position = UDim2.fromScale(0, toY(guide))
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Parent = container

		addAxisLabel("AxisLabel_Guide_" .. index, guide)
	end

	if not pane.guides then
		addAxisLabel("AxisLabel_High", high)
		addAxisLabel("AxisLabel_Low", low)
	end

	if pane.bars then
		local width = 1 / count
		local zero = toY(0)

		for index = 1, count do
			local value = pane.bars.values[index]

			if value and value ~= 0 then
				local bar = Instance.new("Frame")
				bar.Name = "Bar_" .. index
				bar.AnchorPoint = Vector2.new(0.5, 0)
				bar.BackgroundColor3 = value > 0 and GREEN or RED
				bar.BackgroundTransparency = BAR_TRANSPARENCY
				bar.BorderSizePixel = 0
				bar.Position = UDim2.fromScale((index - 0.5) * width, math.min(zero, toY(value)))
				bar.Size = UDim2.fromScale(width * 0.6, math.abs(toY(value) - zero))
				bar.Parent = container
			end
		end
	end

	local readings = {}

	for lineIndex, line in ipairs(pane.lines or {}) do
		local color = line.color or pane.color

		drawLine(container, pane.key .. "_" .. lineIndex, line, count, color, toY)

		local latest = lastValue(line.values, count)

		if latest then
			table.insert(readings, string.format('<font color="#%s">%.2f</font>', color:ToHex(), latest))
		end
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(6, 2)
	label.Size = UDim2.new(1, -12, 0, 16)
	label.FontFace = Theme.Fonts.Mono
	label.TextSize = Theme.TextSize.Caption
	label.TextColor3 = Theme.Colors.TextMuted
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.RichText = true
	label.ZIndex = 3
	label.Text = pane.label .. "  " .. table.concat(readings, "  ")
	label.Parent = container
end

return ChartRenderer
