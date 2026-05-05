local _, GCL = ...

local AuctionatorAdapter = GCL:NewModule("AuctionatorAdapter")

AuctionatorAdapter.callerID = "GuildConsumableLedger"
AuctionatorAdapter.available = false
AuctionatorAdapter.lastScanTime = nil

local STALE_THRESHOLD_SECONDS = 24 * 60 * 60

local function getApi()
    return _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
end

function AuctionatorAdapter:Probe()
    if getApi() then
        self.available = true
        GCL:Print(GCL.L.LOG_AUCTIONATOR_OK)
    else
        self.available = false
        GCL:Print(GCL.L.LOG_AUCTIONATOR_MISSING)
    end
    self:RefreshLastScan()
end

function AuctionatorAdapter:RefreshLastScan()
    -- Auctionator doesn't expose a public scan-time API. Read the SV directly.
    local sv = _G.AUCTIONATOR_PRICE_DATABASE
    if type(sv) ~= "table" then return end
    -- Realm key in Auctionator's SV is "Realm-Faction" or similar; pick the
    -- most recent timestamp across realm entries.
    local mostRecent
    for _, realmTable in pairs(sv) do
        if type(realmTable) == "table" and type(realmTable.__lastUpdate) == "number" then
            if not mostRecent or realmTable.__lastUpdate > mostRecent then
                mostRecent = realmTable.__lastUpdate
            end
        end
    end
    self.lastScanTime = mostRecent
end

function AuctionatorAdapter:IsStale()
    if not self.lastScanTime then return true end
    return (time() - self.lastScanTime) > STALE_THRESHOLD_SECONDS
end

-- Returns: copperPrice (number) or nil, source string, isStale boolean
function AuctionatorAdapter:GetPrice(itemID)
    local api = getApi()
    if api and api.GetAuctionPriceByItemID then
        local price = api.GetAuctionPriceByItemID(self.callerID, itemID)
        if type(price) == "number" and price > 0 then
            return price, "auctionator", self:IsStale()
        end
    end

    local sv = _G.AUCTIONATOR_PRICE_DATABASE
    if type(sv) == "table" then
        local realmKey = GetRealmName()
        local realmTable = sv[realmKey] or sv[realmKey .. "-Alliance"] or sv[realmKey .. "-Horde"]
        if type(realmTable) == "table" then
            local entry = realmTable[itemID]
            if type(entry) == "number" and entry > 0 then
                return entry, "auctionator-sv", self:IsStale()
            elseif type(entry) == "table" and type(entry.recent) == "number" then
                return entry.recent, "auctionator-sv", self:IsStale()
            end
        end
    end

    return nil, "missing", false
end
