local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Events = ReplicatedStorage:WaitForChild("Events")
local TradeEvent = Events:WaitForChild("TradeEvent")
local OptionEvent = Events:WaitForChild("OptionEvent")
local RequestChartEvent = Events:WaitForChild("RequestChartEvent")
local GetMarketDataEvent = Events:WaitForChild("GetMarketDataEvent")

local playerGui = player:WaitForChild("PlayerGui")
local terminalGui = playerGui:WaitForChild("TerminalGUI")
local mainBackground = terminalGui:WaitForChild("BackgroundUI")
local titleBar = mainBackground:WaitForChild("TitleBar")
local tabContainer = titleBar:WaitForChild("TabContainer")
local screenContainer = mainBackground:WaitForChild("ScreenContainer")

local AccentLine = titleBar:WaitForChild("AccentLine")
local AccentGradient = AccentLine:WaitForChild("UIGradient")

local sweepInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local tabs = {
	Dashboard = {
		Button = tabContainer:WaitForChild("DashboardButton"),
		Frame = screenContainer:WaitForChild("DashboardScreen"),
	},
	Portfolio = {
		Button = tabContainer:WaitForChild("PortfolioButton"),
		Frame = screenContainer:WaitForChild("PortfolioScreen"),
	},
	Stocks = {
		Button = tabContainer:WaitForChild("StocksButton"),
		Frame = screenContainer:WaitForChild("StocksScreen"),
	},
	Options = {
		Button = tabContainer:WaitForChild("OptionsButton"),
		Frame = screenContainer:WaitForChild("OptionsScreen"),
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
	for tabName, data in pairs(tabs) do
		data.Frame.Visible = false
		data.Button.TextColor3 = Color3.fromRGB(120, 123, 134)
	end
	if tabs[tabName] then
		tabs[tabName].Frame.Visible = true
		tabs[tabName].Button.TextColor3 = Color3.fromRGB(209, 212, 220)

		AccentGradient.Offset = Vector2.new(-1, 0)

		local sweepTween = TweenService:Create(AccentGradient, sweepInfo, { Offset = Vector2.new(1, 0) })
		sweepTween:Play()
	end
end

for tabName, data in pairs(tabs) do
	data.Button.MouseButton1Click:Connect(function()
		switchTab(tabName)
	end)
end

switchTab("Dashboard")
