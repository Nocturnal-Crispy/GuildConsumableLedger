local _, GCL = ...

local MailPayer = GCL:NewModule("MailPayer")

-- Pending pay request awaiting MAIL_SHOW. WoW requires the mailbox interface
-- to be open before SetSendMailMoney / SendMail succeed. Officers who click
-- "Mail" while not at a mailbox get a polite reminder and the request queues
-- so the next time they open a mailbox the prefilled form appears.
local pendingByEntry = nil
local awaitingSendForEntry = nil

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

local function buildSubject(entry)
    return string.format("%s: %s",
        GCL.L.MAIL_SUBJECT_PREFIX or "Consumable reimbursement",
        entry.recipeName or "?")
end

local function buildBody(entry)
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

local function prefillMailForm(entry)
    if not entry then return false end
    local recipient = entry.providerName
    if not recipient or recipient == "" then return false end

    if _G.MailFrameTab_OnClick and _G.MailFrame then
        -- Switch to Send tab if the API is exposed (not in all client builds).
        local sendTab = _G.MailFrameTab2
        if sendTab and sendTab.GetID then
            pcall(_G.MailFrameTab_OnClick, sendTab)
        end
    end

    if _G.SendMailNameEditBox and _G.SendMailNameEditBox.SetText then
        _G.SendMailNameEditBox:SetText(recipient)
    end
    if _G.SendMailSubjectEditBox and _G.SendMailSubjectEditBox.SetText then
        _G.SendMailSubjectEditBox:SetText(buildSubject(entry))
    end
    if _G.SendMailBodyEditBox and _G.SendMailBodyEditBox.SetText then
        _G.SendMailBodyEditBox:SetText(buildBody(entry))
    end
    if _G.SetSendMailMoney then
        local raw = math.floor(entry.matsCost or 0)
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
    return true
end

-- Public: officer clicked "Mail Gold" on a ledger row. If at a mailbox the
-- form fills immediately; otherwise we queue and prefill when MAIL_SHOW fires.
function MailPayer:Pay(entryID)
    if not GCL.LedgerStore then return false end
    local entry = GCL.LedgerStore:GetByID(entryID)
    if not entry then return false end
    if entry.paymentStatus ~= "unpaid" then
        GCL:Print(GCL.L.MAIL_ALREADY_PAID or "Entry already settled.")
        return false
    end

    if isAtMailbox() then
        if prefillMailForm(entry) then
            awaitingSendForEntry = entry.id
            GCL:Print(GCL.L.MAIL_PREFILLED or "Mail prefilled — review then click Send.")
            return true
        end
        return false
    end

    if pendingByEntry and pendingByEntry ~= entry.id then
        GCL:Print(GCL.L.MAIL_PENDING_REPLACED
            or "Replacing earlier pending mail (only one queue slot).")
    end
    pendingByEntry = entry.id
    GCL:Print(GCL.L.MAIL_QUEUED or "Visit a mailbox to send the prefilled mail.")
    return true
end

function MailPayer:HasPending()
    return pendingByEntry ~= nil
end

function MailPayer:CancelPending()
    pendingByEntry = nil
    awaitingSendForEntry = nil
end

local function onMailShow()
    if not pendingByEntry then return end
    if not GCL.LedgerStore then return end
    local entry = GCL.LedgerStore:GetByID(pendingByEntry)
    pendingByEntry = nil
    if entry and entry.paymentStatus == "unpaid" and prefillMailForm(entry) then
        awaitingSendForEntry = entry.id
        GCL:Print(GCL.L.MAIL_PREFILLED or "Mail prefilled — review then click Send.")
    end
end

local function onMailSendSuccess()
    local id = awaitingSendForEntry
    awaitingSendForEntry = nil
    if not id or not GCL.LedgerStore then return end
    local entry = GCL.LedgerStore:GetByID(id)
    if not entry or entry.paymentStatus ~= "unpaid" then return end
    GCL.LedgerStore:MarkPaid(id, "mailed", entry.matsCost)
end

function MailPayer:Init()
    if not GCL.EventBus then return end
    GCL.EventBus:On("MAIL_SHOW", onMailShow)
    GCL.EventBus:On("MAIL_SEND_SUCCESS", onMailSendSuccess)
end

if GCL.EventBus then
    GCL.EventBus:On("PLAYER_LOGIN", function() MailPayer:Init() end)
end
