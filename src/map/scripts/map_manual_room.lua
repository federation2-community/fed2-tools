-- Manual room management for Federation 2 mapper
-- Provides CRUD operations for rooms (create, delete, info, set properties)

-- ========================================
-- Room Creation
-- ========================================

--- Manually create a new room
--- @param system string System name
--- @param area string Area/planet name
--- @param num number Fed2 room number
--- @param name string Optional room name
--- @return number|nil room_id on success, nil on failure
function f2t_map_manual_create_room(system, area, num, name)
    if not system or system == "" then
        cecho("\n<red>[map]<reset> System name required\n")
        return nil
    end

    if not area or area == "" then
        cecho("\n<red>[map]<reset> Area name required\n")
        return nil
    end

    if not num or type(num) ~= "number" then
        cecho("\n<red>[map]<reset> Room number must be a number\n")
        return nil
    end

    -- Generate hash
    local hash = string.format("%s.%s.%d", system, area, num)

    -- Check if room already exists
    local existing_id = getRoomIDbyHash(hash)
    if existing_id and existing_id > 0 then
        cecho(string.format("\n<yellow>[map]<reset> Room already exists: %s (ID: %d)\n", hash, existing_id))
        cecho(string.format("\n<dim_grey>Use 'map room info %d' to view details<reset>\n", existing_id))
        return existing_id
    end

    -- Get or create area
    local area_id = f2t_map_get_or_create_area(area, {system = system})
    if not area_id then
        cecho(string.format("\n<red>[map]<reset> Failed to create area: %s\n", area))
        return nil
    end

    -- Create room ID
    local room_id = createRoomID()
    if not room_id then
        cecho("\n<red>[map]<reset> Failed to create room ID\n")
        return nil
    end

    -- Add room to map
    addRoom(room_id)
    setRoomArea(room_id, area_id)

    -- Set hash
    setRoomIDbyHash(room_id, hash)

    -- Set name
    if name and name ~= "" then
        setRoomName(room_id, name)
    else
        setRoomName(room_id, hash)  -- Default to hash
    end

    -- Calculate and set coordinates (Fed2 grid layout)
    local x = num % 64
    local y = -math.floor(num / 64)  -- Y-axis inversion
    local z = 0
    setRoomCoordinates(room_id, x, y, z)

    -- Store Fed2 metadata
    setRoomUserData(room_id, "fed2_system", system)
    setRoomUserData(room_id, "fed2_area", area)
    setRoomUserData(room_id, "fed2_num", tostring(num))

    -- Inherit cartel from area data if already stored (best-effort)
    local area_id_for_cartel = getRoomArea(room_id)
    if area_id_for_cartel then
        local cartel = getAreaUserData(area_id_for_cartel, "fed2_cartel")
        if cartel and cartel ~= "" then
            setRoomUserData(room_id, "fed2_cartel", cartel)
        end
    end

    cecho(string.format("\n<green>[map]<reset> Room created: <white>%s<reset> (ID: %d)\n", hash, room_id))
    cecho(string.format("  <dim_grey>Area: %s | Coords: (%d, %d, %d)<reset>\n", area, x, y, z))

    f2t_debug_log("[map_manual] Room created: %s -> ID %d", hash, room_id)

    return room_id
end

-- ========================================
-- Room Deletion
-- ========================================

