-- fed2-tools map — map import/export (ported from map_import_export.lua)
--
-- Two code paths, selected on whether a mapper widget is live (see
-- f2tMapHasLiveMapper in ui/content/map.lua):
--
--   Native  — a Fed2 Map pane is mounted (Full/BYOW mode, or after "mux start"
--             + opening the map). Mudlet's own loadJsonMap/saveJsonMap run; the
--             visible map keeps every decorative detail (custom exit lines, env
--             colours) exactly as before. Unchanged reference behaviour.
--
--   Headless — no widget (Minimal mode). loadJsonMap/saveJsonMap refuse to run
--             without one ("no map present or loaded"), so the map database is
--             rebuilt/serialised directly through the same room-database API the
--             auto-mapper already uses with no widget: addRoom, setExit,
--             setExitStub, addSpecialExit, setRoomIDbyHash, setRoomUserData, …
--             The user's Mudlet layout is never touched (Minimal's promise), and
--             everything functional round-trips — rooms, areas, coordinates,
--             environments, symbols, hashes, user data, standard/special/stub
--             exits and locks. Purely decorative custom exit lines are dropped:
--             there is no map being drawn in this mode for them to appear on.

-- Mudlet exit-direction numbers (setExit/setExitStub/getExitStubs1) <-> the long
-- names used in the JSON format and by f2t_map_direction_to_number.
local _DIR_NUM_TO_NAME = {
    [1]="north",[2]="northeast",[3]="northwest",[4]="east",[5]="west",[6]="south",
    [7]="southeast",[8]="southwest",[9]="up",[10]="down",[11]="in",[12]="out",
}

