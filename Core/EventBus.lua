local _, GCL = ...

local EventBus = GCL:NewModule("EventBus")

-- Anonymous frame: avoids polluting the global namespace and the taint vectors
-- that come with a globally-named frame being looked up by Blizzard or other
-- addons. RegisterEvent must be called at file-load time only — calling it
-- from inside an OnEvent handler triggers ADDON_ACTION_FORBIDDEN on retail.
local frame = CreateFrame("Frame")
EventBus.frame = frame

local listeners = {}
local registered = {}

function EventBus:On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
    if not registered[event] then
        registered[event] = true
        frame:RegisterEvent(event)
    end
end

function EventBus:OnCombatLog(fn)
    self:On("COMBAT_LOG_EVENT_UNFILTERED", fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local fns = listeners[event]
    if not fns then return end
    for i = 1, #fns do
        local ok, err = pcall(fns[i], event, ...)
        if not ok then
            GCL:Print("|cFFFF6060error in %s: %s|r", event, tostring(err))
        end
    end
end)

EventBus:On("ADDON_LOADED", function(_, addonName)
    if addonName ~= GCL.ADDON then return end
    GCL:InitDB()
end)

EventBus:On("PLAYER_LOGIN", function()
    if GCL.AuctionatorAdapter and GCL.AuctionatorAdapter.Probe then
        GCL.AuctionatorAdapter:Probe()
    end
    if GCL.MainFrame and GCL.MainFrame.Build then
        GCL.MainFrame:Build()
    end
    GCL:Print("v%s %s", GCL.VERSION, GCL.L.LOG_LOADED)
end)

EventBus:On("PLAYER_GUILD_UPDATE", function()
    local store = GCL:GetRealmStore()
    if store then
        store.guildName = GCL:GetGuildName() or store.guildName
    end
end)
