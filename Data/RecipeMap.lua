local _, GCL = ...

local RecipeMap = GCL:NewModule("RecipeMap")

-- Reagent item IDs are seeded for The War Within / Midnight era and may need
-- updating per patch. The first patch of an expansion always shifts these.
-- The /gcl learn flow (Phase 4) lets officers update entries without code edits.

-- Format:
--   reagents = { { itemID = N, qty = N }, ... }                   -- leaf recipe
--   composedOf = { { recipe = "Other Recipe Name", qty = N } }    -- composite

RecipeMap.recipes = {
    ["Feast of the Midnight Masquerade"] = {
        category = "feast",
        itemID = 222732,                       -- finished item; AH price for min-vs-craft check
        reagents = {
            { itemID = 222731, qty = 1 },      -- placeholder Algari herb
            { itemID = 222730, qty = 5 },      -- placeholder ingredient A
            { itemID = 222729, qty = 5 },      -- placeholder ingredient B
        },
    },
    ["Hearty Feast"] = {
        category = "feast",
        itemID = 222733,
        composedOf = {
            { recipe = "Feast of the Midnight Masquerade", qty = 10 },
        },
    },
    ["Cauldron of the Pool"] = {
        category = "cauldron",
        itemID = 222740,
        reagents = {
            { itemID = 222741, qty = 12 },     -- placeholder herbs
            { itemID = 222742, qty = 4 },      -- placeholder essence
            { itemID = 222743, qty = 1 },      -- placeholder vial
        },
    },
    ["Cauldron of the Tempest"] = {
        category = "cauldron",
        itemID = 222744,
        reagents = {
            { itemID = 222741, qty = 18 },
            { itemID = 222742, qty = 6 },
            { itemID = 222743, qty = 1 },
        },
    },
    ["Flask of Alchemical Chaos"] = {
        category = "flask",
        itemID = 222750,
        reagents = {
            { itemID = 222731, qty = 5 },
            { itemID = 222730, qty = 2 },
        },
    },
    ["Flask of Tempered Aggression"] = {
        category = "flask",
        itemID = 222751,
        reagents = {
            { itemID = 222731, qty = 5 },
            { itemID = 222729, qty = 4 },
        },
    },
    ["Sizzling Salmon Stew"] = {
        category = "food",
        itemID = 222760,
        reagents = {
            { itemID = 222730, qty = 4 },
            { itemID = 222729, qty = 2 },
        },
    },
    ["Roast Duck Delight"] = {
        category = "food",
        itemID = 222761,
        reagents = {
            { itemID = 222731, qty = 2 },
            { itemID = 222729, qty = 4 },
        },
    },
}

function RecipeMap:Get(name)
    return self.recipes[name]
end
