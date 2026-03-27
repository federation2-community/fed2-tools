-- @patterns:
--   - pattern: ^(?:(?i:(com|comm|say))\s+(.*)|(''|'|")\s*(.*))$

local display
local text = ""

if matches[2] ~= "" then
    text = matches[3] or ""
else
    text = matches[5] or ""
end

local speaker = gmcp.char.vitals.name

send(matches[1], false)

-- Route through ui_chat_add so the line is timestamped and persisted
-- Own com/say — green (#70c890) to distinguish from received teal (#4fa3a3)
local color = (UI.chat and UI.chat.colors and UI.chat.colors.self_com) or "#70c890"
ui_chat_add("self_com", speaker, text, string.format("%s%s: \"%s\"\n", color, speaker, text))