-- LineChart.luau
--
-- Draws a { time, value } series as one continuous line - rotated 2px
-- segments, since Roblox has no polyline - over a soft fill that fades
-- downward. The line is Up or Down by whether the series ends above or below
-- where it started, and fades toward its oldest end. Time runs left to right
-- proportionally, so gaps (a player offline) read as straight stretches.
-- Used by the Portfolio chart and the profile panel's net-worth line.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)

local LineChart = {}

local VERTICAL_INSET = 0.1 -- headroom above the high and below the low
local LINE_THICKNESS = 2
local LINE_FADE = 0.6 -- how far the line's oldest end fades toward the background
local FILL_TOP_TRANSPARENCY = 0.85

-- { time, value } points to { x, y, time, value } with x and y as fractions
-- of the chart (y = 0 at the top). A single point draws as a flat line.
function LineChart.layout(points)
	if #points == 1 then
		points = { points[1], points[1] }
	end

	local low, high = math.huge, -math.huge

	for _, point in ipairs(points) do
		low = math.min(low, point[2])
		high = math.max(high, point[2])
	end

	local firstTime = points[1][1]
	local timeSpan = points[#points][1] - firstTime
	local laidOut = {}

	for index, point in ipairs(points) do
		local x = timeSpan > 0 and (point[1] - firstTime) / timeSpan or (index - 1) / (#points - 1)
		local y = high > low and VERTICAL_INSET + (1 - VERTICAL_INSET * 2) * (high - point[2]) / (high - low) or 0.5

		table.insert(laidOut, { x = x, y = y, time = point[1], value = point[2] })
	end

	return laidOut
end

function LineChart.getColor(points)
	return points[#points][2] >= points[1][2] and Theme.Colors.Up or Theme.Colors.Down
end

-- Draws laid-out points into `parent`, which should be empty and sized; its
-- AbsoluteSize sets the segment lengths, so redraw on resize. The fill sits
-- at `zIndex` and the line just above it.
function LineChart.draw(parent, laidOut, color, backgroundColor, zIndex)
	local width = math.max(parent.AbsoluteSize.X, 1)
	local height = math.max(parent.AbsoluteSize.Y, 1)
	local fadedColor = color:Lerp(backgroundColor, LINE_FADE)

	for i = 1, #laidOut - 1 do
		local from = laidOut[i]
		local to = laidOut[i + 1]
		local dx = (to.x - from.x) * width
		local dy = (to.y - from.y) * height

		local segment = Instance.new("Frame")
		segment.Name = "Segment_" .. i
		segment.BorderSizePixel = 0
		segment.BackgroundColor3 = Color3.new(1, 1, 1) -- tinted by the gradient
		segment.AnchorPoint = Vector2.new(0.5, 0.5)
		segment.Position = UDim2.fromScale((from.x + to.x) / 2, (from.y + to.y) / 2)
		-- +1px overlaps neighbours so sharp turns don't show a notch
		segment.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 1, LINE_THICKNESS)
		segment.Rotation = math.deg(math.atan2(dy, dx))
		segment.ZIndex = zIndex + 1
		segment.Parent = parent

		local segmentGradient = Instance.new("UIGradient")
		segmentGradient.Color = ColorSequence.new(fadedColor:Lerp(color, from.x), fadedColor:Lerp(color, to.x))
		segmentGradient.Parent = segment

		-- Fill: a column under the segment's lower end, fading out downward.
		-- Whole pixels, so neighbouring columns neither gap nor overlap.
		local left = math.floor(from.x * width)
		local right = math.floor(to.x * width)
		local top = math.floor(math.max(from.y, to.y) * height)

		if right > left and top < height then
			local fill = Instance.new("Frame")
			fill.Name = "Fill_" .. i
			fill.BorderSizePixel = 0
			fill.BackgroundColor3 = color
			fill.Position = UDim2.fromOffset(left, top)
			fill.Size = UDim2.fromOffset(right - left, height - top)
			fill.ZIndex = zIndex
			fill.Parent = parent

			local fillGradient = Instance.new("UIGradient")
			fillGradient.Rotation = 90
			fillGradient.Transparency = NumberSequence.new(FILL_TOP_TRANSPARENCY, 1)
			fillGradient.Parent = fill
		end
	end
end

return LineChart
