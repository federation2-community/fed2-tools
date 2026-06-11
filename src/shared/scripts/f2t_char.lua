-- =============================================================================
-- f2t_char — character identity and per-character persistent directory
-- =============================================================================

F2T_CHAR_NAME     = nil   -- set on first gmcp.char.vitals update after login
local _login_done = false  -- prevents re-running setup on repeated gmcp.char fires

-- Returns the persistent data directory for the current character.
-- Falls back to the base directory when no character is known yet.
function f2t_get_char_persistent_dir()
    local base = getMudletHomeDir() .. "/fed2-tools-persistent"
    if F2T_CHAR_NAME and F2T_CHAR_NAME ~= "" then
        return base .. "/" .. F2T_CHAR_NAME:lower()
    end
    return base
end

-- Called on gmcp.char event. On first fire after a new connection, sets
-- F2T_CHAR_NAME, ensures the per-char directory exists, redirects settings
-- saves to the per-char path, and signals UI subsystems to reload their data.
function f2t_on_char_detected()
    local name = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if not name or name == "" then return end
    if _login_done and F2T_CHAR_NAME == name then return end

    local prev    = F2T_CHAR_NAME
    F2T_CHAR_NAME = name
    _login_done   = true

    lfs.mkdir(getMudletHomeDir() .. "/fed2-tools-persistent")
    lfs.mkdir(f2t_get_char_persistent_dir())

    f2t_reload_settings_for_char()

    if prev ~= name then
        if ui_chat_reload      then ui_chat_reload()      end
        if ui_player_db_reload then ui_player_db_reload() end
    end

    f2t_debug_log("[char] logged in as %s", name)
end

-- Reset per-login guard on new connection so the next login is detected fresh.
function f2t_char_reset()
    _login_done = false
end
