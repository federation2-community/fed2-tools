-- fed2-tools — Galaxy Navigator
--
-- Data comes from the in-game "di systems" command — a full listing of every
-- cartel, system, and planet — NOT the Mudlet map DB. This matters because a
-- player's map may be incomplete, whereas "di systems" is always authoritative.
-- The capture/parse mirrors the v1 archive's ui_galaxy module.
--
-- Three pieces, registered with Muxlet from init.lua's muxletReady handler via
-- f2tRegisterGalaxy():
--
--   1. A background "di systems" scrape, run at load (once connected) and on
--      (re)connect / character change. Output lines are captured and deleted by
--      two triggers, so nothing spams the main console. Because the index is
--      pre-built in the background, opening the navigator is instant.
--
--   2. A "fed2_galaxy" Muxlet content type rendering the cartel → system →
--      planet tree in a scrollable console (expand/collapse, click a name for
--      "di" info, click → to navigate). It can be added to any pane/tab from the
--      Content Library like any other content.
--
--   3. A "fed2.galaxy.toggle" action that surfaces/hides a dedicated floating
--      navigator pane (titlebar hidden, not zoomable/resizable/convertible,
--      movable, closeable). Re-showing snaps it back to a known location; the ✕
--      closes it and the next toggle recreates it in the same spot. The action
--      appears in the button editor's Action dropdown, so a Button Grid button
--      can be bound to it.

-- ── Data store ───────────────────────────────────────────────────────────────
-- cartels[cartel] = { name, systems = { [sys] = { name, cartel, planets = { {name,system,cartel}, ... } } } }
F2T_GALAXY = F2T_GALAXY or {
    cartels        = {},
    loaded         = false,
    loading        = false,
    builtAt        = 0,        -- unix time of last successful scrape
    capture_active = false,
    capture_lines  = {},
    expanded       = {},       -- [key]=true; session-only expand state
}

-- Where the navigator snaps to when shown. Two modes, combinable per-axis:
--   • Absolute: set x / y (nil → sensible top-right default).
--   • Relative (anchored to other panes, so it tracks layout changes):
--       anchorRight = "<pane id>"  → my RIGHT edge sits flush on that pane's LEFT edge
--       anchorTop   = "<pane id>"  → my TOP edge sits flush under that pane's BOTTOM edge
--     When an anchor pane is missing (closed / relaid-out) that axis falls back to
--     the absolute value. Read pane ids/coords from any pane's Properties dialog.
F2T_GALAXY_NAV = F2T_GALAXY_NAV or {
    x = nil, y = nil, w = 440, h = 560,
    anchorRight = nil, anchorTop = nil,
}

-- ── "di systems" capture (mirrors the v1 archive methodology) ──────────────────

local captureTimer = nil
local function cancelCaptureTimeout()
    if captureTimer then killTimer(captureTimer); captureTimer = nil end
end

-- Send "di systems" and begin capturing. Safe to call repeatedly; the loading
-- guard prevents overlap. Bails when offline (the command needs the game).
function f2t_galaxy_scrape()
    if F2T_GALAXY.loading then return end
    if F2T_CONNECTED == false then
        f2t_debug_log("[galaxy] scrape skipped (offline)")
        return
    end
    F2T_GALAXY.loading        = true
    F2T_GALAXY.capture_active = true
    F2T_GALAXY.capture_lines  = {}
    f2t_galaxy_refresh_open()              -- show the loading state in any open navigator
    sendAll("di systems", false)           -- false = don't echo the command; triggers delete the output
    cancelCaptureTimeout()
    captureTimer = tempTimer(8, function()  -- safety net if no terminating blank line arrives
        captureTimer = nil
        if F2T_GALAXY.capture_active then f2t_galaxy_finish_capture() end
    end)
end

-- Called by the galaxy_nav_line trigger for every line while capture is active.
-- Buffers system lines and folds wrapped continuation lines into the previous one.
function f2t_galaxy_capture_line(line)
    if not F2T_GALAXY.capture_active then return end
    line = (line or ""):match("^%s*(.-)%s*$")
    if line == "" then return end
    if line:match(" %- .+ cartel %- ") then
        table.insert(F2T_GALAXY.capture_lines, line)
    elseif #F2T_GALAXY.capture_lines > 0 then
        local n = #F2T_GALAXY.capture_lines
        F2T_GALAXY.capture_lines[n] = F2T_GALAXY.capture_lines[n] .. " " .. line
    end
    -- Lines matching neither (command echo, stray text) are ignored.
end

