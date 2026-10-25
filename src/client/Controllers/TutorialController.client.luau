-- TutorialController.client.luau
--
-- The "Getting started" checklist for new players (Phase 1 tutorial): a
-- card in the bottom-right corner on every tab, listing the steps in
-- ReplicatedStorage.Config.Progression.TUTORIAL with what's done ticked.
-- The server tracks progress and awards the completion XP; this reports
-- the two steps only the client sees (looking up a stock, opening the
-- Portfolio tab) and shows the rest from the "TutorialProgress" attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local Progression = require(ReplicatedStorage.Config.Progression)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local CompleteTutorialStepEvent = ReplicatedStorage:WaitForChild("EventsFolder")
	:WaitForChild("CompleteTutorialStepEvent")

local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local MainBackground = TerminalGui:WaitForChild("MainBackground")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")
local TradeScreen = ScreenContainer:WaitForChild("TradeScreen")
local TradeTickerLabel = TradeScreen:WaitForChild("HeaderRow"):WaitForChild("TickerLabel")
local PortfolioScreen = ScreenContainer:WaitForChild("PortfolioScreen")

-- Layout Constants
local CARD_WIDTH = 280
local EDGE_GAP = 12 -- from the screen edges, inside the screen container
local PADDING = 12
local TITLE_HEIGHT = 22
local STEP_HEIGHT = 24
local CHECK_SIZE = 14
local FOOTER_HEIGHT = 18
local DONE_SECONDS = 6 -- how long the finished card stays up

local completionXP = Progression.MILESTONES.TutorialComplete

-- State
local isCollapsed = false
local reportedSteps = {} -- [stepId] = true once sent, so each is reported once

local makeLabel = UIKit.makeLabel

-- Card
local Card = UIKit.makePanel("TutorialCard", ScreenContainer)
Card.AnchorPoint = Vector2.new(1, 1)
Card.Position = UDim2.new(1, -EDGE_GAP, 1, -EDGE_GAP)
Card.Size = UDim2.fromOffset(CARD_WIDTH, 0)
Card.AutomaticSize = Enum.AutomaticSize.Y
Card.ZIndex = 8
Card.Visible = false

local CardPadding = Instance.new("UIPadding")
CardPadding.PaddingTop = UDim.new(0, PADDING)
CardPadding.PaddingBottom = UDim.new(0, PADDING)
CardPadding.PaddingLeft = UDim.new(0, PADDING)
CardPadding.PaddingRight = UDim.new(0, PADDING)
CardPadding.Parent = Card

local CardLayout = Instance.new("UIListLayout")
CardLayout.SortOrder = Enum.SortOrder.LayoutOrder
CardLayout.Padding = UDim.new(0, 4)
CardLayout.Parent = Card

-- Header: title, progress count and a collapse toggle
local Header = Instance.new("TextButton")
Header.Name = "Header"
Header.LayoutOrder = 0
Header.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
Header.BackgroundTransparency = 1
Header.BorderSizePixel = 0
Header.AutoButtonColor = false
Header.Text = ""
Header.ZIndex = 8
Header.Parent = Card

local Title = makeLabel("Title", Header, Theme.Fonts.UISemibold, Theme.TextSize.Title, Theme.Colors.Text)
Title.Size = UDim2.new(1, -60, 1, 0)
Title.Text = "Getting started"
Title.ZIndex = 8

local Count = makeLabel("Count", Header, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.TextMuted)
Count.AnchorPoint = Vector2.new(1, 0)
Count.Position = UDim2.new(1, -20, 0, 0)
Count.Size = UDim2.new(0, 40, 1, 0)
Count.TextXAlignment = Enum.TextXAlignment.Right
Count.ZIndex = 8

local Chevron = makeLabel("Chevron", Header, Theme.Fonts.UIBold, Theme.TextSize.Body, Theme.Colors.TextMuted)
Chevron.AnchorPoint = Vector2.new(1, 0)
Chevron.Position = UDim2.fromScale(1, 0)
Chevron.Size = UDim2.new(0, 16, 1, 0)
Chevron.TextXAlignment = Enum.TextXAlignment.Right
Chevron.ZIndex = 8

local stepRows = {} -- [stepId] = { row, check, label }

