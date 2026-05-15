-- Room info bar: galaxy-path breadcrumb for the map tab.
-- Shows: 🌌 Cartel › ⭐ System › 🌍 Planet › [room-badge] Room   [extra badges]   hash
-- Updated on every gmcp.room.info event via ui_map_update_room_info().

-- Badge colours for each room-type flag.
-- color     = background of the badge chip
-- text_color = text drawn inside the chip (must contrast the background)
local FLAG_BADGE = {
    link       = {symbol = "⟡",  color = "#4477cc", text_color = "#ddeeff"},
    orbit      = {symbol = "○",   color = "#44aa44", text_color = "#001a00"},
    shuttlepad = {symbol = "🚀",  color = "#22aaaa", text_color = "#001a1a"},
    exchange   = {symbol = "$",   color = "#7a0000", text_color = "#ddeeff"},
    shipyard   = {symbol = "🔧",  color = "#7a4500", text_color = "#ffd090"},
    hospital   = {symbol = "✚",   color = "#1a5c1a", text_color = "#88dd88"},
    bar        = {symbol = "🍸",  color = "#cc6600", text_color = "#1a0800"},
    courier    = {symbol = "AC",  color = "#aaaa33", text_color = "#141400"},
}

-- Priority order for the badge shown inline with the last breadcrumb segment.
local ICON_PRIORITY = {
    "link", "orbit", "shuttlepad", "exchange", "shipyard", "hospital", "bar", "courier"
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function badge_html(symbol, color, text_color)
    text_color = text_color or "#ddeeff"
    return string.format(
        "<span style='background:%s;color:%s;padding:0 4px;"
        .. "border-radius:2px;margin-left:3px;font-size:10px'>%s</span>",
        color, text_color, symbol
    )
end

-- Build breadcrumb HTML from typed parts.
-- Each part: {text=…, type="cartel"|"system"|"planet"|"room", badge=html_or_nil}
-- Galaxy-navigator icons prefix each tier; the room-type badge (if any) is
-- rendered inline at the start of the last segment.
local function breadcrumb_html(parts)
    local type_color = {
        cartel = "rgba(120,135,150,0.62)",
        system = "rgba(158,172,188,0.76)",
        planet = "rgba(196,210,226,0.90)",
        room   = "rgba(232,242,252,0.98)",
    }
    -- Icons match the galaxy navigator (🌌 cartel #ff6b9d, ⭐ system #ffd700, 🌍 planet #4ecdc4)
    local type_icon = {
        cartel = "<span style='color:#ff6b9d;font-size:11px'>🌌</span> ",
        system = "<span style='color:#ffd700;font-size:11px'>⭐</span> ",
        planet = "<span style='color:#4ecdc4;font-size:11px'>🌍</span> ",
        room   = "",
    }
    local sep = "<span style='color:rgba(75,88,105,0.55)'> › </span>"
    local out = {}
    for _, part in ipairs(parts) do
        local t    = part.type or "room"
        local icon = type_icon[t] or ""
        local col  = type_color[t] or type_color.room
        -- badge is placed inline before the text for the terminal segment
        local pre  = part.badge or ""
        table.insert(out,
            icon .. pre .. string.format("<span style='color:%s'>%s</span>", col, part.text)
        )
    end
    return table.concat(out, sep)
end

-- ── Main update function ───────────────────────────────────────────────────────

function ui_map_update_room_info()
    if not UI or not UI.map_info_bar then return end

    local room = gmcp and gmcp.room and gmcp.room.info
    if not room then
        UI.map_info_bar:echo(
            "<div style='line-height:40px;padding:0 10px;"
            .. "color:rgba(70,80,90,0.55);font-family:Consolas,Monaco,monospace;"
            .. "font-size:11px;'>No location data</div>"
        )
        return
    end

    local system = room.system or ""
    local area   = room.area   or ""
    local name   = room.name   or ""
    local num    = room.num
    local cartel = room.cartel or ""
    local flags  = room.flags  or {}

    -- Context detection
    local has_space  = f2t_has_value(flags, "space")
    local has_orbit  = f2t_has_value(flags, "orbit")
                       or (type(room.orbit) == "string" and room.orbit ~= "")
    local is_space   = has_space or (area ~= "" and area:match(" Space$") ~= nil)

    -- Prefer stored planet name for orbit rooms
    local planet_name = area
    if has_orbit and F2T_MAP_CURRENT_ROOM_ID then
        local stored = getRoomUserData(F2T_MAP_CURRENT_ROOM_ID, "fed2_planet")
        if stored and stored ~= "" then planet_name = stored end
    end

    -- ── Terminal badge: highest-priority flag, rendered with the last segment ──
    local terminal_badge = ""
    local terminal_sym   = ""
    for _, flag in ipairs(ICON_PRIORITY) do
        if f2t_has_value(flags, flag) and FLAG_BADGE[flag] then
            local b = FLAG_BADGE[flag]
            terminal_sym   = b.symbol
            terminal_badge = string.format(
                "<span style='background:%s;color:%s;padding:0 5px;"
                .. "border-radius:2px;margin-right:5px;font-size:10px'>%s</span>",
                b.color, b.text_color or "#ddeeff", b.symbol
            )
            break
        end
    end

    -- ── Breadcrumb ────────────────────────────────────────────────────────────
    local parts = {}

    -- Cartel: omit when identical to system (primary system = redundant)
    if cartel ~= "" and string.lower(cartel) ~= string.lower(system) then
        table.insert(parts, {text = cartel, type = "cartel"})
    end

    if is_space then
        if system ~= "" then table.insert(parts, {text = system, type = "system"}) end
        table.insert(parts, {text = "Space", type = "room", badge = terminal_badge})
    elseif has_orbit then
        -- Orbit: badge attaches to the planet name (no room name shown)
        if system      ~= "" then table.insert(parts, {text = system,      type = "system"}) end
        if planet_name ~= "" then table.insert(parts, {text = planet_name, type = "planet", badge = terminal_badge}) end
    else
        if system ~= "" then table.insert(parts, {text = system, type = "system"}) end
        if area   ~= "" then table.insert(parts, {text = area,   type = "planet"}) end
        if name   ~= "" then
            -- Badge attaches to the room name (terminal segment)
            table.insert(parts, {text = name, type = "room", badge = terminal_badge})
        end
    end

    -- ── Secondary badges (all flags except the terminal one) ──────────────────
    local badges_html = ""
    for _, flag in ipairs(flags) do
        local b = FLAG_BADGE[flag]
        if b and b.symbol ~= terminal_sym then
            badges_html = badges_html .. badge_html(b.symbol, b.color, b.text_color)
        end
    end

    -- ── Hash — muted, after secondary badges ─────────────────────────────────
    local hash_html = ""
    if system ~= "" and area ~= "" and num then
        hash_html = string.format(
            "<span style='color:rgba(55,65,82,0.80);font-size:10px;margin-left:10px'>"
            .. "%s.%s.%d</span>",
            system, area, num
        )
    end

    -- ── Assemble ──────────────────────────────────────────────────────────────
    local html = string.format(
        "<div style='line-height:40px;padding:0 10px;"
        .. "font-family:Consolas,Monaco,monospace;font-size:13px;"
        .. "white-space:nowrap;overflow:hidden;'>"
        .. "%s%s%s</div>",
        breadcrumb_html(parts),
        badges_html,
        hash_html
    )

    UI.map_info_bar:echo(html)
end
