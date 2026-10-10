# Player Memecoins + Pulse (Phase 2, Slice 1)

## Roadmap context

Phase 2 of the Axiom-style redesign (see `2026-10-10-axiom-look-design.md`) was first
scoped as a "Pulse" tab of real stocks ranked into Gainers / Losers / Crypto columns.
During brainstorming Kevin redirected it: on Axiom, Pulse is a live feed of newly
launched memecoins, and he wants TradingBlox to have **player-launched memecoins**. A
second new market, the **Roblox Market** (Roblox games traded as stocks, priced from
live player counts), comes after this. The curated-stock Pulse is set aside; it can
return later as an extra column.

Order agreed on 2026-10-10:

1. **This spec, Slice 1: coins + Pulse.** The coin engine, launching, the Pulse tab
   and a coin panel.
2. **Slice 2: Robux.** Developer Products to skip the launch cooldown or boost a coin
   on Pulse. Its own spec.
3. **Roblox Market.** Its own brainstorm. Needs a backend route, because Roblox game
   servers can't call Roblox's own web APIs.
4. **Phase 3, the token page.** Unchanged.

Inspired by pump.fun and Axiom, not a clone. Nothing uses either product's name or
assets.

## Goal

Any player can launch a coin by giving it a name and a ticker. Every player, in
every server, sees it appear on Pulse and can buy it in one click. Prices move only
through buying and selling. A coin that draws about $8,500 of net buying graduates,
and its creator earns a bonus. Coins outlive their creator's session, and nobody can
end up holding a coin they can't sell.

## Decisions (from brainstorming, 2026-10-10)

| Question | Decision |
|---|---|
| What comes first | Memecoins + Pulse, before Roblox Market and before the stock Pulse |
| Where a coin exists | Every server, and it persists after its creator leaves |
| Graduation | A milestone: the coin moves to the Graduated column, the creator gets a cash bonus, and trading continues on the same curve |
| Launch cost | A cash fee plus a cooldown in this slice; Robux skip/boost in Slice 2 |
| Cross-server state | MemoryStore holds live state with atomic updates; DataStore holds durable copies |
| Quick-buy | One Buy button per card, with the amount set by a picker in the Pulse header |

## Current state (verified in code, 2026-10-10)

- Players start with `Balance = 10000` (`Data_Manager.server.luau`, `createDefaultData`).
  Player data lives in `_G.PlayerData[userId]` and is saved to DataStore `PlayerData_v1`
  on leave and on `BindToClose`. `Balance` and `NetWorth` are exposed as Player
  attributes. Net worth is seeded on join, as of `4b21579`.
- `CalculatorModule.calculateNetWorth(player)` sums balance, shares and options, and
  sets the `NetWorth` attribute.
- `ServerSetup.server.luau` creates every `RemoteFunction` in
  `ReplicatedStorage.EventsFolder`. `API_Manager.server.luau` throttles each player per
  remote with `PLAYER_COOLDOWN = 1`.
- Tabs are wired in `TerminalController.client.luau` through a `Tabs` table of
  `{ Button, Frame }` entries found with `WaitForChild` under `TopBar.TabContainer` and
  `ScreenContainer`. `ShellController` builds the shell in code and lays the tabs out
  at the width of their text.
- `Theme.luau` holds all colors, fonts and sizes. Text on Up/Down/Accent fills uses
  `Theme.Colors.Background`.
- The codebase doesn't use `MemoryStoreService`, `MessagingService` or `TextService`
  yet.
- Studio playtests have API access: the balance persists across playtests, so
  DataStores are live in Studio and write to **the real game's stores**.

## Section 1: The coin and its price

**Supply.** Every coin has exactly 1,000,000,000 tokens. Nobody holds any at launch,
including the creator. All tokens are bought from the coin's curve, and holders can
sell them back to it.

**Curve.** This is a constant product with virtual reserves, the pump.fun model:

- The curve holds a cash pool `V` and a token pool `T`, and `V × T = k` never changes.
- Starting pools: `V₀ = $3,000` and `T₀ = 1,073,000,000`, so `k = 3.219 × 10¹²`. The
  virtual padding keeps the first buyer from taking most of the supply for pennies.
