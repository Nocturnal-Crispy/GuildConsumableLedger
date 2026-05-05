local _, GCL = ...

local LearnDialog = GCL:NewModule("LearnDialog")

LearnDialog.active = false
LearnDialog.expiresAt = 0
LearnDialog.LEARN_WINDOW_SECONDS = 300  -- 5 minutes

-- ---------------------------------------------------------------------------
-- Pure: turn a recipe-name string into a known recipe entry, or nil if not in
-- the RecipeMap. Used by the dialog Save handler.
-- ---------------------------------------------------------------------------
function LearnDialog:LookupRecipeName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not GCL.RecipeMap or not GCL.RecipeMap.recipes then return nil end
    if GCL.RecipeMap.recipes[name] then return name end
    local lower = name:lower()
    for known in pairs(GCL.RecipeMap.recipes) do
        if known:lower() == lower then return known end
    end
    return nil
end

function LearnDialog:Activate()
    self.active = true
    self.expiresAt = (time and time() or os.time()) + self.LEARN_WINDOW_SECONDS
    GCL:Print(GCL.L.LEARN_ACTIVE or "Learn mode active for 5 minutes — cast an unknown consumable spell.")
end

function LearnDialog:Deactivate()
    self.active = false
    self.expiresAt = 0
end

function LearnDialog:IsActive(now)
    if not self.active then return false end
    now = now or (time and time() or os.time())
    if now > self.expiresAt then
        self:Deactivate()
        return false
    end
    return true
end

-- Save: bind a spellID to a recipe name. Persists via SpellMap and broadcasts
-- MAPPING_LEARNED to peers if Comms is enabled.
function LearnDialog:Save(spellID, recipeName)
    local resolved = self:LookupRecipeName(recipeName)
    if not resolved then return false, "unknown recipe" end
    if not GCL.SpellMap or not GCL.SpellMap.Learn then return false, "no SpellMap" end
    GCL.SpellMap:Learn(spellID, resolved)
    if GCL.Comms then
        local profile = GCL:GetProfile()
        if profile and profile.commsEnabled ~= false then
            GCL.Comms:Send("MAPPING_LEARNED", { spellID, resolved })
        end
    end
    return true, resolved
end

-- ---------------------------------------------------------------------------
-- UI prompt. Built lazily; reused on subsequent unknown-spell hits.
-- ---------------------------------------------------------------------------
local dialog

local function buildDialog()
    if dialog then return dialog end
    dialog = CreateFrame("Frame", "GuildConsumableLedgerLearnFrame",
        UIParent, "BasicFrameTemplateWithInset")
    dialog:SetSize(420, 200)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:SetClampedToScreen(true)
    dialog:Hide()

    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dialog.title:SetPoint("TOP", 0, -5)
    dialog.title:SetText(GCL.L.UI_LEARN_TITLE or "Learn a new consumable spell")

    dialog.spellLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.spellLabel:SetPoint("TOPLEFT", 16, -32)

    dialog.hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dialog.hint:SetPoint("TOPLEFT", 16, -52)
    dialog.hint:SetText(GCL.L.UI_LEARN_HINT
        or "Type the recipe name from RecipeMap, then click Save.")

    dialog.edit = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    dialog.edit:SetSize(380, 28)
    dialog.edit:SetPoint("TOPLEFT", 22, -76)
    dialog.edit:SetAutoFocus(false)

    local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, 24)
    saveBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    saveBtn:SetText(GCL.L.UI_BTN_SAVE or "Save")

    local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
    cancelBtn:SetText(GCL.L.UI_BTN_CANCEL or "Cancel")

    saveBtn:SetScript("OnClick", function()
        local id = dialog.spellID
        local name = dialog.edit:GetText()
        local ok_, resolvedOrErr = LearnDialog:Save(id, name)
        if ok_ then
            GCL:Print(GCL.L.LEARN_SAVED or "Mapped %d -> %s", id, resolvedOrErr)
            dialog:Hide()
        else
            GCL:Print(GCL.L.LEARN_UNKNOWN or "Recipe '%s' not in RecipeMap.", tostring(name))
        end
    end)
    cancelBtn:SetScript("OnClick", function() dialog:Hide() end)

    return dialog
end

-- Hook from CastTracker (or test harness) when an unknown SPELL_CAST_SUCCESS
-- is captured during learn mode.
function LearnDialog:Prompt(spellID, spellName)
    if not self:IsActive() then return false end
    local d = buildDialog()
    d.spellID = spellID
    d.edit:SetText("")
    d.spellLabel:SetText(string.format("Spell ID %d (%s)",
        spellID or 0, spellName or "?"))
    d:Show()
    return true
end
