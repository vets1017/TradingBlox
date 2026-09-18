# Trade Tab Live Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire real Yahoo Finance data into the Trade screen's Quote Details tab and stand up three new tabs (Analyst Reports, Fundamentals, Option Stats) end to end, from a new backend endpoint through to rendered Roblox UI.

**Architecture:** The Render-hosted Node backend (`StockDataFetcher`) is the only thing that can call `yahoo-finance2` (Node-only library). It gains four new routes that each flatten a `quoteSummary`/`options` call into exactly the shape the game needs. `MarketDataModule.luau` (shared, `ServerScriptService.Modules`) gains matching fetch+cache functions. `API_Manager.server.luau` exposes them as three new `RemoteFunction`s (`GetAnalystReportEvent`, `GetFundamentalsEvent`, `GetOptionStatsEvent`) and enriches the existing `GetMarketDataEvent`. `TradeController.client.luau` renders it all, reusing one generic flat-grid renderer for Quote Details/Analyst/Fundamentals and a bespoke two-column (call/put) renderer for Option Stats.

**Tech Stack:** Node/Express + `yahoo-finance2` v3 (backend), Luau + Rojo + Roblox Studio (game). No test framework exists in either repo — verification is manual: `curl` for the backend, live Roblox Studio playtests via the `Roblox_Studio` MCP tools for the game (matches this session's established verification method and `CLAUDE.md`'s "no standalone way to run or test it outside Studio").

**Spec:** `docs/superpowers/specs/2026-09-17-trade-tab-data-design.md`

## Global Constraints

