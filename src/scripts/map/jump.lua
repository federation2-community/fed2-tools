-- fed2-tools map — jump exit management (ported from map_jump.lua)

F2T_MAP_JUMP_CAPTURE = {
    expecting = false,
    active    = false,
    room_id   = nil,
    source_system = nil,
    destinations  = {},
    in_output = false,
}

local jump_timer_id = nil

function f2t_map_process_link_room(room_id, flags)
    if not room_id or not roomExists(room_id) then return end
    if not flags or not f2t_has_value(flags, "link") then return end
    local special_exits = getSpecialExits(room_id)
    for command, _ in pairs(special_exits) do
        if string.match(command, "^jump ") then
            f2t_debug_log("[map] Link room %d already has jump exits", room_id); return
        end
    end
    local system = getRoomUserData(room_id, "fed2_system")
    if not system then return end
    f2t_map_start_jump_capture(room_id, system)
end

function f2t_map_start_jump_capture(room_id, source_system)
    F2T_MAP_JUMP_CAPTURE.expecting     = true
    F2T_MAP_JUMP_CAPTURE.active        = false
    F2T_MAP_JUMP_CAPTURE.room_id       = room_id
    F2T_MAP_JUMP_CAPTURE.source_system = source_system
    F2T_MAP_JUMP_CAPTURE.destinations  = {}
    F2T_MAP_JUMP_CAPTURE.in_output     = false
    send("jump", false)
end

function f2t_map_add_jump_destination(system_name)
    if not F2T_MAP_JUMP_CAPTURE.active then return end
    table.insert(F2T_MAP_JUMP_CAPTURE.destinations, system_name)
end

function f2t_map_finish_jump_capture()
    if not F2T_MAP_JUMP_CAPTURE.active then return end
    local room_id      = F2T_MAP_JUMP_CAPTURE.room_id
    local source_system = F2T_MAP_JUMP_CAPTURE.source_system
    local destinations  = F2T_MAP_JUMP_CAPTURE.destinations
    local created_count = 0
    for _, dest_system in ipairs(destinations) do
        if f2t_map_create_jump_special_exit(room_id, source_system, dest_system) then
            created_count = created_count + 1
        end
    end
    F2T_MAP_JUMP_CAPTURE.expecting     = false
    F2T_MAP_JUMP_CAPTURE.active        = false
    F2T_MAP_JUMP_CAPTURE.in_output     = false
    F2T_MAP_JUMP_CAPTURE.room_id       = nil
    F2T_MAP_JUMP_CAPTURE.source_system = nil
    F2T_MAP_JUMP_CAPTURE.destinations  = {}
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
    for room_id, room_name in pairs(rooms) do
        local room_system = getRoomUserData(room_id, "fed2_system")
        local has_link    = getRoomUserData(room_id, "fed2_flag_link")
        if room_system == system and has_link == "true" then return room_id end
    end
    return nil
end

function f2t_map_jump_reset_timer()
    if jump_timer_id then killTimer(jump_timer_id) end
    jump_timer_id = tempTimer(0.5, function()
        if F2T_MAP_JUMP_CAPTURE.active then
            f2t_map_finish_jump_capture()
        end
        jump_timer_id = nil
    end)
end
