# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TradingBlox is a Roblox experience (Luau) that simulates a stock/options trading terminal. It's built with
[Rojo](https://rojo.space/) and synced into Roblox Studio for playtesting — there is no standalone way to run
or test it outside Studio.

- **Product spec:** `docs/GAME-DESIGN.md`. Treat it as the source of truth for what to build.
- **Architecture and roadmap:** `docs/TECHNICAL-PLAN.md` — current-state inventory, platform limits, Phases
  0–6, the decisions taken, and the Phase 1 build order (§6). Check it before starting a feature.

## Commands

Tooling is pinned in `aftman.toml` (Rojo, selene, StyLua, Lune) and installed with
[Aftman](https://github.com/LPGhatguy/aftman) (`aftman install`); Rokit reads the same file (`rokit install`).

- `rojo serve` — start the Rojo dev server; connect to it from the Rojo plugin inside Roblox Studio to sync
  `src/` live into a place for playtesting. This is the primary "run" loop for this project.
- `rojo build -o RobloxProjects.rbxlx` — build a standalone `.rbxlx` place file from `default.project.json`
  (git-ignored, along with `.lock` files).
- `selene src tests` — lint against `selene.toml` (`std = "roblox"`; vendored code excluded).
- `stylua src tests` — format with `stylua.toml` (Luau, 120 columns, tabs); `.styluaignore` skips vendored code.
- `lune run tests/run.luau` — unit tests: every `tests/*.spec.luau`, with the asserts in `tests/TestKit.luau`.
  Specs `require` game modules by relative path, so only modules that don't touch Roblox services can be
  tested; keep logic worth testing in such a module (`FillPriceModule` was split out of `MarketDataModule`
  for this). Everything else is checked in Studio through the MCP tools.

CI (`.github/workflows/ci.yml`) runs selene, `stylua --check`, the tests and `rojo build` on pushes to `main`
and on pull requests. There's no package manager (no Wally).

## Architecture

### Rojo sync map (`default.project.json`)

Source folders map directly to the Roblox DataModel:

- `src/server` → `ServerScriptService`
- `src/client` → `StarterPlayer.StarterPlayerScripts`
- `src/shared` → `ReplicatedStorage`
- `src/gui` → `StarterGui` — `TerminalGui.rbxmx` is the hand-built Studio UI (371 instances)

Rojo syncs files → Studio only. After changing `TerminalGui` in Studio, right-click it → **Save to File…**
over `src/gui/TerminalGui.rbxmx`; Studio-only edits are lost the next time Rojo syncs that file.

Server scripts (`*.server.luau`) and client scripts (`*.client.luau`) run automatically when Rojo syncs them
into their respective services; plain `.luau` files under `Modules/` are `require`d libraries.

### Client/server split

- **Client (`src/client/Controllers/`)** — one controller per screen/UI area (`ShellController` for the
  full-screen shell — nav bar, balance and level pills, status bar, toasts; `TerminalController` for tab
  switching, the Dashboard greeting and countdown, and Charts; `DashboardController` for the Dashboard's widgets
  (account info, watchlist, orders, performance, market overview, top traders), built in code inside the
  Studio widget frames; `TutorialController` for the "Getting started" checklist card; `TradeController` for the Trade screen; `PortfolioController` for the Portfolio screen, which it builds
  entirely in code inside the empty Studio `PortfolioScreen` frame; `LeaderboardController` for the Leaderboards
  tab (boards beside a public profile with Follow, the trade-sharing toggle and recent trades), whose nav button and empty screen `ShellController` creates in code (`CODE_BUILT_TABS`) and
  `TerminalController` registers for switching; Quote tabs and Options chain stubs). Controllers `WaitForChild` their way through a large, hand-built UI tree (no UI
  framework/library), wire up `TweenService` animations and `UserInputService` input handling directly, and
  call server `RemoteFunction`s to fetch data. Several controllers (`QuoteTabsController`,
  `OptionsChainController`) are stubs (empty or fully commented out) awaiting their corresponding server
  events to go live — check whether a controller is "real" before assuming it runs.
- **Server (`src/server/Core/`)** — one script per subsystem:
  - `ServerSetup.server.luau` creates the `EventsFolder` in `ReplicatedStorage` and all `RemoteFunction`s the
    client calls (`RequestChartEvent`, `GetMarketDataEvent`, `GetOptionsDataEvent`, `GetPositionsEvent`,
    `GetPortfolioEvent`, `GetLeaderboardEvent`, `GetPublicProfileEvent`, `GetNewsFeedEvent`, `GetMarketMoversEvent`,
    `PlayerOrderEvent`, `PlayerOptionOrderEvent`, `FollowPlayerEvent`, `SetShareTradesEvent`, plus watchlist and
    research remotes). This must run before other server scripts wire up
    `OnServerInvoke` handlers.
  - `API_Manager.server.luau` wires the market-data remotes. `Modules/MarketDataModule.luau` is the sole
    bridge to the external HTTP backend (`SERVER_URL`, a Render-hosted service): ticker validation, a
    per-server quote table (`getQuotes` batches up to 50 symbols, 10 s cache; `getLiveQuote`,
    `getCurrentPrice`, falling back to candles if the quotes route fails), splits, and time-based caches
    (`ChartCache`, `OptionChainCache`, etc., swept periodically). `API_Manager` handles
    `GetOptionsDataEvent` (multi-strike option chain, via `MarketDataModule.getOptionChain`),
    `GetMarketOverviewEvent` (the Dashboard's benchmark quotes, cached 60 s per server), `GetNewsFeedEvent`
    (a ticker's headlines for the Trade screen) and `GetMarketMoversEvent` (the Dashboard's gainers/losers/most
    active). **Text from outside Roblox (headlines, publishers, company names) goes through
    `filterExternalText` (TextService, cached per server) before any player sees it; links are never sent.**
    The backend's news, movers and profile routes cache on their side too. `PlayerOrderEvent` and
    `GetPositionsEvent` are handled in `TradeSystem.server.luau` (share buy/sell and position listing), not here.
  - In Studio only, a `BackendUrl` attribute on ServerScriptService points `MarketDataModule` at another
    backend (e.g. `http://localhost:3000` while developing `~/Documents/VS/StockDataFetcher`; Studio can reach
    localhost). Remove it after testing; live servers always use the deployed backend.
  - `Data_Manager.server.luau` is the bootstrap for the player services: it starts the services that listen
    for players (`ProgressionService`, `LeaderboardService`, `PublicProfileService`, `SocialService`, `OrderService`,
    `SettlementService`) before `PlayerDataService`, so none misses a player who loads straight away.
  - `API_Manager`'s option and research remotes check level unlocks; a locked request gets
    `{ available = false, locked = true, message = "Unlocks at Level N · Name" }`, the shape the Trade screen
    already renders as "no data".
  - `TradeSystem.server.luau` handles `PlayerOrderEvent` (share buy/sell, long-only) and `GetPositionsEvent`
    (share position listing; per-ticker for the Trade screen, every position with no ticker for the Portfolio tab). `OptionSystem.server.luau` handles `PlayerOptionOrderEvent` (long-only option
    contract buy/sell at ask/bid, NYSE-hours-gated with no crypto exemption), writing
    `playerData.Portfolio.Options[contractSymbol] = { contracts, ticker, expiration, strike, type, avgCost }`.
  - `PortfolioSystem.server.luau` handles `GetPortfolioEvent` (summary, every chart range's history, option
    positions, recent fills, and at level 2 each holding's allocation group: its sector for stocks — from an
    allowlist of Yahoo's sectors — or ETFs/Crypto/Funds) and reprices every online player every 5 minutes so the history keeps moving.
  - `Modules/CalculatorModule.luau` computes net worth from portfolio + live market data, and records it into
    `NetWorthHistory` only when every holding was priced (a backend outage would otherwise read as a crash).
  - `Modules/PortfolioHistoryModule.luau` — net-worth history storage: 5-minute points for the last day, hourly
    after, 30-day retention; slices and downsamples ranges for the chart; max drawdown.
  - `Modules/TradeLogModule.luau` — records every fill (last 500 in `TradeLog`) and running realized-P/L stats
    (`RealizedPL`, `Wins`, `Losses`, `GrossGain`, `GrossLoss`) used for win rate and average gain/loss.
  - `Modules/RemoteGuard.luau` — per-player token-bucket rate limits. **Every remote handler is registered
    through `RemoteGuard.handle(remote, RemoteGuard.LIMITS.<Tier>, handler[, limitedResult])`** (tiers `Poll`,
    `Read`, `Order`, `Research`, `Rare`); remotes that report success pass `RemoteGuard.TOO_MANY_REQUESTS`.
  - `Modules/FillPriceModule.luau` — pure fill-price rules: ask for buys and bid for sells in the regular
    session when the spread is ≤ 2%, otherwise the last price (crypto, after hours); a regular-session stock
    quote over 15 minutes old is refused.
- **Server services (`src/server/Services/`)** — ModuleScripts that own a subsystem; server code `require`s
  these:
  - `PlayerDataService` — every player's saved data: one session-locked ProfileStore profile per player
    (store `PlayerData_v2`, key `Player_<userId>`, $50,000 start), autosaved every 60 s. A failed load kicks the
    player rather than handing them default data. `get(player)`, `setStat`, `updateShares`, `PlayerLoaded`
    (fires with the player only: a BindableEvent would hand listeners a *copy* of a data table — always read
    data with `get`), `onPlayerLeaving` (synchronous, just before the final save).
    The profile template is the source of truth for the data shape; `Reconcile` adds new fields to old saves.
  - `ProgressionService` — XP, levels, feature unlocks (`hasFeature(player, feature)`) and the getting-started
    tutorial. Mirrors `XP`, `Level`, `TutorialProgress` and `TutorialComplete` to player attributes, and handles
    `CompleteTutorialStepEvent` itself.
  - `OrderService` — share execution: `fillShares` (market orders and limit fills share it) and level 2 limit
    orders kept in `playerData.Orders`: checked every 15 s while the player is online, caught up at login
    against candles since placement, expired after 30 days. `getFillPrice(ticker, side)` prices every share
    fill (live quote through `FillPriceModule`). `notify(player, kind, message)` pushes fills, cancellations,
    expiries and splits through the `OrderUpdateEvent` RemoteEvent (ShellController shows them as a toast).
  - `SettlementService` — at login and every 10 minutes: settles expired options at intrinsic value from the
    underlying's close (logged with `settlement = "Expired"`, which counts in realized P/L but not trades),
    and applies stock splits to shares, average cost and open orders (cash in lieu for fractions), using
    `Portfolio.SplitCheckedAt` so a split is never applied twice or retroactively.
  - `OrderEvents` — `Filled` fires after every share or option fill; progression, leaderboards and profiles
    subscribe rather than the order scripts calling each of them. Fire it from any new order path.
  - `LeaderboardService` — scores players on the boards in `Config/Leaderboards`; each board+period is its own
    OrderedDataStore (`LB_<board>_<period>`); top pages cached per server for 60 s.
  - `PublicProfileService` — the public profile snapshot in DataStore `PublicProfile_v1` (written ≤ 1/min
    after trades, every 5 min, and on leave via `PlayerDataService.onPlayerLeaving`); also submits leaderboard
    scores. The snapshot carries the latest trades only while the player shares them.
  - `SocialService` — Phase 2 social trading (TECHNICAL-PLAN §6 has the build order): `playerData.Social`
    holds the `Following` list (keyed by user id strings, capped by `Config/Social`) and the `ShareTrades`
    setting; follower counts live in DataStore `Followers_v1` (`UpdateAsync`, cached 60 s). Pure rules are in
    `Modules/SocialModule.luau`.
  - `Core/LeaderboardSystem.server.luau` wires `GetLeaderboardEvent` / `GetPublicProfileEvent` (which adds the
    follower count and whether the caller follows); `Core/SocialSystem.server.luau` wires `FollowPlayerEvent`
    and `SetShareTradesEvent`.
- **Vendored (`src/server/Vendor/`)** — `ProfileStore.luau`, unmodified below a provenance header (pinned
  commit, Apache-2.0; license in `THIRD_PARTY_LICENSES/`). Don't edit it in place.
- **Shared config (`src/shared/Config/`)** — read by both sides: the server enforces it, the client explains it.
  `Progression` (levels, unlocks, XP rules), `Leaderboards` (boards, periods, eligibility, score encoding),
  `Economy` (starting cash), `Social` (follow cap, how many recent trades a profile shows).
- **Shared UI (`src/shared/UI/`)** — the in-house kit for UI built in code: `UIKit` (frame/label/panel/dot/
  avatar builders on Theme tokens) and `LineChart` (the gradient line + fill used by the Portfolio chart and
  profile panel). New code-built screens should use these instead of copying builders.
- **Shared (`src/shared/Modules/`)**:
  - `Multi/` — cross-boundary utilities used by both client and server-side logic conceptually:
    `ChartRenderer` (pure UI-building candlestick/grid/axis renderer, takes a table of UI element refs +
    OHLC data and returns min/max price), `MarketHoursModule` (NYSE open/closed + holiday calendar, computed
    algorithmically including Easter-relative Good Friday), `NumberModule` (currency formatting), `Navigation`
    (client-only: `Navigation.openTicker(ticker)` and `Navigation.openTab(name)` let any controller send the
    player to a ticker on the Trade tab or to another tab — the only link between controllers, which otherwise
    can't reach each other's locals).
  - `Terminal/` and `Trade/` subfolders hold per-screen logic pulled out of the client controllers as they
    grow. `Trade/OrderTicketModule` is the Trade screen's Market/Limit preset ticket (one-click presets, the
    house style for order entry); the other files there are still empty placeholders.

### Cross-script state sharing

Server scripts share state only through the services: `PlayerDataService.get(player)` for a player's data
(nil before the profile loads and after the session ends), `setStat` / `updateShares` to change it. The old
`_G` shim is gone; don't add `_G` state.

### Theme system (Axiom-style look)

All colors, fonts and text sizes come from `src/shared/Modules/Multi/Theme.luau`. Hand-built Studio UI opts in
with a `ThemeRole` string attribute (e.g. `Panel`, `Number`, `Tab`); `Theme.apply(root)` stamps each role's
properties, and `ShellController` calls it on `TerminalGui` at startup. Rules:

- **New Studio-built UI must set a `ThemeRole`.** Untagged elements are never styled, on purpose — they stand out.
- **UI built in code reads `Theme.Colors` / `Theme.Fonts` / `Theme.TextSize` directly** — never `Color3.fromRGB`
  literals, except chart data series (indicator/drawing colors).
- **A role never sets a property a controller changes at runtime** (up/down colors, active tab, toggles). Elements
  like that use the color-less roles (`NumberDynamic`, `Tab`, `Toggle`, `Preset`, `ActionButton`, …) and their
  controller owns the color.
- A pre-restyle copy of the UI lives at `ServerStorage.TerminalGui_PreAxiomBackup` in the place file.

### Data flow for a typical UI action

1. Client controller invokes a `RemoteFunction` in `ReplicatedStorage.EventsFolder` (e.g.
   `RequestChartEvent:InvokeServer(ticker, timeframe, mode)`).
2. `API_Manager.server.luau` validates input, checks/updates its cache, and fetches from the external HTTP
   API if needed, returning a plain Luau table.
3. Client renders the result directly into pre-built UI instances (e.g. `ChartRenderer.render(...)`) — there
   is no client-side state management layer beyond local variables in each controller.
4. Player-specific stats (`Balance`, `NetWorth`, `XP`, `Level`) are exposed to the client as Roblox
   `Attribute`s on the `Player` instance and read reactively via `GetAttributeChangedSignal`.

### Known WIP areas

Several files intentionally contain large commented-out blocks or are empty, representing not-yet-wired
features rather than dead code: `OptionsChainController.client.luau`, `QuoteTabsController.client.luau`, and
all files under `shared/Modules/Terminal/` and `shared/Modules/Trade/`. Check git blame/history before
deleting anything that looks unused.
