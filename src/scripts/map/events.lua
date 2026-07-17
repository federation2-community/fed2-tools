-- fed2-tools map — GMCP event handler registration (ported from map_events.lua)

local success, handler_id = pcall(registerAnonymousEventHandler, "gmcp.room.info", "f2t_map_handle_gmcp_room")

if success and handler_id then
    f2t_debug_log("[map] Registered GMCP event handler for gmcp.room.info (ID: %s)", tostring(handler_id))
else
    f2t_debug_log("[map] WARNING: Failed to register GMCP event handler: %s", tostring(handler_id))
end

-- ── Startup topology sync ───────────────────────────────────────────────────
--
-- Once per login, re-ground the jump model (cartel->syndicate groupings and
-- syndicate beacon builds) with a single "display cartels" / "display
-- syndicates" pass, so speedwalk jump planning is correct from the first jump
-- even though the galaxy's politics drift between sessions.
--
-- Runs in EVERY startup mode (Minimal included) and on the very first run:
-- this is a plain GMCP event handler, registered whenever the package loads,
-- and the sync needs no map pane or mapper widget — it only sends game
-- commands whose replies the capture triggers swallow. It is fully silent
-- (opts.silent), so nothing reaches the console.
--
-- Gated to fire once per connection: keyed off gmcp.char.vitals (proof we are
-- logged in and can send commands) with a flag that re-arms on disconnect, the
-- same once-per-session shape used elsewhere in the package. The actual sync is
-- deferred a few seconds so its commands never land in the middle of the login
-- burst.
local topology_startup_synced = false

local function f2t_map_startup_topology_sync()
    if topology_startup_synced then return end
    local name = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if not name or name == "" then return end   -- not logged in yet; wait for vitals
    topology_startup_synced = true
    tempTimer(3, function()
        if type(f2t_map_topology_sync) == "function" then
            f2t_map_topology_sync(nil, { silent = true })
        end
    end)
end

registerAnonymousEventHandler("gmcp.char.vitals", f2t_map_startup_topology_sync)

-- gmcp.char.vitals may already have fired before this script (re)loaded — e.g.
-- a dev-mode rebuild while connected. gmcp.char survives that, so check now too.
f2t_map_startup_topology_sync()

-- Re-arm so the next login after a reconnect syncs once again.
registerAnonymousEventHandler("sysDisconnectionEvent", function()
    topology_startup_synced = false
end)