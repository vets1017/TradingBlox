-- ShellController.client.luau
--
-- Owns the full-screen terminal shell around the screens: sizes the window
-- to the whole viewport, lays the nav bar out around Roblox's own top-bar
-- buttons, adds the wordmark, inbox bell, level and balance pills and bottom
-- status bar, shows toasts, and stamps the theme onto all of TerminalGui
-- once at startup. Switching tabs stays in TerminalController; the inbox
-- itself (badge and list) is InboxController's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local Progression = require(ReplicatedStorage.Config.Progression)
local Social = require(ReplicatedStorage.Config.Social)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local MainBackground = TerminalGui:WaitForChild("MainBackground")
local TopBar = MainBackground:WaitForChild("TopBar")
local TabContainer = TopBar:WaitForChild("TabContainer")
local TabLayout = TabContainer:WaitForChild("UIListLayout")
local AccentLine = TopBar:WaitForChild("AccentLine")
local AccentGradient = AccentLine:WaitForChild("AccentGradient")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")

-- Layout Constants
local NAV_FALLBACK_HEIGHT = 44 -- when Roblox reports no top bar (TopbarInset height 0)
local STATUS_BAR_HEIGHT = 26
local EDGE_PADDING = 12
local WORDMARK_WIDTH = 116
local SECTION_GAP = 24
local BALANCE_PILL_HEIGHT = 28
local BALANCE_PILL_MIN_WIDTH = 90
local BALANCE_PILL_PADDING = 12 -- each side of the balance text
local TAB_TEXT_PADDING = 10
local NET_WORTH_VALUE_WIDTH = 140
local PILL_GAP = 8 -- between the level and balance pills
local INBOX_BUTTON_WIDTH = 34
local INBOX_BADGE_SIZE = 16
local TOAST_WIDTH = 420
local TOAST_HEIGHT = 56
local TOAST_SECONDS = 6
local TOAST_FADE = TweenInfo.new(0.3)

-- The terminal is the whole game UI; these default HUD pieces would sit on
-- top of it once it fills the screen. Chat stays available.
for _, coreGuiType in ipairs({
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.EmotesMenu,
}) do
	StarterGui:SetCoreGuiEnabled(coreGuiType, false)
end

-- Full screen, under Roblox's top bar - the nav bar shares that strip
TerminalGui.ScreenInsets = Enum.ScreenInsets.None
MainBackground.AnchorPoint = Vector2.zero
MainBackground.Position = UDim2.fromScale(0, 0)
MainBackground.Size = UDim2.fromScale(1, 1)

-- Shell elements are built here rather than in Studio so they live in git
local function makeTextLabel(name, role, parent)
	local label = Instance.new("TextLabel")

	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = ""
	label:SetAttribute("ThemeRole", role)
	label.Parent = parent

	return label
end

local Wordmark = makeTextLabel("Wordmark", "Heading", TopBar)
Wordmark.Text = "TradingBlox"
Wordmark.Size = UDim2.new(0, WORDMARK_WIDTH, 1, 0)
Wordmark.TextXAlignment = Enum.TextXAlignment.Left

local BalancePill = Instance.new("Frame")
BalancePill.Name = "BalancePill"
BalancePill.AnchorPoint = Vector2.new(1, 0.5)
BalancePill.Size = UDim2.fromOffset(BALANCE_PILL_MIN_WIDTH, BALANCE_PILL_HEIGHT)
BalancePill.BorderSizePixel = 0
BalancePill:SetAttribute("ThemeRole", "Pill")
BalancePill.Parent = TopBar

local BalanceValue = makeTextLabel("BalanceValue", "Number", BalancePill)
BalanceValue.Size = UDim2.fromScale(1, 1)
BalanceValue.TextXAlignment = Enum.TextXAlignment.Center

local LevelPill = Instance.new("Frame")
LevelPill.Name = "LevelPill"
LevelPill.AnchorPoint = Vector2.new(1, 0.5)
LevelPill.Size = UDim2.fromOffset(BALANCE_PILL_MIN_WIDTH, BALANCE_PILL_HEIGHT)
LevelPill.BorderSizePixel = 0
LevelPill:SetAttribute("ThemeRole", "Pill")
LevelPill.Parent = TopBar

local LevelValue = makeTextLabel("LevelValue", "TextStrong", LevelPill)
LevelValue.Size = UDim2.fromScale(1, 1)
LevelValue.TextXAlignment = Enum.TextXAlignment.Center

