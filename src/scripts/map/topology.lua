-- Galaxy topology model.
--
-- Jump legality is a pure function of: which cartel each system belongs to,
-- which syndicate each cartel belongs to, each hub system (cartel hub ==
-- cartel name, syndicate hub cartel == syndicate name, except Prime whose hub
-- is Sol), and each syndicate's beacon builds. This module owns those facts
-- and derives every link room's "jump <system>" special exits from them, so
-- Mudlet's native getPath() plans over exactly the legal jump graph.
-- Sources of truth: gmcp.room.info.jumps corrects the model as you travel
-- (f2t_map_topology_apply_gmcp); "display cartels"/"display syndicates"
-- captures sync it wholesale (topology_capture.lua).
--
-- Rule set (verified against game server code):
--   1. Always: any member system -> every accepted member of its own cartel.
--   2. From a cartel hub: -> every other cartel hub in the same syndicate.
--   3. Hub Beacon (never Prime): from anywhere in the syndicate -> every
--      accepted member system of every sibling cartel.
--   4. From the syndicate hub system: -> every other syndicate's hub system.
--   5. Distant Beacon (never Prime): from anywhere in the syndicate -> every
--      other syndicate's hub system.
-- Jump edges are directed; destination-side builds never affect legality, so
-- never create a reverse exit by symmetry.

-- systems[name]    = cartel name (accepted members only)
-- cartels[name]    = syndicate name, or false when the cartel is known but
--                    its syndicate is not yet
-- syndicates[name] = {hub_beacon=bool, distant_beacon=bool}
F2T_MAP_TOPOLOGY = F2T_MAP_TOPOLOGY or {systems = {}, cartels = {}, syndicates = {}, synced_at = nil}
F2T_MAP_TOPOLOGY_LOADED = F2T_MAP_TOPOLOGY_LOADED or false
F2T_MAP_TOPOLOGY_REBUILD_TIMER = F2T_MAP_TOPOLOGY_REBUILD_TIMER or nil
F2T_MAP_TOPOLOGY_LAST_AUTO_SYNC = F2T_MAP_TOPOLOGY_LAST_AUTO_SYNC or 0

local MAP_USERDATA_KEY = "f2t_topology"
local AUTO_SYNC_COOLDOWN = 300

function f2t_map_topology_hub_system(syndicate_name)
    if syndicate_name == "Prime" then return "Sol" end
    return syndicate_name
end

function f2t_map_topology_save()
    local ok, encoded = pcall(yajl.to_string, F2T_MAP_TOPOLOGY)
    if ok and encoded then setMapUserData(MAP_USERDATA_KEY, encoded) end
end

function f2t_map_topology_load()
    local raw = getMapUserData(MAP_USERDATA_KEY)
    if raw and raw ~= "" then
        local ok, decoded = pcall(yajl.to_value, raw)
        if ok and type(decoded) == "table" and type(decoded.systems) == "table" then
            F2T_MAP_TOPOLOGY = {
                systems    = decoded.systems or {},
                cartels    = decoded.cartels or {},
                syndicates = decoded.syndicates or {},
                synced_at  = decoded.synced_at,
            }
        end
    end
    f2t_map_topology_bootstrap()
    F2T_MAP_TOPOLOGY_LOADED = true
end

function f2t_map_topology_ensure_loaded()
    if not F2T_MAP_TOPOLOGY_LOADED then f2t_map_topology_load() end
end

-- Seed system->cartel from the mapped areas' userdata so a map that predates
-- the model (bundled starter maps included) starts with rule-1 knowledge.
function f2t_map_topology_bootstrap()
    local t = F2T_MAP_TOPOLOGY
    for area_name, area_id in pairs(getAreaTable()) do
        local system = f2t_map_get_system_from_space_area(area_name)
        if system and not t.systems[system] then
            local cartel = getAreaUserData(area_id, "fed2_cartel")
            if cartel and cartel ~= "" then
                t.systems[system] = cartel
                if t.cartels[cartel] == nil then t.cartels[cartel] = false end
            end
        end
    end
end

function f2t_map_topology_grouping_known(cartel)
    return type(F2T_MAP_TOPOLOGY.cartels[cartel]) == "string"
end

