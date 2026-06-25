-- fed2-tools — Dev Mode: local build auto-reload and manual reload helpers
--
-- Auto-reload: muddlet --profile <name> writes a stamp file to the profile
-- directory after every build. A 30-second timer watches for stamp changes
-- and reloads via uninstallPackage + installPackage.
-- When --fresh is passed to muddlet it also writes a fresh flag file; the
-- watcher detects it and calls f2t_devmode_reload(true) instead of (false),
-- triggering a full clean-install simulation without closing Mudlet.
--
-- Manual reload:
--   f2t reload        — upgrade path (preserves settings, workspaces, player data)
--   f2t reload fresh  — simulate a first-time install: wipes all persistent data,
--                       removes Muxlet and fed2-tools from the profile XML, then
--                       reinstalls fed2-tools; init.lua downloads a fresh Muxlet.
--                       Works while connected — no disconnect required.

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

local function f2tDevmodeDoReload(pkgPath)
    if table.contains(getPackages(), "fed2-tools") then
        uninstallPackage("fed2-tools")
    end
    installPackage(pkgPath)
end

-- Recursive 30-second timer. Does nothing when the stamp file is absent
-- (standard production installs have no stamp file).
local function f2tDevmodeCheck()
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
    local freshPath = home .. "/fed2-tools-fresh.stamp"
    local freshFile = io.open(freshPath, "r")

    if freshFile then
        freshFile:close()
        os.remove(freshPath)
        cecho("\n<yellow>[fed2-tools]<reset> New local build detected (fresh) — wiping and reloading...\n")
        f2t_devmode_reload(true)
    else
        cecho("\n<cyan>[fed2-tools]<reset> New local build detected — reloading...\n")
        f2tDevmodeDoReload(home .. "/fed2-tools.mpackage")
    end
    -- No reschedule: the freshly installed package starts its own timer on load.
end

-- Called by "f2t reload [fresh]".
function f2t_devmode_reload(fresh)
    local pkgPath = getMudletHomeDir() .. "/fed2-tools.mpackage"
    local f = io.open(pkgPath, "r")
    if not f then
        cecho(string.format("\n<red>[fed2-tools]<reset> No deployed build found at: %s\n", pkgPath))
        cecho("\n<yellow>[fed2-tools]<reset> Run: ./muddlet --profile <name>\n")
        return
    end
    f:close()

    if fresh then
        local home = getMudletHomeDir()

        -- Wipe all persistent data so the reinstalled packages start from scratch.
        cecho("\n<yellow>[fed2-tools]<reset> --fresh: deleting Muxlet_persistent...\n")
        rmDir(home .. "/Muxlet_persistent")

        cecho("\n<yellow>[fed2-tools]<reset> --fresh: deleting fed2-tools_persistent...\n")
        rmDir(home .. "/fed2-tools_persistent")

        -- Remove Muxlet from the profile XML. Chain through the uninstall event so
        -- getPackages() no longer lists Muxlet by the time fed2-tools reinstalls and
        -- init.lua decides whether to download a fresh copy.
        if table.contains(getPackages(), "Muxlet") then
            cecho("\n<yellow>[fed2-tools]<reset> --fresh: removing Muxlet from profile...\n")
            local waitId
            waitId = registerAnonymousEventHandler("sysUninstallPackage", function(_, name)
                if name ~= "Muxlet" then return end
                killAnonymousEventHandler(waitId)
                cecho("\n<cyan>[fed2-tools]<reset> Reloading fed2-tools...\n")
                f2tDevmodeDoReload(pkgPath)
            end)
            uninstallPackage("Muxlet")
        else
            cecho("\n<cyan>[fed2-tools]<reset> Reloading fed2-tools...\n")
            f2tDevmodeDoReload(pkgPath)
        end
    else
        cecho("\n<cyan>[fed2-tools]<reset> Reloading fed2-tools...\n")
        f2tDevmodeDoReload(pkgPath)
    end
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
