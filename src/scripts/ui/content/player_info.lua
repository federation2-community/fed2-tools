-- player_info.lua — Fed2 pilot & ship info content for fed2-tools.
--
-- Ported from the archive top-left frame (ui_header.lua): the six live stat
-- labels (Rank, Fuel, Stamina, Groats, Slithies, Hold) plus a Buy Fuel button,
-- with the fuel/stamina/hold value colouring driven by gmcp.char.vitals and
-- gmcp.char.ship.
--
-- Registered as "fed2_player_info" content so it can be applied to any pane or tab.
-- The stat labels live in a Geyser.HBox spanning the content area, so the row
-- scales with the placement automatically; the Buy Fuel button is anchored a
-- fixed width in from the right edge.
--
-- Cleanup: every widget is created inside target.content (the framework's
-- disposable slot), so widget teardown is automatic on content change/removal.
-- The only per-instance state is the label/button table, dropped in remove().
-- Live updates use session-level GMCP handlers that iterate existing instances,
-- so there is nothing per-instance to unregister.

local H_LABEL_CSS = [[
    background-color: qlineargradient(x1:0, y1:0, x2:0, y2:1,
        stop:0 #2a2a3a, stop:0.4 #1e1e2a, stop:1 #16161e);
    color: #c8c8d0;
    border: none;
    border-right: 1px solid #3a3a4a;
    padding: 4px 8px;
    font-family: "Consolas","Monaco",monospace;
]]

local BUTTON_CSS = [[
    QLabel{
        background-color: rgba(40, 40, 45, 200);
        border: 1px solid rgba(100, 100, 110, 180);
        border-radius: 3px;
        color: rgba(200, 200, 210, 255);
        font-size: 11px; font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover{
        background-color: rgba(60, 60, 70, 220);
        border-color: rgba(120, 180, 255, 200);
        color: white;
    }
]]


-- Groats target per rank (archive UI.magic_cash_numbers): the "promotion cash"
-- threshold shown as Groats: cur/target.  Ranks past Financier have no fixed
-- target, so only the current cash is shown.
local MAGIC_CASH = {
    Commander     = 250000,
    Captain       = 400000,
    Adventurer    = 600000,
    Adventuress   = 600000,
    Merchant      = 7500000,
    Trader        = 12500000,
    Industrialist = 17500000,
    Manufacturer  = 22500000,
    Financier     = 27500000,
}

-- Per-placement state, keyed by target._gid
local instances = {}

-- Format long numbers with thousands separators, or "N.N m" above a million.
-- (Ported from archive ui_convert_value.)
local function convertValue(amount)
    if amount == nil then return nil end
    local formatted = tostring(amount)
    if tonumber(formatted) == nil then return nil end
    if tonumber(formatted) <= 1000000 then
        while true do
            local k
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
            if k == 0 then break end
        end
    else
        formatted = math.floor(tonumber(formatted) / 100000) / 10 .. " m"
    end
    return formatted
end

-- Colour a value on a red→green gradient by its percentage of max.
-- (Ported from archive ui_color_percent.)
local COLOR_GRAD = {
    [0]="#800000",[1]="#801a00",[2]="#803400",[3]="#804e00",[4]="#806800",
    [5]="#808000",[6]="#668000",[7]="#4c8000",[8]="#328000",[9]="#008000",[10]="#FFFFFF",
}
local function colorPercent(cur, max)
    local c, m = tonumber(cur), tonumber(max)
    if not c or not m or m == 0 then return "#FFFFFF" end
    local pct = math.floor((c / m) * 10)
    if pct < 0 then pct = 0 elseif pct > 10 then pct = 10 end
    return COLOR_GRAD[pct]
end

local function refreshInstance(gid)
    local inst = instances[gid]
    if not inst or not inst.labels then return end
    local L = inst.labels

    local vitals = (gmcp.char and gmcp.char.vitals) or {}
    local ship   = (gmcp.char and gmcp.char.ship)   or {}

    local rank     = vitals.rank or "-"
    local hold_cur = (ship.hold and ship.hold.cur) or "-"
    local hold_max = (ship.hold and ship.hold.max) or "-"
    local fuel_cur = (ship.fuel and ship.fuel.cur) or "-"
    local fuel_max = (ship.fuel and ship.fuel.max) or "-"
    local stam_cur = (vitals.stamina and vitals.stamina.cur) or "-"
    local stam_max = (vitals.stamina and vitals.stamina.max) or "-"
    local cash     = convertValue(vitals.cash) or "-"
    local slith    = vitals.slithies or "-"
    local groats_max = convertValue(MAGIC_CASH[rank]) or "-"

    L[1]:echo("Rank: <b>" .. rank .. "</b>")

    if tonumber(fuel_cur) then
        L[2]:echo(string.format("Fuel: <b><font color=%s>%s</font></b>/%s",
            colorPercent(fuel_cur, fuel_max), fuel_cur, fuel_max))
    else
        L[2]:echo("Fuel: -")
    end

    if tonumber(stam_cur) then
        L[3]:echo(string.format("Stamina: <b><font color=%s>%s</font></b>/%s",
            colorPercent(stam_cur, stam_max), stam_cur, stam_max))
    else
        L[3]:echo("Stamina: -")
    end

    if groats_max == "-" then
        L[4]:echo("Groats: <b>" .. cash .. "</b>")
    else
        L[4]:echo("Groats: <b>" .. cash .. "</b>/" .. groats_max)
    end

    L[5]:echo("Slithies: <b>" .. tostring(slith) .. "</b>")

    if tonumber(hold_cur) then
        local has_cargo = ship.cargo and next(ship.cargo) ~= nil
        local disp = string.format("Hold: <b><font color=%s>%s</font></b>/%s",
            colorPercent(hold_cur, hold_max), hold_cur, hold_max)
        if has_cargo then disp = disp .. " 📦" end
        L[6]:echo(disp)
    else
        L[6]:echo("Hold: -")
    end
end

local function refreshAll()
    for gid in pairs(instances) do pcall(refreshInstance, gid) end
end

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
    end

    -- Re-show if already built (apply called without a prior remove).
    if instances[gid] then
        refreshInstance(gid)
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_pinfo_%d", gid, wc)
    end

    -- Stat row: an HBox that fills the whole content area so the six cells share
    -- the width evenly and rescale with the placement.
    local box = Geyser.HBox:new({
        name = wid(), x = 0, y = 0,
        width = "100%", height = "100%",
    }, target.content)

    -- Transparent text sub-label CSS (lets the cell's gradient show through).
    local CELL_TEXT_CSS =
        "background: transparent; border: none; color: #c8c8d0;" ..
        ' padding: 4px 8px; font-family: "Consolas","Monaco",monospace;'


    local labels = {}
    local buyBtn
    for i = 1, 6 do
        if i == 2 then
            -- Fuel cell: the readout plus an embedded Buy Fuel button on the
            -- right.  Given a larger stretch factor so there is room for both the
            -- value and the "⛽ Buy Fuel" button.  The cell keeps the row styling;
            -- an inner text label holds the value (so it is what refreshInstance
            -- echoes to) and the button is anchored at the right edge of the cell.
            local cell = Geyser.Label:new({ name = wid(), h_stretch_factor = 1.8 }, box)
            cell:setStyleSheet(H_LABEL_CSS)
            cell.h_stretch_factor = 1.8

            -- Fixed-pixel layout so the gap between readout and button stays small
            -- and constant at any pane width (a percentage gap widens as the strip
            -- grows).  The readout occupies a fixed text region; the button sits a
            -- couple of px after it and is only as large as its label needs.
            local fuelText = Geyser.Label:new({
                name = wid(), x = 0, y = 0,
                width = 92, height = "100%",
            }, cell)
            fuelText:setStyleSheet(CELL_TEXT_CSS)
            pcall(function() fuelText:setFontSize(11) end)
            labels[2] = fuelText

            buyBtn = Geyser.Label:new({
                name = wid(), x = 94, y = "15%",
                width = 84, height = "70%",
            }, cell)
            buyBtn:setStyleSheet(BUTTON_CSS)
            buyBtn:echo("<center>⛽&nbsp;Buy&nbsp;Fuel</center>")
            buyBtn:setToolTip("Buy fuel at a shuttlepad")
            buyBtn:setClickCallback(function() send("buy fuel") end)
        else
            local l = Geyser.Label:new({ name = wid() }, box)
            l:setStyleSheet(H_LABEL_CSS)
            pcall(function() l:setFontSize(11) end)
            labels[i] = l
        end
    end

    -- Hold label stays informative; the legacy inline cargo panel is now its own
    -- registered content (fed2_cargo).
    labels[6]:setToolTip("Cargo hold")

    instances[gid] = { labels = labels, buyBtn = buyBtn }
    refreshInstance(gid)
end

local function buildPlayerInfoDef()
    return {
        name        = "Player Info",
        description = "Live rank / fuel / stamina / groats / slithies / hold strip with Buy Fuel.",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok and f2t_debug_log then
                f2t_debug_log("[player_info] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            -- Widgets are torn down with the slot; just drop per-instance state.
            instances[target._gid] = nil
        end,
        resize = function(target)
            -- HBox + percentage anchors rescale automatically; re-echo so any
            -- text that depends on width re-renders crisply.
            refreshInstance(target._gid)
        end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target) refreshInstance(target._gid) end,
    }
end

function f2tRegisterPlayerInfo()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[player_info] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_player_info", buildPlayerInfoDef())
    if f2t_debug_log then f2t_debug_log("[player_info] registered fed2_player_info content") end
end

-- Session-level live updates: refresh every open header on the relevant GMCP
-- pushes.  Iterates only existing instances, so it is a no-op when no header is
-- placed and needs no per-instance teardown.
registerAnonymousEventHandler("gmcp.char.vitals", refreshAll)
registerAnonymousEventHandler("gmcp.char.ship",   refreshAll)

if f2t_debug_log then f2t_debug_log("[player_info] module loaded") end