--- Delete a room (with confirmation)
--- @param room_id number Room ID to delete
function f2t_map_manual_delete_room(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return
    end

    local room_name = getRoomName(room_id) or "unnamed"
    local hash = getRoomHashByID(room_id) or "unknown"

    -- Request confirmation
    local action = string.format("delete room %d (%s)", room_id, room_name)

    f2t_map_manual_request_confirmation(action, function(data)
        local id = data.room_id

        -- Verify room still exists
        if not roomExists(id) then
            cecho(string.format("\n<red>[map]<reset> Room %d no longer exists\n", id))
            return
        end

        -- Delete the room
        deleteRoom(id)

        cecho(string.format("\n<green>[map]<reset> Room deleted: <white>%d<reset> (%s)\n",
            id, data.room_name))

        f2t_debug_log("[map_manual] Room deleted: %d (%s)", id, data.hash)
    end, {room_id = room_id, room_name = room_name, hash = hash})
end

-- ========================================
-- Room Information Display
-- ========================================

--- Display detailed room information
--- @param room_id number Room ID
function f2t_map_manual_room_info(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return
    end

    -- Get room properties
    local name = getRoomName(room_id)
    local hash = getRoomHashByID(room_id)
    local area_id = getRoomArea(room_id)
    local area_name = f2t_map_get_area_name(area_id)
    local x, y, z = getRoomCoordinates(room_id)
    local char = getRoomChar(room_id)
    local env = getRoomEnv(room_id)
    local weight = getRoomWeight(room_id)

    -- Get Fed2 metadata
    local fed2_system = getRoomUserData(room_id, "fed2_system")
    local fed2_area = getRoomUserData(room_id, "fed2_area")
    local fed2_num = getRoomUserData(room_id, "fed2_num")

    -- Get exits
    local exits = getRoomExits(room_id)
    local special_exits = getSpecialExitsSwap(room_id)

    -- Display info
    cecho(string.format("\n<green>[map]<reset> Room Information: <white>%d<reset>\n", room_id))
    cecho(string.format("  <yellow>Name:<reset> %s\n", name or "(none)"))
    cecho(string.format("  <yellow>Hash:<reset> %s\n", hash or "(none)"))
    cecho(string.format("  <yellow>Area:<reset> %s (ID: %d)\n", area_name or "(none)", area_id or 0))
    cecho(string.format("  <yellow>Coordinates:<reset> (%d, %d, %d)\n", x or 0, y or 0, z or 0))

    if char and char ~= "" then
        cecho(string.format("  <yellow>Symbol:<reset> %s\n", char))
    end

    if env and env >= 0 then
        cecho(string.format("  <yellow>Environment:<reset> %d\n", env))
    end

    if weight and weight ~= 1 then
        cecho(string.format("  <yellow>Weight:<reset> %d\n", weight))
    end

    -- Fed2 metadata
    if fed2_system or fed2_area or fed2_num then
        cecho("\n  <dim_grey>Fed2 Metadata:<reset>\n")
        if fed2_system then
            cecho(string.format("    <dim_grey>System: %s<reset>\n", fed2_system))
        end
        if fed2_area then
            cecho(string.format("    <dim_grey>Area: %s<reset>\n", fed2_area))
        end
        if fed2_num then
            cecho(string.format("    <dim_grey>Num: %s<reset>\n", fed2_num))
        end
    end

    -- Exits
    if exits and next(exits) ~= nil then
        cecho("\n  <yellow>Standard Exits:<reset>\n")
        for dir, dest_id in pairs(exits) do
            local dest_name = getRoomName(dest_id) or "unnamed"
            cecho(string.format("    <cyan>%s<reset> -> %s (ID: %d)\n", dir, dest_name, dest_id))
        end
    end

    if special_exits and next(special_exits) ~= nil then
        cecho("\n  <yellow>Special Exits:<reset>\n")
        for dest_id, command in pairs(special_exits) do
            local dest_name = getRoomName(dest_id) or "unnamed"
            cecho(string.format("    <magenta>%s<reset> -> %s (ID: %d)\n", command, dest_name, dest_id))
        end
    end

    -- Lock status
    local room_locked = roomLocked(room_id)
    cecho("\n  <yellow>Lock Status:<reset>\n")
    if room_locked then
        cecho("    <red>Room is LOCKED<reset> (navigation will avoid)\n")

        -- Check for death-related lock metadata
        local death_date = getRoomUserData(room_id, "f2t_death_date")
        if death_date and death_date ~= "" then
            cecho(string.format("    <red>Death Location<reset>: %s\n", death_date))
        end
    else
        cecho("    <green>Room is UNLOCKED<reset>\n")
    end

    -- Exit lock status
    if exits and next(exits) ~= nil then
        local has_locked_exits = false
        for dir, dest_id in pairs(exits) do
            if hasExitLock(room_id, dir) then
                if not has_locked_exits then
                    cecho("\n  <yellow>Locked Exits:<reset>\n")
                    has_locked_exits = true
                end
                local dest_name = getRoomName(dest_id) or "unnamed"
                cecho(string.format("    <red>%s<reset> -> %s (ID: %d)\n", dir, dest_name, dest_id))
            end
        end
    end

    cecho("\n")
end

-- ========================================
-- Room Property Setters
-- ========================================

--- Set room name
function f2t_map_manual_set_room_name(room_id, name)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    if not name or name == "" then
        cecho("\n<red>[map]<reset> Name cannot be empty\n")
        return false
    end

    setRoomName(room_id, name)
    cecho(string.format("\n<green>[map]<reset> Room %d name set to: <white>%s<reset>\n", room_id, name))

    f2t_debug_log("[map_manual] Room %d name set to: %s", room_id, name)

    return true
end

--- Set room area
function f2t_map_manual_set_room_area(room_id, area_name)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    if not area_name or area_name == "" then
        cecho("\n<red>[map]<reset> Area name cannot be empty\n")
        return false
    end

    -- Get or create area
    local area_id = f2t_map_get_or_create_area(area_name)
    if not area_id then
        cecho(string.format("\n<red>[map]<reset> Failed to create area: %s\n", area_name))
        return false
    end

    setRoomArea(room_id, area_id)
    cecho(string.format("\n<green>[map]<reset> Room %d moved to area: <white>%s<reset> (ID: %d)\n",
        room_id, area_name, area_id))

    f2t_debug_log("[map_manual] Room %d moved to area: %s (ID: %d)", room_id, area_name, area_id)

    return true
end

--- Set room coordinates
function f2t_map_manual_set_room_coords(room_id, x, y, z)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    if not x or not y or not z then
        cecho("\n<red>[map]<reset> Coordinates must be numbers (x, y, z)\n")
        return false
    end

    setRoomCoordinates(room_id, x, y, z)
    cecho(string.format("\n<green>[map]<reset> Room %d coordinates set to: <white>(%d, %d, %d)<reset>\n",
        room_id, x, y, z))

    f2t_debug_log("[map_manual] Room %d coords set to: (%d, %d, %d)", room_id, x, y, z)

    return true
end

--- Set room symbol (1 character)
function f2t_map_manual_set_room_symbol(room_id, symbol)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    if not symbol or symbol == "" then
        cecho("\n<red>[map]<reset> Symbol cannot be empty\n")
        return false
    end

    -- Validate single character
    if string.len(symbol) > 1 then
        cecho("\n<red>[map]<reset> Symbol must be exactly 1 character\n")
        return false
    end

    setRoomChar(room_id, symbol)
    cecho(string.format("\n<green>[map]<reset> Room %d symbol set to: <white>%s<reset>\n", room_id, symbol))

    f2t_debug_log("[map_manual] Room %d symbol set to: %s", room_id, symbol)

    return true
end

--- Set room color (RGB 0-255)
function f2t_map_manual_set_room_color(room_id, r, g, b)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    if not r or not g or not b then
        cecho("\n<red>[map]<reset> Color must be RGB values (0-255)\n")
        return false
    end

    -- Validate range
    if r < 0 or r > 255 or g < 0 or g > 255 or b < 0 or b > 255 then
        cecho("\n<red>[map]<reset> RGB values must be between 0 and 255\n")
        return false
    end

    setRoomBackgroundColor(room_id, r, g, b)
    cecho(string.format("\n<green>[map]<reset> Room %d color set to: <white>RGB(%d, %d, %d)<reset>\n",
        room_id, r, g, b))

    f2t_debug_log("[map_manual] Room %d color set to: RGB(%d, %d, %d)", room_id, r, g, b)

    return true
end

--- Set room environment ID
function f2t_map_manual_set_room_env(room_id, env_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    if not env_id or type(env_id) ~= "number" then
        cecho("\n<red>[map]<reset> Environment ID must be a number\n")
        return false
    end

    setRoomEnv(room_id, env_id)
    cecho(string.format("\n<green>[map]<reset> Room %d environment set to: <white>%d<reset>\n", room_id, env_id))

    f2t_debug_log("[map_manual] Room %d environment set to: %d", room_id, env_id)

    return true
end

--- Set room weight (pathfinding cost multiplier)
function f2t_map_manual_set_room_weight(room_id, weight)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    if not weight or type(weight) ~= "number" then
        cecho("\n<red>[map]<reset> Weight must be a number\n")
        return false
    end

    if weight < 1 then
        cecho("\n<red>[map]<reset> Weight must be >= 1\n")
        return false
    end

    setRoomWeight(room_id, weight)
    cecho(string.format("\n<green>[map]<reset> Room %d weight set to: <white>%d<reset>\n", room_id, weight))
    cecho("\n<dim_grey>Higher weight = higher pathfinding cost (avoid this room)<reset>\n")

    f2t_debug_log("[map_manual] Room %d weight set to: %d", room_id, weight)

    return true
end

f2t_debug_log("[map] Manual room management initialized")
