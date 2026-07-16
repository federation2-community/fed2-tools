-- fed2-tools map — jump exit management
--
-- Fed2's GMCP sends valid jump destinations directly as gmcp.room.info.jumps
-- for link rooms (added 2026-07-15, delivered on entry to the player
-- entering): {inter_syndicate = {...}, intra_syndicate = {...}, local = {...}},
-- each an array of destination system/cartel/syndicate names. This is
-- structured, always-current data pushed alongside the room's flags — no
-- command to send, no text to parse, no staleness window, no async
-- capture/retry machinery. f2t_map_process_link_room below is called from
-- exit.lua's GMCP room handler on every room entry and just rebuilds the
-- room's "jump ___" special exits from that data each time.

-- Collect matching commands first, then remove them in a separate pass —
-- calling removeSpecialExit while iterating the same table with pairs() is
-- unsafe and can silently skip entries.
local function clearJumpExits(room_id)
    if not room_id or not roomExists(room_id) then return end
    local to_remove = {}
    for command, _ in pairs(getSpecialExits(room_id)) do
        if string.match(command, "^jump ") then
            table.insert(to_remove, command)
        end
    end
    for _, command in ipairs(to_remove) do
        removeSpecialExit(room_id, command)
    end
end

function f2t_map_apply_gmcp_jumps(room_id, jumps, source_system)
    if not room_id or not roomExists(room_id) or not jumps then return end
    clearJumpExits(room_id)
    local created_count, total = 0, 0
    for _, category in ipairs({"inter_syndicate", "intra_syndicate", "local"}) do
        for _, dest_system in ipairs(jumps[category] or {}) do
            total = total + 1
            if f2t_map_create_jump_special_exit(room_id, source_system, dest_system) then
                created_count = created_count + 1
            end
        end
    end
    setRoomUserData(room_id, "fed2_jump_synced_at", tostring(os.time()))
    f2t_debug_log("[map/jump] apply_gmcp_jumps(room=%s): %d/%d special exits from GMCP data",
        tostring(room_id), created_count, total)
end

function f2t_map_process_link_room(room_id, flags, gmcp_jumps)
    if not room_id or not roomExists(room_id) then return end
    if not flags or not f2t_has_value(flags, "link") then return end
    if not gmcp_jumps then return end
    local system = getRoomUserData(room_id, "fed2_system")
    if not system then return end
    f2t_map_apply_gmcp_jumps(room_id, gmcp_jumps, system)
end

function f2t_map_create_jump_special_exit(from_room_id, from_system, to_system)
    local to_room_id = f2t_map_find_link_room_in_system(to_system)
    if not to_room_id then return false end
    local forward_command = string.format("jump %s", to_system)
    addSpecialExit(from_room_id, to_room_id, forward_command)
    local reverse_command = string.format("jump %s", from_system)
    addSpecialExit(to_room_id, from_room_id, reverse_command)
    return true
end

function f2t_map_find_link_room_in_system(system)
    if not system or system == "" then return nil end
    local rooms = getRooms()
    for room_id in pairs(rooms) do
        local room_system = getRoomUserData(room_id, "fed2_system")
        local has_link    = getRoomUserData(room_id, "fed2_flag_link")
        if room_system == system and has_link == "true" then return room_id end
    end
    return nil
end
