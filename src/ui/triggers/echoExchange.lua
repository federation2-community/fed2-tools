-- @patterns:
--   - pattern: ^\+{3} The exchange display shows the prices for (.+) \+{3}$
--     type: regex
--   - pattern: ^\+{3} The display shows the prices for (.+) \+{3}$
--     type: regex

--puts the Commodity name into the exchange window
local commodities = ui_commodities_load()
local base_price  = "???"

for _, commodity in ipairs(commodities) do
    if commodity.name == matches[2] then base_price = commodity.basePrice end
end

UI.exchange_window:echo("+++\n")
UI.exchange_window:cecho('<ansiYellow>' .. matches[2] .. ' (base ' .. base_price ..'):\n')
deleteLine()
tempLineTrigger(1,1, [[if getCurrentLine() == "" then deleteLine() end]]) --if the following line is blank, delete it