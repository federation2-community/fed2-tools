-- =============================================================================
-- ui_chat_who  —  compact online player list with hover tooltips
-- Mudlet Script location: ui > ui_chat_who
-- =============================================================================

UI     = UI or {}
UI.who = UI.who or { players = {}, parsing = false, count = 0, staff_count = 0 }

-- ── Rank tier table ───────────────────────────────────────────────────────
-- Higher = more senior.  Drives sort order and name coloring.

local RANK_ORDER = {
    ["Trader"]        = 1,
    ["Engineer"]      = 2,
    ["Merchant"]      = 3,
    ["Manufacturer"]  = 4,
    ["Industrialist"] = 5,
    ["Financier"]     = 6,
    ["Mogul"]         = 7,
    ["Magnate"]       = 8,
    ["Technocrat"]    = 9,
    ["Gengineer"]     = 10,
    ["Founder"]       = 11,
    ["Plutocrat"]     = 12,
}

-- Named cecho colors per rank band (avoids the <r,g,b> vs <r:g:b> ambiguity)
local RANK_COLOR = {
    [12] = "<ansiYellow>",    -- Plutocrat
    [11] = "<ansiYellow>",    -- Founder
    [10] = "<ansiMagenta>",   -- Gengineer
    [9]  = "<ansiMagenta>",   -- Technocrat
    [8]  = "<ansiCyan>",      -- Magnate
    [7]  = "<ansiCyan>",      -- Mogul
    [6]  = "<white>",         -- Financier
    [5]  = "<white>",         -- Industrialist
}
local RANK_COLOR_DEFAULT = "<ansiWhite>"

local function _rank_color(tier)
    return RANK_COLOR[tier] or RANK_COLOR_DEFAULT
end

-- ── Badge definitions ─────────────────────────────────────────────────────
-- Only used for tooltip text now — no inline badge rendering.

local BADGES = {
    { m = function(r) return r == "magellan society member"                          end, tip = "Magellan Society"         },
    { m = function(r) return r == "galactic trade prospector"                        end, tip = "Galactic Trade Prospector"},
    { m = function(r) return r:match("^master of the") or r:match("^mistress of the")end, tip = "Snakes & Foxes"          },
    { m = function(r) return r:match("^ceo of")                                      end, tip = "CEO"                     },
    { m = function(r) return r:match("^captain of")                                  end, tip = "Ship Captain"            },
    { m = function(r) return r == "super sleuth"                                     end, tip = "Super Sleuth"            },
    { m = function(r) return r == "escaped outlaw"                                   end, tip = "Escaped Outlaw"          },
}

-- ── Tooltip builder ───────────────────────────────────────────────────────
-- Produces a single plain string for cechoLink's hint parameter.

function ui_who_build_hint(row)
    local parts = {}

    if row.affil_display and row.affil_display ~= "" then
        table.insert(parts, row.affil_display)
    end
    if row.location and row.location ~= "?" then
        table.insert(parts, "On: " .. row.location)
    end
    if row.staff and row.staff ~= "" then
        table.insert(parts, "[" .. row.staff .. "]")
    end
    for _, b in ipairs(row.badges or {}) do
        table.insert(parts, b.tip)
    end

    if #parts == 0 then return "(no additional info)" end
    return table.concat(parts, "  •  ")
end

-- ── Line parser ───────────────────────────────────────────────────────────

