-- Pre-reset auto-flush: on the six-minute shutdown warning, schedule a flush
-- four minutes out. Gated by both the feature toggle and the auto-flush setting.

if not f2t_settings_get("factory", "enabled") then return end
if not f2t_settings_get("factory", "auto_flush_before_reset") then
    f2t_debug_log("[factory] Shutdown warning received, auto-flush disabled")
    return
end

if f2t_factory.shutdown_timer_id then
    killTimer(f2t_factory.shutdown_timer_id)
    f2t_debug_log("[factory] Cancelled existing shutdown timer")
end

f2t_debug_log("[factory] Shutdown warning received, scheduling flush in 4 minutes")
cecho("\n<yellow>[factory]<reset> Game shutdown in 6 minutes - will flush factories in 4 minutes\n")

f2t_factory.shutdown_timer_id = tempTimer(240, function()
    f2t_debug_log("[factory] Auto-flush timer expired")
    cecho("\n<green>[factory]<reset> Auto-flushing factories before game reset...\n")
    f2t_factory_start_flush()
    f2t_factory.shutdown_timer_id = nil
end)