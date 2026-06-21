-- A factory slot was successfully flushed during a flush sequence.

if f2t_factory.flushing then
    deleteLine()
    f2t_factory.flush_count = f2t_factory.flush_count + 1
    f2t_debug_log("[factory] Flushed factory %d", tonumber(matches[2]))
    f2t_factory_flush_next()
end