local _, GCL = ...

local SettingsPanel = GCL:NewModule("SettingsPanel")

local CATEGORIES = { "cauldron", "feast", "flask", "food", "potion", "rune", "phial" }
local STRATEGIES = { "auctionator", "lowestBuyout", "manual" }

-- ---------------------------------------------------------------------------
-- Pure logic helpers, exposed for tests.
-- ---------------------------------------------------------------------------
function SettingsPanel:SetCategoryEnabled(category, enabled)
    local profile = GCL:GetProfile()
    if not profile then return false end
    profile.enabledCategories = profile.enabledCategories or {}
    profile.enabledCategories[category] = enabled and true or false
    return true
end

function SettingsPanel:IsCategoryEnabled(category)
    local profile = GCL:GetProfile()
    if not profile or not profile.enabledCategories then return false end
    return profile.enabledCategories[category] == true
end

SettingsPanel.MULTIPLIER_MIN = 0.1
SettingsPanel.MULTIPLIER_MAX = 10.0

function SettingsPanel:SetMultiplier(value)
    local profile = GCL:GetProfile()
    if not profile then return false end
    local v = tonumber(value)
    if not v or v <= 0 then return false end
    if v < self.MULTIPLIER_MIN or v > self.MULTIPLIER_MAX then return false end
    profile.multiplier = v
    return true
end

function SettingsPanel:SetRoundTo(value)
    local profile = GCL:GetProfile()
    if not profile then return false end
    local v = tonumber(value)
    if not v or v < 1 then v = 1 end
    profile.roundTo = math.floor(v)
    return true
end

function SettingsPanel:SetPricingStrategy(strategy)
    for _, s in ipairs(STRATEGIES) do
        if s == strategy then
            local profile = GCL:GetProfile()
            if profile then profile.pricingStrategy = strategy; return true end
        end
    end
    return false
end

function SettingsPanel:SetHandoutTracking(enabled)
    local profile = GCL:GetProfile()
    if not profile then return false end
    profile.handoutTrackingEnabled = enabled and true or false
    return true
end

function SettingsPanel:SetCommsEnabled(enabled)
    local profile = GCL:GetProfile()
    if not profile then return false end
    profile.commsEnabled = enabled and true or false
    return true
end

-- Returns a list of itemIDs referenced by RecipeMap that currently have no
-- Auctionator price. Used to populate the manual price editor with the most
-- relevant gaps first.
function SettingsPanel:MissingPriceItemIDs()
    local seen, list = {}, {}
    if not GCL.RecipeMap or not GCL.RecipeMap.recipes then return list end
    for _, recipe in pairs(GCL.RecipeMap.recipes) do
        if recipe.reagents then
            for _, mat in ipairs(recipe.reagents) do
                if not seen[mat.itemID] then
                    seen[mat.itemID] = true
                    local price = GCL.AuctionatorAdapter
                        and select(1, GCL.AuctionatorAdapter:GetPrice(mat.itemID))
                    if not price or price == 0 then
                        table.insert(list, mat.itemID)
                    end
                end
            end
        end
    end
    table.sort(list)
    return list
end

-- ---------------------------------------------------------------------------
-- UI (lazy-built).
-- ---------------------------------------------------------------------------
local frame

local function buildToggle(parent, label, getter, setter, anchorTo, yOffset)
    local cb = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset or -2)
    if cb.Text then cb.Text:SetText(label) end
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
    return cb
end

local function buildFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "GuildConsumableLedgerSettingsFrame",
        UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(420, 460)
    frame:SetPoint("CENTER", 60, 30)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText(GCL.L.UI_SETTINGS_TITLE or "Guild Consumable Ledger — Settings")

    local categoriesHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    categoriesHeader:SetPoint("TOPLEFT", 16, -32)
    categoriesHeader:SetText(GCL.L.UI_SETTINGS_CATEGORIES or "Tracked categories")

    local last = categoriesHeader
    for _, cat in ipairs(CATEGORIES) do
        local cb = buildToggle(frame, cat,
            function() return SettingsPanel:IsCategoryEnabled(cat) end,
            function(v) SettingsPanel:SetCategoryEnabled(cat, v) end,
            last, -2)
        last = cb
    end

    local handoutHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    handoutHeader:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -10)
    handoutHeader:SetText(GCL.L.UI_SETTINGS_OTHER or "Other")

    local handoutCB = buildToggle(frame, GCL.L.UI_SETTINGS_HANDOUT or "Track mail/trade handouts",
        function()
            local p = GCL:GetProfile(); return p and p.handoutTrackingEnabled == true
        end,
        function(v) SettingsPanel:SetHandoutTracking(v) end,
        handoutHeader, -2)

    local commsCB = buildToggle(frame, GCL.L.UI_SETTINGS_COMMS or "Sync via guild addon channel",
        function()
            local p = GCL:GetProfile(); return p and p.commsEnabled ~= false
        end,
        function(v) SettingsPanel:SetCommsEnabled(v) end,
        handoutCB, -2)

    -- Multiplier slider
    local mulLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mulLabel:SetPoint("TOPLEFT", commsCB, "BOTTOMLEFT", 0, -16)
    mulLabel:SetText(GCL.L.UI_SETTINGS_MULTIPLIER or "Cost multiplier")

    local slider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", mulLabel, "BOTTOMLEFT", 4, -16)
    slider:SetWidth(220)
    slider:SetMinMaxValues(0.5, 2.0)
    slider:SetValueStep(0.05)
    slider:SetObeyStepOnDrag(true)
    local p = GCL:GetProfile()
    slider:SetValue((p and p.multiplier) or 1.0)
    slider.Low = _G[slider:GetName() and slider:GetName() .. "Low" or ""] or nil
    slider:SetScript("OnValueChanged", function(self, value)
        SettingsPanel:SetMultiplier(value)
        if self.valueText then
            self.valueText:SetText(string.format("%.2fx", value))
        end
    end)
    slider.valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slider.valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    slider.valueText:SetText(string.format("%.2fx", (p and p.multiplier) or 1.0))

    return frame
end

function SettingsPanel:Show() buildFrame(); frame:Show() end
function SettingsPanel:Hide() if frame then frame:Hide() end end
function SettingsPanel:Toggle()
    buildFrame()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
