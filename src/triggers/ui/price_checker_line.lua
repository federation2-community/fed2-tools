-- price_checker_line — patterns declared in triggers.json
--
-- One `c price`/`c premium` result row: "System: Planet is buying|selling N tons at Mig/ton".
-- Captured for the Price Checker panel (or the in-flight best-profit scan) and gagged,
-- but only when a panel is open — a bare cp with no panel shows normally.
-- The Exchange pane's commodity-name click sends a plain spot check that produces
-- this same line shape; skip capture then so it prints as on-screen confirmation
-- even if a Price Checker panel happens to be open.
if f2tExchangeSpotCheckActive and f2tExchangeSpotCheckActive() then
    -- let it print normally
elseif (f2tPriceCheckerHasOpenPanels and f2tPriceCheckerHasOpenPanels())
   or (f2tPriceCheckerIsSearching and f2tPriceCheckerIsSearching()) then
    f2tPriceCheckerLine(matches[2], matches[3], matches[4], matches[5], matches[6])
    deleteLine()
end
