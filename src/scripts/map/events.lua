-- fed2-tools map — GMCP event handler registration (ported from map_events.lua)

local success, handler_id = pcall(registerAnonymousEventHandler, "gmcp.room.info", "f2t_map_handle_gmcp_room")

if success and handler_id then
    f2t_debug_log("[map] Registered GMCP event handler for gmcp.room.info (ID: %s)", tostring(handler_id))
else
    f2t_debug_log("[map] WARNING: Failed to register GMCP event handler: %s", tostring(handler_id))
end
