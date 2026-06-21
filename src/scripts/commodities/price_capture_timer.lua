-- Timer-based capture completion for commodities price check
-- Replaces unreliable prompt trigger with timer-based approach

-- Timer ID for capture completion
F2T_PRICE_CAPTURE_TIMER_ID = nil

-- Start or reset the capture timer
-- Called on each captured line to extend the timeout
function f2t_price_reset_capture_timer()
    -- Kill existing timer if any
    if F2T_PRICE_CAPTURE_TIMER_ID then
        killTimer(F2T_PRICE_CAPTURE_TIMER_ID)
        F2T_PRICE_CAPTURE_TIMER_ID = nil
    end

    -- Start new timer (0.5s after last line = capture complete)
    F2T_PRICE_CAPTURE_TIMER_ID = tempTimer(0.5, function()
        F2T_PRICE_CAPTURE_TIMER_ID = nil
        if F2T_PRICE_CAPTURE_ACTIVE then
            f2t_price_process_capture()
        end
    end)
end

-- Process captured price data
-- Called when timer expires (no more lines received)
function f2t_price_process_capture()
    f2t_debug_log("[commodities] Price capture ended, processing %d lines", #F2T_PRICE_CAPTURE_DATA)

    -- Parse the captured data
    local parsed_data = f2t_price_parse_data(F2T_PRICE_CAPTURE_DATA)

    -- Analyze the commodity
    local analysis = f2t_price_analyze_commodity(F2T_PRICE_CURRENT_COMMODITY, parsed_data)

    -- If there's a callback, use it (for 'price all' functionality)
    -- Otherwise, display the results (for 'price <commodity>')
    if F2T_PRICE_CALLBACK then
        f2t_debug_log("[commodities] Calling callback for: %s", F2T_PRICE_CURRENT_COMMODITY)

        -- Save callback and commodity name before resetting state
        local callback = F2T_PRICE_CALLBACK
        local commodity_name = F2T_PRICE_CURRENT_COMMODITY

        -- Reset capture state BEFORE calling callback (in case callback initiates another price check)
        F2T_PRICE_CAPTURE_ACTIVE = false
        F2T_PRICE_CAPTURE_DATA = {}
        F2T_PRICE_CURRENT_COMMODITY = nil
        F2T_PRICE_CALLBACK = nil

        -- Now call the callback with saved values
        callback(commodity_name, parsed_data, analysis)
        f2t_debug_log("[commodities] Callback completed")
    else
        f2t_debug_log("[commodities] No callback, displaying results")
        f2t_price_display_commodity(F2T_PRICE_CURRENT_COMMODITY, analysis)

        -- Reset capture state
        F2T_PRICE_CAPTURE_ACTIVE = false
        F2T_PRICE_CAPTURE_DATA = {}
        F2T_PRICE_CURRENT_COMMODITY = nil
        F2T_PRICE_CALLBACK = nil
    end
end

f2t_debug_log("[commodities] Price capture timer loaded")