if not F2T_MAP_EXPLORE_GALAXY_CAPTURE or not F2T_MAP_EXPLORE_GALAXY_CAPTURE.active then
    return
end

deleteLine()

f2t_debug_log("[map-explore-galaxy] Found galaxy cartels header")

f2t_map_explore_galaxy_reset_timer()
