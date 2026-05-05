local _, GCL = ...

local SpellMap = GCL:NewModule("SpellMap")

-- Spell IDs for Midnight (12.0) consumable casts. These are the SPELL_CAST_SUCCESS
-- IDs that fire when a player drops a feast or cauldron in raid. They MUST be
-- verified against the live client; spell IDs commonly shift between patches.
--
-- Verify via: cast the consumable, then in chat: /run print(GetSpellInfo("<spell name>"))
-- Or examine the combat log entry's spellID column.

SpellMap.spells = {
    -- Feasts
    [457285] = { recipe = "Hearty Feast",                    placeholder = true },
    [457284] = { recipe = "Feast of the Midnight Masquerade", placeholder = true },

    -- Cauldrons
    [457290] = { recipe = "Cauldron of the Pool",            placeholder = true },
    [457291] = { recipe = "Cauldron of the Tempest",         placeholder = true },
}

function SpellMap:Get(spellID)
    return self.spells[spellID]
end

function SpellMap:Learn(spellID, recipeName)
    self.spells[spellID] = { recipe = recipeName, placeholder = false, learned = true }
    local store = GCL:GetRealmStore()
    if store then
        store.mappingsLearned[spellID] = { recipe = recipeName, learnedAt = time() }
    end
end

function SpellMap:LoadLearnedFromStore()
    local store = GCL:GetRealmStore()
    if not store or not store.mappingsLearned then return end
    for spellID, data in pairs(store.mappingsLearned) do
        if not self.spells[spellID] then
            self.spells[spellID] = { recipe = data.recipe, placeholder = false, learned = true }
        end
    end
end
