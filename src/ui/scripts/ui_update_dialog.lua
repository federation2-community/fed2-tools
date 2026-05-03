UI = UI or {}

local _CSS_FRAME = [[
    background-color: rgba(10,12,22,254);
    border: 2px solid rgba(255,255,255,0.42);
    border-radius: 8px;
]]
local _CSS_HDR = [[
    background: qlineargradient(x1:0,y1:0,x2:0,y2:1,
        stop:0 rgba(44,50,78,255), stop:1 rgba(22,26,44,255));
    color: rgba(220,230,255,255);
    font-size: 16px; font-weight: bold;
    font-family: "Consolas","Monaco",monospace;
    border-top-left-radius: 6px; border-top-right-radius: 6px;
    border-bottom: 1px solid rgba(255,255,255,0.16);
    padding: 0 16px;
]]
local _CSS_BODY = [[
    background: transparent;
    color: rgba(198,210,238,255);
    font-size: 14px;
    font-family: "Consolas","Monaco",monospace;
    padding: 0 16px;
]]
local _CSS_SUB = [[
    background: transparent;
    color: rgba(105,125,180,255);
    font-size: 12px;
    font-family: "Consolas","Monaco",monospace;
    padding: 0 16px;
]]
local _CSS_DIV = [[ background-color: rgba(255,255,255,0.09); border: none; ]]
local _CSS_BTN = [[
    QLabel {
        background-color: rgba(36,40,62,230);
        color: rgba(178,190,225,255);
        border: 1px solid rgba(85,98,140,210);
        border-radius: 5px;
        font-size: 13px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(52,60,95,245);
        border-color: rgba(105,158,255,210);
        color: white;
    }
]]
local _CSS_OK = [[
    QLabel {
        background-color: rgba(18,58,34,240);
        color: rgba(115,222,148,255);
        border: 1px solid rgba(48,152,78,215);
        border-radius: 5px;
        font-size: 13px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(26,82,46,255);
        border-color: rgba(65,210,108,235);
        color: rgba(178,255,200,255);
    }
]]
local _CSS_DANGER = [[
    QLabel {
        background-color: rgba(52,18,18,230);
        color: rgba(210,120,115,255);
        border: 1px solid rgba(140,48,48,200);
        border-radius: 5px;
        font-size: 13px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(82,22,22,245);
        border-color: rgba(200,70,68,220);
        color: rgba(255,160,155,255);
    }
]]

local _CSS_NOTES = [[
    background-color: rgba(0, 0, 0, 0.2);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 4px;
    margin: 10px;
]]

local _seq = 0
local function _uid()
    _seq = _seq + 1
    return "ui_upd_" .. _seq
end

function _close()
    if UI.update_dialog then
        UI.update_dialog:hide()
        UI.update_dialog = nil
    end
end

local function _lbl(par, x, y, w, h, txt, css)
    local l = Geyser.Label:new({ name=_uid(), x=x, y=y, width=w, height=h }, par)
    l:setStyleSheet(css or _CSS_BODY)
    if txt and txt ~= "" then l:echo(txt) end
    return l
end

local function _btn(par, x, y, w, h, txt, css, cb)
    local b = Geyser.Label:new({ name=_uid(), x=x, y=y, width=w, height=h }, par)
    b:setStyleSheet(css)
    b:echo("<center>" .. txt .. "</center>")
    b:setClickCallback(cb)
    return b
end

local function _close_btn(par, x, y, size)
    local btn = Geyser.Label:new({
        name = _uid(),
        x = x, y = y,
        width = size, height = size
    }, par)
    
    btn:setStyleSheet([[
        QLabel {
            background-color: transparent;
            color: rgba(220,230,255,180);
            font-size: 18px;
            font-weight: bold;
            border-radius: 3px;
        }
        QLabel::hover {
            background-color: rgba(255,80,80,200);
            color: white;
        }
    ]])
    
    btn:echo("<center>×</center>")
    btn:setClickCallback(_close)
    return btn
end

