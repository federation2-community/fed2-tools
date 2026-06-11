if not F2T_MAP_DI_SYSTEM_CAPTURE or not F2T_MAP_DI_SYSTEM_CAPTURE.active then
    return
end

deleteLine()

table.insert(F2T_MAP_DI_SYSTEM_CAPTURE.planet_names, line)

f2t_map_di_system_reset_timer()
