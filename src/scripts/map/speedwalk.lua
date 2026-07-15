-- fed2-tools map — speedwalk (ported from map_speedwalk.lua)

F2T_SPEEDWALK_ACTIVE               = false
F2T_SPEEDWALK_PAUSED               = false
F2T_SPEEDWALK_DIR                  = {}
F2T_SPEEDWALK_PATH                 = {}
F2T_SPEEDWALK_CURRENT_STEP         = 0
F2T_SPEEDWALK_WAITING_FOR_ARRIVAL  = false
F2T_SPEEDWALK_DESTINATION_ROOM_ID  = nil
F2T_SPEEDWALK_LAST_COMMAND         = nil
F2T_SPEEDWALK_EXPECTED_ROOM_ID     = nil
F2T_SPEEDWALK_WAITING_FOR_MOVE     = false
F2T_SPEEDWALK_MOVE_TIMEOUT_ID      = nil
F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
F2T_SPEEDWALK_LAST_RESULT          = nil
F2T_SPEEDWALK_FAILED_EXIT_ROOM     = nil
F2T_SPEEDWALK_FAILED_EXIT_DIR      = nil
F2T_SPEEDWALK_OWNER                = nil
F2T_SPEEDWALK_ON_INTERRUPT         = nil
F2T_SPEEDWALK_BRIEF_SWITCHED       = false

-- room_id -> how many times this speedwalk has proactively resynced that
-- room's jump exits before sending a "jump ___" step. Bounds the self-heal
-- loop in f2t_map_speedwalk_next_step() below: if a room's probe never
-- settles into "not stale" (e.g. "jump" never yields a recognizable
-- response there), we fall back to sending the command as-is after a couple
-- of tries rather than resyncing forever — the normal timeout/retry/give-up
-- path in f2t_map_speedwalk_handle_move_failure is what bounds that case.
local jump_sync_retries = {}
local JUMP_SYNC_RETRY_CAP = 2

function f2t_map_set_nav_owner(owner, on_interrupt)
    F2T_SPEEDWALK_OWNER        = owner
    F2T_SPEEDWALK_ON_INTERRUPT = on_interrupt
end

function f2t_map_clear_nav_owner()
    F2T_SPEEDWALK_OWNER        = nil
    F2T_SPEEDWALK_ON_INTERRUPT = nil
end

function f2t_map_speedwalk_restore_mode()
    if not F2T_EXPLORE_BRIEF_OWNER and F2T_SPEEDWALK_BRIEF_SWITCHED then
        local after_mode = f2t_settings_get("map", "speedwalk_after_mode") or "full"
        send(after_mode)
        F2T_SPEEDWALK_BRIEF_SWITCHED = false
    end
end

