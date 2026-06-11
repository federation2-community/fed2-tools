UI = UI or {}

-- Batch overlay state changes — delegates to the TabWindow class methods which
-- iterate Adjustable.TabWindow.allTabs so floating/rearranged tabs are included.
function ui_tab_overlay_disconnect_all()
    Adjustable.TabWindow.showAllWindowOverlays("offline")
end

function ui_tab_overlay_connect_all()
    Adjustable.TabWindow.showAllWindowOverlays("connecting")
end

function ui_tab_overlay_activate_all()
    Adjustable.TabWindow.hideAllWindowOverlays()
end

-- Per-tab helper used by individual component init code.
function ui_tab_show_overlay(tabname, state)
    local tw = Adjustable.TabWindow.allTabs and Adjustable.TabWindow.allTabs[tabname]
    if tw then tw:showTabOverlay(tabname, state) end
end

function ui_build_tabs()
    -- Build the box to split the right frame in half
    UI.vbox_left = Geyser.VBox:new(
        {
            name   = "UI.vbox_left",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "100%"
        },
        UI.left_frame
    )

    -- Build the box to split the right frame in half
    UI.vbox_right = Geyser.VBox:new(
        {
            name   = "UI.vbox_right",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "100%"
        },
        UI.right_frame
    )

    -- Place Who/General/Exchange tabs In Top Left Navigation Frame (Who is default active)
    UI.tab_top_left = Adjustable.TabWindow:new(
        {
            name             = "UI.tab_left",
            x                = "0%",
            y                = "0%",
            width            = "100%",
            height           = "100%",
            tabBarHeight     = "8%",
            tabs             = {"Who","General","Exchange"},
            activeTabStyle   = UI.style.active_tab_css,
            inactiveTabStyle = UI.style.inactive_tab_css,
            notifyTabStyle   = UI.style.notify_inactive_tab_css,
            footerStyle      = UI.style.footer_css,
            centerStyle      = UI.style.center_css,
            tabOverlays      = {
                Who = {
                    offline_sub    = "connect to see who's online",
                    connecting_sub = "waiting for player data…",
                    geometry       = { y = "21px", height = "100%-21px" },
                },
                General = {
                    offline_sub    = "connect to receive game output",
                    connecting_sub = "connecting to game server…",
                },
                Exchange = {
                    offline_sub    = "visit an exchange while connected to view market data",
                    connecting_sub = "loading exchange data…",
                },
            },
        },
        UI.vbox_left
    )

    -- Place Chat tab on the top of the Bottom Left Navigation Frame (default location)
    UI.tab_bottom_left = Adjustable.TabWindow:new(
        {
            name             = "UI.tab_bottom_left",
            x                = "0%",
            y                = "0%",
            width            = "100%",
            height           = "100%",
            tabBarHeight     = "8%",
            tabs             = {"Chat"},
            activeTabStyle   = UI.style.active_tab_css,
            inactiveTabStyle = UI.style.inactive_tab_css,
            notifyTabStyle   = UI.style.notify_inactive_tab_css,
            footerStyle      = UI.style.footer_css,
            centerStyle      = UI.style.center_css,
        },
        UI.vbox_left
    )

    -- Place Map/Comms tabs on the top of the Right Navigation Frame (default location)
    UI.tab_top_right = Adjustable.TabWindow:new(
        {
            name             = "UI.tab_top_right",
            x                = "0%",
            y                = "0%",
            width            = "100%",
            height           = "100%",
            tabBarHeight     = "8%",
            tabs             = {"Map"},
            activeTabStyle   = UI.style.active_tab_css,
            inactiveTabStyle = UI.style.inactive_tab_css,
            notifyTabStyle   = UI.style.notify_inactive_tab_css,
            footerStyle      = UI.style.footer_css,
            centerStyle      = UI.style.center_css,
            tabOverlays      = {
                Map = {
                    offline_sub    = "connect to enable live auto-mapping",
                    connecting_sub = "loading map data…",
                },
            },
        },
        UI.vbox_right
    )

    -- Place Hauling/Trading/Company tabs on the bottom of the Right Navigation Frame (default location)
    -- Visibility of each tab is managed by ui_update_for_rank() in ui_zLast.lua.
    UI.tab_bottom_right = Adjustable.TabWindow:new(
        {
            name             = "UI.tab_bottom_right",
            x                = "0%",
            y                = "0%",
            width            = "100%",
            height           = "100%",
            tabBarHeight     = "8%",
            tabs             = {"Hauling","Trading","Company","Futures"},
            activeTabStyle   = UI.style.active_tab_css,
            inactiveTabStyle = UI.style.inactive_tab_css,
            notifyTabStyle   = UI.style.notify_inactive_tab_css,
            footerStyle      = UI.style.footer_css,
            centerStyle      = UI.style.center_css,
            tabOverlays      = {
                Hauling = {
                    offline_sub    = "connect to have access to jobs",
                    connecting_sub = "loading haul data…",
                },
                Trading = {
                    offline_sub    = "connect to trade commodities",
                    connecting_sub = "loading trade data…",
                },
                Company = {
                    offline_sub    = "connect to manage your company",
                    connecting_sub = "loading company data…",
                },
                Futures = {
                    offline_sub    = "connect to view futures markets",
                    connecting_sub = "loading futures data…",
                },
            },
        },
        UI.vbox_right
    )
