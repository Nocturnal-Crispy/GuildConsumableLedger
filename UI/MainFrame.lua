local _, GCL = ...

local MainFrame = GCL:NewModule("MainFrame")

local FRAME_W, FRAME_H = 860, 480
local ROW_H = 22
local VISIBLE_ROWS = 14
local TAB_LOGS, TAB_PEOPLE = "logs", "people"

-- ----------------------------------------------------------------------------
-- Column definitions
-- ----------------------------------------------------------------------------
local LOGS_COLS = {
    { key = "date",     label_key = "UI_COL_DATE",     width = 130, align = "LEFT"  },
    { key = "provider", label_key = "UI_COL_PROVIDER", width = 140, align = "LEFT"  },
    { key = "recipe",   label_key = "UI_COL_RECIPE",   width = 220, align = "LEFT"  },
    { key = "cost",     label_key = "UI_COL_COST",     width = 110, align = "RIGHT" },
    { key = "status",   label_key = "UI_COL_STATUS",   width = 80,  align = "LEFT"  },
    { key = "action",   label_key = "UI_COL_ACTION",   width = 120, align = "CENTER"},
}

local PEOPLE_COLS = {
    { key = "provider", label_key = "UI_COL_PROVIDER", width = 180, align = "LEFT"  },
    { key = "count",    label_key = "UI_COL_ENTRIES",  width = 70,  align = "RIGHT" },
    { key = "owed",     label_key = "UI_COL_OWED",     width = 130, align = "RIGHT" },
    { key = "paid",     label_key = "UI_COL_PAID",     width = 130, align = "RIGHT" },
    { key = "action",   label_key = "UI_COL_ACTION",   width = 250, align = "CENTER"},
}

-- ----------------------------------------------------------------------------
-- Module state
-- ----------------------------------------------------------------------------
local frame
local logsTabBtn, peopleTabBtn
local logsPanel, peoplePanel
local activeTab = TAB_LOGS

-- Logs panel state
local logsRowPool = {}
local logsScrollChild
local logsSortKey, logsSortAsc = "date", false

-- People panel state
local peopleRowPool = {}
local peopleScrollChild
local peopleSortKey, peopleSortAsc = "owed", false

-- ----------------------------------------------------------------------------
-- Pure aggregation helper (testable without UI)
-- ----------------------------------------------------------------------------
function MainFrame:AggregateByProvider()
    local list = {}
    if not GCL.LedgerStore then return list end

    local index = {}
    for _, e in ipairs(GCL.LedgerStore:All()) do
        local key = e.providerName or "?"
        local row = index[key]
        if not row then
            row = {
                providerName = key,
                count = 0,
                owed = 0,
                paid = 0,
                unpaidCount = 0,
                unpaidIDs = {},
            }
            index[key] = row
            table.insert(list, row)
        end
        row.count = row.count + 1
        if e.paymentStatus == "unpaid" then
            row.owed = row.owed + (e.matsCost or 0)
            row.unpaidCount = row.unpaidCount + 1
            table.insert(row.unpaidIDs, e.id)
        else
            row.paid = row.paid + (e.paidAmount or e.matsCost or 0)
        end
    end
    return list
end

local function statusLabel(s)
    local L = GCL.L
    if s == "unpaid"   then return L.UI_STATUS_UNPAID   end
    if s == "mailed"   then return L.UI_STATUS_MAILED   end
    if s == "credited" then return L.UI_STATUS_CREDITED end
    if s == "reported" then return L.UI_STATUS_REPORTED end
    return s
end

local function copperToString(copper)
    if GCL.LedgerStore and GCL.LedgerStore.CopperToString then
        return GCL.LedgerStore.CopperToString(copper or 0)
    end
    return tostring(copper or 0)
end

-- ----------------------------------------------------------------------------
-- Comparators
-- ----------------------------------------------------------------------------
local function logsComparator(a, b)
    local k, asc = logsSortKey, logsSortAsc
    if k == "date" then
        if asc then return (a.timestamp or 0) < (b.timestamp or 0)
        else return (a.timestamp or 0) > (b.timestamp or 0) end
    elseif k == "provider" then
        if asc then return (a.providerName or "") < (b.providerName or "")
        else return (a.providerName or "") > (b.providerName or "") end
    elseif k == "recipe" then
        if asc then return (a.recipeName or "") < (b.recipeName or "")
        else return (a.recipeName or "") > (b.recipeName or "") end
    elseif k == "cost" then
        if asc then return (a.matsCost or 0) < (b.matsCost or 0)
        else return (a.matsCost or 0) > (b.matsCost or 0) end
    elseif k == "status" then
        if asc then return (a.paymentStatus or "") < (b.paymentStatus or "")
        else return (a.paymentStatus or "") > (b.paymentStatus or "") end
    end
    return false
