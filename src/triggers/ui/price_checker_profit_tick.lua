-- price_checker_profit_tick — patterns declared in triggers.json
--
-- Blank line marking the end of one commodity's `c price` burst during a
-- best-profit scan: score the captured rows and advance to the next commodity.
if f2tPriceCheckerIsSearching and f2tPriceCheckerIsSearching() then
    if f2tPriceCheckerProfitTick() then
        deleteLine()
    end
end
