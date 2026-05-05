local _, GCL = ...

local LedgerStore = GCL:NewModule("LedgerStore")

local function genID()
    return string.format("%d-%04x-%04x",
        time(),
        math.random(0, 0xFFFF),
        math.random(0, 0xFFFF))
end

local function copperToString(copper)
    copper = math.max(0, math.floor(copper or 0))
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return string.format("%dg %ds %dc", g, s, c)
    elseif s > 0 then
        return string.format("%ds %dc", s, c)
    else
        return string.format("%dc", c)
    end
end
LedgerStore.CopperToString = copperToString

local function adjustBalance(store, providerName, delta)
    store.balances[providerName] = store.balances[providerName] or { owed = 0, paid = 0 }
    local b = store.balances[providerName]
    b.owed = b.owed + delta
    if b.owed < 0 then b.owed = 0 end
end

function LedgerStore:Record(opts)
    -- opts: providerGUID, providerName, category, spellID, recipeName,
    --       matsCost, pricingSnapshot, raidContext (optional)
    local store = GCL:GetRealmStore()
    if not store then return nil end

    local entry = {
        id = genID(),
        timestamp = time(),
        providerGUID = opts.providerGUID,
        providerName = opts.providerName,
        category = opts.category,
        spellID = opts.spellID,
        recipeName = opts.recipeName,
        raidContext = opts.raidContext,
        matsCost = opts.matsCost,
        pricingSnapshot = opts.pricingSnapshot,
        consumedCharges = nil,
        paymentStatus = "unpaid",
        paidBy = nil,
        paidAt = nil,
        paidAmount = nil,
    }

    table.insert(store.entries, entry)
    adjustBalance(store, opts.providerName, opts.matsCost)

    GCL:Print(GCL.L.LOG_RECORDED,
        opts.recipeName,
        opts.providerName,
        copperToString(opts.matsCost))

    if opts.pricingSnapshot and opts.pricingSnapshot.staleness then
        GCL:Print(GCL.L.LOG_PRICE_STALE)
    end
    if opts.pricingSnapshot and opts.pricingSnapshot.missing then
        for _, itemID in ipairs(opts.pricingSnapshot.missing) do
            GCL:Print(GCL.L.LOG_PRICE_MISSING, itemID)
        end
    end

    if GCL.MainFrame and GCL.MainFrame.Refresh then
        GCL.MainFrame:Refresh()
    end

    return entry
end

function LedgerStore:All()
    local store = GCL:GetRealmStore()
    return store and store.entries or {}
end

function LedgerStore:GetByID(id)
    for _, e in ipairs(self:All()) do
        if e.id == id then return e end
    end
end

function LedgerStore:MarkPaid(id, mode, amount)
    local entry = self:GetByID(id)
    if not entry or entry.paymentStatus ~= "unpaid" then return false end
    entry.paymentStatus = mode or "credited"
    entry.paidAt = time()
    entry.paidBy = UnitName("player")
    entry.paidAmount = amount or entry.matsCost

    local store = GCL:GetRealmStore()
    if store then
        adjustBalance(store, entry.providerName, -(entry.paidAmount or entry.matsCost))
        store.balances[entry.providerName] = store.balances[entry.providerName] or { owed = 0, paid = 0 }
        store.balances[entry.providerName].paid =
            (store.balances[entry.providerName].paid or 0) + (entry.paidAmount or entry.matsCost)
    end

    GCL:Print(GCL.L.LOG_PAID, entry.id)

    if GCL.MainFrame and GCL.MainFrame.Refresh then
        GCL.MainFrame:Refresh()
    end
    return true
end

function LedgerStore:IncrementCharges(id)
    local entry = self:GetByID(id)
    if not entry then return false end
    entry.consumedCharges = (entry.consumedCharges or 0) + 1
    if GCL.MainFrame and GCL.MainFrame.Refresh then
        GCL.MainFrame:Refresh()
    end
    return true
end

function LedgerStore:PrintRecent(n)
    local entries = self:All()
    local count = #entries
    n = math.min(n or 10, count)
    if count == 0 then
        GCL:Print(GCL.L.UI_EMPTY)
        return
    end
    for i = count - n + 1, count do
        local e = entries[i]
        GCL:Print("%s | %s | %s | %s | %s",
            date("%Y-%m-%d %H:%M", e.timestamp),
            e.providerName or "?",
            e.recipeName or "?",
            copperToString(e.matsCost),
            e.paymentStatus)
    end
end
