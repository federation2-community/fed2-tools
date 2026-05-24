-- Room styling for Federation 2 mapper
-- Applies visual indicators based on room flags using environment colors and symbols

-- ========================================
-- Mudlet Custom Environment Reference
-- ========================================
-- Mudlet's built-in custom environment IDs and their colors:
--   257 = Red           → multi-service surface hubs
--   258 = Green         → planet orbit
--   259 = Yellow        → system link (jump gate)
--   260 = Blue          → cartel link (hub system)
--   261 = Magenta       → exchange
--   262 = Cyan          → shuttlepad (alone)
--   263 = White         → hospital
--   264 = Black         → open space (default)
--   265 = Light Red     → death rooms (confirmed kill locations)
--   266 = Light Green   → courier/AC
--   267 = Light Yellow  → shipyard
--   268 = Light Blue    → generic locked rooms
--   269 = Light Magenta → bar
--   270 = Light Cyan    → (unused)
--   271 = Light White   → (unused)
--   272 = Light Black   → planet (default) and unknown flags

-- ========================================
-- Environment ID Configuration
-- ========================================

local ENV_MULTI_FLAG     = 257  -- Red: multi-service hub
local ENV_ORBIT          = 258  -- Green: planetary orbit
local ENV_LINK_SYSTEM    = 259  -- Yellow: system jump gate
local ENV_LINK_CARTEL    = 260  -- Blue: cartel hub jump gate
local ENV_EXCHANGE       = 261  -- Magenta: commodity exchange
local ENV_SHUTTLEPAD     = 262  -- Cyan: shuttlepad (alone)
local ENV_HOSPITAL       = 263  -- White: hospital
local ENV_SPACE_DEFAULT  = 264  -- Black: open space
local ENV_DEATH          = 265  -- Blood red: confirmed death location
local ENV_LOCKED         = 268  -- Dark slate: generic locked room
local ENV_COURIER        = 259  -- Yellow: courier/AC jobs (same base color as system links; symbol "AC" distinguishes)
local ENV_SHIPYARD       = 267  -- Light Yellow: shipyard
local ENV_BAR            = 269  -- Light Magenta: bar
local ENV_PLANET_DEFAULT = 272  -- Grey: standard planet room

-- ========================================
-- Symbol Constants
-- ========================================

local SYM_SHUTTLEPAD = "🚀"
local SYM_EXCHANGE   = "$"
local SYM_SHIPYARD   = "🔧"
local SYM_HOSPITAL   = "✚"
local SYM_BAR        = "🍸"
local SYM_COURIER    = "AC"
local SYM_LINK       = "⟡"
local SYM_UNKNOWN    = "?"
local SYM_DEATH      = "☠"
local SYM_LOCKED     = "🔒"

-- ========================================
-- Surface Room Style Definitions
-- ========================================

-- Ordered list for single-flag matching (first match in priority order wins).
local SURFACE_STYLES = {
    {flag = "shuttlepad", symbol = SYM_SHUTTLEPAD, env = ENV_SHUTTLEPAD},
    {flag = "exchange",   symbol = SYM_EXCHANGE,   env = ENV_EXCHANGE},
    {flag = "shipyard",   symbol = SYM_SHIPYARD,   env = ENV_SHIPYARD},
    {flag = "hospital",   symbol = SYM_HOSPITAL,   env = ENV_HOSPITAL},
    {flag = "bar",        symbol = SYM_BAR,         env = ENV_BAR},
    {flag = "courier",    symbol = SYM_COURIER,     env = ENV_COURIER},
}

-- Quick lookup: flag name → style entry
local SURFACE_FLAG_SET = {}
for _, entry in ipairs(SURFACE_STYLES) do
    SURFACE_FLAG_SET[entry.flag] = entry
end

-- Priority order for multi-flag rooms (first match wins → shown on red background).
-- Courier excluded: a courier+other-service room uses the other service's symbol.
local SURFACE_PRIORITY = {"shuttlepad", "exchange", "shipyard", "hospital", "bar"}

