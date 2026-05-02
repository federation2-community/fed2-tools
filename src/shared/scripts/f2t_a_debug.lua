-- Helper function for debug logging with format string support
-- Usage: f2t_debug_log("Player %s has %d gold", playerName, goldAmount)
function f2t_debug_log(format_str, ...)
    if F2T_DEBUG then
        local message
        if select("#", ...) > 0 then
            -- Format string with arguments
            message = string.format(format_str, ...)
        else
            -- No arguments, use format_str as-is
            message = format_str
        end
        cecho(string.format("\n<cyan>[F2T DEBUG]<reset> %s\n", message))
    end
end

-- Helper function to save debug setting
function f2t_set_debug(enabled)
    F2T_DEBUG = enabled
    f2t_settings_set("shared", "debug", enabled)
end