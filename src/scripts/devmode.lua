-- fed2-tools — Dev Mode: local build auto-reload
--
-- muddlet --profile <name> writes a stamp file to the profile directory after
-- every build:
--     fed2-tools-rebuild.stamp   contents: unix timestamp
-- A recursive 30-second timer watches the stamp. When it changes, fed2-tools
-- reinstalls itself from the deployed package. The new code is active
-- immediately; Mux._promptRestartRequired then offers a profile close/reopen
-- for a fully clean UI (stale widgets from the prior session), but doesn't
-- force one.
--
-- muddlet --fresh additionally writes a fresh flag file alongside the stamp.
-- The watcher picks this up and, instead of a plain reinstall, wipes
-- Muxlet_persistent and fed2-tools_persistent, uninstalls Muxlet from the
-- profile XML, then reinstalls fed2-tools — whose own top-level bootstrap
-- notices Muxlet is missing and downloads a clean copy — simulating a
-- first-time install without closing Mudlet.

-- Stamp value seen at last check. nil = not yet observed this session.
local _devLastStamp = nil

-- Recursively delete a file or directory tree.
local function rmDir(path)
    local attr = lfs.attributes(path)
    if not attr then return end
    if attr.mode == "directory" then
        for entry in lfs.dir(path) do
            if entry ~= "." and entry ~= ".." then
                rmDir(path .. "/" .. entry)
            end
        end
        lfs.rmdir(path)
    else
        os.remove(path)
    end
end

-- CRITICAL: deferred to a runtime tempTimer(0) so the uninstall does NOT run
-- while a package-owned timer callback (the watcher below) is still on the
-- Lua stack. Uninstalling the very script that is executing frees it mid-run
-- and crashes Mudlet — the same bug Muxlet hit and fixed in
-- Mux._reinstallPackage (see Muxlet's update.lua).
--
-- Reinstalling only reloads fed2-tools' Lua; Muxlet keeps running and never
-- re-fires "muxletReady", so nothing re-triggers content registration on its
-- own. Clear the registrar list so reloaded modules repopulate it fresh, then
-- run it explicitly once the new package has loaded.
local function f2tDevmodeDoReload(pkgPath)
    tempTimer(0, function()
        if table.contains(getPackages(), "fed2-tools") then
            uninstallPackage("fed2-tools")
        end
        local ok, err = installPackage(pkgPath)
        if ok then
            F2T_CONTENT_REGISTRARS = {}
            if f2tRegisterAllContent then f2tRegisterAllContent() end
            cecho("\n<green>[fed2-tools]<reset> Reinstalled.\n")
            if Mux and Mux._promptRestartRequired then Mux._promptRestartRequired() end
        else
            cecho(string.format(
                "\n<red>[fed2-tools]<reset> Reinstall failed (%s). Install manually from: %s\n",
                tostring(err or "unknown error"), pkgPath))
        end
    end)
end

-- Wipes persisted state and removes Muxlet from the profile before handing off
-- to f2tDevmodeDoReload, simulating a brand-new install without closing Mudlet.
local function f2tDevmodeFreshReload(pkgPath)
    local home = getMudletHomeDir()

    cecho("\n<yellow>[fed2-tools]<reset> --fresh: deleting Muxlet_persistent...\n")
    rmDir(home .. "/Muxlet_persistent")

    cecho("\n<yellow>[fed2-tools]<reset> --fresh: deleting fed2-tools_persistent...\n")
    rmDir(home .. "/fed2-tools_persistent")

    if table.contains(getPackages(), "Muxlet") then
        cecho("\n<yellow>[fed2-tools]<reset> --fresh: removing Muxlet from profile...\n")
        -- Tell init.lua's generic sysUninstallPackage watchdog to stand down for
        -- this uninstall — it's ours, and f2tDevmodeDoReload below already
        -- re-triggers Muxlet's reinstall via fed2-tools' own top-level bootstrap.
        -- Global (not local) because it must survive into the handler below,
        -- and it's cleared there before anything else can race it.
        F2T_FRESH_UNINSTALL_PENDING = true
        local waitId
        waitId = registerAnonymousEventHandler("sysUninstallPackage", function(_, name)
            if name ~= "Muxlet" then return end
            killAnonymousEventHandler(waitId)
            F2T_FRESH_UNINSTALL_PENDING = false
            cecho("\n<cyan>[fed2-tools]<reset> Reloading fed2-tools...\n")
            f2tDevmodeDoReload(pkgPath)
        end)
        uninstallPackage("Muxlet")
    else
        cecho("\n<cyan>[fed2-tools]<reset> Reloading fed2-tools...\n")
        f2tDevmodeDoReload(pkgPath)
    end
end

-- Recursive 30-second timer. Does nothing when the stamp file is absent
-- (standard production installs have no stamp file).
local function f2tDevmodeCheck()
    -- Defer all file I/O and reloads until after login. The synchronous
    -- io.open call blocks Mudlet's main thread; if it fires during the
    -- password prompt the brief freeze can corrupt the login sequence.
    if not F2T_LOGGED_IN then
        tempTimer(5, f2tDevmodeCheck)
        return
    end

    local home      = getMudletHomeDir()
    local stampPath = home .. "/fed2-tools-rebuild.stamp"
    local file      = io.open(stampPath, "r")

    if not file then
        tempTimer(30, f2tDevmodeCheck)
        return
    end

    local stamp = file:read("*a"):match("^%s*(.-)%s*$")
    file:close()

    if stamp == _devLastStamp then
        tempTimer(30, f2tDevmodeCheck)
        return
    end

    if _devLastStamp == nil then
        -- First observation: record stamp but don't reload. Prevents a spurious
        -- reload on every package restart when the stamp file already exists.
        _devLastStamp = stamp
        cecho("\n<yellow>[fed2-tools]<reset> Dev mode active — monitoring for new local builds\n")
        tempTimer(30, f2tDevmodeCheck)
        return
    end

    -- Stamp changed: a new build was deployed; check for the fresh flag.
    _devLastStamp = stamp
    local pkgPath   = home .. "/fed2-tools.mpackage"
    local freshPath = home .. "/fed2-tools-fresh.stamp"
    local freshFile = io.open(freshPath, "r")

    if freshFile then
        freshFile:close()
        os.remove(freshPath)
        cecho("\n<yellow>[fed2-tools]<reset> New local build detected (fresh) — wiping and reloading...\n")
        f2tDevmodeFreshReload(pkgPath)
    else
        cecho("\n<cyan>[fed2-tools]<reset> New local build detected — reloading...\n")
        f2tDevmodeDoReload(pkgPath)
    end
    -- No reschedule: the freshly installed package starts its own timer on load.
end

-- Only start the polling timer if a stamp file already exists in the profile
-- directory. Production installs never have this file, so the timer never
-- runs for end-users.
local function f2tDevmodeStart()
    local stampPath = getMudletHomeDir() .. "/fed2-tools-rebuild.stamp"
    local probe = io.open(stampPath, "r")
    if not probe then return end
    probe:close()
    tempTimer(30, f2tDevmodeCheck)
end

f2tDevmodeStart()