function ui_update_show_dialog(current_version, new_version)
    _close()
    local sw, sh = getMainWindowSize()
    local dw = 500
   
    -- 1. Calculate Dynamic Height (80% max)
    local header_h = 135
    local footer_h = 80
    local estimated_lines = 0
   
    if F2T_CHANGELOG and #F2T_CHANGELOG > 0 then
        for _, entry in ipairs(F2T_CHANGELOG) do
            estimated_lines = estimated_lines + 2
            local _, newlines = entry.body:gsub("\n", "\n")
            estimated_lines = estimated_lines + newlines + math.ceil(#entry.body / 65)
        end
    else
        estimated_lines = 3
    end
    local content_h = math.max(100, estimated_lines * 16)
    local dh = math.min(header_h + content_h + footer_h, math.floor(sh * 0.8))
   
    -- 2. Create Main Frame
    UI.update_dialog = Geyser.Label:new({
        name = "f2t_update_dialog",
        x = math.floor((sw - dw) / 2),
        y = math.floor((sh - dh) / 2),
        width = dw, height = dh,
    })
    UI.update_dialog:setStyleSheet(_CSS_FRAME)
    UI.update_dialog:show()
    UI.update_dialog:raise()

    -- === HEADER ===
    local header = _lbl(UI.update_dialog, 0, 0, dw, 44, "Update Available", _CSS_HDR)
    
    -- Close button (X) in top right
    _close_btn(UI.update_dialog, dw - 36, 4, 28)

    _lbl(UI.update_dialog, 0, 44, dw, 1, "", _CSS_DIV)
    _lbl(UI.update_dialog, 0, 55, dw, 26, "A new version of <b>fed2-tools</b> is available.", _CSS_BODY)
    _lbl(UI.update_dialog, 0, 81, dw, 22, string.format("You have <b>v%s</b>. Latest is <b>v%s</b>.", current_version or "???", new_version), _CSS_SUB)
    _lbl(UI.update_dialog, 16, 115, dw-32, 20, "What's New:", _CSS_SUB)

    -- 3. Dynamic Console Container
    local box_w, box_h = dw - 32, dh - header_h - footer_h + 20
    local notes_box = Geyser.Label:new({
        name = "f2t_notes_box", x = 16, y = 140,
        width = box_w, height = box_h
    }, UI.update_dialog)
    notes_box:setStyleSheet(_CSS_NOTES)
    
    local notes_console = Geyser.MiniConsole:new({
        name = "f2t_notes_console", x = 5, y = 5,
        width = box_w - 15, height = box_h - 10,
        autoWrap = true, fontSize = 10, scrollBar = true, color = "black"
    }, notes_box)
    notes_console:clear()
    notes_console:raise()

    -- Fill Notes using hecho
    if F2T_CHANGELOG and #F2T_CHANGELOG > 0 then
        for _, entry in ipairs(F2T_CHANGELOG) do
            notes_console:hecho("#73de94[ v" .. entry.version .. " ]\n")
            notes_console:hecho("#c6d2ee" .. entry.body .. "\n\n")
        end
    else
        notes_console:hecho("#697db4No specific release notes found.\n")
    end

    -- 4. Footer Buttons
    _lbl(UI.update_dialog, 0, dh - 60, dw, 1, "", _CSS_DIV)
    local bw, bh, by = 140, 32, dh - 44

    _btn(UI.update_dialog, 16, by, bw, bh, "Never", _CSS_DANGER, function()
        _close()
        f2t_settings_set("shared", "update_check_enabled", false)
        f2t_settings_set("shared", "update_check_remind_skip", 0)
    end)
    
    _btn(UI.update_dialog, (dw - bw) / 2, by, bw, bh, "Remind Later", _CSS_BTN, function()
        _close()
        f2t_settings_set("shared", "update_check_enabled", true)
        f2t_settings_set("shared", "update_check_remind_skip", 5)
    end)
    
    _btn(UI.update_dialog, dw - 16 - bw, by, bw, bh, "Update Now", _CSS_OK, function()
        _close()
        mpkg.upgrade("fed2-tools")
    end)
end
