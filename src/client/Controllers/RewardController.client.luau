-- RewardController.client.luau
--
-- Makes progress feel like a game. Every fill pops up at the bottom of the
-- screen with a sound (a profitable sale with confetti too), and so do
-- finished daily challenges, streak days and milestones, all pushed by
-- ChallengeService through RewardEvent. A new level gets a screen of its
-- own: what the player reached and what it unlocked.
--
-- Its own ScreenGui sits above the terminal and below the start screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local Sounds = require(ReplicatedStorage.UI.Sounds)
local Confetti = require(ReplicatedStorage.UI.Confetti)
local Progression = require(ReplicatedStorage.Config.Progression)
local RobloxMarket = require(ReplicatedStorage.Config.RobloxMarket)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local RewardEvent = ReplicatedStorage:WaitForChild("EventsFolder"):WaitForChild("RewardEvent")

-- Layout Constants
local POP_WIDTH = 340
local POP_HEIGHT = 54
local POP_GAP = 8
local POPS_BOTTOM_GAP = 40 -- clear of the status bar
local MAX_POPS = 4
local LEVEL_CARD_WIDTH = 360

-- Timing
local POP_SECONDS = 3.5
local LEVEL_SECONDS = 10
local POP_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local OVERLAY_FADE = TweenInfo.new(0.25)

-- Said to the player, unlike the feed's third-person Social.FEED_MILESTONES
local MILESTONE_TEXT = {
	FirstTrade = "Your first trade!",
	FirstProfitableSale = "Your first profitable sale!",
	Diversified = "Diversified: 3 positions at once",
	TutorialComplete = "Getting started: all done",
}

local makeLabel = UIKit.makeLabel

local RewardGui = Instance.new("ScreenGui")
RewardGui.Name = "RewardGui"
RewardGui.ScreenInsets = Enum.ScreenInsets.None
RewardGui.ResetOnSpawn = false
RewardGui.DisplayOrder = 50 -- over the terminal, under the start screen
RewardGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
RewardGui.Parent = PlayerGui

-- Pops stack up from the bottom center, newest at the bottom
local Pops = UIKit.makeFrame("Pops", RewardGui)
Pops.AnchorPoint = Vector2.new(0.5, 1)
Pops.Position = UDim2.new(0.5, 0, 1, -POPS_BOTTOM_GAP)
Pops.Size = UDim2.fromOffset(POP_WIDTH, (POP_HEIGHT + POP_GAP) * MAX_POPS)

do
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, POP_GAP)
	layout.Parent = Pops
end

local popCount = 0

local function removePop(pop)
	if not pop.Parent then
		return
	end

	local fade = TweenService:Create(pop, POP_OUT, { GroupTransparency = 1 })

	fade.Completed:Connect(function()
		pop:Destroy()
	end)

	fade:Play()
end

