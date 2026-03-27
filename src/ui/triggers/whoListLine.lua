-- @patterns:
--   - pattern: ^(  [A-Z]|\[[A-Z])
--     type: regex

if UI.who.parsing then
  ui_who_line()
  deleteLine()
end