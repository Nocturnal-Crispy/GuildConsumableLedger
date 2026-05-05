#!/usr/bin/env lua
-- Headless unit tests for GuildConsumableLedger pure-logic modules.
-- Run from the addon root:
--   lua tests/run_tests.lua
-- Requires lua 5.1+ (or luajit). No external dependencies.

package.path = "./tests/?.lua;" .. package.path

local stubs = require("wow_stubs")
stubs.install()

-- ----------------------------------------------------------------------------
-- Tiny test harness
-- ----------------------------------------------------------------------------
local pass, fail, failures = 0, 0, {}
local currentSuite = ""

local function suite(name)
    currentSuite = name
    print(("\n=== %s ==="):format(name))
end

local function ok(label, condition, detail)
    if condition then
        pass = pass + 1
        print(("  PASS  %s"):format(label))
    else
        fail = fail + 1
        local msg = ("[%s] %s%s"):format(currentSuite, label, detail and (" — " .. detail) or "")
        table.insert(failures, msg)
        print(("  FAIL  %s%s"):format(label, detail and (" — " .. detail) or ""))
    end
end

local function eq(label, actual, expected)
    ok(label, actual == expected,
        ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

-- ----------------------------------------------------------------------------
-- Load addon modules under a synthetic addon table mimicking the WoW vararg.
-- ----------------------------------------------------------------------------
local GCL = {}
local function loadModule(relPath)
    -- WoW addon files are loaded as `function(addonName, addonTable) <body> end`.
    -- We replicate by reading the file and executing in a chunk that gets the
    -- vararg via load()'s second arg trick.
    local f, err = io.open(relPath, "r")
    if not f then error("cannot open " .. relPath .. ": " .. tostring(err)) end
    local src = f:read("*a"); f:close()
    local chunk, lerr = load(src, "@" .. relPath, "t")
    if not chunk then error("load error in " .. relPath .. ": " .. lerr) end
    -- WoW provides the vararg; in plain Lua we use debug.sethook tricks — easier:
    -- wrap source in `local _, GCL = ...; <body>` already at file level. We
    -- pass the table via setfenv/load env. But the files use `local _, GCL = ...`
    -- so we just call the chunk with the vararg.
    chunk("GuildConsumableLedger", GCL)
end

loadModule("Locale/enUS.lua")
loadModule("Core/Init.lua")
loadModule("Data/RecipeMap.lua")
loadModule("Data/SpellMap.lua")
loadModule("Pricing/ManualPriceTable.lua")
loadModule("Pricing/AuctionatorAdapter.lua")
loadModule("Pricing/CostCalculator.lua")
loadModule("Ledger/LedgerStore.lua")
loadModule("Ledger/BalanceCalculator.lua")

GCL:InitDB()
GCL.AuctionatorAdapter:Probe()

-- ----------------------------------------------------------------------------
-- Tests
-- ----------------------------------------------------------------------------

suite("CostCalculator: leaf recipe with Auctionator prices")
do
    stubs.setMockPrices({
        [222731] = 50000,    -- 5g
        [222730] = 25000,    -- 2g50s
        [222729] = 10000,    -- 1g
    })
    local cost, snap = GCL.CostCalculator:Resolve("Feast of the Midnight Masquerade")
    -- 1*50000 + 5*25000 + 5*10000 = 50000 + 125000 + 50000 = 225000c = 22g50s
    eq("matsCost = 225000c", cost, 225000)
    eq("priceSource = auctionator", snap.priceSource, "auctionator")
    eq("not stale", snap.staleness, false)
    eq("snapshotDate set", type(snap.snapshotDate), "string")
    eq("reagent qty for 222731", snap.reagents[222731].qty, 1)
    eq("reagent unit for 222731", snap.reagents[222731].unit, 50000)
    stubs.clearMockPrices()
end

suite("CostCalculator: composedOf (Hearty Feast = 10x Feast)")
do
    stubs.setMockPrices({
        [222731] = 50000,
        [222730] = 25000,
        [222729] = 10000,
        -- intentionally no market price for Hearty Feast itself
    })
    local cost, snap = GCL.CostCalculator:Resolve("Hearty Feast")
    -- 10 * 225000 = 2,250,000c = 225g
    eq("Hearty matsCost = 2250000c", cost, 2250000)
    ok("composedOf populated", snap.composedOf and #snap.composedOf == 1)
    if snap.composedOf and snap.composedOf[1] then
        eq("composedOf recipe name", snap.composedOf[1].recipe, "Feast of the Midnight Masquerade")
        eq("composedOf qty", snap.composedOf[1].qty, 10)
        eq("composedOf unitCost", snap.composedOf[1].unitCost, 225000)
    end
    -- Reagents should be flattened with qty multiplied by 10
    eq("flattened reagent 222731 qty", snap.reagents[222731].qty, 10)
    eq("flattened reagent 222730 qty", snap.reagents[222730].qty, 50)
    stubs.clearMockPrices()
end

suite("CostCalculator: market-vs-craft min for composite (Hearty Feast cheaper at AH)")
do
    stubs.setMockPrices({
        [222731] = 50000,
        [222730] = 25000,
        [222729] = 10000,
        [222733] = 1500000,  -- Hearty Feast on AH for 150g — cheaper than 225g craft
    })
    local cost, snap = GCL.CostCalculator:Resolve("Hearty Feast")
    eq("uses cheaper market price", cost, 1500000)
    eq("usedMarketPrice flag", snap.usedMarketPrice, true)
    stubs.clearMockPrices()
end

suite("CostCalculator: Auctionator missing falls back to manual price")
do
    stubs.setMockPrices(nil)
    GCL.ManualPriceTable:Set(222741, 80000)
    GCL.ManualPriceTable:Set(222742, 200000)
    GCL.ManualPriceTable:Set(222743, 1000000)
    local cost, snap = GCL.CostCalculator:Resolve("Cauldron of the Pool")
    -- 12*80000 + 4*200000 + 1*1000000 = 960000 + 800000 + 1000000 = 2760000c
    eq("Cauldron cost via manual", cost, 2760000)
    eq("priceSource = manual", snap.priceSource, "manual")
    GCL.ManualPriceTable:Clear(222741)
    GCL.ManualPriceTable:Clear(222742)
    GCL.ManualPriceTable:Clear(222743)
end

suite("CostCalculator: missing prices flagged in snapshot.missing")
do
    stubs.setMockPrices({})  -- empty: Auctionator has nothing
    local cost, snap = GCL.CostCalculator:Resolve("Cauldron of the Pool")
    eq("cost = 0 with no prices", cost, 0)
    ok("missing list non-empty", #snap.missing == 3,
        ("got " .. #snap.missing .. " missing items"))
    stubs.clearMockPrices()
end

suite("LedgerStore: Record + MarkPaid roundtrip")
do
    -- Wipe entries from prior tests
    local store = GCL:GetRealmStore()
    store.entries = {}
    store.balances = {}

    stubs.setMockPrices({ [222731] = 50000, [222730] = 25000, [222729] = 10000 })
    local cost, snap = GCL.CostCalculator:Resolve("Feast of the Midnight Masquerade")

    local entry = GCL.LedgerStore:Record({
        providerGUID = "Player-1-AAA",
        providerName = "Alchy-TestRealm",
        category = "feast",
        spellID = 457284,
        recipeName = "Feast of the Midnight Masquerade",
        matsCost = cost,
        pricingSnapshot = snap,
    })
    ok("entry created", entry ~= nil)
    eq("entry status starts unpaid", entry.paymentStatus, "unpaid")
    eq("balance owed updated", store.balances["Alchy-TestRealm"].owed, 225000)

    GCL.LedgerStore:MarkPaid(entry.id, "credited")
    local refetched = GCL.LedgerStore:GetByID(entry.id)
    eq("paid status persisted", refetched.paymentStatus, "credited")
    eq("balance owed cleared", store.balances["Alchy-TestRealm"].owed, 0)
    eq("balance paid recorded", store.balances["Alchy-TestRealm"].paid, 225000)
    stubs.clearMockPrices()
end

suite("LedgerStore: pricingSnapshot is frozen, not recomputed")
do
    local store = GCL:GetRealmStore()
    store.entries = {}
    store.balances = {}

    -- Tuesday: prices low
    stubs.setMockPrices({ [222731] = 50000, [222730] = 25000, [222729] = 10000 })
    local costTue, snapTue = GCL.CostCalculator:Resolve("Feast of the Midnight Masquerade")
    GCL.LedgerStore:Record({
        providerGUID = "Player-1-AAA",
        providerName = "Alchy-TestRealm",
        category = "feast",
        spellID = 457284,
        recipeName = "Feast of the Midnight Masquerade",
        matsCost = costTue,
        pricingSnapshot = snapTue,
    })

    -- Thursday: prices double — fresh resolve must produce a different cost,
    -- but Tuesday's stored entry must NOT change.
    stubs.setMockPrices({ [222731] = 100000, [222730] = 50000, [222729] = 20000 })
    local costThu, snapThu = GCL.CostCalculator:Resolve("Feast of the Midnight Masquerade")
    GCL.LedgerStore:Record({
        providerGUID = "Player-1-AAA",
        providerName = "Alchy-TestRealm",
        category = "feast",
        spellID = 457284,
        recipeName = "Feast of the Midnight Masquerade",
        matsCost = costThu,
        pricingSnapshot = snapThu,
    })

    local entries = GCL.LedgerStore:All()
    eq("two entries", #entries, 2)
    eq("Tuesday cost frozen at 225000", entries[1].matsCost, 225000)
    eq("Thursday cost recorded at 450000", entries[2].matsCost, 450000)
    eq("Tuesday snapshot unit unchanged", entries[1].pricingSnapshot.reagents[222731].unit, 50000)
    eq("Thursday snapshot unit doubled", entries[2].pricingSnapshot.reagents[222731].unit, 100000)
    stubs.clearMockPrices()
end

suite("BalanceCalculator: Recompute from entries")
do
    GCL.BalanceCalculator:Recompute()
    local store = GCL:GetRealmStore()
    -- After previous test: 2 unpaid entries totaling 675000 for Alchy
    eq("recomputed owed", store.balances["Alchy-TestRealm"].owed, 675000)
    eq("recomputed paid", store.balances["Alchy-TestRealm"].paid, 0)
end

-- ----------------------------------------------------------------------------
-- Summary
-- ----------------------------------------------------------------------------
print("")
print(("Results: %d passed, %d failed"):format(pass, fail))
if fail > 0 then
    print("\nFailures:")
    for _, f in ipairs(failures) do print("  - " .. f) end
    os.exit(1)
else
    os.exit(0)
end
