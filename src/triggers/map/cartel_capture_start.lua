if not F2T_MAP_EXPLORE_CARTEL_CAPTURE or not F2T_MAP_EXPLORE_CARTEL_CAPTURE.active then
    return
end

deleteLine()

F2T_MAP_EXPLORE_CARTEL_CAPTURE.in_members = true

f2t_debug_log("[map-explore-cartel] Found Members section, starting system capture")
