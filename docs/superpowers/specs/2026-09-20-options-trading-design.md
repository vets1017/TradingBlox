# Options Trading: Real Multi-Strike Chain + Contract Buy/Sell

## Roadmap context

This is phase 1 of a phased build-out toward the full TradingBlox vision (progression
levels, Portfolio tab, Dashboard modules, risk system, leaderboards, Roblox Market,
funds, social). Each phase gets its own brainstorm → design → implementation-plan
cycle and ships as a working slice before the next one starts. This phase closes out
the last major gap in the existing Trade tab: options are visible (Option Stats tab)
but not tradeable, and the chain UI that's already built has no data behind it.

## Goal

Wire a real, multi-strike option chain into the Trade tab's already-built (but
unwired) Option Chain panel, and let players actually buy/sell option contracts from
it — priced off live bid/ask, settled against balance, tracked in portfolio, and
counted correctly in net worth.

## Current state (verified in code, not assumed)

- `TradeController.client.luau` already has a complete, working `renderOptionChain()`
  renderer and `createStrikeRow()` builder (script-generated `Instance.new` rows, not
  Studio-placed) wired to a `ChainToggle`/`ChainData` panel that expands/collapses.
  The only thing missing is data: the `GetOptionsDataEvent:InvokeServer(ticker)` call
  that would feed it is commented out (~line 1151) with the comment "Uncomment when
  GetOptionsDataEvent is live on the server."
- `GetOptionsDataEvent` remote already exists (declared in `ServerSetup.server.luau`)
  but has no `OnServerInvoke` handler anywhere — calling it today just hangs.
- The Option Stats tab (single nearest-expiration ATM call/put, no greeks) is fully
  wired end-to-end and stays exactly as-is — this work is additive, not a replacement.
- `OptionSystem.server.luau` is a 0-byte stub — no option order execution exists.
- `OptionsChainController.client.luau` is a 0-byte stub, superseded by the inline
  chain rendering already living in `TradeController.client.luau`. Confirmed dead;
  not touched by this work.
- `Data_Manager.server.luau`'s default player schema already reserves
  `Portfolio.Options = {}`, and `CalculatorModule.luau` already has a
  `-- WIP optionPremium(contractID)` stub in its net-worth calc — both anticipate
  this work but are non-functional today.
- **Bug found, fixed as part of this work**: `CalculatorModule.calculateNetWorth`
  currently branches `if Shares ... elseif Options ...` — a player holding both stock
  and option positions only gets one counted toward net worth, never both.

## Repos involved

- `~/Documents/GitHub/TradingBlox` — this repo (Roblox/Luau game).
- `~/Documents/VS/StockDataFetcher` — the Node/Express backend on Render
  (`tradingblox-terminal-backend.onrender.com`), the only thing that can call
  `yahoo-finance2` (Node-only library). Confirmed via its `index.js`: it already has
  `/api/options/:ticker`, which calls `yahooFinance.options(ticker)` — the full
  chain — but discards everything except the single nearest-ATM call/put before
  responding. That full call/put data (multi-strike, multi so far only nearest
  expiration) is genuinely available; it's just not being returned today.

## What yahoo-finance2's `options()` provides (confirmed via source, not assumed)

