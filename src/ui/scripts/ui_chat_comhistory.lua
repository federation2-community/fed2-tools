-- =============================================================================
-- ui_chat_comhistory — auto-fetch comhistory on login and merge into chat log
--
-- Two permanent triggers drive capture:
--   comhistoryCapture → ui_chat_comhistory_begin()   (header line)
--   comhistoryLine    → ui_chat_comhistory_line()    (message lines)
--
-- A permanent trigger for message lines avoids the timing problem where
-- tempLineTrigger misses lines already batched in the server's response
-- when the command was issued from a timer callback.
-- =============================================================================

local _STATE = {
    -- "pending": we sent comhistory, begin() not yet called
    -- true:      capture done this session (prevents re-request)
    -- false:     no request sent yet
    sent     = false,
    active   = false,   -- true while collecting message lines
    ref_time = nil,
    buffer   = {},      -- list of {name, ago, text}
    current  = nil,     -- in-progress wrapped message
    timer_id = nil,
}

-- ── Time parsing ──────────────────────────────────────────────────────────

-- Returns (estimated_unix_t, tolerance_seconds).
-- "N hours ago" is in the range [N, N+1) hours old, so tolerance = one bucket,
-- making the dedup window span one bucket on each side.
local function _parse_time(ago_str, ref_time)
    if ago_str == "just now" then return ref_time, 60 end
    local n, unit = ago_str:match("^(%d+) (%a+) ago$")
    if not n then return ref_time, 60 end
    n = tonumber(n)
    if unit:match("^minute") then return ref_time - n * 60,   60   end
    if unit:match("^hour")   then return ref_time - n * 3600, 3600 end
    return ref_time, 60
end

-- ── Dedup ─────────────────────────────────────────────────────────────────

local function _is_duplicate(from, msg, t, tolerance)
    for _, r in ipairs(UI.chat.history) do
        if r.type == "com"
           and r.from == from
           and r.msg  == msg
           and math.abs(r.t - t) <= tolerance
        then
            return true
        end
    end
    return false
end

-- ── Merge into history (maintain chronological order) ─────────────────────

local function _merge(new_records)
    -- +1s nudge for same-second entries to preserve comhistory order
    table.sort(new_records, function(a, b) return a.t < b.t end)
    for i = 2, #new_records do
        if new_records[i].t <= new_records[i-1].t then
            new_records[i].t = new_records[i-1].t + 1
        end
    end
    local merged, hi, ni = {}, 1, 1
    local hist = UI.chat.history
    while hi <= #hist or ni <= #new_records do
        local ht = hist[hi]        and hist[hi].t        or math.huge
        local nt = new_records[ni] and new_records[ni].t or math.huge
        if ht <= nt then
            table.insert(merged, hist[hi]);        hi = hi + 1
        else
            table.insert(merged, new_records[ni]); ni = ni + 1
        end
    end
    UI.chat.history = merged
end

-- ── Finish & process ──────────────────────────────────────────────────────

local function _finish()
    if _STATE.current then
        table.insert(_STATE.buffer, _STATE.current)
        _STATE.current = nil
    end
    _STATE.active   = false
    _STATE.timer_id = nil

    local buffer = _STATE.buffer
    f2t_debug_log("[comhistory] processing %d raw entries", #buffer)

    local new_records = {}
    for _, entry in ipairs(buffer) do
        local t, tolerance = _parse_time(entry.ago, _STATE.ref_time)
        if not _is_duplicate(entry.name, entry.text, t, tolerance) then
            table.insert(new_records, {
                t    = t,
                type = "com",
                from = entry.name,
                msg  = entry.text,
            })
        end
    end

    if #new_records == 0 then
        f2t_debug_log("[comhistory] no new messages")
        return
    end

    _merge(new_records)
    ui_chat_save()
    ui_chat_replay()

    local s = #new_records == 1 and "" or "s"
    cecho(string.format("\n<dim_gray>[comhistory]<reset> %d missed message%s added to chat\n",
        #new_records, s))
    f2t_debug_log("[comhistory] added %d messages", #new_records)
end

-- ── Public: begin (called by comhistoryCapture trigger on header line) ─────

function ui_chat_comhistory_begin()
    if _STATE.sent ~= "pending" then return end  -- not our request; show output normally
    if _STATE.active then return end

    _STATE.sent     = true   -- consumed; no further captures this session
    _STATE.active   = true
    _STATE.ref_time = os.time()
    _STATE.buffer   = {}
    _STATE.current  = nil

    deleteLine()  -- hide "COM message history, cycle N:" header

    _STATE.timer_id = tempTimer(0.5, _finish)
    f2t_debug_log("[comhistory] capture started")
end

-- ── Public: line (called by comhistoryLine trigger on each message line) ───

function ui_chat_comhistory_line()
    if not _STATE.active then return end

    local l = line  -- Mudlet global set when the trigger fires
    local name, ago, text = l:match("^(%a+), (%d+ %a+ ago): (.+)$")
    if not name then
        name, text = l:match("^(%a+), just now: (.+)$")
        if name then ago = "just now" end
    end
    if not name then return end

    deleteLine()

    -- Always reset the completion timer for any recognized comhistory line
    if _STATE.timer_id then killTimer(_STATE.timer_id) end
    _STATE.timer_id = tempTimer(0.5, _finish)

    -- Skip own messages — they're already in the live log
    if F2T_CHAR_NAME and name:lower() == F2T_CHAR_NAME:lower() then return end

    if _STATE.current then table.insert(_STATE.buffer, _STATE.current) end
    _STATE.current = { name = name, ago = ago, text = text }
end

-- ── Public: login hook and session reset ──────────────────────────────────

function ui_chat_comhistory_on_login()
    if _STATE.sent then return end  -- already sent or captured this session
    _STATE.sent = "pending"
    tempTimer(2, function()
        send("comhistory", false)
        f2t_debug_log("[comhistory] auto-requested")
    end)
end

function ui_chat_comhistory_reset()
    if _STATE.timer_id then killTimer(_STATE.timer_id) end
    _STATE.sent     = false
    _STATE.active   = false
    _STATE.ref_time = nil
    _STATE.buffer   = {}
    _STATE.current  = nil
    _STATE.timer_id = nil
end
