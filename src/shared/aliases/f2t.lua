-- @patterns:
--   - pattern: ^f2t(?:\s+(.+))?$

-- Main f2t command - handles all fed2-tools system commands
local args = matches[2]

-- No arguments - show help
if not args or args == "" then
    f2t_show_registered_help("f2t")
    return
end

-- Check for help request
if f2t_handle_help("f2t", args) then
    return
end

-- Parse subcommand
local subcommand = string.lower(args):match("^(%S+)")

if subcommand == "status" then
    -- f2t status - Show component states
    local status_rest = args:match("^status%s+(.+)") or ""

    -- Check for help request
    if f2t_handle_help("f2t status", status_rest) then
        return
    end

    f2t_show_status()

elseif subcommand == "debug" then
    -- f2t debug [on|off] - Control debug logging
    local debug_cmd = args:match("^debug%s+(.+)") or ""

    -- Check for help request
    if f2t_handle_help("f2t debug", debug_cmd) then
        return
    end

    if debug_cmd == "" then
        -- Show current state
        cecho(string.format("\n<green>[f2t]<reset> Debug mode: %s\n",
            F2T_DEBUG and "<yellow>ON<reset>" or "<yellow>OFF<reset>"))
        f2t_show_help_hint("f2t debug")
        return
    end

    if debug_cmd == "on" then
        f2t_set_debug(true)
        cecho("\n<green>[f2t]<reset> Debug mode <yellow>ON<reset>\n")
    elseif debug_cmd == "off" then
        f2t_set_debug(false)
        cecho("\n<green>[f2t]<reset> Debug mode <yellow>OFF<reset>\n")
    else
        cecho(string.format("\n<red>[f2t]<reset> Unknown debug option: %s\n", debug_cmd))
        f2t_show_help_hint("f2t debug")
    end

elseif subcommand == "settings" then
    -- f2t settings - Manage shared/system settings
    local settings_args = args:match("^settings%s*(.*)") or ""

    -- Check for help request
    if f2t_handle_help("f2t settings", settings_args) then
        return
    end

    f2t_handle_settings_command("shared", settings_args)

elseif subcommand == "version" then
    -- f2t version - Show package version and check for updates
    f2t_check_latest_version()

elseif subcommand == "reload" then
    -- f2t reload [fresh] - Dev-only: reinstall from local build (uninstall + install).
    -- Not advertised in help. See DEVELOPER.md for usage.
    local reload_args = args:match("^reload%s*(.*)") or ""
    local is_fresh = reload_args:match("^fresh") ~= nil
    f2t_devmode_reload(is_fresh)

else
    cecho(string.format("\n<red>[f2t]<reset> Unknown command: %s\n", subcommand))
    f2t_show_help_hint("f2t")
end
