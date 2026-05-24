-- String utility functions

-- Strip ANSI/MUD color codes from a string
-- Handles formats like: %%bold%%, %%green%%, %%reset%%, etc.
function f2t_strip_color_codes(str)
    if not str then
        return ""
    end

    -- Remove all %%code%% patterns
    local cleaned = string.gsub(str, "%%%%[^%%]+%%%%", "")

    return cleaned
end

-- Clean a room name for display/storage
-- Removes color codes and trims whitespace
function f2t_clean_room_name(name)
    if not name then
        return ""
    end

    -- Strip color codes
    local cleaned = f2t_strip_color_codes(name)

    -- Trim leading/trailing whitespace
    cleaned = string.match(cleaned, "^%s*(.-)%s*$")

    return cleaned
end

-- Count display characters in a UTF-8 string.
-- Continuation bytes (0x80-0xBF) are not character starts, so we skip them.
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
        -- Truncate to `len` display characters without splitting a multi-byte sequence.
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