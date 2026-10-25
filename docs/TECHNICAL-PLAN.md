# TradingBlox Technical Plan

Architecture and phased roadmap for the product spec in [`GAME-DESIGN.md`](GAME-DESIGN.md) (the GDD).
Written 2026-10-24 against branch `portfolio-tab` at `bf0e1d5` and the backend repo
`~/Documents/VS/StockDataFetcher` at `8a571d3` (plus an uncommitted edit). No code changes come with
this document. Each phase below still gets its own spec and plan in `docs/superpowers/`, as earlier
work did.

## Summary

- **Where things stand.** About 6,500 lines of Luau cover most of the GDD's research and trading
terminal (§4) for a single player. That includes live quotes and candles, a full chart, fundamentals,
analyst and option data, market orders for shares, long option contracts, a watchlist and a Portfolio
tab with net-worth history. Nothing exists yet for social trading (§2), the Roblox market (§6), funds
(§7), progression (§8) or leaderboards (§9).
- **The main blocker is the foundation, not missing features.** A player's data can be lost: there is
no session lock and no autosave, and a failed load gets saved over the real record. Server scripts
share state through `_G`. The market-data backend has no cache and no authentication, and every live
price costs two calls to an unofficial Yahoo API. The 371-instance UI tree isn't in git. Market hours
go wrong on 2026-11-01, when daylight saving time ends.
- **Architecture.** Game servers stay authoritative over all money, positions and scores. Shared
modules hold the pure logic so it can be tested outside Roblox. One backend gateway handles every
outside source, with caching, batching and a swappable provider. Player and social state stays in
Roblox storage for the MVP.
- **MVP = Phase 0 + Phase 1.** Phase 0 hardens the foundation. Phase 1 builds the core loop: levels 1–2
of progression, limit orders, portfolio analytics, public profiles, two leaderboards and a working
Dashboard. Social trading comes next because it is the GDD's headline feature, then the Roblox market.
- **Decisions were made on 2026-10-24** (§6): every recommendation was accepted, the memecoins plan is
shelved, and Phases 0 and 1 are done. Phase 2 started on 2026-10-25 (decisions and build order in §6).

## 1. Current state

### Repository and tooling


| Item            | State                                                                                                                                                                                                                                            |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Build           | Rojo 7.7.0-rc.1 through Aftman. `src/server` → ServerScriptService, `src/client` → StarterPlayerScripts, `src/shared` → ReplicatedStorage, `src/gui` → StarterGui                                                                                |
| Dependencies    | None: no Wally and no packages                                                                                                                                                                                                                   |
| Lint and format | selene, StyLua and Lune pinned in `aftman.toml`; `stylua.toml`; selene and StyLua both clean                                                                                                                                                     |
| Tests and CI    | Lune unit tests for the pure modules (`tests/`). GitHub Actions runs selene, StyLua, the tests and a Rojo build. Studio checks through the MCP tools for the rest                                                                                |
| Place file      | Git-ignored. `TerminalGui` (371 instances; Dashboard, Charts and Trade screens) is tracked as `src/gui/TerminalGui.rbxmx`                                                                                                                        |
| Backend         | `StockDataFetcher`: Node, Express and `yahoo-finance2` v3 on Render. Candles, quote details, analyst, fundamentals, options, option chain, news, movers, profile, batch quotes and splits; every Yahoo call cached in memory. No auth, open CORS |
| Player data     | ProfileStore: one session-locked `PlayerData_v2` profile per player, autosaved every 60 s                                                                                                                                                        |


### What the GDD needs vs. what exists

✅ built · ◐ partial · ✗ missing


