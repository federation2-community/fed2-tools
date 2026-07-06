-- chat_inbound — patterns declared in triggers.json
--
-- Routes inbound com/say/tell traffic into the chat history (f2tChatAdd), plus
-- the "hum" confirmation that commits a staged outgoing tell.  Game output is
-- never gagged here — the chat panel mirrors the console, it doesn't replace it.
-- Wrapped (multi-line) messages are completed by the chat_inbound module's
-- state machine (src/scripts/chat/chat_inbound.lua) — see
-- f2tChatInboundBeginContinuation.

-- "Hum" is the tb-send confirmation; commit the staged outgoing tell.
if line:match("^There is a brief hum from your comm unit") then
    local pt = F2T_CHAT and F2T_CHAT.pendingTell
    if pt then
        F2T_CHAT.pendingTell = nil
        f2tChatAdd("self_tell", pt.from, pt.msg)
    end
    return
end

-- Recipient isn't there; drop the staged tell.
if line:match(" doesn't seem to be around at the moment") then
    if F2T_CHAT then F2T_CHAT.pendingTell = nil end
    return
end

local mtype, name, msg

if line:match("^Your comm unit signals") then
    -- Inbound tight beam: 'Your comm unit signals a tight beam message from Name, "msg"'
    mtype = "tell_in"
    name  = matches[2]
    msg   = matches[3]
elseif line:match("^Your comm unit crackles") then
    -- Inbound com: 'Your comm unit crackles with a message from Name, "msg"'
    mtype = "com"
    name  = matches[2]
    msg   = matches[3]
else
    -- Inbound say: 'Name says, "msg"'
    mtype = "say"
    name  = matches[2]
    msg   = matches[4]
end

-- Fed2 wraps long lines before the closing quote — hand off to the
-- state-machine peek in chat_inbound.lua so continuations are captured
-- without desyncing across concurrent/interleaved messages.
if not msg:match('"$') then
    f2tChatInboundBeginContinuation(mtype, name, msg)
    return
end

-- Single-line message: strip the trailing quote captured by (.+)$
msg = msg:gsub('"$', '')

f2tChatAdd(mtype, name, msg)