-- ========================================
-- Navigation Helpers
-- ========================================

-- Returns the symbol to display for an orbit room.
-- Uses the first letter of the stored planet name when orbit_planet_initial is enabled.
local function get_orbit_symbol(room_id, default_symbol)
    if f2t_settings_get("map", "orbit_planet_initial") then
        local planet = getRoomUserData(room_id, "fed2_planet")
        if planet and planet ~= "" then
            return string.upper(string.sub(planet, 1, 1))
        end
    end
    return default_symbol
end

-- Returns true when this link room is in the primary system of its cartel.
-- Primary system = the system whose name matches the cartel name
-- (e.g., "Frontier" system inside "Frontier" cartel → blue).
-- All other link rooms use yellow.
local function is_cartel_link(room_id)
    local system = getRoomUserData(room_id, "fed2_system")
    if not system or system == "" then return false end
    local area_id = getRoomArea(room_id)
    if not area_id then return false end
    local cartel = getAreaUserData(area_id, "fed2_cartel")
    if not cartel or cartel == "" then return false end
    return string.lower(system) == string.lower(cartel)
end

-- ========================================
-- Styling Application
-- ========================================

-- Apply visual styling to a room based on its flags.
-- Returns: true if special style was applied, false if using defaults.
function f2t_map_apply_room_style(room_id, flags)
    if not room_id or not roomExists(room_id) then
        f2t_debug_log("[map] ERROR: Cannot style invalid room: %s", tostring(room_id))
        return false
    end

    if not flags then flags = {} end

    local has_link  = f2t_has_value(flags, "link")
    local has_orbit = f2t_has_value(flags, "orbit")

    -- ── Navigation: link rooms (highest priority) ────────────────────────────
    -- Cartel hub = blue, regular system = yellow.
    -- Symbol: planet initial when also in orbit + setting on, otherwise ⟡.
    if has_link then
        local env    = is_cartel_link(room_id) and ENV_LINK_CARTEL or ENV_LINK_SYSTEM
        local symbol = has_orbit and get_orbit_symbol(room_id, SYM_LINK) or SYM_LINK
        setRoomChar(room_id, symbol)
        setRoomEnv(room_id, env)
        unsetRoomCharColor(room_id)
        f2t_debug_log("[map] Room %d styled: %s (link, env: %d)", room_id, symbol, env)
        return true
    end

    -- ── Navigation: orbit (not also a link) ──────────────────────────────────
    if has_orbit then
        local symbol = get_orbit_symbol(room_id, "O")
        setRoomChar(room_id, symbol)
        setRoomEnv(room_id, ENV_ORBIT)
        unsetRoomCharColor(room_id)
        f2t_debug_log("[map] Room %d styled: %s (orbit, env: %d)", room_id, symbol, ENV_ORBIT)
        return true
    end

    -- ── Planet surface rooms ──────────────────────────────────────────────────
    -- Strip navigation flags; evaluate only service flags.
    local nav_set = {orbit = true, link = true, space = true}
    local surface_flags = {}
    for _, flag in ipairs(flags) do
        if not nav_set[flag] then
            table.insert(surface_flags, flag)
        end
    end

    -- Count how many known service flags this room has.
    local known_count = 0
    for _, flag in ipairs(surface_flags) do
        if SURFACE_FLAG_SET[flag] then
            known_count = known_count + 1
        end
    end

    if known_count >= 2 then
        -- Multi-service hub: red background + highest-priority symbol.
        local top_style = nil
        for _, flag in ipairs(SURFACE_PRIORITY) do
            if f2t_has_value(surface_flags, flag) then
                top_style = SURFACE_FLAG_SET[flag]
                break
            end
        end
        if top_style then
            setRoomChar(room_id, top_style.symbol)
            setRoomEnv(room_id, ENV_MULTI_FLAG)
            unsetRoomCharColor(room_id)
            f2t_debug_log("[map] Room %d styled: %s (multi-flag, env: %d)",
                room_id, top_style.symbol, ENV_MULTI_FLAG)
        else
            setRoomChar(room_id, SYM_UNKNOWN)
            setRoomEnv(room_id, ENV_PLANET_DEFAULT)
            unsetRoomCharColor(room_id)
            f2t_debug_log("[map] Room %d styled: ? (multi-flag, no priority match)", room_id)
        end
        return true
    end

    if known_count == 1 then
        -- Single known service flag: individual color and symbol.
        for _, entry in ipairs(SURFACE_STYLES) do
            if f2t_has_value(surface_flags, entry.flag) then
                setRoomChar(room_id, entry.symbol)
                setRoomEnv(room_id, entry.env)
                unsetRoomCharColor(room_id)
                f2t_debug_log("[map] Room %d styled: %s (flag: %s, env: %d)",
                    room_id, entry.symbol, entry.flag, entry.env)
                return true
            end
        end
    end

    if #surface_flags > 0 then
        -- Has surface flags but none are in our known taxonomy.
        setRoomChar(room_id, SYM_UNKNOWN)
        setRoomEnv(room_id, ENV_PLANET_DEFAULT)
        unsetRoomCharColor(room_id)
        f2t_debug_log("[map] Room %d styled: ? (unknown flags: %s)",
            room_id, table.concat(surface_flags, ","))
        return true
    end

    -- No surface flags: default appearance.
    setRoomChar(room_id, "")
    unsetRoomCharColor(room_id)
    local is_space = f2t_has_value(flags, "space")
    if is_space then
        setRoomEnv(room_id, ENV_SPACE_DEFAULT)
        f2t_debug_log("[map] Room %d styled with space defaults (env: %d)", room_id, ENV_SPACE_DEFAULT)
    else
        setRoomEnv(room_id, ENV_PLANET_DEFAULT)
        f2t_debug_log("[map] Room %d styled with planet defaults (env: %d)", room_id, ENV_PLANET_DEFAULT)
    end
    return false
