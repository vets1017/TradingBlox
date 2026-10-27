-- StartScreen.client.luau
--
-- The loading screen and start menu. It runs from ReplicatedFirst, so it
-- replaces Roblox's default loading screen before the rest of the game has
-- replicated. While loading it follows the real steps - the game, the
-- terminal UI with its fonts and images, the player's saved account - then
-- becomes a title screen over a drifting candlestick backdrop: the player's
-- level and XP, net worth, the market's hours, and Start trading,
-- Leaderboards and How to play. Starting lifts the screen off the terminal,
-- which has been building underneath the whole time.

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- The look is all the loading screen needs; the other modules are required
-- once the game has loaded
local Theme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Multi"):WaitForChild("Theme"))
local UIKit = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("UIKit"))

local startedAt = os.clock()
local isDismissed = false

-- Layout Constants
local COLUMN_MAX_WIDTH = 420
local COLUMN_GAP = 16
local CARD_PADDING = 16
local LOADING_BAR_HEIGHT = 4
local XP_BAR_HEIGHT = 6
local AVATAR_SIZE = 52
local START_BUTTON_HEIGHT = 46
local BUTTON_HEIGHT = 36
local BUTTON_GAP = 8
local STEP_BADGE_SIZE = 22
local FOOTER_GAP = 16
local MIN_COLUMN_SCALE = 0.6

-- Timing
local MIN_LOADING_SECONDS = 1.5 -- an instant load still reads as a loading screen, not a flash
local TERMINAL_TIMEOUT = 20
local ACCOUNT_TIMEOUT = 30 -- PlayerDataService kicks a player whose data fails to load
local PROGRESS_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local REVEAL_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local LIFT_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

-- Backdrop: a made-up price wandering around 100, drawn as faint candles
-- drifting left with the newest one forming as it comes in at the right.
-- Candle colors are chart data, so they're the Up/Down tokens.
local CANDLE_COUNT = 40 -- across the screen
local CANDLE_SECONDS = 1.5 -- one candle's width of drift
local TICK_SECONDS = 0.1 -- how often the forming candle's price moves
local TICKS_PER_CANDLE = math.round(CANDLE_SECONDS / TICK_SECONDS)
local CANDLE_BODY_WIDTH = 0.6 -- of a candle's slot
local CANDLE_TRANSPARENCY = 0.78
local PRICE_CENTER = 100
local PRICE_SPAN = 24 -- the backdrop shows the center ± this
local PRICE_PULL = 0.02 -- per tick, back toward the center
local PRICE_NOISE = 0.35 -- per tick

local ACCENT_HEX = Theme.Colors.Accent:ToHex()

local makeLabel = UIKit.makeLabel

-- Screen
local StartGui = Instance.new("ScreenGui")
StartGui.Name = "StartGui"
StartGui.ScreenInsets = Enum.ScreenInsets.None -- under Roblox's top bar too, like the terminal
StartGui.ResetOnSpawn = false
StartGui.DisplayOrder = 100 -- over the terminal and its toasts
StartGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Active, so clicks never reach the terminal underneath
local Root = UIKit.makeFrame("Root", StartGui)
Root.Size = UDim2.fromScale(1, 1)
Root.BackgroundTransparency = 0
Root.BackgroundColor3 = Theme.Colors.Background
Root.Active = true

local Backdrop = UIKit.makeFrame("Backdrop", Root)
Backdrop.Size = UDim2.fromScale(1, 1)
Backdrop.ClipsDescendants = true

local Strip = UIKit.makeFrame("Strip", Backdrop)
Strip.Size = UDim2.fromScale(1, 1)

-- Dims the candles behind the content and leaves them clear at the sides
local Shade = UIKit.makeFrame("Shade", Root)
Shade.Size = UDim2.fromScale(1, 1)
Shade.BackgroundTransparency = 0
Shade.BackgroundColor3 = Theme.Colors.Background

do
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = Shade
end

local Column = UIKit.makeFrame("Column", Root)
Column.AnchorPoint = Vector2.new(0.5, 0.5)
Column.Position = UDim2.fromScale(0.5, 0.5)
Column.Size = UDim2.fromScale(0.9, 0)
Column.AutomaticSize = Enum.AutomaticSize.Y

