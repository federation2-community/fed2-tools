-- fed2-tools — string utilities (ported from shared/scripts/f2t_string_utils.lua)

function f2t_strip_color_codes(str)
    if not str then return "" end
    return string.gsub(str, "%%%%[^%%]+%%%%", "")
end

function f2t_clean_room_name(name)
    if not name then return "" end
    local cleaned = f2t_strip_color_codes(name)
    cleaned = string.match(cleaned, "^%s*(.-)%s*$")
    return cleaned
end

local function _dlen(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

function f2t_padding(str, len, dir)
    str = tostring(str)
    local dlen = _dlen(str)

    if dlen > len then
        local n, i = 0, 1
        while i <= #str and n < len do
            local b = str:byte(i)
            if b < 0x80 or b >= 0xC0 then n = n + 1 end
            i = i + 1
        end
        return str:sub(1, i - 1)
    end

    local pad = len - dlen
    if dir == "left" then
        return str .. string.rep(" ", pad)
    elseif dir == "right" then
        return string.rep(" ", pad) .. str
    elseif dir == "center" then
        local left  = math.floor(pad / 2)
        local right = pad - left
        return string.rep(" ", left) .. str .. string.rep(" ", right)
    end
end
