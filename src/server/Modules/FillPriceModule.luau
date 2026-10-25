-- FillPriceModule.luau
--
-- The price an order fills at, given a live quote. Pure (no services), so the
-- rules can be unit-tested with made-up quotes (tests/FillPrice.spec.luau).

local FillPriceModule = {}

-- Fills use the bid or ask only in regular trading with a sane spread;
-- otherwise (crypto, after hours, a gapped book) they use the last price
local MAX_FILL_SPREAD = 0.02 -- as a fraction of the price
-- A regular-session stock quote this old means the feed has stalled
local STALE_QUOTE_SECONDS = 15 * 60

-- The price an order fills at, or nil and a reason not to fill. A buy pays
-- the ask and a sell gets the bid during regular trading when the spread is
-- sane; otherwise both use the last price. A regular-session stock quote
-- older than STALE_QUOTE_SECONDS is refused rather than traded against.
function FillPriceModule.getFillPrice(quote, side, isCrypto, now)
	if not quote or not quote.price or quote.price <= 0 then
		return nil, "Price unavailable."
	end

	local isRegular = quote.marketState == "REGULAR"

	if isRegular and not isCrypto and quote.time and now - quote.time > STALE_QUOTE_SECONDS then
		return nil, "The price feed is behind; try again in a moment."
	end

	local bid, ask = quote.bid, quote.ask
	local hasSaneSpread = bid and ask and bid > 0 and ask >= bid and (ask - bid) / quote.price <= MAX_FILL_SPREAD

	if isRegular and not isCrypto and hasSaneSpread then
		return side == "Buy" and ask or bid
	end

	return quote.price
end

return FillPriceModule