| GDD    | Capability               | Status | Notes                                                                                                                                                                                                                           |
| ------ | ------------------------ | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| §1     | $50,000 starting capital | ✗      | Code starts players at $10,000 (`Data_Manager`)                                                                                                                                                                                 |
| §4     | Asset overview           | ✅      | Price, change, quote details, 52-week range, dividends, earnings date, mini chart (Trade screen)                                                                                                                                |
| §4     | Fundamentals             | ◐      | Revenue, margins, free cash flow, cash, debt, ROE/ROA, growth, valuation ratios. No net income or EBITDA                                                                                                                        |
| §4     | News                     | ✗      | `GetNewsFeedEvent` is declared but has no handler and no backend route. The Trade screen's news panel is empty                                                                                                                  |
| §4     | Technical analysis       | ◐      | 1m to 1D candles, zoom, pan, crosshair, SMA/EMA 20/50, trend and horizontal lines. No RSI, MACD, VWAP, Bollinger Bands, ATR, volume profile, or support/resistance                                                              |
| §4, §8 | Order types              | ◐      | Market orders only, long-only shares, Active Trader presets. No limit, stop, stop-limit, bracket or trailing orders                                                                                                             |
| §4, §8 | Options                  | ◐      | Nearest-expiration chain, long calls and puts at bid/ask. No multiple expirations, no Greeks, **no settlement at expiry**, no writing or spreads                                                                                |
| §8     | Short selling, margin    | ✗      |                                                                                                                                                                                                                                 |
| §5     | Position details         | ◐      | Ticker, quantity, average cost, price, value, unrealized P/L, % return. No portfolio weight. Daily P/L only on the Trade screen's table                                                                                         |
| §5     | Portfolio analytics      | ◐      | Net-worth history (24h/7d/30d). No realized P/L (no trade log), win rate, drawdown, volatility, Sharpe, beta, sector allocation or leverage                                                                                     |
| §3     | Dashboard                | ◐      | Greeting, NYSE countdown, Account Info ("option power" is a placeholder), Watchlist and Event Feed widgets (built in Studio, not wired up). No market overview, performance, social or allocation modules, and no customization |
| §3     | Market status            | ◐      | Open/closed and countdown. No pre-market or after-hours, no early closes, no earnings or economic calendar, and the daylight-saving bug                                                                                         |
| —      | Watchlist                | ✅      | Saved, up to 20 tickers (Charts screen)                                                                                                                                                                                         |
| §2     | Social trading           | ✗      | Only the player's own Portfolio header exists                                                                                                                                                                                   |
| §6     | Roblox-native market     | ✗      | A different feature is planned instead (player memecoins, plan `f417577`, not built)                                                                                                                                            |
| §7     | Funds                    | ✗      |                                                                                                                                                                                                                                 |
| §8     | Progression              | ✗      | Everything is unlocked for everyone, including options                                                                                                                                                                          |
| §9     | Leaderboards             | ✗      |                                                                                                                                                                                                                                 |


### Defects and risks in the current code, worst first

Status after Phase 0: 1–3 and 5–9 are fixed. 4 is half done (cache and batching; no auth). 10 is open.

1. **Player data loss.**
  - Saves happen only on leave and on shutdown, so a server crash loses the whole session.
  - There's no session lock, so a quick server hop can let the old server's save overwrite the new
  server's data.
  - If `GetAsync` fails, the player gets default data, and that default is later saved over their
  real record.
2. **Market hours and daylight saving.** `MarketHoursModule` hardcodes 13:30–20:00 UTC, which is New
  York summer time. From 2026-11-01 the game opens and closes an hour early, and orders are gated
   wrong for about four months of the year.
3. **The UI isn't in version control.** The place file is the only copy of the Dashboard, Charts and
  Trade screens.
4. **The backend has no cache or auth, and depends on an unofficial API.**
  - Every live price costs two Yahoo calls (`chart` plus `quote`). Calls grow with player count, not
   with the number of distinct symbols, and Yahoo has already returned 429 errors.
  - Anyone on the internet can use it as a free Yahoo proxy.
5. **Remotes that make HTTP calls have no rate limit.** These are `GetMarketDataEvent`,
  `GetPositionsEvent`, `GetPortfolioEvent` and `GetWatchlistEvent`. Only part of `API_Manager`
   throttles.
6. **Server scripts share state through `_G`** and depend on start order.
7. **Options never settle.** An expired contract silently counts as $0 instead of paying its intrinsic
  value.
8. **Stock splits aren't handled.** Candles are split-adjusted but positions aren't, so a split
  misprices a holding.
9. **Share fills ignore bid and ask, and nothing checks how old a quote is.** Shares fill at the last
  price. A player with a faster quote elsewhere can trade against a stale one.
10. **Undercounted net worth is still shown.** The status bar and the Portfolio header show a lower
  net worth when the backend fails to price a holding. The history chart already skips those values.

## 2. Proposed architecture

### Principles

1. **Server-authoritative.** Every balance, position, order, score and level is computed and stored on
  the server. Clients only display data and send requests.
2. **One gateway to the outside world.** Game servers call only the backend. The backend calls market
  data providers and Roblox's web APIs.
3. **Pure logic lives in shared modules.** Pricing, P/L, analytics, order rules, progression rules,
  option math and the market calendar run without Roblox APIs, so they can be unit-tested anywhere.
4. **Roblox storage for the MVP.** Move data to an external database only when a feature needs queries
  Roblox storage can't do.
5. **Evolve, don't rewrite.** Existing scripts move into the new structure one at a time, and each
  step ships.

### Topology

