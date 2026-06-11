if not F2T_MAP_EXPLORE_CARTEL_CAPTURE or not F2T_MAP_EXPLORE_CARTEL_CAPTURE.active then
    return
end

if not F2T_MAP_EXPLORE_CARTEL_CAPTURE.in_members then
    return
end

deleteLine()

local system_name = matches[2]:match("^(.-)%s+%-.+$") or matches[2]

table.insert(F2T_MAP_EXPLORE_CARTEL_CAPTURE.lines, system_name)

f2t_debug_log("[map-explore-cartel] Captured member system: %s", system_name)

f2t_map_explore_cartel_reset_timer()
