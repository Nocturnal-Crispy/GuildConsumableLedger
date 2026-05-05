# GuildConsumableLedger — Addon Design Plan

**Target:** WoW Retail, Midnight (11.2 / 12.0.x), interface number **120000**
**Working name:** GuildConsumableLedger (GCL)
**One-line pitch:** Logs who provides raid consumables, prices the materials using Auctionator's saved data, and lets officers reimburse providers via mail, guild-bank credit, or a payout report.

---

## 1. Midnight API reality check

Before the design: Blizzard's "addon disarmament" in Midnight gates *real-time combat decisioning* data (enemy casts, debuffs, health, etc.) behind "secret values." It does **not** affect:

- `COMBAT_LOG_EVENT_UNFILTERED` firing for out-of-combat detection of cast/aura events
- `/combatlog` text export (Hazzikostas explicitly confirmed this is unchanged)
- Guild bank API, mail API, item info API, addon-to-addon comms within the guild
- Reading what Auctionator has saved to its SavedVariables

Everything this addon needs sits well outside the restricted zone. We're tracking the `SPELL_CAST_SUCCESS` of a feast/cauldron cast by a guildmate, then doing accounting work against item APIs and the guild bank — nothing real-time, nothing combat-critical.

---

## 2. Feature scope (driven by your answers)

### Tracked event types — all toggleable per guild
The addon ships with a tracking matrix; officers tick what counts. Each row is a category an officer can enable/disable:

1. **Cauldrons** — placed flask cauldrons (Algari, current expansion equivalents)
2. **Feasts** — placed group food
3. **Personal flask casts** — when a guild alchemist creates flasks (use `SPELL_CAST_SUCCESS` on profession spell IDs)
4. **Personal food casts** — chef-cooked food provided to others
5. **Combat potions handed out** — tracked via mail or trade events (see §6)
6. **Augment runes** — same model as potions
7. **Phials / new Midnight consumables** — hooked by adding spell IDs to the data table

Each category has its own ledger view and its own price list.

### Pricing — Auctionator integration
Officers do not maintain a price list. The addon reads `AUCTIONATOR_PRICE_DATABASE` from Auctionator's SavedVariables on login and pulls realm-recent values for each reagent. Auctionator's API exposes `Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)` which is the right entry point. If Auctionator isn't loaded, the addon falls back to a manually-editable price table and warns the officer.

### Reimbursement modes — all three available
1. **Auto-mail gold** — officer clicks "Pay" next to a row; addon opens mail to the recipient with the calculated gold attached. Officer still confirms send (Blizzard requires a click for mail-with-money; we cannot bypass that).
2. **Guild-bank credit** — addon maintains a per-player running balance; officer sees "Player X is owed 12,450g" and can clear it later in any way.
3. **Payout report** — exportable text/CSV (copy-paste box) summarizing all unpaid contributions by player for the period.

---

## 3. Architecture

```
GuildConsumableLedger/
├── GuildConsumableLedger.toc          # Interface 120000, deps: optional Auctionator
├── Core/
│   ├── Init.lua                       # Addon namespace, ACE3 setup
│   ├── EventBus.lua                   # Central event registration
│   └── Comms.lua                      # AceComm-3.0 guild channel
├── Data/
│   ├── SpellMap.lua                   # spellID -> {category, recipe, reagents}
│   ├── RecipeMap.lua                  # recipe -> {itemID, qty} list of mats
│   └── DefaultPrices.lua              # fallback prices if Auctionator absent
├── Tracking/
│   ├── CastTracker.lua                # COMBAT_LOG_EVENT_UNFILTERED listener
│   ├── HandoutTracker.lua             # MAIL_SEND_INFO_UPDATE / TRADE hooks
│   └── CauldronClickTracker.lua       # GameObject interaction (flask handout)
├── Pricing/
│   ├── AuctionatorAdapter.lua         # Reads Auctionator price db
│   ├── ManualPriceTable.lua           # Officer-edited fallback
│   └── CostCalculator.lua             # Sum (qty * unit price) per cast
├── Ledger/
│   ├── LedgerStore.lua                # SavedVariables schema + accessors
│   ├── BalanceCalculator.lua          # Per-player owed totals
│   └── HistoryView.lua                # Filter by date / player / category
├── Reimbursement/
│   ├── MailPayer.lua                  # Opens mail, attaches gold, prefills
│   ├── BankCredit.lua                 # Adjusts running balance
│   └── ReportExporter.lua             # CSV / pasteable text generator
├── UI/
│   ├── MainFrame.lua                  # Tabbed: Ledger | Settings | Pricing | Payout
│   ├── OfficerPanel.lua               # Permission-gated actions
│   ├── MemberPanel.lua                # Read-only "what I'm owed" view
│   └── SettingsPanel.lua              # Toggle categories, price source
└── Locale/
    └── enUS.lua
```

