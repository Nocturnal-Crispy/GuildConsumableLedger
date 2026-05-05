local _, GCL = ...

local MainFrame = GCL:NewModule("MainFrame")

local FRAME_W, FRAME_H = 860, 460
local ROW_H = 22
local VISIBLE_ROWS = 14

local COLS = {
    { key = "date",     label_key = "UI_COL_DATE",     width = 130, align = "LEFT"  },
    { key = "provider", label_key = "UI_COL_PROVIDER", width = 140, align = "LEFT"  },
    { key = "recipe",   label_key = "UI_COL_RECIPE",   width = 220, align = "LEFT"  },
    { key = "cost",     label_key = "UI_COL_COST",     width = 110, align = "RIGHT" },
    { key = "status",   label_key = "UI_COL_STATUS",   width = 80,  align = "LEFT"  },
    { key = "action",   label_key = "UI_COL_ACTION",   width = 120, align = "CENTER"},
}

local frame
local rowPool = {}
local scroll
local scrollChild
local sortKey = "date"
local sortAsc = false

local function statusLabel(s)
    local L = GCL.L
    if s == "unpaid"   then return L.UI_STATUS_UNPAID   end
    if s == "mailed"   then return L.UI_STATUS_MAILED   end
    if s == "credited" then return L.UI_STATUS_CREDITED end
    if s == "reported" then return L.UI_STATUS_REPORTED end
    return s
end

local function comparator(a, b)
    local k = sortKey
    if k == "date" then
        if sortAsc then return (a.timestamp or 0) < (b.timestamp or 0)
        else return (a.timestamp or 0) > (b.timestamp or 0) end
    elseif k == "provider" then
        if sortAsc then return (a.providerName or "") < (b.providerName or "")
        else return (a.providerName or "") > (b.providerName or "") end
    elseif k == "recipe" then
        if sortAsc then return (a.recipeName or "") < (b.recipeName or "")
        else return (a.recipeName or "") > (b.recipeName or "") end
    elseif k == "cost" then
        if sortAsc then return (a.matsCost or 0) < (b.matsCost or 0)
        else return (a.matsCost or 0) > (b.matsCost or 0) end
    elseif k == "status" then
        if sortAsc then return (a.paymentStatus or "") < (b.paymentStatus or "")
        else return (a.paymentStatus or "") > (b.paymentStatus or "") end
    end
    return false
end

local function buildHeaderRow(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(FRAME_W - 40, ROW_H)
    header:SetPoint("TOPLEFT", 16, -42)

    local x = 0
    for _, col in ipairs(COLS) do
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(col.width, ROW_H)
        btn:SetPoint("LEFT", x, 0)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint(col.align, btn, col.align, col.align == "RIGHT" and -4 or 4, 0)
        fs:SetText(GCL.L[col.label_key])

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.15, 0.6)

        if col.key ~= "action" then
            btn:SetScript("OnClick", function()
                if sortKey == col.key then
                    sortAsc = not sortAsc
                else
                    sortKey = col.key
                    sortAsc = (col.key == "provider" or col.key == "recipe")
                end
                MainFrame:Refresh()
            end)
            btn:SetScript("OnEnter", function() bg:SetColorTexture(0.2, 0.2, 0.3, 0.7) end)
            btn:SetScript("OnLeave", function() bg:SetColorTexture(0.1, 0.1, 0.15, 0.6) end)
        end
        x = x + col.width
    end
    return header
end

local function acquireRow(parent, index)
    local row = rowPool[index]
    if row then return row end

    row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_W - 40, ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    local x = 0
    row.cells = {}
    for _, col in ipairs(COLS) do
        if col.key == "action" then
            local container = CreateFrame("Frame", nil, row)
            container:SetSize(col.width - 4, ROW_H)
            container:SetPoint("LEFT", x + 2, 0)

            -- Two action buttons split the column. The Status column already
            -- shows "Credited" / "Mailed" so paid rows simply hide both.
            local btnW = math.floor((col.width - 12) / 2)
            local mailBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
            mailBtn:SetSize(btnW, ROW_H - 4)
            mailBtn:SetPoint("LEFT", 2, 0)
            mailBtn:SetText(GCL.L.UI_BTN_MAIL or "Mail")
            row.mailBtn = mailBtn

            local creditBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
            creditBtn:SetSize(btnW, ROW_H - 4)
            creditBtn:SetPoint("LEFT", mailBtn, "RIGHT", 4, 0)
            creditBtn:SetText(GCL.L.UI_BTN_CREDIT or "Credit")
            row.creditBtn = creditBtn

            row.cells[col.key] = container
        else
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetSize(col.width - 8, ROW_H)
            fs:SetJustifyH(col.align)
            fs:SetWordWrap(false)
            fs:SetPoint("LEFT", x + 4, 0)
            row.cells[col.key] = fs
        end
        x = x + col.width
    end

    rowPool[index] = row
    return row
