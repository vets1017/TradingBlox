-- MarketPickerModule.luau
--
-- The Trade screen's market picker. A dropdown picks the market:
--   Stocks & crypto  real-world stocks, ETFs and crypto; type a ticker as before
--   Roblox market    Roblox games; search by name and pick one from a list with
--                    each game's icon, price, day change and players online
-- so nobody needs to know an RBX- ticker.
--
-- Client-only. TradeController owns loading: the picker calls
-- options.onSelect(ticker) and is told what loaded through showLoaded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local RobloxMarket = require(ReplicatedStorage.Config.RobloxMarket)
local Instruments = require(ReplicatedStorage.Config.Instruments)

local GetRobloxMarketEvent = ReplicatedStorage:WaitForChild("EventsFolder"):WaitForChild("GetRobloxMarketEvent")

local MARKET_BUTTON_WIDTH = 170
local SEARCH_WIDTH = 280
local GAP = 8
local MENU_WIDTH = 300
local MENU_OPTION_HEIGHT = 52
local RESULTS_WIDTH = 480
local RESULTS_MAX_HEIGHT = 384
local RESULT_ROW_HEIGHT = 48
local ICON_SIZE = 36
local PADDING = 10
local LISTING_CACHE_SECONDS = 60
local Z_INDEX = 20 -- TerminalGui renders by global ZIndex, so the dropdowns sit above every section

local MARKETS = {
	{
		id = "World",
		label = "Stocks & crypto",
		description = "Real-world stocks, ETFs and crypto. Type a ticker.",
		placeholder = "Ticker, e.g. AAPL or BTC-USD",
	},
	{
		id = "Roblox",
		label = "Roblox market",
		description = "Roblox games with simulated prices. Search by name.",
		placeholder = "Search Roblox games",
	},
}

local UP_HEX = Theme.Colors.Up:ToHex()
local DOWN_HEX = Theme.Colors.Down:ToHex()

local MarketPickerModule = {}
MarketPickerModule.__index = MarketPickerModule

-- How much of the input row the picker takes, for whatever sits after it
MarketPickerModule.ROW_WIDTH = MARKET_BUTTON_WIDTH + GAP + SEARCH_WIDTH

local function getMarket(id)
	for _, market in ipairs(MARKETS) do
		if market.id == id then
			return market
		end
	end

	return MARKETS[1]
end

-- 150392 -> "150K", 6341 -> "6.3K", 950 -> "950"
local function formatPlayers(count: number): string
	if count >= 1e6 then
		return string.format("%.1fM", count / 1e6)
	elseif count >= 1e5 then
		return string.format("%dK", math.floor(count / 1e3))
	elseif count >= 1e3 then
		return string.format("%.1fK", count / 1e3)
	end

	return tostring(count)
end

local function raise(root)
	root.ZIndex = Z_INDEX

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = Z_INDEX
		end
	end
end

local function isInside(guiObject, position: Vector2): boolean
	local topLeft = guiObject.AbsolutePosition
	local bottomRight = topLeft + guiObject.AbsoluteSize

	return guiObject.Visible
		and position.X >= topLeft.X
		and position.X <= bottomRight.X
		and position.Y >= topLeft.Y
		and position.Y <= bottomRight.Y
end

-- options = {
--   inputRow, input (the row's TextBox), overlayParent (where dropdowns go,
--   outside the scrolling screen), screen (the Trade screen), onSelect(ticker)
-- }
function MarketPickerModule.new(options)
	local self = setmetatable({}, MarketPickerModule)

	self.options = options
	self.input = options.input
	self.market = "World"
	self.loadedText = "" -- what the box showed for the loaded ticker
	self.listing = nil -- GetRobloxMarketEvent's rows
	self.listingAt = -math.huge
	self.isLoadingListing = false

	self:buildButton()
	self:buildMenu()
	self:buildResults()
	self:connect()
	self:setMarket("World", false)

	return self
end

