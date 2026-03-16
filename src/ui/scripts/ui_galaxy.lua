-- ============================================================================
-- GALAXY DATA MANAGEMENT WITH PERSISTENCE
-- ============================================================================

UI.galaxy = UI.galaxy or {
    cartels = {},
    loaded = false,
    loading = false,
    loading_automated = false,
    current_cartel_loading = nil,
    current_system_loading = nil,
    load_queue = {},
    expanded = {},
    last_updated = nil,
    cartel_timestamps = {},
    system_timestamps = {},
    visible = false,
    
    cartel_capture_active = false,
    cartel_list = {},
    member_capture_active = false,
    member_list = {},
    member_capturing = false,
    planet_capture_active = false,
    planet_list = {}
}

-- Register settings for persistence
f2t_settings_register("galaxy", "data", {
    description = "Cached galaxy navigation data",
    default = {},
    validator = function(value)
        return type(value) == "table", "Must be a table"
    end
})

f2t_settings_register("galaxy", "last_updated", {
    description = "Timestamp of last galaxy data update",
    default = 0,
    validator = function(value)
        return type(value) == "number", "Must be a number"
    end
})

f2t_settings_register("galaxy", "expanded", {
    description = "Expanded nodes in galaxy tree",
    default = {},
    validator = function(value)
        return type(value) == "table", "Must be a table"
    end
})

-- Save galaxy data to disk
function ui_galaxy_save()
    f2t_settings_set("galaxy", "data", UI.galaxy.cartels)
    f2t_settings_set("galaxy", "last_updated", UI.galaxy.last_updated or 0)
    f2t_settings_set("galaxy", "expanded", UI.galaxy.expanded)
    f2t_debug_log("[galaxy] Data saved to disk")
end

-- Load galaxy data from disk
function ui_galaxy_load()
    local saved_data = f2t_settings_get("galaxy", "data")
    local saved_time = f2t_settings_get("galaxy", "last_updated")
    local saved_expanded = f2t_settings_get("galaxy", "expanded")
    
    if saved_data and type(saved_data) == "table" then
        UI.galaxy.cartels = saved_data
        UI.galaxy.last_updated = saved_time or 0
        UI.galaxy.expanded = saved_expanded or {}
        
        local cartel_count = 0
        for _ in pairs(UI.galaxy.cartels) do cartel_count = cartel_count + 1 end
        
        if cartel_count > 0 then
            UI.galaxy.loaded = true
            f2t_debug_log("[galaxy] Loaded %d cartels from disk", cartel_count)
            cecho(string.format("\n<green>[Galaxy]<reset> Loaded %d cartels from cache\n", cartel_count))
            return true
        end
    end
    
    return false
end

-- Get data age in human-readable format
function ui_galaxy_get_age()
    if not UI.galaxy.last_updated or UI.galaxy.last_updated == 0 then
        return "Never"
    end
    
    local age_seconds = os.time() - UI.galaxy.last_updated
    
    if age_seconds < 60 then
        return "Just now"
    elseif age_seconds < 3600 then
        local minutes = math.floor(age_seconds / 60)
        return string.format("%dm ago", minutes)
    elseif age_seconds < 86400 then
        local hours = math.floor(age_seconds / 3600)
        return string.format("%dh ago", hours)
    else
        local days = math.floor(age_seconds / 86400)
        return string.format("%dd ago", days)
    end
end

-- Get specific item age
function ui_galaxy_get_item_age(type, cartel_name, system_name)
    local timestamp
    if type == "cartel" then
        timestamp = UI.galaxy.cartel_timestamps[cartel_name]
    elseif type == "system" and cartel_name and system_name then
        timestamp = UI.galaxy.system_timestamps[cartel_name .. ":" .. system_name]
    end
    
    if not timestamp then
        return "Never updated"
    end
    
    local age_seconds = os.time() - timestamp
    if age_seconds < 60 then
        return "Updated just now"
    elseif age_seconds < 3600 then
        local minutes = math.floor(age_seconds / 60)
        return string.format("Updated %dm ago", minutes)
    elseif age_seconds < 86400 then
        local hours = math.floor(age_seconds / 3600)
        return string.format("Updated %dh ago", hours)
    else
        local days = math.floor(age_seconds / 86400)
        return string.format("Updated %dd ago", days)
    end