Libraries: Ace3 (AceAddon, AceDB, AceConfig, AceComm, AceGUI), LibStub, LibDataBroker for minimap icon. All standard, all confirmed Midnight-compatible.

---

## 4. Tracking logic — the actual hard parts

### 4.1 Detecting a cauldron/feast drop

The cast itself is fully visible in `COMBAT_LOG_EVENT_UNFILTERED`. Listen for `SPELL_CAST_SUCCESS` where `sourceGUID` is in the player's group AND `spellID` is in the SpellMap. This is exactly what RaidSlackCheck does today and the post-Midnight API still allows it (combat log events still fire; the restricted bits are the per-spell internal state of enemies).

```lua
-- pseudocode
local function OnCombatLog()
    local _, subEvent, _, sourceGUID, sourceName, _, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
    if subEvent ~= "SPELL_CAST_SUCCESS" then return end
    local entry = SpellMap[spellID]
    if not entry then return end
    if not UnitInParty(sourceName) and not UnitInRaid(sourceName) then return end
    Ledger:RecordCast(sourceGUID, sourceName, entry, GetServerTime())
end
```

The SpellMap entry looks like:
```lua
[SPELL_CAULDRON_OF_THE_POOL] = {
    category = "cauldron",
    recipeName = "Cauldron of the Pool",
    reagents = {
        { itemID = 191328, qty = 12 },  -- example flask reagent
        { itemID = 210796, qty = 4 },
        -- ...
    },
}
```

#### Composite recipes (Hearty Feast and friends)

Some consumables are crafted *from* other consumables. The canonical case: a **Hearty Feast** is built from 10× a regular feast. To avoid duplicating the regular feast's reagent list, recipes can declare a `composedOf` multiplier instead of (or alongside) raw reagents:

```lua
[SPELL_HEARTY_FEAST] = {
    category = "feast",
    recipeName = "Hearty Feast",
    composedOf = {
        { recipe = "Feast of the Midnight Masquerade", qty = 10 },
    },
}
```

The cost calculator resolves `composedOf` recursively: cost(Hearty Feast) = 10 × cost(regular feast), where cost(regular feast) is itself the sum of its reagents at current Auctionator prices. If a sub-recipe also has its own market item ID and Auctionator has a price for the finished item, the calculator uses `min(reagent_cost, market_price) × multiplier` so guilds aren't overcharged when buying the finished feast off the AH is cheaper than crafting.

### 4.2 Maintaining the SpellMap across patches

This is the maintenance burden. Spell IDs change. The plan:
- Ship a starter table for current Midnight cauldrons/feasts/phials
- Provide a `/gcl learn` developer command that, when an unknown profession spell is cast, prompts the officer to map it to a recipe via item link drag-and-drop
- Sync learned mappings via guild comms so the whole guild benefits from one officer's setup

### 4.3 Personal handouts (flasks/potions traded or mailed)

This is fundamentally trickier than cauldrons because no spell fires when you mail someone a flask. Two paths:

**Trade window hook:** Register `TRADE_ACCEPT_UPDATE` and on a successful `TRADE_CLOSED` (after both clicked accept), inspect what the player gave away. If items are in a tracked category and the recipient is a guildmate, log it. The recipient's addon also sees the trade and can confirm via AceComm.

**Mail hook:** Hook `SendMail`. When the player sends mail to a guildmate containing tracked items, log the items, recipient, and timestamp. Recipient confirms on their end via comms when they receive.

Both are opt-in per officer because they introduce some load.

### 4.4 Cauldron-click attribution (who took a flask out)

Optional. Detect `SPELL_AURA_APPLIED` for flask buffs from a cauldron source — when a guild member gets a cauldron flask buff, attribute one flask's worth of mats to the dropper's "consumed" count. Useful for accuracy when the cauldron has 60 charges but only 20 get used. Configurable: pay for charges placed vs. charges actually consumed.

---

## 5. Pricing — Auctionator integration in detail

Auctionator stores prices in a SavedVariables table keyed by realm. There are two ways to read them:

**Public API (preferred):** `Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)` — returns last-seen price. Stable, documented, version-checked.

**Direct SV read (fallback):** `AUCTIONATOR_PRICE_DATABASE[realmKey][itemID]` if the API isn't loaded for some reason.

