-- price_checker.lua — Remote price-checking content for fed2-tools.
--
-- Replaces the old Trading tab. The free, no-subscription spot check
-- ('check price commodity') now lives as a click on the commodity name in
-- the Exchange content's Prices pane — this tab is only the subscription-
-- gated remote variants from the guide's "remote price checking service":
--   Cartel          — c price <commodity> cartel        (remote-access-cert)
--   Planet          — c price <commodity> <planet>       (remote-access-cert)
--   Solar System    — c price <commodity>                (upgrade)
--   Commodity Group — c price <group> <planet>            (upgrade)
--   Premium         — c premium <commodity> buy|sell|all  (premium ticker)
--
-- A pane-level condition can only gate the whole tab, not individual modes
-- inside it, so each mode's tool check lives here via f2t_has_tool() — modes
-- for tools the player doesn't own simply don't render a button. Cartel,
-- Planet, Solar System and Premium all produce the same per-line
-- "System: Planet is buying|selling N tons at Pig/ton" burst as the old cp
-- cartel command, captured by the price_checker_line trigger into the shared
-- table. Commodity Group's output format is unverified (no known player has
-- the upgrade tool yet), so it's sent as a plain command and prints to the
-- console instead of the table.
--
-- Find Best (unchanged from the old Trading tab) iterates every commodity
-- with `c price <c> cartel` and reports the best cartel-wide spread.

local H_MODE = 24  -- mode-selector pill row height (px)
local H_BAR  = 26  -- commodity/group + context input + Check button (px)
local H_STAT = 18
local H_COL  = 20
local ROW_H  = 20
local SB_W   = 17

local CELL_FONT = "font-size:10pt;font-family:Consolas,Monaco,monospace;"

local _COL_HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-size: 10pt; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: white; }
]]

local _BTN_CSS = [[
    QLabel {
        background-color: rgba(28,32,50,210);
        color: rgba(150,165,205,255);
        border: 1px solid rgba(72,85,128,180);
        border-radius: 3px;
        font-size: 10px; font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(42,48,78,230);
        color: rgba(200,215,255,255);
    }
]]

local _PILL_ACTIVE_CSS = [[
    QLabel {
        background-color: rgba(60,90,150,230);
        color: rgba(230,240,255,255);
        border: 1px solid rgba(120,150,220,220);
        border-radius: 3px;
        font-size: 10px; font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(75,105,170,240); }
]]

-- ── Tool gating ───────────────────────────────────────────────────────────────
-- GMCP tool keys under gmcp.char.vitals.tools. remote-access-cert is
-- confirmed. The upgrade and premium-ticker keys are STUBS — nobody has
-- bought those yet to confirm the real key names from GMCP. Fix these once
-- gmcp.char.vitals.tools shows the real entries.
local TOOL_REMOTE  = "remote-access-cert"
local TOOL_UPGRADE = "remote-access-upgrade"  -- STUB — unconfirmed key
local TOOL_PREMIUM = "premium-ticker"         -- STUB — unconfirmed key

local MODES = {
    {
        id = "cartel", label = "Cartel", tool = TOOL_REMOTE, capturesRows = true,
        hint = "Every planet in your current cartel (won't work in Sol)",
        command = function(target) return "c price " .. target .. " cartel" end,
    },
    {
        id = "planet", label = "Planet", tool = TOOL_REMOTE, capturesRows = true, needsPlanet = true,
        hint = "One named planet, checked remotely",
        command = function(target, planet) return "c price " .. target .. " " .. planet end,
    },
    {
        id = "system", label = "Solar Sys", tool = TOOL_UPGRADE, capturesRows = true,
        hint = "Every Solar System planet (only works outside an exchange)",
        command = function(target) return "c price " .. target end,
    },
    {
        id = "group", label = "Group", tool = TOOL_UPGRADE, isGroup = true, needsPlanet = true,
        hint = "A whole commodity group on one planet — prints to the console",
        command = function(target, planet) return "c price " .. target .. " " .. planet end,
    },
    {
        id = "premium", label = "Premium", tool = TOOL_PREMIUM, capturesRows = true, needsSide = true,
        hint = "The whole galaxy, excluding closed systems",
        command = function(target, _planet, side) return "c premium " .. target .. " " .. side end,
    },
}

-- ── Shared state (triggers read this) ────────────────────────────────────────

