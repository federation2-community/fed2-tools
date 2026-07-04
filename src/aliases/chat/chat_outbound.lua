-- chat_outbound — pattern declared in aliases.json
--
-- Mirrors the player's own com/say/tell traffic into the chat history.  The
-- command always passes through to the game unchanged; this only records it.
--
-- Tells are staged rather than recorded: the game confirms delivery with
-- "There is a brief hum from your comm unit." (committed by the chat_inbound
-- trigger) and rejects with "X doesn't seem to be around" (dropped).

local speaker = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name or "You"

send(matches[1], false)

if matches[2] and matches[2] ~= "" then
    -- tb/tell: matches[2]=recipient, matches[3]=message.
    -- Capitalize to match player-DB keys (Lua table keys are case-sensitive).
    local recipient = matches[2]:sub(1, 1):upper() .. matches[2]:sub(2)
    F2T_CHAT.pendingTell = { from = recipient, msg = matches[3] or "" }
else
    local cmd  = matches[1]:lower():match("^%S+")
    local text = (matches[4] and matches[4] ~= "" and matches[4]) or (matches[6] or "")
    -- Quote shortcut (' or ") is say; com/comm are com.
    if cmd == "say" or (matches[5] and matches[5] ~= "") then
        f2tChatAdd("self_say", speaker, text)
    else
        f2tChatAdd("self_com", speaker, text)
    end
end