end

local function peopleComparator(a, b)
    local k, asc = peopleSortKey, peopleSortAsc
    if k == "provider" then
        if asc then return a.providerName < b.providerName
        else return a.providerName > b.providerName end
    elseif k == "count" then
        if asc then return a.count < b.count
        else return a.count > b.count end
    elseif k == "paid" then
        if asc then return a.paid < b.paid
        else return a.paid > b.paid end
    end
    -- default and "owed"
    if asc then return a.owed < b.owed
    else return a.owed > b.owed end
end

-- ----------------------------------------------------------------------------
-- Header builder shared by both panels
-- ----------------------------------------------------------------------------
local function buildHeader(parent, columns, onSort)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(FRAME_W - 40, ROW_H)
    header:SetPoint("TOPLEFT", 0, 0)

    local x = 0
    for _, col in ipairs(columns) do
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(col.width, ROW_H)
        btn:SetPoint("LEFT", x, 0)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint(col.align, btn, col.align, col.align == "RIGHT" and -4 or 4, 0)
        fs:SetText(GCL.L[col.label_key] or col.label_key)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.15, 0.6)

        if col.key ~= "action" and onSort then
            btn:SetScript("OnClick", function() onSort(col.key) end)
            btn:SetScript("OnEnter", function() bg:SetColorTexture(0.2, 0.2, 0.3, 0.7) end)
            btn:SetScript("OnLeave", function() bg:SetColorTexture(0.1, 0.1, 0.15, 0.6) end)
        end
        x = x + col.width
    end
    return header
end

-- ----------------------------------------------------------------------------
-- Logs panel rows
-- ----------------------------------------------------------------------------
local function acquireLogsRow(parent, index)
    local row = logsRowPool[index]
    if row then return row end

    row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_W - 40, ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    local x = 0
    row.cells = {}
    for _, col in ipairs(LOGS_COLS) do
        if col.key == "action" then
            local container = CreateFrame("Frame", nil, row)
            container:SetSize(col.width - 4, ROW_H)
            container:SetPoint("LEFT", x + 2, 0)

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

    logsRowPool[index] = row
    return row
end

-- ----------------------------------------------------------------------------
-- People panel rows
-- ----------------------------------------------------------------------------
local function acquirePeopleRow(parent, index)
    local row = peopleRowPool[index]
    if row then return row end

    row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_W - 40, ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    local x = 0
    row.cells = {}
    for _, col in ipairs(PEOPLE_COLS) do
        if col.key == "action" then
            local container = CreateFrame("Frame", nil, row)
            container:SetSize(col.width - 4, ROW_H)
            container:SetPoint("LEFT", x + 2, 0)

            local btnW = math.floor((col.width - 12) / 2)
            local mailBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
            mailBtn:SetSize(btnW, ROW_H - 4)
            mailBtn:SetPoint("LEFT", 2, 0)
            mailBtn:SetText(GCL.L.UI_BTN_MAIL_ALL or "Mail All")
            row.mailBtn = mailBtn

            local creditBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
            creditBtn:SetSize(btnW, ROW_H - 4)
            creditBtn:SetPoint("LEFT", mailBtn, "RIGHT", 4, 0)
            creditBtn:SetText(GCL.L.UI_BTN_CREDIT_ALL or "Credit All")
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

    peopleRowPool[index] = row
    return row
end

local function emptyLabel(parent)
    if parent.emptyFS then return parent.emptyFS end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    fs:SetPoint("CENTER", parent, "CENTER", 0, 0)
    parent.emptyFS = fs
    return fs
end

-- ----------------------------------------------------------------------------
-- Tab bar
-- ----------------------------------------------------------------------------
local function styleTabBtn(btn, isActive)
    if not btn or not btn.bg then return end
    if isActive then
        btn.bg:SetColorTexture(0.2, 0.4, 0.7, 0.9)
    else
        btn.bg:SetColorTexture(0.15, 0.15, 0.2, 0.8)
    end
end

