-- chat.lua — Chat panel content for fed2-tools.
--
-- Renders F2T_CHAT.history (scripts/chat/history.lua) into a MiniConsole with
-- grouped speakers, per-type colors, an A/C/T/S filter cycle, and a timestamp
-- toggle.  Live messages append via the f2tChatUpdated event; filter or
-- timestamp changes replay the whole log.
--
-- This module ONLY registers content.  To get the archive's always-visible
-- chat tab, place "fed2_chat" in any pane or tab; visibility/layout is
-- Muxlet's job.  Filter and timestamp state serialize with the workspace.
--
-- Ported from archive's ui_chat.lua (rendering half) + chatInbound wiring.

local H_BAR = 24    -- control strip height (px)

-- ── Style per message type ────────────────────────────────────────────────────
-- gutterHex: hecho #RRGGBB for the continuation pipe / direction arrows
-- textHex:   hecho #RRGGBB for the message body

local STYLE = {
    com       = { gutterHex = "#2a7070", textHex = "#008080" },
    say       = { gutterHex = "#008000", textHex = "#008000" },
    tell_in   = { gutterHex = "#882222", textHex = "#882222" },
    self_com  = { gutterHex = "#226622", textHex = "#00ffff" },
    self_say  = { gutterHex = "#4caf70", textHex = "#4caf70" },
    self_tell = { gutterHex = "#ff8888", textHex = "#ff8888" },
}

