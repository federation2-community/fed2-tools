-- Room creation and management for Federation 2 mapper
-- Handles room creation, hashing, and metadata storage

-- ========================================
-- Hash Generation
-- ========================================

-- Generate a unique hash for a Fed2 room
-- Format: system.area.num
-- Returns: hash string or nil on error
function f2t_map_generate_hash(room_data)
    if not room_data then
        f2t_debug_log("[map] ERROR: Cannot generate hash from nil room data")
        return nil
    end

    local system = room_data.system
    local area = room_data.area
    local num = room_data.num

    if not system or not area or not num then
        f2t_debug_log("[map] ERROR: Missing required fields for hash (system: %s, area: %s, num: %s)",
            tostring(system), tostring(area), tostring(num))
        return nil
    end

    local hash = string.format("%s.%s.%d", system, area, num)
    f2t_debug_log("[map] Generated hash: %s", hash)

    return hash
end

-- ========================================
-- Room Lookup
-- ========================================

-- Get the hash for an existing room by room ID
-- Returns: hash string or nil if not found
function f2t_map_generate_hash_from_room(room_id)
    if not room_id or not roomExists(room_id) then
        f2t_debug_log("[map] ERROR: Cannot get hash for invalid room: %s", tostring(room_id))
        return nil
    end

    -- Get stored metadata from room
    local system = getRoomUserData(room_id, "fed2_system")
    local area = getRoomUserData(room_id, "fed2_area")
    local num_str = getRoomUserData(room_id, "fed2_num")

    if not system or system == "" or not area or area == "" or not num_str or num_str == "" then
        f2t_debug_log("[map] ERROR: Room %d missing metadata (system: %s, area: %s, num: %s)",
            room_id, tostring(system), tostring(area), tostring(num_str))
        return nil
    end

    local num = tonumber(num_str)
    if not num then
        f2t_debug_log("[map] ERROR: Invalid num in room %d: %s", room_id, tostring(num_str))
        return nil
    end

    local hash = string.format("%s.%s.%d", system, area, num)
    f2t_debug_log("[map] Retrieved hash for room %d: %s", room_id, hash)

    return hash
end

-- Get a Mudlet room ID by Fed2 hash
-- Returns: room_id or nil if not found
function f2t_map_get_room_by_hash(hash)
    if not hash then
        return nil
    end

    local room_id = getRoomIDbyHash(hash)
    if room_id and room_id > 0 then
        f2t_debug_log("[map] Room found by hash '%s': ID %d", hash, room_id)
        return room_id
    end

    f2t_debug_log("[map] No room found for hash '%s'", hash)
    return nil
end

-- ========================================
-- Room Creation
-- ========================================

-- Create a new room from Fed2 room data
-- Returns: room_id or nil on failure
function f2t_map_create_room(room_data, area_id)
    if not room_data then
        f2t_debug_log("[map] ERROR: Cannot create room from nil data")
        return nil
    end

    if not area_id then
        f2t_debug_log("[map] ERROR: Cannot create room without area_id")
        return nil
    end

    -- Generate hash
    local hash = f2t_map_generate_hash(room_data)
    if not hash then
        return nil
    end

    -- Check if room already exists
    local existing_id = f2t_map_get_room_by_hash(hash)
    if existing_id then
        f2t_debug_log("[map] Room already exists: %s (ID: %d)", hash, existing_id)
        return existing_id
    end

    -- Create new room ID
    local room_id = createRoomID()
    if not room_id then
        f2t_debug_log("[map] ERROR: Failed to create room ID")
        return nil
    end

    -- Add room to map
    addRoom(room_id)
    setRoomArea(room_id, area_id)

    -- Set room hash
    setRoomIDbyHash(room_id, hash)

    -- Set room name (clean color codes)
    if room_data.name then
        local clean_name = f2t_clean_room_name(room_data.name)
        setRoomName(room_id, clean_name)
    end

    f2t_debug_log("[map] Room created: %s -> ID %d (area: %d)", hash, room_id, area_id)

    -- Store room metadata
    f2t_map_store_room_metadata(room_id, room_data)

    return room_id
end

-- ========================================
-- Room Metadata Storage
-- ========================================

