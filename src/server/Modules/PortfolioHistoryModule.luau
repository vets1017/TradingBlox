-- PortfolioHistoryModule.luau
--
-- Net-worth history behind the Portfolio tab's chart. A history is an
-- oldest-first array of { time, value } pairs (os.time() seconds, dollars),
-- kept on playerData.NetWorthHistory and saved with the rest of the
-- player's data. Detail thins out with age so the saved list stays small:
-- one point per 5 minutes for the last day, one per hour after that, and
-- nothing older than 30 days - about 1,000 points at most.

local PortfolioHistoryModule = {}

local RECENT_BUCKET_SECONDS = 300
local OLDER_BUCKET_SECONDS = 3600
local RECENT_WINDOW_SECONDS = 86400
local RETENTION_SECONDS = 30 * 86400
local MAX_CHART_POINTS = 150

-- The Portfolio tab's range pills
PortfolioHistoryModule.RANGES = {
	["24h"] = 86400,
	["7d"] = 7 * 86400,
	["30d"] = 30 * 86400,
}

local function getBucketKey(time, now)
	local bucketSeconds = (now - time) <= RECENT_WINDOW_SECONDS and RECENT_BUCKET_SECONDS or OLDER_BUCKET_SECONDS

	return bucketSeconds .. ":" .. (time // bucketSeconds)
end

-- Returns a new history with `value` appended at `now`, keeping only the
-- latest point in each bucket and dropping points past retention.
function PortfolioHistoryModule.record(history, value, now)
	local lastPoint = history[#history]

	-- Server clocks can disagree by a few seconds when a player changes
	-- servers; never let a point land before the one already saved
	local time = lastPoint and math.max(now, lastPoint[1]) or now
	local points = table.clone(history)

	table.insert(points, { time, math.round(value * 100) / 100 })

	local compacted = {}
	local lastKey = nil

	for _, point in ipairs(points) do
		if time - point[1] <= RETENTION_SECONDS then
			local key = getBucketKey(point[1], time)

			if key == lastKey then
				compacted[#compacted] = point
			else
				table.insert(compacted, point)
				lastKey = key
			end
		end
	end

	return compacted
end

-- Keeps the first point plus the last point in each of maxPoints equal time
-- slices, so the shape survives while the point count stays drawable.
local function downsample(points, maxPoints)
	local count = #points

	if count <= maxPoints then
		return points
	end

	local firstTime = points[1][1]
	local sliceSeconds = (points[count][1] - firstTime) / maxPoints

	if sliceSeconds <= 0 then
		return { points[count] }
	end

	local function getSlice(point)
		return math.floor((point[1] - firstTime) / sliceSeconds)
	end

	local result = { points[1] }

	for i = 2, count do
		if i == count or getSlice(points[i + 1]) ~= getSlice(points[i]) then
			table.insert(result, points[i])
		end
	end

	return result
end

-- The points one range's chart draws: everything inside the range, led by
-- the value the range started from (the last point before it, moved to the
-- range's start so a long absence doesn't stretch the time axis).
function PortfolioHistoryModule.getRange(history, rangeSeconds, now)
	local startTime = now - rangeSeconds
	local points = {}
	local baseline = nil

	for _, point in ipairs(history) do
		if point[1] < startTime then
			baseline = point
		else
			table.insert(points, point)
		end
	end

	if baseline then
		table.insert(points, 1, { startTime, baseline[2] })
	end

	return downsample(points, MAX_CHART_POINTS)
end

return PortfolioHistoryModule