-- Serialise the current room database to a formatVersion-1 JSON map file without
-- a mapper widget. Returns ok (boolean), error_msg (string) on failure.
function f2t_map_save_json_headless(file_path)
    if type(yajl) ~= "table" or type(yajl.to_string) ~= "function" then
        return false, "yajl.to_string unavailable"
    end

    local area_table = getAreaTable() or {}   -- { name = id }
    local areas_out  = {}
    local total_rooms = 0

    for area_name, area_id in pairs(area_table) do
        local room_ids = getAreaRooms(area_id) or {}
        local rooms_out = {}

        for _, rid in pairs(room_ids) do
            if roomExists(rid) then
                local x, y, z = getRoomCoordinates(rid)
                local room = {
                    id          = rid,
                    name        = getRoomName(rid) or "",
                    coordinates = { x or 0, y or 0, z or 0 },
                    environment = getRoomEnv(rid) or 0,
                }

                local sym = getRoomChar(rid)
                if sym and sym ~= "" then room.symbol = sym end
                local hash = getRoomHashByID(rid)
                if hash and hash ~= "" then room.hash = hash end
                if roomLocked(rid) then room.locked = true end

                local ud
                local ok_ud, all_ud = pcall(getAllRoomUserData, rid)
                if ok_ud and type(all_ud) == "table" then ud = all_ud end
                if ud and next(ud) ~= nil then room.userData = ud end

                -- Standard exits (+ per-exit locks).
                local exits = {}
                for dir, dest in pairs(getRoomExits(rid) or {}) do
                    local e = { name = dir, exitId = dest }
                    local ok_lock, locked = pcall(hasExitLock, rid, dir)
                    if ok_lock and locked then e.locked = true end
                    exits[#exits + 1] = e
                end
                -- Special (command) exits: getSpecialExitsSwap → { destId = command }.
                local ok_sp, specials = pcall(getSpecialExitsSwap, rid)
                if ok_sp and type(specials) == "table" then
                    for dest, command in pairs(specials) do
                        local dest_id = tonumber(dest)
                        if dest_id then exits[#exits + 1] = { name = tostring(command), exitId = dest_id } end
                    end
                end
                if #exits > 0 then room.exits = exits end

                -- Stub exits (getExitStubs1 → list of direction numbers).
                local stubs_out = {}
                local ok_st, stubs = pcall(getExitStubs1, rid)
                if ok_st and type(stubs) == "table" then
                    for _, num in pairs(stubs) do
                        local dname = _DIR_NUM_TO_NAME[num]
                        if dname then stubs_out[#stubs_out + 1] = { name = dname } end
                    end
                end
                if #stubs_out > 0 then room.stubExits = stubs_out end

                rooms_out[#rooms_out + 1] = room
                total_rooms = total_rooms + 1
            end
        end

        local area = { id = area_id, name = area_name, roomCount = #rooms_out, rooms = rooms_out }
        local ok_aud, aud = pcall(getAllAreaUserData, area_id)
        if ok_aud and type(aud) == "table" and next(aud) ~= nil then area.userData = aud end
        areas_out[#areas_out + 1] = area
    end

    -- Custom environment colours, if the reader is available.
    local env_out = {}
    local ok_env, env_tbl = pcall(getCustomEnvColorTable)
    if ok_env and type(env_tbl) == "table" then
        for env_id, rgba in pairs(env_tbl) do
            if type(rgba) == "table" and #rgba >= 3 then
                env_out[#env_out + 1] = { id = env_id, color24RGB = { rgba[1], rgba[2], rgba[3] } }
            end
        end
    end

    local doc = {
        formatVersion   = 1,
        roomCount       = total_rooms,
        areaCount       = #areas_out,
        defaultAreaName = "Default Area",
        anonymousAreaName = "Unnamed Area",
        customEnvColors = env_out,
        areas           = areas_out,
    }

    local ok_ser, json = pcall(yajl.to_string, doc)
    if not ok_ser or type(json) ~= "string" then return false, "JSON serialisation failed" end

    local f, ferr = io.open(file_path, "w")
    if not f then return false, ferr or "cannot open file for writing" end
    f:write(json); f:close()
    return true
end

-- Wipe the room database without a widget (deleteMap needs one; this does not).
local function wipe_map_headless()
    for room_id in pairs(getRooms() or {}) do pcall(deleteRoom, room_id) end
    for _, area_id in pairs(getAreaTable() or {}) do
        if area_id and area_id ~= -1 then pcall(deleteArea, area_id) end
    end
end

-- Rebuild the room database from a formatVersion-1 JSON map file without a
-- mapper widget. Returns ok (boolean), error_msg (string) on failure.
function f2t_map_load_json_headless(file_path)
    local file = io.open(file_path, "r")
    if not file then return false, "File not found" end
    local content = file:read("*all"); file:close()

    if type(yajl) ~= "table" or type(yajl.to_value) ~= "function" then
        return false, "yajl.to_value unavailable"
    end
    local ok, data = pcall(yajl.to_value, content)
    if not ok then return false, "Invalid JSON format" end
    if type(data) ~= "table" or type(data.areas) ~= "table" then
        return false, "Invalid map format"
    end

    wipe_map_headless()

    -- Custom environment colours (decorative, but DB-level and cheap).
    if type(data.customEnvColors) == "table" then
        for _, c in ipairs(data.customEnvColors) do
            local rgb = c.color24RGB
            if c.id and type(rgb) == "table" and #rgb >= 3 then
                pcall(setCustomEnvColor, c.id, rgb[1], rgb[2], rgb[3], 255)
            end
        end
    end

    -- Create areas first; map each file area id to the real id Mudlet assigns.
    -- (fed2-tools resolves areas by name and rooms by hash, not by fixed area
    -- id, so remapping ids is safe — room->room exits use global room ids, which
    -- addRoom preserves exactly below.)
    local area_id_map = {}
    for _, area in ipairs(data.areas) do
        if type(area.rooms) == "table" and #area.rooms > 0 and not area_id_map[area.id] then
            local real_id = addAreaName(area.name or "Unnamed Area")
            if type(real_id) == "number" and real_id > 0 then
                area_id_map[area.id] = real_id
                if type(area.userData) == "table" then
                    for k, v in pairs(area.userData) do
                        pcall(setAreaUserData, real_id, tostring(k), tostring(v))
                    end
                end
            end
        end
    end

    -- Pass 1 — create every room and its attributes. Exits are deferred to pass
    -- 2 because a destination room may not exist yet while its source is built.
    local created = 0
    for _, area in ipairs(data.areas) do
        local real_area = area_id_map[area.id]
        if real_area and type(area.rooms) == "table" then
            for _, room in ipairs(area.rooms) do
                local rid = room.id
                if rid and addRoom(rid) then
                    setRoomArea(rid, real_area)
                    local c = room.coordinates
                    if type(c) == "table" and #c >= 3 then
                        setRoomCoordinates(rid, c[1], c[2], c[3])
                    end
                    if room.environment then setRoomEnv(rid, room.environment) end
                    if room.name then setRoomName(rid, room.name) end
                    if room.symbol and room.symbol ~= "" then setRoomChar(rid, room.symbol) end
                    if room.hash and room.hash ~= "" then setRoomIDbyHash(rid, room.hash) end
                    if type(room.userData) == "table" then
                        for k, v in pairs(room.userData) do
                            setRoomUserData(rid, tostring(k), tostring(v))
                        end
                    end
                    if room.locked then pcall(lockRoom, rid, true) end
                    created = created + 1
                end
            end
        end
    end

    -- Pass 2 — wire exits and stubs now that every room exists.
    for _, area in ipairs(data.areas) do
        if type(area.rooms) == "table" then
            for _, room in ipairs(area.rooms) do
                local rid = room.id
                if rid and roomExists(rid) then
                    for _, ex in ipairs(room.exits or {}) do
                        local dest, name = ex.exitId, ex.name
                        if dest and name and roomExists(dest) then
                            local dir_num = f2t_map_direction_to_number(name)
                            if dir_num then
                                setExit(rid, dest, dir_num)
                                if ex.locked then pcall(lockExit, rid, dir_num, true) end
                            else
                                pcall(addSpecialExit, rid, dest, name)
                            end
                        end
                    end
                    for _, st in ipairs(room.stubExits or {}) do
                        local dir_num = st.name and f2t_map_direction_to_number(st.name)
                        if dir_num then setExitStub(rid, dir_num, true) end
                    end
                end
            end
        end
    end

    return true, created
end

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
    -- saveJsonMap needs a live mapper widget. That exists in Full mode, and in
    -- BYOW only once the map pane is added; it is absent in Minimal mode and in
    -- BYOW before the pane is added (Muxlet running, blank default workspace, no
    -- map content). Serialise the database directly when there is no widget, and
    -- fall back to that headless path if a native save is attempted but fails.
    local success, error_msg
    if type(f2tMapHasLiveMapper) == "function" and f2tMapHasLiveMapper() then
        success, error_msg = saveJsonMap(file_path)
    end
    if not success then
        success, error_msg = f2t_map_save_json_headless(file_path)
    end
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
    -- Validate (and fully parse) the file BEFORE any destructive step, so that
    -- no code path can wipe the current map for an unreadable/invalid file —
    -- true whichever loader runs below.
    local file_rooms, _, verr = get_map_file_info(file_path)
    if not file_rooms then return false, verr or "invalid map file" end

    F2T_MAP_CURRENT_ROOM_ID = nil

    -- Mudlet's native deleteMap/loadJsonMap only work with a live mapper widget
    -- (else "no map present or loaded"). That widget exists once the Fed2 Map
    -- pane has been mounted: always in Full mode, but in BYOW ONLY after the
    -- user adds the map content, and never in Minimal mode. So:
    --   * widget live  -> native loader (keeps the visible map's decorative
    --                     data), then fall through to headless if it fails;
    --   * no widget    -> headless rebuild straight through the room-database
    --                     API. This covers Minimal mode AND BYOW before the map
    --                     pane is added — Muxlet may be running with a blank
    --                     default workspace and no map content, which is exactly
    --                     when there is still no widget.
    -- The headless fallback also runs if a native attempt fails for any reason;
    -- the file is already validated and the headless path re-wipes from it, so a
    -- failed native attempt can never leave a half-cleared map. See
    -- f2tMapHasLiveMapper in ui/content/map.lua.
    local success, error_msg
    if type(f2tMapHasLiveMapper) == "function" and f2tMapHasLiveMapper() then
        deleteMap()
        success, error_msg = loadJsonMap(file_path)
        if success then updateMap() end
    end
    if not success then
        success, error_msg = f2t_map_load_json_headless(file_path)
    end
    if not success then return false, error_msg or "unknown error" end

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