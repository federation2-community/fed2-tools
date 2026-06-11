-- Futures: market table (hosted in Exchange tab) + owned futures tab.
--
-- Market table (Exchange tab, Trader/Financier at exchange):
--   Reads gmcp.exchange live — no game commands needed.
--   P&L at liquidation = exchange price − futures price (LONG) or reverse (SHORT).
--   BΔ (Base Δ) = base − futures (L) / futures − base (S). Positive = favorable ticks ahead.
--   EΔ (Exch Δ) = exch − futures (L) / futures − exch (S). Positive = profitable now.
--   Exchange price converges toward base ~1ig/ton per tick (~5-10 min).
--
-- Owned futures tab (any location):
--   Reads gmcp.char.futures in real-time — no di futures command needed.
--   Tab appears when any futures are held; disappears when all are closed.
--   P&L = margin − 4,000ig starting margin. Margin call if margin < min_margin.
--   Game mechanics: Broker fee on liquidation: 5% of profit, min 250ig.
--   Trading Rating: +1pt per 1k profit, −1pt per 1k loss, −4pts per margin call.

UI = UI or {}

-- ─── constants ───────────────────────────────────────────────────────────────

local _ROW_H = 18
local _SF    = "font-size:11pt;font-family:Consolas,Monaco,monospace;"
local _C_W   = "#d8d8d8"
local _C_GR  = "#888888"
local _C_G   = "#44cc44"
local _C_Y   = "#cccc44"
local _C_R   = "#cc4444"
local _C_CY  = "#00cccc"
local _C_MA  = "#993333"

local _BG_NORMAL    = "background-color:transparent; border:none; padding:0;"
local _BG_OWNED     = "background-color:rgba(25,25,50,160); border:none; padding:0;"
local _BG_SUSPENDED = "background-color:rgba(60,12,12,140); border:none; padding:0;"

local _COL_HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-size: 10pt; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: white; }
]]

-- ─── math helpers ────────────────────────────────────────────────────────────

local function fmt_ig(n)
    if not n then return "?" end
    n = tonumber(n) or 0
    local a = math.abs(n)
    if a >= 1000000 then return string.format("%.1fM", n / 1e6)
    elseif a >= 1000 then return string.format("%.1fk", n / 1e3)
    else                  return tostring(math.floor(n)) end
end

local function fmt_ig_signed(n)
    if not n then return "?" end
    n = tonumber(n) or 0
    return (n >= 0 and "+" or "") .. fmt_ig(n)
end

local function fmt_gap_str(n)
    if math.abs(n) < 10000 then
        return string.format("%+d", math.floor(n))
    else
        return string.format("%+.1fk", n / 1000)
    end
end

local function calc_b_delta(contract_type, futures_price, base_price)
    if not base_price then return nil end
    return contract_type == "long" and (base_price - futures_price) or (futures_price - base_price)
end

local function gap_css(n)
    if not n        then return _C_GR end
    if n >= 100     then return _C_G
    elseif n >= 20  then return _C_Y
    elseif n >= -20 then return _C_GR
    else                 return _C_R end
end

local function calc_composite_score(b_delta, e_delta)
    if not b_delta then return nil end
    local composite = e_delta and (b_delta + e_delta) / 2 or b_delta * 0.6
    local clamped   = math.max(-200, math.min(200, composite))
    return math.max(1, math.min(10, math.floor(((clamped + 200) / 400) * 9 + 1.5)))
end

-- ─── span helpers ─────────────────────────────────────────────────────────────

local function _sp(align, color, text)
    return string.format(
        "<p style='text-align:%s;margin:0;padding:0 3px;'><span style='%scolor:%s;'>%s</span></p>",
        align, _SF, color, text)
end

local function sp_state(align, row, text, normal_color)
    if row.suspended then
        return _sp(align, _C_MA, text)
    elseif row.owned then
        return string.format(
            "<p style='text-align:%s;margin:0;padding:0 3px;'><span style='%scolor:%s;text-decoration:line-through;'>%s</span></p>",
            align, _SF, _C_GR, text)
    else
        return _sp(align, normal_color, text)
    end
