-- fed2-tools map — Layer 2 system exploration (ported from map_explore_system.lua)
-- TODO: Full port pending — stubs prevent crashes until complete implementation is added

function f2t_map_explore_system_start(system_name, system_mode, on_complete_callback)
    cecho(string.format("\n<yellow>[map-explore]<reset> System exploration not yet fully implemented.\n"))
    cecho(string.format("  System: %s  Mode: %s\n", system_name or "?", system_mode or "brief"))
    return false
end

function f2t_map_explore_system_start_with_planets(system_name, system_mode, expected_planet_names, planets_without_exchange, on_complete_callback)
    f2t_debug_log("[map-explore-system] start_with_planets stub called")
end

function f2t_map_explore_system_space_complete()
    f2t_debug_log("[map-explore-system] space_complete stub called")
    if F2T_MAP_EXPLORE_STATE.system_phase == "exploring_space" then
        f2t_map_explore_system_next_planet()
    end
end

function f2t_map_explore_system_board_planet()
    f2t_debug_log("[map-explore-system] board_planet stub called")
end

function f2t_map_explore_system_next_planet()
    f2t_debug_log("[map-explore-system] next_planet stub called")
    f2t_map_explore_complete()
end

function f2t_map_explore_system_brief_next_planet()
    f2t_debug_log("[map-explore-system] brief_next_planet stub called")
    f2t_map_explore_system_next_planet()
end

function f2t_map_explore_planet_find_exchange()
    f2t_debug_log("[map-explore-system] find_exchange stub called")
end

function f2t_map_explore_brief_find_next_flag()
    f2t_debug_log("[map-explore-system] brief_find_next_flag stub called")
end

f2t_debug_log("[map] Loaded explore_system.lua (stub)")