-- The inbox bell; InboxController owns its badge and the list it opens
local InboxButton = Instance.new("TextButton")
InboxButton.Name = "InboxButton"
InboxButton.AnchorPoint = Vector2.new(1, 0.5)
InboxButton.Size = UDim2.fromOffset(INBOX_BUTTON_WIDTH, BALANCE_PILL_HEIGHT)
InboxButton.BorderSizePixel = 0
InboxButton.AutoButtonColor = false
InboxButton.FontFace = Theme.Fonts.UI
InboxButton.TextSize = Theme.TextSize.Body
InboxButton.Text = "🔔"
InboxButton:SetAttribute("ThemeRole", "Pill")
InboxButton.Parent = TopBar

-- Untagged on purpose: InboxController shows and fills it
local InboxBadge = Instance.new("TextLabel")
InboxBadge.Name = "Badge"
InboxBadge.AnchorPoint = Vector2.new(0.5, 0.5)
InboxBadge.Position = UDim2.new(1, -2, 0, 2)
InboxBadge.Size = UDim2.fromOffset(INBOX_BADGE_SIZE, INBOX_BADGE_SIZE)
InboxBadge.BackgroundColor3 = Theme.Colors.Accent
InboxBadge.BorderSizePixel = 0
InboxBadge.FontFace = Theme.Fonts.UIBold
InboxBadge.TextSize = Theme.TextSize.Caption - 2
InboxBadge.TextColor3 = Theme.Colors.Background
InboxBadge.Text = ""
InboxBadge.Visible = false
InboxBadge.Parent = InboxButton

local InboxBadgeCorner = Instance.new("UICorner")
InboxBadgeCorner.CornerRadius = UDim.new(0.5, 0)
InboxBadgeCorner.Parent = InboxBadge

-- Announcements under the nav bar (level-ups, limit-order fills);
-- positioned by layoutShell
local Toast = Instance.new("Frame")
Toast.Name = "Toast"
Toast.AnchorPoint = Vector2.new(0.5, 0)
Toast.Size = UDim2.fromOffset(TOAST_WIDTH, TOAST_HEIGHT)
Toast.BorderSizePixel = 0
Toast.Visible = false
Toast.ZIndex = 10
Toast:SetAttribute("ThemeRole", "Panel")
Toast.Parent = MainBackground

local ToastTitle = makeTextLabel("Title", "Heading", Toast)
ToastTitle.Position = UDim2.fromOffset(0, 8)
ToastTitle.Size = UDim2.new(1, 0, 0, 20)
ToastTitle.TextXAlignment = Enum.TextXAlignment.Center
ToastTitle.ZIndex = 10

local ToastBody = makeTextLabel("Body", "TextMuted", Toast)
ToastBody.Position = UDim2.fromOffset(12, 30)
ToastBody.Size = UDim2.new(1, -24, 0, 18)
ToastBody.TextXAlignment = Enum.TextXAlignment.Center
ToastBody.TextTruncate = Enum.TextTruncate.AtEnd
ToastBody.ZIndex = 10

local StatusBar = Instance.new("Frame")
StatusBar.Name = "StatusBar"
StatusBar.AnchorPoint = Vector2.new(0, 1)
StatusBar.Position = UDim2.fromScale(0, 1)
StatusBar.Size = UDim2.new(1, 0, 0, STATUS_BAR_HEIGHT)
StatusBar.BorderSizePixel = 0
StatusBar:SetAttribute("ThemeRole", "PanelFlat") -- Panel color; a stroke/corners would look wrong full-width
StatusBar.Parent = MainBackground

local StatusTopEdge = Instance.new("Frame")
StatusTopEdge.Name = "TopEdge"
StatusTopEdge.Size = UDim2.new(1, 0, 0, 1)
StatusTopEdge.BorderSizePixel = 0
StatusTopEdge:SetAttribute("ThemeRole", "Divider")
StatusTopEdge.Parent = StatusBar

-- Untagged on purpose: its color flips open/closed every update below
local MarketDot = Instance.new("Frame")
MarketDot.Name = "MarketDot"
MarketDot.AnchorPoint = Vector2.new(0, 0.5)
MarketDot.Position = UDim2.new(0, EDGE_PADDING, 0.5, 0)
MarketDot.Size = UDim2.fromOffset(8, 8)
MarketDot.BorderSizePixel = 0
MarketDot.Parent = StatusBar

local MarketDotCorner = Instance.new("UICorner")
MarketDotCorner.CornerRadius = UDim.new(0.5, 0)
MarketDotCorner.Parent = MarketDot

local MarketLabel = makeTextLabel("MarketLabel", "TextMuted", StatusBar)
MarketLabel.Position = UDim2.fromOffset(EDGE_PADDING + 16, 0)
MarketLabel.Size = UDim2.fromScale(0.5, 1)
MarketLabel.TextXAlignment = Enum.TextXAlignment.Left

