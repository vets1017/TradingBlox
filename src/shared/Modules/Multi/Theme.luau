-- Theme.luau
--
-- Single source of truth for TradingBlox's Axiom-style look. Colors, fonts
-- and text sizes are tokens; a UI element opts in by carrying a `ThemeRole`
-- string attribute, and Theme.apply stamps that role's properties onto it.
--
-- Roles deliberately leave out any property a controller changes at runtime
-- (up/down price colors, the active tab, toggle states, preset dimming), so
-- apply() and the controllers never write the same property - LocalScript
-- start order can't matter. Code that builds UI at runtime reads
-- Theme.Colors / Theme.Fonts directly instead of tagging.

local Theme = {}

local BUILDER_SANS = "rbxassetid://16658221428"
local ROBOTO_MONO = "rbxasset://fonts/families/RobotoMono.json"

Theme.Colors = {
	Background = Color3.fromRGB(8, 9, 13),
	Panel = Color3.fromRGB(14, 16, 22),
	Raised = Color3.fromRGB(21, 24, 34), -- buttons, inputs, headers, hover
	Border = Color3.fromRGB(35, 39, 54), -- strokes and 1px dividers
	Text = Color3.fromRGB(231, 233, 240),
	TextMuted = Color3.fromRGB(139, 144, 163),
	TextDisabled = Color3.fromRGB(91, 96, 115), -- e.g. Sell presets with no position
	Accent = Color3.fromRGB(154, 107, 255),
	AccentSoft = Color3.fromRGB(224, 170, 255), -- pale end of the mini-chart gradient
	AccentTint = Color3.fromRGB(30, 24, 48), -- in-the-money option rows
	Up = Color3.fromRGB(46, 189, 133),
	UpHover = Color3.fromRGB(39, 161, 113), -- Up at 85%
	Down = Color3.fromRGB(240, 74, 108),
	DownHover = Color3.fromRGB(204, 63, 92), -- Down at 85%
}

Theme.Fonts = {
	UI = Font.new(BUILDER_SANS),
	UISemibold = Font.new(BUILDER_SANS, Enum.FontWeight.SemiBold),
	UIBold = Font.new(BUILDER_SANS, Enum.FontWeight.Bold),
	Mono = Font.new(ROBOTO_MONO),
	MonoBold = Font.new(ROBOTO_MONO, Enum.FontWeight.Bold),
}

Theme.TextSize = {
	Caption = 12,
	Body = 13,
	Title = 15,
	Display = 24,
}

Theme.Radius = UDim.new(0, 4)

-- Values are token names. `Stroke` names the color of a 1px border;
-- `Corner = true` creates a UICorner when the element has none (an existing
-- UICorner on any tagged element is always flattened to Theme.Radius).
Theme.Roles = {
	-- Surfaces
	Screen = { BackgroundColor3 = "Background" },
	Panel = { BackgroundColor3 = "Panel", Stroke = "Border", Corner = true },
	PanelFlat = { BackgroundColor3 = "Panel" },
	Raised = { BackgroundColor3 = "Raised", Corner = true },
	Pill = { BackgroundColor3 = "Raised", Stroke = "Border", Corner = true },
	Divider = { BackgroundColor3 = "Border" },
	Guide = { BackgroundColor3 = "TextMuted" },
	AccentFill = { BackgroundColor3 = "Accent" },
	Scroll = {}, -- transparent scrolling lists: only the scrollbar is themed

	-- Inputs
	Input = {
		BackgroundColor3 = "Raised",
		Stroke = "Border",
		Corner = true,
		TextColor3 = "Text",
		PlaceholderColor3 = "TextMuted",
		FontFace = "UI",
		TextSize = "Body",
	},
	InputText = { TextColor3 = "Text", PlaceholderColor3 = "TextMuted", FontFace = "UI", TextSize = "Body" },

	-- Text
	Text = { TextColor3 = "Text", FontFace = "UI", TextSize = "Body" },
	TextStrong = { TextColor3 = "Text", FontFace = "UISemibold", TextSize = "Body" },
	TextMuted = { TextColor3 = "TextMuted", FontFace = "UI", TextSize = "Caption" },
	Heading = { TextColor3 = "Text", FontFace = "UIBold", TextSize = "Title" },
	HeadingUp = { TextColor3 = "Up", FontFace = "UIBold", TextSize = "Title" },
	HeadingDown = { TextColor3 = "Down", FontFace = "UIBold", TextSize = "Title" },
	Display = { TextColor3 = "Text", FontFace = "UIBold", TextSize = "Display" },
	Number = { TextColor3 = "Text", FontFace = "Mono", TextSize = "Body" },
	NumberLarge = { TextColor3 = "Text", FontFace = "Mono", TextSize = "Display" },

	-- Controls. Text on an Accent/Up/Down fill is Background: white on those
	-- fills is 2-3:1, dark is 5.6:1 or better
	Button = { BackgroundColor3 = "Raised", TextColor3 = "Text", FontFace = "UISemibold", TextSize = "Body", Corner = true },
	ButtonPrimary = { BackgroundColor3 = "Accent", TextColor3 = "Background", FontFace = "UIBold", TextSize = "Body", Corner = true },

	-- Controller-colored: font, size and shape only - a controller owns the colors
	NumberDynamic = { FontFace = "Mono", TextSize = "Body" },
	NumberLargeDynamic = { FontFace = "Mono", TextSize = "Display" },
	LabelDynamic = { FontFace = "UI", TextSize = "Body" },
	HeadingDynamic = { FontFace = "UISemibold", TextSize = "Title" },
	Tab = { FontFace = "UISemibold", TextSize = "Body" },
	Toggle = { FontFace = "UISemibold", TextSize = "Body", Corner = true },
	Preset = { BackgroundColor3 = "Raised", FontFace = "Mono", TextSize = "Body", Corner = true },
	ActionButton = { TextColor3 = "Background", FontFace = "UIBold", TextSize = "Body", Corner = true }, -- on Up/Down
}

