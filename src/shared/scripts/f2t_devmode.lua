-- =============================================================================
-- Dev Mode: local build auto-reload and manual reload helpers
--
-- Auto-reload: build.ps1 -Profile <name> writes a stamp file to the profile
-- directory. A recursive timer checks every 30s; when the stamp changes it
-- does uninstallPackage + installPackage for a clean replacement.
--
-- Manual reload:
--   f2t reload        -- upgrade path (preserves settings)
--   f2t reload fresh  -- simulates net-new install (clears first_run flag)
-- =============================================================================

-- Tracks the stamp value seen at last load. nil = not yet observed.
F2T_DEV_LAST_STAMP = nil

-- Performs an explicit uninstall then install so stale UI state is fully torn
-- down. installPackage alone can leave orphaned Geyser widgets behind.
local function f2t_devmode_do_reload(pkg_path)
    if f2t_has_value(getPackages(), "fed2-tools") then
        uninstallPackage("fed2-tools")
    end
    installPackage(pkg_path)
end

-- Recursive 30-second timer: watches for a stamp file written by
-- build.ps1 -Profile. Does nothing when the file is absent (production use).
local function f2t_devmode_check()
    local stamp_path = getMudletHomeDir() .. "/fed2-tools-rebuild.stamp"
    local file = io.open(stamp_path, "r")

    if not file then
        tempTimer(30, f2t_devmode_check)
        return
    end

    local stamp = file:read("*a"):match("^%s*(.-)%s*$")  -- trim whitespace
    file:close()

    if stamp == F2T_DEV_LAST_STAMP then
        -- No change since last check
        tempTimer(30, f2t_devmode_check)
        return
    end

    if F2T_DEV_LAST_STAMP == nil then
        -- First observation after load: record stamp but don't reload.
        -- Prevents a spurious reload on every package restart.
        F2T_DEV_LAST_STAMP = stamp
        f2t_debug_log("[f2t] Dev mode: monitoring for new local builds")
        tempTimer(30, f2t_devmode_check)
        return
    end

    -- Stamp changed: a new build was deployed, reload.
    -- Update before the reload so the new package initialises to the same
    -- stamp and skips its own first-check without triggering another reload.
    F2T_DEV_LAST_STAMP = stamp
    cecho("\n<yellow>[f2t]<reset> New local build detected - reloading...\n")
    local pkg_path = getMudletHomeDir() .. "/fed2-tools.mpackage"
    f2t_devmode_do_reload(pkg_path)
    -- No reschedule: the new package starts its own timer on load.
end

-- Manual reload called by the f2t alias.
-- fresh=true simulates a net-new install by clearing the first_run flag so
-- the welcome dialog fires, matching the experience of a brand-new user.
function f2t_devmode_reload(fresh)
    local pkg_path = getMudletHomeDir() .. "/fed2-tools.mpackage"
    local f = io.open(pkg_path, "r")
    if not f then
        cecho("\n<red>[f2t]<reset> No deployed build found in profile directory.\n")
        cecho("\n<yellow>[f2t]<reset> Run: ./build.ps1 -Profile <your-profile-name>\n")
        return
    end
    f:close()

    if fresh then
        f2t_settings_set("shared", "first_run_complete", false)
        f2t_save_settings()
        cecho("\n<yellow>[f2t]<reset> first_run cleared - welcome dialog will appear on install.\n")
    end

    cecho("\n<yellow>[f2t]<reset> Reloading fed2-tools...\n")
    f2t_devmode_do_reload(pkg_path)
end

-- Start the stamp monitor with a 30-second initial delay (avoids a pointless
-- check during the first seconds when nothing could have changed yet).
tempTimer(30, f2t_devmode_check)
