-- fed2-tools — table utilities (ported from shared/scripts/f2t_table_utils.lua)

function f2t_has_value(tab, val)
    for _, value in ipairs(tab) do
        if value == val then return true end
    end
    return false
end

function f2t_table_get_sorted_keys(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys)
    return keys
end

function f2t_table_count_keys(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end