```
┌──────────────────── Client (one per player) ───────────────────┐
│ Screen controllers ──► ClientState (prices, portfolio,          │
│ (Shell, Dashboard,       profile, feed, notifications)          │
│  Portfolio, Trade,  ◄── Navigation (openTicker, openProfile …)  │
│  Charts, Social …)       UI kit (components on Theme tokens)    │
└───────────┬──────────────────────────────▲─────────────────────┘
   RemoteFunction (requests)        RemoteEvent (server pushes)
┌───────────▼──────────────────────────────┴─────────────────────┐
│ Game server                                                     │
│  Remotes layer: one registry, argument checks, per-player limits│
│  Services: PlayerData · MarketData · Orders · Portfolio ·       │
│            Progression · PublicProfile · Social · Leaderboards ·│
│            Funds                                                │
│  Storage: DataStore · OrderedDataStore · MemoryStore ·          │
│           MessagingService                                      │
└───────────┬────────────────────────────────────────────────────┘
   HTTPS with a shared secret (Secrets store); ≤ 500 requests/min per server
┌───────────▼────────────────────────────────────────────────────┐
│ Backend gateway (StockDataFetcher, extended)                    │
│  Response cache · batch routes · auth · health check            │
│  Equity data adapter (Yahoo now, a licensed provider later)     │
│  Roblox experience-stats ingest → Roblox-market price model     │
└────────────────────────────────────────────────────────────────┘
```

### Server (`src/server`)

One bootstrap script, `Main.server.luau`, requires the service modules in dependency order and starts
them. That replaces both `_G` and the reliance on script start order. Existing scripts migrate one at a
time behind temporary `_G` shims.


| Service                | Owns                                                                                     | Replaces or extends                                    |
| ---------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `PlayerDataService`    | Loading and saving profiles (session lock, autosave, schema migrations), `get(player)`   | `Data_Manager`, `_G.PlayerData`, `_G.UpdatePlayerStat` |
| `MarketDataService`    | Per-server quote table, the price pump, the instrument registry, staleness checks        | Wraps `MarketDataModule`                               |
| `OrderService`         | Order checks, unlock checks, market hours, fills, pending orders, settlements, trade log | `TradeSystem`, `OptionSystem`                          |
| `PortfolioService`     | Valuation, net-worth history, realized P/L, analytics snapshot                           | `CalculatorModule`, `PortfolioSystem`                  |
| `ProgressionService`   | XP, levels, unlocks                                                                      | New                                                    |
| `PublicProfileService` | The public "financial résumé" snapshot                                                   | New                                                    |
| `SocialService`        | Follows, feed, theses, reactions, notifications                                          | New                                                    |
| `LeaderboardService`   | Metric writes, cached pages, eligibility rules                                           | New                                                    |
| `FundService`          | Funds, roles, shared portfolio transactions                                              | New                                                    |


### Shared (`src/shared`)

- `Config/`: `Instruments` (asset class, trading hours, unlock level), `Progression` (what each level
unlocks and requires), `Economy` (starting cash, fees), `Leaderboards` (periods, eligibility).
- `Domain/`, pure logic with no Roblox APIs:
  - `OrderRules`, `PnL`, `Analytics` (returns, drawdown, volatility, Sharpe, beta)
  - `OptionsMath` (Black-Scholes Greeks from implied volatility, since Yahoo provides no Greeks)
  - `MarketCalendar` (New York time with daylight saving, holidays, early closes; replaces the hardcoded
  hours)
  - The existing `PortfolioHistoryModule` math, `NumberModule` and indicator math
- `Net/Remotes`: remote names and argument checks, shared by client and server.
- `UI/`: the component kit (Panel, Text, Pill, Button, Table, LineChart, Tabs, Modal, Toast). It's
extracted from the pattern `ShellController` and `PortfolioController` already use, and the line
chart is shared with the Trade screen's mini chart.
- Existing `Theme`, `Navigation`, `ChartRenderer`, `IndicatorModule` and `DrawingModule` stay.

### Client (`src/client`)

- Keep one controller per screen. Add a `ClientState` module that subscribes to server pushes (prices,
portfolio, profile, notifications), so screens stop polling separately.
- Grow `Navigation` into a small router: `openTicker` exists; add `openProfile`, `openFund` and
`openThesis`.
- Build new screens in code with the UI kit, which `ShellController` and `PortfolioController` have
already proven. Existing Studio-built screens stay until they need major work, but get exported to
git in Phase 0.
- **Recommendation:** don't adopt a declarative UI library such as Fusion or React-lua yet. Revisit at
the start of Phase 2, which adds the most new UI.

### Market data

- **Backend:**
  - Cache responses by route, symbol and parameters. Quotes ~5–15 s while the market is open and longer
  when closed; candles by timeframe; fundamentals and analyst data for hours.
  - Add a batch quote route (`/api/quotes?symbols=…`).
  - Require a shared secret, stored in Roblox's Secrets store.
  - Wrap Yahoo behind an adapter so a licensed provider can replace it without changes in the game.
  - Add a health route and add timeouts.
