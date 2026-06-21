-- commodities_price_capture — patterns declared in triggers.json
-- Capture price data from "check price <commodity> cartel" output
-- Triggers on lines like:
--   "Coffee: Affogato is selling 2780 tons at 643ig/ton"
--   "Coffee: Affogato is buying 75 tons at 526ig/ton"
--   "Updog: Cowhide is not currently trading in this commodity"

-- Only capture if we're in automated mode (set by price_output_start.lua)
if not F2T_PRICE_CAPTURE_ACTIVE then
    return
end

-- Hide the price line during automated capture
deleteLine()

-- Store the captured line
table.insert(F2T_PRICE_CAPTURE_DATA, line)

-- Reset capture timer (extends timeout on each new line)
f2t_price_reset_capture_timer()

f2t_debug_log("[commodities] Captured price line: %s", line)