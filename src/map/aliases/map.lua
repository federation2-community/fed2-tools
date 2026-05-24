-- @patterns:
--   - pattern: ^map(?:\s+(.+))?$

-- Main map command - handles all map-related subcommands
local args = matches[2]

-- No arguments - show help
if not args or args == "" then
    f2t_show_registered_help("map")
    return
end

-- Check for help request
if f2t_handle_help("map", args) then
    return
end

-- Parse subcommand
local subcommand = string.lower(args):match("^(%S+)")

if subcommand == "on" then
    -- map on - Enable auto-mapping
    F2T_MAP_ENABLED = true
    f2t_settings_set("map", "enabled", true)
    cecho("\n<green>[map]<reset> Auto-mapping <yellow>ENABLED<reset>\n")
    f2t_debug_log("[map] Mapper enabled by user")

elseif subcommand == "off" then
    -- map off - Disable auto-mapping
    F2T_MAP_ENABLED = false
    f2t_settings_set("map", "enabled", false)
    cecho("\n<green>[map]<reset> Auto-mapping <red>DISABLED<reset>\n")
    f2t_debug_log("[map] Mapper disabled by user")

elseif subcommand == "sync" then
    -- map sync - Force synchronize with current room
    f2t_map_sync()

elseif subcommand == "clear" then
    -- map clear [confirm] - Clear the entire map with confirmation
    local confirm = args:match("^clear%s+(.+)")

    if not confirm or confirm ~= "confirm" then
        cecho("\n<yellow>[map]<reset> This will delete the ENTIRE map!\n")
        cecho("\n<yellow>[map]<reset> Type <white>map clear confirm<reset> to proceed.\n")
        f2t_debug_log("[map] Map clear requested, awaiting confirmation")
        return
    end

    -- User confirmed, clear the map
    f2t_debug_log("[map] Clearing map (confirmed by user)")

    -- Get all rooms and delete them
    local rooms = getRooms()
    local room_count = 0
    for room_id, _ in pairs(rooms) do
        deleteRoom(room_id)
        room_count = room_count + 1
    end

    -- Reset mapper state
    F2T_MAP_CURRENT_ROOM_ID = nil

    -- Update map display
    updateMap()

    cecho(string.format("\n<green>[map]<reset> Map cleared. %d rooms deleted.\n", room_count))
    f2t_debug_log("[map] Map cleared: %d rooms deleted", room_count)

    -- Sync with current location to rebuild
    if F2T_MAP_ENABLED then
        cecho("\n<green>[map]<reset> Synchronizing with current location...\n")
        f2t_map_sync()
    end

elseif subcommand == "dest" or subcommand == "destination" then
    -- map dest [add|remove|list] <name>
    local rest = args:match("^dest%s*(.*)") or args:match("^destination%s*(.*)") or ""

    -- Check for help request
    if f2t_handle_help("map dest", rest) then
        return
    end

    -- No arguments or "list" - show destinations
    if rest == "" or rest == "list" then
        f2t_map_destination_list()
        return
    end

    -- Parse subcommand and arguments
    local dest_subcommand, dest_rest = string.match(rest, "^(%S+)%s*(.*)$")
    if not dest_subcommand then
        dest_subcommand = rest
        dest_rest = ""
    end

    dest_subcommand = string.lower(dest_subcommand)

    -- Handle subcommands
    if dest_subcommand == "add" then
        if dest_rest == "" then
            cecho("\n<red>[map]<reset> Usage: map dest add <name>\n")
            return
        end
        f2t_map_destination_add(dest_rest)

    elseif dest_subcommand == "remove" or dest_subcommand == "rm" then
        if dest_rest == "" then
            cecho("\n<red>[map]<reset> Usage: map dest remove <name>\n")
            return
        end
        f2t_map_destination_remove(dest_rest)

    elseif dest_subcommand == "list" then
        f2t_map_destination_list()

    else
        cecho(string.format("\n<red>[map]<reset> Unknown dest command: %s\n", dest_subcommand))
        f2t_show_help_hint("map dest")
    end

elseif subcommand == "settings" then
    -- map settings [list|get|set|clear] [args]
    local settings_args = args:match("^settings%s*(.*)") or ""

    -- Check for help request
    if f2t_handle_help("map settings", settings_args) then
        return
    end

    f2t_handle_settings_command("map", settings_args)

