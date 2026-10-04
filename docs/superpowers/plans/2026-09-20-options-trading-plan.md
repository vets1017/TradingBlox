# Options Trading (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire a real, multi-strike option chain into the Trade tab's already-built (but unwired) Option Chain panel, and let players buy/sell option contracts from it — priced off live bid/ask, settled against balance, tracked in portfolio, and counted correctly in net worth.

**Architecture:** The Render-hosted Node backend (`StockDataFetcher`) gains one new additive route, `/api/option-chain/:ticker`, returning the full (strike-range-limited) nearest-expiration chain instead of the single ATM contract the existing `/api/options/:ticker` route returns for the Option Stats tab. `MarketDataModule.luau` gains a cached fetch (`getOptionChain`) plus a convenience lookup (`getOptionQuote`) used by both the new order system and the net-worth calculation. `API_Manager.server.luau` wires the already-declared-but-unhandled `GetOptionsDataEvent` remote on top of it. A new `OptionSystem.server.luau` (currently a 0-byte stub) handles a new `PlayerOptionOrderEvent` remote for contract buy/sell, mirroring `TradeSystem.server.luau`'s share-order handler but pricing at ask (buy) / bid (sell) instead of a flat price, and storing positions in `Portfolio.Options[contractSymbol]`. `CalculatorModule.calculateNetWorth` gets a bug fix (shares and options currently can't both count — `if/elseif` instead of two independent `if`s) and its option mark-to-market stub filled in. `TradeController.client.luau` already has a working `renderOptionChain`/`createStrikeRow` renderer wired to a toggleable panel, but built against a placeholder data shape that was invented before the real backend existed, and with no way to select a contract to trade — this plan corrects the shape to match the real backend response, adds click-to-select on a strike's call/put, a small "now trading this contract" indicator, and branches the existing Buy/Sell buttons to place a contract order when one is selected.

**Tech Stack:** Node/Express + `yahoo-finance2` v3 (backend, separate repo), Luau + Rojo + Roblox Studio (game). No test framework in either repo — verification is manual: `curl` for the backend, live Roblox Studio playtests via the `Roblox_Studio` MCP tools for the game (this session has Studio connected — `studio_id: e73f4e4e-728f-458b-b52a-630fb691c876`, place "TradingBlox").

**Spec:** `docs/superpowers/specs/2026-09-20-options-trading-design.md`

## Global Constraints

- Backend lives at `~/Documents/VS/StockDataFetcher` (separate git repo, confirmed clean working tree, `main`/default branch). Roblox game lives at this repo. They are edited and committed independently.
- `MarketDataModule.luau`'s `SERVER_URL` is hardcoded to the production Render URL (`https://tradingblox-terminal-backend.onrender.com`). **Task 2 (Roblox side) cannot be verified live until Task 1's backend route is pushed and deployed** — explicit checkpoint between them.
- No test framework in either repo. Every task ends with a manual verification step (curl for the backend task, Roblox Studio MCP playtest for game tasks) instead of automated tests. Do not add a test framework as a side effect of this plan.
- Match existing code style exactly: tabs for indentation in Luau, comments explain *why* not *what*, no new abstractions beyond what's specified below.
- Long calls/puts only — no short selling or writing options, matching how share trading is long-only today.
- Options are **always** gated by NYSE market hours — unlike share orders, there is no crypto-style 24/7 exemption (there's no such thing as a crypto option here).
- Nearest expiration only. `expirationDates` is returned by the backend for a future expiration-switcher but no switcher UI is built this phase.
- Position display (positions table, P&L) is explicitly out of scope — balance and net worth must be correct; showing option holdings in a list is a later Portfolio-tab phase.
- `Data_Manager.server.luau` needs **no changes** — `Portfolio.Options = {}` is already its default player-data shape.
- `StarterGui` is not version-controlled, but this plan needs **no manual Studio UI building** — every new client-side element (the contract indicator, the per-row hit-area buttons) is created via `Instance.new` in `TradeController.client.luau`, same pattern as the chain rows themselves.

---

## Task 1: Backend — `/api/option-chain/:ticker`

**Files:**
- Modify: `~/Documents/VS/StockDataFetcher/index.js`

**Interfaces:**
- Produces: `GET /api/option-chain/:ticker -> { available: true, spotPrice, expiration, expirationDates, strikes: [{ strike, call: { contractSymbol, bid, ask, lastPrice, impliedVolatility, volume, openInterest } | null, put: {...} | null }] }` or `{ available: false }`. Consumed by Task 2's `MarketDataModule.getOptionChain`.

- [ ] **Step 1: Add the route**

Insert after the existing `/api/options/:ticker` route (after its closing `});`, before `const PORT = ...`) in `index.js`:

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

- [ ] **Step 2: Verify locally**

Run: `cd ~/Documents/VS/StockDataFetcher && node index.js` (leave running), then in another terminal:
```bash
curl -s http://localhost:3000/api/option-chain/AAPL | python3 -m json.tool
curl -s http://localhost:3000/api/option-chain/BTC-USD | python3 -m json.tool
```
Expected: AAPL returns `available: true` with `spotPrice`, `expiration`, a non-empty `strikes` array, and each strike's `call`/`put` carrying a `contractSymbol` plus bid/ask (check a couple of strikes aren't both null — illiquid far strikes legitimately can be). Confirm `strikes` only spans roughly ±20% of `spotPrice` (e.g. for a ~$230 stock, strikes roughly 184–276). BTC-USD (no listed options) returns `{ "available": false }`. Also re-run `curl -s http://localhost:3000/api/options/AAPL` to confirm the existing Option Stats route is unaffected.

