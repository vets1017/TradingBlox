local DrawingModule = {}

DrawingModule.DEFAULT_COLOR = Color3.fromRGB(255, 200, 0)

-- Renders session-only chart drawings (horizontal lines + trend lines) using
-- the same price-scale math ChartRenderer uses for candles/indicators.
--
-- elements: { DrawingsContainer : Frame } - the drawings' frame, covering the
--     candle canvas
-- chartData: the currently-visible candle window (same slice passed to
--     ChartRenderer.render this frame)
-- minPrice, maxPrice: the price range ChartRenderer.render returned for
--     this same chartData/frame
-- drawings: { horizontalLines: { {price, color} }, trendLines: { {t1, p1, t2, p2, color} } }
--
-- A trend line whose endpoint timestamp isn't in the current chartData
-- window (scrolled out of view, or a different timeframe) is skipped for
-- that render - v1 doesn't attempt to extrapolate or clip partial lines.
function DrawingModule.render(elements, chartData, minPrice, maxPrice, drawings)
	local DrawingsContainer = elements.DrawingsContainer

	DrawingsContainer:ClearAllChildren()

	if not chartData or #chartData == 0 or not drawings then
		return
	end

	local priceRange = maxPrice - minPrice

	if priceRange == 0 then
		priceRange = 1
	end

	local numberCandles = #chartData
	local candleWidthScale = 1 / numberCandles

	local timestampToIndex = {}
	for index, candle in ipairs(chartData) do
		timestampToIndex[candle.Timestamp] = index
	end

	local function priceToYScale(price)
		return (maxPrice - price) / priceRange
	end

	local function indexToXScale(index)
		return ((index - 1) * candleWidthScale) + (candleWidthScale / 2)
	end

	for _, line in ipairs(drawings.horizontalLines or {}) do
		local yScale = priceToYScale(line.price)

		local segment = Instance.new("Frame")
		segment.Name = "HorizontalLine"
		segment.BackgroundColor3 = line.color or DrawingModule.DEFAULT_COLOR
		segment.BorderSizePixel = 0
		segment.ZIndex = 3
		segment.Size = UDim2.new(1, 0, 0, 2)
		segment.Position = UDim2.fromScale(0, yScale)
		segment.Parent = DrawingsContainer
	end

	for _, line in ipairs(drawings.trendLines or {}) do
		local index1 = timestampToIndex[line.t1]
		local index2 = timestampToIndex[line.t2]

		if index1 and index2 then
			local x1 = indexToXScale(index1)
			local x2 = indexToXScale(index2)
			local y1 = priceToYScale(line.p1)
			local y2 = priceToYScale(line.p2)

			-- The points are fractions of the canvas, so the length and angle
			-- come from its size (the whole chart's ran each line past its ends)
			local dx = (x2 - x1) * DrawingsContainer.AbsoluteSize.X
			local dy = (y2 - y1) * DrawingsContainer.AbsoluteSize.Y
			local length = math.sqrt(dx * dx + dy * dy)
			local angle = math.deg(math.atan2(dy, dx))

			local segment = Instance.new("Frame")
			segment.Name = "TrendLine"
			segment.AnchorPoint = Vector2.new(0.5, 0.5)
			segment.BackgroundColor3 = line.color or DrawingModule.DEFAULT_COLOR
			segment.BorderSizePixel = 0
			segment.ZIndex = 3
			segment.Size = UDim2.fromOffset(math.max(length, 1), 2)
			segment.Rotation = angle
			segment.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
			segment.Parent = DrawingsContainer
		end
	end
end

return DrawingModule
