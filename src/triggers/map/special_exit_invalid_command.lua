if F2T_MAP_PENDING_SPECIAL_EXIT then
    local command = F2T_MAP_PENDING_SPECIAL_EXIT.command

    cecho(string.format("\n<red>[map]<reset> Invalid command: <white>%s<reset>\n", command))
    cecho("\n<dim_grey>Special exit discovery cancelled. Please check the command and try again.<reset>\n")

    f2t_debug_log("[map-special] Discovery failed: invalid command '%s'", command)

    F2T_MAP_PENDING_SPECIAL_EXIT = nil
end