elseif subcommand == "search" then
    -- map search <text> - search current area
    -- map search <planet|system> <text> - search planet or system
    -- map search all <text> - search all areas
    local rest = args:match("^search%s+(.+)") or ""

    -- Check for help request
    if f2t_handle_help("map search", rest) then
        return
    end

    if rest == "" then
        f2t_show_registered_help("map search")
        return
    end

    -- Parse arguments
    local words = f2t_parse_words(rest)

    -- Check if first word is "all"
    if string.lower(words[1]) == "all" then
        -- map search all <text>
        if #words < 2 then
            cecho("\n<red>[map]<reset> Missing search text after 'all'\n")
            return
        end

        local search_text = table.concat(words, " ", 2)
        local results = f2t_map_search_all(search_text)
        f2t_map_search_display(results, search_text, "all areas")

    else
        -- Try to parse as <location> <search_text>
        local location, search_text = f2t_map_parse_location_prefix(rest)

        if location then
            -- Found a location prefix, search in that location
            local results = f2t_map_search_planet_or_system(location, search_text)
            f2t_map_search_display(results, search_text, location)
        else
            -- No location prefix found, treat entire string as search text in current area
            search_text = rest

            -- Check current location
            if not f2t_map_ensure_current_location() then
                cecho("\n<yellow>[map]<reset> Current location unknown. Refreshing...\n")
                send("look")
                tempTimer(0.5, function()
                    expandAlias(string.format("map search %s", search_text))
                end)
                return
            end

            local results = f2t_map_search_current_area(search_text)
            if results == nil then
                cecho("\n<red>[map]<reset> Cannot determine current area\n")
                return
            end

            local current_area_id = getRoomArea(F2T_MAP_CURRENT_ROOM_ID)
            local area_name = f2t_map_get_area_name(current_area_id) or "current area"
            f2t_map_search_display(results, search_text, area_name)
        end
    end

elseif subcommand == "explore" then
    -- map explore [full|brief] [target]
    -- map explore [target]            (shorthand for brief mode)
    -- map explore cartel [name]       (cartel mode - brief only)
    -- map explore galaxy              (galaxy mode - brief only)
    -- map explore stop|pause|resume|status|suspected
    local rest = args:match("^explore%s*(.*)") or ""

    -- Check for help request
    if f2t_handle_help("map explore", rest) then
        return
    end

    -- No arguments - context-aware exploration (brief mode)
    if rest == "" then
        f2t_map_explore_start("brief")
        return
    end

    -- Parse explore subcommand
    local words = f2t_parse_words(rest)
    local first = string.lower(words[1])

    -- Check for mode specifier (full or brief)
    if first == "full" or first == "brief" then
        -- Mode specified: words[1]=mode, words[2...]=target (or nil for context-aware)
        local mode = first
        local target = words[2] and f2t_parse_rest(words, 2) or nil
        f2t_map_explore_start(mode, target)

    elseif first == "cartel" then
        -- map explore cartel [cartel_name]
        local cartel_name = f2t_parse_rest(words, 2)

        -- Default: use current cartel from map metadata
        if not cartel_name or cartel_name == "" then
            cartel_name = f2t_map_get_current_cartel()
        end

        if not cartel_name or cartel_name == "" then
            cecho("\n<red>[map]<reset> Error: No cartel specified and couldn't detect current cartel\n")
            cecho("\n<dim_grey>Usage: map explore cartel <cartel><reset>\n")
            cecho("\n<dim_grey>Example: map explore cartel Frontier<reset>\n")
            return
        end

        f2t_map_explore_cartel_start(cartel_name)

    elseif first == "galaxy" then
        -- map explore galaxy
        -- No parameters - starts from current cartel, explores all cartels in galaxy
        f2t_map_explore_galaxy_start()

    elseif first == "stop" then
        f2t_map_explore_stop()

    elseif first == "pause" then
        f2t_map_explore_pause()

    elseif first == "resume" then
        f2t_map_explore_resume()

    elseif first == "status" then
        f2t_map_explore_status()

    elseif first == "suspected" then
        f2t_map_explore_list_suspected()

    else
        -- Treat as target name with default brief mode
        -- Auto-detects whether it's a planet or system
        local target = f2t_parse_rest(words, 1)
        f2t_map_explore_start("brief", target)
    end

