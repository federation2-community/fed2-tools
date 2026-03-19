-- ============================================================================
-- GALAXY DATA MANAGEMENT  —  powered by "di systems"
-- ============================================================================
--
-- TRIGGERS REQUIRED (replace all previous galaxy triggers):
--
--   galaxySystemsLine   (fires while capture is active)
--     type    : regex
--     pattern : ^(.+)$          ← any non-blank line
--     script  : if UI.galaxy and UI.galaxy.capture_active then
--                   ui_galaxy_capture_line(matches[2])
--               end
--
--   galaxySystemsEnd    (blank line signals end of "di systems" output)
--     type    : regex
--     pattern : ^$
--     script  : if UI.galaxy and UI.galaxy.capture_active then
--                   ui_galaxy_finish_capture()
--               end
--
-- ============================================================================

UI.galaxy = UI.galaxy or {
    cartels        = {},    -- [cartel_name] = { name, systems = { [sys_name] = {...} } }
    loaded         = false,
    loading        = false,
    last_updated   = nil,   -- unix timestamp of last successful load
    visible        = false,
    expanded       = {},    -- [key] = true/false; persists in-session only

    capture_active = false,
    capture_lines  = {},    -- raw lines buffered during capture
}

UI.galaxy_button_active = false

-- ── Age helper ───────────────────────────────────────────────────────────────

local function _age_str(ts)
    if not ts or ts == 0 then return "Never" end
    local age = os.time() - ts
    if age < 60       then return "Just now"
    elseif age < 3600 then return string.format("%dm ago", math.floor(age / 60))
    elseif age < 86400 then return string.format("%dh ago", math.floor(age / 3600))
    else                   return string.format("%dd ago", math.floor(age / 86400))
    end
end

-- ── Data loading ──────────────────────────────────────────────────────────────

-- Send "di systems" and begin capturing output.
function ui_galaxy_init()
    if UI.galaxy.loading then
        cecho("\n<yellow>[Galaxy]<reset> Already loading...\n")
        return
    end
    UI.galaxy.loading        = true
    UI.galaxy.loaded         = false
    UI.galaxy.capture_active = true
    UI.galaxy.capture_lines  = {}
    UI.galaxy.cartels        = {}

    -- Show loading state immediately if the panel is open
    if UI.galaxy.visible then ui_populate_galaxy_dropdown() end

    sendAll("di systems", false)
end

-- Called by the galaxySystemsLine trigger for every non-blank line.
-- Handles both full system lines and wrapped continuation lines.
function ui_galaxy_capture_line(line)
    if not UI.galaxy.capture_active then return end
    line = line:match("^%s*(.-)%s*$")   -- trim
    if line == "" then return end

    -- A system line contains " - <name> cartel - "
    if line:match(" %- .+ cartel %- ") then
        table.insert(UI.galaxy.capture_lines, line)
    elseif #UI.galaxy.capture_lines > 0 then
        -- Continuation: wrap-around planet list from the previous system.
        -- Append with a space so the parser sees an unbroken planet string.
        local n = #UI.galaxy.capture_lines
        UI.galaxy.capture_lines[n] = UI.galaxy.capture_lines[n] .. " " .. line
    end
    -- Lines that match neither (e.g. command echo, stray text) are ignored.
end

-- Parse one combined system line into its components.
-- Format: "SystemName - CartelName cartel - Rank Owner[tag]: Planet(T) ..."
local function _parse_system_line(line)
    local system_name, cartel_name, planet_str =
        line:match("^(.+) %- (.+) cartel %- [^:]+: (.*)$")
    if not system_name then return nil end

    system_name = system_name:match("^%s*(.-)%s*$")
    cartel_name = cartel_name:match("^%s*(.-)%s*$")

    local planets = {}
    -- Matches "Planet Name(T)" where T is one or more uppercase letters/digits
    for planet_name in (planet_str or ""):gmatch("(.-)%([^%)]+%)%s*") do
        planet_name = planet_name:match("^%s*(.-)%s*$")
        if planet_name ~= "" then
            table.insert(planets, {
                name   = planet_name,
                system = system_name,
                cartel = cartel_name,
            })
        end
    end

    return system_name, cartel_name, planets
