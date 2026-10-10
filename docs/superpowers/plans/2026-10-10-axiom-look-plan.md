# Axiom-Style Look (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle every existing TradingBlox screen into a dark, dense, Axiom-style terminal (one palette, violet accent, two fonts, four text sizes, flat bordered panels) inside a full-screen shell with a top nav bar and bottom status bar.

**Architecture:** A new git-tracked `Theme.luau` module holds color/font/size tokens and ~30 named roles; every hand-built UI element in the Studio place gets a `ThemeRole` attribute (one-time tagging pass), and `Theme.apply(root)` stamps each role's properties. Roles never set a property a controller changes at runtime, so the theme and the controllers can't fight. A new `ShellController` makes the GUI full screen, builds the wordmark / balance pill / status bar in code, and calls `Theme.apply` at startup; `TerminalController`, `TradeController` and `ChartRenderer` swap their hardcoded colors and fonts for theme lookups.

**Tech Stack:** Luau, Rojo (`rojo serve` already running from `/Users/killxinu/Documents/GitHub/TradingBlox`, pid 21122, port 34872), Roblox Studio driven through the `Roblox_Studio` MCP tools (`studio_id: e776d95f-7161-432c-878b-e9355b6cd0db`, place "TradingBlox", placeId 94116835322730). No test framework — every "test" is an `execute_luau` check snippet with an exact expected result, run before the change (fails) and after (passes).

**Spec:** `docs/superpowers/specs/2026-10-10-axiom-look-design.md`

## Global Constraints