end

local function sp_l(c, t) return _sp("left",   c, t) end
local function sp_r(c, t) return _sp("right",  c, t) end
local function sp_c(c, t) return _sp("center", c, t) end

local function _cell_bg(row)
    if     row.suspended then return _BG_SUSPENDED
    elseif row.owned     then return _BG_OWNED
    else                      return _BG_NORMAL end
end

local function _plain_bg()  return _BG_NORMAL end

-- ─── shared column header builder ────────────────────────────────────────────

local function _build_col_hdrs(table_id, prefix, cols, col_bar)
    if not col_bar then return end
    local x_pct = 0
    local hdrs  = {}
    for _, col in ipairs(cols) do
        local lbl = Geyser.Label:new({
            name  = string.format("%s_hdr_%d", prefix, x_pct),
            x     = x_pct .. "%", y = 0,
            width = col.scrollbox_pct .. "%", height = "100%",
        }, col_bar)
        lbl:setStyleSheet(_COL_HDR_CSS)
        lbl:echo(col.label)
        if col.sortable then
            local key = col.key
            lbl:setClickCallback(function() ui_table_toggle_sort(table_id, key) end)
        end
        local tip = col.header_tooltip or (col.sortable and ("Sort by " .. col.label) or nil)
        if tip then lbl:setToolTip(tip) end
        hdrs[col.key] = lbl
        x_pct = x_pct + col.scrollbox_pct
    end
    return hdrs
end

-- ─── scrollbox width/height sync ─────────────────────────────────────────────

local function _sync_sb(scroll, content, table_id)
    if not (scroll and content and UI.tables and UI.tables[table_id]) then return end
    local sb = UI.tables[table_id].scrollbox
    if not sb then return end
    local sw = scroll:get_width()
    if sw > 60 then
        local cw = sw - 17
        if sb.content_w ~= cw then
            sb.content_w = cw
            content:resize(cw, content:get_height())
        end
    end
    local sh = scroll:get_height()
    if sh > 30 then sb.min_height = sh end
end

-- =============================================================================
-- MARKET TABLE  (lives in Exchange tab)
-- =============================================================================

UI.futures_market = UI.futures_market or { data = {}, planet = nil }

local function build_market_from_gmcp()
    local exchange = gmcp and gmcp.exchange
    if not exchange or not exchange.futures then return {} end

    local comms  = exchange.commodities or {}
    local market = {}
    local planet = gmcp.room and gmcp.room.info and
        (gmcp.room.info.area or gmcp.room.info.system) or ""

    for name_lower, contract in pairs(exchange.futures) do
        local comm_name, exc_data = nil, nil
        for cname, cdata in pairs(comms) do
            if cname:lower() == name_lower then
                comm_name = cname
                exc_data  = cdata
                break
            end
        end

        local base    = exc_data and exc_data.base or nil
        local fp      = contract.price
        local b_delta = calc_b_delta(contract.type, fp, base)

        local exc, exc_hidden = nil, false
        if exc_data then
            if contract.type == "long" then
                local sell = exc_data.sell
                if sell and sell > 0 then exc = sell else exc_hidden = true end
            else
                local buy = exc_data.buy
                if buy and buy > 0 then exc = buy else exc_hidden = true end
            end
        end

        local e_delta = nil
        if exc then
            e_delta = contract.type == "long" and (exc - fp) or (fp - exc)
        end

        -- Mark already-owned contracts at this exchange
        local owned = false
        local cf    = gmcp.char and gmcp.char.futures
        if type(cf) == "table" then
            for _, f in ipairs(cf) do
                if (f.commodity or ""):lower() == name_lower and
                   (f.exchange  or ""):lower() == planet:lower() then
                    owned = true; break
                end
            end
        end

        table.insert(market, {
            commodity  = comm_name or name_lower,
            type       = contract.type,
            price      = fp,
            base       = base,
            b_delta    = b_delta,
            exc        = exc,
            exc_hidden = exc_hidden,
            e_delta    = e_delta,
            stock      = exc_data and (tonumber(exc_data.stock) or 0) or nil,
            suspended  = (contract.status == "suspended"),
            owned      = owned,
        })
    end
    return market
