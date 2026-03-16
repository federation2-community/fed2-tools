-- @patterns:
--   - pattern: ^\+{3} Exchange has (.+) for sale \+{3}$
--     type: regex

--puts the amount available into exchange window
UI.exchange_window:cecho('<ansiYellow>Available: ' .. matches[2] ..'\n')
deleteLine()
tempLineTrigger(1,1, [[if getCurrentLine() == "" then deleteLine() end]]) --if the following line is blank, delete it