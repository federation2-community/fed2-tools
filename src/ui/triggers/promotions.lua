-- @patterns:
--   - pattern:  has promoted to
--     type: substring

UI.general_window:cecho(matches[1])
tempLineTrigger(0, 2, [[deleteLine()]]) --delete the current line and the next line, to catch the newline after every SPYNET REPORT