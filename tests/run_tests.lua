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
loadModule("Reimbursement/BankCredit.lua")
loadModule("Reimbursement/ReportExporter.lua")
loadModule("Core/Comms.lua")
loadModule("Tracking/HandoutTracker.lua")

-- Phase 4 modules whose pure-logic surface is testable. We skip the UI-frame
-- builders by only exercising the module's pure helpers.
loadModule("UI/MemberPanel.lua")
loadModule("UI/SettingsPanel.lua")
loadModule("UI/LearnDialog.lua")

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

local function resetStore()
    local store = GCL:GetRealmStore()
    store.entries = {}
    store.balances = {}
end

local function recordTwoUnpaid()
    stubs.setMockPrices({ [222731] = 50000, [222730] = 25000, [222729] = 10000 })
    for i = 1, 2 do
        local cost, snap = GCL.CostCalculator:Resolve("Feast of the Midnight Masquerade")
        GCL.LedgerStore:Record({
            providerGUID = "Player-1-AAA",
            providerName = "Alchy-TestRealm",
            category = "feast",
            spellID = 457284,
            recipeName = "Feast of the Midnight Masquerade",
            matsCost = cost,
            pricingSnapshot = snap,
        })
    end
    stubs.clearMockPrices()
end

suite("BankCredit: Credit single entry")
do
    resetStore()
    recordTwoUnpaid()
    local store = GCL:GetRealmStore()
    local id = store.entries[1].id
    local ok_ = GCL.BankCredit:Credit(id)
    ok("BankCredit:Credit returned true", ok_ == true)
    eq("status -> credited", store.entries[1].paymentStatus, "credited")
    eq("balance owed reduced by entry cost",
        store.balances["Alchy-TestRealm"].owed, 225000)  -- still 1 unpaid x 225000
    eq("balance paid increased", store.balances["Alchy-TestRealm"].paid, 225000)
end

suite("BankCredit: Credit unknown id is no-op")
do
    local ok_ = GCL.BankCredit:Credit("does-not-exist")
    ok("returns false on missing id", ok_ == false)
end

suite("BankCredit: SettleAll bulk-credits unpaid for provider")
do
    resetStore()
    recordTwoUnpaid()
    -- Add one entry for a different provider that should NOT be touched.
    stubs.setMockPrices({ [222731] = 50000, [222730] = 25000, [222729] = 10000 })
    local cost, snap = GCL.CostCalculator:Resolve("Feast of the Midnight Masquerade")
    GCL.LedgerStore:Record({
        providerGUID = "Player-9-ZZZ",
        providerName = "Other-TestRealm",
        category = "feast",
        spellID = 457284,
        recipeName = "Feast of the Midnight Masquerade",
        matsCost = cost,
        pricingSnapshot = snap,
    })
    stubs.clearMockPrices()

    local count, total = GCL.BankCredit:SettleAll("Alchy-TestRealm")
    eq("count = 2", count, 2)
    eq("total = 450000", total, 450000)

    local store = GCL:GetRealmStore()
    eq("Alchy owed cleared", store.balances["Alchy-TestRealm"].owed, 0)
    eq("Alchy paid = 450000", store.balances["Alchy-TestRealm"].paid, 450000)
    eq("Other still unpaid", store.balances["Other-TestRealm"].owed, 225000)
end

suite("BankCredit: SettleAll on unknown provider returns 0")
do
    local count, total = GCL.BankCredit:SettleAll("Nobody-TestRealm")
    eq("count = 0", count, 0)
    eq("total = 0", total, 0)
end

