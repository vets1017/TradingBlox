-- OrderTicketModule.luau
--
-- The Trade screen's share order ticket. Pick an order type, then one
-- click on a preset - buy a dollar amount, or sell a share of the position -
-- places the order straight away, the same one-click pattern as the Charts
-- screen's Active Trader. Limit, Stop and Stop-limit (level 2) add their
-- prices, typed or nudged from the last price; they can be placed while the
-- market is closed and fill once it opens and the price gets there
-- (OrderRules).
--
-- Client-only. TradeController owns the ticker, price and position and
-- calls update() when any of them change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local Progression = require(ReplicatedStorage.Config.Progression)
local Instruments = require(ReplicatedStorage.Config.Instruments)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local PlayerOrderEvent = EventsFolder:WaitForChild("PlayerOrderEvent")
local PlaceLimitOrderEvent = EventsFolder:WaitForChild("PlaceLimitOrderEvent")
local PlaceStopOrderEvent = EventsFolder:WaitForChild("PlaceStopOrderEvent")

local Player = Players.LocalPlayer

local BUY_PRESETS = { 100, 250, 500, 1000 } -- dollars, like Active Trader
local SELL_PRESETS = { 0.25, 0.5, 0.75, 1 } -- of the position
local PRICE_NUDGES = { -0.01, -0.005, 0, 0.005, 0.01 } -- from the last price; 0 resets to it

-- The order types, in the ticket's order: their pill, the unlock they need,
-- and which prices they take
local MODES = {
	{ id = "Market" },
	{ id = "Limit", feature = "LimitOrders", limit = true },
	{ id = "Stop", feature = "StopOrders", stop = true },
	{ id = "StopLimit", label = "Stop-limit", feature = "StopOrders", stop = true, limit = true },
}

local function getMode(id)
	for _, mode in ipairs(MODES) do
		if mode.id == id then
			return mode
		end
	end

	return MODES[1]
end

local NO_TICKER_HINT = "Load a ticker to trade"
local CONTROL_HEIGHT = 28
local PILL_PADDING = 10
local LIMIT_BOX_WIDTH = 90

local OrderTicketModule = {}
OrderTicketModule.__index = OrderTicketModule

local function formatPreset(amount)
	return amount >= 1000 and string.format("$%dK", amount / 1000) or "$" .. amount
end

local function makeGroup(name, parent, layoutOrder)
	local group = UIKit.makeFrame(name, parent)
	group.LayoutOrder = layoutOrder
	group.AutomaticSize = Enum.AutomaticSize.X
	group.Size = UDim2.fromOffset(0, CONTROL_HEIGHT)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = group

	return group
end

local function makePill(name, parent, layoutOrder, text, font)
	local pill = Instance.new("TextButton")
	pill.Name = name
	pill.LayoutOrder = layoutOrder
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromScale(0, 1)
	pill.AutoButtonColor = false
	pill.BorderSizePixel = 0
	pill.BackgroundColor3 = Theme.Colors.Raised
	pill.FontFace = font or Theme.Fonts.Mono
	pill.TextSize = Theme.TextSize.Body
	pill.TextColor3 = Theme.Colors.Text
	pill.Text = text
	pill.Parent = parent
	UIKit.addCorner(pill)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, PILL_PADDING)
	padding.PaddingRight = UDim.new(0, PILL_PADDING)
	padding.Parent = pill

	return pill, UIKit.addStroke(pill)
end