local function buildTabButton(parent, label, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(120, 24)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("CENTER")
    fs:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- ----------------------------------------------------------------------------
-- Tab switching
-- ----------------------------------------------------------------------------
function MainFrame:SwitchTab(name)
    if name ~= TAB_LOGS and name ~= TAB_PEOPLE then return end
    activeTab = name
    if logsPanel and logsPanel.SetShown then logsPanel:SetShown(name == TAB_LOGS) end
    if peoplePanel and peoplePanel.SetShown then peoplePanel:SetShown(name == TAB_PEOPLE) end
    styleTabBtn(logsTabBtn,  name == TAB_LOGS)
    styleTabBtn(peopleTabBtn, name == TAB_PEOPLE)
    self:Refresh()
end

function MainFrame:GetActiveTab() return activeTab end

-- ----------------------------------------------------------------------------
-- Build
-- ----------------------------------------------------------------------------
local function buildLogsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", 16, -68)
    panel:SetPoint("BOTTOMRIGHT", -16, 36)

    buildHeader(panel, LOGS_COLS, function(key)
        if logsSortKey == key then
            logsSortAsc = not logsSortAsc
        else
            logsSortKey = key
            logsSortAsc = (key == "provider" or key == "recipe")
        end
        MainFrame:Refresh()
    end)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -ROW_H - 4)
    scroll:SetPoint("BOTTOMRIGHT", -20, 0)

    logsScrollChild = CreateFrame("Frame", nil, scroll)
    logsScrollChild:SetSize(FRAME_W - 60, ROW_H * VISIBLE_ROWS)
    scroll:SetScrollChild(logsScrollChild)

    return panel
end

local function buildPeoplePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", 16, -68)
    panel:SetPoint("BOTTOMRIGHT", -16, 36)

    buildHeader(panel, PEOPLE_COLS, function(key)
        if peopleSortKey == key then
            peopleSortAsc = not peopleSortAsc
        else
            peopleSortKey = key
            peopleSortAsc = (key == "provider")
        end
        MainFrame:Refresh()
    end)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -ROW_H - 4)
    scroll:SetPoint("BOTTOMRIGHT", -20, 0)

    peopleScrollChild = CreateFrame("Frame", nil, scroll)
    peopleScrollChild:SetSize(FRAME_W - 60, ROW_H * VISIBLE_ROWS)
    scroll:SetScrollChild(peopleScrollChild)

    return panel
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

    -- Tab bar
    logsTabBtn = buildTabButton(frame,
        GCL.L.UI_TAB_LOGS or "Logs",
        function() MainFrame:SwitchTab(TAB_LOGS) end)
    logsTabBtn:SetPoint("TOPLEFT", 16, -32)

    peopleTabBtn = buildTabButton(frame,
        GCL.L.UI_TAB_PEOPLE or "By Person",
        function() MainFrame:SwitchTab(TAB_PEOPLE) end)
    peopleTabBtn:SetPoint("LEFT", logsTabBtn, "RIGHT", 6, 0)

    -- Footer chrome
    local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refresh:SetSize(80, 22)
    refresh:SetPoint("BOTTOMRIGHT", -16, 12)
    refresh:SetText(GCL.L.UI_BTN_REFRESH)
    refresh:SetScript("OnClick", function() MainFrame:Refresh() end)

    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 22)
    exportBtn:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
    exportBtn:SetText(GCL.L.UI_BTN_EXPORT or "Export")
    exportBtn:SetScript("OnClick", function()
        if GCL.ReportExporter and GCL.ReportExporter.Show then
            GCL.ReportExporter:Show(nil, "text")
        end
    end)

    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.footer:SetPoint("BOTTOMLEFT", 16, 16)

    -- Tab content panels
    logsPanel = buildLogsPanel(frame)
    peoplePanel = buildPeoplePanel(frame)

    self:SwitchTab(activeTab)
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