end

-- Initialize galaxy data loading
function ui_galaxy_init(refresh_type, target_name)
    if UI.galaxy.loading then
        cecho("\n<yellow>[Galaxy]<reset> Already loading data...\n")
        return
    end
    
    if refresh_type == "all" and not target_name then
        if ui_galaxy_load() then
            if UI.galaxy_dropdown and UI.galaxy_dropdown:isVisible() then
                ui_populate_galaxy_dropdown()
            end
            return
        end
    end
    
    UI.galaxy.loading = true
    UI.galaxy.loading_automated = true
    UI.galaxy.load_queue = {}
    
    if refresh_type == "all" then
        cecho("\n<cyan>[Galaxy]<reset> Loading galaxy data (1-2 minutes)...\n")
        UI.galaxy.cartel_capture_active = true
        UI.galaxy.cartel_list = {}
        sendAll("di cartels", false)
        
    elseif refresh_type == "cartel" and target_name then
        UI.galaxy.current_cartel_loading = target_name
        UI.galaxy.member_capture_active = true
        UI.galaxy.member_list = {}
        UI.galaxy.member_capturing = false
        sendAll("di cartel " .. target_name, false)
        
    elseif refresh_type == "system" and target_name then
        for cartel_name, cartel_data in pairs(UI.galaxy.cartels) do
            if cartel_data.systems and cartel_data.systems[target_name] then
                UI.galaxy.current_system_loading = {cartel = cartel_name, system = target_name}
                UI.galaxy.planet_capture_active = true
                UI.galaxy.planet_list = {}
                sendAll("di system " .. target_name, false)
                return
            end
        end
        UI.galaxy.loading = false
        UI.galaxy.loading_automated = false
    end
end