Stop the server (Ctrl+C) when done.

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/VS/StockDataFetcher
git add index.js
git commit -m "$(cat <<'EOF'
Add /api/option-chain endpoint for multi-strike option chain

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## ⚠️ CHECKPOINT — Deploy the backend before continuing

`MarketDataModule.luau` in Task 2 calls the **production** Render URL, not
localhost. Push `~/Documents/VS/StockDataFetcher` and deploy it to Render,
then confirm the new route works against the live URL:
```bash
curl -s https://tradingblox-terminal-backend.onrender.com/api/option-chain/AAPL
```
before starting Task 2.

---

## Task 2: `MarketDataModule.luau` — option chain fetch/cache + quote lookup

**Files:**
- Modify: `src/server/Modules/MarketDataModule.luau`

**Interfaces:**
- Consumes: existing `fetchJSON`, `cachedFetch` (private, already in this file).
- Produces: `MarketDataModule.getOptionChain(ticker) -> data, err`, `MarketDataModule.getOptionQuote(ticker, contractSymbol) -> contractFields, err` — consumed by Task 3 (`GetOptionsDataEvent` handler), Task 4 (net-worth mark-to-market), and Task 5 (`OptionSystem.server.luau` order pricing).

- [ ] **Step 1: Add the endpoint + TTL constant and cache table**

In the `-- Config` block (after the existing `local OPTIONS_ENDPOINT = SERVER_URL .. "/api/options/"` line), add:

```lua
local OPTIONS_CHAIN_ENDPOINT = SERVER_URL .. "/api/option-chain/"
```

In the same block, after `local OPTION_STATS_CACHE_DURATION = 300`, add:

```lua
local OPTION_CHAIN_CACHE_DURATION = 300
```

In the `-- State` block, after `local OptionStatsCache = {}`, add:

```lua
local OptionChainCache = {}
```

- [ ] **Step 2: Add `getOptionChain` and `getOptionQuote`**

Insert right after `MarketDataModule.getOptionStats` (after its closing `end`), before the `-- Cache sweep` comment:

```lua
-- Option Chain panel (Trade tab): nearest-expiration, multi-strike chain
-- (~±20% of spot, set server-side). Returns { available = false } if no
-- listed options.
function MarketDataModule.getOptionChain(ticker)
	if not MarketDataModule.isValidTicker(ticker) then
		return nil, "Invalid ticker"
	end

	local targetTicker = string.upper(ticker)

	return cachedFetch(OptionChainCache, targetTicker, OPTION_CHAIN_CACHE_DURATION, function()
		local data, err = fetchJSON(OPTIONS_CHAIN_ENDPOINT .. HttpService:UrlEncode(targetTicker))

		if data and data.error then
			return nil, tostring(data.error)
		end

		return data, err
	end)
end

-- Looks up a single contract's live fields by OCC contractSymbol, reusing
-- the cached chain so order pricing and net-worth mark-to-market share one
-- lookup path instead of two independently-written ones.
function MarketDataModule.getOptionQuote(ticker, contractSymbol)
	local chain, err = MarketDataModule.getOptionChain(ticker)

	if not chain or chain.available == false or not chain.strikes then
		return nil, err or "Option chain unavailable"
	end

	for _, entry in ipairs(chain.strikes) do
		if entry.call and entry.call.contractSymbol == contractSymbol then
			return entry.call, nil
		end

		if entry.put and entry.put.contractSymbol == contractSymbol then
			return entry.put, nil
		end
	end

	return nil, "Contract not found"
end
```

- [ ] **Step 3: Add the new cache to the sweep**

In the `ALL_CACHES` table (in the `-- Cache sweep` block), add an entry after the `OptionStatsCache` line:

```lua
	{ cache = OptionChainCache, ttl = OPTION_CHAIN_CACHE_DURATION },
```

- [ ] **Step 4: Verify via Roblox Studio MCP**

With `rojo serve` running and Studio connected, start play (`mcp__Roblox_Studio__start_stop_play`, `is_start: true`), then run via `mcp__Roblox_Studio__execute_luau` (`datamodel_type: "Server"`):

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)

local chain = MarketDataModule.getOptionChain("AAPL")
local firstSymbol = chain and chain.strikes and chain.strikes[1] and chain.strikes[1].call and chain.strikes[1].call.contractSymbol

