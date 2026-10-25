-- ThesisPanelModule.luau
--
-- The Trade screen's community section (GDD §2): how many players watch and
-- trade the loaded ticker, and their theses on it - bullish or bearish, a
-- time horizon, an optional target and text - with a composer to publish
-- your own. They're opinions, so the
-- section says "Simulated, not financial advice". An author's name opens
-- their profile; other players' theses can be reported.
--
-- Client-only. TradeController calls load(ticker) whenever a ticker loads.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local Navigation = require(ReplicatedStorage.Modules.Multi.Navigation)
local UIKit = require(ReplicatedStorage.UI.UIKit)
local Social = require(ReplicatedStorage.Config.Social)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetTickerThesesEvent = EventsFolder:WaitForChild("GetTickerThesesEvent")
local PublishThesisEvent = EventsFolder:WaitForChild("PublishThesisEvent")
local DeleteThesisEvent = EventsFolder:WaitForChild("DeleteThesisEvent")
local ReportThesisEvent = EventsFolder:WaitForChild("ReportThesisEvent")

local Player = Players.LocalPlayer

local CONTROL_HEIGHT = 28
local TARGET_BOX_WIDTH = 90
local TEXT_BOX_HEIGHT = 56
local AVATAR_SIZE = 20
local AUTHOR_META_WIDTH = 150
local RETRY_DELAY = 1.1 -- past the server's per-request cooldown when throttled
local CONFIRM_SECONDS = 3

local DEFAULT_DIRECTION = "Bullish"
local DEFAULT_HORIZON = "1M"
local DISCLAIMER = "Player opinions. Simulated, not financial advice."

local UP_HEX = Theme.Colors.Up:ToHex()
local DOWN_HEX = Theme.Colors.Down:ToHex()
local MUTED_HEX = Theme.Colors.TextMuted:ToHex()

