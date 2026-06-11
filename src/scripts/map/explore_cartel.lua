-- fed2-tools map — Layer 3 cartel exploration (ported from map_explore_cartel.lua)
-- TODO: Full port pending — stubs prevent crashes

function f2t_map_explore_cartel_start(cartel_name)
    cecho(string.format("\n<yellow>[map-explore]<reset> Cartel exploration not yet fully implemented.\n"))
    cecho(string.format("  Cartel: %s\n", cartel_name or "?"))
    return false
end

function f2t_map_explore_cartel_next_system()
    f2t_debug_log("[map-explore-cartel] next_system stub called")
    f2t_map_explore_complete()
end

function f2t_map_explore_cartel_start_system_mode(system_name)
    f2t_debug_log("[map-explore-cartel] start_system_mode stub: %s", system_name or "?")
    f2t_map_explore_system_start(system_name, "brief", function()
        f2t_map_explore_cartel_next_system()
    end)
end

f2t_debug_log("[map] Loaded explore_cartel.lua (stub)")