- **Game:**
  - `MarketDataService` keeps one quote table per server.
  - A price pump refreshes, in batches every few seconds, the symbols that players in that server hold,
  watch or are viewing, and pushes changes to clients.
  - Trades, net worth, watchlists and positions read from that table and fetch only on a miss or a
  stale quote.
- **Fills:** buy at the ask and sell at the bid when the quote has them. Reject the order if the quote
is older than a set limit (the stale-quote check).
- **Budget example:** 30 players in one server hold or watch about 150 distinct symbols. At 50 symbols
per batch, that's 3 calls every 10 s, about 18 per minute plus candles on demand, far under the limit
of 500 per minute. Yahoo calls then grow with distinct symbols, not with players. The batch size Yahoo
accepts needs testing.
- **Instrument registry:** each symbol maps to an asset class (`equity`, `etf`, `crypto`, `option`,
`roblox`). That decides its trading hours, unlock level and price source.

### Trading engine

- **Order types are data:** market, limit, stop and stop-limit first; bracket and trailing later.
- **Offline catch-up.** A player's profile is loaded only while they're online, because it's
session-locked. So pending orders are checked live while the player is online, then caught up at
login against the candles since the order was placed: a limit order fills at its limit price if the
price range crossed it.
  - The same catch-up step handles option settlement at expiry (in the money pays intrinsic value from
  the underlying's close; out of the money expires worthless), stock splits (adjust shares and average
  cost) and later dividends and margin calls.
- **Every fill goes into a trade log.** Realized P/L is computed from average cost. Each fill also
sends events to progression (XP), the feed and stats.
- **Short selling and margin (level 3)** need buying power, a maintenance requirement and liquidation,
all using the same catch-up step.

### Where data is stored


| Data                                                                                                                                         | Store                                                            | Key            | Notes                                                                                                                 |
| -------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | -------------- | --------------------------------------------------------------------------------------------------------------------- |
| Player profile: cash, positions, pending orders, recent trade log, net-worth history and daily series, stats, progression, follows, settings | DataStore `PlayerData_v2`, session-locked (ProfileStore pattern) | userId         | Autosave about every 60 s. Migrated from v1 or started fresh (§6). Trade log capped at about 500 fills in the profile |
| Older trade-log pages                                                                                                                        | DataStore `TradeLog`                                             | userId + page  | Only if a full trade history view is wanted                                                                           |
| Public profile snapshot                                                                                                                      | DataStore `PublicProfile`                                        | userId         | Small. Written on save. Lets other servers read a profile without the private data                                    |
| Followers                                                                                                                                    | DataStore `Followers`                                            | userId         | `UpdateAsync`, because the writes come from other servers (rare)                                                      |
| Theses and posts                                                                                                                             | DataStore `Posts`, plus index keys by author and by ticker       | postId         | Raw text stored, filtered when displayed                                                                              |
| Leaderboards                                                                                                                                 | OrderedDataStore, one per metric and period                      | userId         | Integers only (cents, basis points). Cached per server because the read budget is small                               |
| Live feed, trending counters, locks                                                                                                          | MemoryStore sorted maps and hash maps                            | —              | Small hot data with expiry. Never the source of truth (memory quota below)                                            |
| Live notifications                                                                                                                           | MessagingService                                                 | topic per kind | 1 KB messages. Offline players get an inbox stored in their profile                                                   |
| Funds                                                                                                                                        | DataStore `Funds`                                                | fundId         | `UpdateAsync` transactions with idempotency keys                                                                      |
| Roblox-market stats and prices                                                                                                               | Backend's own store                                              | —              | Single source of truth for every server                                                                               |


### Social trading (GDD §2)

- **Every feed item has a type and label.** `ExecutedTrade` items are generated from the trade log, so
they're verifiable. `Thesis` items are structured (ticker, direction, target, time horizon, text).
`Milestone` items mark achievements. This covers the GDD's split between executed trades, simulated
trades and opinions (line 48): an "idea" without a trade is a thesis.
- **Follows:** a `Following` list in the profile (capped around 200); follower counts in `Followers`.
- **Feed reads, with no fan-out on write:**
  - A capped global stream lives in MemoryStore.
  - The "Following" view filters that stream and adds each followed player's public snapshot, which
  carries their last ~10 activity items.
- **Text:**
  - Filter with `TextService` when a post is published.
  - Filter again when stored text is displayed, as the docs require for stored text.
  - Cache filtered results briefly, since filtering on every view is expensive.
- **Sharing executed trades is a per-player setting.**
- **Comments and direct messages are deferred** until a policy review (§3). Social Phase 1 uses
reactions only.

### Leaderboards (GDD §9)

