local _, GCL = ...

local MailPayer = GCL:NewModule("MailPayer")

-- Pending pay request awaiting MAIL_SHOW. WoW requires the mailbox interface
-- to be open before SetSendMailMoney / SendMail succeed. Officers who click
-- "Mail" while not at a mailbox get a polite reminder and the request queues
-- so the next time they open a mailbox the prefilled form appears.
--
-- A request is one of:
--   { kind = "single", entryID = "..." }
--   { kind = "multi",  providerName = "...", entryIDs = {...} }
local pending = nil
local awaitingSend = nil  -- same shape; set once the form is prefilled

-- Hard ceiling on auto-prefilled mail money. WoW's per-mail money cap is
-- ~999,999g (depending on patch); we keep our ceiling well below that so a
-- runaway multiplier or a corrupted manual price never prefills a surprise.
-- 100,000g = 1,000,000,000 copper.
MailPayer.MAIL_MONEY_CEILING = 100 * 1000 * 10000

local function isAtMailbox()
    -- MailFrame opens MAIL_SHOW; presence of MailFrame:IsShown() is the only
    -- reliable signal across patches.
    return _G.MailFrame and _G.MailFrame.IsShown and _G.MailFrame:IsShown()
end

local function copperToMoneyString(copper)
    if not copper or copper <= 0 then return "0c" end
    if GCL.LedgerStore and GCL.LedgerStore.CopperToString then
        return GCL.LedgerStore.CopperToString(copper)
    end
    return tostring(copper) .. "c"
end

local function buildSingleSubject(entry)
    return string.format("%s: %s",
        GCL.L.MAIL_SUBJECT_PREFIX or "Consumable reimbursement",
        entry.recipeName or "?")
end

local function buildSingleBody(entry)
    local lines = {
        string.format("Recipe: %s", entry.recipeName or "?"),
        string.format("Date: %s", date("%Y-%m-%d %H:%M", entry.timestamp or time())),
        string.format("Reimbursement: %s", copperToMoneyString(entry.matsCost or 0)),
    }
    if entry.raidContext and entry.raidContext.instance then
        table.insert(lines, string.format("Raid: %s", entry.raidContext.instance))
    end
    return table.concat(lines, "\n")
end

local function setMailMoney(copper)
    if not _G.SetSendMailMoney then return end
    local raw = math.floor(copper or 0)
    if raw > MailPayer.MAIL_MONEY_CEILING then
        GCL:Print((GCL.L.MAIL_MONEY_CAPPED
            or "Cost %s exceeds the prefill ceiling — left mail money empty for officer to set."),
            (GCL.LedgerStore and GCL.LedgerStore.CopperToString
                and GCL.LedgerStore.CopperToString(raw)) or tostring(raw))
        _G.SetSendMailMoney(0)
    else
        _G.SetSendMailMoney(raw)
    end
end

local function selectSendTab()
    if _G.MailFrameTab_OnClick and _G.MailFrame then
        local sendTab = _G.MailFrameTab2
        if sendTab and sendTab.GetID then
            pcall(_G.MailFrameTab_OnClick, sendTab)
        end
    end
end

local function setMailField(boxName, value)
    local box = _G[boxName]
    if box and box.SetText then box:SetText(value or "") end
end

local function prefillSingle(entry)
    if not entry then return false end
    local recipient = entry.providerName
    if not recipient or recipient == "" then return false end
    selectSendTab()
    setMailField("SendMailNameEditBox", recipient)
    setMailField("SendMailSubjectEditBox", buildSingleSubject(entry))
    setMailField("SendMailBodyEditBox", buildSingleBody(entry))
    setMailMoney(entry.matsCost or 0)
    return true
end