- Price = `V / T`. Market cap = price × 1,000,000,000.
- **Buy $x:** a fee of 1% of x is removed from the game, then `x' = 0.99x` goes into
  the curve. Tokens out = `T − k / (V + x')`, floored to whole tokens.
- **Sell n tokens:** gross = `V − k / (T + n)`, a 1% fee is removed, and the payout is
  `0.99 × gross`, rounded down to the cent.
- **Sold out:** a buy that would take the total sold (`T₀ − T`) past 1,000,000,000 is
  refused with "Sold out."
- **Floor:** a sell can never push `T` above `T₀`, which is the same as `V` below
  `V₀`. If a restore ever loses recent trades, this stops the curve paying out cash
  that never went in.

**Key numbers.** These follow from the constants above. All constants live in one config
module.

| Moment | Cash added to curve | Market cap |
|---|---|---|
| Launch | $0 | about $2.8k |
| $250 first buy | $247.50 | buyer gets about 81.8M tokens (8.2%) |
| Graduation | $8,500 (`V = $11,500`) | about $41.1k |
| All 1B sold | — | about $604k |

**Graduation progress** = `(V − V₀) / 8,500`, capped at 1. When a trade takes progress
to 1, the coin is permanently marked graduated, even if it later dumps. The creator
gets a one-time **$2,500** bonus through the payout mailbox (Section 2).

**Creators.** There's no launch allocation; creators buy like everyone else. A creator
can still dump on buyers, as on pump.fun. Each coin records how many tokens its
creator holds, and the coin panel shows that as a share of supply.

**Display.** Per-token prices are tiny, so the UI leads with market cap. Token counts
are abbreviated (`81.8M`). Prices in the coin panel show enough significant digits to
be non-zero.

## Section 2: Storage across servers

| Data | Store | Notes |
|---|---|---|
| Live coin state: id, name, ticker, creator id and name, created time, `V`, `T`, total volume, trade count, last trade time, creator tokens, graduated flag and time, and the last 60 one-minute price points | MemoryStore hash map | Every trade is one atomic `UpdateAsync` on the coin's key |
| Durable coin copy | DataStore `Coins_v1`, keyed by coin id | Written at launch, at graduation, at least every 5 minutes while the coin trades, and at archive |
| Ticker registry | DataStore `CoinTickers_v1`, keyed by ticker | Claimed atomically at launch. Unique forever |
| Holdings | The player's `PlayerData_v1` record: `Portfolio.Coins[coinId] = { tokens, cost }`, plus `LastLaunchAt` and the ids of coins they launched | Loaded in only one server at a time, so no cross-server locking is needed. Old saves without these fields get defaults on load |
| Payout mailbox | DataStore `Payouts_v1`, keyed by user id | A list of pending `{ amount, reason, coinId }` |

**Pulse refresh.** Each server reads the coin list from the memory store about every
10–15 seconds and caches a snapshot. Clients get that cache through a remote, so no
memory-store call happens on a player's request. A player's own trade updates their
view of that coin immediately. Memory-store request limits scale with players online,
so the refresh interval must fit them (see Verification).

**Price points.** Each trade writes the coin's current price into the slot for the
current minute: it overwrites the last point if that point is in the same minute,
otherwise it appends one, keeping at most 60. Minutes with no trades carry the
previous price forward when drawn.

**Archiving.** A coin with no trades for 24 hours is removed from the memory store
after its durable copy is written. It disappears from Pulse, but its holders keep
their tokens and still see it under My coins. A trade on an archived coin first
restores it into the memory store from its durable copy. Coins are also restored
from the durable copy if the memory store ever drops them.

**Payouts.** The server that processes a graduating trade appends the bonus to the
creator's mailbox with `UpdateAsync`. Each server collects the mailbox of every player
it hosts when they join and every 60 seconds after that. Collection is one atomic
`UpdateAsync` that returns the pending list and clears it, then the server credits
the balance. A payout can't be paid twice, and it reaches creators who are offline
or in another server.

