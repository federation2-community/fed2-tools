-- commodities_price_output_start — patterns declared in triggers.json
-- Detect start of price check output
-- Only capture and hide output if this is an automated price check (F2T_PRICE_CURRENT_COMMODITY is set)
-- If user manually runs "check price", let the output show normally
if F2T_PRICE_CURRENT_COMMODITY and not F2T_PRICE_CAPTURE_ACTIVE then
    deleteLine()  -- Hide the broker message during automated capture
    F2T_PRICE_CAPTURE_ACTIVE = true
    F2T_PRICE_CAPTURE_DATA = {}

    -- Start capture timer (will complete when no more lines arrive)
    f2t_price_reset_capture_timer()

    f2t_debug_log("[commodities] Price capture started (automated)")
end