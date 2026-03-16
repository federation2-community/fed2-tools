-- @patterns:
--   - pattern: ^\+{3} Exchange will buy (\d+) tons at (\d+)(.+) \+{3}
--     type: regex

--puts the buying price (matches[3]) into exchange window
--matches[4] contains the 'ig/ton' that usually follows a buying price
--matches[2] is the amount they're willing to purchase, but this should always be 75 tons?
--maybe do some multiplication to get actual price for a 75 ton container?
UI.exchange_window:cecho('<ansiYellow>Buying at: ' .. matches[3] ..'\n')
deleteLine()
tempLineTrigger(1,1, [[if getCurrentLine() == "" then deleteLine() end]]) --if the following line is blank, delete it