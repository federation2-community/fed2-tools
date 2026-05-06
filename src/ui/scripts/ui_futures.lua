-- =============================================================================
-- FUTURES TAB
-- Captures and displays futures contracts for Trader and Financier ranks.
--
-- Portfolio view: di futures outside exchange → shows held contracts with P&L
-- Market view:    di futures inside exchange  → shows available contracts to buy
--
-- Game mechanics:
--   Contracts cost 4,000ig margin. P&L = current margin - 4,000.
--   Settled hourly: margin += (new_value - prev_value).
--   Margin call at < 2,000ig. Auto-liquidated at 15,000ig loss.
--   Broker fee: 5% of profit, min 250ig on liquidation.
-- =============================================================================

UI = UI or {}

-- =============================================================================
-- HELPERS
-- =============================================================================

local function fmt_ig(n)
    if not n then return "?" end
    n = tonumber(n) or 0
    local abs_n = math.abs(n)
    if abs_n >= 1000000 then
        return string.format("%.1fM", n / 1e6)
    elseif abs_n >= 1000 then
        return string.format("%.1fk", n / 1e3)
    else
        return tostring(n)
    end
end

local function fmt_ig_signed(n)
    if not n then return "?" end
    n = tonumber(n) or 0
    return (n >= 0 and "+" or "") .. fmt_ig(n)
end

-- =============================================================================
-- STATE
-- =============================================================================

UI.futures = UI.futures or {
    -- Held contracts (portfolio)
    portfolio     = {},

    -- Available contracts at current exchange (market)
    market        = {},
    market_planet = nil,
    market_info   = {},

    -- Which view is displayed
    view          = "portfolio",

    -- Capture state
    capturing        = false,
    capture_buffer   = {},
    capture_triggers = {},
    capture_timer    = nil,
}

-- =============================================================================
-- CAPTURE HELPERS
-- =============================================================================

local function futures_cap_end()
    UI.futures.capturing = false
    for _, id in ipairs(UI.futures.capture_triggers) do
        killTrigger(id)
    end
    UI.futures.capture_triggers = {}
    if UI.futures.capture_timer then
        killTimer(UI.futures.capture_timer)
        UI.futures.capture_timer = nil
    end
end

local function futures_cap_reset_timer(on_done)
    if UI.futures.capture_timer then killTimer(UI.futures.capture_timer) end
    UI.futures.capture_timer = tempTimer(0.6, function()
        futures_cap_end()
        if on_done then on_done() end
    end)
end

local function futures_start_capture(on_done)
    futures_cap_end()
    UI.futures.capturing    = true
    UI.futures.capture_buffer = {}

    local function reset_t()
        futures_cap_reset_timer(on_done)
    end

    local tid = tempRegexTrigger("^.*$", function()
        if UI.futures.capturing then
            table.insert(UI.futures.capture_buffer, line)
            deleteLine()
            reset_t()
        end
    end)
    table.insert(UI.futures.capture_triggers, tid)

    reset_t()
end

-- =============================================================================
-- PARSE PORTFOLIO  (di futures outside exchange)
-- =============================================================================

local function parse_portfolio()
    UI.futures.portfolio = {}
    local current = nil

    for _, l in ipairs(UI.futures.capture_buffer) do
        -- Contract header: "Mars Exchange - Alloys Futures Contract"
        local planet, name = l:match("^(.+) Exchange %- (.+) Futures Contract$")
        if planet then
            if current then table.insert(UI.futures.portfolio, current) end
            current = { planet = planet, name = name }

        elseif current then
            -- Position + value: "Long position (You to receive)   Value: 131250ig"
            local pos_type, val = l:match("^(Long|Short) position.*Value: (%d+)ig$")
            if pos_type then
                current.type  = pos_type:lower()
                current.value = tonumber(val)
            end

            -- Cost + margin: "Cost: 131250ig    Margin: 4000ig (minimum 2000ig)"
            local cost, margin, min_margin =
                l:match("^Cost: (%d+)ig%s+Margin: (%d+)ig %(minimum (%d+)ig%)$")
            if cost then
                current.cost       = tonumber(cost)
                current.margin     = tonumber(margin)
                current.min_margin = tonumber(min_margin)
            end

            -- Max loss: "Maximum loss: 10000ig"
            local max_loss = l:match("^Maximum loss: (%d+)ig$")
            if max_loss then
                current.max_loss = tonumber(max_loss)
            end
        end
    end

    if current then table.insert(UI.futures.portfolio, current) end