return {
	chain = chain,
	quoteLookup = firstSymbol and MarketDataModule.getOptionQuote("AAPL", firstSymbol) or "no symbol found",
}
```
Expected: `chain.available == true`, `chain.strikes` is a non-empty array of `{ strike, call, put }`; `quoteLookup` returns the same fields as that strike's `call`. Check `mcp__Roblox_Studio__get_console_output` for errors, then stop play.

- [ ] **Step 5: Commit**

```bash
git add src/server/Modules/MarketDataModule.luau
git commit -m "$(cat <<'EOF'
Add getOptionChain/getOptionQuote to MarketDataModule

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `ServerSetup.server.luau` + `API_Manager.server.luau` — new remotes

**Files:**
- Modify: `src/server/Core/ServerSetup.server.luau`
- Modify: `src/server/Core/API_Manager.server.luau`

**Interfaces:**
- Consumes: `MarketDataModule.getOptionChain` from Task 2.
- Produces: a live `GetOptionsDataEvent.OnServerInvoke` handler (the remote already existed, declared but unhandled); registers `PlayerOptionOrderEvent` as a new `RemoteFunction` at `ReplicatedStorage.EventsFolder.PlayerOptionOrderEvent` for Task 5 to handle and Task 8 to call.

- [ ] **Step 1: Register `PlayerOptionOrderEvent`**

In `ServerSetup.server.luau`, add `"PlayerOptionOrderEvent"` to the `EVENTS` table, right after `"PlayerOrderEvent"`:

```lua
local EVENTS = {
	"RequestChartEvent",
	"GetMarketDataEvent",
	"GetOptionsDataEvent",
	"GetPositionsEvent",
	"GetNewsFeedEvent",
	"PlayerOrderEvent",
	"PlayerOptionOrderEvent",
	"GetAnalystReportEvent",
	"GetFundamentalsEvent",
	"GetOptionStatsEvent",
	"GetWatchlistEvent",
	"ToggleWatchlistEvent",
}
```

- [ ] **Step 2: Wire `GetOptionsDataEvent.OnServerInvoke`**

In `API_Manager.server.luau`, add a remote reference after the existing `local GetOptionStatsEvent = EventsFolder:WaitForChild("GetOptionStatsEvent")` line:

```lua
local GetOptionsDataEvent = EventsFolder:WaitForChild("GetOptionsDataEvent")
```

Add the handler right before the `-- GetAnalystReportEvent` handler (same per-remote-cooldown shape as the existing handlers):

```lua
-- GetOptionsDataEvent
GetOptionsDataEvent.OnServerInvoke = function(player, ticker)
	if isThrottled(player, "GetOptionsDataEvent") then
		return nil
	end

	if not MarketDataModule.isValidTicker(ticker) then
		warn(string.format("[API_Manager] Invalid ticker from %s: %s", player.Name, tostring(ticker)))

		return nil
	end

	local chain, err = MarketDataModule.getOptionChain(ticker)

	if not chain then
		warn(string.format("[API_Manager] Option chain fetch failed for %s: %s", string.upper(ticker), tostring(err)))
	end

	return chain
end
```

- [ ] **Step 3: Verify via Roblox Studio MCP**

Start play, then run via `execute_luau` (`datamodel_type: "Client"`):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")

return {
	chain = EventsFolder.GetOptionsDataEvent:InvokeServer("AAPL"),
	optionOrderRemoteExists = EventsFolder:FindFirstChild("PlayerOptionOrderEvent") ~= nil,
}
```
Expected: `chain.available == true` with real `strikes`; `optionOrderRemoteExists == true` (handler comes in Task 5, so invoking it now would hang — don't call it yet). Check console, stop play.

- [ ] **Step 4: Commit**

```bash
git add src/server/Core/ServerSetup.server.luau src/server/Core/API_Manager.server.luau
git commit -m "$(cat <<'EOF'
Wire GetOptionsDataEvent handler; register PlayerOptionOrderEvent remote

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `CalculatorModule.luau` — net-worth bug fix + option mark-to-market

**Files:**
- Modify: `src/server/Modules/CalculatorModule.luau`

