-- ProgressionService.luau
--
-- Awards XP and enforces level unlocks (GDD §8) from the rules in
-- ReplicatedStorage.Config.Progression. A player's XP is saved in their
-- profile; their XP and level are mirrored to the "XP" and "Level"
-- attributes so the client can show progress and locks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Progression = require(ReplicatedStorage.Config.Progression)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local OrderEvents = require(ServerScriptService.Services.OrderEvents)

local ProgressionService = {}

local function publish(player, progression)
	player:SetAttribute("XP", progression.XP)
	player:SetAttribute("Level", Progression.getLevel(progression.XP))
end

local function countKeys(dictionary)
	local count = 0

	for _ in pairs(dictionary) do
		count += 1
	end

	return count
end

-- XP for a milestone the first time it's reached, 0 after that
local function claimMilestone(progression, milestone)
	if progression.Milestones[milestone] then
		return 0
	end

	progression.Milestones[milestone] = true

	return Progression.MILESTONES[milestone]
end

function ProgressionService.getLevel(player): number
	local data = PlayerDataService.get(player)

	return data and Progression.getLevel(data.Progression.XP) or 1
end

function ProgressionService.hasFeature(player, feature: string): boolean
	return Progression.isUnlocked(ProgressionService.getLevel(player), feature)
end

function ProgressionService.addXP(player, amount: number)
	local data = PlayerDataService.get(player)

	if not data or amount <= 0 then
		return
	end

	data.Progression.XP += amount
	publish(player, data.Progression)
end

-- After every filled order. The first fill of each UTC day earns a bonus;
-- each fill earns a little more up to a daily cap.
local function onFill(player, realizedPL: number?, now: number)
	local data = PlayerDataService.get(player)

	if not data then
		return
	end

	local progression = data.Progression
	local today = os.date("!%Y-%m-%d", now)
	local xp = 0

	if progression.XPDay ~= today then
		progression.XPDay = today
		progression.FillXPToday = 0
		xp += Progression.XP.FIRST_TRADE_OF_DAY
	end

	local fillXP = math.min(Progression.XP.PER_FILL, Progression.XP.MAX_FILL_XP_PER_DAY - progression.FillXPToday)

	if fillXP > 0 then
		progression.FillXPToday += fillXP
		xp += fillXP
	end

	xp += claimMilestone(progression, "FirstTrade")

	if realizedPL and realizedPL > 0 then
		xp += claimMilestone(progression, "FirstProfitableSale")
	end

	local holdings = countKeys(data.Portfolio.Shares) + countKeys(data.Portfolio.Options)

	if holdings >= Progression.DIVERSIFIED_HOLDINGS then
		xp += claimMilestone(progression, "Diversified")
	end

	ProgressionService.addXP(player, xp)
end

-- Must run before PlayerDataService.start so no PlayerLoaded is missed
function ProgressionService.start()
	PlayerDataService.PlayerLoaded:Connect(function(player)
		local data = PlayerDataService.get(player)

		if data then
			publish(player, data.Progression)
		end
	end)

	OrderEvents.Filled:Connect(onFill)
end

return ProgressionService
