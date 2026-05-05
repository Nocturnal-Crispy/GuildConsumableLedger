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

    -- Personal flask creation (Alchemy crafting cast). Verify per-patch.
    [457300] = { recipe = "Flask of Alchemical Chaos",       placeholder = true },
    [457301] = { recipe = "Flask of Tempered Aggression",    placeholder = true },

    -- Personal food creation (Cooking crafting cast). Verify per-patch.
    [457310] = { recipe = "Sizzling Salmon Stew",            placeholder = true },
    [457311] = { recipe = "Roast Duck Delight",              placeholder = true },
}

function SpellMap:Get(spellID)
    return self.spells[spellID]
end