end

function ui_futures_market_render()
    if not UI.exchange_market_hdr then return end
    _sync_sb(UI.exchange_market_scroll, UI.exchange_market_content, "futures_market")

    local planet = UI.futures_market.planet or "?"
    UI.exchange_market_hdr:echo(string.format(
        "<span style='%scolor:#cccc44;padding-left:4px;'>%s</span>" ..
        "&nbsp;<span style='%scolor:#888888;'>live</span>",
        _SF, planet, _SF))

    ui_table_set_data("futures_market", UI.futures_market.data)
end

function ui_futures_market_on_gmcp_exchange()
    if not UI.exchange_market_scroll then return end
    UI.futures_market.data   = build_market_from_gmcp()
    UI.futures_market.planet = gmcp and gmcp.room and gmcp.room.info and
        (gmcp.room.info.area or gmcp.room.info.system)
    ui_futures_market_render()
end

function ui_futures_market_init()
    if not UI.exchange_market_scroll then
        f2t_debug_log("[futures] exchange_market_scroll missing — market table skipped")
        return
    end

    UI.futures_market = { data = {}, planet = nil }

    local market_cols = {
        {
            key            = "commodity",
            label          = "Commodity",
            header_tooltip = "Click to buy. Maroon=suspended. Strikethrough=already owned here.",
            scrollbox_pct  = 22,
            sortable       = true,
            sort_value     = function(r) return (r.commodity or ""):lower() end,
            render_label   = function(v, row, cell, col)
                cell:setStyleSheet(_cell_bg(row))
                cell:echo(sp_state("left", row, tostring(v or ""), _C_W))
                if row.suspended then
                    cell:setClickCallback(function() end)
                    cell:setToolTip("Trading suspended — price frozen until hour end.")
                elseif row.owned then
                    cell:setClickCallback(function() end)
                    cell:setToolTip("Already held at this exchange — one contract per commodity per exchange.")
                else
                    cell:setClickCallback(function()
                        send("buy futures " .. (v or ""):lower())
                    end)
                    cell:setToolTip(string.format("Buy %s futures contract", v))
                end
            end,
        },
        {
            key            = "type",
            label          = "T",
            header_tooltip = "L=Long (profit when price rises toward base). S=Short (profit when it falls).",
            scrollbox_pct  = 4,
            sortable       = true,
            sort_value     = function(r) return r.type end,
            render_label   = function(v, row, cell, col)
                cell:setStyleSheet(_cell_bg(row))
                local display = v == "long" and "L" or "S"
                local color   = v == "long" and _C_CY or _C_Y
                cell:echo(sp_state("center", row, display, color))
                cell:setClickCallback(function() end)
                cell:setToolTip(v == "long"
                    and "Long — profit when price rises toward base"
                    or  "Short — profit when price falls toward base")
            end,
        },
        {
            key            = "price",
            label          = "Fut",
            header_tooltip = "Futures price per ton — locked in at purchase.",
            scrollbox_pct  = 10,
            sortable       = true,
            sort_value     = function(r) return r.price or 0 end,
            render_label   = function(v, row, cell, col)
                cell:setStyleSheet(_cell_bg(row))
                local n = tonumber(v)
                cell:echo(sp_state("right", row, n and tostring(math.floor(n)) or "?", _C_W))
                cell:setClickCallback(function() end)
                cell:setToolTip("Futures price per ton")
            end,
        },
        {
            key            = "base",
            label          = "Base",
            header_tooltip = "Commodity base price. Futures converge ~1ig/ton per tick (every 5-10 min).",
            scrollbox_pct  = 10,
            sortable       = true,
            sort_value     = function(r) return r.base or 0 end,
            render_label   = function(v, row, cell, col)
                cell:setStyleSheet(_cell_bg(row))
                local n = tonumber(v)
                cell:echo(sp_state("right", row, n and tostring(math.floor(n)) or "n/a", _C_GR))
                cell:setClickCallback(function() end)
                cell:setToolTip("Commodity base price")
            end,
        },
        {
            key            = "b_delta",
            label          = "BΔ",
            header_tooltip = "Base delta (L=base−Fut, S=Fut−base). Positive=favorable ticks ahead. Green≥100 Yellow≥20 Red=wrong direction.",
            scrollbox_pct  = 13,
            sortable       = true,
            sort_value     = function(r) return r.b_delta or -9999 end,
            render_label   = function(v, row, cell, col)
                cell:setStyleSheet(_cell_bg(row))
                local n = tonumber(v)
                if not n then
                    cell:echo(sp_state("right", row, "n/a", _C_GR))
                    cell:setClickCallback(function() end)
                    cell:setToolTip("Base delta — base price unavailable")
                    return
                end
                cell:echo(sp_state("right", row, fmt_gap_str(n), gap_css(n)))
                cell:setClickCallback(function() end)
                cell:setToolTip(string.format("BΔ=%+d: each unit ≈ 1 favorable tick (~5-10 min)", n))
            end,
        },
        {
            key            = "exc",
            label          = "Exch",
            header_tooltip = "Exchange liquidation price (sell for Long, buy for Short). ?=not in GMCP.",
            scrollbox_pct  = 10,
            sortable       = true,
            sort_value     = function(r) return r.exc or -1 end,
            render_label   = function(v, row, cell, col)
                cell:setStyleSheet(_cell_bg(row))
                local n = tonumber(v)
                if not n then
                    local s = row.exc_hidden and "?" or "n/a"
                    cell:echo(sp_state("right", row, s, _C_GR))
                    cell:setClickCallback(function() end)
                    cell:setToolTip(row.exc_hidden
                        and "Price exists but not visible in GMCP."
                        or  "Not traded at this exchange")
                    return
                end
                cell:echo(sp_state("right", row, tostring(math.floor(n)), _C_W))
                cell:setClickCallback(function() end)
                cell:setToolTip("Exchange price at liquidation")
            end,
        },
        {
            key            = "stock",
            label          = "Stk",
            header_tooltip = "Exchange stock on hand. 0=depleted. High→price pressure down. Low→up.",
            scrollbox_pct  = 11,
            sortable       = true,
            sort_value     = function(r) return r.stock or -1 end,
            render_label   = function(v, row, cell, col)
                cell:setStyleSheet(_cell_bg(row))
                local n = tonumber(v)
                cell:echo(sp_state("right", row, n and fmt_ig(n) or "n/a", _C_GR))
                cell:setClickCallback(function() end)
                cell:setToolTip("Exchange stock on hand")
            end,
        },
        {
            key            = "e_delta",
            label          = "EΔ",
            header_tooltip = "Exch delta (L=Exch−Fut, S=Fut−Exch). Positive=profitable now. ?=not in GMCP.",
            scrollbox_pct  = 10,
            sortable       = true,
            sort_value     = function(r) return r.e_delta or -9999 end,
            render_label   = function(v, row, cell, col)
                cell:setStyleSheet(_cell_bg(row))
                local n = tonumber(v)
                if not n then
                    local s = row.exc_hidden and "?" or "n/a"
                    cell:echo(sp_state("right", row, s, _C_GR))
                    cell:setClickCallback(function() end)
                    cell:setToolTip(row.exc_hidden and "Exch not in GMCP." or "No exchange price")
                    return
                end
                cell:echo(sp_state("right", row, fmt_gap_str(n), gap_css(n)))
                cell:setClickCallback(function() end)
                cell:setToolTip(string.format("EΔ=%+d: positive=profitable to liquidate now", n))
            end,
        },
        {
            key            = "score",
            label          = "S",
            header_tooltip = "Score 1-10: (BΔ+EΔ)/2 normalised ±200ig. ≥7=strong. 5-6=neutral. ≤4=poor.",
            scrollbox_pct  = 10,
            sortable       = true,
            default_sort   = "desc",
            sort_value     = function(r) return calc_composite_score(r.b_delta, r.e_delta) or 0 end,
            render_label   = function(v, row, cell, col)
                cell:setStyleSheet(_cell_bg(row))
                local n = calc_composite_score(row.b_delta, row.e_delta)
                if not n then
                    cell:echo(sp_state("right", row, "?", _C_GR))
                    cell:setClickCallback(function() end)
                    cell:setToolTip("Score unavailable — base price missing")
                    return
                end
                local color = n >= 7 and _C_G or (n >= 5 and _C_Y or _C_R)
                cell:echo(sp_state("right", row, tostring(n), color))
                cell:setClickCallback(function() end)
                cell:setToolTip(string.format("Score %d/10: ≥7 strong · 5-6 neutral · ≤4 poor", n))
            end,
        },
    }

    local cw = math.max(50, UI.exchange_market_scroll:get_width() - 17)
    ui_table_create("futures_market", nil, market_cols, nil)
    ui_table_set_scrollbox("futures_market", UI.exchange_market_content, cw, _ROW_H, UI.exchange_market_scroll)
    local hdrs = _build_col_hdrs("futures_market", "fut_mkt", market_cols, UI.exchange_market_col_bar)
    if hdrs then UI.tables["futures_market"].scrollbox.col_hdrs = hdrs end
