if not F2T_MAP_DI_SYSTEM_CAPTURE or not F2T_MAP_DI_SYSTEM_CAPTURE.active then
    return
end

deleteLine()

local planet_line = matches[2]

table.insert(F2T_MAP_DI_SYSTEM_CAPTURE.planet_names, planet_line)

f2t_debug_log("[map-di-system] Captured planet line: %s", planet_line)

f2t_map_di_system_reset_timer()
