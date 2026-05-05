local _, GCL = ...

local MemberPanel = GCL:NewModule("MemberPanel")

-- Pure aggregation: returns {entries, totals} for a given player name. The
-- player name is matched case-insensitively against entry.providerName so a
-- character without a realm suffix still finds itself.
function MemberPanel:Aggregate(playerName)
    local result = { entries = {}, total = 0, unpaid = 0, paid = 0, count = 0 }
    if not playerName or playerName == "" then return result end
    if not GCL.LedgerStore then return result end

    local target = playerName:lower()
    for _, e in ipairs(GCL.LedgerStore:All()) do
        local who = (e.providerName or ""):lower()
        local short = who:match("^([^-]+)") or who
        if who == target or short == target then
            table.insert(result.entries, e)
            result.count = result.count + 1
            result.total = result.total + (e.matsCost or 0)
            if e.paymentStatus == "unpaid" then
                result.unpaid = result.unpaid + (e.matsCost or 0)
            else
                result.paid = result.paid + (e.paidAmount or e.matsCost or 0)
            end
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Lazy-built read-only window. Member-facing: no Pay/Credit buttons.
-- ---------------------------------------------------------------------------
local frame
local rowFrames = {}

local function getPlayerName()
    if _G.UnitName then
        local name = _G.UnitName("player")
        if name then return name end
    end
    return "?"
end

local function buildRow(parent, idx)
    local r = rowFrames[idx]
    if r then return r end
    r = CreateFrame("Frame", nil, parent)
    r:SetSize(540, 20)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.date = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.date:SetPoint("LEFT", 4, 0)
    r.date:SetWidth(120)
    r.date:SetJustifyH("LEFT")
    r.recipe = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.recipe:SetPoint("LEFT", r.date, "RIGHT", 4, 0)
    r.recipe:SetWidth(220)
    r.recipe:SetJustifyH("LEFT")
    r.cost = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.cost:SetPoint("LEFT", r.recipe, "RIGHT", 4, 0)
    r.cost:SetWidth(100)
    r.cost:SetJustifyH("RIGHT")
    r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.status:SetPoint("LEFT", r.cost, "RIGHT", 4, 0)
    r.status:SetWidth(80)
    r.status:SetJustifyH("LEFT")
    rowFrames[idx] = r
    return r
end

local function buildFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "GuildConsumableLedgerMemberFrame",
        UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(600, 360)
    frame:SetPoint("CENTER", 80, -40)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText(GCL.L.UI_MEMBER_TITLE or "My Contributions")

    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.summary:SetPoint("TOPLEFT", 16, -32)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -56)
    scroll:SetPoint("BOTTOMRIGHT", -36, 16)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(560, 20 * 14)
    scroll:SetScrollChild(child)
    frame.scrollChild = child
    return frame
end

function MemberPanel:Refresh()
    if not frame then return end
    local agg = self:Aggregate(getPlayerName())
    local cps = GCL.LedgerStore and GCL.LedgerStore.CopperToString or tostring

    frame.summary:SetText(string.format("%d contributions   total %s   unpaid %s",
        agg.count, cps(agg.total), cps(agg.unpaid)))

    for _, r in ipairs(rowFrames) do r:Hide() end
    table.sort(agg.entries, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    for i, e in ipairs(agg.entries) do
        local r = buildRow(frame.scrollChild, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -((i - 1) * 20))
        r.bg:SetColorTexture(0.0, 0.0, 0.0, (i % 2 == 0) and 0.4 or 0.2)
        r.date:SetText(date("%Y-%m-%d %H:%M", e.timestamp or 0))
        r.recipe:SetText(e.recipeName or "?")
        r.cost:SetText(cps(e.matsCost or 0))
        r.status:SetText(e.paymentStatus or "?")
        r:Show()
    end
end

function MemberPanel:Show()
    buildFrame()
    self:Refresh()
    frame:Show()
end

function MemberPanel:Hide()
    if frame then frame:Hide() end
end

function MemberPanel:Toggle()
    buildFrame()
    if frame:IsShown() then frame:Hide() else self:Show() end
end
