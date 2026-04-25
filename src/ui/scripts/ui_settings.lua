-- =============================================================================
-- ui_settings.lua  —  Floating settings window
-- Driven entirely by F2T_SETTINGS_REGISTRY / F2T_SETTINGS_ORDER.
-- Widget type is inferred from registration metadata; no component-specific code.
-- =============================================================================

UI.settings_window         = nil
UI.settings_window_visible = false
UI.settings_tabs           = {}
UI.settings_scroll         = nil
UI.settings_content        = nil
UI.settings_content_w      = 400
UI.settings_rows           = {}
UI.settings_draw_epoch     = 0
UI.settings_current_tab    = nil
UI.settings_components     = {}

local _ROW_H    = 50   -- pixels per setting row
local _TITLE_H  = 30   -- title bar height
local _TAB_H    = 28   -- tab bar height
local _WIDGET_W = 130  -- widget area width (right-aligned in each row)
local _WIDGET_H = 28   -- widget height
local _PAD_L    = 10   -- left-side text padding

-- ── Widget type inference ─────────────────────────────────────────────────────
-- choices present       → cycle widget (click cycles through options)
-- boolean default       → toggle widget (ON/OFF click)
-- number with min+max,
--   range ≤ 100         → stepper widget (− value +)
-- everything else       → inputbox widget (click opens inputBox dialog)

local function _widget_type(cfg)
    if cfg.choices then return "cycle" end
    if type(cfg.default) == "boolean" then return "toggle" end
    if type(cfg.default) == "number"
        and cfg.min ~= nil and cfg.max ~= nil
        and (cfg.max - cfg.min) <= 100
    then
        return "stepper"
    end
    return "inputbox"
end

-- ── Individual widget builders ────────────────────────────────────────────────

