local _, GCL = ...

-- In-game test harness. All commands route through `/gcl test <subcommand>`.
-- The harness bypasses the raid-instance gate so you can develop outside a raid.
-- It writes to the same ledger as production drops, so use `clean` to remove
-- test rows before going live, or use a fresh character profile.

local SimHarness = GCL:NewModule("SimHarness")

local FAKE_PRICES = {
    -- itemID -> copper. Round numbers make verification easy.
    [222731] = 50000,    -- 5g placeholder herb
    [222730] = 25000,    -- 2g50s placeholder ingredient A
    [222729] = 10000,    -- 1g placeholder ingredient B
    [222741] = 80000,    -- 8g placeholder herb
    [222742] = 200000,   -- 20g placeholder essence
    [222743] = 1000000,  -- 100g placeholder vial
}
local TEST_PROVIDER = "TestAlchemist-TestRealm"
local TEST_GUID = "Player-0-TESTGUID"

local function seedPrices()
    for itemID, price in pairs(FAKE_PRICES) do
        GCL.ManualPriceTable:Set(itemID, price)
    end
    GCL:Print("seeded %d fake prices into manual table", (function()
        local n = 0; for _ in pairs(FAKE_PRICES) do n = n + 1 end; return n
    end)())
end

local function clearPrices()
    for itemID in pairs(FAKE_PRICES) do
        GCL.ManualPriceTable:Clear(itemID)
    end
    GCL:Print("cleared fake prices")
end

-- Simulate the same path CastTracker takes, but skip raid/group gates.
local function simulateCast(recipeName, spellID, providerName, providerGUID)
    local recipe = GCL.RecipeMap:Get(recipeName)
    if not recipe then
        GCL:Print("|cFFFF6060unknown recipe '%s'|r", recipeName)
        return
    end
    local cost, snapshot = GCL.CostCalculator:Resolve(recipeName)
    GCL.LedgerStore:Record({
        providerGUID = providerGUID or TEST_GUID,
        providerName = providerName or TEST_PROVIDER,
        category = recipe.category,
        spellID = spellID or 0,
        recipeName = recipeName,
        matsCost = cost,
        pricingSnapshot = snapshot,
        raidContext = { instance = "Test Realm", instanceType = "raid", difficulty = 16 },
    })
end

local SCENARIOS = {
    feast = function() simulateCast("Feast of the Midnight Masquerade", 457284) end,
    hearty = function() simulateCast("Hearty Feast", 457285) end,
    cauldron = function() simulateCast("Cauldron of the Pool", 457290) end,
    tempest = function() simulateCast("Cauldron of the Tempest", 457291) end,
    multi = function()
        simulateCast("Feast of the Midnight Masquerade", 457284, "AlchemistA-Test")
        simulateCast("Hearty Feast", 457285, "ChefB-Test")
        simulateCast("Cauldron of the Pool", 457290, "FlaskmasterC-Test")
    end,
}

local function listScenarios()
    GCL:Print("Test scenarios (run with /gcl test <name>):")
    GCL:Print("  seed       - install fake manual prices for placeholder reagents")
    GCL:Print("  unseed     - remove fake manual prices")
    GCL:Print("  feast      - simulate one Feast drop")
    GCL:Print("  hearty     - simulate one Hearty Feast drop (composedOf)")
    GCL:Print("  cauldron   - simulate one Cauldron of the Pool drop")
    GCL:Print("  tempest    - simulate one Cauldron of the Tempest drop")
    GCL:Print("  multi      - simulate one of each from different providers")
    GCL:Print("  inspect    - dump last ledger entry's pricingSnapshot")
    GCL:Print("  clean      - delete test entries from the ledger")
end

local function inspectLast()
    local entries = GCL.LedgerStore:All()
    local last = entries[#entries]
    if not last then GCL:Print("no entries"); return end
    GCL:Print("=== last entry ===")
    GCL:Print("id: %s | provider: %s | recipe: %s", last.id, last.providerName, last.recipeName)
    GCL:Print("matsCost: %s | snapshotDate: %s | source: %s",
        GCL.LedgerStore.CopperToString(last.matsCost),
        last.pricingSnapshot and last.pricingSnapshot.snapshotDate or "?",
        last.pricingSnapshot and last.pricingSnapshot.priceSource or "?")
    if last.pricingSnapshot and last.pricingSnapshot.reagents then
        for itemID, leaf in pairs(last.pricingSnapshot.reagents) do
            GCL:Print("  reagent %d: qty=%d unit=%s",
                itemID, leaf.qty, GCL.LedgerStore.CopperToString(leaf.unit))
        end
    end
    if last.pricingSnapshot and last.pricingSnapshot.composedOf then
        for _, c in ipairs(last.pricingSnapshot.composedOf) do
            GCL:Print("  composedOf: %s x %d (unitCost=%s)",
                c.recipe, c.qty, GCL.LedgerStore.CopperToString(c.unitCost))
        end
    end
end

local function clean()
    local store = GCL:GetRealmStore()
    if not store then return end
    local before = #store.entries
    local kept = {}
    for _, e in ipairs(store.entries) do
        local isTest =
            (e.providerName and e.providerName:find("-Test", 1, true)) or
            e.providerName == TEST_PROVIDER
        if not isTest then table.insert(kept, e) end
    end
    store.entries = kept
    if GCL.BalanceCalculator then GCL.BalanceCalculator:Recompute() end
    if GCL.MainFrame and GCL.MainFrame.Refresh then GCL.MainFrame:Refresh() end
    GCL:Print("removed %d test entries (%d remain)", before - #kept, #kept)
end

function SimHarness:Run(arg)
    arg = (arg or ""):lower()
    if arg == "" or arg == "list" or arg == "help" then listScenarios(); return end
    if arg == "seed"    then seedPrices(); return end
    if arg == "unseed"  then clearPrices(); return end
    if arg == "inspect" then inspectLast(); return end
    if arg == "clean"   then clean(); return end
    local fn = SCENARIOS[arg]
    if fn then fn() else GCL:Print("|cFFFF6060unknown scenario '%s'|r — try /gcl test list", arg) end
end