-- Shrinks the column on a short screen so it clears the footer
local ColumnScale = Instance.new("UIScale")
ColumnScale.Parent = Column

do
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(COLUMN_MAX_WIDTH, math.huge)
	constraint.Parent = Column

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, COLUMN_GAP)
	layout.Parent = Column
end

local Wordmark = makeLabel("Wordmark", Column, Theme.Fonts.UIBold, Theme.TextSize.Logo, Theme.Colors.Text)
Wordmark.LayoutOrder = 1
Wordmark.Size = UDim2.new(1, 0, 0, Theme.TextSize.Logo + 8)
Wordmark.TextXAlignment = Enum.TextXAlignment.Center
Wordmark.TextTruncate = Enum.TextTruncate.None
Wordmark.RichText = true
Wordmark.Text = string.format('Trading<font color="#%s">Blox</font>', ACCENT_HEX)

local Tagline = makeLabel("Tagline", Column, Theme.Fonts.UI, Theme.TextSize.Title, Theme.Colors.TextMuted)
Tagline.LayoutOrder = 2
Tagline.Size = UDim2.fromScale(1, 0)
Tagline.AutomaticSize = Enum.AutomaticSize.Y
Tagline.TextXAlignment = Enum.TextXAlignment.Center
Tagline.TextTruncate = Enum.TextTruncate.None
Tagline.TextWrapped = true
Tagline.Text = "Trade real markets and Roblox games with play money."

-- Loading: a bar and the step it's on
local LoadingBlock = UIKit.makeFrame("Loading", Column)
LoadingBlock.LayoutOrder = 3
LoadingBlock.Size = UDim2.new(1, 0, 0, 32)

local function makeBar(name, parent, height)
	local track = UIKit.makeFrame(name, parent)
	track.Size = UDim2.new(1, 0, 0, height)
	track.BackgroundTransparency = 0
	track.BackgroundColor3 = Theme.Colors.Raised
	UIKit.addCorner(track, UIKit.CIRCLE)

	local fill = UIKit.makeFrame("Fill", track)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = Theme.Colors.Accent
	UIKit.addCorner(fill, UIKit.CIRCLE)

	return track, fill
end

local LoadingTrack, LoadingFill = makeBar("Bar", LoadingBlock, LOADING_BAR_HEIGHT)
LoadingTrack.Position = UDim2.fromOffset(0, 4)

local LoadingStatus = makeLabel("Status", LoadingBlock, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
LoadingStatus.Position = UDim2.fromOffset(0, 14)
LoadingStatus.Size = UDim2.new(1, 0, 0, 16)
LoadingStatus.TextXAlignment = Enum.TextXAlignment.Center

local Footer = makeLabel("Footer", Root, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
Footer.AnchorPoint = Vector2.new(0.5, 1)
Footer.Position = UDim2.new(0.5, 0, 1, -FOOTER_GAP)
Footer.Size = UDim2.fromScale(0.9, 0)
Footer.AutomaticSize = Enum.AutomaticSize.Y
Footer.TextXAlignment = Enum.TextXAlignment.Center
Footer.TextTruncate = Enum.TextTruncate.None
Footer.TextWrapped = true
-- GDD §6: simulated numbers are never passed off as real ones
Footer.Text = "Play money only, never real money or financial advice. Stock and crypto prices come from "
	.. "the real market; Roblox game prices are simulated from public player counts."

local function fitColumn()
	local available = Root.AbsoluteSize.Y - (Footer.AbsoluteSize.Y + FOOTER_GAP) * 2
	local height = Column.AbsoluteSize.Y / ColumnScale.Scale

	if height > 0 then
		ColumnScale.Scale = math.clamp(available / height, MIN_COLUMN_SCALE, 1)
	end
end

Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitColumn)
Column:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitColumn)

-- Backdrop candles
local random = Random.new()
local candles = {} -- { open, high, low, close }, oldest first; the last one is forming
local candleViews = {} -- one { body, wick } per slot, CANDLE_COUNT + 1 of them
local price = PRICE_CENTER

local function gaussian()
	return math.sqrt(-2 * math.log(1 - random:NextNumber())) * math.cos(2 * math.pi * random:NextNumber())
