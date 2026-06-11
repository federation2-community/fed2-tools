if not F2T_MAP_DI_SYSTEM_CAPTURE or not F2T_MAP_DI_SYSTEM_CAPTURE.active then
    return
end

deleteLine()

f2t_debug_log("[map-di-system] Found system information header, starting planet capture")
