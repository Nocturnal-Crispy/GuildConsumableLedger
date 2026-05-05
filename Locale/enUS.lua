local _, GCL = ...

GCL.L = {
    ADDON_NAME = "Guild Consumable Ledger",
    SHORT_NAME = "GCL",

    SLASH_HELP = "|cFFFFFF00/gcl|r commands:",
    SLASH_SHOW = "  show           - open the ledger window",
    SLASH_HIDE = "  hide           - close the ledger window",
    SLASH_TOGGLE = "  toggle         - toggle the ledger window",
    SLASH_PRINT = "  print          - dump recent entries to chat",
    SLASH_RESET = "  reset          - wipe this realm's ledger (confirm required)",
    SLASH_VERSION = "  version        - print addon version",

    LOG_LOADED = "loaded. Type /gcl for help.",
    LOG_AUCTIONATOR_OK = "Auctionator detected — pricing live.",
    LOG_AUCTIONATOR_MISSING = "Auctionator not found — using manual prices only.",
    LOG_RECORDED = "Recorded %s by %s for %s.",
    LOG_PRICE_STALE = "Auctionator data older than 24h — entry flagged stale.",
    LOG_PRICE_MISSING = "No price for itemID %d — set a manual price via /gcl.",
    LOG_PAID = "Marked entry %s as paid.",
    LOG_RESET_PENDING = "Type /gcl reset confirm to wipe this realm's ledger.",
    LOG_RESET_DONE = "Ledger wiped for this realm.",

    UI_TITLE = "Guild Consumable Ledger",
    UI_COL_DATE = "Date",
    UI_COL_PROVIDER = "Provider",
    UI_COL_RECIPE = "Recipe",
    UI_COL_COST = "Cost",
    UI_COL_STATUS = "Status",
    UI_COL_ACTION = "Action",

    UI_STATUS_UNPAID = "Unpaid",
    UI_STATUS_MAILED = "Mailed",
    UI_STATUS_CREDITED = "Credited",
    UI_STATUS_REPORTED = "Reported",

    UI_BTN_MARK_PAID = "Mark Paid",
    UI_BTN_REFRESH = "Refresh",
    UI_BTN_CLOSE = "Close",

    UI_EMPTY = "No consumable drops recorded yet.",
    UI_STALE_TAG = "|cFFFFAA00stale|r",
    UI_NOPRICE_TAG = "|cFFFF6060no price|r",
}