For each tracked cast, `CostCalculator` does:
```lua
local total = 0
for _, mat in ipairs(recipe.reagents) do
    local unit = AuctionatorAdapter:GetPrice(mat.itemID) or ManualPriceTable:Get(mat.itemID) or 0
    total = total + (unit * mat.qty)
end
return total
```

If a price is missing entirely the row shows "?? — set price" with an inline editor for the officer.

### Per-drop price snapshotting (CRITICAL)

**Pricing is taken at the moment the consumable is dropped, using that day's Auctionator data, and frozen on the entry.** Subsequent price moves do NOT retroactively change historical rows.

Worked example: a guild alchemist drops a feast on Tuesday when the materials cost 3,000g, and another on Thursday when the same materials now cost 3,500g. The ledger reflects:

| Date | Provider | Recipe | Cost |
|---|---|---|---|
| Tuesday | AlchemistA | Feast | 3,000g |
| Thursday | AlchemistA | Feast | 3,500g |

Each entry's `pricingSnapshot` field captures the per-reagent unit price *as of that drop's timestamp*. The ledger view never recomputes — what's on the row is what gets paid. This:

- Gives auditability ("why does this entry say 3,500g?" → look at `pricingSnapshot`)
- Protects providers from deflation (Tuesday's contribution doesn't shrink because Thursday's market dropped)
- Protects the guild from inflation spikes (Thursday's market spike doesn't inflate Tuesday's bill)
- Matches how players actually experience cost: the gold they spent at the time

If Auctionator's data is older than 24 hours at the moment of drop, the addon flags the entry with a `staleness` warning so the officer knows the snapshot used a cached price rather than a fresh scan.

**Pricing strategy options** (in settings, applied at snapshot time):
- Use Auctionator "DBMarket" equivalent (recent average)
- Use lowest-buyout from last scan
- Multiply by configurable factor (e.g., 1.1x to cover AH cut and travel time)
- Round to nearest gold / 10g / 100g

---

## 6. The ledger — data model

```lua
GuildConsumableLedgerDB = {
    profile = { ... ace settings ... },
    realms = {
        ["RealmName-Faction"] = {
            guildName = "...",
            entries = {
                {
                    id = "uuid",
                    timestamp = 1746442800,
                    providerGUID = "Player-...",
                    providerName = "Vethric-Stormrage",
                    category = "cauldron",
                    spellID = 12345,
                    recipeName = "Cauldron of the Pool",
                    raidContext = { instance="Manaforge Omega", difficulty=16 },
                    matsCost = 14250000,  -- copper, frozen at drop time
                    pricingSnapshot = {  -- frozen at time of cast for auditability
                        snapshotDate = "2026-05-05",  -- YYYY-MM-DD, server-local
                        priceSource = "auctionator",  -- auctionator | manual | stale
                        staleness = false,  -- true if Auctionator data was >24h old
                        reagents = {
                            [191328] = { qty=12, unit=850000 },
                        },
                        composedOf = nil,  -- populated for hearty feasts etc:
                        --   { { recipe="Feast of...", qty=10, unitCost=300000000 } }
                    },
                    consumedCharges = nil,  -- filled in later if attribution enabled
                    paymentStatus = "unpaid",  -- unpaid | mailed | credited | reported
                    paidBy = nil,
                    paidAt = nil,
                    paidAmount = nil,
                },
            },
            balances = {
                ["Player-..."] = { owed = 142500000, paid = 0 },
            },
            mappingsLearned = { [spellID] = { ... } },
        },
    },
}
```

Per-realm + per-faction scoping because guilds are realm/faction-scoped. Per-character views are derived.

---

## 7. UI sketch

**Main window** (3 tabs visible to officers, 1 to members):

1. **Ledger** — sortable table: Date | Provider | Category | Recipe | Cost | Status | Action button
   - Filter row: date range, player, category, status
   - "Pay all unpaid for [Player]" bulk action
2. **Balances** — one row per provider showing total owed, total paid, net. "Settle" button per row.
3. **Settings** — category toggles, price source, pricing strategy, officer permissions, guild bank tab if used.
4. **My Contributions** (members) — read-only view of what the player personally has provided and current owed balance.

Officer permission is gated by `CanEditPublicNote()` or a configurable guild rank threshold via `GuildControlGetRankFlags`.

---

## 8. Reimbursement flows

### Auto-mail gold
1. Officer clicks Pay on a ledger row
2. Addon opens mailbox interface (must be at a mailbox — Blizzard restriction)
3. Pre-fills recipient, subject ("Consumable reimbursement: Cauldron of the Pool — 142g 50s"), and gold amount
4. Officer clicks send (Blizzard hardware-event requirement; cannot be automated)
5. On `MAIL_SEND_SUCCESS` (or our hook on SendMail), mark entry as `mailed`

### Guild-bank credit
1. Officer clicks "Credit" — entry marked `credited`, balance updated
2. Settlement happens out-of-band (guild bank withdrawal, EPGP, etc.)
3. "Apply settlement" button lets officer mark a balance as paid in lump

### Payout report
1. Officer clicks Export
2. Modal opens with selectable text: CSV-style or human-readable
3. Includes: provider, total, breakdown by category, date range
4. Officer Ctrl+A / Ctrl+C — paste to Discord, spreadsheet, etc.

---

## 9. Comms protocol (guild-wide sync)

Officers and members run the same addon. The addon broadcasts on a custom AceComm channel (`GCL_v1`). Messages:

| Type | Direction | Payload |
|---|---|---|
| `CAST_SEEN` | any → guild | Provider, spellID, timestamp, witness |
| `CAST_CONFIRMED` | officer → guild | Entry ID, recorded |
| `MAPPING_LEARNED` | officer → guild | spellID → recipe data |
| `BALANCE_UPDATE` | officer → guild | Player, new balance |
| `PAYMENT_LOGGED` | officer → guild | Entry ID, status, amount |

Multiple-witness deduplication: the first officer-online to receive `CAST_SEEN` writes the canonical entry and broadcasts `CAST_CONFIRMED`. Others discard their pending copy. This avoids double-counting when 3 officers are in the same raid.

---

## 10. Phased build plan

**Phase 1 — MVP (week 1–2)**
- Cast tracking for cauldrons + feasts only (regular and hearty)
- Hardcoded SpellMap for current Midnight raid consumables
- Auctionator pricing with **per-drop snapshot frozen on the entry** (Tuesday's drop stays at Tuesday's price even if Thursday's market is different)
- Composite recipe support: Hearty Feast = 10× regular feast cost, resolved recursively at snapshot time
- Simple ledger UI, manual "mark paid" only
- SavedVariables persistence

**Phase 2 — Reimbursement (week 3)**
- Mail-based payout
- Guild bank credit balance
- Export report

**Phase 3 — Sync & coverage (week 4–5)**
- AceComm guild sync, deduplication
- Personal flask/food cast tracking
- Trade and mail handout tracking

**Phase 4 — Polish**
- Officer rank permissions
- Member self-view
- Manual price editor for missing items
- `/gcl learn` mapping flow
- Localization scaffold

---

## 11. Known risks and gotchas

1. **Spell ID changes between patches.** Each minor patch may introduce new cauldron variants. The `learn` flow mitigates this; a community-maintained SpellMap on the addon's GitHub is the long-term solution.
2. **Mail with gold requires a mailbox.** Cannot auto-pay people just from raid; officer must visit a mailbox. Document this clearly.
3. **Auctionator data freshness.** If officers don't scan the AH, prices go stale. Add a "last scan was X days ago" warning.
4. **Multiple officers logging the same cast.** Solved by the AceComm dedup, but needs careful testing — race conditions are real.
5. **Trade-window tracking is fragile.** Players can game it by trading non-tracked items. Mark trade-tracked entries with lower confidence, or disable by default.
6. **SavedVariables size.** A heavy raid guild could log thousands of entries per tier. Add an auto-archive that compresses entries older than 90 days into per-player rollups.
7. **Cross-realm guilds (cross-realm assistance, etc.).** Probably out of scope; warn at install if guild looks cross-realm.
8. **Midnight API still iterating.** Beta-stage restrictions kept loosening. Re-validate the cast detection path against the live 12.0 client before public release.

---

## 12. Distribution

- CurseForge + Wago (standard)
- GitHub repo with the SpellMap as a separate community-editable file
- Slash commands: `/gcl`, `/consumables`, `/gcledger`
- Optional: weak dependency declaration on Auctionator in the .toc so users get a reminder if it's missing

---

## 13. Estimated effort

For a single experienced addon developer working with Ace3:
- Phase 1 MVP: ~20–30 hours
- Phase 2 reimbursement: ~10–15 hours
- Phase 3 sync + handouts: ~20–25 hours
- Phase 4 polish + locale: ~15 hours

**Total: ~65–85 hours** to a polished v1.0. A good starter project for someone who's written one or two addons before.