local function makeCaption(name, parent, layoutOrder, text)
	local caption =
		UIKit.makeLabel(name, parent, Theme.Fonts.UISemibold, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	caption.LayoutOrder = layoutOrder
	caption.AutomaticSize = Enum.AutomaticSize.X
	caption.Size = UDim2.fromScale(0, 1)
	caption.TextTruncate = Enum.TextTruncate.None
	caption.Text = text

	return caption
end

-- options = {
--   parent, layoutOrder,
--   getTicker: () -> string ("" when none is loaded),
--   getPrice: () -> number,
--   getPosition: () -> number (shares held of the current ticker),
--   onOrderPlaced: () -> (),
-- }
function OrderTicketModule.new(options)
	local self = setmetatable({}, OrderTicketModule)

	self.options = options
	self.mode = "Market"
	self.isBusy = false
	self.pricesTicker = nil -- the ticker the price boxes were last filled in for

	local frame = UIKit.makePanel("OrderTicket", options.parent)
	frame.LayoutOrder = options.layoutOrder
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Size = UDim2.fromScale(1, 0)
	self.frame = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame

	-- Groups wrap onto a second line on a narrow screen
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Wraps = true
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 16)
	layout.Parent = frame

	-- Order type
	local typeGroup = makeGroup("Type", frame, 1)
	self.typePills = {}

	for index, mode in ipairs(MODES) do
		local pill, stroke = makePill(mode.id, typeGroup, index, mode.label or mode.id, Theme.Fonts.UISemibold)

		self.typePills[mode.id] = { button = pill, stroke = stroke }

		pill.MouseButton1Click:Connect(function()
			self:setMode(mode.id)
		end)
	end

	-- The prices the order types take: a stop first, then a limit (a
	-- stop-limit reads "stop at, then limit")
	self.stopGroup, self.stopBox = self:makePriceField("Stop", "Stop $", 2)
	self.limitGroup, self.limitBox = self:makePriceField("Limit", "Limit $", 3)

	-- Buy dollar amounts
	local buyGroup = makeGroup("Buy", frame, 4)
	makeCaption("Caption", buyGroup, 1, "Buy")
	self.buyPills = {}

	for index, amount in ipairs(BUY_PRESETS) do
		local pill, stroke = makePill("Buy_" .. amount, buyGroup, index + 1, formatPreset(amount))

		pill.TextColor3 = Theme.Colors.Up
		stroke.Color = Theme.Colors.Up
		table.insert(self.buyPills, { button = pill, stroke = stroke })

		pill.MouseButton1Click:Connect(function()
			self:buy(amount)
		end)
	end

	-- Sell shares of the position
	local sellGroup = makeGroup("Sell", frame, 5)
	makeCaption("Caption", sellGroup, 1, "Sell")
	self.sellPills = {}

	for index, fraction in ipairs(SELL_PRESETS) do
		local pill, stroke = makePill("Sell_" .. index, sellGroup, index + 1, string.format("%d%%", fraction * 100))

		table.insert(self.sellPills, { button = pill, stroke = stroke })

		pill.MouseButton1Click:Connect(function()
			self:sell(fraction)
		end)
	end

	local status = UIKit.makeLabel("Status", frame, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	status.LayoutOrder = 6
	status.AutomaticSize = Enum.AutomaticSize.X
	status.Size = UDim2.fromOffset(0, CONTROL_HEIGHT)
	status.TextTruncate = Enum.TextTruncate.None
	self.status = status

	Player:GetAttributeChangedSignal("Level"):Connect(function()
		self:update()
	end)

	self:update()

	return self
end

-- A price box with its caption and nudges from the last price, in a group
-- of its own. Returns the group and the box.
function OrderTicketModule:makePriceField(name, caption, layoutOrder)
	local group = makeGroup(name, self.frame, layoutOrder)

	makeCaption("Caption", group, 1, caption)

	local box = Instance.new("TextBox")
	box.Name = name .. "Price"
	box.LayoutOrder = 2
	box.Size = UDim2.new(0, LIMIT_BOX_WIDTH, 1, 0)
	box.BackgroundColor3 = Theme.Colors.Raised
	box.BorderSizePixel = 0
	box.FontFace = Theme.Fonts.Mono
	box.TextSize = Theme.TextSize.Body
	box.TextColor3 = Theme.Colors.Text
	box.PlaceholderColor3 = Theme.Colors.TextMuted
	box.PlaceholderText = "0.00"
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Parent = group
	UIKit.addCorner(box)
	UIKit.addStroke(box)

	box.FocusLost:Connect(function()
		local price = self:readPrice(box)

		box.Text = price and string.format("%.2f", price) or ""
	end)

	for index, nudge in ipairs(PRICE_NUDGES) do
		local text = nudge == 0 and "Last" or string.format("%+g%%", nudge * 100)
		local pill = makePill("Nudge_" .. index, group, 2 + index, text)

		pill.TextSize = Theme.TextSize.Caption
		pill.TextColor3 = Theme.Colors.TextMuted

		pill.MouseButton1Click:Connect(function()
			local lastPrice = self.options.getPrice()

			if lastPrice and lastPrice > 0 then
				box.Text = string.format("%.2f", lastPrice * (1 + nudge))
			end
		end)
	end

	return group, box
end

function OrderTicketModule:isUnlocked(modeId)
	local feature = getMode(modeId).feature

	return not feature or Progression.isUnlocked(Player:GetAttribute("Level") or 1, feature)
end

-- A box's typed price, ignoring "$" and commas; nil unless positive
function OrderTicketModule:readPrice(box)
	local price = tonumber((string.gsub(box.Text, "[^%d%.]", "")))

	return price and price > 0 and math.round(price * 100) / 100 or nil
end

-- The current mode's prices: { stop?, limit? }, and the name of the first
-- one that's missing
function OrderTicketModule:getPrices()
	local mode = getMode(self.mode)
	local prices = {
		stop = mode.stop and self:readPrice(self.stopBox) or nil,
		limit = mode.limit and self:readPrice(self.limitBox) or nil,
	}

	if mode.stop and not prices.stop then
		return prices, "stop"
	elseif mode.limit and not prices.limit then
		return prices, "limit"
	end

	return prices, nil
end

function OrderTicketModule:setStatus(text, color)
	self.status.Text = text
	self.status.TextColor3 = color or Theme.Colors.TextMuted
end

function OrderTicketModule:setMode(modeId)
	local mode = getMode(modeId)

	if not self:isUnlocked(modeId) then
		self:setStatus(
			string.format("%s orders: %s", mode.label or mode.id, Progression.getLockedMessage(mode.feature))
		)

		return
	end

	self.mode = modeId
	self:update()
end

-- Redraws for the current ticker, price, position and level
function OrderTicketModule:update()
	local options = self.options
	local ticker = options.getTicker()
	local hasTicker = ticker ~= ""

	if not self:isUnlocked(self.mode) then
		self.mode = "Market"
	end

	for _, mode in ipairs(MODES) do
		local pill = self.typePills[mode.id]
		local isActive = mode.id == self.mode
		local label = mode.label or mode.id

		pill.button.BackgroundTransparency = isActive and 0 or 1
		pill.button.TextColor3 = isActive and Theme.Colors.Text or Theme.Colors.TextMuted
		pill.button.Text = self:isUnlocked(mode.id) and label
			or string.format("%s · Lv %d", label, Progression.FEATURES[mode.feature])
		pill.stroke.Enabled = isActive
	end

	local mode = getMode(self.mode)

	self.stopGroup.Visible = mode.stop == true
	self.limitGroup.Visible = mode.limit == true

	-- A new ticker starts its prices at the last price
	if (mode.stop or mode.limit) and hasTicker and self.pricesTicker ~= ticker and options.getPrice() > 0 then
		local lastPrice = string.format("%.2f", options.getPrice())

		self.stopBox.Text = lastPrice
		self.limitBox.Text = lastPrice
		self.pricesTicker = ticker
	end

	for _, pill in ipairs(self.buyPills) do
		pill.button.TextColor3 = hasTicker and Theme.Colors.Up or Theme.Colors.TextDisabled
		pill.stroke.Color = pill.button.TextColor3
	end

	local hasPosition = hasTicker and options.getPosition() > 0

	for _, pill in ipairs(self.sellPills) do
		pill.button.TextColor3 = hasPosition and Theme.Colors.Down or Theme.Colors.TextDisabled
		pill.stroke.Color = pill.button.TextColor3
	end

	if not hasTicker then
		self:setStatus(NO_TICKER_HINT)
	elseif self.status.Text == NO_TICKER_HINT then
		self:setStatus("")
	end
end

-- Market orders fill at the live price, so they need the market open
-- (crypto and the Roblox market trade around the clock); the other types
-- can wait for it
function OrderTicketModule:canTradeNow(ticker)
	if
		self.mode ~= "Market"
		or Instruments.tradesAroundTheClock(ticker)
		or MarketHoursModule.getMarketStatus(os.time())
	then
		return true
	end

	local hint = self:isUnlocked("Limit") and " Use a limit or stop order to trade once it opens." or ""

	self:setStatus("The market is closed." .. hint, Theme.Colors.Down)

	return false
end

-- The prices are there, or the status says which to enter
function OrderTicketModule:checkPrices()
	local prices, missing = self:getPrices()

	if missing then
		self:setStatus(string.format("Enter a %s price first.", missing), Theme.Colors.Down)

		return nil
	end

	return prices
end

function OrderTicketModule:submit(action, shares, prices)
	local ticker = self.options.getTicker()
	local result

	self.isBusy = true

	if self.mode == "Limit" then
		result = PlaceLimitOrderEvent:InvokeServer(action, ticker, shares, prices.limit)
	elseif self.mode == "Stop" or self.mode == "StopLimit" then
		result = PlaceStopOrderEvent:InvokeServer(action, ticker, shares, prices.stop, prices.limit)
	else
		result = PlayerOrderEvent:InvokeServer(action, ticker, shares)
	end

	self.isBusy = false

	if result and result.success then
		self:setStatus(result.message, Theme.Colors.Up)
		self.options.onOrderPlaced()
	else
		self:setStatus((result and result.message) or "Order failed. Try again.", Theme.Colors.Down)
	end
end

function OrderTicketModule:buy(dollarAmount)
	local ticker = self.options.getTicker()

	if self.isBusy or ticker == "" or not self:canTradeNow(ticker) then
		return
	end

	local prices = self:checkPrices()

	if not prices then
		return
	end

	-- Shares at the price it would fill at: the limit, else the stop, else the market
	local price = prices.limit or prices.stop or self.options.getPrice()

	if not price or price <= 0 then
		self:setStatus("Price unavailable. Try again.", Theme.Colors.Down)

		return
	end

	local shares = math.floor(dollarAmount / price)

	if shares < 1 then
		self:setStatus(
			string.format("%s buys less than one share at %s.", formatPreset(dollarAmount), NumberModule.format(price)),
			Theme.Colors.Down
		)

		return
	end

	self:submit("Buy", shares, prices)
end

function OrderTicketModule:sell(fraction)
	local ticker = self.options.getTicker()
	local position = self.options.getPosition()

	if self.isBusy or ticker == "" or position <= 0 or not self:canTradeNow(ticker) then
		return
	end

	local prices = self:checkPrices()

	if not prices then
		return
	end

	-- At least one share, and all of it at 100%
	local shares = fraction >= 1 and position or math.max(1, math.floor(position * fraction))

	self:submit("Sell", shares, prices)
end

return OrderTicketModule