end

-- Restore tab layout from the previous session.
-- save() and load() are class-level operations: they iterate Adjustable.TabWindow.all
-- and save/restore every window's tab assignments, active tab, and floating state
-- (including the position and size of any independently-floated windows).
-- On first run the save file won't exist and load() silently returns, leaving
-- tabs in their default positions.
function ui_load_tab_layout()
    Adjustable.TabWindow:load()
end

-- Reset tab layout to factory defaults and apply immediately.
-- Clears the TabWindowTabs save file (and any floating-tab position saves in the
-- same directory), writes the constructor-default assignments, then calls load()
-- to restore the layout in the running session without a package reload.
function ui_reset_tab_layout()
    local dir = getMudletHomeDir() .. "/AdjustableTabWindow/"

    if io.exists(dir) then
        for file in lfs.dir(dir) do
            if file ~= "." and file ~= ".." and file:sub(-4) == ".lua" then
                os.remove(dir .. file)
            end
        end
    else
        lfs.mkdir(dir)
    end

    -- Write factory defaults in the format load() expects.
    local factory = {}
    factory["UI.tab_left"]         = { tabs = {"Who","General","Exchange"},              current = "Who",     temporary = false }
    factory["UI.tab_bottom_left"]  = { tabs = {"Chat"},                                 current = "Chat",    temporary = false }
    factory["UI.tab_top_right"]    = { tabs = {"Map"},                                  current = "Map",     temporary = false }
    factory["UI.tab_bottom_right"] = { tabs = {"Hauling","Trading","Company","Futures"}, current = "Hauling", temporary = false }
    table.save(dir .. "TabWindowTabs.lua", factory)

    Adjustable.TabWindow:load()

    cecho("\n<green>[ui]<reset> Tab layout reset to factory defaults.\n")
end

-- Call ui_tab_notify("TabName") whenever content is added to a tab to show the
-- red-border indicator on that tab if it is not currently active.
-- The indicator is automatically cleared when the user switches to the tab.
-- Uses Adjustable.TabWindow.allTabs (the live tracker) so this works correctly
-- even after the user drags a tab to a different frame or floats it.
function ui_tab_notify(tab_name)
    local tab_window = Adjustable.TabWindow.allTabs and Adjustable.TabWindow.allTabs[tab_name]

    if not tab_window then return end

    tab_window:notify(tab_name)
end

function ui_tab_clear_notify(tab_name)
    local tab_window = Adjustable.TabWindow.allTabs and Adjustable.TabWindow.allTabs[tab_name]

    if not tab_window then return end

    tab_window:clearNotification(tab_name)
end

