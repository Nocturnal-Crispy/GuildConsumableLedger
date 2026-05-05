-- Minimal WoW API stubs sufficient to load this addon's pure-logic modules
-- (Core/Init, Data/*, Pricing/*, Ledger/*) outside the game client. UI and
-- combat-log modules are not loaded by these tests.

local M = {}

function M.install()
    _G.GuildConsumableLedgerDB = nil

    _G.GetRealmName       = function() return "TestRealm" end
    _G.UnitFactionGroup   = function() return "Alliance" end
    _G.GetGuildInfo       = function() return "TestGuild" end
    _G.UnitName           = function() return "TestPlayer" end
    _G.UnitInRaid         = function() return false end
    _G.UnitInParty        = function() return false end
    _G.UnitIsUnit         = function() return false end
    _G.IsInInstance       = function() return true, "raid" end
    _G.GetInstanceInfo    = function() return "Test Raid", "raid", 16 end
    _G.GetServerTime      = os.time
    _G.time               = os.time
    _G.date               = os.date

    -- Auctionator API simulator. Each test installs its own price function.
    _G.Auctionator = {
        API = {
            v1 = {
                GetAuctionPriceByItemID = function(_, itemID)
                    if M._mockPrices then return M._mockPrices[itemID] end
                    return nil
                end,
            },
        },
    }
    -- Seed a fresh scan timestamp so AuctionatorAdapter:IsStale() returns false
    -- by default. Tests that need stale data can override AUCTIONATOR_PRICE_DATABASE.
    _G.AUCTIONATOR_PRICE_DATABASE = { TestRealm = { __lastUpdate = os.time() } }

    -- Slash commands tables (Core/Init.lua assigns into these — harmless here).
    _G.SLASH_GCL1 = nil
    _G.SLASH_GCL2 = nil
    _G.SLASH_GCL3 = nil
    _G.SlashCmdList = setmetatable({}, { __newindex = function(t, k, v) rawset(t, k, v) end })

    -- Frame stub for EventBus.lua (not strictly needed since we don't load EventBus).
    _G.CreateFrame = function() return setmetatable({
        SetScript = function() end,
        RegisterEvent = function() end,
    }, { __index = function() return function() end end }) end

    -- Chat sink — collected for assertions.
    M.chatLog = {}
    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, msg) table.insert(M.chatLog, msg) end,
    }
end

function M.setMockPrices(prices)
    M._mockPrices = prices
end

function M.clearMockPrices()
    M._mockPrices = nil
end

return M