**Interfaces:**
- Consumes: `MarketDataModule.getCurrentPrice` (existing), `MarketDataModule.getOptionQuote` from Task 2.
- Produces: `CalculatorModule.calculateNetWorth(player)` now correctly sums share value **and** option value (currently only one or the other), consumed by every Buy/Sell path (`TradeSystem.server.luau`, and Task 5's `OptionSystem.server.luau`).

- [ ] **Step 1: Replace `calculateNetWorth`**

Replace the full function body:

```lua
function CalculatorModule.calculateNetWorth(player)
	local playerData = _G.PlayerData[player.UserId]

	if not playerData then
		return 0
	end

	local totalShareValue = 0
	local totalOptionValue = 0

	if playerData.Portfolio and playerData.Portfolio.Shares then
		for ticker, shares in pairs(playerData.Portfolio.Shares) do
			local price = MarketDataModule.getCurrentPrice(ticker)

			if price then
				totalShareValue = (totalShareValue or 0) + (shares * price)
			end
		end
	end

	if playerData.Portfolio and playerData.Portfolio.Options then
		for contractSymbol, position in pairs(playerData.Portfolio.Options) do
			local quote = MarketDataModule.getOptionQuote(position.ticker, contractSymbol)
			local premium = quote and quote.bid and quote.ask and (quote.bid + quote.ask) / 2
				or quote and quote.lastPrice

			if premium then
				totalOptionValue = (totalOptionValue or 0) + (position.contracts * premium * 100)
			end
		end
	end

	local finalNetWorth = playerData.Balance + totalShareValue + totalOptionValue

	if _G.UpdatePlayerStat then
		_G.UpdatePlayerStat(player, "NetWorth", finalNetWorth)
	else
		warn("UpdatePlayerStat function not found. Net worth will not be updated for " .. player.Name)
	end

	return finalNetWorth
end
```

(The bug: the old code used `if Shares ... elseif Options ...`, so a player holding both stock and option positions only ever got one counted. Mark-to-market uses the bid/ask midpoint when both are present — a fairer "what could I actually get for this" number than the transactional buy-at-ask/sell-at-bid price — falling back to `lastPrice` for illiquid contracts missing a two-sided quote.)

- [ ] **Step 2: Verify via Roblox Studio MCP**

Start play, join as a test player, then run via `execute_luau` (`datamodel_type: "Server"`) to simulate a player holding both a share and (fake) option position without needing a real order flow yet:

```lua
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)
local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)

local player = Players:GetPlayers()[1]
local playerData = _G.PlayerData[player.UserId]

playerData.Portfolio.Shares["AAPL"] = 10
playerData.Portfolio.AvgCost["AAPL"] = 200

local chain = MarketDataModule.getOptionChain("AAPL")
local firstStrike = chain.strikes[1]
local symbol = firstStrike.call.contractSymbol

playerData.Portfolio.Options[symbol] = {
	contracts = 1,
	ticker = "AAPL",
	expiration = chain.expiration,
	strike = firstStrike.strike,
	type = "C",
	avgCost = firstStrike.call.ask or 1,
}

local netWorth = CalculatorModule.calculateNetWorth(player)
local sharePrice = MarketDataModule.getCurrentPrice("AAPL")

return {
	netWorth = netWorth,
	expectedAtLeast = playerData.Balance + (10 * sharePrice),
}
```
Expected: `netWorth > expectedAtLeast` (the option position's value is counted on top of the share value — confirms the elseif bug is fixed). Clean up afterwards by setting `playerData.Portfolio.Shares["AAPL"] = nil` and `playerData.Portfolio.Options[symbol] = nil` before stopping play, so this test data isn't accidentally saved. Check console for errors, stop play.

- [ ] **Step 3: Commit**

```bash
git add src/server/Modules/CalculatorModule.luau
git commit -m "$(cat <<'EOF'
Fix net worth to count shares and options together; implement option mark-to-market

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `OptionSystem.server.luau` — contract buy/sell order execution

**Files:**
- Modify: `src/server/Core/OptionSystem.server.luau` (currently a 0-byte stub)

**Interfaces:**
- Consumes: `MarketDataModule.getOptionQuote` from Task 2, `CalculatorModule.calculateNetWorth` from Task 4, `MarketHoursModule.getMarketStatus` (existing shared module), `_G.PlayerData`/`_G.UpdatePlayerStat` (existing globals from `Data_Manager.server.luau`).
- Produces: `PlayerOptionOrderEvent.OnServerInvoke(player, action, contractSymbol, ticker, expiration, strike, optionType, contracts) -> { success, message }` — consumed by Task 8's `placeOrder` branch. Writes `playerData.Portfolio.Options[contractSymbol] = { contracts, ticker, expiration, strike, type, avgCost }`.

- [ ] **Step 1: Write the full handler**

```lua
-- OptionSystem.server.luau
--
-- Option contract order execution (Buy/Sell). Long calls/puts only - no
-- short selling or writing, matching how share trading is long-only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)
local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local PlayerOptionOrderEvent = EventsFolder:WaitForChild("PlayerOptionOrderEvent")

local VALID_ACTIONS = { Buy = true, Sell = true }
local VALID_OPTION_TYPES = { C = true, P = true }

local function isPositiveInteger(value)
	return type(value) == "number" and value > 0 and value == math.floor(value)
end

-- PlayerOptionOrderEvent
PlayerOptionOrderEvent.OnServerInvoke = function(player, action, contractSymbol, ticker, expiration, strike, optionType, contracts)
	if type(action) ~= "string" or not VALID_ACTIONS[action] then
		return { success = false, message = "Invalid order type." }
	end

	if not MarketDataModule.isValidTicker(ticker) then
		return { success = false, message = "Invalid ticker." }
	end

	if type(contractSymbol) ~= "string" or contractSymbol == "" then
		return { success = false, message = "Invalid contract." }
	end

	if type(optionType) ~= "string" or not VALID_OPTION_TYPES[optionType] then
		return { success = false, message = "Invalid option type." }
	end

	if not isPositiveInteger(contracts) then
		return { success = false, message = "Invalid contract quantity." }
	end

	-- Options don't trade 24/7 like crypto does - always gate on NYSE hours,
	-- with no exemption.
	if not MarketHoursModule.getMarketStatus(os.time()) then
		return { success = false, message = "Market is closed." }
	end

	local targetTicker = string.upper(ticker)
	local playerData = _G.PlayerData[player.UserId]

	if not playerData then
		return { success = false, message = "Player data not loaded." }
	end

	local quote, quoteErr = MarketDataModule.getOptionQuote(targetTicker, contractSymbol)

	if not quote then
		return { success = false, message = "Price unavailable: " .. tostring(quoteErr) }
	end

	playerData.Portfolio.Options = playerData.Portfolio.Options or {}

	if action == "Buy" then
		local price = quote.ask

		if not price or price <= 0 then
			return { success = false, message = "No ask price available for this contract." }
		end

		local totalCost = price * 100 * contracts

		if playerData.Balance < totalCost then
			return { success = false, message = "Insufficient funds." }
		end

		local existing = playerData.Portfolio.Options[contractSymbol]
		local currentContracts = existing and existing.contracts or 0
		local newContracts = currentContracts + contracts
		local currentAvgCost = existing and existing.avgCost or price

		playerData.Portfolio.Options[contractSymbol] = {
			contracts = newContracts,
			ticker = targetTicker,
			expiration = expiration,
			strike = strike,
			type = optionType,
			avgCost = ((currentAvgCost * currentContracts) + (price * contracts)) / newContracts,
		}

		_G.UpdatePlayerStat(player, "Balance", playerData.Balance - totalCost)
	else -- Sell
		local price = quote.bid

		if not price or price <= 0 then
			return { success = false, message = "No bid price available for this contract." }
		end

		local existing = playerData.Portfolio.Options[contractSymbol]
		local ownedContracts = existing and existing.contracts or 0

		if ownedContracts < contracts then
			return { success = false, message = "Not enough contracts to sell." }
		end

		local totalProceeds = price * 100 * contracts
		local remainingContracts = ownedContracts - contracts

		if remainingContracts > 0 then
			existing.contracts = remainingContracts
		else
			playerData.Portfolio.Options[contractSymbol] = nil
		end

		_G.UpdatePlayerStat(player, "Balance", playerData.Balance + totalProceeds)
	end

	CalculatorModule.calculateNetWorth(player)

	return {
		success = true,
		message = string.format(
			"%s %d x %s %s $%.2f exp %s",
			action,
			contracts,
			targetTicker,
			optionType == "C" and "Call" or "Put",
			strike or 0,
			tostring(expiration)
		),
	}
end
```

- [ ] **Step 2: Verify via Roblox Studio MCP**

Start play, join as a test player, then run via `execute_luau` (`datamodel_type: "Client"`) to exercise the remote end-to-end (buy, then sell back):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")

local chain = EventsFolder.GetOptionsDataEvent:InvokeServer("AAPL")
local strikeEntry = chain.strikes[1]
local symbol = strikeEntry.call.contractSymbol

local buyResult = EventsFolder.PlayerOptionOrderEvent:InvokeServer(
	"Buy", symbol, "AAPL", chain.expiration, strikeEntry.strike, "C", 1
)

local sellResult = EventsFolder.PlayerOptionOrderEvent:InvokeServer(
	"Sell", symbol, "AAPL", chain.expiration, strikeEntry.strike, "C", 1
)

return { buyResult = buyResult, sellResult = sellResult }
```
Expected: `buyResult.success == true` with a message like `"Buy 1 x AAPL Call $230.00 exp 2026-...".`; `sellResult.success == true`. Then check server-side via `execute_luau` (`datamodel_type: "Server"`) that `_G.PlayerData[<userId>].Portfolio.Options[symbol]` is `nil` after the sell (position fully closed) and that `player:GetAttribute("Balance")` round-tripped close to its starting value (minus the bid/ask spread on 1 contract). Also test the rejection path: call the remote with `contracts = -1` and confirm `{ success = false, message = "Invalid contract quantity." }`. Check console, stop play.

- [ ] **Step 3: Commit**

```bash
git add src/server/Core/OptionSystem.server.luau
git commit -m "$(cat <<'EOF'
Implement OptionSystem: contract buy/sell via PlayerOptionOrderEvent

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `TradeController.client.luau` — render the real option chain

**Files:**
- Modify: `src/client/Controllers/TradeController.client.luau`

**Interfaces:**
- Consumes: `GetOptionsDataEvent` (now live, from Task 3).
- Produces: `createStrikeRow`/`renderOptionChain` now consume the real backend shape (`{ strike, call: {contractSymbol, bid, ask, ...} | nil, put: {...} | nil }`) instead of the placeholder flat shape (`callBid`/`callAsk`/`putBid`/`putAsk`) that was invented before this backend route existed and never actually exercised.

- [ ] **Step 1: Rewrite `createStrikeRow`'s bid/ask rendering**

Replace the `createStrikeRow` function (currently lines 666-711):

```lua
-- s = { strike, call = { contractSymbol, bid, ask, lastPrice, impliedVolatility, volume, openInterest } | nil, put = {...} | nil }
local function createStrikeRow(parent, index, s, spotPrice)
	local callITM = spotPrice > s.strike
	local putITM = spotPrice < s.strike
	local isATM = math.abs(s.strike - spotPrice) < 0.5

	local row = Instance.new("Frame")

	row.Name = "Strike_" .. index
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT_CHAIN)
	row.BackgroundColor3 = (callITM or putITM) and BG_ITM or BG_OTM
	row.BorderSizePixel = 0
	row.LayoutOrder = index
	row.Parent = parent

	makeSeparator(row)

	local callBid = s.call and s.call.bid
	local callAsk = s.call and s.call.ask
	local putBid = s.put and s.put.bid
	local putAsk = s.put and s.put.ask

	makeLabel(row, {
		name = "CallBidAsk",
		text = string.format("%.2f / %.2f", callBid or 0, callAsk or 0),
		sz = UDim2.new(0.38, -8, 1, 0),
		pos = UDim2.fromOffset(8, 0),
		color = callITM and TEXT_PRIMARY or TEXT_SECONDARY,
		align = Enum.TextXAlignment.Left,
	})

	makeLabel(row, {
		name = "StrikeLabel",
		text = string.format("%.2f", s.strike),
		sz = UDim2.new(0.24, 0, 1, 0),
		pos = UDim2.fromScale(0.38, 0),
		color = isATM and TEXT_PRIMARY or TEXT_SECONDARY,
		font = isATM and Enum.Font.SourceSansBold or Enum.Font.SourceSans,
		align = Enum.TextXAlignment.Center,
	})

	makeLabel(row, {
		name = "PutBidAsk",
		text = string.format("%.2f / %.2f", putBid or 0, putAsk or 0),
		sz = UDim2.new(0.38, -8, 1, 0),
		pos = UDim2.new(0.62, 0, 0, 0),
		color = putITM and TEXT_PRIMARY or TEXT_SECONDARY,
		align = Enum.TextXAlignment.Right,
	})

	return row
