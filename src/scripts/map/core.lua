-- fed2-tools map — GMCP room handler (ported from map_core.lua)

function f2t_map_handle_gmcp_room()
    if not F2T_MAP_ENABLED then return end
    if not gmcp or not gmcp.room or not gmcp.room.info then return end

    -- Once per session, after the map is definitely loaded: load the
    -- persisted topology model and re-derive the jump graph from it.
    if not F2T_MAP_TOPOLOGY_SESSION_REBUILT then
        F2T_MAP_TOPOLOGY_SESSION_REBUILT = true
        f2t_map_topology_ensure_loaded()
        f2t_map_topology_request_rebuild()
    end
    local room_data = gmcp.room.info
    if not room_data.system or not room_data.area or not room_data.num then return end

    local hash = f2t_map_generate_hash(room_data)
    if not hash then return end

    local room_id    = f2t_map_get_room_by_hash(hash)
    local is_new_room = (room_id == nil)

    -- Ignore same-room GMCP events during movement wait
    if F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_WAITING_FOR_MOVE and
       room_id and room_id == F2T_MAP_CURRENT_ROOM_ID then
        return
    end

    if is_new_room then
        room_id = f2t_map_create_new_room(room_data)
        if not room_id then return end
    else
        f2t_map_update_room(room_id, room_data)
    end

    f2t_map_process_exits(room_id, room_data.exits, room_data)
    if is_new_room then f2t_map_connect_incoming_stubs(room_id, room_data.num) end
    f2t_map_process_special_exits(room_id, room_data)

    F2T_MAP_CURRENT_ROOM_ID = room_id

    local area_id = getRoomArea(room_id)
    if area_id then
        local zoom = f2t_settings_get("map", "area_zoom")
        setMapZoom(zoom, area_id)
    end

    centerview(room_id)

    -- Map info snap (UI overlay, no-op if not defined)
    if type(f2t_map_info_snap_to_current) == "function" then
        f2t_map_info_snap_to_current()
    end

    if F2T_MAP_PENDING_SPECIAL_EXIT then
        f2t_map_special_exit_discovery_complete(room_id)
    end

    -- Circuit travel manual boarding check
    if F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active and
       F2T_MAP_CIRCUIT_STATE.phase == "waiting_arrival" then
        local current_hash = f2t_map_generate_hash_from_room(room_id)
        if current_hash == F2T_MAP_CIRCUIT_STATE.vehicle_room then
            f2t_map_circuit_handle_boarding(true)
        end
    end

    -- On-arrival commands
    local arrival_cmd, exec_type = f2t_map_special_get_arrival(room_id)
    if arrival_cmd and exec_type then
        if f2t_map_special_should_execute_arrival(room_id, exec_type) then
            send(arrival_cmd)
            f2t_map_special_mark_arrival_executed(room_id, exec_type)
            if F2T_SPEEDWALK_ACTIVE then
                F2T_SPEEDWALK_WAITING_FOR_ARRIVAL = true
                tempTimer(0.5, function()
                    F2T_SPEEDWALK_WAITING_FOR_ARRIVAL = false
                    f2t_map_speedwalk_on_room_change()
                    if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then
                        f2t_map_explore_on_room_change()
                    end
                end)
            end
        else
            f2t_map_speedwalk_on_room_change()
        end
    else
        f2t_map_speedwalk_on_room_change()
    end

    if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then
        f2t_map_explore_on_room_change()
    end
end

function f2t_map_create_new_room(room_data)
    local area_data = {system = room_data.system, cartel = room_data.cartel, owner = room_data.owner}
    local area_id = f2t_map_get_or_create_area(room_data.area, area_data)
    if not area_id then return nil end
    local room_id = f2t_map_create_room(room_data, area_id)
    if not room_id then return nil end
    local x, y, z = f2t_map_calculate_coords_from_room_num(room_data.num)
    f2t_map_set_room_coords(room_id, x, y, z)
    f2t_map_update_room_style(room_id)
    return room_id
end

function f2t_map_sync()
    if not F2T_MAP_ENABLED then
        cecho("\n<red>[map]<reset> Mapper is disabled. Use 'map on' first.\n"); return
    end
    cecho("\n<green>[map]<reset> Synchronizing with current location...\n")
    f2t_map_handle_gmcp_room()
    cecho("\n<green>[map]<reset> Synchronization complete.\n")
end
