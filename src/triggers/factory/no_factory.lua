-- "You don't have a factory with that number!"
-- Handles the empty-slot case for both capture and flush sequences.

if f2t_factory.capturing then
    deleteLine()
    f2t_debug_log("[factory] Factory %d not found, recording as missing", f2t_factory.current_number)
    table.insert(f2t_factory.factories, { number = f2t_factory.current_number, missing = true })
    f2t_factory_query_next()
elseif f2t_factory.flushing then
    deleteLine()
    f2t_debug_log("[factory] Factory %d not found, skipping", f2t_factory.current_number)
    f2t_factory_flush_next()
end