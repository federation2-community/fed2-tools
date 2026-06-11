-- fed2-tools — Bootstrap and initialization
--
-- Installs Muxlet if not present, then starts Muxlet with the fed2-tools
-- workspace. Sets auto_start = false so fed2-tools owns the startup sequence.
--
-- Also handles first-install mapper config (room sizes, grid) via sysInstall.

local MUXLET_PKG = "Muxlet"

-- Dev override: injected by build script when --muxlet-tag / -MuxletTag is
-- passed.  nil (the committed value) means install from the Mudlet Package
-- Repository.  Never edit this line manually — use the build script instead.
local MUXLET_DEV_URL = nil

-- ── generic_mapper removal ────────────────────────────────────────────────────
-- generic_mapper conflicts with the fed2-tools map system; remove it silently.
if table.contains(getPackages(), "generic_mapper") then
    cecho("\n<yellow>[fed2-tools]<reset> Removing incompatible package: generic_mapper\n")
    uninstallPackage("generic_mapper")
end

-- ── Install handler ──────────────────────────────────────────────────────────
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

-- ── Startup ───────────────────────────────────────────────────────────────────

local function startWorkspace()
    -- Flush any settings registrations that queued before Mux was available.
    if f2t_settings_flush_registrations then
        f2t_settings_flush_registrations()
    end

    -- Register content and workspace definition before fullStart so that
    -- activeContent in the workspace definition resolves in the deferred
    -- apply pass.  The "fed2-tools" workspace is always available in the
    -- workspace list regardless of whether the user has applied it.
    if f2tRegisterMapContent then f2tRegisterMapContent() end
    if f2tRegisterWorkspace  then f2tRegisterWorkspace()  end

    if Mux._running then
        -- Mid-session reinstall: Muxlet is already active.  Re-apply map content
        -- after a short delay so pane widget state is stable post-package-reload.
        tempTimer(0.5, function()
            local mapPane = Mux.getPane("map")
            if mapPane then Mux._applyContent(mapPane, "fed2_map") end
        end)
        tempTimer(0.8, function()
            if f2tCheckWelcome then f2tCheckWelcome() end
        end)
        return
    end

    -- fullStart() resolves: current (restored session) → default.
    -- On first install "current" doesn't exist so Muxlet loads "default", then
    -- the welcome dialog offers to apply the fed2-tools workspace.
    Mux.fullStart()
    tempTimer(0.8, function()
        if f2tCheckWelcome then f2tCheckWelcome() end
    end)
end

-- ── Muxlet installation ───────────────────────────────────────────────────────

local function installMuxlet()
    -- Keep the handler alive until Muxlet specifically completes; don't use
    -- oneShot=true because mpkg may fire sysInstallPackage for other packages
    -- (e.g. dependencies) before Muxlet itself finishes.
    local handlerId
    handlerId = registerAnonymousEventHandler("sysInstallPackage", function(_, name)
        if name ~= MUXLET_PKG then return end
        killAnonymousEventHandler(handlerId)
        cecho("\n<green>[fed2-tools]<reset> Muxlet installed.\n")
        tempTimer(0.5, startWorkspace)
    end)

    if MUXLET_DEV_URL then
        cecho("\n<yellow>[fed2-tools]<reset> Installing Muxlet from dev build...\n")
        installPackage(MUXLET_DEV_URL)
        return
    end

    cecho("\n<cyan>[fed2-tools]<reset> Muxlet not found — installing from MPR...\n")

    if not mpkg then
        cecho("\n<red>[fed2-tools]<reset> mpkg is not installed. Install mpkg from the Mudlet Package Repository, then reinstall fed2-tools.\n")
        killAnonymousEventHandler(handlerId)
        return
    end

    -- mpkg.install() silently returns if the package list isn't loaded yet.
    -- Retry up to 5 times, refreshing the list each time, before giving up.
    local attempts = 0
    local function tryInstall()
        if mpkg.ready() then
            mpkg.install(MUXLET_PKG)
        elseif attempts < 5 then
            attempts = attempts + 1
            mpkg.updatePackageList(true)
            tempTimer(6, tryInstall)
        else
            cecho("\n<red>[fed2-tools]<reset> Could not reach MPR after several attempts. Check your internet connection.\n")
            killAnonymousEventHandler(handlerId)
        end
    end
    tryInstall()
end

-- ── Boot ──────────────────────────────────────────────────────────────────────
-- Defer past Muxlet's 1-second auto_start timer so it fires first.
-- If auto_start=true, Muxlet starts itself and we take the mid-session path.
-- If auto_start=false (default), we start it after the timer has already run.
tempTimer(1.1, function()
    if not table.contains(getPackages(), MUXLET_PKG) then
        installMuxlet()
    else
        startWorkspace()
    end
end)
