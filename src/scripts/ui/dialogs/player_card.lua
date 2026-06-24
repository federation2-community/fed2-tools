-- player_card.lua — Contact card popup for fed2-tools.
--
-- Shows a floating Adjustable.Container with player details (rank, location,
-- company/system/cartel, ship class, titles) and a quick-send command line.
-- Multiple cards can be open simultaneously; each is keyed by a generation number.
--
-- Public API:
--   f2tPlayerCardShow(player, pos)           — open card (or raise if already open)
--   f2tPlayerCardClose(cardId)               — close specific card
--   f2tPlayerCardShowOrRaise(player)         — show or bring existing card to front
--   f2tPlayerCardShowOrRaiseByName(name)     — look up by name, then show or raise
--   f2tPlayerCardsRefreshAll()               — rebuild any card whose data changed
--
-- Ported from archive's ui_players.lua (ui_player_card_* functions).

local _cards       = {}     -- cardId → card meta
local _cardsByName = {}     -- player name → cardId
local _cardN       = 0      -- monotonic counter for unique IDs + offset cascade

-- ── Rank → CSS accent color ───────────────────────────────────────────────────

local RANK_CARD_COLOR = {
    ["Groundhog"]     = "rgba(110, 40, 190, 255)",
    ["Commander"]     = "rgba(110, 40, 190, 255)",
    ["Captain"]       = "rgba(180, 180, 230, 255)",
    ["Adventurer"]    = "rgba(180, 180, 230, 255)",
    ["Merchant"]      = "rgba(195, 235, 195, 255)",
    ["Trader"]        = "rgba(195, 235, 195, 255)",
    ["Industrialist"] = "rgba(50, 205, 90, 255)",
    ["Manufacturer"]  = "rgba(50, 205, 90, 255)",
    ["Financier"]     = "rgba(50, 205, 90, 255)",
    ["Mogul"]         = "rgba(0, 215, 235, 255)",
    ["Engineer"]      = "rgba(0, 215, 235, 255)",
    ["Technocrat"]    = "rgba(0, 215, 235, 255)",
    ["Gengineer"]     = "rgba(0, 215, 235, 255)",
    ["Magnate"]       = "rgba(0, 215, 235, 255)",
    ["Founder"]       = "rgba(0, 215, 235, 255)",
    ["Plutocrat"]     = "rgba(215, 65, 65, 255)",
}
local CARD_COLOR_DEFAULT = "rgba(120, 125, 155, 255)"

-- ── Button styles ─────────────────────────────────────────────────────────────

local _CSS_CLOSE = [[
    QLabel {
        background-color: rgba(180, 50, 50, 220);
        border: 1px solid rgba(200, 80, 80, 180);
        border-radius: 3px;
        color: white;
        font-size: 14px; font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(215, 60, 60, 245); border-color: rgba(255, 110, 110, 220); }
]]
local _CSS_NAV = [[
    QLabel {
        background-color: rgba(40, 120, 80, 210);
        border: 1px solid rgba(60, 140, 100, 180);
        border-radius: 3px;
        color: white;
        font-size: 10px; font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(55, 150, 95, 230); }
]]
local _CSS_GAL = [[
    QLabel {
        background-color: rgba(18, 22, 52, 210);
        color: rgba(120, 155, 255, 255);
        border: 1px solid rgba(75, 95, 200, 200);
        border-radius: 3px;
        font-size: 12px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(30, 40, 90, 235);
        border-color: rgba(110, 140, 255, 255);
        color: rgba(180, 205, 255, 255);
    }
]]
local _CSS_ICON = [[
    QLabel {
        background-color: rgba(32, 36, 58, 220);
        color: rgba(165, 180, 220, 255);
        border: 1px solid rgba(80, 92, 140, 210);
        border-radius: 4px;
        font-size: 14px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(50, 58, 95, 240);
        border-color: rgba(110, 125, 195, 255);
        color: rgba(210, 225, 255, 255);
    }
]]
local _TEXT_CSS_BASE = [[
    background: transparent; border: none;
    font-size: 12px; font-family: "Consolas","Monaco",monospace;
    padding: 0 8px;
]]
local _LABEL_HTML = "<span style='color: rgb(120,130,170);'>%s:</span> "

-- ── Galaxy integration ────────────────────────────────────────────────────────