-- Pure helper exposed for tests: gather every unpaid ledger entry whose
-- providerName matches `providerName`, returning the aggregated mail draft.
function MailPayer:CollectUnpaidFor(providerName)
    local result = {
        providerName = providerName,
        total = 0,
        count = 0,
        entryIDs = {},
        entries = {},
    }
    if not providerName or providerName == "" then return result end
    if not GCL.LedgerStore then return result end
    for _, e in ipairs(GCL.LedgerStore:All()) do
        if e.providerName == providerName and e.paymentStatus == "unpaid" then
            result.count = result.count + 1
            result.total = result.total + (e.matsCost or 0)
            table.insert(result.entryIDs, e.id)
            table.insert(result.entries, e)
        end
    end
    return result
end

-- Pure helper exposed for tests: format the body of an aggregated mail.
function MailPayer:BuildBulkBody(draft)
    local lines = {
        string.format("Reimbursement for %d contribution(s)", draft.count or 0),
        string.format("Total: %s", copperToMoneyString(draft.total or 0)),
        "",
    }
    for _, e in ipairs(draft.entries or {}) do
        table.insert(lines, string.format("- %s | %s | %s",
            date("%Y-%m-%d %H:%M", e.timestamp or time()),
            e.recipeName or "?",
            copperToMoneyString(e.matsCost or 0)))
    end
    return table.concat(lines, "\n")
end

local function buildBulkSubject(draft)
    return string.format(GCL.L.MAIL_SUBJECT_BULK
        or "Consumable reimbursement (%d entries)", draft.count or 0)
end

-- Recipients sourced from AggregateByProvider may be the "?" placeholder when
-- an entry was recorded without a providerName. Refuse to prefill those — WoW
-- will happily send mail to "?" but the gold disappears.
local function isValidRecipient(name)
    return type(name) == "string" and name ~= "" and name ~= "?"
end

-- A bulk total above MAIL_MONEY_CEILING would silently zero the gold field but
-- leave the body listing every entry as if full payment is being made. To
-- avoid the resulting "marked mailed but no gold sent" data-integrity bug we
-- refuse to prefill at all and tell the officer to use Credit All.
function MailPayer:ExceedsCeiling(total)
    return (tonumber(total) or 0) > MailPayer.MAIL_MONEY_CEILING
end

local function prefillBulk(draft)
    if not draft or draft.count == 0 then return false end
    if not isValidRecipient(draft.providerName) then
        GCL:Print(GCL.L.MAIL_BAD_RECIPIENT
            or "Cannot mail aggregated payment without a valid recipient.")
        return false
    end
    if MailPayer:ExceedsCeiling(draft.total) then
        GCL:Print((GCL.L.MAIL_BULK_CEILING_HIT
            or "Aggregated total %s for %s exceeds the per-mail ceiling — use Credit All or settle individually."),
            copperToMoneyString(draft.total or 0),
            draft.providerName)
        return false
    end
    selectSendTab()
    setMailField("SendMailNameEditBox", draft.providerName)
    setMailField("SendMailSubjectEditBox", buildBulkSubject(draft))
    setMailField("SendMailBodyEditBox", MailPayer:BuildBulkBody(draft))
    setMailMoney(draft.total or 0)
    return true
end

local function announceReplacingPending()
    if pending then
        GCL:Print(GCL.L.MAIL_PENDING_REPLACED
            or "Replacing earlier pending mail (only one queue slot).")
    end
end

-- Public: officer clicked "Mail Gold" on a single ledger row.
function MailPayer:Pay(entryID)
    if not GCL.LedgerStore then return false end
    local entry = GCL.LedgerStore:GetByID(entryID)
    if not entry then return false end
    if entry.paymentStatus ~= "unpaid" then
        GCL:Print(GCL.L.MAIL_ALREADY_PAID or "Entry already settled.")
        return false
    end

    if isAtMailbox() then
        if prefillSingle(entry) then
            awaitingSend = { kind = "single", entryID = entry.id }
            GCL:Print(GCL.L.MAIL_PREFILLED or "Mail prefilled — review then click Send.")
            return true
        end
        return false
    end

    announceReplacingPending()
    pending = { kind = "single", entryID = entry.id }
    GCL:Print(GCL.L.MAIL_QUEUED or "Visit a mailbox to send the prefilled mail.")
    return true
