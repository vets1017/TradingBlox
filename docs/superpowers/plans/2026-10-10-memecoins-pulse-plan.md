# Player Memecoins + Pulse (Phase 2, Slice 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Any player can launch a coin (name + ticker, $1,000 fee, one per hour). Every server shows it on a new Pulse tab in New / About to graduate / Graduated columns, with one-click quick-buy, a coin panel for buy/sell presets, and a My coins list. Prices move only along a bonding curve, and graduation pays the creator $2,500 exactly once.

**Architecture:** Pure shared modules (`ReplicatedStorage.Modules.Coins`) hold the curve math, coin state transitions, rules, formatting and column sorting, so the server and client share them and they can be tested in Edit mode. On the server, `CoinStore` wraps a MemoryStore hash map (live state, one atomic `UpdateAsync` per trade) plus DataStores (durable copies, ticker registry). `PayoutMailbox` wraps a DataStore mailbox. `CoinService` holds the order and launch rules behind injected dependencies so it can be unit-tested with fakes. `CoinSystem.server.luau` wires the remotes, keeps a cached Pulse snapshot, and runs the archive, backup and payout loops. On the client, `PulseController` builds the tab and screen in code from Theme tokens, using small UI modules in `ReplicatedStorage.Modules.Pulse`.

**Tech Stack:** Luau, Rojo (`rojo serve` from `/Users/killxinu/Documents/GitHub/TradingBlox`), MemoryStoreService, DataStoreService, TextService. Studio is driven through the `Roblox_Studio` MCP tools (`studio_id: e776d95f-7161-432c-878b-e9355b6cd0db`). There's no test framework: every test is an `execute_luau` snippet with an exact expected result. It runs before the change (and fails), then after (and passes).

**Spec:** `docs/superpowers/specs/2026-10-10-memecoins-pulse-design.md`

## Global Constraints