end
```

(This step intentionally does not add the hit-area buttons yet — that's Task 7, so this task's chain-rendering fix can be verified in isolation first.)

- [ ] **Step 2: Rewrite `renderOptionChain`'s doc comment and field names**

Replace lines 873-894 (the comment block + `renderOptionChain` function):

```lua
-- Real shape, from GetOptionsDataEvent / the backend's /api/option-chain/:ticker:
-- {
--   available = true,
--   spotPrice = 150.25,
--   expiration = "2026-01-17",
--   expirationDates = { "2026-01-17", ... },
--   strikes = {
--     { strike = 145, call = { contractSymbol, bid, ask, lastPrice, impliedVolatility, volume, openInterest }, put = {...} },
--     ...
--   }
-- }
local function renderOptionChain(optionData)
	clearOptionChain()

	if not optionData or optionData.available == false or not optionData.strikes then
		return
	end

	local spotPrice = optionData.spotPrice or currentPrice

	for i, s in ipairs(optionData.strikes) do
		createStrikeRow(ChainData, i, s, spotPrice)
	end
end
```

- [ ] **Step 3: Uncomment and rewire the fetch in `loadTicker`**

Replace the commented-out block (currently lines 1151-1157):

```lua
	-- ── Options data ──────────────────────────────────────────────────────────
	local optionData = GetOptionsDataEvent:InvokeServer(ticker)

	if optionData then
		currentOptionData = optionData
		renderOptionChain(optionData)
	end