end

-- =============================================================================
-- OWNED FUTURES TAB  (from gmcp.char.futures, any location)
-- =============================================================================

local function _find_tab_window(name)
    for _, win in pairs(Adjustable.TabWindow.all or {}) do
        if win.tabs and f2t_has_value(win.tabs, name) then return win end
    end
    return nil
end

local function _build_owned_row(f, commods_lookup)
    local margin   = tonumber(f.margin)    or 4000
    local min_m    = tonumber(f.min_margin) or 2000
    local max_loss = tonumber(f.max_loss)   or 15000
    local pl       = margin - 4000

    local risk
    if margin < min_m then
        risk = "call"
    elseif margin < min_m + 1000 then
        risk = "warn"
    elseif (4000 - margin) > max_loss * 0.7 then
        risk = "danger"
    else
        risk = "ok"
    end

    local commodity_raw = f.commodity or "?"
    -- Resolve the proper display name from the commodities list (GMCP sends lowercase)
    local commodity = (commods_lookup and commods_lookup[commodity_raw:lower()]) or commodity_raw

    return {
        exchange  = f.exchange  or "?",
        commodity = commodity,
        position  = f.position  or "?",
        cost      = tonumber(f.cost)  or 0,
        value     = tonumber(f.value) or 0,
        pl        = pl,
        margin    = margin,
        min_m     = min_m,
        max_loss  = max_loss,
        risk      = risk,
    }
