local _, GCL = ...

local ReportExporter = GCL:NewModule("ReportExporter")

local function copperToString(copper)
    if GCL.LedgerStore and GCL.LedgerStore.CopperToString then
        return GCL.LedgerStore.CopperToString(copper)
    end
    return tostring(copper or 0) .. "c"
end

local function passesFilter(entry, filter)
    if not filter then return true end
    if filter.provider and entry.providerName ~= filter.provider then return false end
    if filter.category and entry.category ~= filter.category then return false end
    if filter.status and entry.paymentStatus ~= filter.status then return false end
    if filter.from and (entry.timestamp or 0) < filter.from then return false end
    if filter.to and (entry.timestamp or 0) > filter.to then return false end
    return true
end

local function gatherEntries(filter)
    local matches = {}
    if not GCL.LedgerStore then return matches end
    for _, e in ipairs(GCL.LedgerStore:All()) do
        if passesFilter(e, filter) then
            table.insert(matches, e)
        end
    end
    table.sort(matches, function(a, b)
        local ta, tb = a.timestamp or 0, b.timestamp or 0
        if ta ~= tb then return ta < tb end
        -- Stable secondary key: entry id is generated with timestamp+randomness
        -- so this gives deterministic order for same-second drops.
        return (a.id or "") < (b.id or "")
    end)
    return matches
end

-- CSV escaping per RFC 4180: wrap in quotes, double any embedded quote.
local function csvField(value)
    local s = tostring(value == nil and "" or value)
    if s:find('[",\r\n]') then
        s = '"' .. s:gsub('"', '""') .. '"'
    end
    return s
end

local CSV_HEADER = "date,provider,category,recipe,cost_copper,cost_readable,status"

function ReportExporter:BuildCSV(filter)
    local entries = gatherEntries(filter)
    local lines = { CSV_HEADER }
    for _, e in ipairs(entries) do
        table.insert(lines, table.concat({
            csvField(date("%Y-%m-%d %H:%M", e.timestamp or 0)),
            csvField(e.providerName),
            csvField(e.category),
            csvField(e.recipeName),
            csvField(e.matsCost or 0),
            csvField(copperToString(e.matsCost or 0)),
            csvField(e.paymentStatus),
        }, ","))
    end
    return table.concat(lines, "\n"), #entries
end

function ReportExporter:BuildText(filter)
    local entries = gatherEntries(filter)
    local byProvider = {}
    local order = {}
    local grandTotal, grandUnpaid = 0, 0
    for _, e in ipairs(entries) do
        local who = e.providerName or "?"
        local agg = byProvider[who]
        if not agg then
            agg = { name = who, total = 0, unpaid = 0, count = 0, byCategory = {} }
            byProvider[who] = agg
            table.insert(order, who)
        end
        agg.count = agg.count + 1
        agg.total = agg.total + (e.matsCost or 0)
        if e.paymentStatus == "unpaid" then
            agg.unpaid = agg.unpaid + (e.matsCost or 0)
            grandUnpaid = grandUnpaid + (e.matsCost or 0)
        end
        local cat = e.category or "?"
        agg.byCategory[cat] = (agg.byCategory[cat] or 0) + (e.matsCost or 0)
        grandTotal = grandTotal + (e.matsCost or 0)
    end

    table.sort(order, function(a, b)
        return (byProvider[b].unpaid) < (byProvider[a].unpaid)
    end)

    local lines = {
        string.format("=== Guild Consumable Ledger Report ==="),
        string.format("Generated: %s", date("%Y-%m-%d %H:%M:%S")),
        string.format("Entries: %d   Total: %s   Unpaid: %s",
            #entries, copperToString(grandTotal), copperToString(grandUnpaid)),
        "",
    }
    for _, who in ipairs(order) do
        local agg = byProvider[who]
        table.insert(lines, string.format("%s — %d entries, total %s, unpaid %s",
            agg.name, agg.count,
            copperToString(agg.total),
            copperToString(agg.unpaid)))
        for cat, v in pairs(agg.byCategory) do
            table.insert(lines, string.format("    %s: %s", cat, copperToString(v)))
        end
    end
    return table.concat(lines, "\n"), #entries
end

-- ---------------------------------------------------------------------------
-- Modal dialog with selectable text. Lazy-built; the same frame is reused.
-- ---------------------------------------------------------------------------
local dialog

local function buildDialog()
    if dialog then return dialog end

    dialog = CreateFrame("Frame", "GuildConsumableLedgerExportFrame",
        UIParent, "BasicFrameTemplateWithInset")
    dialog:SetSize(560, 360)
    dialog:SetPoint("CENTER")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:SetClampedToScreen(true)
    dialog:SetFrameStrata("DIALOG")
    dialog:Hide()

    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dialog.title:SetPoint("TOP", 0, -5)
    dialog.title:SetText(GCL.L.UI_EXPORT_TITLE or "Export Report")

    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 16, -32)
    hint:SetText(GCL.L.UI_EXPORT_HINT or "Click in box, Ctrl+A to select all, Ctrl+C to copy.")

    -- Format toggle
    local csvBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    csvBtn:SetSize(80, 22)
    csvBtn:SetPoint("TOPRIGHT", -16, -28)
    csvBtn:SetText("CSV")

    local textBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    textBtn:SetSize(80, 22)
    textBtn:SetPoint("RIGHT", csvBtn, "LEFT", -4, 0)
    textBtn:SetText(GCL.L.UI_EXPORT_FORMAT_TEXT or "Text")

    local scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -56)
    scroll:SetPoint("BOTTOMRIGHT", -36, 16)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(500)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
    scroll:SetScrollChild(edit)
    dialog.edit = edit
    dialog.scroll = scroll

    local function setText(s, count)
        edit:SetText(s)
        edit:HighlightText()
        edit:SetCursorPosition(0)
        edit:SetWidth(scroll:GetWidth() - 4)
        dialog.title:SetText(string.format("%s (%d %s)",
            GCL.L.UI_EXPORT_TITLE or "Export Report",
            count or 0,
            (count == 1) and "entry" or "entries"))
    end

    csvBtn:SetScript("OnClick", function()
        local s, n = ReportExporter:BuildCSV(dialog.filter)
        setText(s, n)
    end)
    textBtn:SetScript("OnClick", function()
        local s, n = ReportExporter:BuildText(dialog.filter)
        setText(s, n)
    end)

    dialog.setText = setText
    return dialog
end

function ReportExporter:Show(filter, format)
    local d = buildDialog()
    d.filter = filter
    if format == "csv" then
        local s, n = self:BuildCSV(filter)
        d.setText(s, n)
    else
        local s, n = self:BuildText(filter)
        d.setText(s, n)
    end
    d:Show()
end

function ReportExporter:Hide()
    if dialog then dialog:Hide() end
end