end

-- One tick of an Ornstein-Uhlenbeck walk, kept on screen
local function stepPrice()
	price += PRICE_PULL * (PRICE_CENTER - price) + PRICE_NOISE * gaussian()
	price = math.clamp(price, PRICE_CENTER - PRICE_SPAN * 0.9, PRICE_CENTER + PRICE_SPAN * 0.9)

	return price
end

local function priceToY(value)
	return 0.5 - (value - PRICE_CENTER) / PRICE_SPAN * 0.4
end

local function startCandle()
	table.insert(candles, { open = price, high = price, low = price, close = price })
end

local function tickCandle(candle)
	local value = stepPrice()

	candle.close = value
	candle.high = math.max(candle.high, value)
	candle.low = math.min(candle.low, value)
end

local function drawCandle(index)
	local candle = candles[index]
	local view = candleViews[index]
	local slot = 1 / CANDLE_COUNT
	local x = (index - 0.5) * slot
	local top = priceToY(math.max(candle.open, candle.close))
	local bottom = priceToY(math.min(candle.open, candle.close))
	local color = candle.close >= candle.open and Theme.Colors.Up or Theme.Colors.Down

	view.body.Position = UDim2.fromScale(x, top)
	view.body.Size = UDim2.new(slot * CANDLE_BODY_WIDTH, 0, bottom - top, 2) -- a flat candle still shows
	view.body.BackgroundColor3 = color
	view.wick.Position = UDim2.fromScale(x, priceToY(candle.high))
	view.wick.Size = UDim2.new(0, 2, priceToY(candle.low) - priceToY(candle.high), 0)
	view.wick.BackgroundColor3 = color
end

local function drawCandles()
	for index in ipairs(candles) do
		drawCandle(index)
	end
end

for index = 1, CANDLE_COUNT + 1 do
	local wick = UIKit.makeFrame("Wick_" .. index, Strip)
	wick.AnchorPoint = Vector2.new(0.5, 0)
	wick.BackgroundTransparency = CANDLE_TRANSPARENCY

	local body = UIKit.makeFrame("Body_" .. index, Strip)
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.BackgroundTransparency = CANDLE_TRANSPARENCY

	candleViews[index] = { body = body, wick = wick }
end