end

-- =============================================================================
-- PARSE MARKET  (di futures inside exchange)
-- =============================================================================

local function parse_market()
    UI.futures.market        = {}
    UI.futures.market_planet = nil
    UI.futures.market_info   = {}

    for _, l in ipairs(UI.futures.capture_buffer) do
        -- Exchange header: "Mars Futures Exchange"
        local planet = l:match("^(.+) Futures Exchange$")
        if planet then UI.futures.market_planet = planet end

        -- Margin: "Margin 4000ig/contract"
        local margin = l:match("^Margin (%d+)ig/contract$")
        if margin then UI.futures.market_info.margin = tonumber(margin) end

        -- Min margin: "(Minimum 2000ig/contract)"
        local min_m = l:match("^%(Minimum (%d+)ig/contract%)$")
        if min_m then UI.futures.market_info.min_margin = tonumber(min_m) end

        -- Min movement: "Min movement 1ig/ton"
        local min_mv = l:match("^Min movement (%d+)ig/ton$")
        if min_mv then UI.futures.market_info.min_movement = tonumber(min_mv) end

        -- Max movement: "Max hourly movement 5ig/ton"
        local max_mv = l:match("^Max hourly movement (%d+)ig/ton$")
        if max_mv then UI.futures.market_info.max_movement = tonumber(max_mv) end

        -- Available contract: "Long  contract in cereals available at 315ig/ton."
        -- Handles multi-word commodity names and variable spacing
        local ctype, commodity, price =
            l:match("^(Long|Short)%s+contract in (.+) available at (%d+)ig/ton%.$")
        if ctype then
            table.insert(UI.futures.market, {
                type      = ctype:lower(),
                commodity = commodity,
                price     = tonumber(price),
            })
        end
    end
end

-- =============================================================================
-- RENDER PORTFOLIO
-- =============================================================================

function ui_futures_render_portfolio()
    if not UI.futures_window then return end
    UI.futures_window:clear()

    local portfolio = UI.futures.portfolio

    if #portfolio == 0 then
        UI.futures_window:cecho("\n<dim_grey>  No futures contracts held.\n\n")
        UI.futures_window:cecho("  Use <white>buy futures <commodity><reset> in a trading exchange\n")
        UI.futures_window:cecho("  to open a position, or visit an exchange and click <white>📈 Market<reset>.\n")
        return
    end

    -- Header row
    UI.futures_window:cecho("\n")
    UI.futures_window:cecho(
        "<dim_grey>Planet      Commodity       Type   Cost       Value      Margin     P&L<reset>\n"
    )
    UI.futures_window:cecho("<dim_grey>" .. string.rep("─", 72) .. "<reset>\n")

    local total_margin = 0
    local total_pl     = 0

    for _, c in ipairs(portfolio) do
        local margin   = c.margin or 4000
        local pl       = margin - 4000
        local pl_color = pl > 0 and "green" or (pl < 0 and "red" or "dim_grey")
        local type_color = c.type == "long" and "ansiCyan" or "yellow"
        local type_str   = c.type == "long" and "LONG " or "SHORT"

        -- At-exchange check: can we liquidate from here?
        local at_this = gmcp and gmcp.room and gmcp.room.info and
            gmcp.room.info.system == c.planet and
            f2t_has_value(gmcp.room.info.flags or {}, "exchange")

        total_margin = total_margin + margin
        total_pl     = total_pl     + pl

        -- Planet (clickable → navigate to exchange)
        UI.futures_window:cechoLink(
            string.format("<ansiCyan>%-10s<reset>", c.planet or "?"),
            function() expandAlias("nav " .. (c.planet or "") .. " exchange") end,
            "Navigate to " .. (c.planet or "") .. " exchange",
            true
        )

        UI.futures_window:cecho(
            string.format("  <white>%-15s<reset>  <%s>%s<reset>  %9s  %9s  %9s  ",
                c.name   or "?",
                type_color, type_str,
                fmt_ig(c.cost),
                fmt_ig(c.value),
                fmt_ig(margin)
            )
        )

        UI.futures_window:cecho(string.format("<%s>%8s<reset>", pl_color, fmt_ig_signed(pl)))

        -- Liquidate link when at the right exchange
        if at_this then
            local liq_commodity = (c.name or ""):lower()
            UI.futures_window:cecho("  ")
            UI.futures_window:cechoLink(
                "<red>[Liq]<reset>",
                function()
                    send("liquidate " .. liq_commodity)
                    tempTimer(1.0, function() ui_futures_refresh() end)
                end,
                "Liquidate " .. (c.name or "") .. " contract",
                true
            )
        end

        UI.futures_window:echo("\n")
    end

    -- Footer
    UI.futures_window:cecho("<dim_grey>" .. string.rep("─", 72) .. "<reset>\n")
    local total_pl_color = total_pl > 0 and "green" or (total_pl < 0 and "red" or "dim_grey")

    UI.futures_window:cecho(
        string.format(
            "<dim_grey>%d contract%s  Total margin: %s  Total P&L: <%s>%s<reset>\n",
            #portfolio,
            #portfolio ~= 1 and "s" or "",
            fmt_ig(total_margin),
            total_pl_color,
            fmt_ig_signed(total_pl)
        )
    )

    -- Trading Rating tip for Traders
    if f2t_is_rank_exactly and f2t_is_rank_exactly("Trader") then
        UI.futures_window:cecho(
            "\n<dim_grey>Tip: Trading Rating goal is 300. " ..
            "Gain 1pt per 1,000ig profit, lose 1pt per 1,000ig loss, lose 4pts per margin call.<reset>\n"
        )
    end
