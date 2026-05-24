-- Map-specific argument parsing utilities
-- Provides helpers for map commands that use optional room_id patterns

-- ========================================
-- Optional Room ID Parsing
-- ========================================

--- Parse optional room_id argument with fallback to current room
--- Supports: numeric room ID, Fed2 hash (system.area.num), or current room fallback
--- Used for: map room delete [room_id], map room info [room_id], etc.
--- @param words table Parsed words array
--- @param index number Word index where room_id might be
--- @return number|nil room_id Parsed room ID, current room, or nil on error
--- @return boolean error_shown True if an error message was already displayed
function f2t_map_parse_optional_room_id(words, index)
    -- No argument provided - use current room
    if not words[index] then
        return F2T_MAP_CURRENT_ROOM_ID, false
    end

    -- Try numeric room ID first
    local room_id = tonumber(words[index])
    if room_id then
        return room_id, false
    end

    -- Try Fed2 hash - rejoin remaining words (hash may contain spaces like "Sol Space")
    local potential_hash = f2t_parse_rest(words, index)

    -- Check if it matches Fed2 hash pattern: system.area.num
    if potential_hash:match("^[^%.]+%.[^%.]+%.%d+$") then
        room_id = getRoomIDbyHash(potential_hash)
        if room_id and room_id > 0 then
            return room_id, false
        else
            -- Hash format valid but room not found
            cecho(string.format("\n<red>[map]<reset> Room with hash '%s' not found in map\n", potential_hash))
            return nil, true
        end
    end

    -- Argument provided but not a valid room ID or hash - error
    cecho(string.format("\n<red>[map]<reset> '%s' is not a valid room ID or Fed2 hash\n", potential_hash))
    return nil, true
end

--- Parse optional room_id + required argument pattern
--- Used for: map exit lock [room_id] <dir>, map exit stub create [room_id] <dir>
--- @param words table Parsed words array
--- @param start_index number Index where room_id might be (typically 2)
--- @return number|nil room_id Parsed room ID or current room, or nil if insufficient args
--- @return string|nil arg The required argument after room_id
--- @return boolean success True if parsing succeeded
function f2t_map_parse_optional_room_and_arg(words, start_index)
    if not words[start_index] then
        return nil, nil, false
    end

    -- Check if first param is a number (room_id provided)
    local potential_room = tonumber(words[start_index])
    if potential_room then
        if words[start_index + 1] then
            -- Format: command <room_id> <arg>
            return potential_room, words[start_index + 1], true
        else
            -- Number provided but no following argument - insufficient
            return nil, nil, false
        end
    end

    -- Format: command <arg> (use current room)
    return F2T_MAP_CURRENT_ROOM_ID, words[start_index], true
end

--- Parse optional room_id + multiple required arguments
--- Used for: map room set coords [room_id] <x> <y> <z>
--- @param words table Parsed words array
--- @param start_index number Index where room_id might be
--- @param arg_count number Number of required arguments after room_id
--- @return number|nil room_id Parsed room ID or current room
--- @return table|nil args Array of parsed arguments
--- @return boolean success True if parsing succeeded
function f2t_map_parse_optional_room_and_args(words, start_index, arg_count)
    local total_with_room = start_index + arg_count
    local total_without_room = start_index + arg_count - 1

    -- Check if room_id is provided (all params are numbers)
    if #words >= total_with_room then
        local room_id = tonumber(words[start_index])
        if room_id then
            -- Collect remaining args
            local args = {}
            for i = 1, arg_count do
                table.insert(args, words[start_index + i])
            end
            return room_id, args, true
        end
    end

    -- Check if room_id is NOT provided (current room + args)
    if #words >= total_without_room then
        local args = {}
        for i = 0, arg_count - 1 do
            table.insert(args, words[start_index + i])
        end
        return F2T_MAP_CURRENT_ROOM_ID, args, true
    end

    -- Insufficient arguments
    return nil, nil, false
end

-- ========================================
-- Current Room Validation
-- ========================================

--- Validate current room exists and offer refresh if not
--- Used at start of commands that require current room context
--- @param args string Original command args for retry
--- @return number|nil current_room Current room ID or nil (with refresh triggered)
function f2t_map_ensure_current_room(args)
    local current_room = F2T_MAP_CURRENT_ROOM_ID

    if not current_room or not roomExists(current_room) then
        cecho("\n<yellow>[map]<reset> No current room detected. Refreshing location data...\n")
        send("look")

        local original_command = string.format("map %s", args)
        tempTimer(0.5, function()
            current_room = F2T_MAP_CURRENT_ROOM_ID
            if not current_room or not roomExists(current_room) then
                cecho("\n<red>[map]<reset> Error: Still no current room. Are you connected and mapped?\n")
                cecho("\n<dim_grey>Try running 'map sync' to force synchronization.<reset>\n")
            else
                cecho("\n<green>[map]<reset> Location refreshed. Retrying command...\n")
                expandAlias(original_command)
            end
        end)
        return nil
    end

    return current_room
end

f2t_debug_log("[map] Map-specific argument parsing utilities initialized")