```

- [ ] **Step 4: Verify via Roblox Studio MCP playtest**

Start play, type "AAPL" into the ticker input, click the Option Chain toggle to expand it, confirm real strikes render with plausible bid/ask on both call and put sides (use `mcp__Roblox_Studio__search_game_tree` on `StarterGui.TerminalGui.MainBackground.ScreenContainer.TradeScreen.OptionChain.ChainData` to confirm `Strike_N` frames exist, then read a couple of their `CallBidAsk`/`PutBidAsk`/`StrikeLabel` label `.Text` values via `execute_luau`). Confirm console is clean (no errors from the shape change). Stop play.

- [ ] **Step 5: Commit**

```bash
git add src/client/Controllers/TradeController.client.luau
git commit -m "$(cat <<'EOF'
Wire real multi-strike option chain data into the Trade tab

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `TradeController.client.luau` — contract selection + indicator

**Files:**
- Modify: `src/client/Controllers/TradeController.client.luau`

**Interfaces:**
- Consumes: `createStrikeRow`/`renderOptionChain` from Task 6; `currentTicker`, `currentOptionData` (existing state).
- Produces: `local selectedContract` (state: `{ contractSymbol, ticker, expiration, strike, type }` or `nil`), `selectContract(contractType, strikeEntry, strike)`, `clearContractSelection()` — both consumed by Task 8's `placeOrder`, and by this task's own hit-area buttons and `loadTicker` reset.