- **Work in the main checkout, on branch `axiom-look-phase1`. Do NOT use a git worktree.** Rojo serves `/Users/killxinu/Documents/GitHub/TradingBlox`, and Studio must see code edits live. Use absolute paths / `git -C /Users/killxinu/Documents/GitHub/TradingBlox` for every command — the session's shell may start inside the old options worktree, which Task 0 deletes.
- **The UI tree is not in git.** `StarterGui.TerminalGui` exists only in the Studio place. Studio edits (Task 2) are made with `execute_luau` (`datamodel_type: "Edit"`), and persist only when Kevin saves the place — there is no MCP save tool. Each Studio-editing task ends by asking Kevin to save.
- **Play-mode changes never persist.** Anything created during a playtest (injected Scripts, test trades' UI state) vanishes on `start_stop_play(false)`; test trades DO persist in the player's DataStore, so always sell back what a test buys.
- **Fresh requires in Edit mode.** Studio caches `require` results per ModuleScript, so an Edit-mode check must clone the module(s) into a temporary Folder in `ServerStorage`, require the clone, then destroy the folder. Every Edit-mode snippet below does this inline. (Verified working in this place on 2026-10-10.)
- **`execute_luau` cannot see game scripts' `_G`.** To read `_G.PlayerData`, inject a real `Script` (see Snippet H4).
- **Screenshots don't work here** (`screen_capture` returns a magenta placeholder). Verify structurally; Kevin judges the look by eye in Task 7.
- **TextBox input:** drive with `TextBox:CaptureFocus()` → set `.Text` → `TextBox:ReleaseFocus(true)` from a Client-datamodel `execute_luau`; synthetic keyboard input does not land. Buttons: `user_mouse_input` `mouseButtonClick` with `instance_path` (e.g. `"LocalPlayer.PlayerGui.TerminalGui.MainBackground.TopBar.TabContainer.TradeButton"`).
- **Market hours:** NYSE is closed on weekends/holidays. Orders are gated twice: the server rejects non-crypto orders when closed, and **both client screens (Trade's `placeOrder`, Charts' Active Trader) refuse every order when closed — crypto included** — before calling the server. So any test that places an order while NYSE is closed needs **H1a (server) and H1b (client)** with `OPEN = true`. Use `ETH-USD` for chart and Active Trader checks (it has live weekend prices and fits the 60px chart badge); use AAPL for the Trade screen (it has an option chain).
- Code style: tabs, comments explain *why*, no new abstractions beyond what's written here. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Exact token values (from the spec, verbatim): Background `8,9,13`; Panel `14,16,22`; Raised `21,24,34`; Border `35,39,54`; Text `231,233,240`; TextMuted `139,144,163`; TextDisabled `91,96,115`; Accent `154,107,255`; AccentSoft `224,170,255`; AccentTint `30,24,48`; Up `46,189,133`; UpHover `39,161,113`; Down `240,74,108`; DownHover `204,63,92`. Text sizes Caption 12 / Body 13 / Title 15 / Display 24. Corner radius 4px. Fonts: Builder Sans (`rbxassetid://16658221428`) and Roboto Mono (`rbxasset://fonts/families/RobotoMono.json`) only.

### Deviations from the spec found while planning (all small; flagged to Kevin)

1. **More roles than the spec's table** (~30 vs ~18): the real tree needs `PanelFlat`, `Pill`, `InputText`, `Scroll`, `TextStrong`, `HeadingUp/Down`, `Display`, `NumberLargeDynamic`, `HeadingDynamic`, `Button`, `ButtonPrimary`. Same mechanism, finer grain.
2. **`Tab` uses Body (13) semibold, not Title (15)** — Axiom-density nav and Trade quote tabs that fit their buttons.
3. **`Preset` role sets no stroke color** — the Sell pills' stroke is recolored by `updateSellPresetsEnabled` at runtime (ownership rule). `TerminalController` now sets the Buy pills' colors and both pills' stroke mode in code.
4. **Chart grid lines become solid `Border`**, not `Border` at 95% transparency (which would be invisible on the new panel color).
5. **Font-width reason corrected:** Builder Sans measures the same as Source Sans (165 vs 164px); the text-fit risk comes from Roboto Mono (~17% wider) and 10–11px labels growing to 12px.
6. **Added (tiny, each verified):** hide 3 stale, unreferenced templates that render phantom "Label" rows (`StrikeRow_Template`, `OpenPosition_Template`, `NewsItem_Template`); `TerminalGui.ResetOnSpawn = false` so a character reset doesn't orphan every controller's UI references; disable the default PlayerList/Backpack/Health/Emotes HUD (it would sit on top of a full-screen terminal; chat stays); chart price badge drops decimals at ≥ $10,000 (today BTC's badge clips in the 60px axis); news headlines truncate with "…" instead of hard-clipping.
7. **Chart price-badge text uses Caption (12px), not Body** — its text box is 12px tall, so 13px text can't fit (the badge's countdown line is already 12px).
8. **Studio stamp happens in Task 2, right after tagging** (spec: last step), so all Studio work is done and saved in one sitting; `ShellController` re-applies the theme at runtime anyway, so later code tasks don't need another Studio pass.
9. **Status bar is `PanelFlat`** (Panel color, no stroke/corners) rather than `Panel` — a bordered, rounded full-width bar would look wrong; its top `Divider` supplies the edge.

## Review Focus

1. **Small or resized windows** (1280×720 laptop, a narrow Studio window): nav tabs must not overlap the wordmark or balance pill and must not sit under Roblox's buttons. → Snippet H3 (`tabsFit`, `wordmarkClearOfRobloxButtons`) runs in Task 3 and again in Task 7 after Kevin narrows the window.
2. **Roblox top bar reports no height** (`TopbarInset.Height == 0` on the first frame before CoreGui settles, or on platforms without the new top bar): nav falls back to 44px and re-lays out when the inset changes. → Task 3 Step 6 confirms `layoutShell` is wired to `TopbarInset` changes and H3 passes once the inset settles.
3. **Balance / NetWorth not loaded yet when the shell starts** (DataStore latency): pill and status bar show `$0.00`, then update. → Task 3 Step 7 checks pill text equals `NumberModule.format(Balance)` after load; Task 7 Step 5 checks both update after a trade.
4. **Weekends, holidays and boundaries for the countdown** (Friday close → Monday open is > 1 day; exactly on the hour; already past target): expected `2d 17h`, `1h 0m`, `0m 0s` — never negative. → Task 3 Step 1 test cases.
5. **Long and large values with the wider number font** (a $1,234,567.89 balance, BTC's six-figure price in the 60px chart badge, long news headlines): no clipped text. → Snippet H2's `fit` check in Tasks 5, 6, 7 and the badge case in Task 6 Step 1.

---

## Shared verification snippets

These are referenced by name from the tasks. Copy them verbatim.

### H1 — Force market hours (during Play)

`execute_luau` has its own `require` cache, so each half injects a real script that patches the shared `MarketHoursModule` table every game script on that side uses. Set `OPEN` to `true` to let orders through while NYSE is closed, or `false` to test the closed-market rejection while NYSE is open. Stopping the playtest discards both. While the client half is active, the Dashboard countdown and status bar also show the forced state — expected.

**H1a — server gate** (Server datamodel):

```lua
local OPEN = true

local override = Instance.new("Script")
override.Name = "TEST_MarketHoursOverride"
override.Source = string.format([[
	local MarketHoursModule = require(game:GetService("ReplicatedStorage").Modules.Multi.MarketHoursModule)
	MarketHoursModule.getMarketStatus = function(currentTime)
		return %s, currentTime + 3600
	end
]], tostring(OPEN))
override.Parent = game:GetService("ServerScriptService")

return "server market forced " .. (OPEN and "OPEN" or "CLOSED")
```

**H1b — client gate** (Client datamodel). Pass = `client market forced OPEN` (or `CLOSED`); `did not run` means the injection failed — stop and tell Kevin. Verified working in this place on 2026-10-10.

```lua
local OPEN = true

local player = game:GetService("Players").LocalPlayer
local override = Instance.new("LocalScript")
override.Name = "TEST_MarketHoursOverrideClient"
override.Source = string.format([[
	local MarketHoursModule = require(game:GetService("ReplicatedStorage").Modules.Multi.MarketHoursModule)
	MarketHoursModule.getMarketStatus = function(currentTime)
		return %s, currentTime + 3600
	end
	game:GetService("Players").LocalPlayer:SetAttribute("TEST_MarketForced", %q)
]], tostring(OPEN), OPEN and "OPEN" or "CLOSED")
override.Parent = player:WaitForChild("PlayerGui")

local deadline = os.clock() + 3
while os.clock() < deadline and player:GetAttribute("TEST_MarketForced") == nil do
	task.wait(0.1)
end
local forced = player:GetAttribute("TEST_MarketForced")
return forced and ("client market forced " .. forced) or "did not run"
```

### H2 — Palette, font and text-fit audit (Client datamodel, during Play)

Set `SCOPE` to `"Shell"` or a screen name under `ScreenContainer` (`"DashboardScreen"`, `"PortfolioScreen"`, `"TradeScreen"`, `"ChartsScreen"`). Only checks elements currently shown, so open the tab/flyout first. **Pass = `0 problem(s)` and font families exactly `rbxassetid://16658221428, rbxasset://fonts/families/RobotoMono.json` (either order).**

```lua
local SCOPE = "Shell"

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

-- Data colors, not chrome: indicator and drawing lines, and anything a
-- UIGradient paints (mini-chart segments, the nav accent line)
local function isDataColored(inst)
	if inst:FindFirstChildOfClass("UIGradient") then
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
	-- An active indicator toggle is filled with its series color on purpose
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
		-- Labels set to truncate ("…") are allowed not to fit; everything else must
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

### H3 — Shell layout check (Client datamodel, during Play)

**Pass = every value `true`.**

```lua
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local mb = Players.LocalPlayer.PlayerGui.TerminalGui.MainBackground
local topBar, screens, status = mb.TopBar, mb.ScreenContainer, mb:FindFirstChild("StatusBar")
local wordmark, pill, tabs = topBar:FindFirstChild("Wordmark"), topBar:FindFirstChild("BalancePill"), topBar.TabContainer
local inset = GuiService.TopbarInset
local viewport = workspace.CurrentCamera.ViewportSize

local tabsWidth = 0
for _, b in ipairs(tabs:GetChildren()) do
	if b:IsA("TextButton") then
		tabsWidth += b.AbsoluteSize.X
	end
end

local navBottom = topBar.AbsolutePosition.Y + topBar.AbsoluteSize.Y
local result = {
	fullWidth = math.abs(mb.AbsoluteSize.X - viewport.X) <= 1,
	fullHeight = math.abs(mb.AbsoluteSize.Y - viewport.Y) <= 1,
	-- On narrow windows the wordmark hides to make room for the tabs
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

local lines = { string.format("inset=%s viewport=%s", tostring(inset), tostring(viewport)) }
for k, v in pairs(result) do
	table.insert(lines, k .. "=" .. tostring(v))
end
return table.concat(lines, "\n")
```

### H4 — Read a player's server-side portfolio (Server datamodel, during Play)

`execute_luau` has its own `_G`, so this injects a real Script that copies the data into a `StringValue` both sides can read.

```lua
local probe = Instance.new("Script")
probe.Name = "TEST_PortfolioProbe"
probe.Source = [[
	local HttpService = game:GetService("HttpService")
	local player = game:GetService("Players"):GetPlayers()[1]
	local data = _G.PlayerData and _G.PlayerData[player.UserId]
	local out = Instance.new("StringValue")
	out.Name = "TEST_PortfolioProbeResult"
	out.Value = data and HttpService:JSONEncode(data.Portfolio) or "no data"
	out.Parent = game:GetService("ReplicatedStorage")
	script:Destroy()
]]
probe.Parent = game:GetService("ServerScriptService")
task.wait(1)
local result = game:GetService("ReplicatedStorage"):FindFirstChild("TEST_PortfolioProbeResult")
local value = result and result.Value or "probe did not run"
if result then
	result:Destroy()
end
return value
```

---

## File map

| File | Status | Responsibility |
|---|---|---|
| `src/shared/Modules/Multi/Theme.luau` | Create | Tokens, roles, `Theme.apply(root)` |
| `src/shared/Modules/Multi/MarketHoursModule.luau` | Modify | + `formatCountdown(seconds)` for the status bar |
| `src/client/Controllers/ShellController.client.luau` | Create | Full-screen layout, wordmark, balance pill, status bar, HUD hiding, runtime `Theme.apply` |
| `src/client/Controllers/TerminalController.client.luau` | Modify | Theme colors for tabs, toggles, presets, countdown; init the toggles it owns |
| `src/client/Controllers/TradeController.client.luau` | Modify | Theme colors/fonts for everything it builds; Buy/Sell resting + hover colors |
| `src/shared/Modules/Multi/ChartRenderer.luau` | Modify | Theme candle/grid/axis/badge colors and fonts; badge decimals ≥ $10k |
| `CLAUDE.md` | Modify | Document the theme system and shell |
| Studio `StarterGui.TerminalGui` (not in git) | Edit in Studio | Cleanup, `ThemeRole` tags, resting colors, stamped look |

---

### Task 0: Merge options trading phase 1, start the Phase 1 branch

**Files:** none edited by hand (git merge brings in the options work).

**Interfaces:**
- Consumes: branch `worktree-options-trading-phase1` (head `48228d1`).
- Produces: `main` containing options trading; branch `axiom-look-phase1` checked out in the main checkout. Later tasks edit the post-merge `TradeController.client.luau` (1,408 lines, constants at lines 57–70).

- [ ] **Step 1: Confirm starting state**

```bash
git -C /Users/killxinu/Documents/GitHub/TradingBlox status --short
git -C /Users/killxinu/Documents/GitHub/TradingBlox branch --show-current
git -C /Users/killxinu/Documents/GitHub/TradingBlox log --oneline -1 worktree-options-trading-phase1
```

Expected: branch `main`; status shows ` M docs/superpowers/specs/2026-09-20-options-trading-design.md` (Kevin's formatter reflow — leave it alone), `?? .claude/`, `?? docs/superpowers/plans/2026-09-20-options-trading-plan.md`; branch head `48228d1 Validate strike/expiration types in OptionSystem; update CLAUDE.md for options trading`.

- [ ] **Step 2: Remove main's untracked duplicate of the options plan (the merge brings the tracked copy)**

```bash
git -C /Users/killxinu/Documents/GitHub/TradingBlox show worktree-options-trading-phase1:docs/superpowers/plans/2026-09-20-options-trading-plan.md | cmp - /Users/killxinu/Documents/GitHub/TradingBlox/docs/superpowers/plans/2026-09-20-options-trading-plan.md && rm /Users/killxinu/Documents/GitHub/TradingBlox/docs/superpowers/plans/2026-09-20-options-trading-plan.md && echo removed
```

Expected: `removed` (and no `cmp` output). If `cmp` reports a difference, STOP and ask Kevin — the files were byte-identical on 2026-10-10.

- [ ] **Step 3: Merge**

```bash
git -C /Users/killxinu/Documents/GitHub/TradingBlox merge --no-ff worktree-options-trading-phase1 -m "Merge options trading phase 1" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Expected: merge commit created, no conflicts (main's only commits since the branch point are the Axiom spec and a `.gitignore` line).

- [ ] **Step 4: Confirm Rojo synced the merged code into Studio** (Edit datamodel)

```lua
local core = game:GetService("ServerScriptService").Core
local ev = game:GetService("ReplicatedStorage")
return string.format("OptionSystem bytes=%d | TradeController has PlayerOptionOrderEvent=%s",
	#core.OptionSystem.Source,
	tostring(string.find(game:GetService("StarterPlayer").StarterPlayerScripts.Controllers.TradeController.Source, "PlayerOptionOrderEvent", 1, true) ~= nil))
```

Expected: `OptionSystem bytes=` well above 0 (it was a 0-byte stub) and `has PlayerOptionOrderEvent=true`. If 0/false, Rojo isn't serving this checkout — ask Kevin to restart `rojo serve` from `/Users/killxinu/Documents/GitHub/TradingBlox` and reconnect the plugin.

- [ ] **Step 5: Run the options plan's final checklist in a playtest**

`start_stop_play(true)`, wait ~5s. Check NYSE status first (Client): `return require(game.ReplicatedStorage.Modules.Multi.MarketHoursModule).getMarketStatus(os.time())`. If `false`, run **H1a** and **H1b**, both with `OPEN = true`.

Record the starting balance (Client): `return game.Players.LocalPlayer:GetAttribute("Balance"), game.Players.LocalPlayer:GetAttribute("NetWorth")`.

Then, in order:
1. Click `LocalPlayer.PlayerGui.TerminalGui.MainBackground.TopBar.TabContainer.TradeButton`. Load AAPL (Client): `local box = game.Players.LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.TradeScreen.InputRow.TickerInput; box:CaptureFocus(); box.Text = "AAPL"; box:ReleaseFocus(true)`. Wait 4s.
2. Click `...TradeScreen.OptionChain.Toggle`. Wait 3s. List rows (Client): `local t = {}; for _, c in ipairs(game.Players.LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.TradeScreen.OptionChain.ChainData:GetChildren()) do if c.Name:match("^Strike_") and c:FindFirstChild("CallHitArea") then table.insert(t, c.Name) end end; return table.concat(t, ",")`. Expected: several `Strike_N` names.
3. Click `...ChainData.Strike_<first listed N>.CallHitArea`. Check (Client) `...TradeScreen.InputRow.ContractIndicator.Visible` is `true` and its `.Text` names AAPL and a strike.
4. Click `...TradeScreen.HeaderRow.BuyButton`. Expected: `Balance` drops by roughly ask × 100; `NetWorth` within a few dollars of before (spread only).
5. Click `...InputRow.ContractIndicator` (back to shares), click `BuyButton` again (1 share). Run **H4**: expected JSON contains both `"Shares":{"AAPL":...}` and an `"Options":{"AAPL...C...":...}` entry; `NetWorth` reflects both.
6. Click `SellButton` (sells the share). Select the same call again (step 3 path) and click `SellButton`. Run **H4**: expected no `AAPL` share entry and `"Options":[]` or `{}` (record removed, not left at 0). Balance back near start minus spread.
7. Select a call on AAPL, then load TSLA (step 1 snippet with `"TSLA"`). Expected: `ContractIndicator.Visible == false`; the step-2 list now shows TSLA rows (check one row's `StrikeLabel.Text` differs from AAPL's).
8. Closed-market rejection (tests the server's gate, which a modified client can't skip): stop and restart Play. If NYSE is actually closed, run only **H1b** with `OPEN = true` (the client lets the order through; the server must refuse it). If NYSE is actually open, run only **H1a** with `OPEN = false`. Load AAPL, select a call, click `BuyButton`. `get_console_output` must contain `[TradeController] Buy failed: Market is closed.` and `Balance` must be unchanged.
9. Click `...TradeScreen.QuoteDetails.TabHeaderContainer.Tab_OptionStats`, wait 3s. Expected (Client): `...TabContentContainer.Content_OptionStats` has children named `OS_*`.

`start_stop_play(false)`. If any item fails, fix it on `main` before continuing (it's local and unpushed) and report it to Kevin.

- [ ] **Step 6: Remove the worktree and branch, start Phase 1's branch**

```bash
git -C /Users/killxinu/Documents/GitHub/TradingBlox worktree remove .claude/worktrees/options-trading-phase1
git -C /Users/killxinu/Documents/GitHub/TradingBlox branch -d worktree-options-trading-phase1
git -C /Users/killxinu/Documents/GitHub/TradingBlox switch -c axiom-look-phase1
git -C /Users/killxinu/Documents/GitHub/TradingBlox branch --show-current
```

Expected: last line `axiom-look-phase1`. (`branch -d` succeeds because the branch is merged.)

---

### Task 1: `Theme.luau` — tokens, roles, `apply()`

**Files:**
- Create: `src/shared/Modules/Multi/Theme.luau`

**Interfaces:**
- Produces (used by Tasks 2–7):
  - `Theme.Colors.{Background, Panel, Raised, Border, Text, TextMuted, TextDisabled, Accent, AccentSoft, AccentTint, Up, UpHover, Down, DownHover}` : `Color3`
  - `Theme.Fonts.{UI, UISemibold, UIBold, Mono, MonoBold}` : `Font`
  - `Theme.TextSize.{Caption, Body, Title, Display}` : `number` (12/13/15/24)
  - `Theme.Radius` : `UDim` (0, 4)
  - `Theme.Roles[name]` — names: `Screen, Panel, PanelFlat, Raised, Pill, Divider, Guide, AccentFill, Scroll, Input, InputText, Text, TextStrong, TextMuted, Heading, HeadingUp, HeadingDown, Display, Number, NumberLarge, Button, ButtonPrimary, NumberDynamic, NumberLargeDynamic, LabelDynamic, HeadingDynamic, Tab, Toggle, Preset, ActionButton`
  - `Theme.apply(root: Instance) -> ()`
  - Studio path: `ReplicatedStorage.Modules.Multi.Theme`

- [ ] **Step 1: Write the check (Edit datamodel) and run it — it must fail**

```lua
local folder = Instance.new("Folder")
folder.Name = "FreshRequire_Theme"
folder.Parent = game:GetService("ServerStorage")
local ok, Theme = pcall(function()
	game:GetService("ReplicatedStorage").Modules.Multi.Theme:Clone().Parent = folder
	return require(folder.Theme)
end)
if not ok then
	folder:Destroy()
	return "FAIL: " .. tostring(Theme)
end

local odd = Color3.fromRGB(1, 2, 3)
local gui = Instance.new("ScreenGui")
local function make(class, role, parent)
	local inst = Instance.new(class)
	if role then
		inst:SetAttribute("ThemeRole", role)
	end
	inst.Parent = parent
	return inst
end

local panel = make("Frame", "Panel", gui)
local oldCorner = Instance.new("UICorner")
oldCorner.CornerRadius = UDim.new(0, 12)
oldCorner.Parent = panel
local number = make("TextLabel", "Number", panel)
local dynamic = make("TextLabel", "NumberDynamic", panel)
dynamic.TextColor3 = odd
local input = make("TextBox", "Input", panel)
local scroll = make("ScrollingFrame", "Scroll", panel)
local untagged = make("Frame", nil, panel)
untagged.BackgroundColor3 = odd
local bogus = make("Frame", "NoSuchRole", panel)
bogus.BackgroundColor3 = odd

Theme.apply(gui)

local panelStroke = panel:FindFirstChildOfClass("UIStroke")
local inputStroke = input:FindFirstChildOfClass("UIStroke")
local cornerCount = 0
for _, c in ipairs(panel:GetChildren()) do
	if c:IsA("UICorner") then
		cornerCount += 1
	end
end
local checks = {
	panelBg = panel.BackgroundColor3:ToHex() == Theme.Colors.Panel:ToHex(),
	panelStrokeBorderMode = panelStroke ~= nil and panelStroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Border and panelStroke.Color:ToHex() == Theme.Colors.Border:ToHex(),
	panelCornerFlattened = cornerCount == 1 and oldCorner.CornerRadius == UDim.new(0, 4),
	numberMono = number.FontFace.Family == Theme.Fonts.Mono.Family and number.TextSize == 13 and number.TextColor3:ToHex() == Theme.Colors.Text:ToHex(),
	dynamicColorUntouched = dynamic.TextColor3:ToHex() == odd:ToHex() and dynamic.FontFace.Family == Theme.Fonts.Mono.Family,
	inputPlaceholderAndStroke = input.PlaceholderColor3:ToHex() == Theme.Colors.TextMuted:ToHex() and inputStroke ~= nil,
	scrollBarThemed = scroll.ScrollBarImageColor3:ToHex() == Theme.Colors.TextDisabled:ToHex(),
	untaggedUntouched = untagged.BackgroundColor3:ToHex() == odd:ToHex(),
	unknownRoleUntouched = bogus.BackgroundColor3:ToHex() == odd:ToHex(),
}
gui:Destroy()
folder:Destroy()

local lines = {}
for k, v in pairs(checks) do
	table.insert(lines, k .. "=" .. tostring(v))
end
table.sort(lines)
return table.concat(lines, "\n")
```

Expected now: `FAIL: Theme is not a valid member of Folder "ReplicatedStorage.Modules.Multi"` (or similar).

- [ ] **Step 2: Create `src/shared/Modules/Multi/Theme.luau`**

```lua
-- Theme.luau
--
-- Single source of truth for TradingBlox's Axiom-style look. Colors, fonts
-- and text sizes are tokens; a UI element opts in by carrying a `ThemeRole`
-- string attribute, and Theme.apply stamps that role's properties onto it.
--
-- Roles deliberately leave out any property a controller changes at runtime
-- (up/down price colors, the active tab, toggle states, preset dimming), so
-- apply() and the controllers never write the same property - LocalScript
-- start order can't matter. Code that builds UI at runtime reads
-- Theme.Colors / Theme.Fonts directly instead of tagging.

local Theme = {}

local BUILDER_SANS = "rbxassetid://16658221428"
local ROBOTO_MONO = "rbxasset://fonts/families/RobotoMono.json"

Theme.Colors = {
	Background = Color3.fromRGB(8, 9, 13),
	Panel = Color3.fromRGB(14, 16, 22),
	Raised = Color3.fromRGB(21, 24, 34), -- buttons, inputs, headers, hover
	Border = Color3.fromRGB(35, 39, 54), -- strokes and 1px dividers
	Text = Color3.fromRGB(231, 233, 240),
	TextMuted = Color3.fromRGB(139, 144, 163),
	TextDisabled = Color3.fromRGB(91, 96, 115), -- e.g. Sell presets with no position
	Accent = Color3.fromRGB(154, 107, 255),
	AccentSoft = Color3.fromRGB(224, 170, 255), -- pale end of the mini-chart gradient
	AccentTint = Color3.fromRGB(30, 24, 48), -- in-the-money option rows
	Up = Color3.fromRGB(46, 189, 133),
	UpHover = Color3.fromRGB(39, 161, 113), -- Up at 85%
	Down = Color3.fromRGB(240, 74, 108),
	DownHover = Color3.fromRGB(204, 63, 92), -- Down at 85%
}

Theme.Fonts = {
	UI = Font.new(BUILDER_SANS),
	UISemibold = Font.new(BUILDER_SANS, Enum.FontWeight.SemiBold),
	UIBold = Font.new(BUILDER_SANS, Enum.FontWeight.Bold),
	Mono = Font.new(ROBOTO_MONO),
	MonoBold = Font.new(ROBOTO_MONO, Enum.FontWeight.Bold),
}

Theme.TextSize = {
	Caption = 12,
	Body = 13,
	Title = 15,
	Display = 24,
}

Theme.Radius = UDim.new(0, 4)

-- Values are token names. `Stroke` names the color of a 1px border;
-- `Corner = true` creates a UICorner when the element has none (an existing
-- UICorner on any tagged element is always flattened to Theme.Radius).
Theme.Roles = {
	-- Surfaces
	Screen = { BackgroundColor3 = "Background" },
	Panel = { BackgroundColor3 = "Panel", Stroke = "Border", Corner = true },
	PanelFlat = { BackgroundColor3 = "Panel" },
	Raised = { BackgroundColor3 = "Raised", Corner = true },
	Pill = { BackgroundColor3 = "Raised", Stroke = "Border", Corner = true },
	Divider = { BackgroundColor3 = "Border" },
	Guide = { BackgroundColor3 = "TextMuted" },
	AccentFill = { BackgroundColor3 = "Accent" },
	Scroll = {}, -- transparent scrolling lists: only the scrollbar is themed

	-- Inputs
	Input = {
		BackgroundColor3 = "Raised",
		Stroke = "Border",
		Corner = true,
		TextColor3 = "Text",
		PlaceholderColor3 = "TextMuted",
		FontFace = "UI",
		TextSize = "Body",
	},
	InputText = { TextColor3 = "Text", PlaceholderColor3 = "TextMuted", FontFace = "UI", TextSize = "Body" },

	-- Text
	Text = { TextColor3 = "Text", FontFace = "UI", TextSize = "Body" },
	TextStrong = { TextColor3 = "Text", FontFace = "UISemibold", TextSize = "Body" },
	TextMuted = { TextColor3 = "TextMuted", FontFace = "UI", TextSize = "Caption" },
	Heading = { TextColor3 = "Text", FontFace = "UIBold", TextSize = "Title" },
	HeadingUp = { TextColor3 = "Up", FontFace = "UIBold", TextSize = "Title" },
	HeadingDown = { TextColor3 = "Down", FontFace = "UIBold", TextSize = "Title" },
	Display = { TextColor3 = "Text", FontFace = "UIBold", TextSize = "Display" },
	Number = { TextColor3 = "Text", FontFace = "Mono", TextSize = "Body" },
	NumberLarge = { TextColor3 = "Text", FontFace = "Mono", TextSize = "Display" },

	-- Controls
	Button = { BackgroundColor3 = "Raised", TextColor3 = "Text", FontFace = "UISemibold", TextSize = "Body", Corner = true },
	ButtonPrimary = { BackgroundColor3 = "Accent", TextColor3 = "Text", FontFace = "UIBold", TextSize = "Body", Corner = true },

	-- Controller-colored: font, size and shape only - a controller owns the colors
	NumberDynamic = { FontFace = "Mono", TextSize = "Body" },
	NumberLargeDynamic = { FontFace = "Mono", TextSize = "Display" },
	LabelDynamic = { FontFace = "UI", TextSize = "Body" },
	HeadingDynamic = { FontFace = "UISemibold", TextSize = "Title" },
	Tab = { FontFace = "UISemibold", TextSize = "Body" },
	Toggle = { FontFace = "UISemibold", TextSize = "Body", Corner = true },
	Preset = { BackgroundColor3 = "Raised", FontFace = "Mono", TextSize = "Body", Corner = true },
	ActionButton = { TextColor3 = "Text", FontFace = "UIBold", TextSize = "Body", Corner = true },
}

local TOKEN_TABLES = {
	BackgroundColor3 = Theme.Colors,
	TextColor3 = Theme.Colors,
	PlaceholderColor3 = Theme.Colors,
	FontFace = Theme.Fonts,
	TextSize = Theme.TextSize,
	Stroke = Theme.Colors,
}

-- Fail at require time if a role names a token that doesn't exist, rather
-- than erroring mid-apply on whichever element reaches it first.
for roleName, role in pairs(Theme.Roles) do
	for property, token in pairs(role) do
		if property ~= "Corner" then
			local tokens = TOKEN_TABLES[property]

			assert(tokens and tokens[token] ~= nil, string.format("[Theme] Role %s: unknown %s token %q", roleName, property, tostring(token)))
		end
	end
end

local function isTextObject(instance)
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function canSet(instance, property)
	if property == "BackgroundColor3" then
		return true
	elseif property == "PlaceholderColor3" then
		return instance:IsA("TextBox")
	end

	return isTextObject(instance)
end

local function applyStroke(instance, colorToken)
	local stroke = instance:FindFirstChildOfClass("UIStroke")

	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "ThemeStroke"
		stroke.Parent = instance
	end

	stroke.Color = Theme.Colors[colorToken]
	stroke.Thickness = 1
	stroke.Transparency = 0
	-- The default (Contextual) outlines a text object's glyphs instead of its box
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local function applyRole(instance, role)
	for property, token in pairs(role) do
		if property == "Stroke" then
			applyStroke(instance, token)
		elseif property ~= "Corner" and canSet(instance, property) then
			instance[property] = TOKEN_TABLES[property][token]
		end
	end

	local corner = instance:FindFirstChildOfClass("UICorner")

	if not corner and role.Corner then
		corner = Instance.new("UICorner")
		corner.Name = "ThemeCorner"
		corner.Parent = instance
	end

	if corner then
		corner.CornerRadius = Theme.Radius
	end

	if instance:IsA("ScrollingFrame") then
		instance.ScrollBarImageColor3 = Theme.Colors.TextDisabled
	end
end

-- Stamps every tagged GuiObject under (and including) root. Untagged
-- elements are never touched, so anything that still looks old is visibly
-- a missed tag rather than a silent half-styling.
function Theme.apply(root: Instance)
	local targets = root:GetDescendants()
	table.insert(targets, root)

	for _, instance in ipairs(targets) do
		local roleName = instance:GetAttribute("ThemeRole")

		if roleName ~= nil and instance:IsA("GuiObject") then
			local role = Theme.Roles[roleName]

			if role then
				applyRole(instance, role)
			else
				warn(string.format("[Theme] Unknown ThemeRole %q on %s", tostring(roleName), instance:GetFullName()))
			end
		end
	end
end

return Theme
```

- [ ] **Step 3: Re-run the Step 1 check — it must pass**

Expected (sorted):
```
dynamicColorUntouched=true
inputPlaceholderAndStroke=true
numberMono=true
panelBg=true
panelCornerFlattened=true
panelStrokeBorderMode=true
scrollBarThemed=true
unknownRoleUntouched=true
untaggedUntouched=true
```
`get_console_output` shows exactly one `[Theme] Unknown ThemeRole "NoSuchRole"` warning (from the test's deliberate bogus role) and no errors.

- [ ] **Step 4: Lint and commit**

```bash
cd /Users/killxinu/Documents/GitHub/TradingBlox && command -v selene >/dev/null && selene src/shared/Modules/Multi/Theme.luau || echo "selene not installed - skipped"
git -C /Users/killxinu/Documents/GitHub/TradingBlox add src/shared/Modules/Multi/Theme.luau
git -C /Users/killxinu/Documents/GitHub/TradingBlox commit -m "Add Theme module: Axiom-style tokens, roles, and apply()" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Studio — back up, clean up, tag every element, stamp the look

**Files:** none in git (all edits are to `StarterGui.TerminalGui` in the Studio place). The tagging script below is the git record of the old-color → role mapping.

**Interfaces:**
- Consumes: `Theme` (Task 1) at `ReplicatedStorage.Modules.Multi.Theme`.
- Produces: every styled element in `StarterGui.TerminalGui` carries a `ThemeRole` attribute (role names from Task 1); `MacButtons` gone; `ServerStorage.TerminalGui_PreAxiomBackup` exists. Later tasks rely on these exact instance paths, unchanged: `MainBackground.TopBar.{TabContainer, AccentLine.AccentGradient}`, `MainBackground.ScreenContainer.*`, and `TabContainer.UIListLayout`.

All snippets: `execute_luau`, `datamodel_type: "Edit"`, Studio not playing.

- [ ] **Step 1: Back up the UI**

```lua
local ServerStorage = game:GetService("ServerStorage")
assert(not ServerStorage:FindFirstChild("TerminalGui_PreAxiomBackup"), "Backup already exists - not overwriting it")
local backup = game:GetService("StarterGui").TerminalGui:Clone()
backup.Name = "TerminalGui_PreAxiomBackup"
backup.Parent = ServerStorage
return #backup:GetDescendants()
```

Expected: `333`.

- [ ] **Step 2: Ask Kevin to save the place** (File → Save to Roblox, or Ctrl/Cmd+S) and wait for confirmation. Tell him the undo: delete `StarterGui.TerminalGui`, move `ServerStorage.TerminalGui_PreAxiomBackup` into `StarterGui`, rename it `TerminalGui`.

- [ ] **Step 3: Cleanup**

```lua
local gui = game:GetService("StarterGui").TerminalGui
local mb = gui.MainBackground
local chain = mb.ScreenContainer.TradeScreen.OptionChain.ChainData
local trade = mb.ScreenContainer.TradeScreen
local done = {}

-- Decorative window buttons (no code references them) and window chrome that
-- doesn't apply to a full-screen terminal
mb.TopBar.MacButtons:Destroy()
table.insert(done, "MacButtons removed")
local topBarGradient = mb.TopBar:FindFirstChildOfClass("UIGradient")
if topBarGradient then
	topBarGradient:Destroy()
	table.insert(done, "TopBar gradient removed")
end
mb:FindFirstChildOfClass("UISizeConstraint"):Destroy()
mb:FindFirstChildOfClass("UICorner"):Destroy()
table.insert(done, "MainBackground size constraint + corner removed")

-- Unreferenced leftovers that render phantom "Label" rows (verified: no
-- script references these names)
for _, template in ipairs({ chain.StrikeRow_Template, trade.PositionsTable.OpenPosition_Template, trade.NewsFeed.NewsItem_Template }) do
	template.Visible = false
end
table.insert(done, "3 stale templates hidden")

-- Survive character resets: controllers hold references to this GUI
gui.ResetOnSpawn = false

-- Mirror ShellController's runtime layout so the editor shows the real shell
gui.ScreenInsets = Enum.ScreenInsets.None
mb.AnchorPoint = Vector2.zero
mb.Position = UDim2.fromScale(0, 0)
mb.Size = UDim2.fromScale(1, 1)
table.insert(done, "full screen")

return table.concat(done, "\n")
```

Expected: the five lines above, no error.

- [ ] **Step 4: Write the "untagged" check and run it — it must report many**

```lua
local root = game:GetService("StarterGui").TerminalGui
local function isText(inst)
	return inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
end
local missing = {}
for _, inst in ipairs(root:GetDescendants()) do
	local needsRole = inst:IsA("GuiObject")
		and not inst:FindFirstChildOfClass("UIGradient")
		and (inst.BackgroundTransparency < 1 or isText(inst))
	if needsRole and inst:GetAttribute("ThemeRole") == nil then
		table.insert(missing, (string.gsub(inst:GetFullName(), "^StarterGui%.TerminalGui%.", "")))
	end
end
return #missing .. " untagged\n" .. table.concat(missing, "\n")
```

Expected now: well over 100 untagged.

- [ ] **Step 5: Run the tagging script**

```lua
-- Tags every styled element in StarterGui.TerminalGui with a ThemeRole.
-- EXPLICIT/PATTERNS first (controller-colored elements, and anything the
-- color rules would misread), then rules keyed on class + current color.
-- Prints anything neither covers; expected leftovers: 0.
local root = game:GetService("StarterGui").TerminalGui

local function rgb(c)
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function shortPath(inst)
	local parts = {}
	local cur = inst
	while cur and cur ~= root do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	local p = table.concat(parts, ".")
	p = string.gsub(p, "^MainBackground%.ScreenContainer%.", "SC.")
	p = string.gsub(p, "^MainBackground%.", "MB.")
	return p
end

local CHARTS = "SC.ChartsScreen."
local AT = CHARTS .. "ActiveTraderPanel."
local WL = CHARTS .. "WatchlistPanel."
local DASH = "SC.DashboardScreen."
local COUNTDOWN = DASH .. "DashboardGrid.MainWorkspace.TopRow.CountdownWidget."
local TRADE = "SC.TradeScreen."

local EXPLICIT = {
	-- Shell
	["MainBackground"] = "Screen",
	["MB.TopBar.TabContainer.DashboardButton"] = "Tab",
	["MB.TopBar.TabContainer.PortfolioButton"] = "Tab",
	["MB.TopBar.TabContainer.TradeButton"] = "Tab",
	["MB.TopBar.TabContainer.ChartsButton"] = "Tab",

	-- Dashboard
	[DASH .. "GreetingBar.GreetingText"] = "Display",
	[DASH .. "DashboardGrid.LeftSidebar.AccountInfoWidget.TitleRow.TextLabel"] = "TextStrong",
	[DASH .. "DashboardGrid.LeftSidebar.WatchlistWidget.TitleRow.TextLabel"] = "TextStrong",
	[COUNTDOWN .. "TitleText"] = "HeadingDynamic",
	[COUNTDOWN .. "TimeContainer.HoursBlock"] = "Raised",
	[COUNTDOWN .. "TimeContainer.MinutesBlock"] = "Raised",
	[COUNTDOWN .. "TimeContainer.SecondsBlock"] = "Raised",
	["SC.PortfolioScreen"] = "Screen",

	-- Charts: chart frame and toolbars
	[CHARTS .. "MainChart"] = "Screen",
	[CHARTS .. "MainChart.TopToolbar.TickerInputBox"] = "Input",
	[CHARTS .. "MainChart.TopToolbar.TimeframeDropdown.TimeDropdownList.1MinuteButton"] = "Toggle",
	[CHARTS .. "MainChart.TopToolbar.TimeframeDropdown.TimeDropdownList.5MinuteButton"] = "Toggle",
	[CHARTS .. "MainChart.TopToolbar.TimeframeDropdown.TimeDropdownList.30MinuteButton"] = "Toggle",
	[CHARTS .. "MainChart.TopToolbar.TimeframeDropdown.TimeDropdownList.1HourButton"] = "Toggle",
	[CHARTS .. "MainChart.TopToolbar.TimeframeDropdown.TimeDropdownList.1DayButton"] = "Toggle",
	[CHARTS .. "MainChart.TopToolbar.IndicatorsDropdown.IndicatorsDropdownList.SMA20Button"] = "Toggle",
	[CHARTS .. "MainChart.TopToolbar.IndicatorsDropdown.IndicatorsDropdownList.SMA50Button"] = "Toggle",
	[CHARTS .. "MainChart.TopToolbar.IndicatorsDropdown.IndicatorsDropdownList.EMA20Button"] = "Toggle",
	[CHARTS .. "MainChart.TopToolbar.IndicatorsDropdown.IndicatorsDropdownList.EMA50Button"] = "Toggle",
	[CHARTS .. "MainChart.LeftToolbar.CursorToolButton"] = "Toggle",
	[CHARTS .. "MainChart.LeftToolbar.TrendLineToolButton"] = "Toggle",
	[CHARTS .. "MainChart.LeftToolbar.HorizontalLineToolButton"] = "Toggle",
	[CHARTS .. "MainChart.RightAxis.HoverPriceTag"] = "Number",
	[CHARTS .. "MainChart.ChartCanvas.HoverTimeTag"] = "Number",
	[CHARTS .. "MainChart.ChartCanvas.ChartLegend.ChartTickerLabel"] = "TextStrong",
	[CHARTS .. "Sidebar.ToggleActiveTraderButton"] = "Button",
	[CHARTS .. "Sidebar.ToggleSymbolInfoButton"] = "Button",
	[CHARTS .. "Sidebar.ToggleWatchlistButton"] = "Button",
	[CHARTS .. "Sidebar.PlaceholderButton"] = "Button",

	-- Charts: Active Trader
	[AT .. "ActiveTraderTopBar"] = "Raised",
	[AT .. "ActiveTraderTopBar.TextLabel"] = "TextStrong",
	[AT .. "ContentArea.TickerLabel"] = "Heading",
	[AT .. "ContentArea.StatusLabel"] = "LabelDynamic",
	[AT .. "ContentArea.BuyHeaderRow.Label"] = "HeadingUp",
	[AT .. "ContentArea.SellHeaderRow.Label"] = "HeadingDown",

	-- Charts: Symbol Info
	[CHARTS .. "SymbolInfoPanel.SymbolInfoTopBar"] = "Raised",
	[CHARTS .. "SymbolInfoPanel.SymbolInfoTopBar.TickerNameLabel"] = "TextStrong",

	-- Charts: Watchlist
	[WL .. "WatchlistTopBar"] = "Raised",
	[WL .. "WatchlistTopBar.TitleLabel"] = "TextStrong",
	[WL .. "AddTickerRow.AddTickerButton"] = "ButtonPrimary",
	[WL .. "ListContainer"] = "Scroll",
	[WL .. "ListContainer.RowTemplate.RowButton"] = "Text", -- empty-text button; normalizes its LegacyArial font
	[WL .. "ListContainer.RowTemplate.RowButton.TickerLabel"] = "TextStrong",
	[WL .. "ListContainer.RowTemplate.RowButton.PriceLabel"] = "Number",
	[WL .. "ListContainer.RowTemplate.RowButton.ChangeLabel"] = "NumberDynamic",
	[WL .. "ListContainer.RowTemplate.RemoveButton"] = "TextMuted",

	-- Trade
	[TRADE .. "HeaderRow.TickerLabel"] = "Display",
	[TRADE .. "HeaderRow.PriceLabel"] = "NumberLargeDynamic",
	[TRADE .. "HeaderRow.ChangeLabel"] = "NumberDynamic",
	[TRADE .. "HeaderRow.BuyButton"] = "ActionButton",
	[TRADE .. "HeaderRow.SellButton"] = "ActionButton",
	[TRADE .. "QuoteDetails.TabHeaderContainer.Tab_QuoteDetails"] = "Tab",
	[TRADE .. "QuoteDetails.TabHeaderContainer.Tab_AnalystReports"] = "Tab",
	[TRADE .. "QuoteDetails.TabHeaderContainer.Tab_Fundamentals"] = "Tab",
	[TRADE .. "QuoteDetails.TabHeaderContainer.Tab_OptionStats"] = "Tab",
	[TRADE .. "QuoteDetails.TabContentContainer"] = "PanelFlat",
	[TRADE .. "OptionChain.ChainData"] = "Scroll",
}

local PATTERNS = {
	{ "^SC%.ChartsScreen%.ActiveTraderPanel%.ContentArea%.%a+PresetsGrid%.%a+Preset_%d+$", "Preset" },
	{ "^SC%.ChartsScreen%.SymbolInfoPanel%.ContentArea%.%w+Row%.Value$", "Number" },
}

local FRAME_BG = {
	["10,10,10"] = "Screen",
	["19,23,34"] = "Screen",
	["15,15,15"] = "Panel",
	["20,20,20"] = "Panel",
	["30,34,45"] = "Panel",
	["46,46,46"] = "Panel",
	["53,57,75"] = "Raised",
	["25,25,25"] = "Raised",
	["30,30,30"] = "Raised",
	["20,22,30"] = "Raised",
	["38,42,54"] = "Raised",
	["18,22,28"] = "Input",
	["74,74,74"] = "Divider",
	["132,142,156"] = "Guide",
	["240,240,240"] = "AccentFill",
}
local BUTTON_BG = { ["42,46,57"] = true, ["30,30,30"] = true, ["30,34,45"] = true, ["255,255,255"] = true }
local TEXT_MUTED = { ["120,123,134"] = true, ["132,142,156"] = true, ["150,150,150"] = true, ["160,165,175"] = true }
local TEXT_LIGHT = { ["209,212,220"] = true, ["240,240,240"] = true, ["255,255,255"] = true }

local function isText(inst)
	return inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
end

local function roleByRule(inst)
	local hasBg = inst.BackgroundTransparency < 1

	if inst:IsA("TextBox") then
		return hasBg and "Input" or "InputText"
	elseif inst:IsA("TextButton") and hasBg then
		return BUTTON_BG[rgb(inst.BackgroundColor3)] and "Button" or nil
	elseif isText(inst) then
		if string.find(tostring(inst.FontFace.Family), "RobotoMono", 1, true) then
			return inst.TextSize >= 20 and "NumberLarge" or "Number"
		elseif TEXT_MUTED[rgb(inst.TextColor3)] then
			return "TextMuted"
		elseif TEXT_LIGHT[rgb(inst.TextColor3)] then
			return "Text"
		end
		return nil
	elseif hasBg then
		return FRAME_BG[rgb(inst.BackgroundColor3)]
	end

	return false -- transparent container: nothing to style
end

local counts, leftovers = {}, {}
local targets = root:GetDescendants()

for _, inst in ipairs(targets) do
	if inst:IsA("GuiObject") and not inst:FindFirstChildOfClass("UIGradient") then
		local p = shortPath(inst)
		local role = EXPLICIT[p]

		if not role then
			for _, pattern in ipairs(PATTERNS) do
				if string.match(p, pattern[1]) then
					role = pattern[2]
					break
				end
			end
		end

		if role == nil then
			role = roleByRule(inst)
		end

		if role then
			inst:SetAttribute("ThemeRole", role)
			counts[role] = (counts[role] or 0) + 1
		elseif role == nil then
			table.insert(leftovers, p .. " [" .. inst.ClassName .. "] bg=" .. rgb(inst.BackgroundColor3) .. (isText(inst) and (" text=" .. rgb(inst.TextColor3)) or ""))
		end
	end
end

local summary = {}
for role, n in pairs(counts) do
	table.insert(summary, role .. "=" .. n)
end
table.sort(summary)
return "tagged: " .. table.concat(summary, ", ") .. "\nleftovers: " .. #leftovers .. "\n" .. table.concat(leftovers, "\n")
```

Expected: `leftovers: 0`. If anything is listed, add it to `EXPLICIT` with the role its look and controller ownership call for (check the controllers with `grep -n "<ElementName>" src/client/Controllers/*.luau` — if a controller writes its color, use a controller-colored role), re-run this step, and add the entry to this plan's `EXPLICIT` table in the same commit as Task 7's docs so the mapping stays recorded.

- [ ] **Step 6: Re-run the Step 4 check — it must pass**

Expected: `0 untagged`.

- [ ] **Step 7: Stamp resting colors and the theme**

```lua
local folder = Instance.new("Folder")
folder.Name = "FreshRequire_Stamp"
folder.Parent = game:GetService("ServerStorage")
game:GetService("ReplicatedStorage").Modules.Multi.Theme:Clone().Parent = folder
local Theme = require(folder.Theme)
local root = game:GetService("StarterGui").TerminalGui
local C = Theme.Colors

-- Controller-colored roles carry no color, so give them their resting
-- color once here; the owning controller takes over at runtime.
local RESTING = {
	Tab = { TextColor3 = C.TextMuted },
	Toggle = { BackgroundColor3 = C.Raised, TextColor3 = C.TextMuted },
	NumberDynamic = { TextColor3 = C.Text },
	NumberLargeDynamic = { TextColor3 = C.Text },
	LabelDynamic = { TextColor3 = C.TextMuted },
	HeadingDynamic = { TextColor3 = C.TextMuted },
}

local stamped = 0
for _, inst in ipairs(root:GetDescendants()) do
	local resting = RESTING[inst:GetAttribute("ThemeRole")]
	if resting then
		for property, value in pairs(resting) do
			inst[property] = value
		end
		stamped += 1
	end
end

local content = root.MainBackground.ScreenContainer.ChartsScreen.ActiveTraderPanel.ContentArea
for _, pair in ipairs({ { content.BuyPresetsGrid, C.Up }, { content.SellPresetsGrid, C.Down } }) do
	for _, button in ipairs(pair[1]:GetChildren()) do
		if button:IsA("TextButton") then
			button.TextColor3 = pair[2]
			local stroke = button:FindFirstChild("Stroke")
			if stroke then
				stroke.Color = pair[2]
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			end
			stamped += 1
		end
	end
end

local header = root.MainBackground.ScreenContainer.TradeScreen.HeaderRow
header.BuyButton.BackgroundColor3 = C.Up
header.SellButton.BackgroundColor3 = C.Down

Theme.apply(root)
folder:Destroy()
return "resting colors stamped on " .. stamped .. " elements; theme applied"
```

Expected: `resting colors stamped on <N> elements; theme applied` with N ≥ 40, and no `[Theme]` warnings in `get_console_output`.

- [ ] **Step 8: Edit-mode palette check** (static version of H2 over the whole place UI; skips the three hidden templates and gradient-painted elements; ignores text fit, which Task 7 checks in Play)

```lua
local folder = Instance.new("Folder")
folder.Name = "FreshRequire_Audit"
folder.Parent = game:GetService("ServerStorage")
game:GetService("ReplicatedStorage").Modules.Multi.Theme:Clone().Parent = folder
local Theme = require(folder.Theme)
folder:Destroy()

local root = game:GetService("StarterGui").TerminalGui
local allowed, sizes = {}, {}
for _, c in pairs(Theme.Colors) do
	allowed[c:ToHex()] = true
end
for _, s in pairs(Theme.TextSize) do
	sizes[s] = true
end

local function underTemplate(inst)
	local cur = inst
	while cur and cur ~= root do
		if string.match(cur.Name, "_Template$") then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local problems, families = {}, {}
for _, inst in ipairs(root:GetDescendants()) do
	if inst:IsA("GuiObject") and not inst:FindFirstChildOfClass("UIGradient") and not underTemplate(inst) then
		local name = string.gsub(inst:GetFullName(), "^StarterGui%.TerminalGui%.MainBackground%.", "")
		if inst.BackgroundTransparency < 1 and not allowed[inst.BackgroundColor3:ToHex()] then
			table.insert(problems, "bg   " .. name .. " #" .. inst.BackgroundColor3:ToHex())
		end
		local stroke = inst:FindFirstChildOfClass("UIStroke")
		if stroke and not allowed[stroke.Color:ToHex()] then
			table.insert(problems, "line " .. name .. " #" .. stroke.Color:ToHex())
		end
		if (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")) then
			if inst.Text ~= "" and not allowed[inst.TextColor3:ToHex()] then
				table.insert(problems, "text " .. name .. " #" .. inst.TextColor3:ToHex())
			end
			if not sizes[inst.TextSize] then
				table.insert(problems, "size " .. name .. " " .. inst.TextSize)
			end
			families[tostring(inst.FontFace.Family)] = true
		end
	end
end
local fam = {}
for f in pairs(families) do
	table.insert(fam, f)
end
return #problems .. " problem(s)\n" .. table.concat(problems, "\n") .. "\nfont families: " .. table.concat(fam, ", ")
```

Expected: `0 problem(s)` and font families exactly `rbxassetid://16658221428, rbxasset://fonts/families/RobotoMono.json` (either order).

- [ ] **Step 9: Ask Kevin to save the place again**, and wait for confirmation. No git commit for this task (nothing in `src/` changed); the tagging table above is the record.

---

### Task 3: Shell — `ShellController` + `MarketHoursModule.formatCountdown`

**Files:**
- Modify: `src/shared/Modules/Multi/MarketHoursModule.luau` (add before the final `return MarketHoursModule`, currently line 135)
- Create: `src/client/Controllers/ShellController.client.luau`

**Interfaces:**
- Consumes: `Theme.apply`, `Theme.Colors.{Up, TextMuted, Border, Accent}` (Task 1); tagged tree + `ResetOnSpawn = false` (Task 2); `NumberModule.format(amount) -> string`; `MarketHoursModule.getMarketStatus(time) -> (isOpen: boolean, targetTime: number)`.
- Produces: `MarketHoursModule.formatCountdown(seconds: number) -> string`; runtime instances `MainBackground.TopBar.Wordmark` (TextLabel), `MainBackground.TopBar.BalancePill` (Frame) with child `BalanceValue` (TextLabel), `MainBackground.StatusBar` (Frame) with children `TopEdge`, `MarketDot`, `MarketLabel`, `NetWorthValue`, `NetWorthCaption`. Tab switching stays in `TerminalController`.

- [ ] **Step 1: Write the countdown check (Edit datamodel) and run it — it must fail**

```lua
local folder = Instance.new("Folder")
folder.Name = "FreshRequire_MarketHours"
folder.Parent = game:GetService("ServerStorage")
game:GetService("ReplicatedStorage").Modules.Multi.MarketHoursModule:Clone().Parent = folder
local MarketHoursModule = require(folder.MarketHoursModule)
folder:Destroy()

if type(MarketHoursModule.formatCountdown) ~= "function" then
	return "FAIL: formatCountdown missing"
end

local cases = {
	{ 0, "0m 0s" },
	{ 59, "0m 59s" },
	{ 3599, "59m 59s" },
	{ 3600, "1h 0m" },
	{ 3 * 3600 + 12 * 60 + 5, "3h 12m" },
	{ 86399, "23h 59m" },
	{ 86400, "1d 0h" },
	{ 2 * 86400 + 17 * 3600 + 30, "2d 17h" }, -- Friday close -> Monday open
	{ -5, "0m 0s" }, -- target already passed: never negative
	{ 90.7, "1m 30s" },
}
local failures = {}
for _, case in ipairs(cases) do
	local got = MarketHoursModule.formatCountdown(case[1])
	if got ~= case[2] then
		table.insert(failures, string.format("%s -> %q (want %q)", tostring(case[1]), got, case[2]))
	end
end
return #failures == 0 and "PASS" or ("FAIL\n" .. table.concat(failures, "\n"))
```

Expected now: `FAIL: formatCountdown missing`.

- [ ] **Step 2: Add `formatCountdown` to `MarketHoursModule.luau`** — insert above `return MarketHoursModule`:

```lua
-- Public: compact countdown for the status bar - "2d 17h", "3h 12m" or
-- "12m 30s" depending on how far away the target is. Never negative.
function MarketHoursModule.formatCountdown(seconds)
	seconds = math.max(0, math.floor(seconds))

	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if days >= 1 then
		return string.format("%dd %dh", days, hours)
	elseif hours >= 1 then
		return string.format("%dh %dm", hours, minutes)
	end

	return string.format("%dm %ds", minutes, seconds % 60)
end

```

- [ ] **Step 3: Re-run the Step 1 check** — expected `PASS`.

- [ ] **Step 4: Create `src/client/Controllers/ShellController.client.luau`**

```lua
-- ShellController.client.luau
--
-- Owns the full-screen terminal shell around the screens: sizes the window
-- to the whole viewport, lays the nav bar out around Roblox's own top-bar
-- buttons, adds the wordmark, balance pill and bottom status bar, and stamps
-- the theme onto all of TerminalGui once at startup. Switching tabs stays in
-- TerminalController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
local NumberModule = require(ReplicatedStorage.Modules.Multi.NumberModule)
local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local TerminalGui = PlayerGui:WaitForChild("TerminalGui")
local MainBackground = TerminalGui:WaitForChild("MainBackground")
local TopBar = MainBackground:WaitForChild("TopBar")
local TabContainer = TopBar:WaitForChild("TabContainer")
local TabLayout = TabContainer:WaitForChild("UIListLayout")
local AccentLine = TopBar:WaitForChild("AccentLine")
local AccentGradient = AccentLine:WaitForChild("AccentGradient")
local ScreenContainer = MainBackground:WaitForChild("ScreenContainer")

-- Layout Constants
local NAV_FALLBACK_HEIGHT = 44 -- when Roblox reports no top bar (TopbarInset height 0)
local STATUS_BAR_HEIGHT = 26
local EDGE_PADDING = 12
local WORDMARK_WIDTH = 116
local SECTION_GAP = 24
local BALANCE_PILL_SIZE = Vector2.new(150, 28)
local TAB_TEXT_PADDING = 10
local NET_WORTH_VALUE_WIDTH = 140

-- The terminal is the whole game UI; these default HUD pieces would sit on
-- top of it once it fills the screen. Chat stays available.
for _, coreGuiType in ipairs({
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.EmotesMenu,
}) do
	StarterGui:SetCoreGuiEnabled(coreGuiType, false)
end

-- Full screen, under Roblox's top bar - the nav bar shares that strip
TerminalGui.ScreenInsets = Enum.ScreenInsets.None
MainBackground.AnchorPoint = Vector2.zero
MainBackground.Position = UDim2.fromScale(0, 0)
MainBackground.Size = UDim2.fromScale(1, 1)

-- Shell elements are built here rather than in Studio so they live in git
local function makeTextLabel(name, role, parent)
	local label = Instance.new("TextLabel")

	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = ""
	label:SetAttribute("ThemeRole", role)
	label.Parent = parent

	return label
end

local Wordmark = makeTextLabel("Wordmark", "Heading", TopBar)
Wordmark.Text = "TradingBlox"
Wordmark.Size = UDim2.new(0, WORDMARK_WIDTH, 1, 0)
Wordmark.TextXAlignment = Enum.TextXAlignment.Left

local BalancePill = Instance.new("Frame")
BalancePill.Name = "BalancePill"
BalancePill.AnchorPoint = Vector2.new(1, 0.5)
BalancePill.Size = UDim2.fromOffset(BALANCE_PILL_SIZE.X, BALANCE_PILL_SIZE.Y)
BalancePill.BorderSizePixel = 0
BalancePill:SetAttribute("ThemeRole", "Pill")
BalancePill.Parent = TopBar

local BalanceValue = makeTextLabel("BalanceValue", "Number", BalancePill)
BalanceValue.Size = UDim2.fromScale(1, 1)
BalanceValue.TextXAlignment = Enum.TextXAlignment.Center

local StatusBar = Instance.new("Frame")
StatusBar.Name = "StatusBar"
StatusBar.AnchorPoint = Vector2.new(0, 1)
StatusBar.Position = UDim2.fromScale(0, 1)
StatusBar.Size = UDim2.new(1, 0, 0, STATUS_BAR_HEIGHT)
StatusBar.BorderSizePixel = 0
StatusBar:SetAttribute("ThemeRole", "PanelFlat") -- Panel color; a stroke/corners would look wrong full-width
StatusBar.Parent = MainBackground

local StatusTopEdge = Instance.new("Frame")
StatusTopEdge.Name = "TopEdge"
StatusTopEdge.Size = UDim2.new(1, 0, 0, 1)
StatusTopEdge.BorderSizePixel = 0
StatusTopEdge:SetAttribute("ThemeRole", "Divider")
StatusTopEdge.Parent = StatusBar

-- Untagged on purpose: its color flips open/closed every update below
local MarketDot = Instance.new("Frame")
MarketDot.Name = "MarketDot"
MarketDot.AnchorPoint = Vector2.new(0, 0.5)
MarketDot.Position = UDim2.new(0, EDGE_PADDING, 0.5, 0)
MarketDot.Size = UDim2.fromOffset(8, 8)
MarketDot.BorderSizePixel = 0
MarketDot.Parent = StatusBar

local MarketDotCorner = Instance.new("UICorner")
MarketDotCorner.CornerRadius = UDim.new(0.5, 0)
MarketDotCorner.Parent = MarketDot

local MarketLabel = makeTextLabel("MarketLabel", "TextMuted", StatusBar)
MarketLabel.Position = UDim2.fromOffset(EDGE_PADDING + 16, 0)
MarketLabel.Size = UDim2.new(0.5, 0, 1, 0)
MarketLabel.TextXAlignment = Enum.TextXAlignment.Left

local NetWorthValue = makeTextLabel("NetWorthValue", "Number", StatusBar)
NetWorthValue.AnchorPoint = Vector2.new(1, 0)
NetWorthValue.Position = UDim2.new(1, -EDGE_PADDING, 0, 0)
NetWorthValue.Size = UDim2.new(0, NET_WORTH_VALUE_WIDTH, 1, 0)
NetWorthValue.TextXAlignment = Enum.TextXAlignment.Right

local NetWorthCaption = makeTextLabel("NetWorthCaption", "TextMuted", StatusBar)
NetWorthCaption.Text = "Net worth"
NetWorthCaption.AnchorPoint = Vector2.new(1, 0)
NetWorthCaption.Position = UDim2.new(1, -(EDGE_PADDING + NET_WORTH_VALUE_WIDTH + 8), 0, 0)
NetWorthCaption.Size = UDim2.new(0, 70, 1, 0)
NetWorthCaption.TextXAlignment = Enum.TextXAlignment.Right

-- Tabs sit left-aligned after the wordmark, sized to their text, instead of
-- the old fixed-width row right-aligned against the window buttons
TabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
TabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
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

-- TerminalController's tab-switch tween ends at Offset (1, 0), where only the
-- first keypoint shows - so at rest the line reads as a plain divider and a
-- tab switch sweeps the violet peak across it
AccentGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Colors.Border),
	ColorSequenceKeypoint.new(0.5, Theme.Colors.Accent),
	ColorSequenceKeypoint.new(1, Theme.Colors.Border),
})

local function layoutShell()
	local inset = GuiService.TopbarInset
	local hasTopbar = inset.Height > 0
	local navHeight = hasTopbar and inset.Height or NAV_FALLBACK_HEIGHT
	local leftEdge = (hasTopbar and inset.Min.X or 0) + EDGE_PADDING
	local rightEdge = (hasTopbar and inset.Max.X or MainBackground.AbsoluteSize.X) - EDGE_PADDING
	local tabsLeft = leftEdge + WORDMARK_WIDTH + SECTION_GAP
	local tabsRight = rightEdge - BALANCE_PILL_SIZE.X - SECTION_GAP

	TopBar.Size = UDim2.new(1, 0, 0, navHeight)
	Wordmark.Position = UDim2.fromOffset(leftEdge, 0)
	TabContainer.Position = UDim2.fromOffset(tabsLeft, 0)
	TabContainer.Size = UDim2.new(0, math.max(tabsRight - tabsLeft, 0), 1, 0)
	BalancePill.Position = UDim2.new(0, rightEdge, 0.5, 0)

	ScreenContainer.Position = UDim2.fromOffset(0, navHeight)
	ScreenContainer.Size = UDim2.new(1, 0, 1, -(navHeight + STATUS_BAR_HEIGHT))
end

local function updateBalance()
	BalanceValue.Text = NumberModule.format(Player:GetAttribute("Balance") or 0)
end

local function updateNetWorth()
	NetWorthValue.Text = NumberModule.format(Player:GetAttribute("NetWorth") or 0)
end

local function updateMarketStatus()
	local now = os.time()
	local isOpen, targetTime = MarketHoursModule.getMarketStatus(now)
	local countdown = MarketHoursModule.formatCountdown(targetTime - now)

	MarketDot.BackgroundColor3 = isOpen and Theme.Colors.Up or Theme.Colors.TextMuted
	MarketLabel.Text = isOpen and ("NYSE open · closes in " .. countdown) or ("NYSE closed · opens in " .. countdown)
end

GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layoutShell)
MainBackground:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutShell)
Player:GetAttributeChangedSignal("Balance"):Connect(updateBalance)
Player:GetAttributeChangedSignal("NetWorth"):Connect(updateNetWorth)

layoutShell()
updateBalance()
updateNetWorth()
updateMarketStatus()
Theme.apply(TerminalGui)

task.spawn(function()
	while true do
		task.wait(1)
		updateMarketStatus()
	end
end)
```

- [ ] **Step 5: Playtest — layout** — `start_stop_play(true)`, wait 5s, run **H3** (Client). Expected: all `true`. Also `get_console_output`: no errors, no `[Theme]` warnings.

- [ ] **Step 6: Confirm the inset-change wiring** (Review Focus 2): `grep -n 'GetPropertyChangedSignal("TopbarInset")' /Users/killxinu/Documents/GitHub/TradingBlox/src/client/Controllers/ShellController.client.luau` → one match; and (Client) `return tostring(game:GetService("GuiService").TopbarInset)` shows a non-zero height after load (so the fallback was only transient).

- [ ] **Step 7: Playtest — content** (Client):

```lua
local Players = game:GetService("Players")
local NumberModule = require(game:GetService("ReplicatedStorage").Modules.Multi.NumberModule)
local p = Players.LocalPlayer
local mb = p.PlayerGui.TerminalGui.MainBackground
local status = mb.StatusBar
return table.concat({
	"balanceMatches=" .. tostring(mb.TopBar.BalancePill.BalanceValue.Text == NumberModule.format(p:GetAttribute("Balance") or 0)),
	"netWorthMatches=" .. tostring(status.NetWorthValue.Text == NumberModule.format(p:GetAttribute("NetWorth") or 0)),
	"market=" .. status.MarketLabel.Text,
	"macButtonsGone=" .. tostring(mb.TopBar:FindFirstChild("MacButtons") == nil),
	"playerListHidden=" .. tostring(not game:GetService("StarterGui"):GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)),
}, "\n")
```

Expected: both `...Matches=true`; `market=NYSE open · closes in …` or `NYSE closed · opens in …` with a countdown in one of the three formats; `macButtonsGone=true`; `playerListHidden=true`. Then run **H2** with `SCOPE = "Shell"` → `0 problem(s)`, two font families. `start_stop_play(false)`.

- [ ] **Step 8: Commit**

```bash
git -C /Users/killxinu/Documents/GitHub/TradingBlox add src/shared/Modules/Multi/MarketHoursModule.luau src/client/Controllers/ShellController.client.luau
git -C /Users/killxinu/Documents/GitHub/TradingBlox commit -m "Add full-screen shell: nav bar, balance pill, status bar" -m "ShellController lays the nav out around Roblox's top-bar buttons, builds the wordmark, balance pill and NYSE/net-worth status bar in code, and applies the theme at startup. MarketHoursModule gains formatCountdown for the status bar." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `TerminalController` — theme colors, init what it owns

**Files:**
- Modify: `src/client/Controllers/TerminalController.client.luau` (line numbers as of `853a2e0`; unchanged by the options merge)

**Interfaces:**
- Consumes: `Theme.Colors.{Up, Down, TextMuted, TextDisabled, Accent, Text, Raised}` (Task 1).
- Produces: at startup the active nav tab is `Accent`, the cursor tool and the `1H` timeframe button show as active, Buy pills are `Up` and Sell pills `Down`/`TextDisabled`, indicator toggles rest at `Raised`/`TextMuted`; EMA50 series color `220,222,230`.

- [ ] **Step 1: Write the check (Client, during Play) and run it — it must fail**

`start_stop_play(true)`, wait 5s, then:

```lua
local Theme = require(game:GetService("ReplicatedStorage").Modules.Multi.Theme)
local mb = game.Players.LocalPlayer.PlayerGui.TerminalGui.MainBackground
local charts = mb.ScreenContainer.ChartsScreen
local hex = function(c) return c:ToHex() end
local C = Theme.Colors
local buy = charts.ActiveTraderPanel.ContentArea.BuyPresetsGrid.BuyPreset_100
local sell = charts.ActiveTraderPanel.ContentArea.SellPresetsGrid.SellPreset_25
local title = mb.ScreenContainer.DashboardScreen.DashboardGrid.MainWorkspace.TopRow.CountdownWidget.TitleText
local checks = {
	activeTabAccent = hex(mb.TopBar.TabContainer.DashboardButton.TextColor3) == hex(C.Accent),
	inactiveTabMuted = hex(mb.TopBar.TabContainer.TradeButton.TextColor3) == hex(C.TextMuted),
	cursorToolActive = hex(charts.MainChart.LeftToolbar.CursorToolButton.BackgroundColor3) == hex(C.Accent),
	trendToolInactive = hex(charts.MainChart.LeftToolbar.TrendLineToolButton.BackgroundColor3) == hex(C.Raised),
	hourTimeframeActive = hex(charts.MainChart.TopToolbar.TimeframeDropdown.TimeDropdownList["1HourButton"].BackgroundColor3) == hex(C.Accent),
	buyPresetUp = hex(buy.TextColor3) == hex(C.Up) and hex(buy.Stroke.Color) == hex(C.Up) and buy.Stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Border,
	sellPresetDimmed = hex(sell.TextColor3) == hex(C.TextDisabled),
	countdownTitleThemed = hex(title.TextColor3) == hex(C.Up) or hex(title.TextColor3) == hex(C.TextMuted),
}
local lines = {}
for k, v in pairs(checks) do
	table.insert(lines, k .. "=" .. tostring(v))
end
table.sort(lines)
return table.concat(lines, "\n")
```

Expected now: at least `activeTabAccent=false`, `cursorToolActive=false`, `hourTimeframeActive=false`, `sellPresetDimmed=false` (old `90,95,105`). `start_stop_play(false)`.

- [ ] **Step 2: Require the theme** — after line 12 (`local DrawingModule = require(...)`) add:

```lua
local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
```

- [ ] **Step 3: EMA50 series color** — in `IndicatorOptions`, the `EMA50Button` entry:

```lua
		color = Color3.fromRGB(150, 100, 255),
```
→
```lua
		color = Color3.fromRGB(220, 222, 230), -- near-white: the old purple was nearly the UI accent
```

- [ ] **Step 4: Color constants** — replace the block at lines 146–154:

```lua
-- RGB Constants
local GREEN = Color3.fromRGB(8, 153, 129)
local RED = Color3.fromRGB(242, 54, 69)
local GRAY = Color3.fromRGB(132, 142, 156)

local COLOR_ACTIVE_BACKGROUND = Color3.fromRGB(38, 166, 154)
local COLOR_ACTIVE_TEXT = Color3.fromRGB(255, 255, 255)
local COLOR_INACTIVE_BACKGROUND = Color3.fromRGB(30, 34, 45)
local COLOR_INACTIVE_TEXT = Color3.fromRGB(132, 142, 156)
```
→
```lua
-- Theme Colors (names kept from the pre-theme constants so call sites stay put)
local GREEN = Theme.Colors.Up
local RED = Theme.Colors.Down
local GRAY = Theme.Colors.TextMuted

local COLOR_ACTIVE_BACKGROUND = Theme.Colors.Accent
local COLOR_ACTIVE_TEXT = Theme.Colors.Text
local COLOR_INACTIVE_BACKGROUND = Theme.Colors.Raised
local COLOR_INACTIVE_TEXT = Theme.Colors.TextMuted
```

- [ ] **Step 5: Tab colors in `switchTab`** — replace

```lua
		data.Button.TextColor3 = Color3.fromRGB(120, 123, 134)
```
→ `		data.Button.TextColor3 = COLOR_INACTIVE_TEXT`

and

```lua
		Tabs[tabName].Button.TextColor3 = Color3.fromRGB(209, 212, 220)
```
→ `		Tabs[tabName].Button.TextColor3 = COLOR_ACTIVE_BACKGROUND -- the accent, as text`

- [ ] **Step 6: Countdown title colors in `updateCountdown`** — replace

```lua
		TitleText.TextColor3 = Color3.fromRGB(8, 153, 129)
```
→ `		TitleText.TextColor3 = GREEN`

and

```lua
		TitleText.TextColor3 = Color3.fromRGB(120, 123, 134)
```
→ `		TitleText.TextColor3 = GRAY`

- [ ] **Step 7: Disabled preset color** — replace

```lua
local ACTIVE_TRADER_DISABLED_COLOR = Color3.fromRGB(90, 95, 105)
```
→
```lua
local ACTIVE_TRADER_DISABLED_COLOR = Theme.Colors.TextDisabled
```

- [ ] **Step 8: Initialize the toggles and pills this script owns** — at the end of the file, replace

```lua
switchTab("Dashboard")
updateGreeting()
updateAccountInfo()
updateActiveTraderPosition() -- grays out Sell presets until a position exists
```
→
```lua
-- Preset pills: the stroke outlines the pill (Border mode - the default,
-- Contextual, outlines a text object's glyphs). Buy pills never dim, so their
-- green is set once here; Sell pills are recolored by updateSellPresetsEnabled.
local function stylePresetPill(button, color)
	local stroke = button:FindFirstChild("Stroke")

	button.TextColor3 = color

	if stroke then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = color
	end
end

for _, preset in ipairs(ActiveTraderBuyPresets) do
	stylePresetPill(preset.button, GREEN)
end

for _, preset in ipairs(ActiveTraderSellPresets) do
	stylePresetPill(preset.button, RED)
end

for button in pairs(IndicatorOptions) do
	button.BackgroundColor3 = COLOR_INACTIVE_BACKGROUND
	button.TextColor3 = COLOR_INACTIVE_TEXT
end

switchTab("Dashboard")
setDrawingTool(currentDrawingTool) -- the Studio defaults no longer show which tool is active
updateTimeframeUI(currentTimeframe)
updateGreeting()
updateAccountInfo()
updateActiveTraderPosition() -- grays out Sell presets until a position exists
```

- [ ] **Step 9: Confirm no stray colors** — `grep -n "Color3.fromRGB" /Users/killxinu/Documents/GitHub/TradingBlox/src/client/Controllers/TerminalController.client.luau` → only the four `IndicatorOptions` series colors (`255, 170, 0`, `0, 170, 255`, `255, 90, 205`, `220, 222, 230`).

- [ ] **Step 10: Re-run the Step 1 check** (new playtest) — expected all `true`. Then EMA50: click `LocalPlayer.PlayerGui.TerminalGui.MainBackground.TopBar.TabContainer.ChartsButton`, `...ChartsScreen.MainChart.TopToolbar.IndicatorsDropdown.MainIndicatorsButton`, `...IndicatorsDropdownList.EMA50Button`; (Client) `return game.Players.LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.ChartsScreen.MainChart.TopToolbar.IndicatorsDropdown.IndicatorsDropdownList.EMA50Button.BackgroundColor3:ToHex()` → `dcdee6`; click EMA50Button again to turn it off. Click `DashboardButton`; run **H2** with `SCOPE = "DashboardScreen"` → `0 problem(s)`. (A `fit` problem means a label outgrew its box in the wider number font: stop Play, widen that label's `Size` in Studio with an Edit-mode `execute_luau` — never shrink text below the four theme sizes — re-run, and list the change in your report so Kevin knows to save the place.) Click `...TopBar.TabContainer.PortfolioButton`; **H2** `SCOPE = "PortfolioScreen"` → `0 problem(s)`. `start_stop_play(false)`.

- [ ] **Step 11: Commit**

```bash
git -C /Users/killxinu/Documents/GitHub/TradingBlox add src/client/Controllers/TerminalController.client.luau
git -C /Users/killxinu/Documents/GitHub/TradingBlox commit -m "Theme TerminalController: tabs, toggles, presets, countdown" -m "Swaps hardcoded colors for Theme tokens, initializes the drawing-tool/timeframe toggles and preset pills it owns, and moves the EMA50 series off the new accent color." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `TradeController` — theme colors and fonts

**Files:**
- Modify: `src/client/Controllers/TradeController.client.luau` (post-merge, 1,408 lines; line numbers below are approximate — match on the quoted code)

**Interfaces:**
- Consumes: `Theme.Colors.{Up, UpHover, Down, DownHover, TextMuted, Text, Panel, Background, AccentTint, Accent, AccentSoft, Border, Raised}`, `Theme.Fonts.{UI, UISemibold, Mono, MonoBold}`, `Theme.TextSize.{Body, Caption}` (Task 1).
- Produces: every element `TradeController` builds uses theme colors/fonts; `makeLabel`'s `props.font` is now a `Font` (not an `Enum.Font`); `BuyButton`/`SellButton` rest at `Up`/`Down`.

- [ ] **Step 1: Write the check (Client, during Play) and run it — it must fail**

`start_stop_play(true)`, wait 5s; click `LocalPlayer.PlayerGui.TerminalGui.MainBackground.TopBar.TabContainer.TradeButton`; load AAPL (Client): `local box = game.Players.LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.TradeScreen.InputRow.TickerInput; box:CaptureFocus(); box.Text = "AAPL"; box:ReleaseFocus(true)`; wait 4s; click `...TradeScreen.OptionChain.Toggle`; wait 3s. Then:

```lua
local Theme = require(game:GetService("ReplicatedStorage").Modules.Multi.Theme)
local trade = game.Players.LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.TradeScreen
local C = Theme.Colors
local hex = function(c) return c:ToHex() end
local firstRow
for _, c in ipairs(trade.OptionChain.ChainData:GetChildren()) do
	if c.Name:match("^Strike_") then
		firstRow = c
		break
	end
end
local price = trade.HeaderRow.PriceLabel.TextColor3
local seg = trade.MiniChart:FindFirstChild("Seg_1")
local grad = seg and seg:FindFirstChildOfClass("UIGradient")
local checks = {
	buyButtonUp = hex(trade.HeaderRow.BuyButton.BackgroundColor3) == hex(C.Up),
	priceUpOrDown = hex(price) == hex(C.Up) or hex(price) == hex(C.Down),
	chainRowThemed = firstRow ~= nil and (hex(firstRow.BackgroundColor3) == hex(C.AccentTint) or hex(firstRow.BackgroundColor3) == hex(C.Background)),
	chainNumbersMono = firstRow ~= nil and firstRow.CallBidAsk.FontFace.Family == Theme.Fonts.Mono.Family,
	miniChartStartsSoft = grad ~= nil and hex(grad.Color.Keypoints[1].Value) == hex(C.AccentSoft),
	quoteTabActiveAccent = hex(trade.QuoteDetails.TabHeaderContainer.Tab_QuoteDetails.TextColor3) == hex(C.Accent),
}
local lines = {}
for k, v in pairs(checks) do
	table.insert(lines, k .. "=" .. tostring(v))
end
table.sort(lines)
return table.concat(lines, "\n")
```

Expected now: `buyButtonUp`, `chainNumbersMono`, `chainRowThemed`, `priceUpOrDown` and `quoteTabActiveAccent` all `false`; `miniChartStartsSoft` is already `true` (the old gradient starts at the same pale violet). `start_stop_play(false)`.

- [ ] **Step 2: Require the theme** — after `local MarketHoursModule = require(ReplicatedStorage.Modules.Multi.MarketHoursModule)` add:

```lua
local Theme = require(ReplicatedStorage.Modules.Multi.Theme)
```

- [ ] **Step 3: Constants** — replace

```lua
-- Contants
local GREEN = Color3.fromRGB(8, 153, 129)
local RED = Color3.fromRGB(242, 54, 69)
local GRAY = Color3.fromRGB(132, 142, 156)

local TEXT_PRIMARY = Color3.fromRGB(209, 212, 220)
local TEXT_SECONDARY = Color3.fromRGB(132, 142, 156)
local BG_ROW_EVEN = Color3.fromRGB(22, 26, 35)
local BG_ROW_ODD = Color3.fromRGB(18, 22, 30)
local BG_ITM = Color3.fromRGB(28, 40, 58) -- In-The-Money
local BG_OTM = Color3.fromRGB(18, 22, 30) -- Out-The-Money

local COLOR_TAB_ACTIVE = Color3.fromRGB(209, 212, 220)
local COLOR_TAB_INACTIVE = Color3.fromRGB(120, 123, 134)
```
→
```lua
-- Theme Colors (names kept from the pre-theme constants so call sites stay put)
local GREEN = Theme.Colors.Up
local RED = Theme.Colors.Down
local GRAY = Theme.Colors.TextMuted

local TEXT_PRIMARY = Theme.Colors.Text
local TEXT_SECONDARY = Theme.Colors.TextMuted
local BG_ROW_EVEN = Theme.Colors.Panel
local BG_ROW_ODD = Theme.Colors.Background
local BG_ITM = Theme.Colors.AccentTint -- In-The-Money
local BG_OTM = Theme.Colors.Background -- Out-The-Money

local COLOR_TAB_ACTIVE = Theme.Colors.Accent
local COLOR_TAB_INACTIVE = Theme.Colors.TextMuted
```

- [ ] **Step 4: Contract indicator font** — replace

```lua
ContractIndicator.Font = Enum.Font.SourceSansSemibold
ContractIndicator.TextSize = 13
```
→
```lua
ContractIndicator.FontFace = Theme.Fonts.UISemibold
ContractIndicator.TextSize = Theme.TextSize.Body
```

- [ ] **Step 5: Field grid fonts (`renderFieldGrid`)** — replace

```lua
		lbl.TextColor3 = TEXT_SECONDARY
		lbl.Font = Enum.Font.SourceSans
		lbl.TextSize = 13
		lbl.TextXAlignment = Enum.TextXAlignment.Left
```
→
```lua
		lbl.TextColor3 = TEXT_SECONDARY
		lbl.FontFace = Theme.Fonts.UI
		lbl.TextSize = Theme.TextSize.Body
		lbl.TextXAlignment = Enum.TextXAlignment.Left
```

and

```lua
		val.TextColor3 = TEXT_PRIMARY
		val.Font = Enum.Font.SourceSansSemibold
		val.TextSize = 13
```
→
```lua
		val.TextColor3 = TEXT_PRIMARY
		val.FontFace = Theme.Fonts.Mono
		val.TextSize = Theme.TextSize.Body
```

- [ ] **Step 6: `renderUnavailable` font** — replace

```lua
	lbl.TextColor3 = TEXT_SECONDARY
	lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Center
```
→
```lua
	lbl.TextColor3 = TEXT_SECONDARY
	lbl.FontFace = Theme.Fonts.UI
	lbl.TextSize = Theme.TextSize.Body
	lbl.TextXAlignment = Enum.TextXAlignment.Center
```

- [ ] **Step 7: `makeLabel` takes a `Font`** — replace

```lua
	lbl.Font = props.font or Enum.Font.SourceSans
	lbl.TextSize = props.size or 13
```
→
```lua
	lbl.FontFace = props.font or Theme.Fonts.UI
	lbl.TextSize = props.size or Theme.TextSize.Body
```

- [ ] **Step 8: `makeLabel` callers** — Edit with `replace_all: true`:
  - `font = Enum.Font.SourceSansSemibold,` → `font = Theme.Fonts.UISemibold,` (6 occurrences: option-stats header/CALL/PUT, positions header ×2, position ticker)
  - `size = 11,` → `size = Theme.TextSize.Caption,` (3 occurrences)
  - `size = 10,` → `size = Theme.TextSize.Caption,` (1 occurrence)

  Then the strike label:

```lua
		font = isATM and Enum.Font.SourceSansBold or Enum.Font.SourceSans,
```
→
```lua
		font = isATM and Theme.Fonts.MonoBold or Theme.Fonts.Mono,
```

- [ ] **Step 9: Numbers in Roboto Mono** — add `font = Theme.Fonts.Mono,` to these `makeLabel` calls, directly after their `color = ...` line:
  - Option Stats `CallValue` and `PutValue` (`color = TEXT_PRIMARY,` inside the `OPTION_STATS_ROWS` loop)
  - Strike row `CallBidAsk` (`color = callITM and TEXT_PRIMARY or TEXT_SECONDARY,`) and `PutBidAsk` (`color = putITM and TEXT_PRIMARY or TEXT_SECONDARY,`)
  - Position row values (`color = isColored and getChangeColor(v) or TEXT_PRIMARY,`)

  Example (CallBidAsk) — before:
```lua
		color = callITM and TEXT_PRIMARY or TEXT_SECONDARY,
		align = Enum.TextXAlignment.Left,
```
  after:
```lua
		color = callITM and TEXT_PRIMARY or TEXT_SECONDARY,
		font = Theme.Fonts.Mono,
		align = Enum.TextXAlignment.Left,
```

- [ ] **Step 10: Separators, positions header, news** — replace:
  - `	sep.BackgroundColor3 = Color3.fromRGB(35, 40, 52)` → `	sep.BackgroundColor3 = Theme.Colors.Border`
  - `	header.BackgroundColor3 = Color3.fromRGB(25, 29, 40)` → `	header.BackgroundColor3 = Theme.Colors.Raised`
  - news headline:
```lua
	headline.Font = Enum.Font.SourceSans
	headline.TextSize = 13
```
→
```lua
	headline.FontFace = Theme.Fonts.UI
	headline.TextSize = Theme.TextSize.Body
	headline.TextTruncate = Enum.TextTruncate.AtEnd -- long headlines end in "…" instead of clipping mid-line
```
  - `		row.BackgroundColor3 = Color3.fromRGB(28, 36, 50)` → `		row.BackgroundColor3 = Theme.Colors.Raised`

- [ ] **Step 11: Mini chart gradient** — replace

```lua
local MINI_CHART_GRADIENT_START = Color3.fromRGB(224, 170, 255) -- pale violet (older)
local MINI_CHART_GRADIENT_END = Color3.fromRGB(124, 58, 237) -- vivid purple (most recent)
```
→
```lua
local MINI_CHART_GRADIENT_START = Theme.Colors.AccentSoft -- pale violet (older)
local MINI_CHART_GRADIENT_END = Theme.Colors.Accent -- the UI accent (most recent)
```

- [ ] **Step 12: Buy/Sell resting and hover colors** — replace

```lua
attachHover(BuyButton, Color3.fromRGB(38, 166, 154), Color3.fromRGB(25, 140, 128))
attachHover(SellButton, Color3.fromRGB(200, 50, 50), Color3.fromRGB(170, 35, 35))
```
→
```lua
BuyButton.BackgroundColor3 = Theme.Colors.Up
SellButton.BackgroundColor3 = Theme.Colors.Down
attachHover(BuyButton, Theme.Colors.Up, Theme.Colors.UpHover)
attachHover(SellButton, Theme.Colors.Down, Theme.Colors.DownHover)
```

- [ ] **Step 13: Confirm no stray colors or legacy fonts**

```bash
grep -n "Color3.fromRGB\|Enum.Font" /Users/killxinu/Documents/GitHub/TradingBlox/src/client/Controllers/TradeController.client.luau || echo "clean"
```

Expected: `clean`. (`Color3.new(1, 1, 1)` for the white gradient base and `Color3.new(...)` inside `lerpColor` are expected and don't match this grep.)

- [ ] **Step 14: Re-run the Step 1 check** (new playtest, same setup) — expected all `true`. Then run **H2** with `SCOPE = "TradeScreen"` (chain expanded, AAPL loaded) → `0 problem(s)`. If `fit` problems appear, shrink nothing below the four sizes: widen the offending label's `Size` (code-built: edit its `sz` in this file; Studio-built: `execute_luau` Edit after stopping Play), then re-run H2. Click each quote tab (`Tab_AnalystReports`, `Tab_Fundamentals`, `Tab_OptionStats`), wait 3s each, H2 again → `0 problem(s)`. `start_stop_play(false)`.

- [ ] **Step 15: Commit**

```bash
git -C /Users/killxinu/Documents/GitHub/TradingBlox add src/client/Controllers/TradeController.client.luau
git -C /Users/killxinu/Documents/GitHub/TradingBlox commit -m "Theme TradeController: colors, fonts, numbers in Roboto Mono" -m "Option chain, positions, news, field grids and Buy/Sell now use Theme tokens; makeLabel takes a Font; long news headlines truncate instead of clipping." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `ChartRenderer` — theme colors, fonts, badge fit

**Files:**
- Modify: `src/shared/Modules/Multi/ChartRenderer.luau`

**Interfaces:**
- Consumes: `Theme.Colors.{Up, Down, TextMuted, Border, Text}`, `Theme.Fonts.{Mono, UI, UIBold}`, `Theme.TextSize.{Caption, Body}` via `require(script.Parent.Theme)`.
- Produces: unchanged `ChartRenderer.render(elements, ticker, chartData, timeframe, liveCandle, indicators) -> (minPrice, maxPrice)`; badge text drops decimals at ≥ 10,000.

- [ ] **Step 1: Write the check (Edit datamodel) and run it — it must fail**

```lua
local folder = Instance.new("Folder")
folder.Name = "FreshRequire_Chart"
folder.Parent = game:GetService("ServerStorage")
local Multi = game:GetService("ReplicatedStorage").Modules.Multi
for _, name in ipairs({ "ChartRenderer", "IndicatorModule", "Theme" }) do
	Multi[name]:Clone().Parent = folder
end
local ChartRenderer = require(folder.ChartRenderer)
local Theme = require(folder.Theme)

local function frame(name, parent)
	local f = Instance.new("Frame")
	f.Name = name
	f.Parent = parent
	return f
end
local main = frame("MainChart", folder)
local elements = {
	ChartTickerLabel = Instance.new("TextLabel"),
	CandlesContainer = frame("CandlesContainer", main),
	GridContainer = frame("GridContainer", main),
	IndicatorsContainer = frame("IndicatorsContainer", main),
	RightAxis = frame("RightAxis", main),
	BottomAxis = frame("BottomAxis", main),
	MainChart = main,
}

local function render(lastClose)
	local data = {}
	for i = 1, 6 do
		local open = (lastClose - 10) + i
		local close = (i % 2 == 0) and open + 2 or open - 2 -- odd candles bearish, even bullish
		if i == 6 then
			close = lastClose
		end
		table.insert(data, { Open = open, Close = close, High = math.max(open, close) + 1, Low = math.min(open, close) - 1, Timestamp = 1700000000 + i * 3600 })
	end
	ChartRenderer.render(elements, "TEST", data, "H", nil, nil)
end

local hex = function(c) return c:ToHex() end
local C = Theme.Colors

render(150.25)
local bear = elements.CandlesContainer:FindFirstChild("Candle_Body_1")
local bull = elements.CandlesContainer:FindFirstChild("Candle_Body_2")
local grid = elements.GridContainer:FindFirstChild("HorizontalGrid_1")
local priceLabel = elements.RightAxis:FindFirstChild("AxisLabel_Price_1")
local badge = elements.RightAxis:FindFirstChild("AxisLabel_LiveBadge")
local checks = {
	candlesUpDown = bear and bull and hex(bear.BackgroundColor3) == hex(C.Down) and hex(bull.BackgroundColor3) == hex(C.Up),
	gridBorderSolid = grid ~= nil and hex(grid.BackgroundColor3) == hex(C.Border) and grid.BackgroundTransparency == 0,
	axisLabelMonoMuted = priceLabel ~= nil and priceLabel.FontFace.Family == Theme.Fonts.Mono.Family and hex(priceLabel.TextColor3) == hex(C.TextMuted) and priceLabel.TextSize == 12,
	badgeTwoDecimals = badge ~= nil and badge.PriceText.Text == "150.25" and hex(badge.PriceText.TextColor3) == hex(C.Text),
}
render(123456.78)
badge = elements.RightAxis:FindFirstChild("AxisLabel_LiveBadge")
checks.badgeLargePriceNoDecimals = badge ~= nil and badge.PriceText.Text == "123457"
folder:Destroy()

local lines = {}
for k, v in pairs(checks) do
	table.insert(lines, k .. "=" .. tostring(v))
end
table.sort(lines)
return table.concat(lines, "\n")
```

Expected now: all five `false` (`badgeTwoDecimals` has the right text but the old white color).

- [ ] **Step 2: Theme require and candle colors** — replace

```lua
local IndicatorModule = require(script.Parent.IndicatorModule)

local ChartRenderer = {}

local GREEN = Color3.fromRGB(8, 153, 129)
local RED = Color3.fromRGB(242, 54, 69)
```
→
```lua
local IndicatorModule = require(script.Parent.IndicatorModule)
local Theme = require(script.Parent.Theme)

local ChartRenderer = {}

local GREEN = Theme.Colors.Up
local RED = Theme.Colors.Down

-- The live-price badge sits in the 60px-wide right axis; six-figure prices
-- (e.g. BTC) only fit without decimals
local BADGE_DECIMALS_CUTOFF = 10000
```

- [ ] **Step 3: Price axis labels and horizontal grid** — replace

```lua
				priceLabel.TextColor3 = Color3.fromRGB(132, 142, 156)
				priceLabel.Font = Enum.Font.SourceSans
				priceLabel.TextSize = 13
```
→
```lua
				priceLabel.TextColor3 = Theme.Colors.TextMuted
				priceLabel.FontFace = Theme.Fonts.Mono
				priceLabel.TextSize = Theme.TextSize.Caption
```

and

```lua
				horizontalGrid.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				horizontalGrid.BackgroundTransparency = 0.95
```
→
```lua
				horizontalGrid.BackgroundColor3 = Theme.Colors.Border
				horizontalGrid.BackgroundTransparency = 0
```

- [ ] **Step 4: Time axis labels and vertical grid** — replace

```lua
				timeLabel.TextColor3 = Color3.fromRGB(132, 142, 156)
				timeLabel.Font = Enum.Font.SourceSans
				timeLabel.TextSize = 13
```
→
```lua
				timeLabel.TextColor3 = Theme.Colors.TextMuted
				timeLabel.FontFace = Theme.Fonts.Mono
				timeLabel.TextSize = Theme.TextSize.Caption
```

and

```lua
					verticalGrid.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					verticalGrid.BackgroundTransparency = 0.95
```
→
```lua
					verticalGrid.BackgroundColor3 = Theme.Colors.Border
					verticalGrid.BackgroundTransparency = 0
```

- [ ] **Step 5: Badge text** — replace

```lua
		BadgeText.Text = string.format("%.2f", currentPrice)
```
→
```lua
		BadgeText.Text = string.format(currentPrice >= BADGE_DECIMALS_CUTOFF and "%.0f" or "%.2f", currentPrice)
```

then

```lua
		BadgeText.TextColor3 = Color3.fromRGB(255, 255, 255)
		BadgeText.Font = Enum.Font.SourceSansBold
		BadgeText.TextSize = 13
```
→
```lua
		BadgeText.TextColor3 = Theme.Colors.Text
		BadgeText.FontFace = Theme.Fonts.UIBold
		BadgeText.TextSize = Theme.TextSize.Caption -- the text box is only 12px tall
```

and

```lua
		TimerText.TextColor3 = Color3.fromRGB(240, 240, 240)
		TimerText.Font = Enum.Font.SourceSans
		TimerText.TextSize = 11
```
→
```lua
		TimerText.TextColor3 = Theme.Colors.Text
		TimerText.FontFace = Theme.Fonts.UI
		TimerText.TextSize = Theme.TextSize.Caption
```

- [ ] **Step 6: Confirm** — `grep -n "Color3.fromRGB\|Enum.Font" /Users/killxinu/Documents/GitHub/TradingBlox/src/shared/Modules/Multi/ChartRenderer.luau || echo clean` → `clean`. Re-run the Step 1 check → all `true`.

- [ ] **Step 7: Playtest the Charts screen** — `start_stop_play(true)`, wait 5s; click `...TopBar.TabContainer.ChartsButton`; load ETH-USD (Client): `local box = game.Players.LocalPlayer.PlayerGui.TerminalGui.MainBackground.ScreenContainer.ChartsScreen.MainChart.TopToolbar.TickerInputBox.TickerInput; box:CaptureFocus(); box.Text = "ETH-USD"; box:ReleaseFocus(true)`; wait 5s. Run **H2** with `SCOPE = "ChartsScreen"` → `0 problem(s)`. Then for each flyout — click `...ChartsScreen.Sidebar.ToggleActiveTraderButton`, wait 1s, H2; `ToggleSymbolInfoButton`, wait 1s, H2; `ToggleWatchlistButton`, wait 1s, H2 — each `0 problem(s)`. Load BTC-USD the same way and H2 once more → `0 problem(s)` (the badge now reads a whole number). `start_stop_play(false)`.

- [ ] **Step 8: Commit**

```bash
git -C /Users/killxinu/Documents/GitHub/TradingBlox add src/shared/Modules/Multi/ChartRenderer.luau
git -C /Users/killxinu/Documents/GitHub/TradingBlox commit -m "Theme ChartRenderer: candles, grid, axis labels, price badge" -m "Axis labels move to Roboto Mono, grid lines to the border color, and the live-price badge drops decimals at 10,000+ so six-figure prices fit the 60px axis." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Full verification, docs, Kevin's look

**Files:**
- Modify: `CLAUDE.md`
- Modify (only if Task 2 Step 5 needed extra `EXPLICIT` entries): `docs/superpowers/plans/2026-10-10-axiom-look-plan.md`

**Interfaces:**
- Consumes: everything above.
- Produces: Phase 1 verified end to end; `CLAUDE.md` documents the theme system.

- [ ] **Step 1: Layout** — `start_stop_play(true)`, wait 5s, **H3** → all `true`. Then, if NYSE is closed (check as in Task 0 Step 5), run **H1a** and **H1b** with `OPEN = true` — Steps 4 and 6 place orders.

- [ ] **Step 2: Full audit** — **H2** for `"Shell"`, then click each nav tab and run H2 for `"DashboardScreen"`, `"PortfolioScreen"`, `"TradeScreen"` (AAPL loaded, chain expanded), `"ChartsScreen"` (ETH-USD loaded, each flyout open in turn). All `0 problem(s)`, two font families. `get_console_output`: no errors, no `[Theme]` warnings.

- [ ] **Step 3: Tabs** — click `DashboardButton`, `PortfolioButton`, `TradeButton`, `ChartsButton` in turn; after each (Client) confirm only the matching `ScreenContainer.<Name>Screen.Visible` is `true` and that button's `TextColor3:ToHex()` is `9a6bff` (Accent) while the others are `8b90a3`.

- [ ] **Step 4: Charts flows** — on Charts with ETH-USD:
  1. Timeframe: click `...TopToolbar.TimeframeDropdown.MainTimeframeButton`, then `...TimeDropdownList.1DayButton`, wait 3s → `MainTimeframeButton.Text == "D"` and `1DayButton.BackgroundColor3:ToHex() == "9a6bff"`.
  2. Indicators: open `MainIndicatorsButton`, click `SMA20Button` → `ChartCanvas.IndicatorsContainer` has children; click again → it's empty after the re-render.
  3. Drawing: click `...LeftToolbar.TrendLineToolButton` → its `BackgroundColor3:ToHex() == "9a6bff"` and `CursorToolButton`'s is `151822`. Read `ChartCanvas.AbsolutePosition`/`AbsoluteSize` (Client), then `user_mouse_input` two `mouseButtonClick`s at screen points 30% and 70% across, 50% down the canvas → `ChartCanvas.DrawingsContainer` has ≥ 1 child. Click `ClearDrawingsButton` → empty. Click `CursorToolButton`.
  4. Active Trader: click `Sidebar.ToggleActiveTraderButton`, wait 3s (the ask price loads), note `Balance`, click `...ActiveTraderPanel.ContentArea.BuyPresetsGrid.BuyPreset_100` → `StatusLabel.TextColor3:ToHex() == "2ebd85"` and `Balance` dropped by ≤ $100. Click `SellPresetsGrid.SellPreset_100` → `Balance` back near start; `SellPreset_25.TextColor3:ToHex() == "5b6073"` (dimmed, no position).

- [ ] **Step 5: Status bar and pill track trades** (Review Focus 3) — right after a Step 4.4 trade (Client): `local p = game.Players.LocalPlayer; local nm = require(game.ReplicatedStorage.Modules.Multi.NumberModule); local mb = p.PlayerGui.TerminalGui.MainBackground; return mb.TopBar.BalancePill.BalanceValue.Text == nm.format(p:GetAttribute("Balance")), mb.StatusBar.NetWorthValue.Text == nm.format(p:GetAttribute("NetWorth"))` → `true, true`.

- [ ] **Step 6: Trade flows** — Trade tab, AAPL. Expand the chain, click a `Strike_N.CallHitArea`, click `HeaderRow.BuyButton` → `Balance` drops; click `HeaderRow.SellButton` → `Balance` back near start (minus spread). Run **H4** → no leftover AAPL option entry.

- [ ] **Step 7: Character reset keeps the terminal working** — (Server) `game:GetService("Players"):GetPlayers()[1].Character.Humanoid.Health = 0`; wait 8s; (Client) `return game.Players.LocalPlayer.PlayerGui.TerminalGui.MainBackground:FindFirstChild("StatusBar") ~= nil` → `true`; click `TradeButton` → `TradeScreen.Visible == true`. `start_stop_play(false)`.

- [ ] **Step 8: Update `CLAUDE.md`** — in the "Client/server split" list, replace the **Client** bullet's first sentence

```markdown
- **Client (`src/client/Controllers/`)** — one controller per screen/UI area (Terminal shell, Trade screen,
  Quote tabs, Options chain).
```
→
```markdown
- **Client (`src/client/Controllers/`)** — one controller per screen/UI area (`ShellController` for the
  full-screen shell — nav bar, balance pill, status bar; `TerminalController` for tab switching, Dashboard and
  Charts; `TradeController` for the Trade screen; Quote tabs and Options chain stubs).
```

and add this section directly after the "Cross-script state sharing" section:

```markdown
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
```

- [ ] **Step 9: Commit docs**

```bash
git -C /Users/killxinu/Documents/GitHub/TradingBlox add CLAUDE.md docs/superpowers/plans/2026-10-10-axiom-look-plan.md
git -C /Users/killxinu/Documents/GitHub/TradingBlox commit -m "Document the theme system and shell controller" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 10: Kevin's look** — ask Kevin to playtest in Studio and judge by eye, specifically: the nav bar next to Roblox's buttons, each tab, the Charts screen with each flyout open, the option chain, and the window made narrow (drag Studio's window smaller, then rerun **H3** — Review Focus 1). Anything he flags becomes a fix (Studio tags/sizes via `execute_luau` Edit, code via a new commit) before Phase 1 is done. Then ask him to save the place.

- [ ] **Step 11: Finish the branch** — use superpowers:finishing-a-development-branch to merge `axiom-look-phase1` into `main`.
