-- fed2-tools — game tool availability utilities (ported from shared/scripts/f2t_tools.lua)

-- Column count cap used by table renderer
COLS = getColumnCount and (getColumnCount() > 100 and 100 or getColumnCount()) or 100

function f2t_get_tool(tool_name)
    if not tool_name then return nil end
    local tools = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.tools
    if not tools then return nil end
    return tools[tool_name]
end

function f2t_has_tool(tool_name)
    return f2t_get_tool(tool_name) ~= nil
end

function f2t_check_tool_requirement(tool_name, feature_name, display_name)
    if f2t_has_tool(tool_name) then return true end
    local name = display_name or tool_name
    cecho(string.format("\n<red>[fed2-tools]<reset> %s requires the <cyan>%s<reset> tool\n",
        feature_name, name))
    cecho("<dim_grey>See: https://federation2.com/guide/#sec-230.20<reset>\n")
    return false
end
