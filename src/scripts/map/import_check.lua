-- fed2-tools — Map import trigger
--
-- f2tCheckMapImport() is called from map content's apply() each time the
-- fed2_map content is applied to a pane.  It decides whether to offer the
-- bundled map-database import dialog and, if so, with what framing:
--
--   "firstrun" — this profile has never been offered a map import
--                (persisted flag absent).  Shown once on first map load.
--   "upgrade"  — a newer MAP_DB_VERSION shipped than the one this profile
--                last acknowledged.  Nudges the user to refresh their maps.
--
-- The decision is driven by a PERSISTED flag, not by the live room count:
-- the mapper auto-maps the current room the moment it mounts, so "is the map
-- empty" is unreliable as a first-run signal.
--
-- The acknowledgement flag is written only AFTER the dialog is actually shown,
-- so a silent miss (bad timing, pane not ready) cannot permanently suppress
-- the prompt.
--
-- Upgrade trigger: bump  MAP_DB_VERSION  in this file when new maps ship.

local MAP_DB_VERSION = 1

local function mapVersionSeen()
    local d = Mux and Mux.settings and Mux.settings._data
    return tonumber(d and d["f2t"] and d["f2t"]["map_db_version_seen"]) or 0
end

-- Persist the acknowledged map-db version.  Called only once the import dialog
-- has actually been presented to the user.
local function markMapSeen()
    if not (Mux and Mux.settings) then return end
    Mux.settings._data["f2t"] = Mux.settings._data["f2t"] or {}
    Mux.settings._data["f2t"]["map_db_version_seen"] = MAP_DB_VERSION
    Mux.settings.save()
    f2t_debug_log("[map-import] marked map_db_version_seen = %d", MAP_DB_VERSION)
end

function f2tCheckMapImport()
    local seen = mapVersionSeen()

    -- Never offered on this profile → first-run.  Otherwise, a stale acknowledged
    -- version → upgrade nudge.  Up to date → nothing to do.
    local reason
    if seen <= 0 then
        reason = "firstrun"
    elseif seen < MAP_DB_VERSION then
        reason = "upgrade"
    else
        f2t_debug_log("[map-import] up to date (seen=%d, current=%d) — no prompt", seen, MAP_DB_VERSION)
        return
    end

    f2t_debug_log("[map-import] offering import dialog (reason=%s, seen=%d)", reason, seen)

    if not f2tShowMapImportDialog then
        f2t_debug_log("[map-import] f2tShowMapImportDialog missing — cannot prompt")
        return
    end

    -- Defer slightly so any onboarding dialog that just closed finishes animating.
    tempTimer(0.2, function()
        local shown = f2tShowMapImportDialog(reason)
        -- Only burn the acknowledgement once the dialog genuinely displayed, so a
        -- failed show leaves the prompt armed for the next map load.
        if shown then
            markMapSeen()
        else
            f2t_debug_log("[map-import] dialog did not show — leaving prompt armed")
        end
    end)
end
