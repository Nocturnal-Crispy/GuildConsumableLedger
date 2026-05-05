local _, GCL = ...

local ManualPriceTable = GCL:NewModule("ManualPriceTable")

local function store()
    local s = GCL:GetRealmStore()
    return s and s.manualPrices
end

function ManualPriceTable:Get(itemID)
    local s = store()
    return s and s[itemID]
end

function ManualPriceTable:Set(itemID, copperPrice)
    local s = store()
    if not s then return end
    s[itemID] = copperPrice
end

function ManualPriceTable:Clear(itemID)
    local s = store()
    if not s then return end
    s[itemID] = nil
end
