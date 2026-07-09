-- Services
local Players = game:GetService("Players")

-- Variables
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PLayerGui")

local TradeScreen = playerGui:WaitForChild("TradeScreen")
local QuoteDetails = TradeScreen:WaitForChild("QuoteDetails")
local TabContentContainer = QuoteDetails:WaitForChild("TabContentContainer")
local TabHeaderContainer = QuoteDetails:WaitForChild("TabHeaderContainer")

local tabs = {
	{ Button = TabHeaderContainer.Tab_QuoteDetails, Frame = TabContentContainer.Content_QuoteDetails },
}

-- Indicator UI to display active tab
local activeIndicator = Instance.new("Frame")

activeIndicator.Size = UDim2.new(1, 0, 0, 2)
activeIndicator.Position = UDim2.new(0, 0, 1, -2)
activeIndicator.BackgroundColor3 = Color3.new(240, 240, 240)

-- Switching Tab Function for Quote Tab
local function switchTab(button)
	for _, tab in ipairs(tabs) do
		if tab.Button == button then
			tab.Frame.Visible = true
			tab.Button.TextColor3 = Color3.fromRGB(240, 240, 240)
			activeIndicator.Parent = tab.Button
		else
			tab.Frame.Visible = false
			tab.Button.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end
end

for _, tab in ipairs(tabs) do
	tab.Button.MouseButton1Click:Connect(function()
		switchTab(tab.Button)
	end)
end

switchTab(TabHeaderContainer.Tab_QuoteDetails)