F2T_PRICE_CHECKER = F2T_PRICE_CHECKER or {
    mode              = "cartel",
    selectedCommodity = nil,
    selectedGroup     = nil,
    premiumSide       = "buy",   -- "buy" | "sell" | "all"
    currentCommodity  = nil,     -- commodity of the in-flight/last capturing check
    rows              = {},      -- current price table rows
    profitSearch      = {
        active      = false,
        list        = {},
        index       = 1,
        results     = {},
        best        = nil,
        bestProfit  = -math.huge,
        totalCount  = 0,
        data        = {},      -- rows captured for the commodity being scanned
    },
}

-- Per-pane state, keyed by target._gid
local instances = {}

-- ── Commodity / group lists (from resources/commodities.json) ────────────────

local _commodities = nil
local function commodityList()
    if _commodities then return _commodities end
    local filePath = getMudletHomeDir() .. "/fed2-tools/commodities.json"
    local file = io.open(filePath, "r")
    if not file then return {} end
    local raw = file:read("*all")
    file:close()
    local ok, data = pcall(yajl.to_value, raw)
    if not ok or not data or not data.groups then return {} end
    local list = {}
    for _, group in ipairs(data.groups) do
        for _, c in ipairs(group.commodities) do
            list[#list + 1] = { name = c.name, basePrice = c.basePrice }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    _commodities = list
    return list
end

local _groups = nil
local function groupList()
    if _groups then return _groups end
    local filePath = getMudletHomeDir() .. "/fed2-tools/commodities.json"
    local file = io.open(filePath, "r")
    if not file then return {} end
    local raw = file:read("*all")
    file:close()
    local ok, data = pcall(yajl.to_value, raw)
    if not ok or not data or not data.groups then return {} end
    local list = {}
    for _, group in ipairs(data.groups) do
        list[#list + 1] = { name = group.name }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    _groups = list
    return list
end

-- ── Mode helpers ──────────────────────────────────────────────────────────────

local function modeById(id)
    for _, m in ipairs(MODES) do
        if m.id == id then return m end
    end
    return nil
end

local function availableModes()
    local out = {}
    for _, m in ipairs(MODES) do
        if f2t_has_tool(m.tool) then out[#out + 1] = m end
    end
    return out
end

local function currentModeSpec()
    local m = modeById(F2T_PRICE_CHECKER.mode)
    if m and f2t_has_tool(m.tool) then return m end
    local avail = availableModes()
    return avail[1]
end

local function pickerList(modeSpec)
    if modeSpec and modeSpec.isGroup then return groupList() end
    return commodityList()
end

-- ── Table columns ─────────────────────────────────────────────────────────────

local function buildCols()
    return {
        {
            key           = "system",
            label         = "System",
            sortable      = true,
            sort_value    = function(r) return r.system:lower() end,
            scrollbox_pct = 22,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#ffffff;'>%s</span>", CELL_FONT, v or ""))
                cell:setToolTip("Jump to " .. tostring(v))
                cell:setClickCallback(function() expandAlias("nav " .. v .. " space link") end)
            end,
        },
        {
            key           = "planet",
            label         = "Planet",
            sortable      = true,
            sort_value    = function(r) return r.planet:lower() end,
            scrollbox_pct = 24,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#00cccc;'>%s</span>", CELL_FONT, v or ""))
                cell:setToolTip("Go to " .. tostring(v) .. " exchange")
                cell:setClickCallback(function()
                    expandAlias("nav " .. row.planet .. " exchange")
                end)
            end,
        },
        {
            key           = "action",
            label         = "Action",
            sortable      = true,
            sort_value    = function(r) return r.action end,
            scrollbox_pct = 16,
            render_label  = function(v, row, cell)
                -- The exchange is buying → the player can SELL there, and vice versa.
                local html
                if v == "buying" then
                    html = string.format("<span style='%scolor:#00cc44;'>[SELL]</span>", CELL_FONT)
                else
                    html = string.format("<span style='%scolor:#cccc44;'>[BUY]</span>", CELL_FONT)
                end
                cell:echo(html)
                cell:setToolTip(v == "buying"
                    and "Exchange is buying — click to sell here"
                    or  "Exchange is selling — click to buy here")
                cell:setClickCallback(function()
                    local cmd = (v == "buying") and "sell " or "buy "
                    send(cmd .. (F2T_PRICE_CHECKER.currentCommodity or ""), false)
                end)
            end,
        },
        {
            key           = "quantity",
            label         = "Qty",
            sortable      = true,
            sort_value    = function(r) return r.quantity or 0 end,
            scrollbox_pct = 14,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#ffffff;'>%s</span>", CELL_FONT, tostring(v or "")))
            end,
        },
        {
            key           = "price",
            label         = "Price",
            sortable      = true,
            default_sort  = "asc",
            sort_value    = function(r) return r.price or 0 end,
            scrollbox_pct = 24,
            render_label  = function(v, row, cell)
                -- Highlight the best buy (lowest selling) and best sell (highest buying).
                local bestBuy, bestSell = math.huge, -1
                for _, r in ipairs(F2T_PRICE_CHECKER.rows) do
                    if r.action == "selling" and r.price < bestBuy  then bestBuy  = r.price end
                    if r.action == "buying"  and r.price > bestSell then bestSell = r.price end
                end
                local color, bold = "#ffffff", ""
                if row.action == "selling" and row.price == bestBuy then
                    color, bold = "#cccc44", "font-weight:bold;"
                elseif row.action == "buying" and row.price == bestSell then
                    color, bold = "#00cc44", "font-weight:bold;"
                end
                cell:echo(string.format(
                    "<span style='%s%scolor:%s;'>%sig</span>", CELL_FONT, bold, color, tostring(v or "")))
            end,
        },
    }
end

-- ── Instance refresh ──────────────────────────────────────────────────────────

local function setStatus(text)
    for _, inst in pairs(instances) do
        if inst.status then inst.status:echo(text or "") end
    end
end

local _renderTimer = nil
local function refreshAllDebounced()
    if _renderTimer then killTimer(_renderTimer) end
    _renderTimer = tempTimer(0.15, function()
        _renderTimer = nil
        for _, inst in pairs(instances) do
            pcall(f2tTableSetData, inst.tableId, F2T_PRICE_CHECKER.rows)
        end
    end)
end

local function updatePremiumPills(inst)
    if not inst.premiumPills then return end
    for side, pill in pairs(inst.premiumPills) do
        pill:setStyleSheet(side == F2T_PRICE_CHECKER.premiumSide and _PILL_ACTIVE_CSS or _BTN_CSS)
    end
end

local function updateModePills(inst)
    if not inst.modePills then return end
    local avail = availableModes()

    if inst.findBestBtn then
        if f2t_has_tool(TOOL_REMOTE) then inst.findBestBtn:show() else inst.findBestBtn:hide() end
    end

    local n = math.max(1, #avail)
    local pillW = 100 / n
    for _, m in ipairs(MODES) do
        local pill = inst.modePills[m.id]
        if pill then
            local vi = nil
            for idx, am in ipairs(avail) do if am.id == m.id then vi = idx end end
            if vi then
                pill:show()
                pill:move(string.format("%.4f%%", (vi - 1) * pillW), 0)
                pill:resize(string.format("%.4f%%", pillW), "100%")
                pill:setStyleSheet(m.id == F2T_PRICE_CHECKER.mode and _PILL_ACTIVE_CSS or _BTN_CSS)
            else
                pill:hide()
            end
        end
    end
end

-- Shows/hides the planet input, premium side pills, or the plain hint label
-- in the context slot, and switches the table area for the group-mode note.
local function updateModeContext(inst)
    local modeSpec = currentModeSpec()
    if not modeSpec then return end

    if inst.dropBtn then
        local label = modeSpec.isGroup
            and (F2T_PRICE_CHECKER.selectedGroup or "Select Group")
            or  (F2T_PRICE_CHECKER.selectedCommodity or "Select Commodity")
        inst.dropBtn:echo("<center>" .. label .. " ▼</center>")
    end

    if inst.planetInput then
        if modeSpec.needsPlanet then inst.planetInput:show() else inst.planetInput:hide() end
    end
    if inst.premiumRow then
        if modeSpec.needsSide then inst.premiumRow:show() else inst.premiumRow:hide() end
    end
    if inst.hintLbl then
        if not modeSpec.needsPlanet and not modeSpec.needsSide then
            inst.hintLbl:show()
            inst.hintLbl:echo("<span style='font-size:9px;color:#7a86a8;'>" .. modeSpec.hint .. "</span>")
        else
            inst.hintLbl:hide()
        end
    end
    updatePremiumPills(inst)

    if inst.scroll and inst.colBar and inst.groupNote then
        if modeSpec.isGroup then
            inst.scroll:hide(); inst.colBar:hide(); inst.groupNote:show()
        else
            inst.scroll:show(); inst.colBar:show(); inst.groupNote:hide()
        end
    end
end

local function updateAllModeContext()
    for _, inst in pairs(instances) do updateModePills(inst); updateModeContext(inst) end
end

-- ── Trigger entry points ──────────────────────────────────────────────────────

function f2tPriceCheckerHasOpenPanels()
    return next(instances) ~= nil
end

function f2tPriceCheckerIsSearching()
    return F2T_PRICE_CHECKER.profitSearch.active
end

function f2tPriceCheckerLine(system, planet, action, quantity, price)
    local row = {
        system   = system,
        planet   = planet,
        action   = action,
        quantity = tonumber(quantity),
        price    = tonumber(price),
    }
    if F2T_PRICE_CHECKER.profitSearch.active then
        table.insert(F2T_PRICE_CHECKER.profitSearch.data, row)
    else
        table.insert(F2T_PRICE_CHECKER.rows, row)
        refreshAllDebounced()
    end
end

-- ── Best-profit search (cartel-only, unchanged from the old Trading tab) ─────

local function searchConsoles(fn)
    for _, inst in pairs(instances) do
        if inst.searchConsole then pcall(fn, inst.searchConsole) end
    end
end

local function searchNext()
    local ps = F2T_PRICE_CHECKER.profitSearch
    if not ps.active then return end

    local commodity = ps.list[ps.index]
    if not commodity then
        -- Done: show verdict.
        ps.active = false
        pcall(disableTrigger, "price_checker_profit_tick")   -- catch-all ^$ pattern; armed only while scanning
        table.sort(ps.results, function(a, b) return a.profit > b.profit end)
        searchConsoles(function(mc)
            mc:cecho("\n<white>==========================================\n")
            if ps.best then
                local best = ps.results[1]
                mc:cecho("<yellow>BEST PROFIT: <reset>")
                mc:cechoLink("<green><b>" .. best.commodity .. "</b><reset>",
                    function()
                        F2T_PRICE_CHECKER.mode = "cartel"
                        F2T_PRICE_CHECKER.selectedCommodity = best.commodity
                        updateAllModeContext()
                        if f2tPriceCheckerCheck then f2tPriceCheckerCheck() end
                    end,
                    "View full cartel prices for " .. best.commodity, true)
                mc:cecho(string.format(" | <green>%dig/ton profit<reset>\n", best.profit))
                mc:cecho(string.format("Buy at %dig, sell at %dig\n", best.bestBuy, best.bestSell))
                F2T_PRICE_CHECKER.selectedCommodity = best.commodity
                updateAllModeContext()
            else
                mc:cecho("<red>No profitable commodities found<reset>\n")
            end
            mc:cecho("<white>==========================================<reset>\n")
            mc:cecho("<dim_grey>Click the commodity name to load full cartel prices.<reset>\n")
        end)
        setStatus(string.format(
            "<span style='font-size:9px;color:#8896c0;padding-left:6px;'>Scan complete — best: %s</span>",
            ps.best or "none"))
        return
    end

    ps.data = {}
    F2T_PRICE_CHECKER.currentCommodity = commodity
    setStatus(string.format(
        "<span style='font-size:9px;color:#8896c0;padding-left:6px;'>Scanning %d/%d — %s</span>",
        ps.index, ps.totalCount, commodity))
    send("c price " .. commodity:lower() .. " cartel", false)
end

-- Called by the price_checker_profit_tick trigger on the blank line ending a cp burst.
function f2tPriceCheckerProfitTick()
    local ps = F2T_PRICE_CHECKER.profitSearch
    if not ps.active or #ps.data == 0 then return false end

    local bestBuy, bestSell = math.huge, -1
    for _, item in ipairs(ps.data) do
        if item.action == "selling" and item.price < bestBuy  then bestBuy  = item.price end
        if item.action == "buying"  and item.price > bestSell then bestSell = item.price end
    end
    local profit = (bestBuy ~= math.huge and bestSell ~= -1) and (bestSell - bestBuy) or -math.huge

    local commodity = F2T_PRICE_CHECKER.currentCommodity
    table.insert(ps.results, {
        commodity = commodity, profit = profit, bestBuy = bestBuy, bestSell = bestSell,
    })
    if profit > ps.bestProfit then
        ps.bestProfit = profit
        ps.best       = commodity
    end

    searchConsoles(function(mc)
        mc:cecho(string.format("<%s>%-20s: %+5dig/ton<reset>\n",
            profit > 0 and "green" or "red", commodity,
            profit ~= -math.huge and profit or 0))
    end)

    ps.data  = {}
    ps.index = ps.index + 1
    tempTimer(0.5, searchNext)
    return true
end

local function findBestProfit()
    if not f2t_check_tool_requirement(TOOL_REMOTE, "Best-profit scan", "Remote Price Check Service") then return end

    local ps = {
        active     = true,
        list       = {},
        index      = 1,
        results    = {},
        best       = nil,
        bestProfit = -math.huge,
        totalCount = 0,
        data       = {},
    }
    for _, c in ipairs(commodityList()) do
        table.insert(ps.list, c.name:lower())
    end
    table.sort(ps.list)
    ps.totalCount = #ps.list
    F2T_PRICE_CHECKER.profitSearch = ps

    if ps.totalCount == 0 then
        cecho("\n<red>[price checker]<reset> Commodity list unavailable\n")
        ps.active = false
        return
    end

    searchConsoles(function(mc)
        mc:clear()
        mc:show()
        mc:raise()
        mc:cecho(string.format("<yellow>Searching %d commodities for best profit...\n\n", ps.totalCount))
    end)
    pcall(enableTrigger, "price_checker_profit_tick")
    searchNext()
end

-- ── Check button ──────────────────────────────────────────────────────────────

function f2tPriceCheckerCheck()
    local modeSpec = currentModeSpec()
    if not modeSpec then
        cecho("\n<red>[price checker]<reset> No price-checking tools available — buy Remote Price Check Service from the brokers on Earth\n")
        return
    end
    if not f2t_check_tool_requirement(modeSpec.tool, "Price checking", modeSpec.label) then return end

    local target = modeSpec.isGroup and F2T_PRICE_CHECKER.selectedGroup or F2T_PRICE_CHECKER.selectedCommodity
    if not target then
        cecho(string.format("\n<red>[price checker]<reset> Select a %s first\n", modeSpec.isGroup and "commodity group" or "commodity"))
        return
    end

    local planet = ""
    if modeSpec.needsPlanet then
        for _, inst in pairs(instances) do
            if inst.planetInput then planet = inst.planetInput:getText() or "" break end
        end
        planet = planet:match("^%s*(.-)%s*$")
        if planet == "" then
            cecho("\n<red>[price checker]<reset> Enter a planet name first\n")
            return
        end
    end

    local cmd = modeSpec.command(target:lower(), planet:lower(), F2T_PRICE_CHECKER.premiumSide)

    if modeSpec.capturesRows then
        F2T_PRICE_CHECKER.currentCommodity = target:lower()
        F2T_PRICE_CHECKER.rows = {}
        refreshAllDebounced()
        for _, inst in pairs(instances) do
            if inst.searchConsole then inst.searchConsole:hide() end
        end
        setStatus(string.format(
            "<span style='font-size:9px;color:#8896c0;padding-left:6px;'>%s: %s</span>",
            modeSpec.label, target))
    else
        setStatus(string.format(
            "<span style='font-size:9px;color:#8896c0;padding-left:6px;'>%s sent — see console</span>",
            modeSpec.label))
    end

    send(cmd, false)
end

-- ── Commodity / group dropdown ─────────────────────────────────────────────────

local function toggleDropdown(inst, target)
    if inst.dropdown then
        inst.dropdown:hide()
        inst.dropdown = nil
        return
    end

    local modeSpec = currentModeSpec()
    inst.dropGen = (inst.dropGen or 0) + 1
    local gen  = inst.dropGen
    local list = pickerList(modeSpec)
    local rowH = 22
    local ddH  = math.min(#list * rowH, math.max(80, target.content:get_height() - H_MODE - H_BAR - 4))

    local dd = Geyser.Container:new({
        name = string.format("%s_pcddd_%d", target._gid, gen),
        x = 4, y = H_MODE + H_BAR, width = 190, height = ddH,
    }, target.content)

    local bg = Geyser.Label:new({
        name = string.format("%s_pcdddbg_%d", target._gid, gen),
        x = 0, y = 0, width = "100%", height = "100%",
    }, dd)
    bg:setStyleSheet([[
        background-color: rgba(20, 22, 32, 250);
        border: 1px solid rgba(100, 100, 110, 200);
        border-radius: 3px;
    ]])

    local sbx = Geyser.ScrollBox:new({
        name = string.format("%s_pcdddsb_%d", target._gid, gen),
        x = 1, y = 1, width = "100%-2px", height = "100%-2px",
    }, dd)

    for i, item in ipairs(list) do
        local lbl = Geyser.Label:new({
            name = string.format("%s_pcdddi_%d_%d", target._gid, gen, i),
            x = 0, y = (i - 1) * rowH, width = "100%-17px", height = rowH,
        }, sbx)
        lbl:setStyleSheet(_BTN_CSS)
        lbl:echo("<center>" .. item.name .. (item.basePrice and (" (" .. item.basePrice .. ")") or "") .. "</center>")
        local name = item.name
        lbl:setClickCallback(function()
            local ms = currentModeSpec()
            if ms and ms.isGroup then
                F2T_PRICE_CHECKER.selectedGroup = name
            else
                F2T_PRICE_CHECKER.selectedCommodity = name
            end
            updateAllModeContext()
            if inst.dropdown then inst.dropdown:hide(); inst.dropdown = nil end
        end)
    end

    dd:show()
    dd:raise()
    inst.dropdown = dd
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
        f2tTableSetData(instances[gid].tableId, F2T_PRICE_CHECKER.rows)
        updateModePills(instances[gid])
        updateModeContext(instances[gid])
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_pc_%d", gid, wc)
    end

    -- ── Mode-selector row ─────────────────────────────────────────────────────
    local modeBar = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = H_MODE,
    }, target.content)
    modeBar:setStyleSheet([[
        background-color: rgba(15, 18, 30, 200);
        border: none;
        border-bottom: 1px solid rgba(70, 75, 110, 150);
    ]])

    local pillRow = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%-94px", height = H_MODE,
    }, modeBar)
    pillRow:setStyleSheet("background: transparent; border: none;")

    local modePills = {}
    for _, m in ipairs(MODES) do
        local pill = Geyser.Label:new({
            name = wid(), x = 0, y = 2, width = "20%", height = H_MODE - 4,
        }, pillRow)
        pill:setStyleSheet(_BTN_CSS)
        pill:echo("<center>" .. m.label .. "</center>")
        pill:setToolTip(m.hint)
        local modeId = m.id
        pill:setClickCallback(function()
            if F2T_PRICE_CHECKER.mode == modeId then return end
            F2T_PRICE_CHECKER.mode = modeId
            for _, inst in pairs(instances) do
                if inst.dropdown then inst.dropdown:hide(); inst.dropdown = nil end
            end
            updateAllModeContext()
        end)
        modePills[m.id] = pill
    end

    local findBestBtn = Geyser.Label:new({
        name = wid(), x = "-90", y = 2, width = 86, height = H_MODE - 4,
    }, modeBar)
    findBestBtn:setStyleSheet(_BTN_CSS)
    findBestBtn:echo("<center>Find Best</center>")
    findBestBtn:setToolTip("Scan every commodity for the best cartel profit spread")
    findBestBtn:setClickCallback(function()
        if not F2T_PRICE_CHECKER.profitSearch.active then findBestProfit() end
    end)

    -- ── Commodity/group + context + Check row ────────────────────────────────
    local bar = Geyser.Label:new({
        name = wid(), x = 0, y = H_MODE, width = "100%", height = H_BAR,
    }, target.content)
    bar:setStyleSheet([[
        background-color: rgba(15, 18, 30, 200);
        border: none;
        border-bottom: 1px solid rgba(70, 75, 110, 150);
    ]])

    local dropBtn = Geyser.Label:new({
        name = wid(), x = 4, y = 3, width = "42%", height = H_BAR - 6,
    }, bar)
    dropBtn:setStyleSheet(_BTN_CSS)
    dropBtn:setToolTip("Select a commodity")

    local hintLbl = Geyser.Label:new({
        name = wid(), x = "44%", y = 3, width = "38%", height = H_BAR - 6,
    }, bar)
    hintLbl:setStyleSheet("background: transparent; border: none;")

    local planetInput = Geyser.CommandLine:new({
        name = wid(), x = "44%", y = 3, width = "38%", height = H_BAR - 6,
    }, bar)
    planetInput:setStyleSheet([[
        background-color: rgba(28,32,50,210); color: rgba(220,225,240,255);
        border: 1px solid rgba(72,85,128,180); border-radius: 3px; font-size: 10px;
    ]])
    planetInput:hide()

    local premiumRow = Geyser.Label:new({
        name = wid(), x = "44%", y = 3, width = "38%", height = H_BAR - 6,
    }, bar)
    premiumRow:setStyleSheet("background: transparent; border: none;")
    premiumRow:hide()

    local premiumPills = {}
    local premiumOrder = { "buy", "sell", "all" }
    for i, side in ipairs(premiumOrder) do
        local pill = Geyser.Label:new({
            name = wid(), x = ((i - 1) * 34) .. "%", y = 0, width = "33%", height = "100%",
        }, premiumRow)
        pill:setStyleSheet(_BTN_CSS)
        pill:echo("<center>" .. side:upper() .. "</center>")
        pill:setClickCallback(function()
            F2T_PRICE_CHECKER.premiumSide = side
            updatePremiumPills(instances[gid])
        end)
        premiumPills[side] = pill
    end

    local checkBtn = Geyser.Label:new({
        name = wid(), x = "83%", y = 3, width = "15%", height = H_BAR - 6,
    }, bar)
    checkBtn:setStyleSheet(_BTN_CSS)
    checkBtn:echo("<center>Check</center>")
    checkBtn:setToolTip("Send the price check")
    checkBtn:setClickCallback(function() f2tPriceCheckerCheck() end)
    planetInput:setAction(function() f2tPriceCheckerCheck() end)

    -- ── Status strip ──────────────────────────────────────────────────────────
    local status = Geyser.Label:new({
        name = wid(), x = 0, y = H_MODE + H_BAR, width = "100%", height = H_STAT,
    }, target.content)
    status:setStyleSheet([[
        background-color: rgba(12, 14, 24, 220);
        border: none;
        color: rgba(136, 150, 192, 255);
    ]])

    -- ── Column header bar ─────────────────────────────────────────────────────
    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = H_MODE + H_BAR + H_STAT, width = "100%", height = H_COL,
    }, target.content)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    -- ── ScrollBox table ───────────────────────────────────────────────────────
    local scrollTop = H_MODE + H_BAR + H_STAT + H_COL
    local scroll = Geyser.ScrollBox:new({
        name   = wid(),
        x = 0, y = scrollTop,
        width  = "100%",
        height = "100%-" .. scrollTop .. "px",
    }, target.content)

    local contentW = math.max(100, target.content:get_width() - SB_W)
    local contentLabel = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = contentW, height = 1000,
    }, scroll)
    contentLabel:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    -- Note shown instead of the table while in Commodity Group mode (output
    -- format unverified — prints to the console rather than being parsed).
    local groupNote = Geyser.Label:new({
        name = wid(), x = 0, y = scrollTop, width = "100%",
        height = "100%-" .. scrollTop .. "px",
    }, target.content)
    groupNote:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")
    groupNote:echo(
        "<div style='padding:10px;color:#8896c0;font-size:10px;'>" ..
        "Commodity Group output prints to the main console.</div>")
    groupNote:hide()

    -- Search console overlays the table area during a best-profit scan.
    local searchConsole = Geyser.MiniConsole:new({
        name = wid(), x = 0, y = scrollTop, width = "100%",
        height = "100%-" .. scrollTop .. "px", fontSize = 9,
    }, target.content)
    searchConsole:setColor(18, 18, 26)
    searchConsole:hide()

    local tableId = "price_checker_" .. gid
    local cols    = buildCols()
    f2tTableCreate(tableId, cols)
    f2tTableSetScrollbox(tableId, contentLabel, contentW, ROW_H, scroll)

    local colHdrs = {}
    local xPct    = 0
    for _, col in ipairs(cols) do
        local lbl = Geyser.Label:new({
            name  = wid(),
            x = xPct .. "%", y = 0,
            width = col.scrollbox_pct .. "%", height = "100%",
        }, colBar)
        lbl:setStyleSheet(_COL_HDR_CSS)
        lbl:echo(col.label)
        if col.sortable then
            local tid, key = tableId, col.key
            lbl:setClickCallback(function() f2tTableToggleSort(tid, key) end)
            lbl:setToolTip("Sort by " .. col.label)
        end
        colHdrs[col.key] = lbl
        xPct = xPct + col.scrollbox_pct
    end
    f2tTableSetColHdrs(tableId, colHdrs)

    local inst = {
        tableId       = tableId,
        dropBtn       = dropBtn,
        hintLbl       = hintLbl,
        planetInput   = planetInput,
        premiumRow    = premiumRow,
        premiumPills  = premiumPills,
        modePills     = modePills,
        findBestBtn   = findBestBtn,
        status        = status,
        colBar        = colBar,
        scroll        = scroll,
        contentLabel  = contentLabel,
        contentW      = contentW,
        groupNote     = groupNote,
        searchConsole = searchConsole,
        dropdown      = nil,
    }
    instances[gid] = inst

    dropBtn:setClickCallback(function() toggleDropdown(inst, target) end)

    updateModePills(inst)
    updateModeContext(inst)
    f2tTableSetData(tableId, F2T_PRICE_CHECKER.rows)