function MarketPickerModule:buildButton()
	local button = Instance.new("TextButton")
	button.Name = "MarketButton"
	button.Position = UDim2.fromScale(0, 0)
	button.Size = UDim2.new(0, MARKET_BUTTON_WIDTH, 1, 0)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Theme.Colors.Raised
	button.FontFace = Theme.Fonts.UISemibold
	button.TextSize = Theme.TextSize.Body
	button.TextColor3 = Theme.Colors.Text
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Parent = self.options.inputRow
	UIKit.addCorner(button)
	UIKit.addStroke(button)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, PADDING)
	padding.Parent = button

	self.button = button

	-- The search box moves over to make room
	self.input.Position = UDim2.fromOffset(MARKET_BUTTON_WIDTH + GAP, 0)
	self.input.Size = UDim2.new(0, SEARCH_WIDTH, 1, 0)
end

function MarketPickerModule:buildMenu()
	local menu = UIKit.makePanel("MarketMenu", self.options.overlayParent)
	menu.Size = UDim2.fromOffset(MENU_WIDTH, 0)
	menu.AutomaticSize = Enum.AutomaticSize.Y
	menu.Visible = false

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = menu

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = menu

	self.menuOptions = {}

	for index, market in ipairs(MARKETS) do
		local option = Instance.new("TextButton")
		option.Name = "Market_" .. market.id
		option.LayoutOrder = index
		option.Size = UDim2.new(1, 0, 0, MENU_OPTION_HEIGHT)
		option.AutoButtonColor = false
		option.BorderSizePixel = 0
		option.BackgroundColor3 = Theme.Colors.Raised
		option.BackgroundTransparency = 1
		option.Text = ""
		option.Parent = menu
		UIKit.addCorner(option)

		local title = UIKit.makeLabel("Title", option, Theme.Fonts.UISemibold, Theme.TextSize.Body, Theme.Colors.Text)
		title.Position = UDim2.fromOffset(PADDING, 8)
		title.Size = UDim2.new(1, -PADDING * 2, 0, 18)
		title.Text = market.label

		local description =
			UIKit.makeLabel("Description", option, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
		description.Position = UDim2.fromOffset(PADDING, 27)
		description.Size = UDim2.new(1, -PADDING * 2, 0, 16)
		description.Text = market.description

		option.MouseEnter:Connect(function()
			option.BackgroundTransparency = 0
		end)

		option.MouseLeave:Connect(function()
			option.BackgroundTransparency = 1
		end)

		option.MouseButton1Click:Connect(function()
			self:closeMenu()
			self:setMarket(market.id, true)
		end)

		self.menuOptions[market.id] = title
	end

	raise(menu)
	self.menu = menu
end

function MarketPickerModule:buildResults()
	local results = UIKit.makePanel("RobloxResults", self.options.overlayParent)
	results.Size = UDim2.fromOffset(RESULTS_WIDTH, 0)
	results.AutomaticSize = Enum.AutomaticSize.Y
	results.Visible = false

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PADDING)
	padding.PaddingBottom = UDim.new(0, PADDING)
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, PADDING)
	padding.Parent = results

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = results

	local caption = UIKit.makeLabel("Caption", results, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	caption.LayoutOrder = 1
	caption.Size = UDim2.new(1, 0, 0, 16)
	caption.Text =
		string.format("%d Roblox games · simulated prices from public Roblox stats", #RobloxMarket.EXPERIENCES)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.LayoutOrder = 2
	list.Size = UDim2.fromScale(1, 0)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = Theme.Colors.TextDisabled
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = results

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local message = UIKit.makeLabel("Message", results, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
	message.LayoutOrder = 3
	message.Size = UDim2.new(1, 0, 0, 20)
	message.Visible = false

	self.results = results
	self.resultsList = list
	self.resultsMessage = message
end

function MarketPickerModule:connect()
	self.button.MouseButton1Click:Connect(function()
		if self.menu.Visible then
			self:closeMenu()
		else
			self:closeResults()
			self:openMenu()
		end
	end)

	self.input.Focused:Connect(function()
		if self.market == "Roblox" then
			self:openResults()
		end
	end)

	self.input:GetPropertyChangedSignal("Text"):Connect(function()
		if self.market == "Roblox" and self.results.Visible then
			self:renderResults()
		end
	end)

	-- Enter picks the best match; TradeController leaves Roblox mode to this
	self.input.FocusLost:Connect(function(enterPressed)
		if self.market == "Roblox" and enterPressed then
			local first = self:getMatches()[1]

			if first then
				self:select(first.ticker)
			end
		end
	end)

	-- A click anywhere outside the picker closes its dropdowns
	UserInputService.InputBegan:Connect(function(input)
		local isClick = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch

		if not isClick or not (self.menu.Visible or self.results.Visible) then
			return
		end

		local position = Vector2.new(input.Position.X, input.Position.Y)

		if
			not isInside(self.options.inputRow, position)
			and not isInside(self.menu, position)
			and not isInside(self.results, position)
		then
			self:closeMenu()
			self:closeResults()
		end
	end)

	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			self:closeMenu()
			self:closeResults()
		end
	end)

	local screen = self.options.screen

	screen:GetPropertyChangedSignal("Visible"):Connect(function()
		if not screen.Visible then
			self:closeMenu()
			self:closeResults()
		end
	end)

	-- The dropdowns hang under the row, which scrolls with the screen
	screen:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:placeOverlays()
	end)
end

-- Under the market button and the search box, in overlayParent's space
function MarketPickerModule:placeOverlays()
	local origin = self.options.overlayParent.AbsolutePosition
	local buttonPosition = self.button.AbsolutePosition
	local inputPosition = self.input.AbsolutePosition
	local below = self.input.AbsoluteSize.Y + 4

	self.menu.Position = UDim2.fromOffset(buttonPosition.X - origin.X, buttonPosition.Y + below - origin.Y)
	self.results.Position = UDim2.fromOffset(inputPosition.X - origin.X, inputPosition.Y + below - origin.Y)
end

function MarketPickerModule:openMenu()
	for id, title in pairs(self.menuOptions) do
		title.TextColor3 = id == self.market and Theme.Colors.Accent or Theme.Colors.Text
	end

	self:placeOverlays()
	self.menu.Visible = true
end

function MarketPickerModule:closeMenu()
	self.menu.Visible = false
end

function MarketPickerModule:getMarket(): string
	return self.market
end

-- Switching by hand clears the box and, for the Roblox market, opens the
-- list straight away
function MarketPickerModule:setMarket(id: string, isByPlayer: boolean)
	local market = getMarket(id)

	self.market = market.id
	self.button.Text = market.label .. "  ▾"
	self.input.PlaceholderText = market.placeholder

	if not isByPlayer then
		return
	end

	self.input.Text = ""

	if market.id == "Roblox" then
		self.input:CaptureFocus()
		self:openResults()
	else
		self:closeResults()
		self.input:CaptureFocus()
	end
end

-- After TradeController loads a ticker (picked here or opened from anywhere
-- else): the picker follows its market, and a game shows by name
function MarketPickerModule:showLoaded(ticker: string)
	local isRoblox = Instruments.isRoblox(ticker)
	local listed = isRoblox and RobloxMarket.getExperience(ticker)

	self:setMarket(isRoblox and "Roblox" or "World", false)
	self.loadedText = listed and listed.name or ticker
	self.input.Text = self.loadedText
end

function MarketPickerModule:loadListing()
	if self.isLoadingListing or os.clock() - self.listingAt < LISTING_CACHE_SECONDS then
		return
	end

	self.isLoadingListing = true

	local success, rows = pcall(GetRobloxMarketEvent.InvokeServer, GetRobloxMarketEvent)

	self.isLoadingListing = false

	if success and rows then
		self.listing = rows
		self.listingAt = os.clock()
	end
end

-- The listing filtered by the search box, matching a game's name or ticker.
-- An empty box, or one still showing the loaded game, lists every game.
function MarketPickerModule:getMatches()
	local query = string.lower((string.gsub(self.input.Text, "^%s+", "")))
	local showsAll = query == "" or query == string.lower(self.loadedText)
	local matches = {}

	for _, row in ipairs(self.listing or {}) do
		if
			showsAll
			or string.find(string.lower(row.name), query, 1, true)
			or string.find(string.lower(row.ticker), query, 1, true)
		then
			table.insert(matches, row)
		end
	end

	return matches
end

function MarketPickerModule:openResults()
	self:placeOverlays()
	self.results.Visible = true
	self:renderResults()

	if os.clock() - self.listingAt >= LISTING_CACHE_SECONDS then
		task.spawn(function()
			self:loadListing()

			if self.results.Visible then
				self:renderResults()
			end
		end)
	end
end

-- Closing without a pick puts the loaded game back in the box
function MarketPickerModule:closeResults()
	self.results.Visible = false

	if self.market == "Roblox" and self.input.Text == "" then
		self.input.Text = self.loadedText
	end
end

function MarketPickerModule:select(ticker: string)
	self:closeResults()
	self.input:ReleaseFocus()
	self.options.onSelect(ticker)
end

function MarketPickerModule:createRow(index, row)
	local listed = RobloxMarket.getExperience(row.ticker)
	local change = row.prevClose and row.prevClose ~= 0 and (row.price - row.prevClose) / row.prevClose * 100

	local button = Instance.new("TextButton")
	button.Name = "Game_" .. row.ticker
	button.LayoutOrder = index
	button.Size = UDim2.new(1, -6, 0, RESULT_ROW_HEIGHT)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Theme.Colors.Raised
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Parent = self.resultsList
	UIKit.addCorner(button)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 6, 0.5, 0)
	icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	icon.BackgroundColor3 = Theme.Colors.Raised
	icon.BorderSizePixel = 0
	icon.Image = listed and string.format("rbxthumb://type=GameIcon&id=%d&w=150&h=150", listed.universeId) or ""
	icon.Parent = button
	UIKit.addCorner(icon)

	local textX = 6 + ICON_SIZE + 10

	local name = UIKit.makeLabel("GameName", button, Theme.Fonts.UISemibold, Theme.TextSize.Body, Theme.Colors.Text)
	name.Position = UDim2.fromOffset(textX, 6)
	name.Size = UDim2.new(1, -(textX + 150), 0, 18)
	name.Text = row.name

	local players = UIKit.makeLabel("Players", button, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	players.Position = UDim2.fromOffset(textX, 25)
	players.Size = UDim2.new(1, -(textX + 150), 0, 16)
	players.Text = string.format("%s · %s playing", row.ticker, formatPlayers(row.playing))

	local price = UIKit.makeLabel("Price", button, Theme.Fonts.Mono, Theme.TextSize.Body, Theme.Colors.Text)
	price.AnchorPoint = Vector2.new(1, 0)
	price.Position = UDim2.new(1, -8, 0, 6)
	price.Size = UDim2.fromOffset(140, 18)
	price.TextXAlignment = Enum.TextXAlignment.Right
	price.Text = NumberModule.format(row.price)

	local changeLabel =
		UIKit.makeLabel("Change", button, Theme.Fonts.Mono, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	changeLabel.AnchorPoint = Vector2.new(1, 0)
	changeLabel.Position = UDim2.new(1, -8, 0, 25)
	changeLabel.Size = UDim2.fromOffset(140, 16)
	changeLabel.TextXAlignment = Enum.TextXAlignment.Right
	changeLabel.RichText = true
	changeLabel.Text = change
			and string.format('<font color="#%s">%+.2f%%</font> today', change >= 0 and UP_HEX or DOWN_HEX, change)
		or "—"

	button.MouseEnter:Connect(function()
		button.BackgroundTransparency = 0
	end)

	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = 1
	end)

	button.MouseButton1Click:Connect(function()
		self:select(row.ticker)
	end)
end

function MarketPickerModule:renderResults()
	for _, child in ipairs(self.resultsList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local matches = self:getMatches()

	if not self.listing then
		self.resultsMessage.Text = self.isLoadingListing and "Loading games…"
			or "Couldn't load the Roblox market. Try again in a moment."
	elseif #self.listing == 0 then
		self.resultsMessage.Text = "The Roblox market opens within a few minutes."
	else
		self.resultsMessage.Text = "No games match that search."
	end

	self.resultsMessage.Visible = #matches == 0

	for index, row in ipairs(matches) do
		self:createRow(index, row)
	end

	self.resultsList.Size = UDim2.new(1, 0, 0, math.min(#matches * RESULT_ROW_HEIGHT, RESULTS_MAX_HEIGHT))
	raise(self.results)
end

return MarketPickerModule
