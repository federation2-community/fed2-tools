-- commodities_price_output_continuation — patterns declared in triggers.json
-- Continuation of broker message (second line)
-- Only delete if we're actively capturing (automated price check)
if F2T_PRICE_CAPTURE_ACTIVE then
    deleteLine()
    f2t_debug_log("[commodities] Captured continuation line (automated)")
end