- [ ] **Step 1: Add selection state, the indicator UI, and its functions**

Insert right after `local orderQuantity = 1` (currently line 159), **before** the `-- Map` / `TabButtons` section:

```lua
local selectedContract = nil

-- Script-generated indicator shown in the (mostly empty) space next to the
-- ticker input while an option contract is selected for trading instead of
-- shares. Clicking it clears the selection and returns to share-trading
-- mode. Created once here rather than per-row, since only one contract can
-- be selected at a time.
local ContractIndicator = Instance.new("TextButton")

ContractIndicator.Name = "ContractIndicator"
ContractIndicator.Size = UDim2.new(0.86, 0, 1, 0)
ContractIndicator.Position = UDim2.new(0.12, 0, 0, 0)
ContractIndicator.BackgroundTransparency = 1
ContractIndicator.Text = ""
ContractIndicator.TextColor3 = TEXT_PRIMARY
ContractIndicator.Font = Enum.Font.SourceSansSemibold
ContractIndicator.TextSize = 13
ContractIndicator.TextXAlignment = Enum.TextXAlignment.Left
ContractIndicator.Visible = false
ContractIndicator.Parent = InputRow

local function updateContractIndicator()
	if not selectedContract then
		ContractIndicator.Visible = false

		return
	end

	local expLabel = string.match(tostring(selectedContract.expiration), "^%d%d%d%d%-%d%d%-%d%d")
		or tostring(selectedContract.expiration)
	local typeLabel = selectedContract.type == "C" and "Call" or "Put"

	ContractIndicator.Text = string.format(
		"Now trading: %s $%.2f %s exp %s — Back to Shares",
		selectedContract.ticker,
		selectedContract.strike,
		typeLabel,
		expLabel
	)
	ContractIndicator.Visible = true
end

local function clearContractSelection()
	selectedContract = nil
	updateContractIndicator()
end

-- contractType: "C" | "P". strikeEntry: a single entry from optionData.strikes
-- (the `s` passed into createStrikeRow), so it carries both call and put.
local function selectContract(contractType, strikeEntry, strike)
	local contract = contractType == "C" and strikeEntry.call or strikeEntry.put

	if not contract or not contract.contractSymbol then
		return
	end

	selectedContract = {
		contractSymbol = contract.contractSymbol,
		ticker = currentTicker,
		expiration = currentOptionData and currentOptionData.expiration,
		strike = strike,
		type = contractType,
	}

	updateContractIndicator()
end

ContractIndicator.MouseButton1Click:Connect(clearContractSelection)
```

- [ ] **Step 2: Add the two hit-area buttons inside `createStrikeRow`**

In `createStrikeRow` (rewritten in Task 6), add before the function's final `return row`:

```lua
	if s.call and s.call.contractSymbol then
		local callHit = Instance.new("TextButton")

		callHit.Name = "CallHitArea"
		callHit.Size = UDim2.new(0.38, -8, 1, 0)
		callHit.Position = UDim2.fromOffset(8, 0)
		callHit.BackgroundTransparency = 1
		callHit.Text = ""
		callHit.ZIndex = 2
		callHit.Parent = row

		callHit.MouseButton1Click:Connect(function()
			selectContract("C", s, s.strike)
		end)
	end

	if s.put and s.put.contractSymbol then
		local putHit = Instance.new("TextButton")

		putHit.Name = "PutHitArea"
		putHit.Size = UDim2.new(0.38, -8, 1, 0)
		putHit.Position = UDim2.new(0.62, 0, 0, 0)
		putHit.BackgroundTransparency = 1
		putHit.Text = ""
		putHit.ZIndex = 2
		putHit.Parent = row

		putHit.MouseButton1Click:Connect(function()
			selectContract("P", s, s.strike)
		end)
	end
```

- [ ] **Step 3: Reset selection on ticker change**

In `loadTicker`, in the existing reset block (currently `setLoadingState(true)` / `clearOptionChain()` / `clearPositions()` / `clearNewsFeed()`), add `clearContractSelection()` right after `clearOptionChain()`:

```lua
	setLoadingState(true)
	clearOptionChain()
	clearContractSelection()
	clearPositions()
	clearNewsFeed()
```

- [ ] **Step 4: Verify via Roblox Studio MCP playtest**

