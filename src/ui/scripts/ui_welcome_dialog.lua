-- =============================================================================
-- FIRST-RUN WELCOME DIALOG
-- Shown once on first install. Blocks the startup update check until dismissed.
-- Offers optional map database import without requiring console commands.
-- =============================================================================

UI = UI or {}

-- ── CSS constants (match ui_update_dialog.lua palette) ───────────────────────

local _FRAME_CSS = [[
    background-color: rgba(10, 12, 22, 254);
    border: 2px solid rgba(255, 255, 255, 0.42);
    border-radius: 6px;
]]
local _CSS_HDR = [[
    background: qlineargradient(x1:0,y1:0,x2:0,y2:1,
        stop:0 rgba(44,50,78,255), stop:1 rgba(22,26,44,255));
    color: rgba(220,230,255,255);
    font-size: 15px; font-weight: bold;
    font-family: "Consolas","Monaco",monospace;
    border-radius: 4px 4px 0 0;
    border-bottom: 1px solid rgba(255,255,255,0.16);
    padding: 0 12px;
]]
local _CSS_CON = [[
    background: transparent;
    color: rgba(198,210,238,255);
    font-size: 10px;
    font-family: "Consolas","Monaco",monospace;
    padding: 4px 14px;
]]
local _CSS_SEC = [[
    background: qlineargradient(x1:0,y1:0,x2:0,y2:1,
        stop:0 rgba(38,44,68,200), stop:1 rgba(22,26,44,200));
    color: rgba(160,180,230,255);
    font-size: 12px; font-weight: bold;
    font-family: "Consolas","Monaco",monospace;
    border-top: 1px solid rgba(255,255,255,0.10);
    border-bottom: 1px solid rgba(255,255,255,0.06);
    padding: 0 12px;
]]
local _CSS_SUB = [[
    background: transparent;
    color: rgba(105,125,180,255);
    font-size: 11px;
    font-family: "Consolas","Monaco",monospace;
    padding: 0 14px;
]]
local _CSS_OK = [[
    QLabel {
        background-color: rgba(18,58,34,240);
        color: rgba(115,222,148,255);
        border: 1px solid rgba(48,152,78,215);
        border-radius: 5px;
        font-size: 12px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(26,82,46,255);
        border-color: rgba(65,210,108,235);
        color: rgba(178,255,200,255);
    }
]]
local _CSS_IMPORT = [[
    QLabel {
        background-color: rgba(28,48,78,230);
        color: rgba(120,180,255,255);
        border: 1px solid rgba(68,118,200,210);
        border-radius: 5px;
        font-size: 12px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(38,68,108,245);
        border-color: rgba(100,158,255,240);
        color: white;
    }
]]
local _CSS_IMPORT_DONE = [[
    QLabel {
        background-color: rgba(18,38,28,220);
        color: rgba(100,180,120,200);
        border: 1px solid rgba(48,120,68,160);
        border-radius: 5px;
        font-size: 12px;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
]]
local _CSS_OPT_OFF = [[
    QLabel {
        background-color: rgba(28,32,50,210);
        color: rgba(150,165,205,255);
        border: 1px solid rgba(72,85,128,180);
        border-radius: 4px;
        font-size: 11px;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 10px;
    }
    QLabel::hover {
        background-color: rgba(42,48,78,230);
        border-color: rgba(105,138,220,200);
        color: rgba(200,215,255,255);
    }
]]
local _CSS_OPT_ON = [[
    QLabel {
        background-color: rgba(20,50,36,240);
        color: rgba(115,222,148,255);
        border: 2px solid rgba(52,160,86,220);
        border-radius: 4px;
        font-size: 11px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 10px;
    }
]]
-- Applied to all options after a successful import: no hover, clearly committed
local _CSS_OPT_FROZEN_SEL = [[
    QLabel {
        background-color: rgba(20,46,32,200);
        color: rgba(100,175,120,195);
        border: 2px solid rgba(50,140,75,155);
        border-radius: 4px;
        font-size: 11px;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 10px;
    }
]]
local _CSS_OPT_FROZEN_OFF = [[
    QLabel {
        background-color: rgba(22,24,36,140);
        color: rgba(80,90,118,180);
        border: 1px solid rgba(48,54,78,130);
        border-radius: 4px;
        font-size: 11px;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 10px;
    }
]]
local _CSS_STATUS_INFO = [[
    background: transparent;
    color: rgba(105,125,180,255);
    font-size: 11px;
    font-family: "Consolas","Monaco",monospace;
    padding: 0 14px;
]]
local _CSS_STATUS_OK = [[
    background: transparent;
    color: rgba(115,222,148,255);
    font-size: 11px;
    font-family: "Consolas","Monaco",monospace;
    padding: 0 14px;
]]
local _CSS_STATUS_ERR = [[
    background: transparent;
    color: rgba(210,120,115,255);
    font-size: 11px;
    font-family: "Consolas","Monaco",monospace;
    padding: 0 14px;
]]
local _CSS_XBTN = [[
    QLabel {
        background-color: transparent;
        color: rgba(200,210,240,160);
        font-size: 17px; font-weight: bold;
        border-radius: 3px;
    }
    QLabel::hover {
        background-color: rgba(200,50,50,200);
        color: white;
    }
]]

-- ── Welcome text (HTML, explicit <br> for every line break) ──────────────────
-- Font is monospace 10px, usable width ~500px (~83 chars). No line exceeds that.

local _WELCOME_HTML =
    "<font color='#c6d2ee'>" ..
        "This is a living toolkit for Federation 2 that grows alongside you.<br>" ..
        "Each component is independent &mdash; use what suits your playstyle." ..
    "</font><br><br>" ..

    "<font color='#73de94'><b>INTERFACE</b></font><br>" ..
    "<font color='#c6d2ee'>" ..
        "The UI panels are draggable. Rearrange and resize the tabs and frames<br>" ..
        "to fit your screen. Positions are saved between sessions." ..
    "</font><br><br>" ..

    "<font color='#73de94'><b>RANK-DEPENDENT FEATURES</b></font><br>" ..
    "<font color='#c6d2ee'>" ..
        "What you see largely depends on your rank. Fed2 has 16 ranks &mdash; new<br>" ..
        "tools and automations unlock as you advance through them." ..
    "</font><br><br>" ..

    "<font color='#73de94'><b>COMPONENTS</b></font><br>" ..
    "<font color='#7ab4ff'>Map</font>" ..
        "<font color='#c6d2ee'> &mdash; Auto-mapper, speedwalk navigation, galaxy explorer</font><br>" ..
    "<font color='#7ab4ff'>Hauling</font>" ..
        "<font color='#c6d2ee'> &mdash; Rank-aware commodity trading automation</font><br>" ..
    "<font color='#7ab4ff'>Factory</font>" ..
        "<font color='#c6d2ee'> &mdash; Monitor all factory statuses at a glance</font><br>" ..
    "<font color='#7ab4ff'>Commodities</font>" ..
        "<font color='#c6d2ee'> &mdash; Price analysis and bulk buy/sell tools</font><br>" ..
    "<font color='#7ab4ff'>Refuel</font>" ..
        "<font color='#c6d2ee'> &mdash; Automatic ship refueling</font><br><br>" ..

    "<font color='#73de94'><b>SETTINGS</b></font><br>" ..
    "<font color='#c6d2ee'>Each component has its own settings command:</font><br>" ..
    "<font color='#7ab4ff'>map settings &nbsp; haul settings &nbsp; refuel settings</font><br>" ..
    "<font color='#c6d2ee'>For system-wide settings (debug, stamina monitoring, etc.):</font><br>" ..
    "<font color='#7ab4ff'>f2t settings</font><br><br>" ..

    "<font color='#73de94'><b>REPORT ISSUES / REQUEST FEATURES</b></font><br>" ..
    "<font color='#697db4'>github.com/tmtocloud/fed2-tools/issues</font>"

-- ── Map database options ──────────────────────────────────────────────────────

local _MAP_OPTIONS = {
    {
        file  = "galaxy_brief.json",
        label = "  --  Whole Galaxy  (Recommended)  --  ~4,500 rooms",
    },
    {
        file  = "starter_map_with_exchanges.json",
        label = "  --  Starter Map with Exchanges  --  ~280 rooms",
    },
    {
        file  = "starter_map.json",
        label = "  --  Starter Map  (Basic)  --  ~250 rooms",
    },
}

-- Unique widget name counter — prevents Geyser registry collisions on re-show
local _n = 0

-- ── Mark complete and close ───────────────────────────────────────────────────

local function _complete_and_close()
    f2t_settings_set("shared", "first_run_complete", true)
    if UI.welcome_dialog then
        UI.welcome_dialog:hide()
        UI.welcome_dialog     = nil
        UI.welcome_map_btns   = nil
        UI.welcome_status_lbl = nil
        UI.welcome_imp_btn    = nil
    end
end

-- ── Silent map import (no file dialog, no confirmation prompt) ───────────────

local function _import_map(file_path, status_lbl, imp_btn)
    local file = io.open(file_path, "r")
    if not file then
        if status_lbl then
            status_lbl:setStyleSheet(_CSS_STATUS_ERR)
            status_lbl:echo("  Map file not found -- was the package installed via MPR?")
        end
        f2t_debug_log("[welcome] Map import failed: file not found: %s", file_path)
        return false
    end
    file:close()

    deleteMap()
    F2T_MAP_CURRENT_ROOM_ID = nil

    local success, err_msg = loadJsonMap(file_path)

    if success then
        updateMap()

        local rooms_after = 0
        for _ in pairs(getRooms()) do rooms_after = rooms_after + 1 end

        tempTimer(0.5, function()
            if F2T_MAP_ENABLED and f2t_map_sync then f2t_map_sync() end
        end)

        if status_lbl then
            status_lbl:setStyleSheet(_CSS_STATUS_OK)
            status_lbl:echo(string.format(
                "  Map imported -- %d rooms loaded", rooms_after))
        end
        if imp_btn then
            imp_btn:setStyleSheet(_CSS_IMPORT_DONE)
            imp_btn:echo("<center>Map Imported</center>")
        end

        cecho(string.format(
            "\n<green>[fed2-tools]<reset> Welcome setup: map imported -- %d rooms\n",
            rooms_after))
        f2t_debug_log("[welcome] Map import OK: %d rooms", rooms_after)
        return true
    else
        if status_lbl then
            status_lbl:setStyleSheet(_CSS_STATUS_ERR)
            status_lbl:echo(string.format(
                "  Import failed: %s", err_msg or "unknown error"))
        end
        f2t_debug_log("[welcome] Map import failed: %s", err_msg or "unknown error")
        return false
    end
end

-- ── Public entry point ────────────────────────────────────────────────────────

function ui_welcome_show_dialog()
    if UI.welcome_dialog then
        UI.welcome_dialog:hide()
        UI.welcome_dialog = nil
    end

    _n = _n + 1
    local n = _n

    local _sel         = 1      -- default: Whole Galaxy
    local _import_done = false

    local sw, sh = getMainWindowSize()
    local dw = 560

    -- ── Fixed vertical layout measurements ───────────────────────────────────
    -- Content is a static Label (not a MiniConsole) — sized to show all text
    -- without any scrolling UI. 26 lines × ~14 px/line + 8 px padding ≈ 372 px;
    -- we use 380 to give a comfortable margin.
    local H_HDR  = 44    -- header bar
    local H_DIV  = 1     -- thin divider
    local H_CON  = 380   -- static welcome text label (no scroll)
    local H_SEC  = 28    -- "Optional: Load Map Data" bar
    local H_DESC = 20    -- sub-description text
    local H_OPT  = 30    -- each map option button
    local H_GAP  = 4     -- gap between option buttons
    local H_IMP  = 34    -- "Import Selected Map" button
    local H_STAT = 22    -- import status label
    local H_FDIV = 1     -- footer divider
    local H_BTN  = 34    -- "Get Started" button
    local H_PAD  = 22    -- bottom padding — enough breathing room below button

    local y_hdr  = 0
    local y_div1 = H_HDR
    local y_con  = y_div1 + H_DIV + 8
    local y_sec  = y_con  + H_CON + 6
    local y_desc = y_sec  + H_SEC + 2
    local y_opt1 = y_desc + H_DESC + 6
    local y_opt2 = y_opt1 + H_OPT + H_GAP
    local y_opt3 = y_opt2 + H_OPT + H_GAP
    local y_imp  = y_opt3 + H_OPT + 10
    local y_stat = y_imp  + H_IMP + 4
    local y_fdiv = y_stat + H_STAT + 6
    local y_btn  = y_fdiv + H_FDIV + 10
    local dh     = y_btn  + H_BTN  + H_PAD

    local cx = math.floor((sw - dw) / 2)
    local cy = math.floor((sh - dh) / 2)

    -- ── Adjustable container ──────────────────────────────────────────────────
    UI.welcome_dialog = Adjustable.Container:new({
        name          = "f2t_wlc_ac_" .. n,
        x             = cx, y = cy,
        width         = dw, height = dh,
        adjLabelstyle = _FRAME_CSS,
        autoSave      = false,
        autoLoad      = false,
    })
    UI.welcome_dialog:lockContainer("border")
    UI.welcome_dialog.locked = false   -- keep draggable

    local _in = UI.welcome_dialog.Inside

    -- ── Header ────────────────────────────────────────────────────────────────
    local hdr = Geyser.Label:new({
        name   = "f2t_wlc_hdr_" .. n,
        x = 0, y = y_hdr, width = "100%", height = H_HDR,
    }, _in)
    hdr:setStyleSheet(_CSS_HDR)
    hdr:echo("Welcome to fed2-tools!")

    local xbtn = Geyser.Label:new({
        name   = "f2t_wlc_xbtn_" .. n,
        x = "92%", y = 8, width = 30, height = 28,
    }, _in)
    xbtn:setStyleSheet(_CSS_XBTN)
    xbtn:echo("<center>x</center>")
    xbtn:setClickCallback(_complete_and_close)

    -- ── Top divider ───────────────────────────────────────────────────────────
    local div1 = Geyser.Label:new({
        name   = "f2t_wlc_div1_" .. n,
        x = 0, y = y_div1, width = "100%", height = H_DIV,
    }, _in)
    div1:setStyleSheet("background-color: rgba(255,255,255,0.10); border:none;")

    -- ── Welcome text — static label, no scrollbar ─────────────────────────────
    local con = Geyser.Label:new({
        name   = "f2t_wlc_con_" .. n,
        x = "2%", y = y_con,
        width  = "96%", height = H_CON,
    }, _in)
    con:setStyleSheet(_CSS_CON)
    con:echo(_WELCOME_HTML)

    -- ── Map section header ────────────────────────────────────────────────────
    local sec = Geyser.Label:new({
        name   = "f2t_wlc_sec_" .. n,
        x = 0, y = y_sec, width = "100%", height = H_SEC,
    }, _in)
    sec:setStyleSheet(_CSS_SEC)
    sec:echo("  Optional: Load Map Data")

    local desc = Geyser.Label:new({
        name   = "f2t_wlc_desc_" .. n,
        x = 0, y = y_desc, width = "100%", height = H_DESC,
    }, _in)
    desc:setStyleSheet(_CSS_SUB)
    desc:echo("  Install a map database to jumpstart navigation (you can skip this):")

    -- ── Map option selector buttons ───────────────────────────────────────────
    UI.welcome_map_btns = {}

    local opt_ys = { y_opt1, y_opt2, y_opt3 }

    local function _refresh_btn_styles()
        for i, btn in ipairs(UI.welcome_map_btns) do
            btn:setStyleSheet(i == _sel and _CSS_OPT_ON or _CSS_OPT_OFF)
        end
    end

    -- Freeze all option buttons after a successful import so the UI communicates
    -- that the choice is committed and clicking again has no effect.
    local function _freeze_map_options()
        for i, btn in ipairs(UI.welcome_map_btns or {}) do
            btn:setStyleSheet(i == _sel and _CSS_OPT_FROZEN_SEL or _CSS_OPT_FROZEN_OFF)
            btn:setClickCallback(function() end)
        end
    end

    for i, opt in ipairs(_MAP_OPTIONS) do
        local btn = Geyser.Label:new({
            name   = string.format("f2t_wlc_opt%d_%d", i, n),
            x = "3%", y = opt_ys[i], width = "94%", height = H_OPT,
        }, _in)
        btn:echo(opt.label)
        table.insert(UI.welcome_map_btns, btn)

        local idx = i
        btn:setClickCallback(function()
            if _import_done then return end
            _sel = idx
            _refresh_btn_styles()
        end)
    end

    _refresh_btn_styles()

    -- ── Import button ─────────────────────────────────────────────────────────
    UI.welcome_imp_btn = Geyser.Label:new({
        name   = "f2t_wlc_imp_" .. n,
        x = "3%", y = y_imp, width = "94%", height = H_IMP,
    }, _in)
    UI.welcome_imp_btn:setStyleSheet(_CSS_IMPORT)
    UI.welcome_imp_btn:echo("<center>Import Selected Map</center>")

    -- ── Status label ──────────────────────────────────────────────────────────
    UI.welcome_status_lbl = Geyser.Label:new({
        name   = "f2t_wlc_stat_" .. n,
        x = 0, y = y_stat, width = "100%", height = H_STAT,
    }, _in)
    UI.welcome_status_lbl:setStyleSheet(_CSS_STATUS_INFO)
    UI.welcome_status_lbl:echo("")

    -- Import callback — defined after status label so it can close over both
    UI.welcome_imp_btn:setClickCallback(function()
        if _import_done then return end

        local opt      = _MAP_OPTIONS[_sel]
        local map_path = getMudletHomeDir() .. "/fed2-tools/shared/" .. opt.file

        UI.welcome_status_lbl:setStyleSheet(_CSS_STATUS_INFO)
        UI.welcome_status_lbl:echo("  Importing, please wait...")

        -- Defer one tick so the status text renders before loadJsonMap runs
        tempTimer(0.1, function()
            local ok = _import_map(map_path, UI.welcome_status_lbl, UI.welcome_imp_btn)
            if ok then
                _import_done = true
                _freeze_map_options()
            end
        end)
    end)

    -- ── Footer divider ────────────────────────────────────────────────────────
    local fdiv = Geyser.Label:new({
        name   = "f2t_wlc_fdiv_" .. n,
        x = 0, y = y_fdiv, width = "100%", height = H_FDIV,
    }, _in)
    fdiv:setStyleSheet("background-color: rgba(255,255,255,0.10); border:none;")

    -- ── Get Started button ────────────────────────────────────────────────────
    local btn_start = Geyser.Label:new({
        name   = "f2t_wlc_start_" .. n,
        x = "15%", y = y_btn, width = "70%", height = H_BTN,
    }, _in)
    btn_start:setStyleSheet(_CSS_OK)
    btn_start:echo("<center>Get Started</center>")
    btn_start:setClickCallback(_complete_and_close)

    -- Hide then show immediately (ensures Qt widget parenting is correct)
    UI.welcome_dialog:hide()
    UI.welcome_dialog:show()
    UI.welcome_dialog:raiseAll()
end
