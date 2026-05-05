local _, GCL = ...

local HandoutTracker = GCL:NewModule("HandoutTracker")

-- Items that, when handed out via mail or trade, qualify as a tracked
-- consumable. Built from RecipeMap so we don't maintain a parallel list.
function HandoutTracker:BuildTrackedItemSet()
    local set = {}
    if not GCL.RecipeMap or not GCL.RecipeMap.recipes then return set end
    for name, recipe in pairs(GCL.RecipeMap.recipes) do
        if recipe.itemID then
            set[recipe.itemID] = { recipe = name, category = recipe.category }
        end
    end
    return set
end

-- Pure resolver: given an item link string and the tracked-item set, returns
-- the matching {recipe, category} entry or nil. Extracted for unit tests.
function HandoutTracker:ResolveItemLink(itemLink, trackedSet)
    if type(itemLink) ~= "string" or not trackedSet then return nil end
    local idStr = itemLink:match("item:(%d+)")
    if not idStr then return nil end
    local itemID = tonumber(idStr)
    return itemID and trackedSet[itemID] or nil
end

-- Aggregate trade items. Helper for tests; production calls collect items
-- from GetTradePlayerItem / GetTradeTargetItem WoW APIs.
function HandoutTracker:CollectTrackedFromList(itemLinks, trackedSet)
    local matches = {}
    for _, link in ipairs(itemLinks or {}) do
        local hit = self:ResolveItemLink(link, trackedSet)
        if hit then table.insert(matches, hit) end
    end
    return matches
end

local function isHandoutEnabled()
    local profile = GCL:GetProfile()
    return profile and profile.handoutTrackingEnabled == true
end

local function isGuildMember(name)
    if not name or name == "" then return false end
    if not _G.GetNumGuildMembers then return false end
    local n = _G.GetNumGuildMembers()
    for i = 1, n do
        local memberName = _G.GetGuildRosterInfo(i)
        if memberName and (memberName == name or memberName:match("^([^-]+)") == name) then
            return true
        end
    end
    return false
end

local function recordHandout(opts)
    if not GCL.LedgerStore then return end
    local cost, snapshot = GCL.CostCalculator:Resolve(opts.recipeName)
    GCL.LedgerStore:Record({
        providerGUID = opts.providerGUID or _G.UnitGUID and _G.UnitGUID("player"),
        providerName = opts.providerName or _G.UnitName and _G.UnitName("player"),
        category = opts.category,
        spellID = 0,
        recipeName = opts.recipeName,
        matsCost = cost,
        pricingSnapshot = snapshot,
        raidContext = opts.raidContext,
        source = opts.source,
        recipient = opts.recipient,
    })
end

-- ---------------------------------------------------------------------------
-- Mail hook: SendMail(recipient, subject, body)
-- We snapshot the attached items at the moment of send. Mail attachments use
-- SendMailItemX slots; the C_Item / GetSendMailItemLink API returns the link.
-- ---------------------------------------------------------------------------
local function getMailAttachmentLinks()
    local links = {}
    if not _G.GetSendMailItemLink then return links end
    local maxAttachments = _G.ATTACHMENTS_MAX_SEND or 12
    for i = 1, maxAttachments do
        local link = _G.GetSendMailItemLink(i)
        if link then table.insert(links, link) end
    end
    return links
end

function HandoutTracker:OnSendMail(recipient)
    if not isHandoutEnabled() then return end
    if not recipient or recipient == "" then return end
    if not isGuildMember(recipient) then return end
    local trackedSet = self:BuildTrackedItemSet()
    local matches = self:CollectTrackedFromList(getMailAttachmentLinks(), trackedSet)
    for _, hit in ipairs(matches) do
        recordHandout({
            recipeName = hit.recipe,
            category = hit.category,
            recipient = recipient,
            source = "mail",
        })
    end
end

-- ---------------------------------------------------------------------------
-- Trade hook: capture player-given items at TRADE_CLOSED if the trade was
-- successful. Trade success is signaled by TRADE_REQUEST_CANCEL absence and
-- final TRADE_CLOSED firing without a prior cancel.
-- ---------------------------------------------------------------------------
local pendingTrade

function HandoutTracker:OnTradeAcceptUpdate(playerAccepted, targetAccepted)
    if not isHandoutEnabled() then return end
    if playerAccepted ~= 1 or targetAccepted ~= 1 then
        pendingTrade = nil
        return
    end
    local links = {}
    if _G.GetTradePlayerItemLink then
        for i = 1, 7 do
            local link = _G.GetTradePlayerItemLink(i)
            if link then table.insert(links, link) end
        end
    end
    -- WoW unit tokens are lowercase. The trade window exposes the partner as
    -- "npc" while open; "NPC" silently returns nil and would discard every
    -- captured trade.
    local target = _G.UnitName and _G.UnitName("npc") or nil
    pendingTrade = { target = target, links = links }
end

function HandoutTracker:OnTradeRequestCancel()
    pendingTrade = nil
end

function HandoutTracker:OnTradeClosed()
    local trade = pendingTrade
    pendingTrade = nil
    if not trade or not trade.target then return end
    if not isGuildMember(trade.target) then return end
    local trackedSet = self:BuildTrackedItemSet()
    local matches = self:CollectTrackedFromList(trade.links, trackedSet)
    for _, hit in ipairs(matches) do
        recordHandout({
            recipeName = hit.recipe,
            category = hit.category,
            recipient = trade.target,
            source = "trade",
        })
    end
end

-- hooksecurefunc on a Blizzard global must wait until that global exists.
-- SendMail is defined by FrameXML, available before PLAYER_LOGIN, but hooking
-- inside an event handler triggers no taint here because the hook is a
-- read-only callback. We still gate on the API being present.
if _G.hooksecurefunc and _G.SendMail then
    _G.hooksecurefunc("SendMail", function(recipient)
        HandoutTracker:OnSendMail(recipient)
    end)
end

if GCL.EventBus then
    GCL.EventBus:On("TRADE_ACCEPT_UPDATE", function(_, p, t)
        HandoutTracker:OnTradeAcceptUpdate(p, t)
    end)
    GCL.EventBus:On("TRADE_REQUEST_CANCEL", function()
        HandoutTracker:OnTradeRequestCancel()
    end)
    GCL.EventBus:On("TRADE_CLOSED", function()
        HandoutTracker:OnTradeClosed()
    end)
end
