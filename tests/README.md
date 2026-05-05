# Testing GuildConsumableLedger

Two complementary paths.

## 1. In-game test harness (no raid required)

The `/gcl test` slash commands fake cast events through the full pipeline
(price lookup → cost calc → ledger write → UI refresh) without needing a
real raid drop. The harness bypasses the raid-instance gate that normally
guards `Tracking/CastTracker.lua`.

```
/gcl test list       — show all scenarios
/gcl test seed       — install fake manual prices for placeholder reagents
/gcl test feast      — simulate a Feast drop
/gcl test hearty     — simulate a Hearty Feast drop (exercises composedOf)
/gcl test cauldron   — simulate a Cauldron of the Pool drop
/gcl test multi      — simulate one of each from different providers
/gcl test inspect    — dump the last entry's pricingSnapshot to chat
/gcl test clean      — remove test rows (provider name ends with -Test)
/gcl test unseed     — clear the fake manual prices
```

Typical first-run flow:

```
/reload
/gcl test seed
/gcl test multi
/gcl
```

You should see three rows in the ledger window with non-zero costs and
working **Mark Paid** buttons. `/gcl test clean` afterwards keeps your
production ledger free of test data.

## 2. Headless unit tests (for CI / pre-commit)

Pure-Lua tests for `CostCalculator`, `LedgerStore`, and `BalanceCalculator`
run outside the game. They stub the WoW API so no client is needed.

### Install a Lua interpreter

This machine has Lua *libraries* but not the CLI binary. Install one:

```bash
sudo apt install lua5.4
# or
sudo apt install luajit
```

### Run

From the addon root:

```bash
cd "/home/mcrispen/.steam/steam/steamapps/compatdata/2832488321/pfx/drive_c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/GuildConsumableLedger"
lua tests/run_tests.lua
```

Expected output:

```
=== CostCalculator: leaf recipe with Auctionator prices ===
  PASS  matsCost = 225000c
  PASS  priceSource = auctionator
  ...
Results: N passed, 0 failed
```

### What the tests cover

- Leaf recipe pricing with Auctionator API
- `composedOf` recursion (Hearty Feast = 10× Feast)
- `min(craft_cost, market_buyout)` for composite recipes
- Auctionator-missing → manual fallback
- Missing prices flagged in `snapshot.missing`
- `LedgerStore:Record` + `MarkPaid` roundtrip with balance updates
- **Critical:** `pricingSnapshot` is frozen on entry — Tuesday's row stays
  at Tuesday's price even when Thursday's market doubles.
- `BalanceCalculator:Recompute` reproduces balances from entries.

### Adding new tests

Each test block in `run_tests.lua` follows:

```lua
suite("description")
do
    -- arrange (set mock prices, prepare store)
    -- act    (call the addon module)
    -- assert (eq/ok)
end
```

`stubs.setMockPrices(t)` controls what `Auctionator.API.v1.GetAuctionPriceByItemID`
returns. `stubs.clearMockPrices()` removes the override.

Modules with WoW UI/event dependencies (`Core/EventBus`, `Tracking/CastTracker`,
`UI/MainFrame`, `Testing/SimHarness`) are *not* loaded by these tests because
their dependencies on `CreateFrame`/event registration are heavier than the
stubs cover. They are exercised by the in-game harness instead.
