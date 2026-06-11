-- fed2-tools map — route calculation (ported from map_route.lua)

function f2t_map_get_route_info(origin, destination)
    local origin_room_id, origin_err
    if origin and origin ~= "" then
        origin_room_id, origin_err = f2t_map_resolve_location(origin)
        if not origin_room_id then
            return nil, string.format("Cannot resolve origin: %s", origin_err or "unknown error")
        end
    else
        origin_room_id = F2T_MAP_CURRENT_ROOM_ID
        if not origin_room_id then return nil, "Current location unknown (no origin specified)" end
    end

    local dest_room_id, dest_err = f2t_map_resolve_location(destination)
    if not dest_room_id then
        return nil, string.format("Cannot resolve destination: %s", dest_err or "unknown error")
    end

    if origin_room_id == dest_room_id then
        return {origin_room_id=origin_room_id, dest_room_id=dest_room_id,
                total_moves=0, space_moves=0, success=true}
    end

    local success, cost = getPath(origin_room_id, dest_room_id)
    if not success then return nil, "No path found between origin and destination" end

    local total_moves = #speedWalkDir
    local space_moves = 0
    for i, room_id in ipairs(speedWalkPath) do
        if room_id and getRoomUserData(room_id, "fed2_flag_space") == "true" then
            space_moves = space_moves + 1
        end
    end

    return {origin_room_id=origin_room_id, dest_room_id=dest_room_id,
            total_moves=total_moves, space_moves=space_moves, success=true}
end

function f2t_map_show_route_info(origin, destination)
    if not destination or destination == "" then
        cecho("\n<red>[map]<reset> No destination specified\n"); return
    end
    local route_info, err = f2t_map_get_route_info(origin, destination)
    if not route_info then
        cecho(string.format("\n<red>[map]<reset> %s\n", err or "Could not calculate route")); return
    end
    local origin_name       = origin and origin ~= "" and origin or "Current location"
    local origin_room_name  = getRoomName(route_info.origin_room_id) or "Unknown"
    local dest_room_name    = getRoomName(route_info.dest_room_id)   or "Unknown"
    local origin_area_id    = getRoomArea(route_info.origin_room_id)
    local dest_area_id      = getRoomArea(route_info.dest_room_id)
    local origin_area_name  = origin_area_id and getRoomAreaName(origin_area_id) or "Unknown"
    local dest_area_name    = dest_area_id   and getRoomAreaName(dest_area_id)   or "Unknown"

    cecho("\n<cyan>═══════════════════════════════════════════════════════════<reset>\n")
    cecho("<cyan>                      Route Information<reset>\n")
    cecho("<cyan>═══════════════════════════════════════════════════════════<reset>\n\n")
    cecho("<yellow>Origin:<reset>\n")
    cecho(string.format("  <white>Query:<reset>    %s\n", origin_name))
    cecho(string.format("  <white>Room:<reset>     %s <dim_grey>(ID: %d)<reset>\n", origin_room_name, route_info.origin_room_id))
    cecho(string.format("  <white>Area:<reset>     %s\n\n", origin_area_name))
    cecho("<yellow>Destination:<reset>\n")
    cecho(string.format("  <white>Query:<reset>    %s\n", destination))
    cecho(string.format("  <white>Room:<reset>     %s <dim_grey>(ID: %d)<reset>\n", dest_room_name, route_info.dest_room_id))
    cecho(string.format("  <white>Area:<reset>     %s\n\n", dest_area_name))
    cecho("<yellow>Route Statistics:<reset>\n")
    cecho(string.format("  <white>Total Moves:<reset>  <green>%d<reset>\n", route_info.total_moves))
    cecho(string.format("  <white>Space Moves:<reset>  <ansiCyan>%d<reset> <dim_grey>(GTU)<reset>\n", route_info.space_moves))
    cecho(string.format("  <white>Ground Moves:<reset> %d\n", route_info.total_moves - route_info.space_moves))
    cecho("\n<cyan>═══════════════════════════════════════════════════════════<reset>\n")
end