local NetWorthValue = makeTextLabel("NetWorthValue", "Number", StatusBar)
NetWorthValue.AnchorPoint = Vector2.new(1, 0)
NetWorthValue.Position = UDim2.new(1, -EDGE_PADDING, 0, 0)
NetWorthValue.Size = UDim2.new(0, NET_WORTH_VALUE_WIDTH, 1, 0)
NetWorthValue.TextXAlignment = Enum.TextXAlignment.Right

local NetWorthCaption = makeTextLabel("NetWorthCaption", "TextMuted", StatusBar)
NetWorthCaption.Text = "Net worth"
NetWorthCaption.AnchorPoint = Vector2.new(1, 0)
NetWorthCaption.Position = UDim2.new(1, -(EDGE_PADDING + NET_WORTH_VALUE_WIDTH + 8), 0, 0)
NetWorthCaption.Size = UDim2.new(0, 70, 1, 0)
NetWorthCaption.TextXAlignment = Enum.TextXAlignment.Right

-- Tabs built in code rather than Studio: the shell adds each one's nav
-- button and an empty screen, the tab's own controller fills the screen,
-- and TerminalController switches to it like any other tab. They sort after
-- the Studio tabs, which all have LayoutOrder 0.
local CODE_BUILT_TABS = { "Social", "Leaderboards" }

for index, tabName in ipairs(CODE_BUILT_TABS) do
	local tabButton = Instance.new("TextButton")
	tabButton.Name = tabName .. "Button"
	tabButton.Text = tabName
	tabButton.LayoutOrder = index
	tabButton.BackgroundTransparency = 1
	tabButton.BorderSizePixel = 0
	tabButton:SetAttribute("ThemeRole", "Tab")
	tabButton.Parent = TabContainer

	local screen = Instance.new("Frame")
	screen.Name = tabName .. "Screen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BorderSizePixel = 0
	screen.Visible = false
	screen:SetAttribute("ThemeRole", "Screen")
	screen.Parent = ScreenContainer
end

-- Tabs sit left-aligned after the wordmark, sized to their text, instead of
-- the old fixed-width row right-aligned against the window buttons
TabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
TabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
TabLayout.Padding = UDim.new(0, 4)

for _, tabButton in ipairs(TabContainer:GetChildren()) do
	if tabButton:IsA("TextButton") then
		tabButton.AutomaticSize = Enum.AutomaticSize.X
		tabButton.Size = UDim2.fromScale(0, 1)

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, TAB_TEXT_PADDING)
		padding.PaddingRight = UDim.new(0, TAB_TEXT_PADDING)
		padding.Parent = tabButton
	end
end

-- TerminalController's tab-switch tween ends at Offset (1, 0), where only the
-- first keypoint shows - so at rest the line reads as a plain divider and a
-- tab switch sweeps the violet peak across it
AccentGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Colors.Border),
	ColorSequenceKeypoint.new(0.5, Theme.Colors.Accent),
	ColorSequenceKeypoint.new(1, Theme.Colors.Border),
})

local function layoutShell()
	local inset = GuiService.TopbarInset
	local hasTopbar = inset.Height > 0
	local navHeight = hasTopbar and inset.Height or NAV_FALLBACK_HEIGHT
	local leftEdge = (hasTopbar and inset.Min.X or 0) + EDGE_PADDING
	local rightEdge = (hasTopbar and inset.Max.X or MainBackground.AbsoluteSize.X) - EDGE_PADDING

	-- The pills hug their text so narrow windows keep room for the tabs
	local pillWidth = math.max(BalanceValue.TextBounds.X + BALANCE_PILL_PADDING * 2, BALANCE_PILL_MIN_WIDTH)
	local levelPillWidth = LevelValue.TextBounds.X + BALANCE_PILL_PADDING * 2
	local levelPillRight = rightEdge - pillWidth - PILL_GAP
	local inboxRight = levelPillRight - levelPillWidth - PILL_GAP
	local tabsRight = inboxRight - INBOX_BUTTON_WIDTH - SECTION_GAP

	-- On a narrow window the wordmark gives up its space before the tabs do
	local tabsLeftWithWordmark = leftEdge + WORDMARK_WIDTH + SECTION_GAP
	local showWordmark = tabsRight - tabsLeftWithWordmark >= TabLayout.AbsoluteContentSize.X
	local tabsLeft = showWordmark and tabsLeftWithWordmark or leftEdge

	TopBar.Size = UDim2.new(1, 0, 0, navHeight)
	Wordmark.Visible = showWordmark
	Wordmark.Position = UDim2.fromOffset(leftEdge, 0)
	TabContainer.Position = UDim2.fromOffset(tabsLeft, 0)
	TabContainer.Size = UDim2.new(0, math.max(tabsRight - tabsLeft, 0), 1, 0)
	BalancePill.Size = UDim2.fromOffset(pillWidth, BALANCE_PILL_HEIGHT)
	BalancePill.Position = UDim2.new(0, rightEdge, 0.5, 0)
	LevelPill.Size = UDim2.fromOffset(levelPillWidth, BALANCE_PILL_HEIGHT)
	LevelPill.Position = UDim2.new(0, levelPillRight, 0.5, 0)
	InboxButton.Position = UDim2.new(0, inboxRight, 0.5, 0)
	Toast.Position = UDim2.new(0.5, 0, 0, navHeight + 12)

	ScreenContainer.Position = UDim2.fromOffset(0, navHeight)
	ScreenContainer.Size = UDim2.new(1, 0, 1, -(navHeight + STATUS_BAR_HEIGHT))