-- Parse one combined system line into its components.
-- Format: "SystemName - CartelName cartel - Rank Owner[tag]: Planet(T) Planet(T) ..."
local function parseSystemLine(line)
    local system_name, cartel_name, planet_str =
        line:match("^(.+) %- (.+) cartel %- [^:]+: (.*)$")
    if not system_name then return nil end
    system_name = system_name:match("^%s*(.-)%s*$")
    cartel_name = cartel_name:match("^%s*(.-)%s*$")

    local planets = {}
    -- "Planet Name(T)" where T is the planet type tag in parentheses.
    for planet_name in (planet_str or ""):gmatch("(.-)%([^%)]+%)%s*") do
        planet_name = planet_name:match("^%s*(.-)%s*$")
        if planet_name ~= "" then
            planets[#planets + 1] = { name = planet_name, system = system_name, cartel = cartel_name }
        end
    end
    return system_name, cartel_name, planets
end

-- Called by the galaxy_nav_end trigger on the terminating blank line.
function f2t_galaxy_finish_capture()
    if not F2T_GALAXY.capture_active then return end
    F2T_GALAXY.capture_active = false
    cancelCaptureTimeout()

    if #F2T_GALAXY.capture_lines == 0 then
        F2T_GALAXY.loading = false
        f2t_galaxy_refresh_open()
        return
    end

    local cartels = {}
    for _, line in ipairs(F2T_GALAXY.capture_lines) do
        local sys, cart, planets = parseSystemLine(line)
        if sys and cart then
            cartels[cart] = cartels[cart] or { name = cart, systems = {} }
            cartels[cart].systems[sys] = { name = sys, cartel = cart, planets = planets }
        end
    end

    F2T_GALAXY.cartels = cartels
    F2T_GALAXY.loading = false
    F2T_GALAXY.loaded  = true
    F2T_GALAXY.builtAt = os.time()

    local nc = 0; for _ in pairs(cartels) do nc = nc + 1 end
    f2t_debug_log("[galaxy] di systems → %d cartels", nc)
    raiseEvent("f2tGalaxyIndexed", nc)
    f2t_galaxy_refresh_open()
end

-- Debounced scheduler so neither load nor reconnect fires multiple scrapes.
local scrapeTimer = nil
function f2t_galaxy_schedule_scrape(delay)
    if scrapeTimer then killTimer(scrapeTimer); scrapeTimer = nil end
    scrapeTimer = tempTimer(delay or 3, function()
        scrapeTimer = nil
        local ok, err = pcall(f2t_galaxy_scrape)
        if not ok then f2t_debug_log("[galaxy] scrape error: %s", tostring(err)) end
    end)
end

-- ── Navigation / info ────────────────────────────────────────────────────────

function f2t_galaxy_nav_to(kind, name)
    expandAlias("nav " .. name)          -- routes via the fed2-tools nav alias
    f2t_galaxy_hide_nav()                -- tidy away the dedicated navigator after picking
end

local function galaxyInfo(kind, name)
    send("di " .. kind .. " " .. name)   -- cartel / system / planet detail to the main console
end

-- ── Rendering ──────────────────────────────────────────────────────────────────
-- One MiniConsole per content target, keyed by the pane/tab's stable _gid.
local consoles = {}

local function ageStr(ts)
    if not ts or ts == 0 then return "never" end
    local age = os.time() - ts
    if age < 60        then return "just now"
    elseif age < 3600  then return string.format("%dm ago", math.floor(age / 60))
    elseif age < 86400 then return string.format("%dh ago", math.floor(age / 3600))
    else                    return string.format("%dd ago", math.floor(age / 86400)) end
end

local function renderConsole(mc)
    if not mc then return end
    mc:clear()
    local g = F2T_GALAXY

    if F2T_CONNECTED == false then
        mc:cecho("<yellow>○ Offline<reset> <dim_grey>— showing last scrape<reset>\n")
    end

    if g.loading then
        mc:cecho("\n<yellow>Loading galaxy data…<reset>  <dim_grey>(di systems)<reset>\n")
        return
    end

    if not g.loaded or not g.cartels or next(g.cartels) == nil then
        mc:cecho("\n<dim_grey>No galaxy data yet.<reset>\n\n")
        mc:echoLink("⟳ Load from 'di systems'", function() f2t_galaxy_scrape() end,
            "Run di systems and build the navigator", true)
        mc:cecho("\n")
        return
    end

    -- Header: age + refresh + collapse-all
    mc:cecho(string.format("<cyan>🔭 Galaxy<reset>  <dim_grey>%s<reset>   ", ageStr(g.builtAt)))
    mc:echoLink("⟳", function() f2t_galaxy_scrape() end, "Refresh (di systems)", true)
    mc:cecho("  ")
    mc:echoLink("⊟", function() g.expanded = {}; f2t_galaxy_refresh_open() end, "Collapse all", true)
    mc:cecho("\n<dim_grey>Click a name for info · click → to navigate<reset>\n\n")

    -- Current location (for a ▶ marker)
    local ri         = gmcp and gmcp.room and gmcp.room.info
    local cur_cartel = ri and ri.cartel or ""
    local cur_system = ri and ri.system or ""
    local cur_area   = ri and ri.area   or ""

    local cnames = {}
    for cn in pairs(g.cartels) do cnames[#cnames + 1] = cn end
    table.sort(cnames)

    for _, cn in ipairs(cnames) do
        local cd   = g.cartels[cn]
        local cexp = g.expanded[cn] or false
        mc:echoLink(cexp and "−" or "+",
            function() g.expanded[cn] = not g.expanded[cn]; f2t_galaxy_refresh_open() end,
            "Expand / collapse", true)
        mc:cecho(" 🌌 ")
        mc:echoLink(cn, function() galaxyInfo("cartel", cn) end, "di cartel " .. cn, true)
        mc:cecho("\n")

        if cexp then
            local snames = {}
            for sn in pairs(cd.systems) do snames[#snames + 1] = sn end
            table.sort(snames)

            for _, sn in ipairs(snames) do
                local sd   = cd.systems[sn]
                local skey = cn .. ":" .. sn
                local sexp = g.expanded[skey] or false
                local here = (sn == cur_system and cn == cur_cartel)
                mc:cecho("   ")
                mc:echoLink(sexp and "−" or "+",
                    function() g.expanded[skey] = not g.expanded[skey]; f2t_galaxy_refresh_open() end,
                    "Expand / collapse", true)
                mc:cecho(here and " ⭐<yellow>▶<reset> " or " ⭐ ")
                mc:echoLink(sn, function() galaxyInfo("system", sn) end, "di system " .. sn, true)
                mc:cecho("  ")
                mc:echoLink("→", function() f2t_galaxy_nav_to("system", sn) end, "Navigate to " .. sn, true)
                mc:cecho("\n")

                if sexp then
                    if #sd.planets == 0 then
                        mc:cecho("      <dim_grey>· space only<reset>\n")
                    else
                        for _, pd in ipairs(sd.planets) do
                            local phere = (pd.name == cur_area and sn == cur_system)
                            mc:cecho(phere and "      🌍<yellow>▶<reset> " or "      🌍 ")
                            mc:echoLink(pd.name, function() galaxyInfo("planet", pd.name) end,
                                "di planet " .. pd.name, true)
                            mc:cecho("  ")
                            mc:echoLink("→", function() f2t_galaxy_nav_to("planet", pd.name) end,
                                "Navigate to " .. pd.name, true)
                            mc:cecho("\n")
                        end
                    end
                end
            end
        end
    end
end

-- Re-render every open navigator (after a scrape or a connection change).
function f2t_galaxy_refresh_open()
    for _, mc in pairs(consoles) do pcall(renderConsole, mc) end
end

-- ── Content type ────────────────────────────────────────────────────────────────
local function buildGalaxyDef()
    return {
        name        = "Galaxy Navigator",
        description = "Browse every cartel, system, and planet from 'di systems'; click → to travel.",
        singleton   = false,

        apply = function(target)
            if target.contentBg then
                target.contentBg:echo("")
                target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
            end
            local mc = consoles[target._gid]
            if not mc then
                mc = Geyser.MiniConsole:new({
                    name = target._gid .. "_galaxymc", x = 0, y = 0, width = "100%", height = "100%",
                    scrollBar = true, fontSize = 9,
                }, target.content)
                mc:setColor(18, 18, 26)
                mc:enableScrollBar()
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

        resize = function(target)
            renderConsole(consoles[target._gid])   -- %-sized console tracks the parent; re-render keeps wrap sane
        end,

        serialize = function(_target) return {} end,     -- data is global; nothing per-instance
        restore   = function(_target, _data) end,
        onReveal  = function(target) renderConsole(consoles[target._gid]) end,
    }
end

-- ── Toggle action + dedicated navigator pane ─────────────────────────────────────
local navPaneId  = nil
local navVisible = false

local function currentNavPane()
    if not navPaneId then return nil end
    local p = Mux.getPane and Mux.getPane(navPaneId) or nil
    if not p then navPaneId = nil end          -- it was closed via ✕
    return p
end

-- Absolute navigator geometry (used when not anchored). x/y nil → top-right default.
local function navGeom()
    local sw, sh = getMainWindowSize()
    local W = F2T_GALAXY_NAV.w or 440
    local H = F2T_GALAXY_NAV.h or 560
    local X = F2T_GALAXY_NAV.x or (sw - W - 30)
    local Y = F2T_GALAXY_NAV.y or 80
    X = math.max(0, math.min(X, math.max(0, sw - W)))
    Y = math.max(0, math.min(Y, math.max(0, sh - H)))
    return X, Y, W, H
end

local function snapTo(p)
    local X, Y, W, H = navGeom()
    p.floatX, p.floatY, p.floatW, p.floatH = X, Y, W, H
    if p.outer then p.outer:move(X, Y); p.outer:resize(W, H) end
    if p._notifyReposition then p:_notifyReposition() end
end

-- Position the navigator. Priority: a configured anchor (built from the pane
-- ids in F2T_GALAXY_NAV and handed to Muxlet, which then tracks layout changes
-- natively — no poll); else any anchor already on the pane (e.g. set graphically
-- and persisted in the workspace), re-applied; else absolute placement. With
-- both ids set it's a corner anchor (right edge to one pane, top to another).
local function placeNav(p)
    if F2T_GALAXY_NAV.anchorRight or F2T_GALAXY_NAV.anchorTop then
        local A = {}
        if F2T_GALAXY_NAV.anchorRight then
            A.v = { ref = F2T_GALAXY_NAV.anchorRight, targetEdge = "left", myEdge = "right" }
        end
        if F2T_GALAXY_NAV.anchorTop then
            A.h = { ref = F2T_GALAXY_NAV.anchorTop, targetEdge = "bottom", myEdge = "top" }
        end
        if not A.v then A.alongH = 0 end
        if not A.h then A.alongV = 0 end
        if p.setAnchor and p:setAnchor(A) then return end
    end
    if p.anchor and p.returnToAnchor and p:returnToAnchor() then return end
    snapTo(p)
end

-- Hide the dedicated navigator pane if it's showing (used after navigating).
function f2t_galaxy_hide_nav()
    local p = currentNavPane()
    if p and navVisible then
        p:hide(); navVisible = false
    end
end

function f2t_galaxy_toggle()
    if not (Mux and Mux.newFloatingPane and Mux._applyContent) then
        cecho("\n<red>[fed2-tools]<reset> Muxlet is not started. Run <cyan>mux start<reset> first.\n")
        return
    end

    local p = currentNavPane()
    if p then
        if navVisible then
            p:hide(); navVisible = false
        else
            p:show()
            placeNav(p)                          -- return to anchor (or absolute) on every show
            if Mux.raisePane then Mux.raisePane(p) end
            navVisible = true
            f2t_galaxy_refresh_open()
        end
        return
    end

    -- Fresh navigator. anchorable so it can also be anchored graphically (drag
    -- in anchor mode); convertible stays false so it never embeds.
    local X, Y, W, H = navGeom()
    p = Mux.newFloatingPane({
        name             = "Galaxy",
        showTitlebar     = false,
        titlebarHideable = false,
        zoomable         = false,
        resizable        = false,
        convertible      = false,
        anchorable       = true,
        movable          = true,
        closeable        = true,
        minimizable      = false,
        splittable       = false,
        swappable        = false,
        floatX = X, floatY = Y, floatW = W, floatH = H,
        onClose = function() navPaneId = nil; navVisible = false end,
    })
    if not p then return end
    navPaneId  = p.id
    navVisible = true
    Mux._applyContent(p, "fed2_galaxy")
    placeNav(p)
    if Mux.raisePane then Mux.raisePane(p) end
end

-- ── Registration (called from init.lua muxletReady) ──────────────────────────────
function f2tRegisterGalaxy()
    if not (Mux and Mux.registerContent and Mux.registerAction) then return end
    Mux.registerContent("fed2_galaxy", buildGalaxyDef())
    Mux.registerAction("fed2.galaxy.toggle", {
        name  = "Toggle Galaxy Navigator",
        group = "fed2-tools",
        desc  = "Show or hide the galaxy navigator pane (snaps to a fixed location).",
        icon  = "🌌",
        run   = function() f2t_galaxy_toggle() end,
    })
    -- Background scrape now if already connected; otherwise the connect handler does it.
    if F2T_CONNECTED ~= false then f2t_galaxy_schedule_scrape(3) end
    f2t_debug_log("[galaxy] registered content + action")
end

-- ── Connection awareness ─────────────────────────────────────────────────────────
-- Scrape in the background on (re)connect and on character switch; refresh any
-- open navigator immediately so the offline/online banner stays accurate.
registerAnonymousEventHandler("sysConnectionEvent", function()
    if f2t_check_connection then f2t_check_connection() end
    if F2T_CONNECTED then f2t_galaxy_schedule_scrape(3) end
    f2t_galaxy_refresh_open()
end)

registerAnonymousEventHandler("f2tCharacterChanged", function()
    f2t_galaxy_schedule_scrape(3)
end)

f2t_debug_log("[galaxy] module loaded")