end

-- Public: officer clicked "Mail All" on the by-person view. Aggregates every
-- unpaid entry for `providerName` into a single mail with the running total.
function MailPayer:PayAll(providerName)
    if not isValidRecipient(providerName) then return false end
    if not GCL.LedgerStore then return false end

    local draft = self:CollectUnpaidFor(providerName)
    if draft.count == 0 then
        GCL:Print((GCL.L.MAIL_NO_UNPAID or "No unpaid entries for %s."), providerName)
        return false
    end

    -- Discard any earlier prefill that the officer never sent — only one form
    -- can be in-flight at a time, and stale awaitingSend would otherwise mark
    -- the wrong entries as "mailed" on the next MAIL_SEND_SUCCESS.
    awaitingSend = nil

    if isAtMailbox() then
        if prefillBulk(draft) then
            awaitingSend = {
                kind = "multi",
                providerName = providerName,
                entryIDs = draft.entryIDs,
            }
            GCL:Print((GCL.L.MAIL_PREFILLED_BULK
                or "Aggregated mail prefilled for %s — review then click Send."),
                providerName)
            return true
        end
        return false
    end

    announceReplacingPending()
    pending = {
        kind = "multi",
        providerName = providerName,
        entryIDs = draft.entryIDs,
    }
    GCL:Print((GCL.L.MAIL_QUEUED_BULK
        or "Visit a mailbox to send the aggregated mail for %s."),
        providerName)
    return true
end

function MailPayer:HasPending()
    return pending ~= nil
end

function MailPayer:CancelPending()
    pending = nil
    awaitingSend = nil
end

local function onMailShow()
    if not pending then return end
    if not GCL.LedgerStore then return end

    local req = pending
    pending = nil

    if req.kind == "single" then
        local entry = GCL.LedgerStore:GetByID(req.entryID)
        if entry and entry.paymentStatus == "unpaid" and prefillSingle(entry) then
            awaitingSend = { kind = "single", entryID = entry.id }
            GCL:Print(GCL.L.MAIL_PREFILLED or "Mail prefilled — review then click Send.")
        end
    elseif req.kind == "multi" then
        local draft = MailPayer:CollectUnpaidFor(req.providerName)
        if draft.count > 0 and prefillBulk(draft) then
            awaitingSend = {
                kind = "multi",
                providerName = req.providerName,
                entryIDs = draft.entryIDs,
            }
            GCL:Print((GCL.L.MAIL_PREFILLED_BULK
                or "Aggregated mail prefilled for %s — review then click Send."),
                req.providerName)
        end
    end
end

local function onMailSendSuccess()
    local req = awaitingSend
    awaitingSend = nil
    if not req or not GCL.LedgerStore then return end

    -- The unpaid-status guard below handles the (rare) case where another
    -- officer's client credits or mails one of these entries between our
    -- prefill and the eventual MAIL_SEND_SUCCESS. We accept that physical
    -- gold may have been overpaid in that scenario; the ledger stays
    -- consistent because we never double-mark a non-unpaid entry.
    if req.kind == "single" then
        local entry = GCL.LedgerStore:GetByID(req.entryID)
        if not entry or entry.paymentStatus ~= "unpaid" then return end
        GCL.LedgerStore:MarkPaid(req.entryID, "mailed", entry.matsCost)
    elseif req.kind == "multi" then
        for _, id in ipairs(req.entryIDs or {}) do
            local entry = GCL.LedgerStore:GetByID(id)
            if entry and entry.paymentStatus == "unpaid" then
                GCL.LedgerStore:MarkPaid(id, "mailed", entry.matsCost)
            end
        end
    end
end

if GCL.EventBus then
    GCL.EventBus:On("MAIL_SHOW", onMailShow)
    GCL.EventBus:On("MAIL_SEND_SUCCESS", onMailSendSuccess)
end
