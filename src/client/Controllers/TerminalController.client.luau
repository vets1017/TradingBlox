local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local TradeEvent = EventsFolder:WaitForChild("TradeEvent")
local OptionEvent = EventsFolder:WaitForChild("OptionEvent")
local RequestChartEvent = EventsFolder:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = EventsFolder:WaitForChild("GetMarketDataEvent")

local PlayerGui = Player:WaitForChild("PlayerGui")

local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local MainBackground = TerminalGui:WaitForChild("MainBackground")
local TopBar = MainBackground:WaitForChild("TopBar")

local AccentLine = TopBar:WaitForChild("AccentLine")
local AccentGradient = AccentLine:WaitForChild("AccentGradient")

local TabContainer = TopBar:WaitForChild("TabContainer")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")

local DashboardScreen = ScreenContainer:WaitForChild("DashboardScreen")

local GreetingBar = DashboardScreen:WaitForChild("GreetingBar")
local GreetingText = GreetingBar:WaitForChild("GreetingText")
local DateText = GreetingBar:WaitForChild("DateText")

local DashboardGrid = DashboardScreen:WaitForChild("DashboardGrid")
local LeftSidebar = DashboardGrid:WaitForChild("LeftSidebar")

local RightSidebar = DashboardGrid:WaitForChild("RightSidebar")

local MainWorkspace = DashboardGrid:WaitForChild("MainWorkspace")
local BottomRow = MainWorkspace:WaitForChild("BottomRow")

local TopRow = MainWorkspace:WaitForChild("TopRow")
local CountdownWidget = TopRow:WaitForChild("CountdownWidget")
local TimeContainer = CountdownWidget:WaitForChild("TimeContainer")
local TitleText = CountdownWidget:WaitForChild("TitleText")
local HoursNumber = TimeContainer.HoursBlock.Number
local MinutesNumber = TimeContainer.MinutesBlock.Number
local SecondsNumber = TimeContainer.SecondsBlock.Number

local SWEEP_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Tabs = {
	Dashboard = {
		Button = TabContainer:WaitForChild("DashboardButton"),
		Frame = ScreenContainer:WaitForChild("DashboardScreen"),
	},
	Portfolio = {
		Button = TabContainer:WaitForChild("PortfolioButton"),
		Frame = ScreenContainer:WaitForChild("PortfolioScreen"),
	},
	Stocks = {
		Button = TabContainer:WaitForChild("StocksButton"),
		Frame = ScreenContainer:WaitForChild("StocksScreen"),
	},
	Options = {
		Button = TabContainer:WaitForChild("OptionsButton"),
		Frame = ScreenContainer:WaitForChild("OptionsScreen"),
	},
}
-- local stockListFrame =

local function refreshTerminal()
	local marketData = GetMarketDataEvent:InvokeServer()

	if not marketData then
		return
	end
	-- continue after stocklist is done
end

local function switchTab(tabName)
	for tabName, data in pairs(Tabs) do
		data.Frame.Visible = false
		data.Button.TextColor3 = Color3.fromRGB(120, 123, 134)
	end

	if Tabs[tabName] then
		Tabs[tabName].Frame.Visible = true
		Tabs[tabName].Button.TextColor3 = Color3.fromRGB(209, 212, 220)

		AccentGradient.Offset = Vector2.new(-1, 0)

		local sweepTween = TweenService:Create(AccentGradient, SWEEP_INFO, { Offset = Vector2.new(1, 0) })
		sweepTween:Play()
	end
end

local function updateGreeting()
	local timeData = os.date("*t")
	local hour = timeData.hour

	local greeting = "Welcome back,"
	if hour >= 5 and hour < 12 then
		greeting = "Good morning,"
	elseif hour >= 12 and hour < 17 then
		greeting = "Good afternoon,"
	elseif hour >= 17 and hour < 22 then
		greeting = "Good evening,"
	end

	local formattedDate = os.date("%A, %d %B %Y")

	GreetingText.Text = string.format("%s %s.", greeting, Player.DisplayName) -- Player.Name might be changed to a custom username instead
	DateText.Text = formattedDate
end

local function updateCountdown()
	local time = os.time()
	local currentUTC = os.date("!*t", time)

	local marketOpen = os.time({
		year = currentUTC.year,
		month = currentUTC.month,
		day = currentUTC.day,
		hour = 13,
		minute = 30,
		second = 0,
	})

	local marketClose = os.time({
		year = currentUTC.year,
		month = currentUTC.month,
		day = currentUTC.day,
		hour = 20,
		minute = 0,
		second = 0,
	})

	local targetTime

	if time < marketOpen then
		targetTime = marketOpen
		TitleText.Text = "NYSE opens in"
		TitleText.TextColor3 = Color3.fromRGB(120, 123, 134)
	elseif time >= marketOpen and time < marketClose then
		targetTime = marketClose
		TitleText.Text = "NYSE closes in"
		TitleText.TextColor3 = Color3.fromRGB(8, 153, 129)
	else -- After-hours
		targetTime = marketOpen + 86400
		TitleText.Text = "NYSE opens in"
		TitleText.TextColor3 = Color3.fromRGB(120, 123, 134)
	end

	local differenceTime = targetTime - time

	local hours = math.floor(differenceTime / 3600)
	local minutes = math.floor((differenceTime % 3600) / 60)
	local seconds = differenceTime % 60

	HoursNumber.Text = string.format("%02d", hours)
	MinutesNumber.Text = string.format("%02d", minutes)
	SecondsNumber.Text = string.format("%02d", seconds)
end

for tabName, data in pairs(Tabs) do
	data.Button.MouseButton1Click:Connect(function()
		switchTab(tabName)
	end)
end

task.spawn(function()
	while true do
		updateCountdown()
		task.wait(1)
	end
end)

switchTab("Dashboard")
updateGreeting()
