local _, GCL = ...

local BankCredit = GCL:NewModule("BankCredit")

-- Mark a single ledger entry as guild-bank-credited. Settlement happens
-- out-of-band (officer transfers from the guild bank, EPGP, etc).
-- Returns true on success, false if the entry is missing or already paid.
function BankCredit:Credit(entryID)
    if not GCL.LedgerStore then return false end
    local entry = GCL.LedgerStore:GetByID(entryID)
    if not entry then return false end
    return GCL.LedgerStore:MarkPaid(entryID, "credited", entry.matsCost)
end

-- Bulk-credit every unpaid entry for a given provider. Useful for end-of-week
-- settlement: officer clears the running balance in one click after a single
-- guild-bank gold transfer covers it.
-- Returns: count of entries credited, total copper credited.
function BankCredit:SettleAll(providerName)
    if not GCL.LedgerStore then return 0, 0 end
    if not providerName or providerName == "" then return 0, 0 end

    local count, total = 0, 0
    -- Snapshot ids first because MarkPaid mutates the underlying entries.
    local toCredit = {}
    for _, e in ipairs(GCL.LedgerStore:All()) do
        if e.providerName == providerName and e.paymentStatus == "unpaid" then
            table.insert(toCredit, { id = e.id, amount = e.matsCost or 0 })
        end
    end
    for _, item in ipairs(toCredit) do
        if GCL.LedgerStore:MarkPaid(item.id, "credited", item.amount) then
            count = count + 1
            total = total + item.amount
        end
    end
    return count, total
end