-- A history that fills the screen, then the forming candle
for _ = 1, CANDLE_COUNT do
	startCandle()

	for _ = 1, TICKS_PER_CANDLE do
		tickCandle(candles[#candles])
	end
end

startCandle()
drawCandles()

-- Each drift moves the strip one slot left; when it ends, the forming candle
-- is complete, the oldest drops off and the strip snaps back
local function drift()
	if not StartGui.Parent then
		return
	end

	local tween = TweenService:Create(
		Strip,
		TweenInfo.new(CANDLE_SECONDS, Enum.EasingStyle.Linear),
		{ Position = UDim2.fromScale(-1 / CANDLE_COUNT, 0) }
	)

	tween.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end

		table.remove(candles, 1)
		startCandle()
		Strip.Position = UDim2.fromScale(0, 0)
		drawCandles()
		drift()
	end)

	tween:Play()
end

StartGui.Parent = PlayerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()
drift()

-- The candles keep moving until the screen is gone, lift included
task.spawn(function()
	while StartGui.Parent do
		task.wait(TICK_SECONDS)
		tickCandle(candles[#candles])
		drawCandle(#candles)
	end
end)

-- Loading
local function setProgress(fraction, status)
	TweenService:Create(LoadingFill, PROGRESS_TWEEN, { Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1) }):Play()

	if status then
		LoadingStatus.Text = status
	end
end

local function waitUntil(condition, timeout)
	local deadline = os.clock() + timeout

	while not condition() and os.clock() < deadline do
		task.wait(0.1)
	end
end

setProgress(0.08, "Joining the market…")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

setProgress(0.35, "Loading the terminal…")

local TerminalGui = PlayerGui:WaitForChild("TerminalGui", TERMINAL_TIMEOUT)

-- Fonts and images, so the terminal doesn't pop in a piece at a time. How
-- many there are isn't known up front, so the bar eases toward the step's end.
do
	local loaded = 0
	local toPreload = { StartGui }

	if TerminalGui then
		table.insert(toPreload, TerminalGui)
	end

	local success, problem = pcall(function()
		ContentProvider:PreloadAsync(toPreload, function()
			loaded += 1
			setProgress(0.35 + 0.35 * loaded / (loaded + 6))
		end)
	end)

	if not success then
		warn("[StartScreen] Preloading failed: " .. tostring(problem))
	end
end

setProgress(0.75, "Loading your account…")

-- PlayerDataService sets Balance once the profile loads, ProgressionService the Level
waitUntil(function()
	return Player:GetAttribute("Balance") ~= nil and Player:GetAttribute("Level") ~= nil
end, ACCOUNT_TIMEOUT)

setProgress(1, "Ready")

task.wait(math.max(MIN_LOADING_SECONDS - (os.clock() - startedAt), PROGRESS_TWEEN.Time))

-- Start menu
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)
local Progression = require(ReplicatedStorage.Config.Progression)
local Economy = require(ReplicatedStorage.Config.Economy)

local GetDailyEvent = ReplicatedStorage:WaitForChild("EventsFolder"):WaitForChild("GetDailyEvent")

local HOW_TO_PLAY = {
	{
		title = "Pick something to trade",
		body = "Stocks, ETFs and crypto move with the real market. Roblox games trade too: their prices "
			.. "follow how many people are playing.",
	},
	{
		title = "Buy in one click",
		body = string.format(
			"You start with %s of play money. Presets buy a dollar amount at the live price, "
				.. "and sell a share of what you hold.",
			NumberModule.format(Economy.STARTING_BALANCE)
		),
	},
	{
		title = "Level up",
		body = "Trades and milestones earn XP. Levels unlock limit and stop orders, chart indicators and options.",
	},
	{
		title = "Climb the leaderboards",
		body = "Share theses, follow the best traders and see how your returns rank against everyone's.",
	},
}

local function makeList(parent, padding)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent

	return layout
end

local function addPadding(parent, size)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, size)
	padding.PaddingBottom = UDim.new(0, size)
	padding.PaddingLeft = UDim.new(0, size)
	padding.PaddingRight = UDim.new(0, size)
	padding.Parent = parent
end

local function makeBlock(name, layoutOrder, gap)
	local block = UIKit.makeFrame(name, Column)
	block.LayoutOrder = layoutOrder
	block.Size = UDim2.fromScale(1, 0)
	block.AutomaticSize = Enum.AutomaticSize.Y
	block.Visible = false
	makeList(block, gap)

	return block
end

-- Accent for the main action, Raised otherwise; Roblox darkens them on hover
-- and press
local function makeButton(name, parent, text, isPrimary)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = true
	button.BorderSizePixel = 0
	button.BackgroundColor3 = isPrimary and Theme.Colors.Accent or Theme.Colors.Raised
	button.FontFace = isPrimary and Theme.Fonts.UIBold or Theme.Fonts.UISemibold
	button.TextSize = isPrimary and Theme.TextSize.Title or Theme.TextSize.Body
	button.TextColor3 = isPrimary and Theme.Colors.Background or Theme.Colors.Text -- dark on Accent reads better
	button.Text = text
	button.Parent = parent
	UIKit.addCorner(button)

	if not isPrimary then
		UIKit.addStroke(button)
	end

	return button
end

local MenuBlock = makeBlock("Menu", 4, 10)

-- The player's card: who, how far along, how they're doing
local Card = UIKit.makePanel("PlayerCard", MenuBlock)
Card.LayoutOrder = 1
Card.Size = UDim2.fromScale(1, 0)
Card.AutomaticSize = Enum.AutomaticSize.Y
addPadding(Card, CARD_PADDING)
makeList(Card, 12)

local Identity = UIKit.makeFrame("Identity", Card)
Identity.LayoutOrder = 1
Identity.Size = UDim2.new(1, 0, 0, AVATAR_SIZE)

UIKit.makeAvatar("Avatar", Identity, Player.UserId, AVATAR_SIZE)

local textX = AVATAR_SIZE + 12

local WelcomeLabel = makeLabel("Welcome", Identity, Theme.Fonts.UIBold, Theme.TextSize.Title, Theme.Colors.Text)
WelcomeLabel.Position = UDim2.fromOffset(textX, 0)
WelcomeLabel.Size = UDim2.new(1, -textX, 0, 20)

local LevelLabel = makeLabel("Level", Identity, Theme.Fonts.UISemibold, Theme.TextSize.Caption, Theme.Colors.Accent)
LevelLabel.Position = UDim2.fromOffset(textX, 21)
LevelLabel.Size = UDim2.new(1, -textX, 0, 14)

local XPTrack, XPFill = makeBar("XPBar", Identity, XP_BAR_HEIGHT)
XPTrack.Position = UDim2.fromOffset(textX, 38)
XPTrack.Size = UDim2.new(1, -textX, 0, XP_BAR_HEIGHT)

local XPLabel = makeLabel("XP", Card, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
XPLabel.LayoutOrder = 2
XPLabel.Size = UDim2.new(1, 0, 0, 14)

-- The streak and today's challenges, once ChallengeService answers
local DailyLabel = makeLabel("Daily", Card, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
DailyLabel.LayoutOrder = 3
DailyLabel.Size = UDim2.new(1, 0, 0, 14)
DailyLabel.RichText = true
DailyLabel.Visible = false

local CardDivider = UIKit.makeFrame("Divider", Card)
CardDivider.LayoutOrder = 4
CardDivider.Size = UDim2.new(1, 0, 0, 1)
CardDivider.BackgroundTransparency = 0
CardDivider.BackgroundColor3 = Theme.Colors.Border

local Worth = UIKit.makeFrame("Worth", Card)
Worth.LayoutOrder = 5
Worth.Size = UDim2.new(1, 0, 0, 44)

local WorthCaption = makeLabel("Caption", Worth, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
WorthCaption.Size = UDim2.new(0.5, 0, 0, 14)
WorthCaption.Text = "Net worth"

local WorthValue = makeLabel("Value", Worth, Theme.Fonts.MonoBold, Theme.TextSize.Display, Theme.Colors.Text)
WorthValue.Position = UDim2.fromOffset(0, 16)
WorthValue.Size = UDim2.new(0.55, 0, 0, 28)

local ChangeCaption = makeLabel("ChangeCaption", Worth, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
ChangeCaption.AnchorPoint = Vector2.new(1, 0)
ChangeCaption.Position = UDim2.fromScale(1, 0)
ChangeCaption.Size = UDim2.new(0.45, 0, 0, 14)
ChangeCaption.TextXAlignment = Enum.TextXAlignment.Right

local ChangeValue = makeLabel("ChangeValue", Worth, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.TextMuted)
ChangeValue.AnchorPoint = Vector2.new(1, 0)
ChangeValue.Position = UDim2.new(1, 0, 0, 22)
ChangeValue.Size = UDim2.new(0.45, 0, 0, 18)
ChangeValue.TextXAlignment = Enum.TextXAlignment.Right

local StartButton = makeButton("StartButton", MenuBlock, "Start trading", true)
StartButton.LayoutOrder = 2
StartButton.Size = UDim2.new(1, 0, 0, START_BUTTON_HEIGHT)

local ButtonRow = UIKit.makeFrame("ButtonRow", MenuBlock)
ButtonRow.LayoutOrder = 3
ButtonRow.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)

local LeaderboardsButton = makeButton("LeaderboardsButton", ButtonRow, "Leaderboards", false)
LeaderboardsButton.Size = UDim2.new(0.5, -BUTTON_GAP / 2, 1, 0)

local HowToPlayButton = makeButton("HowToPlayButton", ButtonRow, "How to play", false)
HowToPlayButton.AnchorPoint = Vector2.new(1, 0)
HowToPlayButton.Position = UDim2.fromScale(1, 0)
HowToPlayButton.Size = UDim2.new(0.5, -BUTTON_GAP / 2, 1, 0)

-- "● NYSE open · closes in 3h 12m", centered
local MarketLine = UIKit.makeFrame("MarketLine", MenuBlock)
MarketLine.LayoutOrder = 4
MarketLine.Size = UDim2.new(1, 0, 0, 18)

do
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = MarketLine
end

local MarketDot = UIKit.makeDot("Dot", MarketLine, 8, Theme.Colors.TextMuted)
MarketDot.AnchorPoint = Vector2.zero
MarketDot.LayoutOrder = 1

local MarketLabel = makeLabel("Label", MarketLine, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
MarketLabel.LayoutOrder = 2
MarketLabel.AutomaticSize = Enum.AutomaticSize.X
MarketLabel.Size = UDim2.fromScale(0, 1)
MarketLabel.TextTruncate = Enum.TextTruncate.None

-- How to play: numbered steps, then Back
local HowToBlock = makeBlock("HowToPlay", 5, 10)

local HowToCard = UIKit.makePanel("Steps", HowToBlock)
HowToCard.LayoutOrder = 1
HowToCard.Size = UDim2.fromScale(1, 0)
HowToCard.AutomaticSize = Enum.AutomaticSize.Y
addPadding(HowToCard, CARD_PADDING)
makeList(HowToCard, 14)

local HowToTitle = makeLabel("Title", HowToCard, Theme.Fonts.UIBold, Theme.TextSize.Title, Theme.Colors.Text)
HowToTitle.LayoutOrder = 0
HowToTitle.Size = UDim2.new(1, 0, 0, 20)
HowToTitle.Text = "How to play"

for index, step in ipairs(HOW_TO_PLAY) do
	local row = UIKit.makeFrame("Step_" .. index, HowToCard)
	row.LayoutOrder = index
	row.Size = UDim2.fromScale(1, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y

	local badge = makeLabel("Number", row, Theme.Fonts.UIBold, Theme.TextSize.Caption, Theme.Colors.Background)
	badge.Size = UDim2.fromOffset(STEP_BADGE_SIZE, STEP_BADGE_SIZE)
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = Theme.Colors.Accent
	badge.TextXAlignment = Enum.TextXAlignment.Center
	badge.Text = tostring(index)
	UIKit.addCorner(badge, UIKit.CIRCLE)

	local stepX = STEP_BADGE_SIZE + 12
	local text = UIKit.makeFrame("Text", row)
	text.Position = UDim2.fromOffset(stepX, 2)
	text.Size = UDim2.new(1, -stepX, 0, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	makeList(text, 2)

	local title = makeLabel("Title", text, Theme.Fonts.UISemibold, Theme.TextSize.Body, Theme.Colors.Text)
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Text = step.title

	local body = makeLabel("Body", text, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	body.LayoutOrder = 2
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.TextWrapped = true
	body.TextTruncate = Enum.TextTruncate.None
	body.Text = step.body
end

local BackButton = makeButton("BackButton", HowToBlock, "Back", false)
BackButton.LayoutOrder = 2
BackButton.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)

local function updateCard()
	local xp = Player:GetAttribute("XP") or 0
	local progress = Progression.getLevelProgress(xp)
	local levelInfo = Progression.LEVELS[progress.level]
	local nextLevel = Progression.LEVELS[progress.level + 1]
	local isNew = xp == 0

	WelcomeLabel.Text = string.format("%s, %s", isNew and "Welcome" or "Welcome back", Player.DisplayName)
	LevelLabel.Text = string.format("Level %d · %s", progress.level, levelInfo.name)
	XPFill.Size = UDim2.fromScale(progress.fraction, 1)
	XPLabel.Text = nextLevel and string.format("%d / %d XP to %s", progress.earned, progress.needed, nextLevel.name)
		or string.format("%d XP · top level", xp)

	-- NetWorth arrives with the first pricing pass. Until then the card shows
	-- the cash, with no gain or loss: cash alone would read as a loss for
	-- anyone holding shares.
	local worth = Player:GetAttribute("NetWorth")
	local balance = Player:GetAttribute("Balance")

	WorthCaption.Text = worth and "Net worth" or "Cash"
	WorthValue.Text = (worth or balance) and NumberModule.format(worth or balance) or "—"

	if not worth or isNew then
		ChangeCaption.Text = ""
		ChangeValue.Text = isNew and "Make your first trade" or ""
		ChangeValue.FontFace = Theme.Fonts.UI
		ChangeValue.TextColor3 = Theme.Colors.TextMuted

		return
	end

	local change = worth - Economy.STARTING_BALANCE
	local percent = change / Economy.STARTING_BALANCE * 100

	ChangeCaption.Text = "Since you started"
	ChangeValue.Text = string.format("%s%s (%+.2f%%)", change >= 0 and "+" or "", NumberModule.format(change), percent)
	ChangeValue.FontFace = Theme.Fonts.Mono
	ChangeValue.TextColor3 = change > 0 and Theme.Colors.Up
		or change < 0 and Theme.Colors.Down
		or Theme.Colors.TextMuted
end

local function updateMarketLine()
	local now = os.time()
	local isOpen, targetTime = MarketHoursModule.getMarketStatus(now)
	local countdown = MarketHoursModule.formatCountdown(targetTime - now)

	MarketDot.BackgroundColor3 = isOpen and Theme.Colors.Up or Theme.Colors.TextMuted
	MarketLabel.Text = isOpen and ("NYSE open · closes in " .. countdown)
		or ("NYSE closed · opens in " .. countdown .. " · crypto and Roblox games trade 24/7")
end

local function selectForGamepad(button)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = button
	end
end

local function showHowToPlay(isShown)
	MenuBlock.Visible = not isShown
	HowToBlock.Visible = isShown
	selectForGamepad(isShown and BackButton or StartButton)
end

local connections = {}

-- Lifts the screen away, optionally onto another tab
local function dismiss(tabName)
	if isDismissed then
		return
	end

	isDismissed = true

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	if tabName then
		Navigation.openTab(tabName)
	end

	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(StartGui) then
		GuiService.SelectedObject = nil
	end

	local lift = TweenService:Create(Root, LIFT_TWEEN, { Position = UDim2.fromScale(0, -1) })

	lift.Completed:Connect(function()
		StartGui:Destroy()
	end)

	lift:Play()
end

-- A new player goes straight to the Trade tab, where picks and a coached
-- first trade wait; everyone else to the Dashboard
local function start()
	dismiss((Player:GetAttribute("XP") or 0) == 0 and "Trade" or nil)
end

StartButton.MouseButton1Click:Connect(start)

LeaderboardsButton.MouseButton1Click:Connect(function()
	dismiss("Leaderboards")
end)

HowToPlayButton.MouseButton1Click:Connect(function()
	showHowToPlay(true)
end)

BackButton.MouseButton1Click:Connect(function()
	showHowToPlay(false)
end)

-- Enter starts (or goes back from How to play); Escape goes back
table.insert(
	connections,
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		local isEnter = input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter

		if HowToBlock.Visible and (isEnter or input.KeyCode == Enum.KeyCode.Escape) then
			showHowToPlay(false)
		elseif MenuBlock.Visible and isEnter then
			start()
		end
	end)
)

for _, attribute in ipairs({ "XP", "Balance", "NetWorth" }) do
	table.insert(connections, Player:GetAttributeChangedSignal(attribute):Connect(updateCard))
end

updateCard()
updateMarketLine()

task.spawn(function()
	local success, daily = pcall(GetDailyEvent.InvokeServer, GetDailyEvent)

	if not success or not daily or isDismissed then
		return
	end

	local done = 0

	for _, challenge in ipairs(daily.challenges) do
		if challenge.done then
			done += 1
		end
	end

	local challenges = string.format("%d/%d daily challenges done", done, #daily.challenges)

	DailyLabel.Text = daily.streak > 0
			and string.format(
				'🔥 <font color="#%s">%d-day streak</font> · %s',
				Theme.Colors.Text:ToHex(),
				daily.streak,
				challenges
			)
		or ("🎯 " .. challenges .. " · finish one to start a streak")
	DailyLabel.Visible = true
end)

task.spawn(function()
	while not isDismissed do
		task.wait(1)
		updateMarketLine()
	end
end)

-- The loading bar gives way to the menu, which rises into place
LoadingBlock.Visible = false
MenuBlock.Visible = true
Column.Position = UDim2.new(0.5, 0, 0.5, 24)
TweenService:Create(Column, REVEAL_TWEEN, { Position = UDim2.fromScale(0.5, 0.5) }):Play()
selectForGamepad(StartButton)
