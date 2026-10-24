# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TradingBlox is a Roblox experience (Luau) that simulates a stock/options trading terminal. It's built with
[Rojo](https://rojo.space/) and synced into Roblox Studio for playtesting — there is no standalone way to run
or test it outside Studio.

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
  full-screen shell — nav bar, balance pill, status bar; `TerminalController` for tab switching, Dashboard and
  Charts; `TradeController` for the Trade screen; `PortfolioController` for the Portfolio screen, which it builds
  entirely in code inside the empty Studio `PortfolioScreen` frame; Quote tabs and Options chain stubs). Controllers `WaitForChild` their way through a large, hand-built UI tree (no UI
  framework/library), wire up `TweenService` animations and `UserInputService` input handling directly, and
  call server `RemoteFunction`s to fetch data. Several controllers (`QuoteTabsController`,
  `OptionsChainController`) are stubs (empty or fully commented out) awaiting their corresponding server
  events to go live — check whether a controller is "real" before assuming it runs.
- **Server (`src/server/Core/`)** — one script per subsystem:
  - `ServerSetup.server.luau` creates the `EventsFolder` in `ReplicatedStorage` and all `RemoteFunction`s the
    client calls (`RequestChartEvent`, `GetMarketDataEvent`, `GetOptionsDataEvent`, `GetPositionsEvent`,
    `GetPortfolioEvent`, `GetNewsFeedEvent`, `PlayerOrderEvent`, `PlayerOptionOrderEvent`). This must run before other server scripts wire up
    `OnServerInvoke` handlers.
  - `API_Manager.server.luau` is the sole bridge to the outside world for market data: it polls an external
    HTTP backend (`SERVER_URL`, currently a Render-hosted service) for live quotes, option chains, and
    candle/chart data, with its own ticker validation, per-player request-cooldown throttling, and
    time-based caches (`ChartCache`, `OptionChainCache`, etc., swept periodically). It handles
    `GetOptionsDataEvent` (multi-strike option chain, via `MarketDataModule.getOptionChain`).
    `GetNewsFeedEvent` is declared but has no server-side handler yet — client calls to it will hang.
    `PlayerOrderEvent` and `GetPositionsEvent` are handled in `TradeSystem.server.luau` (share buy/sell and
    position listing), not here.
  - `Data_Manager.server.luau` owns player persistence (`DataStoreService`, key `PlayerData_v1`): balance,
    portfolio shares/options, `Stats` (`Trades` count, `JoinedAt`), `NetWorthHistory`, load on `PlayerAdded`,
    save on `PlayerRemoving`/`BindToClose`.
  - `TradeSystem.server.luau` handles `PlayerOrderEvent` (share buy/sell, long-only) and `GetPositionsEvent`
    (share position listing; per-ticker for the Trade screen, every position with no ticker for the Portfolio tab). `OptionSystem.server.luau` handles `PlayerOptionOrderEvent` (long-only option
    contract buy/sell at ask/bid, NYSE-hours-gated with no crypto exemption), writing
    `playerData.Portfolio.Options[contractSymbol] = { contracts, ticker, expiration, strike, type, avgCost }`.
  - `PortfolioSystem.server.luau` handles `GetPortfolioEvent` (summary, every chart range's history, option
    positions) and reprices every online player every 5 minutes so the history keeps moving.
  - `Modules/CalculatorModule.luau` computes net worth from portfolio + live market data, and records it into
    `NetWorthHistory` only when every holding was priced (a backend outage would otherwise read as a crash).
  - `Modules/PortfolioHistoryModule.luau` — net-worth history storage: 5-minute points for the last day, hourly
    after, 30-day retention; slices and downsamples ranges for the chart.
- **Shared (`src/shared/Modules/`)**:
  - `Multi/` — cross-boundary utilities used by both client and server-side logic conceptually:
    `ChartRenderer` (pure UI-building candlestick/grid/axis renderer, takes a table of UI element refs +
    OHLC data and returns min/max price), `MarketHoursModule` (NYSE open/closed + holiday calendar, computed
    algorithmically including Easter-relative Good Friday), `NumberModule` (currency formatting), `Navigation`
    (client-only: `Navigation.openTicker(ticker)` lets any controller send the player to that ticker on the Trade
    tab — the only link between controllers, which otherwise can't reach each other's locals).
  - `Terminal/` and `Trade/` subfolders are placeholder modules (currently empty) reserved for pulling
    per-screen rendering logic out of the client controllers as they grow.

### Cross-script state sharing

Server scripts share mutable state via `_G` (e.g. `_G.PlayerData`, `_G.UpdatePlayerStat`,
`_G.UpdatePortfolio`, `_G.LiveMarketData` referenced from `CalculatorModule`) rather than `require`d modules
returning shared tables. This is deliberate but fragile — code depending on `_G.*` assumes
`Data_Manager.server.luau` (and `API_Manager.server.luau` for market data) has already run and initialized it.

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
4. Player-specific stats (`Balance`, `NetWorth`) are exposed to the client as Roblox `Attribute`s on the
   `Player` instance and read reactively via `GetAttributeChangedSignal`.

### Known WIP areas

Several files intentionally contain large commented-out blocks or are empty, representing not-yet-wired
features rather than dead code: `OptionsChainController.client.luau`, `QuoteTabsController.client.luau`, and
all files under `shared/Modules/Terminal/` and `shared/Modules/Trade/`. Check git blame/history before
deleting anything that looks unused.