end

function ui_futures_render()
    if not UI.futures_hdr then return end
    _sync_sb(UI.futures_scroll, UI.futures_content, "owned_futures")

    local cf = gmcp and gmcp.char and gmcp.char.futures
    if type(cf) ~= "table" or #cf == 0 then
        UI.futures_hdr:echo(string.format(
            "<span style='%scolor:%s;padding-left:4px;'>No contracts held.</span>", _SF, _C_GR))
        ui_table_set_data("owned_futures", {})
        return
    end

    -- Build a lowercase→display name lookup once per render (GMCP sends commodity names in lowercase)
    local commods_lookup = {}
    for _, c in ipairs(ui_commodities_load and ui_commodities_load() or {}) do
        if c.name then commods_lookup[c.name:lower()] = c.name end
    end

    local rows   = {}
    local total_pl = 0
    for _, f in ipairs(cf) do
        local row = _build_owned_row(f, commods_lookup)
        table.insert(rows, row)
        total_pl = total_pl + row.pl
    end

    local pl_color = total_pl > 0 and _C_G or (total_pl < 0 and _C_R or _C_GR)
    UI.futures_hdr:echo(string.format(
        "<span style='%scolor:%s;padding-left:4px;'>%d contract%s</span>" ..
        "&nbsp;&nbsp;<span style='%scolor:#888;'>Total P&amp;L:</span>" ..
        "&nbsp;<span style='%scolor:%s;'>%s</span>",
        _SF, _C_GR, #rows, #rows ~= 1 and "s" or "",
        _SF, _SF, pl_color, fmt_ig_signed(total_pl)))

    ui_table_set_data("owned_futures", rows)