for index, step in ipairs(Progression.TUTORIAL) do
	local row = UIKit.makeFrame("Step_" .. step.id, Card)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, 0, 0, STEP_HEIGHT)
	row.ZIndex = 8

	local check = UIKit.makeDot("Check", row, CHECK_SIZE, Theme.Colors.Raised)
	check.Position = UDim2.new(0, CHECK_SIZE / 2, 0.5, 0)
	check.ZIndex = 8

	local checkStroke = UIKit.addStroke(check)

	local tick = makeLabel("Tick", check, Theme.Fonts.UIBold, Theme.TextSize.Caption, Theme.Colors.Background)
	tick.Size = UDim2.fromScale(1, 1)
	tick.TextXAlignment = Enum.TextXAlignment.Center
	tick.TextTruncate = Enum.TextTruncate.None
	tick.Text = "✓"
	tick.ZIndex = 9

	local label = makeLabel("Text", row, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.Text)
	label.Position = UDim2.fromOffset(CHECK_SIZE + 10, 0)
	label.Size = UDim2.new(1, -(CHECK_SIZE + 10), 1, 0)
	label.Text = step.text
	label.ZIndex = 8

	stepRows[step.id] = { row = row, check = check, checkStroke = checkStroke, tick = tick, label = label }
end

local Footer = makeLabel("Footer", Card, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
Footer.LayoutOrder = #Progression.TUTORIAL + 1
Footer.Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT)
Footer.ZIndex = 8

-- Rendering
local function getDoneSteps()
	local done = {}

	for stepId in string.gmatch(Player:GetAttribute("TutorialProgress") or "", "[^,]+") do
		done[stepId] = true
	end

	return done
end

local function render()
	local progress = Player:GetAttribute("TutorialProgress")

	-- Nothing until the server has published progress; gone once claimed
	if progress == nil or Player:GetAttribute("TutorialComplete") then
		return
	end

	local done = getDoneSteps()
	local doneCount = 0

	for _, step in ipairs(Progression.TUTORIAL) do
		local isDone = done[step.id] == true
		local row = stepRows[step.id]

		doneCount += isDone and 1 or 0
		row.row.Visible = not isCollapsed
		row.check.BackgroundColor3 = isDone and Theme.Colors.Up or Theme.Colors.Raised
		row.checkStroke.Color = isDone and Theme.Colors.Up or Theme.Colors.Border
		row.tick.Visible = isDone
		row.label.TextColor3 = isDone and Theme.Colors.TextMuted or Theme.Colors.Text
	end

	Count.Text = string.format("%d/%d", doneCount, #Progression.TUTORIAL)
	Chevron.Text = isCollapsed and "▲" or "▼"
	Footer.Visible = not isCollapsed
	Footer.Text = string.format("Finish them all for +%d XP", completionXP)
	Card.Visible = true
end

-- The finished checklist stays up briefly so the bonus is seen, then goes
local function onComplete()
	if not Card.Visible then
		return
	end

	for _, rowParts in pairs(stepRows) do
		rowParts.check.BackgroundColor3 = Theme.Colors.Up
		rowParts.checkStroke.Color = Theme.Colors.Up
		rowParts.tick.Visible = true
		rowParts.label.TextColor3 = Theme.Colors.TextMuted
	end

	Count.Text = string.format("%d/%d", #Progression.TUTORIAL, #Progression.TUTORIAL)
	Footer.Visible = true
	Footer.TextColor3 = Theme.Colors.Up
	Footer.Text = string.format("All done! +%d XP", completionXP)

	task.delay(DONE_SECONDS, function()
		Card.Visible = false
	end)
end

-- Reporting
local function report(stepId)
	if reportedSteps[stepId] or getDoneSteps()[stepId] or Player:GetAttribute("TutorialComplete") then
		return
	end

	reportedSteps[stepId] = true
	task.spawn(CompleteTutorialStepEvent.InvokeServer, CompleteTutorialStepEvent, stepId)
end

-- Connections
Header.MouseButton1Click:Connect(function()
	isCollapsed = not isCollapsed
	render()
end)

Player:GetAttributeChangedSignal("TutorialProgress"):Connect(render)

Player:GetAttributeChangedSignal("TutorialComplete"):Connect(function()
	if Player:GetAttribute("TutorialComplete") then
		onComplete()
	end
end)

-- A ticker shows in the Trade header once it has loaded
TradeTickerLabel:GetPropertyChangedSignal("Text"):Connect(function()
	if TradeTickerLabel.Text ~= "" then
		report("ViewedTicker")
	end
end)

PortfolioScreen:GetPropertyChangedSignal("Visible"):Connect(function()
	if PortfolioScreen.Visible then
		report("ViewedPortfolio")
	end
end)

render()