end

-- Called by the galaxySystemsEnd trigger on a blank line.
function ui_galaxy_finish_capture()
    if not UI.galaxy.capture_active then return end
    UI.galaxy.capture_active = false

    if #UI.galaxy.capture_lines == 0 then
        cecho("\n<red>[Galaxy]<reset> No data captured from 'di systems'.\n")
        UI.galaxy.loading = false
        if UI.galaxy.visible then ui_populate_galaxy_dropdown() end
        return
    end

    -- Build the cartels/systems structure from captured lines
    local cartels = {}
    for _, line in ipairs(UI.galaxy.capture_lines) do
        local system_name, cartel_name, planets = _parse_system_line(line)
        if system_name and cartel_name then
            if not cartels[cartel_name] then
                cartels[cartel_name] = { name = cartel_name, systems = {} }
            end
            cartels[cartel_name].systems[system_name] = {
                name    = system_name,
                cartel  = cartel_name,
                planets = planets,
            }
        end
    end

    UI.galaxy.cartels      = cartels
    UI.galaxy.loading      = false
    UI.galaxy.loaded       = true
    UI.galaxy.last_updated = os.time()

    local nc = 0; for _ in pairs(cartels) do nc = nc + 1 end
    f2t_debug_log("[galaxy] Loaded %d cartels from di systems", nc)

    if UI.galaxy.visible then ui_populate_galaxy_dropdown() end
end

-- ── Navigation ────────────────────────────────────────────────────────────────

function ui_galaxy_nav_to(location_type, location_name)
    if location_type == "planet" then
        expandAlias("nav " .. location_name)
    elseif location_type == "system" then
        expandAlias("nav " .. location_name .. " link")
    end
    if UI.galaxy_dropdown then
        UI.galaxy_dropdown:hide()
        UI.galaxy.visible       = false
        UI.galaxy_button_active = false
    end
end

function ui_galaxy_get_info(location_type, location_name)
    if location_type == "cartel" then
        send("di cartel " .. location_name)
    elseif location_type == "system" then
        send("di system " .. location_name)
    elseif location_type == "planet" then
        send("di planet " .. location_name)
    end
end

-- ============================================================================
-- GALAXY UI
-- ============================================================================

-- Shared style constants
local _BG  = "background-color: rgb(18, 18, 26); border: none;"
local _ROW = "background-color: rgb(22, 22, 30); border: none; border-bottom: 1px solid rgba(255,255,255,10);"

-- Layout constants (% of row width)
-- Rows are always x=0; indentation is via child widget x-position only.
--
--   Cartel (indent 0): expand@0%, icon@5%, name@10%→96%   (no nav button)
--   System (indent 1): expand@4%, icon@9%, name@14%→91%,  nav@93%
--   Planet (indent 2): (no expand), icon@13%, name@18%→91%, nav@93%
--
local INDENT_PCT = 4    -- % per indent level
local EXPAND_PCT = 5    -- expand button slot width %
local ICON_PCT   = 5    -- icon slot width %
local NAV_X      = "93%"
local NAV_W      = "5%"
local ROW_H      = 23   -- pixels (tied to font size, not window size)

-- Draw epoch: incremented each redraw so widget names are always unique,
-- preventing Geyser registry collisions from stale hidden widgets.
UI.galaxy_draw_epoch = UI.galaxy_draw_epoch or 0

-- ── Build the panel (called once) ────────────────────────────────────────────

