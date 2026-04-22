-- @patterns:
--   - pattern: ^Your comm unit signals a tight beam message from (\w+), "(.+)"$
--     type: regex
--   - pattern: ^Your comm unit crackles with a message from (\w+), "(.+)"$
--     type: regex
--   - pattern: ^(\w+) (says|asks), "(.+)"$
--     type: regex
--   - pattern: ^You (?:say|ask), "(.+)"$
--     type: regex
--   - pattern: ^There is a brief hum from your comm unit\.$
--     type: regex
--   - pattern: ^\w+ doesn't seem to be around at the moment\.$
--     type: regex

local hide = f2t_settings_get("ui", "hide_chat_messages")

-- "Hum" is the tb-send confirmation; commit the staged outgoing tell to chat history.
if line:match("^There is a brief hum from your comm unit") then
    local pt = UI.chat.pending_tell
    if pt then
        UI.chat.pending_tell = nil
        ui_chat_add("self_tell", pt.from, pt.msg)
    end
    if hide then tempLineTrigger(0, 2, [[deleteLine()]]) end
    return
end

-- Your own say echo: alias already recorded it as self_com, just suppress.
if line:match("^You say,") or line:match("^You ask,") then
    if hide then tempLineTrigger(0, 2, [[deleteLine()]]) end
    return
end

-- Cancel pending tell because the recipient isnt there
if line:match(" doesn't seem to be around at the moment") then
    UI.chat.pending_tell = nil
    return
end

local mtype, name, msg

if line:match("^Your comm unit signals") then
    -- Inbound tight beam tell: "Your comm unit signals a tight beam message from Name, "msg""
    mtype = "tell_in"
    name  = matches[2]
    msg   = matches[3]
elseif line:match("^Your comm unit crackles") then
    -- Inbound com: "Your comm unit crackles with a message from Name, "msg""
    mtype = "com"
    name  = matches[2]
    msg   = matches[3]
else
    -- Inbound say: "Name says, "msg""
    mtype = "say"
    name  = matches[2]
    msg   = matches[4]
end

ui_chat_add(mtype, name, msg)

if hide then tempLineTrigger(0, 2, [[deleteLine()]]) end
