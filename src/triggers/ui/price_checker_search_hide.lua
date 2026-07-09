-- price_checker_search_hide — patterns declared in triggers.json
--
-- Broker boilerplate around each `c price` burst ("Your comm unit lights up as
-- your brokers…", "requested spot market p…", "…is not currently trading in
-- this commodity"). Pure spam during a best-profit scan; gag it then.
if f2tPriceCheckerIsSearching and f2tPriceCheckerIsSearching() then
    deleteLine()
end
