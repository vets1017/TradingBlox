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
local TabContainer = TopBar:WaitForChild("TabContainer")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")

local AccentLine = TopBar:WaitForChild("AccentLine")
local AccentGradient = AccentLine:WaitForChild("AccentGradient")

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

for tabName, data in pairs(Tabs) do
	data.Button.MouseButton1Click:Connect(function()
		switchTab(tabName)
	end)
end

switchTab("Dashboard")
