-- Map exploration navigation logic
-- Simplified: queries map for stub exits, navigates directly to rooms

-- ========================================
-- Navigate to Next Unexplored Exit
-- ========================================

function f2t_map_explore_navigate_to_next()
    -- Guard: Check if active
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    local current_room = F2T_MAP_CURRENT_ROOM_ID

    -- Check if we have a planned exit (from previous navigation to stub room)
    local next_exit = F2T_MAP_EXPLORE_STATE.planned_exit

    if next_exit then
        -- We previously navigated to this room to take this specific exit
        f2t_debug_log("[map-explore] Using planned exit: room=%d, direction=%s",
            next_exit.room_id, next_exit.direction)
        F2T_MAP_EXPLORE_STATE.planned_exit = nil  -- Clear after using
    else
        -- No planned exit, pop the next one from frontier
        if #F2T_MAP_EXPLORE_STATE.frontier_stack > 0 then
            next_exit = table.remove(F2T_MAP_EXPLORE_STATE.frontier_stack, 1)  -- Take first (closest)
            f2t_debug_log("[map-explore] Selected closest exit: room=%d, direction=%s, frontier_size=%d",
                next_exit.room_id, next_exit.direction, #F2T_MAP_EXPLORE_STATE.frontier_stack)
        end
    end

    if not next_exit then
        -- No more stub exits - exploration complete
        f2t_debug_log("[map-explore] No more stub exits, exploration complete")

        -- Check if this is brief mode with unfound flags (incomplete exploration)
        if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count and
           F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count > 0 then
            local planet_name = F2T_MAP_EXPLORE_STATE.brief_planet_name or "Unknown"

            -- Determine which flags are truly missing vs. expected-absent
            -- Outside Sol, courier is at the shuttlepad and not flagged separately on player planets
            local area_id = F2T_MAP_EXPLORE_STATE.starting_area_id
            local system_name = area_id and getAreaUserData(area_id, "fed2_system") or ""
            local is_sol = (string.lower(system_name) == "sol")

            local missing_flags = {}
            for flag, _ in pairs(F2T_MAP_EXPLORE_STATE.brief_flags_set or {}) do
                if not F2T_MAP_EXPLORE_STATE.brief_flags_found[flag] then
                    if flag == "courier" and not is_sol then
                        f2t_debug_log("[map-explore] Skipping courier warning outside Sol (at shuttlepad) on '%s'", planet_name)
                    else
                        table.insert(missing_flags, flag)
                    end
                end
            end

            table.sort(missing_flags)

            if #missing_flags == 0 then
                -- Only Sol-specific flags (like courier) were missing - count as complete
                f2t_debug_log("[map-explore] Brief complete (courier skipped outside Sol): planet=%s", planet_name)

                if F2T_MAP_EXPLORE_STATE.system_stats then
                    F2T_MAP_EXPLORE_STATE.system_stats.planets_explored =
                        F2T_MAP_EXPLORE_STATE.system_stats.planets_explored + 1
                    if F2T_MAP_EXPLORE_STATE.brief_flags_found["exchange"] then
                        F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found =
                            F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found + 1
                    end

                    if F2T_MAP_EXPLORE_STATE.mode == "cartel" or F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
                        F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets =
                            F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets + 1
                        if F2T_MAP_EXPLORE_STATE.brief_flags_found["exchange"] then
                            F2T_MAP_EXPLORE_STATE.cartel_stats.total_exchanges =
                                F2T_MAP_EXPLORE_STATE.cartel_stats.total_exchanges + 1
                        end
                    end
                end
            else
                -- Truly missing flags - show warning and record as incomplete
                local flags_msg = table.concat(missing_flags, ", ")
                cecho(string.format("\n  <yellow>Warning:<reset> Flag%s not found on '%s': <yellow>%s<reset> (explored all reachable rooms)\n",
                    #missing_flags > 1 and "s" or "", planet_name, flags_msg))
                f2t_debug_log("[map-explore] Brief incomplete: planet=%s, missing flags=%s",
                    planet_name, flags_msg)

                if F2T_MAP_EXPLORE_STATE.system_stats then
                    if not F2T_MAP_EXPLORE_STATE.system_stats.planets_incomplete then
                        F2T_MAP_EXPLORE_STATE.system_stats.planets_incomplete = 0
                        F2T_MAP_EXPLORE_STATE.system_stats.incomplete_planets = {}
                    end
                    F2T_MAP_EXPLORE_STATE.system_stats.planets_incomplete =
                        F2T_MAP_EXPLORE_STATE.system_stats.planets_incomplete + 1

                    table.insert(F2T_MAP_EXPLORE_STATE.system_stats.incomplete_planets, {
                        name = planet_name,
                        missing_flags = missing_flags
                    })

                    if F2T_MAP_EXPLORE_STATE.mode == "cartel" then
                        if not F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets_incomplete then
                            F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets_incomplete = 0
                            F2T_MAP_EXPLORE_STATE.cartel_stats.incomplete_planets = {}
                        end
                        F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets_incomplete =
                            F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets_incomplete + 1

                        table.insert(F2T_MAP_EXPLORE_STATE.cartel_stats.incomplete_planets, {
                            name = planet_name,
                            missing_flags = missing_flags
                        })
                    end
                end
            end
        end

        -- Check if we have a callback (nested mode)
        local callback = F2T_MAP_EXPLORE_STATE.on_complete_callback

        if callback then
            -- Nested mode: complete immediately, call parent callback
            f2t_debug_log("[map-explore] Nested mode - calling parent callback")
            cecho("\n<green>[map-explore]<reset> Area exploration complete\n\n")

            -- Brief delay to let output settle
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then
                    callback()
                end
            end)
        else
            -- Standalone mode: return to starting room
            f2t_debug_log("[map-explore] Standalone mode - returning to start")
            F2T_MAP_EXPLORE_STATE.phase = "returning"
            f2t_map_explore_next_step()
        end
        return
    end

    -- Navigate to the room with the stub exit
    f2t_debug_log("[map-explore] Navigation check: current_room=%s, next_exit.room_id=%d, equal=%s",
        tostring(current_room), next_exit.room_id, tostring(current_room == next_exit.room_id))

    if current_room ~= next_exit.room_id then
        f2t_debug_log("[map-explore] Navigating to stub room: current=%d, target=%d",
            current_room or 0, next_exit.room_id)

        -- Store this exit as planned so we take it after arriving at the room
        F2T_MAP_EXPLORE_STATE.planned_exit = next_exit
        f2t_debug_log("[map-explore] Stored planned exit for after arrival: room=%d, direction=%s",
            next_exit.room_id, next_exit.direction)

        local success = f2t_map_navigate(tostring(next_exit.room_id))

        if not success then
            cecho(string.format("\n<red>[map-explore]<reset> Failed to navigate to room %d\n", next_exit.room_id))
            f2t_debug_log("[map-explore] Navigation failed to room %d", next_exit.room_id)

            -- Clear planned exit since navigation failed
            F2T_MAP_EXPLORE_STATE.planned_exit = nil

            -- Lock the specific exit that we couldn't reach
            lockExit(next_exit.room_id, next_exit.direction, true)
            f2t_debug_log("[map-explore] Locked exit: room=%d, direction=%s", next_exit.room_id, next_exit.direction)

            -- Track the lock for cleanup
            if not F2T_MAP_EXPLORE_STATE.temp_locked_exits[next_exit.room_id] then
                F2T_MAP_EXPLORE_STATE.temp_locked_exits[next_exit.room_id] = {}
            end
            F2T_MAP_EXPLORE_STATE.temp_locked_exits[next_exit.room_id][next_exit.direction] = true

            -- Try next exit
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then
                    f2t_map_explore_next_step()
                end
            end)
        end
        -- Wait for GMCP room change or speedwalk completion
        return
    end

    -- We're at the stub room, take the exit
    f2t_debug_log("[map-explore] Taking stub exit: room=%d, direction=%s",
        current_room, next_exit.direction)

    -- Track movement for stub resolution
    F2T_MAP_EXPLORE_STATE.last_room_before_move = current_room
    F2T_MAP_EXPLORE_STATE.last_direction_attempted = next_exit.direction

    -- Use speedwalk for protection (timeout, retry, out-of-fuel recovery)
    -- Set both speedWalkDir (directions) and speedWalkPath (room IDs)
    -- We don't know destination room ID yet (stub exit), so use nil
    speedWalkDir = {next_exit.direction}
    speedWalkPath = {nil}
    doSpeedWalk()
end

-- ========================================
-- Return to Starting Room
-- ========================================

function f2t_map_explore_return_to_start()
    -- Guard: Check if active
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    local current_room = F2T_MAP_CURRENT_ROOM_ID
    local starting_room = F2T_MAP_EXPLORE_STATE.starting_room_id

    f2t_debug_log("[map-explore] Returning to start: current=%d, start=%d", current_room or 0, starting_room or 0)

    -- First check if we're at the starting room yet
    if current_room ~= starting_room then
        -- Not at start yet, navigate there
        cecho(string.format("\n<green>[map-explore]<reset> Returning to starting room...\n"))

        local success = f2t_map_navigate(tostring(starting_room))

        if not success then
            cecho(string.format("\n<red>[map-explore]<reset> Failed to return to starting room %d\n", starting_room))
            f2t_debug_log("[map-explore] Return navigation failed to room %d", starting_room)

            -- Show completion anyway
            f2t_map_explore_complete()
        end
        -- Wait for GMCP room change (will trigger completion in on_room_change)
        return
    end

    -- We're at the starting room - check callback vs completion
    f2t_debug_log("[map-explore] Arrived at starting room")

    local callback = F2T_MAP_EXPLORE_STATE.on_complete_callback

    if callback then
        -- Nested mode - call parent callback
        f2t_debug_log("[map-explore] Nested mode - calling parent callback")
        callback()
    else
        -- Standalone mode - show completion message
        f2t_debug_log("[map-explore] Standalone mode - showing completion")
        f2t_map_explore_complete()
    end
end

f2t_debug_log("[map] Loaded map_explore_navigation.lua")