**Net worth.** `CalculatorModule` adds tokens × current price for each held coin.

**Studio isolation.** When `RunService:IsStudio()`, every coin store name (memory store
and DataStore) gets a `_studio` suffix. Playtests can never put coins into the live
game's Pulse. `PlayerData_v1` is unchanged.

**Size budget.** The memory store's size quota grows with players online across the
whole game, and one coin takes about 1 KB. The server refuses new launches when the
live coin count nears the budget (Section 3). Archiving keeps the live set small.

## Section 3: Launching a coin

**Form.** A Launch coin button in the Pulse header opens a form:

- Name: 2–24 characters.
- Ticker: 2–6 letters or digits, uppercased, always shown as `$TICKER`.

Coins have no image or description in this slice. Each card shows a colored tile
with the ticker's first letter, the color picked from a fixed palette by coin id.

**Server checks, in order.** The client pre-checks the same rules for instant feedback,
but the server is the authority.

1. Name and ticker length and character rules.
2. Roblox text filter on both, for broadcast to all users. If the filtered text differs
   from the input, the launch is rejected with "Name not allowed." A filter error also
   rejects it.
3. Cooldown: one launch per player per hour, from `LastLaunchAt`.
4. Limits: at most 3 live (unarchived) coins per player. Launches are refused with
   "Pulse is full, try again later" when the live coin count nears the memory-store
   budget.
5. Balance of at least $1,000.
6. Claim the ticker atomically in `CoinTickers_v1`. If it's already claimed, the
   launch fails with "Ticker taken."
7. Create the coin in the memory store and write its durable copy, then deduct the
   **$1,000 fee** and set `LastLaunchAt`.

The fee comes last, so a failure at any step charges nothing. If step 7 fails after the
ticker was claimed, the claim is released.

**After launch.** The creator's coin panel opens immediately so they can make the
first buy. Other servers show the coin within one Pulse refresh. Coins trade 24/7,
with no NYSE gate.

## Section 4: The Pulse screen

**Tab.** Pulse is the second tab: Dashboard · Pulse · Portfolio · Trade · Charts.
- A new `PulseController.client.luau` builds the tab button and the whole screen in code from
  Theme tokens, so nothing is added in Studio.
- `TerminalController` gains a `Pulse` entry in its `Tabs` table and sets the tab order.
- The shell's narrow-window layout must still pass with five tabs.

**Header.**
- The title.
- A quick-buy amount picker: $100 / $250 / $500 / $1,000, default $250, kept for
  the session.
- A My coins toggle and a Launch coin button.
- A status line showing the last result, e.g. "Bought 81.8M $PEPE for $250" or an
  error message.

**Columns.** Each shows up to 20 cards and scrolls.

| Column | Coins | Sort |
|---|---|---|
| New | Not graduated, progress < 50% | Newest first |
| About to graduate | Not graduated, progress ≥ 50% | Highest progress first |
| Graduated | Graduated | Most recently graduated first |

**Card.**
- The letter tile, `$TICKER`, the name and age (e.g. `3m`, `2h`).
- Market cap and volume.
- A progress bar, or a ★ once graduated.
- A Buy button labeled with the picker amount.

Buy executes on click with no confirm step. There's no slippage limit: the price is
whatever the curve gives when the server executes. Clicking the card body opens the
coin panel.

**Coin panel.** A 320px panel on the right side of the screen.
- Tile, ticker, name, creator, age, graduated badge.
- Market cap, price, volume, trade count, creator's share of supply, progress bar.
- A 60-minute sparkline in the house style: one continuous rotated-segment line with
  a violet gradient.
- Buy presets $100 / $250 / $500 / $1,000 and sell presets 25 / 50 / 75 / 100% of the
  position. All are one-click.
- Your position: tokens, current value, P&L against cost.
- A close button.

**My coins.** The toggle replaces the three columns with one list of every coin the
player holds or launched, including archived ones. Each row opens the coin panel, so an
archived coin can always be sold.

**Remotes.** All are new `RemoteFunction`s created in `ServerSetup`, each with a
per-player cooldown.

