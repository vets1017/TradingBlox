-- GameBannerModule.luau
--
-- The Trade screen's banner for a Roblox-market game, under the header: its
-- icon, name, genre and creator, players online, and what its price is - a
-- simulation, said plainly (GDD §6). Hidden for real-world tickers.
--
-- Client-only. TradeController calls show(marketData) when a game loads and
-- hide() otherwise.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local RobloxMarket = require(ReplicatedStorage.Config.RobloxMarket)

local ICON_SIZE = 84
local PADDING = 12
local CHIP_HEIGHT = 22

local DELISTED_NOTE = "Delisted: this game left the Roblox market, so trading has stopped and holdings "
	.. "were paid out at its last price."

local GameBannerModule = {}
GameBannerModule.__index = GameBannerModule

local function makeChip(name, parent, layoutOrder, color)
	local chip = UIKit.makeLabel(name, parent, Theme.Fonts.UISemibold, Theme.TextSize.Caption, color)
	chip.LayoutOrder = layoutOrder
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, CHIP_HEIGHT)
	chip.BackgroundTransparency = 0
	chip.BackgroundColor3 = Theme.Colors.Raised
	chip.TextTruncate = Enum.TextTruncate.None
	UIKit.addCorner(chip)

	local stroke = UIKit.addStroke(chip, color)
	stroke.Transparency = 0.5

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = chip

	return chip
end

-- options = { parent, layoutOrder }
function GameBannerModule.new(options)
	local self = setmetatable({}, GameBannerModule)

	local frame = UIKit.makePanel("GameBanner", options.parent)
	frame.LayoutOrder = options.layoutOrder
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Visible = false
	self.frame = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PADDING)
	padding.PaddingBottom = UDim.new(0, PADDING)
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, PADDING)
	padding.Parent = frame

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	icon.BackgroundColor3 = Theme.Colors.Raised
	icon.BorderSizePixel = 0
	icon.Parent = frame
	UIKit.addCorner(icon, UDim.new(0, 8))
	self.icon = icon

	-- Everything else stacks to the right of the icon
	local textX = ICON_SIZE + PADDING
	local details = UIKit.makeFrame("Details", frame)
	details.Position = UDim2.fromOffset(textX, 0)
	details.Size = UDim2.new(1, -textX, 0, 0)
	details.AutomaticSize = Enum.AutomaticSize.Y

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = details

	local name = UIKit.makeLabel("GameName", details, Theme.Fonts.UIBold, Theme.TextSize.Display, Theme.Colors.Text)
	name.LayoutOrder = 1
	name.Size = UDim2.new(1, 0, 0, 28)
	self.name = name

	local subtitle = UIKit.makeLabel("Subtitle", details, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
	subtitle.LayoutOrder = 2
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	self.subtitle = subtitle

	local chips = UIKit.makeFrame("Chips", details)
	chips.LayoutOrder = 3
	chips.Size = UDim2.new(1, 0, 0, CHIP_HEIGHT)

	local chipsLayout = Instance.new("UIListLayout")
	chipsLayout.FillDirection = Enum.FillDirection.Horizontal
	chipsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipsLayout.Padding = UDim.new(0, 6)
	chipsLayout.Parent = chips

	self.playersChip = makeChip("Players", chips, 1, Theme.Colors.Text)
	self.priceChip = makeChip("Simulated", chips, 2, Theme.Colors.Accent)

	local note = UIKit.makeLabel("Note", details, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	note.LayoutOrder = 4
	note.Size = UDim2.fromScale(1, 0)
	note.AutomaticSize = Enum.AutomaticSize.Y
	note.TextWrapped = true
	note.TextTruncate = Enum.TextTruncate.None
	self.note = note

	return self
end

-- `data` is GetMarketDataEvent's answer for a Roblox-market ticker
function GameBannerModule:show(data)
	local listed = RobloxMarket.getExperience(data.ticker)
	local observed = data.observed or {}
	local parts = {}

	if observed.genre then
		table.insert(parts, observed.genre)
	end

	if observed.creator then
		table.insert(parts, "by " .. observed.creator)
	end

	self.icon.Image = listed and string.format("rbxthumb://type=GameIcon&id=%d&w=150&h=150", listed.universeId) or ""
	self.name.Text = data.name or data.ticker
	self.subtitle.Text = #parts > 0 and table.concat(parts, " · ") or data.ticker
	self.playersChip.Text = observed.playing
			and string.format("%s playing now · observed", NumberModule.formatShares(observed.playing))
		or "Players unavailable"
	self.priceChip.TextColor3 = data.delisted and Theme.Colors.Down or Theme.Colors.Accent

	local note = RobloxMarket.SIMULATED_NOTE .. " " .. RobloxMarket.OBSERVED_NOTE

	if data.delisted then
		self.priceChip.Text = "Delisted"
		note = DELISTED_NOTE
	elseif data.opensAt then
		self.priceChip.Text = "Opens for trading in " .. MarketHoursModule.formatCountdown(data.opensAt - os.time())
		note = RobloxMarket.WARMUP_NOTE .. " " .. note
	else
		self.priceChip.Text = "Simulated price"
	end

	self.note.Text = note
	self.frame.Visible = true
end

function GameBannerModule:hide()
	self.frame.Visible = false
end

return GameBannerModule
