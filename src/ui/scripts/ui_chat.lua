-- =============================================================================
-- ui_chat_core  —  persistent chat history + timestamp toggle
-- Mudlet Script location: ui > ui_chat_core
-- =============================================================================

UI      = UI or {}
UI.chat = UI.chat or {
    history         = {},
    show_timestamps = false,
    loaded          = false,
}

local _MAX_DAYS = 7
local _MAX_MSGS = 2000

-- Message type colors (hecho #RRGGBB format)
local COLOR_COM       = "#4fa3a3"   -- teal:     com/say from others
local COLOR_TELL_IN   = "#FF5C5C"   -- red:      tell received
local COLOR_SELF_COM  = "#70c890"   -- green:    own com/say
local COLOR_SELF_TELL = "#FF9040"   -- orange:   own tell sent
local COLOR_CONNECT   = "#4a9a4a"   -- green:    connected marker
local COLOR_DISCONN   = "#9a4a4a"   -- dark red: disconnected marker
local COLOR_SEP       = "#3c3c3c"   -- dim:      separator chrome
local COLOR_DATE      = "#2a4a5a"   -- dim blue: date group header

-- Export so handlers and aliases can reference them without hardcoding
UI.chat.colors = {
    com       = COLOR_COM,
    tell_in   = COLOR_TELL_IN,
    self_com  = COLOR_SELF_COM,
    self_tell = COLOR_SELF_TELL,
}

-- File paths
local function _chat_dir()  return getMudletHomeDir() .. "/fed2-tools/chat" end
local function _chat_path() return _chat_dir() .. "/history" end
local function _ensure_dir()
    lfs.mkdir(getMudletHomeDir() .. "/fed2-tools")
    lfs.mkdir(_chat_dir())
end

-- ── Persistence ───────────────────────────────────────────────────────────

function ui_chat_save()
    _ensure_dir()
    local cutoff = os.time() - (_MAX_DAYS * 86400)
    local kept   = {}
    for _, r in ipairs(UI.chat.history) do
        if r.t and r.t >= cutoff then table.insert(kept, r) end
    end
    while #kept > _MAX_MSGS do table.remove(kept, 1) end
    UI.chat.history = kept
    local ok, err = pcall(table.save, _chat_path(), UI.chat.history)
    if not ok then f2t_debug_log("[chat] save error: %s", tostring(err)) end
end

function ui_chat_load()
    local buf = {}
    local ok  = pcall(table.load, _chat_path(), buf)
    if ok and type(buf) == "table" then
        local cutoff = os.time() - (_MAX_DAYS * 86400)
        for _, r in ipairs(buf) do
            if r.t and r.t >= cutoff then
                table.insert(UI.chat.history, r)
            end
        end
    end
    UI.chat.loaded = true
    f2t_debug_log("[chat] loaded %d messages from disk", #UI.chat.history)
end

-- ── Rendering ─────────────────────────────────────────────────────────────

local function _fmt_ts(t) return os.date("%H:%M", t) end

local function _echo_record(r)
    if not UI.chat_window then return end
    local line = r.line
    if UI.chat.show_timestamps and r.type ~= "status" and r.t then
        line = COLOR_SEP .. "[" .. _fmt_ts(r.t) .. "] " .. line
    end
    UI.chat_window:hecho(line)
end

-- Replay the full history into the chat window.
-- "Chat History" / date headers / "Live" chrome lines are ONLY emitted
-- when timestamp mode is active.  When off, the window shows undecorated
-- scrollback with no visual clutter.
function ui_chat_replay()
    if not UI.chat_window then return end
    UI.chat_window:clear()
    if #UI.chat.history == 0 then return end

    local show_ts = UI.chat.show_timestamps

    if show_ts then
        UI.chat_window:hecho(COLOR_SEP .. "─── Chat History ──────────────────────────\n")
    end

    local last_day = ""
    for _, r in ipairs(UI.chat.history) do
        if show_ts and r.t and r.type ~= "status" then
            local day = os.date("%Y-%m-%d", r.t)
            if day ~= last_day then
                UI.chat_window:hecho(
                    COLOR_DATE .. "── " .. os.date("%A, %b %d", r.t) .. " ──\n")
                last_day = day
            end
        end
        _echo_record(r)
    end

    if show_ts then
        UI.chat_window:hecho(COLOR_SEP .. "─── Live ─────────────────────────────────\n")
    end
end

-- ── Timestamp toggle ──────────────────────────────────────────────────────

function ui_chat_toggle_timestamps()
    UI.chat.show_timestamps = not UI.chat.show_timestamps
    if UI.chat_ts_btn then
        if UI.chat.show_timestamps then
            UI.chat_ts_btn:echo("<center><font color='#78c8c8'>⏱</font></center>")
            UI.chat_ts_btn:setToolTip("Timestamps ON — click to hide")
        else
            UI.chat_ts_btn:echo("<center><font color='#3d3d3d'>⏱</font></center>")
            UI.chat_ts_btn:setToolTip("Timestamps OFF — click to show")
        end
    end
    ui_chat_replay()
end

-- ── Public write API ──────────────────────────────────────────────────────

-- mtype    : "com" | "tell_in" | "say" | "self_com" | "self_tell" | "status"
-- hecho_line: full display string in hecho #RRGGBB format, ending with \n
function ui_chat_add(mtype, from, message, hecho_line)
    local r = { t = os.time(), type = mtype, from = from, msg = message, line = hecho_line }
    table.insert(UI.chat.history, r)
    _echo_record(r)
    ui_chat_save()
end

-- ── Connection status markers ─────────────────────────────────────────────

function ui_chat_on_connect()
    local ts = os.date("%H:%M")
    ui_chat_add("status", "", "Connected",
        string.format(COLOR_CONNECT .. "── Connected %s ─────────────────────────\n", ts))
end

function ui_chat_on_disconnect()
    local ts = os.date("%H:%M")
    ui_chat_add("status", "", "Disconnected",
        string.format(COLOR_DISCONN .. "── Disconnected %s ──────────────────────\n", ts))
end

-- ── Init ──────────────────────────────────────────────────────────────────

function ui_chat_init()
    if not UI.chat.loaded then ui_chat_load() end
    ui_chat_replay()
    f2t_debug_log("[chat] init complete")
end

function ui_echo_com()
    local from = gmcp.comm.com.from
    local msg  = gmcp.comm.com.message
    -- Use the color constant from ui_chat_core so it stays in sync
    local color = (UI.chat and UI.chat.colors and UI.chat.colors.com) or "#4fa3a3"
    ui_chat_add("com", from, msg,
        string.format("%s%s: \"%s\"\n", color, from, msg))
end
 
function ui_echo_tell()
    local from = gmcp.comm.tell.from
    local msg  = gmcp.comm.tell.message
    local color = (UI.chat and UI.chat.colors and UI.chat.colors.tell_in) or "#FF5C5C"
    ui_chat_add("tell_in", from, msg,
        string.format("%s%s tells you: \"%s\"\n", color, from, msg))
end
 
function ui_echo_say()
    local from = gmcp.comm.say.from
    local msg  = gmcp.comm.say.message
    local color = (UI.chat and UI.chat.colors and UI.chat.colors.com) or "#4fa3a3"
    ui_chat_add("say", from, msg,
        string.format("%s%s says: \"%s\"\n", color, from, msg))
end