-- Map legend window — toggle and content generation
-- Builds an HTML legend from f2t_map_get_legend_data() and shows/hides UI.map_legend

local _legend_built   = false
local _legend_visible = false

-- Build HTML content for the legend window.
-- Called once on first show and cached via _legend_built.
local function build_legend_html()
    -- Guard: map style data not available (map component not loaded)
    if type(f2t_map_get_legend_data) ~= "function" then return "" end

    local data = f2t_map_get_legend_data()

    local rows = {}
    for _, entry in ipairs(data) do
        local sym        = entry.symbol ~= "" and entry.symbol or "·"
        local text_color = entry.text_color or "#ddeeff"
        table.insert(rows, string.format(
            "<tr>"
            .. "<td style='width:40px;text-align:center;padding:3px 2px'>"
            ..   "<span style='background:%s;color:%s;padding:2px 5px;"
            ..   "border-radius:2px;font-size:11px'>%s</span>"
            .. "</td>"
            .. "<td style='padding:3px 6px;color:rgba(205,215,225,0.95);font-size:11px;"
            ..   "white-space:nowrap'>%s</td>"
            .. "<td style='padding:3px 6px;color:rgba(105,120,135,0.85);font-size:10px;"
            ..   "font-style:italic'>%s</td>"
            .. "</tr>",
            entry.html_color, text_color, sym, entry.label, entry.note
        ))
    end

    return string.format(
        "<div style='font-family:Consolas,Monaco,monospace;'>"
        .. "<div style='background:rgba(25,30,48,230);padding:5px 10px;"
        ..   "border-bottom:1px solid rgba(255,255,255,0.22);"
        ..   "color:rgba(195,210,225,0.95);font-size:11px;letter-spacing:1px;"
        ..   "font-weight:bold'>MAP LEGEND</div>"
        .. "<table style='width:100%%;border-collapse:collapse;padding:3px'>%s</table>"
        .. "</div>",
        table.concat(rows, "")
    )
end

-- Toggle the legend window visibility.
function ui_map_legend_toggle()
    if not UI or not UI.map_legend then return end

    if _legend_visible then
        UI.map_legend:hide()
        _legend_visible = false
    else
        if not _legend_built then
            UI.map_legend:echo(build_legend_html())
            _legend_built = true
        end
        UI.map_legend:show()
        UI.map_legend:raise()
        _legend_visible = true
    end
end