-- Rank → cecho color name for speaker names (mirrors who.lua's palette).
local RANK_CECHO = {
    ["Trader"]        = "mint_cream",
    ["Merchant"]      = "mint_cream",
    ["Engineer"]      = "ansiCyan",
    ["Mogul"]         = "ansiCyan",
    ["Magnate"]       = "ansiCyan",
    ["Technocrat"]    = "ansiCyan",
    ["Gengineer"]     = "ansiCyan",
    ["Founder"]       = "ansiCyan",
    ["Manufacturer"]  = "ansiGreen",
    ["Industrialist"] = "ansiGreen",
    ["Financier"]     = "ansiGreen",
    ["Plutocrat"]     = "ansiRed",
    ["Syndicrat"]     = "dark_khaki",
    ["Commander"]     = "dark_violet",
    ["Groundhog"]     = "dark_violet",
}

local FILTERS = {
    {
        id = "all", label = "A", matches = nil, tip = "Show all messages",
        css = [[QLabel{
            background-color:rgba(28,28,32,200); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(100,100,110,180);
            color:rgba(160,160,170,255); font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(60,60,70,220); color:white; }]],
    },
    {
        id = "com", label = "C", matches = { com = true, self_com = true }, tip = "Com channel only",
        css = [[QLabel{
            background-color:rgba(15,50,50,220); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(50,120,120,200);
            color:rgba(60,170,170,255); font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(25,75,75,240); color:white; }]],
    },
    {
        id = "tell", label = "T", matches = { tell_in = true, self_tell = true }, tip = "Tells only",
        css = [[QLabel{
            background-color:rgba(52,18,18,220); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(140,50,50,200);
            color:rgba(210,80,80,255); font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(75,25,25,240); color:white; }]],
    },
    {
        id = "say", label = "S", matches = { say = true, self_say = true }, tip = "Say only",
        css = [[QLabel{
            background-color:rgba(18,30,52,220); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(50,90,150,200);
            color:rgba(70,130,210,255); font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(25,45,75,240); color:white; }]],
    },
}

-- Per-pane state, keyed by target._gid
local instances = {}

-- ── Name coloring ─────────────────────────────────────────────────────────────

local function rankCecho(name)
    if f2t_player_db_get then
        local entry = f2t_player_db_get(name)
        if entry and entry.rank and RANK_CECHO[entry.rank] then
            return "<" .. RANK_CECHO[entry.rank] .. ">", entry.rank
        end
    end
    return "<dim_gray>", nil
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

-- Render one record into an instance's console.
--   isCont = true: same speaker+type as previous message — colored pipe only.
-- hecho carries #hex prefixes; cecho carries <colorname> tags. Never mixed in
-- one call.
local function renderRecord(inst, r, isCont)
    local mc = inst.console
    if not mc then return end

    -- Cycle markers always render (structural game-day dividers from old saves)
    if r.type == "cycle" then
        mc:hecho(r.line or "")
        return
    end

    -- Status lines only render when timestamps are on
    if r.type == "status" then
        if inst.showTs then mc:hecho(r.line or "") end
        return
    end

    local filter = FILTERS[inst.filterIdx]
    if filter.matches and not filter.matches[r.type] then return end

    local st = STYLE[r.type] or STYLE.com

    if inst.showTs and r.t then
        mc:hecho("#404040[" .. os.date("%H:%M", r.t) .. "] ")
    end

    if isCont then
        mc:hecho(st.gutterHex .. "▎  ")
        mc:hecho(st.textHex .. r.msg .. "\n")
        return
    end

    local nc, rank = rankCecho(r.from)
    local hint     = rank and (rank .. " " .. r.from) or r.from
    local from     = r.from

    if r.type == "self_tell" then
        mc:hecho(st.gutterHex .. "❯❯ ")
    elseif r.type == "tell_in" then
        mc:hecho(st.gutterHex .. "❮❮ ")
    end

    mc:cechoLink(
        nc .. "<b>" .. from .. "</b><reset>",
        function()
            if f2tPlayerCardShowOrRaiseByName then f2tPlayerCardShowOrRaiseByName(from) end
        end,
        hint, true)
    mc:cecho(" <dim_gray>»<reset> ")
    mc:hecho(st.textHex .. r.msg .. "\n")
end

local function replay(inst)
    local mc = inst.console
    if not mc then return end
    mc:clear()
    inst.lastKey = nil
    if #F2T_CHAT.history == 0 then return end

    local filtered = (FILTERS[inst.filterIdx].matches ~= nil)

    if inst.showTs then
        mc:hecho("#303030─── Chat History ──────────────────────────\n")
    end

    local lastDay = ""
    local prev    = nil

    for _, r in ipairs(F2T_CHAT.history) do
        if inst.showTs and r.t and r.type ~= "status" then
            local day = os.date("%Y-%m-%d", r.t)
            if day ~= lastDay then
                mc:hecho("#1a3040── " .. os.date("%A, %b %d", r.t) .. " ──\n")
                lastDay = day
            end
        end

        local isCont = (not filtered)
            and prev
            and r.type ~= "status" and prev.type ~= "status"
            and r.type ~= "cycle"  and prev.type ~= "cycle"
            and prev.from == r.from and prev.type == r.type

        renderRecord(inst, r, isCont)
        if r.type ~= "status" and r.type ~= "cycle" then prev = r end
    end

    if inst.showTs then
        mc:hecho("#303030─── Live ─────────────────────────────────\n")
    end

    inst.lastKey = prev and (prev.from .. prev.type) or nil
end

-- Append the newest history record to one instance, tracking speaker grouping.
local function appendLatest(inst)
    local r = F2T_CHAT.history[#F2T_CHAT.history]
    if not r then return end

    local isCont = false
    if r.type == "status" or r.type == "cycle" then
        inst.lastKey = nil
    else
        local key = r.from .. r.type
        if not FILTERS[inst.filterIdx].matches then
            isCont = (inst.lastKey == key)
        end
        inst.lastKey = key
    end
    renderRecord(inst, r, isCont)
end

-- ── Control strip ─────────────────────────────────────────────────────────────

local function updateTsButton(inst)
    if not inst.tsBtn then return end
    if inst.showTs then
        inst.tsBtn:echo("<center><font color='#78c8c8'>⏱</font></center>")
        inst.tsBtn:setToolTip("Timestamps ON — click to hide")
    else
        inst.tsBtn:echo("<center><font color='#3a3a3a'>⏱</font></center>")
        inst.tsBtn:setToolTip("Timestamps OFF — click to show")
    end
end

local function updateFilterButton(inst)
    if not inst.filterBtn then return end
    local f = FILTERS[inst.filterIdx]
    inst.filterBtn:setStyleSheet(f.css)
    inst.filterBtn:echo("<center>" .. f.label .. "</center>")
    inst.filterBtn:setToolTip(f.tip)
end

-- ── Content build ─────────────────────────────────────────────────────────────

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    if instances[gid] then
        replay(instances[gid])
        return
    end

    local bar = Geyser.Label:new({
        name = gid .. "_chatbar", x = 0, y = 0, width = "100%", height = H_BAR,
    }, target.content)
    bar:setStyleSheet([[
        background-color: rgba(15, 18, 30, 200);
        border: none;
        border-bottom: 1px solid rgba(70, 75, 110, 150);
    ]])

    local title = Geyser.Label:new({
        name = gid .. "_chattitle", x = 6, y = 0, width = "-60", height = H_BAR,
    }, bar)
    title:setStyleSheet([[
        background: transparent; border: none;
        color: rgba(140, 150, 195, 255);
        font-size: 10px; font-family: "Consolas","Monaco",monospace;
    ]])
    title:echo("💬  Chat")

    local filterBtn = Geyser.Label:new({
        name = gid .. "_chatfilter", x = "-52", y = 3, width = 22, height = H_BAR - 6,
    }, bar)

    local tsBtn = Geyser.Label:new({
        name = gid .. "_chatts", x = "-26", y = 3, width = 22, height = H_BAR - 6,
    }, bar)
    tsBtn:setStyleSheet([[
        QLabel{
            background-color:rgba(28,28,32,200); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(100,100,110,180);
            font-size:11px;
        } QLabel::hover{ background-color:rgba(60,60,70,220); }
    ]])

    local mc = Geyser.MiniConsole:new({
        name = gid .. "_chatmc", x = 0, y = H_BAR,
        width = "100%", height = "100%-" .. H_BAR .. "px",
        fontSize = 9,
    }, target.content)
    mc:setColor(18, 18, 26)
    mc:enableAutoWrap()

    local inst = {
        console   = mc,
        bar       = bar,
        tsBtn     = tsBtn,
        filterBtn = filterBtn,
        showTs    = f2t_settings_get("chat", "show_timestamps") or false,
        filterIdx = 1,
        lastKey   = nil,
    }
    instances[gid] = inst

    tsBtn:setClickCallback(function()
        inst.showTs = not inst.showTs
        f2t_settings_set("chat", "show_timestamps", inst.showTs)
        updateTsButton(inst)
        replay(inst)
    end)

    filterBtn:setClickCallback(function()
        inst.filterIdx = (inst.filterIdx % #FILTERS) + 1
        updateFilterButton(inst)
        replay(inst)
    end)

    updateTsButton(inst)
    updateFilterButton(inst)
    replay(inst)
end

-- ── Content registration ──────────────────────────────────────────────────────

local function buildChatDef()
    return {
        name        = "Chat",
        description = "Com/say/tell history with speaker grouping, filters, and timestamps.",
        group       = "Fed2 Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[chat] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            instances[target._gid] = nil
        end,
        serialize = function(target)
            local inst = instances[target._gid]
            if not inst then return {} end
            return { showTs = inst.showTs, filterIdx = inst.filterIdx }
        end,
        restore = function(target, data)
            local inst = instances[target._gid]
            if not inst then return end
            if type(data.showTs) == "boolean" then inst.showTs = data.showTs end
            if type(data.filterIdx) == "number" and FILTERS[data.filterIdx] then
                inst.filterIdx = data.filterIdx
            end
            updateTsButton(inst)
            updateFilterButton(inst)
            replay(inst)
        end,
        onReveal = function(target)
            local inst = instances[target._gid]
            if inst then replay(inst) end
        end,
    }
end

function f2tRegisterChat()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[chat] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_chat", buildChatDef())
    if f2t_debug_log then f2t_debug_log("[chat] registered fed2_chat content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterChat)

registerAnonymousEventHandler("f2tChatUpdated", function(_, mode)
    for gid, inst in pairs(instances) do
        if mode == "append" then
            local ok = pcall(appendLatest, inst)
            if not ok then instances[gid] = nil end
        else
            local ok = pcall(replay, inst)
            if not ok then instances[gid] = nil end
        end
    end
end)

if f2t_debug_log then f2t_debug_log("[chat] content module loaded") end
