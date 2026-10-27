-- DailyController.client.luau
--
-- Daily challenges (ChallengeService). The nav bar pill ShellController
-- builds shows the streak and how many of today's challenges are done
-- ("🔥 3 · 1/3"); it opens a panel under it listing them with their
-- progress and XP, the streak, and when new ones come. Updates arrive
-- through RewardEvent ("daily"); the celebrations are RewardController's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local UIKit = require(ReplicatedStorage.UI.UIKit)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetDailyEvent = EventsFolder:WaitForChild("GetDailyEvent")
local RewardEvent = EventsFolder:WaitForChild("RewardEvent")

-- References
local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local MainBackground = TerminalGui:WaitForChild("MainBackground")
local DailyButton = MainBackground:WaitForChild("TopBar"):WaitForChild("DailyButton")

-- Layout Constants
local PANEL_WIDTH = 340
local PADDING = 12
local TITLE_HEIGHT = 20
local ROW_HEIGHT = 46
local CHECK_SIZE = 18
local BAR_HEIGHT = 4
local EDGE_GAP = 8
local Z_INDEX = 20 -- TerminalGui renders by global ZIndex, so the panel sits above every screen

local STARTUP_RETRIES = 10
local RETRY_DELAY = 1.1

-- State
local isOpen = false
local daily = nil -- the last state from ChallengeService

local makeLabel = UIKit.makeLabel

local function raise(root)
	root.ZIndex = Z_INDEX

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = Z_INDEX
		end
	end
end

-- Panel
local Panel = UIKit.makePanel("DailyPanel", MainBackground)
Panel.AnchorPoint = Vector2.new(1, 0)
Panel.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
Panel.AutomaticSize = Enum.AutomaticSize.Y
Panel.Visible = false

do
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PADDING)
	padding.PaddingBottom = UDim.new(0, PADDING)
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, PADDING)
	padding.Parent = Panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = Panel
end

local Title = makeLabel("Title", Panel, Theme.Fonts.UIBold, Theme.TextSize.Title, Theme.Colors.Text)
Title.LayoutOrder = 1
Title.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
Title.Text = "Daily challenges"