-- Legal jump destinations (set of system names) for a system, from the five
-- rules. Returns nil when the system's cartel is unknown; when the cartel's
-- syndicate is unknown only rule 1 can be derived and `complete` is false.
function f2t_map_topology_jump_destinations(system)
    local t = F2T_MAP_TOPOLOGY
    local cartel = t.systems[system]
    if not cartel then return nil, false end

    local dests = {}
    for name, c in pairs(t.systems) do
        if c == cartel and name ~= system then dests[name] = true end
    end
    if cartel ~= system then dests[cartel] = true end

    local syndicate = t.cartels[cartel]
    if type(syndicate) ~= "string" then return dests, false end

    local syn = t.syndicates[syndicate] or {}
    local is_prime = (syndicate == "Prime")

    if system == cartel then
        for cname, y in pairs(t.cartels) do
            if y == syndicate and cname ~= cartel then dests[cname] = true end
        end
    end

    if syn.hub_beacon and not is_prime then
        for name, c in pairs(t.systems) do
            if c ~= cartel and t.cartels[c] == syndicate and name ~= system then
                dests[name] = true
            end
        end
        for cname, y in pairs(t.cartels) do
            if y == syndicate and cname ~= cartel then dests[cname] = true end
        end
    end

    local hub_system = f2t_map_topology_hub_system(syndicate)
    if system == hub_system or (syn.distant_beacon and not is_prime) then
        for yname, _ in pairs(t.syndicates) do
            if yname ~= syndicate then
                dests[f2t_map_topology_hub_system(yname)] = true
            end
        end
    end

    dests[system] = nil
    return dests, true
end

-- Index of system name -> link room id for every mapped system space area.
function f2t_map_topology_link_room_index()
    local index = {}
    for area_name, area_id in pairs(getAreaTable()) do
        local system = f2t_map_get_system_from_space_area(area_name)
        if system then
            local link_room = f2t_map_find_room_with_flag(area_id, "link")
            if link_room then index[system] = link_room end
        end
    end
    return index
end

-- Reconcile every mapped link room's "jump ___" special exits with the model.
-- Rooms whose syndicate grouping is still unknown are left untouched (their
-- exits keep whatever GMCP last applied directly) rather than stripped down
-- to a rule-1-only set.
function f2t_map_topology_rebuild_exits()
    f2t_map_topology_ensure_loaded()
    local index = f2t_map_topology_link_room_index()
    local rebuilt, skipped, changed_exits = 0, 0, 0

    for system, room_id in pairs(index) do
        local cartel = F2T_MAP_TOPOLOGY.systems[system]
        if cartel and f2t_map_topology_grouping_known(cartel) then
            local dests = f2t_map_topology_jump_destinations(system)
            local wanted = {}
            for dest in pairs(dests or {}) do
                local dest_room = index[dest]
                if dest_room and dest_room ~= room_id then
                    wanted[string.format("jump %s", dest)] = dest_room
                end
            end

            local existing = getSpecialExitsSwap(room_id) or {}
            local to_remove = {}
            for command, dest_room in pairs(existing) do
                if type(command) == "string" and string.match(command, "^jump ") then
                    if wanted[command] == dest_room then
                        wanted[command] = nil
                    else
                        table.insert(to_remove, command)
                    end
                end
            end
            for _, command in ipairs(to_remove) do
                removeSpecialExit(room_id, command)
                changed_exits = changed_exits + 1
            end
            for command, dest_room in pairs(wanted) do
                addSpecialExit(room_id, dest_room, command)
                changed_exits = changed_exits + 1
            end
            rebuilt = rebuilt + 1
        else
            skipped = skipped + 1
        end
    end

    f2t_debug_log("[map/topology] Rebuilt jump exits: %d system(s), %d exit change(s), %d skipped (grouping unknown)",
        rebuilt, changed_exits, skipped)
    return rebuilt, skipped, changed_exits
end

-- Debounced rebuild so bursts of model changes (captures, GMCP) coalesce.
function f2t_map_topology_request_rebuild()
    if F2T_MAP_TOPOLOGY_REBUILD_TIMER then killTimer(F2T_MAP_TOPOLOGY_REBUILD_TIMER) end
    F2T_MAP_TOPOLOGY_REBUILD_TIMER = tempTimer(0.3, function()
        F2T_MAP_TOPOLOGY_REBUILD_TIMER = nil
        f2t_map_topology_rebuild_exits()
    end)