-- A card with an accent edge, a title, a line under it and, on the right,
-- what it earned. Returns the card.
local function showPop(title, body, accent, reward, rewardColor)
	popCount += 1

	-- Oldest out first when the stack is full
	local pops = {}

	for _, child in ipairs(Pops:GetChildren()) do
		if child:IsA("CanvasGroup") then
			table.insert(pops, child)
		end
	end

	table.sort(pops, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)

	for index = 1, #pops - MAX_POPS + 1 do
		pops[index]:Destroy()
	end

	-- A CanvasGroup so the whole card fades as one
	local pop = Instance.new("CanvasGroup")
	pop.Name = "Pop"
	pop.LayoutOrder = popCount
	pop.Size = UDim2.new(1, 0, 0, POP_HEIGHT)
	pop.BackgroundTransparency = 1
	pop.GroupTransparency = 1
	pop.Parent = Pops

	local card = UIKit.makePanel("Card", pop)
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Theme.Colors.Raised

	local edge = UIKit.makeFrame("Edge", card)
	edge.Size = UDim2.new(0, 4, 1, 0)
	edge.BackgroundTransparency = 0
	edge.BackgroundColor3 = accent
	UIKit.addCorner(edge)

	local rewardWidth = reward and 90 or 0

	local titleLabel = makeLabel("Title", card, Theme.Fonts.UIBold, Theme.TextSize.Body, Theme.Colors.Text)
	titleLabel.Position = UDim2.fromOffset(16, 9)
	titleLabel.Size = UDim2.new(1, -(16 + rewardWidth + 12), 0, 18)
	titleLabel.Text = title

	local bodyLabel = makeLabel("Body", card, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	bodyLabel.Position = UDim2.fromOffset(16, 29)
	bodyLabel.Size = UDim2.new(1, -(16 + rewardWidth + 12), 0, 16)
	bodyLabel.RichText = true
	bodyLabel.Text = body

	if reward then
		local rewardLabel = makeLabel("Reward", card, Theme.Fonts.MonoBold, Theme.TextSize.Body, rewardColor)
		rewardLabel.AnchorPoint = Vector2.new(1, 0.5)
		rewardLabel.Position = UDim2.new(1, -12, 0.5, 0)
		rewardLabel.Size = UDim2.fromOffset(rewardWidth, 20)
		rewardLabel.TextXAlignment = Enum.TextXAlignment.Right
		rewardLabel.Text = reward
	end

	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = pop

	TweenService:Create(scale, POP_IN, { Scale = 1 }):Play()
	TweenService:Create(pop, POP_IN, { GroupTransparency = 0 }):Play()

	task.delay(POP_SECONDS, removePop, pop)

	return pop
end

-- Confetti out of a pop, once it has settled into place
local function burstFrom(pop, pieces)
	task.defer(function()
		local center = pop.AbsolutePosition + pop.AbsoluteSize / 2 - RewardGui.AbsolutePosition

		Confetti.burst(RewardGui, UDim2.fromOffset(center.X, center.Y), pieces)
	end)
end

-- A Roblox game by its name, anything else by its ticker
local function describeTicker(ticker)
	local experience = RobloxMarket.getExperience(ticker)

	return experience and experience.name or ticker
end

local function onFill(fill)
	local name = describeTicker(fill.ticker)
	local what = fill.contract
			and string.format("%d %s option%s", fill.quantity, name, fill.quantity == 1 and "" or "s")
		or string.format("%s %s", NumberModule.formatShares(fill.quantity), name)
	local pl = fill.realizedPL

	if fill.side == "Buy" then
		Sounds.play("Fill")
		showPop("Bought " .. what, "at " .. NumberModule.format(fill.price), Theme.Colors.Up)

		return
	end

	if pl and pl > 0 then
		Sounds.play("Profit")
		burstFrom(
			showPop(
				"Sold " .. what,
				"Profit locked in",
				Theme.Colors.Up,
				"+" .. NumberModule.format(pl),
				Theme.Colors.Up
			)
		)
	elseif pl and pl < 0 then
		Sounds.play("Fill")
		showPop("Sold " .. what, "A loss this time", Theme.Colors.Down, NumberModule.format(pl), Theme.Colors.Down)
	else
		Sounds.play("Fill")
		showPop("Sold " .. what, "at " .. NumberModule.format(fill.price), Theme.Colors.TextMuted)
	end
end

local function formatXP(xp)
	return string.format("+%d XP", xp)
end

RewardEvent.OnClientEvent:Connect(function(moment)
	if moment.kind == "fill" then
		onFill(moment)
	elseif moment.kind == "challenge" then
		Sounds.play("Challenge")
		burstFrom(
			showPop("Challenge complete", moment.text, Theme.Colors.Accent, formatXP(moment.xp), Theme.Colors.Accent),
			18
		)
	elseif moment.kind == "streak" then
		showPop(
			string.format("🔥 %d-day streak", moment.days),
			"One challenge a day keeps it going",
			Theme.Colors.Accent,
			formatXP(moment.xp),
			Theme.Colors.Accent
		)
	elseif moment.kind == "milestone" then
		Sounds.play("Challenge")
		showPop(
			"Milestone",
			MILESTONE_TEXT[moment.name] or moment.name,
			Theme.Colors.Accent,
			moment.xp and formatXP(moment.xp),
			Theme.Colors.Accent
		)
	end
end)

-- Level-up screen: the level, its name and what it unlocked, over a dimmed
-- terminal, until the player closes it (or it times out)
local Overlay = UIKit.makeFrame("LevelUp", RewardGui)
Overlay.Size = UDim2.fromScale(1, 1)
Overlay.BackgroundTransparency = 1
Overlay.BackgroundColor3 = Theme.Colors.Background
Overlay.Active = true -- while it shows, clicks stop here
Overlay.Visible = false
Overlay.ZIndex = 10

local LevelCard = UIKit.makePanel("Card", Overlay)
LevelCard.AnchorPoint = Vector2.new(0.5, 0.5)
LevelCard.Position = UDim2.fromScale(0.5, 0.5)
LevelCard.Size = UDim2.fromOffset(LEVEL_CARD_WIDTH, 0)
LevelCard.AutomaticSize = Enum.AutomaticSize.Y
LevelCard.ZIndex = 11

local LevelCardScale = Instance.new("UIScale")
LevelCardScale.Parent = LevelCard

do
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 24)
	padding.PaddingBottom = UDim.new(0, 20)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = LevelCard

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = LevelCard
end

