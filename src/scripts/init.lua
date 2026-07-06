-- fed2-tools — Bootstrap and initialization
--
-- Installs/upgrades Muxlet via Mux.ensureVersion (see Muxlet's README,
-- "Bootstrapping from your own package") and drives our own initialization
-- from its callback.
--
-- On first run, that init shows the mode-selection dialog (ui/popups.lua).
-- The user's choice persists as mux_autostart in Mux.settings and governs all
-- future sessions — no further dialog appears.
--
--   mux_autostart = true  → Mux.fullStart() called automatically each session
--   mux_autostart = false → Muxlet is installed but never auto-started (Minimal)
--
-- Two values are injected by the build script (never edit manually):
--   F2T_REQUIRED_MUXLET — minimum Muxlet version this build needs
--   MUXLET_URL          — GitHub release URL to install/upgrade from
--
-- Dev builds point MUXLET_URL at the prerelease tag (no "v" prefix).
-- Production builds point at the production tag ("v" prefix).

local MUXLET_PKG = "Muxlet"

-- build-injected: minimum Muxlet version required by this fed2-tools build
local F2T_REQUIRED_MUXLET = nil
-- build-injected: GitHub release URL (bare tag = prerelease; v-tag = production)
local MUXLET_URL = nil

-- ── generic_mapper removal ────────────────────────────────────────────────────
-- generic_mapper conflicts with the fed2-tools map system; remove it silently.
if table.contains(getPackages(), "generic_mapper") then
    f2t_debug_log("Removing incompatible package: generic_mapper")
    uninstallPackage("generic_mapper")
end

-- ── Install handler ───────────────────────────────────────────────────────────
-- sysInstall fires during installation only, not on normal session start.
registerAnonymousEventHandler("sysInstall", function(_, pkg)
    if pkg ~= "fed2-tools" then return end

    -- Apply preferred mapper defaults only on the very first install so user
    -- customisations are never overwritten on upgrade.
    local firstInstall = not (Mux and Mux._workspaces and Mux._workspaces["current"])
    if firstInstall then
        tempTimer(3, function()
            local ok = setConfig({
                mapExitSize        = 10,
                mapRoomSize        = 5,
                mapRoundRooms      = false,
                mapShowGrid        = false,
                mapShowRoomBorders = false,
            })
            if ok then updateMap() end
        end)
    end
end)

-- ── Login gating ──────────────────────────────────────────────────────────────
-- Disruptive actions (installing/reinstalling a package, showing dialogs,
-- auto-starting Muxlet) are deferred until after gmcp.char.vitals fires, so
-- they never land mid-login-prompt.
local function afterLogin(fn)
    if gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name then
        fn()
        return
    end
    local waitId
    waitId = registerAnonymousEventHandler("gmcp.char.vitals", function()
        killAnonymousEventHandler(waitId)
        fn()
    end)
end

-- True when the currently loaded Muxlet already meets F2T_REQUIRED_MUXLET.
-- Reuses Muxlet's own comparator rather than re-parsing versions here; only
-- exists so the boot sequence below can decide whether it needs to gate on
-- login before calling Mux.ensureVersion (which does the actual, possibly
-- disruptive, upgrade).
local function versionSatisfied()
    if not (Mux and Mux._version) then return false end
    if Mux._version == "unknown" then return true end
    return not Mux._versionIsNewer(F2T_REQUIRED_MUXLET, Mux._version)
end

-- ── Initialization ────────────────────────────────────────────────────────────
--
-- Content is registered every session regardless of mode so it is available
-- for manual use.
--
-- mux_autostart drives whether Muxlet actually starts:
--   nil   → first run; show mode-selection dialog (ui/popups.lua)
--   true  → auto-start (Full or BYOW choice from first run)
--   false → minimal; Muxlet stays idle until user runs mux start
--
-- fed2-tools suppresses Muxlet's own welcome popup (mux.welcome_shown = true)
-- because it provides its own onboarding via f2tShowModeSelect().  It also
-- prevents Muxlet's auto_start timer from double-starting by owning fullStart().

-- Loops F2T_CONTENT_REGISTRARS. Also called by devmode.lua after a live
-- reload — Mux.registerContent() overwrites by name, safe to call repeatedly.
function f2tRegisterAllContent()
    for _, registrar in ipairs(F2T_CONTENT_REGISTRARS or {}) do
        local ok, err = pcall(registrar)
        if not ok then
            f2t_debug_log("[init] content registrar error: %s", tostring(err))
        end
    end
end

-- Callback passed to Mux.ensureVersion; runs once a satisfying Muxlet is
-- loaded and ready. Settings/content register immediately (so Muxlet's own
-- welcome/autostart timers are suppressed before they can fire); only the
-- mode-select/fullStart decision waits for login.
function f2tInit()
    -- defaultWorkspace is intentionally not set here: it depends on which mode
    -- the user picks (full vs BYOW), so f2tShowModeSelect owns it, set once
    -- at choice time — not re-asserted every session, which would silently
    -- fight a BYOW user's choice of Muxlet's blank "default" workspace.
    Mux.configureHost({
        suppressWelcome = true,   -- fed2-tools shows its own onboarding (f2tShowModeSelect)
        autoStart       = false,  -- fed2-tools exclusively decides when Mux.fullStart() runs
        quietStart      = true,   -- fed2-tools prints its own startup output
        checkForUpdates = false,  -- fed2-tools owns the Muxlet version pin
    })

    if f2t_settings_flush_registrations then f2t_settings_flush_registrations() end

    f2tRegisterAllContent()

    afterLogin(function()
        local d         = Mux.settings._data
        local autostart = d and d["f2t"] and d["f2t"]["mux_autostart"]

        if autostart == nil then
            if f2tShowModeSelect then f2tShowModeSelect() end
        elseif autostart == true then
            Mux.fullStart()
        end
        -- autostart == false: Minimal mode — Muxlet is available but not started.
    end)
end

-- ── Boot ──────────────────────────────────────────────────────────────────────
-- Registered unconditionally so it's in place for every muxletReady this
-- session, whether that's Muxlet's first load or a reload triggered below.
local function onMuxletReady()
    if versionSatisfied() then
        f2tInit()
        return
    end
    -- Wrong (or missing) version: gate the reinstall on login so it can never
    -- land mid-login-prompt. Mux.ensureVersion handles the actual upgrade;
    -- its own fresh muxletReady re-invokes this handler once it's done.
    f2t_debug_log("Muxlet upgrade queued: installed=%s required=%s",
        tostring(Mux and Mux._version), tostring(F2T_REQUIRED_MUXLET))
    afterLogin(function()
        Mux.ensureVersion(F2T_REQUIRED_MUXLET, MUXLET_URL, f2tInit)
    end)
end

registerAnonymousEventHandler("muxletReady", onMuxletReady)

if Mux and Mux._ready then
    onMuxletReady()
elseif not table.contains(getPackages(), MUXLET_PKG) then
    if not MUXLET_URL then
        cecho("\n<red>[fed2-tools]<reset> Cannot install Muxlet: build is missing MUXLET_URL injection. Reinstall fed2-tools from MPR.\n")
    else
        f2t_debug_log("Muxlet install queued: not installed (required=%s)", tostring(F2T_REQUIRED_MUXLET))
        afterLogin(function() installPackage(MUXLET_URL) end)
    end
end
-- Otherwise Muxlet is installed but hasn't finished loading yet this
-- session — onMuxletReady above will fire naturally once it does.
