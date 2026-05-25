local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NumberModule = require(ReplicatedStorage.Modules.NumberModule)

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
local AccountInfoWidget = LeftSidebar:WaitForChild("AccountInfoWidget")

local OptionPowerValue = AccountInfoWidget:WaitForChild("OptionPowerRow").ValueText
local NetLiquidityValue = AccountInfoWidget:WaitForChild("NetLiquidityRow").ValueText
local CashSweepValue = AccountInfoWidget:WaitForChild("CashSweepRow").ValueText
local AvailableFundsValue = AccountInfoWidget:WaitForChild("AvailableFundsRow").ValueText

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

local Holidays = {
	["01-01"] = true, -- New Year's Day
	["01-15"] = true, -- Martin Luther King Jr. Day
	["02-19"] = true, -- Presidents' Day
	["03-29"] = true, -- Good Friday
	["05-27"] = true, -- Memorial Day
	["06-19"] = true, -- Juneteenth
	["07-04"] = true, -- Independence Day
	["09-02"] = true, -- Labor Day
	["11-28"] = true, -- Thanksgiving
	["12-25"] = true, -- Christmas
}

local function refreshTerminal()
	local marketData = GetMarketDataEvent:InvokeServer()

	if not marketData then
		return
	end
	-- continue after stock-list is done
end

local function switchTab(tabName)
	for _, data in pairs(Tabs) do
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

local function isMarketClosed(currentTime)
	local date = os.date("!*t", currentTime)

	if date.wday == 1 or date.wday == 7 then
		return true
	end

	local dateString = string.format("%02d-%02d", date.month, date.day)

	if Holidays[dateString] then
		return true
	end

	return false
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

	if not isMarketClosed(time) and time >= marketOpen and time < marketClose then
		targetTime = marketClose
		TitleText.Text = "NYSE Closes In"
		TitleText.TextColor3 = Color3.fromRGB(8, 153, 129)
	else
		TitleText.Text = "NYSE Opens In"
		TitleText.TextColor3 = Color3.fromRGB(120, 123, 134)
		targetTime = marketOpen

		if time >= marketOpen or isMarketClosed(time) then
			targetTime = targetTime + 86400
		end

		while isMarketClosed(targetTime) do
			targetTime = targetTime + 86400
		end
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

local function updateAccountInfo()
	local currentBalance = Player:GetAttribute("Balance") or 0
	local currentNetWorth = Player:GetAttribute("NetWorth") or 0
	local optionPower = currentBalance or 0 -- wip

	OptionPowerValue.Text = NumberModule.format(optionPower)
	NetLiquidityValue.Text = NumberModule.format(currentNetWorth)
	CashSweepValue.Text = NumberModule.format(currentBalance)
	AvailableFundsValue.Text = NumberModule.format(currentBalance)
end

Player:GetAttributeChangedSignal("Balance"):Connect(updateAccountInfo)
Player:GetAttributeChangedSignal("NetWorth"):Connect(updateAccountInfo)

switchTab("Dashboard")
updateGreeting()
updateAccountInfo()
