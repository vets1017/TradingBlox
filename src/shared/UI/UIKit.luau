-- UIKit.luau
--
-- Builders for UI made in code. Code-built UI is styled straight from Theme
-- tokens rather than ThemeRole tags (see CLAUDE.md, "Theme system"). Each
-- builder returns a plain instance for the caller to finish configuring.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)

local UIKit = {}

UIKit.CIRCLE = UDim.new(0.5, 0)

-- A transparent, borderless frame
function UIKit.makeFrame(name, parent)
	local frame = Instance.new("Frame")

	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent

	return frame
end

function UIKit.makeLabel(name, parent, font, textSize, color)
	local label = Instance.new("TextLabel")

	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = font
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent

	return label
end

function UIKit.addCorner(instance, radius)
	local corner = Instance.new("UICorner")

	corner.CornerRadius = radius or Theme.Radius
	corner.Parent = instance
end

function UIKit.addStroke(instance, color)
	local stroke = Instance.new("UIStroke")

	stroke.Color = color or Theme.Colors.Border
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance

	return stroke
end

-- A Panel-colored frame with the border and corners every panel has
function UIKit.makePanel(name, parent)
	local panel = UIKit.makeFrame(name, parent)

	panel.BackgroundTransparency = 0
	panel.BackgroundColor3 = Theme.Colors.Panel
	UIKit.addCorner(panel)
	UIKit.addStroke(panel)

	return panel
end

-- A Raised, outlined button sized to its text, for presets and toggles. Its
-- height comes from the parent (scale 1). Returns the button and its stroke;
-- the caller owns the colors from then on.
function UIKit.makePill(name, parent, text)
	local pill = Instance.new("TextButton")

	pill.Name = name
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromScale(0, 1)
	pill.AutoButtonColor = false
	pill.BorderSizePixel = 0
	pill.BackgroundColor3 = Theme.Colors.Raised
	pill.FontFace = Theme.Fonts.UISemibold
	pill.TextSize = Theme.TextSize.Caption
	pill.TextColor3 = Theme.Colors.Text
	pill.Text = text
	pill.Parent = parent
	UIKit.addCorner(pill)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = pill

	return pill, UIKit.addStroke(pill)
end

-- A filled circle centered on its Position
function UIKit.makeDot(name, parent, size, color)
	local dot = UIKit.makeFrame(name, parent)

	dot.BackgroundTransparency = 0
	dot.BackgroundColor3 = color
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(size, size)
	UIKit.addCorner(dot, UIKit.CIRCLE)

	return dot
end

-- A round headshot of any user. rbxthumb URLs load without a web request
-- from our side, so a list can show one per row.
function UIKit.makeAvatar(name, parent, userId, size)
	local avatar = Instance.new("ImageLabel")

	avatar.Name = name
	avatar.Size = UDim2.fromOffset(size, size)
	avatar.BackgroundColor3 = Theme.Colors.Raised
	avatar.BorderSizePixel = 0
	avatar.Parent = parent
	UIKit.addCorner(avatar, UIKit.CIRCLE)
	UIKit.setAvatarUser(avatar, userId)

	return avatar
end

function UIKit.setAvatarUser(avatar, userId)
	avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

return UIKit