function ui_build_galaxy_dropdown()
    if UI.galaxy_dropdown then
        UI.galaxy_dropdown:hide()
        return
    end

    -- Position: right edge abuts UI.right_frame; top edge below UI.top_right_frame
    local main_w, main_h = getMainWindowSize()
    local rf_x_px    = UI.right_frame:get_x()
    local trf_bot_px = UI.top_right_frame:get_y() + UI.top_right_frame:get_height()

    local panel_w_pct = 18
    local panel_w_px  = math.floor(main_w * panel_w_pct / 100)
    local panel_x_px  = rf_x_px - panel_w_px
    local panel_y_px  = trf_bot_px
    local panel_h_px  = math.max(100, math.floor(main_h * 0.97) - panel_y_px)

    local panel_x_str = string.format("%.2f%%", panel_x_px / main_w * 100)
    local panel_y_str = string.format("%.2f%%", panel_y_px / main_h * 100)
    local panel_h_str = string.format("%.2f%%", panel_h_px / main_h * 100)

    UI.galaxy_dropdown = Adjustable.Container:new({
        name          = "galaxy_dropdown",
        x             = panel_x_str,
        y             = panel_y_str,
        width         = panel_w_pct .. "%",
        height        = panel_h_str,
        adjLabelstyle = UI.style.frame_css,
        autoSave      = false,
        autoLoad      = false,
    })
    UI.galaxy_dropdown:lockContainer("border")
    f2t_ui_register_container("galaxy_dropdown", UI.galaxy_dropdown)

    -- Opaque background (overrides any alpha in frame_css)
    local bg = Geyser.Label:new({
        name = "galaxy_panel_bg", x=0, y=0, width="100%", height="100%"
    }, UI.galaxy_dropdown)
    bg:setStyleSheet("background-color: rgb(20, 20, 28); border: none;")

    -- ── Header (3%) ───────────────────────────────────────────────────────
    UI.galaxy_topbar = Geyser.Label:new({
        name = "galaxy_topbar", x=0, y=0, width="100%", height="3%"
    }, UI.galaxy_dropdown)
    UI.galaxy_topbar:setStyleSheet(UI.style.header_label_css)

    UI.galaxy_title = Geyser.Label:new({
        name = "galaxy_title", x="2%", y=0, width="64%", height="100%"
    }, UI.galaxy_topbar)
    UI.galaxy_title:setStyleSheet(
        "background-color:transparent; color:#c8c8d0; font-size:11px; font-weight:bold;")
    UI.galaxy_title:echo("Galaxy Navigator")

    -- Collapse all (−)
    UI.galaxy_collapse_btn = Geyser.Label:new({
        name = "galaxy_collapse_btn", x="67%", y="5%", width="9%", height="90%"
    }, UI.galaxy_topbar)
    UI.galaxy_collapse_btn:setStyleSheet(UI.style.button_css)
    UI.galaxy_collapse_btn:echo("<center>−</center>")
    UI.galaxy_collapse_btn:setClickCallback(function()
        UI.galaxy.expanded = {}
        ui_populate_galaxy_dropdown()
    end)
    UI.galaxy_collapse_btn:setToolTip("Collapse all")

    -- Refresh (⟳) — runs "di systems" again; tooltip shows data age
    UI.galaxy_refresh_icon = Geyser.Label:new({
        name = "galaxy_refresh_icon", x="77%", y="5%", width="9%", height="90%"
    }, UI.galaxy_topbar)
    UI.galaxy_refresh_icon:setStyleSheet(UI.style.button_css)
    UI.galaxy_refresh_icon:echo("<center>⟳</center>")
    UI.galaxy_refresh_icon:setClickCallback(function()
        ui_galaxy_init()
    end)
    UI.galaxy_refresh_icon:setToolTip("Refresh: " .. _age_str(UI.galaxy.last_updated))

    -- Close (✕)
    UI.galaxy_close = Geyser.Label:new({
        name = "galaxy_close", x="88%", y="5%", width="10%", height="90%"
    }, UI.galaxy_topbar)
    UI.galaxy_close:setStyleSheet([[
        QLabel {
            background-color: rgba(180, 50, 50, 220);
            border: 1px solid rgba(200, 80, 80, 180);
            border-radius: 3px;
            color: white;
            font-size: 12px;
        }
        QLabel::hover { background-color: rgba(210, 60, 60, 240); }
    ]])
    UI.galaxy_close:echo("<center>✕</center>")
    UI.galaxy_close:setClickCallback(function()
        UI.galaxy_dropdown:hide()
        UI.galaxy.visible       = false
        UI.galaxy_button_active = false
    end)

    -- ── Scroll area (3%–97%) ──────────────────────────────────────────────
    -- Do NOT call setStyleSheet on ScrollBox — unsupported, causes errors.
    UI.galaxy_scroll = Geyser.ScrollBox:new({
        name = "galaxy_scroll",
        x="0%", y="3%", width="100%", height="94%"
    }, UI.galaxy_dropdown)

    -- ── Footer legend (97%–100%) ──────────────────────────────────────────
    UI.galaxy_footer = Geyser.Label:new({
        name = "galaxy_footer", x=0, y="97%", width="100%", height="3%"
    }, UI.galaxy_dropdown)
    UI.galaxy_footer:setStyleSheet(UI.style.header_label_css)

    UI.galaxy_legend = Geyser.Label:new({
        name = "galaxy_legend", x="1%", y=0, width="98%", height="100%"
    }, UI.galaxy_footer)
    UI.galaxy_legend:setStyleSheet(
        "background-color:transparent; color:rgba(160,160,170,190); font-size:9px;")
    UI.galaxy_legend:echo("<center>🌌 Cartel  ⭐ System  🌍 Planet</center>")

    -- Hide LAST so nothing re-shows it during child creation.
    UI.galaxy_dropdown:hide()
