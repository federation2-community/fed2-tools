-- Local rank → cecho color (mirrors ui_players.lua)
local LOCAL_RANK_COLOR = {
    ["Trader"]        = "mint_cream",
    ["Engineer"]      = "ansiCyan",
    ["Merchant"]      = "mint_cream",
    ["Manufacturer"]  = "ansiGreen",
    ["Industrialist"] = "ansiGreen",
    ["Financier"]     = "ansiGreen",
    ["Mogul"]         = "ansiCyan",
    ["Magnate"]       = "ansiCyan",
    ["Technocrat"]    = "ansiCyan",
    ["Gengineer"]     = "ansiCyan",
    ["Founder"]       = "ansiCyan",
    ["Plutocrat"]     = "ansiRed",
    ["Commander"]     = "dark_violet",
    ["Groundhog"]     = "dark_violet",
}
local LOCAL_RANK_COLOR_DEFAULT = "ansi_white"

-- Generation counter: ensures every rebuild uses unique Geyser child names so
-- stale hidden objects from previous rooms never interfere.
local _lp_gen = 0

-- ── Layout ────────────────────────────────────────────────────────────────────
-- Repositions the pane and gap_filler based on current cargo visibility.
-- Uses container_config for LP width — get_width() returns 0 on hidden containers.
function ui_refresh_local_players_layout()
    if not UI.local_players_dropdown then return end

    if not UI.local_players_visible then
        if UI.local_players_gap_filler then UI.local_players_gap_filler:hide() end
        return
    end

    -- Use config values (not get_width()) so positioning is correct even during
    -- early init when Adjustable.Container::get_width() may return 0.
    local cfg                  = UI.container_config
    local right_width_pct      = cfg.right_width_pct
    local lp_width_pct         = cfg.local_players_width_pct
    local cargo_width_pct      = cfg.cargo_width_pct
    local top_left_height_pct  = cfg.top_left_height_pct
    local top_right_height_pct = cfg.top_right_height_pct
    local top_height_diff_pct  = top_right_height_pct - top_left_height_pct
    -- top_right_width_pct: derived from config (needed for gap filler width)
    local left_width_pct       = cfg.left_width_pct
    local available_center_pct = 100 - left_width_pct - right_width_pct
    local top_right_width_pct  = available_center_pct * (1 - cfg.top_left_center_ratio)

    -- Hide before moving: Geyser.Label requires this for position to update visually.
    UI.local_players_dropdown:hide()

    if UI.cargo_display_visible and UI.cargo_dropdown then
        -- ── With cargo ──────────────────────────────────────────────────────
        local lp_x = 100 - right_width_pct - cargo_width_pct - lp_width_pct

        UI.local_players_dropdown:move(lp_x .. "%", top_left_height_pct .. "%")
        UI.local_players_dropdown:setStyleSheet(UI.style.local_players_dropdown_with_cargo_css)
        if UI.local_players_gap_filler then UI.local_players_gap_filler:hide() end
    else
        -- ── Standalone (no cargo) ────────────────────────────────────────────
        local lp_x         = 100 - right_width_pct - lp_width_pct
        local gf_width_pct = lp_width_pct - top_right_width_pct

        UI.local_players_dropdown:move(lp_x .. "%", top_right_height_pct .. "%")
        UI.local_players_dropdown:setStyleSheet(UI.style.local_players_dropdown_standalone_css)

        if UI.local_players_gap_filler then
            UI.local_players_gap_filler:move(lp_x .. "%", top_left_height_pct .. "%")
            UI.local_players_gap_filler:resize(gf_width_pct .. "%", top_height_diff_pct .. "%")
            UI.local_players_gap_filler:show()
            UI.local_players_gap_filler:raise()
        end
    end

    UI.local_players_dropdown:show()
    UI.local_players_dropdown:raise()
    if UI.top_right_frame then UI.top_right_frame:raise() end

    ui_update_local_players_display()
end

-- ── Visibility ────────────────────────────────────────────────────────────────

function ui_show_local_players()
    if not UI.local_players_dropdown then return end
    UI.local_players_visible = true
    ui_refresh_local_players_layout()
end

function ui_hide_local_players()
    if not UI.local_players_dropdown then return end
    UI.local_players_visible = false
    UI.local_players_dropdown:hide()
    if UI.local_players_gap_filler then UI.local_players_gap_filler:hide() end
end

-- ── Entry point (called on every gmcp.room.info event and cargo toggle) ───────

