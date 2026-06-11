-- fed2-tools — Map import trigger
--
-- f2tCheckMapImport() is called from map content's apply() each time the
-- fed2_map content is applied to a pane.  Shows the map import dialog when:
--   1. The Mudlet map database is empty (first use, map never loaded), OR
--   2. MAP_DB_VERSION has been bumped past the stored seen version
--      (new maps shipped with a fed2-tools upgrade).
--
-- If the workspace offer is currently pending, this call returns immediately;
-- the offer will be dismissed on a future session at which point map content
-- re-applies and this check runs again.
--
-- Upgrade trigger: bump  MAP_DB_VERSION  in this file when new maps ship.

local MAP_DB_VERSION = 1

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function mapVersionSeen()
    local d = Mux.settings and Mux.settings._data
    return tonumber(d and d["f2t"] and d["f2t"]["map_db_version_seen"]) or 0
end

local function mapIsEmpty()
    return next(getRooms()) == nil
end

local function markMapSeen()
    if not (Mux and Mux.settings) then return end
    Mux.settings._data["f2t"] = Mux.settings._data["f2t"] or {}
    Mux.settings._data["f2t"]["map_db_version_seen"] = MAP_DB_VERSION
    Mux.settings.save()
end

-- ── Public entry point ────────────────────────────────────────────────────────

function f2tCheckMapImport()
    -- Defer if the workspace offer is pending; it will be settled on next session
    -- when map content re-applies and this check runs again.
    if f2tOfferPending and f2tOfferPending() then return end

    local needsImport = mapIsEmpty() or mapVersionSeen() < MAP_DB_VERSION
    if not needsImport then return end

    markMapSeen()

    tempTimer(0.2, function()
        if f2tShowMapImportDialog then
            f2tShowMapImportDialog()
        end
    end)
end