- Each board has a period (week, month, all-time) and eligibility rules: minimum trades, active days
and account age. That keeps alt accounts and one lucky trade from dominating, as §9 asks.
- Period returns come from the daily net-worth series. Risk-adjusted boards use a Sharpe-style ratio
over at least ~20 days. Consistency is the share of positive weeks. Best analyst is the hit rate on
structured theses, weighted by horizon, with a minimum sample.

### Roblox-native market (GDD §6)

- **Ingest on the backend.** Every 5–10 minutes the backend pulls public stats for a curated allowlist
of experiences (players online, visits, favorites, votes, last update) and stores them as time series.
Game servers can't call those Roblox web APIs themselves (§3).
- **The price model runs on the backend,** so every server sees the same prices. Version 1 is a smoothed
function of the metrics (for example, trend in players online, visit growth and like ratio) with a cap
on daily moves. The research page labels each input "Observed" and the price "Simulated," as GDD line
214 requires.
- **Same quote and candle routes, with asset class `roblox`.** The game reuses `MarketDataService`,
`OrderService` and the charts as-is. Trading is open 24/7.
- **Curation:**
  - Experience names come from outside the game, so they go through the text filter.
  - The allowlist keeps out unsuitable experiences.
  - An experience that goes private or is deleted is delisted, and positions settle at its last price.

### Funds (GDD §7)

- A fund is one `Funds/<fundId>` record holding its profile, strategy, rules, members and roles (a
permission table), shared portfolio, value history and unit ledger.
- **Capital:** members put in cash for units priced at the fund's value per unit, and withdraw by
redeeming units. This keeps each member's return fair.
- **Trades:** trades by Traders and Portfolio Managers run as `UpdateAsync` transactions on the fund
key, because members sit in different servers.
  - The price is fetched first.
  - The transform function checks role permissions, fund rules and cash, and it must not yield.
  - Each order carries an idempotency key.
- Funds unlock at level 4. Fund leaderboards use each fund's value history.

### Progression (GDD §8)

- `Config/Progression` lists what each level unlocks: instruments, order types, indicators, analytics
and funds. It also lists requirements, earned as XP from varied activity: trading on several days,
holding periods, theses, tutorials and risk discipline. **Capital isn't a requirement,** matching §8.
- Server services enforce the unlocks; the client shows locked features and what's needed to unlock
them.
- Options are currently open to everyone. Gating them at level 3 is a deliberate change in behavior.

### Security and anti-exploit

- **Every remote** gets type checks and a per-player rate limit through one shared wrapper.
- **The server prices everything.** Client-sent prices or values are never trusted.
- **Each order carries an idempotency key,** so double-clicks and retries can't fill twice.
- **Stale-quote check on fills,** with an optional short delay before filling.
- **Leaderboard integrity:** eligibility rules, an account-age minimum and review of outliers.
- **Monetization:** Robux must never buy cash, positions or anything that affects returns or rankings.
That would be pay-to-win, and Roblox forbids exchanging Robux in connection with gambling (§3).
Cosmetics, profile themes and extra watchlist slots are fine.
- **Backend:** shared secret, rate limits, and no personal data stored beyond user IDs.

### Testing and tooling

- Pin selene and StyLua in `aftman.toml`, and add `stylua.toml`.
- Unit-test the pure `Domain/` modules with Lune, a standalone Luau runtime, in GitHub Actions. Keep
Studio checks through the MCP tools for integration testing.
- Add a Studio-only test mode (market-hours override, fixed prices, a separate DataStore scope).
It replaces injected test scripts and test trades on the real account.

## 3. Technical limitations and dependencies

### Roblox platform

Checked against create.roblox.com on 2026-10-24 unless marked *community-reported*.