end

-- Apply blood-red skull styling for confirmed death rooms and manually-flagged danger rooms.
-- Called immediately when a death/danger marker is set, so the tile updates without a relog.
function f2t_map_apply_death_room_style(room_id)
    if not room_id or not roomExists(room_id) then return end
    setRoomChar(room_id, SYM_DEATH)
    setRoomEnv(room_id, ENV_DEATH)
    unsetRoomCharColor(room_id)
    f2t_debug_log("[map] Room %d styled: %s (death/danger, env: %d)", room_id, SYM_DEATH, ENV_DEATH)
end

-- Apply dark-slate lock styling for rooms that are locked without a death/danger marker.
-- Called by manual lock operations when no special danger metadata is present.
function f2t_map_apply_locked_room_style(room_id)
    if not room_id or not roomExists(room_id) then return end
    setRoomChar(room_id, SYM_LOCKED)
    setRoomEnv(room_id, ENV_LOCKED)
    unsetRoomCharColor(room_id)
    f2t_debug_log("[map] Room %d styled: %s (locked, env: %d)", room_id, SYM_LOCKED, ENV_LOCKED)
end

-- ========================================
-- Re-apply Styling for Existing Rooms
-- ========================================

-- Re-read flags from room user data and re-apply style.
-- Called on every room visit (new + existing) and when settings change.
function f2t_map_update_room_style(room_id)
    -- Death/danger rooms override flag-based styling regardless of other properties.
    local death_date = getRoomUserData(room_id, "f2t_death_date")
    local is_danger  = getRoomUserData(room_id, "f2t_danger")

    if (death_date and death_date ~= "") or (is_danger == "true") then
        f2t_map_apply_death_room_style(room_id)
        return
    end

    if roomLocked(room_id) then
        f2t_map_apply_locked_room_style(room_id)
        return
    end

    local flags = {}
    local known_flags = {
        "shuttlepad", "exchange", "orbit", "link", "space",
        "shipyard", "hospital", "bar", "courier"
    }

    for _, flag_name in ipairs(known_flags) do
        local key   = string.format("fed2_flag_%s", flag_name)
        local value = getRoomUserData(room_id, key)
        if value == "true" then
            table.insert(flags, flag_name)
        end
    end

    f2t_map_apply_room_style(room_id, flags)
