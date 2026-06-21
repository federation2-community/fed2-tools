-- commodities_buy_error_insufficient_funds — patterns declared in triggers.json
-- Handle insufficient funds during bulk buy
if not F2T_BULK_STATE.active or F2T_BULK_STATE.command ~= "buy" then
    return
end

local bought = F2T_BULK_STATE.total - F2T_BULK_STATE.remaining

if bought == 0 then
    -- Haven't bought anything yet, this is an error
    f2t_debug_log("[bulk-buy] ERROR: Insufficient funds (no lots purchased)")
    f2t_bulk_buy_error("Insufficient funds - cannot afford even one lot")
else
    -- We've already bought some, just stop gracefully
    f2t_debug_log("[bulk-buy] Insufficient funds after buying %d lots, stopping gracefully", bought)

    -- Only show message in user mode
    if not F2T_BULK_STATE.callback then
        cecho("\n<yellow>[bulk-buy]<reset> Insufficient funds for more cargo\n")
    end

    f2t_bulk_buy_finish()
end