| Limit                                              | Value                                                                                                                                                                                                   | Impact                                                                                    |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Outbound HTTP                                      | 500 requests/min per server. Going over stalls requests for about 30 s                                                                                                                                  | Batching and caching are required (see the market-data budget example)                    |
| Open Cloud from a game server                      | Separate 2,500/min limit, but only some endpoints are callable (Assets, Groups, Places, Users, among others)                                                                                            | Roblox experience stats aren't among them                                                 |
| Roblox web APIs (`games.roblox.com`)               | Can't be called from a game server — *community-reported*                                                                                                                                               | The Roblox market needs the backend to fetch them                                         |
| DataStore request budgets (per server, per minute) | Standard read and write: 60 + 40 × players. List and ordered list: 5 + 2 × players. Ordered write: 30 + 5 × players                                                                                     | Leaderboard pages have to be cached per server                                            |
| DataStore sizes                                    | 4 MB per key. Per key per minute: 25 MB read, 4 MB write. Total storage: 500 MB + 1 MB × lifetime users                                                                                                 | A profile holding ~1,000 history points and ~500 trades is well under these               |
| MemoryStore                                        | Memory: 64 KB + 1.2 KB × concurrent users (whole experience). Requests: 1,000 + 120 × concurrent users per minute. 32 KB per item. Longest expiry 45 days. About 30,000 request units/min per partition | Only small hot data: feed, trending, locks                                                |
| MessagingService                                   | 1 KB per message. Send limits grow with player count — *community-reported*                                                                                                                             | Notifications only, not syncing data                                                      |
| Text filtering                                     | Required for user-typed text, for stored text when displayed, and for text from outside sources (news headlines, experience names)                                                                      | Filtering costs a call each time; cache the results                                       |
| Chat age checks                                    | Roblox now requires age checks for chat. `Chat:CanUsersChatAsync` checks age rules between two users. No official guidance was found for custom communication features                                  | Comments and direct messages are deferred until reviewed                                  |
| Servers only run while occupied                    | Servers shut down when empty; `BindToClose` has about 30 s                                                                                                                                              | No background jobs for offline players: catch-up at login, or backend jobs                |
| `loadstring` is unavailable                        | —                                                                                                                                                                                                       | "Algorithmic tools" (GDD §8) must be a rule builder driven by data, not user-written code |


### Roblox policy

This is not legal advice. Read the current Community Standards and the experience questionnaire before
launch.

- **Simulated gambling is banned,** along with exchanging Robux or valuable items in connection with
gambling. Keep Robux away from trading outcomes. Of everything planned, the memecoin design (a
pump.fun-style bonding curve, Robux boosts planned for slice 2) is the most likely to read as
simulated gambling.
- **Content that claims to give authoritative investment information or advice is banned.** Present the
game as a simulation and as education. Add "Simulated, not financial advice" labels to Analyst
Reports, theses and the "Best Analyst" board.

### External market data

- **Yahoo through `yahoo-finance2`** is unofficial, with no service guarantee and no published rate
limits, and it has already returned 429 errors. Secondary sources say Yahoo's terms forbid commercial
redistribution without a license; I couldn't read the terms themselves. It's fine for prototyping.
Before a public launch, pick a licensed provider whose terms allow showing the data to players,
possibly delayed data, which tends to cost less. That's a budget decision (§6).
- **Data situations the game must handle:** delayed vs. real-time quotes, pre-market and after-hours
prices, trading halts, stock splits, dividends, option expiries, crypto trading 24/7, and holidays and
early closes.
- **Hosting:** a single Render instance. Whether it sleeps when idle depends on the plan, which I
haven't checked. Every trade depends on it, so add health checks and timeouts. When quotes go stale,
disable trading for the affected symbols rather than for everything.

### Roblox experience data (for the GDD §6 market)

- Players online, visits, favorites, votes and last-update time are public through Roblox's web APIs
(*community-reported*). Revenue and retention aren't public; the GDD already says "where available."
- Rate limits are undocumented and the endpoints can change without notice. Ingest on the backend, cache
the results, poll infrequently and use the allowlist.

## 4. Phased implementation plan

Sizes are relative: **S** < **M** < **L** < **XL**. Each phase ships on its own and gets its own spec
and plan.

### Phase 0: Foundations (L). Blocks everything else

**Do this week, separately:** fix market hours for daylight saving before 2026-11-01. This is a
`MarketCalendar` change, size S.

1. ✅ **Merge and decide:** merge `portfolio-tab` and settle the questions in §6.
2. ✅ **Data safety:**
  - Session-locked profiles (vendored ProfileStore), autosave, and refusing to load (kick and retry)
   instead of saving defaults.
  - `PlayerData_v2` with a schema version and migrations; $50,000 starting cash.
3. ✅ **Services bootstrap:** `Main.server.luau` plus `PlayerDataService` first, keeping `_G` shims until
  each script has moved. (Done as `Data_Manager.server.luau`; every script has moved and the shims are gone.)
4. ✅ **Remotes layer:** one registry, argument checks, per-player rate limits, and RemoteEvents for
  server pushes. (`ServerSetup` registry; `RemoteGuard` token buckets on every remote.)
5. ◐ **Market data:**
  - Backend cache, batch quotes, shared-secret auth, health route. (Cache and batch quotes done;
  auth and the health route are not.)
  - Server quote table and price pump; fills at bid/ask; stale-quote check. (All but the price pump:
  prices are fetched in batches on demand, not pushed.)
6. ✅ **Trading correctness:** trade log and realized P/L, option settlement at expiry, stock splits, and
  the offline catch-up step at login.