end

-- ========================================
-- Style Query Functions (for legend and UI use)
-- ========================================

-- Get the default symbol for a flag type.
-- Orbit returns "O"; actual display may use planet initial at runtime.
-- Link returns ⟡; actual display may use planet initial when also orbit.
function f2t_map_get_flag_symbol(flag)
    if flag == "link"  then return SYM_LINK end
    if flag == "orbit" then return "O" end
    local entry = SURFACE_FLAG_SET[flag]
    return entry and entry.symbol or nil
end

-- Get the representative environment ID for a flag type.
-- Link returns system link env (yellow); cartel determination is a runtime decision.
function f2t_map_get_flag_env(flag)
    if flag == "link"  then return ENV_LINK_SYSTEM end
    if flag == "orbit" then return ENV_ORBIT end
    local entry = SURFACE_FLAG_SET[flag]
    return entry and entry.env or nil
end

-- All room types use environment color only; no separate character color.
function f2t_map_get_flag_color(flag)
    return nil
end

-- RGB values matching setCustomEnvColor() calls above, keyed by env ID.
-- Env 272 (planet default) intentionally omitted — nil return means no badge.
local ENV_COLOR_RGB = {
    [257] = {200,  50,  50},
    [258] = { 50, 160,  50},
    [259] = {185, 165,  30},
    [260] = { 50, 100, 200},
    [261] = {120,   0,  30},
    [262] = { 30, 170, 170},
    [263] = { 40, 130,  40},
    [265] = {120,   0,   0},  -- Death: blood red
    [267] = {140,  80,  20},
    [268] = { 50,  50,  65},  -- Locked: dark slate
    [269] = {200, 120,   0},
}

-- Returns r, g, b for the badge color associated with a flag type.
-- Returns nil for flags with no distinct badge (plain planet rooms).
function f2t_map_get_flag_badge_rgb(flag)
    local env = f2t_map_get_flag_env(flag)
    if not env then return nil end
    local color = ENV_COLOR_RGB[env]
    if not color then return nil end
    return color[1], color[2], color[3]
end

-- Convert an env ID's RGB entry to an HTML hex color string.
local function env_hex(env_id)
    local c = ENV_COLOR_RGB[env_id]
    if not c then return "#666666" end
    return string.format("#%02x%02x%02x", c[1], c[2], c[3])
end

