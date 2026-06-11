-- fed2-tools — debug logging shim
--
-- Provides f2t_debug_log() backed by Mux.debug so the existing map scripts
-- work without modification. F2T_DEBUG is kept for scripts that check it directly.

F2T_DEBUG = false

function f2t_debug_log(format_str, ...)
    local debug_on = (Mux and Mux.debug) or F2T_DEBUG
    if not debug_on then return end
    local message
    if select("#", ...) > 0 then
        message = string.format(format_str, ...)
    else
        message = format_str
    end
    cecho(string.format("\n<cyan>[F2T DEBUG]<reset> %s\n", message))
end

function f2t_set_debug(enabled)
    F2T_DEBUG = enabled
    if Mux and Mux.settings and Mux.settings.set then
        Mux.settings.set("mux", "debug", enabled)
    end
end