local function openInGalaxy(cartelName, entityName)
    if not F2T_GALAXY then return end

    local function expand()
        if cartelName and cartelName ~= "" then
            F2T_GALAXY.expanded[cartelName] = true
        elseif entityName and entityName ~= "" then
            for cn, cd in pairs(F2T_GALAXY.cartels or {}) do
                if cd.systems then
                    if cd.systems[entityName] then
                        F2T_GALAXY.expanded[cn] = true
                        F2T_GALAXY.expanded[cn .. ":" .. entityName] = true
                        break
                    end
                    for sn, sd in pairs(cd.systems) do
                        for _, pd in ipairs(sd.planets or {}) do
                            if pd.name == entityName then
                                F2T_GALAXY.expanded[cn] = true
                                F2T_GALAXY.expanded[cn .. ":" .. sn] = true
                                break
                            end
                        end
                    end
                end
            end
        end
        if f2t_galaxy_refresh_open then f2t_galaxy_refresh_open() end
    end

    if F2T_GALAXY.loaded then
        expand()
    elseif F2T_GALAXY.loading then
        local function wait()
            if F2T_GALAXY.loaded then expand()
            elseif F2T_GALAXY.loading then tempTimer(0.25, wait) end
        end
        tempTimer(0.25, wait)
    else
        if f2t_galaxy_schedule_scrape then f2t_galaxy_schedule_scrape(0) end
        local function wait()
            if F2T_GALAXY.loaded then expand()
            elseif F2T_GALAXY.loading then tempTimer(0.25, wait) end
        end
        tempTimer(0.5, wait)
    end

    if f2t_galaxy_toggle then f2t_galaxy_toggle() end
end

-- ── Fingerprint ───────────────────────────────────────────────────────────────

local function fingerprint(p)
    return table.concat({
        p.rank or "", p.location or "", p.company or "",
        p.system or "", p.cartel or "", p.ship_class or "",
        p.staff or "", tostring(p.is_online == false),
    }, "\0")
end

-- ── Public: close ─────────────────────────────────────────────────────────────

function f2tPlayerCardClose(cardId)
    local c = _cards[cardId]
    if not c then return end
    for _, h in ipairs(c.resizeHandlers or {}) do killAnonymousEventHandler(h) end
    if c.actionKey then _G[c.actionKey] = nil end
    c.container:hide()
    if c.playerName then _cardsByName[c.playerName] = nil end
    _cards[cardId] = nil
end

-- ── Public: show ──────────────────────────────────────────────────────────────