end

function ui_futures_on_gmcp_char_futures()
    if not ui_built then return end
    local cf      = gmcp and gmcp.char and gmcp.char.futures
    local has_any = type(cf) == "table" and #cf > 0

    if has_any then
        if not _find_tab_window("Futures") then
            UI.tab_bottom_right:addTab("Futures", 4)
        end
        ui_futures_render()
    else
        local w = _find_tab_window("Futures")
        if w then w:removeTab("Futures") end
    end
end

function ui_futures_on_connect()
    -- Defer to let GMCP char data arrive first
    tempTimer(0.5, function() ui_futures_on_gmcp_char_futures() end)
end

function ui_futures_on_disconnect()
    local w = _find_tab_window("Futures")
    if w then w:removeTab("Futures") end
end

-- ─── owned futures init ───────────────────────────────────────────────────────

function ui_futures_init()
    if not UI.futures_scroll then
        f2t_debug_log("[futures] futures_scroll not available — owned futures skipped")
        return
    end

    local owned_cols = {
        {
            key           = "exchange",
            label         = "Exchange",
            scrollbox_pct = 22,
            sortable      = true,
            sort_value    = function(r) return (r.exchange or ""):lower() end,
            render_label  = function(v, row, cell, col)
                cell:setStyleSheet(_plain_bg())
                cell:echo(sp_l(_C_CY, tostring(v or "?")))
                cell:setClickCallback(function()
                    expandAlias("nav " .. tostring(v or "") .. " exchange")
                end)
                cell:setToolTip("Navigate to " .. tostring(v or "?") .. " exchange")
            end,
        },
        {
            key           = "commodity",
            label         = "Commodity",
            scrollbox_pct = 22,
            sortable      = true,
            sort_value    = function(r) return (r.commodity or ""):lower() end,
            render_label  = function(v, row, cell, col)
                cell:setStyleSheet(_plain_bg())
                cell:echo(sp_l(_C_W, tostring(v or "?")))
                cell:setClickCallback(function() end)
                cell:setToolTip("")
            end,
        },
        {
            key           = "position",
            label         = "T",
            header_tooltip = "L=Long  S=Short",
            scrollbox_pct = 4,
            sortable      = true,
            sort_value    = function(r) return r.position end,
            render_label  = function(v, row, cell, col)
                cell:setStyleSheet(_plain_bg())
                local is_long = (v == "long")
                cell:echo(sp_c(is_long and _C_CY or _C_Y, is_long and "L" or "S"))
                cell:setClickCallback(function() end)
                cell:setToolTip(is_long and "Long contract" or "Short contract")
            end,
        },
        {
            key           = "cost",
            label         = "Cost",
            scrollbox_pct = 12,
            sortable      = true,
            sort_value    = function(r) return r.cost or 0 end,
            render_label  = function(v, row, cell, col)
                cell:setStyleSheet(_plain_bg())
                cell:echo(sp_r(_C_GR, fmt_ig(tonumber(v))))
                cell:setClickCallback(function() end)
                cell:setToolTip("Original contract cost")
            end,
        },
        {
            key           = "value",
            label         = "Value",
            scrollbox_pct = 12,
            sortable      = true,
            sort_value    = function(r) return r.value or 0 end,
            render_label  = function(v, row, cell, col)
                cell:setStyleSheet(_plain_bg())
                local n    = tonumber(v) or 0
                local cost = tonumber(row.cost) or 0
                local color = n >= cost and _C_G or (n < cost and _C_R or _C_GR)
                cell:echo(sp_r(color, fmt_ig(n)))
                cell:setClickCallback(function() end)
                cell:setToolTip("Current mark-to-market value")
            end,
        },
        {
            key           = "pl",
            label         = "P&L",
            header_tooltip = "Broker P&L = margin − 4,000ig starting margin",
            scrollbox_pct = 12,
            sortable      = true,
            default_sort  = "asc",
            sort_value    = function(r) return r.pl or 0 end,
            render_label  = function(v, row, cell, col)
                cell:setStyleSheet(_plain_bg())
                local n = tonumber(v) or 0
                local color = n > 0 and _C_G or (n < 0 and _C_R or _C_GR)
                cell:echo(sp_r(color, fmt_ig_signed(n)))
                cell:setClickCallback(function() end)
                cell:setToolTip("P&L = margin − 4,000ig starting margin")
            end,
        },
        {
            key           = "margin",
            label         = "Margin",
            scrollbox_pct = 12,
            sortable      = true,
            sort_value    = function(r) return r.margin or 0 end,
            render_label  = function(v, row, cell, col)
                cell:setStyleSheet(_plain_bg())
                local n = tonumber(v) or 4000
                local color = (row.risk == "call" or row.risk == "danger") and _C_R
                           or row.risk == "warn" and _C_Y
                           or _C_GR
                cell:echo(sp_r(color, fmt_ig(n)))
                cell:setClickCallback(function() end)
                cell:setToolTip("Broker margin. Margin call if < min_margin (charges 4,000ig, −4 Trading Rating pts)")
            end,
        },
        {
            key            = "risk",
            label          = "M",
            header_tooltip = "Margin health: ✓=healthy  !=near minimum  ✗=margin call/danger",
            scrollbox_pct  = 4,
            sortable       = false,
            render_label   = function(v, row, cell, col)
                cell:setStyleSheet(_plain_bg())
                local icons = { ok = {"✓", _C_G}, warn = {"!", _C_Y}, call = {"✗", _C_R}, danger = {"✗", _C_R} }
                local tips  = {
                    ok     = "Margin healthy",
                    warn   = "Approaching minimum margin",
                    call   = "Margin call — below minimum margin (4,000ig charge pending)",
                    danger = "Danger — losses approaching maximum",
                }
                local d = icons[v] or {"?", _C_GR}
                cell:echo(sp_c(d[2], d[1]))
                cell:setClickCallback(function() end)
                cell:setToolTip(tips[v] or "Unknown")
            end,
        },
    }

    local cw = math.max(50, UI.futures_scroll:get_width() - 17)
    ui_table_create("owned_futures", nil, owned_cols, nil)
    ui_table_set_scrollbox("owned_futures", UI.futures_content, cw, _ROW_H, UI.futures_scroll)
    local hdrs = _build_col_hdrs("owned_futures", "fut_own", owned_cols, UI.futures_col_bar)
    if hdrs then UI.tables["owned_futures"].scrollbox.col_hdrs = hdrs end

    -- Futures stays in the tab bar so load() can restore its position without calling
    -- activateTab (same as Who). Runtime add/remove still applies via
    -- ui_futures_on_gmcp_char_futures. Fire a deferred check only for package reloads
    -- mid-session when GMCP data is already present.
    tempTimer(0.1, function()
        if gmcp and gmcp.char and gmcp.char.futures then
            ui_futures_on_gmcp_char_futures()
        end
    end)

    f2t_debug_log("[futures] initialized")
end
