-- fed2-tools map — Layer 4 galaxy exploration (ported from map_explore_galaxy.lua)
-- TODO: Full port pending — stubs prevent crashes

function f2t_map_explore_galaxy_start()
    cecho("\n<yellow>[map-explore]<reset> Galaxy exploration not yet fully implemented.\n")
    return false
end

function f2t_map_explore_galaxy_next_cartel()
    f2t_debug_log("[map-explore-galaxy] next_cartel stub called")
    f2t_map_explore_complete()
end

function f2t_map_explore_galaxy_start_cartel_mode(cartel_name)
    f2t_debug_log("[map-explore-galaxy] start_cartel_mode stub: %s", cartel_name or "?")
    f2t_map_explore_cartel_start(cartel_name)
end

f2t_debug_log("[map] Loaded explore_galaxy.lua (stub)")
