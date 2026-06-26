-- fed2-tools — Bootstrap and initialization
--
-- Owns the Muxlet lifecycle: version-checks the installed Muxlet against the
-- build-declared requirement, installs or upgrades from GitHub if needed, then
-- drives initialization via Muxlet's muxletReady event.
--
-- On first run, muxletReady shows the mode-selection dialog (ui/popups.lua).
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

-- ── Version utilities ─────────────────────────────────────────────────────────

local function versionIsNewer(v1, v2)
    if not v1 or not v2 then return false end
    local function parts(v)
        local a, b, c = v:gsub("^v", ""):match("^(%d+)%.?(%d*)%.?(%d*)")
        return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
    end
    local a1, b1, c1 = parts(v1)
    local a2, b2, c2 = parts(v2)
    if a1 ~= a2 then return a1 > a2 end
    if b1 ~= b2 then return b1 > b2 end
    return c1 > c2
end

-- Returns true when the installed Muxlet meets F2T_REQUIRED_MUXLET.
local function muxletSatisfied()
    if not table.contains(getPackages(), MUXLET_PKG) then return false end
    if not F2T_REQUIRED_MUXLET then return true end
    local installed = Mux and Mux._version
    -- "unknown" means Muxlet loaded but couldn't read its own version; treat as ok
    -- rather than trigger a redundant reinstall.
    if not installed or installed == "unknown" then return true end
    return not versionIsNewer(F2T_REQUIRED_MUXLET, installed)
end


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

-- ── Muxlet install / upgrade ──────────────────────────────────────────────────

local function installMuxlet()
    if not MUXLET_URL then
        cecho("\n<red>[fed2-tools]<reset> Cannot install Muxlet: build is missing MUXLET_URL injection. Reinstall fed2-tools from MPR.\n")
        return
    end

    local ver = F2T_REQUIRED_MUXLET and (" " .. F2T_REQUIRED_MUXLET) or ""

    local function doInstall()
        f2t_debug_log("Installing Muxlet%s", ver)
        -- muxletReady fires when Muxlet loads (Muxlet's settings.lua raises it via
        -- tempTimer(0)), so the existing muxletReady handler at the bottom of this
        -- file drives f2tInit after both fresh and mid-session installs.
        installPackage(MUXLET_URL)
    end

    if table.contains(getPackages(), MUXLET_PKG) then
        -- Uninstall the wrong version first; install the required version only
        -- after the uninstall completes so there is never a partial state.
        local uninstallId
        uninstallId = registerAnonymousEventHandler("sysUninstallPackage", function(_, name)
            if name ~= MUXLET_PKG then return end
            killAnonymousEventHandler(uninstallId)
            tempTimer(0.5, doInstall)
        end)
        f2t_debug_log("Removing existing Muxlet (need%s)", ver)
        uninstallPackage(MUXLET_PKG)
    else
        doInstall()
    end
end

-- ── Dev reload watcher ────────────────────────────────────────────────────────
-- Active only when a stamp file exists in the profile directory, which the
-- build script writes on every local deploy.  Production installs never have
-- this file so the watcher never activates for end users.

local function startDevReloadWatcher()
    local function parentDir(path)
        return path:match("^(.+)[/\\][^/\\]*$") or path
    end

    local profileDir = parentDir(getMudletHomeDir())
    local stampPath  = profileDir .. "/fed2-tools-rebuild.stamp"
    local pkgPath    = profileDir .. "/fed2-tools.mpackage"

    local f = io.open(stampPath, "r")
    if not f then return end
    local lastStamp = f:read("*a"):match("^%d+") or ""
    f:close()

    local function poll()
        local f2 = io.open(stampPath, "r")
        if not f2 then return end
        local stamp = f2:read("*a"):match("^%d+") or ""
        f2:close()

        if stamp ~= lastStamp then
            lastStamp = stamp
            cecho("\n<yellow>[fed2-tools]<reset> Build updated — reloading...\n")
            installPackage(pkgPath)
        else
            tempTimer(5, poll)
        end
    end

    tempTimer(5, poll)
    cecho("\n<cyan>[fed2-tools]<reset> Dev reload watcher active (polling every 5s).\n")
end

-- ── Initialization ────────────────────────────────────────────────────────────
-- All fed2-tools setup is driven by Muxlet's muxletReady event so there is no
-- timing guesswork.  The handler is registered synchronously so it is always
-- in place before any timer fires.
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

function f2tInit()
    if not muxletSatisfied() then return end

    -- fed2-tools owns the Muxlet version pin; prevent Muxlet auto-upgrading.
    Mux.settings.set("mux", "update_check_enabled", false)

    -- Suppress Muxlet's standalone welcome; fed2-tools provides its own onboarding.
    Mux.settings.set("mux", "welcome_shown", true)

    -- Suppress Muxlet's "Started" message; fed2-tools manages its own startup output.
    Mux.settings.set("mux", "quietStart", true)

    -- fed2-tools exclusively controls when Muxlet starts; disable Muxlet's own
    -- auto_start so its 1.5s timer never fires Mux.fullStart() independently.
    Mux.settings.set("mux", "auto_start", false)

    if f2t_settings_flush_registrations then f2t_settings_flush_registrations() end
    if f2tRegisterMapContent            then f2tRegisterMapContent()            end
    if f2tRegisterWho                   then f2tRegisterWho()                   end
    if f2tRegisterGalaxy                then f2tRegisterGalaxy()                end
    if f2tRegisterPlayerInfo            then f2tRegisterPlayerInfo()            end
    if f2tRegisterCargo                 then f2tRegisterCargo()                 end
    if f2tRegisterMapperCss             then f2tRegisterMapperCss()             end

    local d               = Mux.settings._data
    local autostart       = d and d["f2t"] and d["f2t"]["mux_autostart"]
    local alreadyLoggedIn = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name

    local function afterLogin()
        if autostart == nil then
            if f2tShowModeSelect then f2tShowModeSelect() end
        elseif autostart == true then
            Mux.fullStart()
        end
        -- autostart == false: Minimal mode — Muxlet is available but not started.
    end

    if alreadyLoggedIn then
        afterLogin()
    else
        local _loginId
        _loginId = registerAnonymousEventHandler("gmcp.char.vitals", function()
            killAnonymousEventHandler(_loginId)
            afterLogin()
        end)
    end
end

registerAnonymousEventHandler("muxletReady", f2tInit)

-- ── Boot ──────────────────────────────────────────────────────────────────────

startDevReloadWatcher()

if not muxletSatisfied() then
    local installed = Mux and Mux._version
    local reason = installed
        and string.format("version mismatch (installed=%s, required=%s)", installed, tostring(F2T_REQUIRED_MUXLET))
        or  string.format("not installed (required=%s)", tostring(F2T_REQUIRED_MUXLET))
    f2t_debug_log("Muxlet install queued: %s", reason)

    local alreadyLoggedIn = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if alreadyLoggedIn then
        installMuxlet()
    else
        local _waitId
        _waitId = registerAnonymousEventHandler("gmcp.char.vitals", function()
            killAnonymousEventHandler(_waitId)
            installMuxlet()
        end)
    end
end
