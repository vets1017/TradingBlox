# Axiom-Style Look: Theme System + Full-Screen Shell

## Roadmap context

Kevin wants TradingBlox to look and operate like Axiom.trade (a dense, dark,
one-click crypto trading terminal). That is three independent projects, agreed to
ship in this order, each with its own brainstorm → spec → plan cycle:

1. **Look** (this spec) — Axiom's visual language applied to the screens that
   already exist, plus Axiom's full-screen shell (top nav + bottom status bar).
2. **Pulse** — a new tab of live stock columns (e.g. Top Gainers / Most Active /
   Top Losers), each card with a one-click quick-buy. Additive; needs new backend
   routes.
3. **Token page** — Trade + Charts merged into one Axiom-style screen (chart center,
   order panel right, positions/orders tabs below). Riskiest — rewrites the two
   largest controllers — so it goes last and reuses Phases 1 and 2.

Inspired by Axiom, not a clone: the game stays a stock/options market, nothing uses
Axiom's name, logo or assets, and crypto-only controls (slippage, priority fee, MEV
protection, wallet trackers) stay out — same call made for the Active Trader panel.

## Goal

Every existing screen reads as a dark, dense, Axiom-style terminal: one palette, one
violet accent, two fonts, four text sizes, flat bordered panels, and a full-screen
shell with a top nav bar and bottom status bar. Phase 1 changes how things look and
where the shell sits — it does not move anything inside a screen.

## Current state (verified in Studio and code, not assumed)

- The UI is a single hand-built `StarterGui.TerminalGui` tree (333 descendants) that
  lives only in the Studio place file — not in git, not synced by Rojo.
- It floats as a window: `MainBackground` is 90% × 85% of the screen, navy
  `19,23,34`, under `ScreenInsets = CoreUISafeInsets`. `TopBar` (35px) holds
  decorative traffic-light `MacButtons` (no code references them anywhere) and the
  `TabContainer` with Dashboard / Portfolio / Trade / Charts buttons.
- The palette has drifted: **25** distinct visible background colors, **11** text
  colors, **12** text sizes and **6** font families across 118 text elements. The
  Trade screen alone uses black/near-black (`10,10,10`, `20,20,20`) while the window
  is navy. `PortfolioScreen` is an empty, opaque **white** frame.
- `TerminalController.client.luau` (1,427 lines) owns tab switching, the Dashboard
  and the Charts screen. Its `switchTab` sets tab text colors and sweeps
  `TopBar.AccentLine.AccentGradient` across on every switch. Toggle-style buttons
  (Charts sidebar toggles, timeframe/indicator buttons) are colored at runtime from
  `COLOR_ACTIVE_BACKGROUND` (teal `38,166,154`) / `COLOR_INACTIVE_BACKGROUND`.
- `TradeController.client.luau` defines its own color constants (`GREEN`, `RED`,
  `GRAY`, `TEXT_PRIMARY`, `BG_ROW_EVEN`, `BG_ITM`, `MINI_CHART_GRADIENT_START/END`,
  …) and on the options branch adds Buy/Sell hover colors via `attachHover`.
- `ChartRenderer.luau` hardcodes candle colors (`GREEN 8,153,129`,
  `RED 242,54,69`), axis label gray and white grid lines.
- `MarketHoursModule.getMarketStatus(time)` already returns `isOpen, targetTime`;
  the Dashboard countdown uses it.
