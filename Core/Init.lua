local addonName, GCL = ...

GCL.ADDON = addonName
GCL.VERSION = "0.1.0-phase1"

GCL.modules = {}
function GCL:NewModule(name)
    local m = self.modules[name] or {}
    self.modules[name] = m
    self[name] = m
    return m
end

local function chatPrefix()
    return "|cFF7FD3FF[" .. (GCL.L and GCL.L.SHORT_NAME or "GCL") .. "]|r "
end

function GCL:Print(fmt, ...)
    local msg = (select("#", ...) > 0) and fmt:format(...) or fmt
    DEFAULT_CHAT_FRAME:AddMessage(chatPrefix() .. tostring(msg))
end

function GCL:GetRealmKey()
    local realm = GetRealmName() or "UnknownRealm"
    local faction = UnitFactionGroup("player") or "Neutral"
    return realm .. "-" .. faction
end

function GCL:GetGuildName()
    local name = GetGuildInfo("player")
    return name
end

function GCL:GetRealmStore()
    local db = _G.GuildConsumableLedgerDB
    if not db then return nil end
    local key = self:GetRealmKey()
    db.realms = db.realms or {}
    db.realms[key] = db.realms[key] or {
        guildName = self:GetGuildName(),
        entries = {},
        balances = {},
        manualPrices = {},
        mappingsLearned = {},
    }
    local store = db.realms[key]
    store.entries = store.entries or {}
    store.balances = store.balances or {}
    store.manualPrices = store.manualPrices or {}
    store.mappingsLearned = store.mappingsLearned or {}
    if not store.guildName then
        store.guildName = self:GetGuildName()
    end
    return store
end

local DEFAULT_PROFILE = {
    pricingStrategy = "auctionator",
    roundTo = 1,
    multiplier = 1.0,
    autoOpenForOfficers = false,
    enabledCategories = {
        cauldron = true,
        feast = true,
        flask = false,
        food = false,
        potion = false,
        rune = false,
        phial = false,
    },
}

local function deepMerge(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            target[k] = target[k] or {}
            if type(target[k]) == "table" then
                deepMerge(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

function GCL:InitDB()
    _G.GuildConsumableLedgerDB = _G.GuildConsumableLedgerDB or {}
    local db = _G.GuildConsumableLedgerDB
    db.profile = db.profile or {}
    deepMerge(db.profile, DEFAULT_PROFILE)
    db.realms = db.realms or {}
    self.db = db
end

function GCL:GetProfile()
    return self.db and self.db.profile
end

local resetPending = false
local function handleSlash(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local L = GCL.L
    if msg == "" or msg == "toggle" then
        if GCL.MainFrame and GCL.MainFrame.Toggle then GCL.MainFrame:Toggle() end
        return
    end
    if msg == "show" then
        if GCL.MainFrame and GCL.MainFrame.Show then GCL.MainFrame:Show() end
        return
    end
    if msg == "hide" then
        if GCL.MainFrame and GCL.MainFrame.Hide then GCL.MainFrame:Hide() end
        return
    end
    if msg == "version" then
        GCL:Print("v%s", GCL.VERSION)
        return
    end
    if msg == "print" then
        if GCL.LedgerStore and GCL.LedgerStore.PrintRecent then
            GCL.LedgerStore:PrintRecent(10)
        end
        return
    end
    if msg == "reset" then
        resetPending = true
        GCL:Print(L.LOG_RESET_PENDING)
        return
    end
    local testArg = msg:match("^test%s*(.*)$")
    if testArg ~= nil then
        if GCL.SimHarness and GCL.SimHarness.Run then
            GCL.SimHarness:Run(testArg)
        else
            GCL:Print("test harness not loaded")
        end
        return
    end
    if msg == "reset confirm" then
        if not resetPending then
            GCL:Print(L.LOG_RESET_PENDING)
            return
        end
        resetPending = false
        local store = GCL:GetRealmStore()
        if store then
            store.entries = {}
            store.balances = {}
            GCL:Print(L.LOG_RESET_DONE)
        end
        return
    end
    GCL:Print(L.SLASH_HELP)
    GCL:Print(L.SLASH_SHOW)
    GCL:Print(L.SLASH_HIDE)
    GCL:Print(L.SLASH_TOGGLE)
    GCL:Print(L.SLASH_PRINT)
    GCL:Print(L.SLASH_RESET)
    GCL:Print(L.SLASH_VERSION)
    GCL:Print("  test <name>    - test harness (try /gcl test list)")
end

SLASH_GCL1 = "/gcl"
SLASH_GCL2 = "/consumables"
SLASH_GCL3 = "/gcledger"
SlashCmdList["GCL"] = handleSlash