end

-- "—" until the server sets the attribute: Balance arrives once the DataStore
-- loads, and NetWorth is only computed after the first trade - $0.00 would
-- read as a real (and alarming) number
local function formatStat(value)
	return value and NumberModule.format(value) or "—"
end

local function updateBalance()
	BalanceValue.Text = formatStat(Player:GetAttribute("Balance"))
end

local function updateNetWorth()
	NetWorthValue.Text = formatStat(Player:GetAttribute("NetWorth"))
end

local shownLevel = nil -- nil until the server first sets Level, so loading in isn't announced
local toastVersion = 0

local function showToast(title, body)
	toastVersion += 1

	local version = toastVersion

	ToastTitle.Text = title
	ToastBody.Text = body
	Toast.BackgroundTransparency = 1
	Toast.Visible = true
	TweenService:Create(Toast, TOAST_FADE, { BackgroundTransparency = 0 }):Play()

	task.delay(TOAST_SECONDS, function()
		-- A newer toast owns the frame now
		if version == toastVersion then
			Toast.Visible = false
		end
	end)
end

local function showLevelToast(level)
	local unlocks = Progression.getUnlocksAt(level)

	showToast(
		string.format("Level %d · %s", level, Progression.LEVELS[level].name),
		#unlocks > 0 and ("Unlocked " .. table.concat(unlocks, ", ")) or "New level reached"
	)
end

local function updateLevel()
	local level = Player:GetAttribute("Level")

	LevelValue.Text = level and string.format("Lv %d · %s", level, Progression.LEVELS[level].name) or "—"

	if level and shownLevel and level > shownLevel then
		showLevelToast(level)
	end

	shownLevel = level
end

local function updateMarketStatus()
	local now = os.time()
	local isOpen, targetTime = MarketHoursModule.getMarketStatus(now)
	local countdown = MarketHoursModule.formatCountdown(targetTime - now)

	MarketDot.BackgroundColor3 = isOpen and Theme.Colors.Up or Theme.Colors.TextMuted
	MarketLabel.Text = isOpen and ("NYSE open · closes in " .. countdown) or ("NYSE closed · opens in " .. countdown)
end

GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layoutShell)
MainBackground:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutShell)
-- Tab widths and the balance text settle once fonts load, and the balance
-- text changes with every trade
TabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(layoutShell)
BalanceValue:GetPropertyChangedSignal("TextBounds"):Connect(layoutShell)
LevelValue:GetPropertyChangedSignal("TextBounds"):Connect(layoutShell)
Player:GetAttributeChangedSignal("Balance"):Connect(updateBalance)
Player:GetAttributeChangedSignal("NetWorth"):Connect(updateNetWorth)
Player:GetAttributeChangedSignal("Level"):Connect(updateLevel)

updateBalance()
updateNetWorth()
updateLevel()
updateMarketStatus()
Theme.apply(TerminalGui)
layoutShell()

task.spawn(function()
	while true do
		task.wait(1)
		updateMarketStatus()
	end
end)

-- Limit orders fill or get cancelled, options expire and stocks split on
-- the server's schedule, so they're announced here wherever the player is. Spawned so waiting for the remote
-- never holds up the shell.
task.spawn(function()
	local OrderUpdateEvent = ReplicatedStorage:WaitForChild("EventsFolder"):WaitForChild("OrderUpdateEvent")

	local TITLES = {
		filled = "Order filled",
		cancelled = "Order cancelled",
		expired = "Option expired",
		split = "Stock split",
		delisted = "Delisted",
	}

	OrderUpdateEvent.OnClientEvent:Connect(function(update)
		showToast(TITLES[update.kind] or "Update", update.message)
	end)
end)

-- New followers, reactions and the like, as they arrive (see
-- NotificationService); only live ones come with a toast
task.spawn(function()
	local NotificationEvent = ReplicatedStorage:WaitForChild("EventsFolder"):WaitForChild("NotificationEvent")

	NotificationEvent.OnClientEvent:Connect(function(update)
		if update.toast and update.notification then
			showToast(Social.describeNotification(update.notification))
		end
	end)
end)
