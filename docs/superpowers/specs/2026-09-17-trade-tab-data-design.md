# Trade Tab: Live Data for Quote Details, Analyst Reports, Fundamentals, Option Stats

## Goal

Wire real market data into the Trade screen's Quote Details tab (currently rendering
with no real data behind most fields) and build out two brand-new tabs — Analyst
Reports and Fundamentals — plus a basic Option Stats tab, styled to fit the existing
dark ThinkorSwim-inspired terminal look. Active Positions already works end-to-end
(verified live in Studio in a prior session) and is out of scope here except for one
FYI cleanup note. Option Chain and News Feed are explicitly deferred to later work.

## Repos involved

- `~/Documents/GitHub/TradingBlox` — the Roblox/Luau game (this repo).
- `~/Documents/VS/StockDataFetcher` — the Node/Express backend deployed to Render
  (`tradingblox-terminal-backend.onrender.com`), the only thing in the whole system
  that can call `yahoo-finance2` (it's a Node-only library; Roblox can't call Yahoo
  directly). Single file today: `index.js`, one route: `GET /api/candles/:ticker`.

## Constraint that shaped this design

All new data (analyst ratings, fundamentals, option greeks/IV) requires
`yahoo-finance2`'s `quoteSummary()` and `options()` calls, which only run in the
Node backend. Every new data flow therefore needs a new backend route first, then a
Roblox-side fetch/cache/remote to consume it. There is no way to get this data by
touching only the Roblox side.

## What yahoo-finance2 can and can't provide (researched via Context7 + source)

- **Quote Details** (bid/ask/sizes, volume, market cap, beta, PE, dividend yield/amount,
  EPS, ex-div date, earnings date, day/52-week high-low): all available via
  `quoteSummary` modules `summaryDetail`, `defaultKeyStatistics`, `calendarEvents`.
  **VWAP and a single ticker-level "implied volatility" are NOT real Yahoo fields** —
  IV only exists per option contract. Both are dropped from `QUOTE_FIELDS` and
  replaced with real fields (day high/low, 52-week high/low).
- **Analyst Reports**: fully covered by `financialData` (price targets, recommendation
  mean/key, analyst count) + `recommendationTrend` (strong buy/buy/hold/sell/strong
  sell counts).
- **Fundamentals**: covered by `financialData` + `defaultKeyStatistics` + `summaryDetail`
  (revenue, margins, ROE/ROA, cash, debt, debt/equity, FCF, P/B, PEG, EV/EBITDA,
  growth rates).
- **Option Stats**: `options()` gives strike, bid/ask, last price, IV, volume, open
  interest per contract. **It does not return delta/theta/gamma/vega** — real greeks
  need us to compute them ourselves (Black-Scholes) and IV Rank/Percentile need our
  own historical IV tracking. Both are explicitly out of scope for this pass (see
  Decisions below) — v1 Option Stats is the raw nearest-expiration ATM contract data
  only.
- **Non-equity tickers** (crypto like `BTC-USD`, some ETFs/indices): Yahoo has no
  analyst coverage or company financials for these. The backend returns
  `{ available: false }` for Analyst Reports / Fundamentals in that case, and the
  client shows a "Not available for this asset" message instead of an empty-looking
  grid of dashes.

## Decisions made during brainstorming

1. **Option Stats scope**: basic only for v1 — raw nearest-expiration ATM call/put
   data straight from `options()`, no computed greeks, no IV Rank/Percentile. Those
   are future work (greeks need Black-Scholes math; IV Rank needs a new historical
   time-series store in the backend, meaningful only after it's been running a while).
2. **Backend endpoint shape**: several focused endpoints (one per tab), not one
   combined payload — matches the 4 tabs 1:1, keeps each independently cacheable, and
   Roblox only fetches what the active tab needs.
3. **Deploy**: this spec's implementation edits and commits `StockDataFetcher/index.js`
   locally; the user pushes and deploys to Render themselves.

## Section A — Backend: `StockDataFetcher/index.js`

Four new routes, each a thin wrapper over `quoteSummary()`/`options()` that flattens
Yahoo's nested response into exactly the fields Roblox needs, following the same
try/catch → `{ error }` pattern as the existing `/api/candles/:ticker` route.

### `GET /api/quote-details/:ticker`

`quoteSummary(ticker, { modules: ["summaryDetail", "defaultKeyStatistics", "calendarEvents", "price"] })`, flattened to:

```
companyName, bid, ask, bidSize, askSize, volume, avgVolume, marketCap, beta,
trailingPE, forwardPE, dividendYield, dividendRate, exDividendDate, eps,
earningsDate, dayHigh, dayLow, fiftyTwoWeekHigh, fiftyTwoWeekLow
```

Fields Yahoo doesn't have for a given ticker come back `null` (client already renders
`null` as "—").