- `Balance` and `NetWorth` are already exposed as `Player` attributes.
- `GuiService.TopbarInset` exists and is readable (it reports the free area of
  Roblox's own top bar at runtime; `0,0,0,0` in Edit mode).
- The options-trading phase 1 work is finished on `worktree-options-trading-phase1`
  (9 commits, 156 lines changed in `TradeController`) but not merged. `main` has an
  untracked copy of that branch's plan doc (byte-identical) and an uncommitted
  formatter-only reflow of the options spec (the branch doesn't touch that file).

## Decisions made during brainstorming

1. **Phase order: Look → Pulse → Token page.** Lowest risk first; Pulse is purely
   additive; the Trade + Charts rewrite goes last.
2. **Desktop first.** Match Axiom's density on PC/Mac. Mobile keeps working but may
   feel cramped; a mobile pass comes later if players show up there.
3. **Full-screen terminal (mockup option 1B)** instead of a restyled floating
   window. The traffic-light buttons are decorative, so nothing functional is lost.
4. **Accent: violet (2B)**, `154,107,255` — the shade from the mockup, a touch
   lighter than the mini chart's current end color (`124,58,237`) so violet text
   stays readable on near-black (~5.6:1 vs ~3.5:1).
5. **Approach A: role-tagged theme.** Tokens and roles live in a git-tracked module;
   each UI element gets a `ThemeRole` attribute; one `apply()` stamps the look.
   Rejected: a one-time recolor of the place file (fast, but the look leaves git and
   later tweaks mean re-hunting the tree), and rebuilding the shell in code (most
   work, and Phase 3 rebuilds Trade/Charts anyway).
6. **Merge options trading first.** Phase 1 edits the same `TradeController`
   constants; building on top of the merged branch avoids conflicts.
7. **"/" ticker search is deferred to Phase 3.** Trade and Charts each have their own
   ticker box today; one global search belongs with the merged token page. Roblox
   also binds "/" to chat, so that phase must pick another key or rebind chat's.
8. **New shell elements are created in code** (wordmark, balance pill, status bar) by
   `ShellController`, so they are git-tracked. Structural edits to *existing* Studio
   instances (insets, removing `MacButtons`) are made in Studio.

## Section A — `src/shared/Modules/Multi/Theme.luau` (new)

Plain module, required by client controllers and by `ChartRenderer`. No server use.

```lua
local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(8, 9, 13),
	Panel      = Color3.fromRGB(14, 16, 22),
	Raised     = Color3.fromRGB(21, 24, 34),   -- buttons, inputs, headers, hover
	Border     = Color3.fromRGB(35, 39, 54),   -- strokes and 1px dividers
	Text       = Color3.fromRGB(231, 233, 240),
	TextMuted  = Color3.fromRGB(139, 144, 163),
	TextDisabled = Color3.fromRGB(91, 96, 115), -- e.g. sell presets with no position
	Accent     = Color3.fromRGB(154, 107, 255),
	AccentSoft = Color3.fromRGB(224, 170, 255), -- start of the mini-chart gradient
	AccentTint = Color3.fromRGB(30, 24, 48),    -- in-the-money option rows
	Up         = Color3.fromRGB(46, 189, 133),
	UpHover    = Color3.fromRGB(39, 161, 113),  -- Up at 85%
	Down       = Color3.fromRGB(240, 74, 108),
	DownHover  = Color3.fromRGB(204, 63, 92),   -- Down at 85%
}

Theme.Fonts = {
	UI     = Font.new("rbxassetid://16658221428"),                          -- Builder Sans
	UIBold = Font.new("rbxassetid://16658221428", Enum.FontWeight.Bold),
	Mono   = Font.new("rbxasset://fonts/families/RobotoMono.json"),
}

Theme.TextSize = { Caption = 12, Body = 13, Title = 15, Display = 24 }
Theme.Radius = UDim.new(0, 4)

-- Each role lists only the properties it owns. Values are token names.
Theme.Roles = { ... } -- see table below

function Theme.apply(root: Instance) ... end

return Theme
```

### Roles

| Role | Sets | Used for (examples from the current tree) |
|---|---|---|
| `Screen` | bg `Background` | `MainBackground`, `TradeScreen`, `MiniChart`, `InputRow`, `PortfolioScreen` |
| `Panel` | bg `Panel`, stroke `Border`, corner | Dashboard widgets, Trade panels, `MainChart`, Charts toolbars and flyout top bars |
| `Raised` | bg `Raised`, corner | dropdown lists/buttons, table and column headers, widget title rows, watchlist rows, scroll track |
| `Input` | bg `Raised`, stroke `Border`, text `Text`, font `UI`, size `Body`, corner | `TickerInput`, `AddTickerInput`, `TickerInputBox` |
| `Divider` | bg `Border` | toolbar `DividerFrame`s, nav/status-bar edges |
| `Guide` | bg `TextMuted` | `CrosshairX`/`CrosshairY`, `ScrollThumb` |
| `AccentFill` | bg `Accent` | Trade quote-tab `ActiveIndicator`s |
| `Text` | text `Text`, font `UI`, size `Body` | ordinary labels |
| `TextMuted` | text `TextMuted`, font `UI`, size `Caption` | field names, captions, column headers |
| `Heading` | text `Text`, font `UIBold`, size `Title` | widget titles, wordmark |
| `Number` | text `Text`, font `Mono`, size `Body` | static numeric values |
| `NumberLarge` | text `Text`, font `Mono`, size `Display` | Dashboard countdown digits, big prices |
| `NumberDynamic` | font `Mono`, size `Body` (no color) | prices/changes a controller colors up/down |
| `LabelDynamic` | font `UI`, size `Body` (no color) | status labels, countdown title |
| `Tab` | font `UI`, size `Title` (no color) | nav tabs, Trade quote tabs |
| `Toggle` | font `UI`, size `Body`, corner (no colors) | Charts sidebar toggles, timeframe/indicator buttons, cursor tool |
| `Preset` | bg `Raised`, stroke `Border`, font `Mono`, size `Body`, corner (no text color) | Active Trader buy/sell preset pills |
| `ActionButton` | font `UIBold`, size `Body`, corner (no colors) | Trade `BuyButton` / `SellButton` |

### `Theme.apply(root)` behavior

- Walks `root:GetDescendants()` (plus `root` itself) once; for each instance with a
  `ThemeRole` string attribute, looks the role up in `Theme.Roles` and sets only the
  properties that role lists.
- `Stroke = "Border"` → reuse the element's first `UIStroke` or create one; set
  `Color`, `Thickness = 1`, and **`ApplyStrokeMode = Border`** (the default,
  `Contextual`, would outline the *text* of a TextLabel instead of its box).
- Any `UICorner` on a tagged element is set to `Theme.Radius`; roles marked
  `corner` create one if missing. This is what turns today's rounded cards into
  Axiom's flat 4px panels.
- Unknown role name → one `warn` with the element's full path; element untouched.
  Untagged elements are never touched — anything still navy or rounded during
  testing is visibly a missed tag.

### The ownership rule

**A role never sets a property a controller writes at runtime.** Prices turn
green/red, tabs light up, toggles flip, preset text dims when there's no position,
Buy/Sell hover. Those elements get the color-less roles above (`NumberDynamic`,
`LabelDynamic`, `Tab`, `Toggle`, `Preset`, `ActionButton`), so `apply()` and the
controllers never write the same property and LocalScript start order cannot matter.
For these elements the tagging pass (Section D, step 3) sets their *resting* color in
the place file to the theme value once, and controllers own it from then on.

### Where `apply()` runs

- **Runtime:** `ShellController` calls `Theme.apply(PlayerGui:WaitForChild("TerminalGui"))`
  once, after creating its own shell elements. ~330 instances, effectively instant.
  This makes git the source of truth for what players see.
- **Studio Edit mode:** run once via the Studio MCP after tagging, so the editor
  shows the real look. Not required for correctness.

## Section B — Full-screen shell

### Studio edits to existing instances

- `TerminalGui.ScreenInsets = None` (fills the screen under Roblox's top bar).
- `MainBackground`: `Size = UDim2.fromScale(1, 1)`, `Position = (0,0)`,
  `AnchorPoint = (0,0)`; remove its rounded `UICorner` if present.
- Delete `TopBar.MacButtons`.
- `TopBar.AccentLine` becomes the nav bar's 1px bottom edge (`Divider`); its existing
  `AccentGradient` sweep is re-tinted to violet so the switch animation stays.

### `src/client/Controllers/ShellController.client.luau` (new)

Owns the shell only; tab switching stays in `TerminalController`.

- **Layout from `GuiService.TopbarInset`** (and its `GetPropertyChangedSignal`):
  - nav height = `TopbarInset.Height`, falling back to 44px when it reports 0;
  - nav content starts at `TopbarInset.Min.X + 12` and ends by `TopbarInset.Max.X - 12`
    (falling back to 12px each side), so nothing sits under Roblox's menu buttons;
  - status bar height 26px at the bottom of `MainBackground`;
  - `ScreenContainer` fills the space between them.
- **Creates** (via `Instance.new`, each with a `ThemeRole`): `Wordmark` TextLabel
  "TradingBlox" (`Heading`) at the left of the nav; `BalancePill` (Raised frame with
  `Border` stroke + `Number` label) at the right, bound to the `Balance` attribute
  and formatted with `NumberModule.format`; `StatusBar` frame (`Panel`, top
  `Divider`) containing a status dot, a market label and a net-worth label.
- **Status bar content:**
  - left: dot (`Up` when open, `TextMuted` when closed) + `"NYSE open · closes in 3h 12m"`
    / `"NYSE closed · opens in 2d 5h"` from `MarketHoursModule.getMarketStatus`.
    Format: ≥ 1 day → `Xd Yh`; ≥ 1 hour → `Xh Ym`; else `Ym Zs`. Updates every second.
  - right: `"Net worth $54,120.88"` from the `NetWorth` attribute, updated on
    `GetAttributeChangedSignal`.
- Calls `Theme.apply(TerminalGui)` last.

### `TerminalController` tab colors

`switchTab` sets the active tab's text to `Theme.Colors.Accent` and inactive tabs to
`Theme.Colors.TextMuted` (replacing `209,212,220` / `120,123,134`). Sweep tween
unchanged.

## Section C — Controllers and `ChartRenderer`

Swap hardcoded colors for theme lookups, keeping the existing constant names so the
diffs stay small:

- `TerminalController`: `GREEN → Theme.Colors.Up`, `RED → Down`, `GRAY → TextMuted`,
  `COLOR_ACTIVE_BACKGROUND → Accent`, `COLOR_ACTIVE_TEXT → Text`,
  `COLOR_INACTIVE_BACKGROUND → Raised`, `COLOR_INACTIVE_TEXT → TextMuted`,
  `ACTIVE_TRADER_DISABLED_COLOR → TextDisabled`, countdown title colors →
  `Up` / `TextMuted`.
- **Indicator series colors stay distinct from the UI** (they're data, not chrome),
  except EMA50's `150,100,255`, which is nearly the new accent: change it to
  near-white `220,222,230` so it can't be mistaken for UI.
  `DrawingModule.DEFAULT_COLOR` stays.
- `TradeController`: `GREEN/RED/GRAY/TEXT_PRIMARY/TEXT_SECONDARY` → tokens;
  `BG_ROW_EVEN → Panel`, `BG_ROW_ODD/BG_OTM → Background`, `BG_ITM → AccentTint`;
  `COLOR_TAB_ACTIVE → Accent`, `COLOR_TAB_INACTIVE → TextMuted`;
  `MINI_CHART_GRADIENT_START/END → AccentSoft/Accent`; the remaining inline
  `Color3.fromRGB` literals (separator, header, selected row, Buy/Sell `attachHover`
  pairs → `Up`/`UpHover` and `Down`/`DownHover`) → tokens.
- `ChartRenderer`: candles `GREEN/RED → Up/Down`; axis labels → `TextMuted`, font
  `Mono`, size `Caption`; grid lines → `Border` (they're white with transparency
  today — keep the transparency, change the color); badge/timer text → `Text`.

## Section D — Rollout (one commit per step)

0. **Merge options trading.** Run the options plan's final playtest checklist in
   Studio; delete `main`'s untracked duplicate of the options plan doc (identical to
   the branch's copy, which the merge brings in); merge
   `worktree-options-trading-phase1` into `main`; remove the worktree. Leave the
   options spec's uncommitted formatter reflow for Kevin to keep or drop.
1. **Backup.** Clone `StarterGui.TerminalGui` into
   `ServerStorage.TerminalGui_PreAxiomBackup`; Kevin saves the place. Undo = delete
   the restyled `TerminalGui` and move the backup back.
2. **`Theme.luau`.** Tokens, roles, `apply()`. Nothing visible changes yet.
3. **Tagging pass (Studio).** A script assigns `ThemeRole` wherever the old color
   maps unambiguously (e.g. `30,34,45`, `20,20,20`, `15,15,15`, `46,46,46` →
   `Panel`; `10,10,10`, `19,23,34` → `Screen`; `74,74,74` → `Divider`;
   `240,240,240` indicators → `AccentFill`), then lists the leftovers for hand
   assignment. Text elements are tagged by current color/size/font plus whether a
   controller writes their color. Dynamic elements get their resting color stamped.
   The full old-color → role table and the per-element exceptions go into the plan
   doc so the mapping is recorded in git.
4. **Shell.** Studio edits from Section B + new `ShellController` + `switchTab`
   colors.
5. **Controllers.** Section C.
6. **Stamp in Studio.** Run `Theme.apply` in Edit mode so the editor matches.

Also: add `.superpowers/` to `.gitignore` (brainstorm scratch output).

## Testing plan

No test framework; Studio screen capture returns a magenta placeholder in this
environment, so verification is structural, run in a live playtest via the Studio
MCP.

- **Palette audit.** A script walks `PlayerGui.TerminalGui` and lists every visible
  `BackgroundColor3` / `TextColor3` / `UIStroke.Color` not in `Theme.Colors`
  (exempt: indicator series lines, drawing-tool lines, gradient interiors). Pass =
  empty list, exactly 2 font families (Builder Sans, Roboto Mono), and every text
  size one of `Theme.TextSize`'s four values.
- **Text fit.** List every visible text element whose `TextFits` is false — Builder
  Sans is wider than Source Sans, so the font swap can clip tight labels. Pass =
  empty list (fix by size/width, not by `TextScaled`).
- **Nav placement.** Nav content's `AbsolutePosition.X ≥ GuiService.TopbarInset.Min.X`;
  status bar visible at the bottom; `ScreenContainer` doesn't overlap either bar.
- **Regression.** Switch all four tabs; load a ticker on Trade; one-click buy and
  sell from Active Trader; select and buy an option contract; change chart
  timeframe and toggle indicators; draw a trend line; open/close all three Charts
  flyouts; confirm the status bar's net worth changes after a trade and the balance
  pill tracks `Balance`.
- **Kevin's eyes.** Since screenshots don't work, Kevin playtests and judges the look;
  anything that looks wrong is fixed before Phase 1 is done.

**Done =** clean palette audit + text-fit check, every regression flow works, and
Kevin approves the look. Then Phase 2 (Pulse) brainstorming starts.

## Non-goals (explicitly deferred)

- Moving or resizing anything *inside* a screen (Phase 3 rebuilds Trade + Charts).
- The "/" global ticker search (Phase 3).
- Pulse and its backend routes (Phase 2).
- A mobile/tablet layout pass.
- Filling in the empty Portfolio screen (it only gets the `Screen` background).
- Light mode or user-selectable themes.
