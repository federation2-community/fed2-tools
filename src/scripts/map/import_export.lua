-- fed2-tools map — map import/export (ported from map_import_export.lua)

function f2t_map_export()
    local rooms = getRooms()
    local room_count = 0
    for _ in pairs(rooms) do room_count = room_count + 1 end
    if room_count == 0 then
        cecho("\n<yellow>[map]<reset> No rooms to export. Map is empty.\n"); return false
    end
    local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
    local default_filename = string.format("f2t_map_export_%s.json", timestamp)
    cecho(string.format("\n<green>[map]<reset> Select directory to save: <white>%s<reset>\n", default_filename))
    local file_path = invokeFileDialog(false, "Select Directory for Map Export")
    if not file_path or file_path == "" then
        cecho("\n<yellow>[map]<reset> Export cancelled.\n"); return false
    end
    file_path = string.format("%s/%s", file_path:gsub("/$", ""), default_filename)
    local success, error_msg = saveJsonMap(file_path)
    if success then
        cecho("\n<green>[map]<reset> Map exported successfully\n")
        cecho(string.format("\n<dim_grey>  Rooms: %d<reset>\n", room_count))
        cecho(string.format("\n<dim_grey>  File: %s<reset>\n", file_path))
        return true
    else
        cecho("\n<red>[map]<reset> Export failed\n")
        if error_msg then cecho(string.format("\n<dim_grey>  Error: %s<reset>\n", error_msg)) end
        return false
    end
end

local function get_map_file_info(file_path)
    local file = io.open(file_path, "r")
    if not file then return nil, nil, "File not found" end
    local content = file:read("*all"); file:close()
    local success, data = pcall(yajl.to_value, content)
    if not success then return nil, nil, "Invalid JSON format" end
    if not data or type(data) ~= "table" then return nil, nil, "Invalid map format" end
    local room_count, area_count = 0, 0
    if data.areas and type(data.areas) == "table" then
        for _, area in ipairs(data.areas) do
            if area.rooms and type(area.rooms) == "table" then
                local area_room_count = 0
                for _ in ipairs(area.rooms) do room_count = room_count + 1; area_room_count = area_room_count + 1 end
                if area_room_count > 0 then area_count = area_count + 1 end
            end
        end
    end
    return room_count, area_count, nil
end

-- Silently import a map from a known file path. No file dialog, no
-- confirmation prompt, no console output — the caller decides how to report.
-- Wipes the current map, loads the JSON, refreshes the renderer, and (if the
-- mapper is enabled) syncs to the current location.
--
-- Returns: ok (boolean), room_count (number) on success, or error_msg (string)
-- on failure.  Single source of truth for "load a map file into the profile" —
-- the resource-picker dialog and f2t_map_import_execute both route through it.
function f2t_map_import_file(file_path)
    local file = io.open(file_path, "r")
    if not file then return false, "File not found" end
    file:close()

    deleteMap()
    F2T_MAP_CURRENT_ROOM_ID = nil

    local success, error_msg = loadJsonMap(file_path)
    if not success then return false, error_msg or "unknown error" end

    updateMap()
    local new_room_count = 0
    for _ in pairs(getRooms()) do new_room_count = new_room_count + 1 end

    -- The imported map carries its own topology model (map userdata) or at
    -- least area cartel data: reload and re-derive the jump graph from it.
    F2T_MAP_TOPOLOGY = {systems = {}, cartels = {}, syndicates = {}, synced_at = nil}
    F2T_MAP_TOPOLOGY_LOADED = false
    f2t_map_topology_load()
    f2t_map_topology_request_rebuild()

    if F2T_MAP_ENABLED and f2t_map_sync then
        tempTimer(0.5, function() f2t_map_sync() end)
    end

    return true, new_room_count
end

local function f2t_map_import_execute(data)
    local file_path = data.file_path
    local ok, result = f2t_map_import_file(file_path)
    if ok then
        cecho("\n<green>[map]<reset> Map imported successfully\n")
        cecho(string.format("\n<dim_grey>  Rooms: %d<reset>\n", result))
        cecho(string.format("\n<dim_grey>  File: %s<reset>\n", file_path))
        if F2T_MAP_ENABLED then
            cecho("\n<green>[map]<reset> Synchronizing with current location...\n")
        end
        return true
    else
        cecho("\n<red>[map]<reset> Import failed\n")
        if result then cecho(string.format("\n<dim_grey>  Error: %s<reset>\n", result)) end
        return false
    end
end

function f2t_map_import()
    cecho("\n<green>[map]<reset> Select map file to import...\n")
    local file_path = invokeFileDialog(true, "Open Map File (JSON format)")
    if not file_path or file_path == "" then
        cecho("\n<yellow>[map]<reset> Import cancelled.\n"); return false
    end
    local import_room_count, import_area_count, error_msg = get_map_file_info(file_path)
    if not import_room_count then
        cecho("\n<red>[map]<reset> Cannot read map file\n")
        if error_msg then cecho(string.format("\n<dim_grey>  Error: %s<reset>\n", error_msg)) end
        return false
    end
    local rooms = getRooms()
    local current_room_count = 0
    for _ in pairs(rooms) do current_room_count = current_room_count + 1 end
    local areas = getAreaTable()
    local current_area_count = 0
    for _, area_id in pairs(areas) do
        local area_rooms = getAreaRooms(area_id)
        if area_rooms and next(area_rooms) ~= nil then current_area_count = current_area_count + 1 end
    end

    cecho("\n<cyan>[map]<reset> Import Summary:\n")
    cecho(string.format("\n  File: %s\n", file_path))
    cecho(string.format("\n  Map import: %d rooms across %d areas\n", import_room_count, import_area_count))
    if current_room_count > 0 then
        cecho(string.format("\n  Current map: %d rooms across %d areas\n", current_room_count, current_area_count))
        cecho("\n<yellow>[map]<reset> WARNING: Import will DELETE your current map!\n")
        cecho("\n<cyan>[map]<reset> TIP: Use <white>map export<reset> to backup your current map first.\n")
    else
        cecho("\n  Current map: empty\n")
    end

    local action = string.format("import map (%d rooms, %d areas)", import_room_count, import_area_count)
    if current_room_count > 0 then
        action = string.format("import map and DELETE current map (%d -> %d rooms)",
            current_room_count, import_room_count)
    end

    f2t_map_manual_request_confirmation(action, f2t_map_import_execute, {
        file_path  = file_path,
        room_count = import_room_count,
        area_count = import_area_count,
    })
    return nil
end