end

-- =============================================================================
-- RENDER MARKET
-- =============================================================================

function ui_futures_render_market()
    if not UI.futures_window then return end
    UI.futures_window:clear()

    local planet = UI.futures.market_planet or "Unknown"
    local info   = UI.futures.market_info

    UI.futures_window:cecho(
        string.format("\n<ansiYellow>%s Futures Exchange<reset>\n", planet)
    )

    if info.margin then
        UI.futures_window:cecho(
            string.format(
                "<dim_grey>Margin: %sig/contract  |  Min: %sig  |  Movement: %s-%sig/ton/hr<reset>\n\n",
                fmt_ig(info.margin or 4000),
                fmt_ig(info.min_margin or 2000),
                fmt_ig(info.min_movement or 1),
                fmt_ig(info.max_movement or 5)
            )
        )
    end

    if #UI.futures.market == 0 then
        UI.futures_window:cecho("<dim_grey>  No futures contracts available at this exchange.\n")
        UI.futures_window:cecho("  Not all exchanges offer futures contracts.\n")
        return
    end

    -- Header
    UI.futures_window:cecho(
        "<dim_grey>Commodity        Type   Price/ton   Strategy<reset>\n"
    )
    UI.futures_window:cecho("<dim_grey>" .. string.rep("─", 55) .. "<reset>\n")

    for _, contract in ipairs(UI.futures.market) do
        local type_color   = contract.type == "long" and "ansiCyan" or "yellow"
        local type_label   = contract.type == "long" and "LONG " or "SHORT"
        local strategy_tip = contract.type == "long"
            and "profit when price rises"
            or  "profit when price falls"

        UI.futures_window:cecho(
            string.format("<white>%-16s<reset>  <%s>%s<reset>  %8sig/ton  <dim_grey>%s<reset>  ",
                contract.commodity or "?",
                type_color, type_label,
                fmt_ig(contract.price),
                strategy_tip
            )
        )

        local commodity_name = contract.commodity or ""
        UI.futures_window:cechoLink(
            "<green>[Buy]<reset>",
            function()
                send("buy futures " .. commodity_name:lower())
                tempTimer(1.0, function() ui_futures_refresh() end)
            end,
            string.format("Buy %s futures contract (%s)", commodity_name, strategy_tip),
            true
        )

        UI.futures_window:echo("\n")
    end

    UI.futures_window:cecho("\n<dim_grey>Click <white>[Buy]<reset><dim_grey> to purchase a contract (costs " ..
        fmt_ig(info.margin or 4000) .. "ig margin).<reset>\n")

    -- Link to check portfolio even while at exchange
    UI.futures_window:cecho("<dim_grey>Click <white>📋 My Contracts<reset><dim_grey> to view your held contracts.<reset>\n")
end

-- =============================================================================
-- REFRESH ENTRY POINTS
-- =============================================================================

