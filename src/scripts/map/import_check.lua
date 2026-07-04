-- fed2-tools — Map import trigger
--
-- f2tCheckMapImport() is called from map content's apply() each time the
-- fed2_map content is applied to a pane/tab — both a manual add from the
-- Content Library and a workspace restore reapplying a previously-saved
-- layout funnel through the same Mux._applyContent -> apply() path, so this
-- fires identically either way.  It decides whether to offer the bundled
-- map-database import dialog and, if so, with what framing:
--
--   "firstrun" — this profile has never acknowledged a map database version
--                (internal map_db_version_applied == 0).  Shown once.
--   "upgrade"  — a newer MAP_DB_VERSION shipped than the one this profile
--                last acknowledged.  Nudges the user to refresh their maps.
--
-- Gating is the user-facing map.show_import_prompt toggle (src/scripts/map/
-- settings.lua) — a plain on/off switch, not a version number, so it reads
-- sensibly in Fed2-Tools/Map and can be flipped on to re-test. A newer map
-- database version forces that toggle back on even if the user had turned it
-- off, using a separate hidden version counter (map_db_version_applied, a raw
-- Mux.settings._data write — not a registered f2t setting, since it's pure
-- internal bookkeeping the user has no reason to edit directly).
--
-- Decision is NOT based on live room count: mapping is enabled by default, so
-- the Mudlet map already has at least the current room the moment this fires,
-- making "is the map empty" useless as a first-run signal.
--
-- The acknowledgement is written only AFTER the dialog is actually shown, so a
-- silent miss (bad timing, pane not ready) cannot permanently suppress the
-- prompt.
--
-- Upgrade trigger: bump  MAP_DB_VERSION  in this file when new maps ship.

local MAP_DB_VERSION = 1

local function appliedVersion()
    local d = Mux and Mux.settings and Mux.settings._data
    return tonumber(d and d["f2t"] and d["f2t"]["map_db_version_applied"]) or 0
end

local function markVersionApplied()
    if not (Mux and Mux.settings) then return end
    Mux.settings._data["f2t"] = Mux.settings._data["f2t"] or {}
    Mux.settings._data["f2t"]["map_db_version_applied"] = MAP_DB_VERSION
    Mux.settings.save()
end

function f2tCheckMapImport()
    local seen = appliedVersion()

    -- A newer map database shipped than this profile last acknowledged: force
    -- the user-facing toggle back on so the prompt reaches the user again,
    -- even if they'd turned it off after seeing an older version.
    local reason = (seen > 0) and "upgrade" or "firstrun"
    if seen < MAP_DB_VERSION then
        f2t_settings_set("map", "show_import_prompt", true)
        f2t_debug_log("[map-import] new map db (seen=%d, current=%d) — show_import_prompt re-enabled",
            seen, MAP_DB_VERSION)
    end

    if not f2t_settings_get("map", "show_import_prompt") then
        f2t_debug_log("[map-import] show_import_prompt is off — no prompt")
        return
    end

    if not f2tShowMapImportDialog then
        f2t_debug_log("[map-import] f2tShowMapImportDialog missing — cannot prompt")
        return
    end

    f2t_debug_log("[map-import] offering import dialog (reason=%s)", reason)

    -- Defer slightly so any onboarding dialog that just closed finishes animating.
    tempTimer(0.2, function()
        local shown = f2tShowMapImportDialog(reason)
        -- Only burn the acknowledgement once the dialog genuinely displayed, so a
        -- failed show leaves the prompt armed for the next map load.
        if shown then
            f2t_settings_set("map", "show_import_prompt", false)
            markVersionApplied()
            f2t_debug_log("[map-import] dialog shown — show_import_prompt off, version_applied=%d", MAP_DB_VERSION)
        else
            f2t_debug_log("[map-import] dialog did not show — leaving prompt armed")
        end
    end)
end
