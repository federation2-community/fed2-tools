-- Capture factory display output lines into the capture buffer.
-- Patterns are declared in triggers.json. Active only during capture.

if f2t_factory.capturing then
    -- Let factory_no_factory handle the empty-slot line instead.
    if not line:find("You don't have a factory with that number!") then
        deleteLine()
        table.insert(f2t_factory.capture_buffer, line)
        f2t_debug_log("[factory] Captured: %s", line:sub(1, 50))
        f2t_factory_reset_capture_timer()
    end
end