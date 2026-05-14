-- Room styling for Federation 2 mapper
-- Applies visual indicators based on room flags using emojis and environment colors

-- ========================================
-- Mudlet Custom Environment Reference
-- ========================================
-- Mudlet's built-in custom environment IDs and their colors:
--   257 = Red
--   258 = Green
--   259 = Yellow
--   260 = Blue
--   261 = Magenta
--   262 = Cyan
--   263 = White
--   264 = Black
--   265 = Light Red
--   266 = Light Green
--   267 = Light Yellow
--   268 = Light Blue
--   269 = Light Magenta
--   270 = Light Cyan
--   271 = Light White
--   272 = Light Black (Grey)

-- ========================================
-- Environment ID Configuration
-- ========================================

-- Environment IDs for room background colors
local ENV_SHUTTLEPAD = 257   -- Red
local ENV_ORBIT = 258        -- Green
local ENV_LINK = 262         -- Cyan
local ENV_SPACE_DEFAULT = 264  -- Black
local ENV_EXCHANGE = 261     -- Light Green
local ENV_PLANET_DEFAULT = 272  -- Light Black (Grey)

-- ========================================
-- Flag-based Styling Configuration
-- ========================================

-- Priority-ordered styling rules (first match wins)
-- Orbit takes precedence over link for rooms with both flags
-- color is optional {r, g, b} - nil means no character color
local FLAG_STYLES = {
    {flag = "shuttlepad", symbol = "S", env = ENV_SHUTTLEPAD, color = nil},
    {flag = "exchange", symbol = "E", env = ENV_EXCHANGE, color = nil},
    {flag = "orbit", symbol = "O", env = ENV_ORBIT, color = nil},
    {flag = "link", symbol = "L", env = ENV_LINK, color = nil}
}

-- Default styling for rooms with no special flags
local DEFAULT_SYMBOL = ""

-- ========================================
-- Orbit Symbol Helper
-- ========================================

-- Returns the symbol to use for an orbit room.
-- When orbit_planet_initial is enabled, uses the first letter of the stored planet name.
-- Falls back to default_symbol if the setting is off or the planet name isn't stored yet.
local function get_orbit_symbol(room_id, default_symbol)
    if f2t_settings_get("map", "orbit_planet_initial") then
        local planet = getRoomUserData(room_id, "fed2_planet")
        if planet and planet ~= "" then
            return string.upper(string.sub(planet, 1, 1))
        end
    end
    return default_symbol
end

-- ========================================
-- Styling Application
-- ========================================

-- Apply visual styling to a room based on its flags
-- Returns: true if special style was applied, false if using defaults
function f2t_map_apply_room_style(room_id, flags)
    if not room_id or not roomExists(room_id) then
        f2t_debug_log("[map] ERROR: Cannot style invalid room: %s", tostring(room_id))
        return false
    end

    -- Ensure flags is a table
    if not flags then
        flags = {}
    end

    -- Special case: rooms with both link and orbit flags
    local has_link = f2t_has_value(flags, "link")
    local has_orbit = f2t_has_value(flags, "orbit")
    if has_link and has_orbit then
        local symbol = get_orbit_symbol(room_id, "Ø")
        setRoomChar(room_id, symbol)
        setRoomEnv(room_id, ENV_ORBIT)  -- Use orbit environment
        unsetRoomCharColor(room_id)
        f2t_debug_log("[map] Room %d styled: %s (link+orbit, env: %d)", room_id, symbol, ENV_ORBIT)
        return true
    end

    -- Find first matching flag in priority order
    for _, style in ipairs(FLAG_STYLES) do
        if f2t_has_value(flags, style.flag) then
            -- Apply symbol (orbit uses dynamic label based on setting)
            local symbol = style.flag == "orbit" and get_orbit_symbol(room_id, style.symbol) or style.symbol
            setRoomChar(room_id, symbol)

            -- Apply environment (background color)
            setRoomEnv(room_id, style.env)

            -- Apply character color if specified
            if style.color then
                setRoomCharColor(room_id, style.color[1], style.color[2], style.color[3])
            else
                unsetRoomCharColor(room_id)
            end

            f2t_debug_log("[map] Room %d styled: %s (flag: %s, env: %d)",
                room_id, symbol, style.flag, style.env)

            return true
        end
    end

    -- No special flags, use default styling based on space vs planet
    setRoomChar(room_id, DEFAULT_SYMBOL)
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

-- ========================================
-- Style Configuration
-- ========================================

-- Get the symbol for a specific flag
-- Returns: symbol string or nil
function f2t_map_get_flag_symbol(flag)
    for _, style in ipairs(FLAG_STYLES) do
        if style.flag == flag then
            return style.symbol
        end
    end
    return nil
end

-- Get the environment ID for a specific flag
-- Returns: env_id or nil
function f2t_map_get_flag_env(flag)
    for _, style in ipairs(FLAG_STYLES) do
        if style.flag == flag then
            return style.env
        end
    end
    return nil
end

-- Get the color for a specific flag
-- Returns: r, g, b or nil
function f2t_map_get_flag_color(flag)
    for _, style in ipairs(FLAG_STYLES) do
        if style.flag == flag and style.color then
            return style.color[1], style.color[2], style.color[3]
        end
    end
    return nil
end

-- Update styling for an existing room (e.g., if flags change)
function f2t_map_update_room_style(room_id)
    -- Read flags from individual user data fields
    local flags = {}
    local known_flags = {"shuttlepad", "exchange", "orbit", "link", "space"}

    for _, flag_name in ipairs(known_flags) do
        local key = string.format("fed2_flag_%s", flag_name)
        local flag_value = getRoomUserData(room_id, key)
        if flag_value == "true" then
            table.insert(flags, flag_name)
        end
    end

    f2t_map_apply_room_style(room_id, flags)
end
