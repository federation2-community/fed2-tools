-- @patterns:
--   - pattern: ^      (.+)$
--     type: regex

-- Capture individual system names in Members section
-- Triggers on lines starting with 6 spaces (system names)

if not F2T_MAP_EXPLORE_CARTEL_CAPTURE or not F2T_MAP_EXPLORE_CARTEL_CAPTURE.active then
    return
end

-- Only capture if we're in the Members section
if not F2T_MAP_EXPLORE_CARTEL_CAPTURE.in_members then
    return
end

-- Hide output
deleteLine()

-- Extract system name; strip any trailing annotation e.g. " - Dyson Sphere detected"
local system_name = matches[2]:match("^(.-)%s+%-.+$") or matches[2]

-- Store system name
table.insert(F2T_MAP_EXPLORE_CARTEL_CAPTURE.lines, system_name)

f2t_debug_log("[map-explore-cartel] Captured member system: %s", system_name)

-- Reset timer (0.5s of silence = capture complete)
f2t_map_explore_cartel_reset_timer()