local function _make_toggle(parent, wx, wy, uid, comp, name)
    local css_on  = [[QLabel{background:rgb(30,70,40);color:#88ee88;font-size:10px;font-weight:bold;border:1px solid rgba(80,180,80,0.5);border-radius:3px;}QLabel::hover{background:rgb(40,90,50);}]]
    local css_off = [[QLabel{background:rgb(65,30,30);color:rgba(220,120,120,0.9);font-size:10px;font-weight:bold;border:1px solid rgba(180,80,80,0.4);border-radius:3px;}QLabel::hover{background:rgb(80,38,38);}]]

    local w = Geyser.Label:new({
        name=uid.."_tog", x=wx, y=wy, width=_WIDGET_W, height=_WIDGET_H
    }, parent)

    local function _ref()
        local v = f2t_settings_get(comp, name)
        w:setStyleSheet(v and css_on or css_off)
        w:echo("<center>" .. (v and "ON" or "OFF") .. "</center>")
    end
    _ref()
    w:setClickCallback(function()
        f2t_settings_set(comp, name, not f2t_settings_get(comp, name))
        _ref()
    end)
end

local function _make_cycle(parent, wx, wy, uid, comp, name, choices)
    local css = [[QLabel{background:rgb(38,38,58);color:#d8d8f0;font-size:10px;border:1px solid rgba(255,255,255,0.22);border-radius:3px;}QLabel::hover{background:rgb(55,55,80);border-color:rgba(100,140,220,0.7);}]]

    local w = Geyser.Label:new({
        name=uid.."_cyc", x=wx, y=wy, width=_WIDGET_W, height=_WIDGET_H
    }, parent)
    w:setStyleSheet(css)

    local function _ref()
        local v = tostring(f2t_settings_get(comp, name) or "")
        local disp = #v > 11 and v:sub(1,10).."…" or v
        w:echo("<center>" .. disp .. " ▸</center>")
    end
    _ref()
    w:setClickCallback(function()
        local cur = f2t_settings_get(comp, name)
        local ci = 1
        for i, c in ipairs(choices) do if c == cur then ci = i; break end end
        ci = (ci % #choices) + 1
        f2t_settings_set(comp, name, choices[ci])
        _ref()
    end)
end

local function _make_stepper(parent, wx, wy, uid, comp, name, cfg)
    local css_btn = [[QLabel{background:rgb(45,45,68);color:#c0c8e8;font-size:13px;font-weight:bold;border:1px solid rgba(255,255,255,0.2);border-radius:2px;}QLabel::hover{background:rgb(62,62,90);}]]
    local css_val = "background:transparent; color:#e8e8f8; font-size:11px; font-weight:bold;"
    local bw = 26
    local vw = _WIDGET_W - bw * 2 - 4

    local minus = Geyser.Label:new({name=uid.."_sm", x=wx,           y=wy, width=bw, height=_WIDGET_H}, parent)
    local vl    = Geyser.Label:new({name=uid.."_sv", x=wx+bw+2,      y=wy, width=vw, height=_WIDGET_H}, parent)
    local plus  = Geyser.Label:new({name=uid.."_sp", x=wx+bw+2+vw+2, y=wy, width=bw, height=_WIDGET_H}, parent)

    minus:setStyleSheet(css_btn); minus:echo("<center>−</center>")
    vl:setStyleSheet(css_val)
    plus:setStyleSheet(css_btn);  plus:echo("<center>+</center>")

    local function _ref()
        vl:echo("<center>" .. tostring(f2t_settings_get(comp, name)) .. "</center>")
    end
    _ref()

    minus:setClickCallback(function()
        local nv = math.max(cfg.min, (f2t_settings_get(comp, name) or cfg.min) - 1)
        f2t_settings_set(comp, name, nv); _ref()
    end)
    plus:setClickCallback(function()
        local nv = math.min(cfg.max, (f2t_settings_get(comp, name) or cfg.min) + 1)
        f2t_settings_set(comp, name, nv); _ref()
    end)
end

local function _make_inputbox(parent, wx, wy, uid, comp, name, cfg)
    local css = [[QLabel{background:rgb(38,38,58);color:#d8d8f0;font-size:10px;border:1px solid rgba(255,255,255,0.22);border-radius:3px;}QLabel::hover{background:rgb(55,55,80);border-color:rgba(100,140,220,0.7);}]]

    local w = Geyser.Label:new({
        name=uid.."_inp", x=wx, y=wy, width=_WIDGET_W, height=_WIDGET_H
    }, parent)
    w:setStyleSheet(css)

    local function _ref()
        local v = tostring(f2t_settings_get(comp, name) or "")
        local disp = #v > 13 and v:sub(1,12).."…" or v
        w:echo("<center>" .. disp .. "</center>")
    end
    _ref()

    w:setClickCallback(function()
        local cur = f2t_settings_get(comp, name)
        local result = inputBox(comp .. " › " .. name, cfg.description or "", tostring(cur or ""))
        if result ~= nil then  -- nil means user cancelled dialog
            local ok, err = f2t_settings_set(comp, name, result)
            if ok then
                _ref()
            else
                cecho(string.format("\n<red>[settings]<reset> %s.%s: %s\n", comp, name, err or "invalid"))
            end
        end
    end)
end

-- ── Build all rows for a component into the content label ─────────────────────

local function _build_rows(comp, content_lbl, content_w)
    local order = (F2T_SETTINGS_ORDER and F2T_SETTINGS_ORDER[comp]) or {}
    if #order == 0 then
        for k in pairs(F2T_SETTINGS_REGISTRY[comp] or {}) do table.insert(order, k) end
        table.sort(order)
    end

    local epoch    = UI.settings_draw_epoch
    local css_odd  = "background:rgb(22,22,33); border:none; border-bottom:1px solid rgba(255,255,255,0.05);"
    local css_even = "background:rgb(26,26,38); border:none; border-bottom:1px solid rgba(255,255,255,0.05);"
    local css_name = "background:transparent; color:#d0d0ea; font-size:11px; font-weight:bold;"
    local css_desc = "background:transparent; color:rgba(180,180,210,0.65); font-size:9px;"

    local wx = content_w - _WIDGET_W - 10
    local y  = 2

    for i, setting_name in ipairs(order) do
        local cfg = F2T_SETTINGS_REGISTRY[comp] and F2T_SETTINGS_REGISTRY[comp][setting_name]
        if not cfg then goto continue end

        local uid = string.format("set_%d_%s_%s", epoch, comp, setting_name):gsub("[^%w_]", "_")

        local row = Geyser.Label:new({
            name=uid.."_row", x=0, y=y, width=content_w, height=_ROW_H
        }, content_lbl)
        row:setStyleSheet((i%2==1) and css_odd or css_even)
        table.insert(UI.settings_rows, row)

        -- Setting name (left side, upper line)
        local nl = Geyser.Label:new({
            name=uid.."_n", x=_PAD_L, y=7, width=content_w-_WIDGET_W-22, height=18
        }, row)
        nl:setStyleSheet(css_name)
        nl:echo(setting_name)

        -- Description (left side, lower line)
        local dl = Geyser.Label:new({
            name=uid.."_d", x=_PAD_L, y=27, width=content_w-_WIDGET_W-22, height=16
        }, row)
        dl:setStyleSheet(css_desc)
        dl:echo(cfg.description or "")

        -- Widget (right side, vertically centered)
        local wy_widget = math.floor((_ROW_H - _WIDGET_H) / 2)
        local wt = _widget_type(cfg)

        if     wt == "toggle"  then _make_toggle(row, wx, wy_widget, uid, comp, setting_name)
        elseif wt == "cycle"   then _make_cycle(row, wx, wy_widget, uid, comp, setting_name, cfg.choices)
        elseif wt == "stepper" then _make_stepper(row, wx, wy_widget, uid, comp, setting_name, cfg)
        else                        _make_inputbox(row, wx, wy_widget, uid, comp, setting_name, cfg)
        end

        y = y + _ROW_H
        ::continue::
    end

    return y
end

-- ── Tab switching ─────────────────────────────────────────────────────────────

function ui_settings_show_tab(comp)
    -- Hide previous rows (old epoch widgets are hidden, not destroyed)
    for _, r in ipairs(UI.settings_rows) do r:hide() end
    UI.settings_rows = {}
    UI.settings_draw_epoch = UI.settings_draw_epoch + 1

    -- Update tab styles
    for c, tab in pairs(UI.settings_tabs) do
        tab:setStyleSheet(c == comp and UI.style.active_tab_css or UI.style.inactive_tab_css)
    end

    -- Build rows into content label; resize content label to fit
    local total_h = _build_rows(comp, UI.settings_content, UI.settings_content_w)
    UI.settings_content:resize(UI.settings_content_w, math.max(total_h + 4, 200))

    UI.settings_current_tab = comp
end

-- ── Build the window (called once on first open) ──────────────────────────────

local function _build_settings_window()
    local sw, sh = getMainWindowSize()
    local w = math.floor(sw * 0.55)
    local h = math.floor(sh * 0.70)
    local x = math.floor((sw - w) / 2)
    local y = math.floor((sh - h) / 2)

    UI.settings_content_w = w - 4  -- subtract 2px border on each side

    -- Outer frame (top-level, no parent = child of main window)
    UI.settings_window = Geyser.Label:new({
        name="UI.settings_window", x=x, y=y, width=w, height=h
    })
    UI.settings_window:setStyleSheet(UI.style.frame_css)

    -- Opaque solid background (overrides any alpha in frame_css)
    local bg = Geyser.Label:new({name="ui_set_bg", x=0, y=0, width="100%", height="100%"}, UI.settings_window)
    bg:setStyleSheet("background:rgb(18,18,26); border:none;")

    -- ── Title bar ──────────────────────────────────────────────────────────────
    local title_bar = Geyser.Label:new({
        name="ui_set_titlebar", x=0, y=0, width="100%", height=_TITLE_H
    }, UI.settings_window)
    title_bar:setStyleSheet(UI.style.header_label_css .. " border-bottom:1px solid rgba(255,255,255,0.25);")

    local title_lbl = Geyser.Label:new({
        name="ui_set_title_txt", x=8, y=0, width=w-46, height=_TITLE_H
    }, UI.settings_window)
    title_lbl:setStyleSheet("background:transparent; color:#d0d0e8; font-size:12px; font-weight:bold;")
    title_lbl:echo("  ⚙  Settings")

    local close_btn = Geyser.Label:new({
        name="ui_set_close", x=w-36, y=4, width=28, height=_TITLE_H-8
    }, UI.settings_window)
    close_btn:setStyleSheet([[QLabel{background:rgba(180,50,50,200);color:white;font-size:12px;font-weight:bold;border:1px solid rgba(200,80,80,150);border-radius:3px;}QLabel::hover{background:rgba(220,60,60,240);}]])
    close_btn:echo("<center>✕</center>")
    close_btn:setClickCallback(function() ui_toggle_settings() end)

    -- ── Tab bar ────────────────────────────────────────────────────────────────
    local components = {}
    for comp in pairs(F2T_SETTINGS_REGISTRY) do
        table.insert(components, comp)
    end
    table.sort(components)

    local n_tabs = math.max(#components, 1)
    local tab_w  = math.floor(w / n_tabs)
    local tab_y  = _TITLE_H

    UI.settings_tabs = {}
    for i, comp in ipairs(components) do
        local tx  = (i-1) * tab_w
        local tab = Geyser.Label:new({
            name="ui_set_tab_"..comp, x=tx, y=tab_y, width=tab_w, height=_TAB_H
        }, UI.settings_window)
        tab:echo("<center>" .. comp .. "</center>")
        local _comp = comp  -- capture for closure
        tab:setClickCallback(function() ui_settings_show_tab(_comp) end)
        UI.settings_tabs[comp] = tab
    end

    -- ── Scrollable content area ────────────────────────────────────────────────
    local scroll_y = _TITLE_H + _TAB_H
    local scroll_h = h - scroll_y
    -- Note: setStyleSheet on ScrollBox is unsupported in Mudlet; do not call it
    UI.settings_scroll = Geyser.ScrollBox:new({
        name="ui_set_scroll", x=0, y=scroll_y, width=w, height=scroll_h
    }, UI.settings_window)

    -- Single permanent content label; rows are children, resized to fit each tab
    UI.settings_content = Geyser.Label:new({
        name="ui_set_content", x=0, y=0, width=UI.settings_content_w, height=2000
    }, UI.settings_scroll)
    UI.settings_content:setStyleSheet("background:rgb(18,18,26); border:none;")

    UI.settings_rows      = {}
    UI.settings_components = components

    -- Show first tab by default
    if #components > 0 then
        ui_settings_show_tab(components[1])
    end
end

-- ── Public toggle ─────────────────────────────────────────────────────────────

function ui_toggle_settings()
    if not UI.settings_window then
        _build_settings_window()
        UI.settings_window_visible = true
        UI.settings_window:raise()
        return
    end

    if UI.settings_window_visible then
        UI.settings_window:hide()
        UI.settings_window_visible = false
    else
        UI.settings_window:show()
        UI.settings_window_visible = true
        UI.settings_window:raise()
        -- Refresh displayed values whenever the window is re-opened
        if UI.settings_current_tab then
            ui_settings_show_tab(UI.settings_current_tab)
        end
    end
end
