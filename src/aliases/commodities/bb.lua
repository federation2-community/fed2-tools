-- bb — regex declared in aliases.json
-- Bulk buy commodity alias
local args = matches[2]

-- No arguments - show help (no default behavior)
if not args or args == "" then
    f2t_show_registered_help("bb")
    return
end

-- Check for help request
if f2t_handle_help("bb", args) then
    return
end

-- Parse commodity and optional count
local commodity, count_str = args:match("^(%S+)%s*(%d*)$")
local count = count_str ~= "" and tonumber(count_str) or nil

f2t_bulk_buy_start(commodity, count)