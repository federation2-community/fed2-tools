-- fed2-tools chat — comhistory backfill
--
-- Auto-fetches the game's `comhistory` output once per session shortly after
-- login and merges any missed com messages into F2T_CHAT.history, deduplicating
-- against records already present (the game reports ages in whole-unit buckets,
-- so the dedup window spans one bucket on each side).
--
-- Two permanent triggers drive capture (src/triggers/chat/):
--   comhistory_capture → f2tChatComhistoryBegin()   (header line)
--   comhistory_line    → f2tChatComhistoryLine()    (message lines)
--
-- Permanent triggers (rather than tempLineTrigger) avoid missing lines already
-- batched in the server's response when the request was sent from a timer.
--
-- Ported from archive's ui_chat_comhistory.lua.

local state = {
    -- sent: false = not requested yet; "pending" = requested, header not seen;
    --       true  = capture consumed this session (prevents re-capture)
    sent    = false,
    active  = false,   -- true while collecting message lines
    refTime = nil,
    buffer  = {},      -- list of {name, ago, text}
    timerId = nil,
}

-- Returns (estimatedUnixTime, toleranceSeconds).  "N hours ago" means the
-- message is in the range [N, N+1) hours old, so tolerance = one bucket.
local function parseTime(agoStr, refTime)
    if agoStr == "just now" then return refTime, 60 end
    local n, unit = agoStr:match("^(%d+) (%a+) ago$")
    if not n then return refTime, 60 end
    n = tonumber(n)
    if unit:match("^minute") then return refTime - n * 60,   60   end
    if unit:match("^hour")   then return refTime - n * 3600, 3600 end
    return refTime, 60
end

local function isDuplicate(from, msg, t, tolerance)
    for _, r in ipairs(F2T_CHAT.history) do
        if r.type == "com" and r.from == from and r.msg == msg
           and math.abs(r.t - t) <= tolerance then
            return true
        end
    end
    return false
end

-- Merge new records into history preserving chronological order.  Same-second
-- entries get a +1s nudge so comhistory's own ordering survives the sort.
local function merge(newRecords)
    table.sort(newRecords, function(a, b) return a.t < b.t end)
    for i = 2, #newRecords do
        if newRecords[i].t <= newRecords[i-1].t then
            newRecords[i].t = newRecords[i-1].t + 1
        end
    end
    local merged, hi, ni = {}, 1, 1
    local hist = F2T_CHAT.history
    while hi <= #hist or ni <= #newRecords do
        local ht = hist[hi]       and hist[hi].t       or math.huge
        local nt = newRecords[ni] and newRecords[ni].t or math.huge
        if ht <= nt then
            table.insert(merged, hist[hi]);       hi = hi + 1
        else
            table.insert(merged, newRecords[ni]); ni = ni + 1
        end
    end
    F2T_CHAT.history = merged
end

local function finish()
    state.active  = false
    state.timerId = nil

    local buffer = state.buffer
    state.buffer = {}
    f2t_debug_log("[comhistory] processing %d raw entries", #buffer)

    local newRecords = {}
    for _, entry in ipairs(buffer) do
        local t, tolerance = parseTime(entry.ago, state.refTime)
        if not isDuplicate(entry.name, entry.text, t, tolerance) then
            table.insert(newRecords, { t = t, type = "com", from = entry.name, msg = entry.text })
        end
    end

    if #newRecords == 0 then
        f2t_debug_log("[comhistory] no new messages")
        return
    end

    merge(newRecords)
    f2tChatSave()
    raiseEvent("f2tChatUpdated", "replay")

    local s = #newRecords == 1 and "" or "s"
    cecho(string.format("\n<dim_gray>[comhistory]<reset> %d missed message%s added to chat\n",
        #newRecords, s))
end

-- ── Trigger entry points ──────────────────────────────────────────────────────

-- Header line ("COM message history…" or "No COM messages have been sent
-- yet…").  Only consumes output we requested — a manual comhistory shows
-- normally.
function f2tChatComhistoryBegin()
    if state.sent ~= "pending" then return end
    if state.active then return end

    deleteLine()   -- hide the header/no-history line of our automated request

    if line:match("^No COM messages") then
        state.sent = true
        f2t_debug_log("[comhistory] no history to fetch")
        return
    end

    state.sent    = true
    state.active  = true
    state.refTime = os.time()
    state.buffer  = {}

    state.timerId = tempTimer(0.5, finish)
    f2t_debug_log("[comhistory] capture started")
end

function f2tChatComhistoryLine()
    if not state.active then return end

    local l = line   -- Mudlet global for the trigger's current line
    local name, ago, text = l:match("^(%a+), (%d+ %a+ ago): (.+)$")
    if not name then
        name, text = l:match("^(%a+), just now: (.+)$")
        if name then ago = "just now" end
    end
    if not name then return end

    deleteLine()

    -- Timer-based completion: any recognized line resets the window, and the
    -- timer ALWAYS finishes the capture when it expires (even on empty data).
    if state.timerId then killTimer(state.timerId) end
    state.timerId = tempTimer(0.5, finish)

    -- Skip our own messages — they're already in the live log.
    if F2T_CHAR_NAME and name:lower() == F2T_CHAR_NAME:lower() then return end

    table.insert(state.buffer, { name = name, ago = ago, text = text })
end

-- ── Session wiring ────────────────────────────────────────────────────────────

local function requestOnLogin()
    if state.sent then return end
    if f2t_settings_get("chat", "fetch_history") == false then return end
    state.sent = "pending"
    tempTimer(2, function()
        send("comhistory", false)
        f2t_debug_log("[comhistory] auto-requested")
    end)
end

-- gmcp.char.vitals fires repeatedly; the sent-flag makes this once per session.
-- The 2s delay keeps the request clear of the login sequence output.
registerAnonymousEventHandler("gmcp.char.vitals", function()
    local name = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if not name or name == "" then return end
    requestOnLogin()
end)

registerAnonymousEventHandler("sysConnectionEvent", function()
    local _, _, connected = getConnectionInfo()
    if connected then return end
    -- Reset on disconnect so the next login fetches again.
    if state.timerId then killTimer(state.timerId) end
    state.sent, state.active, state.refTime = false, false, nil
    state.buffer, state.timerId = {}, nil
end)

f2t_debug_log("[chat] comhistory module loaded")
