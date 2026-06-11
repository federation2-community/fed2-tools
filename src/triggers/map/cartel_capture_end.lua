if not F2T_MAP_EXPLORE_CARTEL_CAPTURE or not F2T_MAP_EXPLORE_CARTEL_CAPTURE.active then
    return
end

if not F2T_MAP_EXPLORE_CARTEL_CAPTURE.in_members then
    return
end

deleteLine()

F2T_MAP_EXPLORE_CARTEL_CAPTURE.in_members = false

f2t_debug_log("[map-explore-cartel] End of Members section, waiting for output to finish...")

f2t_map_explore_cartel_reset_timer()
