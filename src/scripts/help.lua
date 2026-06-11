-- fed2-tools — help system (ported from f2t_help.lua + f2t_help_registry.lua)

-- ── Display ───────────────────────────────────────────────────────────────────

function f2t_show_help(command, description, usage, examples)
    cecho(string.format("\n<green>[%s]<reset> %s\n\n", command, description))

    if usage and #usage > 0 then
        cecho("<yellow>Usage:<reset>\n")
        for _, u in ipairs(usage) do
            if u.cmd == "" and (not u.desc or u.desc == "") then
                cecho("\n")
            else
                cecho(string.format("  <cyan>%s<reset>\n", u.cmd))
                if u.desc and u.desc ~= "" then
                    cecho(string.format("    <dim_grey>%s<reset>\n", u.desc))
                end
            end
        end
        cecho("\n")
    end

    if examples and #examples > 0 then
        cecho("<yellow>Examples:<reset>\n")
        for _, example in ipairs(examples) do
            if example == "" then
                cecho("\n")
            else
                cecho(string.format("  <cyan>%s<reset>\n", example))
            end
        end
        cecho("\n")
    end
end

function f2t_is_help_request(args)
    if not args or args == "" then return false end
    return string.lower(args) == "help"
end

function f2t_show_help_hint(command)
    cecho(string.format("\n<dim_grey>Use '%s help' for more information<reset>\n", command))
end

-- ── Registry ─────────────────────────────────────────────────────────────────

F2T_HELP_REGISTRY = F2T_HELP_REGISTRY or {}

function f2t_register_help(command, config)
    if not command or command == "" then return false end
    if not config or not config.description then return false end
    F2T_HELP_REGISTRY[command] = {
        description = config.description,
        usage       = config.usage   or {},
        examples    = config.examples or {},
    }
    return true
end

function f2t_show_registered_help(command)
    local help_config = F2T_HELP_REGISTRY[command]
    if not help_config then return false end
    f2t_show_help(command, help_config.description, help_config.usage, help_config.examples)
    return true
end

function f2t_handle_help(command, arg)
    if not f2t_is_help_request(arg) then return false end
    return f2t_show_registered_help(command)
end
