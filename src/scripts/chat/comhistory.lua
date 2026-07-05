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
    peekId  = nil,     -- tempLineTrigger id armed to catch a wrapped continuation line
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

local finish, killPeek, resetFinishTimer, matchHeader, armPeek, recordEntry

killPeek = function()
    if state.peekId then killTrigger(state.peekId); state.peekId = nil end
end

resetFinishTimer = function()
    if state.timerId then killTimer(state.timerId) end
    state.timerId = tempTimer(0.5, finish)
end

-- Matches a comhistory entry header line ("Name, X ago: text" / "Name, just
-- now: text"). Returns name, ago, text, or nil if the line isn't one.
matchHeader = function(l)
    local name, ago, text = l:match("^(%a+), (%d+ %a+ ago): (.+)$")
    if name then return name, ago, text end
    name, text = l:match("^(%a+), just now: (.+)$")
    if name then return name, "just now", text end
    return nil
end

finish = function()
    killPeek()
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

-- Records one entry (skipping our own messages — already in the live log) and
-- arms a peek for a possible wrapped continuation line.
recordEntry = function(name, ago, text)
    local entry = nil
    if not (F2T_CHAR_NAME and name:lower() == F2T_CHAR_NAME:lower()) then
        entry = { name = name, ago = ago, text = text }
        table.insert(state.buffer, entry)
    end
    armPeek(entry)
end

-- Fed2 wraps long comhistory lines the same way it wraps quoted chat messages
-- (chat_inbound.lua) — a continuation line repeats neither the sender name nor
-- the "X ago:" prefix, so comhistory_line's trigger pattern never matches it,
-- and it was previously left on screen, untouched and un-merged (the bug this
-- fixes). Peek the very next physical line with a temp line trigger, the same
-- technique chat_inbound.lua's captureContinuation uses (getCurrentLine(), not
-- the `line` global — temp line triggers don't populate that the same way a
-- pattern-matched trigger does): if it's a new entry's header, dispatch it as
-- one; otherwise fold it into the entry just captured and keep peeking.
-- `entry` is nil when the just-captured line was one of our own messages
-- (still consumed/hidden, just never buffered). killPeek() (called from
-- finish() and the disconnect handler) always tears this down so a still-armed
-- peek can never swallow an unrelated later line once capture is done.
armPeek = function(entry)
    killPeek()
    state.peekId = tempLineTrigger(1, 1, function()
        if not state.active then return end
        local l = getCurrentLine()
        local name, ago, text = matchHeader(l)
        if name then
            deleteLine()
            resetFinishTimer()
            recordEntry(name, ago, text)
            return
        end
        deleteLine()
        if entry then entry.text = entry.text .. " " .. l end
        resetFinishTimer()
        armPeek(entry)
    end)
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
    -- Once the first entry has armed a continuation peek (armPeek below), that
    -- peek becomes the sole handler for every line that follows — permanent and
    -- temp triggers both fire on the same incoming line, so acting here too
    -- would double-delete/double-record it. This trigger only ever needs to
    -- catch the very first entry line, which may already be batched with the
    -- header before a temp trigger could be armed (hence a permanent trigger
    -- for it, per the file-level comment).
    if state.peekId then return end

    local name, ago, text = matchHeader(line)   -- `line` is Mudlet's global for the trigger's current line
    if not name then return end

    deleteLine()

    -- Timer-based completion: any recognized line resets the window, and the
    -- timer ALWAYS finishes the capture when it expires (even on empty data).
    resetFinishTimer()

    -- Records the entry (skipping our own — already in the live log) and arms
    -- a peek for a possible wrapped continuation line (see armPeek above).
    recordEntry(name, ago, text)
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
    killPeek()
    state.sent, state.active, state.refTime = false, false, nil
    state.buffer, state.timerId = {}, nil
end)

f2t_debug_log("[chat] comhistory module loaded")
