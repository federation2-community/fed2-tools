-- Settings persistence functions
-- Handles saving/loading user settings to disk

-- Define settings file path (must be defined before functions use it)
-- Note: @PKGNAME@ substitution only works in XML, use actual package name
F2T_SETTINGS_FILE = F2T_SETTINGS_FILE or (getMudletHomeDir() .. "/fed2-tools_settings.json")

-- Save settings to disk
function f2t_save_settings()
    if not f2t_settings then
        cecho("\n<red>[settings]<reset> ERROR: f2t_settings table does not exist\n")
        return false
    end

    if not F2T_SETTINGS_FILE then
        cecho("\n<red>[settings]<reset> ERROR: F2T_SETTINGS_FILE is not defined\n")
        return false
    end

    local success, err = pcall(function()
        -- Use JSON serialization instead of table.save() for better compatibility
        local json_str = yajl.to_string(f2t_settings)
        local file = io.open(F2T_SETTINGS_FILE, "w")
        file:write(json_str)
        file:close()
    end)

    if success then
        f2t_debug_log("[settings] Settings saved to disk: %s", F2T_SETTINGS_FILE)
        return true
    else
        cecho(string.format("\n<red>[settings]<reset> ERROR: Failed to save settings: %s\n", tostring(err)))
        f2t_debug_log("[settings] ERROR: Failed to save settings: %s", tostring(err))
        return false
    end
end

-- Redirect to per-character settings file and reload.
-- Called by f2t_on_char_detected() after F2T_CHAR_NAME is set.
function f2t_reload_settings_for_char()
    F2T_SETTINGS_FILE = f2t_get_char_persistent_dir() .. "/settings.json"
    f2t_load_settings()
    f2t_debug_log("[settings] redirected to char %s", F2T_CHAR_NAME or "unknown")
end

-- Load settings from disk
function f2t_load_settings()
    if not io.exists(F2T_SETTINGS_FILE) then
        f2t_debug_log("[settings] No settings file found: %s", F2T_SETTINGS_FILE)
        return false
    end

    local success, err = pcall(function()
        -- Use JSON deserialization to load settings
        local file = io.open(F2T_SETTINGS_FILE, "r")
        local json_str = file:read("*all")
        file:close()

        local loaded_settings = yajl.to_value(json_str)

        -- Merge loaded settings into f2t_settings
        f2t_settings = f2t_settings or {}
        for k, v in pairs(loaded_settings) do
            f2t_settings[k] = v
        end
    end)

    if success then
        f2t_debug_log("[settings] Settings loaded from disk: %s", F2T_SETTINGS_FILE)
        return true
    else
        f2t_debug_log("[settings] ERROR: Failed to load settings: %s", tostring(err))
        cecho(string.format("\n<red>[fed2-tools]<reset> Failed to load settings: %s\n", tostring(err)))
        return false
    end
end