-- pos: optional {x=, y=} to override centered placement (used for in-place refresh)
function f2tPlayerCardShow(player, pos)
    local name = player.name or "Unknown"

    local existingId = _cardsByName[name]
    if existingId and _cards[existingId] then
        _cards[existingId].container:raiseAll()
        return
    end

    _cardN = _cardN + 1
    local n = _cardN

    local rank      = player.rank       or "Unknown"
    local loc       = player.location   or ""
    local company   = player.company    or ""
    local system    = player.system     or ""
    local cartel    = player.cartel     or ""
    local staff     = player.staff      or ""
    local ship      = player.ship_class or ""
    local titles    = player.titles     or {}
    local isOffline = (player.is_online == false)
    local lastSeen  = player.last_seen

    local accent = isOffline
        and "rgba(90, 90, 100, 200)"
        or  (RANK_CARD_COLOR[rank] or CARD_COLOR_DEFAULT)

    -- ── Ownership classification ──────────────────────────────────────────────
    local hasCompany   = company ~= ""
    local isIndustrial = rank == "Industrialist"
    local isMfrFin     = rank == "Manufacturer" or rank == "Financier"
    local hasSystem    = system ~= "" and (
        rank == "Engineer"   or rank == "Technocrat" or rank == "Gengineer" or
        rank == "Magnate"    or rank == "Founder"    or rank == "Mogul")
    local hasCartel    = cartel ~= "" and rank == "Plutocrat"
    local hasShip      = ship   ~= ""
    local hasOwnership = (hasCompany and (isIndustrial or isMfrFin)) or hasSystem or hasCartel

    -- ── Layout constants ──────────────────────────────────────────────────────
    local HDR_H   = 44
    local DIV_H   = 2
    local ROW_H   = 26
    local LOC_GAP = 16
    local BTN_W   = 26
    local ICON_W  = 30
    local GAP     = 3
    local R_M     = 4
    local CMD_H   = 30
    local SEND_W  = 34
    local CMD_L_M = 4
    local CMD_R_M = 8

    local NAV_X_2  = tostring(-(BTN_W + GAP + BTN_W + R_M))
    local GAL_X    = tostring(-(BTN_W + R_M))
    local TEXT_W_2 = tostring(-(BTN_W + GAP + BTN_W + GAP + R_M))
    local TEXT_W_1 = tostring(-(BTN_W + GAP + R_M))
    local ACCT_X   = tostring(-(ICON_W + R_M))
    local TEXT_W_A = tostring(-(ICON_W + GAP + R_M))

    -- ── Width / height calculation ────────────────────────────────────────────
    local function badgePx(s) return math.ceil(#s * 6.5) + 16 end
    local nameLblW    = math.ceil(#name * 9.0) + 16
    local rankBadgeW  = badgePx(rank)
    local staffBadgeW = staff ~= "" and badgePx("[" .. staff .. "]") or 0
    local closeW      = 28
    local headerNeed  = 10 + nameLblW + 6 + rankBadgeW
        + (staff ~= "" and (4 + staffBadgeW) or 0)
        + 10 + closeW + 6

    local longest = math.max(
        #(loc ~= "" and loc or "Unknown"),
        hasCompany and (#company + 10) or 0,
        hasSystem  and (#system  + 8)  or 0,
        hasCartel  and (#cartel  + 8)  or 0)
    local bodyNeed = math.ceil(longest * 7.0) + 30 + 62

    local CARD_W = math.max(360, math.min(580, math.max(headerNeed, bodyNeed)))

    local SEND_X  = tostring(-(SEND_W + CMD_R_M))
    local CMD_W   = tostring(-(SEND_W + GAP + CMD_R_M + CMD_L_M))
    local FRAME_W = tostring(-(SEND_W + GAP + CMD_R_M + CMD_L_M - 2))

    local sw, sh = getMainWindowSize()
    local bodyTop   = HDR_H + DIV_H
    local offlineH  = isOffline and ROW_H or 0
    local baseH = bodyTop + offlineH + ROW_H
    if hasOwnership                   then baseH = baseH + LOC_GAP end
    if hasCompany and isIndustrial    then baseH = baseH + ROW_H end
    if hasCompany and isMfrFin        then baseH = baseH + ROW_H end
    if hasSystem                      then baseH = baseH + ROW_H end
    if hasCartel                      then baseH = baseH + ROW_H end
    if hasShip                        then baseH = baseH + ROW_H end

    local quickH = isOffline and 14 or (10 + CMD_H + 22)

    local TITLE_OVERHEAD = 10 + ROW_H
    local maxCardH = sh - 80
    local availForTitles = maxCardH - baseH - quickH
    local shownTitles = 0
    if #titles > 0 and availForTitles >= (TITLE_OVERHEAD + 22) then
        shownTitles = math.min(#titles, math.floor((availForTitles - TITLE_OVERHEAD) / 22))
    end

    local CARD_H = baseH
        + (shownTitles > 0 and (TITLE_OVERHEAD + shownTitles * 22) or 0)
        + quickH

    -- ── Create Adjustable.Container ───────────────────────────────────────────
    local offset   = (_cardN - 1) % 10 * 22
    local cx = pos and pos.x or (math.floor((sw - CARD_W) / 2) + offset)
    local cy = pos and pos.y or (math.floor((sh - CARD_H) / 2) + offset)

    local cardName = string.format("f2t_pcard_%d", n)
    local card = Adjustable.Container:new({
        name          = cardName,
        x = cx, y = cy,
        width = CARD_W, height = CARD_H,
        adjLabelstyle = string.format([[
            background-color: rgba(10, 12, 22, 252);
            border: 2px solid %s;
            border-radius: 6px;
        ]], accent),
        autoSave = false,
        autoLoad = false,
    })
    card:lockContainer("border")
    card.locked = false

    local resizeHandlers = {}
    local function snapSize(_, resizedName)
        if resizedName == cardName then card:resize(CARD_W, CARD_H) end
    end
    for _, evt in ipairs({ "AdjustableContainerResize", "AdjustableContainerResized",
                            "AdjustableContainerResizeFinish" }) do
        resizeHandlers[#resizeHandlers + 1] = registerAnonymousEventHandler(evt, snapSize)
    end

    local quickCmdName = string.format("f2tpc%d_qcmd", n)
    local actionKey    = string.format("_f2t_qsend_%d", n)
    _G[actionKey] = not isOffline and function(text)
        if text and text ~= "" then
            expandAlias(string.format("tb %s %s", name, text), false)
            clearCmdLine(quickCmdName)
        end
    end or nil

    _cards[n] = {
        container      = card,
        resizeHandlers = resizeHandlers,
        actionKey      = actionKey,
        playerName     = name,
        fingerprint    = fingerprint(player),
    }
    _cardsByName[name] = n

    local _in = card.Inside
    local wc  = 0
    local function wid() wc = wc + 1; return string.format("f2tpc%d_%d", n, wc) end

    -- ── Header ────────────────────────────────────────────────────────────────
    local hdr = Geyser.Label:new({ name=wid(), x=0, y=0, width="100%", height=HDR_H }, _in)
    hdr:setStyleSheet([[
        background: qlineargradient(x1:0,y1:0,x2:0,y2:1,
            stop:0 rgba(30,34,54,255), stop:1 rgba(16,18,32,255));
        border: none; border-radius: 4px 4px 0 0;
    ]])

    local hdrY = math.floor((HDR_H - 22) / 2)

    local nameLbl = Geyser.Label:new({
        name=wid(), x=10, y=hdrY-2, width=nameLblW, height=26,
    }, hdr)
    nameLbl:setStyleSheet(string.format([[
        background: transparent; border: none;
        color: %s;
        font-size: 14px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
    ]], accent))
    nameLbl:echo("<u>" .. name .. "</u>")
    nameLbl:setClickCallback(function() send("spynet report " .. name) end)
    nameLbl:setToolTip("Spynet report: " .. name)

    local rankX = 10 + nameLblW + 6
    local rankLbl = Geyser.Label:new({ name=wid(), x=rankX, y=hdrY, width=rankBadgeW, height=22 }, hdr)
    rankLbl:setStyleSheet(string.format([[
        background: rgba(20,22,38,200);
        color: %s;
        font-size: 10px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        border: 1px solid %s;
        border-radius: 3px;
        qproperty-alignment: AlignCenter;
    ]], accent, accent))
    rankLbl:echo(rank)

    if staff ~= "" then
        local staffX = rankX + rankBadgeW + 4
        local staffLbl = Geyser.Label:new({ name=wid(), x=staffX, y=hdrY, width=staffBadgeW, height=22 }, hdr)
        staffLbl:setStyleSheet([[
            background: rgba(100, 80, 0, 180);
            color: rgba(255, 215, 70, 255);
            font-size: 9px; font-weight: bold;
            font-family: "Consolas","Monaco",monospace;
            border: 1px solid rgba(200, 165, 0, 160);
            border-radius: 3px;
            qproperty-alignment: AlignCenter;
        ]])
        staffLbl:echo(string.format("[%s]", staff))
    end

    local closeBtn = Geyser.Label:new({
        name=wid(), x=tostring(-(closeW + 4)), y=hdrY-1, width=closeW, height=24,
    }, hdr)
    closeBtn:setStyleSheet(_CSS_CLOSE)
    closeBtn:echo("<center>✕</center>")
    closeBtn:setClickCallback(function() f2tPlayerCardClose(n) end)

    -- ── Header divider ────────────────────────────────────────────────────────
    local div = Geyser.Label:new({ name=wid(), x=0, y=HDR_H, width="100%", height=DIV_H }, _in)
    div:setStyleSheet("background-color: rgba(255,255,255,0.09); border: none;")

    -- ── Row helpers ───────────────────────────────────────────────────────────
    local rowY = bodyTop

    local function addLinkRow(opts)
        local hasNav = opts.nav_cmd ~= nil
        local hasGal = opts.galaxy_fn ~= nil
        local textW, navX, galX
        if hasNav and hasGal then
            textW = TEXT_W_2; navX = NAV_X_2; galX = GAL_X
        elseif hasGal then
            textW = TEXT_W_1; galX = GAL_X
        else
            textW = tostring(-R_M)
        end
        local labelHtml = opts.label and string.format(_LABEL_HTML, opts.label) or ""
        local txt = Geyser.Label:new({ name=wid(), x=0, y=rowY, width=textW, height=ROW_H }, _in)
        txt:setStyleSheet(_TEXT_CSS_BASE .. string.format("color: %s;", opts.text_color))
        if opts.di_cmd then
            txt:echo(string.format("  %s  %s<u>%s</u>", opts.icon, labelHtml, opts.text))
            txt:setClickCallback(function() send(opts.di_cmd) end)
            txt:setToolTip(opts.di_tooltip or opts.di_cmd)
        else
            txt:echo(string.format("  %s  %s%s", opts.icon, labelHtml, opts.text))
        end
        if hasNav then
            local nb = Geyser.Label:new({ name=wid(), x=navX, y=rowY+2, width=BTN_W, height=ROW_H-4 }, _in)
            nb:setStyleSheet(_CSS_NAV)
            nb:echo("<center>→</center>")
            nb:setClickCallback(function() expandAlias(opts.nav_cmd) end)
            nb:setToolTip("Navigate to " .. opts.text)
        end
        if hasGal then
            local gb = Geyser.Label:new({ name=wid(), x=galX, y=rowY+2, width=BTN_W, height=ROW_H-4 }, _in)
            gb:setStyleSheet(_CSS_GAL)
            gb:echo("<center>🔭</center>")
            gb:setClickCallback(opts.galaxy_fn)
            gb:setToolTip("View in Galaxy Navigator")
        end
        rowY = rowY + ROW_H
    end

    local function addCompanyRow(opts)
        local hasAcct = opts.acct_cmd ~= nil
        local textW   = hasAcct and TEXT_W_A or tostring(-R_M)
        local labelHtml = opts.label and string.format(_LABEL_HTML, opts.label) or ""
        local txt = Geyser.Label:new({ name=wid(), x=0, y=rowY, width=textW, height=ROW_H }, _in)
        txt:setStyleSheet(_TEXT_CSS_BASE .. string.format("color: %s;", opts.text_color))
        if opts.di_cmd then
            txt:echo(string.format("  %s  %s<u>%s</u>", opts.icon, labelHtml, opts.text))
            txt:setClickCallback(function() send(opts.di_cmd) end)
            txt:setToolTip(opts.di_tooltip or opts.di_cmd)
        else
            txt:echo(string.format("  %s  %s%s", opts.icon, labelHtml, opts.text))
        end
        if hasAcct then
            local ab = Geyser.Label:new({ name=wid(), x=ACCT_X, y=rowY+2, width=ICON_W, height=ROW_H-4 }, _in)
            ab:setStyleSheet(_CSS_ICON)
            ab:echo("<center>📊</center>")
            ab:setClickCallback(function() send(opts.acct_cmd) end)
            ab:setToolTip("View accounts  (di accounts " .. opts.text .. ")")
        end
        rowY = rowY + ROW_H
    end

    -- ── Offline banner ────────────────────────────────────────────────────────
    if isOffline then
        local agoStr = (lastSeen and f2t_player_db_last_seen_str)
            and ("Last seen " .. f2t_player_db_last_seen_str(lastSeen))
            or  "Offline"
        local offLbl = Geyser.Label:new({ name=wid(), x=0, y=rowY, width="100%", height=ROW_H }, _in)
        offLbl:setStyleSheet([[
            background: rgba(60, 30, 30, 180);
            border: none;
            color: rgba(200, 140, 140, 255);
            font-size: 11px; font-weight: bold;
            font-family: "Consolas","Monaco",monospace;
            qproperty-alignment: AlignCenter;
        ]])
        offLbl:echo("⊘ OFFLINE  —  " .. agoStr)
        rowY = rowY + ROW_H
    end

    -- ── Location row ──────────────────────────────────────────────────────────
    local locText = loc ~= "" and loc or "Unknown"
    local locSys  = locText:match("^(.+) Space$")
    local diLoc   = locSys and ("di system " .. locSys) or ("di planet " .. locText)
    local navLoc  = locSys and ("nav " .. locSys .. " link") or ("nav " .. locText)

    addLinkRow({
        icon       = "📍",
        text       = locText,
        text_color = "rgba(130, 200, 255, 255)",
        di_cmd     = diLoc,
        di_tooltip = "Get info  (" .. diLoc .. ")",
        nav_cmd    = navLoc,
        galaxy_fn  = function()
            openInGalaxy(nil, locSys or locText)
        end,
    })

    if hasOwnership then
        local sep = Geyser.Label:new({ name=wid(), x=4, y=rowY+7, width=CARD_W-8, height=1 }, _in)
        sep:setStyleSheet("background-color: rgba(255,255,255,0.15); border: none;")
        rowY = rowY + LOC_GAP
    end

    -- ── Company ───────────────────────────────────────────────────────────────
    if hasCompany then
        if isIndustrial then
            addCompanyRow({
                icon       = "🏢",
                label      = "Business",
                text       = company,
                text_color = "rgba(160, 255, 160, 255)",
                di_cmd     = "di business " .. company,
                di_tooltip = "Get business info  (di business " .. company .. ")",
            })
        elseif isMfrFin then
            addCompanyRow({
                icon       = "🏭",
                label      = "Company",
                text       = company,
                text_color = "rgba(160, 255, 160, 255)",
                di_cmd     = "di company " .. company,
                di_tooltip = "Get company info  (di company " .. company .. ")",
                acct_cmd   = "di accounts " .. company,
            })
        end
    end

    -- ── System ────────────────────────────────────────────────────────────────
    if hasSystem then
        addLinkRow({
            icon       = "⭐",
            label      = "System",
            text       = system,
            text_color = "rgba(255, 228, 100, 255)",
            di_cmd     = "di system " .. system,
            di_tooltip = "Get system info  (di system " .. system .. ")",
            nav_cmd    = "nav " .. system .. " link",
            galaxy_fn  = function() openInGalaxy(nil, system) end,
        })
    end

    -- ── Cartel ────────────────────────────────────────────────────────────────
    if hasCartel then
        addLinkRow({
            icon       = "🌌",
            label      = "Cartel",
            text       = cartel,
            text_color = "rgba(255, 150, 200, 255)",
            di_cmd     = "di cartel " .. cartel,
            di_tooltip = "Get cartel info  (di cartel " .. cartel .. ")",
            galaxy_fn  = function() openInGalaxy(cartel, nil) end,
        })
    end

    -- ── Ship class ────────────────────────────────────────────────────────────
    if hasShip then
        local shipTxt = Geyser.Label:new({ name=wid(), x=0, y=rowY, width=tostring(-R_M), height=ROW_H }, _in)
        shipTxt:setStyleSheet(_TEXT_CSS_BASE .. "color: rgba(160, 165, 215, 255);")
        shipTxt:echo("  🚀  " .. ship)
        rowY = rowY + ROW_H
    end

    -- ── Titles ────────────────────────────────────────────────────────────────
    if shownTitles > 0 then
        local tdiv = Geyser.Label:new({ name=wid(), x=4, y=rowY+4, width=CARD_W-8, height=1 }, _in)
        tdiv:setStyleSheet("background-color: rgba(255,255,255,0.15); border: none;")
        rowY = rowY + 10

        local thdr = Geyser.Label:new({ name=wid(), x=0, y=rowY, width="100%", height=ROW_H }, _in)
        thdr:setStyleSheet([[
            background: transparent; border: none;
            color: rgba(130, 140, 185, 255);
            font-size: 10px; font-weight: bold;
            font-family: "Consolas","Monaco",monospace;
            padding: 0 10px;
        ]])
        local titleHdrText = shownTitles < #titles
            and string.format("  Titles  <span style='color: rgb(160,100,100);'>(showing %d of %d)</span>",
                shownTitles, #titles)
            or  "  Titles"
        thdr:echo(titleHdrText)
        rowY = rowY + ROW_H

        for i = 1, shownTitles do
            local tl = Geyser.Label:new({ name=wid(), x=0, y=rowY, width="100%", height=22 }, _in)
            tl:setStyleSheet([[
                background: transparent; border: none;
                color: rgba(175, 185, 225, 200);
                font-size: 11px;
                font-family: "Consolas","Monaco",monospace;
                padding: 0 10px;
            ]])
            tl:echo("  · " .. titles[i])
            rowY = rowY + 22
        end
    end

    -- ── Quick-send (online only) ──────────────────────────────────────────────
    if not isOffline then
        local qdiv = Geyser.Label:new({ name=wid(), x=4, y=rowY+4, width=CARD_W-8, height=1 }, _in)
        qdiv:setStyleSheet("background-color: rgba(255,255,255,0.15); border: none;")

        local cmdY = rowY + 10

        local cmdFrame = Geyser.Label:new({
            name   = wid(),
            x      = CMD_L_M - 2,
            y      = cmdY - 2,
            width  = FRAME_W,
            height = CMD_H + 4,
        }, _in)
        cmdFrame:setStyleSheet(string.format([[
            background: rgba(18, 20, 38, 235);
            border: 2px solid %s;
            border-radius: 4px;
        ]], accent))

        local quickCmd = Geyser.CommandLine:new({
            name   = quickCmdName,
            x      = CMD_L_M,
            y      = cmdY,
            width  = CMD_W,
            height = CMD_H,
        }, _in)
        quickCmd:setStyleSheet([[
            QPlainTextEdit {
                background: transparent;
                color: rgba(198, 210, 238, 255);
                border: none;
                font-size: 12px;
                font-family: "Consolas","Monaco",monospace;
                padding: 2px 6px;
            }
            QPlainTextEdit::placeholder {
                color: rgba(110, 120, 160, 200);
                font-style: italic;
            }
        ]])
        quickCmd:setAction(actionKey)
        if setCommandLineAction then setCommandLineAction(quickCmdName, actionKey) end

        local sendBtn = Geyser.Label:new({
            name   = wid(),
            x      = SEND_X,
            y      = cmdY - 2,
            width  = SEND_W,
            height = CMD_H + 4,
        }, _in)
        sendBtn:setStyleSheet(string.format([[
            QLabel {
                background-color: rgba(14, 17, 34, 245);
                color: %s;
                border: 2px solid %s;
                border-radius: 4px;
                font-size: 18px; font-weight: bold;
                qproperty-alignment: AlignCenter;
            }
            QLabel::hover {
                background-color: rgba(26, 30, 58, 255);
                color: rgba(220, 235, 255, 255);
            }
        ]], accent, accent))
        sendBtn:echo("<center>▶</center>")
        sendBtn:setClickCallback(function()
            local text = getCmdLine(quickCmdName)
            if text and text ~= "" then
                expandAlias(string.format("tb %s %s", name, text), false)
                clearCmdLine(quickCmdName)
            end
        end)
    end

    card:hide(); card:show(); card:raiseAll()
end

-- ── Public helpers ────────────────────────────────────────────────────────────

function f2tPlayerCardShowOrRaise(player)
    local name = player and player.name
    if not name then return end
    local existingId = _cardsByName[name]
    if existingId and _cards[existingId] then
        _cards[existingId].container:raiseAll()
        return
    end
    f2tPlayerCardShow(player)
end

function f2tPlayerCardShowOrRaiseByName(name)
    if not name or name == "" then return end
    local existingId = _cardsByName[name]
    if existingId and _cards[existingId] then
        _cards[existingId].container:raiseAll()
        return
    end
    local dbEntry = f2t_player_db_get and f2t_player_db_get(name)
    if dbEntry then
        f2tPlayerCardShow(dbEntry)
        return
    end
    f2tPlayerCardShow({ name = name })
end

-- Rebuild open cards whose data changed since they were last shown.
function f2tPlayerCardsRefreshAll()
    local online = {}
    for _, e in pairs(F2T_PLAYER_DB or {}) do online[e.name] = e end

    local toRebuild = {}
    for cardId, meta in pairs(_cards) do
        local pname = meta.playerName
        if pname then
            local fresh = online[pname] or (f2t_player_db_get and f2t_player_db_get(pname))
            if fresh then
                local newFp = fingerprint(fresh)
                if newFp ~= meta.fingerprint then
                    toRebuild[#toRebuild + 1] = {
                        cardId = cardId,
                        fresh  = fresh,
                        px     = meta.container:get_x(),
                        py     = meta.container:get_y(),
                    }
                end
            end
        end
    end

    for _, item in ipairs(toRebuild) do
        f2tPlayerCardClose(item.cardId)
        f2tPlayerCardShow(item.fresh, { x = item.px, y = item.py })
    end
end

if f2t_debug_log then f2t_debug_log("[player_card] module loaded") end
