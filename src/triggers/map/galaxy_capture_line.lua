if not F2T_MAP_EXPLORE_GALAXY_CAPTURE or not F2T_MAP_EXPLORE_GALAXY_CAPTURE.active then
    return
end

deleteLine()

local cartel_name = matches[2]

table.insert(F2T_MAP_EXPLORE_GALAXY_CAPTURE.lines, cartel_name)

f2t_debug_log("[map-explore-galaxy] Captured cartel: %s", cartel_name)

f2t_map_explore_galaxy_reset_timer()