Start play, load "AAPL", expand the Option Chain, click a call's bid/ask text (now covered by the invisible hit area) — confirm the indicator appears near the ticker input reading something like "Now trading: AAPL $230.00 Call exp 2026-... — Back to Shares" (read `ContractIndicator.Text`/`.Visible` via `execute_luau` rather than relying on `screen_capture`, which is known-broken in this environment). Click a put on a different strike, confirm the indicator updates to reflect the new selection. Click the indicator itself, confirm it hides (`selectedContract` back to `nil` — check via a `Client`-context `execute_luau` that reads back... actually `selectedContract` is a script-local, not globally inspectable, so instead confirm indirectly: `ContractIndicator.Visible == false`). Load a different ticker ("TSLA"), confirm the indicator is hidden again (selection cleared on ticker switch) even without clicking it first. Check console for errors, stop play.

- [ ] **Step 5: Commit**

```bash
git add src/client/Controllers/TradeController.client.luau
git commit -m "$(cat <<'EOF'
Add option contract selection: click-to-select strike, trading indicator

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `TradeController.client.luau` — place option orders

**Files:**
- Modify: `src/client/Controllers/TradeController.client.luau`

**Interfaces:**
- Consumes: `PlayerOptionOrderEvent` remote from Task 3/5; `selectedContract` from Task 7.
- Produces: `placeOrder(action)` now branches on `selectedContract` to call `PlayerOptionOrderEvent` instead of `PlayerOrderEvent` when a contract is selected — the final piece connecting the existing Buy/Sell buttons to contract trading.

- [ ] **Step 1: Add the remote reference**

After the existing `local PlayerOrderEvent = EventsFolder:WaitForChild("PlayerOrderEvent")` (currently line 23), add:

```lua
local PlayerOptionOrderEvent = EventsFolder:WaitForChild("PlayerOptionOrderEvent")
```

- [ ] **Step 2: Branch `placeOrder` on `selectedContract`**

Replace the `placeOrder` function. **Note:** Task 7 inserted new code earlier in this file (the indicator block and the two hit-area buttons), so `placeOrder`'s line number has shifted since Task 6 — locate it by its `local function placeOrder(action)` signature rather than a line number:

```lua
local function placeOrder(action)
	if currentTicker == "" or isFetchingData then
		return
	end

	if not isMarketOpen() then
		print("[TradeController] Market is closed — cannot place order.") -- Add Toast

		return
	end

	local result

	if selectedContract then
		result = PlayerOptionOrderEvent:InvokeServer(
			action,
			selectedContract.contractSymbol,
			selectedContract.ticker,
			selectedContract.expiration,
			selectedContract.strike,
			selectedContract.type,
			orderQuantity
		)
	else
		result = PlayerOrderEvent:InvokeServer(action, currentTicker, orderQuantity)
	end

	if not result or not result.success then
		print(string.format("[TradeController] %s failed: %s", action, (result and result.message) or "Unknown error"))

		return
	end

	print("[TradeController] " .. result.message)

	refreshPositions()
end
```

- [ ] **Step 3: Verify via Roblox Studio MCP playtest**

Start play (ensure market hours would pass — check `mcp__Roblox_Studio__execute_luau` with `MarketHoursModule.getMarketStatus(os.time())` first; if the real-world market is closed, this order correctly gets rejected both for shares and options, so note which case you're testing). Load "AAPL", click a call strike to select it (indicator shows), click Buy — confirm the console prints a `"Buy 1 x AAPL Call ..."` success message and the player's `Balance` attribute dropped by roughly ask×100. Click Sell on the same still-selected contract — confirm balance credits back up and the console shows a sell success message. Then click the indicator to clear the selection and click Buy again — confirm this now places a **share** order instead (unchanged regular behavior, confirms the branch didn't break the non-option path). Check console for errors, stop play.

- [ ] **Step 4: Commit**

```bash
git add src/client/Controllers/TradeController.client.luau
git commit -m "$(cat <<'EOF'
Wire Buy/Sell buttons to place option contract orders when selected

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Final verification (full pass)

- [ ] Full playtest: load "AAPL", expand the Option Chain, select a call, Buy it, confirm balance debits at ask and net worth stays consistent (balance down, option value up by roughly the same amount minus the bid/ask spread).
- [ ] While still holding that option, Buy 1 share of AAPL too. Confirm net worth now reflects **both** positions (regression check for the Task 4 bug fix — before this plan, only one of Shares/Options ever counted).
- [ ] Sell the share back, then sell the option contract back. Confirm `Portfolio.Options[contractSymbol]` is removed (not left at `contracts = 0`) and balance/net worth land back near the starting point (minus spread costs).
- [ ] Switch ticker from AAPL to TSLA mid-selection (select a contract on AAPL first, then type TSLA and hit enter). Confirm the contract indicator clears and the option chain repopulates with TSLA's own strikes, not AAPL's stale ones.
- [ ] Attempt a contract Buy while market is closed (or mock `MarketHoursModule.getMarketStatus` to return false via a quick `execute_luau` check) and confirm it's rejected the same way share orders already are, with no balance change.
- [ ] Confirm the existing Option Stats tab (nearest-expiration ATM call/put, unrelated `/api/options/:ticker` route) still works unchanged — this phase's backend route is additive, not a replacement.