end

-- ── Row builder ──────────────────────────────────────────────────────────────

function ui_create_galaxy_row(parent, name, row_type, indent_level, y_px, data)
    local cartel_ctx = (data and data.cartel) or ""
    local uid = string.format("gxrow_%d_%s_%s_%s",
        UI.galaxy_draw_epoch, row_type, cartel_ctx, name)
        :gsub("[^%w_]", "_")

    local row = Geyser.Label:new({
        name = uid, x=0, y=y_px, width="100%", height=ROW_H
    }, parent)
    row:setStyleSheet(_ROW)

    local indent_pct = indent_level * INDENT_PCT

    -- Expand / collapse (cartel and system only)
    local exp_key
    if row_type == "cartel" then
        exp_key = name
    elseif row_type == "system" then
        exp_key = (cartel_ctx ~= "" and cartel_ctx or "") .. ":" .. name
    end

    if exp_key then
        local is_exp = UI.galaxy.expanded[exp_key] or false
        local ebtn = Geyser.Label:new({
            name  = uid .. "_exp",
            x     = indent_pct .. "%", y = 1,
            width = EXPAND_PCT .. "%", height = ROW_H - 2
        }, row)
        ebtn:setStyleSheet(UI.style.button_css)
        ebtn:echo(is_exp and "<center>−</center>" or "<center>+</center>")
        ebtn:setClickCallback(function()
            UI.galaxy.expanded[exp_key] = not UI.galaxy.expanded[exp_key]
            ui_populate_galaxy_dropdown()
        end)
    end

    -- Icon
    local icon_x_pct = indent_pct + EXPAND_PCT
    local icon_map = {
        cartel = { "🌌", "#ff6b9d" },
        system = { "⭐",  "#ffd700" },
        planet = { "🌍", "#4ecdc4" },
    }
    local id = icon_map[row_type]
    local icon = Geyser.Label:new({
        name  = uid .. "_ico",
        x     = icon_x_pct .. "%", y = 1,
        width = ICON_PCT .. "%", height = ROW_H - 2
    }, row)
    icon:setStyleSheet(string.format(
        "background-color:transparent; color:%s; font-size:11px;", id[2]))
    icon:echo("<center>" .. id[1] .. "</center>")

    -- Name label — width fills right up to the nav button (or edge for cartels)
    local name_x_pct = icon_x_pct + ICON_PCT
    local has_nav    = (row_type == "system" or row_type == "planet")
    local name_end   = has_nav and 91 or 97
    local name_w_pct = math.max(5, name_end - name_x_pct)

    local nlbl = Geyser.Label:new({
        name  = uid .. "_name",
        x     = name_x_pct .. "%", y = 1,
        width = name_w_pct .. "%", height = ROW_H - 2
    }, row)
    nlbl:setStyleSheet(UI.style.button_css)
    nlbl:echo(name)
    nlbl:setClickCallback(function() ui_galaxy_get_info(row_type, name) end)
    nlbl:setToolTip("Click for info")

    -- Nav button → (system and planet only, fixed column)
    if has_nav then
        local nbtn = Geyser.Label:new({
            name  = uid .. "_nav",
            x     = NAV_X, y = 1, width = NAV_W, height = ROW_H - 2
        }, row)
        nbtn:setStyleSheet([[
            QLabel {
                background-color: rgba(40, 120, 80, 210);
                border: 1px solid rgba(60, 140, 100, 180);
                border-radius: 3px;
                color: white;
                font-size: 10px;
                font-weight: bold;
            }
            QLabel::hover { background-color: rgba(55, 150, 95, 230); }
        ]])
        nbtn:echo("<center>→</center>")
        nbtn:setClickCallback(function() ui_galaxy_nav_to(row_type, name) end)
        nbtn:setToolTip("Navigate here")
    end

    return row