suite("ReportExporter: BuildCSV header + rows")
do
    resetStore()
    recordTwoUnpaid()
    local csv, n = GCL.ReportExporter:BuildCSV()
    eq("csv entry count", n, 2)
    ok("CSV has header row",
        csv:sub(1, #"date,provider,category,recipe,cost_copper,cost_readable,status")
        == "date,provider,category,recipe,cost_copper,cost_readable,status")
    ok("CSV contains provider", csv:find("Alchy%-TestRealm", 1) ~= nil)
    ok("CSV contains cost", csv:find("225000", 1) ~= nil)
end

suite("ReportExporter: BuildCSV escapes embedded commas and quotes")
do
    resetStore()
    stubs.setMockPrices({ [222731] = 50000, [222730] = 25000, [222729] = 10000 })
    local cost, snap = GCL.CostCalculator:Resolve("Feast of the Midnight Masquerade")
    GCL.LedgerStore:Record({
        providerGUID = "Player-1-AAA",
        providerName = 'Bob "the Brewer", Esq.',
        category = "feast",
        spellID = 457284,
        recipeName = "Feast of the Midnight Masquerade",
        matsCost = cost,
        pricingSnapshot = snap,
    })
    stubs.clearMockPrices()
    local csv = GCL.ReportExporter:BuildCSV({ provider = 'Bob "the Brewer", Esq.' })
    ok("contains quoted/escaped field",
        csv:find('"Bob ""the Brewer"", Esq."', 1, true) ~= nil)
end

suite("ReportExporter: filter by status")
do
    resetStore()
    recordTwoUnpaid()
    local store = GCL:GetRealmStore()
    GCL.LedgerStore:MarkPaid(store.entries[1].id, "credited", store.entries[1].matsCost)
    local csv, n = GCL.ReportExporter:BuildCSV({ status = "unpaid" })
    eq("only unpaid included", n, 1)
    local _, paidN = GCL.ReportExporter:BuildCSV({ status = "credited" })
    eq("only credited included", paidN, 1)
end

suite("ReportExporter: BuildText aggregates by provider")
do
    resetStore()
    recordTwoUnpaid()
    local txt, n = GCL.ReportExporter:BuildText()
    eq("entry count", n, 2)
    ok("contains header line", txt:find("Guild Consumable Ledger Report", 1, true) ~= nil)
    ok("contains provider summary",
        txt:find("Alchy%-TestRealm", 1) ~= nil)
    ok("aggregates total of two entries to 45g",
        txt:find("total 45g 0s 0c", 1) ~= nil)
end

suite("Comms: Serialize / Deserialize roundtrip")
do
    local payload = GCL.Comms:Serialize("CAST_SEEN",
        { "Player-1-AAA", "Vethric-Stormrage", 457285, 1700000000, "abc-123" })
    local mt, fields = GCL.Comms:Deserialize(payload)
    eq("messageType", mt, "CAST_SEEN")
    eq("field count", #fields, 5)
    eq("guid", fields[1], "Player-1-AAA")
    eq("name", fields[2], "Vethric-Stormrage")
    eq("spellID-as-string", fields[3], "457285")
end

suite("Comms: payload with delimiter and special chars survives")
do
    local payload = GCL.Comms:Serialize("MAPPING_LEARNED",
        { "457285", 'Hearty | Feast "v2"', "newline\nhere" })
    local _, fields = GCL.Comms:Deserialize(payload)
    eq("name with pipe and quote", fields[2], 'Hearty | Feast "v2"')
    eq("name with newline", fields[3], "newline\nhere")
end

suite("Comms: Deserialize on empty/garbage")
do
    local mt = GCL.Comms:Deserialize("")
    ok("empty payload yields nil", mt == nil)
    local mt2 = GCL.Comms:Deserialize(nil)
    ok("nil payload yields nil", mt2 == nil)
end

suite("Comms: ShouldRecordCast witness dedup")
do
    GCL.Comms:ResetWitnessTable()
    local W = GCL.Comms.WITNESS_DEDUP_SECONDS
    -- Anchor on a bucket boundary so we control which calls share a bucket.
    local t = math.floor(1700000000 / W) * W
    ok("first witness records", GCL.Comms:ShouldRecordCast("guid-1", 12345, t) == true)
    ok("second witness same bucket suppressed",
        GCL.Comms:ShouldRecordCast("guid-1", 12345, t + 2) == false)
    ok("third witness same bucket still suppressed",
        GCL.Comms:ShouldRecordCast("guid-1", 12345, t + W - 1) == false)
    ok("next bucket records again",
        GCL.Comms:ShouldRecordCast("guid-1", 12345, t + W) == true)
    ok("different source same bucket records",
        GCL.Comms:ShouldRecordCast("guid-2", 12345, t + 1) == true)
end

suite("HandoutTracker: BuildTrackedItemSet sources from RecipeMap")
do
    local set = GCL.HandoutTracker:BuildTrackedItemSet()
    ok("Hearty Feast in tracked set",
        set[222733] and set[222733].recipe == "Hearty Feast")
    ok("Feast in tracked set",
        set[222732] and set[222732].category == "feast")
    ok("Cauldron in tracked set",
        set[222740] and set[222740].category == "cauldron")
    ok("Flask in tracked set",
        set[222750] and set[222750].category == "flask")
end

suite("HandoutTracker: ResolveItemLink matches by itemID")
do
    local set = GCL.HandoutTracker:BuildTrackedItemSet()
    local hit = GCL.HandoutTracker:ResolveItemLink(
        "|cffa335ee|Hitem:222733::::::::82:::::|h[Hearty Feast]|h|r", set)
    ok("matched Hearty Feast link",
        hit and hit.recipe == "Hearty Feast" and hit.category == "feast")
    local miss = GCL.HandoutTracker:ResolveItemLink(
        "|cffffffff|Hitem:99999::|h[Random]|h|r", set)
    ok("untracked link returns nil", miss == nil)
    local invalid = GCL.HandoutTracker:ResolveItemLink("not a link", set)
    ok("garbage returns nil", invalid == nil)
end

suite("HandoutTracker: CollectTrackedFromList filters mixed list")
do
    local set = GCL.HandoutTracker:BuildTrackedItemSet()
    local links = {
        "|cff|Hitem:222733::|h[Hearty]|h|r",         -- tracked
        "|cff|Hitem:99999::|h[Random]|h|r",           -- untracked
        "|cff|Hitem:222740::|h[Cauldron]|h|r",        -- tracked
        "garbage",                                    -- invalid
    }
    local matches = GCL.HandoutTracker:CollectTrackedFromList(links, set)
    eq("two matches", #matches, 2)
end

suite("MemberPanel: Aggregate filters by player")
do
    resetStore()
    stubs.setMockPrices({ [222731] = 50000, [222730] = 25000, [222729] = 10000 })
    local cost, snap = GCL.CostCalculator:Resolve("Feast of the Midnight Masquerade")
    GCL.LedgerStore:Record({
        providerGUID = "Player-1-AAA", providerName = "Vethric-Stormrage",
        category = "feast", spellID = 457284,
        recipeName = "Feast of the Midnight Masquerade",
        matsCost = cost, pricingSnapshot = snap,
    })
    GCL.LedgerStore:Record({
        providerGUID = "Player-1-AAA", providerName = "Vethric-Stormrage",
        category = "feast", spellID = 457284,
        recipeName = "Feast of the Midnight Masquerade",
        matsCost = cost, pricingSnapshot = snap,
    })
    GCL.LedgerStore:Record({
        providerGUID = "Player-2-BBB", providerName = "Other-Stormrage",
        category = "feast", spellID = 457284,
        recipeName = "Feast of the Midnight Masquerade",
        matsCost = cost, pricingSnapshot = snap,
    })
    stubs.clearMockPrices()

    local agg = GCL.MemberPanel:Aggregate("Vethric-Stormrage")
    eq("count", agg.count, 2)
    eq("total", agg.total, 450000)
    eq("unpaid", agg.unpaid, 450000)
    eq("paid", agg.paid, 0)
    -- Match by short name should also work
    local agg2 = GCL.MemberPanel:Aggregate("Vethric")
    eq("short-name match count", agg2.count, 2)
    -- Empty / nil player returns zero
    local empty = GCL.MemberPanel:Aggregate(nil)
    eq("nil player count", empty.count, 0)
end

suite("SettingsPanel: category toggles persist on profile")
do
    GCL.SettingsPanel:SetCategoryEnabled("flask", true)
    ok("flask enabled", GCL.SettingsPanel:IsCategoryEnabled("flask"))
    GCL.SettingsPanel:SetCategoryEnabled("flask", false)
    ok("flask disabled", not GCL.SettingsPanel:IsCategoryEnabled("flask"))
end

suite("SettingsPanel: SetMultiplier rejects invalid values")
do
    local profile = GCL:GetProfile()
    profile.multiplier = 1.0
    ok("accepts 1.5", GCL.SettingsPanel:SetMultiplier(1.5))
    eq("multiplier set", profile.multiplier, 1.5)
    ok("rejects 0", GCL.SettingsPanel:SetMultiplier(0) == false)
    ok("rejects negative", GCL.SettingsPanel:SetMultiplier(-1) == false)
    ok("rejects non-numeric", GCL.SettingsPanel:SetMultiplier("abc") == false)
    ok("rejects above MULTIPLIER_MAX",
        GCL.SettingsPanel:SetMultiplier(GCL.SettingsPanel.MULTIPLIER_MAX + 1) == false)
    ok("rejects below MULTIPLIER_MIN",
        GCL.SettingsPanel:SetMultiplier(GCL.SettingsPanel.MULTIPLIER_MIN / 2) == false)
    eq("multiplier preserved after rejected sets", profile.multiplier, 1.5)
    profile.multiplier = 1.0
end

suite("LedgerStore: IncrementCharges")
do
    resetStore()
    recordTwoUnpaid()
    local store = GCL:GetRealmStore()
    local id = store.entries[1].id
    ok("first increment", GCL.LedgerStore:IncrementCharges(id) == true)
    ok("second increment", GCL.LedgerStore:IncrementCharges(id) == true)
    eq("consumedCharges accumulated", store.entries[1].consumedCharges, 2)
    ok("unknown id returns false",
        GCL.LedgerStore:IncrementCharges("does-not-exist") == false)
end

suite("SettingsPanel: SetPricingStrategy validates")
do
    ok("auctionator accepted",
        GCL.SettingsPanel:SetPricingStrategy("auctionator") == true)
    ok("manual accepted",
        GCL.SettingsPanel:SetPricingStrategy("manual") == true)
    ok("garbage rejected",
        GCL.SettingsPanel:SetPricingStrategy("magic") == false)
end

suite("SettingsPanel: MissingPriceItemIDs lists items without prices")
do
    stubs.setMockPrices({})  -- nothing
    local list = GCL.SettingsPanel:MissingPriceItemIDs()
    ok("non-empty when nothing priced", #list > 0)
    -- All known reagents missing → all should be in the list. The Hearty
    -- Feast composite has no own reagents, so its mats live under its
    -- sub-recipe — but the composite's itemID is not iterated here.
    stubs.setMockPrices({
        [222731] = 50000, [222730] = 25000, [222729] = 10000,
        [222741] = 80000, [222742] = 200000, [222743] = 1000000,
        [222750] = 1, [222751] = 1, [222760] = 1, [222761] = 1,
    })
    local listAll = GCL.SettingsPanel:MissingPriceItemIDs()
    eq("nothing missing once all priced", #listAll, 0)
    stubs.clearMockPrices()
end

suite("LearnDialog: LookupRecipeName resolves case-insensitively")
do
    eq("exact match",
        GCL.LearnDialog:LookupRecipeName("Hearty Feast"), "Hearty Feast")
    eq("case-insensitive match",
        GCL.LearnDialog:LookupRecipeName("hearty feast"), "Hearty Feast")
    ok("unknown returns nil",
        GCL.LearnDialog:LookupRecipeName("Fake Recipe") == nil)
    ok("nil returns nil",
        GCL.LearnDialog:LookupRecipeName(nil) == nil)
end

suite("LearnDialog: Save persists mapping via SpellMap")
do
    -- Use a fresh spellID
    local sid = 999991
    ok("not yet known", GCL.SpellMap:Get(sid) == nil)
    local ok_, resolved = GCL.LearnDialog:Save(sid, "hearty feast")
    ok("save returns true", ok_ == true)
    eq("save returns canonical name", resolved, "Hearty Feast")
    local mapping = GCL.SpellMap:Get(sid)
    ok("SpellMap learned mapping", mapping and mapping.recipe == "Hearty Feast")
    -- Unknown recipe rejected
    local ok2, err = GCL.LearnDialog:Save(999992, "Fake Recipe")
    ok("unknown recipe rejected", ok2 == false)
    ok("error string returned", err == "unknown recipe")
end

suite("LearnDialog: IsActive honours expiry")
do
    GCL.LearnDialog:Deactivate()
    ok("inactive by default", not GCL.LearnDialog:IsActive())
    GCL.LearnDialog:Activate()
    ok("active after Activate", GCL.LearnDialog:IsActive())
    -- Simulate a future time past the window
    ok("expires after window",
        not GCL.LearnDialog:IsActive(GCL.LearnDialog.expiresAt + 1))
    ok("auto-deactivates after expiry check",
        GCL.LearnDialog.active == false)
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