end

local function emptyLabel(parent)
    if parent.emptyFS then return parent.emptyFS end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    fs:SetPoint("CENTER", parent, "CENTER", 0, 0)
    parent.emptyFS = fs
    return fs
end

function MainFrame:Build()
    if frame then return frame end

    frame = CreateFrame("Frame", "GuildConsumableLedgerFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText(GCL.L.UI_TITLE .. " — v" .. GCL.VERSION)

    -- Refresh button
    local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refresh:SetSize(80, 22)
    refresh:SetPoint("BOTTOMRIGHT", -16, 12)
    refresh:SetText(GCL.L.UI_BTN_REFRESH)
    refresh:SetScript("OnClick", function() MainFrame:Refresh() end)

    -- Export button (opens ReportExporter dialog)
    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 22)
    exportBtn:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
    exportBtn:SetText(GCL.L.UI_BTN_EXPORT or "Export")
    exportBtn:SetScript("OnClick", function()
        if GCL.ReportExporter and GCL.ReportExporter.Show then
            GCL.ReportExporter:Show(nil, "text")
        end
    end)

    -- Status footer
    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.footer:SetPoint("BOTTOMLEFT", 16, 16)

    -- Header row
    buildHeaderRow(frame)

    -- Scroll frame
    scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -42 - ROW_H - 4)
    scroll:SetPoint("BOTTOMRIGHT", -36, 40)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(FRAME_W - 60, ROW_H * VISIBLE_ROWS)
    scroll:SetScrollChild(scrollChild)

    self:Refresh()
    return frame
end

function MainFrame:Show()
    self:Build()
    frame:Show()
    self:Refresh()
end

function MainFrame:Hide()
    if frame then frame:Hide() end
end

function MainFrame:Toggle()
    self:Build()
    if frame:IsShown() then frame:Hide() else self:Show() end
end

function MainFrame:Refresh()
    if not frame then return end
    if not GCL.LedgerStore then return end

    local entries = {}
    for _, e in ipairs(GCL.LedgerStore:All()) do
        table.insert(entries, e)
    end
    table.sort(entries, comparator)

    local empty = emptyLabel(scrollChild)
    if #entries == 0 then
        empty:SetText(GCL.L.UI_EMPTY)
        empty:Show()
    else
        empty:Hide()
    end

    -- Resize scroll child
    scrollChild:SetHeight(math.max(ROW_H * VISIBLE_ROWS, ROW_H * #entries))

    -- Hide all pooled rows
    for _, r in ipairs(rowPool) do r:Hide() end

    for i, e in ipairs(entries) do
        local row = acquireRow(scrollChild, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
        row:SetWidth(scrollChild:GetWidth())

        if i % 2 == 0 then
            row.bg:SetColorTexture(0.05, 0.05, 0.08, 0.5)
        else
            row.bg:SetColorTexture(0.0, 0.0, 0.0, 0.3)
        end

        local dateStr = date("%Y-%m-%d %H:%M", e.timestamp or 0)
        row.cells.date:SetText(dateStr)
        row.cells.provider:SetText(e.providerName or "?")

        local recipeText = e.recipeName or "?"
        if e.pricingSnapshot and e.pricingSnapshot.staleness then
            recipeText = recipeText .. "  " .. GCL.L.UI_STALE_TAG
        end
        if e.pricingSnapshot and e.pricingSnapshot.missing
            and #e.pricingSnapshot.missing > 0 then
            recipeText = recipeText .. "  " .. GCL.L.UI_NOPRICE_TAG
        end
        row.cells.recipe:SetText(recipeText)

        row.cells.cost:SetText(GCL.LedgerStore.CopperToString(e.matsCost or 0))
        row.cells.status:SetText(statusLabel(e.paymentStatus))

        local entryID = e.id
        if e.paymentStatus == "unpaid" then
            row.mailBtn:Show()
            row.mailBtn:Enable()
            row.mailBtn:SetScript("OnClick", function()
                if GCL.MailPayer and GCL.MailPayer.Pay then
                    GCL.MailPayer:Pay(entryID)
                end
            end)
            row.creditBtn:Show()
            row.creditBtn:Enable()
            row.creditBtn:SetScript("OnClick", function()
                if GCL.BankCredit and GCL.BankCredit.Credit then
                    GCL.BankCredit:Credit(entryID)
                end
            end)
        else
            row.mailBtn:Hide()
            row.creditBtn:Hide()
        end

        row:Show()
    end

    -- Footer summary
    local owedTotal = 0
    for _, e in ipairs(entries) do
        if e.paymentStatus == "unpaid" then
            owedTotal = owedTotal + (e.matsCost or 0)
        end
    end
    frame.footer:SetText(string.format("%d entries — %s outstanding",
        #entries,
        GCL.LedgerStore.CopperToString(owedTotal)))
end