-- ----------------------------------------------------------------------------
-- Refresh — dispatches to the active panel
-- ----------------------------------------------------------------------------
local function refreshLogs()
    if not logsScrollChild or not GCL.LedgerStore then return 0 end

    local entries = {}
    for _, e in ipairs(GCL.LedgerStore:All()) do
        table.insert(entries, e)
    end
    table.sort(entries, logsComparator)

    local empty = emptyLabel(logsScrollChild)
    if #entries == 0 then
        empty:SetText(GCL.L.UI_EMPTY)
        empty:Show()
    else
        empty:Hide()
    end

    logsScrollChild:SetHeight(math.max(ROW_H * VISIBLE_ROWS, ROW_H * #entries))
    for _, r in ipairs(logsRowPool) do r:Hide() end

    for i, e in ipairs(entries) do
        local row = acquireLogsRow(logsScrollChild, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
        row:SetWidth(logsScrollChild:GetWidth())

        if i % 2 == 0 then
            row.bg:SetColorTexture(0.05, 0.05, 0.08, 0.5)
        else
            row.bg:SetColorTexture(0.0, 0.0, 0.0, 0.3)
        end

        row.cells.date:SetText(date("%Y-%m-%d %H:%M", e.timestamp or 0))
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

        row.cells.cost:SetText(copperToString(e.matsCost or 0))
        row.cells.status:SetText(statusLabel(e.paymentStatus))

        local entryID = e.id
        if e.paymentStatus == "unpaid" then
            row.mailBtn:Show(); row.mailBtn:Enable()
            row.mailBtn:SetScript("OnClick", function()
                if GCL.MailPayer and GCL.MailPayer.Pay then
                    GCL.MailPayer:Pay(entryID)
                end
            end)
            row.creditBtn:Show(); row.creditBtn:Enable()
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

    return #entries
end

local function refreshPeople()
    if not peopleScrollChild then return 0 end

    local rows = MainFrame:AggregateByProvider()
    table.sort(rows, peopleComparator)

    local empty = emptyLabel(peopleScrollChild)
    if #rows == 0 then
        empty:SetText(GCL.L.UI_PEOPLE_EMPTY or GCL.L.UI_EMPTY)
        empty:Show()
    else
        empty:Hide()
    end

    peopleScrollChild:SetHeight(math.max(ROW_H * VISIBLE_ROWS, ROW_H * #rows))
    for _, r in ipairs(peopleRowPool) do r:Hide() end

    for i, p in ipairs(rows) do
        local row = acquirePeopleRow(peopleScrollChild, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
        row:SetWidth(peopleScrollChild:GetWidth())

        if i % 2 == 0 then
            row.bg:SetColorTexture(0.05, 0.05, 0.08, 0.5)
        else
            row.bg:SetColorTexture(0.0, 0.0, 0.0, 0.3)
        end

        row.cells.provider:SetText(p.providerName)
        row.cells.count:SetText(tostring(p.count))
        row.cells.owed:SetText(copperToString(p.owed))
        row.cells.paid:SetText(copperToString(p.paid))

        local providerName = p.providerName
        local hasValidRecipient = providerName ~= "?" and providerName ~= ""
        if p.unpaidCount > 0 then
            -- Credit All works as accounting cleanup even for orphaned rows;
            -- Mail All needs a real recipient WoW can deliver to.
            if hasValidRecipient then
                row.mailBtn:Show(); row.mailBtn:Enable()
                row.mailBtn:SetScript("OnClick", function()
                    if GCL.MailPayer and GCL.MailPayer.PayAll then
                        GCL.MailPayer:PayAll(providerName)
                    end
                end)
            else
                row.mailBtn:Hide()
            end
            row.creditBtn:Show(); row.creditBtn:Enable()
            row.creditBtn:SetScript("OnClick", function()
                if GCL.BankCredit and GCL.BankCredit.SettleAll then
                    local count, total = GCL.BankCredit:SettleAll(providerName)
                    if count == 0 then
                        GCL:Print(GCL.L.LOG_CREDITED_NONE
                            or "No unpaid entries found for '%s'.", providerName)
                    else
                        GCL:Print(GCL.L.LOG_CREDITED_BULK
                            or "Credited %d entries totaling %s.",
                            count, copperToString(total))
                    end
                end
            end)
        else
            row.mailBtn:Hide()
            row.creditBtn:Hide()
        end

        row:Show()
    end

    return #rows
end

local function totalOwed(entries)
    local sum = 0
    for _, e in ipairs(entries) do
        if e.paymentStatus == "unpaid" then
            sum = sum + (e.matsCost or 0)
        end
    end
    return sum
end

function MainFrame:Refresh()
    if not frame then return end
    if not GCL.LedgerStore then return end

    if activeTab == TAB_LOGS then
        local n = refreshLogs() or 0
        local owed = totalOwed(GCL.LedgerStore:All())
        frame.footer:SetText(string.format("%d entries — %s outstanding",
            n, copperToString(owed)))
    else
        local n = refreshPeople() or 0
        local owed = totalOwed(GCL.LedgerStore:All())
        frame.footer:SetText(string.format("%d providers — %s outstanding",
            n, copperToString(owed)))
    end
end