end

-- ── Content registration ──────────────────────────────────────────────────────

local function buildPriceCheckerDef()
    return {
        name        = "Price Checker",
        description = "Remote/cartel/premium price-check commands, gated by the tools you own.",
        group       = "Fed2 Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[price_checker] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            local inst = instances[target._gid]
            if inst then
                f2tTableDestroy(inst.tableId)
                instances[target._gid] = nil
            end
        end,
        resize = function(target)
            local inst = instances[target._gid]
            if not inst then return end
            local newCw = math.max(100, target.content:get_width() - SB_W)
            if newCw ~= inst.contentW then
                inst.contentW = newCw
                inst.contentLabel:resize(newCw, inst.contentLabel:get_height())
                f2tTableOnResize(inst.tableId, newCw)
            end
        end,
        serialize = function(_t)
            return {
                mode              = F2T_PRICE_CHECKER.mode,
                selectedCommodity = F2T_PRICE_CHECKER.selectedCommodity,
                selectedGroup     = F2T_PRICE_CHECKER.selectedGroup,
                premiumSide       = F2T_PRICE_CHECKER.premiumSide,
            }
        end,
        restore = function(_t, data)
            if type(data.mode) == "string" and modeById(data.mode) then
                F2T_PRICE_CHECKER.mode = data.mode
            end
            if type(data.selectedCommodity) == "string" then
                F2T_PRICE_CHECKER.selectedCommodity = data.selectedCommodity
            end
            if type(data.selectedGroup) == "string" then
                F2T_PRICE_CHECKER.selectedGroup = data.selectedGroup
            end
            if type(data.premiumSide) == "string" then
                F2T_PRICE_CHECKER.premiumSide = data.premiumSide
            end
            updateAllModeContext()
        end,
        onReveal = function(target)
            local inst = instances[target._gid]
            if inst then
                f2tTableSetData(inst.tableId, F2T_PRICE_CHECKER.rows)
                updateModePills(inst)
                updateModeContext(inst)
            end
        end,
    }
end

function f2tRegisterPriceChecker()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[price_checker] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_price_checker", buildPriceCheckerDef())
    -- Package (re)install re-enables all triggers; the profit-tick trigger is a
    -- catch-all blank-line pattern, so park it unless a scan is actually running.
    if not (F2T_PRICE_CHECKER.profitSearch and F2T_PRICE_CHECKER.profitSearch.active) then
        pcall(disableTrigger, "price_checker_profit_tick")
    end
    if f2t_debug_log then f2t_debug_log("[price_checker] registered fed2_price_checker content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterPriceChecker)

-- Tool ownership can change mid-session (buying the upgrade / premium ticker
-- at the brokers) — re-render mode pills/context so a newly-bought mode
-- appears without needing to reopen the pane.
registerAnonymousEventHandler("gmcp.char.vitals", updateAllModeContext)

if f2t_debug_log then f2t_debug_log("[price_checker] module loaded") end
