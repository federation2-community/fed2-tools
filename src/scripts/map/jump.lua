-- fed2-tools map — jump exit management (ported from map_jump.lua)

F2T_MAP_JUMP_CAPTURE = {
    expecting = false,
    active    = false,
    room_id   = nil,
    source_system = nil,
    destinations  = {},
    in_output = false,
}

local jump_timer_id   = nil
local giveup_timer_id = nil

-- room_id -> os.time() of the last silent "jump" probe sent for that link room.
-- GMCP room events can re-fire repeatedly for the same room (another player
-- entering, "look" resending room data, etc). Without this throttle, every
-- re-fire would restart the probe, and overlapping probes made
-- jump_capture_line's deleteLine() eat real console output (including the
-- player's own "look") instead of just the probe's.
local last_attempt_at   = {}
local ATTEMPT_COOLDOWN  = 60

-- A room's jump exits are considered fresh for this long after a successful
-- probe; process_link_room won't re-check them again until it's stale. This
-- is what lets the map catch up on its own after a syndicate builds or loses
-- a Hub/Distant Beacon (which changes valid "jump" destinations from an
-- already-mapped link room) just by the player passing back through later,
-- instead of that room's jump exits being probed once and then never again.
local JUMP_SYNC_TTL = 3600

local function clearJumpExits(room_id)
    if not room_id or not roomExists(room_id) then return end
    for command, _ in pairs(getSpecialExits(room_id)) do
        if string.match(command, "^jump ") then
            removeSpecialExit(room_id, command)
        end
    end
end

-- True if room_id's jump exits are missing a recent-enough sync stamp (never
-- probed, or probed more than JUMP_SYNC_TTL ago). Shared by the passive
-- auto-probe below and by speedwalk.lua's per-step check before it sends a
-- "jump ___" special exit command.
function f2t_map_jump_exit_needs_sync(room_id)
    if not room_id or not roomExists(room_id) then return false end
    local synced_at = tonumber(getRoomUserData(room_id, "fed2_jump_synced_at"))
    local needs = not (synced_at and os.time() - synced_at < JUMP_SYNC_TTL)
    f2t_debug_log("[map/jump] needs_sync(room=%s): synced_at=%s age=%s -> %s",
        tostring(room_id), tostring(synced_at),
        synced_at and tostring(os.time() - synced_at) or "n/a", tostring(needs))
    return needs
end

function f2t_map_process_link_room(room_id, flags)
    if not room_id or not roomExists(room_id) then return end
    if not flags or not f2t_has_value(flags, "link") then return end
    if F2T_MAP_JUMP_CAPTURE.expecting or F2T_MAP_JUMP_CAPTURE.active then
        f2t_debug_log("[map/jump] process_link_room(%s): skip, capture busy (expecting=%s active=%s)",
            tostring(room_id), tostring(F2T_MAP_JUMP_CAPTURE.expecting), tostring(F2T_MAP_JUMP_CAPTURE.active))
        return
    end
    local last = last_attempt_at[room_id]
    if last and os.time() - last < ATTEMPT_COOLDOWN then
        f2t_debug_log("[map/jump] process_link_room(%s): skip, cooldown (%ds ago)", tostring(room_id), os.time() - last)
        return
    end
    if not f2t_map_jump_exit_needs_sync(room_id) then
        f2t_debug_log("[map/jump] process_link_room(%s): skip, still fresh", tostring(room_id))
        return
    end
    local system = getRoomUserData(room_id, "fed2_system")
    if not system then
        f2t_debug_log("[map/jump] process_link_room(%s): skip, no fed2_system userdata", tostring(room_id))
        return
    end
    last_attempt_at[room_id] = os.time()
    clearJumpExits(room_id)   -- routes may have changed since the last sync, not just grown
    f2t_debug_log("[map/jump] process_link_room(%s): passive probe firing (system=%s)", tostring(room_id), system)
    f2t_map_start_jump_capture(room_id, system)
end

function f2t_map_start_jump_capture(room_id, source_system)
    F2T_MAP_JUMP_CAPTURE.expecting     = true
    F2T_MAP_JUMP_CAPTURE.active        = false
    F2T_MAP_JUMP_CAPTURE.room_id       = room_id
    F2T_MAP_JUMP_CAPTURE.source_system = source_system
    F2T_MAP_JUMP_CAPTURE.destinations  = {}
    F2T_MAP_JUMP_CAPTURE.in_output     = false
    f2t_debug_log("[map/jump] start_jump_capture(room=%s, system=%s): sending silent 'jump', expecting=true",
        tostring(room_id), tostring(source_system))
    send("jump", false)
    -- Safety net: if "jump" never produces the expected header (unexpected
    -- game response), don't leave "expecting" stuck forever blocking every
    -- other link room's probe for the rest of the session.
    if giveup_timer_id then killTimer(giveup_timer_id) end
    giveup_timer_id = tempTimer(3, function()
        giveup_timer_id = nil
        if F2T_MAP_JUMP_CAPTURE.expecting and not F2T_MAP_JUMP_CAPTURE.active then
            f2t_debug_log("[map/jump] start_jump_capture(room=%s): gave up, no header seen within 3s",
                tostring(room_id))
            F2T_MAP_JUMP_CAPTURE.expecting = false
        end
    end)
end

function f2t_map_add_jump_destination(system_name)
    if not F2T_MAP_JUMP_CAPTURE.active then return end
    table.insert(F2T_MAP_JUMP_CAPTURE.destinations, system_name)
end