elseif subcommand == "room" then
    -- map room [add|delete|info|set] [args]
    local rest = args:match("^room%s*(.*)") or ""

    -- Check for help request
    if f2t_handle_help("map room", rest) then
        return
    end

    if rest == "" then
        f2t_show_registered_help("map room")
        return
    end

    local words = f2t_parse_words(rest)
    local room_subcmd = words[1]

    if room_subcmd == "add" then
        -- map room add <system> <area> <num> [name]
        local system = words[2]
        local area = words[3]
        local num = tonumber(words[4])
        local name = string.match(rest, "^add%s+%S+%s+%S+%s+%S+%s+(.+)$")

        if not system or not area or not num then
            cecho("\n<red>[map]<reset> Usage: map room add <system> <area> <num> [name]\n")
            f2t_show_help_hint("map room")
            return
        end

        f2t_map_manual_create_room(system, area, num, name)

    elseif room_subcmd == "delete" then
        -- map room delete [room_id] - defaults to current room
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)

        if not room_id then
            if not error_shown then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                f2t_show_help_hint("map room")
            end
            return
        end

        f2t_map_manual_delete_room(room_id)

    elseif room_subcmd == "info" then
        -- map room info [room_id] - defaults to current room
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)

        if not room_id then
            if not error_shown then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                f2t_show_help_hint("map room")
            end
            return
        end

        f2t_map_manual_room_info(room_id)

    elseif room_subcmd == "set" then
        -- map room set <property> [room_id] <value...>
        -- If room_id is omitted, uses current room
        local property = words[2]

        if not property then
            cecho("\n<red>[map]<reset> Usage: map room set <property> [room_id] <value...>\n")
            f2t_show_help_hint("map room")
            return
        end

        if property == "name" then
            -- Room names can be multi-word, so parse accordingly
            local room_id, name
            local potential_room = tonumber(words[3])

            if potential_room and words[4] then
                -- Format: set name <room_id> <name...>
                room_id = potential_room
                name = f2t_parse_rest(words, 4)
            else
                -- Format: set name <name...>
                room_id = F2T_MAP_CURRENT_ROOM_ID
                name = f2t_parse_rest(words, 3)
            end

            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            if not name or name == "" then
                cecho("\n<red>[map]<reset> Usage: map room set name [room_id] <name>\n")
                return
            end
            f2t_map_manual_set_room_name(room_id, name)

        elseif property == "area" then
            -- map room set area [room_id] <area>
            local room_id, area, success = f2t_map_parse_optional_room_and_arg(words, 3)

            if not success or not area then
                cecho("\n<red>[map]<reset> Usage: map room set area [room_id] <area>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            f2t_map_manual_set_room_area(room_id, area)

        elseif property == "coords" then
            local room_id, args, success = f2t_map_parse_optional_room_and_args(words, 3, 3)
            if not success then
                cecho("\n<red>[map]<reset> Usage: map room set coords [room_id] <x> <y> <z>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
            if not x or not y or not z then
                cecho("\n<red>[map]<reset> Coordinates must be numbers\n")
                cecho("\n<red>[map]<reset> Usage: map room set coords [room_id] <x> <y> <z>\n")
                return
            end
            f2t_map_manual_set_room_coords(room_id, x, y, z)

        elseif property == "symbol" then
            local room_id, symbol, success = f2t_map_parse_optional_room_and_arg(words, 3)
            if not success or not symbol then
                cecho("\n<red>[map]<reset> Usage: map room set symbol [room_id] <char>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            f2t_map_manual_set_room_symbol(room_id, symbol)

        elseif property == "color" then
            local room_id, args, success = f2t_map_parse_optional_room_and_args(words, 3, 3)
            if not success then
                cecho("\n<red>[map]<reset> Usage: map room set color [room_id] <r> <g> <b>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            local r, g, b = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
            if not r or not g or not b then
                cecho("\n<red>[map]<reset> Color values must be numbers\n")
                cecho("\n<red>[map]<reset> Usage: map room set color [room_id] <r> <g> <b>\n")
                return
            end
            f2t_map_manual_set_room_color(room_id, r, g, b)

        elseif property == "env" then
            local room_id, env_str, success = f2t_map_parse_optional_room_and_arg(words, 3)
            if not success or not env_str then
                cecho("\n<red>[map]<reset> Usage: map room set env [room_id] <env_id>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            local env_id = tonumber(env_str)
            if not env_id then
                cecho("\n<red>[map]<reset> Environment ID must be a number\n")
                cecho("\n<red>[map]<reset> Usage: map room set env [room_id] <env_id>\n")
                return
            end
            f2t_map_manual_set_room_env(room_id, env_id)

        elseif property == "weight" then
            local room_id, weight_str, success = f2t_map_parse_optional_room_and_arg(words, 3)
            if not success or not weight_str then
                cecho("\n<red>[map]<reset> Usage: map room set weight [room_id] <weight>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            local weight = tonumber(weight_str)
            if not weight then
                cecho("\n<red>[map]<reset> Weight must be a number\n")
                cecho("\n<red>[map]<reset> Usage: map room set weight [room_id] <weight>\n")
                return
            end
            f2t_map_manual_set_room_weight(room_id, weight)

        else
            cecho(string.format("\n<red>[map]<reset> Unknown property: %s\n", property))
            cecho("\n<dim_grey>Available: name, area, coords, symbol, color, env, weight<reset>\n")
        end

    elseif room_subcmd == "lock" then
        -- map room lock [room_id] - defaults to current room
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)
        if not room_id then
            if not error_shown then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                f2t_show_help_hint("map room")
            end
            return
        end
        f2t_map_manual_lock_room(room_id)

    elseif room_subcmd == "unlock" then
        -- map room unlock [room_id] - defaults to current room
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)
        if not room_id then
            if not error_shown then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                f2t_show_help_hint("map room")
            end
            return
        end
        f2t_map_manual_unlock_room(room_id)

    elseif room_subcmd == "death" then
        -- map room death <room_id> - mark a specific room as death/danger (room_id required)
        local room_id = tonumber(words[2])
        if not room_id then
            cecho("\n<red>[map]<reset> Usage: map room death <room_id>\n")
            cecho("\n<dim_grey>A room ID is required (you cannot be standing in a death room)<reset>\n")
            return
        end
        f2t_map_manual_mark_room_death(room_id)

    elseif room_subcmd == "safe" then
        -- map room safe [room_id] - mark room as safe from auto-locking (defaults to current)
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)
        if not room_id then
            if not error_shown then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                f2t_show_help_hint("map room")
            end
            return
        end
        f2t_map_manual_mark_room_safe(room_id)

    elseif room_subcmd == "unsafe" then
        -- map room unsafe [room_id] - remove safe mark and mark as death (defaults to current)
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)
        if not room_id then
            if not error_shown then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                f2t_show_help_hint("map room")
            end
            return
        end
        f2t_map_manual_mark_room_unsafe(room_id)

    else
        cecho(string.format("\n<red>[map]<reset> Unknown room command: %s\n", room_subcmd))
        f2t_show_help_hint("map room")
    end

elseif subcommand == "confirm" then
    -- map confirm - Confirm pending action
    f2t_map_manual_confirm()

elseif subcommand == "cancel" then
    -- map cancel - Cancel pending confirmation
    f2t_map_manual_cancel_confirmation()

elseif subcommand == "restyle" then
    -- map restyle - Re-apply styling to all rooms based on their current metadata
    f2t_map_restyle_all()

elseif subcommand == "raw" then
    -- map raw - Show raw mapper + GMCP data for current room
    -- map raw [room_id] - Show raw mapper data for specified room
    local rest = args:match("^raw%s*(.*)") or ""

    -- Check for help request
    if f2t_handle_help("map raw", rest) then
        return
    end

    if rest == "" then
        -- No arguments - show mapper + GMCP data for current room
        f2t_map_raw_display_room(nil, true)
    else
        -- Try to parse as room ID
        local room_id = tonumber(rest)
        if room_id then
            f2t_map_raw_display_room(room_id, false)
        else
            cecho("\n<red>[map]<reset> Usage: map raw [room_id]\n")
            cecho("\n<dim_grey>No arguments: Show mapper + GMCP data for current room<reset>\n")
            cecho("\n<dim_grey>With room ID: Show mapper data for specified room<reset>\n")
        end
    end

elseif subcommand == "exit" then
    -- map exit [special|add|remove|list] [args]
    -- Get current room
    local current_room = f2t_map_ensure_current_room(args)
    if not current_room then return end

    local rest = args:match("^exit%s*(.*)") or ""

    -- Check for help request
    if f2t_handle_help("map exit", rest) then
        return
    end

    -- No arguments - show help
    if rest == "" then
        f2t_show_registered_help("map exit")
        return
    end

    -- Parse subcommand
    local words = f2t_parse_words(rest)
    local exit_subcmd = words[1]

    if exit_subcmd == "special" then
        -- map exit special <command> (discovery)
        -- map exit special reverse [cmd]
        -- map exit special <dest> <cmd> (manual 2-arg)
        -- map exit special <src> <dest> <cmd> (manual 3-arg)
        -- map exit special list [room]
        -- map exit special remove <cmd>
        -- map exit special remove <room> <cmd>

        local dest_or_remove = words[2]

        -- Check for help request
        if f2t_handle_help("map exit special", dest_or_remove) then
            return
        end

        if not dest_or_remove then
            f2t_show_registered_help("map exit special")
            return
        end

        if dest_or_remove == "list" then
            -- map exit special list [room_id]
            local room_id = current_room
            if words[3] then
                room_id = tonumber(words[3])
                if not room_id then
                    cecho("\n<red>[map]<reset> Invalid room ID: must be a number\n")
                    return
                end
            end

            if not roomExists(room_id) then
                cecho(string.format("\n<red>[map]<reset> Room %d does not exist\n", room_id))
                return
            end

            local room_name = getRoomName(room_id)
            local exits = f2t_map_special_get_all_exits(room_id)

            cecho(string.format("\n<green>[map]<reset> Special exits for room %d (<white>%s<reset>)\n",
                room_id, room_name or "unnamed"))

            if exits and next(exits) ~= nil then
                for command, dest_room_id in pairs(exits) do
                    local dest_name = getRoomName(dest_room_id) or "unnamed"
                    local dest_hash = f2t_map_generate_hash_from_room(dest_room_id) or "unknown"

                    -- Check if this is an auto-transit command (__move_no_op_<room_id>)
                    if command:match("^__move_no_op_%d+$") then
                        cecho(string.format("  <yellow>%s<reset> <dim_grey>(auto-transit)<reset> -> <white>%s<reset> <dim_grey>[%d | %s]<reset>\n",
                            command, dest_name, dest_room_id, dest_hash))
                    else
                        cecho(string.format("  <yellow>%s<reset> -> <white>%s<reset> <dim_grey>[%d | %s]<reset>\n",
                            command, dest_name, dest_room_id, dest_hash))
                    end
                end
            else
                cecho("\n<dim_grey>No special exits configured for this room.<reset>\n")
            end

        elseif dest_or_remove == "reverse" then
            -- map exit special reverse [command]
            -- If no command specified, uses pending discovery state
            -- If command specified, finds that exit and reverses it

            -- Get full command (everything after "reverse") - may be nil
            local command = string.match(rest, "^special%s+reverse%s+(.+)$")

            local success, error_msg, from_room, to_room, used_command =
                f2t_map_special_reverse_exit(current_room, command)

            if success then
                local from_name = getRoomName(from_room) or string.format("Room %d", from_room)
                local to_name = getRoomName(to_room) or string.format("Room %d", to_room)

                cecho(string.format("\n<green>[map]<reset> Reverse special exit created: <white>%s<reset> -> <white>%s<reset>\n",
                    from_name, to_name))

                if used_command == "noop" then
                    cecho("\n<dim_grey>  Command: (auto-transit, wait for GMCP)<reset>\n")
                else
                    cecho(string.format("\n<dim_grey>  Command: %s<reset>\n", used_command))
                end
            else
                cecho(string.format("\n<red>[map]<reset> Error: %s\n", error_msg or "Failed to create reverse exit"))
            end

        elseif dest_or_remove == "remove" then
            -- map exit special remove <command>
            -- map exit special remove <room_id> <command>
            if #words < 3 then
                cecho("\n<red>[map]<reset> Usage: map exit special remove <command>\n")
                cecho("\n<red>[map]<reset> Usage: map exit special remove <room_id> <command>\n")
                return
            end

            -- Check if words[3] is a number to determine form
            local room_id, command
            local third_word_is_number = tonumber(words[3]) ~= nil

            if third_word_is_number then
                -- 2-arg form: remove <room_id> <command>
                room_id = tonumber(words[3])
                if not room_id then
                    cecho("\n<red>[map]<reset> Invalid room ID: must be a number\n")
                    return
                end

                -- Get command (everything after room_id)
                command = string.match(rest, "^special%s+remove%s+%d+%s+(.+)$")
            else
                -- 1-arg form: remove <command> (defaults to current room)
                room_id = current_room

                -- Get full command (everything after "remove")
                command = string.match(rest, "^special%s+remove%s+(.+)$")
            end

            if not command then
                cecho("\n<red>[map]<reset> Invalid command\n")
                return
            end

            local success = f2t_map_special_remove_exit(room_id, command)
            if success then
                cecho(string.format("\n<green>[map]<reset> Special exit removed: <yellow>%s<reset>\n", command))
            else
                cecho(string.format("\n<yellow>[map]<reset> No special exit found for command: %s\n", command))
            end
        else
            -- Try to determine if this is:
            -- 1. Discovery-based: map exit special <command> (dest_or_remove is not a number)
            -- 2. Manual 2-arg: map exit special <dest_room_id> <command> (dest_or_remove is a number, words[3] is not a number)
            -- 3. Manual 3-arg: map exit special <source_room_id> <dest_room_id> <command> (dest_or_remove is a number, words[3] is a number)

            local second_is_number = tonumber(dest_or_remove) ~= nil
            local third_is_number = words[3] and tonumber(words[3]) ~= nil

            if not second_is_number then
                -- Discovery-based workflow: map exit special <command>
                -- Get the full command (everything after "special")
                local command = string.match(rest, "^special%s+(.+)$")
                if not command then
                    cecho("\n<red>[map]<reset> Invalid command\n")
                    return
                end

                -- Start the discovery process
                f2t_map_special_exit_discovery_start(current_room, command)

            elseif second_is_number and third_is_number then
                -- Manual 3-arg form: source dest command
                local source_room_id = tonumber(words[2])
                local dest_room_id = tonumber(words[3])

                if not source_room_id or not dest_room_id then
                    cecho("\n<red>[map]<reset> Invalid room IDs: must be numbers\n")
                    return
                end

                -- Get command (everything after two room IDs)
                local command = string.match(rest, "^special%s+%d+%s+%d+%s+(.+)$")
                if not command then
                    cecho("\n<red>[map]<reset> Missing command\n")
                    return
                end

                -- Create the special exit
                local success = f2t_map_special_set_exit(source_room_id, dest_room_id, command)
                if success then
                    local from_name = getRoomName(source_room_id) or string.format("Room %d", source_room_id)
                    local to_name = getRoomName(dest_room_id) or string.format("Room %d", dest_room_id)

                    if command == "noop" then
                        cecho(string.format("\n<green>[map]<reset> Special exit created: <white>%s<reset> -> <white>%s<reset>\n",
                            from_name, to_name))
                        cecho("\n<dim_grey>  Command: (auto-transit, wait for GMCP)<reset>\n")
                    else
                        cecho(string.format("\n<green>[map]<reset> Special exit created: <white>%s<reset> -> <white>%s<reset>\n",
                            from_name, to_name))
                        cecho(string.format("\n<dim_grey>  Command: %s<reset>\n", command))
                    end
                else
                    cecho("\n<red>[map]<reset> Failed to create special exit\n")
                end

            else
                -- Manual 2-arg form: dest command (source defaults to current room)
                local source_room_id = current_room
                local dest_room_id = tonumber(words[2])

                if not dest_room_id then
                    cecho("\n<red>[map]<reset> Invalid room ID: must be a number\n")
                    return
                end

                -- Get command (everything after dest_room_id)
                local command = string.match(rest, "^special%s+%d+%s+(.+)$")
                if not command then
                    cecho("\n<red>[map]<reset> Missing command\n")
                    return
                end

                -- Create the special exit
                local success = f2t_map_special_set_exit(source_room_id, dest_room_id, command)
                if success then
                    local from_name = getRoomName(source_room_id) or string.format("Room %d", source_room_id)
                    local to_name = getRoomName(dest_room_id) or string.format("Room %d", dest_room_id)

                    if command == "noop" then
                        cecho(string.format("\n<green>[map]<reset> Special exit created: <white>%s<reset> -> <white>%s<reset>\n",
                            from_name, to_name))
                        cecho("\n<dim_grey>  Command: (auto-transit, wait for GMCP)<reset>\n")
                    else
                        cecho(string.format("\n<green>[map]<reset> Special exit created: <white>%s<reset> -> <white>%s<reset>\n",
                            from_name, to_name))
                        cecho(string.format("\n<dim_grey>  Command: %s<reset>\n", command))
                    end
                else
                    cecho("\n<red>[map]<reset> Failed to create special exit\n")
                end
            end
        end

    elseif exit_subcmd == "add" then
        -- map exit add <from> <to> <direction>
        if #words < 4 then
            cecho("\n<red>[map]<reset> Usage: map exit add <from_room_id> <to_room_id> <direction>\n")
            return
        end

        local from_room = tonumber(words[2])
        local to_room = tonumber(words[3])
        local direction = words[4]

        if not from_room or not to_room then
            cecho("\n<red>[map]<reset> Room IDs must be numbers\n")
            return
        end

        f2t_map_manual_add_exit(from_room, to_room, direction, false)

    elseif exit_subcmd == "remove" then
        -- map exit remove <room_id> <direction>
        if #words < 3 then
            cecho("\n<red>[map]<reset> Usage: map exit remove <room_id> <direction>\n")
            return
        end

        local room_id = tonumber(words[2])
        local direction = words[3]

        if not room_id then
            cecho("\n<red>[map]<reset> Room ID must be a number\n")
            return
        end

        f2t_map_manual_remove_exit(room_id, direction)

    elseif exit_subcmd == "list" then
        -- map exit list <room_id>
        local room_id
        if words[2] then
            room_id = tonumber(words[2])
            if not room_id then
                cecho("\n<red>[map]<reset> Room ID must be a number\n")
                return
            end
        else
            room_id = current_room
        end

        f2t_map_manual_list_exits(room_id)

    elseif exit_subcmd == "lock" then
        -- map exit lock [room_id] <direction>
        local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 2)

        if not success then
            cecho("\n<red>[map]<reset> Usage: map exit lock [room_id] <direction>\n")
            f2t_show_help_hint("map exit")
            return
        end

        if not room_id then
            cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
            return
        end

        f2t_map_manual_lock_exit(room_id, direction)

    elseif exit_subcmd == "unlock" then
        -- map exit unlock [room_id] <direction>
        local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 2)

        if not success then
            cecho("\n<red>[map]<reset> Usage: map exit unlock [room_id] <direction>\n")
            f2t_show_help_hint("map exit")
            return
        end

        if not room_id then
            cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
            return
        end

        f2t_map_manual_unlock_exit(room_id, direction)

    elseif exit_subcmd == "death" then
        -- map exit death [room_id] <direction>
        local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 2)

        if not success then
            cecho("\n<red>[map]<reset> Usage: map exit death [room_id] <direction>\n")
            f2t_show_help_hint("map exit")
            return
        end

        if not room_id then
            cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
            return
        end

        f2t_map_manual_death_exit(room_id, direction)

    elseif exit_subcmd == "stub" then
        -- map exit stub [create|delete|connect|list] [args]
        local stub_subcmd = words[2]

        -- Check for help request
        if f2t_handle_help("map exit stub", stub_subcmd) then
            return
        end

        if not stub_subcmd then
            f2t_show_registered_help("map exit stub")
            return
        end

        if stub_subcmd == "create" then
            -- map exit stub create [room_id] <direction>
            local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 3)

            if not success then
                cecho("\n<red>[map]<reset> Usage: map exit stub create [room_id] <direction>\n")
                return
            end

            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end

            f2t_map_manual_create_stub(room_id, direction)

        elseif stub_subcmd == "delete" then
            -- map exit stub delete [room_id] <direction>
            local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 3)

            if not success then
                cecho("\n<red>[map]<reset> Usage: map exit stub delete [room_id] <direction>\n")
                return
            end

            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end

            f2t_map_manual_delete_stub(room_id, direction)

        elseif stub_subcmd == "connect" then
            -- map exit stub connect [room_id] <direction>
            local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 3)

            if not success then
                cecho("\n<red>[map]<reset> Usage: map exit stub connect [room_id] <direction>\n")
                return
            end

            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end

            f2t_map_manual_connect_stub(room_id, direction)

        elseif stub_subcmd == "list" then
            -- map exit stub list [room_id]
            local room_id
            if words[3] then
                room_id = tonumber(words[3])
                if not room_id then
                    cecho("\n<red>[map]<reset> Room ID must be a number\n")
                    return
                end
            else
                room_id = current_room
            end

            f2t_map_manual_list_stubs(room_id)

        else
            cecho(string.format("\n<red>[map]<reset> Unknown stub command: %s\n", stub_subcmd))
            f2t_show_help_hint("map exit stub")
        end

    else
        cecho(string.format("\n<red>[map]<reset> Unknown exit subcommand: %s\n", exit_subcmd))
        f2t_show_help_hint("map exit")
    end