-- Store Fed2 metadata in room user data
function f2t_map_store_room_metadata(room_id, room_data)
    if not room_id or not roomExists(room_id) then
        f2t_debug_log("[map] ERROR: Cannot store metadata for invalid room: %s", tostring(room_id))
        return false
    end

    if not room_data then
        return false
    end

    -- Store system (always store for both planets and space)
    if room_data.system then
        setRoomUserData(room_id, "fed2_system", room_data.system)
        f2t_debug_log("[map]   Stored system: %s", room_data.system)
    end

    -- Store cartel (enables breadcrumb info overlay on any room, not just current)
    if room_data.cartel then
        setRoomUserData(room_id, "fed2_cartel", room_data.cartel)
        f2t_debug_log("[map]   Stored cartel: %s", room_data.cartel)
    end

    -- Store area (always useful for reference)
    if room_data.area then
        setRoomUserData(room_id, "fed2_area", room_data.area)
        f2t_debug_log("[map]   Stored area: %s", room_data.area)
    end

    -- Store room number
    if room_data.num then
        setRoomUserData(room_id, "fed2_num", tostring(room_data.num))
        f2t_debug_log("[map]   Stored num: %d", room_data.num)
    end

    -- Owner is not stored - not needed for navigation

    -- Store flags as individual boolean fields
    if room_data.flags then
        for _, flag in ipairs(room_data.flags) do
            local key = string.format("fed2_flag_%s", flag)
            setRoomUserData(room_id, key, "true")
        end
        f2t_debug_log("[map]   Stored %d flag(s)", #room_data.flags)
    end

    -- Fallback: Set orbit flag if orbit field is present (in orbit above a planet)
    -- Planet owners don't reliably set the orbit flag, so we infer from GMCP
    if room_data.orbit then
        local existing = getRoomUserData(room_id, "fed2_flag_orbit")
        if existing ~= "true" then
            setRoomUserData(room_id, "fed2_flag_orbit", "true")
            f2t_debug_log("[map]   Set orbit flag (from orbit field)")
        end
    end

    -- Fallback: Set space flag if area name ends with " Space"
    -- Planet owners don't reliably set the space flag, so we infer from area name
    if room_data.area and string.match(room_data.area, " Space$") then
        local existing = getRoomUserData(room_id, "fed2_flag_space")
        if existing ~= "true" then
            setRoomUserData(room_id, "fed2_flag_space", "true")
            f2t_debug_log("[map]   Set space flag (from area name)")
        end
    end

    -- Store exits data for stub connection (format: "dir1:num1,dir2:num2,...")
    if room_data.exits then
        local exit_parts = {}
        for direction, fed2_num in pairs(room_data.exits) do
            table.insert(exit_parts, string.format("%s:%d", direction, fed2_num))
        end
        local exits_str = table.concat(exit_parts, ",")
        setRoomUserData(room_id, "fed2_exits", exits_str)
        f2t_debug_log("[map]   Stored exits data: %s", exits_str)
    end

    -- Store planet name for orbit rooms
    -- orbit field contains shuttlepad hash (system.planet.num) - extract planet name
    if room_data.orbit then
        local parts = {}
        for part in string.gmatch(room_data.orbit, "[^.]+") do
            table.insert(parts, part)
        end
        if #parts == 3 then
            local planet_name = parts[2]  -- Middle part is planet name
            setRoomUserData(room_id, "fed2_planet", planet_name)
            f2t_debug_log("[map]   Stored planet (orbit): %s", planet_name)
        end
    end

    return true
end

-- ========================================
-- Room Update
-- ========================================

-- Update an existing room's metadata
-- Returns: true on success, false on failure
function f2t_map_update_room(room_id, room_data)
    if not room_id or not roomExists(room_id) then
        f2t_debug_log("[map] ERROR: Cannot update invalid room: %s", tostring(room_id))
        return false
    end

    if not room_data then
        return false
    end

    -- Update room name if changed (clean color codes)
    if room_data.name then
        local clean_name = f2t_clean_room_name(room_data.name)
        local current_name = getRoomName(room_id)
        if current_name ~= clean_name then
            setRoomName(room_id, clean_name)
            f2t_debug_log("[map] Room %d name updated: '%s' -> '%s'",
                room_id, current_name, clean_name)
        end
    end

    -- Update metadata (includes fallback flag detection)
    f2t_map_store_room_metadata(room_id, room_data)

    -- Update styling (reads stored flags including fallbacks)
    f2t_map_update_room_style(room_id)

    -- Ensure coordinates are set (in case room was created before coordinate system)
    if room_data.num then
        local x, y, z = getRoomCoordinates(room_id)
        if not x or not y or not z or (x == 0 and y == 0 and z == 0) then
            -- Coordinates not set or at origin, calculate and set them
            local new_x, new_y, new_z = f2t_map_calculate_coords_from_room_num(room_data.num)
            f2t_map_set_room_coords(room_id, new_x, new_y, new_z)
        end
    end

    return true
end
