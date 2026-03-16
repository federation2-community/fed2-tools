-- @patterns:
--   - pattern: ^\+{3} Offer price is (\d+)(.+) for first (\d+) tons \+{3}$
--     type: regex

--puts the selling price (matches[2]) into exchange window
--matches[3] is the ig/ton that usually follows the price
--matches[4] is the amount they're willing to sell, but this should always be 75 tons?
UI.exchange_window:cecho('<ansiYellow>Selling at: ' .. matches[2] ..'\n')
deleteLine()
tempLineTrigger(1,1, [[if getCurrentLine() == "" then deleteLine() end]]) --if the following line is blank, delete it