elseif subcommand == "special" then
    -- map special [arrival|circuit] [args]
    -- Get current room
    local current_room = f2t_map_ensure_current_room(args)
    if not current_room then return end

    local rest = args:match("^special%s*(.*)") or ""

    -- No arguments or help request - show help
    if rest == "" or f2t_handle_help("map special", rest) then
        if rest == "" then
            f2t_show_registered_help("map special")
        end
        return
    end

    -- Parse subcommand
    local words = f2t_parse_words(rest)
    local special_subcmd = words[1]

    if special_subcmd == "arrival" then
        -- map special arrival <command>
        -- map special arrival remove
        -- map special arrival list
        local arrival_rest = string.match(rest, "^arrival%s*(.*)") or ""

        if arrival_rest == "" or f2t_handle_help("map special arrival", arrival_rest) then
            if arrival_rest == "" then
                f2t_show_registered_help("map special arrival")
            end
            return
        end

        local command_or_remove = words[2]

        if command_or_remove == "list" then
            -- List all rooms with on-arrival commands
            f2t_map_special_list_arrivals()
        elseif command_or_remove == "remove" then
            -- Remove on-arrival command
            local success = f2t_map_special_remove_arrival(current_room)
            if success then
                cecho("\n<green>[map]<reset> On-arrival command removed\n")
            else
                cecho("\n<red>[map]<reset> Failed to remove on-arrival command\n")
            end
        else
            -- Set on-arrival command (everything after "arrival")
            -- Format: map special arrival [always|once-room|once-area|once-ever] <command>
            local type_or_command = command_or_remove
            local exec_type = F2T_MAP_ARRIVAL_TYPE_ALWAYS  -- Default

            -- Check if first word is a type
            if type_or_command == "always" or type_or_command == "once-room" or
               type_or_command == "once-area" or type_or_command == "once-ever" then
                exec_type = type_or_command

                -- Get command from remaining words after type (words[1]=arrival, words[2]=type, words[3+]=command)
                if #words < 3 then
                    cecho("\n<red>[map]<reset> Missing command after execution type\n")
                    cecho("\n<dim_grey>Usage: map special arrival [type] <command><reset>\n")
                    cecho("\n<dim_grey>Types: always, once-room, once-area, once-ever<reset>\n")
                    return
                end

                local command_parts = {}
                for i = 3, #words do
                    table.insert(command_parts, words[i])
                end
                local command = table.concat(command_parts, " ")

                local success = f2t_map_special_set_arrival(current_room, command, exec_type)
                if success then
                    cecho(string.format("\n<green>[map]<reset> On-arrival command set (<cyan>%s<reset>): <white>%s<reset>\n",
                        exec_type, command))
                else
                    cecho("\n<red>[map]<reset> Failed to set on-arrival command\n")
                end
            else
                -- No type specified, use default (always) and treat everything as command
                local command = string.match(rest, "^arrival%s+(.+)$")
                if not command then
                    cecho("\n<red>[map]<reset> Invalid command\n")
                    return
                end

                local success = f2t_map_special_set_arrival(current_room, command, exec_type)
                if success then
                    cecho(string.format("\n<green>[map]<reset> On-arrival command set: <white>%s<reset>\n", command))
                else
                    cecho("\n<red>[map]<reset> Failed to set on-arrival command\n")
                end
            end
        end

    elseif special_subcmd == "circuit" then
        -- map special circuit [create|set|stop|connect|list|show|delete] [args]
        local circuit_rest = string.match(args, "^special%s+circuit%s*(.*)") or ""

        if circuit_rest == "" or f2t_handle_help("map special circuit", circuit_rest) then
            if circuit_rest == "" then
                f2t_show_registered_help("map special circuit")
            end
            return
        end

        local circuit_subcmd = words[2]

        if circuit_subcmd == "create" then
            -- map special circuit create <circuit_id>
            local circuit_id = words[3]
            f2t_map_circuit_cmd_create(circuit_id)

        elseif circuit_subcmd == "set" then
            -- map special circuit set <circuit_id> <property> <value>
            local circuit_id = words[3]
            local property = words[4]
            local value = string.match(rest, "^circuit%s+set%s+%S+%s+%S+%s+(.+)$")
            f2t_map_circuit_cmd_set(circuit_id, property, value)

        elseif circuit_subcmd == "stop" then
            -- map special circuit stop [add|set] [args]
            local stop_action = words[3]

            if not stop_action then
                cecho("\n<red>[map]<reset> Usage: map special circuit stop add <id> <name>\n")
                cecho("\n<red>[map]<reset> Usage: map special circuit stop set <id> <name> arrival_pattern <pattern>\n")
                return
            end

            if stop_action == "add" then
                -- map special circuit stop add <circuit_id> <stop_name>
                local circuit_id = words[4]
                local stop_name = words[5]
                f2t_map_circuit_cmd_stop_add(circuit_id, stop_name)

            elseif stop_action == "set" then
                -- map special circuit stop set <circuit_id> <stop_name> arrival_pattern <pattern>
                local circuit_id = words[4]
                local stop_name = words[5]
                local property = words[6]
                local value = string.match(rest, "^circuit%s+stop%s+set%s+%S+%s+%S+%s+arrival_pattern%s+(.+)$")
                f2t_map_circuit_cmd_stop_set(circuit_id, stop_name, property, value)

            else
                cecho(string.format("\n<red>[map]<reset> Unknown stop command: %s\n", stop_action))
            end

        elseif circuit_subcmd == "connect" then
            -- map special circuit connect <circuit_id>
            local circuit_id = words[3]
            f2t_map_circuit_cmd_connect(circuit_id)

        elseif circuit_subcmd == "list" then
            -- map special circuit list
            f2t_map_circuit_cmd_list()

        elseif circuit_subcmd == "show" then
            -- map special circuit show <circuit_id>
            local circuit_id = words[3]
            f2t_map_circuit_cmd_show(circuit_id)

        elseif circuit_subcmd == "delete" then
            -- map special circuit delete <circuit_id>
            local circuit_id = words[3]
            f2t_map_circuit_cmd_delete(circuit_id)

        else
            cecho(string.format("\n<red>[map]<reset> Unknown circuit command: %s\n", circuit_subcmd))
        end

    else
        cecho(string.format("\n<red>[map]<reset> Unknown special subcommand: %s\n", special_subcmd))
        f2t_show_help_hint("map special")
    end

elseif subcommand == "export" then
    -- map export - Opens file dialog for user to select save location
    local rest = args:match("^export%s*(.*)") or ""

    -- Check for help request
    if f2t_handle_help("map export", rest) then
        return
    end

    f2t_map_export()

elseif subcommand == "import" then
    -- map import - Opens file dialog for user to select file, requires 'map confirm'
    local rest = args:match("^import%s*(.*)") or ""

    -- Check for help request
    if f2t_handle_help("map import", rest) then
        return
    end

    if rest ~= "" then
        cecho(string.format("\n<red>[map]<reset> Unknown import option: %s\n", rest))
        f2t_show_help_hint("map import")
        return
    end

    f2t_map_import()

else
    cecho(string.format("\n<red>[map]<reset> Unknown command: %s\n", subcommand))
    f2t_show_help_hint("map")
end
