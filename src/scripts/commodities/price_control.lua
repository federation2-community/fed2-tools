-- Control functions for checking commodity prices
-- Handles sending commands and managing capture state

-- Start a price check for a single commodity
-- @param commodity: Commodity name (supports short names like "petros")
-- @param callback: Optional callback for programmatic mode
function f2t_price_check_commodity(commodity, callback)
    -- Check prerequisites before sending game command
    if not f2t_check_rank_requirement("Merchant", "Price checking") then
        if callback then
            f2t_price_cancel_all()
            callback(commodity, nil, nil)
        end
        return
    end
    if not f2t_check_tool_requirement("remote-access-cert", "Price checking", "Remote Price Check Service") then
        if callback then
            f2t_price_cancel_all()
            callback(commodity, nil, nil)
        end
        return
    end

    -- Resolve short names to full names (canonical = properly cased)
    local canonical, was_short = f2t_resolve_commodity(commodity)
    if was_short then
        f2t_debug_log("[commodities] Resolved short name '%s' to '%s'", commodity, canonical)
    end

    f2t_debug_log(string.format("[commodities] Starting price check for: %s", canonical))

    -- Set up capture state
    F2T_PRICE_CAPTURE_ACTIVE = false  -- Will be set to true by start trigger
    F2T_PRICE_CAPTURE_DATA = {}
    F2T_PRICE_CURRENT_COMMODITY = canonical  -- Store canonical name for display
    F2T_PRICE_CALLBACK = callback

    -- Send the game command (lowercase for game)
    send(string.format("check price %s cartel", string.lower(canonical)), false)
end

-- Show price analysis for a single commodity
function f2t_price_show(commodity)
    f2t_price_check_commodity(commodity, nil)
end

f2t_debug_log("[commodities] Price control loaded")