-- Parse cartel list
function ui_galaxy_parse_cartels(cartel_list)
    if not UI.galaxy.loading_automated then return end
    
    for _, cartel_name in ipairs(cartel_list) do
        UI.galaxy.cartels[cartel_name] = UI.galaxy.cartels[cartel_name] or {}
        UI.galaxy.cartels[cartel_name].name = cartel_name
        UI.galaxy.cartels[cartel_name].systems = UI.galaxy.cartels[cartel_name].systems or {}
        table.insert(UI.galaxy.load_queue, {type = "cartel", name = cartel_name})
    end
    
    f2t_debug_log("[galaxy] Found %d cartels", #cartel_list)
    ui_galaxy_process_queue()
end

-- Process loading queue
function ui_galaxy_process_queue()
    if #UI.galaxy.load_queue == 0 then
        UI.galaxy.loading = false
        UI.galaxy.loading_automated = false
        UI.galaxy.last_updated = os.time()
        ui_galaxy_save()
        
        cecho("\n<green>[Galaxy]<reset> Galaxy data loaded successfully!\n")
        
        if UI.galaxy_dropdown and UI.galaxy_dropdown:isVisible() then
            ui_populate_galaxy_dropdown()
        end
        return
    end
    
    local next_item = table.remove(UI.galaxy.load_queue, 1)
    
    if next_item.type == "cartel" then
        UI.galaxy.current_cartel_loading = next_item.name
        UI.galaxy.member_capture_active = true
        UI.galaxy.member_list = {}
        UI.galaxy.member_capturing = false
        
        tempTimer(0.3, function()
            sendAll("di cartel " .. next_item.name, false)
        end)
    elseif next_item.type == "system" then
        UI.galaxy.current_system_loading = {cartel = next_item.cartel, system = next_item.name}
        UI.galaxy.planet_capture_active = true
        UI.galaxy.planet_list = {}
        
        tempTimer(0.3, function()
            sendAll("di system " .. next_item.name, false)
        end)
    end
end

-- Parse cartel info
function ui_galaxy_parse_cartel_info(cartel_name, members)
    if not UI.galaxy.loading_automated then return end
    if not UI.galaxy.cartels[cartel_name] then return end
    
    UI.galaxy.cartels[cartel_name].members = members
    UI.galaxy.cartel_timestamps[cartel_name] = os.time()
    
    for _, system_name in ipairs(members) do
        table.insert(UI.galaxy.load_queue, {
            type = "system",
            name = system_name,
            cartel = cartel_name
        })
    end
    
    f2t_debug_log("[galaxy] Cartel %s has %d systems", cartel_name, #members)
    tempTimer(0.3, function() ui_galaxy_process_queue() end)
end

-- Parse system info
function ui_galaxy_parse_system_info(system_name, cartel_name, planets)
    if not UI.galaxy.loading_automated then return end
    if not UI.galaxy.cartels[cartel_name] then return end
    
    UI.galaxy.cartels[cartel_name].systems[system_name] = {
        name = system_name,
        cartel = cartel_name,
        planets = planets
    }
    UI.galaxy.system_timestamps[cartel_name .. ":" .. system_name] = os.time()
    
    f2t_debug_log("[galaxy] System %s has %d planets", system_name, #planets)
    tempTimer(0.3, function() ui_galaxy_process_queue() end)
end

-- Navigate to location
function ui_galaxy_nav_to(location_type, location_name)
    if location_type == "planet" then
        send("nav " .. location_name)
    elseif location_type == "system" then
        send("nav " .. location_name .. " link")
    end
    
    if UI.galaxy_dropdown then
        UI.galaxy_dropdown:hide()
        UI.galaxy_button_active = false
    end
end

-- Get info about location
function ui_galaxy_get_info(location_type, location_name)
    local was_automated = UI.galaxy.loading_automated
    UI.galaxy.loading_automated = false
    
    if location_type == "cartel" then
        send("di cartel " .. location_name)
    elseif location_type == "system" then
        send("di system " .. location_name)
    elseif location_type == "planet" then
        send("di planet " .. location_name)
    end
    
    tempTimer(0.5, function()
        UI.galaxy.loading_automated = was_automated
    end)
end

-- ============================================================================
-- LINE CAPTURE HANDLERS
-- ============================================================================

function ui_galaxy_capture_cartel_line(line)
    if not UI.galaxy.cartel_capture_active then return end
    if not UI.galaxy.loading_automated then return end
    
    local cartel = line:match("^%s*(.-)%s*$")
    if cartel and cartel ~= "" then
        table.insert(UI.galaxy.cartel_list, cartel)
    end
end

function ui_galaxy_finish_cartel_capture()
    if not UI.galaxy.cartel_capture_active then return end
    
    UI.galaxy.cartel_capture_active = false
    
    if #UI.galaxy.cartel_list > 0 then
        ui_galaxy_parse_cartels(UI.galaxy.cartel_list)
    else
        cecho("\n<red>[Galaxy]<reset> No cartels captured!\n")
        UI.galaxy.loading = false
        UI.galaxy.loading_automated = false
    end
end

function ui_galaxy_start_member_capturing()
    if not UI.galaxy.member_capture_active then return end
    if not UI.galaxy.loading_automated then return end
    
    UI.galaxy.member_capturing = true
end

function ui_galaxy_capture_member_line(line)
    if not UI.galaxy.member_capture_active then return end
    if not UI.galaxy.loading_automated then return end
    if not UI.galaxy.member_capturing then return end
    
    if line and line ~= "" then
        table.insert(UI.galaxy.member_list, line)
    end
end

function ui_galaxy_finish_member_capture()
    if not UI.galaxy.member_capture_active then return end
    
    UI.galaxy.member_capture_active = false
    UI.galaxy.member_capturing = false
    local cartel_name = UI.galaxy.current_cartel_loading
    
    if cartel_name then
        if #UI.galaxy.member_list > 0 then
            ui_galaxy_parse_cartel_info(cartel_name, UI.galaxy.member_list)
        else
            tempTimer(0.3, function() ui_galaxy_process_queue() end)
        end
    end
end

function ui_galaxy_capture_planet_line(planet_name, system_name, cartel_name)
    if not UI.galaxy.planet_capture_active then return end
    if not UI.galaxy.loading_automated then return end
    
    table.insert(UI.galaxy.planet_list, {
        name = planet_name,
        system = system_name,
        cartel = cartel_name
    })
end

function ui_galaxy_finish_planet_capture()
    if not UI.galaxy.planet_capture_active then return end
    
    UI.galaxy.planet_capture_active = false
    local system_info = UI.galaxy.current_system_loading
    
    if system_info and #UI.galaxy.planet_list > 0 then
        ui_galaxy_parse_system_info(system_info.system, system_info.cartel, UI.galaxy.planet_list)
    elseif system_info then
        tempTimer(0.3, function() ui_galaxy_process_queue() end)
    end
end

-- ============================================================================
-- CONFIRMATION POPUP
-- ============================================================================

function ui_show_refresh_confirmation()
    if UI.galaxy_confirm_popup then
        UI.galaxy_confirm_popup:hide()
    end
    
    UI.galaxy_confirm_popup = Geyser.Label:new({
        name = "galaxy_confirm_popup",
        x = "35%", y = "40%",
        width = "30%", height = "20%"
    })
    
    UI.galaxy_confirm_popup:setStyleSheet([[
        background-color: rgba(35, 35, 45, 240);
        border: 2px solid rgba(255, 255, 255, 0.46);
        border-radius: 5px;
        box-shadow: 0 10px 30px rgba(0, 0, 0, 0.6);
        -webkit-backdrop-filter: blur(4px) saturate(110%);
        backdrop-filter: blur(4px) saturate(110%);
    ]])
    
    local title = Geyser.Label:new({
        x = 0, y = "5%",
        width = "100%", height = "25%"
    }, UI.galaxy_confirm_popup)
    title:setStyleSheet([[
        background-color: transparent;
        color: rgba(200, 200, 210, 255);
        font-size: 14px;
        font-weight: bold;
    ]])
    title:echo("<center>Refresh All Galaxy Data?</center>")
    
    local message = Geyser.Label:new({
        x = "5%", y = "30%",
        width = "90%", height = "30%"
    }, UI.galaxy_confirm_popup)
    message:setStyleSheet([[
        background-color: transparent;
        color: rgba(200, 200, 210, 200);
        font-size: 11px;
    ]])
    message:echo("<center>This will take 1-2 minutes</center>")
    
    local ok_btn = Geyser.Label:new({
        x = "15%", y = "65%",
        width = "30%", height = "25%"
    }, UI.galaxy_confirm_popup)
    ok_btn:setStyleSheet(UI.style.button_css)
    ok_btn:echo("<center>OK</center>")
    ok_btn:setClickCallback(function()
        UI.galaxy_confirm_popup:hide()
        UI.galaxy.loaded = false
        UI.galaxy.cartels = {}
        ui_galaxy_init("all")
    end)
    
    local cancel_btn = Geyser.Label:new({
        x = "55%", y = "65%",
        width = "30%", height = "25%"
    }, UI.galaxy_confirm_popup)
    cancel_btn:setStyleSheet(UI.style.button_css)
    cancel_btn:echo("<center>Cancel</center>")
    cancel_btn:setClickCallback(function()
        UI.galaxy_confirm_popup:hide()
    end)
    
    UI.galaxy_confirm_popup:show()
    UI.galaxy_confirm_popup:raise()
end

-- ============================================================================
-- galaxy UI (PROPERLY STYLED)
-- ============================================================================

UI.galaxy_button_active = false

function ui_build_galaxy_dropdown()
    if UI.galaxy_dropdown then
        UI.galaxy_dropdown:hide()
        return
    end
    
    -- Main container using frame style
    UI.galaxy_dropdown = Adjustable.Container:new({
        name = "galaxy_dropdown",
        x = "75%",
        y = "15%",
        width = "20%",
        height = "75%",
        adjLabelstyle = UI.style.frame_css,
        autoSave = false,
        autoLoad = false
    })
    UI.galaxy_dropdown:lockContainer("border")
    
    UI.galaxy_dropdown:hide()
    f2t_ui_register_container("galaxy_dropdown", UI.galaxy_dropdown)

    -- Top bar with title and close button
    UI.galaxy_topbar = Geyser.Label:new({
        name = "galaxy_topbar",
        x = 0, y = 0,
        width = "100%",
        height = "25px"
    }, UI.galaxy_dropdown)
    UI.galaxy_topbar:setStyleSheet(UI.style.header_label_css)
    
    -- Title (top left)
    UI.galaxy_title = Geyser.Label:new({
        x = "5px", y = 0,
        width = "200px", height = "25px"
    }, UI.galaxy_topbar)
    UI.galaxy_title:setStyleSheet([[
        background-color: transparent;
        color: #c8c8d0;
        font-size: 12px;
        font-weight: bold;
    ]])
    UI.galaxy_title:echo("Galaxy Navigator")
    
    -- Refresh All icon (top right, before close)
    UI.galaxy_refresh_icon = Geyser.Label:new({
        x = "-50px", y = "2px",
        width = "20px", height = "20px"
    }, UI.galaxy_topbar)
    UI.galaxy_refresh_icon:setStyleSheet(UI.style.button_css)
    UI.galaxy_refresh_icon:echo("<center>⟳</center>")
    UI.galaxy_refresh_icon:setClickCallback(function()
        ui_show_refresh_confirmation()
    end)
    UI.galaxy_refresh_icon:setToolTip("Refresh all galaxy data")
    
    -- Close button
    UI.galaxy_close = Geyser.Label:new({
        x = "-25px", y = "2px",
        width = "20px", height = "20px"
    }, UI.galaxy_topbar)
    UI.galaxy_close:setStyleSheet([[
        QLabel{
            background-color: rgba(180, 50, 50, 200);
            border: 1px solid rgba(200, 80, 80, 180);
            border-radius: 3px;
            color: white;
            font-size: 12px;
        }
        QLabel::hover{
            background-color: rgba(200, 60, 60, 220);
            border-color: rgba(220, 100, 100, 200);
        }
    ]])
    UI.galaxy_close:echo("<center>✕</center>")
    UI.galaxy_close:setClickCallback(function()
        UI.galaxy_dropdown:hide()
        UI.galaxy.visible       = false
        UI.galaxy_button_active = false
    end)
    
    -- Scrollable content area
    UI.galaxy_scroll = Geyser.ScrollBox:new({
        name = "galaxy_scroll",
        x = "0%", y = "0%",
        width = "100%",
        height = "-42px",
        backgroundColor = "black"
    }, UI.galaxy_dropdown)

    -- Bottom status bar
    UI.galaxy_statusbar = Geyser.Label:new({
        name = "galaxy_statusbar",
        x = 0, y = "-25px",
        width = "100%",
        height = "25px"
    }, UI.galaxy_dropdown)
    UI.galaxy_statusbar:setStyleSheet(UI.style.header_label_css)
    
    -- Cartel count (bottom left)
    UI.galaxy_status = Geyser.Label:new({
        x = "5px", y = 0,
        width = "150px", height = "25px"
    }, UI.galaxy_statusbar)
    UI.galaxy_status:setStyleSheet([[
        background-color: black;
        color: rgba(200, 200, 210, 180);
        font-size: 10px;
    ]])
    
    -- Last updated (bottom left, after count)
    UI.galaxy_age = Geyser.Label:new({
        x = "160px", y = 0,
        width = "200px", height = "25px"
    }, UI.galaxy_statusbar)
    UI.galaxy_age:setStyleSheet([[
        background-color: black;
        color: rgba(150, 150, 160, 160);
        font-size: 9px;
    ]])
end

-- Create galaxy row (NO HBOX - individual labels)
function ui_create_galaxy_row(parent, name, type, indent_level, y_pos, data)
    local indent_px = indent_level * 15
    local row_height = 20
    
    -- Row container
    local row = Geyser.Label:new({
        x = indent_px .. "px",
        y = y_pos,
        width = "100%",
        height = row_height .. "px"
    }, parent)
    row:setStyleSheet([[
        background-color: black;
    ]])
    
    -- Expand/collapse
    if type == "cartel" or type == "system" then
        local expand_btn = Geyser.Label:new({
            x = "0%", y = 0,
            width = "5%", height = "100%"
        }, row)
        
        local key = type == "cartel" and name or (data.cartel .. ":" .. name)
        local is_expanded = UI.galaxy.expanded[key] or false
        
        expand_btn:setStyleSheet(UI.style.button_css)
        expand_btn:echo(is_expanded and "<center>−</center>" or "<center>+</center>")
        expand_btn:setClickCallback(function()
            UI.galaxy.expanded[key] = not UI.galaxy.expanded[key]
            ui_galaxy_save()
            ui_populate_galaxy_dropdown()
        end)
    end
    
    -- Icon (3%)
    local icon = Geyser.Label:new({
        x = "6%", y = 0,
        width = "3%", height = "100%"
    }, row)
    
    local icon_text, icon_color
    if type == "cartel" then
        icon_text = "🌌"
        icon_color = "#ff6b9d"
    elseif type == "system" then
        icon_text = "⭐"
        icon_color = "#ffd700"
    else
        icon_text = "🌍"
        icon_color = "#4ecdc4"
    end
    
    icon:setStyleSheet(string.format([[
        background-color: black;
        color: %s;
        font-size: 11px;
    ]], icon_color))
    icon:echo("<center>" .. icon_text .. "</center>")
    
    -- Name (50% - standard size)
    local name_label = Geyser.Label:new({
        x = "10%", y = 0,
        width = "40%", height = "100%"
    }, row)
    name_label:setStyleSheet(UI.style.button_css)
    name_label:echo(name)
    name_label:setClickCallback(function()
        ui_galaxy_get_info(type, name)
    end)
    
    -- Nav button
    if type == "system" or type == "planet" then
        local nav_btn = Geyser.Label:new({
            x = "91%", y = 0,
            width = "4%", height = "100%"
        }, row)
        nav_btn:setStyleSheet([[
            QLabel{
                background-color: rgba(40, 120, 80, 200);
                border: 1px solid rgba(60, 140, 100, 180);
                border-radius: 3px;
                color: white;
                font-size: 10px;
                font-weight: bold;
            }
            QLabel::hover{
                background-color: rgba(50, 140, 90, 220);
                border-color: rgba(80, 160, 120, 200);
            }
        ]])
        nav_btn:echo("<center>→</center>")
        nav_btn:setClickCallback(function()
            ui_galaxy_nav_to(type, name)
        end)
        nav_btn:setToolTip("Navigate here")
    end
    
    -- Refresh button (4%, last position, cartels/systems only)
    if type == "cartel" or type == "system" then
        local refresh_btn = Geyser.Label:new({
            x = "96%", y = 0,
            width = "4%", height = "100%"
        }, row)
        refresh_btn:setStyleSheet(UI.style.button_css)
        refresh_btn:echo("<center>⟳</center>")
        
        -- Set tooltip with age
        local age_text = ui_galaxy_get_item_age(type, data.cartel or name, type == "system" and name or nil)
        refresh_btn:setToolTip(age_text)
        
        refresh_btn:setClickCallback(function()
            ui_galaxy_init(type, name)
            tempTimer(0.5, function()
                if UI.galaxy_dropdown and UI.galaxy_dropdown:isVisible() then
                    ui_populate_galaxy_dropdown()
                end
            end)
        end)
    end
    
    return row
end

-- Populate galaxy dropdown
function ui_populate_galaxy_dropdown()
    if not UI.galaxy_scroll then return end
    
    -- Update displays
    if UI.galaxy_age then
        UI.galaxy_age:echo(ui_galaxy_get_age())
    end
    
    -- Recreate content
    if UI.galaxy_scroll_content then
        UI.galaxy_scroll_content:hide()
        UI.galaxy_scroll_content = nil
    end
    
    UI.galaxy_scroll_content = Geyser.Container:new({
        name = "galaxy_scroll_content",
        x = 0, y = 0,
        width = "100%",
        height = "100%"
    }, UI.galaxy_scroll)
    
    -- Update status
    if UI.galaxy.loading then
        if UI.galaxy_status then
            UI.galaxy_status:echo("Loading...")
        end
        local loading_label = Geyser.Label:new({
            x = 0, y = 0,
            width = "100%",
            height = "30px"
        }, UI.galaxy_scroll_content)
        loading_label:setStyleSheet([[
            background-color: black;
            color: rgba(200, 200, 100, 200);
            padding: 10px;
        ]])
        loading_label:echo("<center>Loading galaxy data...</center>")
        return
    elseif not UI.galaxy.loaded then
        if UI.galaxy_status then
            UI.galaxy_status:echo("No data")
        end
        local error_label = Geyser.Label:new({
            x = 0, y = 0,
            width = "100%",
            height = "60px"
        }, UI.galaxy_scroll_content)
        error_label:setStyleSheet([[
            background-color: transparent;
            color: rgba(200, 100, 100, 200);
            padding: 10px;
        ]])
        error_label:echo("<center>No galaxy data<br/>Click ⟳ to load</center>")
        return
    end
    
    -- Count items
    local cartel_count = 0
    for _ in pairs(UI.galaxy.cartels) do cartel_count = cartel_count + 1 end
    if UI.galaxy_status then
        UI.galaxy_status:echo(string.format("%d cartels", cartel_count))
    end
    
    local y_offset = 2
    local row_height = 22
    
    -- Sort cartels
    local sorted_cartels = {}
    for cartel_name, _ in pairs(UI.galaxy.cartels) do
        table.insert(sorted_cartels, cartel_name)
    end
    table.sort(sorted_cartels)
    
    -- Build tree view
    for _, cartel_name in ipairs(sorted_cartels) do
        local cartel_data = UI.galaxy.cartels[cartel_name]
        
        ui_create_galaxy_row(
            UI.galaxy_scroll_content,
            cartel_name,
            "cartel",
            0,
            y_offset,
            cartel_data
        )
        y_offset = y_offset + row_height
        
        if UI.galaxy.expanded[cartel_name] then
            local sorted_systems = {}
            for system_name, _ in pairs(cartel_data.systems or {}) do
                table.insert(sorted_systems, system_name)
            end
            table.sort(sorted_systems)
            
            for _, system_name in ipairs(sorted_systems) do
                local system_data = cartel_data.systems[system_name]
                
                ui_create_galaxy_row(
                    UI.galaxy_scroll_content,
                    system_name,
                    "system",
                    1,
                    y_offset,
                    system_data
                )
                y_offset = y_offset + row_height
                
                local sys_key = cartel_name .. ":" .. system_name
                if UI.galaxy.expanded[sys_key] then
                    for _, planet_data in ipairs(system_data.planets or {}) do
                        ui_create_galaxy_row(
                            UI.galaxy_scroll_content,
                            planet_data.name,
                            "planet",
                            2,
                            y_offset,
                            planet_data
                        )
                        y_offset = y_offset + row_height
                    end
                end
            end
        end
    end
end

function ui_toggle_galaxy()
    if not UI.galaxy_dropdown then
        ui_build_galaxy_dropdown()
    end

    if UI.galaxy.visible then
        UI.galaxy_dropdown:hide()
        UI.galaxy.visible       = false
        UI.galaxy_button_active = false
    else
        if not UI.galaxy.loaded and not UI.galaxy.loading then
            if not ui_galaxy_load() then
                ui_galaxy_init("all")
            end
        end
        ui_populate_galaxy_dropdown()
        UI.galaxy_dropdown:show()
        UI.galaxy_dropdown:raise()
        UI.galaxy.visible       = true
        UI.galaxy_button_active = true
    end
end