function f2t_map_finish_jump_capture()
    if not F2T_MAP_JUMP_CAPTURE.active then return end
    local room_id      = F2T_MAP_JUMP_CAPTURE.room_id
    local source_system = F2T_MAP_JUMP_CAPTURE.source_system
    local destinations  = F2T_MAP_JUMP_CAPTURE.destinations
    local created_count = 0
    for _, dest_system in ipairs(destinations) do
        if f2t_map_create_jump_special_exit(room_id, source_system, dest_system) then
            created_count = created_count + 1
        end
    end
    f2t_debug_log("[map/jump] finish_jump_capture(room=%s): captured [%s] -> created %d/%d special exits",
        tostring(room_id), table.concat(destinations, ", "), created_count, #destinations)
    if room_id then setRoomUserData(room_id, "fed2_jump_synced_at", tostring(os.time())) end
    F2T_MAP_JUMP_CAPTURE.expecting     = false
    F2T_MAP_JUMP_CAPTURE.active        = false
    F2T_MAP_JUMP_CAPTURE.in_output     = false
    F2T_MAP_JUMP_CAPTURE.room_id       = nil
    F2T_MAP_JUMP_CAPTURE.source_system = nil
    F2T_MAP_JUMP_CAPTURE.destinations  = {}
end

function f2t_map_create_jump_special_exit(from_room_id, from_system, to_system)
    local to_room_id = f2t_map_find_link_room_in_system(to_system)
    if not to_room_id then return false end
    local forward_command = string.format("jump %s", to_system)
    addSpecialExit(from_room_id, to_room_id, forward_command)
    local reverse_command = string.format("jump %s", from_system)
    addSpecialExit(to_room_id, from_room_id, reverse_command)
    return true
end

function f2t_map_find_link_room_in_system(system)
    if not system or system == "" then return nil end
    local rooms = getRooms()
    for room_id in pairs(rooms) do
        local room_system = getRoomUserData(room_id, "fed2_system")
        local has_link    = getRoomUserData(room_id, "fed2_flag_link")
        if room_system == system and has_link == "true" then return room_id end
    end
    return nil
end

function f2t_map_jump_reset_timer()
    if jump_timer_id then killTimer(jump_timer_id) end
    jump_timer_id = tempTimer(0.5, function()
        if F2T_MAP_JUMP_CAPTURE.active then
            f2t_map_finish_jump_capture()
        end
        jump_timer_id = nil
    end)
end

-- ── Manual resync ────────────────────────────────────────────────────────────
-- process_link_room already re-checks a link room's jump exits on its own
-- once JUMP_SYNC_TTL has passed (see above), and navigate.lua/speedwalk.lua
-- force a fresh check of whatever room the player is actually standing in
-- before routing/on failure — no bulk command needed for the normal case.
--
-- This is deliberately per-room only, not "resync every mapped link room":
-- the "jump" probe's answer depends on where the player's character is
-- actually, physically standing in the game right now (that's the whole
-- reason "jump" is only meaningful from a flagged link room in the first
-- place) — Mudlet's room_id bookkeeping doesn't change that. A room the
-- player isn't currently in can't be soundly probed remotely; the only
-- correct way to refresh it is to actually be there when the probe runs.

-- Force a re-probe of one link room's jump destinations right now, ignoring
-- JUMP_SYNC_TTL and the retry cooldown (both exist for the passive check, not
-- a deliberate manual resync). Returns false without doing anything if a
-- capture is already in flight. Only sound for the room the player is
-- actually standing in — see note above.
function f2t_map_resync_jump_exits(room_id)
    if not room_id or not roomExists(room_id) then
        f2t_debug_log("[map/jump] resync_jump_exits(%s): no such room", tostring(room_id))
        return false
    end
    if F2T_MAP_JUMP_CAPTURE.expecting or F2T_MAP_JUMP_CAPTURE.active then
        f2t_debug_log("[map/jump] resync_jump_exits(%s): declined, capture already busy (expecting=%s active=%s)",
            tostring(room_id), tostring(F2T_MAP_JUMP_CAPTURE.expecting), tostring(F2T_MAP_JUMP_CAPTURE.active))
        return false
    end
    local system = getRoomUserData(room_id, "fed2_system")
    if not system then
        f2t_debug_log("[map/jump] resync_jump_exits(%s): no fed2_system userdata, can't probe", tostring(room_id))
        return false
    end
    clearJumpExits(room_id)
    last_attempt_at[room_id] = os.time()
    f2t_debug_log("[map/jump] resync_jump_exits(%s): forcing fresh probe (system=%s)", tostring(room_id), system)
    f2t_map_start_jump_capture(room_id, system)
    return true
end

-- Poll until no jump-exit probe is in flight (whether one this caller just
-- started or one already running), then invoke callback(). Bounded to ~4s —
-- f2t_map_start_jump_capture's own giveup_timer_id already caps a single
-- probe at ~3s, this just adds a small margin. Used by nav (navigate.lua)
-- and the speedwalk failure handler (speedwalk.lua) so they can force-
-- refresh the room they're standing in and wait for the truth before
-- routing, instead of computing a path from possibly-stale data.
function f2t_map_wait_for_jump_sync(callback)
    f2t_debug_log("[map/jump] wait_for_jump_sync: begin waiting (expecting=%s active=%s)",
        tostring(F2T_MAP_JUMP_CAPTURE.expecting), tostring(F2T_MAP_JUMP_CAPTURE.active))
    local waited = 0
    local function wait()
        if not (F2T_MAP_JUMP_CAPTURE.expecting or F2T_MAP_JUMP_CAPTURE.active) then
            f2t_debug_log("[map/jump] wait_for_jump_sync: settled after %.2fs, invoking callback", waited)
            callback()
            return
        end
        waited = waited + 0.25
        if waited >= 4 then
            f2t_debug_log("[map/jump] wait_for_jump_sync: gave up after %.2fs, invoking callback anyway", waited)
            callback(); return
        end
        tempTimer(0.25, wait)
    end
    tempTimer(0.25, wait)
end