function ui_update_local_players()
    local players = gmcp.room and gmcp.room.info and gmcp.room.info.players

    if not players or #players == 0 then
        ui_hide_local_players()
        return
    end

    ui_show_local_players()
end

-- ── Row renderer ──────────────────────────────────────────────────────────────

function ui_update_local_players_display()
    if not UI.local_players_dropdown then return end

    local players = gmcp.room and gmcp.room.info and gmcp.room.info.players
    if not players or #players == 0 then return end

    -- Bump generation so every child has a unique name
    _lp_gen = _lp_gen + 1
    local g = _lp_gen
    local cargo_visible = UI.cargo_display_visible and UI.cargo_dropdown ~= nil

    -- Hide previous generation
    if UI.local_players_entries then
        for _, e in ipairs(UI.local_players_entries) do e:hide() end
    end
    if UI.local_players_separators then
        for _, s in ipairs(UI.local_players_separators) do s:hide() end
    end
    if UI.local_players_header_label then
        UI.local_players_header_label:hide()
        UI.local_players_header_label = nil
    end
    UI.local_players_entries    = {}
    UI.local_players_separators = {}

    local player_count = #players

    -- Heights in pixels
    -- Header only in cargo mode; standalone mode puts the label in the gap filler.
    local header_px = cargo_visible and 22 or 0
    local entry_px  = 28
    local sep_px    = 2
    local pad_px    = 6   -- top and bottom padding around the player list

    local total_px = math.max(50,
                       header_px
                     + pad_px
                     + (player_count * entry_px)
                     + math.max(0, player_count - 1) * sep_px
                     + pad_px)

    UI.local_players_dropdown:resize(UI.container_config.local_players_width_pct .. "%", total_px)

    local function pct(px) return (px / total_px) * 100 end

    local y = 0

    -- Header label only when cargo is visible (gap filler holds the text otherwise)
    if cargo_visible then
        UI.local_players_header_label = Geyser.Label:new({
            name    = "lp_hdr_" .. g,
            x       = "0%",
            y       = "0%",
            width   = "100%",
            height  = pct(header_px) .. "%",
            message = "<center><b>Local Players:</b></center>",
        }, UI.local_players_dropdown)
        UI.local_players_header_label:setStyleSheet([[
            background-color: transparent;
            color: rgba(255,255,255,0.95);
        ]])
        y = pct(header_px)
    end

    -- Top padding
    y = y + pct(pad_px)

    for i, player in ipairs(players) do
        local name = player.name or "Unknown"
        local rank = player.rank or ""
        local cc   = LOCAL_RANK_COLOR[rank] or LOCAL_RANK_COLOR_DEFAULT

        local entry = Geyser.Container:new({
            name   = "lp_row_" .. g .. "_" .. i,
            x      = "0%",
            y      = y .. "%",
            width  = "100%",
            height = pct(entry_px) .. "%",
        }, UI.local_players_dropdown)
        table.insert(UI.local_players_entries, entry)

        -- Name console — vertically centred within the row
        local name_con = Geyser.MiniConsole:new({
            name      = "lp_name_" .. g .. "_" .. i,
            x         = "3%",
            y         = "20%",
            width     = "74%",
            height    = "60%",
            autoWrap  = false,
            scrollBar = false,
            fontSize  = text_size,
            color     = "black",
        }, entry)
        name_con:cechoLink(
            "<" .. cc .. "><b>" .. name .. "</b><reset>",
            function() printCmdLine("tb " .. name .. " ") end,
            rank ~= "" and (rank .. " " .. name) or name,
            true
        )

        -- Eye button — same vertical band as the name console
        local eye_btn = Geyser.Label:new({
            name    = "lp_eye_" .. g .. "_" .. i,
            x       = "79%",
            y       = "8%",
            width   = 22,
            height  = "84%",
            message = "<center>👁</center>",
        }, entry)
        eye_btn:setStyleSheet(UI.style.button_css)
        eye_btn:setToolTip("Examine " .. name)
        eye_btn:setClickCallback(function() send("ex " .. name, false) end)

        y = y + pct(entry_px)

        -- Separator between players only (not above first or below last)
        if i < player_count then
            local sep = Geyser.Label:new({
                name   = "lp_sep_" .. g .. "_" .. i,
                x      = "4%",
                y      = y .. "%",
                width  = "92%",
                height = pct(sep_px) .. "%",
            }, UI.local_players_dropdown)
            sep:setStyleSheet("background-color: rgba(255,255,255,0.46)")
            table.insert(UI.local_players_separators, sep)
            y = y + pct(sep_px)
        end
    end
end
