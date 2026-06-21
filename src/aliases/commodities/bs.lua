-- bs — regex declared in aliases.json
-- Bulk sell commodity alias
local args = matches[2]

-- No arguments - default behavior (sell all cargo)
if not args or args == "" then
    f2t_bulk_sell_start(nil, nil)
    return
end

-- Check for help request
if f2t_handle_help("bs", args) then
    return
end

-- Parse commodity and optional count
local commodity, count_str = args:match("^(%S+)%s*(%d*)$")
local count = count_str ~= "" and tonumber(count_str) or nil

f2t_bulk_sell_start(commodity, count)