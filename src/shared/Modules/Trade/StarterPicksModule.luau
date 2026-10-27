-- StarterPicksModule.luau
--
-- The Trade screen's "Popular right now" row while nothing is loaded: a few
-- picks to tap instead of an empty ticker box. They're today's most traded
-- (DiscoveryService), topped up with well-known names. While NYSE is
-- closed, what trades around the clock (crypto, Roblox games) comes first
-- and says so, so a new player's first trade can go through right away.
--
-- Client-only. TradeController creates it and hides it once a ticker loads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local Instruments = require(ReplicatedStorage.Config.Instruments)
local RobloxMarket = require(ReplicatedStorage.Config.RobloxMarket)

local GetTrendingEvent = ReplicatedStorage:WaitForChild("EventsFolder"):WaitForChild("GetTrendingEvent")

local MAX_PICKS = 6
local CHIP_HEIGHT = 32
local PADDING = 12
local TITLE_HEIGHT = 22

-- When few trades have happened today: two big stocks, the S&P 500, two
-- coins and the first two Roblox games listed
local DEFAULT_PICKS = {
	"AAPL",
	"NVDA",
	"SPY",
	"BTC-USD",
	"ETH-USD",
	RobloxMarket.EXPERIENCES[1].ticker,
	RobloxMarket.EXPERIENCES[2].ticker,
}

local StarterPicksModule = {}
StarterPicksModule.__index = StarterPicksModule

-- A Roblox game by its name, anything else by its ticker
local function describe(ticker)
	local experience = RobloxMarket.getExperience(ticker)

	return experience and experience.name or ticker
end

-- options = { parent, layoutOrder, onSelect: (ticker) -> () }
function StarterPicksModule.new(options)
	local self = setmetatable({}, StarterPicksModule)

	self.options = options

	local frame = UIKit.makePanel("StarterPicks", options.parent)
	frame.LayoutOrder = options.layoutOrder
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	self.frame = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PADDING)
	padding.PaddingBottom = UDim.new(0, PADDING)
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, PADDING)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = frame

	local title = UIKit.makeLabel("Title", frame, Theme.Fonts.UIBold, Theme.TextSize.Title, Theme.Colors.Text)
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
	title.Text = "Popular right now"

	local caption = UIKit.makeLabel("Caption", frame, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	caption.LayoutOrder = 2
	caption.Size = UDim2.new(1, 0, 0, 16)
	self.caption = caption

	local chips = UIKit.makeFrame("Chips", frame)
	chips.LayoutOrder = 3
	chips.Size = UDim2.fromScale(1, 0)
	chips.AutomaticSize = Enum.AutomaticSize.Y
	self.chips = chips

	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Wraps = true
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Padding = UDim.new(0, 8)
	chipLayout.Parent = chips

	self:render({})

	-- The ranking can take a moment (and fail); the defaults show meanwhile
	task.spawn(function()
		local success, trending = pcall(GetTrendingEvent.InvokeServer, GetTrendingEvent)

		if success and trending and trending.traded and self.frame.Visible then
			local tickers = {}

			for _, entry in ipairs(trending.traded) do
				table.insert(tickers, entry.ticker)
			end

			self:render(tickers)
		end
	end)

	return self
end

-- The picks: the trending tickers, then defaults, without repeats; while
-- NYSE is closed, the around-the-clock ones first
function StarterPicksModule:choose(trending)
	local isOpen = MarketHoursModule.getMarketStatus(os.time())
	local seen = {}
	local now, later = {}, {}

	for _, list in ipairs({ trending, DEFAULT_PICKS }) do
		for _, ticker in ipairs(list) do
			if not seen[ticker] then
				seen[ticker] = true
				table.insert((isOpen or Instruments.tradesAroundTheClock(ticker)) and now or later, ticker)
			end
		end
	end

	table.move(later, 1, #later, #now + 1, now)

	return { table.unpack(now, 1, math.min(#now, MAX_PICKS)) }, isOpen
end

function StarterPicksModule:render(trending)
	for _, child in ipairs(self.chips:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local picks, isOpen = self:choose(trending)

	self.caption.Text = isOpen and "Tap one to see it, then buy in one click."
		or "The stock market is closed. Crypto and Roblox games trade around the clock."

	for index, ticker in ipairs(picks) do
		local isAroundTheClock = Instruments.tradesAroundTheClock(ticker)
		local chip, stroke = UIKit.makePill("Pick_" .. ticker, self.chips, describe(ticker))

		chip.LayoutOrder = index
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Size = UDim2.fromOffset(0, CHIP_HEIGHT)
		chip.TextSize = Theme.TextSize.Body

		-- What can be traded this minute is outlined in the accent
		if not isOpen and isAroundTheClock then
			stroke.Color = Theme.Colors.Accent
			chip.Text = describe(ticker) .. "  · 24/7"
		end

		chip.MouseButton1Click:Connect(function()
			self.options.onSelect(ticker)
		end)
	end
end

function StarterPicksModule:hide()
	self.frame.Visible = false
end

return StarterPicksModule
