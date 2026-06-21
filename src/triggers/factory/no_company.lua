-- "You don't have a company or business, let alone factories!"
-- Aborts whichever sequence is active with a helpful message.

if f2t_factory.capturing then
    deleteLine()
    f2t_debug_log("[factory] No company or business")
    cecho("\n<yellow>[factory]<reset> You don't have a company or business.\n")
    cecho("<dim_grey>You need to purchase a company first before building factories.<reset>\n")
    f2t_factory_reset()
elseif f2t_factory.flushing then
    deleteLine()
    f2t_debug_log("[factory] No company or business")
    f2t_factory.flushing       = false
    f2t_factory.current_number = 0
    f2t_factory.flush_count    = 0
    cecho("\n<yellow>[factory]<reset> You don't have a company or business.\n")
    cecho("<dim_grey>You need to purchase a company first before building factories.<reset>\n")
end