-- Returns a structured table describing every named room type, for building the legend.
-- Each entry: {label, symbol, html_color, [text_color], note}
-- text_color is optional; defaults to "#ddeeff" if omitted (legend renders it).
-- html_color is derived from ENV_COLOR_RGB so map tiles and legend stay in sync.
function f2t_map_get_legend_data()
    return {
        {label = "Death Room",              symbol = SYM_DEATH,      html_color = env_hex(ENV_DEATH),                             note = "Confirmed kill — navigation locked"},
        {label = "Locked Room",             symbol = SYM_LOCKED,     html_color = env_hex(ENV_LOCKED),                            note = "Manually locked — navigation avoids"},
        {label = "Cartel Link",             symbol = SYM_LINK,       html_color = env_hex(ENV_LINK_CARTEL),                       note = "Hub system jump gate"},
        {label = "System Link",             symbol = SYM_LINK,       html_color = env_hex(ENV_LINK_SYSTEM), text_color = "#141400", note = "Jump gate"},
        {label = "Orbit",                   symbol = "E / O",        html_color = env_hex(ENV_ORBIT),       text_color = "#001a00", note = "Above planet (first letter = planet name)"},
        {label = "Multi-service",           symbol = "🚀 / $ …",     html_color = env_hex(ENV_MULTI_FLAG),                        note = "2+ services — top priority shown"},
        {label = "Shuttlepad",              symbol = SYM_SHUTTLEPAD, html_color = env_hex(ENV_SHUTTLEPAD),  text_color = "#001a1a", note = "Dock / launch pad"},
        {label = "Exchange",                symbol = SYM_EXCHANGE,   html_color = env_hex(ENV_EXCHANGE),                          note = "Commodity market"},
        {label = "Shipyard",                symbol = SYM_SHIPYARD,   html_color = env_hex(ENV_SHIPYARD),    text_color = "#ffd090", note = "Repairs & upgrades"},
        {label = "Hospital",                symbol = SYM_HOSPITAL,   html_color = env_hex(ENV_HOSPITAL),    text_color = "#88dd88", note = "Medical"},
        {label = "Bar",                     symbol = SYM_BAR,        html_color = env_hex(ENV_BAR),         text_color = "#1a0800", note = "Food & drink"},
        {label = "Armstrong Cuthbert (AC)", symbol = SYM_COURIER,    html_color = env_hex(ENV_COURIER),     text_color = "#141400", note = "AC offices — courier jobs"},
    }
end

-- ========================================
-- Custom Environment Colours
-- ========================================

-- Apply custom colours so the 2D mapper room tiles match the badge palette above.
-- Called once on load; setCustomEnvColor() persists in the Mudlet profile.
local function f2t_map_apply_env_colors()
    setCustomEnvColor(257, 200,  50,  50, 255)  -- Multi-service: red
    setCustomEnvColor(258,  50, 160,  50, 255)  -- Orbit:         green
    setCustomEnvColor(259, 185, 165,  30, 255)  -- Yellow (system link + AC courier)
    setCustomEnvColor(260,  50, 100, 200, 255)  -- Cartel link:   blue
    setCustomEnvColor(261, 120,   0,  30, 255)  -- Exchange:      maroon
    setCustomEnvColor(262,  30, 170, 170, 255)  -- Shuttlepad:    cyan
    setCustomEnvColor(263,  40, 130,  40, 255)  -- Hospital:      green
    setCustomEnvColor(264,  40,  40,  40, 255)  -- Space:         dark grey
    setCustomEnvColor(265, 120,   0,   0, 255)  -- Death:         blood red
    setCustomEnvColor(267, 140,  80,  20, 255)  -- Shipyard:      brown
    setCustomEnvColor(268,  50,  50,  65, 255)  -- Locked:        dark slate
    setCustomEnvColor(269, 200, 120,   0, 255)  -- Bar:           orange
    setCustomEnvColor(272,  80,  80,  90, 255)  -- Planet default: mid grey
end

f2t_map_apply_env_colors()

-- ========================================
-- Bulk Restyle
-- ========================================

--- Re-apply correct styling to every room in the map database based on its current metadata.
--- Useful after visual changes (new env colors, icon updates) or to fix rooms that were
--- styled under old logic (e.g. rooms visited before death/locked icons were introduced).
--- No movement required — reads metadata directly from the map database.
--- @return number rooms_processed Total rooms styled
function f2t_map_restyle_all()
    local rooms = getRooms()
    if not rooms then
        cecho("\n<red>[map]<reset> No rooms found in map database\n")
        return 0
    end

    local count = 0
    for room_id, _ in pairs(rooms) do
        f2t_map_update_room_style(room_id)
        count = count + 1
    end

    updateMap()

    cecho(string.format("\n<green>[map]<reset> Restyled <white>%d<reset> rooms based on current metadata\n", count))
    f2t_debug_log("[map_style] Bulk restyle complete: %d rooms processed", count)

    return count
end