function ui_futures_show_portfolio()
    local at_exchange = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")

    UI.futures.view = "portfolio"

    if at_exchange then
        -- di futures at exchange shows market, not portfolio.
        -- Render whatever we last captured (cached data) or prompt.
        ui_futures_render_portfolio()
    else
        futures_start_capture(function()
            parse_portfolio()
            ui_futures_render_portfolio()
        end)
        send("di futures", false)
    end
end

function ui_futures_show_market()
    local at_exchange = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")

    if not at_exchange then
        cecho("\n<red>[futures]<reset> Must be at a trading exchange to view the market.\n")
        return
    end

    UI.futures.view = "market"

    futures_start_capture(function()
        parse_market()
        ui_futures_render_market()
    end)
    send("di futures", false)
end

function ui_futures_refresh()
    local at_exchange = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")

    if at_exchange then
        -- If we were viewing portfolio, keep showing portfolio (cached)
        if UI.futures.view == "portfolio" then
            ui_futures_render_portfolio()
        else
            ui_futures_show_market()
        end
    else
        ui_futures_show_portfolio()
    end
end

-- =============================================================================
-- BUTTON STATE (called when room changes)
-- =============================================================================

function ui_futures_update_buttons()
    if not UI.futures_market_btn then return end

    local at_exchange = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")

    if at_exchange then
        UI.futures_market_btn:setStyleSheet(UI.style.button_css)
        UI.futures_market_btn:setClickCallback("ui_futures_show_market")
        UI.futures_market_btn:setToolTip("View futures contracts available at this exchange")
    else
        UI.futures_market_btn:setStyleSheet(UI.style.disabled_button_css)
        UI.futures_market_btn:setClickCallback(function() end)
        UI.futures_market_btn:setToolTip("Enter a trading exchange to view available contracts")
    end
end

-- =============================================================================
-- TAB SETUP  (called from ui_build)
-- =============================================================================

function ui_futures()
    -- ── Button bar ────────────────────────────────────────────────────────────

    UI.futures_portfolio_btn = Geyser.Label:new({
        name    = "UI.futures_portfolio_btn",
        message = "<center>📋 My Contracts</center>",
    }, UI.futures_button_bar)
    UI.futures_portfolio_btn:setStyleSheet(UI.style.button_css)
    UI.futures_portfolio_btn:setClickCallback("ui_futures_show_portfolio")
    UI.futures_portfolio_btn:setToolTip("View your held futures contracts (di futures)")

    UI.futures_market_btn = Geyser.Label:new({
        name    = "UI.futures_market_btn",
        message = "<center>📈 Market</center>",
    }, UI.futures_button_bar)
    UI.futures_market_btn:setStyleSheet(UI.style.disabled_button_css)
    UI.futures_market_btn:setClickCallback(function() end)
    UI.futures_market_btn:setToolTip("Enter a trading exchange to view available contracts")

    -- ── Initial state ─────────────────────────────────────────────────────────

    UI.futures = {
        portfolio     = {},
        market        = {},
        market_planet = nil,
        market_info   = {},
        view          = "portfolio",
        capturing        = false,
        capture_buffer   = {},
        capture_triggers = {},
        capture_timer    = nil,
    }

    -- ── Placeholder text ──────────────────────────────────────────────────────
    UI.futures_window:cecho(
        "\n<dim_grey>  Click <white>📋 My Contracts<reset><dim_grey> to load your futures portfolio.\n"
    )
    UI.futures_window:cecho(
        "  When at a trading exchange, <white>📈 Market<reset><dim_grey> shows contracts available to buy.\n\n"
    )
    UI.futures_window:cecho(
        "  <white>How futures work:<reset>\n"
    )
    UI.futures_window:cecho(
        "  <dim_grey>• Each contract costs 4,000ig margin deposit.\n"
    )
    UI.futures_window:cecho(
        "  • LONG: profit when price rises above your entry price.\n"
    )
    UI.futures_window:cecho(
        "  • SHORT: profit when price falls below your entry price.\n"
    )
    UI.futures_window:cecho(
        "  • Settled hourly — margin updated based on price movement.\n"
    )
    UI.futures_window:cecho(
        "  • Margin call if margin < 2,000ig (costs 4,000ig to top up).\n"
    )
    UI.futures_window:cecho(
        "  • Liquidate in the exchange where you bought the contract.<reset>\n"
    )
end
