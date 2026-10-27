-- ChallengeService.luau
--
-- Daily challenges and the streak they keep (Config/Challenges; the rules
-- are in Modules/ChallengeModule), saved in playerData.Daily. Challenges
-- advance on filled orders (OrderEvents), published theses and feed
-- reactions (ThesisService and FeedService call record); each one finished
-- earns XP through ProgressionService, and the day's first also extends the
-- streak, which earns a bonus.
--
-- It also tells the player's client about each moment worth celebrating,
-- through the RewardEvent RemoteEvent: { kind = "fill" } after every one of
-- their fills, "challenge" and "streak" as they're earned, "milestone" for
-- ProgressionService's milestones, and "daily" with the day's challenges
-- whenever they change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Challenges = require(ReplicatedStorage.Config.Challenges)
local Instruments = require(ReplicatedStorage.Config.Instruments)
local Progression = require(ReplicatedStorage.Config.Progression)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local ProgressionService = require(ServerScriptService.Services.ProgressionService)
local OrderEvents = require(ServerScriptService.Services.OrderEvents)
local RemoteGuard = require(ServerScriptService.Modules.RemoteGuard)
local ChallengeModule = require(ServerScriptService.Modules.ChallengeModule)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local RewardEvent = EventsFolder:WaitForChild("RewardEvent")
local GetDailyEvent = EventsFolder:WaitForChild("GetDailyEvent")

local DAY = 86400
local ROLLOVER_CHECK_SECONDS = 60 -- new challenges reach online players within a minute of midnight UTC
local STOCK_MARKET_CHECK_HOUR = 15 -- UTC: mid-morning in New York, inside any session that day

local ChallengeService = {}

local function push(player, moment)
	if player.Parent == Players then
		RewardEvent:FireClient(player, moment)
	end
end

-- Whether NYSE opens at all on a UTC day; a stock-buying challenge on a
-- weekend or holiday couldn't be done
local function stockMarketOpens(day)
	return not MarketHoursModule.isMarketClosed(day * DAY + STOCK_MARKET_CHECK_HOUR * 3600)
end

local function isEligible(player, challenge, day)
	if challenge.feature and not ProgressionService.hasFeature(player, challenge.feature) then
		return false
	elseif challenge.stockMarket and not stockMarketOpens(day) then
		return false
	end

	return true
end

-- The day's challenges and the streak, as the client shows them
local function describe(daily, day)
	local challenges = {}

	for _, entry in ipairs(daily.Challenges) do
		local challenge = Challenges.get(entry.id)

		if challenge then
			table.insert(challenges, {
				id = entry.id,
				text = challenge.text,
				progress = entry.progress,
				goal = challenge.goal,
				done = entry.done,
				xp = Challenges.XP,
			})
		end
	end

	return {
		challenges = challenges,
		streak = ChallengeModule.currentStreak(daily, day),
		bestStreak = daily.BestStreak,
		extendedToday = daily.StreakDay == day,
		resetsAt = ChallengeModule.resetsAt(day),
	}
end

local function pushDaily(player, data, day)
	push(player, { kind = "daily", daily = describe(data.Daily, day) })
end

-- New challenges once the UTC day changes. Returns whether they changed.
local function refreshDay(player, data, day)
	local daily = data.Daily

	if daily.Day == day then
		return false
	end

	daily.Day = day
	daily.Challenges = ChallengeModule.pick(Challenges.POOL, Challenges.PER_DAY, day, player.UserId, function(challenge)
		return isEligible(player, challenge, day)
	end)

	return true
end

-- Moves the player's challenges along for `event` (see
-- ChallengeModule.matches), awarding what that earns
function ChallengeService.record(player, event)
	local data = PlayerDataService.get(player)

	if not data then
		return
	end

	local day = ChallengeModule.dayOf(os.time())
	local changed = refreshDay(player, data, day)
	local finished = 0
	local xp = 0

	for _, entry in ipairs(data.Daily.Challenges) do
		local challenge = Challenges.get(entry.id)

		if challenge then
			local progressed, done = ChallengeModule.advance(entry, challenge, event)

			changed = changed or progressed

			if done then
				finished += 1
				xp += Challenges.XP
				push(player, { kind = "challenge", text = challenge.text, xp = Challenges.XP })
			end
		end
	end

	if finished > 0 then
		local streak = ChallengeModule.extendStreak(data.Daily, day)

		if streak then
			local bonus = Challenges.getStreakXP(streak)

			xp += bonus
			push(player, { kind = "streak", days = streak, xp = bonus })
		end
	end

	if changed then
		pushDaily(player, data, day)
	end

	ProgressionService.addXP(player, xp)
end

local function onFill(player, realizedPL: number?, _now, fill)
	-- An option settled at expiry isn't a trade the player made
	if not fill or fill.settlement then
		return
	end

	push(player, {
		kind = "fill",
		ticker = fill.ticker,
		contract = fill.contract,
		side = fill.side,
		quantity = fill.quantity,
		price = fill.price,
		realizedPL = realizedPL,
	})

	ChallengeService.record(player, {
		kind = "fill",
		key = fill.ticker,
		side = fill.side,
		assetClass = Instruments.getAssetClass(fill.ticker),
		profit = realizedPL ~= nil and realizedPL > 0,
		option = fill.contract ~= nil,
	})
end

-- Must run before PlayerDataService.start so no PlayerLoaded is missed
function ChallengeService.start()
	PlayerDataService.PlayerLoaded:Connect(function(player)
		local data = PlayerDataService.get(player)

		if data then
			local day = ChallengeModule.dayOf(os.time())

			refreshDay(player, data, day)
			pushDaily(player, data, day)
		end
	end)

	OrderEvents.Filled:Connect(onFill)

	ProgressionService.Achieved:Connect(function(player, kind, value)
		if kind == "Milestone" then
			push(player, { kind = "milestone", name = value, xp = Progression.MILESTONES[value] })
		end
	end)

	RemoteGuard.handle(GetDailyEvent, RemoteGuard.LIMITS.Read, function(player)
		local data = PlayerDataService.get(player)

		if not data then
			return nil
		end

		local day = ChallengeModule.dayOf(os.time())

		refreshDay(player, data, day)

		return describe(data.Daily, day)
	end)

	task.spawn(function()
		while true do
			task.wait(ROLLOVER_CHECK_SECONDS)

			local day = ChallengeModule.dayOf(os.time())

			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerDataService.get(player)

				if data and refreshDay(player, data, day) then
					pushDaily(player, data, day)
				end
			end
		end
	end)
end

return ChallengeService