local TOKEN_TABLES = {
	BackgroundColor3 = Theme.Colors,
	TextColor3 = Theme.Colors,
	PlaceholderColor3 = Theme.Colors,
	FontFace = Theme.Fonts,
	TextSize = Theme.TextSize,
	Stroke = Theme.Colors,
}

-- Fail at require time if a role names a token that doesn't exist, rather
-- than erroring mid-apply on whichever element reaches it first.
for roleName, role in pairs(Theme.Roles) do
	for property, token in pairs(role) do
		if property ~= "Corner" then
			local tokens = TOKEN_TABLES[property]

			assert(tokens and tokens[token] ~= nil, string.format("[Theme] Role %s: unknown %s token %q", roleName, property, tostring(token)))
		end
	end
end

local function isTextObject(instance)
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function canSet(instance, property)
	if property == "BackgroundColor3" then
		return true
	elseif property == "PlaceholderColor3" then
		return instance:IsA("TextBox")
	end

	return isTextObject(instance)
end

local function applyStroke(instance, colorToken)
	local stroke = instance:FindFirstChildOfClass("UIStroke")

	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "ThemeStroke"
		stroke.Parent = instance
	end

	stroke.Color = Theme.Colors[colorToken]
	stroke.Thickness = 1
	stroke.Transparency = 0
	-- The default (Contextual) outlines a text object's glyphs instead of its box
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local function applyRole(instance, role)
	for property, token in pairs(role) do
		if property == "Stroke" then
			applyStroke(instance, token)
		elseif property ~= "Corner" and canSet(instance, property) then
			instance[property] = TOKEN_TABLES[property][token]
		end
	end

	local corner = instance:FindFirstChildOfClass("UICorner")

	if not corner and role.Corner then
		corner = Instance.new("UICorner")
		corner.Name = "ThemeCorner"
		corner.Parent = instance
	end

	if corner then
		corner.CornerRadius = Theme.Radius
	end

	if instance:IsA("ScrollingFrame") then
		instance.ScrollBarImageColor3 = Theme.Colors.TextDisabled
	end
end

-- Stamps every tagged GuiObject under (and including) root. Untagged
-- elements are never touched, so anything that still looks old is visibly
-- a missed tag rather than a silent half-styling.
function Theme.apply(root: Instance)
	local targets = root:GetDescendants()
	table.insert(targets, root)

	for _, instance in ipairs(targets) do
		local roleName = instance:GetAttribute("ThemeRole")

		if roleName ~= nil and instance:IsA("GuiObject") then
			local role = Theme.Roles[roleName]

			if role then
				applyRole(instance, role)
			else
				warn(string.format("[Theme] Unknown ThemeRole %q on %s", tostring(roleName), instance:GetFullName()))
			end
		end
	end
end

return Theme
