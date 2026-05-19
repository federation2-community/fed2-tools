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

-- Unique widget name counter — prevents Geyser registry collisions on re-show
local _n = 0

-- ── Mark complete and close ───────────────────────────────────────────────────

local function _complete_and_close()
    f2t_settings_set("shared", "first_run_complete", true)
    if UI.welcome_dialog then
        UI.welcome_dialog:hide()
        UI.welcome_dialog = nil
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

    local sw, sh = getMainWindowSize()
    local dw = 560

    -- ── Fixed vertical layout measurements ───────────────────────────────────
    -- Content is a static Label (not a MiniConsole) — sized to show all text
    -- without any scrolling UI. 26 lines × ~14 px/line + 8 px padding ≈ 372 px;
    -- we use 380 to give a comfortable margin.
    local H_HDR  = 44    -- header bar
    local H_DIV  = 1     -- thin divider
    local H_CON  = 380   -- static welcome text label (no scroll)
    local H_FDIV = 1     -- footer divider
    local H_BTN  = 34    -- "Get Started" button
    local H_PAD  = 22    -- bottom padding

    local y_hdr  = 0
    local y_div1 = H_HDR
    local y_con  = y_div1 + H_DIV + 8
    local y_sec  = y_con  + H_CON + 6
    -- Map section height comes from ui_map_import_dialog.lua
    local y_fdiv = y_sec  + UI_MAP_IMPORT_SECTION_H + 6
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

    -- ── Map import section ────────────────────────────────────────────────────
    ui_map_import_build_section(_in, n, "f2t_wlc_mi_", y_sec, {
        title = "  Optional: Load Map Data",
    })

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
