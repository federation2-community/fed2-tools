-- trading_line — patterns declared in triggers.json
--
-- One `c price` result row: "System: Planet is buying|selling N tons at Mig/ton".
-- Captured for the Trading panel (or the in-flight best-profit scan) and gagged,
-- but only when a trading panel is open — a bare cp with no panel shows normally.
if (f2tTradingHasOpenPanels and f2tTradingHasOpenPanels())
   or (f2tTradingIsSearching and f2tTradingIsSearching()) then
    f2tTradingLine(matches[2], matches[3], matches[4], matches[5], matches[6])
    deleteLine()
end