- **Work in the main checkout, on a new branch `memecoins-pulse` cut from `main` (`0a132d9` or later). Don't use a git worktree.** Rojo serves the main checkout, and Studio must see code edits live.
- **Never stage** `docs/superpowers/specs/2026-09-20-options-trading-design.md` (Kevin's unrelated edit) or `.claude/`. Stage files by name only.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Code style: tabs, and comments that explain *why*. Match the surrounding code. Add no abstractions beyond what's written here.
- **Constants, copied from the spec into `CoinConfig`.** Every other file reads them from there; none hardcodes them.
  - Supply 1,000,000,000.
  - `V₀ = 3000`, `T₀ = 1,073,000,000`, fee 1%.
  - Graduation at `V − V₀ ≥ 8,500`, bonus $2,500.
  - Launch fee $1,000, cooldown 3,600 s, 3 live coins per player.
  - Name 2–24 characters; ticker 2–6 letters or digits.
  - Archive after 86,400 s idle; 60 price points; 20 cards per column.
  - About to graduate at progress ≥ 0.5.
  - Buy presets $100/$250/$500/$1,000 (default $250). Sell presets 25/50/75/100%.
- **Store names.** MemoryStore hash map `Coins`. DataStores `Coins_v1`, `CoinTickers_v1` and `Payouts_v1`.
  - Every coin store gets the suffix `_studio` when `RunService:IsStudio()`.
  - Store-level tests use `_studio_test` and delete what they write.
  - `PlayerData_v1` is unchanged.
- **Player-facing messages are exact strings.** Copy them from the code in this plan. Tests compare them verbatim.
- **The server computes every amount.** Clients send only an action, a coin id, and either dollars (buy) or a fraction of the position (sell).
- **UI is built in code from Theme tokens.** Nothing for Pulse is added in Studio.
  - Text on Up/Down/Accent fills is `Theme.Colors.Background`.
  - Coin tiles use `Theme.TileColors` and are named `CoinTile`; H2 exempts that name.
  - Only Builder Sans and Roboto Mono, through `Theme.Fonts`. Only `Theme.TextSize` sizes.
- **Testing in Studio:**
  - Pure modules are tested in **Edit** mode on a fresh clone (Snippet H7), because Studio caches `require` per ModuleScript.
  - Play mode gets a new DataModel on every start, so Play tests require modules directly. **Code edits don't reach a running playtest**: finish the code, then start Play.
  - `execute_luau` has its own `_G`. To touch the game's `_G.PlayerData`, use Snippet H5.
  - Play viewport is 615×659, with TopbarInset `(164,0)-(615,58)`.
  - TextBox input: `CaptureFocus()`, then set `.Text`, then `ReleaseFocus(true)`, from a Client `execute_luau`. Task 7's launch form is the exception: `true` acts as pressing Enter, which submits the form, so its snippet chooses per box. Buttons: `user_mouse_input` with `instance_path`.
  - `screen_capture` doesn't work here, so verify structurally.
- **Playtests write Kevin's real save** (`PlayerData_v1`):
  - Task 0 records his starting balance as `START_BALANCE`.
  - **Before every `start_stop_play(false)`, run H5 with `ACTION = "RESTORE"`.** It puts the balance back and clears coin holdings and launches. Shares and options are never touched by these tests.
- Remotes hit back-to-back within 0.5 s are throttled. Test snippets that call the same remote twice put `task.wait(0.6)` between the calls.

### Rulings made while planning (deviations from the spec; flagged to Kevin)

1. **Launch checks run cheapest first.** Order: rules → cooldown → limits → balance → text filter → ticker claim → create. The spec puts the filter second. The filter is a rate-limited web call, and there's no reason to make it for a launch that fails anyway. The player gets the same result; only which refusal they see first differs.
2. **Cash is reserved first and refunded on failure,** rather than charged last. A share trade (`TradeSystem`) can change the balance while a coin call waits on the store. Charging last could then take the balance below zero. The guarantee the spec cares about still holds: any failure charges nothing.
3. **The graduated card shows a "Graduated" text badge, not ★.** Whether Builder Sans has a ★ glyph is unverified, and a tofu box would look broken.
4. **A failed coin update says "Coins unavailable, try again."** This keeps the spec's "Try again" and says why.
5. **Price points store market cap rounded to whole dollars,** not price. This keeps one coin under about 1 KB (Task 0 measures it). The sparkline doesn't depend on scale.
6. **Launch history is one field:** `CoinLaunches = { lastAt, ids }`, not `LastLaunchAt` plus a separate list.
7. **Tab order is set in `ShellController`,** which already lays the tabs out. `TerminalController` only gains the `Pulse` entry.
8. **The Pulse refresh interval is computed:** `clamp(liveCoins × 60 / (50 × playersInServer), 12, 60)` seconds. The spec says "about 10–15 s" and also that the interval must fit the memory-store limits, so this fits them.
9. **A sell doesn't reserve tokens.** The per-player order lock already stops a second order from selling them. This matches the spec's order: check, update, credit.
10. **A payout whose claim committed but then errored is lost, not paid twice.** The claim marks ids as paid, and the other order would risk a double payment.
11. **Live coins are capped at 50** (`MAX_LIVE_COINS`), so a full Pulse fits the 64 KB base memory-store quota at about 1 KB per coin.
12. **My coins refreshes when opened, after each order, and every 30 s while shown,** not every 5 s. Archived rows cost store reads.
13. **Throttled remotes:** the three read remotes return `nil`, and the client keeps its current view. Order and launch remotes return "Slow down."
14. **Buys are at least $1** ("Minimum buy is $1."), where the spec only says "greater than 0". Amounts are rounded to cents, so a tiny amount would become a $0.00 buy that still moves the trade count and writes a price point. A NaN, infinite or non-number amount gets the same message.

## Review Focus

1. **A player leaves (or the server shuts down) mid-order.** Expected: no money is lost or duplicated, because the save waits for the order to finish. → Task 4: `_G.WaitForCoinOrders` (H5 `WAIT` check), and `Data_Manager` waiting before it saves.
2. **Double clicks and spam.** Expected: one order per click, never two charges from one balance. → Task 4: the CoinService lock check and the concurrent-remote integration check. Task 6: buttons are disabled while an order is in flight.
3. **The memory store is unreachable.** Expected:
   - the header says "Coins unavailable, retrying…";
   - buy, sell and launch buttons are disabled;
   - the last snapshot stays on screen with its age;
   - any reserved cash is refunded.

   → Task 4: refund on store failure (unit). Task 6: the unavailable-snapshot check. Task 7: the Launch button is disabled too.
4. **Extreme values.** Expected: the text stays readable and nothing overflows. Cases: a 24-character name, sold-out caps (about $604k), a price of $0.0000028, `999,960` tokens, and a $1,234,567.89 balance. → Task 1: format cases. Task 6: H2 with the seeded long-name coin.
5. **Clock skew between servers.** Expected:
   - an age never goes negative;
   - price points never go back in time;
   - a coin's last trade time never goes backward.

   → Task 1: `age(-5)`. Task 2: the skewed-trade check. The client uses the server's clock (`serverTime`) for ages.

---

## File map

| File | Status | Responsibility |
|---|---|---|
| `src/shared/Modules/Coins/CoinConfig.luau` | Create | Every coin constant; `snapshotInterval` |
| `src/shared/Modules/Coins/CoinCurve.luau` | Create | Bonding-curve math: price, cap, progress, buy/sell quotes |
| `src/shared/Modules/Coins/CoinRules.luau` | Create | Name and ticker validation |
| `src/shared/Modules/Coins/CoinFormat.luau` | Create | Token counts, ages, tiny prices, preset labels |
| `src/shared/Modules/Coins/CoinState.luau` | Create | Immutable coin state transitions, price points, summaries |
| `src/shared/Modules/Coins/PulseColumns.luau` | Create | Assign and sort summaries into the three columns |
| `src/server/Modules/CoinStore.luau` | Create | MemoryStore + DataStore access for coins and tickers |
| `src/server/Modules/PayoutMailbox.luau` | Create | Exactly-once payouts through a DataStore mailbox |
| `src/server/Modules/CoinService.luau` | Create | Launch, buy, sell and My coins rules, with injected deps |
| `src/server/Core/CoinSystem.server.luau` | Create | Remotes, snapshot cache, archive/backup/payout loops |
| `src/server/Core/ServerSetup.server.luau` | Modify | Five new remotes |
| `src/server/Core/Data_Manager.server.luau` | Modify | Coin fields defaulted on load; save waits for coin orders |
| `src/server/Modules/CalculatorModule.luau` | Modify | Net worth includes coins |
| `src/shared/Modules/Multi/Theme.luau` | Modify | `Theme.TileColors` |
| `src/client/Controllers/ShellController.client.luau` | Modify | Tab order and adaptive tab padding for five tabs |
| `src/client/Controllers/TerminalController.client.luau` | Modify | `Tabs.Pulse` |
| `src/shared/Modules/Pulse/PulseUI.luau` | Create | Small builders for code-made UI |
| `src/shared/Modules/Pulse/CoinCard.luau` | Create | One Pulse card |
| `src/shared/Modules/Pulse/Sparkline.luau` | Create | House-style gradient line |
| `src/shared/Modules/Pulse/CoinPanel.luau` | Create | The right-side coin panel |
| `src/shared/Modules/Pulse/LaunchForm.luau` | Create | The launch dialog |
| `src/client/Controllers/PulseController.client.luau` | Create | The Pulse tab and screen |
| `CLAUDE.md` | Modify | Document coins, Pulse and the new remotes |

---

## Shared verification snippets

Tasks reference these by name. Copy them verbatim, changing only the marked constants.

### H2: Palette, font and text-fit audit (Client datamodel, during Play)

This is Phase 1's audit with one addition: frames named `CoinTile` are exempt, because they're painted with identity colors (data, not chrome). Set `SCOPE` to `"Shell"` or a screen name under `ScreenContainer` (`"PulseScreen"`). It only checks elements currently shown. **Pass = `0 problem(s)`, and font families are exactly `rbxassetid://16658221428, rbxasset://fonts/families/RobotoMono.json` (in either order).**

```lua
local SCOPE = "PulseScreen"

local Players = game:GetService("Players")
local Theme = require(game:GetService("ReplicatedStorage").Modules.Multi.Theme)
local gui = Players.LocalPlayer.PlayerGui.TerminalGui
local mb = gui.MainBackground

local allowed = {}
for _, color in pairs(Theme.Colors) do
	allowed[color:ToHex()] = true
end

local allowedSizes = {}
for _, size in pairs(Theme.TextSize) do
	allowedSizes[size] = true
end

local function isShown(inst)
	local cur = inst
	while cur and cur ~= gui do
		if cur:IsA("GuiObject") and not cur.Visible then
			return false
		end
		cur = cur.Parent
	end
	return true
end

-- Data colors, not chrome: coin identity tiles, indicator and drawing
-- lines, and anything a UIGradient paints (sparklines, the nav accent line)
local function isDataColored(inst)
	if inst.Name == "CoinTile" or inst:FindFirstChildOfClass("UIGradient") then
		return true
	end
	local cur = inst
	while cur and cur ~= gui do
		if cur.Name == "IndicatorsContainer" or cur.Name == "DrawingsContainer" then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local problems, families = {}, {}

local function check(inst)
	if not inst:IsA("GuiObject") or not isShown(inst) or isDataColored(inst) then
		return
	end

	local name = string.gsub(inst:GetFullName(), "^.-TerminalGui%.MainBackground%.", "")
	local bgIsSeriesColor = inst.Parent and inst.Parent.Name == "IndicatorsDropdownList"

	if inst.BackgroundTransparency < 1 and not bgIsSeriesColor and not allowed[inst.BackgroundColor3:ToHex()] then
		table.insert(problems, "bg   " .. name .. " #" .. inst.BackgroundColor3:ToHex())
	end

	local stroke = inst:FindFirstChildOfClass("UIStroke")
	if stroke and stroke.Enabled and stroke.Transparency < 1 and not allowed[stroke.Color:ToHex()] then
		table.insert(problems, "line " .. name .. " #" .. stroke.Color:ToHex())
	end

	local isText = inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
	if isText and inst.Text ~= "" and inst.TextTransparency < 1 then
		if not allowed[inst.TextColor3:ToHex()] then
			table.insert(problems, "text " .. name .. " #" .. inst.TextColor3:ToHex())
		end
		if not allowedSizes[inst.TextSize] then
			table.insert(problems, "size " .. name .. " " .. inst.TextSize)
		end
		if not inst.TextFits and inst.TextTruncate == Enum.TextTruncate.None then
			table.insert(problems, "fit  " .. name .. " '" .. inst.Text .. "'")
		end
		families[inst.FontFace.Family] = true
	end
end

local roots = SCOPE == "Shell" and { mb.TopBar, mb.StatusBar } or { mb.ScreenContainer[SCOPE] }
for _, r in ipairs(roots) do
	check(r)
	for _, d in ipairs(r:GetDescendants()) do
		check(d)
	end
end

local familyList = {}
for family in pairs(families) do
	table.insert(familyList, family)
end

return string.format("%s: %d problem(s)\n%s\nfont families: %s", SCOPE, #problems, table.concat(problems, "\n"), table.concat(familyList, ", "))
```

### H3: Shell layout check (Client datamodel, during Play)

**Pass = every value is `true`.** This is unchanged from Phase 1. It now also proves five tabs fit.

```lua
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local mb = Players.LocalPlayer.PlayerGui.TerminalGui.MainBackground
local topBar, screens, status = mb.TopBar, mb.ScreenContainer, mb:FindFirstChild("StatusBar")
local wordmark, pill, tabs = topBar:FindFirstChild("Wordmark"), topBar:FindFirstChild("BalancePill"), topBar.TabContainer
local inset = GuiService.TopbarInset
local viewport = workspace.CurrentCamera.ViewportSize

local tabsWidth, tabCount = 0, 0
for _, b in ipairs(tabs:GetChildren()) do
	if b:IsA("TextButton") then
		tabsWidth += b.AbsoluteSize.X
		tabCount += 1
	end
end
tabsWidth += math.max(tabCount - 1, 0) * tabs.UIListLayout.Padding.Offset

local navBottom = topBar.AbsolutePosition.Y + topBar.AbsoluteSize.Y
local result = {
	fiveTabs = tabCount == 5,
	fullWidth = math.abs(mb.AbsoluteSize.X - viewport.X) <= 1,
	fullHeight = math.abs(mb.AbsoluteSize.Y - viewport.Y) <= 1,
	wordmarkClearOfRobloxButtons = wordmark ~= nil and (not wordmark.Visible or wordmark.AbsolutePosition.X >= inset.Min.X),
	tabsAfterWordmark = wordmark ~= nil and (not wordmark.Visible or tabs.AbsolutePosition.X >= wordmark.AbsolutePosition.X + wordmark.AbsoluteSize.X),
	tabsClearOfRobloxButtons = tabs.AbsolutePosition.X >= inset.Min.X,
	tabsFit = tabsWidth <= tabs.AbsoluteSize.X,
	pillAfterTabs = pill ~= nil and pill.AbsolutePosition.X >= tabs.AbsolutePosition.X + tabs.AbsoluteSize.X,
	pillOnScreen = pill ~= nil and pill.AbsolutePosition.X + pill.AbsoluteSize.X <= mb.AbsolutePosition.X + mb.AbsoluteSize.X,
	screensBelowNav = screens.AbsolutePosition.Y >= navBottom - 1,
	screensAboveStatus = status ~= nil and screens.AbsolutePosition.Y + screens.AbsoluteSize.Y <= status.AbsolutePosition.Y + 1,
	statusAtBottom = status ~= nil and math.abs((status.AbsolutePosition.Y + status.AbsoluteSize.Y) - (mb.AbsolutePosition.Y + mb.AbsoluteSize.Y)) <= 1,
}

local lines = { string.format("inset=%s viewport=%s tabsWidth=%d container=%d", tostring(inset), tostring(viewport), tabsWidth, tabs.AbsoluteSize.X) }
for k, v in pairs(result) do
	table.insert(lines, k .. "=" .. tostring(v))
end
return table.concat(lines, "\n")
```

### H5: Act on the game's real `_G.PlayerData` (Server datamodel, during Play)

`execute_luau` has its own `_G`, so this injects a real Script that reports back as JSON through a ServerStorage attribute. Set `ACTION` and `BALANCE`:

- `"READ"` changes nothing.
- `"SETUP"` resets the launch cooldown and sets the balance to `BALANCE`. It needs Task 4.
- `"RESTORE"` sets the balance to `BALANCE` (use `START_BALANCE` from Task 0) and clears coin holdings and launches. It needs Task 4.
- `"WAIT"` times `_G.WaitForCoinOrders` for an idle player. It needs Task 4.

Every action also reports `coinValue`, the game's own valuation of the player's coins (`CalculatorModule.coinValue`). It's absent before Task 4.

```lua
local ACTION = "READ"
local BALANCE = 0

local ServerStorage = game:GetService("ServerStorage")
ServerStorage:SetAttribute("H5Result", nil)

local probe = Instance.new("Script")
probe.Name = "TEST_H5"
probe.Source = string.format([[
	local HttpService = game:GetService("HttpService")
	local player = game:GetService("Players"):GetPlayers()[1]
	local ACTION, BALANCE = %q, %s
	local data = player and _G.PlayerData and _G.PlayerData[player.UserId]
	local result = { ok = data ~= nil, hasWait = type(_G.WaitForCoinOrders) == "function" }
	if data then
		if ACTION == "SETUP" then
			data.CoinLaunches.lastAt = 0
			_G.UpdatePlayerStat(player, "Balance", BALANCE)
		elseif ACTION == "RESTORE" then
			data.Portfolio.Coins = {}
			data.CoinLaunches = { lastAt = 0, ids = {} }
			_G.UpdatePlayerStat(player, "Balance", BALANCE)
		elseif ACTION == "WAIT" then
			local started = os.clock()
			_G.WaitForCoinOrders(player.UserId, 10)
			result.waited = os.clock() - started
		end
		result.balance = data.Balance
		result.shares = data.Portfolio and data.Portfolio.Shares
		result.coins = data.Portfolio and data.Portfolio.Coins
		result.launches = data.CoinLaunches
		local calculator = require(game:GetService("ServerScriptService").Modules.CalculatorModule)
		result.coinValue = calculator.coinValue and calculator.coinValue(data)
	end
	game:GetService("ServerStorage"):SetAttribute("H5Result", HttpService:JSONEncode(result))
	script:Destroy()
]], ACTION, tostring(BALANCE))
probe.Parent = game:GetService("ServerScriptService")

local deadline = os.clock() + 15
while ServerStorage:GetAttribute("H5Result") == nil and os.clock() < deadline do
	task.wait(0.1)
end
return ServerStorage:GetAttribute("H5Result") or "probe did not run"
```

### H7: Fresh require in Edit mode

Studio caches `require` per ModuleScript in Edit mode, so each Edit-mode test clones what it needs into `ServerStorage` and requires the clone. Clone the whole `Coins` folder so `script.Parent` siblings are fresh too. Every Edit-mode test below starts with this and ends with `holder:Destroy()`.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local holder = Instance.new("Folder")
holder.Name = "TEST_Fresh"
holder.Parent = ServerStorage
local Coins = ReplicatedStorage.Modules.Coins:Clone()
Coins.Parent = holder
```

Every test uses this checker:

```lua
local total, failures = 0, {}
local function check(name, actual, expected, tolerance)
	total += 1
	local pass
	if tolerance then
		pass = typeof(actual) == "number" and math.abs(actual - expected) <= tolerance
	else
		pass = actual == expected
	end
	if not pass then
		table.insert(failures, string.format("FAIL %s: got %s, want %s", name, tostring(actual), tostring(expected)))
	end
end
local function report()
	return string.format("%d/%d passed\n%s", total - #failures, total, table.concat(failures, "\n"))
end
```

### H8: Seed three coins into the Studio Pulse (Server datamodel, during Play)

This writes straight to the `_studio` stores the running game reads, so the game's snapshot picks the coins up within 15 s. It returns their ids as JSON. **Keep the ids;** Tasks 6 and 8 refer to them as `LONG`, `ABOUT` and `GRAD`. Ticker suffixes are random, so seeding can be repeated.

```lua
local HttpService = game:GetService("HttpService")
local CoinState = require(game:GetService("ReplicatedStorage").Modules.Coins.CoinState)
local CoinStore = require(game:GetService("ServerScriptService").Modules.CoinStore)

local now = os.time()
local suffix = tostring(math.random(100, 999))

local function seed(name, ticker, buyDollars, ageSeconds)
	local id = string.lower((string.gsub(HttpService:GenerateGUID(false), "-", "")))
	local state = CoinState.new({ id = id, name = name, ticker = ticker, creatorId = 1, creatorName = "Roblox", now = now - ageSeconds })
	if buyDollars > 0 then
		state = CoinState.applyBuy(state, buyDollars, 2, now)
	end
	assert(CoinStore.create(state), "create failed for " .. ticker)
	return id
end

return HttpService:JSONEncode({
	LONG = seed("Twenty Four Characters!!", "LNG" .. suffix, 0, 30), -- 24 chars, no trades: New
	ABOUT = seed("Halfway There", "HLF" .. suffix, 5000, 600), -- progress 0.58: About to graduate
	GRAD = seed("Moon Mission", "GRD" .. suffix, 8600, 3600), -- V = $11,514: Graduated
})
```

### H9: Archive the test player's live coins (Server datamodel, during Play)

Coins launched in earlier playtests stay live in the `_studio` store. A player may hold at most 3 live coins, so without this a rerun of Task 4, 7 or 8 fails with "You already have 3 live coins." Run it right after H5 `SETUP` in any check that launches a coin. Archived coins stay sellable under My coins.

```lua
local CoinStore = require(game:GetService("ServerScriptService").Modules.CoinStore)
local userId = game:GetService("Players"):GetPlayers()[1].UserId
local mine = {}
for _, state in ipairs(CoinStore.listLive() or {}) do
	if state.creatorId == userId then
		table.insert(mine, state)
	end
end
return string.format("mine=%d archived=%d", #mine, CoinStore.archiveIdle(mine, os.time() + 25 * 3600))
```

Expected: `mine=` and `archived=` are equal (both `0` on a first run). Then wait 15 s. The launch limit reads the server's snapshot, which refreshes at least every 12 s while there are few coins.

---
## Recording results

Each task ends by writing one line that ends in `PASS` to `$WS/task-N-studio.txt`, then running `task-done`, which checks that line. `<BASE>` is the commit that `$S/executing-plans/scripts/task-start $PLAN N` prints when the task starts: the HEAD before the task's first commit. Set up these variables once per shell:

```bash
cd /Users/killxinu/Documents/GitHub/TradingBlox
PLAN=docs/superpowers/plans/2026-10-10-memecoins-pulse-plan.md
S=/Users/killxinu/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills
WS=$($S/subagent-driven-development/scripts/sdd-workspace $PLAN)
```

---

### Task 0: Verify the platform, start the branch

This task makes no code changes and no commit. It records `START_BALANCE` and the platform facts the later tasks depend on.

**Files:** none.

**Interfaces:**
- Consumes: nothing.
- Produces:
  - branch `memecoins-pulse`;
  - `START_BALANCE` (Kevin's balance before any test), recorded in `$WS/task-0-studio.txt`;
  - rulings in the ledger if a platform fact contradicts this plan.

- [ ] **Step 1: Start the branch**

```bash
git -C /Users/killxinu/Documents/GitHub/TradingBlox status --short
git -C /Users/killxinu/Documents/GitHub/TradingBlox switch -c memecoins-pulse
git -C /Users/killxinu/Documents/GitHub/TradingBlox branch --show-current
```

Expected:
- Status shows only ` M docs/superpowers/specs/2026-09-20-options-trading-design.md` and `?? .claude/`, plus `?? docs/superpowers/plans/2026-10-10-memecoins-pulse-plan.md` if the plan isn't committed yet.
- The last line is `memecoins-pulse`.

- [ ] **Step 2: Record Kevin's starting save**

Run `start_stop_play(true)` and wait about 5 s. Run **H5** with `ACTION = "READ"`.

Expected: `"ok":true` and `"hasWait":false`. `launches` and `coins` are absent, because his save predates coins. Write down `balance` as **`START_BALANCE`**, and note `shares`.

- [ ] **Step 3: Probe the memory store** (Server datamodel, during Play)

```lua
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local map = MemoryStoreService:GetHashMap("Coins_studio_probe")
local out = {}
local ok, err = pcall(function()
	map:SetAsync("probe", { n = 1 }, 3888000) -- the 45-day maximum this plan uses
	out.updated = map:UpdateAsync("probe", function(old)
		return { n = old.n + 1 }
	end, 60)
	out.cancelled = map:UpdateAsync("probe", function()
		return nil
	end, 60)
	local page = map:ListItemsAsync(10):GetCurrentPage()
	out.firstKey = page[1] and page[1].key
	out.firstValueType = page[1] and typeof(page[1].value)
	map:RemoveAsync("probe")
	out.afterRemove = map:GetAsync("probe")
end)
out.ok, out.err = ok, err and tostring(err)
return HttpService:JSONEncode(out)
```

Expected: `"ok":true`, `"updated":{"n":2}`, no `cancelled` key (a cancelled update returns nil), `"firstKey":"probe"`, `"firstValueType":"table"`, and no `afterRemove` key.

If `ok` is false, the memory store doesn't work in Studio playtests for this place. **Stop and ask Kevin.** He may need to enable Studio access to API services (Game Settings → Security).

- [ ] **Step 4: Probe DataStore cancel and one coin's size** (Server datamodel, during Play)

The table below has the same shape as a real coin: the largest name and creator name, and 60 whole-dollar price points.

```lua
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local store = DataStoreService:GetDataStore("Coins_v1_studio_test")
local cancelled = store:UpdateAsync("probe", function()
	return nil
end)

local points = {}
for i = 1, 60 do
	points[i] = 604053 - i
end
local coin = {
	id = string.rep("f", 32), name = string.rep("W", 24), ticker = "ABCDEF",
	creatorId = 9999999999, creatorName = string.rep("n", 20), createdAt = 1760000000,
	V = 11514.000000000002, T = 279573032.5555556, volume = 123456.78, trades = 99999,
	lastTradeAt = 1760000000, creatorTokens = 123456789, graduated = true, graduatedAt = 1760000000,
	points = points, pointsMinute = 29333333,
}
return string.format("cancelled=%s bytes=%d", tostring(cancelled), #HttpService:JSONEncode(coin) + 32)
```

Expected: `cancelled=nil`, and `bytes=` under 1024. If it's 1024 or more, **ledger a ruling** that lowers `MAX_LIVE_COINS` in Task 1 to `floor(65536 / bytes) - 4`.

- [ ] **Step 5: Probe the text filter** (Server datamodel, during Play)

```lua
local TextService = game:GetService("TextService")
local player = game:GetService("Players"):GetPlayers()[1]
local function filter(text, userId)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()
	end)
	return ok and result or ("ERROR " .. tostring(result))
end
return string.format("own=[%s] absent=[%s] digits=[%s]", filter("Pepe Coin", player.UserId), filter("Pepe Coin", 1), filter("PEPE123", player.UserId))
```

Expected: `own=[Pepe Coin]`. Record what `absent` and `digits` return.
- If `absent` is `ERROR …`, re-filtering names for creators who aren't in the server fails. `CoinSystem`'s `displayNames` already falls back to the stored (launch-filtered) names in that case. Ledger it as a note; no code change.
- If `digits` comes back hashed (`#`), tickers with digits get "Name not allowed." for this account. That's expected behavior, not a bug. Ledger it as a note.

Then run `start_stop_play(false)`. Nothing changed the save, so H5 RESTORE isn't needed here.

- [ ] **Step 6: Check the published limits**

WebFetch `https://create.roblox.com/docs/cloud-services/memory-stores` (and its limits section or page), then `https://create.roblox.com/docs/ui/text-filtering`. Record:

1. Memory size quota. This plan assumes 64 KB + 1 KB × users online, experience-wide.
2. Request-unit quota. This plan assumes 1,000 + 100 × users per minute, and that `ListItemsAsync` costs at most one unit per item returned.
3. Maximum item expiration. This plan assumes 3,888,000 s (45 days).
4. Whether stored user text must be re-filtered when displayed. This plan re-filters names every 30 minutes, showing the launch-filtered text until then.

Wherever a fact is stricter than the assumption:
- **ledger a ruling** that changes the matching constant in Task 1 (`MAX_LIVE_COINS`, `LISTING_UNITS_PER_PLAYER`) or Task 3 (`EXPIRATION`);
- note the new value. Later tasks use it.

- [ ] **Step 7: Record the result**

```bash
printf '%s\n' "Task 0: START_BALANCE=<value>; memory store, DataStore cancel, size <bytes>B, filter own ok; limits checked PASS" > "$WS/task-0-studio.txt"
$S/executing-plans/scripts/task-done $PLAN 0 $(git rev-parse HEAD) -- grep -q 'PASS$' "$WS/task-0-studio.txt"
```

Expected: `task-done` prints the line and records `Task 0: complete` in the ledger.

---

### Task 1: Coin config, curve math, rules and formatting

**Files:**
- Create: `src/shared/Modules/Coins/CoinConfig.luau`, `src/shared/Modules/Coins/CoinCurve.luau`, `src/shared/Modules/Coins/CoinRules.luau`, `src/shared/Modules/Coins/CoinFormat.luau`
- Test: Edit-mode `execute_luau` (below)

**Interfaces:**
- Consumes: nothing.
- Produces (all in `ReplicatedStorage.Modules.Coins`):
  - **`CoinConfig`:** the constants listed in Global Constraints, by the names in the code below, plus `snapshotInterval(liveCoins, playersInServer) -> seconds`.
  - **`CoinCurve`:**
    - `K`;
    - `price(V, T)`, `marketCap(V, T)`, `progress(V)` (0–1), `tokensSold(T)`;
    - `quoteBuy(V, T, dollars) -> { tokensOut, fee, cashIn, newV, newT }`, or `nil, message`;
    - `quoteSell(V, T, tokens) -> { payout, fee, gross, newV, newT }`, or `nil, message`.
  - **`CoinRules`:** `validateName(any) -> cleanedName` or `nil, message`; `validateTicker(any) -> TICKER` or `nil, message`.
  - **`CoinFormat`:** `tokens(n)`, `age(seconds)`, `price(p)`, `preset(dollars)`, each returning a string.

- [ ] **Step 1: Write the failing test** (Edit datamodel)

Start with the **H7** header and checker, then:

```lua
local CoinConfig = require(Coins.CoinConfig)
local CoinCurve = require(Coins.CoinCurve)
local CoinRules = require(Coins.CoinRules)
local CoinFormat = require(Coins.CoinFormat)

local V0, T0 = 3000, 1073000000
local K = V0 * T0

-- The spec's key numbers
check("launchCap", CoinCurve.marketCap(V0, T0), 2795.90, 0.005)
local buy = CoinCurve.quoteBuy(V0, T0, 250)
check("buy250 tokens", buy and buy.tokensOut, 81775981)
check("buy250 fee", buy and buy.fee, 2.5, 1e-9)
check("buy250 newV", buy and buy.newV, 3247.5, 1e-9)
check("buy250 newT", buy and buy.newT, T0 - 81775981)
local sell = buy and CoinCurve.quoteSell(buy.newV, buy.newT, buy.tokensOut)
check("roundTrip payout", sell and sell.payout, 245.02)
check("roundTrip newT", sell and sell.newT, T0)
check("roundTrip newV", sell and sell.newV, V0, 1e-6)
check("progress at launch", CoinCurve.progress(V0), 0)
check("progress at graduation", CoinCurve.progress(V0 + 8500), 1)
check("progress just short", CoinCurve.progress(V0 + 8499.99) < 1, true)
check("progress capped", CoinCurve.progress(50000), 1)
check("graduationCap", CoinCurve.marketCap(11500, K / 11500), 41084.19, 0.05)
check("maxCap", CoinCurve.marketCap(K / 73000000, 73000000), 604053.29, 1)
check("tokensSold at launch", CoinCurve.tokensSold(T0), 0)

-- Sold out: one token left, a $100 buy wants far more
local lastT = T0 - 1000000000 + 1
local soldOut, soldOutErr = CoinCurve.quoteBuy(K / lastT, lastT, 100)
check("soldOut quote", soldOut, nil)
check("soldOut message", soldOutErr, "Sold out.")

-- The floor: selling can't take the curve below its starting pools
check("sell floor", select(2, CoinCurve.quoteSell(V0, T0, 1)), "Can't sell that many tokens right now.")
check("too small", select(2, CoinCurve.quoteBuy(V0, T0, 0.000001)), "Amount too small.")

-- Buying then selling everything never returns more than was paid
local noFreeMoney = true
for _, dollars in ipairs({ 1, 37.5, 250, 1000, 9000, 40000 }) do
	local b = CoinCurve.quoteBuy(V0, T0, dollars)
	local s = b and CoinCurve.quoteSell(b.newV, b.newT, b.tokensOut)
	if not s or s.payout > dollars then
		noFreeMoney = false
	end
end
check("buy then sell never profits", noFreeMoney, true)

-- Rules
check("name trimmed", CoinRules.validateName("  Pepe   Coin "), "Pepe Coin")
check("name 24 ok", CoinRules.validateName("Twenty Four Characters!!"), "Twenty Four Characters!!")
check("name too short", select(2, CoinRules.validateName("P")), "Name must be 2-24 characters.")
check("name too long", select(2, CoinRules.validateName(string.rep("a", 25))), "Name must be 2-24 characters.")
check("name huge", select(2, CoinRules.validateName(string.rep("a", 100000))), "Name must be 2-24 characters.")
check("name charset", select(2, CoinRules.validateName("Pepe<3")), "Name can use letters, numbers, spaces and . , ' ! ? - _ &")
check("name not string", select(2, CoinRules.validateName(42)), "Enter a name.")
check("name blank", select(2, CoinRules.validateName("   ")), "Enter a name.")
check("ticker cleaned", CoinRules.validateTicker(" $pepe "), "PEPE")
check("ticker digits", CoinRules.validateTicker("pepe1"), "PEPE1")
check("ticker space", select(2, CoinRules.validateTicker("PE PE")), "Ticker must be 2-6 letters or numbers.")
check("ticker short", select(2, CoinRules.validateTicker("P")), "Ticker must be 2-6 letters or numbers.")
check("ticker long", select(2, CoinRules.validateTicker("ABCDEFG")), "Ticker must be 2-6 letters or numbers.")
check("ticker blank", select(2, CoinRules.validateTicker("  ")), "Enter a ticker.")
check("ticker not string", select(2, CoinRules.validateTicker(nil)), "Enter a ticker.")

-- Formatting, including the extremes
check("tokens M", CoinFormat.tokens(81775981), "81.8M")
check("tokens B", CoinFormat.tokens(1000000000), "1.00B")
check("tokens K", CoinFormat.tokens(1234), "1.2K")
check("tokens small", CoinFormat.tokens(999), "999")
check("tokens zero", CoinFormat.tokens(0), "0")
check("tokens rounds up a unit", CoinFormat.tokens(999960), "1.0M")
check("age s", CoinFormat.age(45), "45s")
check("age m", CoinFormat.age(180), "3m")
check("age h", CoinFormat.age(7200), "2h")
check("age d", CoinFormat.age(30 * 86400), "30d")
check("age negative", CoinFormat.age(-5), "0s")
check("price tiny", CoinFormat.price(V0 / T0), "$0.00000280")
check("price dollars", CoinFormat.price(1.5), "$1.50")
check("price zero", CoinFormat.price(0), "$0.00")
check("preset 250", CoinFormat.preset(250), "$250")
check("preset 1000", CoinFormat.preset(1000), "$1K")

-- Pulse refresh pacing
check("interval floor", CoinConfig.snapshotInterval(10, 20), 12)
check("interval ceiling", CoinConfig.snapshotInterval(50, 1), 60)
check("interval scaled", CoinConfig.snapshotInterval(25, 2), 15)
check("interval empty server", CoinConfig.snapshotInterval(0, 0), 12)

holder:Destroy()
return report()
```

- [ ] **Step 2: Run it and confirm it fails**

Expected: an error, `Coins is not a valid member of Folder "ReplicatedStorage.Modules"`. (If it errors after cloning, destroy `ServerStorage.TEST_Fresh` by hand.)

- [ ] **Step 3: Write `CoinConfig.luau`**

```lua
-- CoinConfig.luau
--
-- Every constant for player memecoins, in one place. The curve is a
-- constant product with virtual reserves (spec: docs/superpowers/specs/
-- 2026-10-10-memecoins-pulse-design.md): V * T stays at
-- VIRTUAL_CASH * VIRTUAL_TOKENS, and the virtual padding stops the first
-- buyer taking most of the supply for pennies.

local CoinConfig = {}

-- Curve
CoinConfig.TOTAL_SUPPLY = 1000000000
CoinConfig.VIRTUAL_CASH = 3000
CoinConfig.VIRTUAL_TOKENS = 1073000000
CoinConfig.FEE_RATE = 0.01
CoinConfig.GRADUATION_CASH = 8500 -- net cash into the curve that graduates a coin
CoinConfig.GRADUATION_BONUS = 2500

-- Launching
CoinConfig.LAUNCH_FEE = 1000
CoinConfig.LAUNCH_COOLDOWN = 3600
CoinConfig.MAX_LIVE_COINS_PER_PLAYER = 3
CoinConfig.MAX_LIVE_COINS = 50 -- a full Pulse at ~1 KB per coin fits the 64 KB base memory-store quota
CoinConfig.NAME_MIN = 2
CoinConfig.NAME_MAX = 24
CoinConfig.TICKER_MIN = 2
CoinConfig.TICKER_MAX = 6

-- Lifecycle and display
CoinConfig.ARCHIVE_AFTER = 86400
CoinConfig.PRICE_POINTS = 60
CoinConfig.COLUMN_SIZE = 20
CoinConfig.ABOUT_TO_GRADUATE_PROGRESS = 0.5
CoinConfig.BUY_PRESETS = { 100, 250, 500, 1000 }
CoinConfig.SELL_PRESETS = { 0.25, 0.5, 0.75, 1 }
CoinConfig.DEFAULT_QUICK_BUY = 250
CoinConfig.MY_COINS_LIMIT = 30 -- held coins always show; launched-only coins fill up to this

-- Pulse refresh pacing. Memory-store requests are budgeted per player
-- online; listing spends about half of each player's share, at one unit per
-- coin listed
CoinConfig.SNAPSHOT_MIN_INTERVAL = 12
CoinConfig.SNAPSHOT_MAX_INTERVAL = 60
CoinConfig.LISTING_UNITS_PER_PLAYER = 50

function CoinConfig.snapshotInterval(liveCoins, playersInServer)
	local unitsPerMinute = CoinConfig.LISTING_UNITS_PER_PLAYER * math.max(playersInServer, 1)
	local interval = math.max(liveCoins, 1) * 60 / unitsPerMinute

	return math.clamp(interval, CoinConfig.SNAPSHOT_MIN_INTERVAL, CoinConfig.SNAPSHOT_MAX_INTERVAL)
end

return CoinConfig
```

- [ ] **Step 4: Write `CoinCurve.luau`**

```lua
-- CoinCurve.luau
--
-- Bonding-curve math. Pure functions of the cash pool V and token pool T;
-- callers own the state. Every buy and sell takes a 1% fee out of the game.

local CoinConfig = require(script.Parent.CoinConfig)

local CoinCurve = {}

local V0 = CoinConfig.VIRTUAL_CASH
local T0 = CoinConfig.VIRTUAL_TOKENS
local K = V0 * T0
local SUPPLY = CoinConfig.TOTAL_SUPPLY
local FEE_RATE = CoinConfig.FEE_RATE

CoinCurve.K = K

function CoinCurve.price(V, T)
	return V / T
end

function CoinCurve.marketCap(V, T)
	return V / T * SUPPLY
end

function CoinCurve.progress(V)
	return math.clamp((V - V0) / CoinConfig.GRADUATION_CASH, 0, 1)
end

function CoinCurve.tokensSold(T)
	return T0 - T
end

function CoinCurve.quoteBuy(V, T, dollars)
	local fee = dollars * FEE_RATE
	local cashIn = dollars - fee
	local newV = V + cashIn
	-- Floored, so the curve keeps the fraction and V * T never drops below K
	local tokensOut = math.floor(T - K / newV)

	if tokensOut < 1 then
		return nil, "Amount too small."
	end

	local newT = T - tokensOut

	if T0 - newT > SUPPLY then
		return nil, "Sold out."
	end

	return { tokensOut = tokensOut, fee = fee, cashIn = cashIn, newV = newV, newT = newT }
end

function CoinCurve.quoteSell(V, T, tokens)
	local newT = T + tokens

	-- The floor: if a restore ever lost recent trades, this stops the curve
	-- paying out cash that never went in
	if newT > T0 then
		return nil, "Can't sell that many tokens right now."
	end

	local newV = K / newT
	local gross = V - newV

	if gross <= 0 then
		return nil, "Amount too small."
	end

	local fee = gross * FEE_RATE
	local payout = math.floor((gross - fee) * 100) / 100

	return { payout = payout, fee = fee, gross = gross, newV = newV, newT = newT }
end

return CoinCurve
```

- [ ] **Step 5: Write `CoinRules.luau`**

```lua
-- CoinRules.luau
--
-- Name and ticker rules for launching a coin. The client checks these for
-- instant feedback; the server checks them again as the authority.

local CoinConfig = require(script.Parent.CoinConfig)

local CoinRules = {}

-- Nothing longer can be valid; rejecting it first keeps a huge string from
-- a client out of the pattern matching
local MAX_RAW_LENGTH = 200

local NAME_LENGTH_MESSAGE = string.format("Name must be %d-%d characters.", CoinConfig.NAME_MIN, CoinConfig.NAME_MAX)
local NAME_CHARSET_MESSAGE = "Name can use letters, numbers, spaces and . , ' ! ? - _ &"
local TICKER_MESSAGE = string.format("Ticker must be %d-%d letters or numbers.", CoinConfig.TICKER_MIN, CoinConfig.TICKER_MAX)

function CoinRules.validateName(name)
	if typeof(name) ~= "string" then
		return nil, "Enter a name."
	end

	if #name > MAX_RAW_LENGTH then
		return nil, NAME_LENGTH_MESSAGE
	end

	local cleaned = string.gsub(name, "%s+", " ")
	cleaned = string.match(cleaned, "^ ?(.-) ?$")

	if cleaned == "" then
		return nil, "Enter a name."
	end

	if string.find(cleaned, "[^%w %.,'!%?%-_&]") then
		return nil, NAME_CHARSET_MESSAGE
	end

	if #cleaned < CoinConfig.NAME_MIN or #cleaned > CoinConfig.NAME_MAX then
		return nil, NAME_LENGTH_MESSAGE
	end

	return cleaned
end

function CoinRules.validateTicker(ticker)
	if typeof(ticker) ~= "string" then
		return nil, "Enter a ticker."
	end

	if #ticker > MAX_RAW_LENGTH then
		return nil, TICKER_MESSAGE
	end

	-- "$pepe" and " pepe " both mean PEPE
	local cleaned = string.upper(string.match(ticker, "^%s*%$?(.-)%s*$"))

	if cleaned == "" then
		return nil, "Enter a ticker."
	end

	if not string.match(cleaned, "^%w+$") or #cleaned < CoinConfig.TICKER_MIN or #cleaned > CoinConfig.TICKER_MAX then
		return nil, TICKER_MESSAGE
	end

	return cleaned
end

return CoinRules
```

- [ ] **Step 6: Write `CoinFormat.luau`**

```lua
-- CoinFormat.luau
--
-- Display strings for coins: abbreviated token counts, short ages, prices
-- small enough to need extra decimals, and preset button labels.

local CoinFormat = {}

-- Largest first. A count that would round to "1000.0" of one unit shows as
-- 1 of the next unit up instead
local TOKEN_UNITS = {
	{ size = 1e9, suffix = "B", format = "%.2f" },
	{ size = 1e6, suffix = "M", format = "%.1f" },
	{ size = 1e3, suffix = "K", format = "%.1f" },
}
local ROUND_UP_FACTOR = 0.99995

function CoinFormat.tokens(count)
	for _, unit in ipairs(TOKEN_UNITS) do
		if count >= unit.size * ROUND_UP_FACTOR then
			return string.format(unit.format, count / unit.size) .. unit.suffix
		end
	end

	return tostring(math.floor(count))
end

function CoinFormat.age(seconds)
	-- Another server's clock can run ahead of this one
	seconds = math.max(math.floor(seconds), 0)

	if seconds < 60 then
		return seconds .. "s"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. "h"
	end

	return math.floor(seconds / 86400) .. "d"
end

function CoinFormat.price(price)
	if price <= 0 then
		return "$0.00"
	elseif price >= 1 then
		return string.format("$%.2f", price)
	end

	-- Three significant digits, so a launch price reads $0.00000280, not $0.00
	local decimals = math.max(2, -math.floor(math.log10(price)) + 2)

	return string.format("$%." .. decimals .. "f", price)
end

function CoinFormat.preset(dollars)
	if dollars >= 1000 then
		return "$" .. math.floor(dollars / 1000) .. "K"
	end

	return "$" .. dollars
end

return CoinFormat
```

- [ ] **Step 7: Run the test and confirm it passes**

Confirm Rojo synced the folder: `return #game.ReplicatedStorage.Modules.Coins:GetChildren()` should return `4`. Then re-run Step 1.

Expected: `55/55 passed`.

- [ ] **Step 8: Commit and record**

```bash
git add src/shared/Modules/Coins/CoinConfig.luau src/shared/Modules/Coins/CoinCurve.luau src/shared/Modules/Coins/CoinRules.luau src/shared/Modules/Coins/CoinFormat.luau
git commit -m "Coins: config, curve math, name and ticker rules, formatting" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
printf '%s\n' "Task 1: 55/55 Edit checks PASS" > "$WS/task-1-studio.txt"
$S/executing-plans/scripts/task-done $PLAN 1 <BASE> -- grep -q 'PASS$' "$WS/task-1-studio.txt"
```

---
### Task 2: Coin state transitions and Pulse columns

**Files:**
- Create: `src/shared/Modules/Coins/CoinState.luau`, `src/shared/Modules/Coins/PulseColumns.luau`
- Test: Edit-mode `execute_luau` (below)

**Interfaces:**
- Consumes (Task 1): `CoinConfig` constants; `CoinCurve.marketCap`, `progress`, `price`, `quoteBuy`, `quoteSell`.
- Produces (in `ReplicatedStorage.Modules.Coins`):
  - **The coin state table.** Every store keeps it and every server shares it:
    - `{ id, name, ticker, creatorId, creatorName, createdAt, V, T, volume, trades, lastTradeAt, creatorTokens, graduated, graduatedAt, points, pointsMinute }`;
    - `points` holds whole-dollar market caps, oldest first, at most 60;
    - `pointsMinute` is `floor(time / 60)` of the last point.
  - **`CoinState` functions:**
    - `new({ id, name, ticker, creatorId, creatorName, now }) -> state`.
    - `applyBuy(state, dollars, userId, now) -> newState, { tokensOut, fee, graduatedNow }`, or `nil, message`.
    - `applySell(state, tokens, userId, now) -> newState, { payout, fee }`, or `nil, message`.
    - `summary(state) -> { id, name, ticker, creatorName, createdAt, marketCap, volume, trades, progress, graduated, graduatedAt }`.
    - `detail(state) -> summary + { price, creatorShare, points, pointsMinute }`.
    - `pointsAsOf(points, pointsMinute, now) -> points`.
  - **`PulseColumns`:** `build(summaries) -> { New = {...}, AboutToGraduate = {...}, Graduated = {...} }`. Each column is sorted and holds at most 20.

- [ ] **Step 1: Write the failing test** (Edit datamodel)

Start with the **H7** header and checker, then:

```lua
local CoinCurve = require(Coins.CoinCurve)
local CoinState = require(Coins.CoinState)
local PulseColumns = require(Coins.PulseColumns)

local NOW = 1700000000 -- minute 28333333, 20 s in
local T0 = 1073000000
local function capPoint(state)
	return math.floor(CoinCurve.marketCap(state.V, state.T) + 0.5)
end

local base = CoinState.new({ id = "c1", name = "Pepe Coin", ticker = "PEPE", creatorId = 7, creatorName = "Kevin", now = NOW })
check("new V", base.V, 3000)
check("new T", base.T, T0)
check("new trades", base.trades, 0)
check("new point", #base.points == 1 and base.points[1], 2796)
check("new pointsMinute", base.pointsMinute, 28333333)

-- Trades return a new state and leave the old one alone
local bought, info = CoinState.applyBuy(base, 250, 2, NOW + 10)
check("buy tokens", info and info.tokensOut, 81775981)
check("buy trades", bought.trades, 1)
check("buy volume", bought.volume, 250)
check("old state untouched", base.trades == 0 and #base.points == 1 and base.V == 3000, true)
check("same-minute trade overwrites the point", #bought.points == 1 and bought.points[1], capPoint(bought))
check("non-creator buy", bought.creatorTokens, 0)

-- Creator holdings, shown as the creator's share of supply
local creatorBuy, creatorInfo = CoinState.applyBuy(base, 100, 7, NOW)
check("creator buy tracked", creatorBuy.creatorTokens, creatorInfo.tokensOut)
local half = math.floor(creatorInfo.tokensOut / 2)
check("creator sell tracked", CoinState.applySell(creatorBuy, half, 7, NOW).creatorTokens, creatorInfo.tokensOut - half)

-- Price points: one per minute, gaps carry the last value, at most 60
local s = CoinState.applyBuy(bought, 10, 2, NOW + 60)
check("next minute appends", #s.points, 2)
s = CoinState.applyBuy(s, 10, 2, NOW + 300) -- three empty minutes in between
check("gap filled", #s.points, 6)
check("gap carries last value", s.points[3] == s.points[2] and s.points[5] == s.points[2], true)
s = CoinState.applyBuy(s, 10, 2, NOW + 7200)
check("capped at 60", #s.points, 60)

-- A server whose clock runs behind can't move points or lastTradeAt backwards
local skewed = CoinState.applyBuy(s, 10, 2, NOW + 7000)
check("skew keeps pointsMinute", skewed.pointsMinute, s.pointsMinute)
check("skew keeps point count", #skewed.points, 60)
check("skew keeps lastTradeAt", skewed.lastTradeAt, NOW + 7200)
check("skew updates the last point", skewed.points[60], capPoint(skewed))

-- Graduation happens once and sticks
local grad, gradInfo = CoinState.applyBuy(base, 8600, 2, NOW)
check("graduates", grad.graduated and gradInfo.graduatedNow and grad.graduatedAt == NOW, true)
local after, afterInfo = CoinState.applyBuy(grad, 100, 3, NOW + 5)
check("graduates once", afterInfo.graduatedNow, false)
local dumped = CoinState.applySell(after, gradInfo.tokensOut, 2, NOW + 10)
check("stays graduated after a dump", dumped.graduated and CoinCurve.progress(dumped.V) < 1, true)

local nope, nopeErr = CoinState.applyBuy(base, 1e9, 2, NOW)
check("sold out refused", nope == nil and nopeErr == "Sold out.", true)

local sold, sellInfo = CoinState.applySell(bought, 1000000, 2, NOW + 20)
check("sell volume adds gross", sold.volume, bought.volume + (bought.V - sold.V), 1e-6)
check("sell pays out", sellInfo.payout > 0, true)

local summary = CoinState.summary(bought)
check("summary cap", summary.marketCap, CoinCurve.marketCap(bought.V, bought.T), 1e-6)
check("summary progress", summary.progress, CoinCurve.progress(bought.V), 1e-9)
local detail = CoinState.detail(creatorBuy)
check("detail price", detail.price, creatorBuy.V / creatorBuy.T, 1e-15)
check("detail creatorShare", detail.creatorShare, creatorInfo.tokensOut / 1e9, 1e-12)
table.insert(detail.points, 1)
check("detail points are a copy", #creatorBuy.points, 1)

check("pointsAsOf pads to now", (function()
	local padded = CoinState.pointsAsOf({ 5 }, 100, 100 * 60 + 3 * 60)
	return #padded == 4 and padded[4] == 5
end)(), true)
check("pointsAsOf ignores an earlier now", #CoinState.pointsAsOf({ 5, 6 }, 100, 99 * 60), 2)
check("pointsAsOf caps at 60", #CoinState.pointsAsOf({ 5 }, 100, 600 * 60), 60)

-- Columns
local function row(id, createdAt, progress, graduated, graduatedAt)
	return { id = id, createdAt = createdAt, progress = progress, graduated = graduated, graduatedAt = graduatedAt or 0 }
end
local function ids(list)
	local out = {}
	for _, item in ipairs(list) do
		table.insert(out, item.id)
	end
	return table.concat(out, ",")
end
local columns = PulseColumns.build({
	row("a", 10, 0.49, false),
	row("b", 30, 0.2, false),
	row("c", 20, 0.5, false),
	row("d", 5, 0.9, false),
	row("e", 1, 0.2, true, 50),
	row("f", 2, 1, true, 80),
	row("g", 30, 0.1, false),
})
check("New: newest first, ties by id", ids(columns.New), "b,g,a")
check("About: highest progress first", ids(columns.AboutToGraduate), "d,c")
check("Graduated: most recent first", ids(columns.Graduated), "f,e")
local many = {}
for i = 1, 25 do
	table.insert(many, row("n" .. i, i, 0, false))
end
check("columns hold 20", #PulseColumns.build(many).New, 20)
local empty = PulseColumns.build({})
check("empty columns", #empty.New + #empty.AboutToGraduate + #empty.Graduated, 0)

holder:Destroy()
return report()
```

- [ ] **Step 2: Run it and confirm it fails**

Expected: an error, `CoinState is not a valid member of Folder "TEST_Fresh.Coins"`. (Destroy `ServerStorage.TEST_Fresh` by hand after an error.)

- [ ] **Step 3: Write `CoinState.luau`**

```lua
-- CoinState.luau
--
-- A coin's full state and the pure transitions on it. Trades return a new
-- table instead of mutating: the memory store may run a transform more than
-- once, and each run must start from the stored value it was given.

local CoinConfig = require(script.Parent.CoinConfig)
local CoinCurve = require(script.Parent.CoinCurve)

local CoinState = {}

local function minuteOf(now)
	return math.floor(now / 60)
end

local function copy(state)
	local new = table.clone(state)
	new.points = table.clone(state.points)

	return new
end

local function trimPoints(points)
	while #points > CoinConfig.PRICE_POINTS do
		table.remove(points, 1)
	end
end

-- One market-cap point per minute, in whole dollars to keep a coin small in
-- the memory store. A trade overwrites the current minute's point; minutes
-- nobody traded in repeat the last value. A server whose clock runs behind
-- writes into the latest point rather than going back in time
local function recordPoint(state, now)
	local cap = math.floor(CoinCurve.marketCap(state.V, state.T) + 0.5)
	local minute = minuteOf(now)
	local points = state.points

	if #points > 0 and minute <= state.pointsMinute then
		points[#points] = cap
		return
	end

	local last = points[#points]

	if last then
		for _ = 1, math.min(minute - state.pointsMinute - 1, CoinConfig.PRICE_POINTS) do
			table.insert(points, last)
		end
	end

	table.insert(points, cap)
	state.pointsMinute = minute
	trimPoints(points)
end

function CoinState.new(args)
	local state = {
		id = args.id,
		name = args.name,
		ticker = args.ticker,
		creatorId = args.creatorId,
		creatorName = args.creatorName,
		createdAt = args.now,
		V = CoinConfig.VIRTUAL_CASH,
		T = CoinConfig.VIRTUAL_TOKENS,
		volume = 0,
		trades = 0,
		lastTradeAt = args.now,
		creatorTokens = 0,
		graduated = false,
		graduatedAt = 0,
		points = {},
		pointsMinute = minuteOf(args.now),
	}

	table.insert(state.points, math.floor(CoinCurve.marketCap(state.V, state.T) + 0.5))

	return state
end

function CoinState.applyBuy(state, dollars, userId, now)
	local quote, message = CoinCurve.quoteBuy(state.V, state.T, dollars)

	if not quote then
		return nil, message
	end

	local new = copy(state)
	new.V = quote.newV
	new.T = quote.newT
	new.volume += dollars
	new.trades += 1
	new.lastTradeAt = math.max(new.lastTradeAt, now)

	if userId == new.creatorId then
		new.creatorTokens += quote.tokensOut
	end

	-- Graduation is permanent: a coin that later dumps keeps its badge
	local graduatedNow = false

	if not new.graduated and CoinCurve.progress(new.V) >= 1 then
		new.graduated = true
		new.graduatedAt = now
		graduatedNow = true
	end

	recordPoint(new, now)

	return new, { tokensOut = quote.tokensOut, fee = quote.fee, graduatedNow = graduatedNow }
end

function CoinState.applySell(state, tokens, userId, now)
	local quote, message = CoinCurve.quoteSell(state.V, state.T, tokens)

	if not quote then
		return nil, message
	end

	local new = copy(state)
	new.V = quote.newV
	new.T = quote.newT
	new.volume += quote.gross
	new.trades += 1
	new.lastTradeAt = math.max(new.lastTradeAt, now)

	if userId == new.creatorId then
		new.creatorTokens = math.max(0, new.creatorTokens - tokens)
	end

	recordPoint(new, now)

	return new, { payout = quote.payout, fee = quote.fee }
end

function CoinState.summary(state)
	return {
		id = state.id,
		name = state.name,
		ticker = state.ticker,
		creatorName = state.creatorName,
		createdAt = state.createdAt,
		marketCap = CoinCurve.marketCap(state.V, state.T),
		volume = state.volume,
		trades = state.trades,
		progress = CoinCurve.progress(state.V),
		graduated = state.graduated,
		graduatedAt = state.graduatedAt,
	}
end

function CoinState.detail(state)
	local detail = CoinState.summary(state)
	detail.price = CoinCurve.price(state.V, state.T)
	detail.creatorShare = state.creatorTokens / CoinConfig.TOTAL_SUPPLY
	detail.points = table.clone(state.points)
	detail.pointsMinute = state.pointsMinute

	return detail
end

-- The points to draw at `now`: minutes since the last trade repeat its value
function CoinState.pointsAsOf(points, pointsMinute, now)
	local result = table.clone(points)
	local last = result[#result]

	if last then
		for _ = 1, math.min(minuteOf(now) - pointsMinute, CoinConfig.PRICE_POINTS) do
			table.insert(result, last)
		end
	end

	trimPoints(result)

	return result
end

return CoinState
```

- [ ] **Step 4: Write `PulseColumns.luau`**

```lua
-- PulseColumns.luau
--
-- Splits coin summaries into Pulse's three columns and sorts each. Ties
-- break by id so every server and client orders cards the same way.

local CoinConfig = require(script.Parent.CoinConfig)

local PulseColumns = {}

local function descendingBy(field)
	return function(a, b)
		if a[field] ~= b[field] then
			return a[field] > b[field]
		end

		return a.id < b.id
	end
end

function PulseColumns.build(summaries)
	local columns = { New = {}, AboutToGraduate = {}, Graduated = {} }

	for _, summary in ipairs(summaries) do
		if summary.graduated then
			table.insert(columns.Graduated, summary)
		elseif summary.progress >= CoinConfig.ABOUT_TO_GRADUATE_PROGRESS then
			table.insert(columns.AboutToGraduate, summary)
		else
			table.insert(columns.New, summary)
		end
	end

	table.sort(columns.New, descendingBy("createdAt"))
	table.sort(columns.AboutToGraduate, descendingBy("progress"))
	table.sort(columns.Graduated, descendingBy("graduatedAt"))

	for _, list in pairs(columns) do
		while #list > CoinConfig.COLUMN_SIZE do
			table.remove(list)
		end
	end

	return columns
end

return PulseColumns
```

- [ ] **Step 5: Run the test and confirm it passes**

Expected: `40/40 passed`. Re-run Task 1's test too, and expect `55/55 passed`.

- [ ] **Step 6: Commit and record**

```bash
git add src/shared/Modules/Coins/CoinState.luau src/shared/Modules/Coins/PulseColumns.luau
git commit -m "Coins: immutable state transitions, price points, Pulse columns" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
printf '%s\n' "Task 2: 40/40 Edit checks, Task 1 still 55/55 PASS" > "$WS/task-2-studio.txt"
$S/executing-plans/scripts/task-done $PLAN 2 <BASE> -- grep -q 'PASS$' "$WS/task-2-studio.txt"
```

---
### Task 3: Coin store and payout mailbox

**Files:**
- Create: `src/server/Modules/CoinStore.luau`, `src/server/Modules/PayoutMailbox.luau`
- Test: Play-mode `execute_luau` on the Server datamodel, against the `_studio_test` stores (below)

**Interfaces:**
- Consumes (Tasks 1–2): `CoinConfig.ARCHIVE_AFTER`; `CoinState.applyBuy`, `applySell`, and the state table shape.
- Produces (in `ServerScriptService.Modules`):
  - **`CoinStore`:**
    - `configure(suffix)`.
    - `read(id) -> state, "live" | "archived"`, or `nil, "missing" | "unavailable"`.
    - `buy(id, dollars, userId, now)` and `sell(id, tokens, userId, now)`: each returns `newState, info` (as `CoinState.applyBuy`/`applySell` return), or `nil, message`. The message is `"Coin not found."`, `"Coins unavailable, try again."`, or the curve's own message.
    - `create(state) -> boolean`.
    - `backup(state) -> boolean`.
    - `listLive() -> { state }`, or `nil` when unavailable.
    - `archiveIdle(states, now) -> count`.
    - `claimTicker(ticker, coinId) -> true | false | nil` (nil means unavailable).
    - `releaseTicker(ticker, coinId)`.
  - **`PayoutMailbox`:**
    - `configure(suffix)`.
    - `add(userId, { id, amount, reason, coinId }) -> boolean`.
    - `claim(userId) -> { payout }` (possibly empty), or `nil`.

- [ ] **Step 1: Write the failing store test** (Server datamodel, during Play)

DataStore writes to the same key are paced by Roblox, so this can take 30–60 s. That's expected.

```lua
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ServerScriptService = game:GetService("ServerScriptService")
local CoinState = require(game:GetService("ReplicatedStorage").Modules.Coins.CoinState)
local CoinStore = require(ServerScriptService.Modules.CoinStore)
CoinStore.configure("_studio_test")

-- (H7's checker: total, failures, check, report)

local T0 = 1073000000
local now = os.time()
local run = tostring(math.random(100000, 999999))
local function newCoin(tag)
	return CoinState.new({ id = "test" .. run .. tag, name = "Test " .. tag, ticker = "T" .. tag, creatorId = 7, creatorName = "Tester", now = now })
end

-- Create, read, trade
local coin = newCoin("a")
check("create", CoinStore.create(coin), true)
local read, where = CoinStore.read(coin.id)
check("read live", where, "live")
check("read state", read and read.T, T0)
local bought, info = CoinStore.buy(coin.id, 250, 2, now)
check("buy tokens", bought and info.tokensOut, 81775981)
check("buy stored", bought and bought.trades, 1)
local sold, sellInfo = CoinStore.sell(coin.id, 81775981, 2, now)
check("sell payout", sold and sellInfo.payout, 245.02)
check("sell stored", sold and sold.T, T0)
check("missing coin", select(2, CoinStore.buy("test" .. run .. "nope", 10, 2, now)), "Coin not found.")
check("curve message passes through", select(2, CoinStore.buy(coin.id, 0.000001, 2, now)), "Amount too small.")
local found = false
for _, state in ipairs(CoinStore.listLive() or {}) do
	if state.id == coin.id then
		found = true
	end
end
check("listed", found, true)

-- Backups keep the copy that has seen more trades
local newer = table.clone(sold)
newer.trades = 5
check("backup newer", CoinStore.backup(newer), true)
local older = table.clone(sold)
older.trades = 3
check("backup older is a no-op", CoinStore.backup(older), true)
local durable = DataStoreService:GetDataStore("Coins_v1_studio_test")
check("durable keeps 5 trades", durable:GetAsync(coin.id).trades, 5)

-- Archiving: only coins idle past ARCHIVE_AFTER (the "aged 25 hours" hook
-- is the `now` argument), and a trade brings them back
check("recent coin not archived", CoinStore.archiveIdle({ sold }, now + 60), 0)
check("idle coin archived", CoinStore.archiveIdle({ sold }, now + 25 * 3600), 1)
check("archived read", select(2, CoinStore.read(coin.id)), "archived")
local revived = CoinStore.buy(coin.id, 100, 2, now)
check("trade revives", revived ~= nil and select(2, CoinStore.read(coin.id)) == "live", true)

-- Tickers are unique
local ticker = "TK" .. string.sub(run, 1, 4)
check("claim new ticker", CoinStore.claimTicker(ticker, "id1"), true)
check("claim again same coin", CoinStore.claimTicker(ticker, "id1"), true)
check("ticker taken", CoinStore.claimTicker(ticker, "id2"), false)
CoinStore.releaseTicker(ticker, "id2")
check("release by another coin does nothing", CoinStore.claimTicker(ticker, "id2"), false)
CoinStore.releaseTicker(ticker, "id1")
check("release frees it", CoinStore.claimTicker(ticker, "id2"), true)

-- 20 buys at once, as from many servers: each is applied exactly once
local hot = newCoin("hot")
CoinStore.create(hot)
local received, successes, done = 0, 0, 0
for i = 1, 20 do
	task.spawn(function()
		local state, buyInfo = CoinStore.buy(hot.id, 50, 100 + i, now)
		if state then
			received += buyInfo.tokensOut
			successes += 1
		end
		done += 1
	end)
end
local deadline = os.clock() + 30
while done < 20 and os.clock() < deadline do
	task.wait(0.1)
end
local final = CoinStore.read(hot.id)
check("all 20 succeeded", successes, 20)
check("tokens received == tokens sold", received, T0 - final.T)
check("cash pool == V0 + net cash in", final.V - 3000, 49.5 * successes, 1e-6)
check("trade count", final.trades, successes)

-- Clean up everything this run wrote
local liveMap = MemoryStoreService:GetHashMap("Coins_studio_test")
local tickers = DataStoreService:GetDataStore("CoinTickers_v1_studio_test")
for _, id in ipairs({ coin.id, hot.id }) do
	pcall(liveMap.RemoveAsync, liveMap, id)
	pcall(durable.RemoveAsync, durable, id)
end
pcall(tickers.RemoveAsync, tickers, ticker)

return report()
```

- [ ] **Step 2: Write the failing mailbox test** (Server datamodel, during Play)

Each scenario uses its own user key, so per-key write pacing stays short.

```lua
local DataStoreService = game:GetService("DataStoreService")
local PayoutMailbox = require(game:GetService("ServerScriptService").Modules.PayoutMailbox)
PayoutMailbox.configure("_studio_test")

-- (H7's checker: total, failures, check, report)

local run = tostring(math.random(100000, 999999))
local base = 900000000 + math.random(1, 99999) * 10
local userA, userB, userC = base + 1, base + 2, base + 3
local payout = { id = "test" .. run .. ":graduation", amount = 2500, reason = "graduation", coinId = "x" }

-- Adding the same payout twice leaves one; claiming takes it once
check("add payout", PayoutMailbox.add(userA, payout), true)
check("add same id again", PayoutMailbox.add(userA, payout), true)
local claimed = PayoutMailbox.claim(userA)
check("claimed once", claimed and #claimed == 1 and claimed[1].amount, 2500)
local again = PayoutMailbox.claim(userA)
check("second claim empty", again and #again, 0)

-- A paid id can't be added again
PayoutMailbox.add(userB, payout)
PayoutMailbox.claim(userB)
PayoutMailbox.add(userB, payout)
local afterPaid = PayoutMailbox.claim(userB)
check("a paid id can't come back", afterPaid and #afterPaid, 0)

-- Two collections racing pay exactly once
PayoutMailbox.add(userC, { id = "test" .. run .. ":race", amount = 123, reason = "test", coinId = "x" })
local raceTotal, raceDone = 0, 0
for _ = 1, 2 do
	task.spawn(function()
		for _, item in ipairs(PayoutMailbox.claim(userC) or {}) do
			raceTotal += item.amount
		end
		raceDone += 1
	end)
end
local deadline = os.clock() + 30
while raceDone < 2 and os.clock() < deadline do
	task.wait(0.1)
end
check("race pays once", raceTotal, 123)

local mailbox = DataStoreService:GetDataStore("Payouts_v1_studio_test")
for _, user in ipairs({ userA, userB, userC }) do
	pcall(mailbox.RemoveAsync, mailbox, tostring(user))
end

return report()
```

- [ ] **Step 3: Run both and confirm they fail**

Run `start_stop_play(true)`, wait about 5 s, then run Step 1 and Step 2.

Expected: errors `CoinStore is not a valid member of Folder "ServerScriptService.Modules"` and `PayoutMailbox is not a valid member of …`. Run `start_stop_play(false)`.

- [ ] **Step 4: Write `CoinStore.luau`**

If Task 0 ledgered a different maximum expiration, use it for `EXPIRATION`.

```lua
-- CoinStore.luau
--
-- Where coins live. Live state is a MemoryStore hash map: every trade is
-- one atomic UpdateAsync on the coin's key, so servers never overwrite each
-- other's trades. A DataStore keeps a durable copy of each coin (written at
-- launch, at graduation, every few minutes while it trades, and at
-- archive), and a second DataStore makes tickers unique forever.

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CoinConfig = require(ReplicatedStorage.Modules.Coins.CoinConfig)
local CoinState = require(ReplicatedStorage.Modules.Coins.CoinState)

local CoinStore = {}

local EXPIRATION = 3888000 -- 45 days, the memory-store maximum; archiving removes idle coins long before
local ATTEMPTS = 3
local LIST_PAGE_SIZE = 100

local liveMap, durable, tickers

-- Tests point the store at their own names
function CoinStore.configure(suffix)
	liveMap = MemoryStoreService:GetHashMap("Coins" .. suffix)
	durable = DataStoreService:GetDataStore("Coins_v1" .. suffix)
	tickers = DataStoreService:GetDataStore("CoinTickers_v1" .. suffix)
end

-- Playtests must never put coins into the live game's Pulse
CoinStore.configure(RunService:IsStudio() and "_studio" or "")

-- For reads and repeatable writes only. A trade is never retried: if its
-- update committed but the reply was lost, a retry would apply it twice
local function retry(label, action)
	for attempt = 1, ATTEMPTS do
		local ok, a, b = pcall(action)

		if ok then
			return true, a, b
		end

		warn(string.format("[CoinStore] %s failed (attempt %d): %s", label, attempt, tostring(a)))

		if attempt < ATTEMPTS then
			task.wait(0.25 * attempt)
		end
	end

	return false
end

function CoinStore.read(id)
	local ok, state = retry("read " .. id, function()
		return liveMap:GetAsync(id)
	end)

	if not ok then
		return nil, "unavailable"
	end

	if state then
		return state, "live"
	end

	local savedOk, saved = retry("read durable " .. id, function()
		return durable:GetAsync(id)
	end)

	if not savedOk then
		return nil, "unavailable"
	end

	if saved then
		return saved, "archived"
	end

	return nil, "missing"
end

-- Keeps whichever copy has seen more trades, so a slow or repeated write
-- can't roll a coin back
function CoinStore.backup(state)
	return (retry("backup " .. state.id, function()
		durable:UpdateAsync(state.id, function(old)
			if old and old.trades > state.trades then
				return nil
			end

			return state
		end)
	end))
end

-- Puts an archived (or dropped) coin back into the memory store from its
-- durable copy, unless another server already has
local function restore(id)
	local ok, saved = retry("restore read " .. id, function()
		return durable:GetAsync(id)
	end)

	if not ok then
		return false, "Coins unavailable, try again."
	end

	if not saved then
		return false, "Coin not found."
	end

	local restored = retry("restore " .. id, function()
		liveMap:UpdateAsync(id, function(old)
			if old then
				return nil
			end

			return saved
		end, EXPIRATION)
	end)

	if not restored then
		return false, "Coins unavailable, try again."
	end

	return true
end

-- One atomic update on a live coin. `apply(old)` returns a new state and an
-- info table, or nil and a player-facing message
local function trade(id, apply)
	local failure, info

	local function transform(old)
		-- The store can call this more than once; only the last call counts
		failure, info = nil, nil

		if not old then
			failure = "missing"
			return nil
		end

		local new, result = apply(old)

		if not new then
			failure = result
			return nil
		end

		info = result

		return new
	end

	local function attempt()
		return pcall(function()
			return liveMap:UpdateAsync(id, transform, EXPIRATION)
		end)
	end

	local ok, state = attempt()

	if ok and failure == "missing" then
		local restored, message = restore(id)

		if not restored then
			return nil, message
		end

		ok, state = attempt()
	end

	if not ok then
		warn("[CoinStore] trade on " .. id .. " failed: " .. tostring(state))
		return nil, "Coins unavailable, try again."
	end

	if failure == "missing" then
		return nil, "Coin not found."
	end

	if failure then
		return nil, failure
	end

	return state, info
end

function CoinStore.buy(id, dollars, userId, now)
	return trade(id, function(old)
		return CoinState.applyBuy(old, dollars, userId, now)
	end)
end

function CoinStore.sell(id, tokens, userId, now)
	return trade(id, function(old)
		return CoinState.applySell(old, tokens, userId, now)
	end)
end

-- Durable copy first: a coin that existed only in memory could be lost
function CoinStore.create(state)
	if not CoinStore.backup(state) then
		return false
	end

	local ok = retry("create " .. state.id, function()
		liveMap:SetAsync(state.id, state, EXPIRATION)
	end)

	if not ok then
		pcall(function()
			durable:RemoveAsync(state.id)
		end)
	end

	return ok
end

function CoinStore.listLive()
	local states = {}

	local ok = retry("list", function()
		table.clear(states)

		local pages = liveMap:ListItemsAsync(LIST_PAGE_SIZE)

		while true do
			for _, item in ipairs(pages:GetCurrentPage()) do
				table.insert(states, item.value)
			end

			if pages.IsFinished then
				break
			end

			pages:AdvanceToNextPageAsync()
		end
	end)

	return ok and states or nil
end

-- Moves coins nobody has traded for ARCHIVE_AFTER seconds out of the memory
-- store, after saving their durable copy. Holders keep their tokens and see
-- the coin under My coins; the next trade restores it. Returns how many
-- were archived
function CoinStore.archiveIdle(states, now)
	local archived = 0

	for _, listed in ipairs(states) do
		if now - listed.lastTradeAt >= CoinConfig.ARCHIVE_AFTER then
			-- Re-read: another server may have traded it since the listing
			local ok, state = retry("archive read " .. listed.id, function()
				return liveMap:GetAsync(listed.id)
			end)

			if ok and state and now - state.lastTradeAt >= CoinConfig.ARCHIVE_AFTER and CoinStore.backup(state) then
				local removed = retry("archive " .. state.id, function()
					liveMap:RemoveAsync(state.id)
				end)

				if removed then
					archived += 1
				end
			end
		end
	end

	return archived
end

-- True when this coin now owns the ticker, false when another coin does,
-- nil when the store couldn't be reached
function CoinStore.claimTicker(ticker, coinId)
	local owner

	local ok = retry("claim " .. ticker, function()
		tickers:UpdateAsync(ticker, function(old)
			owner = old or coinId

			if old then
				return nil
			end

			return coinId
		end)
	end)

	if not ok then
		return nil
	end

	return owner == coinId
end

-- Gives a ticker back after a launch failed past the claim
function CoinStore.releaseTicker(ticker, coinId)
	retry("release " .. ticker, function()
		if tickers:GetAsync(ticker) == coinId then
			tickers:RemoveAsync(ticker)
		end
	end)
end

return CoinStore
```

- [ ] **Step 5: Write `PayoutMailbox.luau`**

```lua
-- PayoutMailbox.luau
--
-- Pays a player exactly once, whether they're in this server, another one,
-- or offline. A payout goes into the player's DataStore mailbox with an id.
-- A server collects it with one atomic UpdateAsync that empties the pending
-- list and remembers the ids, so the same payout can't be added or paid
-- twice.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local PayoutMailbox = {}

local ATTEMPTS = 3

local mailbox

function PayoutMailbox.configure(suffix)
	mailbox = DataStoreService:GetDataStore("Payouts_v1" .. suffix)
end

PayoutMailbox.configure(RunService:IsStudio() and "_studio" or "")

local function isKnown(box, id)
	if box.paidIds[id] then
		return true
	end

	for _, payout in ipairs(box.pending) do
		if payout.id == id then
			return true
		end
	end

	return false
end

-- payout = { id, amount, reason, coinId }. Retrying is safe: the id makes a
-- repeated add a no-op
function PayoutMailbox.add(userId, payout)
	for attempt = 1, ATTEMPTS do
		local ok, err = pcall(function()
			mailbox:UpdateAsync(tostring(userId), function(old)
				local box = old or { pending = {}, paidIds = {} }

				if isKnown(box, payout.id) then
					return nil
				end

				table.insert(box.pending, payout)

				return box
			end)
		end)

		if ok then
			return true
		end

		warn(string.format("[PayoutMailbox] add %s for %d failed (attempt %d): %s", payout.id, userId, attempt, tostring(err)))
		task.wait(attempt)
	end

	return false
end

-- Takes every pending payout: a list (possibly empty), or nil if the store
-- couldn't be reached. Not retried: if the claim committed but the reply was
-- lost, claiming again would find nothing, and paying from memory could pay
-- twice. Losing that payout is the safer failure
function PayoutMailbox.claim(userId)
	local claimed = {}

	local ok, err = pcall(function()
		mailbox:UpdateAsync(tostring(userId), function(old)
			claimed = {}

			if not old or #old.pending == 0 then
				return nil
			end

			claimed = old.pending

			for _, payout in ipairs(old.pending) do
				old.paidIds[payout.id] = true
			end

			old.pending = {}

			return old
		end)
	end)

	if not ok then
		warn("[PayoutMailbox] claim for " .. userId .. " failed: " .. tostring(err))
		return nil
	end

	return claimed
end

return PayoutMailbox
```

- [ ] **Step 6: Run both tests and confirm they pass**

Run `start_stop_play(true)`, wait about 5 s, then run Step 1 and Step 2.

Expected: `26/26 passed` and `6/6 passed`.

If `all 20 succeeded` fails but the other three concurrency checks pass, the store refused some updates under contention. That's acceptable only if `get_console_output` shows `[CoinStore] trade … failed` throttling warnings. Ledger the number that succeeded, because the players in those orders were refunded. Any failure of the other three checks is a bug.

Then run `start_stop_play(false)`. Nothing touched the save.

- [ ] **Step 7: Commit and record**

```bash
git add src/server/Modules/CoinStore.luau src/server/Modules/PayoutMailbox.luau
git commit -m "Coins: MemoryStore/DataStore coin store, exactly-once payout mailbox" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
printf '%s\n' "Task 3: store 26/26, mailbox 6/6 (Play, _studio_test) PASS" > "$WS/task-3-studio.txt"
$S/executing-plans/scripts/task-done $PLAN 3 <BASE> -- grep -q 'PASS$' "$WS/task-3-studio.txt"
```

---
### Task 4: Server wiring: CoinService, CoinSystem, remotes, saves, net worth

**Files:**
- Create: `src/server/Modules/CoinService.luau`, `src/server/Core/CoinSystem.server.luau`
- Modify:
  - `src/server/Core/ServerSetup.server.luau:3-16` (the `EVENTS` list);
  - `src/server/Core/Data_Manager.server.luau` (`createDefaultData`, `onPlayerAdded`, `onPlayerRemoving`);
  - `src/server/Modules/CalculatorModule.luau`.
- Test:
  - CoinService unit test in Edit mode with fakes;
  - Play integration through the real remotes (Client);
  - H5 checks;
  - a payout check.

**Interfaces:**
- Consumes:
  - Task 3: the `CoinStore` and `PayoutMailbox` functions, exactly as Task 3 lists them.
  - Tasks 1–2: `CoinRules`, `CoinFormat`, `CoinState.new`, `summary`, `detail`, `PulseColumns.build`, `CoinConfig.snapshotInterval`.
- Produces:
  - **Remotes in `ReplicatedStorage.EventsFolder`:**
    - `GetPulseEvent() -> { ok, updatedAt, serverTime, columns }`, or `nil` when throttled.
    - `GetCoinEvent(coinId) -> { success = true, coin = detail, serverTime }` or `{ success = false, message }`, or `nil` when throttled.
    - `GetMyCoinsEvent() -> { success = true, rows, serverTime }` or `{ success = false, message }`, or `nil` when throttled.
    - `CoinOrderEvent(action, coinId, amount) -> { success, message, coin? }`.
    - `LaunchCoinEvent(name, ticker) -> { success, message, coin? }`.
  - **Shapes:**
    - `detail` is `CoinState.detail` plus `name`/`ticker` (display-filtered), `position = { tokens, value, cost, pnl }`, and `archived` (boolean).
    - Each row is `CoinState.summary` plus display `name`/`ticker`, `position` and `archived`.
  - **`_G` hooks:**
    - `_G.WaitForCoinOrders(userId, timeoutSeconds)`;
    - `_G.LookupCoin(coinId) -> state, where`.
  - **Player data:** `Portfolio.Coins[coinId] = { tokens, cost }` and `CoinLaunches = { lastAt, ids }`.
  - **`CalculatorModule.coinValue(playerData) -> dollars`.**

- [ ] **Step 1: Write the failing CoinService unit test** (Edit datamodel)

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local holder = Instance.new("Folder")
holder.Name = "TEST_Fresh"
holder.Parent = ServerStorage
local serviceModule = game:GetService("ServerScriptService").Modules.CoinService:Clone()
serviceModule.Parent = holder
local CoinService = require(serviceModule)
local CoinState = require(ReplicatedStorage.Modules.Coins.CoinState)

-- (H7's checker: total, failures, check, report)

local NOW = 1700000000

-- A fake world: an in-memory store with switches to make calls fail
local function setup(balance)
	local world = { coins = {}, archived = {}, tickers = {}, failNext = {}, delay = 0, filterCalls = 0, traded = {}, launched = {} }
	local function failing(op)
		local mode = world.failNext[op]
		world.failNext[op] = nil
		if mode == "throw" then
			error("fake " .. op .. " exploded")
		end
		return mode ~= nil
	end
	local function trade(apply, id, ...)
		if world.delay > 0 then
			task.wait(world.delay)
		end
		local state = world.coins[id]
		if not state then
			return nil, "Coin not found."
		end
		local new, info = apply(state, ...)
		if new then
			world.coins[id] = new
		end
		return new, info
	end
	local store = {
		claimTicker = function(ticker, id)
			if failing("claim") then
				return nil
			end
			if world.tickers[ticker] and world.tickers[ticker] ~= id then
				return false
			end
			world.tickers[ticker] = id
			return true
		end,
		releaseTicker = function(ticker, id)
			if world.tickers[ticker] == id then
				world.tickers[ticker] = nil
			end
		end,
		create = function(state)
			if failing("create") then
				return false
			end
			world.coins[state.id] = state
			return true
		end,
		buy = function(id, ...)
			if failing("buy") then
				return nil, "Coins unavailable, try again."
			end
			return trade(CoinState.applyBuy, id, ...)
		end,
		sell = function(id, ...)
			if failing("sell") then
				return nil, "Coins unavailable, try again."
			end
			return trade(CoinState.applySell, id, ...)
		end,
	}
	local player = { UserId = 101, Name = "Tester" }
	local data = { Balance = balance or 10000, Portfolio = { Coins = {} }, CoinLaunches = { lastAt = 0, ids = {} } }
	local stats = { total = 0, byCreator = {} }
	local nextId = 0
	local service = CoinService.new({
		store = store,
		lookup = function(id)
			if world.coins[id] then
				return world.coins[id], world.archived[id] and "archived" or "live"
			end
			return nil, "missing"
		end,
		filter = function(text)
			world.filterCalls += 1
			if world.filterMode == "error" then
				return nil
			elseif world.filterMode == "hash" then
				return string.rep("#", #text)
			end
			return text
		end,
		displayNames = function(state)
			return state.name, state.ticker
		end,
		setBalance = function(_, balanceNow)
			data.Balance = balanceNow
		end,
		liveStats = function()
			return stats
		end,
		onTraded = function(_, _, info)
			table.insert(world.traded, info)
		end,
		onLaunched = function(_, state)
			table.insert(world.launched, state.id)
		end,
		now = function()
			return NOW
		end,
		newId = function()
			nextId += 1
			return "coin" .. nextId
		end,
	})
	return service, world, player, data, stats
end

-- Launching
local service, world, player, data, stats = setup()
check("bad name", service:launch(player, data, "P", "PEPE").message, "Name must be 2-24 characters.")
local launched = service:launch(player, data, "Pepe Coin", "$pepe")
check("launch succeeds", launched.success, true)
check("launch message", launched.message, "Launched $PEPE.")
check("launch fee charged", data.Balance, 9000)
check("launch recorded", data.CoinLaunches.lastAt == NOW and data.CoinLaunches.ids[1] == "coin1", true)
check("launch returns the panel", launched.coin and launched.coin.ticker == "PEPE" and launched.coin.position.tokens == 0, true)
check("launch claimed the ticker", world.tickers.PEPE, "coin1")
check("onLaunched called", world.launched[1], "coin1")

local filterCallsBefore = world.filterCalls
check("cooldown message", service:launch(player, data, "Second Coin", "TWO").message, "You can launch again in 1h.")
check("cooldown charges nothing", data.Balance, 9000)
check("cooldown skips the filter", world.filterCalls, filterCallsBefore)

data.CoinLaunches.lastAt = 0
stats.byCreator[101] = 3
check("per-player limit", service:launch(player, data, "Second Coin", "TWO").message, "You already have 3 live coins.")
stats.byCreator[101] = 0
stats.total = 50
check("Pulse full", service:launch(player, data, "Second Coin", "TWO").message, "Pulse is full, try again later.")
stats.total = 0
data.Balance = 999
check("launch needs the fee", service:launch(player, data, "Second Coin", "TWO").message, "Launching costs $1,000.00.")
data.Balance = 9000
world.filterMode = "hash"
check("filtered name refused", service:launch(player, data, "Second Coin", "TWO").message, "Name not allowed.")
world.filterMode = "error"
check("filter error refused", service:launch(player, data, "Second Coin", "TWO").message, "Couldn't check that name, try again.")
world.filterMode = nil
check("refusals charged nothing", data.Balance, 9000)
check("refusals claimed nothing", world.tickers.TWO, nil)

check("ticker taken", service:launch(player, data, "Other Pepe", "PEPE").message, "Ticker taken.")
check("ticker taken refunded", data.Balance, 9000)
world.failNext.claim = true
check("claim error", service:launch(player, data, "Second Coin", "TWO").message, "Couldn't launch, try again.")
world.failNext.create = true
check("create failure", service:launch(player, data, "Second Coin", "TWO").message, "Couldn't launch, try again.")
check("create failure released the ticker", world.tickers.TWO, nil)
check("store failures refunded", data.Balance, 9000)

-- Buying
local coinId = "coin1"
local buy = service:buy(player, data, coinId, 250)
check("buy succeeds", buy.success, true)
check("buy message", buy.message, "Bought 81.8M $PEPE for $250.00")
check("buy debits", data.Balance, 8750)
check("buy holding", data.Portfolio.Coins[coinId].tokens == 81775981 and data.Portfolio.Coins[coinId].cost == 250, true)
check("buy returns the panel", buy.coin.position.tokens, 81775981)
check("insufficient funds", service:buy(player, data, coinId, 1e6).message, "Insufficient funds.")
check("under $1", service:buy(player, data, coinId, 0.5).message, "Minimum buy is $1.")
check("NaN", service:buy(player, data, coinId, 0 / 0).message, "Minimum buy is $1.")
check("infinity", service:buy(player, data, coinId, math.huge).message, "Minimum buy is $1.")
check("string amount", service:buy(player, data, coinId, "100").message, "Minimum buy is $1.")
check("bad coin id", service:buy(player, data, 42, 100).message, "Coin not found.")
check("unknown coin refunded", service:buy(player, data, "nope", 100).message == "Coin not found." and data.Balance == 8750, true)
world.failNext.buy = true
check("store down", service:buy(player, data, coinId, 100).message, "Coins unavailable, try again.")
world.failNext.buy = "throw"
check("store error", service:buy(player, data, coinId, 100).message, "Something went wrong, try again.")
check("failed buys refunded", data.Balance, 8750)
service:buy(player, data, coinId, 100.456)
check("cents rounding", data.Balance, 8649.54, 1e-9)

-- A second order while the first waits on the store is refused
world.delay = 0.3
local first
task.spawn(function()
	first = service:buy(player, data, coinId, 10)
end)
task.wait(0.05)
check("busy while in flight", service:isBusy(101), true)
check("double click refused", service:buy(player, data, coinId, 10).message, "Order in progress.")
task.wait(0.5)
world.delay = 0
check("first order went through", first and first.success, true)
check("lock released", service:isBusy(101), false)

-- Selling
local before = data.Balance
local held = data.Portfolio.Coins[coinId].tokens
local costBefore = data.Portfolio.Coins[coinId].cost
local sell = service:sell(player, data, coinId, 0.5)
local remaining = held - math.floor(held * 0.5)
check("sell half", sell.success and data.Portfolio.Coins[coinId].tokens == remaining, true)
check("sell keeps proportional cost", data.Portfolio.Coins[coinId].cost, costBefore * remaining / held, 1e-9)
check("sell credits payout", data.Balance > before, true)
check("sell message", string.sub(sell.message, 1, 5), "Sold ")
service:sell(player, data, coinId, 1)
check("sell all removes holding", data.Portfolio.Coins[coinId], nil)
check("nothing to sell", service:sell(player, data, coinId, 1).message, "Nothing to sell.")
check("fraction 0", service:sell(player, data, coinId, 0).message, "Invalid amount.")
check("fraction over 1", service:sell(player, data, coinId, 1.5).message, "Invalid amount.")
service:buy(player, data, coinId, 100)
local heldNow, balanceNow = data.Portfolio.Coins[coinId].tokens, data.Balance
world.failNext.sell = true
check("sell store down", service:sell(player, data, coinId, 1).message, "Coins unavailable, try again.")
check("failed sell changes nothing", data.Portfolio.Coins[coinId].tokens == heldNow and data.Balance == balanceNow, true)

-- Graduation reaches CoinSystem through onTraded
local gService, gWorld, gPlayer, gData = setup(20000)
gService:launch(gPlayer, gData, "Moon Coin", "MOON")
gService:buy(gPlayer, gData, "coin1", 8600)
check("graduation reaches onTraded", gWorld.traded[1] and gWorld.traded[1].graduatedNow, true)

-- My coins: held and launched, archived included, most valuable first
gWorld.coins.old1 = CoinState.new({ id = "old1", name = "Old Coin", ticker = "OLD", creatorId = 5, creatorName = "Someone", now = NOW - 100 })
gWorld.archived.old1 = true
gData.Portfolio.Coins.old1 = { tokens = 1000, cost = 1 }
local rows = gService:myCoins(gData)
check("my coins rows", #rows, 2)
check("my coins sorted by value", rows[1] and rows[1].id, "coin1")
check("my coins archived flag", rows[2] and rows[2].archived, true)
check("my coins position", rows[2] and rows[2].position.tokens, 1000)

holder:Destroy()
return report()
```

- [ ] **Step 2: Write the failing integration test** (Client datamodel, during Play)

```lua
local Players = game:GetService("Players")
local Events = game:GetService("ReplicatedStorage"):WaitForChild("EventsFolder")
local player = Players.LocalPlayer

-- (H7's checker: total, failures, check, report)

local function invoke(name, ...)
	local remote = Events:FindFirstChild(name)
	if not remote then
		return { success = false, message = "missing remote " .. name }
	end
	local result = remote:InvokeServer(...)
	task.wait(0.6) -- clear of the per-remote cooldown
	return result
end

local ticker = "IT" .. tostring(math.random(1000, 9999))
local launch = invoke("LaunchCoinEvent", "Integration Test", ticker)
check("launch", launch and launch.message, "Launched $" .. ticker .. ".")
local coinId = launch and launch.coin and launch.coin.id
check("launch fee", player:GetAttribute("Balance"), 19000)

local pulse = invoke("GetPulseEvent")
local inNew = false
for _, summary in ipairs(pulse and pulse.columns and pulse.columns.New or {}) do
	if summary.id == coinId then
		inNew = true
	end
end
check("pulse ok", pulse and pulse.ok, true)
check("new coin in New right away", inNew, true)
check("pulse has server time", pulse and typeof(pulse.serverTime), "number")

local buy = invoke("CoinOrderEvent", "Buy", coinId, 250)
check("buy", buy and buy.message, "Bought 81.8M $" .. ticker .. " for $250.00")
check("buy balance", player:GetAttribute("Balance"), 18750)
local coin = invoke("GetCoinEvent", coinId)
check("panel position", coin and coin.success and coin.coin.position.tokens, 81775981)

local sell = invoke("CoinOrderEvent", "Sell", coinId, 1)
check("sell", sell and string.sub(sell.message, 1, 5), "Sold ")
check("sell balance", player:GetAttribute("Balance"), 18995.02, 1e-6)

local mine = invoke("GetMyCoinsEvent")
local listed = false
for _, row in ipairs(mine and mine.rows or {}) do
	if row.id == coinId then
		listed = row.position.tokens == 0
	end
end
check("launched coin in My coins", listed, true)
check("invalid action", invoke("CoinOrderEvent", "Short", coinId, 1).message, "Invalid order type.")
check("string amount", invoke("CoinOrderEvent", "Buy", coinId, "abc").message, "Minimum buy is $1.")
check("cooldown", string.sub(invoke("LaunchCoinEvent", "Another One", "AN" .. tostring(math.random(1000, 9999))).message, 1, 23), "You can launch again in")
check("unknown coin", invoke("GetCoinEvent", "nope").message, "Unknown coin.")

-- A double click: two orders at once, exactly one goes through
local results = {}
for i = 1, 2 do
	task.spawn(function()
		results[i] = Events.CoinOrderEvent:InvokeServer("Buy", coinId, 10)
	end)
end
local deadline = os.clock() + 10
while (not results[1] or not results[2]) and os.clock() < deadline do
	task.wait(0.1)
end
local successes = (results[1] and results[1].success and 1 or 0) + (results[2] and results[2].success and 1 or 0)
check("double click buys once", successes, 1)
check("double click charged once", player:GetAttribute("Balance"), 18985.02, 1e-6)

return report() .. "\ncoinId=" .. tostring(coinId)
```

- [ ] **Step 3: Run them and confirm they fail**

- Step 1 in Edit: expect the error `CoinService is not a valid member of Folder "ServerScriptService.Modules"`.
- `start_stop_play(true)`, wait about 5 s.
  - Step 2: expect `0/17 passed`, with `launch` reading `got missing remote LaunchCoinEvent`.
  - **H5** `READ`: expect `"hasWait":false` and no `launches` key.
- `start_stop_play(false)`.

- [ ] **Step 4: Add the remotes to `ServerSetup.server.luau`**

Replace:

```lua
	"GetWatchlistEvent",
	"ToggleWatchlistEvent",
}
```

with:

```lua
	"GetWatchlistEvent",
	"ToggleWatchlistEvent",
	"GetPulseEvent",
	"GetCoinEvent",
	"GetMyCoinsEvent",
	"CoinOrderEvent",
	"LaunchCoinEvent",
}
```

- [ ] **Step 5: Default the coin fields and wait for coin orders in `Data_Manager.server.luau`**

After the `createDefaultData` function, add:

```lua
-- Saves from before memecoins have no coin fields
local function applyCoinDefaults(playerData)
	playerData.Portfolio.Coins = playerData.Portfolio.Coins or {}
	playerData.CoinLaunches = playerData.CoinLaunches or { lastAt = 0, ids = {} }
end
```

In `onPlayerAdded`, replace:

```lua
		_G.PlayerData[player.UserId].Watchlist = saveData.Watchlist or {}
```

with:

```lua
		_G.PlayerData[player.UserId].Watchlist = saveData.Watchlist or {}
		_G.PlayerData[player.UserId].CoinLaunches = saveData.CoinLaunches
```

Still in `onPlayerAdded`, replace:

```lua
	-- Seed NetWorth so the status bar has a value before the first trade;
```

with:

```lua
	-- Set last: CoinSystem treats CoinLaunches as "this save has loaded"
	applyCoinDefaults(_G.PlayerData[player.UserId])

	-- Seed NetWorth so the status bar has a value before the first trade;
```

In `onPlayerRemoving`, replace:

```lua
local function onPlayerRemoving(player)
	local sessionData = _G.PlayerData[player.UserId]
```

with:

```lua
local function onPlayerRemoving(player)
	-- A coin order still waiting on the store would change this data after
	-- it's saved
	if _G.WaitForCoinOrders then
		_G.WaitForCoinOrders(player.UserId, 10)
	end

	local sessionData = _G.PlayerData[player.UserId]
```

- [ ] **Step 6: Count coins in `CalculatorModule.luau`**

Replace:

```lua
local ServerScriptService = game:GetService("ServerScriptService")

local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)

local CalculatorModule = {}
```

with:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CoinCurve = require(ReplicatedStorage.Modules.Coins.CoinCurve)
local MarketDataModule = require(ServerScriptService.Modules.MarketDataModule)

local CalculatorModule = {}

-- Coins are priced from this server's Pulse snapshot, or from the store for
-- coins that aren't on it. _G.LookupCoin is set by CoinSystem
function CalculatorModule.coinValue(playerData)
	local total = 0

	if not (_G.LookupCoin and playerData.Portfolio and playerData.Portfolio.Coins) then
		return total
	end

	for coinId, holding in pairs(playerData.Portfolio.Coins) do
		local state = _G.LookupCoin(coinId)

		if state then
			total += holding.tokens * CoinCurve.price(state.V, state.T)
		end
	end

	return total
end
```

Then replace:

```lua
	local finalNetWorth = playerData.Balance + totalShareValue + totalOptionValue
```

with:

```lua
	local finalNetWorth = playerData.Balance + totalShareValue + totalOptionValue + CalculatorModule.coinValue(playerData)
```

- [ ] **Step 7: Write `CoinService.luau`**

```lua
-- CoinService.luau
--
-- The rules for launching, buying and selling coins, kept apart from Roblox
-- services so they can be tested with fakes. CoinSystem.server.luau builds
-- the real one. deps:
--   store                  CoinStore (claimTicker, releaseTicker, create, buy, sell)
--   lookup(id)             state, "live" | "archived" (or nil, reason): a cached read
--   filter(text, userId)   broadcast-filtered text, or nil when the filter errors
--   displayNames(state)    name, ticker as currently shown to everyone
--   setBalance(player, balance)
--   liveStats()            { total, byCreator = { [userId] = count } }
--   onTraded(player, state, info)
--   onLaunched(player, state)
--   now()                  seconds
--   newId()                a fresh coin id

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Coins = ReplicatedStorage.Modules.Coins
local CoinConfig = require(Coins.CoinConfig)
local CoinCurve = require(Coins.CoinCurve)
local CoinFormat = require(Coins.CoinFormat)
local CoinRules = require(Coins.CoinRules)
local CoinState = require(Coins.CoinState)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)

local CoinService = {}
CoinService.__index = CoinService

local MAX_COIN_ID_LENGTH = 64

local function fail(message)
	return { success = false, message = message }
end

local function isCoinId(coinId)
	return typeof(coinId) == "string" and #coinId >= 1 and #coinId <= MAX_COIN_ID_LENGTH
end

local function isFiniteNumber(value)
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function CoinService.new(deps)
	return setmetatable({ deps = deps, busy = {} }, CoinService)
end

function CoinService:isBusy(userId)
	return self.busy[userId] == true
end

-- One coin order, launch or payout collection per player at a time: a
-- double click can't spend one balance twice while the first order waits
-- on the store, and a leaving player's save can wait for whatever is running
function CoinService:exclusive(player, action)
	local userId = player.UserId

	if self.busy[userId] then
		return fail("Order in progress.")
	end

	self.busy[userId] = true
	local ok, result = pcall(action)
	self.busy[userId] = nil

	if not ok then
		warn("[CoinService] " .. tostring(result))
		return fail("Something went wrong, try again.")
	end

	return result
end

function CoinService:position(playerData, state)
	local holding = playerData.Portfolio.Coins[state.id]

	if not holding then
		return { tokens = 0, value = 0, cost = 0, pnl = 0 }
	end

	local value = holding.tokens * CoinCurve.price(state.V, state.T)

	return { tokens = holding.tokens, value = value, cost = holding.cost, pnl = value - holding.cost }
end

-- Everything the coin panel shows, as this player sees it
function CoinService:detail(playerData, state, where)
	local detail = CoinState.detail(state)
	detail.name, detail.ticker = self.deps.displayNames(state)
	detail.position = self:position(playerData, state)
	detail.archived = where == "archived"

	return detail
end

-- Checks run cheapest first, so the filter (a web call) only runs for a
-- launch that would otherwise go through. The fee is taken before the store
-- calls and refunded if one fails: a share trade made while they wait can't
-- take the balance below zero
function CoinService:launch(player, playerData, rawName, rawTicker)
	local name, nameMessage = CoinRules.validateName(rawName)

	if not name then
		return fail(nameMessage)
	end

	local ticker, tickerMessage = CoinRules.validateTicker(rawTicker)

	if not ticker then
		return fail(tickerMessage)
	end

	return self:exclusive(player, function()
		local deps = self.deps
		local now = deps.now()
		local launches = playerData.CoinLaunches
		local wait = launches.lastAt + CoinConfig.LAUNCH_COOLDOWN - now

		if wait > 0 then
			return fail("You can launch again in " .. CoinFormat.age(wait) .. ".")
		end

		local stats = deps.liveStats()

		if (stats.byCreator[player.UserId] or 0) >= CoinConfig.MAX_LIVE_COINS_PER_PLAYER then
			return fail(string.format("You already have %d live coins.", CoinConfig.MAX_LIVE_COINS_PER_PLAYER))
		end

		if stats.total >= CoinConfig.MAX_LIVE_COINS then
			return fail("Pulse is full, try again later.")
		end

		if playerData.Balance < CoinConfig.LAUNCH_FEE then
			return fail("Launching costs " .. NumberModule.format(CoinConfig.LAUNCH_FEE) .. ".")
		end

		-- Shown to every player in every server, so it must pass the
		-- broadcast filter untouched
		local filteredName = deps.filter(name, player.UserId)
		local filteredTicker = filteredName and deps.filter(ticker, player.UserId)

		if not filteredName or not filteredTicker then
			return fail("Couldn't check that name, try again.")
		end

		if filteredName ~= name or filteredTicker ~= ticker then
			return fail("Name not allowed.")
		end

		deps.setBalance(player, playerData.Balance - CoinConfig.LAUNCH_FEE)

		local function refund(message)
			deps.setBalance(player, playerData.Balance + CoinConfig.LAUNCH_FEE)
			return fail(message)
		end

		local id = deps.newId()
		local claimOk, claimed = pcall(deps.store.claimTicker, ticker, id)

		if not claimOk or claimed == nil then
			return refund("Couldn't launch, try again.")
		end

		if not claimed then
			return refund("Ticker taken.")
		end

		local state = CoinState.new({ id = id, name = name, ticker = ticker, creatorId = player.UserId, creatorName = player.Name, now = now })
		local createOk, created = pcall(deps.store.create, state)

		if not createOk or not created then
			pcall(deps.store.releaseTicker, ticker, id)
			return refund("Couldn't launch, try again.")
		end

		launches.lastAt = now
		table.insert(launches.ids, 1, id)
		-- Spawned so a bug in a listener can't turn a finished launch into an error
		task.spawn(deps.onLaunched, player, state)

		return { success = true, message = "Launched $" .. ticker .. ".", coin = self:detail(playerData, state, "live") }
	end)
end

function CoinService:buy(player, playerData, coinId, amount)
	if not isCoinId(coinId) then
		return fail("Coin not found.")
	end

	if not isFiniteNumber(amount) or amount < 1 then
		return fail("Minimum buy is $1.")
	end

	local dollars = math.floor(amount * 100 + 0.5) / 100

	return self:exclusive(player, function()
		if playerData.Balance < dollars then
			return fail("Insufficient funds.")
		end

		local deps = self.deps

		-- Taken first and refunded on failure, as in launch
		deps.setBalance(player, playerData.Balance - dollars)

		local ok, state, info = pcall(deps.store.buy, coinId, dollars, player.UserId, deps.now())

		if not ok or not state then
			if not ok then
				warn("[CoinService] buy failed: " .. tostring(state))
			end

			deps.setBalance(player, playerData.Balance + dollars)
			return fail(ok and info or "Something went wrong, try again.")
		end

		local holding = playerData.Portfolio.Coins[coinId] or { tokens = 0, cost = 0 }
		holding.tokens += info.tokensOut
		holding.cost += dollars
		playerData.Portfolio.Coins[coinId] = holding

		task.spawn(deps.onTraded, player, state, info)

		local _, ticker = deps.displayNames(state)

		return {
			success = true,
			message = string.format("Bought %s $%s for %s", CoinFormat.tokens(info.tokensOut), ticker, NumberModule.format(dollars)),
			coin = self:detail(playerData, state, "live"),
		}
	end)
end

-- The order lock means nothing else can sell these tokens while the store
-- call runs, so they're only taken once it succeeds
function CoinService:sell(player, playerData, coinId, fraction)
	if not isCoinId(coinId) then
		return fail("Coin not found.")
	end

	if not isFiniteNumber(fraction) or fraction <= 0 or fraction > 1 then
		return fail("Invalid amount.")
	end

	return self:exclusive(player, function()
		local holding = playerData.Portfolio.Coins[coinId]
		local tokens = holding and math.floor(holding.tokens * fraction) or 0

		if tokens < 1 then
			return fail("Nothing to sell.")
		end

		local deps = self.deps
		local ok, state, info = pcall(deps.store.sell, coinId, tokens, player.UserId, deps.now())

		if not ok or not state then
			if not ok then
				warn("[CoinService] sell failed: " .. tostring(state))
			end

			return fail(ok and info or "Something went wrong, try again.")
		end

		-- What's left keeps its share of the original cost
		local remaining = holding.tokens - tokens
		holding.cost = remaining >= 1 and holding.cost * remaining / holding.tokens or 0
		holding.tokens = remaining

		if remaining < 1 then
			playerData.Portfolio.Coins[coinId] = nil
		end

		deps.setBalance(player, playerData.Balance + info.payout)
		task.spawn(deps.onTraded, player, state, info)

		local _, ticker = deps.displayNames(state)

		return {
			success = true,
			message = string.format("Sold %s $%s for %s", CoinFormat.tokens(tokens), ticker, NumberModule.format(info.payout)),
			coin = self:detail(playerData, state, "live"),
		}
	end)
end

-- Every coin the player holds (always, so anything held can be sold) and
-- the coins they launched, up to MY_COINS_LIMIT rows, archived ones included
function CoinService:myCoins(playerData)
	local ids, seen = {}, {}

	for id in pairs(playerData.Portfolio.Coins) do
		seen[id] = true
		table.insert(ids, id)
	end

	for _, id in ipairs(playerData.CoinLaunches.ids) do
		if #ids >= CoinConfig.MY_COINS_LIMIT then
			break
		end

		if not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end

	local rows = {}

	for _, id in ipairs(ids) do
		local state, where = self.deps.lookup(id)

		if state then
			local row = CoinState.summary(state)
			row.name, row.ticker = self.deps.displayNames(state)
			row.position = self:position(playerData, state)
			row.archived = where == "archived"
			table.insert(rows, row)
		end
	end

	table.sort(rows, function(a, b)
		if a.position.value ~= b.position.value then
			return a.position.value > b.position.value
		end

		return a.createdAt > b.createdAt
	end)

	return rows
end

return CoinService
```

- [ ] **Step 8: Run the unit test and confirm it passes**

Run Step 1 in Edit.

Expected: `59/59 passed`.

- [ ] **Step 9: Write `CoinSystem.server.luau`**

```lua
-- CoinSystem.server.luau
--
-- Player memecoins on the server. Answers the coin remotes through
-- CoinService, keeps this server's cached Pulse snapshot fresh (a player's
-- request never touches the memory store), archives idle coins, backs coins
-- up while they trade, and pays graduation bonuses through the mailbox.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")

local Coins = ReplicatedStorage.Modules.Coins
local CoinConfig = require(Coins.CoinConfig)
local CoinState = require(Coins.CoinState)
local PulseColumns = require(Coins.PulseColumns)
local CoinStore = require(ServerScriptService.Modules.CoinStore)
local CoinService = require(ServerScriptService.Modules.CoinService)
local PayoutMailbox = require(ServerScriptService.Modules.PayoutMailbox)
local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetPulseEvent = EventsFolder:WaitForChild("GetPulseEvent")
local GetCoinEvent = EventsFolder:WaitForChild("GetCoinEvent")
local GetMyCoinsEvent = EventsFolder:WaitForChild("GetMyCoinsEvent")
local CoinOrderEvent = EventsFolder:WaitForChild("CoinOrderEvent")
local LaunchCoinEvent = EventsFolder:WaitForChild("LaunchCoinEvent")

local REQUEST_COOLDOWN = 0.5 -- per player, per remote
local ARCHIVE_INTERVAL = 300
local BACKUP_INTERVAL = 300 -- a trading coin's durable copy is at most 5 minutes old
local PAYOUT_INTERVAL = 60
local DISPLAY_FILTER_TTL = 1800
local DATA_WAIT = 30 -- how long a joining player's save may take to load
local SAVE_WAIT_POLL = 0.1
local MAX_COIN_ID_LENGTH = 64

local snapshot = {
	ok = true,
	updatedAt = 0,
	columns = PulseColumns.build({}),
	states = {},
	total = 0,
	byCreator = {},
}
local lastBackupAt = {}
local displayCache = {}
local lastRequest = {}
local service

local function isThrottled(player, remoteName)
	local now = os.clock()
	local perRemote = lastRequest[player.UserId]

	if not perRemote then
		perRemote = {}
		lastRequest[player.UserId] = perRemote
	end

	if now - (perRemote[remoteName] or 0) < REQUEST_COOLDOWN then
		return true
	end

	perRemote[remoteName] = now

	return false
end

local function getPlayerData(player)
	local data = _G.PlayerData and _G.PlayerData[player.UserId]

	-- Data_Manager sets CoinLaunches last, once the save has loaded
	if data and data.Balance and data.Portfolio and data.Portfolio.Coins and data.CoinLaunches then
		return data
	end

	return nil
end

local function filterForBroadcast(text, userId)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()
	end)

	return ok and result or nil
end

-- Names passed the filter at launch. Stored text should be filtered again
-- when it's shown, since the filter changes over time, so names are
-- re-filtered in the background. Until that finishes (or if it fails) the
-- launch-time text is shown
local function displayNames(state)
	local entry = displayCache[state.id]

	if not entry then
		entry = { name = state.name, ticker = state.ticker, checkedAt = -math.huge }
		displayCache[state.id] = entry
	end

	if not entry.refreshing and os.clock() - entry.checkedAt >= DISPLAY_FILTER_TTL then
		entry.refreshing = true

		task.spawn(function()
			local name = filterForBroadcast(state.name, state.creatorId)
			local ticker = filterForBroadcast(state.ticker, state.creatorId)

			if name and ticker then
				entry.name, entry.ticker = name, ticker
			end

			entry.checkedAt = os.clock()
			entry.refreshing = false
		end)
	end

	return entry.name, entry.ticker
end

local function rebuild(states, ok, updatedAt)
	local summaries, byCreator = {}, {}

	for _, state in ipairs(states) do
		local summary = CoinState.summary(state)
		summary.name, summary.ticker = displayNames(state)
		table.insert(summaries, summary)
		byCreator[state.creatorId] = (byCreator[state.creatorId] or 0) + 1
	end

	snapshot = {
		ok = ok,
		updatedAt = updatedAt,
		columns = PulseColumns.build(summaries),
		states = states,
		total = #states,
		byCreator = byCreator,
	}
end

local function refreshSnapshot()
	local states = CoinStore.listLive()

	if states then
		rebuild(states, true, os.time())
	else
		-- Keep the last good list on screen; clients show its age
		snapshot.ok = false
	end
end

-- A trade or launch in this server shows on its Pulse right away, not at
-- the next refresh
local function upsert(state)
	local states = table.clone(snapshot.states)
	local replaced = false

	for index, existing in ipairs(states) do
		if existing.id == state.id then
			states[index] = state
			replaced = true
			break
		end
	end

	if not replaced then
		table.insert(states, state)
	end

	rebuild(states, snapshot.ok, snapshot.updatedAt)
end

-- The snapshot first (free), then the store for coins that aren't on Pulse
local function lookup(id)
	for _, state in ipairs(snapshot.states) do
		if state.id == id then
			return state, "live"
		end
	end

	return CoinStore.read(id)
end

local function maybeBackup(state)
	if os.time() - (lastBackupAt[state.id] or 0) >= BACKUP_INTERVAL then
		lastBackupAt[state.id] = os.time()
		task.spawn(CoinStore.backup, state)
	end
end

local function collectPayouts(player)
	local playerData = getPlayerData(player)

	if not playerData then
		return
	end

	-- Under the order lock, so a player leaving mid-collection has their
	-- save wait for the credit (Data_Manager waits on the lock)
	service:exclusive(player, function()
		local payouts = PayoutMailbox.claim(player.UserId)

		if not payouts or #payouts == 0 then
			return
		end

		local total = 0

		for _, payout in ipairs(payouts) do
			total += payout.amount
		end

		_G.UpdatePlayerStat(player, "Balance", playerData.Balance + total)
		task.spawn(CalculatorModule.calculateNetWorth, player)
	end)
end

-- Only one server's trade sees a coin cross the line (the update is
-- atomic), and the payout id stops a repeat from paying twice
local function onGraduated(state)
	lastBackupAt[state.id] = os.time()

	task.spawn(function()
		CoinStore.backup(state)

		local added = PayoutMailbox.add(state.creatorId, {
			id = state.id .. ":graduation",
			amount = CoinConfig.GRADUATION_BONUS,
			reason = "graduation",
			coinId = state.id,
		})

		if not added then
			warn("[CoinSystem] graduation bonus for coin " .. state.id .. " could not be queued")
			return
		end

		-- A creator in this server is paid now; anyone else at their
		-- server's next collection
		local creator = Players:GetPlayerByUserId(state.creatorId)

		if creator then
			collectPayouts(creator)
		end
	end)
end

service = CoinService.new({
	store = CoinStore,
	lookup = lookup,
	filter = filterForBroadcast,
	displayNames = displayNames,
	setBalance = function(player, balance)
		_G.UpdatePlayerStat(player, "Balance", balance)
	end,
	liveStats = function()
		return { total = snapshot.total, byCreator = snapshot.byCreator }
	end,
	onTraded = function(player, state, info)
		upsert(state)
		maybeBackup(state)

		if info.graduatedNow then
			onGraduated(state)
		end

		task.spawn(CalculatorModule.calculateNetWorth, player)
	end,
	onLaunched = function(_, state)
		-- create() just wrote the durable copy
		lastBackupAt[state.id] = os.time()
		upsert(state)
	end,
	now = os.time,
	newId = function()
		return string.lower((string.gsub(HttpService:GenerateGUID(false), "-", "")))
	end,
})

_G.LookupCoin = lookup

-- Data_Manager calls this before saving a leaving player, so an order still
-- waiting on the store can't change their data after it's saved
_G.WaitForCoinOrders = function(userId, timeout)
	local deadline = os.clock() + timeout

	while service:isBusy(userId) and os.clock() < deadline do
		task.wait(SAVE_WAIT_POLL)
	end
end

GetPulseEvent.OnServerInvoke = function(player)
	if isThrottled(player, "GetPulse") then
		return nil
	end

	return { ok = snapshot.ok, updatedAt = snapshot.updatedAt, serverTime = os.time(), columns = snapshot.columns }
end

GetCoinEvent.OnServerInvoke = function(player, coinId)
	if isThrottled(player, "GetCoin") then
		return nil
	end

	local playerData = getPlayerData(player)

	if not playerData or typeof(coinId) ~= "string" or #coinId > MAX_COIN_ID_LENGTH then
		return { success = false, message = "Unknown coin." }
	end

	-- The panel reads the store directly: it shows one coin and should be
	-- exact, while Pulse cards can be a refresh behind
	local state, where = CoinStore.read(coinId)

	if not state then
		return { success = false, message = where == "unavailable" and "Coins unavailable, retrying…" or "Unknown coin." }
	end

	return { success = true, coin = service:detail(playerData, state, where), serverTime = os.time() }
end

GetMyCoinsEvent.OnServerInvoke = function(player)
	if isThrottled(player, "GetMyCoins") then
		return nil
	end

	local playerData = getPlayerData(player)

	if not playerData then
		return { success = false, message = "Your data is still loading." }
	end

	return { success = true, rows = service:myCoins(playerData), serverTime = os.time() }
end

CoinOrderEvent.OnServerInvoke = function(player, action, coinId, amount)
	if isThrottled(player, "CoinOrder") then
		return { success = false, message = "Slow down." }
	end

	local playerData = getPlayerData(player)

	if not playerData then
		return { success = false, message = "Your data is still loading." }
	end

	if action == "Buy" then
		return service:buy(player, playerData, coinId, amount)
	elseif action == "Sell" then
		return service:sell(player, playerData, coinId, amount)
	end

	return { success = false, message = "Invalid order type." }
end

LaunchCoinEvent.OnServerInvoke = function(player, name, ticker)
	if isThrottled(player, "LaunchCoin") then
		return { success = false, message = "Slow down." }
	end

	local playerData = getPlayerData(player)

	if not playerData then
		return { success = false, message = "Your data is still loading." }
	end

	return service:launch(player, playerData, name, ticker)
end

local function onPlayerAdded(player)
	local deadline = os.clock() + DATA_WAIT

	while not getPlayerData(player) and player.Parent and os.clock() < deadline do
		task.wait(0.5)
	end

	collectPayouts(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player.UserId] = nil
end)

-- Pulse snapshot, as often as the memory-store request budget allows
task.spawn(function()
	while true do
		refreshSnapshot()
		task.wait(CoinConfig.snapshotInterval(snapshot.total, #Players:GetPlayers()))
	end
end)

task.spawn(function()
	while true do
		task.wait(ARCHIVE_INTERVAL)

		if snapshot.ok and CoinStore.archiveIdle(snapshot.states, os.time()) > 0 then
			refreshSnapshot()
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(PAYOUT_INTERVAL)

		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(collectPayouts, player)
		end
	end
end)
```

- [ ] **Step 10: Run the integration test, H5 and the payout check**

Run `start_stop_play(true)` and wait about 5 s.

1. **H5** with `ACTION = "READ"`. Expected:
   - `"hasWait":true`;
   - `"launches":{"lastAt":0,"ids":[]}` (Kevin's old save was defaulted on load);
   - `"coins":[]`;
   - `"coinValue":0`;
   - `shares` unchanged from Task 0.
2. **H5** with `ACTION = "SETUP"`, `BALANCE = 20000`. Expected: `"balance":20000`. Then run **H9** and wait 15 s.
3. Step 2 (Client). Expected:
   - `17/17 passed`;
   - a `coinId=` line, which you note;
   - `get_console_output` shows no errors from `CoinSystem`, `CoinService` or `CoinStore`.
4. Client: `return game:GetService("ReplicatedStorage").EventsFolder.GetCoinEvent:InvokeServer("<coinId>").coin.position.value`. Note the value. Then run **H5** `READ`. Expected: `coinValue` equals that value within $0.01. The double-click left a $10 position, so it's above 0.
5. **H5** with `ACTION = "WAIT"`. Expected: `"waited":` below `0.5`, because no order is running.
6. Server:
   ```lua
   local PayoutMailbox = require(game:GetService("ServerScriptService").Modules.PayoutMailbox)
   local player = game:GetService("Players"):GetPlayers()[1]
   return PayoutMailbox.add(player.UserId, { id = "test:" .. os.time(), amount = 123, reason = "test", coinId = "none" })
   ```
   Expected: `true`.
7. Client:
   ```lua
   local player = game:GetService("Players").LocalPlayer
   local start = player:GetAttribute("Balance")
   local deadline = os.clock() + 70
   while player:GetAttribute("Balance") == start and os.clock() < deadline do
   	task.wait(1)
   end
   return player:GetAttribute("Balance") - start
   ```
   Expected: `123`. The 60 s collection loop paid it once.
8. **H5** with `ACTION = "RESTORE"`, `BALANCE = START_BALANCE`. Expected: `"balance":` equals `START_BALANCE`, `"coins":[]`. Then run `start_stop_play(false)`.

- [ ] **Step 11: Commit and record**

```bash
git add src/server/Modules/CoinService.luau src/server/Core/CoinSystem.server.luau src/server/Core/ServerSetup.server.luau src/server/Core/Data_Manager.server.luau src/server/Modules/CalculatorModule.luau
git commit -m "Coins: server rules, remotes, Pulse snapshot, payouts, saves and net worth" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
printf '%s\n' "Task 4: unit 59/59, integration 17/17, H5 defaults+wait+coinValue, payout 123 once PASS" > "$WS/task-4-studio.txt"
$S/executing-plans/scripts/task-done $PLAN 4 <BASE> -- grep -q 'PASS$' "$WS/task-4-studio.txt"
```


---
### Task 5: The Pulse tab in the shell

This task adds the tab button and an empty Pulse screen, and makes five tabs fit the narrow window.

**Files:**
- Create: `src/client/Controllers/PulseController.client.luau` (a stub here; Task 6 replaces it)
- Modify:
  - `src/client/Controllers/ShellController.client.luau` (constants, tab layout, `layoutShell`, signals);
  - `src/client/Controllers/TerminalController.client.luau:210-227` (the `Tabs` table);
  - `src/shared/Modules/Multi/Theme.luau` (`Theme.TileColors`).
- Test: Play-mode Client checks, H3 and H2 (`"Shell"`)

**Interfaces:**
- Consumes: nothing from earlier tasks. It runs alongside the server work, but the Pulse screen stays empty until Task 6.
- Produces:
  - `TopBar.TabContainer.PulseButton` (a TextButton);
  - `ScreenContainer.PulseScreen` (a full-size Frame, hidden until its tab is picked);
  - `Theme.TileColors`: an array of six `Color3`;
  - tabs ordered Dashboard · Pulse · Portfolio · Trade · Charts, with padding that shrinks (10 → 2 px) before tabs overflow.

- [ ] **Step 1: Write the failing check** (Client datamodel, during Play)

```lua
local mb = game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground
local buttons = {}
for _, button in ipairs(mb.TopBar.TabContainer:GetChildren()) do
	if button:IsA("TextButton") then
		table.insert(buttons, button)
	end
end
table.sort(buttons, function(a, b)
	return a.AbsolutePosition.X < b.AbsolutePosition.X
end)
local names = {}
for _, button in ipairs(buttons) do
	table.insert(names, button.Name)
end
local pulse = mb.ScreenContainer:FindFirstChild("PulseScreen")
return string.format("%s | pulseScreen=%s", table.concat(names, ","), pulse and tostring(pulse.Visible) or "missing")
```

- [ ] **Step 2: Run it and confirm it fails**

`start_stop_play(true)`, wait about 5 s, then run Step 1 and **H3**.

Expected:
- Step 1 lists four buttons with no `PulseButton`, and `pulseScreen=missing`.
- H3 has `fiveTabs=false`.

Then `start_stop_play(false)`.

- [ ] **Step 3: Add `Theme.TileColors`**

In `Theme.luau`, after the closing `}` of `Theme.Colors`, add:

```lua

-- Identity colors for coin tiles, picked per coin by id. Data, not chrome:
-- the palette audit exempts tiles by name. Dark (Background) letters read on
-- every one of them at 7:1 or better
Theme.TileColors = {
	Theme.Colors.Accent,
	Color3.fromRGB(0, 170, 255),
	Color3.fromRGB(255, 170, 0),
	Color3.fromRGB(255, 90, 205),
	Theme.Colors.Up,
	Theme.Colors.AccentSoft,
}
```

- [ ] **Step 4: Order and squeeze the tabs in `ShellController.client.luau`**

Replace:

```lua
local TAB_TEXT_PADDING = 10
```

with:

```lua
local TAB_TEXT_PADDING = 10 -- each side, when there's room
local MIN_TAB_PADDING = 2 -- narrow windows squeeze tab padding down to this
local UNLISTED_TAB_ORDER = 99

-- Left to right. Pulse's button is made in code, so the order lives here
-- rather than in the Studio place
local TAB_ORDER = {
	DashboardButton = 1,
	PulseButton = 2,
	PortfolioButton = 3,
	TradeButton = 4,
	ChartsButton = 5,
}
```

Replace:

```lua
TabLayout.Padding = UDim.new(0, 4)

for _, tabButton in ipairs(TabContainer:GetChildren()) do
	if tabButton:IsA("TextButton") then
		tabButton.AutomaticSize = Enum.AutomaticSize.X
		tabButton.Size = UDim2.new(0, 0, 1, 0)

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, TAB_TEXT_PADDING)
		padding.PaddingRight = UDim.new(0, TAB_TEXT_PADDING)
		padding.Parent = tabButton
	end
end
```

with:

```lua
TabLayout.Padding = UDim.new(0, 4)
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
```

In `layoutShell`, replace:

```lua
	-- On a narrow window the wordmark gives up its space before the tabs do
	local tabsLeftWithWordmark = leftEdge + WORDMARK_WIDTH + SECTION_GAP
	local showWordmark = tabsRight - tabsLeftWithWordmark >= TabLayout.AbsoluteContentSize.X
	local tabsLeft = showWordmark and tabsLeftWithWordmark or leftEdge
```

with:

```lua
	-- Measured from the text, not the buttons' current size, which depends
	-- on the padding set below
	local textWidth, tabCount = 0, 0

	for _, tabButton in ipairs(TabContainer:GetChildren()) do
		if tabButton:IsA("TextButton") then
			textWidth += tabButton.TextBounds.X
			tabCount += 1
		end
	end

	local gaps = math.max(tabCount - 1, 0) * TabLayout.Padding.Offset
	local naturalWidth = textWidth + gaps + tabCount * TAB_TEXT_PADDING * 2

	-- On a narrow window the wordmark gives up its space first, then the
	-- tabs give up padding
	local tabsLeftWithWordmark = leftEdge + WORDMARK_WIDTH + SECTION_GAP
	local showWordmark = tabsRight - tabsLeftWithWordmark >= naturalWidth
	local tabsLeft = showWordmark and tabsLeftWithWordmark or leftEdge
	local spare = tabsRight - tabsLeft - textWidth - gaps
	local tabPadding = math.clamp(math.floor(spare / math.max(tabCount * 2, 1)), MIN_TAB_PADDING, TAB_TEXT_PADDING)

	for _, tabButton in ipairs(TabContainer:GetChildren()) do
		local padding = tabButton:FindFirstChild("TabPadding")

		if padding then
			padding.PaddingLeft = UDim.new(0, tabPadding)
			padding.PaddingRight = UDim.new(0, tabPadding)
		end
	end
```

Directly after the `end` that closes `layoutShell` (the line after `ScreenContainer.Size = UDim2.new(1, 0, 1, -(navHeight + STATUS_BAR_HEIGHT))`), add:

```lua

local function styleTabButton(tabButton)
	if not tabButton:IsA("TextButton") or tabButton:FindFirstChild("TabPadding") then
		return
	end

	tabButton.AutomaticSize = Enum.AutomaticSize.X
	tabButton.Size = UDim2.new(0, 0, 1, 0)
	tabButton.LayoutOrder = TAB_ORDER[tabButton.Name] or UNLISTED_TAB_ORDER

	local padding = Instance.new("UIPadding")
	padding.Name = "TabPadding"
	padding.PaddingLeft = UDim.new(0, TAB_TEXT_PADDING)
	padding.PaddingRight = UDim.new(0, TAB_TEXT_PADDING)
	padding.Parent = tabButton

	-- Text widths settle once fonts load
	tabButton:GetPropertyChangedSignal("TextBounds"):Connect(layoutShell)
	layoutShell()
end

for _, child in ipairs(TabContainer:GetChildren()) do
	styleTabButton(child)
end

-- PulseController adds its tab button at runtime
TabContainer.ChildAdded:Connect(styleTabButton)
```

Replace:

```lua
-- Tab widths and the balance text settle once fonts load, and the balance
-- text changes with every trade
TabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(layoutShell)
BalanceValue:GetPropertyChangedSignal("TextBounds"):Connect(layoutShell)
```

with:

```lua
-- The balance text settles once fonts load and changes with every trade.
-- (Not the list's content size: the padding set in layoutShell changes it,
-- which would loop)
BalanceValue:GetPropertyChangedSignal("TextBounds"):Connect(layoutShell)
```

- [ ] **Step 5: Add the Pulse tab to `TerminalController.client.luau`**

Replace:

```lua
	Dashboard = {
		Button = TabContainer:WaitForChild("DashboardButton"),
		Frame = ScreenContainer:WaitForChild("DashboardScreen"),
	},
```

with:

```lua
	Dashboard = {
		Button = TabContainer:WaitForChild("DashboardButton"),
		Frame = ScreenContainer:WaitForChild("DashboardScreen"),
	},
	-- Built in code by PulseController
	Pulse = {
		Button = TabContainer:WaitForChild("PulseButton"),
		Frame = ScreenContainer:WaitForChild("PulseScreen"),
	},
```

- [ ] **Step 6: Write the `PulseController.client.luau` stub**

```lua
-- PulseController.client.luau
--
-- The Pulse tab: player-launched coins in New / About to graduate /
-- Graduated columns. Built entirely in code from Theme tokens; nothing for
-- Pulse lives in the Studio place. TerminalController switches to it like
-- any other tab.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)

local Player = Players.LocalPlayer
local MainBackground = Player:WaitForChild("PlayerGui"):WaitForChild("TerminalGui"):WaitForChild("MainBackground")
local TabContainer = MainBackground:WaitForChild("TopBar"):WaitForChild("TabContainer")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")

-- Styled like the Studio-made tabs (Tab role); TerminalController owns the
-- active/inactive text color
local PulseButton = Instance.new("TextButton")
PulseButton.Name = "PulseButton"
PulseButton.Text = "Pulse"
PulseButton.FontFace = Theme.Fonts.UISemibold
PulseButton.TextSize = Theme.TextSize.Body
PulseButton.TextColor3 = Theme.Colors.TextMuted
PulseButton.BackgroundTransparency = 1
PulseButton.BorderSizePixel = 0
PulseButton.AutoButtonColor = false
PulseButton.Size = UDim2.new(0, 0, 1, 0)
PulseButton.Parent = TabContainer

local PulseScreen = Instance.new("Frame")
PulseScreen.Name = "PulseScreen"
PulseScreen.Size = UDim2.fromScale(1, 1)
PulseScreen.BackgroundColor3 = Theme.Colors.Background
PulseScreen.BorderSizePixel = 0
PulseScreen.Visible = false
PulseScreen.Parent = ScreenContainer
```

- [ ] **Step 7: Run the checks and confirm they pass**

`start_stop_play(true)`, wait about 5 s.

1. Step 1. Expected: `DashboardButton,PulseButton,PortfolioButton,TradeButton,ChartsButton | pulseScreen=false`.
2. `user_mouse_input` click on `LocalPlayer.PlayerGui.TerminalGui.MainBackground.TopBar.TabContainer.PulseButton`. Then on the Client:
   ```lua
   local mb = game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground
   local screens, tabs = mb.ScreenContainer, mb.TopBar.TabContainer
   return string.format("pulse=%s dashboard=%s charts=%s pulseText=%s dashboardText=%s", tostring(screens.PulseScreen.Visible), tostring(screens.DashboardScreen.Visible), tostring(screens.ChartsScreen.Visible), tabs.PulseButton.TextColor3:ToHex(), tabs.DashboardButton.TextColor3:ToHex())
   ```
   Expected: `pulse=true dashboard=false charts=false pulseText=9a6bff dashboardText=8b90a3`.
3. Click `…TabContainer.DashboardButton`. Expected: re-running the snippet gives `pulse=false dashboard=true`.
4. **H3.** Expected: every value is `true`, including `fiveTabs` and `tabsFit`.
5. **H2** with `SCOPE = "Shell"`. Expected: `0 problem(s)`.

Run **H5** `RESTORE` (`BALANCE = START_BALANCE`), then `start_stop_play(false)`.

- [ ] **Step 8: Commit and record**

```bash
git add src/client/Controllers/PulseController.client.luau src/client/Controllers/ShellController.client.luau src/client/Controllers/TerminalController.client.luau src/shared/Modules/Multi/Theme.luau
git commit -m "Pulse tab in the shell: five tabs ordered and fitted, tile colors" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
printf '%s\n' "Task 5: tab order ok, Pulse switches (9a6bff/8b90a3), H3 all true with 5 tabs, H2 Shell 0 PASS" > "$WS/task-5-studio.txt"
$S/executing-plans/scripts/task-done $PLAN 5 <BASE> -- grep -q 'PASS$' "$WS/task-5-studio.txt"
```

---
### Task 6: The Pulse screen: columns, cards, quick-buy, coin panel, My coins

**Files:**
- Create: `src/shared/Modules/Pulse/PulseUI.luau`, `src/shared/Modules/Pulse/CoinCard.luau`, `src/shared/Modules/Pulse/Sparkline.luau`, `src/shared/Modules/Pulse/CoinPanel.luau`
- Replace: `src/client/Controllers/PulseController.client.luau` (Task 5's stub becomes the full controller)
- Test: Play-mode checks with seeded coins (H8), H2 (`"PulseScreen"`), H3

**Interfaces:**
- Consumes:
  - Task 4: the remotes and their result shapes, exactly as Task 4 lists them.
  - Task 5: `PulseButton`, `PulseScreen`, `Theme.TileColors`.
  - Tasks 1–2: `CoinConfig.BUY_PRESETS`, `SELL_PRESETS`, `DEFAULT_QUICK_BUY`; `CoinFormat`; `CoinState.pointsAsOf`.
- Produces (Task 7 builds on these):
  - In `PulseController`, the locals `PulseScreen`, `Header`, `Panel` (a CoinPanel), `refresh()`, `setStatus(text, color)`, `serverNow()`, `applyEnabled()`, `storeOk`, `orderInFlight`, and the marker comment `-- Launching (Task 7)`.
  - **`PulseUI`:**
    - `corner`, `stroke`, `frame(props)`, `label(props)`, `button(props)`, `scroller(props)`;
    - `hover(button, base, hover)`, `setEnabled(button, enabled, color, textColor)`, `onClick(button, callback)`.
    - `props` takes: `name`, `parent`, `position`, `size`, `anchor`, `z`, `color` (a fill; omit it for transparent), `text`, `textColor`, `font`, `textSize`, `alignX`.
  - **`CoinPanel`:** `new(parent, top, { onBuy(coinId, dollars), onSell(coinId, fraction) })`, plus `:select(coinId)`, `:show(detail, now)`, `:hide()` and `:setEnabled(enabled)`. Its fields are `.coinId`, `.detail` and `.root`.
- UI paths the tests use, all under `PulseScreen`:
  - `Header.{Title, QuickBuyPicker.Amount_<n>, MyCoinsToggle, StatusLabel, FreshnessLabel}`;
  - `Columns.{New,AboutToGraduate,Graduated}Column.{List.Card_<id>.{BuyButton, GraduatedBadge, Ticker}, Count, EmptyLabel}`;
  - `MyCoinsView.List.Row_<id>.ArchivedTag`;
  - `CoinPanel.{Ticker, Chart, BuyPresets.Buy_<n>, SellPresets.Sell_<pct>, Position, PnL, ArchivedNote, CloseButton}`.

- [ ] **Step 1: Write the failing check** (Client datamodel, during Play)

Replace `<LONG>`, `<ABOUT>` and `<GRAD>` with the ids H8 returns in Step 8.

```lua
local screen = game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen
local ids = { LONG = "<LONG>", ABOUT = "<ABOUT>", GRAD = "<GRAD>" }
local function columnOf(id)
	for _, column in ipairs({ "NewColumn", "AboutToGraduateColumn", "GraduatedColumn" }) do
		if screen.Columns[column].List:FindFirstChild("Card_" .. id) then
			return column
		end
	end
	return "missing"
end
local grad = screen.Columns.GraduatedColumn.List:FindFirstChild("Card_" .. ids.GRAD)
return string.format("long=%s about=%s grad=%s badge=%s buy=%s fresh=%s", columnOf(ids.LONG), columnOf(ids.ABOUT), columnOf(ids.GRAD), tostring(grad and grad.GraduatedBadge.Visible), grad and grad.BuyButton.Text or "-", screen.Header.FreshnessLabel.Text)
```

- [ ] **Step 2: Run it and confirm it fails**

`start_stop_play(true)`, wait about 5 s, click `…TopBar.TabContainer.PulseButton`, then run Step 1 with any ids.

Expected: the error `Columns is not a valid member of Frame "…PulseScreen"`.

Run **H5** `RESTORE`, then `start_stop_play(false)`.

- [ ] **Step 3: Write `PulseUI.luau`**

```lua
-- PulseUI.luau
--
-- Small builders for the Pulse screen's code-made UI. Every color, font and
-- size comes from Theme tokens, so the palette audit (H2) holds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)

local PulseUI = {}

local HOVER_TWEEN = TweenInfo.new(0.12)
local LIST_GAP = 6
local LIST_PADDING = 8
local SCROLLBAR_THICKNESS = 4

local hoverTweens = setmetatable({}, { __mode = "k" })

function PulseUI.corner(parent)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Radius
	corner.Parent = parent

	return corner
end

function PulseUI.stroke(parent)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Border
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent

	return stroke
end

-- Shared placement props. `color` is a fill; without one the element is
-- transparent
local function place(instance, props)
	instance.Name = props.name
	instance.BorderSizePixel = 0
	instance.Position = props.position or UDim2.new()
	instance.Size = props.size or UDim2.fromScale(1, 1)
	instance.AnchorPoint = props.anchor or Vector2.zero
	instance.ZIndex = props.z or 1
	instance.BackgroundTransparency = props.color and 0 or 1

	if props.color then
		instance.BackgroundColor3 = props.color
	end

	instance.Parent = props.parent

	return instance
end

local function setText(instance, props, defaultFont, defaultAlign)
	instance.Text = props.text or ""
	instance.TextColor3 = props.textColor or Theme.Colors.Text
	instance.FontFace = props.font or defaultFont
	instance.TextSize = props.textSize or Theme.TextSize.Body
	instance.TextXAlignment = props.alignX or defaultAlign
	instance.TextYAlignment = Enum.TextYAlignment.Center
end

function PulseUI.frame(props)
	return place(Instance.new("Frame"), props)
end

-- Labels end in "…" rather than overflow: names and numbers can be long
function PulseUI.label(props)
	local label = Instance.new("TextLabel")
	setText(label, props, Theme.Fonts.UI, Enum.TextXAlignment.Left)
	label.TextTruncate = Enum.TextTruncate.AtEnd

	return place(label, props)
end

-- Buttons don't truncate: a clipped button label is a bug the audit catches
function PulseUI.button(props)
	local button = Instance.new("TextButton")
	setText(button, props, Theme.Fonts.UISemibold, Enum.TextXAlignment.Center)
	button.AutoButtonColor = false
	place(button, props)
	PulseUI.corner(button)

	return button
end

-- A vertical list that grows with its content
function PulseUI.scroller(props)
	local scroller = Instance.new("ScrollingFrame")
	scroller.ScrollBarThickness = SCROLLBAR_THICKNESS
	scroller.ScrollBarImageColor3 = Theme.Colors.TextDisabled
	scroller.ScrollingDirection = Enum.ScrollingDirection.Y
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	place(scroller, props)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, LIST_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroller

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, LIST_PADDING)
	padding.PaddingRight = UDim.new(0, LIST_PADDING)
	padding.PaddingTop = UDim.new(0, LIST_PADDING)
	padding.PaddingBottom = UDim.new(0, LIST_PADDING)
	padding.Parent = scroller

	return scroller
end

-- Hover tints only enabled buttons
function PulseUI.hover(button, baseColor, hoverColor)
	local function tweenTo(color)
		if button:GetAttribute("Enabled") == false then
			return
		end

		local tween = TweenService:Create(button, HOVER_TWEEN, { BackgroundColor3 = color })
		hoverTweens[button] = tween
		tween:Play()
	end

	button.MouseEnter:Connect(function()
		tweenTo(hoverColor)
	end)

	button.MouseLeave:Connect(function()
		tweenTo(baseColor)
	end)
end

-- Disabled buttons show Raised with TextDisabled text and ignore clicks (see
-- onClick). Acts only on a change, so it's cheap to call every refresh
function PulseUI.setEnabled(button, enabled, color, textColor)
	if button:GetAttribute("Enabled") == enabled then
		return
	end

	button:SetAttribute("Enabled", enabled)

	-- A hover tween still playing would paint over the new color
	if hoverTweens[button] then
		hoverTweens[button]:Cancel()
		hoverTweens[button] = nil
	end

	button.BackgroundColor3 = enabled and color or Theme.Colors.Raised
	button.TextColor3 = enabled and textColor or Theme.Colors.TextDisabled
end

-- Clicks on a disabled button are dropped here rather than relying on
-- Active, which doesn't stop MouseButton1Click
function PulseUI.onClick(button, callback)
	button.MouseButton1Click:Connect(function()
		if button:GetAttribute("Enabled") ~= false then
			callback()
		end
	end)
end

return PulseUI
```

- [ ] **Step 4: Write `CoinCard.luau`**

```lua
-- CoinCard.luau
--
-- One Pulse card: the coin's tile, ticker, name and age, market cap and
-- volume, graduation progress (or a Graduated badge), and a one-click Buy
-- for the header's quick-buy amount. Cards are reused across refreshes and
-- move between columns as their coin grows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local CoinFormat = require(ReplicatedStorage.Modules.Coins.CoinFormat)
local PulseUI = require(script.Parent.PulseUI)

local CoinCard = {}
CoinCard.__index = CoinCard

local CARD_HEIGHT = 100
local TILE_SIZE = 36
local TEXT_LEFT = 52
local BUY_WIDTH = 84
local BUY_HEIGHT = 26
local EDGE = 8

-- The same id gives the same color in every server and client
function CoinCard.tileColor(coinId)
	local hash = 0

	for index = 1, #coinId do
		hash = (hash * 31 + string.byte(coinId, index)) % 1000003
	end

	return Theme.TileColors[hash % #Theme.TileColors + 1]
end

-- Named CoinTile: the palette audit exempts identity colors by this name
function CoinCard.makeTile(parent, size, coinId, ticker, z)
	local tile = PulseUI.frame({ name = "CoinTile", parent = parent, size = UDim2.fromOffset(size, size), color = CoinCard.tileColor(coinId), z = z })
	PulseUI.corner(tile)

	PulseUI.label({
		name = "Letter",
		parent = tile,
		text = string.sub(ticker, 1, 1),
		textColor = Theme.Colors.Background,
		font = Theme.Fonts.UIBold,
		textSize = size >= 48 and Theme.TextSize.Display or Theme.TextSize.Title,
		alignX = Enum.TextXAlignment.Center,
		z = z,
	})

	return tile
end

-- callbacks: onOpen(coinId), onBuy(coinId)
function CoinCard.new(parent, callbacks)
	local self = setmetatable({}, CoinCard)

	local root = Instance.new("TextButton")
	root.Name = "Card"
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundColor3 = Theme.Colors.Raised
	root.BorderSizePixel = 0
	root.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
	root.Parent = parent
	PulseUI.corner(root)

	-- An outline on hover, so the card reads as clickable
	local outline = PulseUI.stroke(root)

	root.MouseEnter:Connect(function()
		outline.Color = Theme.Colors.TextDisabled
	end)

	root.MouseLeave:Connect(function()
		outline.Color = Theme.Colors.Border
	end)

	local textWidth = UDim2.new(1, -(TEXT_LEFT + EDGE), 0, 16)
	local lowerWidth = UDim2.new(1, -(BUY_WIDTH + 3 * EDGE), 0, 4)

	self.root = root
	self.tileHolder = PulseUI.frame({ name = "TileHolder", parent = root, position = UDim2.fromOffset(EDGE, EDGE), size = UDim2.fromOffset(TILE_SIZE, TILE_SIZE) })
	self.ticker = PulseUI.label({ name = "Ticker", parent = root, position = UDim2.fromOffset(TEXT_LEFT, EDGE), size = textWidth, font = Theme.Fonts.UIBold })
	self.name = PulseUI.label({
		name = "CoinName",
		parent = root,
		position = UDim2.fromOffset(TEXT_LEFT, 26),
		size = UDim2.new(1, -(TEXT_LEFT + EDGE), 0, 14),
		textColor = Theme.Colors.TextMuted,
		textSize = Theme.TextSize.Caption,
	})
	self.stats = PulseUI.label({
		name = "Stats",
		parent = root,
		position = UDim2.fromOffset(EDGE, 48),
		size = UDim2.new(1, -2 * EDGE, 0, 14),
		textColor = Theme.Colors.TextMuted,
		font = Theme.Fonts.Mono,
		textSize = Theme.TextSize.Caption,
	})

	self.track = PulseUI.frame({
		name = "ProgressTrack",
		parent = root,
		position = UDim2.new(0, EDGE, 1, -(EDGE + BUY_HEIGHT / 2 + 2)),
		size = lowerWidth,
		color = Theme.Colors.Border,
	})
	PulseUI.corner(self.track)
	self.fill = PulseUI.frame({ name = "ProgressFill", parent = self.track, size = UDim2.fromScale(0, 1), color = Theme.Colors.Accent })
	PulseUI.corner(self.fill)

	self.badge = PulseUI.label({
		name = "GraduatedBadge",
		parent = root,
		position = UDim2.new(0, EDGE, 1, -(EDGE + BUY_HEIGHT)),
		size = UDim2.new(1, -(BUY_WIDTH + 3 * EDGE), 0, BUY_HEIGHT),
		text = "Graduated",
		textColor = Theme.Colors.Accent,
		font = Theme.Fonts.UISemibold,
		textSize = Theme.TextSize.Caption,
	})
	self.badge.Visible = false

	self.buy = PulseUI.button({
		name = "BuyButton",
		parent = root,
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -EDGE, 1, -EDGE),
		size = UDim2.fromOffset(BUY_WIDTH, BUY_HEIGHT),
		color = Theme.Colors.Up,
		textColor = Theme.Colors.Background,
		font = Theme.Fonts.UIBold,
	})
	PulseUI.hover(self.buy, Theme.Colors.Up, Theme.Colors.UpHover)

	root.MouseButton1Click:Connect(function()
		if self.coinId then
			callbacks.onOpen(self.coinId)
		end
	end)

	PulseUI.onClick(self.buy, function()
		if self.coinId then
			callbacks.onBuy(self.coinId)
		end
	end)

	return self
end

function CoinCard:update(summary, quickBuy, now)
	if self.coinId ~= summary.id then
		self.coinId = summary.id
		self.root.Name = "Card_" .. summary.id
		self.tileHolder:ClearAllChildren()
		CoinCard.makeTile(self.tileHolder, TILE_SIZE, summary.id, summary.ticker, 1)
	end

	-- The ticker can change when names are re-filtered
	self.tileHolder.CoinTile.Letter.Text = string.sub(summary.ticker, 1, 1)
	self.ticker.Text = "$" .. summary.ticker
	self.name.Text = summary.name .. " · " .. CoinFormat.age(now - summary.createdAt)
	self.stats.Text = "MC " .. NumberModule.formatCompact(summary.marketCap) .. "  Vol " .. NumberModule.formatCompact(summary.volume)
	self.fill.Size = UDim2.fromScale(summary.progress, 1)
	self.track.Visible = not summary.graduated
	self.badge.Visible = summary.graduated
	self.buy.Text = "Buy " .. CoinFormat.preset(quickBuy)
end

function CoinCard:setEnabled(enabled)
	PulseUI.setEnabled(self.buy, enabled, Theme.Colors.Up, Theme.Colors.Background)
end

function CoinCard:destroy()
	self.root:Destroy()
end

return CoinCard
```

- [ ] **Step 5: Write `Sparkline.luau`**

```lua
-- Sparkline.luau
--
-- The house line chart: one continuous line of rotated 2px segments with a
-- violet gradient, as in the Trade screen's mini chart. Draws into `frame`,
-- replacing the line that was there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)

local Sparkline = {}

local LINE_THICKNESS = 2

local function colorAt(x)
	return Theme.Colors.AccentSoft:Lerp(Theme.Colors.Accent, x)
end

-- Returns the number of segments drawn. The frame must be on screen: the
-- segments are sized from its AbsoluteSize
function Sparkline.draw(frame, values, z)
	for _, child in ipairs(frame:GetChildren()) do
		if string.sub(child.Name, 1, 4) == "Seg_" then
			child:Destroy()
		end
	end

	-- One point is still a price: draw it flat
	if #values == 1 then
		values = { values[1], values[1] }
	end

	local count = #values

	if count < 2 then
		return 0
	end

	local low, high = math.huge, -math.huge

	for _, value in ipairs(values) do
		low = math.min(low, value)
		high = math.max(high, value)
	end

	local range = high - low
	local width = math.max(frame.AbsoluteSize.X, 1)
	local height = math.max(frame.AbsoluteSize.Y, 1)

	-- A flat series runs through the middle rather than along an edge
	local function yOf(value)
		return range > 0 and 1 - (value - low) / range or 0.5
	end

	for i = 1, count - 1 do
		local x1, x2 = (i - 1) / (count - 1), i / (count - 1)
		local y1, y2 = yOf(values[i]), yOf(values[i + 1])
		local dx, dy = (x2 - x1) * width, (y2 - y1) * height

		local segment = Instance.new("Frame")
		segment.Name = "Seg_" .. i
		segment.BackgroundColor3 = Color3.new(1, 1, 1)
		segment.BorderSizePixel = 0
		segment.ZIndex = z or 1
		segment.AnchorPoint = Vector2.new(0.5, 0.5)
		segment.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), LINE_THICKNESS)
		segment.Rotation = math.deg(math.atan2(dy, dx))
		segment.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(colorAt(x1), colorAt(x2))
		gradient.Parent = segment

		segment.Parent = frame
	end

	return count - 1
end

return Sparkline
```

- [ ] **Step 6: Write `CoinPanel.luau`**

```lua
-- CoinPanel.luau
--
-- The coin panel on the right of the Pulse screen: identity, stats, a
-- 60-minute sparkline, one-click buy and sell presets, and the player's
-- position. Shows a detail table from GetCoinEvent or an order result.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local CoinConfig = require(ReplicatedStorage.Modules.Coins.CoinConfig)
local CoinFormat = require(ReplicatedStorage.Modules.Coins.CoinFormat)
local CoinState = require(ReplicatedStorage.Modules.Coins.CoinState)
local PulseUI = require(script.Parent.PulseUI)
local CoinCard = require(script.Parent.CoinCard)
local Sparkline = require(script.Parent.Sparkline)

local CoinPanel = {}
CoinPanel.__index = CoinPanel

local PANEL_WIDTH = 320
local PANEL_Z = 10 -- over the columns
local EDGE = 12
local TILE_SIZE = 48
local TEXT_LEFT = EDGE + TILE_SIZE + 12
local STAT_TOP = 92
local STAT_ROW = 40
local CHART_TOP = 224
local CHART_HEIGHT = 64
local BUY_TOP = 298
local SELL_TOP = 352
local POSITION_TOP = 404
local PRESET_HEIGHT = 28
local PRESET_GAP = 6

local STATS = {
	{ key = "MarketCap", caption = "Market cap" },
	{ key = "Price", caption = "Price" },
	{ key = "Volume", caption = "Volume" },
	{ key = "Trades", caption = "Trades" },
	{ key = "CreatorShare", caption = "Creator holds" },
	{ key = "Progress", caption = "Progress" },
}

-- callbacks: onBuy(coinId, dollars), onSell(coinId, fraction)
function CoinPanel.new(parent, top, callbacks)
	local self = setmetatable({ callbacks = callbacks, ordersEnabled = true, buyButtons = {}, sellButtons = {}, values = {} }, CoinPanel)
	local z = PANEL_Z + 1
	local fullWidth = UDim2.new(1, -2 * EDGE, 0, 14)

	local root = Instance.new("ScrollingFrame")
	root.Name = "CoinPanel"
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -8, 0, top)
	root.Size = UDim2.new(0, PANEL_WIDTH, 1, -(top + 8))
	root.BackgroundColor3 = Theme.Colors.Panel
	root.BorderSizePixel = 0
	root.ScrollBarThickness = 4
	root.ScrollBarImageColor3 = Theme.Colors.TextDisabled
	root.ScrollingDirection = Enum.ScrollingDirection.Y
	root.CanvasSize = UDim2.new()
	root.AutomaticCanvasSize = Enum.AutomaticSize.Y
	root.ZIndex = PANEL_Z
	root.Visible = false
	root.Parent = parent
	PulseUI.corner(root)
	PulseUI.stroke(root)
	self.root = root

	self.tileHolder = PulseUI.frame({ name = "TileHolder", parent = root, position = UDim2.fromOffset(EDGE, EDGE), size = UDim2.fromOffset(TILE_SIZE, TILE_SIZE), z = z })
	self.ticker = PulseUI.label({
		name = "Ticker",
		parent = root,
		position = UDim2.fromOffset(TEXT_LEFT, EDGE),
		size = UDim2.new(1, -(TEXT_LEFT + 40), 0, 20),
		font = Theme.Fonts.UIBold,
		textSize = Theme.TextSize.Title,
		z = z,
	})

	local function muted(name, y, text, color, font)
		return PulseUI.label({
			name = name,
			parent = root,
			position = UDim2.fromOffset(TEXT_LEFT, y),
			size = UDim2.new(1, -(TEXT_LEFT + EDGE), 0, 14),
			text = text,
			textColor = color or Theme.Colors.TextMuted,
			font = font,
			textSize = Theme.TextSize.Caption,
			z = z,
		})
	end

	self.name = muted("CoinName", 34)
	self.meta = muted("Meta", 50)
	self.badge = muted("GraduatedBadge", 66, "Graduated", Theme.Colors.Accent, Theme.Fonts.UISemibold)

	local close = PulseUI.button({
		name = "CloseButton",
		parent = root,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -8, 0, 8),
		size = UDim2.fromOffset(24, 24),
		text = "×",
		textColor = Theme.Colors.TextMuted,
		textSize = Theme.TextSize.Title,
		z = z,
	})

	close.MouseButton1Click:Connect(function()
		self:hide()
	end)

	for index, stat in ipairs(STATS) do
		local column = (index - 1) % 2
		local row = math.floor((index - 1) / 2)
		local cell = PulseUI.frame({
			name = stat.key,
			parent = root,
			position = UDim2.new(column * 0.5, column == 0 and EDGE or 4, 0, STAT_TOP + row * STAT_ROW),
			size = UDim2.new(0.5, -(EDGE + 4), 0, 36),
			z = z,
		})

		PulseUI.label({ name = "Caption", parent = cell, size = UDim2.new(1, 0, 0, 14), text = stat.caption, textColor = Theme.Colors.TextMuted, textSize = Theme.TextSize.Caption, z = z })
		self.values[stat.key] = PulseUI.label({ name = "Value", parent = cell, position = UDim2.fromOffset(0, 16), size = UDim2.new(1, 0, 0, 18), font = Theme.Fonts.Mono, z = z })
	end

	self.track = PulseUI.frame({ name = "ProgressTrack", parent = root, position = UDim2.fromOffset(EDGE, STAT_TOP + 3 * STAT_ROW - 2), size = UDim2.new(1, -2 * EDGE, 0, 4), color = Theme.Colors.Border, z = z })
	PulseUI.corner(self.track)
	self.fill = PulseUI.frame({ name = "ProgressFill", parent = self.track, size = UDim2.fromScale(0, 1), color = Theme.Colors.Accent, z = z })
	PulseUI.corner(self.fill)

	self.chart = PulseUI.frame({ name = "Chart", parent = root, position = UDim2.fromOffset(EDGE, CHART_TOP), size = UDim2.new(1, -2 * EDGE, 0, CHART_HEIGHT), z = z })

	local presetSize = UDim2.new(0.25, -PRESET_GAP * 3 / 4, 1, 0)

	local function presetRow(name, caption, y)
		PulseUI.label({ name = name .. "Caption", parent = root, position = UDim2.fromOffset(EDGE, y), size = fullWidth, text = caption, textColor = Theme.Colors.TextMuted, textSize = Theme.TextSize.Caption, z = z })

		local row = PulseUI.frame({ name = name, parent = root, position = UDim2.fromOffset(EDGE, y + 16), size = UDim2.new(1, -2 * EDGE, 0, PRESET_HEIGHT), z = z })
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, PRESET_GAP)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = row

		return row
	end

	local function preset(row, name, text, color, hoverColor, onClick, order)
		local button = PulseUI.button({ name = name, parent = row, size = presetSize, text = text, color = color, textColor = Theme.Colors.Background, font = Theme.Fonts.Mono, z = z })
		button.LayoutOrder = order
		PulseUI.hover(button, color, hoverColor)
		PulseUI.onClick(button, function()
			-- The coin on screen, even if another is still loading
			if self.detail then
				onClick(self.detail.id)
			end
		end)

		return button
	end

	local buyRow = presetRow("BuyPresets", "Buy", BUY_TOP)

	for index, dollars in ipairs(CoinConfig.BUY_PRESETS) do
		table.insert(self.buyButtons, preset(buyRow, "Buy_" .. dollars, CoinFormat.preset(dollars), Theme.Colors.Up, Theme.Colors.UpHover, function(coinId)
			self.callbacks.onBuy(coinId, dollars)
		end, index))
	end

	local sellRow = presetRow("SellPresets", "Sell", SELL_TOP)

	for index, fraction in ipairs(CoinConfig.SELL_PRESETS) do
		local percent = math.floor(fraction * 100 + 0.5)

		table.insert(self.sellButtons, preset(sellRow, "Sell_" .. percent, percent .. "%", Theme.Colors.Down, Theme.Colors.DownHover, function(coinId)
			self.callbacks.onSell(coinId, fraction)
		end, index))
	end

	local function line(name, y)
		return PulseUI.label({ name = name, parent = root, position = UDim2.fromOffset(EDGE, y), size = UDim2.new(1, -2 * EDGE, 0, 16), font = Theme.Fonts.Mono, textSize = Theme.TextSize.Caption, z = z })
	end

	self.positionLabel = line("Position", POSITION_TOP)
	self.pnl = line("PnL", POSITION_TOP + 18)
	self.archivedNote = PulseUI.label({
		name = "ArchivedNote",
		parent = root,
		position = UDim2.fromOffset(EDGE, POSITION_TOP + 40),
		size = fullWidth,
		text = "Archived: trading brings it back to Pulse",
		textColor = Theme.Colors.TextMuted,
		textSize = Theme.TextSize.Caption,
		z = z,
	})
	-- Room below the last line when the panel scrolls
	PulseUI.frame({ name = "BottomSpacer", parent = root, position = UDim2.fromOffset(0, POSITION_TOP + 54), size = UDim2.new(1, 0, 0, 12), z = z })

	return self
end

-- Which coin to load next; the panel keeps showing the current one until
-- show() is called with the new detail
function CoinPanel:select(coinId)
	self.coinId = coinId
end

function CoinPanel:show(detail, now)
	self.coinId = detail.id
	self.detail = detail
	-- Visible first: the sparkline measures the chart's on-screen size
	self.root.Visible = true

	if self.tileId ~= detail.id then
		self.tileId = detail.id
		self.tileHolder:ClearAllChildren()
		CoinCard.makeTile(self.tileHolder, TILE_SIZE, detail.id, detail.ticker, PANEL_Z + 1)
	end

	self.ticker.Text = "$" .. detail.ticker
	self.name.Text = detail.name
	self.meta.Text = "by " .. detail.creatorName .. " · " .. CoinFormat.age(now - detail.createdAt)
	self.badge.Visible = detail.graduated

	self.values.MarketCap.Text = NumberModule.formatCompact(detail.marketCap)
	self.values.Price.Text = CoinFormat.price(detail.price)
	self.values.Volume.Text = NumberModule.formatCompact(detail.volume)
	self.values.Trades.Text = NumberModule.formatShares(detail.trades)
	self.values.CreatorShare.Text = string.format("%.1f%%", detail.creatorShare * 100)
	self.values.Progress.Text = detail.graduated and "Graduated" or string.format("%d%%", math.floor(detail.progress * 100))
	self.fill.Size = UDim2.fromScale(detail.progress, 1)

	Sparkline.draw(self.chart, CoinState.pointsAsOf(detail.points, detail.pointsMinute, now), PANEL_Z + 1)

	local position = detail.position

	if position.tokens > 0 then
		local sign = position.pnl >= 0 and "+" or "-"
		local percent = position.cost > 0 and math.abs(position.pnl) / position.cost * 100 or 0

		self.positionLabel.Text = "Position " .. CoinFormat.tokens(position.tokens) .. " · " .. NumberModule.format(position.value)
		self.pnl.Text = string.format("P&L %s%s (%s%.1f%%)", sign, NumberModule.format(math.abs(position.pnl)), sign, percent)
		self.pnl.TextColor3 = position.pnl >= 0 and Theme.Colors.Up or Theme.Colors.Down
	else
		self.positionLabel.Text = "No position"
		self.pnl.Text = ""
	end

	self.positionLabel.TextColor3 = Theme.Colors.Text
	self.archivedNote.Visible = detail.archived
	self:applyEnabled()
end

function CoinPanel:hide()
	self.root.Visible = false
	self.coinId = nil
	self.detail = nil
end

-- Orders are off while one is in flight or the store can't be reached
function CoinPanel:setEnabled(enabled)
	self.ordersEnabled = enabled
	self:applyEnabled()
end

function CoinPanel:applyEnabled()
	local holds = self.detail ~= nil and self.detail.position.tokens > 0

	for _, button in ipairs(self.buyButtons) do
		PulseUI.setEnabled(button, self.ordersEnabled, Theme.Colors.Up, Theme.Colors.Background)
	end

	for _, button in ipairs(self.sellButtons) do
		PulseUI.setEnabled(button, self.ordersEnabled and holds, Theme.Colors.Down, Theme.Colors.Background)
	end
end

return CoinPanel
```

- [ ] **Step 7: Replace `PulseController.client.luau` with the full screen**

```lua
-- PulseController.client.luau
--
-- The Pulse tab: player-launched coins in New / About to graduate /
-- Graduated columns with one-click quick-buy, a coin panel, and a My coins
-- list. Built entirely in code from Theme tokens; nothing for Pulse lives
-- in the Studio place. TerminalController switches to it like any other
-- tab. The server computes every number; this only shows them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local CoinConfig = require(ReplicatedStorage.Modules.Coins.CoinConfig)
local CoinFormat = require(ReplicatedStorage.Modules.Coins.CoinFormat)
local PulseUI = require(ReplicatedStorage.Modules.Pulse.PulseUI)
local CoinCard = require(ReplicatedStorage.Modules.Pulse.CoinCard)
local CoinPanel = require(ReplicatedStorage.Modules.Pulse.CoinPanel)

local EventsFolder = ReplicatedStorage:WaitForChild("EventsFolder")
local GetPulseEvent = EventsFolder:WaitForChild("GetPulseEvent")
local GetCoinEvent = EventsFolder:WaitForChild("GetCoinEvent")
local GetMyCoinsEvent = EventsFolder:WaitForChild("GetMyCoinsEvent")
local CoinOrderEvent = EventsFolder:WaitForChild("CoinOrderEvent")

local Player = Players.LocalPlayer
local MainBackground = Player:WaitForChild("PlayerGui"):WaitForChild("TerminalGui"):WaitForChild("MainBackground")
local TabContainer = MainBackground:WaitForChild("TopBar"):WaitForChild("TabContainer")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")

-- Layout Constants
local HEADER_HEIGHT = 72
local EDGE = 12
local COLUMN_GAP = 8
local PICKER_PILL_WIDTH = 48
local PILL_HEIGHT = 24
local BUTTON_HEIGHT = 28
local TOGGLE_WIDTH = 88
local LAUNCH_WIDTH = 104 -- the Launch button (Task 7) sits right of the toggle
local FRESHNESS_WIDTH = 140
local ROW_HEIGHT = 44

-- Timing
local POLL_INTERVAL = 5
local MY_COINS_INTERVAL = 30 -- archived rows cost store reads

local UNAVAILABLE_MESSAGE = "Coins unavailable, retrying…"

local COLUMNS = {
	{ key = "New", title = "New" },
	{ key = "AboutToGraduate", title = "About to graduate" },
	{ key = "Graduated", title = "Graduated" },
}

-- Styled like the Studio-made tabs (Tab role); TerminalController owns the
-- active/inactive text color
local PulseButton = Instance.new("TextButton")
PulseButton.Name = "PulseButton"
PulseButton.Text = "Pulse"
PulseButton.FontFace = Theme.Fonts.UISemibold
PulseButton.TextSize = Theme.TextSize.Body
PulseButton.TextColor3 = Theme.Colors.TextMuted
PulseButton.BackgroundTransparency = 1
PulseButton.BorderSizePixel = 0
PulseButton.AutoButtonColor = false
PulseButton.Size = UDim2.new(0, 0, 1, 0)
PulseButton.Parent = TabContainer

local PulseScreen = Instance.new("Frame")
PulseScreen.Name = "PulseScreen"
PulseScreen.Size = UDim2.fromScale(1, 1)
PulseScreen.BackgroundColor3 = Theme.Colors.Background
PulseScreen.BorderSizePixel = 0
PulseScreen.Visible = false
PulseScreen.Parent = ScreenContainer

-- Header: title, quick-buy amount, My coins, status and freshness
local Header = PulseUI.frame({ name = "Header", parent = PulseScreen, size = UDim2.new(1, 0, 0, HEADER_HEIGHT) })

PulseUI.label({ name = "Title", parent = Header, position = UDim2.fromOffset(EDGE, 10), size = UDim2.fromOffset(64, BUTTON_HEIGHT), text = "Pulse", font = Theme.Fonts.UIBold, textSize = Theme.TextSize.Title })

local QuickBuyPicker = PulseUI.frame({ name = "QuickBuyPicker", parent = Header, position = UDim2.fromOffset(88, 10), size = UDim2.fromOffset(280, BUTTON_HEIGHT) })
local pickerLayout = Instance.new("UIListLayout")
pickerLayout.FillDirection = Enum.FillDirection.Horizontal
pickerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
pickerLayout.Padding = UDim.new(0, 6)
pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder
pickerLayout.Parent = QuickBuyPicker

PulseUI.label({ name = "Caption", parent = QuickBuyPicker, size = UDim2.new(0, 60, 1, 0), text = "Quick buy", textColor = Theme.Colors.TextMuted, textSize = Theme.TextSize.Caption })

local pickerButtons = {}

for index, dollars in ipairs(CoinConfig.BUY_PRESETS) do
	local pill = PulseUI.button({
		name = "Amount_" .. dollars,
		parent = QuickBuyPicker,
		size = UDim2.fromOffset(PICKER_PILL_WIDTH, PILL_HEIGHT),
		text = CoinFormat.preset(dollars),
		font = Theme.Fonts.Mono,
		textSize = Theme.TextSize.Caption,
	})
	pill.LayoutOrder = index
	pickerButtons[dollars] = pill
end

local MyCoinsToggle = PulseUI.button({
	name = "MyCoinsToggle",
	parent = Header,
	anchor = Vector2.new(1, 0),
	position = UDim2.new(1, -(EDGE + LAUNCH_WIDTH + 8), 0, 10),
	size = UDim2.fromOffset(TOGGLE_WIDTH, BUTTON_HEIGHT),
	text = "My coins",
	color = Theme.Colors.Raised,
})

local StatusLabel = PulseUI.label({
	name = "StatusLabel",
	parent = Header,
	position = UDim2.fromOffset(EDGE, 44),
	size = UDim2.new(1, -(2 * EDGE + FRESHNESS_WIDTH), 0, 18),
	textColor = Theme.Colors.TextMuted,
	textSize = Theme.TextSize.Caption,
})

local FreshnessLabel = PulseUI.label({
	name = "FreshnessLabel",
	parent = Header,
	anchor = Vector2.new(1, 0),
	position = UDim2.new(1, -EDGE, 0, 44),
	size = UDim2.fromOffset(FRESHNESS_WIDTH, 18),
	text = "Loading coins…",
	textColor = Theme.Colors.TextMuted,
	textSize = Theme.TextSize.Caption,
	alignX = Enum.TextXAlignment.Right,
})

-- A titled panel with a scrolling list and an empty-state line
local function makeListPanel(name, parent, size, title, emptyText)
	local panel = PulseUI.frame({ name = name, parent = parent, size = size, color = Theme.Colors.Panel })
	PulseUI.corner(panel)
	PulseUI.stroke(panel)

	PulseUI.label({ name = "Title", parent = panel, position = UDim2.fromOffset(10, 6), size = UDim2.new(1, -60, 0, 20), text = title, font = Theme.Fonts.UISemibold })

	local count = PulseUI.label({
		name = "Count",
		parent = panel,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -10, 0, 6),
		size = UDim2.fromOffset(40, 20),
		textColor = Theme.Colors.TextMuted,
		font = Theme.Fonts.Mono,
		textSize = Theme.TextSize.Caption,
		alignX = Enum.TextXAlignment.Right,
	})

	local list = PulseUI.scroller({ name = "List", parent = panel, position = UDim2.fromOffset(0, 30), size = UDim2.new(1, 0, 1, -30) })

	local empty = PulseUI.label({
		name = "EmptyLabel",
		parent = panel,
		position = UDim2.fromOffset(0, 30),
		size = UDim2.new(1, 0, 0, 40),
		text = emptyText,
		textColor = Theme.Colors.TextMuted,
		textSize = Theme.TextSize.Caption,
		alignX = Enum.TextXAlignment.Center,
	})

	return { panel = panel, list = list, count = count, empty = empty }
end

local ColumnsView = PulseUI.frame({ name = "Columns", parent = PulseScreen, position = UDim2.fromOffset(0, HEADER_HEIGHT), size = UDim2.new(1, 0, 1, -HEADER_HEIGHT) })
local columnsLayout = Instance.new("UIListLayout")
columnsLayout.FillDirection = Enum.FillDirection.Horizontal
columnsLayout.Padding = UDim.new(0, COLUMN_GAP)
columnsLayout.SortOrder = Enum.SortOrder.LayoutOrder
columnsLayout.Parent = ColumnsView
local columnsPadding = Instance.new("UIPadding")
columnsPadding.PaddingLeft = UDim.new(0, COLUMN_GAP)
columnsPadding.PaddingRight = UDim.new(0, COLUMN_GAP)
columnsPadding.PaddingBottom = UDim.new(0, COLUMN_GAP)
columnsPadding.Parent = ColumnsView

local ColumnViews = {}

for index, column in ipairs(COLUMNS) do
	local view = makeListPanel(column.key .. "Column", ColumnsView, UDim2.new(1 / 3, -COLUMN_GAP * 2 / 3, 1, 0), column.title, "No coins yet. Launch one.")
	view.panel.LayoutOrder = index
	ColumnViews[column.key] = view
end

local MyCoinsView = makeListPanel("MyCoinsView", PulseScreen, UDim2.new(1, -2 * COLUMN_GAP, 1, -(HEADER_HEIGHT + COLUMN_GAP)), "My coins", "You don't hold any coins yet.")
MyCoinsView.panel.Position = UDim2.fromOffset(COLUMN_GAP, HEADER_HEIGHT)
MyCoinsView.panel.Visible = false

-- State
local quickBuy = CoinConfig.DEFAULT_QUICK_BUY
local showingMyCoins = false
local orderInFlight = false
local storeOk = true
local lastPulse = nil -- the last GetPulseEvent result
local serverOffset = 0 -- the server's clock minus this one
local cards = {} -- coinId -> CoinCard
local lastMyCoinsAt = -math.huge

local placeOrder, openPanel -- defined below; cards and the panel call them

local Panel = CoinPanel.new(PulseScreen, HEADER_HEIGHT, {
	onBuy = function(coinId, dollars)
		placeOrder("Buy", coinId, dollars)
	end,
	onSell = function(coinId, fraction)
		placeOrder("Sell", coinId, fraction)
	end,
})

local cardCallbacks = {
	onOpen = function(coinId)
		openPanel(coinId)
	end,
	onBuy = function(coinId)
		placeOrder("Buy", coinId, quickBuy)
	end,
}

-- Ages use the server's clock, so a client clock that's off can't make a
-- coin look older or newer than it is
local function serverNow()
	return os.time() + serverOffset
end

local function noteServerTime(serverTime)
	if typeof(serverTime) == "number" then
		serverOffset = serverTime - os.time()
	end
end

local function setStatus(text, color)
	StatusLabel.Text = text
	StatusLabel.TextColor3 = color or Theme.Colors.TextMuted
end

local function updateFreshness()
	if not lastPulse or lastPulse.updatedAt == 0 then
		FreshnessLabel.Text = "Loading coins…"
	else
		FreshnessLabel.Text = "Updated " .. CoinFormat.age(serverNow() - lastPulse.updatedAt) .. " ago"
	end
end

-- Every order button is off while an order is in flight (one click, one
-- order) or while the server can't reach the coin store
local function applyEnabled()
	local enabled = storeOk and not orderInFlight

	for _, card in pairs(cards) do
		card:setEnabled(enabled)
	end

	Panel:setEnabled(enabled)
end

local function setStoreOk(ok)
	storeOk = ok

	if not ok then
		setStatus(UNAVAILABLE_MESSAGE, Theme.Colors.Down)
	elseif StatusLabel.Text == UNAVAILABLE_MESSAGE then
		setStatus("")
	end

	applyEnabled()
end

local function renderColumns(columns)
	local now = serverNow()
	local enabled = storeOk and not orderInFlight
	local shown = {}

	for _, column in ipairs(COLUMNS) do
		local view = ColumnViews[column.key]
		local summaries = columns[column.key] or {}

		for index, summary in ipairs(summaries) do
			local card = cards[summary.id]

			if not card then
				card = CoinCard.new(view.list, cardCallbacks)
				cards[summary.id] = card
			end

			-- A coin moves between columns as it grows
			card.root.Parent = view.list
			card.root.LayoutOrder = index
			card:update(summary, quickBuy, now)
			card:setEnabled(enabled)
			shown[summary.id] = true
		end

		view.count.Text = tostring(#summaries)
		view.empty.Visible = #summaries == 0
	end

	for coinId, card in pairs(cards) do
		if not shown[coinId] then
			card:destroy()
			cards[coinId] = nil
		end
	end
end

local function refresh()
	local ok, result = pcall(GetPulseEvent.InvokeServer, GetPulseEvent)

	-- Throttled, or a network blip: keep what's on screen
	if not ok or type(result) ~= "table" then
		return
	end

	noteServerTime(result.serverTime)
	lastPulse = result
	renderColumns(result.columns)
	setStoreOk(result.ok)
	updateFreshness()
end

-- True when the server answered
local function refreshPanel()
	local coinId = Panel.coinId

	if not coinId then
		return true
	end

	local ok, result = pcall(GetCoinEvent.InvokeServer, GetCoinEvent, coinId)

	if not ok or type(result) ~= "table" then
		return false
	end

	-- The player may have opened another coin or closed the panel meanwhile
	if Panel.coinId ~= coinId then
		return true
	end

	if result.success then
		noteServerTime(result.serverTime)
		Panel:show(result.coin, serverNow())
	else
		setStatus(result.message, Theme.Colors.Down)

		-- Keep retrying only when the store is down
		if result.message ~= UNAVAILABLE_MESSAGE then
			Panel:hide()
		end
	end

	return true
end

openPanel = function(coinId)
	Panel:select(coinId)

	-- A second open within the remote's cooldown gets no answer; try once more
	if not refreshPanel() then
		task.delay(0.6, refreshPanel)
	end
end

local function makeRow(row, index)
	local button = Instance.new("TextButton")
	button.Name = "Row_" .. row.id
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = Theme.Colors.Raised
	button.BorderSizePixel = 0
	button.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	button.LayoutOrder = index
	PulseUI.corner(button)

	local tileHolder = PulseUI.frame({ name = "TileHolder", parent = button, position = UDim2.fromOffset(8, 8), size = UDim2.fromOffset(28, 28) })
	CoinCard.makeTile(tileHolder, 28, row.id, row.ticker, 1)

	local holds = row.position.tokens > 0

	PulseUI.label({ name = "Ticker", parent = button, position = UDim2.fromOffset(44, 5), size = UDim2.new(0.5, -44, 0, 16), text = "$" .. row.ticker, font = Theme.Fonts.UIBold })
	PulseUI.label({ name = "CoinName", parent = button, position = UDim2.fromOffset(44, 23), size = UDim2.new(0.5, -110, 0, 14), text = row.name, textColor = Theme.Colors.TextMuted, textSize = Theme.TextSize.Caption })

	local archivedTag = PulseUI.label({ name = "ArchivedTag", parent = button, position = UDim2.new(0.5, -62, 0, 23), size = UDim2.fromOffset(56, 14), text = "Archived", textColor = Theme.Colors.TextMuted, textSize = Theme.TextSize.Caption })
	archivedTag.Visible = row.archived

	PulseUI.label({
		name = "Value",
		parent = button,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -10, 0, 5),
		size = UDim2.new(0.5, -10, 0, 16),
		text = holds and NumberModule.format(row.position.value) or "No position",
		font = Theme.Fonts.Mono,
		alignX = Enum.TextXAlignment.Right,
	})
	PulseUI.label({
		name = "Holding",
		parent = button,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -10, 0, 23),
		size = UDim2.new(0.5, -10, 0, 14),
		text = holds and (CoinFormat.tokens(row.position.tokens) .. " tokens") or "Launched by you",
		textColor = Theme.Colors.TextMuted,
		font = Theme.Fonts.Mono,
		textSize = Theme.TextSize.Caption,
		alignX = Enum.TextXAlignment.Right,
	})

	-- Archived coins open the panel too, so anything held can be sold
	button.MouseButton1Click:Connect(function()
		openPanel(row.id)
	end)

	button.Parent = MyCoinsView.list
end

local function renderMyCoins(rows)
	for _, child in ipairs(MyCoinsView.list:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end

	for index, row in ipairs(rows) do
		makeRow(row, index)
	end

	MyCoinsView.count.Text = tostring(#rows)
	MyCoinsView.empty.Visible = #rows == 0
end

local function refreshMyCoins()
	lastMyCoinsAt = os.clock()

	local ok, result = pcall(GetMyCoinsEvent.InvokeServer, GetMyCoinsEvent)

	if not ok or type(result) ~= "table" then
		return
	end

	if result.success then
		noteServerTime(result.serverTime)
		renderMyCoins(result.rows)
	else
		setStatus(result.message, Theme.Colors.Down)
	end
end

local function refreshVisible()
	if showingMyCoins then
		refreshMyCoins()
	end

	refresh()

	if Panel.coinId then
		refreshPanel()
	end
end

local function setOrderInFlight(inFlight)
	orderInFlight = inFlight
	applyEnabled()
end

placeOrder = function(action, coinId, amount)
	if orderInFlight then
		return
	end

	setOrderInFlight(true)
	local ok, result = pcall(CoinOrderEvent.InvokeServer, CoinOrderEvent, action, coinId, amount)
	setOrderInFlight(false)

	if not ok or type(result) ~= "table" then
		setStatus("Order failed, try again.", Theme.Colors.Down)
		return
	end

	setStatus(result.message, result.success and Theme.Colors.Text or Theme.Colors.Down)

	-- The result carries the coin as the order left it
	if result.success and result.coin and Panel.coinId == result.coin.id then
		Panel:show(result.coin, serverNow())
	end

	if result.success then
		task.spawn(refreshVisible)
	end
end

local function updatePicker()
	for dollars, pill in pairs(pickerButtons) do
		local selected = dollars == quickBuy
		pill.BackgroundColor3 = selected and Theme.Colors.Accent or Theme.Colors.Raised
		pill.TextColor3 = selected and Theme.Colors.Background or Theme.Colors.TextMuted
	end
end

for dollars, pill in pairs(pickerButtons) do
	pill.MouseButton1Click:Connect(function()
		quickBuy = dollars
		updatePicker()

		-- Relabel every card's Buy button
		if lastPulse then
			renderColumns(lastPulse.columns)
		end
	end)
end

local function setShowingMyCoins(show)
	showingMyCoins = show
	ColumnsView.Visible = not show
	MyCoinsView.panel.Visible = show
	MyCoinsToggle.BackgroundColor3 = show and Theme.Colors.Accent or Theme.Colors.Raised
	MyCoinsToggle.TextColor3 = show and Theme.Colors.Background or Theme.Colors.Text

	if show then
		task.spawn(refreshMyCoins)
	end
end

MyCoinsToggle.MouseButton1Click:Connect(function()
	setShowingMyCoins(not showingMyCoins)
end)

-- Launching (Task 7)

PulseScreen:GetPropertyChangedSignal("Visible"):Connect(function()
	if PulseScreen.Visible then
		task.spawn(refreshVisible)
	end
end)

-- Polls only while Pulse is on screen; the server answers from its cache
task.spawn(function()
	while true do
		task.wait(POLL_INTERVAL)

		if PulseScreen.Visible then
			refresh()

			if Panel.coinId then
				refreshPanel()
			end

			if showingMyCoins and os.clock() - lastMyCoinsAt >= MY_COINS_INTERVAL then
				refreshMyCoins()
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(1)

		if PulseScreen.Visible then
			updateFreshness()
		end
	end
end)

updatePicker()
```

- [ ] **Step 8: Seed coins and run the checks**

`start_stop_play(true)`, wait about 5 s.

1. **H5** `SETUP` with `BALANCE = 20000`.
2. **H8.** Note `LONG`, `ABOUT` and `GRAD`.
3. Click `…TopBar.TabContainer.PulseButton`, wait 20 s (one snapshot refresh plus one poll), then run **Step 1** with the ids.

   Expected: `long=NewColumn about=AboutToGraduateColumn grad=GraduatedColumn badge=true buy=Buy $250 fresh=Updated <n>s ago`.
4. **H2** with `SCOPE = "PulseScreen"`. Expected: `0 problem(s)`, even with the 24-character name.
5. Click `…PulseScreen.Header.QuickBuyPicker.Amount_100`. Then on the Client:
   ```lua
   local screen = game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen
   return screen.Columns.NewColumn.List["Card_<LONG>"].BuyButton.Text, screen.Header.QuickBuyPicker.Amount_100.BackgroundColor3:ToHex()
   ```
   Expected: `Buy $100`, `9a6bff`.
6. Click `…PulseScreen.Columns.NewColumn.List.Card_<LONG>.BuyButton`, wait 2 s. Then on the Client:
   ```lua
   local player = game:GetService("Players").LocalPlayer
   local screen = player.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen
   return string.format("status=%s balance=%s panel=%s", screen.Header.StatusLabel.Text, tostring(player:GetAttribute("Balance")), tostring(screen.CoinPanel.Visible))
   ```
   Expected: `status=Bought <n>M $LNG<nnn> for $100.00 balance=19900 panel=false`. The Buy click didn't open the panel.
7. Click the card body `…NewColumn.List.Card_<LONG>`, wait 2 s. Then on the Client:
   ```lua
   local panel = game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen.CoinPanel
   local segments = 0
   for _, child in ipairs(panel.Chart:GetChildren()) do
   	if string.sub(child.Name, 1, 4) == "Seg_" then
   		segments += 1
   	end
   end
   return string.format("visible=%s ticker=%s position=%s segments=%d sellEnabled=%s", tostring(panel.Visible), panel.Ticker.Text, panel.Position.Text, segments, tostring(panel.SellPresets.Sell_100:GetAttribute("Enabled")))
   ```
   Expected: `visible=true ticker=$LNG<nnn> position=Position <n>M · $<value> segments=` at least 1, and `sellEnabled=true`.
8. Click `…CoinPanel.BuyPresets.Buy_250`, wait 2 s. Expected: the status starts `Bought`, and Balance is `19650`.
9. Click `…CoinPanel.SellPresets.Sell_100`, wait 2 s. Re-run the item 7 snippet. Expected:
   - the status starts `Sold `;
   - `position=No position`;
   - `sellEnabled=false`;
   - Balance is `19993.03` (within $0.01). The two buys put $346.50 into the curve after fees, and selling everything back pays 99% of that, $343.03.
10. **H2** `PulseScreen`, with the panel open. Expected: `0 problem(s)`.
11. **Archived coins stay sellable:**
    - Click `…CoinPanel.BuyPresets.Buy_100` and wait 2 s, so the player holds a position.
    - Archive the coin on the Server:
      ```lua
      local CoinStore = require(game:GetService("ServerScriptService").Modules.CoinStore)
      local state = CoinStore.read("<LONG>")
      local archived = CoinStore.archiveIdle({ state }, os.time() + 25 * 3600)
      return archived, select(2, CoinStore.read("<LONG>"))
      ```
      Expected: `1 archived`.
    - Click `…CoinPanel.CloseButton`. Wait 15 s, so the server's snapshot drops the coin.
    - Click `…Header.MyCoinsToggle` and wait 3 s. Then on the Client:
      ```lua
      local screen = game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen
      local row = screen.MyCoinsView.List:FindFirstChild("Row_<LONG>")
      return string.format("row=%s archived=%s toggle=%s", tostring(row ~= nil), tostring(row and row.ArchivedTag.Visible), screen.Header.MyCoinsToggle.BackgroundColor3:ToHex())
      ```
      Expected: `row=true archived=true toggle=9a6bff`.
    - Click `…MyCoinsView.List.Row_<LONG>`, wait 2 s. Expected: `…CoinPanel.ArchivedNote.Visible == true`.
    - Click `…CoinPanel.SellPresets.Sell_100`, wait 2 s. Expected: the status starts `Sold `. On the Server, `select(2, CoinStore.read("<LONG>"))` is `live`: the trade revived the coin.
12. **H2** `PulseScreen`, with My coins showing. Expected: `0 problem(s)`. Then click `…MyCoinsToggle` (back to columns) and `…CoinPanel.CloseButton`.
13. **H3.** Expected: every value is `true`.
14. **Store unavailable.** Do this last, because it replaces the server's handler for the rest of this playtest. On the Server:
    ```lua
    local probe = Instance.new("Script")
    probe.Name = "TEST_Unavailable"
    probe.Source = [[
    	local columns = {
    		New = { { id = "fake1", name = "Stale Coin", ticker = "STALE", creatorName = "x", createdAt = os.time() - 300, marketCap = 5000, volume = 10, trades = 1, progress = 0.1, graduated = false, graduatedAt = 0 } },
    		AboutToGraduate = {},
    		Graduated = {},
    	}
    	game:GetService("ReplicatedStorage").EventsFolder.GetPulseEvent.OnServerInvoke = function()
    		return { ok = false, updatedAt = os.time() - 120, serverTime = os.time(), columns = columns }
    	end
    ]]
    probe.Parent = game:GetService("ServerScriptService")
    ```
    Wait 7 s. Then on the Client:
    ```lua
    local screen = game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen
    local card = screen.Columns.NewColumn.List:FindFirstChild("Card_fake1")
    return string.format("status=%s fresh=%s buyEnabled=%s", screen.Header.StatusLabel.Text, screen.Header.FreshnessLabel.Text, tostring(card and card.BuyButton:GetAttribute("Enabled")))
    ```
    Expected: `status=Coins unavailable, retrying… fresh=Updated 2m ago buyEnabled=false`.

    Click `…NewColumn.List.Card_fake1.BuyButton`. Expected: Balance is unchanged and the status is unchanged.

Run **H5** `RESTORE` (`BALANCE = START_BALANCE`), then `start_stop_play(false)`.

- [ ] **Step 9: Commit and record**

```bash
git add src/shared/Modules/Pulse/PulseUI.luau src/shared/Modules/Pulse/CoinCard.luau src/shared/Modules/Pulse/Sparkline.luau src/shared/Modules/Pulse/CoinPanel.luau src/client/Controllers/PulseController.client.luau
git commit -m "Pulse screen: coin columns, quick-buy cards, coin panel, My coins" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
printf '%s\n' "Task 6: columns, picker, quick-buy, panel buy/sell, archived sell+revive, unavailable state, H2 x3 0, H3 all true PASS" > "$WS/task-6-studio.txt"
$S/executing-plans/scripts/task-done $PLAN 6 <BASE> -- grep -q 'PASS$' "$WS/task-6-studio.txt"
```

---
### Task 7: Launching from Pulse

**Files:**
- Create: `src/shared/Modules/Pulse/LaunchForm.luau`
- Modify: `src/client/Controllers/PulseController.client.luau` (requires, a forward declaration, `applyEnabled`, and the `-- Launching (Task 7)` marker)
- Test: Play-mode checks through the form, H2 (`"PulseScreen"`)

**Interfaces:**
- Consumes:
  - Task 4: `LaunchCoinEvent(name, ticker) -> { success, message, coin? }`.
  - Task 6: `PulseUI`; the `PulseController` locals `Header`, `Panel`, `PulseScreen`, `setStatus`, `serverNow`, `refresh`, `applyEnabled`, `storeOk`, `EDGE`, `LAUNCH_WIDTH` and `BUTTON_HEIGHT`.
  - Task 1: `CoinRules`, `CoinConfig.LAUNCH_FEE`.
- Produces:
  - `PulseScreen.Header.LaunchButton`;
  - `PulseScreen.LaunchBackdrop.LaunchDialog.{NameInput, TickerInput, Error, CancelButton, SubmitButton}`;
  - `LaunchForm.new(parent, onSubmit(name, ticker))`, plus `:open()`, `:close()`, `:isOpen()`, `:setBusy(busy)` and `:showError(message)`.

- [ ] **Step 1: Write the failing check** (Client datamodel, during Play)

```lua
local screen = game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen
return string.format("launchButton=%s backdrop=%s", tostring(screen.Header:FindFirstChild("LaunchButton") ~= nil), tostring(screen:FindFirstChild("LaunchBackdrop") ~= nil))
```

- [ ] **Step 2: Run it and confirm it fails**

`start_stop_play(true)`, wait about 5 s, then run Step 1.

Expected: `launchButton=false backdrop=false`.

Run **H5** `RESTORE`, then `start_stop_play(false)`.

- [ ] **Step 3: Write `LaunchForm.luau`**

```lua
-- LaunchForm.luau
--
-- The Launch coin dialog: a name and a ticker, checked here for instant
-- feedback with the same rules the server enforces. The server's answer
-- (cooldown, taken ticker, filter) comes back through showError.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local CoinConfig = require(ReplicatedStorage.Modules.Coins.CoinConfig)
local CoinRules = require(ReplicatedStorage.Modules.Coins.CoinRules)
local PulseUI = require(script.Parent.PulseUI)

local LaunchForm = {}
LaunchForm.__index = LaunchForm

local FORM_Z = 20 -- over the columns and the coin panel
local DIALOG_WIDTH = 340
local DIALOG_HEIGHT = 236
local EDGE = 16
local INPUT_HEIGHT = 30
local BUTTON_HEIGHT = 30
local BACKDROP_TRANSPARENCY = 0.35

local function makeInput(parent, name, y, placeholder, z)
	local input = Instance.new("TextBox")
	input.Name = name
	input.Position = UDim2.fromOffset(EDGE, y)
	input.Size = UDim2.new(1, -2 * EDGE, 0, INPUT_HEIGHT)
	input.BackgroundColor3 = Theme.Colors.Raised
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Text = ""
	input.PlaceholderText = placeholder
	input.PlaceholderColor3 = Theme.Colors.TextMuted
	input.TextColor3 = Theme.Colors.Text
	input.FontFace = Theme.Fonts.UI
	input.TextSize = Theme.TextSize.Body
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.ZIndex = z
	input.Parent = parent
	PulseUI.corner(input)
	PulseUI.stroke(input)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = input

	return input
end

-- onSubmit(name, ticker) gets cleaned values that passed the rules
function LaunchForm.new(parent, onSubmit)
	local self = setmetatable({ onSubmit = onSubmit, busy = false }, LaunchForm)
	local z = FORM_Z + 1

	-- Dims the screen and catches clicks meant for what's underneath
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "LaunchBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Theme.Colors.Background
	backdrop.BackgroundTransparency = BACKDROP_TRANSPARENCY
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = FORM_Z
	backdrop.Visible = false
	backdrop.Parent = parent
	self.backdrop = backdrop

	local dialog = PulseUI.frame({
		name = "LaunchDialog",
		parent = backdrop,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromOffset(DIALOG_WIDTH, DIALOG_HEIGHT),
		color = Theme.Colors.Panel,
		z = z,
	})
	PulseUI.corner(dialog)
	PulseUI.stroke(dialog)

	local fullWidth = UDim2.new(1, -2 * EDGE, 0, 14)

	local function caption(name, y, text, color)
		return PulseUI.label({ name = name, parent = dialog, position = UDim2.fromOffset(EDGE, y), size = fullWidth, text = text, textColor = color or Theme.Colors.TextMuted, textSize = Theme.TextSize.Caption, z = z })
	end

	PulseUI.label({ name = "Title", parent = dialog, position = UDim2.fromOffset(EDGE, 12), size = UDim2.new(1, -2 * EDGE, 0, 22), text = "Launch a coin", font = Theme.Fonts.UIBold, textSize = Theme.TextSize.Title, z = z })
	caption("NameCaption", 42, "Name")
	self.nameInput = makeInput(dialog, "NameInput", 58, "e.g. Pepe Coin", z)
	caption("TickerCaption", 96, "Ticker")
	self.tickerInput = makeInput(dialog, "TickerInput", 112, "e.g. PEPE", z)
	caption("Hint", 148, "Costs " .. NumberModule.format(CoinConfig.LAUNCH_FEE) .. " · one launch per hour")
	self.errorLabel = caption("Error", 166, "", Theme.Colors.Down)

	self.cancel = PulseUI.button({
		name = "CancelButton",
		parent = dialog,
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -(EDGE + 96 + 8), 1, -EDGE),
		size = UDim2.fromOffset(92, BUTTON_HEIGHT),
		text = "Cancel",
		color = Theme.Colors.Raised,
		z = z,
	})
	self.submit = PulseUI.button({
		name = "SubmitButton",
		parent = dialog,
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -EDGE, 1, -EDGE),
		size = UDim2.fromOffset(96, BUTTON_HEIGHT),
		text = "Launch",
		color = Theme.Colors.Accent,
		textColor = Theme.Colors.Background,
		font = Theme.Fonts.UIBold,
		z = z,
	})
	PulseUI.hover(self.submit, Theme.Colors.Accent, Theme.Colors.AccentSoft)

	PulseUI.onClick(self.submit, function()
		self:trySubmit()
	end)

	self.cancel.MouseButton1Click:Connect(function()
		if not self.busy then
			self:close()
		end
	end)

	self.tickerInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			self:trySubmit()
		end
	end)

	return self
end

function LaunchForm:open()
	self.nameInput.Text = ""
	self.tickerInput.Text = ""
	self:showError(nil)
	self:setBusy(false)
	self.backdrop.Visible = true
end

function LaunchForm:close()
	self.backdrop.Visible = false
end

function LaunchForm:isOpen()
	return self.backdrop.Visible
end

function LaunchForm:setBusy(busy)
	self.busy = busy
	self.submit.Text = busy and "Launching…" or "Launch"
	PulseUI.setEnabled(self.submit, not busy, Theme.Colors.Accent, Theme.Colors.Background)
end

function LaunchForm:showError(message)
	self.errorLabel.Text = message or ""
end

function LaunchForm:trySubmit()
	if self.busy then
		return
	end

	local name, nameMessage = CoinRules.validateName(self.nameInput.Text)

	if not name then
		self:showError(nameMessage)
		return
	end

	local ticker, tickerMessage = CoinRules.validateTicker(self.tickerInput.Text)

	if not ticker then
		self:showError(tickerMessage)
		return
	end

	self:showError(nil)
	self.onSubmit(name, ticker)
end

return LaunchForm
```

- [ ] **Step 4: Wire the form into `PulseController.client.luau`**

Replace:

```lua
local CoinPanel = require(ReplicatedStorage.Modules.Pulse.CoinPanel)
```

with:

```lua
local CoinPanel = require(ReplicatedStorage.Modules.Pulse.CoinPanel)
local LaunchForm = require(ReplicatedStorage.Modules.Pulse.LaunchForm)
```

Replace:

```lua
local CoinOrderEvent = EventsFolder:WaitForChild("CoinOrderEvent")
```

with:

```lua
local CoinOrderEvent = EventsFolder:WaitForChild("CoinOrderEvent")
local LaunchCoinEvent = EventsFolder:WaitForChild("LaunchCoinEvent")
```

Replace:

```lua
local placeOrder, openPanel -- defined below; cards and the panel call them
```

with:

```lua
local placeOrder, openPanel -- defined below; cards and the panel call them
local LaunchButton -- built with the launch form, below
```

In `applyEnabled`, replace:

```lua
	Panel:setEnabled(enabled)
end
```

with:

```lua
	Panel:setEnabled(enabled)

	-- Launching needs the store too, but not an idle order slot. Nil only
	-- if this runs before the launch section below has built the button
	if LaunchButton then
		PulseUI.setEnabled(LaunchButton, storeOk, Theme.Colors.Accent, Theme.Colors.Background)
	end
end
```

Replace:

```lua
-- Launching (Task 7)
```

with:

```lua
-- Launching
local Launcher

LaunchButton = PulseUI.button({
	name = "LaunchButton",
	parent = Header,
	anchor = Vector2.new(1, 0),
	position = UDim2.new(1, -EDGE, 0, 10),
	size = UDim2.fromOffset(LAUNCH_WIDTH, BUTTON_HEIGHT),
	text = "Launch coin",
	color = Theme.Colors.Accent,
	textColor = Theme.Colors.Background,
	font = Theme.Fonts.UIBold,
})
PulseUI.hover(LaunchButton, Theme.Colors.Accent, Theme.Colors.AccentSoft)

local function launchCoin(name, ticker)
	Launcher:setBusy(true)
	local ok, result = pcall(LaunchCoinEvent.InvokeServer, LaunchCoinEvent, name, ticker)
	Launcher:setBusy(false)

	if not ok or type(result) ~= "table" then
		Launcher:showError("Couldn't launch, try again.")
		return
	end

	if not result.success then
		Launcher:showError(result.message)
		return
	end

	Launcher:close()
	setStatus(result.message, Theme.Colors.Text)

	-- The creator's panel opens right away for the first buy
	Panel:show(result.coin, serverNow())
	task.spawn(refresh)
end

Launcher = LaunchForm.new(PulseScreen, launchCoin)

PulseUI.onClick(LaunchButton, function()
	Launcher:open()
end)
```

- [ ] **Step 5: Run the checks and confirm they pass**

`start_stop_play(true)`, wait about 5 s. Run **H5** `SETUP` with `BALANCE = 20000`, then **H9**, and wait 15 s. Click `…TabContainer.PulseButton`. Step 1 should now return `launchButton=true backdrop=true`.

Fill the form with this Client snippet. Set `NAME`, `TICKER` and `ENTER` each time. This snippet departs from the Global Constraints' `ReleaseFocus(true)` on purpose. `ReleaseFocus(true)` fires `FocusLost` with `enterPressed = true`, which is the form's Enter-to-submit path. So the name box always releases with `false`, and the ticker box uses `ENTER`: `false` leaves submitting to the Submit click, and `true` submits the way pressing Enter does.

```lua
local NAME, TICKER, ENTER = "P", "AB", false
local dialog = game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen.LaunchBackdrop.LaunchDialog
local function fill(box, text, submit)
	box:CaptureFocus()
	box.Text = text
	box:ReleaseFocus(submit)
end
fill(dialog.NameInput, NAME, false)
fill(dialog.TickerInput, TICKER, ENTER)
return dialog.NameInput.Text .. " | " .. dialog.TickerInput.Text
```

Read the result with this Client snippet:

```lua
local player = game:GetService("Players").LocalPlayer
local screen = player.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen
return string.format("open=%s error=%s balance=%s status=%s panel=%s ticker=%s", tostring(screen.LaunchBackdrop.Visible), screen.LaunchBackdrop.LaunchDialog.Error.Text, tostring(player:GetAttribute("Balance")), screen.Header.StatusLabel.Text, tostring(screen.CoinPanel.Visible), screen.CoinPanel.Ticker.Text)
```

1. Click `…PulseScreen.Header.LaunchButton`. Run **H2** `PulseScreen`. Expected: `0 problem(s)` with the form open.
2. Fill with `"P"`, `"AB"` and `ENTER = false`, then click `…LaunchBackdrop.LaunchDialog.SubmitButton`. Expected: `open=true error=Name must be 2-24 characters. balance=20000`.
3. Pick a ticker `L` plus four random digits, written below as `L<dddd>`. Fill with `"Launch Test"`, `"L<dddd>"` and `ENTER = false`, click Submit, and wait 3 s. Expected: `open=false error= balance=19000 status=Launched $L<dddd>. panel=true ticker=$L<dddd>`.
4. Click `…PulseScreen.CoinPanel.BuyPresets.Buy_100` and wait 2 s. Then on the Client: `return game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen.CoinPanel.CreatorShare.Value.Text`. Expected: `3.4%`, the creator's own first buy (34,277,832 tokens).
5. Click LaunchButton. Fill with `"Too Soon"`, `"TS<dddd>"` and `ENTER = true`, so Enter submits and there's no Submit click. Wait 2 s. Expected: `open=true`, `error=` starts with `You can launch again in`, and `balance=` is unchanged from item 4.
6. Run **H5** `SETUP` with `BALANCE = 20000`, which clears the cooldown. Fill with `"Copy Cat"`, `"L<dddd>"` (the item 3 ticker) and `ENTER = false`, click Submit, and wait 2 s. Expected: `error=Ticker taken. balance=20000`.
7. Click `…LaunchDialog.CancelButton`. Expected: `open=false`.
8. **H2** `PulseScreen`, with the creator's panel open. Expected: `0 problem(s)`.
9. **Store unavailable disables launching.** Do this last, because it replaces the server's handler for the rest of this playtest. On the Server:
    ```lua
    local probe = Instance.new("Script")
    probe.Name = "TEST_Unavailable"
    probe.Source = [[
    	local columns = { New = {}, AboutToGraduate = {}, Graduated = {} }
    	game:GetService("ReplicatedStorage").EventsFolder.GetPulseEvent.OnServerInvoke = function()
    		return { ok = false, updatedAt = os.time() - 120, serverTime = os.time(), columns = columns }
    	end
    ]]
    probe.Parent = game:GetService("ServerScriptService")
    ```
    Wait 7 s. On the Client: `return tostring(game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen.Header.LaunchButton:GetAttribute("Enabled"))`. Expected: `false`. Click `…Header.LaunchButton`. Expected: `open=false`, so the form didn't open.

Run **H5** `RESTORE` (`BALANCE = START_BALANCE`), then `start_stop_play(false)`.

- [ ] **Step 6: Commit and record**

```bash
git add src/shared/Modules/Pulse/LaunchForm.luau src/client/Controllers/PulseController.client.luau
git commit -m "Pulse: launch a coin from the header" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
printf '%s\n' "Task 7: form validation, launch -1000 + panel, creator share, Enter submits, cooldown, ticker taken, H2 x2 0, launch disabled when unavailable PASS" > "$WS/task-7-studio.txt"
$S/executing-plans/scripts/task-done $PLAN 7 <BASE> -- grep -q 'PASS$' "$WS/task-7-studio.txt"
```

---
### Task 8: Graduation end to end, docs, and the finish

This task adds no game code. It walks the spec's "Done means" list in one playtest on a coin the player launches. Then it documents the system in `CLAUDE.md` and runs the last audits.

If any expected value differs, the bug is in an earlier task. Use superpowers:systematic-debugging. Fix it in that task's file with a failing check written first, ledger the fix, and rerun this task from Step 1.

**Files:**
- Modify: `CLAUDE.md`
- Test: Play-mode walkthrough, H2 (`"Shell"`, `"PulseScreen"`), H3, console

**Interfaces:**
- Consumes everything from Tasks 1–7, in particular:
  - `CoinOrderEvent("Buy", coinId, dollars)`;
  - card `Card_<id>` with `Ticker`, `GraduatedBadge`, `BuyButton`;
  - `CoinPanel.{GraduatedBadge, Progress.Value, CreatorShare.Value, SellPresets.Sell_100, CloseButton, ArchivedNote}`;
  - `MyCoinsView.List.Row_<id>.ArchivedTag`;
  - `CoinStore.read` and `CoinStore.archiveIdle`;
  - the launch form from Task 7.
- Produces: nothing new.

The numbers below follow from Global Constraints. Each buy puts 99% of its dollars into the curve. Graduation needs $8,500 in the curve. Selling everything back pays 99% of what's in the curve.

| After | Curve holds (V − V₀) | Progress | Balance |
|---|---|---|---|
| H5 `SETUP` | — | — | 20000 |
| Launch | 0 | 0% | 19000 |
| Card quick-buy $250 | 247.50 | 2% | 18750 |
| Buy $4,400 | 4603.50 | 54% | 14350 |
| Buy $4,000 | 8563.50 | graduated | 10350 |
| Bonus collected | 8563.50 | graduated | 12850 |
| Panel Sell 100% | 0 | graduated | 21327.87 |
| Buy $8,600 (crosses $8,500 again) | 8514 | graduated | 12727.87 |
| Archive, then Sell 100% from My coins | 0 | graduated | 21156.73 |

- [ ] **Step 1: Walk the spec's "Done means" list**

`start_stop_play(true)`, wait about 5 s. Run **H5** `SETUP` with `BALANCE = 20000`, then **H9**, and wait 15 s. Click `…TopBar.TabContainer.PulseButton`.

Pick a ticker `G` plus four random digits, written below as `G<dddd>`. Find its card and read the state with this Client snippet:

```lua
local TICKER = "G<dddd>"
local player = game:GetService("Players").LocalPlayer
local screen = player.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen
local found = "none"
for _, column in ipairs(screen.Columns:GetChildren()) do
	local list = column:FindFirstChild("List")
	if list then
		for _, card in ipairs(list:GetChildren()) do
			if string.sub(card.Name, 1, 5) == "Card_" and card.Ticker.Text == "$" .. TICKER then
				found = string.format("%s id=%s badge=%s", column.Name, string.sub(card.Name, 6), tostring(card.GraduatedBadge.Visible))
			end
		end
	end
end
return string.format("card=%s balance=%s status=%s", found, tostring(player:GetAttribute("Balance")), screen.Header.StatusLabel.Text)
```

Read the panel with this Client snippet:

```lua
local panel = game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen.CoinPanel
return string.format("visible=%s ticker=%s badge=%s progress=%s creator=%s archived=%s", tostring(panel.Visible), panel.Ticker.Text, tostring(panel.GraduatedBadge.Visible), panel.Progress.Value.Text, panel.CreatorShare.Value.Text, tostring(panel.ArchivedNote.Visible))
```

1. **Launch.** Click `…PulseScreen.Header.LaunchButton`. Fill the form using Task 7's fill snippet with `"Grad Test"`, `"G<dddd>"` and `ENTER = false`. Click `…LaunchDialog.SubmitButton` and wait 3 s. Expected status: `Launched $G<dddd>.`, with balance `19000`. Wait 20 s, then run the card snippet. Expected: `card=NewColumn id=<id> badge=false`. Note `<id>`.
2. **Buy from a card.** Click `…Columns.NewColumn.List.Card_<id>.BuyButton` and wait 2 s. Expected: balance `18750`.
3. **About to graduate.** On the Client: `return game:GetService("ReplicatedStorage").EventsFolder.CoinOrderEvent:InvokeServer("Buy", "<id>", 4400).message`. Expected: starts `Bought`. Wait 20 s, then run the card snippet. Expected: `card=AboutToGraduateColumn`, balance `14350`.
4. **Graduated.** On the Client: `return game:GetService("ReplicatedStorage").EventsFolder.CoinOrderEvent:InvokeServer("Buy", "<id>", 4000).message`. Expected: starts `Bought`, and the balance right after is `10350`. Wait 20 s, then run the card snippet. Expected: `card=GraduatedColumn id=<id> badge=true`.
5. **The bonus arrives.** Within 70 s of item 4's buy, the balance reaches `12850`: the $2,500 bonus, collected by the 60 s payout loop. Run the panel snippet. Expected: `visible=true ticker=$G<dddd> badge=true progress=Graduated creator=79.5%`. The creator holds every token sold, 794,624,076 of 1,000,000,000.
6. **Sell from the panel.** Click `…CoinPanel.SellPresets.Sell_100` and wait 2 s. Expected: the status starts `Sold `, and the balance is `21327.87` (within $0.01). Wait 20 s. The card snippet still shows `card=GraduatedColumn`, because graduation is permanent.
7. **The bonus is paid once.** On the Client: `return game:GetService("ReplicatedStorage").EventsFolder.CoinOrderEvent:InvokeServer("Buy", "<id>", 8600).message`. This puts $8,514 into the curve, crossing $8,500 again. Expected: balance `12727.87` (within $0.01) right after, and still `12727.87` after 70 s. A second bonus would show up as `15227.87`.
8. **Archived, found under My coins, sold.**
   - On the Server:
     ```lua
     local CoinStore = require(game:GetService("ServerScriptService").Modules.CoinStore)
     local state = CoinStore.read("<id>")
     local archived = CoinStore.archiveIdle({ state }, os.time() + 25 * 3600)
     return archived, select(2, CoinStore.read("<id>"))
     ```
     Expected: `1 archived`.
   - Click `…CoinPanel.CloseButton`, then wait 20 s (one snapshot refresh plus one poll). The card snippet shows `card=none`.
   - Click `…Header.MyCoinsToggle` and wait 3 s. On the Client:
     ```lua
     local row = game:GetService("Players").LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.PulseScreen.MyCoinsView.List:FindFirstChild("Row_<id>")
     return tostring(row ~= nil), tostring(row and row.ArchivedTag.Visible)
     ```
     Expected: `true true`.
   - Click `…MyCoinsView.List.Row_<id>` and wait 2 s. Run the panel snippet. Expected: `badge=true archived=true`.
   - Click `…CoinPanel.SellPresets.Sell_100` and wait 2 s. Expected: the status starts `Sold `, and the balance is `21156.73` (within $0.02). On the Server, `select(2, CoinStore.read("<id>"))` is `live`.
9. **Audits.** Click `…Header.MyCoinsToggle` (back to the columns) and `…CoinPanel.CloseButton`.
   - Run **H2** with `SCOPE = "PulseScreen"`, then with `SCOPE = "Shell"`. Expected: `0 problem(s)` for each.
   - Run **H3**. Expected: every value is `true`.
10. **Console.** Run `get_console_output`. Expected: no errors or warnings from these sources:
    - `CoinSystem`, `CoinService`, `CoinStore`, `PayoutMailbox`;
    - `PulseController`, `PulseUI`, `CoinCard`, `CoinPanel`, `Sparkline`, `LaunchForm`;
    - `Theme`, `ShellController`, `TerminalController`, `Data_Manager`, `CalculatorModule`.

    Backend warnings from `API_Manager` (the Yahoo 429) are known and don't count.

Run **H5** `RESTORE` (`BALANCE = START_BALANCE`), then `start_stop_play(false)`.

- [ ] **Step 2: Document the system in `CLAUDE.md`**

Replace:

```
`TradeController` for the Trade screen; Quote tabs and Options chain stubs).
```

with:

```
`TradeController` for the Trade screen; `PulseController` for the Pulse tab, whose UI is built entirely in
  code; Quote tabs and Options chain stubs).
```

Replace:

```
    `GetNewsFeedEvent`, `PlayerOrderEvent`, `PlayerOptionOrderEvent`). This must run before other server scripts wire up
```

with:

```
    `GetNewsFeedEvent`, `PlayerOrderEvent`, `PlayerOptionOrderEvent`, and the coin remotes `GetPulseEvent`,
    `GetCoinEvent`, `GetMyCoinsEvent`, `CoinOrderEvent`, `LaunchCoinEvent`). This must run before other server scripts wire up
```

Replace:

```
    portfolio shares/options, load on `PlayerAdded`, save on `PlayerRemoving`/`BindToClose`.
```

with:

```
    portfolio shares/options/coins (`Portfolio.Coins[coinId] = { tokens, cost }`), the coin launch cooldown
    (`CoinLaunches`), load on `PlayerAdded`, save on `PlayerRemoving`/`BindToClose`. A leaving player's save
    first waits for their in-flight coin order (`_G.WaitForCoinOrders`).
```

Replace:

```
  - `Modules/CalculatorModule.luau` computes net worth from portfolio + live market data.
```

with:

```
  - `CoinSystem.server.luau` handles the five coin remotes for player-launched memecoins (see "Player coins
    (Pulse)" below). Its rules live in `Modules/CoinService.luau` and its storage in `Modules/CoinStore.luau`
    and `Modules/PayoutMailbox.luau`.
  - `Modules/CalculatorModule.luau` computes net worth from portfolio + live market data, plus coin holdings
    at their current curve price (`CalculatorModule.coinValue`).
```

Replace:

```
  - `Terminal/` and `Trade/` subfolders are placeholder modules (currently empty) reserved for pulling
```

with:

```
  - `Coins/` — coin logic shared by server and client: `CoinConfig` (every coin constant), `CoinCurve`
    (bonding-curve math), `CoinState` (immutable state transitions), `CoinRules` (name/ticker validation),
    `CoinFormat`, `PulseColumns`.
  - `Pulse/` — the Pulse screen's code-built UI pieces (`PulseUI`, `CoinCard`, `CoinPanel`, `Sparkline`,
    `LaunchForm`), used only by `PulseController`.
  - `Terminal/` and `Trade/` subfolders are placeholder modules (currently empty) reserved for pulling
```

Replace:

```
`_G.UpdatePortfolio`, `_G.LiveMarketData` referenced from `CalculatorModule`) rather than `require`d modules
```

with:

```
`_G.UpdatePortfolio`, `_G.LiveMarketData` referenced from `CalculatorModule`, and `CoinSystem`'s `_G.LookupCoin`
and `_G.WaitForCoinOrders`) rather than `require`d modules
```

Replace:

```
### Data flow for a typical UI action
```

with:

```
### Player coins (Pulse)

Players launch memecoins that every server sees. Prices come only from buying and selling on a bonding curve
(`CoinCurve`); no outside data is involved. Design: `docs/superpowers/specs/2026-10-10-memecoins-pulse-design.md`.

- **Storage.** Live coin state lives in a MemoryStore hash map (`Coins`), with one atomic `UpdateAsync` per
  trade. DataStores hold the durable copy (`Coins_v1`), ticker claims (`CoinTickers_v1`) and payout mailboxes
  (`Payouts_v1`). In Studio every store name gets a `_studio` suffix, so playtests never touch live coins.
- **Money rules.** Cash is taken before a trade and refunded if the trade fails. Trades are never retried;
  reads and idempotent writes are. A player has at most one coin order in flight.
- **Graduation.** At $8,500 of net buying a coin graduates for good, and its creator gets a one-time $2,500
  through their mailbox. Each server collects the mailboxes of the players it hosts every 60 s.
- **Pulse** reads a server-side snapshot rebuilt every 12–60 s. Coins idle for 24 h are archived; holders still
  see and sell them under My coins, and a trade restores them.
- **Playtests write real data.** Trades in a Studio playtest change the tester's real `PlayerData_v1`
  balance. The plan's H5 snippet (`docs/superpowers/plans/2026-10-10-memecoins-pulse-plan.md`) restores it.

### Data flow for a typical UI action
```

Check that every edit landed:

```bash
for s in 'LaunchCoinEvent' '_G.LookupCoin' '### Player coins (Pulse)' 'CalculatorModule.coinValue' '`PulseController` for the Pulse tab' '`Coins/`' '`Pulse/`' 'Portfolio.Coins[coinId]' 'CoinSystem.server.luau'; do
  grep -qF -- "$s" CLAUDE.md && echo "ok   $s" || echo "MISSING $s"
done
```

Expected: nine lines, each starting `ok`.

- [ ] **Step 3: Commit and record**

```bash
git add CLAUDE.md
git commit -m "Document player coins and Pulse" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
printf '%s\n' "Task 8: launch, New->About->Graduated, bonus once (12850, no second after re-cross), panel sell, archived My coins sell, H2 x2 0, H3 all true, console clean PASS" > "$WS/task-8-studio.txt"
$S/executing-plans/scripts/task-done $PLAN 8 <BASE> -- grep -q 'PASS$' "$WS/task-8-studio.txt"
```

- [ ] **Step 4: Hand off**

The executor's skill now runs the final whole-branch review, with this plan's Review Focus section. It then runs superpowers:finishing-a-development-branch with base branch `main`. With the finishing menu, ask Kevin to play Pulse in Studio and approve the feel; the spec's "Done means" requires it. Remind him of what's still open from Phase 1:
- save the Studio place;
- retest options and Active Trader once the backend's Yahoo 429 clears, before pushing `main`;
- fix MarketHoursModule's hardcoded EDT before 2026-11-01.