**Validation note (do during implementation):** confirm empirically whether
`dividendYield` from this yahoo-finance2 version is a raw fraction (0.0056) or
already scaled (0.56) by testing against a known-yield ticker (e.g. KO ~3%) — scale
in the backend flattening step if needed so the client's `percent` formatter
(`%.2f%%`) is correct without guessing.

### `GET /api/analyst/:ticker`

`financialData` + `recommendationTrend`, flattened to:

```
targetHigh, targetLow, targetMean, targetMedian, recommendationMean,
recommendationKey, numberOfAnalysts,
strongBuyCount, buyCount, holdCount, sellCount, strongSellCount
```

(most-recent `recommendationTrend` period). Returns `{ available: false }` if Yahoo
has no analyst coverage for the ticker.

### `GET /api/fundamentals/:ticker`

`financialData` + `defaultKeyStatistics` + `summaryDetail`, flattened to:

```
totalRevenue, grossMargins, operatingMargins, profitMargins, returnOnEquity,
returnOnAssets, totalCash, totalDebt, debtToEquity, freeCashflow, priceToBook,
pegRatio, enterpriseToEbitda, revenueGrowth, earningsGrowth
```

Returns `{ available: false }` if unavailable for the ticker.

### `GET /api/options/:ticker`

`yahooFinance.options(ticker)` → pick the nearest expiration, find the strike closest
to the current price within that expiration, return just that one pair:

```
{ expiration, strike,
  call: { bid, ask, lastPrice, impliedVolatility, volume, openInterest },
  put:  { bid, ask, lastPrice, impliedVolatility, volume, openInterest } }
```

## Section B — Roblox data layer

### `ServerSetup.server.luau`

Add to `EVENTS`: `GetAnalystReportEvent`, `GetFundamentalsEvent`, `GetOptionStatsEvent`.
(`GetOptionsDataEvent` stays reserved, untouched, for the future full Option Chain.)

### `MarketDataModule.luau`

Generalize the existing single-purpose `ChartCache` pattern into a reusable helper:

```lua
local function cachedFetch(cache, key, ttl, fetchFn)
    local cached = cache[key]
    if cached and (os.time() - cached.lastUpdated) < ttl then
        return cached.data, nil
    end
    local data, err = fetchFn()
    if data then cache[key] = { data = data, lastUpdated = os.time() } end
    return data, err
end
```

New functions, each with its own cache table and TTL:

- `getQuoteDetails(ticker)` — TTL 60s (bid/ask/volume move during the day)
- `getAnalystReport(ticker)` — TTL 6 hours (changes rarely)
- `getFundamentals(ticker)` — TTL 6 hours
- `getOptionStats(ticker)` — TTL 300s (matches existing chart-cache cadence)

Extend the existing cache-sweep `task.spawn` loop to sweep all cache tables, not just
`ChartCache`.

### `API_Manager.server.luau`

Three new `OnServerInvoke` handlers (`GetAnalystReportEvent`, `GetFundamentalsEvent`,
`GetOptionStatsEvent`): validate ticker → reuse the existing per-player
`PLAYER_COOLDOWN` throttle → call the matching `MarketDataModule` function → return
result or `nil` + `warn` on failure. Same shape as the existing `GetMarketDataEvent`
handler.

### `GetMarketDataEvent` — enriched, not replaced

Today it returns `{ ticker, price, prevClose }` from candles only. Merge in
`MarketDataModule.getQuoteDetails(ticker)`'s fields into the same returned table, so
`updateHeader`/`renderQuoteDetails` on the client receive real data through the
**same remote call they already make** — only the field list changes (Section C).

## Section C — Client: `TradeController.client.luau` + new Studio panels

### Formatting fixes (`NumberModule.luau`)

`NumberModule.format()` always prepends `$` and never abbreviates — wrong for share
counts (Volume) and unreadable for large dollar figures (a $3T market cap rendered
as a raw 13-digit string). Add:

- `NumberModule.formatShares(amount)` — comma-grouped integer, no `$`.
- `NumberModule.formatCompact(amount)` — `$3.00T` / `$245.67B` / `$12.30M` / `$850.00K`
  style abbreviation, falls back to plain comma-grouped `$X.XX` under 1,000.

Add `"count"` and `"compact"` cases to `TradeController`'s `formatValue()`.

