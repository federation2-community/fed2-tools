-- Exchange tab: ticker strip + futures market table (delegated to ui_futures.lua).
-- Additional exchange content for other ranks will be added here.
--
-- Ticker: collects exchange spam line-by-line (via ui_exchange_ticker_add), assembles
-- per-commodity entries, and displays the most recent TICKER_SHOW prices at the bottom.

UI = UI or {}

local TICKER_MAX = 30   -- ring-buffer depth

-- ─── market panel visibility (market table is built by ui_futures.lua) ────────

function ui_exchange_market_update_visibility()
    if not UI.exchange_market_scroll then return end
    local at_ex = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")
    local show = at_ex and (f2t_is_rank_exactly("Trader") or f2t_is_rank_exactly("Financier"))
    if show then
        if UI.exchange_market_hdr     then UI.exchange_market_hdr:show()     end
        if UI.exchange_market_col_bar then UI.exchange_market_col_bar:show() end
        UI.exchange_market_scroll:show()
    else
        if UI.exchange_market_hdr     then UI.exchange_market_hdr:hide()     end
        if UI.exchange_market_col_bar then UI.exchange_market_col_bar:hide() end
        UI.exchange_market_scroll:hide()
    end
end

-- ─── ticker ───────────────────────────────────────────────────────────────────

-- Per-commodity emoji icons; keyed by exact commodity name from commodities.json.
local COMMOD_ICONS = {
    -- Agricultural
    Cereals         = "🌾", Fruit           = "🍎", Furs            = "🐾",
    Hides           = "🐃", Livestock       = "🐄", Meats           = "🍖",
    Soya            = "🌱", Spices          = "🌶️", Textiles        = "📜",
    Woods           = "🪵",
    -- Resource
    Alloys          = "🥈", Clays           = "🏺", Crystals        = "💎",
    Gold            = "🏆", Monopoles       = "🔮", Nickel          = "⚪",
    Petrochemicals  = "🛢️",  Radioactives    = "☢️",  Semiconductors  = "💽",
    Xmetals         = "🔩",
    -- Industrial
    Explosives      = "💣", Generators      = "⚡", LanzariK        = "💫",
    LubOils         = "💧", Mechparts       = "⚙️",  Munitions       = "🎯",
    Nitros          = "💨", Pharmaceuticals = "💊", Polymers        = "🔗",
    Propellants     = "🚀", RNA             = "🧬",
    -- Technological
    AntiMatter      = "✨", Controllers     = "🎮", Droids          = "🤖",
    Electros        = "🔌", GAsChips        = "📟", Lasers          = "🔦",
    NanoFabrics     = "🕸️",  Nanos           = "🔬", Powerpacks      = "🔋",
    Synths          = "🎹", Tools           = "🛠️",  TQuarks         = "⚛️",
    Vidicasters     = "📺", Weapons         = "⚔️",
    -- Biological
    BioChips        = "💉", BioComponents   = "🦠", Clinics         = "🏥",
    Laboratories    = "🧪", MicroScalpels   = "🔪", Probes          = "🛸",
    Proteins        = "🍗", Sensors         = "📡", ToxicMunchers   = "☣️",
    Tracers         = "🔍",
    -- Leisure
    Artifacts       = "🏛️",  Firewalls       = "🔥", Games           = "🎲",
    Holos           = "🌀", Hypnotapes      = "📼", Katydidics      = "🦗",
    Libraries       = "📚", Musiks          = "🎵", Sensamps        = "📻",
    Simulations     = "🎭", Studios         = "🎬", Univators       = "🌍",
}

-- Columnar ticker layout (visible chars per row):
--   " [icon] [name:10] [base:≤6]  [buy:BUY_COL_W]  [sell:variable]"
-- Column headers (Buying/Selling) replace the old b:/s: prefixes.
-- Buy column is fixed-width so the Selling column aligns across rows.
-- Sell-only rows omit the buy blank to keep line length short.
-- Delta color: green = favorable for the player:
--   buy  delta ≥ 0 → exchange pays premium  → green
--   sell delta ≤ 0 → exchange charges less  → green

local BUY_COL_W = 12  -- visible chars for the fixed-width buy column