local StreakLabel = makeLabel("Streak", Panel, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
StreakLabel.LayoutOrder = 2
StreakLabel.Size = UDim2.new(1, 0, 0, 16)
StreakLabel.RichText = true

local List = UIKit.makeFrame("List", Panel)
List.LayoutOrder = 3
List.Size = UDim2.fromScale(1, 0)
List.AutomaticSize = Enum.AutomaticSize.Y

do
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = List
end

local Footer = makeLabel("Footer", Panel, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
Footer.LayoutOrder = 4
Footer.Size = UDim2.new(1, 0, 0, 16)
Footer.TextWrapped = true

local function updatePill()
	if not daily then
		DailyButton.Text = "🎯"

		return
	end

	local done = 0

	for _, challenge in ipairs(daily.challenges) do
		if challenge.done then
			done += 1
		end
	end

	local count = done == #daily.challenges and "✓" or string.format("%d/%d", done, #daily.challenges)

	DailyButton.Text = daily.streak > 0 and string.format("🔥 %d · %s", daily.streak, count) or ("🎯 " .. count)
end

local function updateFooter()
	if daily then
		Footer.Text = "New challenges in " .. MarketHoursModule.formatCountdown(daily.resetsAt - os.time())
	end
end

local function createRow(index, challenge)
	local row = UIKit.makeFrame("Challenge_" .. index, List)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)

	local check = makeLabel("Check", row, Theme.Fonts.UIBold, Theme.TextSize.Caption, Theme.Colors.Background)
	check.Position = UDim2.fromOffset(0, 6)
	check.Size = UDim2.fromOffset(CHECK_SIZE, CHECK_SIZE)
	check.BackgroundTransparency = 0
	check.BackgroundColor3 = challenge.done and Theme.Colors.Accent or Theme.Colors.Raised
	check.TextXAlignment = Enum.TextXAlignment.Center
	check.Text = challenge.done and "✓" or ""
	UIKit.addCorner(check, UIKit.CIRCLE)

	if not challenge.done then
		UIKit.addStroke(check)
	end

	local textX = CHECK_SIZE + 10

	local text = makeLabel(
		"Text",
		row,
		Theme.Fonts.UISemibold,
		Theme.TextSize.Body,
		challenge.done and Theme.Colors.TextMuted or Theme.Colors.Text
	)
	text.Position = UDim2.fromOffset(textX, 5)
	text.Size = UDim2.new(1, -(textX + 90), 0, 20)
	text.Text = challenge.text

	local reward = makeLabel("Reward", row, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.Accent)
	reward.AnchorPoint = Vector2.new(1, 0)
	reward.Position = UDim2.new(1, 0, 0, 5)
	reward.Size = UDim2.fromOffset(90, 20)
	reward.TextXAlignment = Enum.TextXAlignment.Right
	reward.Text = string.format("%d/%d · +%d XP", challenge.progress, challenge.goal, challenge.xp)

	local track = UIKit.makeFrame("Bar", row)
	track.Position = UDim2.fromOffset(textX, 31)
	track.Size = UDim2.new(1, -textX, 0, BAR_HEIGHT)
	track.BackgroundTransparency = 0
	track.BackgroundColor3 = Theme.Colors.Raised
	UIKit.addCorner(track, UIKit.CIRCLE)

	local fill = UIKit.makeFrame("Fill", track)
	fill.Size = UDim2.fromScale(math.clamp(challenge.progress / challenge.goal, 0, 1), 1)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = Theme.Colors.Accent
	UIKit.addCorner(fill, UIKit.CIRCLE)
end

local function render()
	for _, child in ipairs(List:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if not daily then
		StreakLabel.Text = "Couldn't load today's challenges. Try again in a moment."
		Footer.Text = ""
		raise(Panel)

		return
	end

	if daily.streak > 0 then
		StreakLabel.Text = string.format(
			'🔥 <font color="#%s"><b>%d-day streak</b></font> · best %d%s',
			Theme.Colors.Text:ToHex(),
			daily.streak,
			daily.bestStreak,
			daily.extendedToday and "" or " · finish one today to keep it"
		)
	else
		StreakLabel.Text = "Finish a challenge to start a streak. Each day in a row earns more XP."
	end

	for index, challenge in ipairs(daily.challenges) do
		createRow(index, challenge)
	end

	updateFooter()
	raise(Panel)
end

local function setDaily(state)
	daily = state
	updatePill()

	if isOpen then
		render()
	end
end

local function invoke()
	local success, result = pcall(GetDailyEvent.InvokeServer, GetDailyEvent)

	if not success then
		warn("[DailyController] GetDailyEvent failed: " .. tostring(result))

		return nil
	end

	return result
end

local function close()
	isOpen = false
	Panel.Visible = false
end

local function open()
	local buttonPosition = DailyButton.AbsolutePosition
	local buttonSize = DailyButton.AbsoluteSize
	local origin = MainBackground.AbsolutePosition

	-- Right-aligned under the pill, but never off the left edge of a narrow screen
	local right = math.max(buttonPosition.X + buttonSize.X - origin.X, PANEL_WIDTH + EDGE_GAP)

	isOpen = true
	Panel.Position = UDim2.fromOffset(right, buttonPosition.Y + buttonSize.Y + 6 - origin.Y)
	Panel.Visible = true
	render()

	-- Fresh progress, in case a push was missed
	task.spawn(function()
		local state = invoke()

		if state then
			setDaily(state)
		end
	end)
end

DailyButton.MouseButton1Click:Connect(function()
	if isOpen then
		close()
	else
		open()
	end
end)

RewardEvent.OnClientEvent:Connect(function(moment)
	if moment.kind == "daily" then
		setDaily(moment.daily)
	end
end)

-- The profile may still be loading, so it's asked again a few times
task.spawn(function()
	for _ = 1, STARTUP_RETRIES do
		local state = invoke()

		if state then
			setDaily(state)

			return
		end

		task.wait(RETRY_DELAY)
	end
end)

task.spawn(function()
	while true do
		task.wait(1)

		if isOpen then
			updateFooter()
		end
	end
end)

updatePill()