| Remote | Purpose |
|---|---|
| `GetPulseEvent()` | The server's cached snapshot: three columns of card summaries and the snapshot's time |
| `GetCoinEvent(coinId)` | Full state for the panel, including price points and the caller's position |
| `GetMyCoinsEvent()` | The caller's held and launched coins, including archived ones |
| `CoinOrderEvent(action, coinId, amount)` | `"Buy"` with dollars, or `"Sell"` with a fraction of the position (0 < f ≤ 1). The server computes tokens from the curve when it executes |
| `LaunchCoinEvent(name, ticker)` | Section 3 |

**Empty and error states.**
- An empty column reads "No coins yet. Launch one."
- If the memory store can't be reached, the header shows "Coins unavailable, retrying…",
  buttons are disabled, and the last snapshot stays on screen with its age.

## Section 5: Failure handling and testing

**Trade order.**
- **Buy:** the server checks the balance locally, then runs the atomic coin update,
  which computes the tokens. Only on success does it debit cash and credit tokens.
- **Sell:** the server checks tokens locally, then runs the coin update, then credits
  cash.
- **Failed update:** nothing changes and the player sees "Try again."
- **Crash:** if the server dies between the coin update and the player save, the
  player loses nothing they paid. The curve keeps the extra movement, which is
  bounded by the sell floor.

**Validation.**
- Dollar amounts must be finite, greater than 0 and no more than the balance.
- Sell fractions must be in (0, 1].
- Coin ids must exist.
- Every token and cash computation happens on the server.

**Retries.** Memory-store reads retry with backoff. Payout and backup writes retry on
throttling. Pulse keeps the last good snapshot.

**Tests.** Studio `execute_luau` checks, run RED then GREEN, as in Phase 1.

- **Pure modules** (tested with fresh requires):
  - Curve math: buy and sell amounts and fees, sold out, the sell floor, the
    graduation threshold and the table values above, and that buying then selling
    never returns more than was put in.
  - Column assignment and sorting.
  - Name and ticker rules.
- **In Play:**
  - Launching: success, the fee charged only on success, and filter rejection,
    taken tickers, cooldown and limits each charging nothing.
  - Buying and selling: balance, tokens and curve state agree.
  - Graduation pays the creator exactly once, even when two collections race.
  - Archiving and restoring, using a test hook that ages a coin 25 hours.
  - Old saves load with the new fields defaulted.
  - The Pulse screen through Phase 1's palette, fit and layout audits (H2/H3) with
    five tabs.
- **Concurrency.** Studio runs only one server, so 20 buys of one coin fire at once
  from parallel tasks. The memory store enforces atomicity, so this exercises the
  same path as two real servers. It passes when the tokens players received exactly
  equal what the curve recorded as sold, and the cash pool equals `V₀` plus the net
  cash added.

## Verification before building (first plan task)

- **Memory store in Studio.** Confirm it works in Studio playtests with this place's
  API settings, and that the `_studio` suffix keeps test data separate.
- **Memory store limits.** Check the current published size and request limits, and how
  hash-map listing is charged. Set the Pulse refresh interval and the "Pulse is full"
  threshold from them.
- **Text filtering.** Confirm whether Roblox requires stored user-generated text to be
  re-filtered when displayed. If it does, re-filter names when the server builds
  snapshots.

If any of these contradict this spec, the plan records a ruling before building on it.

## Non-goals (this slice)

- Robux Developer Products: Slice 2.
- Coin images, descriptions, comments or chat.
- Limit orders, slippage settings, or transfers between players.
- Candle charts for coins, or trading coins from the Trade or Charts screens:
  Phase 3.
- Coin leaderboards.
- Roblox Market.
- The curated-stock Pulse columns.

## Done means

In a Studio playtest, a player can do all of the following:

- launch a coin;
- see it in New;
- buy and sell it from a card and from the panel;
- push it into About to graduate and then Graduated;
- receive the $2,500 bonus exactly once;
- find it under My coins after it's archived, and sell it.

Every check in Section 5 passes. Kevin plays it in Studio and approves the feel.