-- BMP code-points that carry a U+FE0F variation selector to force emoji presentation
-- may still render as narrow (1-column) text glyphs in Mudlet's MiniConsole on some
-- builds/fonts. Map them here so _ticker_cecho can add one extra trailing space and
-- keep the icon slot uniformly 2 visual columns wide without changing which icon is used.
-- BMP code-points with U+FE0F variation selector that still render as 1-column text
-- glyphs in Mudlet's MiniConsole on some Qt/font builds. These get an extra trailing
-- space so every icon slot is uniformly 4 visual columns wide.
-- U+1F000+ emoji with Emoji_Presentation:No are fixed by keeping their U+FE0F suffix
-- in COMMOD_ICONS (🌶️ 🛢️ 🕸️ 🛠️ 🏛️) — that forces 2-wide emoji rendering.
-- Icons that render as 1-wide in Mudlet's MiniConsole character grid.
-- Two groups cause this:
--   BMP code-points (U+0000–U+FFFF): Qt measures the base glyph width, ignoring FE0F.
--   U+1F000+ with Emoji_Presentation:No: even with FE0F the base glyph is measured as narrow.
-- All listed icons get an extra trailing space so the icon slot is always 4 visual chars wide.
local NARROW_ICONS = {
    -- BMP + FE0F (base glyph is narrow in Qt's font metrics)
    ["⚙️"] = true,  -- gear        U+2699+FE0F
    ["☢️"] = true,  -- radioactive U+2622+FE0F
    ["⚛️"] = true,  -- atom        U+269B+FE0F
    ["⚔️"] = true,  -- swords      U+2694+FE0F
    ["☣️"] = true,  -- biohazard   U+2623+FE0F
    -- U+1F000+ with Emoji_Presentation:No — FE0F doesn't widen the measured glyph
    ["🌶️"] = true,  -- chili       U+1F336+FE0F
    ["🛢️"] = true,  -- oil drum    U+1F6E2+FE0F
    ["🕸️"] = true,  -- spider web  U+1F578+FE0F
    ["🛠️"] = true,  -- tools       U+1F6E0+FE0F
    ["🏛️"] = true,  -- temple      U+1F3DB+FE0F
}

local function _truncate(s, n)
    if #s <= n then return string.format("%-" .. n .. "s", s) end
    return s:sub(1, n - 1) .. "…"
end

-- Fixed-width buy column (BUY_COL_W visible chars).
-- Padding sits outside the parentheses so there are no internal spaces.
local function _buy_col(price, base)
    local price_s = tostring(price)
    if base then
        local d     = price - base
        local good  = (price >= base)
        local col   = good and "<green>" or "<red>"
        local delta = string.format("(%+d)", d)
        local vis_w = #price_s + 1 + #delta
        local pad   = math.max(0, BUY_COL_W - vis_w)
        return string.format("%s %s%s<reset>%s", price_s, col, delta, string.rep(" ", pad))
    else
        return string.format("%-" .. BUY_COL_W .. "s", price_s)
    end
end

-- Variable-width sell column (last on line — no fixed-width padding needed).
local function _sell_col(price, base)
    local price_s = tostring(price)
    if base then
        local d    = price - base
        local good = (price <= base)
        local col  = good and "<green>" or "<red>"
        return string.format("%s %s(%+d)<reset>", price_s, col, d)
    else
        return price_s
    end
end

-- Appends one ticker entry to the given MiniConsole.
-- Uses cechoLink on the sell price when sell_qty is available so hovering shows
-- the available quantity as a tooltip. Sell-only rows show "---" in the Buying
-- column so the sell price always falls under the "Selling" header.
local function _ticker_append(mc, e)
    local icon       = COMMOD_ICONS[e.name] or "⬛"
    local name_col   = _truncate(e.name or "?", 12)
    local base_raw   = e.base and string.format("(%d)", e.base) or "(?)"
    local base_col   = string.format("%-6s", base_raw)
    -- Slot = 1 leading space + icon + trailing space(s) = always 4 visual chars before name.
    -- Narrow (BMP+FE0F) icons get 2 trailing spaces; wide (U+1F000+) icons get 1.
    local icon_trail = NARROW_ICONS[icon] and "  " or " "
    local prefix     = string.format(" %s%s<white>%s<reset> <gray>%s<reset> ",
        icon, icon_trail, name_col, base_col)

    if not e.buy and not e.sell then
        mc:cecho(prefix .. "---\n")
        return
    end

    local function emit_sell()
        local txt = _sell_col(e.sell, e.base)
        if e.sell_qty then
            -- useCurrentColors=true keeps green/red colouring; setLinkStyleSheet in
            -- ui_exchange_init strips the underline so it looks like regular text.
            mc:cechoLink(txt, "", e.sell_qty .. " for sale", true)
        else
            mc:cecho(txt)
        end
    end

    if e.buy and e.sell then
        mc:cecho(prefix .. _buy_col(e.buy, e.base) .. " ")
        emit_sell()
        mc:cecho("\n")
    elseif e.buy then
        mc:cecho(prefix .. _buy_col(e.buy, e.base) .. "\n")
    else
        -- Sell-only: "---" in Buying column so the sell price falls under "Selling".
        mc:cecho(prefix .. string.format("%-" .. BUY_COL_W .. "s ", "---"))
        emit_sell()
        mc:cecho("\n")
    end
end

-- Apply the exchange_ticker_mode setting to live widgets.
-- Called at init and whenever the setting changes via the side-effect dispatch.
function ui_exchange_apply_ticker_mode()
    local mode        = f2t_settings_get("ui", "exchange_ticker_mode") or "ticker"
    local show_ticker = (mode ~= "console")

    for _, w in ipairs({UI.exchange_ticker, UI.exchange_ticker_sep, UI.exchange_ticker_hdr}) do
        if w then
            if show_ticker then w:show() else w:hide() end
        end
    end
    -- Resize market scroll: 137px reserved with ticker (36px chrome + 1px sep + 20px hdr + 80px ticker), 36px without.
    if UI.exchange_market_scroll then
        UI.exchange_market_scroll:resize("100%", show_ticker and "100%-137px" or "100%-36px")
    end
    if show_ticker then ui_exchange_ticker_hdr_render() end
end

-- Render the fixed column-header bar above the ticker.
-- Offsets match _ticker_cecho: 1(space)+2(icon)+1(space) = 4 chars before Commodity.
-- Buy column = BUY_COL_W (12) chars; Selling is the last column (variable-width).
function ui_exchange_ticker_hdr_render()
    if not UI.exchange_ticker_hdr then return end
    clearWindow(UI.exchange_ticker_hdr.name)
    -- Header offsets: 4 chars (space+icon_slot) + name(12) + space + base(6) + sep(1) + buy(BUY_COL_W) + sep(1).
    -- \n required — MiniConsoles buffer partial lines and won't render without it.
    UI.exchange_ticker_hdr:cecho(string.format(
        "    <dim_grey>%-12s %-6s %-12s Selling<reset>\n",
        "Commodity", "Base", "Buying"
    ))
end

function ui_exchange_ticker_clear()
    if UI.exchange then UI.exchange.ticker_entries = {} end
    if UI.exchange_ticker then
        clearWindow(UI.exchange_ticker.name)
    end
end

-- Re-renders full history into the MiniConsole (used after reconnect or hot-reload).
function ui_exchange_ticker_render()
    if not UI.exchange_ticker then return end
    clearWindow(UI.exchange_ticker.name)
    local entries = UI.exchange and UI.exchange.ticker_entries or {}
    for _, e in ipairs(entries) do
        _ticker_append(UI.exchange_ticker, e)
    end
    ui_exchange_ticker_hdr_render()
end

function ui_exchange_ticker_add(entry)
    if not UI.exchange then return end
    local t = UI.exchange.ticker_entries
    table.insert(t, entry)
    while #t > TICKER_MAX do table.remove(t, 1) end
    if UI.exchange_ticker then
        _ticker_append(UI.exchange_ticker, entry)
    end
end

-- ─── GMCP / room handlers ─────────────────────────────────────────────────────

function ui_exchange_on_gmcp_exchange()
    ui_exchange_market_update_visibility()
    local at_ex = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")
    if at_ex and (f2t_is_rank_exactly("Trader") or f2t_is_rank_exactly("Financier")) then
        ui_futures_market_on_gmcp_exchange()
    end
end

function ui_exchange_on_room_info()
    ui_exchange_market_update_visibility()
    local at_ex = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")
    if at_ex then
        if f2t_is_rank_exactly("Trader") or f2t_is_rank_exactly("Financier") then
            ui_futures_market_on_gmcp_exchange()
        end
    else
        ui_exchange_ticker_clear()
    end
end

function ui_exchange_on_connect()
    ui_exchange_ticker_clear()
    ui_exchange_market_update_visibility()
end

function ui_exchange_on_disconnect()
    ui_exchange_ticker_clear()
    if UI.exchange_market_hdr     then UI.exchange_market_hdr:hide()     end
    if UI.exchange_market_col_bar then UI.exchange_market_col_bar:hide() end
    if UI.exchange_market_scroll  then UI.exchange_market_scroll:hide()  end
end

-- ─── init ─────────────────────────────────────────────────────────────────────

function ui_exchange_init()
    if not UI.exchange_market_scroll then
        f2t_debug_log("[exchange] exchange_market_scroll not available — skipping init")
        return
    end

    UI.exchange = {
        ticker_entries  = {},
        ticker_inflight = nil,
        ticker_timer    = nil,
    }

    -- Market futures table (column defs, table_create, scrollbox wiring) owned by ui_futures.lua
    ui_futures_market_init()

    ui_exchange_market_update_visibility()
    ui_exchange_ticker_render()
    tempTimer(0.1, function() ui_exchange_on_room_info() end)
    ui_exchange_apply_ticker_mode()

    -- Suppress link underline on sell-price hover tooltips so they look like normal text.
    -- cechoLink with useCurrentColors=true already preserves colour; this removes the underline.
    if UI.exchange_ticker then
        pcall(setLinkStyleSheet,
            [[color: inherit; text-decoration: none;]],
            [[color: inherit; text-decoration: none;]],
            UI.exchange_ticker.name
        )
    end

    f2t_debug_log("[exchange] initialized")
end