-- populate our various tabs
function ui_build_tab_content()
    local text_size = 12

    --put general console in general tab
    UI.general_window = Geyser.MiniConsole:new(
        {
            name      = "UI.general_window",
            x         = "0%",
            y         = "0%",
            width     = "100%",
            height    = "100%",
            autoWrap  = true,
            scrollBar = true,
            fontSize  = text_size,
            color     = "black",
        },
        UI.tab_top_left.Generalcenter
    )

    -- ── General tab filter button ─────────────────────────────────────────
    UI.general_filter_btn = Geyser.Label:new(
        {
            name   = "UI.general_filter_btn",
            x      = "-22",
            y      = "2",
            width  = "20",
            height = "16",
        },
        UI.tab_top_left.Generalcenter
    )
    UI.general_filter_btn:setStyleSheet(
        [[
            QLabel{
                background-color:rgba(28,28,32,200);
                border-style:solid;
                border-width:1px;
                border-radius:3px;
                border-color:rgba(100,100,110,180);
                color:rgba(160,160,170,255);
                font-size:10px;
                font-weight:bold;
            }
            QLabel::hover{
                background-color:rgba(60,60,70,220);
                color:white;
            }
        ]]
    )
    UI.general_filter_btn:echo("<center>A</center>")
    UI.general_filter_btn:setToolTip("Show all")
    UI.general_filter_btn:setClickCallback(function() ui_general_cycle_filter() end)

    -- Exchange tab: market futures panel (Trader/Financier at exchange) + ticker strip.
    -- Market panel: 18px info header + 18px col-bar + scrollbox filling remainder above ticker.
    -- Ticker: 56px fixed at bottom, always visible while at exchange.
    -- 36px top chrome + 56px ticker = 92px total; scrollbox fills 100%-92px.
    UI.exchange_market_hdr = Geyser.Label:new(
        {
            name   = "UI.exchange_market_hdr",
            x      = "0%",
            y      = "0px",
            width  = "100%",
            height = "18px",
        },
        UI.tab_top_left.Exchangecenter
    )
    UI.exchange_market_hdr:setStyleSheet("background-color:rgba(10,12,22,240); border:none;")

    UI.exchange_market_col_bar = Geyser.Label:new(
        {
            name   = "UI.exchange_market_col_bar",
            x      = "0%",
            y      = "18px",
            width  = "100%",
            height = "18px",
        },
        UI.tab_top_left.Exchangecenter
    )
    UI.exchange_market_col_bar:setStyleSheet(
        "background-color:rgba(20,22,38,210); border:none; border-bottom:1px solid rgba(255,255,255,0.18);"
    )

    -- 36px top chrome + 1px sep + 20px ticker col-header + 80px ticker = 137px total reserved.
    UI.exchange_market_scroll = Geyser.ScrollBox:new(
        {
            name   = "UI.exchange_market_scroll",
            x      = "0%",
            y      = "36px",
            width  = "100%",
            height = "100%-137px",
        },
        UI.tab_top_left.Exchangecenter
    )

    local exmkt_cw = math.max(50, UI.exchange_market_scroll:get_width() - 17)
    UI.exchange_market_content = Geyser.Label:new(
        {
            name   = "UI.exchange_market_content",
            x      = 0,
            y      = 0,
            width  = exmkt_cw,
            height = 2000,
        },
        UI.exchange_market_scroll
    )
    UI.exchange_market_content:setStyleSheet("background-color:rgb(10,10,16); border:none;")

    -- 1px separator above the ticker column-header bar.
    UI.exchange_ticker_sep = Geyser.Label:new(
        {
            name   = "UI.exchange_ticker_sep",
            x      = "0%",
            y      = "-101",
            width  = "100%",
            height = "1px",
        },
        UI.tab_top_left.Exchangecenter
    )
    UI.exchange_ticker_sep:setStyleSheet(
        "background-color:rgba(255,255,255,0.08); border:none;"
    )

    -- Fixed column-header bar pinned just above the ticker.
    -- Must be a MiniConsole (not a Label) so it shares the same character-grid renderer
    -- as the ticker below and column text aligns correctly.
    -- 20px = enough height for one line of text at the ticker's font size.
    UI.exchange_ticker_hdr = Geyser.MiniConsole:new(
        {
            name      = "UI.exchange_ticker_hdr",
            x         = "0%",
            y         = "-100",
            width     = "100%",
            height    = "20px",
            fontSize  = text_size,
            scrollBar = false,
            color     = "black",
        },
        UI.tab_top_left.Exchangecenter
    )
    UI.exchange_ticker_hdr:setBgColor(20, 22, 38)

    UI.exchange_ticker = Geyser.MiniConsole:new(
        {
            name      = "UI.exchange_ticker",
            x         = "0%",
            y         = "-80",
            width     = "100%",
            height    = "80px",
            fontSize  = text_size,
            scrollBar = false,
            color     = "black",
        },
        UI.tab_top_left.Exchangecenter
    )
    UI.exchange_ticker:setBgColor(8, 10, 18)

    --put chat console in chat tab
    UI.chat_window = Geyser.MiniConsole:new(
        {
            name      = "UI.chat_window",
            x         = "0%",
            y         = "0%",
            width     = "100%",
            height    = "100%",
            autoWrap  = true,
            scrollBar = true,
            fontSize  = text_size,
            color     = "black",
        },
        UI.tab_bottom_left.Chatcenter
    )

    -- ── Chat tab buttons ──────────────────────────────────────────────────
    -- Filter button (cycles A/C/T/S); sits left of the timestamp button.
    UI.chat_filter_btn = Geyser.Label:new(
        {
            name   = "UI.chat_filter_btn",
            x      = "-44",
            y      = "2",
            width  = "20",
            height = "16",
        },
        UI.tab_bottom_left.Chatcenter
    )
    UI.chat_filter_btn:setStyleSheet(
        [[
            QLabel{
                background-color:rgba(28,28,32,200);
                border-style:solid;
                border-width:1px;
                border-radius:3px;
                border-color:rgba(100,100,110,180);
                color:rgba(160,160,170,255);
                font-size:10px;
                font-weight:bold;
            }
            QLabel::hover{
                background-color:rgba(60,60,70,220);
                color:white;
            }
        ]]
    )
    UI.chat_filter_btn:echo("<center>A</center>")
    UI.chat_filter_btn:setToolTip("Show all messages")
    UI.chat_filter_btn:setClickCallback(function() ui_chat_cycle_filter() end)

    -- Timestamp toggle button.
    UI.chat_ts_btn = Geyser.Label:new(
        {
            name   = "UI.chat_ts_btn",
            x      = "-22",
            y      = "2",
            width  = "20",
            height = "16",
        },
        UI.tab_bottom_left.Chatcenter
    )
    UI.chat_ts_btn:echo("<center><font color='#3a3a3a'>⏱</font></center>")
    UI.chat_ts_btn:setStyleSheet(UI.style.button_css)
    UI.chat_ts_btn:setToolTip("Timestamps OFF — click to toggle")
    UI.chat_ts_btn:setClickCallback(function() ui_chat_toggle_timestamps() end)

    -- ── Who tab ───────────────────────────────────────────────────────────
    -- Header leaves 44px on the right for the Online/All toggle button.
    UI.who_header = Geyser.Label:new(
        {
            name   = "UI.who_header",
            x      = "0%",
            y      = "0",
            width  = "-46",
            height = "20",
        },
        UI.tab_top_left.Whocenter
    )
    UI.who_header:setStyleSheet(UI.style.header_label_css)
    UI.who_header:echo("  👥  Who's Online")

    -- Online / All toggle button
    UI.who_toggle_btn = Geyser.Label:new(
        {
            name   = "UI.who_toggle_btn",
            x      = "-44",
            y      = "2",
            width  = "42",
            height = "16",
        },
        UI.tab_top_left.Whocenter
    )
    UI.who_toggle_btn:setStyleSheet(
        [[
            QLabel{
                background-color:rgba(28,28,32,200);
                border-style:solid;
                border-width:1px;
                border-radius:3px;
                border-color:rgba(100,100,110,180);
                color:rgba(160,160,170,255);
                font-size:9px;
                font-weight:bold;
            }
            QLabel::hover{
                background-color:rgba(60,60,70,220);
                color:white;
            }
        ]]
    )
    UI.who_toggle_btn:echo("<center>Online</center>")
    UI.who_toggle_btn:setToolTip("Toggle Online / All known players")
    UI.who_toggle_btn:setClickCallback(function() ui_who_toggle_view() end)

    -- Fixed column-header bar (below 21px title strip, above scrollable rows)
    UI.who_col_bar = Geyser.Label:new(
        {
            name   = "UI.who_col_bar",
            x      = "0%",
            y      = "21px",
            width  = "100%",
            height = "18px",
        },
        UI.tab_top_left.Whocenter
    )
    UI.who_col_bar:setStyleSheet("background-color:rgba(20,22,38,210); border:none; border-bottom:1px solid rgba(255,255,255,0.18);")

    -- Scrollable player-row area (39px = 21px title + 18px col-header bar)
    UI.who_scroll = Geyser.ScrollBox:new(
        {
            name   = "UI.who_scroll",
            x      = "0%",
            y      = "39px",
            width  = "100%",
            height = "100%-39px",
        },
        UI.tab_top_left.Whocenter
    )

    -- Permanent content label: never destroyed, only resized on each render.
    -- Qt preserves the QScrollArea scroll offset as long as the same child widget
    -- stays in place — this is how the who list avoids the scroll-reset problem.
    local who_cw = math.max(50, UI.who_scroll:get_width() - 17)

    UI.who_content_w      = who_cw
    UI.who_scroll_content = Geyser.Label:new(
        {
            name   = "who_main_content",
            x      = 0,
            y      = 0,
            width  = who_cw,
            height = 2000,
        },
        UI.who_scroll
    )
    UI.who_scroll_content:setStyleSheet("background-color:rgb(10,10,16); border:none;")

    -- "fedmap" is the Mudlet map widget name (must match the Mapper name); "Map" is the tab name.
    UI.mapper = Geyser.Mapper:new(
        {
            name   = "fedmap",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "100%",
        },
        UI.tab_top_right.Mapcenter
    )

    -- Legend info button — bottom-right corner of the map.
    UI.map_legend_btn = Geyser.Label:new(
        {
            name   = "UI.map_legend_btn",
            x      = "-26",
            y      = "-26",
            width  = "24",
            height = "24",
        },
        UI.tab_top_right.Mapcenter
    )
    UI.map_legend_btn:setStyleSheet(UI.style.map_legend_btn_css)
    UI.map_legend_btn:echo("<center>ℹ</center>")
    UI.map_legend_btn:setToolTip("Map room type legend")
    UI.map_legend_btn:setClickCallback(function() ui_map_legend_toggle() end)

    --put hauling container in hauling tab
    UI.hauling_container = Geyser.Container:new(
        {
            name   = "UI.hauling_container",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "100%",
        },
        UI.tab_bottom_right.Haulingcenter
    )

    -- Button bar at top
    UI.hauling_button_bar = Geyser.HBox:new(
        {
            name   = "UI.hauling_button_bar",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "25px",
        },
        UI.hauling_container
    )

    UI.hauling_window = Geyser.MiniConsole:new(
        {
            name      = "UI.hauling_window",
            x         = "0%",
            y         = "25px",
            width     = "100%",
            height    = "100%-25px",
            autoWrap  = true,
            scrollBar = true,
            fontSize  = 12,
            color     = "black",
        },
        UI.hauling_container
    )

    --put trading container in trading tab
    UI.trading_container = Geyser.Container:new(
        {
            name   = "UI.trading_container",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "100%",
        },
        UI.tab_bottom_right.Tradingcenter
    )

    -- Button bar at top
    UI.trading_button_bar = Geyser.HBox:new(
        {
            name   = "UI.trading_button_bar",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "25px",
        },
        UI.trading_container
    )

    UI.trading_window = Geyser.MiniConsole:new(
        {
            name      = "UI.trading_window",
            x         = "0%",
            y         = "25px",
            width     = "100%",
            height    = "100%-25px",
            autoWrap  = true,
            scrollBar = true,
            fontSize  = 12,
            color     = "black",
        },
        UI.trading_container
    )

    -- Owned futures tab (from gmcp.char.futures): 18px header + 18px col-bar + scrollbox.
    -- Tab visibility is managed by ui_futures_on_gmcp_char_futures() — appears only when
    -- the player holds at least one futures contract; disappears when all are closed.
    UI.futures_hdr = Geyser.Label:new(
        {
            name   = "UI.futures_hdr",
            x      = "0%",
            y      = "0px",
            width  = "100%",
            height = "18px",
        },
        UI.tab_bottom_right.Futurescenter
    )
    UI.futures_hdr:setStyleSheet("background-color:rgba(10,12,22,240); border:none;")

    UI.futures_col_bar = Geyser.Label:new(
        {
            name   = "UI.futures_col_bar",
            x      = "0%",
            y      = "18px",
            width  = "100%",
            height = "18px",
        },
        UI.tab_bottom_right.Futurescenter
    )
    UI.futures_col_bar:setStyleSheet(
        "background-color:rgba(20,22,38,210); border:none; border-bottom:1px solid rgba(255,255,255,0.18);"
    )

    -- 36px = 18px header + 18px col-bar
    UI.futures_scroll = Geyser.ScrollBox:new(
        {
            name   = "UI.futures_scroll",
            x      = "0%",
            y      = "36px",
            width  = "100%",
            height = "100%-36px",
        },
        UI.tab_bottom_right.Futurescenter
    )

    local fut_own_cw = math.max(50, UI.futures_scroll:get_width() - 17)
    UI.futures_content = Geyser.Label:new(
        {
            name   = "UI.futures_content",
            x      = 0,
            y      = 0,
            width  = fut_own_cw,
            height = 2000,
        },
        UI.futures_scroll
    )
    UI.futures_content:setStyleSheet("background-color:rgb(10,10,16); border:none;")

end