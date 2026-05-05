local _, GCL = ...

local BalanceCalculator = GCL:NewModule("BalanceCalculator")

function BalanceCalculator:GetAll()
    local store = GCL:GetRealmStore()
    return store and store.balances or {}
end

function BalanceCalculator:GetForProvider(providerName)
    local b = self:GetAll()[providerName]
    return b and b.owed or 0, b and b.paid or 0
end

-- Recompute balances from entries (defensive — used after manual edits or migrations).
function BalanceCalculator:Recompute()
    local store = GCL:GetRealmStore()
    if not store then return end
    local fresh = {}
    for _, e in ipairs(store.entries) do
        fresh[e.providerName] = fresh[e.providerName] or { owed = 0, paid = 0 }
        if e.paymentStatus == "unpaid" then
            fresh[e.providerName].owed = fresh[e.providerName].owed + (e.matsCost or 0)
        else
            fresh[e.providerName].paid = fresh[e.providerName].paid + (e.paidAmount or e.matsCost or 0)
        end
    end
    store.balances = fresh
end
