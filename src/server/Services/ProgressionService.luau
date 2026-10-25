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
local RemoteGuard = require(ServerScriptService.Modules.RemoteGuard)

local ProgressionService = {}

local achieved = Instance.new("BindableEvent")

-- Fires (player, kind, value) when a player claims a milestone (kind
-- "Milestone", value its name) or reaches a new level ("Level", the level)
ProgressionService.Achieved = achieved.Event

local function isTutorialStepDone(progression, step)
	if step.milestone then
		return progression.Milestones[step.id] == true
	end

	return progression.TutorialSteps[step.id] == true
end

-- "TutorialProgress" lists the done step ids ("FirstTrade,ViewedTicker")
-- for the client's checklist
local function publish(player, progression)
	local doneSteps = {}

	for _, step in ipairs(Progression.TUTORIAL) do
		if isTutorialStepDone(progression, step) then
			table.insert(doneSteps, step.id)
		end
	end

	player:SetAttribute("XP", progression.XP)
	player:SetAttribute("Level", Progression.getLevel(progression.XP))
	player:SetAttribute("TutorialProgress", table.concat(doneSteps, ","))
	player:SetAttribute("TutorialComplete", progression.Milestones.TutorialComplete == true)
end

local function countKeys(dictionary)
	local count = 0

	for _ in pairs(dictionary) do
		count += 1
	end

	return count
end

-- XP for a milestone the first time it's reached, 0 after that
local function claimMilestone(player, progression, milestone)
	if progression.Milestones[milestone] then
		return 0
	end

	progression.Milestones[milestone] = true
	achieved:Fire(player, "Milestone", milestone)

	return Progression.MILESTONES[milestone]
end

-- The completion bonus, the first time every tutorial step is done
local function claimTutorialIfDone(player, progression)
	for _, step in ipairs(Progression.TUTORIAL) do
		if not isTutorialStepDone(progression, step) then
			return 0
		end
	end

	return claimMilestone(player, progression, "TutorialComplete")
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

	local previousLevel = Progression.getLevel(data.Progression.XP)

	data.Progression.XP += amount
	publish(player, data.Progression)

	local level = Progression.getLevel(data.Progression.XP)

	if level > previousLevel then
		achieved:Fire(player, "Level", level)
	end
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

	xp += claimMilestone(player, progression, "FirstTrade")

	if realizedPL and realizedPL > 0 then
		xp += claimMilestone(player, progression, "FirstProfitableSale")
	end

	local holdings = countKeys(data.Portfolio.Shares) + countKeys(data.Portfolio.Options)

	if holdings >= Progression.DIVERSIFIED_HOLDINGS then
		xp += claimMilestone(player, progression, "Diversified")
	end

	xp += claimTutorialIfDone(player, progression)
	ProgressionService.addXP(player, xp)
end

-- A tutorial step only the client can see happen (opening a screen).
-- Milestone steps can't be reported this way.
local function completeTutorialStep(player, stepId)
	local data = PlayerDataService.get(player)
	local step = type(stepId) == "string" and Progression.getTutorialStep(stepId)

	if not data or not step or step.milestone or data.Progression.TutorialSteps[stepId] then
		return
	end

	data.Progression.TutorialSteps[stepId] = true

	local xp = claimTutorialIfDone(player, data.Progression)

	if xp > 0 then
		ProgressionService.addXP(player, xp)
	else
		publish(player, data.Progression)
	end
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

	-- Small enough not to need its own Core script
	RemoteGuard.handle(
		ReplicatedStorage:WaitForChild("EventsFolder"):WaitForChild("CompleteTutorialStepEvent"),
		RemoteGuard.LIMITS.Rare,
		completeTutorialStep
	)
end

return ProgressionService