local RICH_TEXT_ESCAPES = { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" }

local ThesisPanelModule = {}
ThesisPanelModule.__index = ThesisPanelModule

local function escape(text: string): string
	return (string.gsub(text, "[<>&]", RICH_TEXT_ESCAPES))
end

-- "3 min ago", "2 h ago", "just now"
local function formatAge(seconds)
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. " min ago"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. " h ago"
	end

	return math.floor(seconds / 86400) .. " d ago"
end

-- "Bullish · target $210.00 (+12.3% from $187.00) · 1 month · ends Nov 25"
local function describeCall(thesis, now)
	local isBullish = thesis.direction == "Bullish"
	local horizon = Social.getHorizon(thesis.horizon)
	local parts = {
		string.format('<font color="#%s"><b>%s</b></font>', isBullish and UP_HEX or DOWN_HEX, thesis.direction),
	}

	if thesis.targetPrice then
		table.insert(
			parts,
			string.format(
				"target %s (%+.1f%% from %s)",
				NumberModule.format(thesis.targetPrice),
				(thesis.targetPrice - thesis.priceAtPost) / thesis.priceAtPost * 100,
				NumberModule.format(thesis.priceAtPost)
			)
		)
	else
		table.insert(parts, "from " .. NumberModule.format(thesis.priceAtPost))
	end

	table.insert(parts, horizon and horizon.label or thesis.horizon)
	table.insert(parts, (thesis.endsAt > now and "ends " or "ended ") .. os.date("%b %d", thesis.endsAt))

	return table.concat(parts, " · ")
end

local function invoke(remote, ...)
	local success, result = pcall(remote.InvokeServer, remote, ...)

	if not success then
		warn("[ThesisPanelModule] " .. remote.Name .. " failed: " .. tostring(result))

		return nil
	end

	return result
end

-- A horizontal row of controls that wraps on a narrow screen
local function makeRow(name, parent, layoutOrder, padding)
	local row = UIKit.makeFrame(name, parent)
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.fromScale(1, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Wraps = true
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = row

	return row
end

-- A fixed-height, text-sized group inside a row
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

local function makeTextBox(name, parent)
	local box = Instance.new("TextBox")
	box.Name = name
	box.BackgroundColor3 = Theme.Colors.Raised
	box.BorderSizePixel = 0
	box.FontFace = Theme.Fonts.UI
	box.TextSize = Theme.TextSize.Body
	box.TextColor3 = Theme.Colors.Text
	box.PlaceholderColor3 = Theme.Colors.TextMuted
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Parent = parent
	UIKit.addCorner(box)
	UIKit.addStroke(box)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = box

	return box
end

-- A filled button: Accent for the main action, Raised otherwise
local function makeButton(name, parent, layoutOrder, text, isPrimary)
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = layoutOrder
	button.AutomaticSize = Enum.AutomaticSize.X
	button.Size = UDim2.fromOffset(0, CONTROL_HEIGHT)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = isPrimary and Theme.Colors.Accent or Theme.Colors.Raised
	button.FontFace = isPrimary and Theme.Fonts.UIBold or Theme.Fonts.UISemibold
	button.TextSize = Theme.TextSize.Body
	button.TextColor3 = isPrimary and Theme.Colors.Background or Theme.Colors.Text -- dark on Accent reads better
	button.Text = text
	button.Parent = parent
	UIKit.addCorner(button)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = button

	return button
end

-- options = {
--   parent, layoutOrder,
--   getPrice: () -> number (the loaded ticker's last price, 0 if unknown),
-- }
function ThesisPanelModule.new(options)
	local self = setmetatable({}, ThesisPanelModule)

	self.options = options
	self.ticker = nil
	self.data = nil -- the last GetTickerThesesEvent answer
	self.requestId = 0
	self.isBusy = false
	self.direction = DEFAULT_DIRECTION
	self.horizon = DEFAULT_HORIZON

	local frame = UIKit.makePanel("Theses", options.parent)
	frame.LayoutOrder = options.layoutOrder
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Size = UDim2.fromScale(1, 0)
	self.frame = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = frame

	-- Header: title on the left, the Write button on the right
	local header = UIKit.makeFrame("Header", frame)
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, CONTROL_HEIGHT)

	local title = UIKit.makeLabel("Title", header, Theme.Fonts.UIBold, Theme.TextSize.Title, Theme.Colors.Text)
	title.Size = UDim2.new(1, -160, 1, 0)
	title.Text = "Community"
	self.title = title

	local writeButton = makeButton("Write", header, 0, "Write a thesis", true)
	writeButton.AnchorPoint = Vector2.new(1, 0)
	writeButton.Position = UDim2.fromScale(1, 0)
	self.writeButton = writeButton

	local summary = UIKit.makeLabel("Summary", frame, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	summary.LayoutOrder = 2
	summary.Size = UDim2.new(1, 0, 0, 16)
	summary.RichText = true
	summary.Text = DISCLAIMER
	self.summary = summary

	self:buildComposer(frame)

	local list = UIKit.makeFrame("List", frame)
	list.LayoutOrder = 4
	list.Size = UDim2.fromScale(1, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = list
	self.list = list

	local message = UIKit.makeLabel("Message", frame, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.TextMuted)
	message.LayoutOrder = 5
	message.Size = UDim2.new(1, 0, 0, 20)
	message.Text = "Load a ticker to see theses on it."
	self.message = message

	writeButton.MouseButton1Click:Connect(function()
		if self.ticker and self.data and not self.data.openThesisId then
			self:setComposerOpen(not self.composer.Visible)
		end
	end)

	self:updateWriteButton()

	return self
end

function ThesisPanelModule:buildComposer(frame)
	local composer = UIKit.makeFrame("Composer", frame)
	composer.LayoutOrder = 3
	composer.Size = UDim2.fromScale(1, 0)
	composer.AutomaticSize = Enum.AutomaticSize.Y
	composer.Visible = false
	self.composer = composer

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = composer

	local controls = makeRow("Controls", composer, 1, 16)

	-- Direction
	local directionGroup = makeGroup("Direction", controls, 1)
	makeCaption("Caption", directionGroup, 0, "Call")
	self.directionPills = {}

	for index, direction in ipairs(Social.THESIS_DIRECTIONS) do
		local pill, stroke = UIKit.makePill("Direction_" .. direction, directionGroup, direction)
		pill.LayoutOrder = index
		self.directionPills[direction] = { button = pill, stroke = stroke }

		pill.MouseButton1Click:Connect(function()
			self.direction = direction
			self:updatePills()
		end)
	end

	-- Horizon
	local horizonGroup = makeGroup("Horizon", controls, 2)
	makeCaption("Caption", horizonGroup, 0, "Horizon")
	self.horizonPills = {}

	for index, horizon in ipairs(Social.THESIS_HORIZONS) do
		local pill, stroke = UIKit.makePill("Horizon_" .. horizon.id, horizonGroup, horizon.id)
		pill.LayoutOrder = index
		self.horizonPills[horizon.id] = { button = pill, stroke = stroke }

		pill.MouseButton1Click:Connect(function()
			self.horizon = horizon.id
			self:updatePills()
		end)
	end

	-- Target, optional
	local targetGroup = makeGroup("Target", controls, 3)
	makeCaption("Caption", targetGroup, 0, "Target $")

	local targetBox = makeTextBox("TargetPrice", targetGroup)
	targetBox.LayoutOrder = 1
	targetBox.Size = UDim2.new(0, TARGET_BOX_WIDTH, 1, 0)
	targetBox.FontFace = Theme.Fonts.Mono
	targetBox.PlaceholderText = "optional"
	self.targetBox = targetBox
	self.priceCaption = makeCaption("Now", targetGroup, 2, "")

	-- Text, for players whose accounts allow chat
	local textBox = makeTextBox("Text", composer)
	textBox.LayoutOrder = 2
	textBox.Size = UDim2.new(1, 0, 0, TEXT_BOX_HEIGHT)
	textBox.TextWrapped = true
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.TextYAlignment = Enum.TextYAlignment.Top
	textBox.PlaceholderText = string.format("Why? Optional, up to %d characters.", Social.THESIS_TEXT_MAX)
	self.textBox = textBox

	local textPadding = textBox:FindFirstChildOfClass("UIPadding")
	textPadding.PaddingTop = UDim.new(0, 6)
	textPadding.PaddingBottom = UDim.new(0, 6)

	local textNote =
		UIKit.makeLabel("TextNote", composer, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	textNote.LayoutOrder = 2
	textNote.Size = UDim2.new(1, 0, 0, 16)
	textNote.Text = "Text needs chat turned on for your account. You can still publish your call."
	textNote.Visible = false
	self.textNote = textNote

	-- Publish, Cancel, then the status (or the character count)
	local actions = makeRow("Actions", composer, 3, 8)
	local publishButton = makeButton("Publish", actions, 1, "Publish", true)
	local cancelButton = makeButton("Cancel", actions, 2, "Cancel", false)

	local status = makeCaption("Status", actions, 3, "")
	status.Size = UDim2.fromOffset(0, CONTROL_HEIGHT)
	status.FontFace = Theme.Fonts.UI
	self.status = status

	-- Keeps the text within the limit as it's typed
	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = textBox.Text
		local length = utf8.len(text) or #text

		if length > Social.THESIS_TEXT_MAX then
			textBox.Text = string.sub(text, 1, (utf8.offset(text, Social.THESIS_TEXT_MAX + 1) or #text + 1) - 1)

			return
		end

		if not self.isBusy then
			self:setStatus(length > 0 and string.format("%d/%d", length, Social.THESIS_TEXT_MAX) or "")
		end
	end)

	publishButton.MouseButton1Click:Connect(function()
		self:publish()
	end)

	cancelButton.MouseButton1Click:Connect(function()
		self:setComposerOpen(false)
	end)

	self:updatePills()
end

function ThesisPanelModule:updatePills()
	for direction, pill in pairs(self.directionPills) do
		local isActive = direction == self.direction
		local activeColor = direction == "Bullish" and Theme.Colors.Up or Theme.Colors.Down

		pill.button.TextColor3 = isActive and activeColor or Theme.Colors.TextMuted
		pill.stroke.Color = isActive and activeColor or Theme.Colors.Border
	end

	for horizonId, pill in pairs(self.horizonPills) do
		local isActive = horizonId == self.horizon

		pill.button.TextColor3 = isActive and Theme.Colors.Text or Theme.Colors.TextMuted
		pill.stroke.Color = isActive and Theme.Colors.Accent or Theme.Colors.Border
	end
end

function ThesisPanelModule:setStatus(text, color)
	self.status.Text = text
	self.status.TextColor3 = color or Theme.Colors.TextMuted
end

-- Opening refreshes the current price beside the target; closing clears
-- the draft
function ThesisPanelModule:setComposerOpen(isOpen)
	self.composer.Visible = isOpen

	local canUseText = self.data and self.data.canUseText

	self.textBox.Visible = canUseText == true
	self.textNote.Visible = not canUseText

	if isOpen then
		local price = self.options.getPrice()

		self.priceCaption.Text = price and price > 0 and ("now " .. NumberModule.format(price)) or ""

		return
	end

	self.direction = DEFAULT_DIRECTION
	self.horizon = DEFAULT_HORIZON
	self.targetBox.Text = ""
	self.textBox.Text = ""
	self:setStatus("")
	self:updatePills()
end

-- The write button reads "Thesis open" while you have one on this ticker:
-- one open thesis per ticker
function ThesisPanelModule:updateWriteButton()
	local hasOpenThesis = self.data and self.data.openThesisId ~= nil

	self.writeButton.Text = hasOpenThesis and "Your thesis is open" or "Write a thesis"
	self.writeButton.BackgroundColor3 = hasOpenThesis and Theme.Colors.Raised or Theme.Colors.Accent
	self.writeButton.TextColor3 = hasOpenThesis and Theme.Colors.TextMuted or Theme.Colors.Background
	self.writeButton.Visible = self.ticker ~= nil and self.data ~= nil
end

function ThesisPanelModule:clearList()
	for _, child in ipairs(self.list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function ThesisPanelModule:renderThesis(index, thesis, now)
	local isYours = thesis.userId == Player.UserId

	local card = UIKit.makeFrame("Thesis_" .. index, self.list)
	card.LayoutOrder = index
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundTransparency = 0
	card.BackgroundColor3 = Theme.Colors.Raised
	UIKit.addCorner(card)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = card

	-- Author: the name opens their profile; your own thesis has Delete
	local top = UIKit.makeFrame("Top", card)
	top.LayoutOrder = 1
	top.Size = UDim2.new(1, 0, 0, AVATAR_SIZE)

	UIKit.makeAvatar("Avatar", top, thesis.userId, AVATAR_SIZE)

	local author = Instance.new("TextButton")
	author.Name = "Author"
	author.Position = UDim2.fromOffset(AVATAR_SIZE + 8, 0)
	author.Size = UDim2.new(1, -(AVATAR_SIZE + 8 + AUTHOR_META_WIDTH), 1, 0)
	author.BackgroundTransparency = 1
	author.BorderSizePixel = 0
	author.FontFace = Theme.Fonts.UISemibold
	author.TextSize = Theme.TextSize.Body
	author.TextColor3 = isYours and Theme.Colors.Accent or Theme.Colors.Text
	author.TextXAlignment = Enum.TextXAlignment.Left
	author.TextTruncate = Enum.TextTruncate.AtEnd
	author.RichText = true
	author.Text = string.format(
		'%s%s <font color="#%s">@%s</font>',
		escape(thesis.displayName),
		isYours and " (you)" or "",
		MUTED_HEX,
		escape(thesis.username)
	)
	author.Parent = top

	author.MouseButton1Click:Connect(function()
		Navigation.openProfile(thesis.userId)
	end)

	local meta = UIKit.makeLabel("Age", top, Theme.Fonts.UI, Theme.TextSize.Caption, Theme.Colors.TextMuted)
	meta.AnchorPoint = Vector2.new(1, 0)
	meta.Position = UDim2.fromScale(1, 0)
	meta.Size = UDim2.new(0, AUTHOR_META_WIDTH, 1, 0)
	meta.TextXAlignment = Enum.TextXAlignment.Right
	meta.Text = formatAge(now - thesis.createdAt)

	-- Delete on your own theses, Report on everyone else's
	meta.Size = UDim2.new(0, AUTHOR_META_WIDTH - 60, 1, 0)
	meta.Position = UDim2.new(1, -60, 0, 0)

	if isYours then
		self:addConfirmButton(top, "Delete", "Sure?", Theme.Colors.Down, function()
			self:delete(thesis)
		end)
	else
		self:addConfirmButton(top, "Report", "Report?", Theme.Colors.TextMuted, function()
			self:report(thesis)
		end)
	end

	local call = UIKit.makeLabel("Call", card, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.Text)
	call.LayoutOrder = 2
	call.Size = UDim2.new(1, 0, 0, 18)
	call.RichText = true
	call.Text = describeCall(thesis, now)

	if thesis.text then
		-- Already filtered by the server; shown as plain text, never rich text
		local body = UIKit.makeLabel("Text", card, Theme.Fonts.UI, Theme.TextSize.Body, Theme.Colors.Text)
		body.LayoutOrder = 3
		body.Size = UDim2.fromScale(1, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.TextWrapped = true
		body.TextTruncate = Enum.TextTruncate.None
		body.Text = thesis.text
	end
end

-- A text button that acts on the second click; the first asks for
-- confirmation for a few seconds
function ThesisPanelModule:addConfirmButton(parent, text, confirmText, color, onConfirm)
	local button = Instance.new("TextButton")
	button.Name = text
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.fromScale(1, 0)
	button.Size = UDim2.new(0, 56, 1, 0)
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.FontFace = Theme.Fonts.UISemibold
	button.TextSize = Theme.TextSize.Caption
	button.TextColor3 = color
	button.TextXAlignment = Enum.TextXAlignment.Right
	button.Text = text
	button.Parent = parent

	local isConfirming = false

	button.MouseButton1Click:Connect(function()
		if self.isBusy then
			return
		end

		if not isConfirming then
			isConfirming = true
			button.Text = confirmText

			task.delay(CONFIRM_SECONDS, function()
				isConfirming = false

				if button.Parent then
					button.Text = text
				end
			end)

			return
		end

		onConfirm()
	end)
end

function ThesisPanelModule:render()
	self:clearList()
	self:updateWriteButton()

	local data = self.data

	if not data then
		self.summary.Text = DISCLAIMER
		self.message.Visible = true
		self.message.Text = "Couldn't load theses. Try reloading the ticker in a moment."

		return
	end

	local now = os.time()

	local stats = data.stats or {}
	local activity = ""

	if stats.watchers then
		activity ..= string.format("%s watching · ", NumberModule.formatShares(stats.watchers))
	end

	if stats.trades then
		activity ..= string.format(
			"%s %s in 2 days · ",
			NumberModule.formatShares(stats.trades),
			stats.trades == 1 and "trade" or "trades"
		)
	end

	self.title.Text = "Community · " .. data.ticker
	self.summary.Text = string.format(
		'%s<font color="#%s">%d bullish</font> · <font color="#%s">%d bearish</font> theses · %s',
		activity,
		UP_HEX,
		data.counts.Bullish,
		DOWN_HEX,
		data.counts.Bearish,
		DISCLAIMER
	)
	self.message.Visible = #data.theses == 0
	self.message.Text = string.format("No theses on %s yet. Publish the first one.", data.ticker)

	for index, thesis in ipairs(data.theses) do
		self:renderThesis(index, thesis, now)
	end
end

-- The server answers nil when throttled, so one retry after its cooldown.
-- Loading another ticker makes an older request drop its answer.
function ThesisPanelModule:load(ticker: string)
	if ticker ~= self.ticker then
		self.ticker = ticker
		self.data = nil
		self:setComposerOpen(false)
		self:clearList()
		self:updateWriteButton()
		self.title.Text = "Community · " .. ticker
		self.message.Visible = true
		self.message.Text = "Loading…"
	end

	self.requestId += 1

	local requestId = self.requestId
	local result = invoke(GetTickerThesesEvent, ticker)

	if result == nil then
		task.wait(RETRY_DELAY)

		if requestId ~= self.requestId then
			return
		end

		result = invoke(GetTickerThesesEvent, ticker)
	end

	if requestId ~= self.requestId then
		return
	end

	self.data = result
	self:render()
end

function ThesisPanelModule:publish()
	if self.isBusy or not self.ticker then
		return
	end

	local targetText = string.gsub(self.targetBox.Text, "[%s,%$]", "")
	local targetPrice = nil

	if targetText ~= "" then
		targetPrice = tonumber(targetText)

		if not targetPrice then
			self:setStatus("Enter the target as a number, like 210.50.", Theme.Colors.Down)

			return
		end
	end

	local text = nil

	if self.data and self.data.canUseText and self.textBox.Text ~= "" then
		text = self.textBox.Text
	end

	local ticker = self.ticker

	self.isBusy = true
	self:setStatus("Publishing…")

	local result = invoke(PublishThesisEvent, ticker, {
		direction = self.direction,
		horizon = self.horizon,
		targetPrice = targetPrice,
		text = text,
	})

	self.isBusy = false

	if ticker ~= self.ticker then
		return
	end

	if not result or not result.success then
		self:setStatus(result and result.message or "Couldn't reach the server. Try again.", Theme.Colors.Down)

		return
	end

	self:setComposerOpen(false)
	self:load(ticker)
end

-- The reported thesis is hidden for the reporter from then on
function ThesisPanelModule:report(thesis)
	local ticker = self.ticker

	self.isBusy = true

	local result = invoke(ReportThesisEvent, thesis.id, thesis.ticker)

	self.isBusy = false

	if ticker ~= self.ticker then
		return
	end

	if not result or not result.success then
		self.message.Visible = true
		self.message.Text = result and result.message or "Couldn't reach the server. Try again."

		return
	end

	self:load(ticker)

	if ticker == self.ticker then
		self.message.Visible = true
		self.message.Text = "Thanks for the report. That thesis is hidden for you now."
	end
end

function ThesisPanelModule:delete(thesis)
	local ticker = self.ticker

	self.isBusy = true

	local result = invoke(DeleteThesisEvent, thesis.id)

	self.isBusy = false

	if ticker ~= self.ticker then
		return
	end

	if not result or not result.success then
		self.message.Visible = true
		self.message.Text = result and result.message or "Couldn't reach the server. Try again."

		return
	end

	self:load(ticker)
end

return ThesisPanelModule
