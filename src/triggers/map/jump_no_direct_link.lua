-- Fires when the game refuses a jump ("There isn't a direct link to X from
-- here."). The map believed this edge was legal, so the model is stale
-- (usually a membership change): drop the edge immediately so replans avoid
-- it, and schedule a topology resync to heal the underlying facts.
local dest = matches[2]
local room_id = F2T_MAP_CURRENT_ROOM_ID

if room_id and roomExists(room_id) then
    local command_lower = string.lower(string.format("jump %s", dest))
    local to_remove = {}
    for command, _ in pairs(getSpecialExitsSwap(room_id) or {}) do
        if type(command) == "string" and string.lower(command) == command_lower then
            table.insert(to_remove, command)
        end
    end
    for _, command in ipairs(to_remove) do
        removeSpecialExit(room_id, command)
        f2t_debug_log("[map/jump] Removed refused jump exit '%s' from room %d", command, room_id)
    end
end

if f2t_map_topology_auto_sync then
    f2t_map_topology_auto_sync(string.format("jump to %s refused", dest))
end

-- Explorer blind-jump chains have no destination room id to recompute
-- against: skip to the explorer's next target instead (same recovery as the
-- system-closed trigger).
if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then
    local mode = F2T_MAP_EXPLORE_STATE.mode
    local phase = F2T_MAP_EXPLORE_STATE.phase
    local jumping_to_cartel = mode == "galaxy" and
        (phase == "arriving_in_cartel" or phase == "jumping_to_cartel")
    local jumping_to_system = (mode == "cartel" or mode == "galaxy") and
        (phase == "arriving_in_system" or phase == "jumping_to_system")

    if jumping_to_cartel or jumping_to_system then
        cecho(string.format("\n<yellow>[map-explore]<reset> Jump to '%s' refused, skipping...\n", dest))
        if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
            killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
            F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
        end
        F2T_SPEEDWALK_WAITING_FOR_MOVE = false
        F2T_SPEEDWALK_ACTIVE = false
        F2T_MAP_EXPLORE_STATE.phase = nil

        if jumping_to_cartel then
            F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = nil
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
                    f2t_map_explore_galaxy_next_cartel()
                end
            end)
        else
            F2T_MAP_EXPLORE_STATE.cartel_target_system = nil
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active and
                   (F2T_MAP_EXPLORE_STATE.mode == "cartel" or F2T_MAP_EXPLORE_STATE.mode == "galaxy") then
                    f2t_map_explore_cartel_next_system()
                end
            end)
        end
        return
    end
end

-- Ordinary planned speedwalk: fail the move now rather than waiting out the
-- timeout — the recompute will replan without the removed edge.
if F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_WAITING_FOR_MOVE then
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
    f2t_map_speedwalk_handle_move_failure()
end
