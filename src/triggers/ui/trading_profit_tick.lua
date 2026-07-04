-- trading_profit_tick — patterns declared in triggers.json
--
-- Blank line marking the end of one commodity's `c price` burst during a
-- best-profit scan: score the captured rows and advance to the next commodity.
if f2tTradingIsSearching and f2tTradingIsSearching() then
    if f2tTradingProfitTick() then
        deleteLine()
    end
end