function ui_who_parse_line(raw)
    local line = raw:match("^%s*(.-)%s*$")
    if line == "" then return nil end

    -- 1. Strip trailing staff badge e.g. " [Navigator]"
    local staff = ""
    line = line:gsub("%s+%[(%a+)%]%s*$", function(b) staff = b; return "" end)
    line = line:match("^%s*(.-)%s*$")

    -- 2. Location: last ", on <place>" segment
    local location = "?"
    local last_on  = nil
    local pos = 1
    while true do
        local f = line:find(", on ", pos, true)
        if not f then break end
        last_on = f; pos = f + 1
    end
    if last_on then
        location = line:sub(last_on + 5):match("^%s*(.-)%s*$")
        line     = line:sub(1, last_on - 1)
    end

    -- 3. Rank
    local rank = line:match("^(%a+)")
    if not rank then return nil end
    line = (line:sub(#rank + 1):match("^%s*(.*)") or "")

    -- 4. Name
    local name = line:match("^(%a+)")
    if not name then return nil end
    line = (line:sub(#name + 1):match("^[,]?%s*(.*)") or "")

    -- 5. Affiliation
    local affiliation, affil_type = "", ""
    if line:sub(1, 6) == "of the" then
        local rest = line:sub(8)
        local a, t, leftover
        a, t, leftover = rest:match("^(.-)%s+(system)%s*,?%s*(.-)$")
        if not a then a, t, leftover = rest:match("^(.-)%s+(cartel)%s*,?%s*(.-)$") end
        if a then affiliation = a; affil_type = t; line = leftover or "" end
    end

    -- 6. Remaining comma-separated segments → badge recognition
    local badges = {}
    for seg in (line .. ","):gmatch("([^,]+),") do
        local r = seg:match("^%s*(.-)%s*$")
        if r ~= "" then
            local rl = r:lower()
            for _, def in ipairs(BADGES) do
                if def.m(rl) then
                    local dup = false
                    for _, b in ipairs(badges) do if b.tip == def.tip then dup = true; break end end
                    if not dup then table.insert(badges, { tip = def.tip }) end
                    break
                end
            end
        end
    end

    if staff ~= "" then
        table.insert(badges, { tip = staff })
    end

    local affil_display = ""
    if affiliation ~= "" then
        affil_display = affiliation .. " (" .. affil_type:sub(1,1):upper() .. ")"
    end

    return {
        raw_line      = raw:match("^%s*(.-)%s*$"),
        rank          = rank,
        rank_order    = RANK_ORDER[rank] or 0,
        name          = name,
        affiliation   = affiliation,
        affil_type    = affil_type,
        affil_display = affil_display,
        location      = location,
        badges        = badges,
        staff         = staff,
    }
end

-- ── Trigger callbacks ─────────────────────────────────────────────────────

function ui_who_start()
    if not UI.who.parsing then return end

    UI.who.players = {}
    f2t_debug_log("[who] parse start")
end

function ui_who_line()
    if not UI.who.parsing then return end

    local solo_badge = line:match("^%[(%a+)%]%s*$")
    if solo_badge and #UI.who.players > 0 then
        local last = UI.who.players[#UI.who.players]
        if last.staff == "" then
            last.staff = solo_badge
            table.insert(last.badges, { tip = solo_badge })
        end
        return
    end

    local parsed = ui_who_parse_line(line)
    if parsed then table.insert(UI.who.players, parsed) end
end

function ui_who_end()
    if not UI.who.parsing then return end
    UI.who.parsing = false

    local total, stf = line:match("(%d+) players, (%d+) staff")
    UI.who.count       = tonumber(total) or #UI.who.players
    UI.who.staff_count = tonumber(stf)   or 0

    f2t_debug_log("[who] parsed %d players", #UI.who.players)

    if UI.who_header then
        UI.who_header:echo(string.format(
            "  👥  Online: %d players, %d staff",
            UI.who.count, UI.who.staff_count))
    end

    ui_table_set_data("who_list", UI.who.players)
end

-- ── Refresh ───────────────────────────────────────────────────────────────

function ui_who_refresh()
    if UI.who_window then
        UI.who_window:clear()
        UI.who_window:cecho("<dim_grey>Fetching who list...\n")
        UI.who.parsing = true
    end
    send("who", false)
end

-- ── Table init ────────────────────────────────────────────────────────────
-- Two columns only: Rank (color-coded, sortable by tier) + Name (with tooltip).
-- All extended data — affiliation, location, badges, staff — lives in the
-- hover tooltip on the Name link.

function ui_who_init()
    if not UI.who_window then
        f2t_debug_log("[who] who_window not ready yet")
        return
    end

    local cols = {
        {
            key          = "rank",
            label        = "Rank",
            width        = 13,
            align        = "left",
            sortable     = true,
            sort_value   = function(row) return row.rank_order or 0 end,
            format       = function(v, row)
                return _rank_color(row.rank_order or 0) .. v .. "<reset>"
            end,
        },
        {
            key      = "name",
            label    = "Name",
            width    = 16,
            align    = "left",
            default_sort = "asc",
            sortable = true,
            -- Use render so we can build a dynamic tooltip per row
            render   = function(value, row, window, col)
                local hint    = row.raw_line or ""
                -- Staff gets a gold highlight on the name
                local ncolor  = (row.staff and row.staff ~= "") and "<ansiYellow>" or "<white>"
                local padded  = f2t_padding(value or "", col.width or 16, "left")
                window:cechoLink(
                    ncolor .. padded .. "<reset>",
                    function() end,
                    hint,
                    true)
            end,
        },
    }

    ui_table_create("who_list", UI.who_window, cols, {
        column = "  ",
        row    = nil,
        header = "",
    })
end