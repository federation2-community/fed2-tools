-- local_players.lua — Players-in-room content for fed2-tools.
--
-- Renders gmcp.room.info.players — the players standing in the current room —
-- with rank-colored, clickable names (player card) and an examine link.
--
-- This module ONLY registers content; it does not manage visibility.  The
-- archive showed/hid its dropdown as players came and went — to replicate
-- that, place "fed2_local_players" in a pane and add a rule:
--     Show when → GMCP has value → room.info.players
-- Muxlet's condition engine handles the dynamics from there.
--
-- Ported from archive's ui_local_players.lua.

-- Rank → cecho color for names (archive's LOCAL_RANK_COLOR).
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
    ["Syndicrat"]     = "olive",
    ["Commander"]     = "dark_violet",
    ["Groundhog"]     = "dark_violet",
}
local RANK_CECHO_DEFAULT = "ansi_white"

local consoles = {}   -- target._gid → MiniConsole

local function roomPlayers()
    return gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.players or nil
end

local function renderConsole(mc)
    if not mc then return end
    mc:clear()

    local players = roomPlayers()
    local count   = players and #players or 0

    mc:cecho(string.format("<ansiCyan><b>  Local Players</b><reset>  <grey>(%d)<reset>\n", count))
    mc:cecho("  <grey>" .. string.rep("─", 30) .. "<reset>\n")

    if count == 0 then
        mc:cecho("\n  <grey>No one else is here.<reset>\n")
        return
    end

    for _, player in ipairs(players) do
        local name = player.name or "Unknown"
        local rank = player.rank or ""
        local cc   = RANK_CECHO[rank] or RANK_CECHO_DEFAULT
        local hint = rank ~= "" and (rank .. " " .. name) or name

        mc:cecho("  ")
        mc:cechoLink(
            "<" .. cc .. "><b>" .. name .. "</b><reset>",
            function()
                if f2tPlayerCardShowOrRaiseByName then f2tPlayerCardShowOrRaiseByName(name) end
            end,
            hint, true)
        mc:cecho("  ")
        mc:cechoLink(
            "<dim_gray>[ex]<reset>",
            function() send("ex " .. name, false) end,
            "Examine " .. name, true)
        mc:cecho("\n")
    end
end

local function refreshAll()
    for _, mc in pairs(consoles) do
        if mc then pcall(renderConsole, mc) end
    end
end

local function buildLocalPlayersDef()
    return {
        name        = "Local Players",
        description = "Players in the current room from gmcp.room.info.",
        group       = "Fed2 Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            if target.contentBg then
                target.contentBg:echo("")
                target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
            end
            local mc = consoles[target._gid]
            if not mc then
                mc = Geyser.MiniConsole:new({
                    name = target._gid .. "_lpmc", x = 0, y = 0, width = "100%", height = "100%",
                    scrollBar = false, fontSize = 9,
                }, target.content)
                mc:setColor(18, 18, 26)
                consoles[target._gid] = mc
            else
                mc:show(); mc:raise()
            end
            renderConsole(mc)
        end,
        remove = function(target)
            local mc = consoles[target._gid]
            if mc then if mc.delete then mc:delete() else mc:hide() end end
            consoles[target._gid] = nil
        end,
        resize    = function(target) renderConsole(consoles[target._gid]) end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target) renderConsole(consoles[target._gid]) end,
    }
end

function f2tRegisterLocalPlayers()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[local_players] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_local_players", buildLocalPlayersDef())
    if f2t_debug_log then f2t_debug_log("[local_players] registered fed2_local_players content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterLocalPlayers)

-- Room changes (and player arrivals/departures) arrive as gmcp.room.info pushes.
registerAnonymousEventHandler("gmcp.room.info", function() refreshAll() end)

if f2t_debug_log then f2t_debug_log("[local_players] module loaded") end
