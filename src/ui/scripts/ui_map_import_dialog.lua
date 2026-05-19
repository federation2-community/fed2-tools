-- =============================================================================
-- MAP IMPORT SECTION BUILDER + STANDALONE POST-UPGRADE DIALOG
-- =============================================================================
-- ui_map_import_build_section() is called by ui_welcome_dialog.lua to embed
-- the import UI inside the welcome flow.  ui_map_import_show_dialog() creates
-- a standalone window used when an upgrade includes a map-database update.
-- =============================================================================

UI = UI or {}

-- ── CSS (matches welcome / update dialog palette) ─────────────────────────────

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
local _CSS_BTN = [[
    QLabel {
        background-color: rgba(36,40,62,230);
        color: rgba(178,190,225,255);
        border: 1px solid rgba(85,98,140,210);
        border-radius: 5px;
        font-size: 12px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(52,60,95,245);
        border-color: rgba(105,158,255,210);
        color: white;
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

-- ── Section layout constants ──────────────────────────────────────────────────
-- Exposed as a global so callers can factor the height into their own layouts
-- without duplicating the arithmetic.

local _H_SEC  = 28
local _H_DESC = 20
local _H_OPT  = 30
local _H_OGAP = 4
local _H_IMP  = 34
local _H_STAT = 22

UI_MAP_IMPORT_SECTION_H =
    _H_SEC  + 2 +
    _H_DESC + 6 +
    (_H_OPT + _H_OGAP) * 2 +
    _H_OPT  + 10 +
    _H_IMP  + 4 +
    _H_STAT   -- = 224

-- Unique name counter for the standalone dialog
local _n = 0

-- ── Silent map import ─────────────────────────────────────────────────────────

local function _import_map(file_path, status_lbl, imp_btn)
    local file = io.open(file_path, "r")
    if not file then
        if status_lbl then
            status_lbl:setStyleSheet(_CSS_STATUS_ERR)
            status_lbl:echo("  Map file not found -- was the package installed via MPR?")
        end
        f2t_debug_log("[map-import] Import failed: file not found: %s", file_path)
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
            status_lbl:echo(string.format("  Map imported -- %d rooms loaded", rooms_after))
        end
        if imp_btn then
            imp_btn:setStyleSheet(_CSS_IMPORT_DONE)
            imp_btn:echo("<center>Map Imported</center>")
        end

        cecho(string.format(
            "\n<green>[fed2-tools]<reset> Map imported -- %d rooms\n", rooms_after))
        f2t_debug_log("[map-import] OK: %d rooms", rooms_after)
        return true
    else
        if status_lbl then
            status_lbl:setStyleSheet(_CSS_STATUS_ERR)
            status_lbl:echo(string.format(
                "  Import failed: %s", err_msg or "unknown error"))
        end
        f2t_debug_log("[map-import] Failed: %s", err_msg or "unknown error")
        return false
    end
end

-- ── Map import section builder ────────────────────────────────────────────────
-- Builds the database selector + import button + status label into parent_in
-- starting at y_start.  Returns UI_MAP_IMPORT_SECTION_H.
--
-- opts.title  overrides the section-header text (default "  Load Map Data")

function ui_map_import_build_section(parent_in, n, prefix, y_start, opts)
    opts = opts or {}
    local section_title = opts.title or "  Load Map Data"

    local y_sec  = y_start
    local y_desc = y_sec  + _H_SEC  + 2
    local y_opt1 = y_desc + _H_DESC + 6
    local y_opt2 = y_opt1 + _H_OPT  + _H_OGAP
    local y_opt3 = y_opt2 + _H_OPT  + _H_OGAP
    local y_imp  = y_opt3 + _H_OPT  + 10
    local y_stat = y_imp  + _H_IMP  + 4

    local _sel         = 1
    local _import_done = false
    local map_btns     = {}

    -- Section header
    local sec = Geyser.Label:new({
        name   = prefix .. "sec_" .. n,
        x = 0, y = y_sec, width = "100%", height = _H_SEC,
    }, parent_in)
    sec:setStyleSheet(_CSS_SEC)
    sec:echo(section_title)

    -- Description
    local desc = Geyser.Label:new({
        name   = prefix .. "desc_" .. n,
        x = 0, y = y_desc, width = "100%", height = _H_DESC,
    }, parent_in)
    desc:setStyleSheet(_CSS_SUB)
    desc:echo("  Install a map database to jumpstart navigation (you can skip this):")

    -- Option buttons
    local opt_ys = { y_opt1, y_opt2, y_opt3 }

    local function _refresh_btn_styles()
        for i, btn in ipairs(map_btns) do
            btn:setStyleSheet(i == _sel and _CSS_OPT_ON or _CSS_OPT_OFF)
        end
    end

    local function _freeze_map_options()
        for i, btn in ipairs(map_btns) do
            btn:setStyleSheet(i == _sel and _CSS_OPT_FROZEN_SEL or _CSS_OPT_FROZEN_OFF)
            btn:setClickCallback(function() end)
        end
    end

    for i, opt in ipairs(_MAP_OPTIONS) do
        local btn = Geyser.Label:new({
            name   = string.format("%sopt%d_%d", prefix, i, n),
            x = "3%", y = opt_ys[i], width = "94%", height = _H_OPT,
        }, parent_in)
        btn:echo(opt.label)
        table.insert(map_btns, btn)

        local idx = i
        btn:setClickCallback(function()
            if _import_done then return end
            _sel = idx
            _refresh_btn_styles()
        end)
    end

    _refresh_btn_styles()

    -- Import button
    local imp_btn = Geyser.Label:new({
        name   = prefix .. "imp_" .. n,
        x = "3%", y = y_imp, width = "94%", height = _H_IMP,
    }, parent_in)
    imp_btn:setStyleSheet(_CSS_IMPORT)
    imp_btn:echo("<center>Import Selected Map</center>")

    -- Status label
    local status_lbl = Geyser.Label:new({
        name   = prefix .. "stat_" .. n,
        x = 0, y = y_stat, width = "100%", height = _H_STAT,
    }, parent_in)
    status_lbl:setStyleSheet(_CSS_STATUS_INFO)
    status_lbl:echo("")

    -- Import callback — defined after status_lbl so both locals are in scope
    imp_btn:setClickCallback(function()
        if _import_done then return end

        local opt      = _MAP_OPTIONS[_sel]
        local map_path = getMudletHomeDir() .. "/fed2-tools/shared/" .. opt.file

        status_lbl:setStyleSheet(_CSS_STATUS_INFO)
        status_lbl:echo("  Importing, please wait...")

        -- Defer one tick so the status text renders before loadJsonMap runs
        tempTimer(0.1, function()
            local ok = _import_map(map_path, status_lbl, imp_btn)
            if ok then
                _import_done = true
                _freeze_map_options()
            end
        end)
    end)

    return UI_MAP_IMPORT_SECTION_H
end

-- ── Standalone post-upgrade dialog ────────────────────────────────────────────

local function _close_import_dialog()
    if UI.map_import_dialog then
        UI.map_import_dialog:hide()
        UI.map_import_dialog = nil
    end
end

function ui_map_import_show_dialog()
    _close_import_dialog()
    _n = _n + 1
    local n = _n

    local sw, sh = getMainWindowSize()
    local dw = 500

    local H_HDR  = 44
    local H_DIV  = 1
    local H_BODY = 42   -- two lines of intro text
    local H_FDIV = 1
    local H_BTN  = 34
    local H_PAD  = 16

    local y_hdr  = 0
    local y_div1 = H_HDR
    local y_body = y_div1 + H_DIV + 8
    local y_sec  = y_body + H_BODY + 8
    local y_fdiv = y_sec  + UI_MAP_IMPORT_SECTION_H + 8
    local y_btn  = y_fdiv + H_FDIV + 10
    local dh     = y_btn  + H_BTN  + H_PAD

    local cx = math.floor((sw - dw) / 2)
    local cy = math.floor((sh - dh) / 2)

    UI.map_import_dialog = Adjustable.Container:new({
        name          = "f2t_mip_ac_" .. n,
        x             = cx, y = cy,
        width         = dw, height = dh,
        adjLabelstyle = _FRAME_CSS,
        autoSave      = false,
        autoLoad      = false,
    })
    UI.map_import_dialog:lockContainer("border")
    UI.map_import_dialog.locked = false   -- keep draggable

    local _in = UI.map_import_dialog.Inside

    -- Header
    local hdr = Geyser.Label:new({
        name   = "f2t_mip_hdr_" .. n,
        x = 0, y = y_hdr, width = "100%", height = H_HDR,
    }, _in)
    hdr:setStyleSheet(_CSS_HDR)
    hdr:echo("  Map Database Update Recommended")

    local xbtn = Geyser.Label:new({
        name   = "f2t_mip_xbtn_" .. n,
        x = "92%", y = 8, width = 30, height = 28,
    }, _in)
    xbtn:setStyleSheet(_CSS_XBTN)
    xbtn:echo("<center>×</center>")
    xbtn:setClickCallback(_close_import_dialog)

    -- Divider
    local div1 = Geyser.Label:new({
        name   = "f2t_mip_div1_" .. n,
        x = 0, y = y_div1, width = "100%", height = H_DIV,
    }, _in)
    div1:setStyleSheet("background-color: rgba(255,255,255,0.1); border:none;")

    -- Intro text
    local body = Geyser.Label:new({
        name   = "f2t_mip_body_" .. n,
        x = 0, y = y_body, width = "100%", height = H_BODY,
    }, _in)
    body:setStyleSheet(_CSS_CON)
    body:echo(
        "<font color='#c6d2ee'>This version includes an updated map database.<br>" ..
        "Importing it is recommended for the best navigation experience.</font>"
    )

    -- Map import section (same UI as the welcome dialog)
    ui_map_import_build_section(_in, n, "f2t_mip_", y_sec)

    -- Footer divider
    local fdiv = Geyser.Label:new({
        name   = "f2t_mip_fdiv_" .. n,
        x = 0, y = y_fdiv, width = "100%", height = H_FDIV,
    }, _in)
    fdiv:setStyleSheet("background-color: rgba(255,255,255,0.1); border:none;")

    -- Dismiss button
    local btn_dismiss = Geyser.Label:new({
        name   = "f2t_mip_dismiss_" .. n,
        x = "15%", y = y_btn, width = "70%", height = H_BTN,
    }, _in)
    btn_dismiss:setStyleSheet(_CSS_BTN)
    btn_dismiss:echo("<center>Dismiss</center>")
    btn_dismiss:setClickCallback(_close_import_dialog)

    -- Hide then show immediately (ensures Qt widget parenting is correct)
    UI.map_import_dialog:hide()
    UI.map_import_dialog:show()
    UI.map_import_dialog:raiseAll()
end
