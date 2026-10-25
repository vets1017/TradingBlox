-- FeedText.luau
--
-- How feed items read (see FeedModule on the server for their shape),
-- shared by the Social tab and the Dashboard's Social widget. Returns rich
-- text; player names go through escape first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local Social = require(ReplicatedStorage.Config.Social)
local Progression = require(ReplicatedStorage.Config.Progression)

local UP_HEX = Theme.Colors.Up:ToHex()
local DOWN_HEX = Theme.Colors.Down:ToHex()

local RICH_TEXT_ESCAPES = { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" }

local FeedText = {}

function FeedText.escape(text: string): string
	return (string.gsub(text, "[<>&]", RICH_TEXT_ESCAPES))
end

-- "now", "12m", "3h", "2d"
function FeedText.formatAge(seconds: number): string
	if seconds < 60 then
		return "now"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. "h"
	end

	return math.floor(seconds / 86400) .. "d"
end

local function formatSignedMoney(amount)
	return (amount >= 0 and "+" or "-") .. NumberModule.format(math.abs(amount))
end

-- "Bought 5 AAPL @ $182.10", with the realized P/L after a sale; "Bullish
-- on AAPL · target $210.00 · 1 month" for a thesis; "Reached Level 2 ·
-- Investor" for a milestone
function FeedText.describe(item): string
	if item.kind == "Trade" then
		local isBuy = item.side == "Buy"
		local realized = ""

		if item.realizedPL then
			realized = string.format(
				' <font color="#%s">%s</font>',
				item.realizedPL >= 0 and UP_HEX or DOWN_HEX,
				formatSignedMoney(item.realizedPL)
			)
		end

		return string.format(
			'<font color="#%s">%s</font> %s %s%s @ %s%s',
			isBuy and UP_HEX or DOWN_HEX,
			isBuy and "Bought" or "Sold",
			NumberModule.formatShares(item.quantity),
			item.ticker,
			item.contract and " opt" or "",
			NumberModule.format(item.price),
			realized
		)
	end

	if item.kind == "Thesis" then
		local horizon = Social.getHorizon(item.horizon)

		return string.format(
			'<font color="#%s">%s</font> on %s%s · %s',
			item.direction == "Bullish" and UP_HEX or DOWN_HEX,
			item.direction,
			item.ticker,
			item.targetPrice and (" · target " .. NumberModule.format(item.targetPrice)) or "",
			horizon and horizon.label or item.horizon
		)
	end

	local levelInfo = item.level and Progression.LEVELS[item.level]

	if levelInfo then
		return string.format("Reached Level %d · %s", item.level, levelInfo.name)
	end

	return Social.FEED_MILESTONES[item.milestone] or "Reached a milestone"
end

-- Every reaction on an item added up, for ranking theses
function FeedText.countReactions(item): number
	local total = 0

	for _, count in pairs(item.reactions or {}) do
		total += count
	end

	return total
end

return FeedText