local function makeCenteredLabel(name, layoutOrder, font, textSize, color, height)
	local label = makeLabel(name, LevelCard, font, textSize, color)
	label.LayoutOrder = layoutOrder
	label.Size = UDim2.new(1, 0, 0, height)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 12

	return label
end

local LevelCaption =
	makeCenteredLabel("Caption", 1, Theme.Fonts.UIBold, Theme.TextSize.Caption, Theme.Colors.Accent, 16)
LevelCaption.Text = "LEVEL UP"

local LevelNumber =
	makeCenteredLabel("Level", 2, Theme.Fonts.UIBold, Theme.TextSize.Hero, Theme.Colors.Text, Theme.TextSize.Hero + 6)
local LevelName = makeCenteredLabel("Name", 3, Theme.Fonts.UISemibold, Theme.TextSize.Title, Theme.Colors.TextMuted, 20)

local LevelUnlocks = makeCenteredLabel("Unlocks", 4, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.Text, 0)
LevelUnlocks.AutomaticSize = Enum.AutomaticSize.Y
LevelUnlocks.TextWrapped = true
LevelUnlocks.TextTruncate = Enum.TextTruncate.None
LevelUnlocks.RichText = true

local LevelSpacer = UIKit.makeFrame("Spacer", LevelCard)
LevelSpacer.LayoutOrder = 5
LevelSpacer.Size = UDim2.new(1, 0, 0, 8)

local LevelButton = Instance.new("TextButton")
LevelButton.Name = "Continue"
LevelButton.LayoutOrder = 6
LevelButton.Size = UDim2.new(1, 0, 0, 40)
LevelButton.AutoButtonColor = true
LevelButton.BorderSizePixel = 0
LevelButton.BackgroundColor3 = Theme.Colors.Accent
LevelButton.FontFace = Theme.Fonts.UIBold
LevelButton.TextSize = Theme.TextSize.Title
LevelButton.TextColor3 = Theme.Colors.Background -- dark on Accent reads better
LevelButton.Text = "Nice!"
LevelButton.ZIndex = 12
LevelButton.Parent = LevelCard
UIKit.addCorner(LevelButton)

local levelVersion = 0

local function hideLevelUp()
	levelVersion += 1

	local fade = TweenService:Create(Overlay, OVERLAY_FADE, { BackgroundTransparency = 1 })

	fade.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			Overlay.Visible = false
		end
	end)

	LevelCard.Visible = false
	fade:Play()
end

local function capitalize(text)
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

local function showLevelUp(level)
	levelVersion += 1

	local version = levelVersion
	local unlocks = Progression.getUnlocksAt(level)
	local nextLevel = Progression.LEVELS[level + 1]

	LevelNumber.Text = "Level " .. level
	LevelName.Text = Progression.LEVELS[level].name

	if #unlocks > 0 then
		for index, unlock in ipairs(unlocks) do
			unlocks[index] = "• " .. capitalize(unlock)
		end

		LevelUnlocks.Text = string.format(
			'<font color="#%s">Unlocked</font>\n%s',
			Theme.Colors.TextMuted:ToHex(),
			table.concat(unlocks, "\n")
		)
	else
		LevelUnlocks.Text = nextLevel and string.format("Next: Level %d · %s", level + 1, nextLevel.name)
			or "The top level. Nothing left to unlock."
	end

	Overlay.Visible = true
	LevelCard.Visible = true
	Overlay.BackgroundTransparency = 1
	LevelCardScale.Scale = 0.7
	TweenService:Create(Overlay, OVERLAY_FADE, { BackgroundTransparency = 0.35 }):Play()
	TweenService:Create(LevelCardScale, POP_IN, { Scale = 1 }):Play()
	Sounds.play("LevelUp")
	Confetti.burst(Overlay, UDim2.fromScale(0.5, 0.5), 60, 13)

	task.delay(LEVEL_SECONDS, function()
		if version == levelVersion then
			hideLevelUp()
		end
	end)
end

LevelButton.MouseButton1Click:Connect(hideLevelUp)

local shownLevel = Player:GetAttribute("Level") -- nil until the server first sets it, so loading in isn't announced

Player:GetAttributeChangedSignal("Level"):Connect(function()
	local level = Player:GetAttribute("Level")

	if level and shownLevel and level > shownLevel then
		showLevelUp(level)
	end

	shownLevel = level
end)
