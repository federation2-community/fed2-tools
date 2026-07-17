if not F2T_MAP_EXPLORE_STATE or not F2T_MAP_EXPLORE_STATE.active then
    return
end

local mode = F2T_MAP_EXPLORE_STATE.mode
local phase = F2T_MAP_EXPLORE_STATE.phase
local closed_system = matches[2]

local is_jumping_to_cartel = mode == "galaxy" and phase == "arriving_in_cartel"
local is_jumping_to_system = (mode == "cartel" or mode == "galaxy") and phase == "arriving_in_system"

if not is_jumping_to_cartel and not is_jumping_to_system then
    return
end

f2t_debug_log("[map-explore] System '%s' is closed to visitors, skipping", closed_system)
cecho(string.format("\n<yellow>[map-explore]<reset> System '%s' is closed to visitors, skipping...\n", closed_system))

if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
    killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
end
F2T_SPEEDWALK_WAITING_FOR_MOVE = false
F2T_SPEEDWALK_ACTIVE = false

F2T_MAP_EXPLORE_STATE.phase = nil

if is_jumping_to_cartel then
    F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = nil
    tempTimer(0.5, function()
        if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
            f2t_map_explore_galaxy_next_cartel()
        end
    end)
elseif is_jumping_to_system then
    F2T_MAP_EXPLORE_STATE.cartel_target_system = nil
    tempTimer(0.5, function()
        if F2T_MAP_EXPLORE_STATE.active and
           (F2T_MAP_EXPLORE_STATE.mode == "cartel" or F2T_MAP_EXPLORE_STATE.mode == "galaxy") then
            f2t_map_explore_cartel_next_system()
        end
    end)
end