function doSpeedWalk()
    if not speedWalkDir or #speedWalkDir == 0 then
        cecho("\n<red>[map]<reset> No path available - call getPath() first\n"); return false
    end
    F2T_SPEEDWALK_ACTIVE               = true
    F2T_SPEEDWALK_PAUSED               = false
    F2T_SPEEDWALK_DIR                  = speedWalkDir
    F2T_SPEEDWALK_PATH                 = speedWalkPath
    F2T_SPEEDWALK_CURRENT_STEP         = 0
    F2T_SPEEDWALK_DESTINATION_ROOM_ID  = tonumber(speedWalkPath[#speedWalkPath])
    F2T_SPEEDWALK_LAST_COMMAND         = nil
    F2T_SPEEDWALK_LAST_RESULT          = nil
    F2T_SPEEDWALK_EXPECTED_ROOM_ID     = nil
    F2T_SPEEDWALK_WAITING_FOR_MOVE     = false
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID      = nil
    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
    F2T_SPEEDWALK_BRIEF_SWITCHED       = false
    jump_sync_retries                  = {}
    local path_length = #speedWalkDir
    cecho(string.format("\n<green>[map]<reset> Speedwalking (%d steps)\n", path_length))
    if path_length >= 3 and f2t_settings_get("map", "speedwalk_brief") and not F2T_EXPLORE_BRIEF_OWNER then
        send("brief")
        F2T_SPEEDWALK_BRIEF_SWITCHED = true
    end
    f2t_map_speedwalk_next_step()
    return true
end

function f2t_map_handle_special_movement(direction)
    if direction:match("^__circuit:") then
        if f2t_map_circuit_begin(direction) then
            F2T_SPEEDWALK_LAST_COMMAND = nil
        else
            cecho("\n<red>[map]<reset> Circuit travel failed, stopping speedwalk\n")
            f2t_map_speedwalk_stop()
        end
        return true
    end
    if direction:match("^__move_no_op_%d+$") then
        F2T_SPEEDWALK_LAST_COMMAND = nil
        return true
    end
    return false
end

function f2t_map_speedwalk_next_step()
    if not F2T_SPEEDWALK_ACTIVE then return end
    if F2T_SPEEDWALK_PAUSED then return end
    if F2T_SPEEDWALK_WAITING_FOR_ARRIVAL then return end
    F2T_SPEEDWALK_CURRENT_STEP = F2T_SPEEDWALK_CURRENT_STEP + 1
    if F2T_SPEEDWALK_CURRENT_STEP > #F2T_SPEEDWALK_DIR then
        f2t_map_speedwalk_complete(); return
    end
    local direction = F2T_SPEEDWALK_DIR[F2T_SPEEDWALK_CURRENT_STEP]
    if f2t_map_handle_special_movement(direction) then return end

    -- A "jump ___" step relies on cached special-exit data that can be
    -- stale (a syndicate beacon build changes which destinations are valid)
    -- or already being refreshed right now (e.g. the passive per-visit
    -- check just fired for this room on arrival, moments before this step
    -- runs). Sending our own "jump X" while a probe is in flight puts two
    -- "jump"-family responses in the stream at once and corrupts both, so
    -- wait for it to settle first — refreshing proactively if the data is
    -- just stale, not yet in flight — then recompute from the corrected
    -- data instead of blindly sending a command that might already be wrong.
    if type(direction) == "string" and direction:match("^jump ") then
        local current_room_id = F2T_MAP_CURRENT_ROOM_ID
        local busy = F2T_MAP_JUMP_CAPTURE.expecting or F2T_MAP_JUMP_CAPTURE.active
        local retries = jump_sync_retries[current_room_id] or 0
        f2t_debug_log("[map/speedwalk] next_step: about to send '%s' from room=%s (busy=%s retries=%d/%d)",
            direction, tostring(current_room_id), tostring(busy), retries, JUMP_SYNC_RETRY_CAP)
        if not busy and retries < JUMP_SYNC_RETRY_CAP and f2t_map_jump_exit_needs_sync(current_room_id) then
            -- true only if a probe actually started; if it couldn't (e.g. the
            -- room is missing its system userdata), fall through and send
            -- the command as-is rather than looping on a resync that will
            -- never succeed.
            busy = f2t_map_resync_jump_exits(current_room_id)
            if busy then jump_sync_retries[current_room_id] = retries + 1 end
        end
        if busy then
            f2t_debug_log("[map/speedwalk] next_step: deferring '%s', waiting on jump sync first", direction)
            f2t_map_wait_for_jump_sync(f2t_map_speedwalk_recompute_path)
            return
        end
    end

    F2T_SPEEDWALK_LAST_COMMAND      = direction
    F2T_SPEEDWALK_EXPECTED_ROOM_ID  = tonumber(F2T_SPEEDWALK_PATH[F2T_SPEEDWALK_CURRENT_STEP])
    F2T_SPEEDWALK_WAITING_FOR_MOVE  = true
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE  = F2T_MAP_CURRENT_ROOM_ID
    local timeout_seconds = f2t_settings_get("map", "speedwalk_timeout")
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID = tempTimer(timeout_seconds, function()
        f2t_map_speedwalk_on_move_timeout()
    end)
    send(direction)
end

function f2t_map_speedwalk_complete()
    if not F2T_SPEEDWALK_ACTIVE then return end
    local dest_name = F2T_MAP_CURRENT_ROOM_ID and getRoomName(F2T_MAP_CURRENT_ROOM_ID)
    cecho(string.format("\n<green>[map]<reset> Arrived at <white>%s<reset>\n", dest_name or "destination"))
    F2T_SPEEDWALK_LAST_RESULT = "completed"
    f2t_map_speedwalk_restore_mode()
    F2T_SPEEDWALK_ACTIVE               = false
    F2T_SPEEDWALK_PAUSED               = false
    F2T_SPEEDWALK_DIR                  = {}
    F2T_SPEEDWALK_PATH                 = {}
    F2T_SPEEDWALK_CURRENT_STEP         = 0
    F2T_SPEEDWALK_WAITING_FOR_ARRIVAL  = false
    F2T_SPEEDWALK_DESTINATION_ROOM_ID  = nil
    F2T_SPEEDWALK_LAST_COMMAND         = nil
    F2T_SPEEDWALK_EXPECTED_ROOM_ID     = nil
    F2T_SPEEDWALK_WAITING_FOR_MOVE     = false
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE     = nil
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end
    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
    f2t_map_clear_nav_owner()
    local arrival_room = F2T_MAP_CURRENT_ROOM_ID
    if arrival_room then tempTimer(0.05, function() centerview(arrival_room) end) end
end

function f2t_map_speedwalk_stop()
    if not F2T_SPEEDWALK_ACTIVE then return false end
    cecho("\n<yellow>[map]<reset> Speedwalk stopped\n")
    if F2T_SPEEDWALK_LAST_RESULT ~= "failed" then F2T_SPEEDWALK_LAST_RESULT = "stopped" end
    f2t_map_speedwalk_restore_mode()
    if F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active then
        f2t_map_circuit_delete_triggers()
        F2T_MAP_CIRCUIT_STATE = {active = false}
    end
    F2T_SPEEDWALK_ACTIVE               = false
    F2T_SPEEDWALK_PAUSED               = false
    F2T_SPEEDWALK_DIR                  = {}
    F2T_SPEEDWALK_PATH                 = {}
    F2T_SPEEDWALK_CURRENT_STEP         = 0
    F2T_SPEEDWALK_WAITING_FOR_ARRIVAL  = false
    F2T_SPEEDWALK_DESTINATION_ROOM_ID  = nil
    F2T_SPEEDWALK_LAST_COMMAND         = nil
    F2T_SPEEDWALK_EXPECTED_ROOM_ID     = nil
    F2T_SPEEDWALK_WAITING_FOR_MOVE     = false
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE     = nil
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end
    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
    f2t_map_clear_nav_owner()
    return true
end

function f2t_map_speedwalk_pause()
    if not F2T_SPEEDWALK_ACTIVE then return false end
    if F2T_SPEEDWALK_PAUSED then cecho("\n<yellow>[map]<reset> Speedwalk is already paused\n"); return false end
    F2T_SPEEDWALK_PAUSED = true
    local remaining = #F2T_SPEEDWALK_DIR - F2T_SPEEDWALK_CURRENT_STEP
    cecho(string.format("\n<yellow>[map]<reset> Speedwalk paused (%d steps remaining)\n", remaining))
    return true
end

function f2t_map_speedwalk_resume()
    if not F2T_SPEEDWALK_ACTIVE then return false end
    if not F2T_SPEEDWALK_PAUSED then cecho("\n<yellow>[map]<reset> Speedwalk is not paused\n"); return false end
    F2T_SPEEDWALK_PAUSED = false
    local remaining = #F2T_SPEEDWALK_DIR - F2T_SPEEDWALK_CURRENT_STEP
    cecho(string.format("\n<green>[map]<reset> Speedwalk resumed (%d steps remaining)\n", remaining))
    f2t_map_speedwalk_next_step()
    return true
end

function f2t_map_speedwalk_on_room_change()
    if not F2T_SPEEDWALK_ACTIVE then return end
    if F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active then return end
    if F2T_SPEEDWALK_WAITING_FOR_MOVE then
        if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
            killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
            F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
        end
        F2T_SPEEDWALK_WAITING_FOR_MOVE = false
        local current_room  = F2T_MAP_CURRENT_ROOM_ID
        local expected_room = F2T_SPEEDWALK_EXPECTED_ROOM_ID
        local movement_success = false
        if current_room == expected_room then
            movement_success = true
        elseif expected_room == nil and current_room ~= F2T_SPEEDWALK_ROOM_BEFORE_MOVE then
            movement_success = true
        end
        if movement_success then
            F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
            F2T_SPEEDWALK_EXPECTED_ROOM_ID     = nil
            F2T_SPEEDWALK_ROOM_BEFORE_MOVE     = nil
            if F2T_SPEEDWALK_CURRENT_STEP == #F2T_SPEEDWALK_DIR - 1 then
                f2t_map_speedwalk_restore_mode()
            end
            f2t_map_speedwalk_next_step()
        else
            if F2T_SPEEDWALK_ROOM_BEFORE_MOVE and current_room == F2T_SPEEDWALK_ROOM_BEFORE_MOVE then
                cecho(string.format("\n<yellow>[map]<reset> Exit blocked: <white>%s<reset> from room %d\n",
                    F2T_SPEEDWALK_LAST_COMMAND or "unknown", current_room))
            end
            F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
            F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
            f2t_map_speedwalk_handle_move_failure()
        end
    else
        f2t_map_speedwalk_next_step()
    end
end

function f2t_map_speedwalk_retry_last_command()
    if not F2T_SPEEDWALK_ACTIVE or not F2T_SPEEDWALK_LAST_COMMAND then return false end
    cecho("\n<yellow>[map]<reset> Retrying movement...\n")
    send(F2T_SPEEDWALK_LAST_COMMAND)
    return true
end

function f2t_map_speedwalk_recompute_path()
    if not F2T_SPEEDWALK_ACTIVE then return false end
    if not F2T_SPEEDWALK_DESTINATION_ROOM_ID then
        cecho("\n<red>[map]<reset> Unable to recover speedwalk: destination unknown\n")
        F2T_SPEEDWALK_LAST_RESULT     = "failed"
        F2T_SPEEDWALK_FAILED_EXIT_ROOM = F2T_MAP_CURRENT_ROOM_ID
        F2T_SPEEDWALK_FAILED_EXIT_DIR  = F2T_SPEEDWALK_LAST_COMMAND
        f2t_map_speedwalk_stop(); return false
    end
    local current_room_id = F2T_MAP_CURRENT_ROOM_ID
    if not current_room_id then
        cecho("\n<red>[map]<reset> Unable to recover speedwalk: current location unknown\n")
        F2T_SPEEDWALK_LAST_RESULT     = "failed"
        F2T_SPEEDWALK_FAILED_EXIT_ROOM = F2T_SPEEDWALK_ROOM_BEFORE_MOVE
        F2T_SPEEDWALK_FAILED_EXIT_DIR  = F2T_SPEEDWALK_LAST_COMMAND
        f2t_map_speedwalk_stop(); return false
    end
    cecho("\n<yellow>[map]<reset> Recomputing path from current location...\n")
    local success = getPath(current_room_id, F2T_SPEEDWALK_DESTINATION_ROOM_ID)
    if not success then
        cecho("\n<red>[map]<reset> Unable to find path from current location\n")
        F2T_SPEEDWALK_LAST_RESULT     = "failed"
        F2T_SPEEDWALK_FAILED_EXIT_ROOM = current_room_id
        F2T_SPEEDWALK_FAILED_EXIT_DIR  = F2T_SPEEDWALK_LAST_COMMAND
        f2t_map_speedwalk_stop(); return false
    end
    if #speedWalkDir == 0 then
        cecho("\n<green>[map]<reset> Already at destination\n")
        f2t_map_speedwalk_stop(); return true
    end
    F2T_SPEEDWALK_DIR              = speedWalkDir
    F2T_SPEEDWALK_PATH             = speedWalkPath
    F2T_SPEEDWALK_CURRENT_STEP     = 0
    F2T_SPEEDWALK_LAST_COMMAND     = nil
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end
    cecho(string.format("\n<green>[map]<reset> Path recomputed (%d steps), resuming...\n", #speedWalkDir))
    f2t_map_speedwalk_next_step()
    return true
end

function f2t_map_speedwalk_handle_move_failure()
    if not F2T_SPEEDWALK_ACTIVE then return end
    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = F2T_SPEEDWALK_CONSECUTIVE_FAILURES + 1
    local max_retries = f2t_settings_get("map", "speedwalk_max_retries")
    if F2T_SPEEDWALK_CONSECUTIVE_FAILURES >= max_retries then
        cecho(string.format("\n<red>[map]<reset> Path appears blocked after %d attempts, stopping speedwalk\n",
            max_retries))
        F2T_SPEEDWALK_LAST_RESULT     = "failed"
        F2T_SPEEDWALK_FAILED_EXIT_ROOM = F2T_MAP_CURRENT_ROOM_ID
        F2T_SPEEDWALK_FAILED_EXIT_DIR  = F2T_SPEEDWALK_LAST_COMMAND
        f2t_map_speedwalk_restore_mode()
        cecho("\n<yellow>[map]<reset> Speedwalk stopped\n")
        if F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active then
            f2t_map_circuit_delete_triggers()
            F2T_MAP_CIRCUIT_STATE = {active = false}
        end
        F2T_SPEEDWALK_ACTIVE               = false
        F2T_SPEEDWALK_PAUSED               = false
        F2T_SPEEDWALK_DIR                  = {}
        F2T_SPEEDWALK_PATH                 = {}
        F2T_SPEEDWALK_CURRENT_STEP         = 0
        F2T_SPEEDWALK_WAITING_FOR_ARRIVAL  = false
        F2T_SPEEDWALK_DESTINATION_ROOM_ID  = nil
        F2T_SPEEDWALK_LAST_COMMAND         = nil
        F2T_SPEEDWALK_EXPECTED_ROOM_ID     = nil
        F2T_SPEEDWALK_WAITING_FOR_MOVE     = false
        F2T_SPEEDWALK_ROOM_BEFORE_MOVE     = nil
        if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
            killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
            F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
        end
        F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
        f2t_map_clear_nav_owner()
        tempTimer(0, function()
            if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then
                f2t_map_explore_on_room_change()
            end
        end)
        return
    end
    cecho(string.format("\n<yellow>[map]<reset> Movement erred, recomputing path... (attempt %d/%d)\n",
        F2T_SPEEDWALK_CONSECUTIVE_FAILURES, max_retries))

    -- A failed "jump ___" step is proof its cached special exit is wrong
    -- right now — regardless of what f2t_map_jump_exit_needs_sync's TTL
    -- stamp claims (e.g. an earlier interleaved/corrupted probe could have
    -- stamped a "fresh" sync despite capturing bad data, or a beacon change
    -- landed within the TTL window). Force a resync before blindly
    -- recomputing against the same bad data again. Shares its retry budget
    -- with the proactive check in f2t_map_speedwalk_next_step so a room
    -- that can never sync falls through to the ordinary give-up above
    -- instead of looping.
    local failed_room = F2T_MAP_CURRENT_ROOM_ID
    f2t_debug_log("[map/speedwalk] handle_move_failure: last_command='%s' failed_room=%s",
        tostring(F2T_SPEEDWALK_LAST_COMMAND), tostring(failed_room))
    if F2T_SPEEDWALK_LAST_COMMAND and F2T_SPEEDWALK_LAST_COMMAND:match("^jump ") and failed_room then
        local retries = jump_sync_retries[failed_room] or 0
        f2t_debug_log("[map/speedwalk] handle_move_failure: jump step failed, retries=%d/%d",
            retries, JUMP_SYNC_RETRY_CAP)
        if retries < JUMP_SYNC_RETRY_CAP then
            local busy = F2T_MAP_JUMP_CAPTURE.expecting or F2T_MAP_JUMP_CAPTURE.active
            if not busy then
                busy = f2t_map_resync_jump_exits(failed_room)
                if busy then jump_sync_retries[failed_room] = retries + 1 end
            end
            if busy then
                f2t_debug_log("[map/speedwalk] handle_move_failure: forcing resync before recompute")
                f2t_map_wait_for_jump_sync(f2t_map_speedwalk_recompute_path)
                return
            end
        end
    end

    f2t_debug_log("[map/speedwalk] handle_move_failure: recomputing without resync")
    f2t_map_speedwalk_recompute_path()
end

function f2t_map_speedwalk_on_move_timeout()
    if not F2T_SPEEDWALK_ACTIVE or not F2T_SPEEDWALK_WAITING_FOR_MOVE then return end
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID  = nil
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
    f2t_map_speedwalk_handle_move_failure()
end
