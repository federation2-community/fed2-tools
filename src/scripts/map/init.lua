-- fed2-tools map — initialization
--
-- Declares this package as the Mudlet mapper controller, registers all map
-- settings, and initializes global map state variables.

mudlet = mudlet or {}
mudlet.mapper_script = true

-- ── Settings ──────────────────────────────────────────────────────────────────

f2t_settings_register("map", "planet_nav_default", {
    description = "Default destination when navigating to a planet (shuttlepad, orbit, or exchange)",
    default = "shuttlepad",
    choices = {"shuttlepad", "orbit", "exchange"},
})

f2t_settings_register("map", "enabled", {
    description = "Enable/disable auto-mapping",
    default = true,
})

f2t_settings_register("map", "speedwalk_timeout", {
    description = "Timeout in seconds to wait for movement (detects stuck speedwalk)",
    default = 3,
    min = 1, max = 10,
})

f2t_settings_register("map", "speedwalk_max_retries", {
    description = "Maximum retry attempts before stopping speedwalk",
    default = 3,
    min = 1, max = 10,
})

f2t_settings_register("map", "speedwalk_brief", {
    description = "Use brief room descriptions during speedwalk",
    default = true,
})

f2t_settings_register("map", "speedwalk_after_mode", {
    description = "Room description mode to restore after speedwalk ends (brief or full)",
    default = "full",
    choices = {"brief", "full"},
})

f2t_settings_register("map", "map_manual_confirm", {
    description = "Require confirmation for destructive manual mapping operations",
    default = true,
})

f2t_settings_register("map", "area_zoom", {
    description = "Default zoom level for new map areas (3-50)",
    default = 10,
    min = 3, max = 50,
})

f2t_settings_register("map", "brief_additional_flags", {
    description = "Additional flags to discover in brief mode (shuttlepad is always included)",
    default = "exchange, courier",
})

f2t_settings_register("map", "orbit_planet_initial", {
    description = "Use first letter of planet name as orbit room label instead of 'O'",
    default = true,
})

f2t_settings_register("map", "movement_keys", {
    description = "Enable numpad keys for directional movement",
    default = true,
})

-- ── Globals ───────────────────────────────────────────────────────────────────

F2T_MAP_ENABLED            = f2t_settings_get("map", "enabled")
F2T_MAP_PLANET_NAV_DEFAULT = f2t_settings_get("map", "planet_nav_default")
F2T_MAP_MOVEMENT_KEYS      = f2t_settings_get("map", "movement_keys")
F2T_MAP_CURRENT_ROOM_ID    = nil

f2t_debug_log("[map] Mapper initialized (enabled=%s)", tostring(F2T_MAP_ENABLED))