7. ✅ **UI in git:** export `TerminalGui` to a Rojo-tracked `.rbxmx` model and map StarterGui.
8. ✅ **Tooling:** pin selene and StyLua, add Lune unit tests for `Domain/` and `PortfolioHistoryModule`,
  and run both in CI. (There's no `Domain/` folder; the tests cover every pure module instead.)

**Done when:** no code path can lose or overwrite a profile; every remote is rate-limited; Yahoo calls
grow with distinct symbols, not players; market hours are right in both summer and winter time; expired
options and splits settle correctly; CI is green.

### Phase 1: MVP, "trade, track, compete" (XL)

- **Progression levels 1–2:** XP, levels and the unlock table. Stocks and ETFs at level 1. Fundamentals,
analytics and limit orders at level 2. Options gated to level 3. A short tutorial for new players.
- **Limit orders:** pending orders, checked live, caught up at login, and cancellable.
- **Portfolio:**
  - Daily P/L, realized vs. unrealized P/L, and portfolio weight per position.
  - Allocation by position and by sector (needs a backend sector route).
  - Win rate, average gain and loss, and maximum drawdown.
- **Public profiles:** the snapshot, plus a profile screen for any player (in-server, or by username).
It shows value, return, win rate, drawdown, trade count and join date.
- **Leaderboards:** Highest Portfolio Value (all-time) and Highest Return (weekly and monthly), with
eligibility rules.
- **Dashboard:**
  - Real Account Info with buying power.
  - Portfolio Performance.
  - Market Overview: indices, top gainers and losers (needs a backend route).
  - The Watchlist widget wired up.
  - News: needs a backend route; headlines go through the text filter.
- **Done when:** a new player starts with $50,000, can learn, trade stocks and ETFs with market and limit
orders, follow their analytics, show up on leaderboards and view other players' profiles. Everything
survives a server crash.

### Phase 2: Social trading (L)

- Following players. A feed of executed trades (per the sharing setting), structured theses and
milestones. Reactions.
- Notifications: an in-game inbox, with live delivery through MessagingService.
- Asset discovery from in-game signals: how many players watch, trade or write theses about an asset.
- A Social module on the Dashboard. Reporting, blocking and muting.
- **Done when:** a player can follow someone, see their verified trades and theses within seconds
across servers, and find popular assets. All text goes through the filter.

### Phase 3: Roblox-native market (L)

- The backend pulls stats for the allowlisted experiences; price model v1; quote and candle routes with
asset class `roblox`.
- An in-game research page that separates observed stats from simulated prices; trading 24/7; Roblox
Market filters on the Dashboard and leaderboards.
- **Done when:** players can research and trade about 50 allowlisted experiences, prices agree across
servers, and every number is labeled observed or simulated.

### Phase 4: Advanced trading and risk, the rest of levels 2–3 (XL)

- Stop and stop-limit orders. Short selling and margin (buying power, maintenance requirement,
liquidation).
- Options at level 3: several expirations, Greeks from `OptionsMath`, a display of combined positions.
- Indicators: RSI, MACD, VWAP, Bollinger Bands, ATR, volume profile.
- Risk analytics: volatility, Sharpe ratio, beta against SPY, concentration, leverage, options exposure.
- Leaderboards: Best Risk-Adjusted Return, Consistency, Best Trader and Best Analyst (thesis scoring).

### Phase 5: Investment funds (XL)

- Creating a fund; members, roles and permissions; contributions and redemptions in units.
- A shared portfolio traded through transactions; fund research, performance and risk; fund
leaderboards and competitions. Unlocks at level 4.

### Phase 6: Professional tier (L)

- Bracket and trailing-stop orders, hedging tools, and a rule builder for "algorithmic" strategies.
- Customizable Dashboard layouts, pre-market and after-hours data, and earnings and economic calendars.

### Not planned

- Copy trading: the GDD says it would need to be added deliberately.
- Comments and direct messages: until the chat-policy review.
- Player memecoins: pending decision 1 below.

## 5. Phase dependencies

```
Phase 0 ──► Phase 1 (MVP) ──► Phase 2 Social ──► Phase 4 Advanced trading ──► Phase 5 Funds ──► Phase 6
                     └──────► Phase 3 Roblox market (needs only Phases 0–1; can run in parallel with 2)
```

## 6. Decisions

Decided 2026-10-24: Kevin accepted every recommendation and asked to begin Phase 1.

1. **The memecoins + Pulse plan** (`f417577`) is **shelved.** It isn't in the GDD, the GDD's Roblox
  market fills the "Roblox-native market" role, and memecoins carry the most gambling-policy risk.
2. **Start fresh on `PlayerData_v2` with $50,000.** Balances aren't migrated; the game hasn't launched,
  so only test accounts are affected.
3. **Market data:** keep prototyping on Yahoo, and choose a licensed provider before a public launch.
4. **ProfileStore,** vendored as one module, for session-locked player data.
5. **UI:** the in-house component kit; revisit a declarative library at the start of Phase 2.
6. **Social storage:** Roblox storage for the MVP.
7. `**portfolio-tab**` is merged into `main`.

### Phase 1 build order

Phase 1 starts with the Phase 0 pieces it can't ship without: safe player data and the trade log. The
rest of Phase 0 (backend cache, rate limits, UI export, CI) runs alongside.

1. ✅ Market hours: daylight saving, observed holidays, early closes and the 30-minute-early open.
2. ✅ Player data v2: ProfileStore, $50,000 start, autosave and session lock, `_G` kept as a shim (removed
   later in Phase 0).
3. ✅ Trade log and realized P/L.
4. ✅ Progression, levels 1–3 gating.
5. ✅ Portfolio analytics, including sector allocation.
6. ✅ Public profiles (holdings stay private until Phase 2's sharing setting).
7. ✅ Leaderboards: net worth, weekly and monthly return.
8. ✅ Limit orders, plus a preset order ticket on the Trade screen.
9. ✅ Dashboard modules (account info, watchlist, orders, performance, market overview with gainers, losers
   and most active, top traders) and Trade-screen news. Uses the backend's news, movers and profile routes.
10. ✅ Getting-started checklist (tutorial).

### Phase 2 decisions

Taken at the start of Phase 2 (2026-10-25), following the recommendations above:

- **UI stays on the in-house kit** (decision 5, revisited as planned). There's no package manager, every
  existing screen is imperative, and Phase 2's new UI is lists, a profile panel and one form, which
  `UIKit` covers. A declarative library would leave two UI styles in one codebase.
- **Sharing executed trades is on by default**, with a toggle on the player's own profile. Turning it off
  hides their trades from their profile and the feed; the aggregate stats stay public, as in Phase 1.
- **The feed is one global MemoryStore sorted map**, capped by count and a two-day expiry, because
  MemoryStore memory is only 64 KB + 1.2 KB × concurrent users. Servers read it incrementally every few
  seconds and cache it; the Following view filters that cache.
- **Thesis text needs chat permission.** Only players `TextChatService:CanUserChatAsync` allows can add
  text; anyone can publish the structured part (ticker, direction, target, horizon). Text is filtered
  for broadcast when shown and cached per server.

### Phase 2 build order

1. ✅ Follows (`Following` in the profile, counts in DataStore `Followers_v1`), the trade-sharing setting,
   and recent trades on public profiles.
2. The feed: executed trades and milestones in MemoryStore, a code-built Social tab with All and
   Following views, and `Navigation.openProfile`.
3. Theses: structured posts in DataStore `Posts`, indexed by author and ticker; shown in the feed, on
   profiles and on the Trade screen, labeled "Simulated, not financial advice".
4. Safety: blocking and muting (hidden from your feed and profile views), and reporting theses.
5. Reactions on feed items.
6. Notifications: an inbox in the profile (ProfileStore messages for new followers and reactions), live
   delivery through MessagingService, a toast and a nav badge.
7. Asset discovery: per-ticker counts of watchers, traders and theses; "Trending in TradingBlox" on the
   Social tab and in Market overview, and the counts on the Trade screen beside the fundamentals.
8. Dashboard Social module: activity from followed players and trending theses.

## Sources

- [In-experience HTTP requests (Roblox docs)](https://create.roblox.com/docs/cloud-services/http-service)
- [Open Cloud rate limits (Roblox docs)](https://create.roblox.com/docs/cloud/reference/rate-limits)
- [Data store error codes and limits (Roblox docs)](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits)
- [Memory stores (Roblox docs)](https://create.roblox.com/docs/cloud-services/memory-stores)
- [Text filtering (Roblox docs)](https://create.roblox.com/docs/ui/text-filtering)
- [Roblox Community Standards](https://about.roblox.com/community-standards)
- [Chat class reference, `CanUsersChatAsync` (Roblox docs)](https://create.roblox.com/docs/reference/engine/classes/Chat.md)
- [Age check requirement to chat now live globally (DevForum)](https://devforum.roblox.com/t/age-check-requirement-to-chat-now-live-globally/4226101)
- [Global players count: proxy needed for Roblox web APIs (DevForum)](https://devforum.roblox.com/t/global-players-count/2951985)
- [MessagingService limits discussion (DevForum)](https://devforum.roblox.com/t/what-is-the-fastest-way-to-send-messages-across-servers/2631722)
- [Yahoo Finance API alternatives, on licensing (Intrinio)](https://intrinio.com/blog/yahoo-finance-api-replacement)
- [Guide to the Yahoo Finance API (Scrapfly)](https://scrapfly.io/blog/posts/guide-to-yahoo-finance-api)

