-- Map info overlay: renders Fed2 breadcrumb and room badge on the mapper canvas.
-- Uses room_id parameter so clicking any room shows that room's stored data.
-- Requires Mudlet 4.11+ (registerMapInfo API).

pcall(function() disableMapInfo("Short") end)
pcall(function() disableMapInfo("Full") end)
pcall(function() disableMapInfo("fed2_info") end)
pcall(function() disableMapInfo("fed2_bc") end)
pcall(function() disableMapInfo("fed2_rm") end)

-- Priority order for which flag icon to show (highest first).
-- Symbols and badge colors sourced from map_style.lua (single source of truth).
local ICON_PRIORITY = {
    "link", "orbit", "shuttlepad", "exchange", "shipyard", "hospital", "bar", "courier"
}

-- After the player moves, snap the info display back to the current room.
-- Mudlet persists the user's clicked-room selection even after centerview();
-- this override holds for 1.5s so movement snaps cleanly without permanently
-- disabling click-to-inspect on other rooms.
local _snap_to_current = false

function f2t_map_info_snap_to_current()
    _snap_to_current = true
    -- centerview() already fired before this call, so force a second render
    -- now that the snap flag is set so the overlay shows the new room immediately.
    updateMap()
    tempTimer(1.5, function()
        _snap_to_current = false
    end)
end

local function resolve_room(room_id)
    if _snap_to_current and F2T_MAP_CURRENT_ROOM_ID and
       roomExists(F2T_MAP_CURRENT_ROOM_ID) then
        return F2T_MAP_CURRENT_ROOM_ID
    end
    return room_id
end

-- Line 1: galaxy path breadcrumb  (cartel › system › planet)
registerMapInfo("fed2_bc", function(room_id)
    room_id = resolve_room(room_id)
    if not room_id or not roomExists(room_id) then return "" end

    local system = getRoomUserData(room_id, "fed2_system") or ""
    local planet = getRoomUserData(room_id, "fed2_planet") or ""
    local cartel = getRoomUserData(room_id, "fed2_cartel") or ""

    local parts = {}
    if cartel ~= "" then table.insert(parts, "🌌 " .. cartel) end
    if system ~= "" then table.insert(parts, "⭐ " .. system) end
    if planet ~= "" then table.insert(parts, "🌍 " .. planet) end

    if #parts == 0 then return "" end
    return table.concat(parts, " › "), false, false, 190, 210, 230
end)

-- Line 2: room name, with colored badge square when the room has a typed flag.
-- ■ symbol  Room Name  — text colored with the badge's environment color.
-- Plain room name in default color when no special flag is set.
registerMapInfo("fed2_rm", function(room_id)
    room_id = resolve_room(room_id)
    if not room_id or not roomExists(room_id) then return "" end

    local name = getRoomName(room_id) or ""
    if name == "" then return "" end

    local matched_flag = nil
    for _, f in ipairs(ICON_PRIORITY) do
        if getRoomUserData(room_id, "fed2_flag_" .. f) == "true" then
            matched_flag = f
            break
        end
    end

    if matched_flag and type(f2t_map_get_flag_symbol) == "function" then
        local sym = f2t_map_get_flag_symbol(matched_flag) or matched_flag
        local r, g, b
        if type(f2t_map_get_flag_badge_rgb) == "function" then
            r, g, b = f2t_map_get_flag_badge_rgb(matched_flag)
        end
        if r then
            return "■ " .. sym .. "  " .. name, false, false, r, g, b
        end
        return sym .. "  " .. name, false, false, 190, 210, 230
    end

    return name, false, false, 190, 210, 230
end)

enableMapInfo("fed2_bc")
enableMapInfo("fed2_rm")
-- Deferred refresh: mapper may not be fully ready at package-load time.
tempTimer(2, function() updateMap() end)
