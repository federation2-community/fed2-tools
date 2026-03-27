-- @patterns:
--   - pattern: ^(?i:tb|tell)\s+(\w+)\s+(.+)$

local speaker = gmcp.char.vitals.name

send(matches[1], false)

-- Route through ui_chat_add so the line is timestamped and persisted
-- Own tell — orange (#FF9040) to distinguish from received red (#FF5C5C)
local color = (UI.chat and UI.chat.colors and UI.chat.colors.self_tell) or "#FF9040"
ui_chat_add("self_tell", matches[2], matches[3], string.format("%s-> %s: \"%s\"\n", color, matches[2], matches[3]))