- Backend lives at `~/Documents/VS/StockDataFetcher` (separate git repo). Roblox game lives at this repo. They are edited and committed independently.
- `MarketDataModule.luau`'s `SERVER_URL` is hardcoded to the production Render URL (`https://tradingblox-terminal-backend.onrender.com`). **Tasks 5+ (Roblox side) cannot be verified live until the backend from Tasks 1-4 is pushed and deployed** — there is an explicit checkpoint for this between Task 4 and Task 5.
- No test framework in either repo. Every task ends with a manual verification step (curl for backend tasks, Roblox Studio MCP playtest for game tasks) instead of automated tests. Do not add a test framework as a side effect of this plan — out of scope.
- Match existing code style exactly: tabs for indentation in Luau, the existing comment style (why, not what), no new abstractions beyond what's specified below.
- `StarterGui` (all of the game's UI) is **not** version-controlled — it's not in `default.project.json`'s Rojo sync map, and the built place file is git-ignored. Any task that creates new UI instances does so live in Roblox Studio via MCP tools, not by editing a file. **Save the Studio place file (Cmd+S) after any such task** so the new instances aren't lost.
- Non-equity tickers (crypto, etc.) have no Yahoo analyst/fundamentals data. Endpoints/functions for those two tabs return `{ available = false }` rather than an error — this is an expected, valid response, not a failure case.

---

## Task 1: Backend — `/api/quote-details/:ticker`

**Files:**
- Modify: `~/Documents/VS/StockDataFetcher/index.js`

**Interfaces:**
- Produces: `fetchQuoteSummary(ticker, modules) -> Promise<{ data, error }>` — shared helper, reused by Tasks 2 and 3.
- Produces: `GET /api/quote-details/:ticker -> { companyName, bid, ask, bidSize, askSize, volume, avgVolume, marketCap, beta, trailingPE, forwardPE, dividendYield, dividendRate, exDividendDate, eps, earningsDate, dayHigh, dayLow, fiftyTwoWeekHigh, fiftyTwoWeekLow }` (any field Yahoo lacks comes back `null`).

- [ ] **Step 1: Add the shared `fetchQuoteSummary` helper**

Insert right after the `const yahooFinance = new YahooFinance();` line (line 10) in `index.js`:

```js
async function fetchQuoteSummary(ticker, modules) {
  try {
    const result = await yahooFinance.quoteSummary(ticker, { modules });
    return { data: result, error: null };
  } catch (error) {
    return { data: null, error: error.message };
  }
}
```

- [ ] **Step 2: Add the `/api/quote-details/:ticker` route**

Insert after the existing `/api/candles/:ticker` route (after its closing `});` , before `const PORT = ...`):

```js
app.get("/api/quote-details/:ticker", async (request, response) => {
  const ticker = request.params.ticker.toUpperCase();
  const { data, error } = await fetchQuoteSummary(ticker, [
    "summaryDetail",
    "defaultKeyStatistics",
    "calendarEvents",
    "price",
  ]);

  if (!data) {
    console.error("Quote details: ", error);
    return response.status(500).json({ error: "Yahoo " + error });
  }

  const summaryDetail = data.summaryDetail || {};
  const keyStats = data.defaultKeyStatistics || {};
  const calendar = data.calendarEvents || {};
  const price = data.price || {};
  const earningsDate = Array.isArray(calendar.earningsDate)
    ? calendar.earningsDate[0]
    : calendar.earningsDate ?? null;

  response.json({
    companyName: price.longName || price.shortName || null,
    bid: summaryDetail.bid ?? null,
    ask: summaryDetail.ask ?? null,
    bidSize: summaryDetail.bidSize ?? null,
    askSize: summaryDetail.askSize ?? null,
    volume: summaryDetail.volume ?? null,
    avgVolume: summaryDetail.averageVolume ?? null,
    marketCap: summaryDetail.marketCap ?? null,
    beta: keyStats.beta ?? null,
    trailingPE: summaryDetail.trailingPE ?? null,
    forwardPE: summaryDetail.forwardPE ?? null,
    dividendYield: summaryDetail.dividendYield ?? null,
    dividendRate: summaryDetail.dividendRate ?? null,
    exDividendDate: calendar.exDividendDate ?? null,
    eps: keyStats.trailingEps ?? null,
    earningsDate: earningsDate,
    dayHigh: summaryDetail.dayHigh ?? null,
    dayLow: summaryDetail.dayLow ?? null,
    fiftyTwoWeekHigh: summaryDetail.fiftyTwoWeekHigh ?? null,
    fiftyTwoWeekLow: summaryDetail.fiftyTwoWeekLow ?? null,
  });
});
```

- [ ] **Step 3: Verify locally**

Run: `cd ~/Documents/VS/StockDataFetcher && node index.js` (leave running), then in another terminal:
```bash
curl -s http://localhost:3000/api/quote-details/AAPL | python3 -m json.tool
curl -s http://localhost:3000/api/quote-details/KO | python3 -m json.tool
```
Expected: real numbers for both, all 19 fields present (some may be `null`, that's fine). **Check `dividendYield` on KO specifically** (Coca-Cola, well-known ~3% yield): if the raw value is close to `0.03` it's a fraction and the client's `%.2f%%` formatter will show "0.03%" instead of "~3.00%" — if so, come back and multiply `dividendYield` by 100 in the response above before moving on. If it's already ~`3.0`, leave it as-is.

Stop the server (Ctrl+C) when done.

- [ ] **Step 4: Commit**

```bash
cd ~/Documents/VS/StockDataFetcher
git add index.js
git commit -m "Add /api/quote-details endpoint for real quote stats"
```

---

## Task 2: Backend — `/api/analyst/:ticker`

**Files:**
- Modify: `~/Documents/VS/StockDataFetcher/index.js`

**Interfaces:**
- Consumes: `fetchQuoteSummary(ticker, modules)` from Task 1.
- Produces: `GET /api/analyst/:ticker -> { available: true, targetHigh, targetLow, targetMean, targetMedian, recommendationMean, recommendationKey, numberOfAnalysts, strongBuyCount, buyCount, holdCount, sellCount, strongSellCount }` or `{ available: false }`.

- [ ] **Step 1: Add the route**

Insert after the `/api/quote-details/:ticker` route:

```js
app.get("/api/analyst/:ticker", async (request, response) => {
  const ticker = request.params.ticker.toUpperCase();
  const { data, error } = await fetchQuoteSummary(ticker, [
    "financialData",
    "recommendationTrend",
  ]);

  if (!data) {
    console.error("Analyst report: ", error);
    return response.status(500).json({ error: "Yahoo " + error });
  }

  const financialData = data.financialData;
  const trend =
    data.recommendationTrend &&
    data.recommendationTrend.trend &&
    data.recommendationTrend.trend[0];

  if (!financialData && !trend) {
    return response.json({ available: false });
  }

  response.json({
    available: true,
    targetHigh: financialData?.targetHighPrice ?? null,
    targetLow: financialData?.targetLowPrice ?? null,
    targetMean: financialData?.targetMeanPrice ?? null,
    targetMedian: financialData?.targetMedianPrice ?? null,
    recommendationMean: financialData?.recommendationMean ?? null,
    recommendationKey: financialData?.recommendationKey ?? null,
    numberOfAnalysts: financialData?.numberOfAnalystOpinions ?? null,
    strongBuyCount: trend?.strongBuy ?? null,
    buyCount: trend?.buy ?? null,
    holdCount: trend?.hold ?? null,
    sellCount: trend?.sell ?? null,
    strongSellCount: trend?.strongSell ?? null,
  });
});
```

- [ ] **Step 2: Verify locally**

Run: `node index.js`, then:
```bash
curl -s http://localhost:3000/api/analyst/AAPL | python3 -m json.tool
curl -s http://localhost:3000/api/analyst/BTC-USD | python3 -m json.tool
```
Expected: AAPL returns `available: true` with real target prices and rating counts; BTC-USD returns `{ "available": false }` (no analyst coverage for crypto). Stop the server.

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/VS/StockDataFetcher
git add index.js
git commit -m "Add /api/analyst endpoint for price targets and ratings"
```

---

## Task 3: Backend — `/api/fundamentals/:ticker`

**Files:**
- Modify: `~/Documents/VS/StockDataFetcher/index.js`

**Interfaces:**
- Consumes: `fetchQuoteSummary(ticker, modules)` from Task 1.
- Produces: `GET /api/fundamentals/:ticker -> { available: true, totalRevenue, grossMargins, operatingMargins, profitMargins, returnOnEquity, returnOnAssets, totalCash, totalDebt, debtToEquity, freeCashflow, priceToBook, pegRatio, enterpriseToEbitda, revenueGrowth, earningsGrowth }` or `{ available: false }`. Margin/ROE/ROA/growth fields are **percentages (0-100 range)**, not raw fractions — `financialData`'s margin/growth fields come back from Yahoo as fractions (e.g. `0.2531` for 25.31%), so this route multiplies them by 100 before returning, matching what the client's `percent` formatter expects.

- [ ] **Step 1: Add the route**

Insert after the `/api/analyst/:ticker` route:

```js
app.get("/api/fundamentals/:ticker", async (request, response) => {
  const ticker = request.params.ticker.toUpperCase();
  const { data, error } = await fetchQuoteSummary(ticker, [
    "financialData",
    "defaultKeyStatistics",
    "summaryDetail",
  ]);

  if (!data) {
    console.error("Fundamentals: ", error);
    return response.status(500).json({ error: "Yahoo " + error });
  }

  const financialData = data.financialData;
  const keyStats = data.defaultKeyStatistics;

  if (!financialData && !keyStats) {
    return response.json({ available: false });
  }

  const pct = (value) => (typeof value === "number" ? value * 100 : null);

  response.json({
    available: true,
    totalRevenue: financialData?.totalRevenue ?? null,
    grossMargins: pct(financialData?.grossMargins),
    operatingMargins: pct(financialData?.operatingMargins),
    profitMargins: pct(financialData?.profitMargins),
    returnOnEquity: pct(financialData?.returnOnEquity),
    returnOnAssets: pct(financialData?.returnOnAssets),
    totalCash: financialData?.totalCash ?? null,
    totalDebt: financialData?.totalDebt ?? null,
    debtToEquity: financialData?.debtToEquity ?? null,
    freeCashflow: financialData?.freeCashflow ?? null,
    priceToBook: keyStats?.priceToBook ?? null,
    pegRatio: keyStats?.pegRatio ?? null,
    enterpriseToEbitda: keyStats?.enterpriseToEbitda ?? null,
    revenueGrowth: pct(financialData?.revenueGrowth),
    earningsGrowth: pct(financialData?.earningsGrowth),
  });
});
```

- [ ] **Step 2: Verify locally**

Run: `node index.js`, then:
```bash
curl -s http://localhost:3000/api/fundamentals/AAPL | python3 -m json.tool
curl -s http://localhost:3000/api/fundamentals/BTC-USD | python3 -m json.tool
```
Expected: AAPL's `profitMargins` should be roughly in the 20-30 range (percent, not 0.20-0.30) — if it looks off by 100x either direction, adjust the `pct()` helper. BTC-USD returns `{ "available": false }`. Stop the server.

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/VS/StockDataFetcher
git add index.js
git commit -m "Add /api/fundamentals endpoint for financial ratios"
```

---

## Task 4: Backend — `/api/options/:ticker`

**Files:**
- Modify: `~/Documents/VS/StockDataFetcher/index.js`

**Interfaces:**
- Produces: `GET /api/options/:ticker -> { available: true, expiration, strike, call: { bid, ask, lastPrice, impliedVolatility, volume, openInterest }, put: { ...same } }` or `{ available: false }`. `impliedVolatility` is a **percentage (0-100)**, scaled from Yahoo's raw fraction.

- [ ] **Step 1: Add the route**

Insert after the `/api/fundamentals/:ticker` route:

```js
app.get("/api/options/:ticker", async (request, response) => {
  const ticker = request.params.ticker.toUpperCase();

  try {
    const result = await yahooFinance.options(ticker);
    const chain = result.options && result.options[0];
    const spotPrice = result.quote?.regularMarketPrice ?? null;

    if (!chain || !chain.calls || chain.calls.length === 0 || spotPrice === null) {
      return response.json({ available: false });
    }

    const calls = chain.calls;
    const puts = chain.puts || [];

    let atmCall = calls[0];
    let smallestDiff = Math.abs(calls[0].strike - spotPrice);

    for (const call of calls) {
      const diff = Math.abs(call.strike - spotPrice);
      if (diff < smallestDiff) {
        smallestDiff = diff;
        atmCall = call;
      }
    }

    const atmPut = puts.find((put) => put.strike === atmCall.strike) || null;

    const pickFields = (contract) =>
      contract
        ? {
            bid: contract.bid ?? null,
            ask: contract.ask ?? null,
            lastPrice: contract.lastPrice ?? null,
            impliedVolatility:
              typeof contract.impliedVolatility === "number"
                ? contract.impliedVolatility * 100
                : null,
            volume: contract.volume ?? null,
            openInterest: contract.openInterest ?? null,
          }
        : null;

    response.json({
      available: true,
      expiration: chain.expirationDate ?? null,
      strike: atmCall.strike,
      call: pickFields(atmCall),
      put: pickFields(atmPut),
    });
  } catch (error) {
    console.error("Options: ", error.message);
    response.status(500).json({ error: "Yahoo " + error.message });
  }
});
```

- [ ] **Step 2: Verify locally, and confirm the raw field names**

Run: `node index.js`, then:
```bash
curl -s http://localhost:3000/api/options/AAPL | python3 -m json.tool
curl -s http://localhost:3000/api/options/BTC-USD | python3 -m json.tool
```
Expected: AAPL returns `available: true` with a plausible strike near AAPL's current price, and both `call`/`put` populated. BTC-USD (no listed options market) returns `{ "available": false }`.

**If the AAPL response is `available: false` unexpectedly**, add a temporary `console.log(JSON.stringify(result, null, 2))` right after the `yahooFinance.options(ticker)` call to see the actual raw shape — the code above assumes `result.options[0].calls`/`.puts` and `result.options[0].expirationDate`, which matches yahoo-finance2 v3's documented shape, but confirm before trusting it silently. Remove the `console.log` once confirmed.

Stop the server.

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/VS/StockDataFetcher
git add index.js
git commit -m "Add /api/options endpoint for nearest-expiration ATM contract stats"
```

---

## ⚠️ CHECKPOINT — Deploy the backend before continuing

`MarketDataModule.luau` in Task 5 calls the **production** Render URL, not localhost.
**Push `~/Documents/VS/StockDataFetcher` and deploy it to Render now** (per your
earlier choice, this is on you — I've only committed locally). Confirm the new
routes work against the live URL, e.g.:
```bash
curl -s https://tradingblox-terminal-backend.onrender.com/api/quote-details/AAPL
```
before starting Task 5.

---

## Task 5: `MarketDataModule.luau` — fetch + cache functions

**Files:**
- Modify: `src/server/Modules/MarketDataModule.luau`

**Interfaces:**
- Consumes: existing `fetchJSON(url) -> data, err` (private, already in this file).
- Produces: `MarketDataModule.getQuoteDetails(ticker) -> data, err`, `MarketDataModule.getAnalystReport(ticker) -> data, err`, `MarketDataModule.getFundamentals(ticker) -> data, err`, `MarketDataModule.getOptionStats(ticker) -> data, err` — all consumed by Task 6.

- [ ] **Step 1: Add new endpoint + TTL constants and cache tables**

Replace the `-- Config` and `-- State` blocks (current lines 13-23) with:

```lua
-- Config
local SERVER_URL = "https://tradingblox-terminal-backend.onrender.com" -- temp
local CANDLES_ENDPOINT = SERVER_URL .. "/api/candles/"
local QUOTE_DETAILS_ENDPOINT = SERVER_URL .. "/api/quote-details/"
local ANALYST_ENDPOINT = SERVER_URL .. "/api/analyst/"
local FUNDAMENTALS_ENDPOINT = SERVER_URL .. "/api/fundamentals/"
local OPTIONS_ENDPOINT = SERVER_URL .. "/api/options/"

local CHART_CACHE_DURATION = 300
local QUOTE_DETAILS_CACHE_DURATION = 60
local ANALYST_CACHE_DURATION = 21600 -- 6 hours
local FUNDAMENTALS_CACHE_DURATION = 21600 -- 6 hours
local OPTION_STATS_CACHE_DURATION = 300
local CACHE_SWEEP_INTERVAL = 600
local MAX_TICKER_LENGTH = 10
local VALID_TIMEFRAMES = { ["1M"] = true, ["5M"] = true, ["30M"] = true, ["H"] = true, ["D"] = true }

-- State
local ChartCache = {} -- [cacheKey] = { data = ..., lastUpdated = os.time() }
local QuoteDetailsCache = {}
local AnalystCache = {}
local FundamentalsCache = {}
local OptionStatsCache = {}
```

- [ ] **Step 2: Add the generic `cachedFetch` helper**

Insert after the existing `fetchJSON` function (after its closing `end`, before the `-- Fetches candles...` comment):

```lua
-- Generic cache-or-fetch: returns cached data if still within `ttl` seconds,
-- otherwise calls fetchFn() and stores a fresh copy on success.
local function cachedFetch(cache, key, ttl, fetchFn)
	local cached = cache[key]
	local now = os.time()

	if cached and (now - cached.lastUpdated) < ttl then
		return cached.data, nil
	end

	local data, err = fetchFn()

	if data then
		cache[key] = { data = data, lastUpdated = now }
	end

	return data, err
end
```

- [ ] **Step 3: Add the four new public functions**

Insert after `MarketDataModule.getQuote` (after its closing `end`), before the `-- Cache sweep` comment:

```lua
-- Quote Details tab: bid/ask/sizes, volume, market cap, beta, PE, dividends,
-- EPS, ex-div/earnings dates, day & 52-week range.
function MarketDataModule.getQuoteDetails(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedFetch(QuoteDetailsCache, targetTicker, QUOTE_DETAILS_CACHE_DURATION, function()
		local data, err = fetchJSON(QUOTE_DETAILS_ENDPOINT .. HttpService:UrlEncode(targetTicker))

		if data and data.error then
			return nil, tostring(data.error)
		end

		return data, err
	end)
end

-- Analyst Reports tab: price targets, recommendation mean/key, rating counts.
-- Returns { available = false } for tickers with no analyst coverage.
function MarketDataModule.getAnalystReport(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedFetch(AnalystCache, targetTicker, ANALYST_CACHE_DURATION, function()
		local data, err = fetchJSON(ANALYST_ENDPOINT .. HttpService:UrlEncode(targetTicker))

		if data and data.error then
			return nil, tostring(data.error)
		end

		return data, err
	end)
end

-- Fundamentals tab: revenue, margins, ROE/ROA, cash, debt, valuation ratios,
-- growth. Returns { available = false } for tickers with no financials.
function MarketDataModule.getFundamentals(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedFetch(FundamentalsCache, targetTicker, FUNDAMENTALS_CACHE_DURATION, function()
		local data, err = fetchJSON(FUNDAMENTALS_ENDPOINT .. HttpService:UrlEncode(targetTicker))

		if data and data.error then
			return nil, tostring(data.error)
		end

		return data, err
	end)
end

-- Option Stats tab: nearest-expiration ATM call/put. No greeks - Yahoo
-- doesn't provide them. Returns { available = false } if no listed options.
function MarketDataModule.getOptionStats(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedFetch(OptionStatsCache, targetTicker, OPTION_STATS_CACHE_DURATION, function()
		local data, err = fetchJSON(OPTIONS_ENDPOINT .. HttpService:UrlEncode(targetTicker))

		if data and data.error then
			return nil, tostring(data.error)
		end

		return data, err
	end)
end
```

- [ ] **Step 4: Extend the cache sweep to cover all five caches**

Replace the existing `-- Cache sweep` `task.spawn` block (the last block before `return MarketDataModule`) with:

```lua
-- Cache sweep
local ALL_CACHES = {
	{ cache = ChartCache, ttl = CHART_CACHE_DURATION },
	{ cache = QuoteDetailsCache, ttl = QUOTE_DETAILS_CACHE_DURATION },
	{ cache = AnalystCache, ttl = ANALYST_CACHE_DURATION },
	{ cache = FundamentalsCache, ttl = FUNDAMENTALS_CACHE_DURATION },
	{ cache = OptionStatsCache, ttl = OPTION_STATS_CACHE_DURATION },
}

task.spawn(function()
	while true do
		task.wait(CACHE_SWEEP_INTERVAL)

		local now = os.time()
		local deletedCount = 0

		for _, entry in ipairs(ALL_CACHES) do
			for key, cacheEntry in pairs(entry.cache) do
				if (now - cacheEntry.lastUpdated) > entry.ttl then
					entry.cache[key] = nil
					deletedCount += 1
				end
			end
		end

		if deletedCount > 0 then
			print("[MarketDataModule] Cleared " .. deletedCount .. " stale cache entries.")
		end
	end
end)
```

- [ ] **Step 5: Verify via Roblox Studio MCP**

With `rojo serve` running and Studio connected (as established earlier this session), start play via `mcp__Roblox_Studio__start_stop_play` (`is_start: true`), then run via `mcp__Roblox_Studio__execute_luau` (`datamodel_type: "Server"`):

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)

return {
	quoteDetails = MarketDataModule.getQuoteDetails("AAPL"),
	analyst = MarketDataModule.getAnalystReport("AAPL"),
	fundamentals = MarketDataModule.getFundamentals("AAPL"),
	optionStats = MarketDataModule.getOptionStats("AAPL"),
}
```
Expected: all four return non-nil tables with the field names from Tasks 1-4. Check `mcp__Roblox_Studio__get_console_output` for errors, then stop play (`is_start: false`).

- [ ] **Step 6: Commit**

```bash
git add src/server/Modules/MarketDataModule.luau
git commit -m "$(cat <<'EOF'
Add fetch/cache functions for quote details, analyst, fundamentals, option stats

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `ServerSetup.server.luau` + `API_Manager.server.luau` — new remotes

**Files:**
- Modify: `src/server/Core/ServerSetup.server.luau`
- Modify: `src/server/Core/API_Manager.server.luau`

**Interfaces:**
- Consumes: `MarketDataModule.getQuoteDetails/getAnalystReport/getFundamentals/getOptionStats` from Task 5.
- Produces: three new `RemoteFunction`s reachable at `ReplicatedStorage.EventsFolder.{GetAnalystReportEvent,GetFundamentalsEvent,GetOptionStatsEvent}`, and an enriched `GetMarketDataEvent` return shape (adds all `getQuoteDetails` fields on top of the existing `{ ticker, price, prevClose }`) — consumed by Task 8-11.

- [ ] **Step 1: Register the new remotes**

In `ServerSetup.server.luau`, replace the `EVENTS` table (lines 3-10):

```lua
local EVENTS = {
	"RequestChartEvent",
	"GetMarketDataEvent",
	"GetOptionsDataEvent",
	"GetPositionsEvent",
	"GetNewsFeedEvent",
	"PlayerOrderEvent",
	"GetAnalystReportEvent",
	"GetFundamentalsEvent",
	"GetOptionStatsEvent",
}
```

- [ ] **Step 2: Wire the three new handlers + enrich `GetMarketDataEvent`**

In `API_Manager.server.luau`, add three new remote references after the existing ones (after line 14, `local GetMarketDataEvent = ...`):

```lua
local GetAnalystReportEvent = EventsFolder:WaitForChild("GetAnalystReportEvent")
local GetFundamentalsEvent = EventsFolder:WaitForChild("GetFundamentalsEvent")
local GetOptionStatsEvent = EventsFolder:WaitForChild("GetOptionStatsEvent")
```

Replace the `GetMarketDataEvent.OnServerInvoke` handler (current lines 65-83) with:

```lua
GetMarketDataEvent.OnServerInvoke = function(player, ticker)
	if not ticker then
		return nil
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local quote = MarketDataModule.getQuote(ticker)

	if not quote then
		warn(string.format("[API_Manager] Quote fetch failed for %s", string.upper(ticker)))

		return nil
	end

	local details = MarketDataModule.getQuoteDetails(ticker)

	if details then
		for key, value in pairs(details) do
			quote[key] = value
		end
	end

	return quote
end
```

Add the three new handlers right before the `-- Clean up` section at the end:

```lua
-- GetAnalystReportEvent
GetAnalystReportEvent.OnServerInvoke = function(player, ticker)
	local userId = player.UserId
	local now = os.time()
	local lastRequest = PlayerLastRequest[userId] or 0

	if (now - lastRequest) < PLAYER_COOLDOWN then
		return nil
	end

	PlayerLastRequest[userId] = now

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local report, err = MarketDataModule.getAnalystReport(ticker)

	if not report then
		warn(string.format("[API_Manager] Analyst report fetch failed for %s: %s", string.upper(ticker), tostring(err)))
	end

	return report
end

-- GetFundamentalsEvent
GetFundamentalsEvent.OnServerInvoke = function(player, ticker)
	local userId = player.UserId
	local now = os.time()
	local lastRequest = PlayerLastRequest[userId] or 0

	if (now - lastRequest) < PLAYER_COOLDOWN then
		return nil
	end

	PlayerLastRequest[userId] = now

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local fundamentals, err = MarketDataModule.getFundamentals(ticker)

	if not fundamentals then
		warn(string.format("[API_Manager] Fundamentals fetch failed for %s: %s", string.upper(ticker), tostring(err)))
	end

	return fundamentals
end

-- GetOptionStatsEvent
GetOptionStatsEvent.OnServerInvoke = function(player, ticker)
	local userId = player.UserId
	local now = os.time()
	local lastRequest = PlayerLastRequest[userId] or 0

	if (now - lastRequest) < PLAYER_COOLDOWN then
		return nil
	end

	PlayerLastRequest[userId] = now

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local stats, err = MarketDataModule.getOptionStats(ticker)

	if not stats then
		warn(string.format("[API_Manager] Option stats fetch failed for %s: %s", string.upper(ticker), tostring(err)))
	end

	return stats
end
```

- [ ] **Step 3: Verify via Roblox Studio MCP**

Start play, then run via `execute_luau` (`datamodel_type: "Client"`):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")

return {
	marketData = EventsFolder.GetMarketDataEvent:InvokeServer("AAPL"),
	analyst = EventsFolder.GetAnalystReportEvent:InvokeServer("AAPL"),
	fundamentals = EventsFolder.GetFundamentalsEvent:InvokeServer("AAPL"),
	optionStats = EventsFolder.GetOptionStatsEvent:InvokeServer("AAPL"),
}
```
Expected: `marketData` now includes `bid`, `ask`, `marketCap`, etc. alongside `ticker`/`price`/`prevClose`; the other three return their respective real data. Check console for errors, then stop play.

- [ ] **Step 4: Commit**

```bash
git add src/server/Core/ServerSetup.server.luau src/server/Core/API_Manager.server.luau
git commit -m "$(cat <<'EOF'
Wire GetAnalystReportEvent, GetFundamentalsEvent, GetOptionStatsEvent; enrich GetMarketDataEvent with quote details

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `NumberModule.luau` — share-count and compact-currency formatting

**Files:**
- Modify: `src/shared/Modules/Multi/NumberModule.luau`

**Interfaces:**
- Produces: `NumberModule.formatShares(amount: number) -> string`, `NumberModule.formatCompact(amount: number) -> string` — consumed by Task 8's `formatValue`.
- `NumberModule.format` keeps its existing signature/behavior (still `$`-prefixed, comma-grouped) — no caller elsewhere in the codebase breaks.

- [ ] **Step 1: Replace the file**

```lua
local NumberModule = {}

local function addCommas(numberString)
	local formatted = numberString
	local k

	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")

		if k == 0 then
			break
		end
	end

	return formatted
end

function NumberModule.format(amount)
	return "$" .. addCommas(tostring(amount))
end

-- Comma-grouped integer, no currency prefix - for share/contract counts
-- (Volume, Open Interest, # of Analysts), not dollar amounts.
function NumberModule.formatShares(amount)
	return addCommas(string.format("%d", math.floor(amount)))
end

-- Abbreviated currency for large dollar figures (market cap, revenue, cash,
-- debt) - e.g. $3.00T, $245.67B, $12.30M, $850.00K. Falls back to plain
-- comma-grouped dollars under $1,000.
function NumberModule.formatCompact(amount)
	local sign = amount < 0 and "-" or ""
	local magnitude = math.abs(amount)

	if magnitude >= 1e12 then
		return sign .. string.format("$%.2fT", magnitude / 1e12)
	elseif magnitude >= 1e9 then
		return sign .. string.format("$%.2fB", magnitude / 1e9)
	elseif magnitude >= 1e6 then
		return sign .. string.format("$%.2fM", magnitude / 1e6)
	elseif magnitude >= 1e3 then
		return sign .. string.format("$%.2fK", magnitude / 1e3)
	end

	return sign .. "$" .. addCommas(string.format("%.2f", magnitude))
end

return NumberModule
```

- [ ] **Step 2: Verify via Roblox Studio MCP**

Run via `execute_luau` (`datamodel_type: "Edit"`):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)

return {
	format = NumberModule.format(10000),
	formatShares = NumberModule.formatShares(1234567),
	compactTrillion = NumberModule.formatCompact(3000000000000),
	compactBillion = NumberModule.formatCompact(245670000000),
	compactSmall = NumberModule.formatCompact(850),
}
```
Expected: `format = "$10,000"`, `formatShares = "1,234,567"`, `compactTrillion = "$3.00T"`, `compactBillion = "$245.67B"`, `compactSmall = "$850.00"`.

- [ ] **Step 3: Commit**

```bash
git add src/shared/Modules/Multi/NumberModule.luau
git commit -m "$(cat <<'EOF'
Add share-count and compact-currency formatters to NumberModule

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `TradeController.client.luau` — real Quote Details + generic field-grid renderer

**Files:**
- Modify: `src/client/Controllers/TradeController.client.luau`

**Interfaces:**
- Consumes: `NumberModule.formatShares`/`formatCompact` from Task 7; enriched `GetMarketDataEvent` from Task 6.
- Produces: `renderFieldGrid(container: Frame, fields: table, data: table?, prefix: string)` (local function) — consumed by Tasks 9 and 10 for Analyst Reports and Fundamentals.

- [ ] **Step 1: Replace `QUOTE_FIELDS`**

Replace lines 68-81:

```lua
local QUOTE_FIELDS = {
	{ label = "Volume", key = "volume", format = "count" },
	{ label = "Avg Volume", key = "avgVolume", format = "count" },
	{ label = "Beta", key = "beta", format = "decimal2" },
	{ label = "Market Cap", key = "marketCap", format = "compact" },
	{ label = "Yield", key = "dividendYield", format = "percent" },
	{ label = "Div Amount", key = "dividendRate", format = "price" },
	{ label = "Ex Date", key = "exDividendDate", format = "date" },
	{ label = "PE (Trailing)", key = "trailingPE", format = "decimal2" },
	{ label = "PE (Forward)", key = "forwardPE", format = "decimal2" },
	{ label = "EPS", key = "eps", format = "decimal2" },
	{ label = "Earnings", key = "earningsDate", format = "date" },
	{ label = "Day High", key = "dayHigh", format = "price" },
	{ label = "Day Low", key = "dayLow", format = "price" },
	{ label = "52-Wk High", key = "fiftyTwoWeekHigh", format = "price" },
	{ label = "52-Wk Low", key = "fiftyTwoWeekLow", format = "price" },
}
```

- [ ] **Step 2: Add `"count"` and `"compact"` cases to `formatValue`**

Replace the `formatValue` function (lines 124-146):

```lua
local function formatValue(value, formatType)
	if value == nil or value == "" then
		return "—"
	end

	if formatType == "price" then
		return string.format("%.2f", value)
	elseif formatType == "decimal2" then
		return string.format("%.2f", value)
	elseif formatType == "percent" then
		return string.format("%.2f%%", value)
	elseif formatType == "change" then
		local sign = value >= 0 and "+" or ""

		return string.format("%s%.2f", sign, value)
	elseif formatType == "number" then
		return NumberModule.format(value)
	elseif formatType == "count" then
		return NumberModule.formatShares(value)
	elseif formatType == "compact" then
		return NumberModule.formatCompact(value)
	elseif formatType == "date" or formatType == "auto" then
		return tostring(value)
	end

	return tostring(value)
end
```

- [ ] **Step 3: Extract the generic `renderFieldGrid` and rewrite `renderQuoteDetails` on top of it**

Replace the `renderQuoteDetails` function (lines 222-267) with:

```lua
-- Renders a flat label/value grid into `container`, clearing any previous
-- rows tagged with `prefix` first. Shared by Quote Details, Analyst
-- Reports, and Fundamentals - all three are flat field-list tabs.
local function renderFieldGrid(container, fields, data, prefix)
	for _, child in pairs(container:GetChildren()) do
		if child:IsA("Frame") and string.match(child.Name, "^" .. prefix) then
			child:Destroy()
		end
	end

	if not data then
		return
	end

	for i, field in ipairs(fields) do
		local row = Instance.new("Frame")

		row.Name = prefix .. field.key
		row.Size = UDim2.new(0.5, -4, 0, 22)
		row.BackgroundTransparency = 1
		row.LayoutOrder = i
		row.Parent = container

		local lbl = Instance.new("TextLabel")

		lbl.Name = "Label"
		lbl.Text = field.label
		lbl.Size = UDim2.new(0.55, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = TEXT_SECONDARY
		lbl.Font = Enum.Font.SourceSans
		lbl.TextSize = 13
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = row

		local val = Instance.new("TextLabel")

		val.Name = "Value"
		val.Text = formatValue(data[field.key], field.format)
		val.Size = UDim2.new(0.45, 0, 1, 0)
		val.Position = UDim2.fromScale(0.55, 0)
		val.BackgroundTransparency = 1
		val.TextColor3 = TEXT_PRIMARY
		val.Font = Enum.Font.SourceSansSemibold
		val.TextSize = 13
		val.TextXAlignment = Enum.TextXAlignment.Right
		val.Parent = row
	end
end

local function renderQuoteDetails(data)
	renderFieldGrid(ContentQuoteDetails, QUOTE_FIELDS, data, "QF_")
end
```

(Leave `updateQuoteField` right after it untouched — it already looks up children by the same `"QF_" .. key` naming and needs no change.)

- [ ] **Step 4: Verify via Roblox Studio MCP playtest**

Start play, invoke `loadTicker` behavior indirectly by setting the ticker input and pressing enter (or directly via `execute_luau` in `Client` context calling `EventsFolder.GetMarketDataEvent:InvokeServer("AAPL")` and checking the shape), then use `mcp__Roblox_Studio__search_game_tree` to confirm `Content_QuoteDetails` now has 15 `QF_*` child frames with real (non-dash) values in a `screen_capture` or by reading label `Text` properties via `execute_luau`. Confirm console is clean. Stop play.

- [ ] **Step 5: Commit**

```bash
git add src/client/Controllers/TradeController.client.luau
git commit -m "$(cat <<'EOF'
Wire real Quote Details fields; extract shared renderFieldGrid helper

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Analyst Reports tab

**Files:**
- Modify (Studio, via MCP — not a repo file): `StarterGui.TerminalGui.MainBackground.ScreenContainer.TradeScreen.QuoteDetails.TabContentContainer` — add `Content_AnalystReports`.
- Modify: `src/client/Controllers/TradeController.client.luau`

**Interfaces:**
- Consumes: `renderFieldGrid` from Task 8; `GetAnalystReportEvent` remote from Task 6.
- Produces: `renderUnavailable(container, prefix, message)` (local function) — reused by Tasks 10 and 11.

- [ ] **Step 1: Create the `Content_AnalystReports` panel in Studio**

With Studio in **Edit** mode (not playing), run via `mcp__Roblox_Studio__execute_luau` (`datamodel_type: "Edit"`):

```lua
local StarterGui = game:GetService("StarterGui")
local QuoteDetails = StarterGui.TerminalGui.MainBackground.ScreenContainer.TradeScreen.QuoteDetails
local TabContentContainer = QuoteDetails.TabContentContainer
local ContentQuoteDetails = TabContentContainer.Content_QuoteDetails

local existing = TabContentContainer:FindFirstChild("Content_AnalystReports")
if existing then
	existing:Destroy()
end

local ContentAnalystReports = ContentQuoteDetails:Clone()
ContentAnalystReports.Name = "Content_AnalystReports"
ContentAnalystReports.Visible = false

for _, child in ipairs(ContentAnalystReports:GetChildren()) do
	if child:IsA("Frame") and string.match(child.Name, "^QF_") then
		child:Destroy()
	end
end

ContentAnalystReports.Parent = TabContentContainer

return "created: " .. ContentAnalystReports:GetFullName()
```

**Then save the Studio place file (Cmd+S)** so this isn't lost.

- [ ] **Step 2: Add the remote ref, container ref, state var, and tab wiring**

In `TradeController.client.luau`:

Add after the existing remote declarations (after `local PlayerOrderEvent = EventsFolder:WaitForChild("PlayerOrderEvent")`):
```lua
local GetAnalystReportEvent = EventsFolder:WaitForChild("GetAnalystReportEvent")
```

Add after `local ContentQuoteDetails = TabContentContainer:WaitForChild("Content_QuoteDetails")`:
```lua
local ContentAnalystReports = TabContentContainer:WaitForChild("Content_AnalystReports")
```

In the `TabContents` map, replace the commented-out line:
```lua
	-- AnalystReports = TabContentContainer:WaitForChild("Content_AnalystReports"),
```
with:
```lua
	AnalystReports = ContentAnalystReports,
```

In the `-- State` section (near `local currentOptionData = nil`), add:
```lua
local currentAnalystData = nil
```

- [ ] **Step 3: Add `ANALYST_FIELDS`, `renderUnavailable`, `renderAnalystReport`, `fetchAnalystReport`**

Add near `QUOTE_FIELDS` (after `POSITION_COLUMNS`):

```lua
local ANALYST_FIELDS = {
	{ label = "Mean Target", key = "targetMean", format = "price" },
	{ label = "High Target", key = "targetHigh", format = "price" },
	{ label = "Low Target", key = "targetLow", format = "price" },
	{ label = "Median Target", key = "targetMedian", format = "price" },
	{ label = "Rating", key = "recommendationKey", format = "auto" },
	{ label = "Rating Score (1-5)", key = "recommendationMean", format = "decimal2" },
	{ label = "# Analysts", key = "numberOfAnalysts", format = "count" },
	{ label = "Strong Buy", key = "strongBuyCount", format = "count" },
	{ label = "Buy", key = "buyCount", format = "count" },
	{ label = "Hold", key = "holdCount", format = "count" },
	{ label = "Sell", key = "sellCount", format = "count" },
	{ label = "Strong Sell", key = "strongSellCount", format = "count" },
}
```

Add right after `renderFieldGrid` (defined in Task 8):

```lua
-- Shows a single centered message instead of a field grid - used when a
-- tab's data comes back { available = false } (e.g. Analyst/Fundamentals
-- for a crypto ticker with no Yahoo coverage).
local function renderUnavailable(container, prefix, message)
	for _, child in pairs(container:GetChildren()) do
		if child:IsA("Frame") and string.match(child.Name, "^" .. prefix) then
			child:Destroy()
		end
	end

	local row = Instance.new("Frame")

	row.Name = prefix .. "Unavailable"
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.Parent = container

	local lbl = Instance.new("TextLabel")

	lbl.Name = "Label"
	lbl.Text = message
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = TEXT_SECONDARY
	lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.Parent = row
end

local function renderAnalystReport(data)
	if data and data.available == false then
		renderUnavailable(ContentAnalystReports, "AR_", "Not available for this asset")
		return
	end

	renderFieldGrid(ContentAnalystReports, ANALYST_FIELDS, data, "AR_")
end

local function fetchAnalystReport()
	local data = GetAnalystReportEvent:InvokeServer(currentTicker)
	currentAnalystData = data
	renderAnalystReport(data)
end
```

- [ ] **Step 4: Wire lazy-fetch into `switchTab`, and reset on ticker change**

In `switchTab`, add at the end of the function (after the `for name, frame in pairs(TabContents) do ... end` loop):
```lua
	if tabName == "AnalystReports" and currentTicker ~= "" and not currentAnalystData then
		fetchAnalystReport()
	end
```

In `loadTicker`, add `currentAnalystData = nil` alongside the existing `currentQuoteData = nil`-style resets — specifically, add it right after the line `currentTicker = ticker` (near the top of the function, in the same block as `setLoadingState(true)` / `clearOptionChain()` / `clearPositions()` / `clearNewsFeed()`):
```lua
	currentAnalystData = nil
```

(`loadTicker` already unconditionally calls `switchTab("QuoteDetails")` on every ticker load, so there's no "currently active non-QuoteDetails tab" case to special-case — the next time the user clicks Analyst Reports, `switchTab` sees `currentAnalystData == nil` and fetches fresh data for the new ticker automatically.)

- [ ] **Step 5: Verify via Roblox Studio MCP playtest**

Start play, load ticker "AAPL" (via the input box or `execute_luau` calling the remotes directly), click the Analyst Reports tab, confirm real target prices and rating counts render. Load ticker "BTC-USD", click Analyst Reports again, confirm it shows "Not available for this asset" instead of a grid of dashes. Check console for errors. Stop play.

- [ ] **Step 6: Commit**

```bash
git add src/client/Controllers/TradeController.client.luau
git commit -m "$(cat <<'EOF'
Wire Analyst Reports tab: panel, fields, lazy fetch, unavailable-asset handling

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Fundamentals tab

**Files:**
- Modify (Studio, via MCP): same `TabContentContainer` — add `Content_Fundamentals`.
- Modify: `src/client/Controllers/TradeController.client.luau`

**Interfaces:**
- Consumes: `renderFieldGrid`, `renderUnavailable` from Tasks 8-9; `GetFundamentalsEvent` remote from Task 6.

- [ ] **Step 1: Create the `Content_Fundamentals` panel in Studio**

Same pattern as Task 9 Step 1, run via `execute_luau` (`datamodel_type: "Edit"`):

```lua
local StarterGui = game:GetService("StarterGui")
local QuoteDetails = StarterGui.TerminalGui.MainBackground.ScreenContainer.TradeScreen.QuoteDetails
local TabContentContainer = QuoteDetails.TabContentContainer
local ContentQuoteDetails = TabContentContainer.Content_QuoteDetails

local existing = TabContentContainer:FindFirstChild("Content_Fundamentals")
if existing then
	existing:Destroy()
end

local ContentFundamentals = ContentQuoteDetails:Clone()
ContentFundamentals.Name = "Content_Fundamentals"
ContentFundamentals.Visible = false

for _, child in ipairs(ContentFundamentals:GetChildren()) do
	if child:IsA("Frame") and string.match(child.Name, "^QF_") then
		child:Destroy()
	end
end

ContentFundamentals.Parent = TabContentContainer

return "created: " .. ContentFundamentals:GetFullName()
```

**Save the Studio place file (Cmd+S).**

- [ ] **Step 2: Add remote ref, container ref, state var, tab wiring**

Add after `local GetAnalystReportEvent = ...`:
```lua
local GetFundamentalsEvent = EventsFolder:WaitForChild("GetFundamentalsEvent")
```

Add after `local ContentAnalystReports = ...`:
```lua
local ContentFundamentals = TabContentContainer:WaitForChild("Content_Fundamentals")
```

In `TabContents`, replace:
```lua
	-- Fundamentals   = TabContentContainer:WaitForChild("Content_Fundamentals"),
```
with:
```lua
	Fundamentals = ContentFundamentals,
```

In the `-- State` section, add:
```lua
local currentFundamentalsData = nil
```

- [ ] **Step 3: Add `FUNDAMENTALS_FIELDS`, `renderFundamentals`, `fetchFundamentals`**

Add near `ANALYST_FIELDS`:

```lua
local FUNDAMENTALS_FIELDS = {
	{ label = "Revenue", key = "totalRevenue", format = "compact" },
	{ label = "Gross Margin", key = "grossMargins", format = "percent" },
	{ label = "Operating Margin", key = "operatingMargins", format = "percent" },
	{ label = "Profit Margin", key = "profitMargins", format = "percent" },
	{ label = "ROE", key = "returnOnEquity", format = "percent" },
	{ label = "ROA", key = "returnOnAssets", format = "percent" },
	{ label = "Cash", key = "totalCash", format = "compact" },
	{ label = "Debt", key = "totalDebt", format = "compact" },
	{ label = "Debt/Equity", key = "debtToEquity", format = "decimal2" },
	{ label = "Free Cash Flow", key = "freeCashflow", format = "compact" },
	{ label = "P/B", key = "priceToBook", format = "decimal2" },
	{ label = "PEG Ratio", key = "pegRatio", format = "decimal2" },
	{ label = "EV/EBITDA", key = "enterpriseToEbitda", format = "decimal2" },
	{ label = "Revenue Growth", key = "revenueGrowth", format = "percent" },
	{ label = "Earnings Growth", key = "earningsGrowth", format = "percent" },
}
```

Add near `renderAnalystReport`/`fetchAnalystReport`:

```lua
local function renderFundamentals(data)
	if data and data.available == false then
		renderUnavailable(ContentFundamentals, "FN_", "Not available for this asset")
		return
	end

	renderFieldGrid(ContentFundamentals, FUNDAMENTALS_FIELDS, data, "FN_")
end

local function fetchFundamentals()
	local data = GetFundamentalsEvent:InvokeServer(currentTicker)
	currentFundamentalsData = data
	renderFundamentals(data)
end
```

- [ ] **Step 4: Wire lazy-fetch and ticker-change reset**

In `switchTab`, add alongside the `AnalystReports` check:
```lua
	if tabName == "Fundamentals" and currentTicker ~= "" and not currentFundamentalsData then
		fetchFundamentals()
	end
```

In `loadTicker`, add alongside `currentAnalystData = nil`:
```lua
	currentFundamentalsData = nil
```

- [ ] **Step 5: Verify via Roblox Studio MCP playtest**

Same as Task 9 Step 5, but for the Fundamentals tab: AAPL shows real revenue/margins/ratios, BTC-USD shows "Not available for this asset". Check console, stop play.

- [ ] **Step 6: Commit**

```bash
git add src/client/Controllers/TradeController.client.luau
git commit -m "$(cat <<'EOF'
Wire Fundamentals tab: panel, fields, lazy fetch

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Option Stats tab

**Files:**
- Modify (Studio, via MCP): same `TabContentContainer` — add `Content_OptionStats` (bare frame + `UIListLayout`, not a clone of the grid layout).
- Modify: `src/client/Controllers/TradeController.client.luau`

**Interfaces:**
- Consumes: `makeLabel` (existing local helper, already in the file), `renderUnavailable` from Task 9; `GetOptionStatsEvent` remote from Task 6.

- [ ] **Step 1: Create the `Content_OptionStats` panel in Studio**

Run via `execute_luau` (`datamodel_type: "Edit"`):

```lua
local StarterGui = game:GetService("StarterGui")
local QuoteDetails = StarterGui.TerminalGui.MainBackground.ScreenContainer.TradeScreen.QuoteDetails
local TabContentContainer = QuoteDetails.TabContentContainer
local ContentQuoteDetails = TabContentContainer.Content_QuoteDetails

local existing = TabContentContainer:FindFirstChild("Content_OptionStats")
if existing then
	existing:Destroy()
end

local ContentOptionStats = Instance.new("Frame")
ContentOptionStats.Name = "Content_OptionStats"
ContentOptionStats.Size = ContentQuoteDetails.Size
ContentOptionStats.Position = ContentQuoteDetails.Position
ContentOptionStats.BackgroundTransparency = 1
ContentOptionStats.Visible = false
ContentOptionStats.Parent = TabContentContainer

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 2)
listLayout.Parent = ContentOptionStats

return "created: " .. ContentOptionStats:GetFullName()
```

**Save the Studio place file (Cmd+S).**

- [ ] **Step 2: Add remote ref, container ref, state var, tab wiring**

Add after `local GetFundamentalsEvent = ...`:
```lua
local GetOptionStatsEvent = EventsFolder:WaitForChild("GetOptionStatsEvent")
```

Add after `local ContentFundamentals = ...`:
```lua
local ContentOptionStats = TabContentContainer:WaitForChild("Content_OptionStats")
```

In `TabContents`, replace:
```lua
	-- OptionStats    = TabContentContainer:WaitForChild("Content_OptionStats"),
```
with:
```lua
	OptionStats = ContentOptionStats,
```

In the `-- State` section, add:
```lua
local currentOptionStatsData = nil
```

- [ ] **Step 3: Add `OPTION_STATS_ROWS` and the custom two-column renderer**

Add near `FUNDAMENTALS_FIELDS`:

```lua
local OPTION_STATS_ROWS = {
	{ label = "Bid", key = "bid", format = "price" },
	{ label = "Ask", key = "ask", format = "price" },
	{ label = "Last", key = "lastPrice", format = "price" },
	{ label = "IV", key = "impliedVolatility", format = "percent" },
	{ label = "Volume", key = "volume", format = "count" },
	{ label = "Open Interest", key = "openInterest", format = "count" },
}
```

Add near `renderFundamentals`/`fetchFundamentals` (this one doesn't use `renderFieldGrid` — the call/put payload is inherently two-sided, not a flat field list):

```lua
local function clearOptionStats()
	for _, child in pairs(ContentOptionStats:GetChildren()) do
		if child:IsA("Frame") and string.match(child.Name, "^OS_") then
			child:Destroy()
		end
	end
end

local function renderOptionStats(data)
	clearOptionStats()

	if not data or data.available == false then
		renderUnavailable(ContentOptionStats, "OS_", "Not available for this asset")
		return
	end

	local header = Instance.new("Frame")

	header.Name = "OS_Header"
	header.Size = UDim2.new(1, 0, 0, 22)
	header.BackgroundTransparency = 1
	header.LayoutOrder = 0
	header.Parent = ContentOptionStats

	makeLabel(header, {
		name = "HeaderLabel",
		text = string.format("Nearest Expiry: %s   ·   Strike: %.2f", tostring(data.expiration), data.strike or 0),
		sz = UDim2.new(1, 0, 1, 0),
		color = TEXT_SECONDARY,
		font = Enum.Font.SourceSansSemibold,
		align = Enum.TextXAlignment.Left,
	})

	local columnsRow = Instance.new("Frame")

	columnsRow.Name = "OS_Columns"
	columnsRow.Size = UDim2.new(1, 0, 0, 20)
	columnsRow.BackgroundTransparency = 1
	columnsRow.LayoutOrder = 1
	columnsRow.Parent = ContentOptionStats

	makeLabel(columnsRow, {
		name = "CallHeader",
		text = "CALL",
		sz = UDim2.new(0.35, 0, 1, 0),
		pos = UDim2.fromScale(0.4, 0),
		color = TEXT_SECONDARY,
		font = Enum.Font.SourceSansSemibold,
		align = Enum.TextXAlignment.Center,
	})

	makeLabel(columnsRow, {
		name = "PutHeader",
		text = "PUT",
		sz = UDim2.new(0.35, 0, 1, 0),
		pos = UDim2.fromScale(0.75, 0),
		color = TEXT_SECONDARY,
		font = Enum.Font.SourceSansSemibold,
		align = Enum.TextXAlignment.Center,
	})

	for i, field in ipairs(OPTION_STATS_ROWS) do
		local row = Instance.new("Frame")

		row.Name = "OS_" .. field.key
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundTransparency = 1
		row.LayoutOrder = i + 1
		row.Parent = ContentOptionStats

		makeLabel(row, {
			name = "Label",
			text = field.label,
			sz = UDim2.new(0.4, 0, 1, 0),
			color = TEXT_SECONDARY,
			align = Enum.TextXAlignment.Left,
		})

		makeLabel(row, {
			name = "CallValue",
			text = formatValue(data.call and data.call[field.key], field.format),
			sz = UDim2.new(0.3, 0, 1, 0),
			pos = UDim2.fromScale(0.4, 0),
			color = TEXT_PRIMARY,
			align = Enum.TextXAlignment.Center,
		})

		makeLabel(row, {
			name = "PutValue",
			text = formatValue(data.put and data.put[field.key], field.format),
			sz = UDim2.new(0.3, 0, 1, 0),
			pos = UDim2.fromScale(0.75, 0),
			color = TEXT_PRIMARY,
			align = Enum.TextXAlignment.Center,
		})
	end
end

local function fetchOptionStats()
	local data = GetOptionStatsEvent:InvokeServer(currentTicker)
	currentOptionStatsData = data
	renderOptionStats(data)
end
```

- [ ] **Step 4: Wire lazy-fetch and ticker-change reset**

In `switchTab`, add alongside the other two tab checks:
```lua
	if tabName == "OptionStats" and currentTicker ~= "" and not currentOptionStatsData then
		fetchOptionStats()
	end
```

In `loadTicker`, add alongside the other two resets:
```lua
	currentOptionStatsData = nil
```

- [ ] **Step 5: Verify via Roblox Studio MCP playtest**

Load "AAPL", click Option Stats, confirm the header shows a real expiration date and strike, and both CALL and PUT columns show plausible bid/ask/last/IV/volume/OI values. Check console, stop play.

- [ ] **Step 6: Commit**

```bash
git add src/client/Controllers/TradeController.client.luau
git commit -m "$(cat <<'EOF'
Wire Option Stats tab: panel, two-column call/put renderer, lazy fetch

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Final verification (full pass)

- [ ] Full playtest: type "AAPL", cycle through Quote Details → Analyst Reports → Fundamentals → Option Stats → back to Quote Details on tab clicks, confirm every tab shows real, sensibly-formatted data and no console errors.
- [ ] Type "BTC-USD", repeat: confirm Quote Details still populates what Yahoo has for crypto, Analyst Reports and Fundamentals both show "Not available for this asset", Option Stats depends on whether Yahoo lists BTC-USD options (likely "Not available" too — verify and note actual behavior, don't assume).
- [ ] Confirm Active Positions still renders correctly after a Buy (unrelated to this plan's changes, but a regression here would mean something broke `GetMarketDataEvent`'s shape in a way `CalculatorModule`/`TradeSystem` didn't expect — quick sanity check).
- [ ] Save the Studio place file one final time.
