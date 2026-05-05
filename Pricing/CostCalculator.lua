local _, GCL = ...

local CostCalculator = GCL:NewModule("CostCalculator")

local function getUnitPrice(itemID)
    local price, source, stale = GCL.AuctionatorAdapter:GetPrice(itemID)
    if not price then
        local manual = GCL.ManualPriceTable:Get(itemID)
        if manual then
            return manual, "manual", false
        end
        return 0, "missing", false
    end
    return price, source, stale
end

local function applyStrategy(profile, raw)
    local p = raw or 0
    if profile and profile.multiplier and profile.multiplier ~= 1 then
        p = p * profile.multiplier
    end
    if profile and profile.roundTo and profile.roundTo > 1 then
        local unit = profile.roundTo * 10000  -- copper per gold
        p = math.floor(p / unit + 0.5) * unit
    end
    return math.floor(p + 0.5)
end

-- Recursively resolves a recipe's cost into:
--   matsCost      (copper, scalar — sum of leaf reagents at unit prices)
--   pricingSnapshot:
--     reagents    [itemID] = { qty=N, unit=copper, source=string, stale=bool }
--     composedOf  optional list of { recipe=name, qty=N, unitCost=copper }
--     priceSource "auctionator" | "manual" | "mixed"
--     staleness   true if any leaf used stale data
--     missing     list of itemIDs with no price
function CostCalculator:Resolve(recipeName, depth)
    depth = depth or 0
    if depth > 6 then
        error("CostCalculator: composedOf depth exceeded for " .. tostring(recipeName))
    end

    local recipe = GCL.RecipeMap:Get(recipeName)
    if not recipe then
        return 0, {
            reagents = {},
            composedOf = nil,
            priceSource = "missing",
            staleness = false,
            missing = {},
            error = "unknown recipe: " .. tostring(recipeName),
        }
    end

    local snapshot = {
        reagents = {},
        composedOf = nil,
        priceSource = nil,
        staleness = false,
        missing = {},
    }

    local total = 0
    local sourcesSeen = {}

    if recipe.reagents then
        for _, mat in ipairs(recipe.reagents) do
            local unit, src, stale = getUnitPrice(mat.itemID)
            snapshot.reagents[mat.itemID] = {
                qty = mat.qty,
                unit = unit,
                source = src,
                stale = stale,
            }
            sourcesSeen[src] = true
            if stale then snapshot.staleness = true end
            if src == "missing" then
                table.insert(snapshot.missing, mat.itemID)
            end
            total = total + (unit * mat.qty)
        end
    end

    if recipe.composedOf then
        snapshot.composedOf = {}
        for _, sub in ipairs(recipe.composedOf) do
            local subCost, subSnap = self:Resolve(sub.recipe, depth + 1)
            local entry = {
                recipe = sub.recipe,
                qty = sub.qty,
                unitCost = subCost,
            }
            table.insert(snapshot.composedOf, entry)

            -- merge sub-snapshot leaves into this snapshot, scaled by qty
            for itemID, leaf in pairs(subSnap.reagents or {}) do
                local existing = snapshot.reagents[itemID]
                if existing then
                    existing.qty = existing.qty + (leaf.qty * sub.qty)
                else
                    snapshot.reagents[itemID] = {
                        qty = leaf.qty * sub.qty,
                        unit = leaf.unit,
                        source = leaf.source,
                        stale = leaf.stale,
                    }
                end
                sourcesSeen[leaf.source] = true
                if leaf.stale then snapshot.staleness = true end
            end
            for _, m in ipairs(subSnap.missing or {}) do
                table.insert(snapshot.missing, m)
            end

            total = total + (subCost * sub.qty)
        end

        -- min(reagent_cost, market_buyout) per the plan
        if recipe.itemID then
            local marketUnit = select(1, getUnitPrice(recipe.itemID))
            if marketUnit and marketUnit > 0 and marketUnit < total then
                total = marketUnit
                snapshot.usedMarketPrice = true
                snapshot.marketUnit = marketUnit
            end
        end
    end

    -- Determine combined source label
    local n, label = 0, nil
    for k in pairs(sourcesSeen) do n = n + 1; label = k end
    if n == 0 then
        snapshot.priceSource = "missing"
    elseif n == 1 then
        snapshot.priceSource = label
    else
        snapshot.priceSource = "mixed"
    end

    if depth == 0 then
        local profile = GCL:GetProfile()
        total = applyStrategy(profile, total)
        snapshot.snapshotDate = date("%Y-%m-%d")
        snapshot.snapshotTime = time()
    end

    return total, snapshot
end