end

-- ── Count visible rows ────────────────────────────────────────────────────────

local function _count_visible_rows(sorted_cartels)
    local n = 0
    for _, cn in ipairs(sorted_cartels) do
        n = n + 1
        if UI.galaxy.expanded[cn] then
            local cd = UI.galaxy.cartels[cn]
            for sn in pairs(cd.systems or {}) do
                if sn ~= (cn .. " Space") then
                    n = n + 1
                    local sys_key = cn .. ":" .. sn
                    if UI.galaxy.expanded[sys_key] then
                        for _, pd in ipairs((cd.systems[sn] or {}).planets or {}) do
                            if pd.name ~= (sn .. " Space") then
                                n = n + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return n
end

-- ── Populate the scrollable tree ──────────────────────────────────────────────
--
-- SCROLL POSITION STRATEGY
-- Destroying and recreating the content label creates a new Qt widget, which
-- always starts at scroll offset 0.  Instead we keep ONE permanent content
-- label (galaxy_main_content) and only RESIZE it on each redraw.  Qt's
-- QScrollArea preserves its vertical scroll offset as long as the same child
-- widget is in place.  Old row labels are hidden (not destroyed) and new ones
-- are created with epoch-suffixed names so the Geyser registry never collides.

function ui_populate_galaxy_dropdown()
    if not UI.galaxy_scroll then return end

    UI.galaxy_draw_epoch = UI.galaxy_draw_epoch + 1

    -- Update ⟳ tooltip with current data age
    if UI.galaxy_refresh_icon then
        UI.galaxy_refresh_icon:setToolTip("Refresh: " .. _age_str(UI.galaxy.last_updated))
    end

    -- Hide all rows from the previous draw pass.
    -- Row labels are children of galaxy_main_content; hiding each row also
    -- hides its children (expand btn, icon, name, nav) in Qt.
    UI.galaxy_rows = UI.galaxy_rows or {}
    for _, r in ipairs(UI.galaxy_rows) do r:hide() end
    UI.galaxy_rows = {}

    -- ── Ensure the two permanent sibling labels exist ────────────────────────
    -- galaxy_scroll_state  : shown for loading / no-data messages
    -- galaxy_main_content  : shown when data is available; never destroyed
    if not UI.galaxy_scroll_state then
        UI.galaxy_scroll_state = Geyser.Label:new({
            name="galaxy_scroll_state", x=0, y=0, width="96%", height=2000
        }, UI.galaxy_scroll)
        UI.galaxy_scroll_state:setStyleSheet(_BG)

        UI.galaxy_state_msg = Geyser.Label:new({
            name="galaxy_state_msg", x=0, y="40%", width="100%", height=60
        }, UI.galaxy_scroll_state)
        UI.galaxy_state_msg:setStyleSheet(
            "background-color:transparent; font-size:11px;")
    end

    if not UI.galaxy_scroll_content then
        UI.galaxy_scroll_content = Geyser.Label:new({
            name="galaxy_main_content", x=0, y=0, width="96%", height=2000
        }, UI.galaxy_scroll)
        UI.galaxy_scroll_content:setStyleSheet(_BG)
    end

    -- ── Loading state ────────────────────────────────────────────────────────
    if UI.galaxy.loading then
        UI.galaxy_scroll_content:hide()
        UI.galaxy_state_msg:setStyleSheet(
            "background-color:transparent; color:rgba(200,200,100,220); font-size:11px;")
        UI.galaxy_state_msg:echo("<center>Loading galaxy data…</center>")
        UI.galaxy_scroll_state:show()
        return
    end

    -- ── No-data state ────────────────────────────────────────────────────────
    if not UI.galaxy.loaded then
        UI.galaxy_scroll_content:hide()
        UI.galaxy_state_msg:setStyleSheet(
            "background-color:transparent; color:rgba(180,180,190,210); font-size:11px;")
        UI.galaxy_state_msg:echo(
            "<center>Galaxy data is not loaded.<br/>Click ⟳ in the header to load it.</center>")
        UI.galaxy_scroll_state:show()
        return
    end

    -- ── Render tree ──────────────────────────────────────────────────────────
    UI.galaxy_scroll_state:hide()
    UI.galaxy_scroll_content:show()

    local sorted_cartels = {}
    for cn in pairs(UI.galaxy.cartels) do table.insert(sorted_cartels, cn) end
    table.sort(sorted_cartels)

    local visible_rows = _count_visible_rows(sorted_cartels)
    local content_h    = math.max(visible_rows * ROW_H + 4, 2000)

    -- Resize in place — preserves Qt scroll offset
    UI.galaxy_scroll_content:resize("96%", content_h)

    local y_px = 2

    for _, cartel_name in ipairs(sorted_cartels) do
        local cartel_data = UI.galaxy.cartels[cartel_name]

        local r = ui_create_galaxy_row(UI.galaxy_scroll_content, cartel_name, "cartel", 0, y_px, cartel_data)
        table.insert(UI.galaxy_rows, r)
        y_px = y_px + ROW_H

        if UI.galaxy.expanded[cartel_name] then
            local sorted_sys = {}
            for sn in pairs(cartel_data.systems or {}) do table.insert(sorted_sys, sn) end
            table.sort(sorted_sys)

            for _, system_name in ipairs(sorted_sys) do
                if system_name ~= (cartel_name .. " Space") then
                    local system_data = cartel_data.systems[system_name]

                    local sr = ui_create_galaxy_row(UI.galaxy_scroll_content, system_name, "system", 1, y_px, system_data)
                    table.insert(UI.galaxy_rows, sr)
                    y_px = y_px + ROW_H

                    local sys_key = cartel_name .. ":" .. system_name
                    if UI.galaxy.expanded[sys_key] then
                        for _, planet_data in ipairs(system_data.planets or {}) do
                            if planet_data.name ~= (system_name .. " Space") then
                                local pr = ui_create_galaxy_row(UI.galaxy_scroll_content, planet_data.name, "planet", 2, y_px, planet_data)
                                table.insert(UI.galaxy_rows, pr)
                                y_px = y_px + ROW_H
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ── Toggle visibility ─────────────────────────────────────────────────────────

function ui_toggle_galaxy()
    if not UI.galaxy_dropdown then
        UI.galaxy.visible       = false
        UI.galaxy_button_active = false
        ui_build_galaxy_dropdown()
        if not UI.galaxy_dropdown then return end
    end

    if UI.galaxy.visible then
        UI.galaxy_dropdown:hide()
        UI.galaxy.visible       = false
        UI.galaxy_button_active = false
    else
        -- Auto-load on first open if not yet loaded and not already loading
        if not UI.galaxy.loaded and not UI.galaxy.loading then
            ui_galaxy_init()
        end
        ui_populate_galaxy_dropdown()
        UI.galaxy_dropdown:show()
        UI.galaxy_dropdown:raise()
        UI.galaxy.visible       = true
        UI.galaxy_button_active = true
    end
end