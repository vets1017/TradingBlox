-- Instruments.luau
--
-- What kind of instrument a ticker is, and what follows from it. Shared so
-- the client and server gate orders the same way.
--
--   "roblox"   an experience on the Roblox market (Config/RobloxMarket);
--              simulated price, trades 24/7
--   "crypto"   Yahoo's "-USD" pairs; trades 24/7
--   "security" everything else (stocks, ETFs, funds); NYSE hours

local Instruments = {}

Instruments.ROBLOX_PREFIX = "RBX-"

function Instruments.getAssetClass(ticker: string): string
	local upper = string.upper(ticker)

	if string.sub(upper, 1, #Instruments.ROBLOX_PREFIX) == Instruments.ROBLOX_PREFIX then
		return "roblox"
	elseif string.match(upper, "^%a+%-USD$") then
		return "crypto"
	end

	return "security"
end

function Instruments.isRoblox(ticker: string): boolean
	return Instruments.getAssetClass(ticker) == "roblox"
end

-- Crypto and the Roblox market ignore NYSE hours
function Instruments.tradesAroundTheClock(ticker: string): boolean
	return Instruments.getAssetClass(ticker) ~= "security"
end

return Instruments
