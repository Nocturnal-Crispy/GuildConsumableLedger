local _, GCL = ...

local Comms = GCL:NewModule("Comms")

Comms.PREFIX = "GCL_v1"
Comms.WITNESS_DEDUP_SECONDS = 12

-- Pipe-delimited wire format. Fields are URL-encoded so pipes inside payloads
-- never collide with the delimiter. The format is intentionally simple to
-- avoid a hard dependency on AceSerializer / LibCompress.
local function urlEncode(s)
    s = tostring(s == nil and "" or s)
    return (s:gsub("[^A-Za-z0-9%-_.~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function urlDecode(s)
    s = tostring(s == nil and "" or s)
    return (s:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

function Comms:Serialize(messageType, fields)
    fields = fields or {}
    local parts = { urlEncode(messageType) }
    for _, v in ipairs(fields) do
        table.insert(parts, urlEncode(v))
    end
    return table.concat(parts, "|")
end

function Comms:Deserialize(payload)
    if type(payload) ~= "string" or payload == "" then return nil end
    local parts = {}
    -- Split on '|' without losing empty fields (so nil-as-empty roundtrips).
    local i, j = 1, payload:find("|", 1, true)
    while j do
        table.insert(parts, payload:sub(i, j - 1))
        i = j + 1
        j = payload:find("|", i, true)
    end
    table.insert(parts, payload:sub(i))
    local messageType = urlDecode(parts[1])
    local fields = {}
    for k = 2, #parts do
        fields[k - 1] = urlDecode(parts[k])
    end
    return messageType, fields
end

-- Witness dedup table keyed by sourceGUID:spellID:bucket where bucket is
-- floor(timestamp / WITNESS_DEDUP_SECONDS). The bucket prevents legitimately
-- repeated drops (e.g. tempest cauldron every 10 minutes) from being suppressed
-- forever while still folding all witnesses of the same drop into one entry.
local witnessSeen = {}
local witnessInsertCount = 0
local WITNESS_GC_INTERVAL = 32  -- run prune every N successful inserts

local function witnessKey(sourceGUID, spellID, ts)
    local bucket = math.floor((ts or 0) / Comms.WITNESS_DEDUP_SECONDS)
    return string.format("%s:%s:%d", tostring(sourceGUID or "?"),
        tostring(spellID or "?"), bucket)
end

-- Returns true the first time a (source, spell, bucket) is seen; false on
-- subsequent witnesses inside the same bucket. The `now` argument is for tests.
function Comms:ShouldRecordCast(sourceGUID, spellID, now)
    now = now or time()
    local key = witnessKey(sourceGUID, spellID, now)
    if witnessSeen[key] then return false end
    witnessSeen[key] = now
    witnessInsertCount = witnessInsertCount + 1
    -- Throttled GC: prune entries older than 4 buckets only every Nth insert
    -- so we don't iterate the table on every combat-log event during raids.
    if witnessInsertCount >= WITNESS_GC_INTERVAL then
        witnessInsertCount = 0
        local cutoff = now - (4 * Comms.WITNESS_DEDUP_SECONDS)
        for k, v in pairs(witnessSeen) do
            if v < cutoff then witnessSeen[k] = nil end
        end
    end
    return true
end

function Comms:ResetWitnessTable()
    witnessSeen = {}
    witnessInsertCount = 0
end

-- Wire send. Falls back to no-op outside the game. Channel is "GUILD" by
-- default; raid/party can be requested explicitly when needed.
function Comms:Send(messageType, fields, channel)
    channel = channel or "GUILD"
    local payload = self:Serialize(messageType, fields)
    if not _G.C_ChatInfo or not _G.C_ChatInfo.SendAddonMessage then return false end
    if not _G.IsInGuild or not _G.IsInGuild() then
        if channel == "GUILD" then return false end
    end
    local ok = _G.C_ChatInfo.SendAddonMessage(self.PREFIX, payload, channel)
    return ok ~= false
end

-- Dispatch table: messageType -> handler(sender, fields)
local handlers = {}

function Comms:On(messageType, handler)
    handlers[messageType] = handler
end

local function dispatch(_, prefix, payload, _channel, sender)
    if prefix ~= Comms.PREFIX then return end
    local messageType, fields = Comms:Deserialize(payload)
    if not messageType then return end
    local h = handlers[messageType]
    if h then
        local ok, err = pcall(h, sender, fields)
        if not ok then
            GCL:Print("|cFFFF6060comms handler error (%s): %s|r",
                tostring(messageType), tostring(err))
        end
    end
end

function Comms:Init()
    if _G.C_ChatInfo and _G.C_ChatInfo.RegisterAddonMessagePrefix then
        _G.C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    end
end

if GCL.EventBus then
    GCL.EventBus:On("CHAT_MSG_ADDON", dispatch)
    GCL.EventBus:On("PLAYER_LOGIN", function() Comms:Init() end)
end