Per contract (`CallOrPut` type): `contractSymbol` (unique OCC-format ID, e.g.
`AAPL260117C00150000`), `strike`, `bid`, `ask`, `lastPrice`, `volume`,
`openInterest`, `impliedVolatility`, `expiration`. **No delta/gamma/theta/vega** —
matches the existing Option Stats comment ("No greeks - Yahoo doesn't provide
them"). Calling `options(ticker)` with no date param returns only the **nearest**
expiration's chain (`result.options[0]`) plus a top-level `expirationDates` list of
all available expirations — confirmed by the existing backend code's
`result.options && result.options[0]` usage.

## Decisions made during brainstorming

1. **Reuse `contractSymbol` as the position key/ID** instead of inventing our own —
   it's already unique and provided by Yahoo, no parsing needed.
2. **Nearest expiration only for v1.** The backend response includes
   `expirationDates` for a future expiration-switcher, but no switcher UI is built
   this phase — same scope-limiting call the prior Option Stats work made.
3. **Buy at ask, sell at bid** (not a single flat price like share trades use) — the
   data's already fetched per contract, and it's meaningfully more authentic than a
   flat `lastPrice` that's often stale/zero for illiquid strikes.
4. **UI approach: reuse the existing Buy/Sell panel in a "contract mode"** rather
   than per-row inline buy/sell controls or a separate order ticket. Clicking a
   strike's call/put price selects that contract; the existing quantity input +
   Buy/Sell buttons act on it instead of on shares. Rejected alternatives:
   inline-per-row buttons (much bigger new-UI surface across ~20-40 rows, harder to
   test given Studio screen-capture is currently broken) and Option-Stats-only
   trading (wastes the chain UI that already exists and only allows the exact ATM
   strike).
5. **All new UI is script-generated**, matching the existing pattern
   (`createStrikeRow`/`makeLabel` already build entirely via `Instance.new`, not
   Studio-placed templates). This avoids the "Studio UI isn't git-tracked" problem
   that affected the prior Trade-tab-data work — nothing here needs building live in
   Studio by hand.
6. **Position display (positions table, P&L) is out of scope.** Net worth and
   balance update correctly; seeing option holdings listed is Portfolio-tab work
   (a later phase). Data is stored in a shape that makes that easy later (see below).

## Section A — Backend: `StockDataFetcher/index.js`

New, additive route — does not touch or change `/api/options/:ticker`, so the
existing Option Stats tab is unaffected.

### `GET /api/option-chain/:ticker`

```js
app.get("/api/option-chain/:ticker", async (request, response) => {
  const ticker = request.params.ticker.toUpperCase();

  try {
    const result = await yahooFinance.options(ticker);
    const chain = result.options && result.options[0];
    const spotPrice = result.quote?.regularMarketPrice ?? null;

    if (!chain || !chain.calls || chain.calls.length === 0 || spotPrice === null) {
      return response.json({ available: false });
    }

    const STRIKE_RANGE_PCT = 0.20; // keep payload focused/small for a Roblox client
    const minStrike = spotPrice * (1 - STRIKE_RANGE_PCT);
    const maxStrike = spotPrice * (1 + STRIKE_RANGE_PCT);

    const pickFields = (contract) =>
      contract
        ? {
            contractSymbol: contract.contractSymbol,
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

    const callsByStrike = new Map(
      chain.calls.filter((c) => c.strike >= minStrike && c.strike <= maxStrike).map((c) => [c.strike, c]),
    );
    const putsByStrike = new Map(
      (chain.puts || []).filter((p) => p.strike >= minStrike && p.strike <= maxStrike).map((p) => [p.strike, p]),
    );
    const allStrikes = [...new Set([...callsByStrike.keys(), ...putsByStrike.keys()])].sort((a, b) => a - b);

    response.json({
      available: true,
      spotPrice,
      expiration: chain.expirationDate ?? null,
      expirationDates: result.expirationDates ?? [],
      strikes: allStrikes.map((strike) => ({
        strike,
        call: pickFields(callsByStrike.get(strike)),
        put: pickFields(putsByStrike.get(strike)),
      })),
    });
  } catch (error) {
    console.error("Option chain: ", error.message);
    response.status(500).json({ error: "Yahoo " + error.message });
  }
});
```

## Section B — Roblox data layer

### `ServerSetup.server.luau`

Add `PlayerOptionOrderEvent` to `EVENTS`. `GetOptionsDataEvent` already exists — it
finally gets a handler this phase (Section below).

### `MarketDataModule.luau`

New cache + two functions, following the exact `cachedFetch` pattern already used
for `getOptionStats`:

- `getOptionChain(ticker)` — TTL 300s (matches the existing option-stats cadence),
  hits `OPTIONS_CHAIN_ENDPOINT = SERVER_URL .. "/api/option-chain/"`.
- `getOptionQuote(ticker, contractSymbol)` — convenience wrapper: fetches (cached)
  chain via `getOptionChain`, linear-searches `strikes[].call`/`.put` for a matching
  `contractSymbol`, returns that contract's fields or an error. Used by both the
  order system (pricing) and the net-worth fix (mark-to-market) so there's one
  lookup path, not two independently-written ones.

Add the new cache table to the existing `ALL_CACHES` sweep list.

### `API_Manager.server.luau`

New `GetOptionsDataEvent.OnServerInvoke` handler: validate ticker → throttle (same
per-remote cooldown pattern as the other handlers) → `MarketDataModule.getOptionChain(ticker)`
→ return result or `nil` + `warn` on failure. Identical shape to the existing
`GetOptionStatsEvent` handler right above it.

### `OptionSystem.server.luau` (currently empty — implemented this phase)

Mirrors `TradeSystem.server.luau`'s `PlayerOrderEvent` handler, adapted for
contracts:

```lua
PlayerOptionOrderEvent.OnServerInvoke = function(player, action, contractSymbol, ticker, expiration, strike, optionType, contracts)
    -- validate action/ticker/contractSymbol/optionType(C|P)/contracts (positive integer)
    -- market-hours check (options don't trade 24/7 like crypto does)
    -- quote, err = MarketDataModule.getOptionQuote(ticker, contractSymbol)
    -- price = action == "Buy" and quote.ask or quote.bid
    -- Buy: totalCost = price * 100 * contracts; balance check; weighted-average
    --      avgCost into playerData.Portfolio.Options[contractSymbol]
    -- Sell: ownedContracts check; reduce or delete the record; credit proceeds
    -- CalculatorModule.calculateNetWorth(player)
end
```

Position record shape (avoids ever needing to parse the OCC `contractSymbol` back
apart — everything needed is stored explicitly):

```lua
Portfolio.Options[contractSymbol] = {
    contracts = 3,
    ticker = "AAPL",
    expiration = "2026-01-17",
    strike = 150,
    type = "C", -- or "P"
    avgCost = 5.42, -- per-share premium, weighted-average like Shares' AvgCost
}
```

### `CalculatorModule.luau` — bug fix + real implementation

Change `if Shares ... elseif Options ...` to two independent `if` blocks so both
contribute to net worth. Replace the `-- WIP optionPremium(contractID)` stub:

```lua
for contractSymbol, position in pairs(playerData.Portfolio.Options) do
    local quote = MarketDataModule.getOptionQuote(position.ticker, contractSymbol)
    local premium = quote and quote.bid and quote.ask and (quote.bid + quote.ask) / 2
        or quote and quote.lastPrice

    if premium then
        totalOptionValue += position.contracts * premium * 100
    end
end
```

(Mark-to-market uses bid/ask midpoint when both are present — a fairer "what could I
actually get for this" number than the transactional buy-at-ask/sell-at-bid price —
falling back to `lastPrice` for illiquid contracts missing a two-sided quote.)

### `Data_Manager.server.luau`

No structural change — `Portfolio.Options = {}` is already the default. Documented
here only so the record shape above is the single source of truth for what lives in
it.

## Section C — Client: `TradeController.client.luau`

- Uncomment and rewire the `GetOptionsDataEvent` call in `loadTicker()` (~line
  1151): store as `currentOptionData`, call `renderOptionChain(optionData)` (already
  works, just needs real data instead of never being called).
- `createStrikeRow()`: add two transparent, invisible hit-area `TextButton`s
  (script-created, same as every other row element) overlaying the call and put
  bid/ask label areas, each wired to `selectContract(row, "C" | "P")`.
- New state: `local selectedContract = nil` (alongside `currentOptionData` etc).
  `selectContract` builds `{ contractSymbol, ticker, expiration, strike, type }`
  from the clicked row and shows a small script-created indicator near the existing
  Buy/Sell buttons — e.g. `"Now trading: AAPL $150 Call exp 1/17 — Back to Shares"`
  — clicking it calls `clearContractSelection()`, restoring share-trading mode.
- `loadTicker()`: call `clearContractSelection()` alongside the existing
  `currentOptionStatsData = nil` / `clearOptionChain()` reset block (~line 1105) —
  switching tickers invalidates any selected contract from the old ticker's chain.
- `placeOrder(action)`: branch on `selectedContract` — if set, invoke
  `PlayerOptionOrderEvent` with the stored contract fields + `orderQuantity`
  (read as "contracts" instead of "shares" in this mode); otherwise unchanged,
  invokes `PlayerOrderEvent` as it does today.
- `OptionsChainController.client.luau` — confirmed dead, not touched.

No Studio-side manual UI work is required for this phase — everything above is
created the same way the existing chain rows already are, in script.

## Non-goals (explicitly deferred)

- Expiration switching (nearest expiration only; `expirationDates` is returned by
  the backend now so a future selector doesn't need another backend change).
- Option positions shown in the Trade tab's positions table or a Portfolio tab
  (balance/net worth are correct; the *display* of holdings is later work).
- Computed/estimated greeks (delta/theta/gamma/vega) — real IV only.
- Selling contracts short / writing options (only long calls/puts, matching how
  share trading today is long-only).

## Testing plan

- Backend: `curl` the new `/api/option-chain/:ticker` route for a liquid equity
  (e.g. AAPL) and confirm the strike range/shape looks right; confirm the existing
  `/api/options/:ticker` route is unaffected.
- Roblox, live in Studio via MCP: load a ticker, expand the Option Chain panel,
  confirm real strikes/bid/ask render; click a call and a put, confirm the contract
  indicator appears with correct details; Buy a contract, confirm balance debits at
  ask price and `PlayerOptionOrderEvent` returns success; Sell it back, confirm
  balance credits at bid price and the position clears; hold both a stock and an
  option position simultaneously and confirm net worth reflects both (regression
  check for the fixed bug); switch ticker mid-selection and confirm it clears back
  to share-trading mode; attempt a trade while market is closed and confirm it's
  rejected the same way share orders already are.
