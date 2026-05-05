local _, GCL = ...

local RecipeMap = GCL:NewModule("RecipeMap")

-- Reagent item IDs are seeded for the Midnight (12.0) era and may need
-- updating per patch. The first patch of an expansion always shifts these.
-- The /gcl learn flow (Phase 4) lets officers update entries without code edits.

-- Format:
--   reagents = { { itemID = N, qty = N }, ... }                   -- leaf recipe
--   composedOf = { { recipe = "Other Recipe Name", qty = N } }    -- composite

RecipeMap.recipes = {
    ["Harandar Celebration"] = {
        category = "feast",
        itemID = 255846,                       -- finished item; AH price for min-vs-craft check
        spellID = 1226175,
        reagents = {
            { itemID = 242640, qty = 10 },     -- Plant Protein
            { itemID = 242647, qty = 4 },      -- Tavern Fixings
            { itemID = 242641, qty = 3 },      -- Cooking Spirits
            { itemID = 236951, qty = 3 },      -- Mote of Wild Magic
            { itemID = 236774, qty = 3 },      -- Azeroot
            { itemID = 251285, qty = 1 },      -- Petrified Root
        },
    },
    ["Hearty Harandar Celebration"] = {
        category = "feast",
        itemID = 266996,
        composedOf = {
            { recipe = "Harandar Celebration", qty = 10 },
        },
    },
    ["Voidlight Potion Cauldron"] = {
        category = "cauldron",
        itemID = 241284,
        spellID = 1230857,
        reagents = {
            { itemID = 236780, qty = 1 },      -- Nocturnal Lotus
            { itemID = 242651, qty = 5 },      -- Stabilized Derivate
            { itemID = 251285, qty = 4 },      -- Petrified Root
            { itemID = 240991, qty = 20 },     -- Sunglass Vial
            { itemID = 241283, qty = 4 },      -- Wondrous Synergist
        },
    },
    ["Cauldron of Sin'dorei Flasks"] = {
        category = "cauldron",
        itemID = 241318,
        spellID = 1230874,
        reagents = {
            { itemID = 236780, qty = 1 },      -- Nocturnal Lotus
            { itemID = 242651, qty = 5 },      -- Stabilized Derivate
            { itemID = 251285, qty = 4 },      -- Petrified Root
            { itemID = 240991, qty = 20 },     -- Sunglass Vial
            { itemID = 241283, qty = 4 },      -- Wondrous Synergist
        },
    }
}

function RecipeMap:Get(name)
    return self.recipes[name]
end
