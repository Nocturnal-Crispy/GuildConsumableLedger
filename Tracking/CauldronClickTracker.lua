local _, GCL = ...

local CauldronClickTracker = GCL:NewModule("CauldronClickTracker")

-- Maps cauldron-flask buff IDs to the cauldron recipe that produced them.
-- When a guildmate gets a flask buff and the source is a guild cauldron, we
-- attribute one charge of consumption to the most recent matching cauldron
-- entry. Because the actual buff IDs vary per patch, this table is seeded
-- empty; officers populate it via /gcl learn (Phase 4) or by editing.
CauldronClickTracker.buffMap = {
    -- [buffSpellID] = "Cauldron of the Pool",
    -- [buffSpellID] = "Cauldron of the Tempest",
}

function CauldronClickTracker:RegisterBuff(buffSpellID, recipeName)
    self.buffMap[buffSpellID] = recipeName
end

-- Find the most recent unpaid cauldron entry of the matching recipe. Charge
-- attribution is best-effort: we increment consumedCharges on that entry.
local function mostRecentCauldron(recipeName)
    if not GCL.LedgerStore then return nil end
    local entries = GCL.LedgerStore:All()
    for i = #entries, 1, -1 do
        local e = entries[i]
        if e.category == "cauldron" and e.recipeName == recipeName then
            return e
        end
    end
    return nil
end

function CauldronClickTracker:OnCombatLog()
    local _, subEvent, _, _sourceGUID, _sourceName, _, _, _destGUID, destName, _, _, spellID =
        _G.CombatLogGetCurrentEventInfo()
    if subEvent ~= "SPELL_AURA_APPLIED" then return end
    local recipe = self.buffMap[spellID]
    if not recipe then return end

    local profile = GCL:GetProfile()
    if not profile or profile.attributeCauldronCharges ~= true then return end

    -- Only count charges consumed by group/raid members.
    if not destName then return end
    if _G.UnitInRaid and _G.UnitInRaid(destName) then
        -- ok
    elseif _G.UnitInParty and _G.UnitInParty(destName) then
        -- ok
    else
        return
    end

    local entry = mostRecentCauldron(recipe)
    if not entry then return end
    if GCL.LedgerStore and GCL.LedgerStore.IncrementCharges then
        GCL.LedgerStore:IncrementCharges(entry.id)
    end
end

function CauldronClickTracker:Init()
    if GCL.EventBus then
        GCL.EventBus:OnCombatLog(function() CauldronClickTracker:OnCombatLog() end)
    end
end

if GCL.EventBus then
    GCL.EventBus:On("PLAYER_LOGIN", function() CauldronClickTracker:Init() end)
end
