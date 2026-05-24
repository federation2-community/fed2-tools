-- Lock management for Federation 2 mapper
-- Provides functions to lock/unlock rooms and exits for navigation control

-- ========================================
-- Room Locking
-- ========================================

--- Lock a room (prevents pathfinding through it)
--- @param room_id number Room ID to lock
--- @return boolean true on success, false on failure
function f2t_map_manual_lock_room(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    -- Check if already locked
    if roomLocked(room_id) then
        cecho(string.format("\n<yellow>[map]<reset> Room %d is already locked\n", room_id))
        return true
    end

    -- Lock the room
    lockRoom(room_id, true)

    -- Apply generic locked styling (death monitor will override with skull if this is a death room)
    f2t_map_apply_locked_room_style(room_id)

    local room_name = getRoomName(room_id) or "unnamed"
    local hash = getRoomHashByID(room_id) or "unknown"

    cecho(string.format("\n<green>[map]<reset> Room locked: <white>%s<reset> (ID: %d)\n", room_name, room_id))
    cecho(string.format("  <dim_grey>Hash: %s<reset>\n", hash))
    cecho("  <red>Navigation will avoid this room<reset>\n")

    f2t_debug_log("[map_manual] Room locked: %d (%s)", room_id, hash)

    return true
end

--- Unlock a room
--- @param room_id number Room ID to unlock
--- @return boolean true on success, false on failure
function f2t_map_manual_unlock_room(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    -- Check if locked
    if not roomLocked(room_id) then
        cecho(string.format("\n<yellow>[map]<reset> Room %d is not locked\n", room_id))
        return true
    end

    -- Unlock the room
    lockRoom(room_id, false)

    -- Clear all death/danger metadata so styling reverts to normal
    setRoomUserData(room_id, "f2t_death_date", "")
    setRoomUserData(room_id, "f2t_danger", "")
    setRoomUserData(room_id, "f2t_locked_reason", "")

    -- Reapply flag-based styling (metadata cleared, normal flags take effect)
    f2t_map_update_room_style(room_id)

    local room_name = getRoomName(room_id) or "unnamed"

    cecho(string.format("\n<green>[map]<reset> Room unlocked: <white>%s<reset> (ID: %d)\n", room_name, room_id))

    f2t_debug_log("[map_manual] Room unlocked: %d", room_id)

    return true
end

-- ========================================
-- Exit Locking
-- ========================================

--- Lock an exit (prevents pathfinding through it).
--- If the destination room is undiscovered (exit is a stub or only visible in GMCP),
--- creates a locked placeholder room so the exit can be connected and locked.
--- @param room_id number Mudlet room ID
--- @param direction string Exit direction to lock (abbreviated or full name)
--- @return boolean true on success, false on failure
function f2t_map_manual_lock_exit(room_id, direction)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    if not direction or direction == "" then
        cecho("\n<red>[map]<reset> Direction required\n")
        return false
    end

    direction = string.lower(direction)

    -- Expand abbreviations so lockExit/getRoomExits get the full name Mudlet expects
    local dir_expand = {n="north",s="south",e="east",w="west",ne="northeast",nw="northwest",se="southeast",sw="southwest",u="up",d="down"}
    direction = dir_expand[direction] or direction

    -- Fast path: exit is already connected in the mapper
    local exits = getRoomExits(room_id)
    if exits and exits[direction] then
        if hasExitLock(room_id, direction) then
            cecho(string.format("\n<yellow>[map]<reset> Exit '%s' in room %d is already locked\n", direction, room_id))
            return true
        end

        lockExit(room_id, direction, true)

        local room_name = getRoomName(room_id) or "unnamed"
        local dest_room = exits[direction]
        local dest_name = getRoomName(dest_room) or "unnamed"

        cecho(string.format("\n<green>[map]<reset> Exit locked: <white>%s<reset> --%s--> <white>%s<reset>\n",
            room_name, direction, dest_name))
        cecho("  <red>Navigation will avoid this exit<reset>\n")

        f2t_debug_log("[map_manual] Exit locked: %d --%s--> %d", room_id, direction, dest_room)
        return true
    end

    -- Exit not connected - check for stub exit or GMCP data (undiscovered destination)
    local dir_num = f2t_map_direction_to_number(direction)
    if not dir_num then
        cecho(string.format("\n<red>[map]<reset> Unknown direction: %s\n", direction))
        return false
    end

    local has_stub = false
    local stubs = getExitStubs(room_id)
    for _, stub_dir_num in pairs(stubs) do
        if stub_dir_num == dir_num then
            has_stub = true
            break
        end
    end

    -- Check GMCP (only available for the room we're currently in).
    -- GMCP exits use abbreviated keys ("n", "se") while our direction is now full ("north").
    local gmcp_fed2_num = nil
    if room_id == F2T_MAP_CURRENT_ROOM_ID and gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.exits then
        local abbrev = f2t_map_normalize_direction(direction)
        gmcp_fed2_num = gmcp.room.info.exits[direction] or gmcp.room.info.exits[abbrev]
    end

    if not has_stub and not gmcp_fed2_num then
        cecho(string.format("\n<red>[map]<reset> No exit '%s' from room %d\n", direction, room_id))
        return false
    end

    if not gmcp_fed2_num then
        -- Stub exists but we don't know where it leads (different room or no GMCP)
        cecho(string.format("\n<yellow>[map]<reset> Exit '%s' is a stub — destination unknown\n", direction))
        cecho("\n<dim_grey>Must be standing in this room with GMCP to lock an undiscovered exit.\n")
        return false
    end

    -- Build a placeholder room for the undiscovered destination.
    -- The hash (system.area.fed2_num) is the canonical key linking mapper IDs to game rooms.
    local system = getRoomUserData(room_id, "fed2_system") or
                   (gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.system)
    local area   = getRoomUserData(room_id, "fed2_area") or
                   (gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.area)

    if not system or not area then
        cecho("\n<red>[map]<reset> Cannot determine system/area to create placeholder room\n")
        return false
    end

    local hash = string.format("%s.%s.%d", system, area, gmcp_fed2_num)

    -- Reuse existing room if already created (idempotent).
    -- getRoomIDbyHash returns 0 (not nil) when not found; 0 is truthy in Lua so check > 0.
    local dest_room_id = getRoomIDbyHash(hash)
    if dest_room_id and dest_room_id > 0 then
        f2t_debug_log("[map_manual] Locked placeholder already exists: %d (%s)", dest_room_id, hash)
    else
        local area_id = getRoomArea(room_id)
        if not area_id or area_id <= 0 then
            cecho("\n<red>[map]<reset> Cannot determine area ID to create placeholder room\n")
            return false
        end

        -- createRoomID() gives a new Mudlet-internal ID (unrelated to Fed2 room numbers)
        dest_room_id = createRoomID()
        local room_added = addRoom(dest_room_id)
        if not room_added then
            cecho(string.format("\n<red>[map]<reset> Failed to create placeholder room (ID: %d)\n", dest_room_id))
            return false
        end
        -- setRoomArea must be called immediately after addRoom (matches auto-mapper pattern)
        setRoomArea(dest_room_id, area_id)
        setRoomIDbyHash(dest_room_id, hash)
        setRoomName(dest_room_id, string.format("[Locked] %s.%d", area, gmcp_fed2_num))

        -- Use Fed2 grid coordinates (room_num % 64, -floor(room_num/64)) for visual placement
        local x, y, z = f2t_map_calculate_coords_from_room_num(gmcp_fed2_num)
        setRoomCoordinates(dest_room_id, x, y, z)

        setRoomUserData(dest_room_id, "fed2_system", system)
        setRoomUserData(dest_room_id, "fed2_area", area)
        setRoomUserData(dest_room_id, "fed2_num", tostring(gmcp_fed2_num))

        f2t_debug_log("[map_manual] Created locked placeholder: Mudlet ID %d, hash %s", dest_room_id, hash)
    end

    -- Remove stub if present, connect the exit, then lock it.
    -- IMPORTANT: lockRoom must happen AFTER setExit — locking the destination room
    -- before calling setExit prevents Mudlet from creating the exit connection.
    if has_stub then
        setExitStub(room_id, dir_num, false)
    end
    local exit_created = setExit(room_id, dest_room_id, dir_num)
    if not exit_created then
        if has_stub then setExitStub(room_id, dir_num, true) end
        cecho(string.format("\n<red>[map]<reset> Failed to connect exit to placeholder room %d\n", dest_room_id))
        return false
    end
    lockExit(room_id, direction, true)
    -- Lock destination room and apply styling after the exit is established
    lockRoom(dest_room_id, true)
    f2t_map_apply_locked_room_style(dest_room_id)

    local room_name = getRoomName(room_id) or "unnamed"
    local dest_name = getRoomName(dest_room_id) or "unnamed"

    cecho(string.format("\n<green>[map]<reset> Exit locked: <white>%s<reset> --%s--> <white>%s<reset>\n",
        room_name, direction, dest_name))
    cecho(string.format("  <yellow>Locked placeholder created for undiscovered room %s<reset>\n", hash))
    cecho("  <red>Navigation will avoid this exit<reset>\n")

    updateMap()

    f2t_debug_log("[map_manual] Undiscovered exit locked: %d --%s--> %d (locked placeholder)", room_id, direction, dest_room_id)
    return true
end

--- Mark an exit to a danger/death room (creates skull placeholder for undiscovered destinations).
--- Like lock_exit but sets f2t_danger metadata and skull styling.
--- @param room_id number Mudlet room ID
--- @param direction string Exit direction (abbreviated or full name)
--- @return boolean true on success, false on failure
function f2t_map_manual_death_exit(room_id, direction)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    if not direction or direction == "" then
        cecho("\n<red>[map]<reset> Direction required\n")
        return false
    end

    direction = string.lower(direction)

    local dir_expand = {n="north",s="south",e="east",w="west",ne="northeast",nw="northwest",se="southeast",sw="southwest",u="up",d="down"}
    direction = dir_expand[direction] or direction

    -- Fast path: exit is already connected — mark destination as death room
    local exits = getRoomExits(room_id)
    if exits and exits[direction] then
        local dest_room = exits[direction]

        -- Lock the exit
        lockExit(room_id, direction, true)

        -- Mark the destination as a death/danger room
        lockRoom(dest_room, true)
        setRoomUserData(dest_room, "f2t_danger", "true")
        f2t_map_apply_death_room_style(dest_room)

        local room_name = getRoomName(room_id) or "unnamed"
        local dest_name = getRoomName(dest_room) or "unnamed"

        cecho(string.format("\n<green>[map]<reset> Exit marked dangerous: <white>%s<reset> --%s--> <white>%s<reset>\n",
            room_name, direction, dest_name))
        cecho("  <red>Destination marked as death/danger room<reset>\n")
        cecho("  <red>Navigation will avoid this exit and room<reset>\n")

        f2t_debug_log("[map_manual] Death exit: %d --%s--> %d", room_id, direction, dest_room)
        updateMap()
        return true
    end

    -- Exit not connected — build a skull placeholder (same as lock_exit, but with danger metadata)
    local dir_num = f2t_map_direction_to_number(direction)
    if not dir_num then
        cecho(string.format("\n<red>[map]<reset> Unknown direction: %s\n", direction))
        return false
    end

    local has_stub = false
    local stubs = getExitStubs(room_id)
    for _, stub_dir_num in pairs(stubs) do
        if stub_dir_num == dir_num then
            has_stub = true
            break
        end
    end

    local gmcp_fed2_num = nil
    if room_id == F2T_MAP_CURRENT_ROOM_ID and gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.exits then
        local abbrev = f2t_map_normalize_direction(direction)
        gmcp_fed2_num = gmcp.room.info.exits[direction] or gmcp.room.info.exits[abbrev]
    end

    if not has_stub and not gmcp_fed2_num then
        cecho(string.format("\n<red>[map]<reset> No exit '%s' from room %d\n", direction, room_id))
        return false
    end

    if not gmcp_fed2_num then
        cecho(string.format("\n<yellow>[map]<reset> Exit '%s' is a stub — destination unknown\n", direction))
        cecho("\n<dim_grey>Must be standing in this room with GMCP to mark an undiscovered exit as danger.\n")
        return false
    end

    local system = getRoomUserData(room_id, "fed2_system") or
                   (gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.system)
    local area   = getRoomUserData(room_id, "fed2_area") or
                   (gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.area)

    if not system or not area then
        cecho("\n<red>[map]<reset> Cannot determine system/area to create placeholder room\n")
        return false
    end

    local hash = string.format("%s.%s.%d", system, area, gmcp_fed2_num)

    -- getRoomIDbyHash returns 0 (not nil) when not found; 0 is truthy in Lua so check > 0.
    local dest_room_id = getRoomIDbyHash(hash)
    if dest_room_id and dest_room_id > 0 then
        -- Already exists — upgrade to death styling if not already set
        setRoomUserData(dest_room_id, "f2t_danger", "true")
        f2t_map_apply_death_room_style(dest_room_id)
        f2t_debug_log("[map_manual] Death placeholder already exists (upgraded): %d (%s)", dest_room_id, hash)
    else
        local area_id = getRoomArea(room_id)
        if not area_id or area_id <= 0 then
            cecho("\n<red>[map]<reset> Cannot determine area ID to create placeholder room\n")
            return false
        end

        dest_room_id = createRoomID()
        local room_added = addRoom(dest_room_id)
        if not room_added then
            cecho(string.format("\n<red>[map]<reset> Failed to create placeholder room (ID: %d)\n", dest_room_id))
            return false
        end
        -- setRoomArea must be called immediately after addRoom (matches auto-mapper pattern)
        setRoomArea(dest_room_id, area_id)
        setRoomIDbyHash(dest_room_id, hash)
        setRoomName(dest_room_id, string.format("[Death] %s.%d", area, gmcp_fed2_num))

        local x, y, z = f2t_map_calculate_coords_from_room_num(gmcp_fed2_num)
        setRoomCoordinates(dest_room_id, x, y, z)

        setRoomUserData(dest_room_id, "fed2_system", system)
        setRoomUserData(dest_room_id, "fed2_area", area)
        setRoomUserData(dest_room_id, "fed2_num", tostring(gmcp_fed2_num))
        setRoomUserData(dest_room_id, "f2t_danger", "true")

        f2t_debug_log("[map_manual] Created death placeholder: Mudlet ID %d, hash %s", dest_room_id, hash)
    end

    -- Remove stub if present, connect the exit, then lock it.
    -- IMPORTANT: lockRoom must happen AFTER setExit — locking the destination room
    -- before calling setExit prevents Mudlet from creating the exit connection.
    if has_stub then
        setExitStub(room_id, dir_num, false)
    end
    local exit_created = setExit(room_id, dest_room_id, dir_num)
    if not exit_created then
        if has_stub then setExitStub(room_id, dir_num, true) end
        cecho(string.format("\n<red>[map]<reset> Failed to connect exit to placeholder room %d\n", dest_room_id))
        return false
    end
    lockExit(room_id, direction, true)
    -- Lock destination room and apply styling after the exit is established
    lockRoom(dest_room_id, true)
    f2t_map_apply_death_room_style(dest_room_id)

    local room_name = getRoomName(room_id) or "unnamed"
    local dest_name = getRoomName(dest_room_id) or "unnamed"

    cecho(string.format("\n<green>[map]<reset> Exit marked dangerous: <white>%s<reset> --%s--> <white>%s<reset>\n",
        room_name, direction, dest_name))
    cecho(string.format("  <yellow>Death placeholder created for undiscovered room %s<reset>\n", hash))
    cecho("  <red>Navigation will avoid this exit and room<reset>\n")

    updateMap()

    f2t_debug_log("[map_manual] Undiscovered exit marked death: %d --%s--> %d (death placeholder)", room_id, direction, dest_room_id)
    return true
end

--- Mark an already-mapped room as a death/danger room.
--- Locks it, sets f2t_danger metadata, and applies skull styling.
--- @param room_id number Room ID to mark
--- @return boolean true on success, false on failure
function f2t_map_manual_mark_room_death(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    lockRoom(room_id, true)
    setRoomUserData(room_id, "f2t_danger", "true")
    f2t_map_apply_death_room_style(room_id)

    local room_name = getRoomName(room_id) or "unnamed"
    local hash = getRoomHashByID(room_id) or "unknown"

    cecho(string.format("\n<green>[map]<reset> Room marked dangerous: <white>%s<reset> (ID: %d)\n", room_name, room_id))
    cecho(string.format("  <dim_grey>Hash: %s<reset>\n", hash))
    cecho("  <red>Navigation will avoid this room<reset>\n")

    updateMap()
    f2t_debug_log("[map_manual] Room marked death: %d (%s)", room_id, hash)

    return true
end

--- Unlock an exit
--- @param room_id number Room ID
--- @param direction string Exit direction to unlock
--- @return boolean true on success, false on failure
function f2t_map_manual_unlock_exit(room_id, direction)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    if not direction or direction == "" then
        cecho("\n<red>[map]<reset> Direction required\n")
        return false
    end

    direction = string.lower(direction)

    local dir_expand = {n="north",s="south",e="east",w="west",ne="northeast",nw="northwest",se="southeast",sw="southwest",u="up",d="down"}
    direction = dir_expand[direction] or direction

    -- Check if exit exists
    local exits = getRoomExits(room_id)
    if not exits or not exits[direction] then
        cecho(string.format("\n<red>[map]<reset> No exit '%s' from room %d\n", direction, room_id))
        return false
    end

    -- Check if locked
    if not hasExitLock(room_id, direction) then
        cecho(string.format("\n<yellow>[map]<reset> Exit '%s' in room %d is not locked\n", direction, room_id))
        return true
    end

    -- Unlock the exit
    lockExit(room_id, direction, false)

    local room_name = getRoomName(room_id) or "unnamed"
    local dest_room = exits[direction]
    local dest_name = getRoomName(dest_room) or "unnamed"

    cecho(string.format("\n<green>[map]<reset> Exit unlocked: <white>%s<reset> --%s--> <white>%s<reset>\n",
        room_name, direction, dest_name))

    f2t_debug_log("[map_manual] Exit unlocked: %d --%s--> %d", room_id, direction, dest_room)

    return true
end

-- ========================================
-- Lock Status Display
-- ========================================

--- Display lock status for a room (room + all exits)
--- @param room_id number Room ID
function f2t_map_manual_lock_status(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return
    end

    local room_name = getRoomName(room_id) or "unnamed"
    local room_locked = roomLocked(room_id)

    cecho(string.format("\n<green>[map]<reset> Lock status for room %d (<white>%s<reset>):\n", room_id, room_name))

    -- Safe flag
    local is_safe = getRoomUserData(room_id, "f2t_safe")
    if is_safe == "true" then
        cecho("  <cyan>Safe flag: SET<reset> (death monitor will never auto-lock)\n")
    end

    -- Room lock status
    if room_locked then
        cecho("  <red>Room is LOCKED<reset> (navigation will avoid this room)\n")

        -- Check for death-related lock metadata
        local death_date = getRoomUserData(room_id, "f2t_death_date")
        if death_date and death_date ~= "" then
            cecho(string.format("  <red>Death Location<reset>: %s\n", death_date))
        end
    else
        cecho("  <green>Room is UNLOCKED<reset>\n")
    end

    -- Exit lock status
    local exits = getRoomExits(room_id)
    if exits and next(exits) ~= nil then
        cecho("\n  <yellow>Exit Lock Status:<reset>\n")

        local has_locked_exits = false
        for dir, dest_id in pairs(exits) do
            local locked = hasExitLock(room_id, dir)
            if locked then
                has_locked_exits = true
                local dest_name = getRoomName(dest_id) or "unnamed"
                cecho(string.format("    <red>%-10s<reset> <red>LOCKED<reset>   -> <white>%s<reset> (ID: %d)\n",
                    dir, dest_name, dest_id))
            end
        end

        if not has_locked_exits then
            cecho("    <green>No locked exits<reset>\n")
        end
    else
        cecho("\n  <dim_grey>No exits to lock<reset>\n")
    end

    cecho("\n")
end

-- ========================================
-- Safe Room Management
-- ========================================

--- Mark a room as safe from auto-locking on death.
--- The death monitor will never automatically lock this room.
--- Independent of lock state — a room can be safe AND unlocked at the same time.
--- @param room_id number Room ID to mark safe
--- @return boolean true on success, false on failure
function f2t_map_manual_mark_room_safe(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    setRoomUserData(room_id, "f2t_safe", "true")

    local room_name = getRoomName(room_id) or "unnamed"
    local hash = getRoomHashByID(room_id) or "unknown"

    cecho(string.format("\n<green>[map]<reset> Room marked safe: <white>%s<reset> (ID: %d)\n", room_name, room_id))
    cecho(string.format("  <dim_grey>Hash: %s<reset>\n", hash))
    cecho("  <cyan>Death monitor will never auto-lock this room<reset>\n")
    cecho("  <dim_grey>Use 'map room unsafe' to remove this mark (also marks as death)<reset>\n")

    f2t_debug_log("[map_manual] Room marked safe: %d (%s)", room_id, hash)
    return true
end

--- Remove the safe mark from a room and mark it as a death/danger room.
--- @param room_id number Room ID
--- @return boolean true on success, false on failure
function f2t_map_manual_mark_room_unsafe(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id)))
        return false
    end

    setRoomUserData(room_id, "f2t_safe", "")

    local room_name = getRoomName(room_id) or "unnamed"
    cecho(string.format("\n<green>[map]<reset> Safe mark removed from room: <white>%s<reset> (ID: %d)\n", room_name, room_id))

    -- Mark as death room now that safe protection is lifted
    f2t_map_manual_mark_room_death(room_id)

    f2t_debug_log("[map_manual] Room marked unsafe (safe flag cleared, death applied): %d", room_id)
    return true
end

f2t_debug_log("[map] Manual lock management initialized")