end

-- Correct the model from gmcp.room.info at a link room. The payload is exact
-- ground truth for this source system at this moment; a single observation
-- can therefore fix every room in the affected cartel/syndicate. Returns true
-- when any fact changed (a rebuild is then requested by the caller).
function f2t_map_topology_apply_gmcp(system, cartel, jumps)
    if not system or not cartel or not jumps then return false end
    f2t_map_topology_ensure_loaded()
    local t = F2T_MAP_TOPOLOGY
    local changed = false

    if t.systems[system] ~= cartel then
        t.systems[system] = cartel
        changed = true
    end
    if t.cartels[cartel] == nil then
        t.cartels[cartel] = false
        changed = true
    end

    -- The local list is the complete accepted roster of this cartel (minus
    -- this system): reconcile membership both ways.
    local roster = {[system] = true}
    for _, dest in ipairs(jumps["local"] or {}) do
        roster[dest] = true
        if t.systems[dest] ~= cartel then
            t.systems[dest] = cartel
            changed = true
        end
    end
    for name, c in pairs(t.systems) do
        if c == cartel and not roster[name] then
            t.systems[name] = nil
            changed = true
        end
    end

    local syndicate = t.cartels[cartel]
    if type(syndicate) == "string" then
        if syndicate ~= "Prime" then
            local syn = t.syndicates[syndicate]
            if not syn then
                syn = {}
                t.syndicates[syndicate] = syn
            end
            local hub_system = f2t_map_topology_hub_system(syndicate)
            local intra = jumps.intra_syndicate or {}
            local inter = jumps.inter_syndicate or {}

            if system ~= cartel then
                -- Non-hub member: intra list is non-empty iff the Hub Beacon
                -- is built (and sibling cartels have members); inter list is
                -- non-empty iff the Distant Beacon is built.
                local has_intra = (#intra > 0)
                if syn.hub_beacon ~= has_intra then
                    syn.hub_beacon = has_intra
                    changed = true
                end
                local has_inter = (#inter > 0)
                if syn.distant_beacon ~= has_inter then
                    syn.distant_beacon = has_inter
                    changed = true
                end
            else
                -- Cartel hub: intra always contains the sibling cartel hubs,
                -- so only a non-hub name in it proves the Hub Beacon. Never
                -- infer beacon absence from a hub's lists.
                for _, dest in ipairs(intra) do
                    if t.cartels[dest] == nil and not syn.hub_beacon then
                        syn.hub_beacon = true
                        changed = true
                        break
                    end
                end
                if system ~= hub_system then
                    local has_inter = (#inter > 0)
                    if syn.distant_beacon ~= has_inter then
                        syn.distant_beacon = has_inter
                        changed = true
                    end
                end
            end
        end
    else
        -- Grouping unknown for the cartel we are standing in: the model can't
        -- derive rules 2-5 anywhere in this syndicate. One sync heals it.
        f2t_map_topology_auto_sync("unknown syndicate for cartel " .. cartel)
    end

    if changed then f2t_map_topology_save() end
    return changed
end

-- Rate-limited background sync used when the model proves itself wrong
-- (unknown grouping, refused jump). Manual "map topology sync" bypasses this.
function f2t_map_topology_auto_sync(reason)
    if not f2t_settings_get("map", "topology_auto_sync") then return end
    if F2T_MAP_TOPOLOGY_CAPTURE and F2T_MAP_TOPOLOGY_CAPTURE.active then return end
    local now = os.time()
    if now - F2T_MAP_TOPOLOGY_LAST_AUTO_SYNC < AUTO_SYNC_COOLDOWN then return end
    F2T_MAP_TOPOLOGY_LAST_AUTO_SYNC = now
    f2t_debug_log("[map/topology] Auto-sync triggered: %s", reason or "unknown")
    f2t_map_topology_sync()
end

-- Shortest legal blind-jump command chain between two systems, mirroring the
-- server's own route builder. Used by the explorers to reach unmapped
-- territory where getPath() has no rooms to work with. Returns an array of
-- "jump <system>" commands, or nil when the model lacks the grouping to build
-- a legal chain.
function f2t_map_topology_jump_chain(from_system, to_system)
    f2t_map_topology_ensure_loaded()
    local t = F2T_MAP_TOPOLOGY

    local from_cartel = t.systems[from_system]
    local to_cartel = t.systems[to_system]
    if not to_cartel and t.cartels[to_system] ~= nil then to_cartel = to_system end
    if not from_cartel or not to_cartel then return nil end
    if from_system == to_system then return {} end

    local chain = {}
    local last = from_system
    local function emit(dest)
        if dest ~= last then
            table.insert(chain, string.format("jump %s", dest))
            last = dest
        end
    end

    if from_cartel == to_cartel then
        emit(to_system)
        return chain
    end

    local from_syn = t.cartels[from_cartel]
    local to_syn = t.cartels[to_cartel]
    if type(from_syn) ~= "string" or type(to_syn) ~= "string" then return nil end
    local fsyn = t.syndicates[from_syn] or {}
    local tsyn = t.syndicates[to_syn] or {}

    if from_syn == to_syn then
        if fsyn.hub_beacon and from_syn ~= "Prime" then
            emit(to_system)
        else
            emit(from_cartel)
            emit(to_cartel)
            emit(to_system)
        end
        return chain
    end

    local from_hub = f2t_map_topology_hub_system(from_syn)
    local to_hub = f2t_map_topology_hub_system(to_syn)

    if fsyn.distant_beacon and from_syn ~= "Prime" then
        emit(to_hub)
    elseif fsyn.hub_beacon and from_syn ~= "Prime" then
        emit(from_hub)
        emit(to_hub)
    else
        emit(from_cartel)
        emit(from_hub)
        emit(to_hub)
    end

    if tsyn.hub_beacon and to_syn ~= "Prime" then
        emit(to_system)
    else
        emit(to_cartel)
        emit(to_system)
    end

    return chain
end

function f2t_map_topology_show()
    f2t_map_topology_ensure_loaded()
    local t = F2T_MAP_TOPOLOGY

    local system_count = 0
    for _ in pairs(t.systems) do system_count = system_count + 1 end

    cecho("\n<cyan>═══════════════════════════════════════════════════════════<reset>\n")
    cecho("<cyan>                    Galaxy Topology Model<reset>\n")
    cecho("<cyan>═══════════════════════════════════════════════════════════<reset>\n\n")

    local syndicate_names = {}
    for name in pairs(t.syndicates) do table.insert(syndicate_names, name) end
    table.sort(syndicate_names)

    if #syndicate_names == 0 then
        cecho("<yellow>No syndicates known yet.<reset> Run <white>map topology sync<reset>\n")
    end

    for _, syndicate in ipairs(syndicate_names) do
        local syn = t.syndicates[syndicate]
        local beacons = {}
        if syn.hub_beacon then table.insert(beacons, "Hub Beacon") end
        if syn.distant_beacon then table.insert(beacons, "Distant Beacon") end
        local beacon_str = #beacons > 0
            and string.format(" <green>(%s)<reset>", table.concat(beacons, ", "))
            or ""
        cecho(string.format("<white>%s<reset> syndicate%s <dim_grey>(hub: %s)<reset>\n",
            syndicate, beacon_str, f2t_map_topology_hub_system(syndicate)))

        local cartel_names = {}
        for cname, y in pairs(t.cartels) do
            if y == syndicate then table.insert(cartel_names, cname) end
        end
        table.sort(cartel_names)
        for _, cname in ipairs(cartel_names) do
            local members = 0
            for _, c in pairs(t.systems) do
                if c == cname then members = members + 1 end
            end
            cecho(string.format("  <cyan>%s<reset> <dim_grey>(%d known system%s)<reset>\n",
                cname, members, members == 1 and "" or "s"))
        end
    end

    local orphans = {}
    for cname, y in pairs(t.cartels) do
        if type(y) ~= "string" then table.insert(orphans, cname) end
    end
    if #orphans > 0 then
        table.sort(orphans)
        cecho(string.format("\n<yellow>Cartels with unknown syndicate:<reset> %s\n", table.concat(orphans, ", ")))
    end

    cecho(string.format("\n<dim_grey>Known systems: %d   Last sync: %s<reset>\n",
        system_count,
        t.synced_at and os.date("%Y-%m-%d %H:%M:%S", t.synced_at) or "never"))
    cecho("<cyan>═══════════════════════════════════════════════════════════<reset>\n")
end

f2t_debug_log("[map] Loaded topology.lua")
