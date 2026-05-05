local _, GCL = ...

local CastTracker = GCL:NewModule("CastTracker")

local function isInGroupOrRaid(unitName)
    if not unitName or unitName == "" then return false end
    if UnitIsUnit(unitName, "player") then return true end
    if UnitInRaid and UnitInRaid(unitName) then return true end
    if UnitInParty and UnitInParty(unitName) then return true end
    return false
end

-- Returns true only when the player is inside a raid instance (raid zone).
-- Cauldrons and feasts dropped in cities or open world are intentionally ignored.
local function isInsideRaidInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "raid"
end

local function getRaidContext()
    local instanceName, instanceType, difficultyID = GetInstanceInfo()
    if instanceType == "raid" then
        return { instance = instanceName, instanceType = instanceType, difficulty = difficultyID }
    end
    return nil
end

local recentlyRecorded = {}
local DEDUP_WINDOW = 5  -- seconds

local function dedupKey(sourceGUID, spellID)
    return (sourceGUID or "?") .. ":" .. tostring(spellID)
end

local function isDuplicate(sourceGUID, spellID, now)
    local key = dedupKey(sourceGUID, spellID)
    local last = recentlyRecorded[key]
    if last and (now - last) < DEDUP_WINDOW then
        return true
    end
    recentlyRecorded[key] = now
    return false
end

function CastTracker:OnCombatLog()
    local _, subEvent, _, sourceGUID, sourceName, _, _, _, _, _, _, spellID =
        CombatLogGetCurrentEventInfo()
    if subEvent ~= "SPELL_CAST_SUCCESS" then return end

    -- Hard gate: only track drops that happen inside a raid instance.
    if not isInsideRaidInstance() then return end

    local mapping = GCL.SpellMap:Get(spellID)
    if not mapping then
        -- Unknown spell. If learn mode is active and the cast came from the
        -- player themselves, prompt the officer to map it. Other players'
        -- unknown casts are ignored to avoid prompt spam.
        if GCL.LearnDialog and GCL.LearnDialog.IsActive
            and GCL.LearnDialog:IsActive()
            and sourceGUID and _G.UnitGUID and sourceGUID == _G.UnitGUID("player") then
            local spellName = (_G.GetSpellInfo and _G.GetSpellInfo(spellID)) or "?"
            GCL.LearnDialog:Prompt(spellID, spellName)
        end
        return
    end

    if not isInGroupOrRaid(sourceName) then return end

    local recipe = GCL.RecipeMap:Get(mapping.recipe)
    if not recipe then return end

    local profile = GCL:GetProfile()
    if profile and profile.enabledCategories
        and profile.enabledCategories[recipe.category] == false then
        return
    end

    local now = time()
    if isDuplicate(sourceGUID, spellID, now) then return end

    -- Local witness dedup also passes through Comms.ShouldRecordCast so the
    -- bucket-time-keyed table acts as a stricter second pass within the same
    -- session. Cross-officer dedup over the addon channel is intentionally
    -- NOT enabled until peer messages can be authenticated; until then each
    -- officer writes their own entry and a manual reconciliation step (or a
    -- future signed-payload protocol) deduplicates after the fact.
    if GCL.Comms and not GCL.Comms:ShouldRecordCast(sourceGUID, spellID, now) then
        return
    end

    local cost, snapshot = GCL.CostCalculator:Resolve(mapping.recipe)

    GCL.LedgerStore:Record({
        providerGUID = sourceGUID,
        providerName = sourceName,
        category = recipe.category,
        spellID = spellID,
        recipeName = mapping.recipe,
        matsCost = cost,
        pricingSnapshot = snapshot,
        raidContext = getRaidContext(),
    })
end

function CastTracker:Init()
    GCL.SpellMap:LoadLearnedFromStore()
    GCL.EventBus:OnCombatLog(function() CastTracker:OnCombatLog() end)
end

GCL.EventBus:On("PLAYER_LOGIN", function() CastTracker:Init() end)
