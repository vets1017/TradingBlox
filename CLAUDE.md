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

Tooling is managed by [Aftman](https://github.com/LPGhatguy/aftman) (`aftman.toml` pins `rojo`).

- `aftman install` — install the pinned Rojo version.
- `rojo serve` — start the Rojo dev server; connect to it from the Rojo plugin inside Roblox Studio to sync
  `src/` live into a place for playtesting. This is the primary "run" loop for this project.
- `rojo build -o RobloxProjects.rbxlx` — build a standalone `.rbxlx` place file from `default.project.json`
  (git-ignored, along with `.lock` files).
- `selene src` — lint against `selene.toml` (`std = "roblox"`). Selene is not currently pinned in
  `aftman.toml`, so it must be installed separately (e.g. via cargo or a system package manager) if not
  already on `PATH`.

There is no test suite, no `stylua` config, and no package manager (no Wally) in this repo.

## Architecture

### Rojo sync map (`default.project.json`)

Source folders map directly to the Roblox DataModel:

- `src/server` → `ServerScriptService`
- `src/client` → `StarterPlayer.StarterPlayerScripts`
- `src/shared` → `ReplicatedStorage`

Server scripts (`*.server.luau`) and client scripts (`*.client.luau`) run automatically when Rojo syncs them
into their respective services; plain `.luau` files under `Modules/` are `require`d libraries.

### Client/server split

- **Client (`src/client/Controllers/`)** — one controller per screen/UI area (`ShellController` for the
  full-screen shell — nav bar, balance and level pills, status bar, toasts; `TerminalController` for tab
  switching, the Dashboard greeting and countdown, and Charts; `DashboardController` for the Dashboard's widgets
  (account info, watchlist, orders, performance, market overview, top traders), built in code inside the
  Studio widget frames; `TutorialController` for the "Getting started" checklist card; `TradeController` for the Trade screen; `PortfolioController` for the Portfolio screen, which it builds
  entirely in code inside the empty Studio `PortfolioScreen` frame; `LeaderboardController` for the Leaderboards
  tab, whose nav button and empty screen `ShellController` creates in code (`CODE_BUILT_TABS`) and
  `TerminalController` registers for switching; Quote tabs and Options chain stubs). Controllers `WaitForChild` their way through a large, hand-built UI tree (no UI
  framework/library), wire up `TweenService` animations and `UserInputService` input handling directly, and
  call server `RemoteFunction`s to fetch data. Several controllers (`QuoteTabsController`,
  `OptionsChainController`) are stubs (empty or fully commented out) awaiting their corresponding server
  events to go live — check whether a controller is "real" before assuming it runs.
- **Server (`src/server/Core/`)** — one script per subsystem:
  - `ServerSetup.server.luau` creates the `EventsFolder` in `ReplicatedStorage` and all `RemoteFunction`s the
    client calls (`RequestChartEvent`, `GetMarketDataEvent`, `GetOptionsDataEvent`, `GetPositionsEvent`,
    `GetPortfolioEvent`, `GetLeaderboardEvent`, `GetPublicProfileEvent`, `GetNewsFeedEvent`, `PlayerOrderEvent`,
    `PlayerOptionOrderEvent`, plus watchlist and research remotes). This must run before other server scripts wire up
    `OnServerInvoke` handlers.
  - `API_Manager.server.luau` is the sole bridge to the outside world for market data: it polls an external
    HTTP backend (`SERVER_URL`, currently a Render-hosted service) for live quotes, option chains, and
    candle/chart data, with its own ticker validation, per-player request-cooldown throttling, and
    time-based caches (`ChartCache`, `OptionChainCache`, etc., swept periodically). It handles
    `GetOptionsDataEvent` (multi-strike option chain, via `MarketDataModule.getOptionChain`) and
    `GetMarketOverviewEvent` (the Dashboard's benchmark quotes, cached 60 s per server).
    `GetNewsFeedEvent` is declared but has no server-side handler yet — client calls to it will hang.
    `PlayerOrderEvent` and `GetPositionsEvent` are handled in `TradeSystem.server.luau` (share buy/sell and
    position listing), not here.
  - `Data_Manager.server.luau` is the bootstrap for the player services: it starts `ProgressionService` then
    `PlayerDataService`, and keeps the `_G` names (below) pointing at them.
  - `API_Manager`'s option and research remotes check level unlocks; a locked request gets
    `{ available = false, locked = true, message = "Unlocks at Level N · Name" }`, the shape the Trade screen
    already renders as "no data".
  - `TradeSystem.server.luau` handles `PlayerOrderEvent` (share buy/sell, long-only) and `GetPositionsEvent`
    (share position listing; per-ticker for the Trade screen, every position with no ticker for the Portfolio tab). `OptionSystem.server.luau` handles `PlayerOptionOrderEvent` (long-only option
    contract buy/sell at ask/bid, NYSE-hours-gated with no crypto exemption), writing
    `playerData.Portfolio.Options[contractSymbol] = { contracts, ticker, expiration, strike, type, avgCost }`.
  - `PortfolioSystem.server.luau` handles `GetPortfolioEvent` (summary, every chart range's history, option
    positions) and reprices every online player every 5 minutes so the history keeps moving.
  - `Modules/CalculatorModule.luau` computes net worth from portfolio + live market data, and records it into
    `NetWorthHistory` only when every holding was priced (a backend outage would otherwise read as a crash).
  - `Modules/PortfolioHistoryModule.luau` — net-worth history storage: 5-minute points for the last day, hourly
    after, 30-day retention; slices and downsamples ranges for the chart; max drawdown.
  - `Modules/TradeLogModule.luau` — records every fill (last 500 in `TradeLog`) and running realized-P/L stats
    (`RealizedPL`, `Wins`, `Losses`, `GrossGain`, `GrossLoss`) used for win rate and average gain/loss.
- **Server services (`src/server/Services/`)** — ModuleScripts that own a subsystem; new server code should
  `require` these rather than reach for `_G`:
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
    against candles since placement, expired after 30 days. Pushes fills/cancellations through the
    `OrderUpdateEvent` RemoteEvent (ShellController shows them as a toast).
  - `OrderEvents` — `Filled` fires after every share or option fill; progression, leaderboards and profiles
    subscribe rather than the order scripts calling each of them. Fire it from any new order path.
  - `LeaderboardService` — scores players on the boards in `Config/Leaderboards`; each board+period is its own
    OrderedDataStore (`LB_<board>_<period>`); top pages cached per server for 60 s.
  - `PublicProfileService` — the public profile snapshot in DataStore `PublicProfile_v1` (written ≤ 1/min
    after trades, every 5 min, and on leave via `PlayerDataService.onPlayerLeaving`); also submits leaderboard
    scores.
  - `Core/LeaderboardSystem.server.luau` wires `GetLeaderboardEvent` / `GetPublicProfileEvent` (1 req/s per
    board or profile per player).
- **Vendored (`src/server/Vendor/`)** — `ProfileStore.luau`, unmodified below a provenance header (pinned
  commit, Apache-2.0; license in `THIRD_PARTY_LICENSES/`). Don't edit it in place.
- **Shared config (`src/shared/Config/`)** — read by both sides: the server enforces it, the client explains it.
  `Progression` (levels, unlocks, XP rules), `Leaderboards` (boards, periods, eligibility, score encoding),
  `Economy` (starting cash).
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

Older server scripts still use `_G.PlayerData[userId]`, `_G.UpdatePlayerStat` and `_G.UpdatePortfolio`. These
are now a shim set up by `Data_Manager.server.luau`: `_G.PlayerData` is a proxy whose reads resolve to
`PlayerDataService.get(player)` (nil before the profile loads and after the session ends), and the two
functions are `PlayerDataService.setStat` / `updateShares`. Scripts are moving onto services one at a time
(`docs/TECHNICAL-PLAN.md`, Phase 0); don't add new `_G` uses. Note that `execute_luau` from the Studio MCP runs
with its own isolated `_G` — inject a real `Script` to inspect it.

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