### `QUOTE_FIELDS` (replaces current list — drops `vwap`/`impliedVolatility`, real fields only)

```
Volume(count) · Avg Volume(count) · Beta(decimal2) · Market Cap(compact) ·
Yield(percent) · Div Amount(price) · Ex Date(date) · PE Trailing(decimal2) ·
PE Forward(decimal2) · EPS(decimal2) · Earnings(date) · Day High(price) ·
Day Low(price) · 52-Wk High(price) · 52-Wk Low(price)
```

Keys match the backend's flattened field names exactly (no renaming needed at the
call site).

### `ANALYST_FIELDS` (new)

```
Mean Target(price) · High Target(price) · Low Target(price) · Median Target(price) ·
Rating(auto) · Rating Score 1-5(decimal2) · # Analysts(count) ·
Strong Buy(count) · Buy(count) · Hold(count) · Sell(count) · Strong Sell(count)
```

Same flat grid render pattern as Quote Details — no custom bar-chart widget for v1.

### `FUNDAMENTALS_FIELDS` (new)

```
Revenue(compact) · Gross Margin(percent) · Operating Margin(percent) ·
Profit Margin(percent) · ROE(percent) · ROA(percent) · Cash(compact) ·
Debt(compact) · Debt/Equity(decimal2) · Free Cash Flow(compact) · P/B(decimal2) ·
PEG(decimal2) · EV/EBITDA(decimal2) · Revenue Growth(percent) · Earnings Growth(percent)
```

Same flat grid render pattern.

### Option Stats — custom renderer (not the flat grid)

Payload is inherently two-sided (call vs put for one ATM strike). Header line
(`Nearest Expiry: <date> · Strike: <strike>`), then 6 rows — Bid/Ask/Last/IV/Volume/
Open Interest — each showing Call value | Put value side by side, visually
consistent with the existing Call|Strike|Put styling in `createStrikeRow` (Option
Chain code).

### Non-equity handling

When a tab's data comes back `{ available: false }`, show one centered "Not
available for this asset" label instead of the field grid.

### Studio-side UI (not version-controlled — see Known limitation below)

`Content_AnalystReports` and `Content_Fundamentals` don't exist yet (only their tab
buttons do). Create them as empty Frames under `TabContentContainer`, cloned from
`Content_QuoteDetails`'s existing `UIGridLayout` setup (rows are generated by script
at render time, same as today). `Content_OptionStats` needs no grid — a bare Frame,
rows generated in code via the existing `makeLabel`/`makeSeparator` helpers.

### Lazy loading

Fetch each tab's data only when that tab is first opened for the current ticker,
cached client-side per ticker (`currentAnalystData`, `currentFundamentalsData`,
`currentOptionStatsData`, alongside the existing `currentQuoteData`). Changing
ticker while a non-QuoteDetails tab is active triggers an immediate refetch for that
tab (via a `refreshActiveTab()` call from `loadTicker()`), not just on next tab click.

## Known limitation: Studio UI isn't in git

`default.project.json` doesn't map `StarterGui` at all, and the built place file is
git-ignored. The entire GUI tree (`TerminalGui` and everything under it) lives only
inside the Studio place file, not in this repo. New Frames created for this work
will exist only in Studio's current session/saved place — there is no local source
of truth to diff, review, or restore from if the place file is lost. This spec does
not change that (out of scope), but the plan should save the place file after the
UI panels are built.

## Non-goals (explicitly deferred)

- Option Chain (full strike ladder) — `GetOptionsDataEvent` stays reserved but unwired.
- News Feed — `GetNewsFeedEvent` stays reserved but unwired.
- Computed option greeks (delta/theta/gamma/vega).
- IV Rank/Percentile / Historical Volatility (needs new backend time-series storage).
- Any change to Active Positions functionality (already works). The unused static
  `TableHeader`/`OpenPosition_Template` Studio instances are noted as dead code but
  not touched.

## Testing plan

- Backend: manually curl each new route for an equity (e.g. AAPL) and a crypto ticker
  (e.g. BTC-USD) to confirm real data vs. `{ available: false }` fallback, and
  specifically check the `dividendYield` scale question above.
- Roblox: live Studio playtest via MCP (as used in prior sessions) — load a ticker,
  switch through all 4 tabs, confirm real values render, confirm crypto ticker shows
  "Not available" for Analyst/Fundamentals, confirm cache TTLs behave (rapid re-fetch
  within TTL window returns cached data — verify via backend request logs).
- Visual: screenshot or live-inspect the new panels in Studio to confirm layout
  reads cleanly at the existing screen size before calling this done.
